# frozen_string_literal: true

require "rails_helper"

describe Ingenic::Assistant::Search do
  fab!(:series) do
    IngenicProduct.create!(slug: "t-series", name: "T Series", kind: "series", locale: "en")
  end
  fab!(:chip) do
    IngenicProduct.create!(slug: "t33", name: "T33", kind: "chip", parent: series, locale: "en")
  end
  fab!(:v1) { IngenicDocVersion.create!(product: chip, slug: "1.0", label: "1.0", position: 0) }
  fab!(:v2) { IngenicDocVersion.create!(product: chip, slug: "1.1", label: "1.1", position: 1) }

  def page(version, slug, title: slug, body: "#{slug} body", parent: nil, published: true)
    IngenicDocPage.create!(
      version: version,
      slug: slug,
      title: title,
      body: body,
      parent: parent,
      published: published,
    )
  end

  def search(query, **options)
    described_class.new(query: query, **options).results
  end

  describe "documentation" do
    it "finds a page by its body and links to the newest version that shows it" do
      page(v1, "flash-image", title: "Flashing the image", body: "Use the USB boot tool.")

      result = search("USB boot").first

      expect(result.title).to eq("Flashing the image")
      expect(result.path).to eq("/ingenic/docs/t-series/t33/1.1/flash-image")
      expect(result.kind).to eq(:documentation)
    end

    it "returns an inherited page once, not once per version" do
      page(v1, "flash-image", body: "Use the USB boot tool.")

      expect(search("USB boot").count { |result| result.title == "flash-image" }).to eq(1)
    end

    it "needs every word to match" do
      page(v1, "flash-image", body: "Use the USB boot tool.")

      expect(search("USB ethernet")).to be_empty
    end

    it "does not return an article whose folder was taken down" do
      folder = page(v1, "guides", body: "", published: false)
      page(v1, "flash-image", body: "Use the USB boot tool.", parent: folder)

      expect(search("USB boot")).to be_empty
    end

    it "does not return a chip filed under an unpublished series" do
      series.update!(published: false)
      page(v1, "flash-image", body: "Use the USB boot tool.")

      expect(search("USB boot")).to be_empty
    end

    it "strips markdown out of the excerpt" do
      page(v1, "flash-image", title: "Flashing", body: "## Steps\n\nRun `flash.sh` with **sudo**.")

      expect(search("flash.sh").first.excerpt).to include("Run flash.sh with sudo")
      expect(search("flash.sh").first.excerpt).not_to include("`")
    end

    it "answers from the reader's language" do
      series.update!(locale: "en")
      page(v1, "flash-image", title: "Flashing in English", body: "USB boot")

      zh_series =
        IngenicProduct.create!(slug: "t-series", name: "T 系列", kind: "series", locale: "zh_CN")
      zh_chip =
        IngenicProduct.create!(
          slug: "t33",
          name: "T33",
          kind: "chip",
          parent: zh_series,
          locale: "zh_CN",
        )
      zh_version =
        IngenicDocVersion.create!(product: zh_chip, slug: "1.0", label: "1.0", position: 0)
      page(zh_version, "flash-image", title: "烧录镜像", body: "使用 USB 启动工具")

      titles = search("usb", locale: "zh_CN").map(&:title)

      expect(titles).to include("烧录镜像")
      expect(titles).not_to include("Flashing in English")
    end

    it "falls back to every language when the reader's has nothing" do
      page(v1, "flash-image", title: "Flashing in English", body: "USB boot")

      expect(search("usb", locale: "zh_CN").map(&:title)).to include("Flashing in English")
    end
  end

  describe "downloads" do
    fab!(:sdk) do
      IngenicDownload.create!(
        name: "T33 SDK",
        access_level: IngenicDownload::APPROVAL_REQUIRED,
        family: IngenicDownload::FAMILY_ALGORITHM,
        locale: "en",
      )
    end

    before do
      IngenicDownloadVersion.create!(
        download: sdk,
        version: "2.0",
        description: "Halley5 kernel sources",
        file_url: "https://example.com/sdk.zip",
        published: true,
      )
    end

    it "finds the catalogue entry and says what it takes to download" do
      result = search("T33 SDK").find { |candidate| candidate.kind == :download }

      expect(result.path).to eq("/ingenic/downloads")
      expect(result.excerpt).to include("Halley5 kernel sources")
      expect(result.meta).to include("approved")
    end

    it "can be searched on its own" do
      expect(search("T33", scope: "downloads").map(&:kind).uniq).to eq([:download])
    end
  end

  describe "boards" do
    fab!(:board) do
      IngenicBoard.create!(
        slug: "t33-dev-board",
        name: "T33 Development Board",
        kind: "board",
        product: chip,
        description: "A carrier board with Ethernet and camera interface",
      )
    end

    it "finds a board by what it offers" do
      result = search("camera interface").find { |candidate| candidate.kind == :board }

      expect(result.title).to eq("T33 Development Board")
      expect(result.path).to eq("/ingenic/boards")
    end

    it "leaves unpublished boards out" do
      board.update!(published: false)

      expect(search("camera interface")).to be_empty
    end
  end

  describe "limits" do
    it "ignores a query too short to mean anything" do
      page(v1, "flash-image", body: "USB boot")

      expect(search("u")).to be_empty
    end

    it "returns no more than the limit asked for" do
      3.times { |index| page(v1, "page-#{index}", body: "USB boot #{index}") }

      expect(search("USB boot", limit: 2).size).to eq(2)
    end
  end
end
