# frozen_string_literal: true

# The `_zh` columns were a second way to say "this row has a Chinese version".
# The rows themselves now do, and the regular migration copied every value
# across. Removing the columns leaves one rule instead of two.
class DropIngenicSiteContentTranslations < ActiveRecord::Migration[7.2]
  OLD_INDEXES = {
    ingenic_header_links: "idx_ingenic_header_links_order",
    ingenic_section_cards: "idx_ingenic_section_cards_order",
    ingenic_footer_columns: "idx_ingenic_footer_columns_order",
    ingenic_social_links: "idx_ingenic_social_links_order",
    ingenic_promotions: "idx_ingenic_promotions_order",
  }.freeze

  def up
    remove_column :ingenic_footer_columns, :title_zh
    remove_column :ingenic_footer_links, :label_zh
    remove_column :ingenic_social_links, :label_zh
    remove_column :ingenic_social_links, :qr_caption_zh

    OLD_INDEXES.each { |table, name| remove_index table, name: name }
  end

  def down
    add_column :ingenic_footer_columns, :title_zh, :string
    add_column :ingenic_footer_links, :label_zh, :string
    add_column :ingenic_social_links, :label_zh, :string
    add_column :ingenic_social_links, :qr_caption_zh, :string

    OLD_INDEXES.each do |table, name|
      add_index table, %i[published position], name: name
    end
  end
end
