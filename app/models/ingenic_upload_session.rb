# frozen_string_literal: true

# One file being sent to the download library in pieces.
#
# A session is the server's memory of an upload in progress: who started it,
# what the browser says the file is called and how large it will be, and how
# many bytes have actually arrived. `received_size` is the offset the next
# chunk must start at, which is also what lets a browser resume a transfer
# after its connection drops.
class IngenicUploadSession < ActiveRecord::Base
  self.table_name = "ingenic_upload_sessions"

  STATUSES = %w[pending completed].freeze

  # Which library the finished file belongs to. The part file is staged inside
  # that library's root, so the two cannot be mixed after the fact.
  PURPOSE_DOWNLOADS = "downloads"
  PURPOSE_FILES = "files"
  PURPOSES = [PURPOSE_DOWNLOADS, PURPOSE_FILES].freeze

  belongs_to :user, optional: true

  # The browser holds the token; this table holds only its digest. Finding a
  # session from the token the browser sends is therefore a lookup by digest,
  # and the part file is named from the digest too, so nothing on disk or in
  # the database can be turned back into the handle the endpoints accept.
  def self.token_digest(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  def self.find_by_token(token, user_id: nil)
    return nil if token.blank?

    scope = user_id.nil? ? all : where(user_id: user_id)
    scope.find_by(token_digest: token_digest(token))
  end

  validates :token_digest, presence: true, uniqueness: true
  validates :user_id, presence: true
  validates :original_filename, presence: true
  validates :expected_size, numericality: { only_integer: true, greater_than: 0 }
  validates :received_size, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :status, inclusion: { in: STATUSES }
  validates :purpose, inclusion: { in: PURPOSES }

  scope :stale, ->(before) { where(created_at: ...before) }
  scope :for_downloads, -> { where(purpose: PURPOSE_DOWNLOADS) }
  scope :for_files, -> { where(purpose: PURPOSE_FILES) }

  def pending?
    status == "pending"
  end

  def completed?
    status == "completed"
  end

  def files?
    purpose == PURPOSE_FILES
  end

  def storage
    files? ? ::Ingenic::FileStorage : ::Ingenic::DownloadStorage
  end

  def staging_relative
    storage.staging_relative(token_digest)
  end
end
