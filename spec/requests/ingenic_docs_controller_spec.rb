# frozen_string_literal: true

require "rails_helper"

describe IngenicDocsController do
  # The tree is series -> chip -> versions, which is also how the reader's URL
  # is spelled: /ingenic/docs/t-series/t32pro/2.1.0/overview. A version hangs off
  # a chip, so documentation a URL can reach is always filed under one.
  #
  # Positions run oldest first, because that is the order a version inherits
  # from: 2.0.0 is position 0 and the pages its successor did not rewrite are
  # read through it.
  fab!(:series) do
    IngenicProduct.create!(slug: "t-series", name: "T Series", locale: "en", position: 0)
  end

  fab!(:product) do
    IngenicProduct.create!(
      slug: "t32pro",
      name: "T32Pro",
      kind: IngenicProduct::CHIP,
      parent: series,
      position: 0,
    )
  end

  fab!(:latest_version) do
    IngenicDocVersion.create!(
      product: product,
      slug: "2.1.0",
      label: "2.1.0",
      latest: true,
      position: 1,
    )
  end

  fab!(:older_version) do
    IngenicDocVersion.create!(
      product: product,
      slug: "2.0.0",
      label: "2.0.0",
      position: 0,
    )
  end

  fab!(:overview) do
    IngenicDocPage.create!(
      version: latest_version,
      slug: "overview",
      title: "Overview",
      position: 0,
      body: "Chip introduction.",
    )
  end

  fab!(:quick_start) do
    IngenicDocPage.create!(
      version: latest_version,
      slug: "quick-start",
      title: "Quick Start",
      position: 1,
      body: "Build your first image.",
    )
  end

  before { SiteSetting.ingenic_enabled = true }

  describe "GET /ingenic/docs" do
    it "resolves the first published product so navigation can link to one URL" do
      IngenicProduct.create!(
        slug: "x2000",
        name: "X2000",
          position: 1,
      )

      get "/ingenic/docs.json"

      json = response.parsed_body
      expect(response.status).to eq(200)
      expect(json["product"]["slug"]).to eq("t32pro")
      expect(json["version"]["slug"]).to eq("2.1.0")
      expect(json["pages"].map { |page| page["slug"] }).to contain_exactly(
        "overview",
        "quick-start",
      )
    end

    # A series created before anyone writes its first page used to be the place
    # the bare URL landed, because it came first in display order. The reader
    # then saw an empty page with no version dropdown and concluded the
    # documentation was broken. Landing on the first series that has something
    # to read is the difference between "not written yet" and "does not work".
    it "lands on the first series that has documentation, not the first one listed" do
      empty_series =
        IngenicProduct.create!(
          slug: "a-series",
          name: "A Series",
              position: -1,
        )
      IngenicProduct.create!(
        slug: "a1",
        name: "A1",
        kind: IngenicProduct::CHIP,
        parent: empty_series,
        )

      get "/ingenic/docs.json"

      json = response.parsed_body
      expect(json["series_slug"]).to eq("t-series")
      expect(json["chip_slug"]).to eq("t32pro")
      expect(json["versions"].map { |version| version["slug"] }).to contain_exactly(
        "2.0.0",
        "2.1.0",
      )
    end

    it "lands on a chip that has versions when the series has one that does not" do
      IngenicProduct.create!(
        slug: "t31",
        name: "T31",
        kind: IngenicProduct::CHIP,
        parent: series,
          position: -1,
      )

      get "/ingenic/docs.json"

      expect(response.parsed_body["chip_slug"]).to eq("t32pro")
    end

    it "does not serve a chip that has been unpublished" do
      product.update!(published: false)

      get "/ingenic/docs/t-series/t32pro/2.1.0.json"

      expect(response.status).to eq(404)
    end

    it "answers with an empty shelf rather than an error when nothing is published" do
      # The sidebar links here on every page, so a site whose documentation has
      # not been written yet has to render something. An error would make the
      # navigation entry look broken.
      IngenicProduct.update_all(published: false)

      get "/ingenic/docs.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["series"]).to eq([])
      expect(response.parsed_body["version"]).to be_nil
    end
  end

  describe "GET /ingenic/docs/:series/:chip" do
    it "returns the latest version and its page tree" do
      get "/ingenic/docs/t-series/t32pro.json"

      expect(response.status).to eq(200)
      json = response.parsed_body
      expect(json["version"]["slug"]).to eq("2.1.0")
      expect(json["pages"].map { |page| page["slug"] }).to contain_exactly(
        "overview",
        "quick-start",
      )
    end

    it "404s for a series this site does not have" do
      # Not a fallback to the first series: naming one that does not exist is a
      # broken link, and answering it with somebody else's documentation hides
      # the break instead of reporting it.
      get "/ingenic/docs/does-not-exist.json"
      expect(response.status).to eq(404)
    end

    it "404s for a chip that series does not have" do
      get "/ingenic/docs/t-series/does-not-exist.json"
      expect(response.status).to eq(404)
    end
  end

  describe "GET /ingenic/docs/:series/:chip/:version" do
    it "resolves an explicit version" do
      get "/ingenic/docs/t-series/t32pro/2.0.0.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["version"]["slug"]).to eq("2.0.0")
    end

    it "404s for a version the chip does not have" do
      get "/ingenic/docs/t-series/t32pro/9.9.9.json"

      expect(response.status).to eq(404)
    end

    it "treats latest as an alias for the version flagged latest" do
      get "/ingenic/docs/t-series/t32pro/latest.json"
      expect(response.parsed_body["version"]["slug"]).to eq("2.1.0")
    end
  end

  describe "GET /ingenic/docs/:series/:chip/:version/:page" do
    it "returns the page with previous and next navigation" do
      get "/ingenic/docs/t-series/t32pro/2.1.0/overview.json"

      json = response.parsed_body
      expect(json["page"]["slug"]).to eq("overview")
      expect(json["navigation"]["next"]["slug"]).to eq("quick-start")
      expect(json["navigation"]["previous"]).to be_nil
    end

    it "404s for a page that does not exist in that version" do
      get "/ingenic/docs/t-series/t32pro/2.0.0/overview.json"
      expect(response.status).to eq(404)
    end
  end

  describe "unpublished content" do
    it "hides unpublished pages" do
      overview.update!(published: false)

      get "/ingenic/docs/t-series/t32pro/2.1.0/overview.json"

      expect(response.status).to eq(404)
    end
  end

  describe "browser navigation" do
    it "serves the app shell so opening or refreshing the URL does not 404" do
      get "/ingenic/docs/t-series/t32pro/2.1.0/overview"

      expect(response.status).to eq(200)
      expect(response.body).to include('id="data-preloaded"')
    end

    it "serves the app shell for a chip URL with no version or page" do
      get "/ingenic/docs/t-series/t32pro"

      expect(response.status).to eq(200)
      expect(response.body).to include('id="data-preloaded"')
    end

    it "serves the app shell for the bare documentation URL" do
      get "/ingenic/docs"

      expect(response.status).to eq(200)
      expect(response.body).to include('id="data-preloaded"')
    end
  end

  describe "version numbers in the path" do
    # A version slug is a version number. Rails treats the last dot in a path
    # as the start of a format unless the route says otherwise, so a browser
    # fetching /2.1.0 asked for version "2" with format "1.0" and got a 404 —
    # which is every version choice the reader could make.
    it "keeps the dot in the version when the client asks for JSON" do
      get "/ingenic/docs/t-series/t32pro/2.1.0", headers: { "Accept" => "application/json" }

      expect(response.media_type).to eq("application/json")
      expect(response.parsed_body["version"]["slug"]).to eq("2.1.0")
    end

    it "keeps the dot in the version when a page is named too" do
      get "/ingenic/docs/t-series/t32pro/2.1.0/overview",
          headers: { "Accept" => "application/json" }

      expect(response.parsed_body["page"]["slug"]).to eq("overview")
    end

    it "serves the app shell to a browser refresh on a dotted version" do
      get "/ingenic/docs/t-series/t32pro/2.1.0"

      expect(response.status).to eq(200)
      expect(response.body).to include('id="data-preloaded"')
    end
  end

  describe "translated content" do
    # A translation is a second set of product rows, not a second locale column
    # on the same rows. The Chinese chip has its own versions and pages, and
    # nothing in it is reachable through the English one.
    fab!(:chinese_series) do
      IngenicProduct.create!(
        slug: "t-series",
        name: "T 系列",
        kind: IngenicProduct::SERIES,
        locale: "zh_CN",
        position: 0,
      )
    end

    fab!(:chinese_product) do
      IngenicProduct.create!(
        slug: "t32pro",
        name: "T32Pro 中文",
        kind: IngenicProduct::CHIP,
        parent: chinese_series,
        locale: "zh_CN",
        position: 0,
      )
    end

    fab!(:chinese_version) do
      IngenicDocVersion.create!(
        product: chinese_product,
        slug: "2.1.0",
        label: "2.1.0",
        latest: true,
        position: 0,
      )
    end

    fab!(:chinese_overview) do
      IngenicDocPage.create!(
        version: chinese_version,
        slug: "overview",
        title: "概述",
        position: 0,
        body: "芯片介绍。",
      )
    end

    before { SiteSetting.default_locale = "zh_CN" }

    it "serves the reader's language and lists only that language's pages" do
      get "/ingenic/docs/t-series/t32pro/2.1.0/overview.json"

      json = response.parsed_body
      expect(json["page"]["title"]).to eq("概述")
      expect(json["pages"].map { |page| page["slug"] }).to eq(["overview"])
    end

    it "does not fall back to another language for a page with no translation" do
      get "/ingenic/docs/t-series/t32pro/2.1.0/quick-start.json"

      expect(response.status).to eq(404)
    end

    it "does not serve a product filed only under another language" do
      chinese_product.destroy!

      get "/ingenic/docs/t-series/t32pro/2.1.0.json"

      expect(response.status).to eq(404)
    end
  end

  describe "discuss in forum link" do
    it "uses the page's own topic when it has one" do
      overview.update!(topic_url: "/t/overview/12")

      get "/ingenic/docs/t-series/t32pro/2.1.0/overview.json"

      expect(response.parsed_body["page"]["discussion_url"]).to eq("/t/overview/12")
    end

    it "falls back to the configured category" do
      SiteSetting.ingenic_docs_discussion_category = "documentation"

      get "/ingenic/docs/t-series/t32pro/2.1.0/overview.json"

      expect(response.parsed_body["page"]["discussion_url"]).to eq("/c/documentation")
    end

    it "omits the link when neither is available" do
      get "/ingenic/docs/t-series/t32pro/2.1.0/overview.json"

      expect(response.parsed_body["page"]["discussion_url"]).to be_nil
    end
  end
end
