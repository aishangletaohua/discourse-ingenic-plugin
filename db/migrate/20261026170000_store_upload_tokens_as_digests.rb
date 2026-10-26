# frozen_string_literal: true

# The token that names an upload in progress is the only thing standing between
# a half-finished transfer and someone else's request, and it was stored as it
# was sent. A copy of the database would therefore contain the live tokens of
# every upload in flight.
#
# The token is not needed to find the row or name the part file: a digest does
# both. The browser keeps the token, the server keeps the digest, and a leaked
# row cannot be turned back into the handle the endpoints accept.
#
# Existing rows are converted in place. Their tokens remain valid for the
# browser that holds them; only the server's copy changes shape.
class StoreUploadTokensAsDigests < ActiveRecord::Migration[7.2]
  def up
    add_column :ingenic_upload_sessions, :token_digest, :string
    execute <<~SQL
      UPDATE ingenic_upload_sessions
      SET token_digest = encode(sha256(token::bytea), 'hex')
    SQL
    change_column_null :ingenic_upload_sessions, :token_digest, false
    add_index :ingenic_upload_sessions,
              :token_digest,
              unique: true,
              name: "index_ingenic_upload_sessions_on_token_digest"
  end

  def down
    remove_index :ingenic_upload_sessions,
                 name: "index_ingenic_upload_sessions_on_token_digest"
    remove_column :ingenic_upload_sessions, :token_digest
  end
end
