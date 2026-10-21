# frozen_string_literal: true

# The board's product link is required and unique by product and slug (the
# regular migration added that), so the copied language and the typed chip name
# are gone. Both duplicated what the linked product already owns.
class DropIngenicBoardColumns < ActiveRecord::Migration[7.2]
  def up
    remove_index :ingenic_boards, name: "index_ingenic_boards_on_slug_and_locale"
    remove_column :ingenic_boards, :locale
    remove_column :ingenic_boards, :chip
  end

  def down
    add_column :ingenic_boards, :locale, :string, null: false, default: "en"
    add_column :ingenic_boards, :chip, :string

    execute <<~SQL
      UPDATE ingenic_boards b
      SET locale = p.locale,
          chip = p.name
      FROM ingenic_products p
      WHERE p.id = b.product_id
    SQL

    add_index :ingenic_boards, %i[slug locale], unique: true
  end
end
