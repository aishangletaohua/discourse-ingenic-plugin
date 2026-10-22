# frozen_string_literal: true

require "rails_helper"

describe IngenicSitePage do
  # The migration seeds the three policy pages. These examples are about the
  # rules a row follows, so they start from an empty table.
  before { described_class.delete_all }

  def page(attrs = {})
    described_class.new(
      { slug: "terms", locale: "en", title: "Terms of Service", body: "Text." }.merge(attrs)
    )
  end

  describe "the address" do
    it "accepts a lowercase slug with hyphens" do
      expect(page(slug: "points-rules")).to be_valid
    end

    it "refuses a slug that would not survive a URL" do
      expect(page(slug: "Points Rules")).not_to be_valid
      expect(page(slug: "points_rules")).not_to be_valid
      expect(page(slug: "")).not_to be_valid
    end

    # The slug and the language together are the address. Two English terms
    # pages would be two answers to /ingenic/pages/terms.
    it "refuses the same slug twice in one language" do
      page.save!

      expect(page).to be_invalid
    end

    it "accepts the same slug in another language" do
      page.save!

      expect(page(locale: "zh_CN", title: "用户协议")).to be_valid
    end
  end

  describe "the lists" do
    it "leaves unpublished pages out and keeps the rest in order" do
      second = page(slug: "privacy", title: "Privacy", position: 1)
      first = page(slug: "terms", title: "Terms", position: 0)
      hidden = page(slug: "retired", title: "Retired", position: 2, published: false)
      [second, first, hidden].each(&:save!)

      expect(described_class.published.ordered.pluck(:slug)).to eq(%w[terms privacy])
    end

    it "answers for one language only" do
      page.save!
      page(locale: "zh_CN", title: "用户协议").save!

      expect(described_class.for_locale("en").pluck(:title)).to eq(["Terms of Service"])
    end
  end

  describe "the title" do
    it "is required" do
      expect(page(title: "")).not_to be_valid
    end
  end
end
