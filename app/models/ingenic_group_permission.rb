# frozen_string_literal: true

# A group allowed to reach one of the plugin's management screens in full.
#
# The screens line up with the kinds of thing the plugin owns, and a row means
# "this group may manage all of them": every documentation product, every
# download, every board, the official file library, or the site's own content
# blocks. Narrower delegation stays where it was, in `IngenicPermission`, which
# names a single record and a single principal.
#
# Files has no narrower form: the library is one screen, and lending somebody
# one folder would be a second permission model for no gain. A group works in
# the library or does not see it at all.
#
# `points` is separate from the rest because moving a balance is not editing
# content: a group trusted with documentation should not be able to pay itself
# points by accident.
class IngenicGroupPermission < ActiveRecord::Base
  self.table_name = "ingenic_group_permissions"

  # `files` is the file manager: the internal library of official SDK archives,
  # PDFs and images. It is one screen and one grant — there is no narrower
  # record to lend it over, and a group either works in the library or does not
  # see it at all.
  FEATURES = %w[documentation boards downloads files points site].freeze

  belongs_to :group

  validates :group_id, presence: true
  validates :feature, inclusion: { in: FEATURES }
  validates :group_id, uniqueness: { scope: :feature }

  # Groups worth offering in the matrix. Discourse's automatic groups — staff
  # and the trust levels — are membership the site maintains rather than a set
  # anyone curates, and granting `everyone` a management screen by accident is
  # exactly the kind of click this list exists to prevent. Custom groups are the
  # ones an administrator creates, names and fills.
  def self.assignable_groups
    Group.where.not(id: Group::AUTO_GROUPS.values).order(:name)
  end
end
