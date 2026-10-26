# frozen_string_literal: true

require "rails_helper"

describe IngenicUploadSession do
  fab!(:user)

  def session_for(token: SecureRandom.urlsafe_base64(24), **attributes)
    IngenicUploadSession.new(
      {
        token_digest: IngenicUploadSession.token_digest(token),
        user_id: user.id,
        original_filename: "sdk.bin",
        expected_size: 1024,
        received_size: 0,
      }.merge(attributes),
    )
  end

  it "starts pending" do
    expect(session_for).to be_valid
    expect(session_for).to be_pending
  end

  it "needs a token digest, an owner, a name and a size" do
    expect(session_for(token_digest: nil)).not_to be_valid
    expect(session_for(user_id: nil)).not_to be_valid
    expect(session_for(original_filename: nil)).not_to be_valid
    expect(session_for(expected_size: 0)).not_to be_valid
  end

  it "does not reuse a token" do
    token = SecureRandom.urlsafe_base64(24)
    session_for(token: token).save!

    expect(session_for(token: token)).not_to be_valid
  end

  it "finds a session from the token the browser holds" do
    token = SecureRandom.urlsafe_base64(24)
    session = session_for(token: token)
    session.save!

    expect(IngenicUploadSession.find_by_token(token)).to eq(session)
    expect(IngenicUploadSession.find_by_token(token, user_id: user.id)).to eq(session)
    expect(IngenicUploadSession.find_by_token(token, user_id: user.id + 1)).to be_nil
    expect(IngenicUploadSession.find_by_token("not-the-token")).to be_nil
  end

  # What the cleanup job reads. A session older than the window is either an
  # abandoned transfer or a finished upload no resource ever named.
  it "finds sessions started before a cutoff" do
    old = session_for
    old.save!
    old.update_column(:created_at, 2.days.ago)
    recent = session_for
    recent.save!

    expect(IngenicUploadSession.stale(24.hours.ago)).to contain_exactly(old)
  end

  it "names its part file by the digest, not by the token or the uploaded filename" do
    token = SecureRandom.urlsafe_base64(24)
    session = session_for(token: token)

    expect(session.staging_relative).to eq(
      File.join(".uploads", "#{IngenicUploadSession.token_digest(token)}.part"),
    )
    expect(session.staging_relative).not_to include(token)
  end
end
