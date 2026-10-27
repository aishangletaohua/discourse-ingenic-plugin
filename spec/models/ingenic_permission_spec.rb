# frozen_string_literal: true

require "rails_helper"

# A grant is over one record and one job. The record says what it is; the job
# says which part of that chip's content the holder looks after. The pair is
# what lets T33's documentation belong to one person and its downloads to
# another, so the area has to be both defaulted correctly and checked against
# the record rather than trusted from the caller.
describe IngenicPermission do
  fab!(:user) { Fabricate(:user) }
  fab!(:family) { IngenicProduct.create!(slug: "t-series", name: "T Series") }
  fab!(:product) do
    IngenicProduct.create!(
      slug: "t33",
      name: "T33",
      kind: IngenicProduct::CHIP,
      parent: family,
    )
  end
  fab!(:board) do
    IngenicBoard.create!(slug: "t33-board", name: "T33 Board", kind: "board", product: product)
  end
  fab!(:download) do
    IngenicDownload.create!(
      name: "T33 SDK",
      family: IngenicDownload::FAMILY_CHIP,
      product: product,
      access_level: IngenicDownload::LOGIN_ONLY,
    )
  end

  it "files a product grant under documentation when the caller names no area" do
    permission = described_class.create!(user: user, resource_type: "IngenicProduct", resource_id: product.id)

    expect(permission.area).to eq("documentation")
  end

  it "files a board grant under boards" do
    permission = described_class.create!(user: user, resource_type: "IngenicBoard", resource_id: board.id)

    expect(permission.area).to eq("boards")
  end

  it "files a download grant under downloads" do
    permission = described_class.create!(user: user, resource_type: "IngenicDownload", resource_id: download.id)

    expect(permission.area).to eq("downloads")
  end

  it "refuses a board grant filed under documentation" do
    permission =
      described_class.new(
        user: user,
        resource_type: "IngenicBoard",
        resource_id: board.id,
        area: "documentation",
      )

    expect(permission).not_to be_valid
    expect(permission.errors[:area]).to be_present
  end

  it "lets one chip carry a separate owner in each area" do
    %w[documentation downloads boards].each do |area|
      described_class.create!(
        user: user,
        resource_type: "IngenicProduct",
        resource_id: product.id,
        area: area,
      )
    end

    expect(described_class.where(resource_id: product.id).count).to eq(3)
  end

  it "refuses the same grant twice in one area" do
    described_class.create!(user: user, resource_type: "IngenicProduct", resource_id: product.id, area: "documentation")

    expect do
      described_class.create!(user: user, resource_type: "IngenicProduct", resource_id: product.id, area: "documentation")
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
