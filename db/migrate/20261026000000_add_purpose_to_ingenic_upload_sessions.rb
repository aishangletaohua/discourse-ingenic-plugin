# frozen_string_literal: true

# One upload mechanism now serves two screens: the download centre, whose files
# live in `ingenic-downloads`, and the file manager, whose files live in the
# directory it is pointed at. The session row has to remember which, because
# the part file is staged inside the root it will be moved into, and the
# cleanup job has to look in the same place when it sweeps an abandoned one.
class AddPurposeToIngenicUploadSessions < ActiveRecord::Migration[7.0]
  def up
    add_column :ingenic_upload_sessions, :purpose, :string, null: false, default: "downloads"
    add_index :ingenic_upload_sessions, [:purpose, :created_at]
  end

  def down
    remove_index :ingenic_upload_sessions, [:purpose, :created_at]
    remove_column :ingenic_upload_sessions, :purpose
  end
end
