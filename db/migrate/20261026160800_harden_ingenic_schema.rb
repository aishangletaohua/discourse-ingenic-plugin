# frozen_string_literal: true

# What the database audit found, fixed where the fix is mechanical.
#
# The models already validate these values, but the database did not: a
# console session or an import that skipped the model could write a feature or
# an access level the code has no branch for. The checks below make the same
# set of answers the only set the table can hold, so a bad row is refused at
# the point it would be written rather than quietly changing how a screen
# behaves.
#
# A download log also gains the account name beside the account id. The log
# exists to answer who collected a gated file; the earlier rule let the row go
# with the account, which answered nothing, and simply blanking the account
# would have left a delivery with no recipient named. Copying the name in is
# the same thing the row already does with the resource name and version.
# The foreign key that blanks the id lives in the post-deploy migration, where
# Discourse requires a referential action to be changed.
#
# The rest is tidying: one checksum per row instead of two columns holding the
# same hash, and fourteen indexes that duplicate the leading column of another
# index on the same table.
class HardenIngenicSchema < ActiveRecord::Migration[7.2]
  CHECKS = {
    ingenic_feature_permissions: {
      "ingenic_feature_permissions_feature_known" =>
        "feature IN ('documentation', 'boards', 'downloads', 'files', 'points', 'site')",
    },
    ingenic_permissions: {
      "ingenic_permissions_permission_known" => "permission = 'manage'",
      "ingenic_permissions_area_known" =>
        "area IN ('documentation', 'downloads', 'boards')",
      "ingenic_permissions_resource_type_known" =>
        "resource_type IN ('IngenicProduct', 'IngenicDocPage', 'IngenicBoard', 'IngenicDownload')",
    },
    ingenic_downloads: {
      "ingenic_downloads_access_level_known" =>
        "access_level IN ('public_login', 'login_form', 'login_form_request')",
      "ingenic_downloads_family_known" => "family IN ('chip', 'algorithm')",
    },
    ingenic_doc_pages: {
      "ingenic_doc_pages_kind_known" => "kind IN ('page', 'folder')",
    },
    ingenic_boards: {
      "ingenic_boards_kind_known" => "kind IN ('board', 'sample')",
    },
    ingenic_download_requests: {
      "ingenic_download_requests_status_known" =>
        "status IN ('pending', 'approved', 'rejected')",
    },
    ingenic_bounties: {
      "ingenic_bounties_state_known" =>
        "state IN ('open', 'accepted', 'cancelled', 'expired')",
    },
    ingenic_upload_sessions: {
      "ingenic_upload_sessions_status_known" => "status IN ('pending', 'completed')",
      "ingenic_upload_sessions_purpose_known" => "purpose IN ('downloads', 'files')",
    },
    ingenic_tag_colours: {
      "ingenic_tag_colours_family_known" =>
        "family IN ('sky', 'tech', 'resolved', 'announcement', 'hot')",
    },
    ingenic_social_links: {
      "ingenic_social_links_kind_known" => "kind IN ('link', 'qr')",
    },
    ingenic_point_rules: {
      "ingenic_point_rules_event_known" =>
        "event IN ('topic_created', 'post_created', 'like_received', 'solution_accepted')",
      "ingenic_point_rules_points_not_negative" => "points >= 0",
    },
  }.freeze

  REDUNDANT_INDEXES = {
    ingenic_boards: %w[index_ingenic_boards_on_product_id],
    ingenic_bounties: %w[index_ingenic_bounties_on_state],
    ingenic_contributions: %w[index_ingenic_contributions_on_user_id],
    ingenic_doc_pages: %w[index_ingenic_doc_pages_on_version_id],
    ingenic_doc_versions: %w[index_ingenic_doc_versions_on_product_id],
    ingenic_download_grants: %w[index_ingenic_download_grants_on_user_id],
    ingenic_download_logs: %w[
      index_ingenic_download_logs_on_download_id
      index_ingenic_download_logs_on_user_id
    ],
    ingenic_download_requests: %w[index_ingenic_download_requests_on_user_id],
    ingenic_downloads: %w[index_ingenic_downloads_on_product_id],
    ingenic_footer_links: %w[index_ingenic_footer_links_on_column_id],
    ingenic_permissions: %w[
      index_ingenic_permissions_on_group_id
      index_ingenic_permissions_on_user_id
    ],
    ingenic_point_entries: %w[index_ingenic_point_entries_on_user_id],
  }.freeze

  def up
    add_enum_checks
    keep_one_checksum
    keep_download_log_identity
    index_accepted_post
    add_index :ingenic_upload_sessions, :user_id
    drop_redundant_indexes
    describe_columns
  end

  # Written out one by one rather than driven by CHECKS: the repository's
  # migration spec reads each `def` by hand and treats a block inside `down` as
  # the end of the method, so a loop here reads as a destroy outside it.
  def down
    remove_check_constraint :ingenic_feature_permissions,
                            name: "ingenic_feature_permissions_feature_known"
    remove_check_constraint :ingenic_permissions, name: "ingenic_permissions_permission_known"
    remove_check_constraint :ingenic_permissions, name: "ingenic_permissions_area_known"
    remove_check_constraint :ingenic_permissions,
                            name: "ingenic_permissions_resource_type_known"
    remove_check_constraint :ingenic_downloads, name: "ingenic_downloads_access_level_known"
    remove_check_constraint :ingenic_downloads, name: "ingenic_downloads_family_known"
    remove_check_constraint :ingenic_doc_pages, name: "ingenic_doc_pages_kind_known"
    remove_check_constraint :ingenic_boards, name: "ingenic_boards_kind_known"
    remove_check_constraint :ingenic_download_requests,
                            name: "ingenic_download_requests_status_known"
    remove_check_constraint :ingenic_bounties, name: "ingenic_bounties_state_known"
    remove_check_constraint :ingenic_upload_sessions,
                            name: "ingenic_upload_sessions_status_known"
    remove_check_constraint :ingenic_upload_sessions,
                            name: "ingenic_upload_sessions_purpose_known"
    remove_check_constraint :ingenic_tag_colours, name: "ingenic_tag_colours_family_known"
    remove_check_constraint :ingenic_social_links, name: "ingenic_social_links_kind_known"
    remove_check_constraint :ingenic_point_rules, name: "ingenic_point_rules_event_known"
    remove_check_constraint :ingenic_point_rules,
                            name: "ingenic_point_rules_points_not_negative"
    remove_check_constraint :ingenic_downloads,
                            "file_sha256 IS NULL OR sha256 IS NULL",
                            name: "ingenic_downloads_one_checksum"

    remove_index :ingenic_bounties,
                 name: "index_ingenic_bounties_on_accepted_post_id",
                 if_exists: true
    remove_index :ingenic_upload_sessions, :user_id, if_exists: true
    remove_column :ingenic_download_logs, :username
    restore_indexes

    execute <<~SQL
      COMMENT ON COLUMN ingenic_downloads.sha256 IS NULL;
      COMMENT ON COLUMN ingenic_downloads.file_sha256 IS NULL;
      COMMENT ON COLUMN ingenic_feature_permissions.feature IS NULL;
      COMMENT ON COLUMN ingenic_permissions.area IS NULL;
      COMMENT ON COLUMN ingenic_permissions.resource_type IS NULL;
      COMMENT ON COLUMN ingenic_permissions.resource_id IS NULL;
    SQL
  end

  private

  def add_enum_checks
    CHECKS.each do |table, constraints|
      constraints.each do |name, expression|
        add_check_constraint table, expression, name: name
      end
    end
  end

  # `sha256` is the checksum a hand-entered URL came with; `file_sha256` is the
  # digest the server computed when it stored the bytes. A row can only be one
  # of those, and keeping the stale hand-entered value beside the computed one
  # made two columns claim to answer the same question.
  def keep_one_checksum
    execute "UPDATE ingenic_downloads SET sha256 = NULL WHERE file_sha256 IS NOT NULL"
    add_check_constraint :ingenic_downloads,
                         "file_sha256 IS NULL OR sha256 IS NULL",
                         name: "ingenic_downloads_one_checksum"
  end

  def keep_download_log_identity
    add_column :ingenic_download_logs, :username, :string
    execute <<~SQL
      UPDATE ingenic_download_logs AS log
      SET username = users.username
      FROM users
      WHERE users.id = log.user_id
    SQL
    change_column_null :ingenic_download_logs, :user_id, true
  end

  # A settled bounty points at the answer it paid for. The post-deploy
  # migration writes the rule; the column it reads by needs an index first so
  # the database does not scan the table to find the rows a deletion touches.
  def index_accepted_post
    add_index :ingenic_bounties,
              :accepted_post_id,
              name: "index_ingenic_bounties_on_accepted_post_id"
  end

  def drop_redundant_indexes
    REDUNDANT_INDEXES.each do |table, names|
      names.each { |name| remove_index table, name: name, if_exists: true }
    end
  end

  def restore_indexes
    REDUNDANT_INDEXES.each do |table, names|
      names.each do |name|
        column = name.delete_prefix("index_#{table}_on_")
        add_index table, column
      end
    end
  end

  def describe_columns
    execute <<~SQL
      COMMENT ON COLUMN ingenic_downloads.sha256 IS
        'Checksum supplied for a resource hosted at file_url; null for managed uploads';
      COMMENT ON COLUMN ingenic_downloads.file_sha256 IS
        'SHA-256 computed by the server when the file was stored; authoritative for managed uploads';
      COMMENT ON COLUMN ingenic_download_logs.username IS
        'Account name copied at hand-over, so the log still names the recipient after the account is gone';
      COMMENT ON COLUMN ingenic_feature_permissions.feature IS
        'One whole management screen: documentation, boards, downloads, files, points or site';
      COMMENT ON COLUMN ingenic_permissions.area IS
        'The domain a per-record grant applies to: documentation, downloads or boards';
      COMMENT ON COLUMN ingenic_permissions.resource_type IS
        'Polymorphic target, validated by the model; deliberately no foreign key because it spans tables';
      COMMENT ON COLUMN ingenic_permissions.resource_id IS
        'Id of the product, page, board or download this grant names';
    SQL
  end
end
