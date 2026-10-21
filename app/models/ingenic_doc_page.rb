# frozen_string_literal: true

class IngenicDocPage < ActiveRecord::Base
  self.table_name = "ingenic_doc_pages"

  # A folder is a heading in the table of contents, not a page: it expands and
  # collapses, and has no body. Everything else is an article. Storing the two
  # in one table keeps the parent chain — and therefore version inheritance —
  # unchanged.
  KINDS = %w[page folder].freeze

  belongs_to :version, class_name: "IngenicDocVersion", foreign_key: :version_id
  belongs_to :parent, class_name: "IngenicDocPage", foreign_key: :parent_id, optional: true

  has_many :children,
           -> { order(position: :asc) },
           class_name: "IngenicDocPage",
           foreign_key: :parent_id,
           dependent: :destroy

  # A page is written in its version's language, which is its product's. The
  # method is kept so serializers and callers can ask without walking the
  # chain themselves; there is no second value to keep in sync.
  delegate :locale, to: :version, allow_nil: true

  validates :slug, presence: true, uniqueness: { scope: :version_id }
  validates :title, presence: true
  validates :kind, presence: true, inclusion: { in: KINDS }

  # A body under a folder is invisible to every reader, so accepting one would
  # store text that can never be seen and leave the editor wondering where it
  # went.
  before_save { self.body = nil if folder? }

  # A parent chain that loops back on itself makes every depth walk recurse
  # forever — the admin screen, the reader and the API all build the tree from
  # it. Walking up from the prospective parent is the cheap way to see the loop
  # before it is written.
  validate :parent_does_not_close_a_loop

  scope :published, -> { where(published: true) }
  scope :ordered, -> { order(position: :asc) }
  scope :folders, -> { where(kind: "folder") }

  def folder?
    kind == "folder"
  end

  def depth
    parent ? parent.depth + 1 : 0
  end

  private

  def parent_does_not_close_a_loop
    return if parent_id.blank?

    seen = Set.new
    node = parent

    while node
      if (id.present? && node.id == id) || seen.include?(node.id)
        errors.add(:parent_id, :invalid)
        return
      end

      seen << node.id
      node = node.parent
    end
  end
end
