# frozen_string_literal: true

# A chunked upload has to survive the request that started it. The browser
# sends a three-gigabyte image in pieces because the web server in front of
# Rails refuses any single request over ten megabytes; the file being assembled
# needs a name, an owner and a byte count that outlive each of those requests.
#
# The row is also what makes the upload resumable: after a dropped connection
# the browser asks the server how many bytes it already has rather than
# starting the image again.
class CreateIngenicUploadSessions < ActiveRecord::Migration[7.0]
  def change
    create_table :ingenic_upload_sessions do |t|
      t.string :token, null: false
      t.integer :user_id, null: false
      t.string :original_filename, null: false
      t.bigint :expected_size, null: false, default: 0
      t.bigint :received_size, null: false, default: 0
      t.string :status, null: false, default: "pending"
      t.string :sha256
      t.string :storage_path
      t.timestamps
    end

    add_index :ingenic_upload_sessions, :token, unique: true
    add_index :ingenic_upload_sessions, :created_at
  end
end
