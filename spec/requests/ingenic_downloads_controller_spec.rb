# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

describe IngenicDownloadsController do
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

  before { SiteSetting.ingenic_download_admin_email = "team@example.com" }

  def resource(level, name: "SDK", **attrs)
    IngenicDownload.create!(
      {
        name: name,
        product: chip,
        category: category,
        locale: "en",
        access_level: level,
        file_url: "https://example.com/sdk.tgz",
      }.merge(attrs),
    )
  end

  def with_profile(owner = nil)
    IngenicDeveloperProfile.create!(
      user: owner || user,
      identity: "company",
      full_name: "Ada",
      company: "Acme",
      country: "UK",
      contact_email: "ada@example.com",
      use_case: "Set-top boxes",
    )
  end

  describe "GET /ingenic/downloads" do
    it "says which state each resource is in for the reader" do
      resource(IngenicDownload::LOGIN_ONLY, name: "Open")
      resource(IngenicDownload::APPROVAL_REQUIRED, name: "Gated")

      get "/ingenic/downloads.json"

      states = response.parsed_body["downloads"].to_h { |d| [d["name"], d["access_state"]] }
      expect(states).to eq("Open" => "anonymous", "Gated" => "anonymous")
      expect(response.parsed_body["signed_in"]).to eq(false)
    end

    it "keeps the algorithm library parallel to the chip resources" do
      algorithms = IngenicDownloadCategory.find_or_create_by!(name: "algorithm", locale: "en")
      resource(IngenicDownload::LOGIN_ONLY, name: "Encoder", family: "algorithm", product: nil, category: algorithms)
      resource(IngenicDownload::LOGIN_ONLY, name: "Chip SDK")

      get "/ingenic/downloads.json?family=algorithm"

      expect(response.parsed_body["downloads"].map { |row| row["name"] }).to eq(["Encoder"])

      filters = response.parsed_body["filters"]
      expect(filters["families"]).to eq(%w[chip algorithm])

      entry = filters["categories"].find { |category| category["name"] == "algorithm" }
      expect(entry["families"]).to eq(["algorithm"])
      expect(entry["product_slugs"]).to eq([])
    end

    it "never puts the resource's own address in the listing" do
      resource(IngenicDownload::LOGIN_ONLY)

      get "/ingenic/downloads.json"

      expect(response.body).not_to include("example.com")
      expect(response.parsed_body["downloads"].first["file_path"]).to end_with("/file")
    end

    it "reports a granted resource for the account that holds the grant" do
      resource(IngenicDownload::LOGIN_ONLY)
      sign_in(user)

      get "/ingenic/downloads.json"

      expect(response.parsed_body["downloads"].first["access_state"]).to eq("granted")
      expect(response.parsed_body["signed_in"]).to eq(true)
    end

    # A telephone number is not among the questions. The account already has an
    # address the team can write to, and a field nobody reads is one more reason
    # for a developer to give up on the form.
    it "does not ask for a telephone number" do
      get "/ingenic/downloads.json"

      keys = response.parsed_body.dig("form", "fields").map { |field| field["key"] }
      expect(keys).not_to include("phone")
    end

    it "serves the app shell for a direct navigation" do
      get "/ingenic/downloads"

      expect(response.status).to eq(200)
    end

    # The two levels of the product filter. The options come from the product
    # tree rather than from the slugs on the resources, so a chip is offered
    # under its name and not as the string that happens to be in the row.
    describe "the product filters" do
      fab!(:other_series) do
        IngenicProduct.create!(slug: "c-series", name: "C Series", locale: "en")
      end

      fab!(:other_chip) do
        IngenicProduct.create!(
          slug: "c100",
          name: "C100",
          kind: IngenicProduct::CHIP,
          parent: other_series,
          locale: "en",
        )
      end

      it "offers the series, and each chip under the series it belongs to" do
        resource(IngenicDownload::LOGIN_ONLY, name: "Chip SDK")

        get "/ingenic/downloads.json"

        filters = response.parsed_body["filters"]
        expect(filters["series"]).to eq([{ "slug" => "t-series", "name" => "T Series" }])
        expect(filters["chips"]).to eq(
          [{ "slug" => "t33", "name" => "T33", "series_slug" => "t-series" }],
        )
      end

      it "matches a resource filed against a chip when its series is chosen" do
        resource(IngenicDownload::LOGIN_ONLY, name: "Chip SDK", product: chip)
        resource(IngenicDownload::LOGIN_ONLY, name: "Other SDK", product: other_chip)

        get "/ingenic/downloads.json?series=t-series"

        expect(response.parsed_body["downloads"].map { |row| row["name"] }).to eq(["Chip SDK"])
      end

      it "still narrows by a named chip" do
        resource(IngenicDownload::LOGIN_ONLY, name: "Chip SDK", product: chip)
        resource(IngenicDownload::LOGIN_ONLY, name: "Other SDK", product: other_chip)

        get "/ingenic/downloads.json?product=t33"

        expect(response.parsed_body["downloads"].map { |row| row["name"] }).to eq(["Chip SDK"])
      end
    end
  end

  describe "POST /ingenic/downloads/profile" do
    before { sign_in(user) }

    def save(profile)
      post "/ingenic/downloads/profile.json", params: { profile: profile }
    end

    def universal(identity, **extra)
      {
        identity: identity,
        full_name: "Ada",
        country: "UK",
        contact_email: "ada@example.com",
        use_case: "Set-top boxes",
      }.merge(extra)
    end

    it "stores a company's answers" do
      expect { save(universal("company", company: "Acme", job_title: "Engineer")) }.to change(
        IngenicDeveloperProfile,
        :count,
      ).by(1)

      profile = IngenicDeveloperProfile.for(user)
      expect(response.status).to eq(200)
      expect(response.parsed_body["form"]["completed"]).to eq(true)
      expect(profile.identity).to eq("company")
      expect(profile.company).to eq("Acme")
      expect(profile.value_for("job_title")).to eq("Engineer")
      # The universal answers have columns now, so the document is empty rather
      # than holding a second copy of them.
      expect(profile.data).to eq({})
    end

    it "asks a company for its name" do
      save(universal("company"))

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"].first).to include(
        I18n.t("ingenic.developer_form.fields.company"),
      )
      expect(IngenicDeveloperProfile.for(user)).to be_nil
    end

    it "asks a student for a school" do
      save(universal("student"))

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"].first).to include(
        I18n.t("ingenic.developer_form.fields.school"),
      )
      expect(IngenicDeveloperProfile.for(user)).to be_nil
    end

    it "asks an individual developer for nothing more" do
      save(universal("individual"))

      expect(response.status).to eq(200)
      profile = IngenicDeveloperProfile.for(user)
      expect(profile.identity).to eq("individual")
      expect(profile.company).to be_nil
      expect(profile.school).to be_nil
    end

    it "clears the company answers when the identity changes" do
      save(universal("company", company: "Acme", job_title: "Engineer"))
      save(universal("individual"))

      profile = IngenicDeveloperProfile.for(user)
      expect(profile.identity).to eq("individual")
      expect(profile.company).to be_nil
      expect(profile.job_title).to be_nil
    end

    it "clears the school answers when the identity changes" do
      save(universal("student", school: "Cambridge", major: "Engineering"))
      save(universal("individual"))

      profile = IngenicDeveloperProfile.for(user)
      expect(profile.school).to be_nil
      expect(profile.major).to be_nil
    end

    it "refuses a form with a required answer missing" do
      save(full_name: "Ada")

      expect(response.status).to eq(422)
      expect(IngenicDeveloperProfile.for(user)).to be_nil
    end

    it "refuses an answer that is not a valid email address" do
      save(universal("individual", contact_email: "not-an-email"))

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"].first).to include(
        I18n.t(
          "ingenic.developer_form.invalid_email",
          field: I18n.t("ingenic.developer_form.fields.contact_email"),
        ),
      )
    end

    it "refuses an identity it does not offer" do
      save(universal("partner"))

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"].first).to include(
        I18n.t(
          "ingenic.developer_form.invalid_option",
          field: I18n.t("ingenic.developer_form.fields.identity"),
        ),
      )
    end

    it "keeps only the answers the form asks for" do
      save(
        universal("company", company: "Acme").merge(
          phone: "+44 20 7946 0000",
          admin: "true",
          injected: "<script>",
        ),
      )

      profile = IngenicDeveloperProfile.for(user)
      expect(profile.data.keys).not_to include("admin", "injected", "phone")
      # A core answer lives in its column, never in the document.
      expect(profile.data).not_to include("company")
    end

    it "offers the identity choices and says which questions follow from them" do
      get "/ingenic/downloads.json"

      fields = response.parsed_body["form"]["fields"].index_by { |field| field["key"] }
      identity = fields["identity"]
      expect(identity["type"]).to eq("select")
      expect(identity["options"].map { |option| option["value"] }).to eq(
        %w[company student individual],
      )
      expect(fields["company"]["when"]).to eq({ "key" => "identity", "value" => "company" })
      expect(fields["school"]["when"]).to eq({ "key" => "identity", "value" => "student" })
      expect(fields["full_name"]["when"]).to be_nil
    end

    context "when the site adds its own questions" do
      before do
        SiteSetting.ingenic_developer_form_fields = [
          { "key" => "team_size", "label" => "Team size", "type" => "text" },
          { "key" => "phone_number", "label" => "Phone", "type" => "text" },
          { "key" => "wechat_id", "label" => "WeChat", "type" => "text" },
          { "key" => "qq_number", "label" => "QQ", "type" => "text" },
        ].to_json
      end

      it "adds the question but refuses ones that ask for a phone number, WeChat or QQ" do
        get "/ingenic/downloads.json"

        keys = response.parsed_body["form"]["fields"].map { |field| field["key"] }
        expect(keys).to include("team_size")
        expect(keys).not_to include("phone_number", "wechat_id", "qq_number")
      end

      it "stores the extra answer beside the core columns" do
        save(universal("individual", team_size: "12"))

        expect(response.status).to eq(200)
        profile = IngenicDeveloperProfile.for(user)
        expect(profile.value_for("team_size")).to eq("12")
        expect(profile.data).to eq("team_size" => "12")
      end
    end
  end

  describe "POST /ingenic/downloads/:id/request" do
    before { sign_in(user) }

    it "records the application and emails the team" do
      Jobs.run_immediately!
      with_profile
      download = resource(IngenicDownload::APPROVAL_REQUIRED)

      expect {
        post "/ingenic/downloads/#{download.id}/request.json",
             params: {
               message: "Building a camera",
             }
      }.to change(IngenicDownloadRequest, :count).by(1).and change {
              ActionMailer::Base.deliveries.size
            }.by(1)

      expect(response.status).to eq(200)
      expect(ActionMailer::Base.deliveries.last.to).to contain_exactly("team@example.com")
      expect(IngenicDownloadRequest.last.message).to eq("Building a camera")
    end

    it "asks for the developer information instead of filing an application" do
      download = resource(IngenicDownload::APPROVAL_REQUIRED)

      expect { post "/ingenic/downloads/#{download.id}/request.json" }.not_to change(
        IngenicDownloadRequest,
        :count,
      )

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"].first).to eq(
        I18n.t("ingenic.downloads.profile_required"),
      )
    end

    it "answers a second application with the first one still open" do
      Jobs.run_immediately!
      with_profile
      download = resource(IngenicDownload::APPROVAL_REQUIRED)
      post "/ingenic/downloads/#{download.id}/request.json"

      expect { post "/ingenic/downloads/#{download.id}/request.json" }.not_to change(
        IngenicDownloadRequest,
        :count,
      )

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"].first).to eq(
        I18n.t("ingenic.downloads.already_requested"),
      )
    end
  end

  describe "GET /ingenic/downloads/:id/file" do
    it "turns away a visitor who has not signed in" do
      download = resource(IngenicDownload::LOGIN_ONLY)

      get "/ingenic/downloads/#{download.id}/file.json"

      expect(response.status).to eq(403)
    end

    it "sends a browser navigation back to the centre rather than a wall of JSON" do
      download = resource(IngenicDownload::FORM_REQUIRED)

      get "/ingenic/downloads/#{download.id}/file"

      expect(response.status).to eq(302)
      expect(response.location).to end_with("/ingenic/downloads")
    end

    it "sends the browser to an external address once access is settled" do
      download = resource(IngenicDownload::LOGIN_ONLY)
      sign_in(user)

      get "/ingenic/downloads/#{download.id}/file"

      expect(response.status).to eq(302)
      expect(response.location).to eq("https://example.com/sdk.tgz")
    end

    it "does not send the browser to a value that is not a web address" do
      download = resource(IngenicDownload::LOGIN_ONLY, file_url: "javascript:alert(1)")
      sign_in(user)

      get "/ingenic/downloads/#{download.id}/file"

      expect(response.location).not_to include("javascript")
    end

    it "serves an uploaded file to an account that holds a grant" do
      directory = Dir.mktmpdir("ingenic-download")
      SiteSetting.ingenic_download_storage_path = directory

      tempfile = Tempfile.new("sdk")
      tempfile.binmode
      tempfile.write("firmware")
      tempfile.rewind

      stored =
        Ingenic::DownloadStorage.store(
          ActionDispatch::Http::UploadedFile.new(tempfile: tempfile, filename: "sdk.bin"),
        )

      download =
        resource(
          IngenicDownload::APPROVAL_REQUIRED,
          storage_path: stored[:path],
          original_filename: "sdk.bin",
          file_url: nil,
        )

      with_profile
      IngenicDownloadGrant.issue!(user, download)
      sign_in(user)

      get "/ingenic/downloads/#{download.id}/file"

      expect(response.status).to eq(200)
      expect(response.headers["Content-Type"]).to eq("application/octet-stream")
      expect(response.headers["Content-Disposition"]).to include("attachment", "sdk.bin")
      # The body is handed back as an Enumerator so a firmware image is never
      # read into memory, so what the response promises about it is the length.
      expect(response.headers["Content-Length"]).to eq("8")
    ensure
      FileUtils.remove_entry(directory) if directory
    end

    it "refuses the file to a signed-in account without a grant" do
      download = resource(IngenicDownload::APPROVAL_REQUIRED)
      with_profile
      sign_in(user)

      get "/ingenic/downloads/#{download.id}/file"

      expect(response.status).to eq(302)
    end

    it "reports a resource that has gone missing from storage instead of failing" do
      directory = Dir.mktmpdir("ingenic-download")
      SiteSetting.ingenic_download_storage_path = directory

      download =
        resource(
          IngenicDownload::LOGIN_ONLY,
          storage_path: "aa/gone.bin",
          original_filename: "gone.bin",
          file_url: nil,
        )
      sign_in(user)

      get "/ingenic/downloads/#{download.id}/file.json"

      expect(response.status).to eq(404)
      expect(response.parsed_body["errors"].first).to eq(
        I18n.t("ingenic.downloads.not_available"),
      )
    ensure
      FileUtils.remove_entry(directory) if directory
    end
  end

  # What a resource costs, from the listing's point of view and from the file
  # endpoint's. The two have to agree: a card that says Unlock and an endpoint
  # that serves the file for nothing would be a price that means nothing.
  describe "a resource that costs points" do
    before { SiteSetting.ingenic_points_enabled = true }

    def earn(account, event = IngenicPointRule::TOPIC_CREATED)
      Ingenic::Points.award(user: account, event: event)
    end

    # Enough to afford a price the seeded rules would not reach: opening a topic
    # pays 5, and a test about buying something needs a balance that can buy it.
    # Put in the way an administrator would, so nothing here writes a balance
    # the ledger has no row for.
    def fund(account, points)
      Ingenic::Points.adjust(user: account, points: points, note: "seed", by: admin)
    end

    it "reports the reader's balance with the listing" do
      earn(user)
      sign_in(user)

      get "/ingenic/downloads.json"

      expect(response.parsed_body["points"]).to eq(
        IngenicPointRule.amount_for(IngenicPointRule::TOPIC_CREATED),
      )
      expect(response.parsed_body["points_enabled"]).to eq(true)
    end

    it "carries the price of a resource and whether it is already unlocked" do
      download = resource(IngenicDownload::LOGIN_ONLY, name: "Priced", point_cost: 40)
      fund(user, 40)
      sign_in(user)

      get "/ingenic/downloads.json"

      card = response.parsed_body["downloads"].find { |d| d["name"] == "Priced" }
      expect(card["point_cost"]).to eq(40)
      expect(card["unlocked"]).to eq(false)

      get "/ingenic/downloads/#{download.id}/file"
      get "/ingenic/downloads.json"

      card = response.parsed_body["downloads"].find { |d| d["name"] == "Priced" }
      expect(card["unlocked"]).to eq(true)
    end

    it "refuses the file to an account that cannot afford it, with the price" do
      download = resource(IngenicDownload::LOGIN_ONLY, point_cost: 400)
      sign_in(user)

      get "/ingenic/downloads/#{download.id}/file.json"

      expect(response.status).to eq(403)
      expect(response.parsed_body["errors"].first).to eq(
        I18n.t("ingenic.downloads.not_enough_points", points: 400),
      )
    end

    it "sends a browser navigation back to the centre when the balance is short" do
      download = resource(IngenicDownload::LOGIN_ONLY, point_cost: 400)
      sign_in(user)

      get "/ingenic/downloads/#{download.id}/file"

      expect(response.status).to eq(302)
      expect(response.location).to end_with("/ingenic/downloads")
    end

    it "takes the points and hands the file over when the balance is enough" do
      download = resource(IngenicDownload::LOGIN_ONLY, point_cost: 5)
      earn(user)
      sign_in(user)

      get "/ingenic/downloads/#{download.id}/file"

      expect(response.location).to eq("https://example.com/sdk.tgz")
      expect(IngenicPointBalance.total_for(user)).to eq(
        IngenicPointRule.amount_for(IngenicPointRule::TOPIC_CREATED) - 5,
      )
    end

    it "charges nothing more for a resource already bought" do
      download = resource(IngenicDownload::LOGIN_ONLY, point_cost: 5)
      earn(user)
      earn(user, IngenicPointRule::POST_CREATED)
      sign_in(user)

      get "/ingenic/downloads/#{download.id}/file"
      after_first = IngenicPointBalance.total_for(user)
      get "/ingenic/downloads/#{download.id}/file"

      expect(IngenicPointBalance.total_for(user)).to eq(after_first)
    end

    it "charges nothing for a resource that is not in storage" do
      directory = Dir.mktmpdir("ingenic-download")
      SiteSetting.ingenic_download_storage_path = directory

      download =
        resource(
          IngenicDownload::LOGIN_ONLY,
          storage_path: "aa/gone.bin",
          original_filename: "gone.bin",
          file_url: nil,
          point_cost: 5,
        )
      earn(user)
      sign_in(user)

      get "/ingenic/downloads/#{download.id}/file.json"

      expect(response.status).to eq(404)
      expect(IngenicPointBalance.total_for(user)).to eq(
        IngenicPointRule.amount_for(IngenicPointRule::TOPIC_CREATED),
      )
    ensure
      FileUtils.remove_entry(directory) if directory
    end

    it "charges nothing while points are switched off" do
      SiteSetting.ingenic_points_enabled = false
      download = resource(IngenicDownload::LOGIN_ONLY, point_cost: 5)
      sign_in(user)

      get "/ingenic/downloads/#{download.id}/file"

      expect(response.location).to eq("https://example.com/sdk.tgz")
      expect(IngenicPointBalance.total_for(user)).to eq(0)
    end
  end

  # The record the team asked for by name. An approval lasts, so the grant table
  # answers "who may" and never "who did" — this is the only remaining account of
  # a gated file having been collected, and of the account that collected it.
  describe "the record of a delivery" do
    it "names the account that took the file" do
      download = resource(IngenicDownload::LOGIN_ONLY)
      sign_in(user)

      expect { get "/ingenic/downloads/#{download.id}/file" }.to change(
        IngenicDownloadLog,
        :count,
      ).by(1)

      log = IngenicDownloadLog.last
      expect(log.user).to eq(user)
      expect(log.download).to eq(download)
      expect(log.resource_name).to eq(download.name)
    end

    it "records nothing for a visitor who was refused" do
      download = resource(IngenicDownload::APPROVAL_REQUIRED)

      expect { get "/ingenic/downloads/#{download.id}/file" }.not_to change(
        IngenicDownloadLog,
        :count,
      )
      expect(response.status).to eq(302)
    end

    # Allowed, but there is nothing to hand over. A row here would put a name
    # against a file that never left, which is worse than no row at all.
    it "records nothing for a resource that is no longer in storage" do
      download =
        resource(
          IngenicDownload::LOGIN_ONLY,
          storage_path: "aa/gone.bin",
          original_filename: "gone.bin",
          file_url: nil,
        )
      sign_in(user)

      expect { get "/ingenic/downloads/#{download.id}/file" }.not_to change(
        IngenicDownloadLog,
        :count,
      )
      expect(response.status).to eq(302)
    end

    # A grant is what the team approves, and it is not a deadline: once an
    # application is approved the resource stays available to that account.
    it "keeps the grant, and with it the access, with no end date" do
      download = resource(IngenicDownload::APPROVAL_REQUIRED)
      with_profile
      IngenicDownloadRequest.create!(user: user, download: download).approve!(admin)

      grant = IngenicDownloadGrant.find_by(user: user, download: download)
      expect(grant.expires_at).to be_nil
      expect(Ingenic::DownloadAccess.new(user, download).result.state).to eq(:granted)
    end

    # The record is kept for the team, not asked of the visitor: a download
    # somebody is entitled to is not to be turned into an error page because a
    # row could not be written.
    it "hands the file over even when the record cannot be written" do
      download = resource(IngenicDownload::LOGIN_ONLY)
      sign_in(user)
      IngenicDownloadLog.stubs(:create!).raises(ActiveRecord::StatementInvalid.new("no space left"))

      get "/ingenic/downloads/#{download.id}/file"

      expect(response.status).to eq(302)
      expect(response.location).to eq("https://example.com/sdk.tgz")
    end
  end

  describe "the admin queue" do
    before { sign_in(admin) }

    it "lists a waiting application with the applicant's information" do
      download = resource(IngenicDownload::APPROVAL_REQUIRED)
      with_profile
      IngenicDownloadRequest.create!(user: user, download: download, message: "hello")

      get "/admin/plugins/discourse-ingenic/download-requests.json"

      expect(response.status).to eq(200)
      entry = response.parsed_body["requests"].first
      expect(entry["status"]).to eq("pending")
      expect(entry["profile_summary"]).to include("Ada")
      expect(response.parsed_body["pending_count"]).to eq(1)
    end

    it "grants access and tells the applicant when an application is approved" do
      Jobs.run_immediately!
      download = resource(IngenicDownload::APPROVAL_REQUIRED)
      with_profile
      request = IngenicDownloadRequest.create!(user: user, download: download)

      expect {
        put "/admin/plugins/discourse-ingenic/download-requests/#{request.id}/approve.json",
            params: {
              note: "welcome",
            }
      }.to change { ActionMailer::Base.deliveries.size }.by(1)

      expect(response.status).to eq(200)
      expect(IngenicDownloadGrant.active.find_by(user: user, download: download)).to be_present
      expect(Ingenic::DownloadAccess.new(user, download).result.state).to eq(:granted)
    end

    it "withdraws access when a grant is revoked" do
      download = resource(IngenicDownload::APPROVAL_REQUIRED)
      with_profile
      grant = IngenicDownloadGrant.issue!(user, download, granted_by: admin)
      expect(Ingenic::DownloadAccess.new(user, download).result.state).to eq(:granted)

      delete "/admin/plugins/discourse-ingenic/download-grants/#{grant.id}.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["grant"]["active"]).to eq(false)
      expect(Ingenic::DownloadAccess.new(user, download).result.state).to eq(:needs_request)
    end

    it "is out of reach for an ordinary account" do
      sign_in(user)

      # The management routes sit behind a routing constraint, so for an account
      # that manages nothing they are not in the table at all. Whether that
      # surfaces as an unrouted request or as Discourse's 404 page depends on
      # the exception settings in play; neither reaches the controller.
      outcome =
        begin
          get "/admin/plugins/discourse-ingenic/download-requests.json"
          response.status
        rescue ActionController::RoutingError
          :unrouted
        end

      expect([:unrouted, 404]).to include(outcome)
    end
  end
end
