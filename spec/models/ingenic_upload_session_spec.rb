# frozen_string_literal: true

require "rails_helper"

describe IngenicUploadSession do
  fab!(:user)

  def session_for(attributes = {})
    IngenicUploadSession.new(
      {
        token: SecureRandom.urlsafe_base64(24),
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

  it "needs a token, an owner, a name and a size" do
    expect(session_for(token: nil)).not_to be_valid
    expect(session_for(user_id: nil)).not_to be_valid
    expect(session_for(original_filename: nil)).not_to be_valid
    expect(session_for(expected_size: 0)).not_to be_valid
  end

  it "does not reuse a token" do
    token = SecureRandom.urlsafe_base64(24)
    session_for(token: token).save!

    expect(session_for(token: token)).not_to be_valid
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

  it "names its part file by token, not by the uploaded filename" do
    session = session_for
    expect(session.staging_relative).to eq(File.join(".uploads", "#{session.token}.part"))
  end
end
