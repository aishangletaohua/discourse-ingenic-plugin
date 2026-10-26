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
        # A part file's name begins with a dot, which the library's public path
        # rules refuse; `delete_staging` is the one door that reaches it.
        #
        # A completed download upload that no resource adopted is garbage, so
        # its file is swept with the row. A completed file-manager upload,
        # though, is not garbage: its bytes are already a library file that an
        # operator may be about to link. Only the row is stale there, and it
        # exists so a browser that missed the answer can ask again.
        if session.pending?
          session.storage.delete_staging(session.token_digest)
        elsif !session.files?
          session.storage.delete(session.storage_path)
        end
        session.destroy!
      end
    end
  end
end
