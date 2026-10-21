# frozen_string_literal: true

# Site chrome is authored per language, like every other content row.
#
# The footer and social strip carried `_zh` copies of their label columns while
# header links, section cards and footer columns had no language at all. The
# result was three different answers to "which language is this row?": a
# locale column, a suffixed pair of columns, and "whatever the page is". One
# `locale` column per row, with the Chinese copy promoted to a row of its own,
# gives the management screen the same rule everywhere: pick a language, and
# everything you write belongs to it.
#
# Untranslated rows are copied rather than dropped. A Chinese footer that used
# to fall back to an English label keeps that label, now as an editable row,
# instead of losing the link.
class LocalizeIngenicSiteContent < ActiveRecord::Migration[7.2]
  TABLES = %i[
    ingenic_header_links
    ingenic_section_cards
    ingenic_footer_columns
    ingenic_social_links
  ].freeze

  def up
    default = default_locale

    TABLES.each do |table|
      add_column table, :locale, :string, null: false, default: default
    end

    promote_chinese_rows(default)

    add_order_indexes
  end

  def down
    remove_order_indexes
    TABLES.each { |table| remove_column table, :locale }
  end

  private

  def default_locale
    SiteSetting.default_locale.presence || "en"
  end

  def chinese_locale
    return @chinese_locale if defined?(@chinese_locale)

    supported =
      if SiteSetting.content_localization_enabled
        Array(SiteSetting.content_localization_supported_locales).map(&:to_s)
      else
        []
      end

    @chinese_locale = supported.find { |code| code.start_with?("zh") }
  end

  def promote_chinese_rows(default)
    chinese = chinese_locale
    return if chinese.blank? || chinese == default

    %i[ingenic_header_links ingenic_section_cards].each do |table|
      execute <<~SQL
        INSERT INTO #{table}
          (label, #{table == :ingenic_header_links ? "href, icon, image_url, show_label, external, " : "category, href, description, icon, image_url, color, "}
           position, published, locale, created_at, updated_at)
        SELECT label,
               #{table == :ingenic_header_links ? "href, icon, image_url, show_label, external, " : "category, href, description, icon, image_url, color, "}
               position, published, #{quote(chinese)}, NOW(), NOW()
        FROM #{table}
        WHERE locale = #{quote(default)}
      SQL
    end

    execute <<~SQL
      INSERT INTO ingenic_social_links
        (label, kind, href, image_url, qr_image_url, qr_caption, icon_only, position, published,
         locale, created_at, updated_at)
      SELECT COALESCE(NULLIF(label_zh, ''), label),
             kind, href, image_url, qr_image_url,
             COALESCE(NULLIF(qr_caption_zh, ''), qr_caption),
             icon_only, position, published, #{quote(chinese)}, NOW(), NOW()
      FROM ingenic_social_links
      WHERE locale = #{quote(default)}
    SQL

    columns =
      select_all(<<~SQL).to_a
        SELECT *
        FROM ingenic_footer_columns
        WHERE locale = #{quote(default)}
        ORDER BY position, id
      SQL

    columns.each do |column|
      copy =
        select_one(<<~SQL)
          INSERT INTO ingenic_footer_columns
            (title, position, published, locale, created_at, updated_at)
          VALUES
            (#{quote(column["title_zh"].presence || column["title"])},
             #{quote(column["position"])}, #{quote(column["published"])},
             #{quote(chinese)}, NOW(), NOW())
          RETURNING id
        SQL

      execute <<~SQL
        INSERT INTO ingenic_footer_links
          (column_id, label, href, external, position, published, created_at, updated_at)
        SELECT #{quote(copy["id"])},
               COALESCE(NULLIF(label_zh, ''), label),
               href, external, position, published, NOW(), NOW()
        FROM ingenic_footer_links
        WHERE column_id = #{quote(column["id"])}
        ORDER BY position, id
      SQL
    end
  end

  def add_order_indexes
    %i[
      ingenic_header_links
      ingenic_section_cards
      ingenic_footer_columns
      ingenic_social_links
      ingenic_promotions
    ].each do |table|
      add_index table,
                %i[locale published position],
                name: index_name_for(table)
    end
  end

  def remove_order_indexes
    %i[
      ingenic_header_links
      ingenic_section_cards
      ingenic_footer_columns
      ingenic_social_links
      ingenic_promotions
    ].each do |table|
      remove_index table, name: index_name_for(table)
    end
  end

  def index_name_for(table)
    "idx_#{table}_locale_order"
  end
end
