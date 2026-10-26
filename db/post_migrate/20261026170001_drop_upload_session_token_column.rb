# frozen_string_literal: true

# The plaintext token itself, once the digest has taken over its two jobs
# (finding the row, naming the part file). This runs after the deploy because
# Discourse refuses to drop a column while the previous application server may
# still be reading it.
#
# Rolling back cannot bring the old tokens back — they were never stored
# anywhere but the browser and the row. The column is re-added empty so the
# previous code has somewhere to write; transfers that were in flight when the
# migration ran are swept by the cleanup job.
class DropUploadSessionTokenColumn < ActiveRecord::Migration[7.2]
  def up
    remove_column :ingenic_upload_sessions, :token
  end

  def down
    add_column :ingenic_upload_sessions, :token, :string
  end
end
