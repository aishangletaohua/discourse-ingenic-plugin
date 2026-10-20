# frozen_string_literal: true

require "rails_helper"
require "zip"

describe Admin::IngenicController do
  fab!(:admin) { Fabricate(:admin) }
  fab!(:product) { IngenicDocProduct.create!(slug: "t-series", name: "T Series", locale: "en") }
  fab!(:board) do
    IngenicBoard.create!(slug: "board-one", name: "Board One", locale: "en", application_url: "https://example.com")
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
      expect(response.parsed_body["default_locale"]).to be_present
    end
  end

  describe "PUT /admin/plugins/discourse-ingenic/documentation/products/:id" do
    # Rows written before the default was fixed are filed under "en" and are
    # invisible to a reader of the site's own language. The screen has to be
    # able to move such a row, with its versions and pages, without deleting
    # it and writing its content again.
    it "changes the language of an existing row" do
      put "/admin/plugins/discourse-ingenic/documentation/products/#{product.id}.json",
          params: { name: "C 系列", slug: "c-series", locale: "zh_CN", published: false }

      expect(response.status).to eq(200)
      expect(product.reload).to have_attributes(
        name: "C 系列",
        slug: "c-series",
        locale: "zh_CN",
        published: false,
      )
    end

    # The reader filters *pages* by locale, so moving only the series would
    # leave a Chinese title opening onto an empty section. Rows carrying the
    # old language follow it down the whole tree.
    it "takes the rows below it along when the language changes" do
      chip =
        IngenicDocProduct.create!(
          slug: "t33",
          name: "T33",
          kind: IngenicDocProduct::CHIP,
          parent: product,
          locale: "en",
        )
      version =
        IngenicDocVersion.create!(product: chip, slug: "1.0", label: "1.0", locale: "en")
      page =
        IngenicDocPage.create!(
          version: version,
          slug: "start",
          title: "Start",
          locale: "en",
        )

      put "/admin/plugins/discourse-ingenic/documentation/products/#{product.id}.json",
          params: { locale: "zh_CN" }

      expect(response.status).to eq(200)
      expect(chip.reload.locale).to eq("zh_CN")
      expect(version.reload.locale).to eq("zh_CN")
      expect(page.reload.locale).to eq("zh_CN")
    end

    it "leaves a row deliberately filed under another language alone" do
      IngenicDocProduct.create!(
        slug: "t33",
        name: "T33",
        kind: IngenicDocProduct::CHIP,
        parent: product,
        locale: "ja",
      )

      put "/admin/plugins/discourse-ingenic/documentation/products/#{product.id}.json",
          params: { locale: "zh_CN" }

      expect(IngenicDocProduct.find_by(slug: "t33").locale).to eq("ja")
    end
  end

  describe "POST /admin/plugins/discourse-ingenic/documentation/products" do
    it "creates a product" do
      expect {
        post "/admin/plugins/discourse-ingenic/documentation/products.json",
             params: { slug: "c-series", name: "C Series", locale: "en" }
      }.to change(IngenicDocProduct, :count).by(1)

      expect(response.status).to eq(200)
    end
  end

  describe "POST /admin/plugins/discourse-ingenic/documentation/versions" do
    fab!(:chip) do
      IngenicDocProduct.create!(
        slug: "t33",
        name: "T33",
        kind: IngenicDocProduct::CHIP,
        parent: product,
        locale: "en",
      )
    end

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
               locale: "en",
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
    fab!(:chip) do
      IngenicDocProduct.create!(
        slug: "t33",
        name: "T33",
        kind: IngenicDocProduct::CHIP,
        parent: product,
        locale: "en",
      )
    end
    fab!(:version) do
      IngenicDocVersion.create!(product: chip, slug: "v1", label: "v1.0", locale: "en", position: 0)
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
          locale: "en",
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
    fab!(:chip) do
      IngenicDocProduct.create!(
        slug: "t33",
        name: "T33",
        kind: IngenicDocProduct::CHIP,
        parent: product,
        locale: "en",
      )
    end
    fab!(:version) do
      IngenicDocVersion.create!(product: chip, slug: "v1", label: "v1.0", locale: "en", position: 0)
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
    fab!(:chip) do
      IngenicDocProduct.create!(
        slug: "t33",
        name: "T33",
        kind: IngenicDocProduct::CHIP,
        parent: product,
        locale: "en",
      )
    end
    fab!(:version) do
      IngenicDocVersion.create!(product: chip, slug: "v1", label: "v1.0", locale: "en", position: 0)
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
      IngenicDocProduct.create!(
        slug: "t33",
        name: "T33",
        kind: IngenicDocProduct::CHIP,
        parent: product,
        locale: "en",
      )

      get "/admin/plugins/discourse-ingenic/boards.json"

      expect(response.status).to eq(200)
      chip = response.parsed_body["chips"].first
      expect(chip["slug"]).to eq("t33")
      expect(chip["series_name"]).to eq("T Series")
    end

    it "offers a boards manager only the chips they may file a board under" do
      chip = IngenicDocProduct.create!(
        slug: "t33",
        name: "T33",
        kind: IngenicDocProduct::CHIP,
        parent: product,
        locale: "en",
      )
      other_series = IngenicDocProduct.create!(slug: "c-series", name: "C Series", locale: "en")
      IngenicDocProduct.create!(
        slug: "c100",
        name: "C100",
        kind: IngenicDocProduct::CHIP,
        parent: other_series,
        locale: "en",
      )
      manager = Fabricate(:user)
      IngenicPermission.create!(
        user: manager,
        resource_type: "IngenicDocProduct",
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
      chip =
        IngenicDocProduct.create!(
          slug: "t33",
          name: "T33",
          kind: IngenicDocProduct::CHIP,
          parent: product,
          locale: "en",
        )

      put "/admin/plugins/discourse-ingenic/boards/#{board.id}.json",
          params: {
            product_id: chip.id,
          }

      expect(response.status).to eq(200)
      expect(response.parsed_body["board"]["chip_name"]).to eq("T33")
      expect(response.parsed_body["board"]["series_name"]).to eq("T Series")
      expect(board.reload.product).to eq(chip)
    end

    it "unfiles the board when the chip picker is cleared" do
      chip =
        IngenicDocProduct.create!(
          slug: "t33",
          name: "T33",
          kind: IngenicDocProduct::CHIP,
          parent: product,
          locale: "en",
        )
      board.update!(product: chip)

      # The picker posts an empty string for its blank option, which the foreign
      # key would refuse as a value.
      put "/admin/plugins/discourse-ingenic/boards/#{board.id}.json",
          params: {
            product_id: "",
          }

      expect(response.status).to eq(200)
      expect(board.reload.product_id).to be_nil
    end
  end

  describe "GET /admin/plugins/discourse-ingenic/permissions" do
    it "is restricted to admins" do
      get "/admin/plugins/discourse-ingenic/permissions.json"

      expect(response.status).to eq(200)
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
      category = IngenicDownloadCategory.create!(name: "SDK", locale: "en")

      put "/admin/plugins/discourse-ingenic/download-categories/#{category.id}.json",
          params: { name: "Software development kits" }

      expect(response.status).to eq(200)
      expect(category.reload.name).to eq("Software development kits")
    end
  end

  describe "DELETE /admin/plugins/discourse-ingenic/download-categories/:id" do
    it "leaves the resources filed under it in place, unfiled" do
      category = IngenicDownloadCategory.create!(name: "SDK", locale: "en")
      download =
        IngenicDownload.create!(
          name: "T33 SDK",
          product_slug: "t33",
          locale: "en",
          category: category,
          file_url: "https://example.com/sdk.tgz",
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
        product_slug: "t33",
        locale: "en",
        file_url: "https://example.com/sdk.tgz",
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
        product_slug: "t33",
        locale: "en",
        access_level: IngenicDownload::APPROVAL_REQUIRED,
        file_url: "https://example.com/sdk.tgz",
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
        product_slug: "t33",
        locale: "en",
        file_url: "https://example.com/sdk.tgz",
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

  describe "GET /admin/plugins/discourse-ingenic/group-permissions" do
    it "lists the custom groups and the screens" do
      custom = Fabricate(:group)
      IngenicGroupPermission.create!(group: custom, feature: "downloads")

      get "/admin/plugins/discourse-ingenic/group-permissions.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["features"]).to eq(IngenicGroupPermission::FEATURES)
      row = response.parsed_body["groups"].find { |group| group["id"] == custom.id }
      expect(row["features"]).to eq(["downloads"])
      expect(response.parsed_body["groups"].map { |group| group["name"] }).not_to include("everyone")
    end

    it "is not offered to a member" do
      sign_in(Fabricate(:user))

      get "/admin/plugins/discourse-ingenic/group-permissions.json"

      expect(response.status).to eq(404)
    end
  end

  describe "PUT /admin/plugins/discourse-ingenic/group-permissions" do
    it "replaces the matrix in one write" do
      docs = Fabricate(:group)
      downloads = Fabricate(:group)
      IngenicGroupPermission.create!(group: docs, feature: "documentation")

      put "/admin/plugins/discourse-ingenic/group-permissions.json",
          params: {
            grants: JSON.generate(
              docs.id => ["documentation"],
              downloads.id => ["downloads", "points"],
            ),
          }

      expect(response.status).to eq(204)
      expect(IngenicGroupPermission.where(group: docs).pluck(:feature)).to eq(["documentation"])
      expect(IngenicGroupPermission.where(group: downloads).pluck(:feature))
        .to contain_exactly("downloads", "points")
    end

    it "refuses an automatic group and an unknown feature" do
      custom = Fabricate(:group)

      put "/admin/plugins/discourse-ingenic/group-permissions.json",
          params: {
            grants: JSON.generate(
              Group::AUTO_GROUPS[:everyone] => ["downloads"],
              custom.id => ["everything"],
            ),
          }

      expect(response.status).to eq(204)
      expect(IngenicGroupPermission.count).to eq(0)
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
end
