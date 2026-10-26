# frozen_string_literal: true

# The second half of unifying the whole-screen grants: the regular migration
# created `ingenic_feature_permissions` and copied every group grant into it;
# this one removes the table that is now only a copy.
#
# It lives in `db/post_migrate` because Discourse refuses a table drop in a
# regular migration. A deploy runs the regular migrations first, swaps the
# application servers over, and only then runs post-deploy migrations, so the
# table is still there for any process that was still reading it during the
# switch. That is also why the copy is in the other migration: by the time the
# table goes, its rows are already somewhere else.
class DropIngenicGroupPermissions < ActiveRecord::Migration[7.2]
  OLD_UNIQUE_INDEX = "idx_ingenic_group_permissions_unique"

  def up
    drop_table :ingenic_group_permissions
  end

  # Rolling back rebuilds the old table from the group half of the new one.
  #
  # A grant held by an account has no column here to go in, so the rollback is
  # lossy in one direction: accounts that were given a screen on their own keep
  # nothing. Saying so is better than a migration that silently drops rows, and
  # the new table is left standing so the rows are still there to be copied
  # again if the rollback is itself rolled forward.
  def down
    create_table :ingenic_group_permissions do |t|
      t.integer :group_id, null: false
      t.string :feature, null: false
      t.timestamps
    end

    add_index :ingenic_group_permissions,
              %i[group_id feature],
              unique: true,
              name: OLD_UNIQUE_INDEX
    add_foreign_key :ingenic_group_permissions,
                    :groups,
                    column: :group_id,
                    on_delete: :cascade

    execute <<~SQL
      INSERT INTO ingenic_group_permissions (group_id, feature, created_at, updated_at)
      SELECT group_id, feature, created_at, updated_at
      FROM ingenic_feature_permissions
      WHERE group_id IS NOT NULL
      ON CONFLICT DO NOTHING
    SQL
  end
end
