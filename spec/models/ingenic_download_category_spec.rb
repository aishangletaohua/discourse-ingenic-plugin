# frozen_string_literal: true

require "rails_helper"

# The classification list, which used to be a constant in the download model and
# now ships as eight seeded rows — sdk, firmware, manual and the rest.
#
# A fixture here therefore names its own rows instead of reusing one of those
# names, and anything asserting on order says which rows it means: the table it
# is reading is never empty on an installed site.
describe IngenicDownloadCategory do
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

  def category(attrs = {})
    IngenicDownloadCategory.create!(
      { name: "sample-#{SecureRandom.hex(4)}", locale: "en" }.merge(attrs),
    )
  end

  it "requires a name" do
    expect(IngenicDownloadCategory.new(name: "", locale: "en")).not_to be_valid
  end

  it "refuses the same name twice in one locale" do
    existing = category

    expect(IngenicDownloadCategory.new(name: existing.name, locale: "en")).not_to be_valid
  end

  it "allows the same name in another locale" do
    existing = category

    expect(IngenicDownloadCategory.new(name: existing.name, locale: "zh_CN")).to be_valid
  end

  # "SDK" and "sdk" are one material type written twice, and a filter that
  # offers both splits a shelf in half. The second spelling is refused.
  it "refuses a name that differs only in case" do
    category(name: "Toolchain Release")

    expect(IngenicDownloadCategory.new(name: "toolchain release", locale: "en")).not_to be_valid
  end

  it "strips surrounding whitespace before comparing" do
    category(name: "SDK Bundle")

    expect(IngenicDownloadCategory.new(name: "  sdk bundle ", locale: "en")).not_to be_valid
  end

  it "orders by position and then by name" do
    second = category(position: 1)
    first = category(position: 0)

    # Scoped to the two rows this example made: the seeded ones sit at positions
    # 0 to 7, so an unscoped read would be asserting on the install as well.
    ordered = described_class.ordered.where(id: [first.id, second.id]).to_a

    expect(ordered).to eq([first, second])
  end

  it "counts the resources filed under it" do
    record = category
    IngenicDownload.create!(
      name: "T33 SDK",
      product: chip,
      category: record,
      locale: "en"
    )

    expect(record.download_count).to eq(1)
  end

  it "leaves a resource unfiled rather than deleting it when the category goes" do
    record = category
    download =
      IngenicDownload.create!(
        name: "T33 SDK",
        product: chip,
        category: record,
        locale: "en"
      )

    record.destroy!

    expect(download.reload.category_id).to be_nil
    expect(download.category_name).to be_nil
  end
end
