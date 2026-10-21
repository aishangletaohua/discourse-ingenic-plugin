# frozen_string_literal: true

# One partner platform in the footer strip.
#
# Two shapes, told apart by kind. A "link" leaves the site. A "qr" opens an
# image on hover, which is how a WeChat account has to be presented: there is no
# URL that means "follow us", only a code someone scans.
class IngenicSocialLink < ActiveRecord::Base
  self.table_name = "ingenic_social_links"

  LINK = "link"
  QR = "qr"
  KINDS = [LINK, QR].freeze

  validates :label, presence: true
  validates :locale, presence: true
  validates :kind, inclusion: { in: KINDS }
  validate :has_something_to_show

  scope :published, -> { where(published: true) }
  scope :ordered, -> { order(position: :asc, id: :asc) }

  def qr?
    kind == QR
  end

  private

  # An entry that neither goes anywhere nor shows anything renders as a dead
  # icon on every page, and the admin who typed it gets no feedback at all. The
  # requirement depends on which kind was chosen, so it is checked here rather
  # than as a presence validation on either column.
  def has_something_to_show
    if qr?
      errors.add(:qr_image_url, :blank) if qr_image_url.blank?
    elsif href.blank?
      errors.add(:href, :blank)
    end
  end
end
