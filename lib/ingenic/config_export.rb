# frozen_string_literal: true

module Ingenic
  # The Ingenic team's configuration, in one file.
  #
  # Everything here is something a person typed into an admin page: the product
  # tree, the documentation, the download catalogue, the board shop, the
  # documentation permissions, the homepage slots, the footer and the points
  # rules. Rebuilding the forum, or moving it to another machine, otherwise
  # means typing all of it a second time. That is the whole reason this exists.
  #
  # What is deliberately absent: anything a member produced. Point balances and
  # entries, bounties, download requests and grants, developer profiles and
  # download logs are a record of what people did, and one of those tables holds
  # personal data about them. A copy of those is a database dump, which has a
  # different lifetime and a different place to be kept, and is not something an
  # admin should be able to email around as a YAML file.
  #
  # Import is an upsert by natural key, and it never deletes. A row that exists
  # in the forum but not in the file stays where it is: the file says what the
  # forum should contain, not what it may contain, and an old file imported over
  # a newer forum would otherwise take real content away. Rows the file does not
  # mention are counted and reported instead, so nothing disappears quietly.
  #
  # The uploaded SDK and firmware files themselves are not in here. Their rows
  # are, including the path each file was written to, so a machine whose storage
  # directory was copied across restores to a working download centre; a machine
  # without those files gets rows pointing at files that are not there, which is
  # what `ingenic_download_storage_path` is for.
  module ConfigExport
    # A row the forum refused. Carries which row and why, because "import
    # failed" on a file of several hundred rows is not something an admin can
    # act on.
    class ImportError < StandardError
    end

    VERSION = 1
    FILE_NAME = "ingenic-config.yml"
    SETTING_PREFIX = "ingenic_"

    # What each exporter reads, in an order where a row's parents come first.
    # Import walks the same list, so the two cannot drift apart.
    SECTIONS = %w[
      doc_products
      doc_versions
      doc_pages
      download_categories
      downloads
      boards
      promotions
      social_links
      footer_columns
      footer_links
      point_rules
      permissions
    ].freeze

    module_function

    def default_path
      File.join(Rails.root, FILE_NAME)
    end

    def export(path = nil)
      path ||= default_path
      File.write(path, payload.to_yaml)
      path
    end

    def payload
      {
        "version" => VERSION,
        "exported_at" => Time.zone.now.iso8601,
        "site_settings" => site_settings,
        "content" => SECTIONS.index_with { |section| public_send(section) },
      }
    end

    # The plugin's own site settings, and only the ones somebody changed.
    #
    # Discourse's exporter leaves out settings still sitting on their default,
    # which is exactly right here: an untouched setting is not configuration
    # anybody chose, and writing it down would freeze today's default into a
    # file that outlives it.
    def site_settings
      SiteSettingsTask
        .export_to_hash
        .select { |key, _value| key.start_with?(SETTING_PREFIX) }
        .sort
        .to_h
    end

    # ---------------------------------------------------------------- reading

    def doc_products
      IngenicDocProduct.order(:position, :slug, :locale).map do |product|
        {
          "slug" => product.slug,
          "locale" => product.locale,
          "name" => product.name,
          "kind" => product.kind,
          "description" => product.description,
          "parent_slug" => product.parent&.slug,
          "parent_locale" => product.parent&.locale,
          "published" => product.published,
          "position" => product.position,
        }
      end
    end

    def doc_versions
      IngenicDocVersion.includes(:product).order(:position, :slug).map do |version|
        {
          "product_slug" => version.product.slug,
          "product_locale" => version.product.locale,
          "slug" => version.slug,
          "locale" => version.locale,
          "label" => version.label,
          "latest" => version.latest,
          "deprecated" => version.deprecated,
          "released_on" => version.released_on&.iso8601,
          "position" => version.position,
        }
      end
    end

    def doc_pages
      IngenicDocPage.includes(:parent, version: :product).order(:position, :slug).map do |page|
        {
          "product_slug" => page.version.product.slug,
          "product_locale" => page.version.product.locale,
          "version_slug" => page.version.slug,
          "version_locale" => page.version.locale,
          "slug" => page.slug,
          "locale" => page.locale,
          "kind" => page.kind,
          "title" => page.title,
          "body" => page.body,
          "parent_slug" => page.parent&.slug,
          "topic_url" => page.topic_url,
          "published" => page.published,
          "position" => page.position,
        }
      end
    end

    def download_categories
      IngenicDownloadCategory.order(:position, :name, :locale).map do |category|
        {
          "name" => category.name,
          "locale" => category.locale,
          "position" => category.position,
          "published" => category.published,
        }
      end
    end

    def downloads
      IngenicDownload.includes(:category).order(:position, :name).map do |download|
        {
          "name" => download.name,
          "product_slug" => download.product_slug,
          "category" => download.category&.name,
          "version" => download.version,
          "locale" => download.locale,
          "description" => download.description,
          "platform" => download.platform,
          "architecture" => download.architecture,
          "access_level" => download.access_level,
          "point_cost" => download.point_cost,
          "file_url" => download.file_url,
          "file_size" => download.file_size,
          "sha256" => download.sha256,
          "storage_path" => download.storage_path,
          "original_filename" => download.original_filename,
          "file_sha256" => download.file_sha256,
          "released_on" => download.released_on&.iso8601,
          "published" => download.published,
          "position" => download.position,
        }
      end
    end

    def boards
      IngenicBoard.includes(:product).order(:position, :slug, :locale).map do |board|
        {
          "slug" => board.slug,
          "locale" => board.locale,
          "name" => board.name,
          "kind" => board.kind,
          "chip" => board.chip,
          "description" => board.description,
          "details" => board.details,
          "specs" => board.specs,
          "image_url" => board.image_url,
          "application_url" => board.application_url,
          "purchase_url" => board.purchase_url,
          "sold_out" => board.sold_out,
          "product_slug" => board.product&.slug,
          "product_locale" => board.product&.locale,
          "published" => board.published,
          "position" => board.position,
        }
      end
    end

    def promotions
      IngenicPromotion.order(:position, :title, :locale).map do |promotion|
        {
          "title" => promotion.title,
          "locale" => promotion.locale,
          "corner_label" => promotion.corner_label,
          "description" => promotion.description,
          "button_label" => promotion.button_label,
          "button_href" => promotion.button_href,
          "button_external" => promotion.button_external,
          "image_url" => promotion.image_url,
          "starts_at" => promotion.starts_at&.iso8601,
          "ends_at" => promotion.ends_at&.iso8601,
          "published" => promotion.published,
          "position" => promotion.position,
        }
      end
    end

    def social_links
      IngenicSocialLink.order(:position, :label).map do |link|
        {
          "label" => link.label,
          "label_zh" => link.label_zh,
          "kind" => link.kind,
          "href" => link.href,
          "image_url" => link.image_url,
          "qr_image_url" => link.qr_image_url,
          "qr_caption" => link.qr_caption,
          "qr_caption_zh" => link.qr_caption_zh,
          "published" => link.published,
          "position" => link.position,
        }
      end
    end

    def footer_columns
      IngenicFooterColumn.order(:position, :title).map do |column|
        {
          "title" => column.title,
          "title_zh" => column.title_zh,
          "published" => column.published,
          "position" => column.position,
        }
      end
    end

    def footer_links
      IngenicFooterLink.includes(:column).order(:position, :label).map do |link|
        {
          "column" => link.column.title,
          "label" => link.label,
          "label_zh" => link.label_zh,
          "href" => link.href,
          "external" => link.external,
          "published" => link.published,
          "position" => link.position,
        }
      end
    end

    def point_rules
      IngenicPointRule.order(:position, :event).map do |rule|
        {
          "event" => rule.event,
          "points" => rule.points,
          "label" => rule.label,
          "published" => rule.published,
          "position" => rule.position,
        }
      end
    end

    # Who may manage which product's documentation.
    #
    # Principals and resources are written down by name rather than by id: ids
    # belong to one database, and a file whose meaning depends on them is not
    # portable, which is the point of the file.
    def permissions
      IngenicPermission.includes(:user, :group).order(:id).filter_map do |permission|
        principal = principal_of(permission)
        resource = resource_of(permission)

        if principal.nil? || resource.nil?
          Rails.logger.warn(
            "[discourse-ingenic] permission #{permission.id} names a " \
              "#{permission.resource_type} that this export cannot describe; skipped",
          )
          next
        end

        {
          "principal_type" => principal.first,
          "principal" => principal.last,
          "resource_type" => permission.resource_type,
          "resource" => resource,
          "permission" => permission.permission,
        }
      end
    end

    def principal_of(permission)
      return ["user", permission.user.username] if permission.user_id
      return ["group", permission.group.name] if permission.group_id

      nil
    end

    def resource_of(permission)
      case permission.resource_type
      when "IngenicDocProduct"
        product = IngenicDocProduct.find_by(id: permission.resource_id)
        product && { "slug" => product.slug, "locale" => product.locale }
      when "IngenicDocPage"
        page = IngenicDocPage.includes(version: :product).find_by(id: permission.resource_id)
        page &&
          {
            "product_slug" => page.version.product.slug,
            "product_locale" => page.version.product.locale,
            "version_slug" => page.version.slug,
            "version_locale" => page.version.locale,
            "slug" => page.slug,
            "locale" => page.locale,
          }
      when "IngenicBoard"
        board = IngenicBoard.find_by(id: permission.resource_id)
        board && { "slug" => board.slug, "locale" => board.locale }
      end
    end

    # ---------------------------------------------------------------- writing

    # Reads a file back in, in a transaction: a configuration half applied is
    # worse than one not applied at all, because the second run has to work out
    # which half it was looking at.
    def import(path, dry_run: false)
      data = load_file(path)
      report = SECTIONS.index_with { { "created" => 0, "updated" => 0 } }

      ActiveRecord::Base.transaction do
        report["settings"] = apply_settings(data["site_settings"] || {})
        SECTIONS.each { |section| public_send("apply_#{section}", data.dig("content", section) || [], report[section]) }
        report["untouched"] = untouched(data["content"] || {})
        raise ActiveRecord::Rollback if dry_run
      end

      report
    end

    def load_file(path)
      raise ArgumentError, "no configuration file at #{path}" unless File.exist?(path)

      data = YAML.safe_load(File.read(path), permitted_classes: [Date, Time], aliases: true)

      # A file of ours says so: it carries a format version and a content
      # section, and `payload` always writes both. Asking only whether the YAML
      # was a mapping let any mapping through — importing an unrelated
      # configuration file reported a run in which nothing was applied and
      # nothing was wrong, which is the worst of the two answers, and the
      # message below was one this never raised.
      unless data.is_a?(Hash) && data["version"].is_a?(Integer) && data["content"].is_a?(Hash)
        raise ArgumentError, "#{path} is not an Ingenic configuration file"
      end

      if data["version"] > VERSION
        raise ArgumentError,
              "#{path} was written by a newer version (#{data["version"]}); " \
                "this plugin understands #{VERSION}"
      end

      data
    end

    def apply_settings(settings)
      return { "updated" => 0, "not_found" => 0, "errors" => 0 } if settings.empty?

      # Discourse's own importer already knows how to write a setting of each
      # type, refuses keys it does not recognise, and logs what it changed.
      _log, counts = SiteSettingsTask.import(settings.to_yaml)
      counts.transform_keys(&:to_s)
    end

    def apply_doc_products(rows, report)
      # Series before chips. The forum enforces that a chip has a parent and a
      # series does not, so a chip cannot be saved before the series it names —
      # and it cannot be saved without its parent either, which is why the
      # parent is set here rather than in a second pass.
      rows
        .sort_by { |row| [row["parent_slug"].blank? ? 0 : 1, row["position"].to_i] }
        .each do |row|
          parent =
            row["parent_slug"].presence &&
              IngenicDocProduct.find_by(
                slug: row["parent_slug"],
                locale: row["parent_locale"].presence || locale_of(row),
              )

          upsert(report, IngenicDocProduct, { slug: row["slug"], locale: locale_of(row) }) do |product|
            product.name = row["name"]
            product.kind = row["kind"].presence || (parent ? IngenicDocProduct::CHIP : IngenicDocProduct::SERIES)
            product.parent = parent
            product.description = row["description"]
            product.published = row.fetch("published", true)
            product.position = row["position"].to_i
          end
        end
    end

    def apply_doc_versions(rows, report)
      rows.each do |row|
        product = product_for(row)
        next if product.nil?

        upsert(
          report,
          IngenicDocVersion,
          { product_id: product.id, slug: row["slug"], locale: locale_of(row) },
        ) do |version|
          version.label = row["label"]
          version.latest = row.fetch("latest", false)
          version.deprecated = row.fetch("deprecated", false)
          version.released_on = row["released_on"]
          version.position = row["position"].to_i
        end
      end
    end

    def apply_doc_pages(rows, report)
      rows.each do |row|
        version = version_for(row)
        next if version.nil?

        upsert(report, IngenicDocPage, { version_id: version.id, slug: row["slug"], locale: locale_of(row) }) do |page|
          # Files written before folders existed carry no `kind`; every row in
          # them is an article.
          page.kind = row["kind"].presence || "page"
          page.title = row["title"]
          page.body = row["body"]
          page.topic_url = row["topic_url"]
          page.published = row.fetch("published", true)
          page.position = row["position"].to_i
        end
      end

      # Parent pages come second for the same reason chip parents do: a page
      # cannot point at one that is not there yet.
      rows.each do |row|
        next if row["parent_slug"].blank?

        version = version_for(row)
        next if version.nil?

        page = IngenicDocPage.find_by(version_id: version.id, slug: row["slug"], locale: locale_of(row))
        parent =
          IngenicDocPage.find_by(version_id: version.id, slug: row["parent_slug"], locale: locale_of(row))
        page.update!(parent: parent) if page && parent && page.parent_id != parent.id
      end
    end

    def apply_download_categories(rows, report)
      rows.each do |row|
        upsert(report, IngenicDownloadCategory, { name: row["name"], locale: locale_of(row) }) do |category|
          category.position = row["position"].to_i
          category.published = row.fetch("published", true)
        end
      end
    end

    # Keyed on the name as well as the product, category, version and language:
    # a version can legitimately have more than one file under it — an SDK and
    # its release notes, say — and keying on the version alone would fold them
    # into one row.
    def apply_downloads(rows, report)
      rows.each do |row|
        category =
          row["category"].presence &&
            IngenicDownloadCategory.find_by(name: row["category"], locale: locale_of(row))

        upsert(
          report,
          IngenicDownload,
          {
            product_slug: row["product_slug"],
            category_id: category&.id,
            version: row["version"],
            locale: locale_of(row),
            name: row["name"],
          },
        ) do |download|
          download.description = row["description"]
          download.platform = row["platform"]
          download.architecture = row["architecture"]
          download.access_level = row["access_level"].presence || IngenicDownload::LOGIN_ONLY
          download.point_cost = row["point_cost"].to_i
          download.file_url = row["file_url"]
          download.file_size = row["file_size"]
          download.sha256 = row["sha256"]
          download.storage_path = row["storage_path"]
          download.original_filename = row["original_filename"]
          download.file_sha256 = row["file_sha256"]
          download.released_on = row["released_on"]
          download.published = row.fetch("published", true)
          download.position = row["position"].to_i
        end
      end
    end

    def apply_boards(rows, report)
      rows.each do |row|
        product = product_for(row)

        upsert(report, IngenicBoard, { slug: row["slug"], locale: locale_of(row) }) do |board|
          board.name = row["name"]
          board.kind = row.fetch("kind", "board")
          board.chip = row["chip"]
          board.description = row["description"]
          board.details = row["details"]
          board.specs = row["specs"]
          board.image_url = row["image_url"]
          board.application_url = row["application_url"]
          board.purchase_url = row["purchase_url"]
          board.sold_out = row.fetch("sold_out", false)
          board.product = product
          board.published = row.fetch("published", true)
          board.position = row["position"].to_i
        end
      end
    end

    def apply_promotions(rows, report)
      rows.each do |row|
        upsert(report, IngenicPromotion, { title: row["title"], locale: locale_of(row) }) do |promotion|
          promotion.corner_label = row["corner_label"]
          promotion.description = row["description"]
          promotion.button_label = row["button_label"]
          promotion.button_href = row["button_href"]
          promotion.button_external = row.fetch("button_external", false)
          promotion.image_url = row["image_url"]
          promotion.starts_at = row["starts_at"]
          promotion.ends_at = row["ends_at"]
          promotion.published = row.fetch("published", true)
          promotion.position = row["position"].to_i
        end
      end
    end

    def apply_social_links(rows, report)
      rows.each do |row|
        upsert(report, IngenicSocialLink, { label: row["label"], kind: row["kind"].presence || "link" }) do |link|
          link.label_zh = row["label_zh"]
          link.href = row["href"]
          link.image_url = row["image_url"]
          link.qr_image_url = row["qr_image_url"]
          link.qr_caption = row["qr_caption"]
          link.qr_caption_zh = row["qr_caption_zh"]
          link.published = row.fetch("published", true)
          link.position = row["position"].to_i
        end
      end
    end

    def apply_footer_columns(rows, report)
      rows.each do |row|
        upsert(report, IngenicFooterColumn, { title: row["title"] }) do |column|
          column.title_zh = row["title_zh"]
          column.published = row.fetch("published", true)
          column.position = row["position"].to_i
        end
      end
    end

    def apply_footer_links(rows, report)
      rows.each do |row|
        column = IngenicFooterColumn.find_by(title: row["column"])
        next if column.nil?

        upsert(report, IngenicFooterLink, { column_id: column.id, label: row["label"] }) do |link|
          link.label_zh = row["label_zh"]
          link.href = row["href"]
          link.external = row.fetch("external", false)
          link.published = row.fetch("published", true)
          link.position = row["position"].to_i
        end
      end
    end

    def apply_point_rules(rows, report)
      rows.each do |row|
        upsert(report, IngenicPointRule, { event: row["event"] }) do |rule|
          rule.points = row["points"].to_i
          rule.label = row["label"]
          rule.published = row.fetch("published", true)
          rule.position = row["position"].to_i
        end
      end
    end

    def apply_permissions(rows, report)
      rows.each do |row|
        principal = find_principal(row)
        resource = find_resource(row["resource_type"], row["resource"] || {})

        if principal.nil? || resource.nil?
          Rails.logger.warn(
            "[discourse-ingenic] permission for #{row["principal_type"]} " \
              "#{row["principal"]} on #{row["resource_type"]} names something this " \
              "forum does not have; skipped",
          )
          next
        end

        upsert(
          report,
          IngenicPermission,
          principal.merge(
            resource_type: row["resource_type"],
            resource_id: resource.id,
            permission: row["permission"].presence || "manage",
          ),
        ) { |_permission| nil }
      end
    end

    def find_principal(row)
      case row["principal_type"]
      when "user"
        user = User.find_by(username: row["principal"])
        { user_id: user.id, group_id: nil } if user
      when "group"
        group = Group.find_by(name: row["principal"])
        { user_id: nil, group_id: group.id } if group
      end
    end

    def find_resource(resource_type, resource)
      case resource_type
      when "IngenicDocProduct"
        IngenicDocProduct.find_by(slug: resource["slug"], locale: locale_of(resource))
      when "IngenicBoard"
        IngenicBoard.find_by(slug: resource["slug"], locale: locale_of(resource))
      when "IngenicDocPage"
        version =
          IngenicDocVersion.joins(:product).find_by(
            slug: resource["version_slug"],
            locale: locale_of(resource, "version_locale"),
            ingenic_doc_products: {
              slug: resource["product_slug"],
              locale: locale_of(resource, "product_locale"),
            },
          )
        version &&
          IngenicDocPage.find_by(
            version_id: version.id,
            slug: resource["slug"],
            locale: locale_of(resource),
          )
      end
    end

    # ------------------------------------------------------------- accounting

    # Rows the file does not mention. Reported rather than removed: an admin
    # importing yesterday's file should be told what today's forum has that the
    # file does not, and then decide.
    def untouched(content)
      counts = {}

      {
        "doc_products" => IngenicDocProduct,
        "doc_versions" => IngenicDocVersion,
        "doc_pages" => IngenicDocPage,
        "download_categories" => IngenicDownloadCategory,
        "downloads" => IngenicDownload,
        "boards" => IngenicBoard,
        "promotions" => IngenicPromotion,
        "social_links" => IngenicSocialLink,
        "footer_columns" => IngenicFooterColumn,
        "footer_links" => IngenicFooterLink,
        "point_rules" => IngenicPointRule,
      }.each do |section, model|
        listed = (content[section] || []).size
        extra = model.count - listed
        counts[section] = extra if extra.positive?
      end

      counts
    end

    # ----------------------------------------------------------------- shared

    # Saving only what changed is what lets the report distinguish "the file
    # brought something new" from "the file agreed with the forum", which is
    # the difference between a first import and the fifth one.
    def upsert(report, model, key)
      record = model.find_or_initialize_by(key)
      created = record.new_record?
      yield record

      if created || record.changed?
        record.save!
        report[created ? "created" : "updated"] += 1
      end

      record
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
      raise ImportError,
            "#{model.name} #{key.inspect} was refused: #{e.record.errors.full_messages.join("; ")}"
    end

    def locale_of(row, key = "locale")
      row[key].presence || SiteSetting.ingenic_default_locale.presence || "en"
    end

    def product_for(row)
      IngenicDocProduct.find_by(
        slug: row["product_slug"],
        locale: row["product_locale"].presence || locale_of(row),
      )
    end

    def version_for(row)
      product = product_for(row)
      return nil if product.nil?

      IngenicDocVersion.find_by(
        product_id: product.id,
        slug: row["version_slug"],
        locale: row["version_locale"].presence || locale_of(row),
      )
    end
  end
end
