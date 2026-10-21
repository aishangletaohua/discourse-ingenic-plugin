# frozen_string_literal: true

# The foreign key replaced the free-text slug; the column and its index go in a
# post-deploy migration, as Discourse requires for a removal.
class DropIngenicDownloadProductSlug < ActiveRecord::Migration[7.2]
  def up
    remove_index :ingenic_downloads, name: "idx_ingenic_downloads_lookup"
    remove_column :ingenic_downloads, :product_slug
  end

  def down
    add_column :ingenic_downloads, :product_slug, :string

    execute <<~SQL
      UPDATE ingenic_downloads d
      SET product_slug = p.slug
      FROM ingenic_products p
      WHERE p.id = d.product_id
    SQL

    add_index :ingenic_downloads,
              %i[product_slug category_id version locale],
              name: "idx_ingenic_downloads_lookup"
  end
end
