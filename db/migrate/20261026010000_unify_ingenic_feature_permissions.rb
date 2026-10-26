# frozen_string_literal: true

# Whole-screen grants were a group's alone, which meant lending somebody the
# download centre required putting them in a group first. A group is the right
# way to hand one job to a team, but it is the wrong way to hand it to one
# person, and the forum ended up with a group per individual.
#
# The table now names either a user or a group, exactly one of the two, which
# is the same shape `ingenic_permissions` already uses for a single record.
# One grant table, one resolver, one place to look when asking who may do
# something.
class UnifyIngenicFeaturePermissions < ActiveRecord::Migration[7.2]
  NEW_USER_INDEX = "idx_ingenic_feature_permissions_user"
  NEW_GROUP_INDEX = "idx_ingenic_feature_permissions_group"
  PRINCIPAL_CHECK = "ingenic_feature_permissions_one_principal"

  def up
    create_table :ingenic_feature_permissions do |t|
      t.integer :user_id
      t.integer :group_id
      t.string :feature, null: false
      t.timestamps
    end

    add_index :ingenic_feature_permissions, %i[user_id feature],
              unique: true,
              where: "user_id IS NOT NULL",
              name: NEW_USER_INDEX
    add_index :ingenic_feature_permissions, %i[group_id feature],
              unique: true,
              where: "group_id IS NOT NULL",
              name: NEW_GROUP_INDEX

    add_check_constraint :ingenic_feature_permissions,
                         "(user_id IS NOT NULL AND group_id IS NULL) OR " \
                           "(user_id IS NULL AND group_id IS NOT NULL)",
                         name: PRINCIPAL_CHECK,
                         validate: true

    add_foreign_key :ingenic_feature_permissions, :users, on_delete: :cascade
    add_foreign_key :ingenic_feature_permissions, :groups, on_delete: :cascade

    execute <<~SQL
      INSERT INTO ingenic_feature_permissions (group_id, feature, created_at, updated_at)
      SELECT group_id, feature, created_at, updated_at
      FROM ingenic_group_permissions
    SQL

    # The old table is not dropped here. Discourse refuses to drop a table from
    # a normal migration (db/migrate) so that a deploy can be rolled back before
    # the old code is gone; the drop lives in db/post_migrate, which runs in the
    # same deploy but only after the new code is in place.
  end

  def down
    # `ingenic_group_permissions` is recreated by the post-deploy migration's
    # down, which runs first when rolling back. Only the new table belongs to
    # this migration.
    drop_table :ingenic_feature_permissions
  end
end
