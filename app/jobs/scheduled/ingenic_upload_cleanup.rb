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
        #
        # File-manager sessions are destroyed as soon as their upload is
        # finalised, so one that is still here is pending and only has a part
        # file to sweep — in the file manager's own root, not the downloads'.
        #
        # A part file's name begins with a dot, which the library's public path
        # rules refuse; `delete_staging` is the one door that reaches it.
        if session.pending?
          session.storage.delete_staging(session.token)
        else
          session.storage.delete(session.storage_path)
        end
        session.destroy!
      end
    end
  end
end
