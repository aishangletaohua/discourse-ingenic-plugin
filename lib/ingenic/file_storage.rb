# frozen_string_literal: true

require "digest"
require "fileutils"

module Ingenic
  # The official-file library: SDK archives, PDFs and images that the team keeps
  # on the server and links to from posts, documentation and the download
  # centre.
  #
  # Separate from `DownloadStorage`, which exists to hold the bytes of a
  # catalogue row behind `IngenicDownload`. This one is a plain directory tree
  # an operator maintains by hand: real folders, real filenames, and a stable
  # URL for each file. Nothing here decides who may download a file — that is
  # the download centre's three tiers, applied where the link is used — but the
  # serving endpoint does require a session for everything that is not an
  # image, so an anonymous visitor cannot walk a shared SDK link.
  #
  # The root is deliberately outside `public/`. The web server never serves
  # these files directly; `IngenicFilesController` checks the path and streams
  # the bytes, which is what keeps a link a URL on this site rather than a
  # filesystem path a misconfiguration could expose.
  module FileStorage
    DEFAULT_DIRECTORY = "ingenic-files"
    CHUNK = 256.kilobytes
    STAGING_DIRECTORY = ".uploads"
    MAX_NAME_LENGTH = 120

    # Raised for every refusal a person can cause. `code` names the message the
    # screen shows, so the storage layer does not carry copy.
    class Error < StandardError
      attr_reader :code

      def initialize(code)
        @code = code
        super(code.to_s)
      end
    end

    module_function

    def root
      configured = SiteSetting.ingenic_file_manager_path.to_s.strip
      Pathname.new(configured.presence || Rails.root.join(DEFAULT_DIRECTORY).to_s)
    end

    def root_path
      root.cleanpath
    end

    def ensure_root!
      FileUtils.mkdir_p(root_path)
    end

    def writable?
      ensure_root!
      File.writable?(root_path)
    rescue StandardError
      false
    end

    # A path is a list of names joined with `/`, relative to the root. Empty is
    # the root itself. Anything that could climb out of the root, address a
    # device, or hide from the listing is refused before it reaches the disk.
    def normalize_relative(value)
      value = value.to_s
      raise Error.new(:path_invalid) if value.include?("\0") || value.include?("\\")
      raise Error.new(:path_invalid) if value.start_with?("/")

      segments = value.split("/").reject(&:blank?)
      segments.each do |segment|
        raise Error.new(:path_invalid) if segment == "." || segment == ".."
        raise Error.new(:path_invalid) if segment.start_with?(".")
      end

      segments.join("/")
    end

    def absolute_path(relative)
      normalized = normalize_relative(relative)
      candidate = (root_path + normalized).cleanpath
      prefix = "#{root_path}/"

      unless candidate.to_s == root_path.to_s || candidate.to_s.start_with?(prefix)
        raise Error.new(:path_invalid)
      end

      candidate
    end

    # The staging directory is hidden from the listing, which is why the public
    # path rules refuse a name beginning with a dot. Internal paths are built by
    # this module from a server-generated token, so they skip that rule and keep
    # only the one that matters: the result stays inside the root.
    def internal_absolute(relative)
      candidate = (root_path + relative.to_s).cleanpath
      prefix = "#{root_path}/"

      unless candidate.to_s.start_with?(prefix)
        raise Error.new(:path_invalid)
      end

      candidate
    end

    # An existing path, with symlinks resolved and checked. A symlink placed in
    # the tree by hand could otherwise point at `/etc`, and a listing or a
    # download would follow it out of the root.
    def existing_path(relative)
      path = absolute_path(relative)
      raise Error.new(:not_found) unless path.exist?

      real = File.realpath(path)
      real_root = File.realpath(root_path)

      unless real == real_root || real.start_with?("#{real_root}/")
        raise Error.new(:not_found)
      end

      path
    rescue Errno::ENOENT
      raise Error.new(:not_found)
    end

    def exist?(relative)
      existing_path(relative).file?
    rescue Error
      false
    end

    def list(relative, limit: 1000)
      directory = existing_path(relative)
      raise Error.new(:not_a_directory) unless directory.directory?

      normalized = normalize_relative(relative)
      entries = []
      truncated = false

      children = directory.children.reject { |child| child.basename.to_s.start_with?(".") }
      children
        .sort_by { |child| [child.directory? ? 0 : 1, child.basename.to_s.downcase] }
        .each do |child|
          if entries.length >= limit
            truncated = true
            break
          end

          next if File.symlink?(child)

          stat =
            begin
              File.stat(child)
            rescue StandardError
              next
            end

          entries << entry_for(child, stat, normalized)
        end

      { path: normalized, entries: entries, truncated: truncated }
    end

    def entry_for(path, stat, parent_relative)
      name = path.basename.to_s
      relative = [parent_relative, name].reject(&:blank?).join("/")

      if stat.directory?
        {
          name: name,
          path: relative,
          kind: "dir",
          modified_at: stat.mtime.iso8601,
        }
      else
        {
          name: name,
          path: relative,
          kind: "file",
          size: stat.size,
          human_size: ActiveSupport::NumberHelper.number_to_human_size(stat.size),
          modified_at: stat.mtime.iso8601,
          extension: File.extname(name).delete_prefix(".").downcase,
          mime: mime_for(name),
          previewable: previewable?(name),
          image: image?(name),
          url: url_for(relative),
        }
      end
    end

    def breadcrumbs(relative)
      current = []
      result = [{ name: "", path: "" }]

      normalize_relative(relative).split("/").each do |segment|
        current << segment
        result << { name: segment, path: current.join("/") }
      end

      result
    end

    def create_folder(parent_relative, name)
      clean = clean_name(name)
      directory = existing_path(parent_relative)
      raise Error.new(:not_a_directory) unless directory.directory?

      target = directory.join(clean)
      raise Error.new(:exists) if target.exist?

      Dir.mkdir(target)
    end

    def rename(relative, new_name)
      source = existing_path(relative)
      clean = clean_name(new_name)
      target = source.dirname.join(clean)

      raise Error.new(:exists) if target.exist? && target != source

      File.rename(source, target)
      relative_for(target)
    end

    def move(relative, target_directory)
      source = existing_path(relative)
      destination = existing_path(target_directory)
      raise Error.new(:not_a_directory) unless destination.directory?

      if source.directory? &&
           (destination == source || destination.to_s.start_with?("#{source}/"))
        raise Error.new(:move_into_self)
      end

      target = destination.join(source.basename)
      raise Error.new(:exists) if target.exist?

      File.rename(source, target)
      relative_for(target)
    end

    def delete(relative)
      return if relative.blank?

      path = existing_path(relative)

      if path.directory?
        raise Error.new(:not_empty) unless path.children.empty?

        Dir.rmdir(path)
      else
        File.delete(path)
      end
    end

    def delete_quietly(relative)
      delete(relative)
    rescue Error, SystemCallError
      nil
    end

    # Sweeping an abandoned transfer: the part file's name begins with a dot,
    # so it cannot be reached through `delete`, and it is not something the
    # screen may name either.
    def delete_staging(token_digest)
      path = staging_path(token_digest)
      File.delete(path) if path.file?
    rescue SystemCallError
      nil
    end

    # Where the pieces of one upload are appended. Named from the digest of the
    # server's token, never from the uploaded filename.
    def staging_relative(token_digest)
      File.join(STAGING_DIRECTORY, "#{token_digest}.part")
    end

    def staging_path(token_digest)
      internal_absolute(staging_relative(token_digest))
    end

    def append(relative, bytes)
      target = internal_absolute(relative)
      FileUtils.mkdir_p(target.dirname)

      File.open(target, "ab") { |file| file.write(bytes) }
      target.size
    end

    def align(relative, byte_size)
      target = internal_absolute(relative)
      FileUtils.mkdir_p(target.dirname)
      FileUtils.touch(target) unless target.exist?

      actual = target.size
      File.truncate(target, byte_size) if actual > byte_size
      actual
    end

    # The last step of an upload: hash the assembled bytes, then move them into
    # the folder the operator chose, under the filename they chose.
    #
    # The move is a rename, and staging lives inside the root, so a
    # three-gigabyte archive is not copied a second time. If the destination
    # exists the refused session keeps its part file, so the browser can retry
    # with another name without sending the bytes again.
    def finalize(staging_relative_path, directory_relative, filename)
      directory = existing_path(directory_relative)
      raise Error.new(:not_a_directory) unless directory.directory?

      clean = clean_name(filename)
      raise Error.new(:extension) unless allowed_extension?(clean)

      target = directory.join(clean)
      raise Error.new(:exists) if target.exist?

      source = internal_absolute(staging_relative_path)
      raise Error.new(:not_found) unless source.file?

      digest = Digest::SHA256.new
      byte_size = 0

      File.open(source, "rb") do |file|
        while (chunk = file.read(CHUNK))
          digest.update(chunk)
          byte_size += chunk.bytesize
        end
      end

      File.rename(source, target)

      {
        relative: relative_for(target),
        sha256: digest.hexdigest,
        size: byte_size,
        filename: clean,
      }
    end

    # A filename that came from a browser, made safe to be one name in one
    # directory. Unicode is kept — the team names files in both languages — but
    # separators, control characters and the two directory aliases are not.
    def clean_name(name)
      value = name.to_s.unicode_normalize(:nfc).strip

      raise Error.new(:name_invalid) if value.blank?
      raise Error.new(:name_invalid) if value == "." || value == ".."
      raise Error.new(:name_invalid) if value.start_with?(".")
      raise Error.new(:name_invalid) if value.length > MAX_NAME_LENGTH
      raise Error.new(:name_invalid) if value.include?("/") || value.include?("\\")
      raise Error.new(:name_invalid) if value.match?(/[[:cntrl:]]/)

      value
    end

    def allowed_extension?(filename)
      extension = File.extname(filename.to_s).delete_prefix(".").downcase
      return false if extension.blank?

      extensions.include?(extension)
    end

    # A list setting comes back as an array on some code paths and as the
    # comma-joined value on others, depending on how it was written and when it
    # was read. Both forms mean the same list, so both are accepted here rather
    # than leaving one of them to look like an empty allowlist.
    def extensions
      raw = SiteSetting.ingenic_file_manager_extensions
      list = raw.is_a?(Array) ? raw : raw.to_s.split(",")

      list.map { |item| item.to_s.strip.delete_prefix(".").downcase }.reject(&:blank?)
    end

    def image?(filename)
      %w[png jpg jpeg gif webp avif].include?(
        File.extname(filename.to_s).delete_prefix(".").downcase,
      )
    end

    def previewable?(filename)
      image?(filename) ||
        File.extname(filename.to_s).delete_prefix(".").downcase == "pdf" ||
        File.extname(filename.to_s).delete_prefix(".").downcase == "txt"
    end

    def mime_for(filename)
      extension = File.extname(filename.to_s).delete_prefix(".").downcase

      special = {
        "zip" => "application/zip",
        "7z" => "application/x-7z-compressed",
        "rar" => "application/vnd.rar",
        "tar" => "application/x-tar",
        "gz" => "application/gzip",
        "bz2" => "application/x-bzip2",
        "xz" => "application/x-xz",
        "bin" => "application/octet-stream",
        "md" => "text/markdown",
      }[extension]

      special || Mime::Type.lookup_by_extension(extension).to_s.presence ||
        "application/octet-stream"
    end

    # The public address of a file. Each segment is escaped separately so that
    # a folder or file named in Chinese, or with a space in it, still produces a
    # URL a browser can follow.
    def url_for(relative)
      normalized = normalize_relative(relative)
      escaped = normalized.split("/").map { |part| CGI.escape(part).gsub("+", "%20") }

      "/ingenic/files/#{escaped.join("/")}"
    end

    def relative_for(absolute)
      real_root = File.realpath(root_path)
      real = File.realpath(absolute)

      unless real.start_with?("#{real_root}/")
        raise Error.new(:path_invalid)
      end

      real.delete_prefix("#{real_root}/")
    end
  end
end
