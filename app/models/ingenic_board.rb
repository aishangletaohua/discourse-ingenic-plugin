# frozen_string_literal: true

# A development board or sample chip in the catalogue.
#
# Both are physical things the Ingenic team sells or lends, so the plugin never
# takes an order for one: the links on a card leave the forum, and everything
# here is presentation. They are one model because they are one catalogue to a
# visitor — the first filter chooses which of the two — and because everything
# except `kind` is written the same way for both.
#
# A board is filed against a chip in the shared product catalogue. That is not
# the documentation: a chip may exist here only because a board needs it, and a
# board may exist for a chip nobody has written a page about. Because the
# catalogue row owns the language, the board does not carry one.
class IngenicBoard < ActiveRecord::Base
  self.table_name = "ingenic_boards"

  # What the catalogue's first filter chooses between. A string so a third
  # kind is a row value rather than a migration; the column's default is
  # "board", which is also what every row created before this column was.
  KINDS = %w[board sample].freeze

  belongs_to :product, class_name: "IngenicProduct", foreign_key: :product_id

  delegate :locale, to: :product, allow_nil: true

  validates :slug, presence: true, uniqueness: { scope: :product_id }
  validates :name, presence: true
  validates :kind, presence: true, inclusion: { in: KINDS }
  # Neither link is required: the card always draws both buttons and grays the
  # one without an address. Being sold out is a separate decision stored in
  # `sold_out`, so a restocked board keeps the links it had.
  validate :product_is_a_chip
  validate :purchase_link_is_usable

  scope :published, -> { where(published: true) }
  scope :ordered, -> { order(position: :asc, name: :asc) }
  scope :for_kind, ->(kind) { where(kind: kind) }
  scope :for_locale, ->(locale) { joins(:product).where(ingenic_products: { locale: locale }) }

  # The chip filter reads the product tree rather than a chip name typed onto
  # the board.
  def self.for_chip(slug)
    joins(:product).where(ingenic_products: { slug: slug })
  end

  # What the card prints under the name. The catalogue wins, because a rename
  # there is meant to show up here.
  def chip_name
    product&.name
  end

  def series
    product&.parent
  end

  def series_name
    series&.name
  end

  private

  # A purchase link is only ever sent to a browser as a Location or an href, so
  # the same two shapes the download centre accepts are accepted here. A typo
  # caught on save is one the admin can still fix, rather than a dead button.
  def purchase_link_is_usable
    return if purchase_url.blank?
    return if purchase_url.start_with?("/") || purchase_url.match?(%r{\Ahttps?://}i)

    errors.add(:purchase_url, "must be a site path or an http(s) address")
  end

  # Only a chip: a board is for a specific part, and a board filed against a
  # series would appear under every chip in it.
  def product_is_a_chip
    return errors.add(:product, :blank) if product.nil?
    return errors.add(:product, "must be a chip") unless product.chip?
  end
end
