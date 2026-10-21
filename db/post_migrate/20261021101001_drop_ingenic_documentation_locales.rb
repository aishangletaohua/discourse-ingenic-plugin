# frozen_string_literal: true

# The second half of removing the language from versions and pages: the rows
# were aligned and the narrower unique keys added by the regular migration.
# This one removes the columns and the keys that scoped them by language.
class DropIngenicDocumentationLocales < ActiveRecord::Migration[7.2]
  def up
    remove_index :ingenic_doc_versions, name: "index_ingenic_doc_versions_on_product_id_and_slug_and_locale"
    remove_index :ingenic_doc_pages, name: "index_ingenic_doc_pages_on_version_id_and_slug_and_locale"

    remove_column :ingenic_doc_versions, :locale
    remove_column :ingenic_doc_pages, :locale
  end

  def down
    add_column :ingenic_doc_versions, :locale, :string, null: false, default: "en"
    add_column :ingenic_doc_pages, :locale, :string, null: false, default: "en"

    execute <<~SQL
      UPDATE ingenic_doc_versions v
      SET locale = p.locale
      FROM ingenic_products p
      WHERE p.id = v.product_id
    SQL

    execute <<~SQL
      UPDATE ingenic_doc_pages pg
      SET locale = v.locale
      FROM ingenic_doc_versions v
      WHERE v.id = pg.version_id
    SQL

    add_index :ingenic_doc_versions,
              %i[product_id slug locale],
              unique: true,
              name: "index_ingenic_doc_versions_on_product_id_and_slug_and_locale"
    add_index :ingenic_doc_pages,
              %i[version_id slug locale],
              unique: true,
              name: "index_ingenic_doc_pages_on_version_id_and_slug_and_locale"
  end
end
