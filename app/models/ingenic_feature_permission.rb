# frozen_string_literal: true

# A whole management screen, granted to one account or one group.
#
# A group is the batch layer: "everybody in documentation-owners may edit the
# documentation screen". An account is the exception that does not deserve a
# group of its own: one contractor who looks after the download centre, one
# engineer who maintains the boards for a quarter. Both mean exactly the same
# thing to the resolver, which is why they live in one table rather than in a
# group table beside a user table.
#
# Narrower delegation stays in `IngenicPermission`, which names one product,
# page, board or download. A row here says "all of them on this screen".
#
# `points` is separate from the content screens because moving a balance is not
# editing content: an account trusted with documentation should not be able to
# pay itself points by accident. It is still a grant an administrator can make
# deliberately.
class IngenicFeaturePermission < ActiveRecord::Base
  self.table_name = "ingenic_feature_permissions"

  # `files` is the file manager: the internal library of official SDK archives,
  # PDFs and images. It is one screen and one grant — there is no narrower
  # record to lend it over, and a grantee either works in the library or does
  # not see it at all.
  FEATURES = %w[documentation boards downloads files points site].freeze

  belongs_to :user, optional: true
  belongs_to :group, optional: true

  validates :feature, inclusion: { in: FEATURES }
  validates :user_id, uniqueness: { scope: :feature }, if: -> { user_id.present? }
  validates :group_id, uniqueness: { scope: :feature }, if: -> { group_id.present? }
  validate :exactly_one_principal

  # Groups worth offering in the matrix. Discourse's automatic groups — staff
  # and the trust levels — are membership the site maintains rather than a set
  # anyone curates, and granting `everyone` a management screen by accident is
  # exactly the kind of click this list exists to prevent. Custom groups are the
  # ones an administrator creates, names and fills.
  def self.assignable_groups
    Group.where.not(id: Group::AUTO_GROUPS.values).order(:name)
  end

  def self.assignable_users
    User.activated.not_suspended
  end

  def principal
    user || group
  end

  private

  def exactly_one_principal
    return if user_id.present? ^ group_id.present?

    errors.add(:base, I18n.t("ingenic.admin_errors.one_principal"))
  end
end
