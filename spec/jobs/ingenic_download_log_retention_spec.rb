# frozen_string_literal: true

require "rails_helper"

# The delivery log keeps the row and forgets the person. Clearing only the
# copied name would leave `user_id` pointing at the account, so every
# identifying column goes at once.
describe Jobs::IngenicDownloadLogRetention do
  fab!(:user)

  let(:download) do
    IngenicDownload.create!(
      name: "SDK",
      locale: "en",
      access_level: IngenicDownload::LOGIN_ONLY,
      family: IngenicDownload::FAMILY_ALGORITHM,
    )
  end

  def log_at(moment)
    log = IngenicDownloadLog.create!(
      user_id: user.id,
      username: user.username,
      download_id: download.id,
      resource_name: download.name,
      version: "1.0",
      ip_address: "203.0.113.9",
      user_agent: "Mozilla/5.0",
      locale: "en",
    )
    log.update_column(:created_at, moment)
    log
  end

  before do
    SiteSetting.ingenic_enabled = true
    SiteSetting.ingenic_download_log_retention_months = 24
  end

  it "forgets who took an old file and keeps what was taken" do
    old = log_at(25.months.ago)

    described_class.new.execute({})

    old.reload
    expect(old.user_id).to be_nil
    expect(old.username).to be_nil
    expect(old.ip_address).to be_nil
    expect(old.user_agent).to be_nil
    expect(old.resource_name).to eq("SDK")
    expect(old.download_id).to eq(download.id)
  end

  it "leaves a log inside the window alone" do
    recent = log_at(23.months.ago)

    described_class.new.execute({})

    recent.reload
    expect(recent.user_id).to eq(user.id)
    expect(recent.username).to eq(user.username)
    expect(recent.ip_address).to eq("203.0.113.9")
  end

  it "keeps everything when the window is set to zero" do
    SiteSetting.ingenic_download_log_retention_months = 0
    old = log_at(10.years.ago)

    described_class.new.execute({})

    expect(old.reload.username).to eq(user.username)
  end
end
