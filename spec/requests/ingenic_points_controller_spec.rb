# frozen_string_literal: true

require "rails_helper"

describe IngenicPointsController do
  fab!(:user) { Fabricate(:user) }
  fab!(:other_user) { Fabricate(:user) }
  fab!(:admin) { Fabricate(:admin) }

  before { SiteSetting.ingenic_points_enabled = true }

  describe "GET /ingenic/points" do
    it "reports a visitor with no account as having nothing" do
      get "/ingenic/points.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["signed_in"]).to eq(false)
      expect(response.parsed_body["balance"]).to eq(0)
      expect(response.parsed_body["entries"]).to be_empty
    end

    it "still says what the forum pays for, so the page has an answer for a visitor" do
      get "/ingenic/points.json"

      events = response.parsed_body["rules"].map { |rule| rule["event"] }
      expect(events).to match_array(IngenicPointRule::EVENTS)
    end

    it "reports the signed-in reader's own balance and movements" do
      Ingenic::Points.award(user: user, event: IngenicPointRule::TOPIC_CREATED)
      sign_in(user)

      get "/ingenic/points.json"

      expect(response.parsed_body["signed_in"]).to eq(true)
      expect(response.parsed_body["balance"]).to eq(
        IngenicPointRule.amount_for(IngenicPointRule::TOPIC_CREATED),
      )
      expect(response.parsed_body["entries"].size).to eq(1)
      expect(response.parsed_body["entries"].first["reason"]).to eq(
        IngenicPointRule.for(IngenicPointRule::TOPIC_CREATED).label,
      )
    end

    it "does not show one account another account's movements" do
      Ingenic::Points.award(user: other_user, event: IngenicPointRule::TOPIC_CREATED)
      sign_in(user)

      get "/ingenic/points.json"

      expect(response.parsed_body["balance"]).to eq(0)
      expect(response.parsed_body["entries"]).to be_empty
    end

    it "leaves out a rule that has been retired" do
      IngenicPointRule.for(IngenicPointRule::POST_CREATED).update!(published: false)

      get "/ingenic/points.json"

      events = response.parsed_body["rules"].map { |rule| rule["event"] }
      expect(events).not_to include(IngenicPointRule::POST_CREATED)
    end

    it "says when points are switched off" do
      SiteSetting.ingenic_points_enabled = false

      get "/ingenic/points.json"

      expect(response.parsed_body["enabled"]).to eq(false)
    end

    it "serves the app shell for a direct navigation" do
      get "/ingenic/points"

      expect(response.status).to eq(200)
      # The shell is the application, not the answer: the number itself arrives
      # from the JSON endpoint once it has mounted. Asserted on a key the
      # payload has rather than on the word "balance", which core's own
      # preloaded site settings happen to contain.
      expect(response.body).to include('id="data-preloaded"')
      expect(response.body).not_to include('"entries"')
    end
  end

  # The management screen. Administrator-only throughout, including the reading:
  # the ledger names accounts and an adjustment moves a member's standing, which
  # is the same kind of act as deciding who may have a file — and that is not
  # delegated to a scoped content manager either.
  describe "the admin screen" do
    # The management endpoints are JSON like the rest of Discourse's admin API,
    # so the format is on the path. Without it the request never reaches the
    # controller: the route has no format segment to match, and the base
    # controller answers a non-AJAX request with an empty page.
    let(:endpoint) { "/admin/plugins/discourse-ingenic" }

    it "is out of reach for an ordinary account" do
      sign_in(user)

      # The management routes sit behind a routing constraint, so for an account
      # that manages nothing they are not in the table at all. Whether that
      # surfaces as an unrouted request or as Discourse's 404 page depends on
      # the exception settings in play; neither reaches the controller.
      outcome =
        begin
          get "#{endpoint}/points.json"
          response.status
        rescue ActionController::RoutingError
          :unrouted
        end

      expect([:unrouted, 404]).to include(outcome)
    end

    it "is out of reach for a scoped content manager" do
      product = IngenicProduct.create!(slug: "t33", name: "T33", locale: "en")
      IngenicPermission.create!(
        user: user,
        resource_type: "IngenicProduct",
        resource_id: product.id,
        permission: "manage",
      )
      sign_in(user)

      get "#{endpoint}/points.json"

      expect(response.status).to eq(404)
    end

    it "shows an administrator the rules, the movements and the balances" do
      Ingenic::Points.award(user: user, event: IngenicPointRule::TOPIC_CREATED)
      sign_in(admin)

      get "#{endpoint}/points.json"

      body = response.parsed_body
      expect(body["rules"].map { |rule| rule["event"] }).to match_array(IngenicPointRule::EVENTS)
      expect(body["entries"].size).to eq(1)
      expect(body["balances"].map { |row| row["username"] }).to include(user.username)
      expect(body["totals"]["earned"]).to eq(
        IngenicPointRule.amount_for(IngenicPointRule::TOPIC_CREATED),
      )
    end

    it "adjusts an account by username, and says what it left them with" do
      sign_in(admin)

      post "#{endpoint}/points/adjust.json",
           params: {
             username: user.username,
             points: 25,
             note: "helped with a bug",
           }

      expect(response.status).to eq(200)
      expect(response.parsed_body["balance"]).to eq(25)
      expect(response.parsed_body["entry"]["reason"]).to eq("helped with a bug")
      expect(IngenicPointBalance.total_for(user)).to eq(25)
    end

    it "refuses an adjustment to an account that does not exist" do
      sign_in(admin)

      post "#{endpoint}/points/adjust.json", params: { username: "nobody", points: 5 }

      expect(response.status).to eq(404)
    end

    it "refuses an adjustment of nothing" do
      sign_in(admin)

      post "#{endpoint}/points/adjust.json", params: { username: user.username, points: 0 }

      expect(response.status).to eq(422)
      expect(IngenicPointBalance.total_for(user)).to eq(0)
    end

    it "reprices a rule without touching what the ledger already says" do
      Ingenic::Points.award(user: user, event: IngenicPointRule::TOPIC_CREATED)
      rule = IngenicPointRule.for(IngenicPointRule::TOPIC_CREATED)
      paid = rule.points
      sign_in(admin)

      put "#{endpoint}/points/rules/#{rule.id}.json", params: { points: 99, label: "Opening a topic" }

      expect(response.status).to eq(200)
      expect(rule.reload.points).to eq(99)
      expect(rule.label).to eq("Opening a topic")
      # The row written under the old price still says what it paid.
      expect(IngenicPointEntry.first.points).to eq(paid)
    end

    it "cannot be used to rename the action itself" do
      rule = IngenicPointRule.for(IngenicPointRule::TOPIC_CREATED)
      sign_in(admin)

      put "#{endpoint}/points/rules/#{rule.id}.json", params: { event: "something_else" }

      expect(rule.reload.event).to eq(IngenicPointRule::TOPIC_CREATED)
    end

    it "repairs a balance that has drifted from the ledger" do
      Ingenic::Points.award(user: user, event: IngenicPointRule::TOPIC_CREATED)
      IngenicPointBalance.where(user_id: user.id).update_all(points: 999)
      sign_in(admin)

      post "#{endpoint}/points/rebuild.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["corrected"]).to eq(1)
      expect(IngenicPointBalance.total_for(user)).to eq(
        IngenicPointRule.amount_for(IngenicPointRule::TOPIC_CREATED),
      )
    end

    it "lists one account's movements on request" do
      Ingenic::Points.award(user: user, event: IngenicPointRule::TOPIC_CREATED)
      Ingenic::Points.award(user: other_user, event: IngenicPointRule::TOPIC_CREATED)
      sign_in(admin)

      get "#{endpoint}/point-entries.json", params: { user_id: user.id }

      expect(response.parsed_body["total"]).to eq(1)
      expect(response.parsed_body["entries"].first["username"]).to eq(user.username)
    end
  end
end
