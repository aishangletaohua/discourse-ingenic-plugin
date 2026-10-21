# frozen_string_literal: true

class IngenicDocsController < ::ApplicationController
  requires_plugin DiscourseIngenic::PLUGIN_NAME

  include DiscourseIngenic::AppShell

  # A visitor opening or refreshing /ingenic/docs/... is a plain browser
  # navigation, not an AJAX call. Without this the base controller rejects it
  # before we ever get to render the app shell.
  skip_before_action :check_xhr, only: %i[show]

  # Paths are /<series>/<chip>/<version>/<page>. Everything after the series is
  # optional: /ingenic/docs opens the first series and its first chip, and
  # /ingenic/docs/t-series opens that series' first chip.
  MAX_PATH_SEGMENTS = 4

  # One-character queries match nearly every page and cost a full scan of the
  # resolved tree, so they are answered with an empty result instead.
  MIN_SEARCH_LENGTH = 2

  # Enough to fill the results pane without shipping the whole manual over the
  # wire when a query is broad.
  SEARCH_LIMIT = 50

  # Characters on each side of the match shown in a result excerpt.
  EXCERPT_RADIUS = 90

  def show
    return render_app_shell unless request.format.json?

    series = find_series
    # A name in the URL that resolves to nothing is a 404. Only the *absence* of
    # a choice falls back to the first one — an address that spells out a series
    # this site does not have is a broken link, and answering it with somebody
    # else's documentation is worse than saying so.
    return render_not_found(:product_not_found) if series.nil? && series_slug.present?

    chip = series && find_chip(series)
    return render_not_found(:product_not_found) if chip.nil? && chip_slug.present?

    version = chip && find_version(chip)
    # `latest` is an alias rather than a slug, so it is not a missing version
    # when a chip has none flagged.
    if version.nil? && chip && version_slug.present? && version_slug != "latest"
      return render_not_found(:version_not_found)
    end

    page = version && find_page(version)

    # No series at all is not a 404: a site whose documentation has not been
    # written yet still has to render the sidebar entry that points here.
    return render_not_found(:page_not_found) if version && page_slug.present? && page.nil?

    render_json_dump(payload(series, chip, version, page))
  end

  # Full-text search across the pages of one chip at one version.
  #
  # Matching happens in Ruby over the *resolved* page set rather than in SQL
  # over `ingenic_doc_pages`, because the set a reader sees is assembled from
  # several versions by Ingenic::DocumentationResolver — a SQL query would have
  # to reimplement the inheritance walk and would drift from it. Documentation
  # sets are small enough that this is the cheaper correctness trade.
  def search
    query = params[:q].to_s.strip
    return render_json_dump(results: []) if query.length < MIN_SEARCH_LENGTH

    series = find_series
    chip = series && find_chip(series)
    version = chip && find_version(chip)
    return render_json_dump(results: []) if version.nil?

    render_json_dump(results: search_results(version, query))
  end

  private

  def payload(series, chip, version, page)
    data = {
      series: series_list,
      series_slug: series&.slug,
      chip_slug: chip&.slug,
      product: chip && IngenicProductSerializer.new(chip, root: false),
      versions: available_versions(chip),
    }

    return data if version.nil?

    data[:version] = IngenicVersionSerializer.new(version, root: false)
    data[:pages] =
      ActiveModel::ArraySerializer.new(
        version.published_pages,
        each_serializer: IngenicPageListSerializer,
      )

    if page
      data[:page] = IngenicPageSerializer.new(page, root: false)
      data[:navigation] = navigation_json(version, page)
    end

    data
  end

  def navigation_json(version, page)
    links = version.navigation_for(page)

    {
      previous: links[:previous] && IngenicPageListSerializer.new(links[:previous], root: false),
      next: links[:next] && IngenicPageListSerializer.new(links[:next], root: false),
    }
  end

  # The selector's data. Sent with every documentation response so switching
  # series or chip does not need a second round trip.
  def series_list
    IngenicProduct.series.published.where(locale: locale).ordered.map do |series|
      {
        id: series.id,
        slug: series.slug,
        name: series.name,
        chips:
          series.children.published.where(locale: locale).ordered.map do |chip|
            { id: chip.id, slug: chip.slug, name: chip.name }
          end,
      }
    end
  end

  def search_results(version, query)
    needle = query.downcase

    version.published_pages.reject(&:folder?).filter_map do |resolved|
      body = resolved.body.to_s
      title = resolved.title.to_s

      if title.downcase.include?(needle)
        { slug: resolved.slug, title: title, excerpt: excerpt_for(body, needle), matched: "title" }
      elsif body.downcase.include?(needle)
        { slug: resolved.slug, title: title, excerpt: excerpt_for(body, needle), matched: "body" }
      end
    end.first(SEARCH_LIMIT)
  end

  # Documentation is authored in Markdown, so the excerpt is taken from the
  # source and flattened rather than from cooked HTML — the reader wants the
  # sentence, not the markup around it.
  def excerpt_for(body, needle)
    text = body
      .gsub(/```.*?```/m, " ")
      .gsub(/<[^>]*>/, " ")
      .gsub(/!?\[([^\]]*)\]\([^)]*\)/, '\1')
      .gsub(/[#*_>`~]/, " ")
      .gsub(/\s+/, " ")
      .strip

    index = text.downcase.index(needle)
    return text.first(EXCERPT_RADIUS * 2) if index.nil?

    start = [index - EXCERPT_RADIUS, 0].max
    finish = [index + needle.length + EXCERPT_RADIUS, text.length].min
    fragment = text[start...finish]
    fragment = "…#{fragment}" if start.positive?
    fragment = "#{fragment}…" if finish < text.length
    fragment
  end

  # A version carries no `published` flag, so the selector lists every version
  # the product has: what a reader may see is decided page by page, and the
  # version that is empty because nobody has written it yet shows the pages it
  # inherited.
  def available_versions(chip)
    return [] if chip.nil?

    chip.versions.ordered.map { |record| IngenicVersionSerializer.new(record, root: false) }
  end

  # Read from the path segments on `show`, and from query parameters on
  # `search` — both funnel through the same resolvers, so a search is always
  # scoped to the chip and version the reader is actually looking at.
  def series_slug
    @series_slug ||= path_segments[0].presence || params[:series].presence
  end

  def chip_slug
    @chip_slug ||= path_segments[1].presence || params[:chip].presence
  end

  def version_slug
    @version_slug ||= path_segments[2].presence || params[:version].presence
  end

  def page_slug
    @page_slug ||= path_segments[3].presence || params[:page].presence
  end

  def path_segments
    @path_segments ||= params[:path].to_s.split("/").reject(&:blank?).first(MAX_PATH_SEGMENTS)
  end

  # Resolves the series named in the path, or the first one when the visitor has
  # not chosen yet. That is what lets the navigation point every "Documentation"
  # entry at one stable URL.
  #
  # The fallback prefers a series whose documentation has actually been written.
  # A series can be created before the first page is, and landing the bare
  # /ingenic/docs on it showed an empty page with no version dropdown — the
  # reader then concluded the documentation was broken rather than unwritten.
  def find_series
    scope = IngenicProduct.series.published.where(locale: locale).ordered

    return scope.find_by(slug: series_slug) if series_slug.present?

    candidates = scope.to_a
    candidates.find { |series| series_documented?(series) } || candidates.first
  end

  def find_chip(series)
    scope = series.children.published.where(locale: locale).ordered

    return scope.find_by(slug: chip_slug) if chip_slug.present?

    chips = scope.to_a
    chips.find { |chip| chip.versions.exists? } || chips.first
  end

  # A chip with no versions is a chip nobody has written about yet.
  def series_documented?(series)
    series.children.published.where(locale: locale).any? { |chip| chip.versions.exists? }
  end

  # An explicit `latest` is an alias for the version flagged latest, not a slug
  # of its own. The version list belongs to one product, and a product is one
  # language's manual, so there is no other language to fall back to.
  def find_version(chip)
    versions = chip.versions.ordered

    if version_slug.blank? || version_slug == "latest"
      return versions.find(&:latest) || versions.first
    end

    # No `published` scope here: a version has no such column. What is published
    # or not is decided per page — an unpublished version is one whose pages a
    # reader cannot see — so a version that exists is one a reader can open, and
    # asking for one that does not exist is the 404 below.
    versions.find_by(slug: version_slug)
  end

  def find_page(version)
    return if page_slug.blank?

    version.find_readable_page(page_slug)
  end

  def locale
    @locale ||= Ingenic::Locales.reading
  end

  def render_not_found(key)
    render json: { errors: [I18n.t("ingenic.errors.#{key}")] }, status: 404
  end
end
