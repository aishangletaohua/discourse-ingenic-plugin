# frozen_string_literal: true

# The reference rules, which need the post-deploy slot: PostgreSQL has no ALTER
# for a referential action, so each one is dropped and written again, and
# Discourse makes a `DROP CONSTRAINT` in a regular migration raise.
#
# Four rules were wrong for what a row is for:
#
# * A download log is evidence of a hand-over. It was cascading away with the
#   account, which left no record that a gated file was collected. It now
#   outlives the account — the id is blanked and the name, copied in by the
#   regular migration, is what the row still says. The earlier rule chose
#   between a surviving row and a named recipient; the copy keeps both.
# * A contribution score belongs to the person and goes with them. Its key had
#   no action at all, so deleting a member failed on the constraint instead of
#   removing the score.
# * Deleting a download took neither its requests nor its grants, so the delete
#   failed. Both are about the resource and go with it. A grant keeps its
#   request link nullable, so removing one request does not take the grant too.
# * An upload session is a transfer in progress for one account. It had no
#   foreign key at all, so deleting that account left the row and its staged
#   bytes behind.
#
# A settled bounty also gains the reference it was missing: the accepted
# answer. It is nullable because the post can be permanently deleted, and it
# cascades nowhere because the bounty already goes with its topic.
#
# None of these can lose a row that was not going anyway. The download tables
# and the bounty table only drop rows their parent is already dropping, and
# the account rules blank rather than delete.
class HardenIngenicReferences < ActiveRecord::Migration[7.2]
  def up
    nullify_log_user
    cascade_contributions
    cascade_resource_children
    nullify_grant_request
    cascade_upload_sessions
    nullify_accepted_post
  end

  def down
    restore_log_cascade
    restore_contributions
    restore_resource_children
    restore_grant_request
    drop_upload_sessions_key
    drop_accepted_post_key
  end

  private

  def nullify_log_user
    remove_foreign_key :ingenic_download_logs, column: :user_id
    add_foreign_key :ingenic_download_logs,
                    :users,
                    column: :user_id,
                    on_delete: :nullify
  end

  # Rolling back cannot bring an account back. A log whose account was deleted
  # after this ran has no id to restore, so the key goes back to cascading and
  # the column stays nullable rather than failing the rollback. The regular
  # migration is where the column would be made required again, and it is not.
  def restore_log_cascade
    remove_foreign_key :ingenic_download_logs, column: :user_id
    add_foreign_key :ingenic_download_logs,
                    :users,
                    column: :user_id,
                    on_delete: :cascade
  end

  def cascade_contributions
    remove_foreign_key :ingenic_contributions, column: :user_id
    add_foreign_key :ingenic_contributions,
                    :users,
                    column: :user_id,
                    on_delete: :cascade
  end

  def restore_contributions
    remove_foreign_key :ingenic_contributions, column: :user_id
    add_foreign_key :ingenic_contributions, :users, column: :user_id
  end

  def cascade_resource_children
    remove_foreign_key :ingenic_download_requests, column: :download_id
    add_foreign_key :ingenic_download_requests,
                    :ingenic_downloads,
                    column: :download_id,
                    on_delete: :cascade

    remove_foreign_key :ingenic_download_grants, column: :download_id
    add_foreign_key :ingenic_download_grants,
                    :ingenic_downloads,
                    column: :download_id,
                    on_delete: :cascade
  end

  def restore_resource_children
    remove_foreign_key :ingenic_download_grants, column: :download_id
    add_foreign_key :ingenic_download_grants, :ingenic_downloads, column: :download_id
    remove_foreign_key :ingenic_download_requests, column: :download_id
    add_foreign_key :ingenic_download_requests, :ingenic_downloads, column: :download_id
  end

  def nullify_grant_request
    remove_foreign_key :ingenic_download_grants, column: :request_id
    add_foreign_key :ingenic_download_grants,
                    :ingenic_download_requests,
                    column: :request_id,
                    on_delete: :nullify
  end

  def restore_grant_request
    remove_foreign_key :ingenic_download_grants, column: :request_id
    add_foreign_key :ingenic_download_grants,
                    :ingenic_download_requests,
                    column: :request_id
  end

  def cascade_upload_sessions
    add_foreign_key :ingenic_upload_sessions,
                    :users,
                    column: :user_id,
                    on_delete: :cascade
  end

  def drop_upload_sessions_key
    remove_foreign_key :ingenic_upload_sessions, column: :user_id
  end

  def nullify_accepted_post
    add_foreign_key :ingenic_bounties,
                    :posts,
                    column: :accepted_post_id,
                    on_delete: :nullify
  end

  def drop_accepted_post_key
    remove_foreign_key :ingenic_bounties, column: :accepted_post_id
  end
end
