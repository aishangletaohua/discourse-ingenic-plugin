# frozen_string_literal: true

require "rails_helper"

describe IngenicBoard do
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

  fab!(:other_chip) do
    IngenicProduct.create!(
      slug: "t32",
      name: "T32",
      kind: IngenicProduct::CHIP,
      parent: series,
      locale: "en",
      position: 1,
    )
  end

  def board_attributes(attrs = {})
    {
      slug: "halley5",
      name: "Halley5",
      product: chip,
      application_url: "https://example.com/apply",
    }.merge(attrs)
  end

  def board(attrs = {})
    IngenicBoard.create!(board_attributes(attrs))
  end

  # Built rather than created, for the examples that are about a record being
  # refused: `create!` raises instead of handing back something to inspect, so a
  # test of "this must not be valid" has to stop short of the insert.
  def unsaved_board(attrs = {})
    IngenicBoard.new(board_attributes(attrs))
  end

  describe "the chip a board is for" do
    it "reads the name from the tree" do
      record = board

      expect(record.chip_name).to eq("T33")
      expect(record.series_name).to eq("T Series")
    end

    it "keeps the name in step with the tree when the chip is renamed" do
      record = board
      chip.update!(name: "T33P")

      expect(record.reload.chip_name).to eq("T33P")
    end

    it "refuses a board filed against a series" do
      record = unsaved_board(product: series)

      expect(record).not_to be_valid
      expect(record.errors[:product]).to be_present
    end

    it "refuses a board with no chip at all" do
      record = unsaved_board(product: nil)

      expect(record).not_to be_valid
      expect(record.errors[:product]).to be_present
    end

    # The chip owns the row; a board pointing at nothing would be a card with
    # no product under it. The catalogue therefore refuses the delete rather
    # than leaving the board orphaned.
    it "refuses to remove a chip that still has a board" do
      board

      expect { chip.destroy! }.to raise_error(ActiveRecord::RecordNotDestroyed)
      expect(chip.reload).to be_persisted
    end
  end

  describe "the catalogue filters" do
    fab!(:on_t33) { board(slug: "halley5", name: "Halley5") }
    fab!(:on_t32) { board(slug: "halley3", name: "Halley3", product: other_chip) }

    it "finds the boards for one chip" do
      expect(described_class.for_chip("t33").pluck("ingenic_boards.slug")).to eq(["halley5"])
    end

    it "leaves a board out of a chip filter it does not belong to" do
      expect(described_class.for_chip("t33")).not_to include(on_t32)
      expect(described_class.published).to include(on_t32)
    end
  end

  describe "the links out" do
    it "accepts a board with only an application link" do
      expect(unsaved_board(purchase_url: nil)).to be_valid
    end

    it "accepts a board with only a purchase link" do
      expect(unsaved_board(application_url: nil, purchase_url: "https://example.com/buy")).to be_valid
    end

    # Missing links and being sold out are two different things: the buttons are
    # grayed one at a time, and only the switch marks the board itself.
    it "accepts a board with neither link without calling it sold out" do
      record = board(application_url: nil, purchase_url: nil)

      expect(record.reload.application_url).to be_nil
      expect(record.purchase_url).to be_nil
      expect(record.sold_out).to eq(false)
    end

    it "keeps its links when marked sold out" do
      record = board(purchase_url: "https://example.com/buy", sold_out: true)

      expect(record.reload.sold_out).to eq(true)
      expect(record.application_url).to eq("https://example.com/apply")
      expect(record.purchase_url).to eq("https://example.com/buy")
    end

    it "starts unsold" do
      expect(board.sold_out).to eq(false)
    end
  end

  describe "publication" do
    it "leaves a withdrawn board out of the published list" do
      record = board
      record.update!(published: false)

      expect(described_class.published.find_by(id: record.id)).to be_nil
    end
  end
end
