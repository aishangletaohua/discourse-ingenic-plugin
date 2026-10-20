# frozen_string_literal: true

# One external button, drawn in the footer's "Find us" row.
#
# Content rather than theme code: the official site, a GitHub organisation and
# a partner portal are addresses an administrator changes without a release.
# An entry can be a label, an icon, or both; when `show_label` is off the icon is
# drawn alone and the label becomes the button's accessible name, so "icon only"
# does not also mean "unnamed".
class IngenicHeaderLink < ActiveRecord::Base
  self.table_name = "ingenic_header_links"

  validates :label, presence: true
  validates :href, presence: true

  scope :published, -> { where(published: true) }
  scope :ordered, -> { order(position: :asc, id: :asc) }

  # A button with neither a name to read nor a picture to show is an empty
  # clickable box on every page. The label is required for screen readers; this
  # catches the visible half.
  validate :has_something_to_draw

  private

  def has_something_to_draw
    return if show_label
    return if icon.present? || image_url.present?

    errors.add(:icon, :blank)
  end
end
