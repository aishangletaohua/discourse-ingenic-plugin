# frozen_string_literal: true

class IngenicPermission < ActiveRecord::Base
  self.table_name = "ingenic_permissions"

  # One principal: a member or a group, exactly one of the two, which is what
  # the check constraint in the migration enforces. Both are optional here so a
  # row can name either, and both keys cascade — a permission granted to an
  # account or a group that no longer exists has nothing left to permit, and the
  # constraint means it cannot be kept with its principal blanked either.
  belongs_to :user, optional: true
  belongs_to :group, optional: true

  # What can be managed by somebody other than an administrator. A download is
  # on the list because a resource is edited by whoever looks after that
  # product's material, and the screens around it were written on that
  # assumption: the listing filters by what the reader may manage, and the
  # downloads page sends a scoped manager a flag saying the access log is not
  # theirs to read. Left off the list, that filter had nothing it could ever
  # match — every manager saw an empty page, and the flag distinguished a case
  # that could not arise.
  RESOURCE_TYPES = %w[IngenicProduct IngenicDocPage IngenicBoard IngenicDownload].freeze
  PERMISSIONS = %w[manage].freeze

  # What a grant is over. A product — a series or a chip — can carry all three,
  # which is what lets the same chip have a documentation owner, a downloads
  # owner and a boards owner who are different people. Every other kind of
  # record belongs to exactly one area.
  DOCUMENTATION = "documentation"
  DOWNLOADS = "downloads"
  BOARDS = "boards"
  AREAS = [DOCUMENTATION, DOWNLOADS, BOARDS].freeze

  AREA_FOR_RESOURCE_TYPE = {
    "IngenicProduct" => DOCUMENTATION,
    "IngenicDocPage" => DOCUMENTATION,
    "IngenicBoard" => BOARDS,
    "IngenicDownload" => DOWNLOADS,
  }.freeze

  before_validation :take_default_area

  validates :area, inclusion: { in: AREAS }
  validates :resource_type, inclusion: { in: RESOURCE_TYPES }
  validates :permission, inclusion: { in: PERMISSIONS }
  validates :user, presence: true, unless: :group
  validates :group, presence: true, unless: :user
  validates :resource_id, presence: true
  validate :resource_must_exist
  validate :area_matches_resource

  scope :in_area, ->(area) { where(area: area) }

  def resource
    resource_type.constantize.find_by(id: resource_id) if RESOURCE_TYPES.include?(resource_type)
  end

  private

  # Callers that predate the column, and a console grant typed without one,
  # keep the meaning the old interface had rather than becoming invalid.
  def take_default_area
    self.area = AREA_FOR_RESOURCE_TYPE[resource_type] if area.blank?
  end

  def resource_must_exist
    return if resource_type.blank? || resource_id.blank?
    return errors.add(:resource_type, :inclusion) unless RESOURCE_TYPES.include?(resource_type)

    errors.add(:resource_id, :invalid) if resource.nil?
  end

  def area_matches_resource
    return if area.blank? || resource_type.blank?
    # A product node is the one thing worth granting that is shared by all
    # three jobs; everything else names the area it belongs to.
    return if resource_type == "IngenicProduct"

    errors.add(:area, :invalid) unless AREA_FOR_RESOURCE_TYPE[resource_type] == area
  end
end
