# frozen_string_literal: true

module Jobs
  # Removes the part files of uploads nobody finished.
  #
  # A chunked upload lives in the database between requests, which is what
  # makes it resumable — and also what makes it forgettable. A tab closed
  # halfway through a three-gigabyte firmware image leaves a row and a part
  # file behind, and neither will ever be named again. A day is long enough
  # for an interrupted transfer to be resumed after lunch, and short enough
  # that abandoned files do not accumulate on the disk.
  class IngenicUploadCleanup < ::Jobs::Scheduled
    every 1.hour

    def execute(_args)
      return unless SiteSetting.ingenic_enabled

      IngenicUploadSession.stale(24.hours.ago).find_each do |session|
        # A completed session's file has already been moved beside the
        # library's files, so the staging path no longer exists; deleting the
        # wrong one is how a finished upload would disappear.
        ::Ingenic::DownloadStorage.delete(
          session.pending? ? session.staging_relative : session.storage_path,
        )
        session.destroy!
      end
    end
  end
end
