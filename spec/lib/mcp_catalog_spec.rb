# frozen_string_literal: true

require "rails_helper"

describe Ingenic::Mcp::Catalog do
  fab!(:series) do
    IngenicProduct.create!(
      slug: "t-series",
      name: "T Series",
      kind: "series",
      locale: "en"
    )
  end
  fab!(:chip) do
    IngenicProduct.create!(
      slug: "t33",
      name: "T33",
      kind: "chip",
      parent: series,
      locale: "en"
    )
  end
  fab!(:v1) do
    IngenicDocVersion.create!(
      product: chip,
      slug: "1.0",
      label: "1.0",
      position: 0
    )
  end
  fab!(:v2) do
    IngenicDocVersion.create!(
      product: chip,
      slug: "1.1",
      label: "1.1",
      position: 1,
      latest: true
    )
  end

  def page(
    version,
    slug,
    title: slug,
    body: "#{slug} body",
    parent: nil,
    published: true
  )
    IngenicDocPage.create!(
      version: version,
      slug: slug,
      title: title,
      body: body,
      parent: parent,
      published: published
    )
  end

  def catalog(locale: "en")
    described_class.new(locale: locale)
  end

  # The catalogue only answers in a language the site serves; a language turned
  # off in settings falls back to the default, which is what these tests would
  # otherwise be measuring.
  before do
    SiteSetting.content_localization_enabled = true
    SiteSetting.content_localization_supported_locales = "en|zh_CN"
  end

  describe "#catalogue" do
    it "lists published series, their chips and each chip's versions" do
      chip

      entry = catalog.catalogue[:series].first

      expect(entry[:slug]).to eq("t-series")
      expect(entry[:chips].first[:slug]).to eq("t33")
      expect(
        entry[:chips].first[:versions].map { |version| version[:label] }
      ).to eq(%w[1.0 1.1])
      expect(entry[:chips].first[:versions].last[:latest]).to eq(true)
    end

    it "leaves out a chip whose series is not published" do
      chip
      series.update!(published: false)

      expect(catalog.catalogue[:series]).to be_empty
    end

    it "answers from the language it was asked for" do
      chip
      IngenicProduct.create!(
        slug: "c-series",
        name: "C 系列",
        kind: "series",
        locale: "zh_CN"
      )

      expect(catalog.catalogue[:series].map { |entry| entry[:slug] }).to eq(
        ["t-series"]
      )
      expect(
        catalog(locale: "zh_CN").catalogue[:series].map { |entry| entry[:slug] }
      ).to eq(["c-series"])
    end
  end

  describe "#chip_document" do
    it "shows the table of contents at the latest version, inherited pages included" do
      page(v1, "overview", title: "Overview")
      page(v2, "getting-started", title: "Getting started")

      document = catalog.chip_document(chip_slug: "t33")

      expect(document[:version][:slug]).to eq("1.1")
      expect(document[:pages].map { |entry| entry[:slug] }).to eq(
        %w[overview getting-started]
      )
      expect(document[:pages].first[:inherited_from]).to eq("1.0")
      expect(document[:pages].first[:url]).to eq(
        "#{Discourse.base_url}/ingenic/docs/t-series/t33/1.1/overview"
      )
    end

    it "does not show a section whose folder was withdrawn" do
      folder = page(v1, "guides", body: "", published: false)
      page(v1, "flashing", parent: folder)

      expect(catalog.chip_document(chip_slug: "t33")[:pages]).to be_empty
    end

    it "reports a chip that is not in the published catalogue" do
      expect { catalog.chip_document(chip_slug: "nope") }.to raise_error(
        Ingenic::Mcp::NotFound
      ) do |error|
        expect(error.key).to eq(:chip_not_found)
      end
    end
  end

  describe "#page" do
    it "returns the page as markdown with its neighbours and its source version" do
      page(v1, "overview", title: "Overview", body: "# Hello")
      page(v2, "getting-started", title: "Getting started")

      document = catalog.page(chip_slug: "t33", page_slug: "overview")

      expect(document[:page]).to include(
        slug: "overview",
        title: "Overview",
        format: "markdown",
        body: "# Hello",
        truncated: false,
        inherited_from: "1.0"
      )
      expect(document[:next][:slug]).to eq("getting-started")
      expect(document[:url]).to eq(
        "#{Discourse.base_url}/ingenic/docs/t-series/t33/1.1/overview"
      )
    end

    it "refuses a page that is not published" do
      page(v2, "draft", published: false)

      expect {
        catalog.page(chip_slug: "t33", page_slug: "draft")
      }.to raise_error(Ingenic::Mcp::NotFound)
    end

    it "refuses a chip with no documentation at all" do
      bare =
        IngenicProduct.create!(
          slug: "bare",
          name: "Bare",
          kind: "chip",
          parent: series,
          locale: "en"
        )

      expect {
        catalog.page(chip_slug: bare.slug, page_slug: "overview")
      }.to raise_error(Ingenic::Mcp::NotFound) do |error|
        expect(error.key).to eq(:version_not_found)
      end
    end
  end

  describe "#downloads" do
    fab!(:sdk) do
      IngenicDownload.create!(
        name: "T33 SDK",
        product: chip,
        locale: "en",
        access_level: IngenicDownload::APPROVAL_REQUIRED,
        point_cost: 20
      )
    end

    before do
      IngenicDownloadVersion.create!(
        download: sdk,
        version: "2.0",
        description: "Halley5 kernel sources",
        file_url: "https://example.com/sdk.zip",
        published: true
      )
      IngenicDownloadVersion.create!(
        download: sdk,
        version: "2.1",
        file_url: "https://example.com/sdk-2.1.zip",
        published: false
      )
    end

    it "describes what the card offers without handing out the file" do
      entry = catalog.downloads[:downloads].first

      expect(entry).to include(
        name: "T33 SDK",
        access_level: IngenicDownload::APPROVAL_REQUIRED,
        access: "approved application required",
        points: 20
      )
      expect(entry[:chip]).to eq({ slug: "t33", name: "T33" })
      expect(entry[:versions].map { |version| version[:label] }).to eq(["2.0"])
      expect(entry[:versions].first).not_to have_key(:file_url)
      expect(entry.to_s).not_to include("example.com/sdk")
    end

    it "leaves unpublished resources out" do
      sdk.update!(published: false)

      expect(catalog.downloads[:downloads]).to be_empty
    end

    it "answers from the language it was asked for" do
      expect(catalog(locale: "zh_CN").downloads[:downloads]).to be_empty
    end
  end

  describe "#boards" do
    fab!(:board) do
      IngenicBoard.create!(
        slug: "halley-t33",
        name: "Halley T33",
        kind: "board",
        product: chip,
        description: "Reference board",
        specs: "DDR3 128 MB",
        application_url: "https://example.com/apply"
      )
    end

    it "lists published boards with their links" do
      entry = catalog.boards[:boards].first

      expect(entry).to include(
        name: "Halley T33",
        kind: "board",
        description: "Reference board",
        specs: "DDR3 128 MB",
        apply_url: "https://example.com/apply",
        sold_out: false
      )
      expect(entry[:chip]).to eq({ slug: "t33", name: "T33" })
    end

    it "leaves unpublished boards out" do
      board.update!(published: false)

      expect(catalog.boards[:boards]).to be_empty
    end
  end
end
