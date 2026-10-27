# frozen_string_literal: true

require "rails_helper"

describe IngenicDownloadMailer do
  fab!(:user) { Fabricate(:user, locale: "zh_CN") }
  fab!(:download) do
    IngenicDownload.create!(
      name: "T33 SDK",
      family: IngenicDownload::FAMILY_ALGORITHM,
      access_level: IngenicDownload::LOGIN_ONLY,
      locale: "en",
    )
  end

  def decided_body(note, status: IngenicDownloadRequest::APPROVED)
    request =
      IngenicDownloadRequest.create!(
        user: user,
        download: download,
        status: status,
        review_note: note,
      )
    described_class.request_decided(user.email, request).body.to_s
  end

  it "writes a fallback note, and writes it in the applicant's language" do
    body = decided_body(nil)

    expect(body).to include("团队备注：")
    expect(body).to include("未填写备注。")
    expect(body).not_to include("Notes from the team")
  end

  it "keeps the note the team wrote" do
    body = decided_body("Please complete your profile.", status: IngenicDownloadRequest::REJECTED)

    expect(body).to include("Please complete your profile.")
    expect(body).not_to include("未填写备注。")
  end
end
