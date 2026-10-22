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

  belongs_to :user, optional: true

  validates :token, presence: true, uniqueness: true
  validates :user_id, presence: true
  validates :original_filename, presence: true
  validates :expected_size, numericality: { only_integer: true, greater_than: 0 }
  validates :received_size, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :status, inclusion: { in: STATUSES }

  scope :stale, ->(before) { where(created_at: ...before) }

  def pending?
    status == "pending"
  end

  def completed?
    status == "completed"
  end

  def staging_relative
    ::Ingenic::DownloadStorage.staging_relative(token)
  end
end
