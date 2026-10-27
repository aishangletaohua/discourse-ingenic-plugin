# frozen_string_literal: true

require "rails_helper"
require "zip"

describe Admin::IngenicController do
  fab!(:admin) { Fabricate(:admin) }
  fab!(:product) { IngenicProduct.create!(slug: "t-series", name: "T Series", locale: "en") }
  fab!(:chip) do
    IngenicProduct.create!(
      slug: "t33",
      name: "T33",
      kind: IngenicProduct::CHIP,
      parent: product,
      locale: "en",
    )
  end
  fab!(:board) do
    IngenicBoard.create!(slug: "board-one", name: "Board One", product: chip, application_url: "https://example.com")
  end

  before { sign_in(admin) }

  describe "GET /admin/plugins/discourse-ingenic/documentation" do
    it "returns products" do
      get "/admin/plugins/discourse-ingenic/documentation.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["series"].first["slug"]).to eq("t-series")
      # The screen offers a language picker rather than a text box, so the
      # list of languages has to travel with the tree.
      expect(response.parsed_body["locales"]).to be_present
      expect(response.parsed_body["locale"]).to eq("en")
    end
  end

  describe "PUT /admin/plugins/discourse-ingenic/documentation/products/:id" do
    it "renames a row in place" do
      put "/admin/plugins/discourse-ingenic/documentation/products/#{product.id}.json",
          params: { name: "T 系列", slug: "t-series", published: false }

      expect(response.status).to eq(200)
      expect(product.reload).to have_attributes(
        name: "T 系列",
        slug: "t-series",
        locale: "en",
        published: false,
      )
    end

    # A row's language is what everything under it was written in. Moving the
    # row would either move that content into a language nobody wrote it in or
    # strand it, so the edit is refused and the other language is built by
    # creating its own rows.
    it "refuses to move a row to another language" do
      put "/admin/plugins/discourse-ingenic/documentation/products/#{product.id}.json",
          params: { name: "T 系列", locale: "zh_CN" }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"].first).to eq(
        I18n.t("ingenic.admin_errors.locale_immutable"),
      )
      expect(product.reload.locale).to eq("en")
      expect(product.name).to eq("T Series")
    end
  end

  describe "POST /admin/plugins/discourse-ingenic/documentation/products" do
    it "creates a product" do
      expect {
        post "/admin/plugins/discourse-ingenic/documentation/products.json",
             params: { slug: "c-series", name: "C Series", locale: "en" }
      }.to change(IngenicProduct, :count).by(1)

      expect(response.status).to eq(200)
    end
  end

  describe "POST /admin/plugins/discourse-ingenic/documentation/versions" do

    # A version has no `published` column, and `published` is what every other
    # form in this controller sends. Permitting it made the request raise
    # `UnknownAttributeError` — a 500 where a row should have been written — so
    # the parameter list is the thing under test, not the version.
    it "creates a version even when the request carries a published flag" do
      expect {
        post "/admin/plugins/discourse-ingenic/documentation/versions.json",
             params: {
               product_id: chip.id,
               slug: "v1",
               label: "v1.0",
               published: true,
             }
      }.to change(IngenicDocVersion, :count).by(1)

      expect(response.status).to eq(200)
    end
  end

  # The page tree distinguishes folders from articles and files a child by id.
  # A parent typed as a slug used to produce a top-level page when the slug
  # matched nothing, which read as "the folder would not take".
  describe "POST /admin/plugins/discourse-ingenic/documentation/pages" do
    fab!(:version) do
      IngenicDocVersion.create!(product: chip, slug: "v1", label: "v1.0", position: 0)
    end

    it "creates a folder and returns its kind" do
      post "/admin/plugins/discourse-ingenic/documentation/pages.json",
           params: {
             version_id: version.id,
             slug: "guide",
             title: "Guide",
             kind: "folder",
             body: "ignored",
           }

      expect(response.status).to eq(200)
      expect(response.parsed_body["page"]["kind"]).to eq("folder")

      folder = IngenicDocPage.find_by!(version: version, slug: "guide")
      expect(folder).to be_folder
      expect(folder.body).to be_nil
    end

    it "files a page under the folder named by parent_id and appends it" do
      folder =
        IngenicDocPage.create!(
          version: version,
          slug: "guide",
          title: "Guide",
          kind: "folder",
          position: 0,
        )

      post "/admin/plugins/discourse-ingenic/documentation/pages.json",
           params: {
             version_id: version.id,
             parent_id: folder.id,
             slug: "setup",
             title: "Setup",
             kind: "page",
           }

      expect(response.status).to eq(200)
      page = IngenicDocPage.find_by!(version: version, slug: "setup")
      expect(page.parent_id).to eq(folder.id)
      expect(page.position).to eq(0)
    end
  end

  # The preview has to be the server's own rendering, not the browser's: a page
  # previewed by a different Markdown implementation would agree with the
  # editor and disagree with the published article.
  describe "POST /admin/plugins/discourse-ingenic/documentation/preview" do
    fab!(:version) do
      IngenicDocVersion.create!(product: chip, slug: "v1", label: "v1.0", position: 0)
    end

    it "cooks the body with the public page pipeline" do
      post "/admin/plugins/discourse-ingenic/documentation/preview.json",
           params: { version_id: version.id, body: "# Title\n\n**bold**" }

      expect(response.status).to eq(200)
      html = response.parsed_body["html"]
      expect(html).to include("<h1")
      expect(html).to include("<strong>bold</strong>")
    end
  end

  # Importing turns a manual a team already has as files into pages. One file is
  # one page — a heading is not a reliable unit, and neither is a Word section —
  # so what is pinned down here is that shape, the heading becoming the title,
  # and a bad file being reported without discarding the good ones beside it.
  describe "POST /admin/plugins/discourse-ingenic/documentation/versions/:id/import" do
    fab!(:version) do
      IngenicDocVersion.create!(product: chip, slug: "v1", label: "v1.0", position: 0)
    end

    def uploaded(name, content, type)
      Rack::Test::UploadedFile.new(StringIO.new(content), type, original_filename: name)
    end

    def words(text)
      "<w:p><w:r><w:t>#{text}</w:t></w:r></w:p>"
    end

    def docx(*body)
      Zip::OutputStream.write_buffer do |zip|
        zip.put_next_entry("word/document.xml")
        zip.write(<<~XML)
          <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
          <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
            <w:body>#{body.join}</w:body>
          </w:document>
        XML
      end.string
    end

    it "stores a Markdown file as a page and takes its first heading as the title" do
      markdown = "# Getting Started\n\nBuild the firmware with `make`.\n"

      post "/admin/plugins/discourse-ingenic/documentation/versions/#{version.id}/import.json",
           params: { files: [uploaded("getting-started.md", markdown, "text/markdown")] }

      expect(response.status).to eq(200)
      page = IngenicDocPage.find_by!(version: version, slug: "getting-started")
      expect(page.title).to eq("Getting Started")
      expect(page.body).to eq("Build the firmware with `make`.")
      expect(page.locale).to eq("en")
      expect(page.published).to eq(true)
      expect(response.parsed_body["errors"]).to eq([])
    end

    it "converts a Word file to Markdown and reports a file it cannot read" do
      document =
        docx(
          "<w:p><w:pPr><w:pStyle w:val=\"Title\"/></w:pPr><w:r><w:t>Flash Guide</w:t></w:r></w:p>",
          "<w:p><w:r><w:rPr><w:b/></w:rPr><w:t>Erase</w:t></w:r><w:r><w:t> the chip first.</w:t></w:r></w:p>",
          "<w:p><w:pPr><w:numPr/></w:pPr><w:r><w:t>Connect USB</w:t></w:r></w:p>",
          <<~TABLE,
            <w:tbl>
              <w:tr><w:tc>#{words("Pin")}</w:tc><w:tc>#{words("Signal")}</w:tc></w:tr>
              <w:tr><w:tc>#{words("1")}</w:tc><w:tc>#{words("VDD")}</w:tc></w:tr>
            </w:tbl>
          TABLE
        )

      post "/admin/plugins/discourse-ingenic/documentation/versions/#{version.id}/import.json",
           params: {
             files: [
               uploaded("flash-guide.docx", document, "application/vnd.openxmlformats-officedocument.wordprocessingml.document"),
               uploaded("manual.pdf", "%PDF-1.4", "application/pdf"),
             ],
           }

      expect(response.status).to eq(200)
      expect(response.parsed_body["imported"].length).to eq(1)
      expect(response.parsed_body["errors"].first["file"]).to eq("manual.pdf")

      page = IngenicDocPage.find_by!(version: version, slug: "flash-guide")
      expect(page.title).to eq("Flash Guide")
      expect(page.body).to include("**Erase** the chip first.")
      expect(page.body).to include("- Connect USB")
      expect(page.body).to include("| Pin | Signal |")
      expect(page.body).to include("| --- | --- |")
    end

    it "keeps the slug unique when two files would claim the same one" do
      2.times do
        post "/admin/plugins/discourse-ingenic/documentation/versions/#{version.id}/import.json",
             params: { files: [uploaded("overview.md", "# Overview\n\nText.", "text/markdown")] }
      end

      expect(IngenicDocPage.where(version: version).pluck(:slug)).to contain_exactly(
        "overview",
        "overview-2",
      )
    end
  end

  describe "GET /admin/plugins/discourse-ingenic/boards" do
    it "offers the chips a board can be filed against, with their series" do
      chip

      get "/admin/plugins/discourse-ingenic/boards.json"

      expect(response.status).to eq(200)
      option = response.parsed_body["chips"].first
      expect(option["slug"]).to eq("t33")
      expect(option["series_name"]).to eq("T Series")
    end

    it "offers a boards manager only the chips they may file a board under" do
      chip
      other_series = IngenicProduct.create!(slug: "c-series", name: "C Series", locale: "en")
      IngenicProduct.create!(
        slug: "c100",
        name: "C100",
        kind: IngenicProduct::CHIP,
        parent: other_series,
        locale: "en",
      )
      manager = Fabricate(:user)
      IngenicPermission.create!(
        user: manager,
        resource_type: "IngenicProduct",
        resource_id: product.id,
        area: "boards",
      )
      sign_in(manager)

      get "/admin/plugins/discourse-ingenic/boards.json"

      expect(response.status).to eq(200)
      # The other chip is still a real chip, and the server would refuse a board
      # on it; the picker should not offer a choice that cannot be saved.
      expect(response.parsed_body["chips"].pluck("id")).to contain_exactly(chip.id)
    end
  end

  describe "PUT /admin/plugins/discourse-ingenic/boards/:id" do
    it "updates a board" do
      put "/admin/plugins/discourse-ingenic/boards/#{board.id}.json",
          params: { name: "Updated Board" }

      expect(response.status).to eq(200)
      expect(board.reload.name).to eq("Updated Board")
    end

    it "turns the sold-out switch on without touching the links" do
      put "/admin/plugins/discourse-ingenic/boards/#{board.id}.json",
          params: {
            sold_out: "true",
          }

      expect(response.status).to eq(200)
      expect(response.parsed_body["board"]["sold_out"]).to eq(true)
      expect(board.reload.sold_out).to eq(true)
      expect(board.reload.application_url).to eq("https://example.com")
    end

    it "files the board against a chip and reads the name back from the tree" do
      second_chip =
        IngenicProduct.create!(
          slug: "t32",
          name: "T32",
          kind: IngenicProduct::CHIP,
          parent: product,
          locale: "en",
        )

      put "/admin/plugins/discourse-ingenic/boards/#{board.id}.json",
          params: {
            product_id: second_chip.id,
          }

      expect(response.status).to eq(200)
      expect(response.parsed_body["board"]["chip_name"]).to eq("T32")
      expect(response.parsed_body["board"]["series_name"]).to eq("T Series")
      expect(board.reload.product).to eq(second_chip)
    end

    # A board is a card for one product; clearing the picker would leave it
    # with nothing to be listed under, so the blank option is refused rather
    # than saved as null.
    it "refuses to unfile the board when the chip picker is cleared" do
      put "/admin/plugins/discourse-ingenic/boards/#{board.id}.json",
          params: {
            product_id: "",
          }

      expect(response.status).to eq(422)
      expect(board.reload.product).to eq(chip)
    end
  end

  describe "GET /admin/plugins/discourse-ingenic/permissions" do
    it "is restricted to admins" do
      get "/admin/plugins/discourse-ingenic/permissions.json"

      expect(response.status).to eq(200)
    end

    it "returns both matrices and the scope grants in one payload" do
      custom = Fabricate(:group)
      account = Fabricate(:user, username: "chip_owner")
      IngenicFeaturePermission.create!(group: custom, feature: "downloads")
      IngenicFeaturePermission.create!(user: account, feature: "boards")

      get "/admin/plugins/discourse-ingenic/permissions.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["features"]).to eq(IngenicFeaturePermission::FEATURES)

      group_row =
        response.parsed_body["groups"].find { |group| group["id"] == custom.id }
      account_row =
        response.parsed_body["users"].find { |user| user["id"] == account.id }

      expect(group_row["features"]).to eq(["downloads"])
      expect(account_row["features"]).to eq(["boards"])
      expect(response.parsed_body["groups"].map { |group| group["name"] })
        .not_to include("everyone")
    end

    it "is not offered to a member" do
      sign_in(Fabricate(:user))

      get "/admin/plugins/discourse-ingenic/permissions.json"

      expect(response.status).to eq(404)
    end
  end

  # The admin-editable lists. Each one is a table the screens read and write, so
  # an edit that renders "Saved." over an unchanged row is the failure these
  # cover.
  describe "GET /admin/plugins/discourse-ingenic/site" do
    it "returns every list the site screen draws" do
      IngenicPromotion.create!(title: "Spring campaign", locale: "en")
      IngenicSocialLink.create!(label: "GitHub", kind: IngenicSocialLink::LINK, href: "https://github.com")
      IngenicHeaderLink.create!(label: "Ingenic", href: "https://www.ingenic.com")
      IngenicSectionCard.create!(label: "Docs", href: "/ingenic/docs")
      column = IngenicFooterColumn.create!(title: "Developers")
      IngenicFooterLink.create!(column: column, label: "Downloads", href: "/ingenic/downloads")

      get "/admin/plugins/discourse-ingenic/site.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["promotions"].first["title"]).to eq("Spring campaign")
      expect(response.parsed_body["social_links"].first["label"]).to eq("GitHub")
      expect(response.parsed_body["header_links"].first["label"]).to eq("Ingenic")
      expect(response.parsed_body["section_cards"].first["label"]).to eq("Docs")
      column_json = response.parsed_body["footer_columns"].first
      expect(column_json["title"]).to eq("Developers")
      expect(column_json["links"].first["label"]).to eq("Downloads")
      expect(response.parsed_body["homepage_blocks"]).to eq([])
    end
  end

  describe "PUT /admin/plugins/discourse-ingenic/homepage-blocks" do
    it "saves the list in the order it was sent" do
      blocks = [
        { type: "categories", limit: 3, categories: "engineering, announcements" },
        { type: "latest", limit: 8, layout: "main" },
        { type: "hot", limit: 5, layout: "side" },
      ]

      put "/admin/plugins/discourse-ingenic/homepage-blocks.json", params: { blocks: blocks.to_json }

      expect(response.status).to eq(200)
      saved = DiscourseIngenic::ConfigParser.homepage_blocks
      expect(saved.map { |block| block["type"] }).to eq(%w[categories latest hot])
      expect(saved.map { |block| block["position"] }).to eq([0, 1, 2])
      expect(saved.first["categories"]).to eq(%w[engineering announcements])
      expect(saved.last["layout"]).to eq("side")
    end

    it "refuses a type the home page cannot draw, and writes nothing" do
      put "/admin/plugins/discourse-ingenic/homepage-blocks.json",
          params: { blocks: [{ type: "latest" }, { type: "weather" }].to_json }

      expect(response.status).to eq(422)
      expect(SiteSetting.ingenic_homepage_blocks).to eq("")
    end

    it "refuses a body that is not a list" do
      put "/admin/plugins/discourse-ingenic/homepage-blocks.json", params: { blocks: "not json" }

      expect(response.status).to eq(422)
      expect(SiteSetting.ingenic_homepage_blocks).to eq("")
    end
  end

  describe "PUT /admin/plugins/discourse-ingenic/promotions/:id" do
    it "persists the form and reports whether the slot is showing" do
      promotion = IngenicPromotion.create!(title: "Old headline", locale: "en")

      put "/admin/plugins/discourse-ingenic/promotions/#{promotion.id}.json",
          params: { title: "New headline", published: "true" }

      expect(response.status).to eq(200)
      expect(promotion.reload.title).to eq("New headline")
      expect(response.parsed_body["promotion"]["live"]).to eq(true)
    end

    it "clears a date the editor emptied rather than storing a blank string" do
      promotion =
        IngenicPromotion.create!(title: "Timed", locale: "en", starts_at: 1.day.from_now)

      put "/admin/plugins/discourse-ingenic/promotions/#{promotion.id}.json",
          params: { title: "Timed", starts_at: "" }

      expect(response.status).to eq(200)
      expect(promotion.reload.starts_at).to be_nil
    end
  end

  describe "DELETE /admin/plugins/discourse-ingenic/promotions/:id" do
    it "removes the slot" do
      promotion = IngenicPromotion.create!(title: "Old campaign", locale: "en")

      expect {
        delete "/admin/plugins/discourse-ingenic/promotions/#{promotion.id}.json"
      }.to change(IngenicPromotion, :count).by(-1)

      expect(response.status).to eq(204)
    end
  end

  describe "PUT /admin/plugins/discourse-ingenic/social-links/:id" do
    it "moves a platform from a QR code to a link" do
      # A QR entry needs its code; a link entry needs an address. Switching kinds
      # therefore has to arrive with the address in the same request.
      record =
        IngenicSocialLink.create!(
          label: "WeChat",
          kind: IngenicSocialLink::QR,
          qr_image_url: "/uploads/wechat.png",
        )

      put "/admin/plugins/discourse-ingenic/social-links/#{record.id}.json",
          params: { kind: IngenicSocialLink::LINK, href: "https://wechat.example.com" }

      expect(response.status).to eq(200)
      expect(record.reload.kind).to eq(IngenicSocialLink::LINK)
      expect(record.href).to eq("https://wechat.example.com")
    end
  end

  describe "POST /admin/plugins/discourse-ingenic/header-links" do
    it "creates a header button and reports it back" do
      expect {
        post "/admin/plugins/discourse-ingenic/header-links.json",
             params: { label: "GitHub", href: "https://github.com", icon: "fab-github" }
      }.to change(IngenicHeaderLink, :count).by(1)

      expect(response.status).to eq(200)
      expect(response.parsed_body["header_link"]["label"]).to eq("GitHub")
    end

    it "refuses an icon-only button with nothing to draw" do
      post "/admin/plugins/discourse-ingenic/header-links.json",
           params: { label: "GitHub", href: "https://github.com", show_label: "false" }

      expect(response.status).to eq(422)
      expect(IngenicHeaderLink.count).to eq(0)
    end
  end

  describe "DELETE /admin/plugins/discourse-ingenic/header-links/:id" do
    it "removes the button" do
      record = IngenicHeaderLink.create!(label: "GitHub", href: "https://github.com")

      expect {
        delete "/admin/plugins/discourse-ingenic/header-links/#{record.id}.json"
      }.to change(IngenicHeaderLink, :count).by(-1)

      expect(response.status).to eq(204)
    end
  end

  describe "POST /admin/plugins/discourse-ingenic/section-cards" do
    it "creates a card that points somewhere other than a category" do
      expect {
        post "/admin/plugins/discourse-ingenic/section-cards.json",
             params: { label: "Docs", href: "/ingenic/docs", icon: "book" }
      }.to change(IngenicSectionCard, :count).by(1)

      expect(response.status).to eq(200)
      expect(response.parsed_body["section_card"]["href"]).to eq("/ingenic/docs")
    end

    it "refuses a card with nowhere to go" do
      post "/admin/plugins/discourse-ingenic/section-cards.json",
           params: { label: "Docs" }

      expect(response.status).to eq(422)
      expect(IngenicSectionCard.count).to eq(0)
    end
  end

  describe "POST /admin/plugins/discourse-ingenic/footer-links" do
    it "files a link under the column it was added to" do
      column = IngenicFooterColumn.create!(title: "Company")

      expect {
        post "/admin/plugins/discourse-ingenic/footer-links.json",
             params: { column_id: column.id, label: "About", href: "/about" }
      }.to change(IngenicFooterLink, :count).by(1)

      expect(response.status).to eq(200)
      expect(response.parsed_body["footer_link"]["column_id"]).to eq(column.id)
    end
  end

  describe "site pages" do
    it "creates a page in the language the screen is working in" do
      expect {
        post "/admin/plugins/discourse-ingenic/site-pages.json",
             params: { slug: "cookies", title: "Cookies", body: "What we store." }
      }.to change(IngenicSitePage, :count).by(1)

      expect(response.status).to eq(200)
      expect(response.parsed_body["site_page"]).to include(
        "slug" => "cookies",
        "locale" => "en",
        "title" => "Cookies",
      )
    end

    it "edits the body and takes the page off the site without deleting it" do
      record =
        IngenicSitePage.create!(slug: "cookies", locale: "en", title: "Cookies", body: "Old.")

      put "/admin/plugins/discourse-ingenic/site-pages/#{record.id}.json",
          params: { title: "Cookies and storage", body: "New.", published: false }

      expect(response.status).to eq(200)
      expect(record.reload).to have_attributes(
        title: "Cookies and storage",
        body: "New.",
        published: false,
      )
    end

    it "refuses a page whose address is already taken in that language" do
      IngenicSitePage.create!(slug: "cookies", locale: "en", title: "Cookies")

      post "/admin/plugins/discourse-ingenic/site-pages.json",
           params: { slug: "cookies", title: "Another cookies page" }

      expect(response.status).to eq(422)
      expect(IngenicSitePage.where(slug: "cookies").count).to eq(1)
    end

    it "lists the pages with the rest of the site content" do
      IngenicSitePage.create!(slug: "cookies", locale: "en", title: "Cookies")

      get "/admin/plugins/discourse-ingenic/site.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["site_pages"].map { |page| page["slug"] }).to include("cookies")
    end

    it "removes a page" do
      record = IngenicSitePage.create!(slug: "cookies", locale: "en", title: "Cookies")

      expect {
        delete "/admin/plugins/discourse-ingenic/site-pages/#{record.id}.json"
      }.to change(IngenicSitePage, :count).by(-1)

      expect(response.status).to eq(204)
    end

    it "refuses a member without the site-content permission" do
      sign_in(Fabricate(:user))

      post "/admin/plugins/discourse-ingenic/site-pages.json",
           params: { slug: "cookies", title: "Cookies" }

      expect(response.status).to eq(404)
      expect(IngenicSitePage.where(slug: "cookies").count).to eq(0)
    end
  end

  describe "DELETE /admin/plugins/discourse-ingenic/footer-columns/:id" do
    it "takes the column's links with it" do
      column = IngenicFooterColumn.create!(title: "Company")
      IngenicFooterLink.create!(column: column, label: "About", href: "/about")

      expect {
        delete "/admin/plugins/discourse-ingenic/footer-columns/#{column.id}.json"
      }.to change(IngenicFooterLink, :count).by(-1)

      expect(response.status).to eq(204)
    end
  end

  describe "PUT /admin/plugins/discourse-ingenic/download-categories/:id" do
    it "renames a category" do
      category = IngenicDownloadCategory.create!(name: "Toolchain Release", locale: "en")

      put "/admin/plugins/discourse-ingenic/download-categories/#{category.id}.json",
          params: { name: "Software development kits" }

      expect(response.status).to eq(200)
      expect(category.reload.name).to eq("Software development kits")
    end
  end

  describe "DELETE /admin/plugins/discourse-ingenic/download-categories/:id" do
    it "leaves the resources filed under it in place, unfiled" do
      category = IngenicDownloadCategory.create!(name: "Toolchain Release", locale: "en")
      download =
        IngenicDownload.create!(
          name: "T33 SDK",
          product: chip,
          locale: "en",
          category: category
        )

      delete "/admin/plugins/discourse-ingenic/download-categories/#{category.id}.json"

      expect(response.status).to eq(204)
      expect(download.reload.category_id).to be_nil
    end
  end

  describe "GET /admin/plugins/discourse-ingenic/download-logs" do
    it "lists what was taken, newest first" do
      download = IngenicDownload.create!(
        name: "T33 SDK",
        product: chip,
        locale: "en"
      )
      IngenicDownloadLog.create!(user: admin, download: download, resource_name: download.name)

      get "/admin/plugins/discourse-ingenic/download-logs.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["logs"].first["resource_name"]).to eq("T33 SDK")
      expect(response.parsed_body["total"]).to eq(1)
    end

    it "is closed to a scoped content manager" do
      # The log names accounts, so it is an administrator's even though the rest
      # of the downloads page is not.
      sign_in(Fabricate(:moderator))

      get "/admin/plugins/discourse-ingenic/download-logs.json"

      expect(response.status).to eq(404)
    end
  end

  # An application outlives the account that made it: deleting a member blanks
  # the applicant on their rows rather than taking the rows with them, and the
  # queue then has a row with nobody to name. Two things have to hold — the
  # screen still draws, and access cannot be granted to an account that is not
  # there.
  describe "the access queue, with an applicant who has been deleted" do
    fab!(:applicant) { Fabricate(:user) }
    fab!(:gated_download) do
      IngenicDownload.create!(
        name: "T33 SDK",
        product: chip,
        locale: "en",
        access_level: IngenicDownload::APPROVAL_REQUIRED
      )
    end
    fab!(:application) do
      IngenicDownloadRequest.create!(user: applicant, download: gated_download, message: "Board bring-up")
    end

    before do
      # What the nullifying foreign key does to the row when the account is
      # destroyed.
      IngenicDownloadRequest.where(id: application.id).update_all(user_id: nil)
      application.reload
    end

    it "lists the application without a name instead of failing" do
      get "/admin/plugins/discourse-ingenic/download-requests.json"

      expect(response.status).to eq(200)
      row = response.parsed_body["requests"].first
      expect(row["id"]).to eq(application.id)
      expect(row["username"]).to be_nil
      expect(row["message"]).to eq("Board bring-up")
    end

    it "refuses to approve it, because there is no account to let in" do
      put "/admin/plugins/discourse-ingenic/download-requests/#{application.id}/approve.json"

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"].first).to eq(
        I18n.t("ingenic.admin_errors.applicant_deleted"),
      )
      expect(IngenicDownloadGrant.count).to eq(0)
      expect(application.reload.status).to eq(IngenicDownloadRequest::PENDING)
    end

    it "still records a decision to decline it" do
      put "/admin/plugins/discourse-ingenic/download-requests/#{application.id}/reject.json",
          params: { note: "no account" }

      expect(response.status).to eq(200)
      expect(application.reload.status).to eq(IngenicDownloadRequest::REJECTED)
    end
  end

  describe "GET /admin/plugins/discourse-ingenic/downloads" do
    it "offers the record tab to an administrator" do
      get "/admin/plugins/discourse-ingenic/downloads.json"

      expect(response.parsed_body["can_read_log"]).to eq(true)
    end

    it "tells a scoped content manager not to offer the record tab" do
      # A scoped manager reaches the page — the route admits anyone who manages
      # something, and the log is not something they manage. The flag is what the
      # page reads before it draws the tab, so a manager is never offered a tab
      # whose request would be refused.
      manager = Fabricate(:user)
      download = IngenicDownload.create!(
        name: "T33 SDK",
        product: chip,
        locale: "en"
      )
      IngenicPermission.create!(
        user: manager,
        resource_type: "IngenicDownload",
        resource_id: download.id,
      )
      sign_in(manager)

      get "/admin/plugins/discourse-ingenic/downloads.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["downloads"].map { |row| row["id"] }).to eq([download.id])
      expect(response.parsed_body["can_read_log"]).to eq(false)
    end
  end

  describe "the card and its versions" do
    def create_resource(**attrs)
      post "/admin/plugins/discourse-ingenic/downloads.json",
           params: {
             name: "T33 SDK",
             family: "chip",
             product_id: chip.id,
             access_level: IngenicDownload::LOGIN_ONLY,
           }.merge(attrs)
      response.parsed_body["download"]
    end

    def add_version(download, **attrs)
      post "/admin/plugins/discourse-ingenic/downloads/#{download["id"]}/versions.json",
           params: {
             version: "1.0",
             file_url: "https://example.com/sdk.tgz",
           }.merge(attrs)
    end

    it "creates a card before it has a file, and says it has no versions" do
      download = create_resource

      expect(response.status).to eq(200)
      expect(download["name"]).to eq("T33 SDK")
      expect(download["versions"]).to eq([])
      expect(download["image_url"]).to be_nil
    end

    it "adds a version under the card, with what that release says about itself" do
      download = create_resource

      add_version(
        download,
        version: "2.0",
        description: "Adds the new ISP and a smaller boot image.",
        platform: "Linux",
        architecture: "mips",
        file_size: "1.2 GB",
        released_on: "2026-06-01",
      )

      expect(response.status).to eq(200)
      version = response.parsed_body["version"]
      expect(version["version"]).to eq("2.0")
      expect(version["description"]).to include("new ISP")
      expect(version["platform"]).to eq("Linux")
      expect(version["released_on"]).to eq("2026-06-01")
      expect(response.parsed_body["download"]["versions"].map { |row| row["version"] }).to eq(["2.0"])
    end

    it "refuses a second version with the same label on one card" do
      download = create_resource
      add_version(download)

      add_version(download)

      expect(response.status).to eq(422)
    end

    it "changes the description the card shows for one version" do
      download = create_resource
      add_version(download, version: "1.0", description: "First cut.")
      version = IngenicDownloadVersion.find(response.parsed_body["version"]["id"])

      put "/admin/plugins/discourse-ingenic/downloads/#{download["id"]}/versions/#{version.id}.json",
          params: {
            description: "First cut, rebuilt with a newer toolchain.",
            published: false,
          }

      expect(response.status).to eq(200)
      version.reload
      expect(version.description).to include("newer toolchain")
      expect(version.published).to eq(false)
    end

    it "removes a version and the file it kept" do
      directory = Dir.mktmpdir("ingenic-version")
      SiteSetting.ingenic_download_storage_path = directory
      stored = Ingenic::DownloadStorage.store(
        ActionDispatch::Http::UploadedFile.new(
          tempfile: Tempfile.new("sdk").tap do |file|
            file.binmode
            file.write("firmware")
            file.rewind
          end,
          filename: "sdk.bin",
        ),
      )
      download = create_resource
      version =
        IngenicDownloadVersion.create!(
          download_id: download["id"],
          version: "1.0",
          storage_path: stored[:path],
          original_filename: "sdk.bin",
        )
      path = Pathname.new(directory).join(version.storage_path)
      expect(path).to exist

      delete "/admin/plugins/discourse-ingenic/downloads/#{download["id"]}/versions/#{version.id}.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["download"]["versions"]).to eq([])
      expect(path).not_to exist
    ensure
      FileUtils.remove_entry(directory) if directory && File.exist?(directory)
    end

    it "will not reach a version through another card" do
      mine = create_resource(name: "Mine")
      theirs = create_resource(name: "Theirs")
      add_version(theirs)
      version = IngenicDownloadVersion.find(response.parsed_body["version"]["id"])

      put "/admin/plugins/discourse-ingenic/downloads/#{mine["id"]}/versions/#{version.id}.json",
          params: {
            description: "borrowed",
          }

      expect(response.status).to eq(404)
      expect(version.reload.description).to be_nil
    end

    it "puts the link an operator pasted on the card" do
      download = create_resource(image_url: "/ingenic/files/cards/t33-sdk.png")

      expect(response.status).to eq(200)
      expect(download["image_url"]).to eq("/ingenic/files/cards/t33-sdk.png")
    end

    it "keeps a full address as given, and trims the field" do
      download = create_resource(image_url: "  https://ingenic.com/t33.png  ")

      expect(response.status).to eq(200)
      expect(download["image_url"]).to eq("https://ingenic.com/t33.png")
    end

    it "refuses a value that is not an address" do
      create_resource(image_url: "t33-sdk.png")

      expect(response.status).to eq(422)
      expect(IngenicDownload.find_by(name: "T33 SDK")).to be_nil
    end

    it "takes the picture off when the field is cleared" do
      download = create_resource(image_url: "/ingenic/files/cards/t33-sdk.png")

      put "/admin/plugins/discourse-ingenic/downloads/#{download["id"]}.json",
          params: {
            image_url: "",
          }

      expect(response.status).to eq(200)
      expect(response.parsed_body["download"]["image_url"]).to be_nil
    end
  end

  # Each listing used to answer every signed-in manager with whatever their
  # grants happened to filter to. An empty 200 still carried the parts of the
  # screen that are not records — the chip picker, the categories — and it made
  # "this manager may not see this screen" indistinguishable from "there is
  # nothing on it yet".
  describe "a listing outside a manager's screen" do
    fab!(:manager) { Fabricate(:user) }

    before do
      IngenicFeaturePermission.create!(user: manager, feature: "downloads")
      sign_in(manager)
    end

    it "refuses the documentation listing" do
      get "/admin/plugins/discourse-ingenic/documentation.json"

      expect(response.status).to eq(404)
    end

    it "refuses the boards listing" do
      get "/admin/plugins/discourse-ingenic/boards.json"

      expect(response.status).to eq(404)
    end

    it "answers the downloads listing, which is the screen they hold" do
      get "/admin/plugins/discourse-ingenic/downloads.json"

      expect(response.status).to eq(200)
    end
  end

  describe "a listing a manager reaches through one record" do
    fab!(:manager) { Fabricate(:user) }

    before do
      IngenicPermission.create!(
        user: manager,
        resource_type: "IngenicProduct",
        resource_id: chip.id,
        area: IngenicPermission::DOCUMENTATION,
      )
      sign_in(manager)
    end

    it "opens the documentation listing scoped to that chip" do
      get "/admin/plugins/discourse-ingenic/documentation.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["series"].map { |row| row["slug"] }).to eq(["t-series"])
    end
  end

  # The two new screens. Both decide who may do something, so both stay
  # administrator-only: delegating either would let its holder widen their own
  # grant.
  describe "GET /admin/plugins/discourse-ingenic/tag-colours" do
    it "lists every tag with the family it currently draws in" do
      Fabricate(:tag, name: "camera")

      get "/admin/plugins/discourse-ingenic/tag-colours.json"

      expect(response.status).to eq(200)
      row = response.parsed_body["tags"].find { |tag| tag["name"] == "camera" }
      expect(row["family"]).to eq("tech")
      expect(response.parsed_body["families"]).to eq(IngenicTagColour::FAMILIES)
    end

    it "is not offered to a member" do
      sign_in(Fabricate(:user))

      get "/admin/plugins/discourse-ingenic/tag-colours.json"

      expect(response.status).to eq(404)
    end
  end

  describe "PUT /admin/plugins/discourse-ingenic/tag-colours" do
    it "stores the assignment and ignores a family the theme cannot draw" do
      put "/admin/plugins/discourse-ingenic/tag-colours.json",
          params: { colours: JSON.generate("linux" => "announcement", "sdk" => "orange") }

      expect(response.status).to eq(204)
      expect(IngenicTagColour.family_for("linux")).to eq("announcement")
      expect(IngenicTagColour.where(tag_name: "sdk")).not_to exist
    end

    it "replaces an earlier assignment to the same tag" do
      IngenicTagColour.create!(tag_name: "linux", family: "tech")

      put "/admin/plugins/discourse-ingenic/tag-colours.json",
          params: { colours: JSON.generate("linux" => "resolved") }

      expect(IngenicTagColour.find_by(tag_name: "linux").family).to eq("resolved")
    end
  end

  describe "PUT /admin/plugins/discourse-ingenic/feature-permissions" do
    it "replaces both matrices in one write" do
      docs = Fabricate(:group)
      downloads = Fabricate(:group)
      account = Fabricate(:user)
      IngenicFeaturePermission.create!(group: docs, feature: "documentation")
      IngenicFeaturePermission.create!(user: account, feature: "documentation")

      put "/admin/plugins/discourse-ingenic/feature-permissions.json",
          params: {
            grants:
              JSON.generate(
                [
                  { type: "group", id: docs.id, features: ["documentation"] },
                  { type: "group", id: downloads.id, features: %w[downloads points] },
                  { type: "user", id: account.id, features: %w[downloads files] },
                ],
              ),
          }

      expect(response.status).to eq(204)
      expect(IngenicFeaturePermission.where(group: docs).pluck(:feature)).to eq(["documentation"])
      expect(IngenicFeaturePermission.where(group: downloads).pluck(:feature))
        .to contain_exactly("downloads", "points")
      expect(IngenicFeaturePermission.where(user: account).pluck(:feature))
        .to contain_exactly("downloads", "files")
    end

    it "takes a removed account's grant away with the same write" do
      account = Fabricate(:user)
      IngenicFeaturePermission.create!(user: account, feature: "downloads")

      put "/admin/plugins/discourse-ingenic/feature-permissions.json",
          params: { grants: JSON.generate([]) }

      expect(response.status).to eq(204)
      expect(IngenicFeaturePermission.count).to eq(0)
    end

    it "refuses an automatic group and an unknown feature" do
      custom = Fabricate(:group)

      put "/admin/plugins/discourse-ingenic/feature-permissions.json",
          params: {
            grants:
              JSON.generate(
                [
                  { type: "group", id: Group::AUTO_GROUPS[:everyone], features: ["downloads"] },
                  { type: "group", id: custom.id, features: ["everything"] },
                ],
              ),
          }

      expect(response.status).to eq(204)
      expect(IngenicFeaturePermission.count).to eq(0)
    end

    it "refuses a payload that is not a list instead of clearing every grant" do
      IngenicFeaturePermission.create!(user: Fabricate(:user), feature: "downloads")

      put "/admin/plugins/discourse-ingenic/feature-permissions.json",
          params: { grants: JSON.generate("downloads" => true) }

      expect(response.status).to eq(400)
      expect(IngenicFeaturePermission.count).to eq(1)
    end
  end

  describe "GET /admin/plugins/discourse-ingenic/permission-principals" do
    it "finds accounts and custom groups by name" do
      user = Fabricate(:user, username: "t33_owner")
      group = Fabricate(:group, name: "t33-owners")

      get "/admin/plugins/discourse-ingenic/permission-principals.json", params: { q: "t33" }

      expect(response.status).to eq(200)
      expect(response.parsed_body["users"].map { |row| row["id"] }).to include(user.id)
      expect(response.parsed_body["groups"].map { |row| row["id"] }).to include(group.id)
    end
  end

  describe "GET /admin/plugins/discourse-ingenic/category-permissions" do
    it "lists sections with their current group permissions and the custom groups" do
      custom = Fabricate(:group, name: "tech-writers")
      category = Fabricate(:category, name: "Technical Discussions")
      CategoryGroup.create!(category: category, group: custom, permission_type: 3)

      get "/admin/plugins/discourse-ingenic/category-permissions.json"

      expect(response.status).to eq(200)
      row = response.parsed_body["categories"].find { |c| c["id"] == category.id }
      expect(row["permissions"]).to eq("tech-writers" => 3)
      expect(response.parsed_body["groups"].map { |g| g["name"] }).to include("tech-writers")
      expect(response.parsed_body["groups"].map { |g| g["name"] }).not_to include("everyone")
      expect(response.parsed_body["permission_types"]).to eq(
        "full" => 1, "create_post" => 2, "readonly" => 3,
      )
    end

    it "is not offered to a member" do
      sign_in(Fabricate(:user))

      get "/admin/plugins/discourse-ingenic/category-permissions.json"

      expect(response.status).to eq(404)
    end
  end

  describe "PUT /admin/plugins/discourse-ingenic/category-permissions" do
    it "writes and clears group rows" do
      grants = Fabricate(:group, name: "official")
      readers = Fabricate(:group, name: "readers")
      category = Fabricate(:category, name: "Official Open Source")
      CategoryGroup.create!(category: category, group: readers, permission_type: 3)

      put "/admin/plugins/discourse-ingenic/category-permissions.json",
          params: {
            changes: JSON.generate(
              [
                { category_id: category.id, group_id: grants.id, permission: "full" },
                { category_id: category.id, group_id: readers.id, permission: "none" },
              ],
            ),
          }

      expect(response.status).to eq(204)
      expect(CategoryGroup.where(category: category).pluck(:group_id, :permission_type)).to eq(
        [[grants.id, 1]],
      )
    end

    it "refuses to leave a section with no group at all" do
      only = Fabricate(:group)
      category = Fabricate(:category, name: "News")
      CategoryGroup.create!(category: category, group: only, permission_type: 1)

      put "/admin/plugins/discourse-ingenic/category-permissions.json",
          params: {
            changes: JSON.generate(
              [{ category_id: category.id, group_id: only.id, permission: "none" }],
            ),
          }

      expect(response.status).to eq(400)
      expect(response.parsed_body["errors"].join).to include("News")
      expect(CategoryGroup.where(category: category).count).to eq(1)
    end

    it "leaves a section that never had rows at none without refusing the save" do
      group = Fabricate(:group)
      untouched = Fabricate(:category, name: "Third-Party Open Source")
      changed = Fabricate(:category, name: "News")
      CategoryGroup.create!(category: changed, group: group, permission_type: 1)

      put "/admin/plugins/discourse-ingenic/category-permissions.json",
          params: {
            changes: JSON.generate(
              [
                { category_id: untouched.id, group_id: group.id, permission: "none" },
                { category_id: changed.id, group_id: group.id, permission: "readonly" },
              ],
            ),
          }

      expect(response.status).to eq(204)
      expect(CategoryGroup.where(category: untouched).count).to eq(0)
      expect(CategoryGroup.where(category: changed).pluck(:permission_type)).to eq([3])
    end

    it "ignores automatic groups" do
      category = Fabricate(:category)
      CategoryGroup.create!(
        category: category,
        group_id: Group::AUTO_GROUPS[:everyone],
        permission_type: 3,
      )

      put "/admin/plugins/discourse-ingenic/category-permissions.json",
          params: {
            changes: JSON.generate(
              [
                {
                  category_id: category.id,
                  group_id: Group::AUTO_GROUPS[:registered],
                  permission: "full",
                },
              ],
            ),
          }

      expect(response.status).to eq(204)
      expect(
        CategoryGroup.where(category: category, group_id: Group::AUTO_GROUPS[:registered]).count,
      ).to eq(0)
      expect(
        CategoryGroup.where(category: category, group_id: Group::AUTO_GROUPS[:everyone]).count,
      ).to eq(1)
    end
  end

  # A firmware image larger than the ten-megabyte proxy limit cannot be one
  # request. These endpoints are that transfer: open a session, append pieces,
  # finish, then name the finished file when the resource is saved.
  describe "chunked uploads" do
    let(:storage_dir) { Dir.mktmpdir("ingenic-uploads") }

    before { SiteSetting.ingenic_download_storage_path = storage_dir }
    after { FileUtils.remove_entry(storage_dir) if File.exist?(storage_dir) }

    def open_session(name, bytes)
      post "/admin/plugins/discourse-ingenic/uploads.json",
           params: {
             filename: name,
             size: bytes.bytesize,
           }
      expect(response.status).to eq(200)
      response.parsed_body["upload"]["token"]
    end

    def send_piece(token, offset, bytes)
      post "/admin/plugins/discourse-ingenic/uploads/#{token}/chunks.json?offset=#{offset}",
           params: bytes,
           headers: {
             "CONTENT_TYPE" => "application/octet-stream",
           }
      response
    end

    it "assembles a file from pieces and attaches it to a resource" do
      content = "firmware-" * 1000
      token = open_session("sdk.bin", content)

      expect(send_piece(token, 0, content.byteslice(0, 3000)).status).to eq(200)
      still_open = send_piece(token, 3000, content.byteslice(3000, 3000))
      expect(still_open.parsed_body["upload"]["received_size"]).to eq(6000)

      send_piece(token, 6000, content.byteslice(6000..))

      post "/admin/plugins/discourse-ingenic/uploads/#{token}/complete.json"
      expect(response.status).to eq(200)
      expect(response.parsed_body["upload"]["status"]).to eq("completed")

      post "/admin/plugins/discourse-ingenic/downloads.json",
           params: {
             name: "SDK bundle",
             family: "algorithm",
           }
      expect(response.status).to eq(200)
      download = IngenicDownload.find(response.parsed_body["download"]["id"])

      post "/admin/plugins/discourse-ingenic/downloads/#{download.id}/versions.json",
           params: {
             version: "1.0",
             upload_token: token,
           }

      expect(response.status).to eq(200)
      version = IngenicDownloadVersion.find(response.parsed_body["version"]["id"])
      expect(version.original_filename).to eq("sdk.bin")
      expect(version.file_sha256).to eq(Digest::SHA256.hexdigest(content))
      stored = Pathname.new(storage_dir).join(version.storage_path)
      expect(stored.read).to eq(content)

      # The finished upload is consumed by the row that names it.
      expect(IngenicUploadSession.find_by_token(token)).to be_nil
    end

    # The offset is the contract that makes resuming safe. A browser that
    # guessed wrong is told where the file actually ends rather than having
    # its bytes written over someone else's.
    it "reports the byte it has when a piece arrives at the wrong offset" do
      token = open_session("sdk.bin", "abcdefghij")
      send_piece(token, 0, "abcdef")

      response = send_piece(token, 0, "XXXXXX")

      expect(response.status).to eq(409)
      expect(response.parsed_body["received_size"]).to eq(6)
      staging = Ingenic::DownloadStorage.staging_path(IngenicUploadSession.token_digest(token))
      expect(staging.read).to eq("abcdef")
    end

    it "will not finish an upload that is missing bytes" do
      token = open_session("sdk.bin", "abcdefghij")
      send_piece(token, 0, "abc")

      post "/admin/plugins/discourse-ingenic/uploads/#{token}/complete.json"

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"].first).to eq(I18n.t("ingenic.errors.upload_incomplete"))
    end

    it "keeps one person's upload out of another person's reach" do
      token = open_session("sdk.bin", "abcdef")
      sign_in(Fabricate(:admin))

      get "/admin/plugins/discourse-ingenic/uploads/#{token}.json"

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"].first).to eq(I18n.t("ingenic.errors.upload_missing"))
    end

    it "refuses a piece larger than the per-request limit" do
      content = "x" * 9.megabytes
      token = open_session("sdk.bin", content)

      response = send_piece(token, 0, content)

      expect(response.status).to eq(413)
    end
  end
end
