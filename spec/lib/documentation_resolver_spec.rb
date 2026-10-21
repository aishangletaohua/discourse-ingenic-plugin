# frozen_string_literal: true

require "rails_helper"

describe Ingenic::DocumentationResolver do
  fab!(:series) do
    IngenicProduct.create!(slug: "t-series", name: "T Series", kind: "series")
  end
  fab!(:chip) do
    IngenicProduct.create!(slug: "t33", name: "T33", kind: "chip", parent: series)
  end
  fab!(:v1) { IngenicDocVersion.create!(product: chip, slug: "1.0", label: "1.0", position: 0) }
  fab!(:v2) { IngenicDocVersion.create!(product: chip, slug: "1.1", label: "1.1", position: 1) }

  def page(version, slug, title: slug, parent: nil, position: 0)
    IngenicDocPage.create!(
      version: version,
      slug: slug,
      title: title,
      body: "#{slug} body",
      parent: parent,
      position: position,
    )
  end

  describe "version inheritance" do
    it "carries pages the new version did not touch" do
      page(v1, "overview")
      page(v1, "kernel")

      slugs = v2.published_pages.map(&:slug)

      expect(slugs).to contain_exactly("overview", "kernel")
    end

    it "marks inherited pages with the version they came from" do
      page(v1, "overview")
      page(v2, "overview", title: "Overview rewritten")

      resolved = v2.published_pages.find { |candidate| candidate.slug == "overview" }

      expect(resolved.title).to eq("Overview rewritten")
      expect(resolved).not_to be_inherited
    end

    it "reports the source version for untouched pages" do
      page(v1, "kernel")
      page(v2, "overview")

      resolved = v2.published_pages.find { |candidate| candidate.slug == "kernel" }

      expect(resolved).to be_inherited
      expect(resolved.inherited_from).to eq(v1)
    end

    it "does not leak pages from a later version backwards" do
      page(v1, "overview")
      page(v2, "only-in-1-1")

      expect(v1.published_pages.map(&:slug)).to contain_exactly("overview")
    end
  end

  describe "tree shape" do
    it "keeps parents before children and records depth" do
      parent = page(v1, "overview", position: 0)
      page(v1, "kernel", parent: parent, position: 1)

      resolved = v2.published_pages

      expect(resolved.map(&:slug)).to eq(%w[overview kernel])
      expect(resolved.map(&:depth)).to eq([0, 1])
    end

    it "lets a new version add a child under an inherited parent" do
      parent = page(v1, "overview")
      page(v2, "driver", parent: parent)

      resolved = v2.published_pages

      expect(resolved.map(&:slug)).to eq(%w[overview driver])
      expect(resolved.last.depth).to eq(1)
    end
  end

  describe "folders" do
    it "keeps a folder in the tree but does not resolve it as a page" do
      folder =
        IngenicDocPage.create!(
          version: v1,
          slug: "guide",
          title: "Guide",
          kind: "folder",
          )
      page(v1, "setup", parent: folder)

      expect(v2.published_pages.map(&:slug)).to eq(%w[guide setup])
      expect(v2.published_pages.first).to be_folder
      expect(v2.find_readable_page("guide")).to be_nil
    end

    it "steps over a folder when moving between articles" do
      folder =
        IngenicDocPage.create!(
          version: v1,
          slug: "guide",
          title: "Guide",
          kind: "folder",
          )
      page(v1, "setup", parent: folder, position: 0)
      page(v1, "flash", position: 1)

      links = v2.navigation_for(v2.find_readable_page("setup"))

      expect(links[:next].slug).to eq("flash")
    end

    it "drops a body written under a folder" do
      folder =
        IngenicDocPage.create!(
          version: v1,
          slug: "guide",
          title: "Guide",
          kind: "folder",
          body: "never read",
          )

      expect(folder.reload.body).to be_nil
    end

    it "takes the whole section down when the folder is unpublished" do
      folder =
        IngenicDocPage.create!(
          version: v1,
          slug: "guide",
          title: "Guide",
          kind: "folder",
          )
      subfolder =
        IngenicDocPage.create!(
          version: v1,
          slug: "advanced",
          title: "Advanced",
          kind: "folder",
          parent: folder,
          )
      page(v1, "setup", parent: folder)
      page(v1, "tuning", parent: subfolder)

      folder.update!(published: false)

      # Not "re-attached at the top level": a reader sees none of the section.
      expect(v2.published_pages.map(&:slug)).to be_empty

      # The editor still sees it, folder and children, so it can be put back.
      admin_slugs = v2.page_tree.map(&:slug)
      expect(admin_slugs).to eq(%w[guide advanced tuning setup])
      expect(v2.page_tree.find { |resolved| resolved.slug == "setup" }.depth).to eq(1)
      expect(v2.page_tree.find { |resolved| resolved.slug == "tuning" }.depth).to eq(2)
    end

    it "refuses a parent chain that loops back on itself" do
      one = page(v1, "one")
      two = page(v1, "two", parent: one)

      two.parent = two
      expect(two).not_to be_valid
      two.reload

      one.parent = two
      expect(one).not_to be_valid
    end
  end

  describe "navigation" do
    it "walks the resolved order, including inherited pages" do
      page(v1, "one", position: 0)
      page(v1, "two", position: 1)
      page(v2, "three", position: 2)

      middle = v2.find_readable_page("two")
      links = v2.navigation_for(middle)

      expect(links[:previous].slug).to eq("one")
      expect(links[:next].slug).to eq("three")
    end
  end
end
