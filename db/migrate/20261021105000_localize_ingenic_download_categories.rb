# frozen_string_literal: true

# The download categories were seeded in the default language only.
#
# Every other content table now carries one row per language, and the category
# list is what the download screen's picker shows, so a Chinese editor opening
# it must find the Chinese shelves rather than an empty list. The names are
# copied as they stand: they are the vocabulary the team already uses, and an
# editor can rename the copy afterwards without touching the English one.
#
# Downloads in the copied language are re-pointed at their own copy. Two rows
# with the same name in different languages are different shelves; leaving a
# Chinese resource filed under the English one would put it under a label its
# reader's language does not show in the admin list.
class LocalizeIngenicDownloadCategories < ActiveRecord::Migration[7.2]
  def up
    chinese = chinese_locale
    return if chinese.blank? || chinese == default_locale

    rows =
      select_all(<<~SQL).to_a
        SELECT *
        FROM ingenic_download_categories
        WHERE locale = #{quote(default_locale)}
        ORDER BY position, id
      SQL

    rows.each do |row|
      copy =
        select_one(<<~SQL)
          INSERT INTO ingenic_download_categories
            (name, locale, position, published, created_at, updated_at)
          VALUES
            (#{quote(row["name"])}, #{quote(chinese)},
             #{quote(row["position"])}, #{quote(row["published"])},
             NOW(), NOW())
          ON CONFLICT (name, locale) DO UPDATE
          SET position = EXCLUDED.position,
              published = EXCLUDED.published,
              updated_at = EXCLUDED.updated_at
          RETURNING id
        SQL

      execute <<~SQL
        UPDATE ingenic_downloads
        SET category_id = #{quote(copy["id"])},
            updated_at = NOW()
        WHERE locale = #{quote(chinese)}
          AND category_id = #{quote(row["id"])}
      SQL
    end
  end

  def down
    chinese = chinese_locale
    return if chinese.blank? || chinese == default_locale

    copies =
      select_all(<<~SQL).to_a
        SELECT id, name
        FROM ingenic_download_categories
        WHERE locale = #{quote(chinese)}
      SQL

    copies.each do |copy|
      original =
        select_one(<<~SQL)
          SELECT id FROM ingenic_download_categories
          WHERE locale = #{quote(default_locale)} AND name = #{quote(copy["name"])}
        SQL
      next if original.nil?

      execute <<~SQL
        UPDATE ingenic_downloads
        SET category_id = #{quote(original["id"])},
            updated_at = NOW()
        WHERE locale = #{quote(chinese)}
          AND category_id = #{quote(copy["id"])}
      SQL

      execute <<~SQL
        DELETE FROM ingenic_download_categories WHERE id = #{quote(copy["id"])}
      SQL
    end
  end

  private

  def default_locale
    SiteSetting.default_locale.presence || "en"
  end

  def chinese_locale
    supported =
      if SiteSetting.content_localization_enabled
        Array(SiteSetting.content_localization_supported_locales).map(&:to_s)
      else
        []
      end

    supported.find { |code| code.start_with?("zh") }
  end
end
