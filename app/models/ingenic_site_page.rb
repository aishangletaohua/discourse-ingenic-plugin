# frozen_string_literal: true

# A standalone page the team edits: the terms, the privacy policy, the rules for
# points, and anything else the footer needs to point at.
#
# Each language is a row of its own, the same as every other content table in
# the plugin. A reader asking for Chinese gets the Chinese page, and a page that
# has not been translated is a page that does not exist in that language — the
# trailing pages are public statements, and answering one in a language the
# reader did not ask for would be worse than saying it is not there.
class IngenicSitePage < ActiveRecord::Base
  self.table_name = "ingenic_site_pages"

  # The address is the slug, so it has to be one that survives a URL, a file
  # name and a person reading it out loud.
  SLUG_FORMAT = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/

  validates :slug, presence: true, format: { with: SLUG_FORMAT }
  validates :slug, uniqueness: { scope: :locale }
  validates :title, presence: true
  validates :locale, presence: true

  scope :published, -> { where(published: true) }
  scope :ordered, -> { order(position: :asc, id: :asc) }
  scope :for_locale, ->(locale) { where(locale: locale) }

  def to_param
    slug
  end
end
