# frozen_string_literal: true

require "rails_helper"

describe IngenicPagesController do
  before { SiteSetting.ingenic_enabled = true }

  # The migration seeds the three pages in every language, so the database a
  # test starts from already has rows. Each example writes the copy it is about
  # rather than borrowing whatever the site happened to be installed with.
  before { IngenicSitePage.delete_all }

  let!(:terms) do
    IngenicSitePage.create!(
      slug: "terms",
      locale: "en",
      title: "Terms of Service",
      body: "## Using the forum\n\nBe kind.",
    )
  end

  describe "GET /ingenic/pages/:slug" do
    it "returns the page rendered for the reader" do
      get "/ingenic/pages/terms.json"

      json = response.parsed_body
      expect(response.status).to eq(200)
      expect(json["page"]["title"]).to eq("Terms of Service")
      expect(json["page"]["slug"]).to eq("terms")
      expect(json["page"]["html"]).to include("Using the forum")
    end

    it "serves the app shell to a browser navigation" do
      get "/ingenic/pages/terms"

      expect(response.status).to eq(200)
      expect(response.body).to include('id="data-preloaded"')
    end

    # A footer links to these pages before anyone has opened the management
    # screen. The copy that ships with the plugin is the page until an editor
    # replaces it.
    it "falls back to the shipped copy when no row has been written" do
      terms.destroy!

      get "/ingenic/pages/privacy.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["page"]["title"]).to eq("Privacy Policy")
      expect(response.parsed_body["page"]["html"]).to include("What we collect")
    end

    # Unpublishing has to take the page off the site. Falling back to the
    # shipped copy here would make the switch do nothing.
    it "does not fall back to the shipped copy for an unpublished page" do
      terms.update!(published: false)

      get "/ingenic/pages/terms.json"

      expect(response.status).to eq(404)
    end

    it "404s for a slug it does not have" do
      get "/ingenic/pages/no-such-page.json"

      expect(response.status).to eq(404)
    end
  end

  describe "the reader's language" do
    let!(:chinese_terms) do
      IngenicSitePage.create!(
        slug: "terms",
        locale: "zh_CN",
        title: "用户协议",
        body: "## 使用论坛\n\n友善交流。",
      )
    end

    before do
      SiteSetting.content_localization_enabled = true
      SiteSetting.content_localization_supported_locales = "zh_CN"
    end

    it "answers in the language the address names" do
      get "/ingenic/pages/terms.json?locale=zh_CN"

      expect(response.parsed_body["page"]["title"]).to eq("用户协议")
      expect(response.parsed_body["page"]["html"]).to include("使用论坛")
    end

    # The same address has to be able to answer in either language: the reader
    # switches language without leaving the page, and a cache keyed on the URL
    # must be able to tell the two apart.
    it "answers an unnamed request in the site's language" do
      SiteSetting.default_locale = "zh_CN"

      get "/ingenic/pages/terms.json"

      expect(response.parsed_body["page"]["title"]).to eq("用户协议")
    end

    it "does not fall back across languages when a page is not translated" do
      IngenicSitePage.for_locale("zh_CN").destroy_all

      get "/ingenic/pages/points-rules.json?locale=zh_CN"

      # The shipped copy exists in Chinese, so that is what the reader gets;
      # what must not happen is the English row being served in its place.
      expect(response.parsed_body["page"]["title"]).to eq("积分与权益规则")
    end
  end
end
