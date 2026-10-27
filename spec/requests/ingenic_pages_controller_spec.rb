# frozen_string_literal: true

require "rails_helper"

# The download centre and development board pages are served by the same action
# that answers their JSON: a browser navigation gets the Ember app shell, the
# component's fetch gets data. These specs pin that contract, because breaking it
# turns a shared link into a 404 without breaking any in-app navigation.
describe "Ingenic pages" do
  before { SiteSetting.ingenic_enabled = true }

  fab!(:category) { IngenicDownloadCategory.find_or_create_by!(name: "sdk", locale: "en") }
  fab!(:series) { IngenicProduct.create!(slug: "t-series", name: "T Series", locale: "en") }
  fab!(:chip) do
    IngenicProduct.create!(
      slug: "t32pro",
      name: "T32Pro",
      kind: IngenicProduct::CHIP,
      parent: series,
      locale: "en",
    )
  end

  fab!(:download) do
    record =
      IngenicDownload.create!(
        product: chip,
        category: category,
        locale: "en",
        name: "T32Pro SDK",
      )
    record.versions.create!(
      version: "2.1.0",
      file_url: "https://example.com/sdk.tar.gz",
    )
    record
  end

  fab!(:board) do
    IngenicBoard.create!(
      slug: "halley5",
      name: "Halley5",
      product: chip,
      application_url: "https://example.com/apply",
    )
  end

  describe "GET /ingenic/downloads" do
    it "returns the resources and filter options as JSON" do
      get "/ingenic/downloads.json"

      json = response.parsed_body
      expect(json["downloads"].map { |item| item["name"] }).to eq(["T32Pro SDK"])
      expect(json["filters"]["categories"].map { |item| item["name"] }).to include("sdk")
    end

    it "serves the app shell on browser navigation" do
      get "/ingenic/downloads"

      expect(response.status).to eq(200)
      expect(response.body).to include('id="data-preloaded"')
    end
  end

  # What the catalogue answers with is covered by the board spec; what is
  # checked here is the half that is shared with the download centre: the same
  # address answering a browser navigation with the shell rather than data.
  describe "GET /ingenic/boards" do
    it "serves the app shell on browser navigation" do
      get "/ingenic/boards"

      expect(response.status).to eq(200)
      expect(response.body).to include('id="data-preloaded"')
    end
  end
end
