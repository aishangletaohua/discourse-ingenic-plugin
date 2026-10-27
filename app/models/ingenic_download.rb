# frozen_string_literal: true

class IngenicDownload < ActiveRecord::Base
  self.table_name = "ingenic_downloads"

  # The three tiers, in the order the Ingenic team describes them.
  #
  # public_login        signed in is enough
  # login_form          signed in, with developer information on file
  # login_form_request  signed in, information on file, and an approved request
  LOGIN_ONLY = "public_login"
  FORM_REQUIRED = "login_form"
  APPROVAL_REQUIRED = "login_form_request"
  ACCESS_LEVELS = [LOGIN_ONLY, FORM_REQUIRED, APPROVAL_REQUIRED].freeze

  # The catalogue's two top-level lines. A chip resource belongs to a part
  # number; an algorithm is offered across parts and has no chip of its own, so
  # it is not filed under one. Keeping the family here rather than as another
  # node in the product tree keeps the tree about chips.
  FAMILY_CHIP = "chip"
  FAMILY_ALGORITHM = "algorithm"
  FAMILIES = [FAMILY_CHIP, FAMILY_ALGORITHM].freeze

  # The files under this card. One row per release, each with its own
  # description and download, while the access rule above is shared by all of
  # them: approving an account for the resource approves it for every version
  # the team publishes under it.
  has_many :versions,
           class_name: "IngenicDownloadVersion",
           foreign_key: :download_id,
           dependent: :destroy

  # The picture on the card, uploaded from the management screen. A resource
  # without one is drawn with the catalogue placeholder rather than with an
  # empty box; an upload that is deleted elsewhere leaves the card in that same
  # state instead of taking the resource with it.
  belongs_to :image_upload, class_name: "Upload", optional: true

  has_many :requests,
           class_name: "IngenicDownloadRequest",
           foreign_key: :download_id,
           dependent: :destroy
  has_many :grants,
           class_name: "IngenicDownloadGrant",
           foreign_key: :download_id,
           dependent: :destroy
  has_many :logs,
           class_name: "IngenicDownloadLog",
           foreign_key: :download_id,
           dependent: :destroy

  # Optional on purpose. The classification is Ingenic's own list and they can
  # retire an entry, which leaves the resources filed under it unfiled rather
  # than deleted; a resource in that state has to remain valid so it can be
  # reclassified instead of refusing to save.
  belongs_to :category, class_name: "IngenicDownloadCategory", optional: true

  # A chip resource points at the same catalogue row its board and its
  # documentation use. An algorithm runs across parts and has no chip, so the
  # link stays optional and the family decides whether it is required.
  belongs_to :product, class_name: "IngenicProduct", optional: true

  validates :name, presence: true
  validates :access_level, inclusion: { in: ACCESS_LEVELS }
  validates :family, inclusion: { in: FAMILIES }
  validates :locale, presence: true
  # A row cannot be both untethered and filed under a part number. Clearing the
  # link here makes the family the single source of truth even for a row that
  # was switched from chip to algorithm after it had one.
  before_validation { self.product = nil if algorithm? }
  # Only a chip resource needs a part number. An algorithm that runs on several
  # chips is not filed under one, and requiring a link would either invent a
  # false attachment or leave algorithms out of the catalogue.
  validate :chip_has_a_product
  validate :product_is_a_chip
  validate :product_locale_matches
  validate :image_is_an_image
  # Not signed, for the same reason a point rule is not: a negative price is a
  # charge for arriving, and a member who cannot afford one would be refused a
  # file for having done nothing.
  validates :point_cost, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :published, -> { where(published: true) }
  scope :ordered, -> { order(position: :asc, name: :asc) }
  scope :for_locale, ->(locale) { where(locale: locale) }

  def chip?
    family == FAMILY_CHIP
  end

  def algorithm?
    family == FAMILY_ALGORITHM
  end

  def login_only?
    access_level == LOGIN_ONLY
  end

  def form_required?
    access_level == FORM_REQUIRED
  end

  def approval_required?
    access_level == APPROVAL_REQUIRED
  end

  # Whether this resource costs points to unlock. An addition to the access
  # levels rather than a fourth one: the levels decide who may have a file, and
  # this decides what it costs once they may.
  def costs_points?
    point_cost.positive?
  end

  # What the listing prints on the card. Null for a resource whose category has
  # been retired or was never set, which the callers treat as "show no label"
  # rather than as an error.
  def category_name
    category&.name
  end

  # What the listing draws: only versions the team has published, newest order
  # first. A withdrawn version stays in the table so its delivery log still
  # names something real.
  def published_versions
    versions.published.ordered.to_a
  end

  # Whether the card can be offered at all. A published resource whose every
  # version is withdrawn has nothing to hand over and is left out of the
  # listing rather than shown with a button that cannot work.
  def downloadable?
    published_versions.any?
  end

  # The picture on the card. Read through the upload so a replacement at the
  # same id is picked up without touching the resource; nil draws the
  # placeholder.
  def image_url
    image_upload&.url
  end

  private

  def chip_has_a_product
    return unless chip?
    return if product.present?

    errors.add(:product, :blank)
  end

  def product_is_a_chip
    return if product.nil? || product.chip?

    errors.add(:product, "must be a chip")
  end

  # A download is written in the language of the chip it belongs to. Letting the
  # two differ is how an English file ends up under a Chinese chip and appears
  # in neither reader's listing.
  def product_locale_matches
    return if product.nil? || locale.blank?
    return if product.locale == locale

    errors.add(:locale, "must match the product's language")
  end

  # The card's picture is drawn at a fixed ratio, and a PDF or an archive in
  # that slot is a broken image on the catalogue. The uploader already knows
  # what it accepted; this is the server saying so as well.
  def image_is_an_image
    return if image_upload.nil?
    return if FileHelper.is_supported_image?("image.#{image_upload.extension}")

    errors.add(:image_upload, "must be an image")
  end
end
