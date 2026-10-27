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

  # The picture is drawn straight into an <img>, so the stored value has to be
  # something a browser may fetch: the link the file library returns, or a full
  # address. A bare filename would draw a broken card with no hint why.
  describe "the card's picture link" do
    it "takes the address the file library hands back" do
      expect(download(image_url: "/ingenic/files/cards/t33-sdk.png")).to be_valid
    end

    it "takes a full address" do
      expect(download(image_url: "https://ingenic.com/t33.png")).to be_valid
    end

    it "is optional" do
      expect(download(image_url: nil)).to be_valid
      expect(download(image_url: "")).to be_valid
    end

    it "refuses a bare name" do
      record = download(image_url: "t33-sdk.png")

      expect(record).not_to be_valid
      expect(record.errors[:image_url]).to be_present
    end

    it "refuses a protocol that is not http(s)" do
      expect(download(image_url: "javascript:alert(1)")).not_to be_valid
    end

    # "//example.com/x.png" is an off-site address wearing a path's clothes;
    # only a single leading slash means this site.
    it "refuses a protocol-relative address" do
      expect(download(image_url: "//example.com/x.png")).not_to be_valid
    end
  end

  # The card exists before its first file does: an admin names the resource and
  # uploads a picture, then adds versions. Nothing is listed until one of them
  # is published, because a card with nothing behind it is not a download.
  describe "what makes a resource downloadable" do
    it "is not downloadable with no versions" do
      record = download
      record.save!

      expect(record).not_to be_downloadable
      expect(record.published_versions).to eq([])
    end

    it "is not downloadable while every version is unpublished" do
      record = download
      record.save!
      record.versions.create!(version: "1.0", file_url: "https://example.com/a.tgz", published: false)

      expect(record.reload).not_to be_downloadable
    end

    it "is downloadable once one version is published" do
      record = download
      record.save!
      record.versions.create!(version: "1.0", file_url: "https://example.com/a.tgz")

      expect(record.reload).to be_downloadable
    end

    it "offers its published versions newest-first in their chosen order" do
      record = download
      record.save!
      old = record.versions.create!(version: "1.0", file_url: "https://example.com/a.tgz", position: 1)
      new = record.versions.create!(version: "2.0", file_url: "https://example.com/b.tgz", position: 0)
      hidden =
        record.versions.create!(
          version: "3.0-beta",
          file_url: "https://example.com/c.tgz",
          published: false,
        )

      expect(record.reload.published_versions).to eq([new, old])
      expect(record.versions).to include(hidden)
    end
  end

  it "takes its versions with it when the resource goes" do
    record = download
    record.save!
    record.versions.create!(version: "1.0", file_url: "https://example.com/a.tgz")

    expect { record.destroy! }.to change(IngenicDownloadVersion, :count).by(-1)
  end
end
