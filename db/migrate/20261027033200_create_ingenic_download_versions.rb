# frozen_string_literal: true

# A download card is a resource, and the files under it are versions.
#
# Until now one row was one file: a chip with SDK 1.0 and SDK 1.1 was two
# cards, each with its own access tier, its own applications and its own
# grants. The catalogue the team wants is one card per resource with a version
# selector under it, so the row that carries the access rule and the row that
# carries the bytes have to be separated.
#
# `ingenic_downloads` stays the resource: it is what requests, grants, points
# and the delivery log already point at, and keeping it that way means none of
# those records has to move. The file columns move to `ingenic_download_versions`
# one row per existing download, so every current file remains downloadable
# under the same id and the same access rules.
class CreateIngenicDownloadVersions < ActiveRecord::Migration[7.2]
  def up
    create_table :ingenic_download_versions do |t|
      t.bigint :download_id, null: false
      t.string :version
      t.text :description
      t.string :platform
      t.string :architecture
      t.string :file_url
      t.string :storage_path
      t.string :original_filename
      t.string :file_size
      t.string :file_sha256
      t.string :sha256
      t.date :released_on
      t.boolean :published, null: false, default: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    # Two versions under one resource cannot share a label: the select would
    # show two identical options and nothing would say which file is which.
    # Unlabelled drafts are allowed to repeat, so the index is partial.
    add_index :ingenic_download_versions,
              %i[download_id version],
              unique: true,
              where: "version IS NOT NULL",
              name: "index_ingenic_download_versions_unique_label"
    add_index :ingenic_download_versions, %i[download_id published]

    add_foreign_key :ingenic_download_versions,
                    :ingenic_downloads,
                    column: :download_id,
                    on_delete: :cascade

    # One version per existing row, carrying the file it already had. The
    # resource keeps its id, so an application approved yesterday still points
    # at the card the applicant was approved for.
    execute <<~SQL
      INSERT INTO ingenic_download_versions
        (download_id, version, description, platform, architecture, file_url,
         storage_path, original_filename, file_size, file_sha256, sha256,
         released_on, published, position, created_at, updated_at)
      SELECT id, version, description, platform, architecture, file_url,
             storage_path, original_filename, file_size, file_sha256, sha256,
             released_on, published, position, created_at, updated_at
      FROM ingenic_downloads
    SQL

    add_column :ingenic_downloads, :image_upload_id, :bigint
    add_index :ingenic_downloads, :image_upload_id
    add_foreign_key :ingenic_downloads,
                    :uploads,
                    column: :image_upload_id,
                    on_delete: :nullify
  end

  def down
    remove_foreign_key :ingenic_downloads, column: :image_upload_id
    remove_index :ingenic_downloads, :image_upload_id
    remove_column :ingenic_downloads, :image_upload_id
    drop_table :ingenic_download_versions
  end
end
