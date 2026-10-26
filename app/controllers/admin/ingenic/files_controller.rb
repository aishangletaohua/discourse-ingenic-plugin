# frozen_string_literal: true

module Admin
  module Ingenic
    # The official-file library.
    #
    # One screen, one permission: whoever holds the `files` feature works in
    # every folder, and nobody else sees the addresses at all. The storage layer
    # (`Ingenic::FileStorage`) does the path checking; this controller decides
    # who may ask and turns refusals into the messages the screen shows.
    #
    # Uploads reuse the download centre's chunked session, marked with
    # `purpose: files`, so a three-gigabyte archive travels the same way it
    # always did and is staged inside the library root it will end up in.
    class FilesController < BaseController
      MAX_CHUNK_SIZE = 8.megabytes
      MAX_UPLOAD_SIZE = 8.gigabytes

      before_action :authorize_files!

      # Every refusal the storage layer can name is something the operator did
      # — a name that is already taken, a folder that is not empty — so it
      # belongs to the screen as a message rather than to the log as a 500.
      rescue_from ::Ingenic::FileStorage::Error do |error|
        status = error.code == :not_found ? 404 : 422
        render json: { errors: [message_for(error.code)] }, status: status
      end

      def index
        ::Ingenic::FileStorage.ensure_root!
        listing = ::Ingenic::FileStorage.list(params[:path])

        render_json_dump(
          path: listing[:path],
          breadcrumbs: ::Ingenic::FileStorage.breadcrumbs(listing[:path]),
          entries: listing[:entries],
          truncated: listing[:truncated],
          writable: ::Ingenic::FileStorage.writable?,
          extensions: ::Ingenic::FileStorage.extensions,
        )
      end

      def create_folder
        parent = ::Ingenic::FileStorage.normalize_relative(params[:path])
        name = ::Ingenic::FileStorage.clean_name(params[:name])
        ::Ingenic::FileStorage.create_folder(parent, name)

        folder = [parent, name].reject(&:blank?).join("/")
        render_json_dump(folder: { name: name, path: folder })
      end

      def rename
        relative = ::Ingenic::FileStorage.rename(params[:path], params[:name])

        render_json_dump(
          entry:
            entry_json(relative, ::Ingenic::FileStorage.existing_path(relative)),
        )
      end

      def move
        relative = ::Ingenic::FileStorage.move(params[:path], params[:directory])

        render_json_dump(
          entry:
            entry_json(relative, ::Ingenic::FileStorage.existing_path(relative)),
        )
      end

      def destroy
        ::Ingenic::FileStorage.delete(params[:path])
        head :no_content
      end

      # An upload session is opened with the folder it is for, so a transfer
      # that is still running cannot be landed somewhere else at the end.
      def create_upload
        return render_upload_error(:upload_invalid) if params[:size].to_i <= 0
        return render_upload_error(:upload_too_large) if params[:size].to_i > MAX_UPLOAD_SIZE

        directory = ::Ingenic::FileStorage.normalize_relative(params[:directory])
        name = ::Ingenic::FileStorage.clean_name(params[:filename])
        ::Ingenic::FileStorage.existing_path(directory)
        raise ::Ingenic::FileStorage::Error.new(:extension) unless ::Ingenic::FileStorage.allowed_extension?(name)
        raise ::Ingenic::FileStorage::Error.new(:storage_unavailable) unless ::Ingenic::FileStorage.writable?

        token = SecureRandom.urlsafe_base64(24)
        session =
          IngenicUploadSession.create!(
            token_digest: IngenicUploadSession.token_digest(token),
            user_id: current_user.id,
            original_filename: name,
            expected_size: params[:size].to_i,
            received_size: 0,
            purpose: IngenicUploadSession::PURPOSE_FILES,
          )

        ::Ingenic::FileStorage.append(session.staging_relative, "")

        # Returned once; the row keeps only the digest.
        render_json_dump(upload: upload_session_json(session, token: token))
      end

      def show_upload
        session = owned_upload_session
        return render_upload_error(:upload_missing) unless session

        render_json_dump(upload: upload_session_json(session, token: params[:token]))
      end

      def append_upload_chunk
        session = owned_upload_session
        return render_upload_error(:upload_missing) unless session&.pending?

        # Read only after the size is known: the body is buffered whole, and a
        # request that announces far more than one piece would otherwise take
        # that many bytes of memory before the check below could refuse it.
        if request.content_length.to_i > MAX_CHUNK_SIZE
          return(
            render json: { errors: [I18n.t("ingenic.errors.upload_chunk_too_large")] },
                   status: 413
          )
        end

        bytes = request.body.read.to_s
        offset = params[:offset].to_i

        return render_upload_error(:upload_invalid) if bytes.empty?

        if bytes.bytesize > MAX_CHUNK_SIZE
          return(
            render json: { errors: [I18n.t("ingenic.errors.upload_chunk_too_large")] },
                   status: 413
          )
        end

        session.with_lock do
          actual =
            ::Ingenic::FileStorage.align(session.staging_relative, session.received_size)

          if actual < session.received_size
            session.update!(received_size: actual)
            return render_offset_error(actual)
          end

          return render_offset_error(session.received_size) if offset != session.received_size

          if session.received_size + bytes.bytesize > session.expected_size
            return render_upload_error(:upload_too_large)
          end

          written = ::Ingenic::FileStorage.append(session.staging_relative, bytes)
          session.update!(received_size: written)
        end

        render_json_dump(upload: upload_session_json(session, token: params[:token]))
      end

      def complete_upload
        session = owned_upload_session
        return render_upload_error(:upload_missing) unless session

        session.with_lock do
          # A retry after a response the browser never received arrives once
          # the first request has finished. The row remembers where the file
          # landed, so answering the same file beats reporting a missing
          # upload for bytes that are already in the library.
          unless session.pending?
            if file_landed?(session)
              return render_completed_file(session)
            end

            session.destroy!
            return render_upload_error(:upload_missing)
          end

          unless session.received_size == session.expected_size
            return(
              render json: {
                       errors: [I18n.t("ingenic.errors.upload_incomplete")],
                       received_size: session.received_size,
                     },
                     status: 422
            )
          end

          directory = ::Ingenic::FileStorage.normalize_relative(params[:directory])
          filename = params[:filename].presence || session.original_filename

          stored = ::Ingenic::FileStorage.finalize(session.staging_relative, directory, filename)

          if params[:sha256].present? && params[:sha256].to_s.downcase != stored[:sha256]
            ::Ingenic::FileStorage.delete(stored[:relative])
            session.destroy!
            return render_upload_error(:upload_checksum)
          end

          # The bytes are a library file now. The row stays long enough for a
          # browser that never saw this answer to ask again; the cleanup pass
          # drops it without touching the file, which is no longer staging.
          session.update!(
            status: "completed",
            sha256: stored[:sha256],
            storage_path: stored[:relative],
          )
        end

        render_completed_file(session)
      end

      def destroy_upload
        session = owned_upload_session
        return render_upload_error(:upload_missing) unless session

        ::Ingenic::FileStorage.delete_staging(session.token_digest)
        session.destroy!

        head :no_content
      end

      private

      def authorize_files!
        authorize_ingenic_feature!("files")
      end

      def owned_upload_session
        IngenicUploadSession
          .for_files
          .find_by_token(params[:token].to_s, user_id: current_user.id)
      end

      def upload_session_json(session, token: nil)
        {
          token: token,
          filename: session.original_filename,
          size: session.expected_size,
          received_size: session.received_size,
          status: session.status,
        }
      end

      # A finished library upload whose file is still there. A session that
      # says it completed but whose file an operator has since renamed or
      # deleted is only a stale row.
      def file_landed?(session)
        session.storage_path.present? && ::Ingenic::FileStorage.exist?(session.storage_path)
      end

      def render_completed_file(session)
        render_json_dump(
          file:
            entry_json(
              session.storage_path,
              ::Ingenic::FileStorage.existing_path(session.storage_path),
            ).merge(sha256: session.sha256),
        )
      end

      def entry_json(relative, path)
        stat = File.stat(path)
        parent = relative.split("/")[0...-1].join("/")
        ::Ingenic::FileStorage.entry_for(Pathname.new(path), stat, parent)
      end

      def render_offset_error(received_size)
        render json: {
                 errors: [I18n.t("ingenic.errors.upload_offset")],
                 received_size: received_size,
               },
               status: 409
      end

      def render_upload_error(key)
        render json: { errors: [I18n.t("ingenic.errors.#{key}")] }, status: 422
      end

      def message_for(code)
        key = "ingenic.files.errors.#{code}"
        I18n.exists?(key) ? I18n.t(key) : I18n.t("ingenic.files.errors.unavailable")
      end
    end
  end
end
