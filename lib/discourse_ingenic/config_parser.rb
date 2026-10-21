# frozen_string_literal: true

module DiscourseIngenic
  # Admin-editable navigation and homepage layout are stored as JSON strings in
  # site settings so that the Ingenic team can reorder or hide entries without a
  # deploy. Parsing is defensive: a malformed value degrades to an empty list
  # instead of breaking page rendering.
  module ConfigParser
    module_function

    def parse_list(raw)
      return [] if raw.blank?

      parsed = JSON.parse(raw)
      return [] unless parsed.is_a?(Array)

      parsed.select { |item| item.is_a?(Hash) }
    rescue JSON::ParserError => e
      Rails.logger.warn("[discourse-ingenic] #{e.message}")
      []
    end

    # The three blocks the navigation recognises, in the order it draws them.
    # The theme reads an entry's section to decide which block it goes in, so the
    # set is fixed here: an entry naming something else is read as the first
    # block rather than dropped, because a navigation row that vanishes is
    # harder to account for than one that appears in the wrong list. `member`
    # entries are drawn as rows of core's community section, below Topics.
    NAV_SECTIONS = %w[forum resources member].freeze

    def nav_items
      parse_list(SiteSetting.ingenic_nav_items)
        .select { |item| item["enabled"] != false }
        .map
        .with_index do |item, index|
          {
            "key" => item["key"].presence || "item-#{index}",
            "label" => item["label"].to_s,
            "icon" => item["icon"].presence || "circle",
            "href" => resolve_href(item),
            "section" => resolve_section(item),
            "external" => item["external"] == true,
            "position" => item["position"].is_a?(Integer) ? item["position"] : index,
          }
        end
        .sort_by { |item| item["position"] }
    end

    # Case and stray spaces are not a wrong group, so they are not treated as
    # one: "Resources" and " resources " both mean resources.
    def resolve_section(item)
      section = item["section"].to_s.strip.downcase

      NAV_SECTIONS.include?(section) ? section : NAV_SECTIONS.first
    end

    # The block types the front page knows how to draw. Kept here rather than
    # only in the theme so the admin endpoint can refuse a type that would be
    # saved and then silently skipped by the renderer.
    HOMEPAGE_BLOCK_TYPES = %w[
      categories
      promotions
      announcements
      discussions
      latest
      hot
      popular
      activity
      downloads
      boards
      bounties
      leaderboard
    ].freeze

    HOMEPAGE_LAYOUTS = %w[full main side].freeze

    # The layout is per language: an English reader and a Chinese reader get
    # the list written for them, and neither sees the other's titles. The
    # setting is a map of locale to block list; a plain array is the legacy
    # shape and is read as the default language's layout, so an existing site
    # keeps rendering while its administrator fills in the second language.
    def homepage_blocks(locale = nil)
      raw = parse_homepage_setting
      list =
        if raw.is_a?(Hash)
          raw[locale.to_s] || raw[Ingenic::Locales.default] || []
        else
          locale.nil? || locale.to_s == Ingenic::Locales.default ? raw : []
        end

      normalize_homepage_blocks(list)
    end

    # Every language's layout, for the admin screen and the export task.
    def homepage_blocks_by_locale
      raw = parse_homepage_setting

      Ingenic::Locales.supported.index_with do |code|
        list =
          if raw.is_a?(Hash)
            raw[code] || []
          elsif code == Ingenic::Locales.default
            raw
          else
            []
          end
        normalize_homepage_blocks(list)
      end
    end

    def parse_homepage_setting
      raw = SiteSetting.ingenic_homepage_blocks
      return [] if raw.blank?

      parsed = JSON.parse(raw)
      parsed.is_a?(Hash) || parsed.is_a?(Array) ? parsed : []
    rescue JSON::ParserError => e
      Rails.logger.warn("[discourse-ingenic] #{e.message}")
      []
    end

    def normalize_homepage_blocks(list)
      Array(list)
        .select { |item| item.is_a?(Hash) && item["enabled"] != false }
        .map
        .with_index do |item, index|
          layout = item["layout"].to_s
          {
            "type" => item["type"].to_s,
            "layout" => HOMEPAGE_LAYOUTS.include?(layout) ? layout : "",
            "position" => item["position"].is_a?(Integer) ? item["position"] : index,
            "limit" => item["limit"].is_a?(Integer) ? item["limit"] : 5,
            "category" => item["category"].to_s,
            "title" => item["title"].to_s,
            "html" => item["html"].to_s,
            # The categories block. An empty list means "the busiest ones",
            # which is what a front page wants before anyone has decided which
            # sections deserve the space.
            "categories" => slug_list(item["categories"]),
            "show_all" => item["show_all"] != false,
          }
        end
        .select { |item| item["type"].present? }
        .sort_by { |item| item["position"] }
    end

    # Written as a list, or as the comma-separated line an admin is more likely
    # to type into a one-line field.
    def slug_list(raw)
      list = raw.is_a?(Array) ? raw : raw.to_s.split(",")
      list.map { |slug| slug.to_s.strip }.reject(&:empty?)
    end

    # A nav entry may point at a Discourse category slug, an internal path or an
    # absolute external URL.
    #
    # A category entry resolves through the category itself, because Discourse
    # addresses a category by its slug *and* its id: `/c/open-source/12`. The
    # slug on its own is not a route — it answers 404 — so an entry built from
    # the slug alone is a link that looks right in the admin UI and goes nowhere
    # in the sidebar. Nobody wants to look up ids to write a navigation list,
    # which is what this is for.
    #
    # A category that is not there keeps the slug-only address rather than
    # disappearing: a visible link the doctor task names is easier to account
    # for than a navigation row that quietly went missing.
    def resolve_href(item)
      return item["href"].to_s if item["href"].present?

      slug = item["category"].to_s
      return "" if slug.blank?

      category = Category.find_by(slug: slug)
      category ? category.url : "/c/#{slug}"
    end
  end
end
