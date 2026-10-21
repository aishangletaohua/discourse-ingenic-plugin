# frozen_string_literal: true

# A version and a page are not separately translated things.
#
# A product is one language's row in the catalogue: the English T33 and the
# Chinese T33 are two products. Its versions and pages therefore belong to the
# product's language already, and carrying a second copy of that value let the
# two disagree. When they did, the admin screen listed a Chinese version under
# an English chip and the reader's tree was assembled from both languages.
#
# This half merges the rows that disagree and adds the narrower unique keys.
# The columns themselves are dropped in a post-deploy migration, which is what
# Discourse requires for a column removal.
class PrepareIngenicDocumentationLocales < ActiveRecord::Migration[7.2]
  def up
    merge_versions_filed_under_another_language
    merge_pages_filed_under_another_language

    add_index :ingenic_doc_versions, %i[product_id slug], unique: true
    add_index :ingenic_doc_pages, %i[version_id slug], unique: true
  end

  def down
    remove_index :ingenic_doc_versions, %i[product_id slug]
    remove_index :ingenic_doc_pages, %i[version_id slug]
  end

  private

  # A version filed under a language other than its product's is either a
  # duplicate of a version that already exists in the right language, or the
  # only copy and safely relabelled. Merging first keeps the unique index from
  # refusing the relabel.
  def merge_versions_filed_under_another_language
    rows =
      select_all(<<~SQL).to_a
        SELECT v.id, v.product_id, v.slug, p.locale AS product_locale
        FROM ingenic_doc_versions v
        JOIN ingenic_products p ON p.id = v.product_id
        WHERE v.locale IS DISTINCT FROM p.locale
        ORDER BY v.product_id, v.slug, v.id
      SQL

    rows.each do |row|
      sibling =
        select_one(<<~SQL)
          SELECT id
          FROM ingenic_doc_versions
          WHERE product_id = #{quote(row["product_id"])}
            AND slug = #{quote(row["slug"])}
            AND locale = #{quote(row["product_locale"])}
          LIMIT 1
        SQL

      if sibling
        merge_version_into(row["id"], sibling["id"])
      else
        execute <<~SQL
          UPDATE ingenic_doc_versions
          SET locale = #{quote(row["product_locale"])}
          WHERE id = #{quote(row["id"])}
        SQL
      end
    end
  end

  def merge_version_into(loser_id, keeper_id)
    # Children in the kept version that hang off a page only the losing
    # version has are re-attached to the kept version's page of the same slug
    # before that row is removed.
    execute <<~SQL
      UPDATE ingenic_doc_pages child
      SET parent_id = keeper.id
      FROM ingenic_doc_pages lost
      JOIN ingenic_doc_pages keeper
        ON keeper.version_id = #{quote(keeper_id)}
       AND keeper.slug = lost.slug
      WHERE child.parent_id = lost.id
        AND lost.version_id = #{quote(loser_id)}
    SQL

    # A slug the kept version already defines belongs to that row; the losing
    # copy is the duplicate the merge exists to remove.
    execute <<~SQL
      DELETE FROM ingenic_doc_pages page
      WHERE page.version_id = #{quote(loser_id)}
        AND EXISTS (
          SELECT 1
          FROM ingenic_doc_pages kept
          WHERE kept.version_id = #{quote(keeper_id)}
            AND kept.slug = page.slug
        )
    SQL

    execute <<~SQL
      UPDATE ingenic_doc_pages
      SET version_id = #{quote(keeper_id)}
      WHERE version_id = #{quote(loser_id)}
    SQL

    execute <<~SQL
      DELETE FROM ingenic_doc_versions
      WHERE id = #{quote(loser_id)}
    SQL
  end

  # After the versions are aligned, a page can still repeat a slug its version
  # owns in another language. Keep the row written in the product's language,
  # otherwise the oldest one, and re-attach its children to the survivor.
  def merge_pages_filed_under_another_language
    rows =
      select_all(<<~SQL).to_a
        SELECT pg.id, pg.version_id, pg.slug, pg.locale, p.locale AS product_locale
        FROM ingenic_doc_pages pg
        JOIN ingenic_doc_versions v ON v.id = pg.version_id
        JOIN ingenic_products p ON p.id = v.product_id
        ORDER BY pg.version_id, pg.slug, pg.id
      SQL

    rows.group_by { |row| [row["version_id"], row["slug"]] }.each_value do |group|
      next if group.size < 2

      keeper =
        group.min_by do |row|
          [row["locale"] == row["product_locale"] ? 0 : 1, row["id"]]
        end

      group.each do |row|
        next if row["id"] == keeper["id"]

        execute <<~SQL
          UPDATE ingenic_doc_pages
          SET parent_id = #{quote(keeper["id"])}
          WHERE parent_id = #{quote(row["id"])}
        SQL

        execute <<~SQL
          DELETE FROM ingenic_doc_pages
          WHERE id = #{quote(row["id"])}
        SQL
      end
    end

    execute <<~SQL
      UPDATE ingenic_doc_pages pg
      SET locale = p.locale
      FROM ingenic_doc_versions v
      JOIN ingenic_products p ON p.id = v.product_id
      WHERE pg.version_id = v.id
        AND pg.locale IS DISTINCT FROM p.locale
    SQL
  end
end
