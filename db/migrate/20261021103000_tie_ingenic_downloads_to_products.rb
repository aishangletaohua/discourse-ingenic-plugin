# frozen_string_literal: true

# A download that belongs to a chip belongs to a row in the catalogue.
#
# `product_slug` was free text. It was not checked against the catalogue, could
# not follow a renamed chip, and the public filter compared it by equality — so
# one stray character made a resource unreachable while the admin screen still
# showed it as filed. A foreign key makes the relationship real. Algorithm
# downloads stay unfiled: they run across parts and have no chip of their own.
class TieIngenicDownloadsToProducts < ActiveRecord::Migration[7.2]
  def up
    add_reference :ingenic_downloads,
                  :product,
                  null: true,
                  foreign_key: {
                    to_table: :ingenic_products,
                  }

    backfill_product_links

    add_index :ingenic_downloads,
              %i[product_id category_id version],
              name: "idx_ingenic_downloads_product_lookup"

    add_check_constraint :ingenic_downloads,
                         "family <> 'chip' OR product_id IS NOT NULL",
                         name: "ingenic_downloads_chip_needs_product"
    add_check_constraint :ingenic_downloads,
                         "family <> 'algorithm' OR product_id IS NULL",
                         name: "ingenic_downloads_algorithm_has_no_product"
  end

  def down
    remove_check_constraint :ingenic_downloads, name: "ingenic_downloads_algorithm_has_no_product"
    remove_check_constraint :ingenic_downloads, name: "ingenic_downloads_chip_needs_product"

    remove_index :ingenic_downloads, name: "idx_ingenic_downloads_product_lookup"
    remove_reference :ingenic_downloads, :product, foreign_key: { to_table: :ingenic_products }
  end

  private

  def backfill_product_links
    downloads =
      select_all(<<~SQL).to_a
        SELECT id, locale, family, product_slug
        FROM ingenic_downloads
        WHERE product_id IS NULL AND family = 'chip'
        ORDER BY id
      SQL

    downloads.each do |download|
      locale = download["locale"].presence || "en"
      slug = download["product_slug"].to_s.strip
      product_id = matching_chip_id(locale, slug) || create_chip(locale, slug)

      execute <<~SQL
        UPDATE ingenic_downloads
        SET product_id = #{quote(product_id)}
        WHERE id = #{quote(download["id"])}
      SQL
    end
  end

  def matching_chip_id(locale, slug)
    return if slug.blank?

    row =
      select_one(<<~SQL)
        SELECT id
        FROM ingenic_products
        WHERE kind = 'chip'
          AND locale = #{quote(locale)}
          AND (slug = #{quote(slug)} OR lower(name) = lower(#{quote(slug)}))
        ORDER BY (slug = #{quote(slug)}) DESC, id
        LIMIT 1
      SQL

    row && row["id"]
  end

  def create_chip(locale, slug)
    series_id = uncategorized_series_id(locale)
    name = slug.presence || uncategorized_name(locale)
    product_slug = unique_slug(locale, slug.to_s.parameterize.presence || "uncategorized")

    row =
      select_one(<<~SQL)
        INSERT INTO ingenic_products
          (slug, name, locale, kind, parent_id, published, position, created_at, updated_at)
        VALUES
          (#{quote(product_slug)}, #{quote(name)}, #{quote(locale)}, 'chip', #{quote(series_id)},
           true, #{next_position(locale)}, NOW(), NOW())
        RETURNING id
      SQL

    row["id"]
  end

  def uncategorized_series_id(locale)
    row =
      select_one(<<~SQL)
        SELECT id
        FROM ingenic_products
        WHERE kind = 'series' AND locale = #{quote(locale)} AND slug = 'uncategorized'
        LIMIT 1
      SQL
    return row["id"] if row

    row =
      select_one(<<~SQL)
        INSERT INTO ingenic_products
          (slug, name, locale, kind, parent_id, published, position, created_at, updated_at)
        VALUES
          (#{quote(unique_slug(locale, "uncategorized"))}, #{quote(uncategorized_name(locale))},
           #{quote(locale)}, 'series', NULL, true, #{next_position(locale)}, NOW(), NOW())
        RETURNING id
      SQL
    row["id"]
  end

  def uncategorized_name(locale)
    locale.to_s.start_with?("zh") ? "未分类" : "Uncategorized"
  end

  def unique_slug(locale, base)
    candidate = base
    suffix = 2

    while select_one(<<~SQL).present?
      SELECT 1 FROM ingenic_products
      WHERE locale = #{quote(locale)} AND slug = #{quote(candidate)}
      LIMIT 1
    SQL
      candidate = "#{base}-#{suffix}"
      suffix += 1
    end

    candidate
  end

  def next_position(locale)
    row =
      select_one(<<~SQL)
        SELECT COALESCE(MAX(position), -1) + 1 AS position
        FROM ingenic_products
        WHERE locale = #{quote(locale)}
      SQL
    row["position"]
  end
end
