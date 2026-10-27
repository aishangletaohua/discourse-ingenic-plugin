# frozen_string_literal: true

module Ingenic
  module Assistant
    # The assistant's window onto the developer centre.
    #
    # The forum's own search knows about topics and posts, and the assistant's
    # search tool is built on it. Everything this plugin publishes — the
    # documentation, the download catalogue, the boards — lives in tables of its
    # own, so without this the assistant answers as though the documentation did
    # not exist and sends readers to threads about it instead of to it.
    #
    # One query, three kinds of answer, ranked together: a reader asking "how do
    # I flash the image" wants the page that says how, and a reader asking
    # "where is the T33 SDK" wants the catalogue entry. The tool that wraps this
    # gets both without having to know which kind of thing was asked for.
    class Search
      MIN_QUERY_LENGTH = 2
      MAX_TERMS = 6
      DEFAULT_LIMIT = 8
      MAX_LIMIT = 12

      # Characters of body text shown around a match.
      SNIPPET_RADIUS = 180

      # Catalogue rows are few enough to read whole; the cap is a guard against
      # a site that files thousands of them.
      CATALOGUE_LIMIT = 400

      SCOPES = %w[all documentation downloads boards].freeze

      Result = Struct.new(:kind, :title, :path, :excerpt, :meta, :score, keyword_init: true)

      def initialize(query:, user: nil, locale: nil, limit: DEFAULT_LIMIT, scope: "all")
        @query = query.to_s.strip
        @user = user
        @locale = locale.to_s.presence || reader_locale
        @limit = limit.to_i.clamp(1, MAX_LIMIT)
        @scope = SCOPES.include?(scope.to_s) ? scope.to_s : "all"
      end

      def results
        return [] if query.length < MIN_QUERY_LENGTH

        found = collect(locale)

        # A catalogue that has not been translated yet should still answer: if
        # the reader's language found nothing, look through every language
        # rather than reporting that the documentation does not exist.
        found = collect(nil) if found.empty? && locale.present?

        found
          .sort_by { |result| [-result.score, KIND_ORDER.fetch(result.kind, 9), result.title] }
          .first(limit)
      end

      private

      attr_reader :query, :user, :locale, :limit

      KIND_ORDER = { documentation: 0, download: 1, board: 2 }.freeze

      def collect(for_locale)
        results = []

        results.concat(documentation(for_locale)) if scope?("documentation")

        results.concat(downloads(for_locale)) if scope?("downloads")

        results.concat(boards(for_locale)) if scope?("boards")

        results
      end

      def scope?(kind)
        @scope == "all" || @scope == kind
      end

      def terms
        @terms ||= query.downcase.split(/\s+/).reject(&:blank?).first(MAX_TERMS)
      end

      # ---- documentation ------------------------------------------------------

      # Documentation is read from the resolver rather than from the page rows.
      # Only the resolver knows that a page written for v1.0 is still part of
      # v1.1, and that an article under a withdrawn folder is not part of
      # anything — searching rows directly would quote a page the reader cannot
      # open, and link to a version that no longer shows it.
      def documentation(for_locale)
        chips(for_locale).flat_map do |chip|
          series = chip.parent
          # The newest version in the chain, ordered the way the resolver orders
          # them, so "newest" means the same thing here as it does on the page.
          version =
            chip.versions.to_a.max_by { |candidate| [candidate.position.to_i, candidate.id] }
          next [] unless version

          # The newest version resolves the whole manual, inherited pages
          # included, so its resolved set is the reader's current view of this
          # chip and the address it gives is one that opens.
          version
            .published_pages
            .reject(&:folder?)
            .filter_map do |page|
              text = "#{page.title}\n#{page.body}".downcase
              next unless terms.all? { |term| text.include?(term) }

              Result.new(
                kind: :documentation,
                title: page.title,
                path: "/ingenic/docs/#{series.slug}/#{chip.slug}/#{version.slug}/#{page.slug}",
                excerpt: excerpt_for(page.body),
                meta: [series.name, chip.name, version.label].compact.join(" · "),
                score: score_for(title: page.title, body: page.body, title_weight: 6),
              )
            end
        end
      end

      # Only chips filed under a published series have an address a reader can
      # open: the documentation path starts at the series.
      def chips(for_locale)
        scope = IngenicProduct.chips.published.includes(:parent)
        scope = scope.where(locale: for_locale.to_s) if for_locale.present?

        scope.select { |chip| chip.parent&.series? && chip.parent.published? }
      end

      # ---- downloads ----------------------------------------------------------

      def downloads(for_locale)
        scope = IngenicDownload.where(published: true).includes(:versions, :category)
        scope = scope.where(locale: for_locale.to_s) if for_locale.present?

        scope
          .limit(CATALOGUE_LIMIT)
          .filter_map do |download|
            versions = download.versions.select(&:published)
            text = [
              download.name,
              download.category&.name,
              *versions.map(&:version),
              *versions.map(&:description),
            ].compact.join("\n").downcase

            next unless terms.all? { |term| text.include?(term) }

            Result.new(
              kind: :download,
              title: download.name,
              path: "/ingenic/downloads",
              excerpt: download_excerpt(download, versions),
              meta: download_meta(download),
              score: score_for(title: download.name, body: text, title_weight: 4),
            )
          end
      end

      def download_excerpt(download, versions)
        version = versions.find { |candidate| candidate.description.present? }

        if version
          "#{version.version}: #{flatten(version.description)}"
        else
          I18n.t(
            "ingenic.assistant.download.none_description",
            default: "Listed in the download centre.",
          )
        end
      end

      # The catalogue's access rules, said in the reader's terms. What the file
      # is gated on is a property of the resource, not of the account asking:
      # the assistant says what is needed, and the reader is sent to the card
      # that applies it.
      def download_meta(download)
        requirement =
          case download.access_level
          when IngenicDownload::FORM_REQUIRED
            I18n.t(
              "ingenic.assistant.download.needs_profile",
              default: "needs developer information",
            )
          when IngenicDownload::APPROVAL_REQUIRED
            I18n.t(
              "ingenic.assistant.download.needs_approval",
              default: "needs an approved application",
            )
          else
            I18n.t("ingenic.assistant.download.needs_sign_in", default: "needs sign-in")
          end

        [
          I18n.t("ingenic.assistant.download.kind", default: "download"),
          download.category&.name,
          requirement,
          download.point_cost.to_i.positive? ? "#{download.point_cost} points" : nil,
        ].compact.join(" · ")
      end

      # ---- boards -------------------------------------------------------------

      def boards(for_locale)
        scope = IngenicBoard.published
        scope = scope.for_locale(for_locale.to_s) if for_locale.present?

        scope
          .includes(:product)
          .limit(CATALOGUE_LIMIT)
          .filter_map do |board|
            text = [board.name, board.description, board.specs, board.details].compact
              .join("\n")
              .downcase

            next unless terms.all? { |term| text.include?(term) }

            Result.new(
              kind: :board,
              title: board.name,
              path: "/ingenic/boards",
              excerpt: flatten([board.description, board.specs].compact.join(" — ")),
              meta: [
                board.kind == "sample" ? "sample" : "board",
                board.chip_name,
                board.series_name,
              ].compact.join(" · "),
              score: score_for(title: board.name, body: text, title_weight: 4),
            )
          end
      end

      # ---- shared -------------------------------------------------------------

      def score_for(title:, body:, title_weight:)
        title = title.to_s.downcase
        body = body.to_s.downcase

        title_score = terms.count { |term| title.include?(term) } * title_weight
        body_score = body.scan(terms.first.to_s).size.clamp(0, 10)

        title_score + body_score + 1
      end

      def excerpt_for(markdown)
        text = flatten(markdown)
        return text.first(SNIPPET_RADIUS * 2) if terms.empty?

        indexes = terms.filter_map { |term| text.downcase.index(term) }
        index = indexes.min
        return text.first(SNIPPET_RADIUS * 2) if index.nil?

        start = [index - SNIPPET_RADIUS, 0].max
        finish = [index + SNIPPET_RADIUS, text.length].min

        fragment = text[start...finish]
        fragment = "…#{fragment}" if start.positive?
        fragment = "#{fragment}…" if finish < text.length
        fragment
      end

      # Documentation is authored in Markdown and the catalogue is written in
      # plain prose. The assistant wants the sentence either way, not the
      # markup around it.
      def flatten(text)
        text
          .to_s
          .gsub(/```.*?```/m, " ")
          .gsub(/<[^>]*>/, " ")
          .gsub(/!?\[([^\]]*)\]\([^)]*\)/, '\1')
          .gsub(/[#*_>`~]/, " ")
          .gsub(/\s+/, " ")
          .strip
      end

      # Which language's catalogue to answer from. The reader is talking to the
      # assistant in their own language, so the answer is drawn from the
      # catalogue written in it; `Ingenic::Locales` normalises `zh-CN` and falls
      # back to the site default the same way the public pages do.
      def reader_locale
        return @reader_locale if defined?(@reader_locale)

        requested = user&.effective_locale if user.respond_to?(:effective_locale)
        @reader_locale = Ingenic::Locales.reading(requested)
      end
    end
  end
end
