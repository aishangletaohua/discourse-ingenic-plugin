# frozen_string_literal: true

# A titled column of links in the footer.
#
# The heading and the links are separate rows because the heading has no
# destination of its own — "Developer Services" is a label, not somewhere to go,
# and a self-referencing link row would have to pretend otherwise.
class IngenicFooterColumn < ActiveRecord::Base
  self.table_name = "ingenic_footer_columns"

  # Two associations over one table: the admin screen edits every link, the
  # footer renders only the published ones. A method that filtered in Ruby would
  # load the hidden rows on every page view to throw them away.
  has_many :links,
           -> { order(position: :asc, id: :asc) },
           class_name: "IngenicFooterLink",
           foreign_key: :column_id,
           dependent: :destroy

  has_many :published_links,
           -> { where(published: true).order(position: :asc, id: :asc) },
           class_name: "IngenicFooterLink",
           foreign_key: :column_id

  validates :title, presence: true
  validates :locale, presence: true

  scope :published, -> { where(published: true) }
  scope :ordered, -> { order(position: :asc, id: :asc) }
end
