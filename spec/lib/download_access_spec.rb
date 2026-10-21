# frozen_string_literal: true

require "rails_helper"

# The three tiers, and every state a visitor can be in on the way through them.
#
# This is the one place the rules are written down, so it is the one place they
# are tested: the listing asks this object which control to draw, and the file
# endpoint asks it whether to serve. A tier that is wrong here is wrong in both
# places at once, which is the point.
describe Ingenic::DownloadAccess do
  fab!(:user) { Fabricate(:user) }
  fab!(:admin) { Fabricate(:admin) }
  fab!(:category) { IngenicDownloadCategory.find_or_create_by!(name: "sdk", locale: "en") }
  fab!(:series) { IngenicProduct.create!(slug: "t-series", name: "T Series", locale: "en") }
  fab!(:chip) do
    IngenicProduct.create!(
      slug: "t33",
      name: "T33",
      kind: IngenicProduct::CHIP,
      parent: series,
      locale: "en",
    )
  end

  def resource(level, name: "SDK", point_cost: 0)
    IngenicDownload.create!(
      name: name,
      product: chip,
      category: category,
      locale: "en",
      access_level: level,
      point_cost: point_cost,
      file_url: "https://example.com/sdk.tgz",
    )
  end

  # Points to spend. Every route into the ledger goes through the service, so
  # the tests do not write balances directly and cannot invent a state the
  # forum could never reach.
  def earn(user, event = IngenicPointRule::TOPIC_CREATED)
    Ingenic::Points.award(user: user, event: event)
  end

  def with_profile(user)
    IngenicDeveloperProfile.create!(user: user, data: { "full_name" => "Ada" })
    user
  end

  def state_for(user, download)
    described_class.new(user, download).result.state
  end

  describe "the sign-in tier" do
    it "asks a visitor to sign in, whichever tier the resource is" do
      expect(state_for(nil, resource(IngenicDownload::LOGIN_ONLY))).to eq(:anonymous)
      expect(state_for(nil, resource(IngenicDownload::APPROVAL_REQUIRED))).to eq(:anonymous)
    end

    it "lets any signed-in account have a login-only resource" do
      expect(state_for(user, resource(IngenicDownload::LOGIN_ONLY))).to eq(:granted)
    end
  end

  describe "the information tier" do
    it "asks for the developer information once" do
      download = resource(IngenicDownload::FORM_REQUIRED)

      expect(state_for(user, download)).to eq(:needs_profile)
      expect(state_for(with_profile(user), download)).to eq(:granted)
    end

    it "does not accept information in place of approval on the tier above" do
      download = resource(IngenicDownload::APPROVAL_REQUIRED)

      expect(state_for(with_profile(user), download)).to eq(:needs_request)
    end
  end

  describe "the approval tier" do
    it "walks an application from pending to granted" do
      download = resource(IngenicDownload::APPROVAL_REQUIRED)
      with_profile(user)
      request = IngenicDownloadRequest.create!(user: user, download: download)

      expect(state_for(user, download)).to eq(:pending)

      request.approve!(admin)
      expect(state_for(user, download)).to eq(:granted)
    end

    it "keeps a rejection, so the applicant is not sent back to Apply" do
      download = resource(IngenicDownload::APPROVAL_REQUIRED)
      with_profile(user)
      IngenicDownloadRequest.create!(user: user, download: download).reject!(admin, note: "no")

      expect(state_for(user, download)).to eq(:rejected)
    end

    it "ignores a grant that has been revoked" do
      download = resource(IngenicDownload::APPROVAL_REQUIRED)
      with_profile(user)
      IngenicDownloadGrant.issue!(user, download).revoke!(admin)

      expect(state_for(user, download)).to eq(:needs_request)
    end

    it "ignores a grant whose time has run out" do
      download = resource(IngenicDownload::APPROVAL_REQUIRED)
      with_profile(user)
      IngenicDownloadGrant.issue!(user, download, expires_at: 1.day.ago)

      expect(state_for(user, download)).to eq(:needs_request)
    end

    it "answers one applicant about one resource, not about the tier in general" do
      # The profile is part of the tier's own preconditions, so the applicant
      # has to have one for either answer to be about the grant rather than
      # about the form.
      with_profile(user)
      mine = resource(IngenicDownload::APPROVAL_REQUIRED, name: "Mine")
      IngenicDownloadGrant.issue!(user, mine)
      theirs = resource(IngenicDownload::APPROVAL_REQUIRED, name: "Theirs")
      other = Fabricate(:user)
      IngenicDownloadGrant.issue!(other, theirs)

      expect(state_for(user, mine)).to eq(:granted)
      expect(state_for(user, theirs)).to eq(:needs_request)
    end
  end

  # The listing decides every resource on the page at once. Loading the three
  # facts it depends on up front is what keeps the page's cost from growing with
  # its length, so the batch path has to give the same answers as the single one.
  describe ".for_list" do
    it "decides a whole page the same way it decides one resource" do
      open_resource = resource(IngenicDownload::LOGIN_ONLY, name: "Open")
      filled_in = resource(IngenicDownload::FORM_REQUIRED, name: "Form")
      applied_for = resource(IngenicDownload::APPROVAL_REQUIRED, name: "Applied")
      declined = resource(IngenicDownload::APPROVAL_REQUIRED, name: "Declined")

      with_profile(user)
      IngenicDownloadRequest.create!(user: user, download: applied_for)
      IngenicDownloadRequest.create!(user: user, download: declined).reject!(admin)

      results = described_class.for_list(user, [open_resource, filled_in, applied_for, declined])

      expect(results.map(&:download)).to eq([open_resource, filled_in, applied_for, declined])
      expect(results.map(&:state)).to eq(%i[granted granted pending rejected])

      # The same four, asked one at a time. If the batch ever drifts from the
      # single-resource path, the button and the file endpoint stop agreeing.
      one_at_a_time = [open_resource, filled_in, applied_for, declined].map { |d| state_for(user, d) }
      expect(results.map(&:state)).to eq(one_at_a_time)
    end

    it "sees a grant it was loaded after" do
      download = resource(IngenicDownload::APPROVAL_REQUIRED)
      with_profile(user)
      IngenicDownloadGrant.issue!(user, download)

      expect(described_class.for_list(user, [download]).map(&:state)).to eq([:granted])
    end

    it "decides an anonymous listing without touching the account tables" do
      download = resource(IngenicDownload::LOGIN_ONLY)

      expect(described_class.for_list(nil, [download]).map(&:state)).to eq([:anonymous])
    end
  end

  # What a resource costs, which is a question asked after the one above rather
  # than instead of it: the levels decide who may have a file, and this decides
  # what it costs once they may.
  describe "a resource that costs points" do
    before { SiteSetting.ingenic_points_enabled = true }

    it "asks for the points when the balance is short" do
      download = resource(IngenicDownload::LOGIN_ONLY, point_cost: 50)

      expect(state_for(user, download)).to eq(:needs_points)
    end

    it "lets the account through once it can afford it" do
      download = resource(IngenicDownload::LOGIN_ONLY, point_cost: 5)
      earn(user)

      expect(state_for(user, download)).to eq(:granted)
    end

    it "lets an account through on a resource it has already bought" do
      download = resource(IngenicDownload::LOGIN_ONLY, point_cost: 5)
      earn(user)
      # Paid for and spent down to nothing, which is the state a second visit
      # starts in: what was bought once is not re-charged and not re-priced.
      described_class.charge(user, download)
      expect(IngenicPointBalance.total_for(user)).to eq(0)

      expect(state_for(user, download)).to eq(:granted)
    end

    it "does not charge again for a resource already bought" do
      download = resource(IngenicDownload::LOGIN_ONLY, point_cost: 5)
      earn(user)

      expect(described_class.charge(user, download)).to eq(:spent)
      expect(described_class.charge(user, download)).to eq(:already)
      expect(IngenicPointBalance.total_for(user)).to eq(
        IngenicPointRule.amount_for(IngenicPointRule::TOPIC_CREATED) - 5,
      )
    end

    it "asks for the points last, after everything the level asks for" do
      download = resource(IngenicDownload::APPROVAL_REQUIRED, point_cost: 500)

      # Not for sale at any price to somebody who has not been cleared for it.
      expect(state_for(user, download)).to eq(:needs_profile)
      expect(state_for(with_profile(user), download)).to eq(:needs_request)
    end

    it "asks for nothing on a free resource" do
      download = resource(IngenicDownload::LOGIN_ONLY)

      expect(state_for(user, download)).to eq(:granted)
      expect(described_class.charge(user, download)).to eq(:free)
    end

    it "asks for nothing while points are switched off" do
      SiteSetting.ingenic_points_enabled = false
      download = resource(IngenicDownload::LOGIN_ONLY, point_cost: 500)

      expect(state_for(user, download)).to eq(:granted)
      expect(described_class.charge(user, download)).to eq(:free)
    end

    it "refuses a visitor with no account for the same reason as any other level" do
      download = resource(IngenicDownload::LOGIN_ONLY, point_cost: 5)

      expect(state_for(nil, download)).to eq(:anonymous)
    end
  end
end
