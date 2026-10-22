# frozen_string_literal: true

require_relative "../../lib/ingenic/site_page_defaults"

# The footer's policy links need somewhere to land.
#
# Until now every footer link was a URL, and the three pages a forum is expected
# to publish — the terms, the privacy policy and the rules for points — had no
# page of their own. The link was editable, so an editor pointed it at whatever
# existed; the page itself was never written.
#
# A page is a row per language, like every other piece of content the team
# edits. The initial copy is seeded in every language the site serves, so the
# footer works on the day this migration runs and the management screen opens
# with the text to edit rather than an empty form.
class CreateIngenicSitePages < ActiveRecord::Migration[7.2]
  def up
    create_table :ingenic_site_pages do |t|
      t.string :slug, null: false
      t.string :locale, null: false
      t.string :title, null: false
      t.text :body
      t.boolean :published, null: false, default: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    # A slug and a language identify a page. Two rows would be two answers to
    # the same address, and the reader would get whichever the query returned
    # first.
    add_index :ingenic_site_pages, %i[locale slug], unique: true
    add_index :ingenic_site_pages, %i[locale published position], name: "idx_ingenic_site_pages_locale_order"

    seed_defaults
  end

  def down
    drop_table :ingenic_site_pages
  end

  private

  def seed_defaults
    ::Ingenic::SitePageDefaults.rows_for(supported_locales).each do |row|
      execute <<~SQL
        INSERT INTO ingenic_site_pages
          (slug, locale, title, body, published, position, created_at, updated_at)
        VALUES
          (#{quote(row["slug"])}, #{quote(row["locale"])}, #{quote(row["title"])},
           #{quote(row["body"])}, TRUE, #{quote(row["position"])}, NOW(), NOW())
        ON CONFLICT (locale, slug) DO NOTHING
      SQL
    end
  end

  # What the site published at the moment this ran. Pages added to the default
  # set later are seeded by their own migration, not by this one.
  def supported_locales
    codes = [SiteSetting.default_locale.presence || "en"]

    if SiteSetting.content_localization_enabled
      codes.concat(Array(SiteSetting.content_localization_supported_locales))
    end

    codes.map(&:to_s).uniq
  end
end
