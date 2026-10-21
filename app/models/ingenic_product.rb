# frozen_string_literal: true

class IngenicProduct < ActiveRecord::Base
  self.table_name = "ingenic_products"

  SERIES = "series"
  CHIP = "chip"
  KINDS = [SERIES, CHIP].freeze

  belongs_to :parent,
             class_name: "IngenicProduct",
             foreign_key: :parent_id,
             optional: true

  has_many :children,
           -> { order(position: :asc, name: :asc) },
           class_name: "IngenicProduct",
           foreign_key: :parent_id,
           dependent: :restrict_with_error

  has_many :versions,
           -> { order(position: :asc, released_on: :desc) },
           class_name: "IngenicDocVersion",
           foreign_key: :product_id,
           dependent: :destroy

  # Boards and downloads are filed against a chip in the catalogue, but they are
  # not owned by it: deleting a chip must not take the files or the boards that
  # mention it away. Restricting the delete makes the administrator move or
  # retire those rows first.
  has_many :boards,
           class_name: "IngenicBoard",
           foreign_key: :product_id,
           dependent: :restrict_with_error

  has_many :downloads,
           class_name: "IngenicDownload",
           foreign_key: :product_id,
           dependent: :restrict_with_error

  validates :slug, presence: true, uniqueness: { scope: :locale }
  validates :name, presence: true
  validates :locale, presence: true
  validates :kind, inclusion: { in: KINDS }
  validate :parent_cannot_be_self_or_descendant
  validate :shape_matches_kind
  validate :parent_locale_matches

  scope :published, -> { where(published: true) }
  scope :ordered, -> { order(position: :asc, name: :asc) }
  scope :series, -> { where(kind: SERIES) }
  scope :chips, -> { where(kind: CHIP) }

  def series?
    kind == SERIES
  end

  def chip?
    kind == CHIP
  end

  # The version a reader lands on when the URL names none. A version has no
  # `published` column — what is published is decided page by page — so this used
  # to raise `NoMethodError` for every chip whose version list it was asked
  # about, which is every visit to /ingenic/docs.
  #
  # The flagged one wins; failing that, the first in display order, which is the
  # association's own ordering rather than whatever the database returns first.
  def default_version
    versions.detect(&:latest) || versions.first
  end

  private

  def parent_cannot_be_self_or_descendant
    return if parent.nil?
    return errors.add(:parent, "cannot be itself") if parent == self

    ancestor = parent
    while ancestor
      if ancestor == self
        errors.add(:parent, "cannot be a descendant")
        break
      end
      ancestor = ancestor.parent
    end
  end

  # A series is a root and a chip belongs to exactly one series. The database
  # enforces the same shape; this is here so the admin forms report it as a
  # validation error instead of a constraint violation.
  def shape_matches_kind
    if series? && parent_id.present?
      errors.add(:parent_id, "a series cannot have a parent")
    elsif chip? && parent_id.nil?
      errors.add(:parent_id, "a chip must belong to a series")
    elsif chip? && parent && !parent.series?
      errors.add(:parent_id, "a chip must belong to a series, not another chip")
    end
  end

  # A chip's series is the same language's series. Linking across languages
  # used to be possible and made the tree show a Chinese series above an
  # English chip, which is the shape the language-first editor exists to
  # prevent.
  def parent_locale_matches
    return if parent.nil? || locale.blank? || parent.locale == locale

    errors.add(:parent, "must be in the same language")
  end
end
