# frozen_string_literal: true

# The file columns now live on the version, not on the card.
#
# Run as a post-deployment migration because it removes columns the previous
# release still reads: deploying the new code first and dropping the columns
# after means a rolling restart never has an old process looking for a column
# that is no longer there. The backfill in the preceding migration has already
# copied every row into `ingenic_download_versions`.
class RemoveIngenicDownloadFileColumns < ActiveRecord::Migration[7.2]
  COLUMNS = %w[
    version
    description
    platform
    architecture
    file_url
    storage_path
    original_filename
    file_size
    file_sha256
    sha256
    released_on
  ].freeze

  def up
    # The constraint has to move with the columns, or the new table would let a
    # version carry two different checksums for the same file.
    remove_check_constraint :ingenic_downloads,
                            "file_sha256 IS NULL OR sha256 IS NULL",
                            name: "ingenic_downloads_one_checksum"

    COLUMNS.each { |column| remove_column :ingenic_downloads, column }

    add_check_constraint :ingenic_download_versions,
                         "file_sha256 IS NULL OR sha256 IS NULL",
                         name: "ingenic_download_versions_one_checksum"

    # Every version has to name a file somewhere. The model says so, but an
    # import or a console session writes without the model, and a version with
    # no source is a card that answers "download" with nothing.
    add_check_constraint :ingenic_download_versions,
                         "COALESCE(NULLIF(BTRIM(file_url), ''), NULLIF(BTRIM(storage_path), '')) IS NOT NULL",
                         name: "ingenic_download_versions_has_source"

    execute <<~SQL
      COMMENT ON COLUMN ingenic_download_versions.sha256 IS
        'Checksum published beside a hand-entered or external URL.';
      COMMENT ON COLUMN ingenic_download_versions.file_sha256 IS
        'Checksum computed by the server while storing the uploaded file.';
    SQL
  end

  def down
    add_column :ingenic_downloads, :version, :string
    add_column :ingenic_downloads, :description, :text
    add_column :ingenic_downloads, :platform, :string
    add_column :ingenic_downloads, :architecture, :string
    add_column :ingenic_downloads, :file_url, :string
    add_column :ingenic_downloads, :storage_path, :string
    add_column :ingenic_downloads, :original_filename, :string
    add_column :ingenic_downloads, :file_size, :string
    add_column :ingenic_downloads, :file_sha256, :string
    add_column :ingenic_downloads, :sha256, :string
    add_column :ingenic_downloads, :released_on, :date

    remove_check_constraint :ingenic_download_versions,
                            "COALESCE(NULLIF(BTRIM(file_url), ''), NULLIF(BTRIM(storage_path), '')) IS NOT NULL",
                            name: "ingenic_download_versions_has_source"

    remove_check_constraint :ingenic_download_versions,
                            "file_sha256 IS NULL OR sha256 IS NULL",
                            name: "ingenic_download_versions_one_checksum"

    # The first version in the card's own order becomes the row's file again.
    # Anything the old schema could not hold — a second version — stays in the
    # versions table, which this migration does not drop.
    execute <<~SQL
      UPDATE ingenic_downloads AS d
      SET version = v.version,
          description = v.description,
          platform = v.platform,
          architecture = v.architecture,
          file_url = v.file_url,
          storage_path = v.storage_path,
          original_filename = v.original_filename,
          file_size = v.file_size,
          file_sha256 = v.file_sha256,
          sha256 = v.sha256,
          released_on = v.released_on
      FROM (
        SELECT DISTINCT ON (download_id) *
        FROM ingenic_download_versions
        ORDER BY download_id, position ASC, released_on DESC NULLS LAST, id ASC
      ) AS v
      WHERE v.download_id = d.id
    SQL

    # A row that was created as a card and never given a version has no file to
    # restore. The old schema required one, so it is left pointing at an empty
    # address rather than refusing the rollback; the application refuses to
    # save such a resource and the operator can fix it after rolling forward
    # again.
    execute <<~SQL
      UPDATE ingenic_downloads
      SET file_url = ''
      WHERE file_url IS NULL AND storage_path IS NULL
    SQL

    add_check_constraint :ingenic_downloads,
                         "file_sha256 IS NULL OR sha256 IS NULL",
                         name: "ingenic_downloads_one_checksum"
  end
end
