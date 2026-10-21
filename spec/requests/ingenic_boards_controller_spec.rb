# frozen_string_literal: true

require "rails_helper"

describe IngenicBoardsController do
  before { SiteSetting.ingenic_enabled = true }

  fab!(:series) do
    IngenicProduct.create!(
      slug: "t-series",
      name: "T Series",
      kind: IngenicProduct::SERIES,
      locale: "en",
      position: 0,
    )
  end

  fab!(:chip) do
    IngenicProduct.create!(
      slug: "t33",
      name: "T33",
      kind: IngenicProduct::CHIP,
      parent: series,
      locale: "en",
      position: 0,
    )
  end

  fab!(:other_series) do
    IngenicProduct.create!(
      slug: "c-series",
      name: "C Series",
      kind: IngenicProduct::SERIES,
      locale: "en",
      position: 1,
    )
  end

  fab!(:other_chip) do
    IngenicProduct.create!(
      slug: "c100",
      name: "C100",
      kind: IngenicProduct::CHIP,
      parent: other_series,
      locale: "en",
      position: 0,
    )
  end

  def board(attrs = {})
    IngenicBoard.create!(
      {
        slug: "halley5",
        name: "Halley5",
        product: chip,
        application_url: "https://example.com/apply",
      }.merge(attrs),
    )
  end

  describe "GET /ingenic/boards" do
    it "lists the published boards with the chip they are for" do
      board(product: chip, specs: "DDR3 1GB")

      get "/ingenic/boards.json"

      entry = response.parsed_body["boards"].first
      expect(entry["slug"]).to eq("halley5")
      expect(entry["kind"]).to eq("board")
      expect(entry["chip_name"]).to eq("T33")
      expect(entry["series_slug"]).to eq("t-series")
      expect(entry["product_slug"]).to eq("t33")
      expect(entry["specs"]).to eq("DDR3 1GB")
    end

    it "sends the sold-out switch and the Markdown description cooked" do
      board(
        product: chip,
        sold_out: true,
        details: "**Halley5** ships with [the docs](/ingenic/docs) and a photo.",
      )

      get "/ingenic/boards.json"

      entry = response.parsed_body["boards"].first
      expect(entry["sold_out"]).to eq(true)
      expect(entry["details_html"]).to include("<strong>Halley5</strong>")
      expect(entry["details_html"]).to include('href="/ingenic/docs"')
    end

    it "offers both kinds and every chip, each naming the series it belongs to" do
      get "/ingenic/boards.json"

      filters = response.parsed_body["filters"]
      expect(filters["kinds"]).to contain_exactly("board", "sample")

      chip_filter = filters["chips"].find { |item| item["slug"] == "c100" }
      expect(chip_filter["series_slug"]).to eq("c-series")
      expect(chip_filter["series_name"]).to eq("C Series")
    end

    it "narrows to one kind" do
      board(product: chip)
      board(slug: "t33-sample", name: "T33 Sample", kind: "sample", product: chip)

      get "/ingenic/boards.json?kind=sample"

      expect(response.parsed_body["boards"].map { |item| item["slug"] }).to eq(["t33-sample"])
    end

    it "ignores an unknown kind rather than showing an empty catalogue" do
      board(product: chip)

      get "/ingenic/boards.json?kind=module"

      expect(response.parsed_body["boards"].map { |item| item["slug"] }).to eq(["halley5"])
    end

    it "narrows to one chip" do
      board(product: chip)
      board(slug: "halley3", name: "Halley3", product: other_chip)

      get "/ingenic/boards.json?chip=c100"

      expect(response.parsed_body["boards"].map { |item| item["slug"] }).to eq(["halley3"])
    end

    it "still offers both kinds while one is filtered, so the choice can be undone" do
      board(product: chip, kind: "sample")

      get "/ingenic/boards.json?kind=sample"

      expect(response.parsed_body["filters"]["kinds"]).to contain_exactly("board", "sample")
    end

    it "leaves a withdrawn board out of the catalogue" do
      board(product: chip, published: false)

      get "/ingenic/boards.json"

      expect(response.parsed_body["boards"]).to be_empty
    end

    # The board's language is its chip's language, so each language has its own
    # catalogue rather than two rows of the same card.
    it "shows only the board filed under the reader's language" do
      board(product: chip, name: "Halley5")
      chinese_series =
        IngenicProduct.create!(
          slug: "t-series",
          name: "T 系列",
          kind: IngenicProduct::SERIES,
          locale: "zh_CN",
        )
      chinese_chip =
        IngenicProduct.create!(
          slug: "t33",
          name: "T33 中文",
          kind: IngenicProduct::CHIP,
          parent: chinese_series,
          locale: "zh_CN",
        )
      board(product: chinese_chip, name: "Halley5 中文", slug: "halley5-cn")

      get "/ingenic/boards.json"

      expect(response.parsed_body["boards"].length).to eq(1)
      expect(response.parsed_body["boards"].first["name"]).to eq("Halley5")

      SiteSetting.default_locale = "zh_CN"

      get "/ingenic/boards.json"

      expect(response.parsed_body["boards"].map { |row| row["name"] }).to eq(["Halley5 中文"])
    end
  end
end
