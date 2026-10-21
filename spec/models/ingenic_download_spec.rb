# frozen_string_literal: true

require "rails_helper"

describe IngenicDownload do
  fab!(:series) { IngenicProduct.create!(slug: "t-series", name: "T Series", locale: "en") }
  fab!(:chip) do
    IngenicProduct.create!(
      slug: "t33",
      name: "T33",
      kind: IngenicProduct::CHIP,
      parent: series,
      locale: "en",
    )
  end

  def download(**attrs)
    IngenicDownload.new(
      {
        name: "SDK",
        family: "chip",
        product: chip,
        locale: "en",
        access_level: IngenicDownload::LOGIN_ONLY,
        file_url: "https://example.com/sdk.tgz",
      }.merge(attrs),
    )
  end

  it "requires a part number for a chip resource" do
    expect(download(product: nil)).not_to be_valid
  end

  it "refuses a part number that is a series, not a chip" do
    expect(download(product: series)).not_to be_valid
  end

  # An algorithm runs across chips; requiring a product would either invent an
  # attachment or keep algorithms out of the catalogue.
  it "accepts an algorithm without a part number" do
    expect(download(family: "algorithm", product: nil)).to be_valid
  end

  # A row switched from chip to algorithm after it had a product must not keep
  # it: otherwise a product filter would still draw the algorithm.
  it "clears a part number when the resource is an algorithm" do
    record = download(family: "algorithm", product: chip)

    expect(record).to be_valid
    expect(record.product).to be_nil
  end
end
