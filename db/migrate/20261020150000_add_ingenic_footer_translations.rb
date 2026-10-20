# frozen_string_literal: true

# The footer follows the forum's language. English keeps the existing columns
# and Chinese sits beside them, rather than the other way round, because these
# tables were created with the English site and every row already has its
# English text in place. A blank Chinese value falls back to the English one, so
# an editor who has not translated a link yet still gets a footer that reads.
class AddIngenicFooterTranslations < ActiveRecord::Migration[7.2]
  def change
    add_column :ingenic_footer_columns, :title_zh, :string
    add_column :ingenic_footer_links, :label_zh, :string

    # The partner strip's icons are drawn without their labels, but the name is
    # still what a screen reader reads and what the QR panel prints under the
    # code, so both need a Chinese spelling.
    add_column :ingenic_social_links, :label_zh, :string
    add_column :ingenic_social_links, :qr_caption_zh, :string
  end
end
