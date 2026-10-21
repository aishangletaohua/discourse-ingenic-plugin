# frozen_string_literal: true

# A board is filed against the shared catalogue, not against a chip name typed
# onto the row.
#
# The old `chip` string let a board show a part number the catalogue had never
# heard of, and the optional product link meant the same board could render a
# chip label from one language beside a board written in another. Boards also
# carried their own `locale`, a second copy of a value the linked chip already
# owns. Both columns go: the link is required and the language follows it.
#
# Boards that predate the link are matched to a chip in their own language. A
# board whose chip is not in the catalogue yet gets one created under an
# "Uncategorized" series rather than being deleted — the catalogue is a place
# for products to live, not a documentation index, so a board can put a chip
# there before anyone writes a page about it.
class TieIngenicBoardsToProducts < ActiveRecord::Migration[7.2]
  def up
    backfill_product_links
    deduplicate_slugs

    change_column_null :ingenic_boards, :product_id, false
    add_index :ingenic_boards, %i[product_id slug], unique: true
  end

  def down
    remove_index :ingenic_boards, %i[product_id slug]
    change_column_null :ingenic_boards, :product_id, true
  end

  private

  def backfill_product_links
    boards =
      select_all(<<~SQL).to_a
        SELECT id, locale, chip
        FROM ingenic_boards
        WHERE product_id IS NULL
        ORDER BY id
      SQL

    boards.each do |board|
      locale = board["locale"].presence || "en"
      chip = board["chip"].to_s.strip
      product_id = matching_chip_id(locale, chip) || create_chip(locale, chip)

      execute <<~SQL
        UPDATE ingenic_boards
        SET product_id = #{quote(product_id)}
        WHERE id = #{quote(board["id"])}
      SQL
    end
  end

  def matching_chip_id(locale, chip)
    return if chip.blank?

    row =
      select_one(<<~SQL)
        SELECT id
        FROM ingenic_products
        WHERE kind = 'chip'
          AND locale = #{quote(locale)}
          AND (slug = #{quote(chip)} OR lower(name) = lower(#{quote(chip)}))
        ORDER BY (slug = #{quote(chip)}) DESC, id
        LIMIT 1
      SQL

    row && row["id"]
  end

  def create_chip(locale, chip)
    series_id = uncategorized_series_id(locale)
    name = chip.presence || uncategorized_name(locale)
    slug = unique_chip_slug(locale, chip)

    row =
      select_one(<<~SQL)
        INSERT INTO ingenic_products
          (slug, name, locale, kind, parent_id, published, position, created_at, updated_at)
        VALUES
          (#{quote(slug)}, #{quote(name)}, #{quote(locale)}, 'chip', #{quote(series_id)},
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
          (#{quote(unique_series_slug(locale))}, #{quote(uncategorized_name(locale))},
           #{quote(locale)}, 'series', NULL, true, #{next_position(locale)}, NOW(), NOW())
        RETURNING id
      SQL
    row["id"]
  end

  def uncategorized_name(locale)
    locale.to_s.start_with?("zh") ? "未分类" : "Uncategorized"
  end

  def unique_chip_slug(locale, chip)
    unique_slug(locale, chip.to_s.parameterize.presence || "uncategorized")
  end

  def unique_series_slug(locale)
    unique_slug(locale, "uncategorized")
  end

  def unique_slug(locale, base)
    candidate = base
    suffix = 2

    while product_slug_taken?(locale, candidate)
      candidate = "#{base}-#{suffix}"
      suffix += 1
    end

    candidate
  end

  def product_slug_taken?(locale, slug)
    select_one(<<~SQL).present?
      SELECT 1 FROM ingenic_products
      WHERE locale = #{quote(locale)} AND slug = #{quote(slug)}
      LIMIT 1
    SQL
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

  # Removing `locale` narrows the old uniqueness rule. Two rows for the same
  # product and slug would now collide, so the later one gets its id appended
  # rather than being dropped: a board is content someone entered.
  def deduplicate_slugs
    rows =
      select_all(<<~SQL).to_a
        SELECT id, product_id, slug
        FROM ingenic_boards
        WHERE product_id IS NOT NULL
        ORDER BY product_id, slug, id
      SQL

    rows.group_by { |row| [row["product_id"], row["slug"]] }.each_value do |group|
      group.drop(1).each do |row|
        execute <<~SQL
          UPDATE ingenic_boards
          SET slug = #{quote("#{row["slug"]}-#{row["id"]}")}
          WHERE id = #{quote(row["id"])}
        SQL
      end
    end
  end
end
