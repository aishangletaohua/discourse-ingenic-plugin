# frozen_string_literal: true

# The product catalogue is not owned by the documentation.
#
# Documentation, boards and downloads all file their rows against the same
# series and chip list, and a product may have any combination of the three —
# or none. The table was named for the first feature that used it, which made
# every later reference read as if the catalogue belonged to the docs. Renaming
# it now, while the schema around it is being repaired, leaves one name that
# says what the table is.
class RenameIngenicDocProductsToProducts < ActiveRecord::Migration[7.2]
  def up
    rename_table :ingenic_doc_products, :ingenic_products

    # PostgreSQL keeps index and constraint names on rename, and Rails derives
    # future names from the table. Leaving the old names in place would make
    # the schema dump disagree with itself after the next change.
    rename_index_if_present :ingenic_products, "ingenic_doc_products_pkey", "ingenic_products_pkey"
    rename_index_if_present :ingenic_products,
                            "idx_ingenic_doc_products_kind",
                            "idx_ingenic_products_kind"
    rename_index_if_present :ingenic_products,
                            "index_ingenic_doc_products_on_parent_id",
                            "index_ingenic_products_on_parent_id"
    rename_index_if_present :ingenic_products,
                            "index_ingenic_doc_products_on_slug_and_locale",
                            "index_ingenic_products_on_slug_and_locale"

    execute <<~SQL
      ALTER TABLE ingenic_products
      RENAME CONSTRAINT ingenic_doc_products_kind_shape TO ingenic_products_kind_shape
    SQL
  end

  def down
    execute <<~SQL
      ALTER TABLE ingenic_products
      RENAME CONSTRAINT ingenic_products_kind_shape TO ingenic_doc_products_kind_shape
    SQL

    rename_index_if_present :ingenic_products,
                            "index_ingenic_products_on_slug_and_locale",
                            "index_ingenic_doc_products_on_slug_and_locale"
    rename_index_if_present :ingenic_products,
                            "index_ingenic_products_on_parent_id",
                            "index_ingenic_doc_products_on_parent_id"
    rename_index_if_present :ingenic_products, "idx_ingenic_products_kind", "idx_ingenic_doc_products_kind"
    rename_index_if_present :ingenic_products, "ingenic_products_pkey", "ingenic_doc_products_pkey"

    rename_table :ingenic_products, :ingenic_doc_products
  end

  private

  def rename_index_if_present(table, from, to)
    return unless index_name_exists?(table, from)

    rename_index table, from, to
  end
end
