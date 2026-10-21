# frozen_string_literal: true

# One entry inside a footer column.
class IngenicFooterLink < ActiveRecord::Base
  self.table_name = "ingenic_footer_links"

  belongs_to :column, class_name: "IngenicFooterColumn"

  # A link is written in the language of the column it sits in; asking the
  # column is the single answer.
  delegate :locale, to: :column, allow_nil: true

  validates :label, presence: true
  validates :href, presence: true

  scope :published, -> { where(published: true) }
  scope :ordered, -> { order(position: :asc, id: :asc) }

  # Whether the link leaves the forum. Stored rather than inferred from the URL,
  # because an admin may want a same-site link opened in a new tab.
  def external?
    external
  end
end
