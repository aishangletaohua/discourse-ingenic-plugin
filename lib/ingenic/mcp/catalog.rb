# frozen_string_literal: true

module Ingenic
  module Mcp
    # The developer centre as an outside client sees it.
    #
    # It is the same catalogue the public pages draw and the assistant reads,
    # with two differences that matter to a machine. Every answer names the
    # language it came from, and every row carries the address a person would
    # open. Nothing here reaches for the database directly: the product tree,
    # the version resolver and the published scopes are the same ones the
    # reader's pages use, so a page that is not published cannot leak out
    # through MCP.
    #
    # Downloads are described, never delivered. The catalogue carries what the
    # card carries — release, platform, size, checksum, and what the card asks
    # for before the file opens. Handing out the file address would walk around
    # the access rule the download centre exists to apply.
    class Catalog
      # The catalogues are small; the caps keep a site that has filed thousands
      # of rows from answering an integration with a megabyte of JSON.
      CATALOGUE_LIMIT = 500

      # Longer than the assistant's excerpts because this is the page itself,
      # and short enough that one answer stays inside a model's context.
      MAX_BODY_LENGTH = 50_000

      def initialize(locale: nil)
        @locale = Ingenic::Locales.reading(locale)
      end

      attr_reader :locale

      # The whole catalogue: every published series, its published chips and
      # each chip's versions. This is what a client reads first, to learn the
      # names every other argument takes.
      def catalogue
        {
          locale:,
          documentation_url: url("/ingenic/docs"),
          series: series_tree
        }
      end

      # One chip at one version: the version list, and the table of contents a
      # reader of that version sees — inherited pages included, withdrawn
      # folders excluded, because it is the resolver's set.
      def chip_document(chip_slug:, series_slug: nil, version_slug: nil)
        chip = find_chip!(chip_slug:, series_slug:)
        series = chip.parent
        version = find_version(chip, version_slug)

        {
          locale:,
          documentation_url: url("/ingenic/docs"),
          series: series_tree,
          chip: chip_json(series, chip),
          version: version && version_json(version),
          pages:
            (
              if version
                version.published_pages.map do |page|
                  page_entry(series, chip, version, page)
                end
              else
                []
              end
            )
        }
      end

      # One page, as Markdown, with the addresses of the pages either side of
      # it so a client can walk the manual without asking for the contents
      # again between every page.
      def page(chip_slug:, page_slug:, series_slug: nil, version_slug: nil)
        chip = find_chip!(chip_slug:, series_slug:)
        series = chip.parent
        version = find_version(chip, version_slug)
        raise NotFound.new(:version_not_found, chip: chip_slug) if version.nil?

        resolved = version.find_readable_page(page_slug)
        raise NotFound.new(:page_not_found, page: page_slug) if resolved.nil?

        navigation = version.navigation_for(resolved)
        body = resolved.body.to_s

        {
          locale:,
          series: {
            slug: series.slug,
            name: series.name
          },
          chip: chip_json(series, chip),
          version: version_json(version),
          url: page_url(series, chip, version, resolved.slug),
          page: {
            slug: resolved.slug,
            title: resolved.title,
            format: "markdown",
            body: body.first(MAX_BODY_LENGTH),
            truncated: body.length > MAX_BODY_LENGTH,
            inherited_from: resolved.inherited_from&.label
          },
          previous:
            navigation_entry(series, chip, version, navigation[:previous]),
          next: navigation_entry(series, chip, version, navigation[:next])
        }
      end

      # The download centre. `access_level` and `access` say what the card asks
      # for, and `url` is the card; the file itself is not reachable from here.
      def downloads
        rows =
          IngenicDownload
            .where(published: true, locale:)
            .includes(:category, :versions, product: :parent)
            .order(:position, :name)
            .limit(CATALOGUE_LIMIT)

        {
          locale:,
          downloads_url: url("/ingenic/downloads"),
          downloads: rows.map { |download| download_json(download) }
        }
      end

      # The board and sample catalogue.
      def boards
        rows =
          IngenicBoard
            .published
            .for_locale(locale)
            .includes(product: :parent)
            .ordered
            .limit(CATALOGUE_LIMIT)

        {
          locale:,
          boards_url: url("/ingenic/boards"),
          boards: rows.map { |board| board_json(board) }
        }
      end

      private

      # ---- documentation ------------------------------------------------------

      def series_tree
        IngenicProduct
          .series
          .published
          .where(locale:)
          .ordered
          .limit(CATALOGUE_LIMIT)
          .map do |series|
            {
              slug: series.slug,
              name: series.name,
              url: url("/ingenic/docs/#{series.slug}"),
              chips:
                series
                  .children
                  .published
                  .where(locale:)
                  .ordered
                  .map do |chip|
                    {
                      slug: chip.slug,
                      name: chip.name,
                      url: url("/ingenic/docs/#{series.slug}/#{chip.slug}"),
                      versions:
                        chip.versions.map { |version| version_json(version) }
                    }
                  end
            }
          end
      end

      # Only a chip under a published series has an address a reader can open.
      # The slug alone is enough when it is unique, and the series is a
      # disambiguator for a site that has filed the same part number twice.
      def find_chip!(chip_slug:, series_slug:)
        chip =
          IngenicProduct
            .chips
            .published
            .where(locale:, slug: chip_slug)
            .includes(:parent)
            .detect do |candidate|
              parent = candidate.parent
              parent&.series? && parent.published? &&
                (series_slug.blank? || parent.slug == series_slug)
            end

        chip ||
          raise(
            NotFound.new(:chip_not_found, chip: chip_slug, series: series_slug)
          )
      end

      # A chip with no versions is a chip nobody has written about yet. The
      # contents are empty rather than an error; reading a page from it is.
      def find_version(chip, slug)
        return chip.default_version if slug.blank? || slug == "latest"

        chip.versions.find_by(slug:)
      end

      def chip_json(series, chip)
        {
          slug: chip.slug,
          name: chip.name,
          series_slug: series.slug,
          series_name: series.name,
          url: url("/ingenic/docs/#{series.slug}/#{chip.slug}"),
          versions: chip.versions.map { |version| version_json(version) }
        }
      end

      def version_json(version)
        {
          slug: version.slug,
          label: version.label,
          latest: version.latest?,
          deprecated: version.deprecated?,
          released_on: version.released_on&.iso8601
        }
      end

      def page_entry(series, chip, version, page)
        {
          slug: page.slug,
          title: page.title,
          folder: page.folder?,
          depth: page.depth.to_i,
          inherited_from: page.inherited_from&.label,
          url: page_url(series, chip, version, page.slug)
        }
      end

      def navigation_entry(series, chip, version, page)
        return if page.nil?

        {
          slug: page.slug,
          title: page.title,
          url: page_url(series, chip, version, page.slug)
        }
      end

      def page_url(series, chip, version, page_slug)
        url(
          "/ingenic/docs/#{series.slug}/#{chip.slug}/#{version.slug}/#{page_slug}"
        )
      end

      # ---- downloads ----------------------------------------------------------

      def download_json(download)
        product = download.product

        {
          name: download.name,
          family: download.family,
          category: download.category&.name,
          chip: product && { slug: product.slug, name: product.name },
          series:
            product&.parent &&
              { slug: product.parent.slug, name: product.parent.name },
          access_level: download.access_level,
          access: access_description(download.access_level),
          points: download.point_cost.to_i,
          url: url("/ingenic/downloads"),
          versions:
            download.versions.published.ordered.map do |version|
              {
                label: version.version,
                description: version.description,
                platform: version.platform,
                architecture: version.architecture,
                filename: version.original_filename,
                size: version.file_size,
                checksum: version.checksum,
                released_on: version.released_on&.iso8601
              }
            end
        }
      end

      # Two accounts can be asked for two different things for the same card,
      # so the catalogue states the rule rather than an answer. `points` beside
      # it is the other half of the price.
      def access_description(level)
        case level
        when IngenicDownload::FORM_REQUIRED
          "developer information required"
        when IngenicDownload::APPROVAL_REQUIRED
          "approved application required"
        else
          "sign-in required"
        end
      end

      # ---- boards -------------------------------------------------------------

      def board_json(board)
        product = board.product

        {
          name: board.name,
          slug: board.slug,
          kind: board.kind,
          chip: product && { slug: product.slug, name: product.name },
          series:
            product&.parent &&
              { slug: product.parent.slug, name: product.parent.name },
          description: board.description,
          specs: board.specs,
          details: board.details,
          sold_out: board.sold_out?,
          apply_url: board.application_url,
          purchase_url: board.purchase_url,
          url: url("/ingenic/boards")
        }
      end

      # ---- shared -------------------------------------------------------------

      def url(path)
        "#{Discourse.base_url.chomp("/")}#{path}"
      end
    end
  end
end
