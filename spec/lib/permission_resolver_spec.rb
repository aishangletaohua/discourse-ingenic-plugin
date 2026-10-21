# frozen_string_literal: true

require "rails_helper"

describe Ingenic::PermissionResolver do
  fab!(:user) { Fabricate(:user) }
  fab!(:group) { Fabricate(:group) }
  # A grant on a series reaches everything filed under it, so the fixture is the
  # tree the plugin actually builds: a series, the chips beneath it, and the
  # versions and pages that hang off a chip. Only a chip may have a parent —
  # `kind` defaults to `series`, and a series with a parent is refused.
  fab!(:family) { IngenicProduct.create!(slug: "t-series", name: "T Series") }
  fab!(:child) do
    IngenicProduct.create!(
      slug: "t33",
      name: "T33",
      kind: IngenicProduct::CHIP,
      parent: family,
    )
  end
  fab!(:other_family) { IngenicProduct.create!(slug: "c-series", name: "C Series") }
  fab!(:version) do
    IngenicDocVersion.create!(product: child, slug: "latest", label: "Latest")
  end
  fab!(:page) do
    IngenicDocPage.create!(version: version, slug: "overview", title: "Overview")
  end

  it "inherits product grants through versions and pages" do
    IngenicPermission.create!(user: user, resource_type: "IngenicProduct", resource_id: family.id)
    resolver = described_class.new(user)

    expect(resolver.can_manage?(child)).to eq(true)
    expect(resolver.can_manage?(version)).to eq(true)
    expect(resolver.can_manage?(page)).to eq(true)
    expect(resolver.can_manage?(other_family)).to eq(false)
  end

  it "supports group grants" do
    group.add(user)
    IngenicPermission.create!(group: group, resource_type: "IngenicProduct", resource_id: family.id)

    expect(described_class.new(user).can_manage?(child)).to eq(true)
  end

  it "limits a page grant to that page subtree" do
    IngenicPermission.create!(user: user, resource_type: "IngenicDocPage", resource_id: page.id)

    expect(described_class.new(user).can_manage?(page)).to eq(true)
    expect(described_class.new(user).can_manage?(family)).to eq(false)
  end

  it "lets administrators manage every record" do
    user.update!(admin: true)

    expect(described_class.new(user).can_manage?(other_family)).to eq(true)
    expect(described_class.new(user).can_manage_permissions?).to eq(true)
  end

  describe "group feature grants" do
    it "lets a group manage every record on the screen it was given" do
      group.add(user)
      IngenicGroupPermission.create!(group: group, feature: "documentation")

      resolver = described_class.new(user)

      expect(resolver.can_manage_feature?("documentation")).to eq(true)
      expect(resolver.can_manage?(family)).to eq(true)
      expect(resolver.can_manage?(other_family)).to eq(true)
      expect(resolver.visible_ids(IngenicProduct)).to contain_exactly(family, other_family, child)
    end

    it "keeps the other screens out of the grant" do
      group.add(user)
      IngenicGroupPermission.create!(group: group, feature: "documentation")

      resolver = described_class.new(user)

      expect(resolver.can_manage_feature?("boards")).to eq(false)
      expect(resolver.can_manage_feature?("downloads")).to eq(false)
    end

    it "leaves a user outside the group with nothing" do
      other = Fabricate(:user)
      IngenicGroupPermission.create!(group: group, feature: "documentation")

      expect(described_class.new(other).can_manage?(family)).to eq(false)
    end

    it "counts as content management for the navigation" do
      group.add(user)
      IngenicGroupPermission.create!(group: group, feature: "points")

      expect(described_class.new(user).can_manage_any_content?).to eq(true)
    end
  end

  describe "areas" do
    fab!(:board) do
      IngenicBoard.create!(slug: "t33-board", name: "T33 Board", kind: "board", product: child)
    end
    fab!(:download) do
      IngenicDownload.create!(
        name: "T33 SDK",
        family: IngenicDownload::FAMILY_CHIP,
        product: child,
        access_level: IngenicDownload::LOGIN_ONLY,
        file_url: "https://example.com/sdk.zip",
      )
    end

    it "keeps a documentation grant out of the chip's boards and downloads" do
      IngenicPermission.create!(
        user: user,
        resource_type: "IngenicProduct",
        resource_id: family.id,
        area: "documentation",
      )
      resolver = described_class.new(user)

      expect(resolver.can_manage?(child)).to eq(true)
      expect(resolver.can_manage?(board)).to eq(false)
      expect(resolver.can_manage?(download)).to eq(false)
    end

    it "lets a downloads grant reach the resources filed under the chip" do
      IngenicPermission.create!(
        user: user,
        resource_type: "IngenicProduct",
        resource_id: family.id,
        area: "downloads",
      )
      resolver = described_class.new(user)

      expect(resolver.can_manage?(download)).to eq(true)
      expect(resolver.can_manage?(board)).to eq(false)
      expect(resolver.can_manage?(version)).to eq(false)
    end

    it "lets a boards grant reach the boards filed under the chip" do
      IngenicPermission.create!(
        user: user,
        resource_type: "IngenicProduct",
        resource_id: family.id,
        area: "boards",
      )
      resolver = described_class.new(user)

      expect(resolver.can_manage?(board)).to eq(true)
      expect(resolver.can_manage?(download)).to eq(false)
      expect(resolver.can_manage?(version)).to eq(false)
    end

    it "reports which screens have anything to manage, for the admin navigation" do
      IngenicPermission.create!(
        user: user,
        resource_type: "IngenicProduct",
        resource_id: family.id,
        area: "documentation",
      )
      resolver = described_class.new(user)

      expect(resolver.can_manage_any_area?("documentation")).to eq(true)
      expect(resolver.can_manage_any_area?("boards")).to eq(false)
    end

    it "does not treat a whole-screen grant in another area as this one" do
      group.add(user)
      IngenicGroupPermission.create!(group: group, feature: "downloads")

      resolver = described_class.new(user)

      expect(resolver.can_manage_any_area?("downloads")).to eq(true)
      expect(resolver.can_manage_any_area?("documentation")).to eq(false)
      expect(resolver.can_manage_any_area?("boards")).to eq(false)
    end

    it "lists only the downloads and boards the grant covers" do
      other_chip =
        IngenicProduct.create!(
          slug: "c100",
          name: "C100",
          kind: IngenicProduct::CHIP,
            parent: other_family,
        )
      other_board =
        IngenicBoard.create!(slug: "c-series-board", name: "C Board", kind: "board", product: other_chip)
      other_download =
        IngenicDownload.create!(
          name: "C SDK",
          family: IngenicDownload::FAMILY_CHIP,
          product: other_chip,
          access_level: IngenicDownload::LOGIN_ONLY,
          file_url: "https://example.com/c-sdk.zip",
          )
      IngenicPermission.create!(
        user: user,
        resource_type: "IngenicProduct",
        resource_id: family.id,
        area: "downloads",
      )

      expect(described_class.new(user).visible_ids(IngenicDownload)).to contain_exactly(download)
      expect(described_class.new(user).visible_ids(IngenicDownload)).not_to include(other_download)
      # The same grant says nothing about boards, so that screen stays empty
      # rather than borrowing the downloads list.
      expect(described_class.new(user).visible_ids(IngenicBoard)).to be_empty
      expect(described_class.new(user).visible_ids(IngenicBoard)).not_to include(other_board, board)
    end
  end
end
