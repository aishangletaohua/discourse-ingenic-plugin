# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

describe Ingenic::ConfigExport do
  fab!(:user) { Fabricate(:user) }

  let(:path) { File.join(Dir.mktmpdir, "ingenic-config.yml") }

  def payload_of_this_forum
    described_class.export(path)
    YAML.safe_load(File.read(path))
  end

  def build_a_tree
    series =
      IngenicProduct.create!(
        slug: "t-series",
        name: "T Series",
        kind: IngenicProduct::SERIES,
        locale: "en",
        position: 1,
      )
    chip =
      IngenicProduct.create!(
        slug: "t33",
        name: "T33",
        kind: IngenicProduct::CHIP,
        parent: series,
        locale: "en",
        position: 2,
      )
    version =
      IngenicDocVersion.create!(
        product: chip,
        slug: "v1.0",
        label: "v1.0",
        latest: true,
        released_on: Date.new(2026, 1, 5),
      )
    intro =
      IngenicDocPage.create!(
        version: version,
        slug: "intro",
        title: "Introduction",
        body: "# Hello",
      )
    IngenicDocPage.create!(
      version: version,
      slug: "pinout",
      title: "Pinout",
      parent: intro,
      position: 2,
    )

    IngenicBoard.create!(
      slug: "t33-evb",
      name: "T33 EVB",
      product: chip,
      application_url: "/t/t33-evb-application",
      purchase_url: "https://example.com/buy",
    )

    IngenicPermission.create!(
      user: user,
      resource_type: "IngenicProduct",
      resource_id: chip.id,
      permission: "manage",
    )

    series
  end

  # delete_all rather than destroy_all: the point here is an empty database, and
  # the product tree's own callbacks would refuse to take a series out from
  # under the chips it still has.
  def wipe_content
    IngenicDocPage.delete_all
    IngenicDocVersion.delete_all
    IngenicBoard.delete_all
    IngenicPermission.delete_all
    IngenicProduct.delete_all
    IngenicPromotion.delete_all
    IngenicSocialLink.delete_all
    IngenicFooterLink.delete_all
    IngenicFooterColumn.delete_all
    IngenicPointRule.delete_all
  end

  describe "the settings half" do
    it "carries the settings an admin changed" do
      SiteSetting.ingenic_download_admin_email = "team@example.com"

      settings = payload_of_this_forum["site_settings"]

      expect(settings["ingenic_download_admin_email"]).to eq("team@example.com")
    end

    it "carries this plugin's settings and nothing else" do
      SiteSetting.ingenic_download_admin_email = "team@example.com"

      expect(payload_of_this_forum["site_settings"].keys).to all(start_with("ingenic_"))
    end

    it "leaves out a setting still sitting on its default" do
      SiteSetting.ingenic_download_admin_email = ""

      expect(payload_of_this_forum["site_settings"]).not_to have_key(
        "ingenic_download_admin_email",
      )
    end
  end

  describe "the content half" do
    it "puts the tree back, links and all, after a wipe" do
      build_a_tree
      described_class.export(path)
      wipe_content

      report = described_class.import(path)

      series = IngenicProduct.find_by(slug: "t-series")
      chip = IngenicProduct.find_by(slug: "t33")
      expect(series).to be_series
      expect(chip).to be_chip
      expect(chip.parent).to eq(series)

      version = IngenicDocVersion.find_by(slug: "v1.0")
      expect(version.product).to eq(chip)
      expect(version).to be_latest
      expect(version.released_on).to eq(Date.new(2026, 1, 5))

      expect(IngenicDocPage.find_by(slug: "intro").body).to eq("# Hello")
      expect(IngenicDocPage.find_by(slug: "pinout").parent.slug).to eq("intro")

      expect(IngenicBoard.find_by(slug: "t33-evb").product).to eq(chip)
      expect(report.dig("doc_products", "created")).to eq(2)
    end

    it "brings the permissions back with the things they are about" do
      build_a_tree
      described_class.export(path)
      wipe_content

      described_class.import(path)

      permission = IngenicPermission.find_by(user: user)
      expect(permission.resource_type).to eq("IngenicProduct")
      expect(permission.resource_id).to eq(IngenicProduct.find_by(slug: "t33").id)
    end

    it "has nothing to do the second time" do
      build_a_tree
      described_class.export(path)

      report = described_class.import(path)

      expect(report["doc_products"]).to eq("created" => 0, "updated" => 0)
      expect(report["doc_versions"]).to eq("created" => 0, "updated" => 0)
      expect(report["doc_pages"]).to eq("created" => 0, "updated" => 0)
    end

    it "leaves a row the file does not mention where it is" do
      build_a_tree
      described_class.export(path)
      IngenicProduct.create!(
        slug: "m-series",
        name: "M Series",
        kind: IngenicProduct::SERIES,
        locale: "en",
      )

      report = described_class.import(path)

      expect(IngenicProduct.find_by(slug: "m-series")).to be_present
      expect(report["untouched"]).to include("doc_products" => 1)
    end

    it "changes nothing at all in a dry run" do
      build_a_tree
      described_class.export(path)
      wipe_content

      report = described_class.import(path, dry_run: true)

      expect(IngenicProduct.count).to eq(0)
      expect(IngenicDocVersion.count).to eq(0)
      expect(report.dig("doc_products", "created")).to eq(2)
    end

    it "counts the rows it touched rather than the rows it read" do
      build_a_tree
      described_class.export(path)
      IngenicProduct.find_by(slug: "t33").update!(name: "T33 (revised)")

      report = described_class.import(path)

      expect(report["doc_products"]).to eq("created" => 0, "updated" => 1)
      expect(IngenicProduct.find_by(slug: "t33").name).to eq("T33")
    end
  end

  describe "what it refuses" do
    it "says which row the forum would not accept" do
      File.write(
        path,
        <<~YAML,
          version: 1
          content:
            downloads:
              - name: "Broken"
                product_slug: "t33"
                locale: "en"
                access_level: "whatever"
                file_url: "https://example.com/a.zip"
        YAML
      )

      expect { described_class.import(path) }.to raise_error(
        Ingenic::ConfigExport::ImportError,
        /Broken/,
      )
      expect(IngenicDownload.count).to eq(0)
    end

    it "turns back a file written by a newer plugin" do
      File.write(path, "version: 99\ncontent: {}\n")

      expect { described_class.import(path) }.to raise_error(ArgumentError, /newer version/)
    end

    it "turns back a path with no file behind it" do
      expect { described_class.import("/nowhere/ingenic-config.yml") }.to raise_error(
        ArgumentError,
        /no configuration file/,
      )
    end

    it "turns back a file that is not one of these" do
      File.write(path, "hello: world\n")

      expect { described_class.import(path) }.to raise_error(ArgumentError, /not an Ingenic/)
    end
  end

  describe "what it will not copy" do
    # The file's shape is the guarantee. There is no section a balance, a
    # request, a grant or a profile could be written into, so this checks the
    # shape rather than looking for names that must not appear in it.
    it "has no section a member's record could go in" do
      IngenicPointEntry.create!(
        user: user,
        points: 5,
        event: IngenicPointEntry::MANUAL,
        reason: "test",
      )
      IngenicDeveloperProfile.create!(user: user, data: { name: "Someone" })

      payload = payload_of_this_forum

      expect(payload.keys).to contain_exactly("version", "exported_at", "site_settings", "content")
      expect(payload["content"].keys).to contain_exactly(*Ingenic::ConfigExport::SECTIONS)
    end
  end
end
