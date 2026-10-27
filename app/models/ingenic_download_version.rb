# frozen_string_literal: true

# One file under a download resource.
#
# The card is the resource: its name, chip, category and access rule. The
# version is the thing that is actually downloaded, and it is the version that
# carries the description the card shows once it is selected, so SDK 1.0 and
# SDK 1.1 can say different things about themselves under one set of access
# rules.
#
# Requests, grants, points and the delivery log stay keyed to the resource.
# A customer approved for a chip's SDK is approved for its next release too,
# which is what "one approval per resource" means in practice.
class IngenicDownloadVersion < ActiveRecord::Base
  self.table_name = "ingenic_download_versions"

  belongs_to :download, class_name: "IngenicDownload"

  validates :version, uniqueness: { scope: :download_id }, allow_blank: true
  validate :has_somewhere_to_download_from
  validate :one_checksum

  # An uploaded file carries its own digest. A checksum typed beside an old
  # external URL is the other kind, and a row cannot hold both: showing one
  # while the bytes were verified against the other is worse than showing none.
  before_validation { self.sha256 = nil if file_sha256.present? }

  scope :published, -> { where(published: true) }
  # Undated versions sort after dated ones. PostgreSQL puts NULLs first on a
  # descending sort, which would put the version nobody dated at the top of
  # every card.
  scope :ordered, -> {
    order(position: :asc).order(Arel.sql("released_on DESC NULLS LAST")).order(id: :asc)
  }

  def stored?
    storage_path.present?
  end

  def external?
    !stored? && file_url.present? && file_url !~ %r{\A/}
  end

  def checksum
    file_sha256.presence || sha256
  end

  # What the selector shows. A draft without a label is still a file, and the
  # card prints its release date rather than an empty option.
  def label
    version.presence
  end

  private

  def has_somewhere_to_download_from
    return if file_url.present? || storage_path.present?

    errors.add(:base, "a version needs either a file URL or an uploaded file")
  end

  def one_checksum
    return if file_sha256.blank? || sha256.blank?

    errors.add(:sha256, "cannot be set when the file was uploaded and hashed")
  end
end
