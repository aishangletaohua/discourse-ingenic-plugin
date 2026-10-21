# frozen_string_literal: true

class IngenicDocVersion < ActiveRecord::Base
  self.table_name = "ingenic_doc_versions"

  belongs_to :product, class_name: "IngenicProduct", foreign_key: :product_id

  has_many :pages,
           -> { order(position: :asc) },
           class_name: "IngenicDocPage",
           foreign_key: :version_id,
           dependent: :destroy

  # The version's language is the product's. Storing it twice let the two
  # disagree; the reader then saw a version under a product it was not written
  # for.
  delegate :locale, to: :product

  validates :slug, presence: true, uniqueness: { scope: :product_id }
  validates :label, presence: true

  # There is deliberately no `published` scope: a version has no such column.
  # What a reader may see is decided page by page, which is also what makes
  # inheritance work — a version that has not been written yet shows the pages
  # it inherited.
  scope :ordered, -> { order(position: :asc, released_on: :desc) }

  # The version's pages as a reader sees them, which includes everything
  # inherited from earlier versions. See Ingenic::DocumentationResolver.
  def published_pages
    resolver.effective_pages(self)
  end

  def find_readable_page(slug)
    resolver.find_page(self, slug)
  end

  # Every page the version resolves to, drafts included. Used by the management
  # page, which has to show what a reader cannot yet see.
  def page_tree
    resolver.effective_pages(self, published_only: false)
  end

  # The row this version owns for a slug, if any. Its absence is what makes a
  # page inherited.
  def own_page(slug)
    pages.find_by(slug: slug)
  end

  def navigation_for(page)
    resolver.navigation_for(self, page)
  end

  def resolver
    @resolver ||= Ingenic::DocumentationResolver.new(product)
  end
end
