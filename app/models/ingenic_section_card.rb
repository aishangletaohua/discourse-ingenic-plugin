# frozen_string_literal: true

# One card under "Popular sections" on the front page.
#
# Two shapes. A card naming a category borrows that category's address, colour,
# icon, description and topic count — the front page then says what the section
# page says. A card without one carries its own label and href, which is how
# something that is not a category (the documentation reader, a downloads page)
# stands beside the forum's sections.
class IngenicSectionCard < ActiveRecord::Base
  self.table_name = "ingenic_section_cards"

  validates :locale, presence: true
  validates :category, format: { with: /\A[a-z0-9-]+\z/ }, allow_blank: true
  validate :has_somewhere_to_go
  validate :has_a_name

  scope :published, -> { where(published: true) }
  scope :ordered, -> { order(position: :asc, id: :asc) }

  def category?
    category.present?
  end

  private

  def has_somewhere_to_go
    return if category? || href.present?

    errors.add(:href, :blank)
  end

  # A category card takes its name from the category; anything else has only
  # the name on the row, and a nameless card is an unlabelled link.
  def has_a_name
    return if category? || label.present?

    errors.add(:label, :blank)
  end
end
