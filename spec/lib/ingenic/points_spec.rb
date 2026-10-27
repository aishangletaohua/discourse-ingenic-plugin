# frozen_string_literal: true

require "rails_helper"

describe Ingenic::Points do
  fab!(:user) { Fabricate(:user) }
  fab!(:other_user) { Fabricate(:user) }
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

  before { SiteSetting.ingenic_points_enabled = true }

  def balance
    IngenicPointBalance.total_for(user)
  end

  # A resource somebody can buy. Spending only needs a row to be the subject of
  # the purchase; the file under it is never fetched here.
  def make_download(name)
    download =
      IngenicDownload.create!(
        product: chip,
        name: name,
        locale: "en",
        access_level: IngenicDownload::LOGIN_ONLY,
      )
    download.versions.create!(version: "1.0", file_url: "https://example.com/#{name.parameterize}.zip")
    download
  end

  describe "the seeded rules" do
    it "has a row for every event the plugin can report" do
      expect(IngenicPointRule.where(event: IngenicPointRule::EVENTS).count).to eq(
        IngenicPointRule::EVENTS.size,
      )
    end
  end

  describe ".award" do
    it "records the rule's amount and moves the balance with it" do
      entry = described_class.award(user: user, event: IngenicPointRule::POST_CREATED)

      expect(entry.points).to eq(IngenicPointRule.amount_for(IngenicPointRule::POST_CREATED))
      expect(balance).to eq(entry.points)
    end

    it "writes the rule's label as the reason" do
      rule = IngenicPointRule.for(IngenicPointRule::POST_CREATED)
      entry = described_class.award(user: user, event: IngenicPointRule::POST_CREATED)

      expect(entry.reason).to eq(rule.label)
    end

    it "records nothing when points are switched off" do
      SiteSetting.ingenic_points_enabled = false

      expect(
        described_class.award(user: user, event: IngenicPointRule::POST_CREATED),
      ).to be_nil
      expect(balance).to eq(0)
    end

    it "records nothing for an event with no rule" do
      expect(described_class.award(user: user, event: "something_else")).to be_nil
      expect(balance).to eq(0)
    end

    it "records nothing for a rule priced at zero" do
      IngenicPointRule.for(IngenicPointRule::POST_CREATED).update!(points: 0)

      expect(
        described_class.award(user: user, event: IngenicPointRule::POST_CREATED),
      ).to be_nil
      expect(balance).to eq(0)
    end

    it "records nothing for a rule that has been retired" do
      IngenicPointRule.for(IngenicPointRule::POST_CREATED).update!(published: false)

      expect(
        described_class.award(user: user, event: IngenicPointRule::POST_CREATED),
      ).to be_nil
    end

    it "awards the same subject once, however many times the event arrives" do
      post = Fabricate(:post, user: user)

      first = described_class.award(user: user, event: IngenicPointRule::POST_CREATED, subject: post)
      second = described_class.award(user: user, event: IngenicPointRule::POST_CREATED, subject: post)

      expect(first).to be_present
      expect(second).to be_nil
      expect(balance).to eq(first.points)
    end

    it "awards two different subjects separately" do
      described_class.award(user: user, event: IngenicPointRule::POST_CREATED, subject: Fabricate(:post, user: user))
      described_class.award(user: user, event: IngenicPointRule::POST_CREATED, subject: Fabricate(:post, user: user))

      expect(balance).to eq(IngenicPointRule.amount_for(IngenicPointRule::POST_CREATED) * 2)
    end
  end

  describe ".reverse" do
    it "takes the award back and leaves the award itself in the ledger" do
      entry = described_class.award(user: user, event: IngenicPointRule::POST_CREATED)

      described_class.reverse(entry, reason: "the post went away")

      expect(balance).to eq(0)
      expect(entry.reload.points).to eq(IngenicPointRule.amount_for(IngenicPointRule::POST_CREATED))
      expect(entry.reversed?).to eq(true)
    end

    it "does nothing the second time" do
      entry = described_class.award(user: user, event: IngenicPointRule::POST_CREATED)
      2.times { described_class.reverse(entry, reason: "the post went away") }

      expect(balance).to eq(0)
      expect(IngenicPointEntry.where(event: IngenicPointEntry::REVERSAL).count).to eq(1)
    end

    it "records who wrote it down when an administrator did" do
      entry = described_class.award(user: user, event: IngenicPointRule::POST_CREATED)
      described_class.reverse(entry, reason: "removed by hand", by: other_user)

      reversal = IngenicPointEntry.find_by(event: IngenicPointEntry::REVERSAL)
      expect(reversal.awarded_by_id).to eq(other_user.id)
    end

    it "does nothing for an entry that never moved the balance" do
      expect(described_class.reverse(nil, reason: "nothing")).to be_nil
    end
  end

  describe ".reverse_subject" do
    it "takes back every award a subject earned, whatever it was for" do
      post = Fabricate(:post, user: user)
      described_class.award(user: user, event: IngenicPointRule::TOPIC_CREATED, subject: post)
      described_class.award(user: user, event: IngenicPointRule::SOLUTION_ACCEPTED, subject: post)

      described_class.reverse_subject(post, reason: "the post went away")

      expect(balance).to eq(0)
    end
  end

  describe ".spend" do
    fab!(:download) { make_download("T32 SDK") }

    before { described_class.award(user: user, event: IngenicPointRule::TOPIC_CREATED) }

    it "takes the points and records the purchase" do
      outcome = described_class.spend(user: user, points: 3, subject: download, reason: "unlocked")

      expect(outcome).to eq(:spent)
      expect(balance).to eq(IngenicPointRule.amount_for(IngenicPointRule::TOPIC_CREATED) - 3)
      expect(IngenicPointEntry.find_by(event: IngenicPointEntry::DOWNLOAD).points).to eq(-3)
    end

    it "says so and writes nothing when the balance is short" do
      outcome = described_class.spend(user: user, points: 500, subject: download, reason: "unlocked")

      expect(outcome).to eq(:insufficient)
      expect(balance).to eq(IngenicPointRule.amount_for(IngenicPointRule::TOPIC_CREATED))
      expect(IngenicPointEntry.where(event: IngenicPointEntry::DOWNLOAD)).to be_empty
    end

    it "charges once for a subject already bought" do
      described_class.spend(user: user, points: 3, subject: download, reason: "unlocked")
      after_first = balance

      outcome = described_class.spend(user: user, points: 3, subject: download, reason: "unlocked")

      expect(outcome).to eq(:already)
      expect(balance).to eq(after_first)
    end

    it "refuses an account with no balance at all" do
      expect(
        described_class.spend(user: other_user, points: 1, subject: download, reason: "unlocked"),
      ).to eq(:insufficient)
    end

    it "refuses when points are switched off" do
      SiteSetting.ingenic_points_enabled = false

      expect(
        described_class.spend(user: user, points: 1, subject: download, reason: "unlocked"),
      ).to eq(:insufficient)
      expect(balance).to eq(IngenicPointRule.amount_for(IngenicPointRule::TOPIC_CREATED))
    end

    it "refuses a price of nothing" do
      expect(
        described_class.spend(user: user, points: 0, subject: download, reason: "unlocked"),
      ).to eq(:insufficient)
    end
  end

  describe ".adjust" do
    it "adds points with the note as the reason" do
      entry = described_class.adjust(user: user, points: 25, note: "helped with a bug", by: other_user)

      expect(balance).to eq(25)
      expect(entry.reason).to eq("helped with a bug")
      expect(entry.awarded_by_id).to eq(other_user.id)
      expect(entry.event).to eq(IngenicPointEntry::MANUAL)
    end

    it "deducts when the amount is negative" do
      described_class.adjust(user: user, points: 25, note: "helped with a bug", by: other_user)
      described_class.adjust(user: user, points: -10, note: "corrected", by: other_user)

      expect(balance).to eq(15)
    end

    it "works while points are switched off" do
      SiteSetting.ingenic_points_enabled = false
      described_class.adjust(user: user, points: 5, note: "goodwill", by: other_user)

      expect(balance).to eq(5)
    end

    it "does nothing for an amount of zero" do
      expect(described_class.adjust(user: user, points: 0, note: "nothing", by: other_user)).to be_nil
      expect(balance).to eq(0)
    end

    it "falls back to a written reason when no note is given" do
      entry = described_class.adjust(user: user, points: 5, note: nil, by: other_user)

      expect(entry.reason).to eq(I18n.t("ingenic.points.manual_reason"))
    end

    it "can adjust the same account more than once" do
      2.times { described_class.adjust(user: user, points: 5, note: "again", by: other_user) }

      expect(balance).to eq(10)
    end
  end

  describe ".unlocked_download_ids" do
    fab!(:download) { make_download("T32 SDK") }
    fab!(:other_download) { make_download("T31 Firmware") }

    it "names the resources the account has paid for" do
      described_class.award(user: user, event: IngenicPointRule::TOPIC_CREATED)
      described_class.spend(user: user, points: 1, subject: download, reason: "unlocked")

      expect(described_class.unlocked_download_ids(user)).to contain_exactly(download.id)
    end

    it "does not name a resource somebody else bought" do
      described_class.award(user: other_user, event: IngenicPointRule::TOPIC_CREATED)
      described_class.spend(user: other_user, points: 1, subject: other_download, reason: "unlocked")

      expect(described_class.unlocked_download_ids(user)).to be_empty
    end

    it "is empty for a visitor with no account" do
      expect(described_class.unlocked_download_ids(nil)).to be_empty
    end
  end

  describe ".rebuild!" do
    it "puts a balance back in step with the ledger" do
      described_class.award(user: user, event: IngenicPointRule::TOPIC_CREATED)
      IngenicPointBalance.where(user_id: user.id).update_all(points: 999)

      result = described_class.rebuild!

      expect(balance).to eq(IngenicPointRule.amount_for(IngenicPointRule::TOPIC_CREATED))
      expect(result[:corrected]).to be >= 1
    end

    it "is a no-op when the two already agree" do
      described_class.award(user: user, event: IngenicPointRule::TOPIC_CREATED)

      expect(described_class.rebuild![:corrected]).to eq(0)
    end

    it "recreates a balance row that was deleted by hand" do
      described_class.award(user: user, event: IngenicPointRule::TOPIC_CREATED)
      IngenicPointBalance.where(user_id: user.id).delete_all

      described_class.rebuild!

      expect(balance).to eq(IngenicPointRule.amount_for(IngenicPointRule::TOPIC_CREATED))
    end
  end

  # What a deleted member leaves behind. The account is gone and the movements
  # stay, so the plugin's own paths run into rows with nobody behind them: the
  # reversal of an award they earned, the refund of a bounty they left standing.
  # Neither may raise on the way — the bounty expiry job closes every due offer
  # in one pass, so an orphan that raised would strand every offer queued behind
  # it — and neither may put a total on an account that does not exist.
  describe "a movement with no account behind it" do
    it "writes the entry and moves no balance" do
      entry =
        described_class.record(
          user: nil,
          points: 20,
          event: IngenicPointEntry::BOUNTY_REFUND,
          reason: "the offer expired",
        )

      expect(entry.user_id).to be_nil
      expect(IngenicPointEntry.where(user_id: nil).count).to eq(1)
      expect(IngenicPointBalance.where(user_id: nil)).to be_empty
    end

    it "still takes back an award whose account has gone" do
      entry = described_class.award(user: user, event: IngenicPointRule::POST_CREATED)
      # The state deleting the member leaves the ledger in: the row stays, the
      # account on it is blanked, and the balance row goes with the account.
      IngenicPointEntry.where(id: entry.id).update_all(user_id: nil)
      IngenicPointBalance.where(user_id: user.id).delete_all

      reversal = described_class.reverse(entry.reload, reason: "the post went away")

      expect(reversal.user_id).to be_nil
      expect(reversal.points).to eq(-entry.points)
    end

    it "leaves such an entry out of the rebuilt totals" do
      described_class.record(
        user: nil,
        points: 20,
        event: IngenicPointEntry::BOUNTY_REFUND,
        reason: "the offer expired",
      )

      described_class.rebuild!

      # No balance row for nobody: the totals are what members hold, and a row
      # here would count as a holder on the admin screen.
      expect(IngenicPointBalance.where(user_id: nil)).to be_empty
    end
  end

  describe ".total_for" do
    it "reads nothing for an account that has never earned" do
      expect(described_class.total_for(other_user)).to eq(0)
    end

    it "reads nothing for a visitor with no account" do
      expect(described_class.total_for(nil)).to eq(0)
    end
  end
end
