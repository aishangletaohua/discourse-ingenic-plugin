# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

# The sweep that forgets abandoned uploads. A pending upload only owns a part
# file; a finished file-manager upload owns a real library file, which the
# sweep must never mistake for garbage.
describe Jobs::IngenicUploadCleanup do
  fab!(:user) { Fabricate(:admin) }

  let(:storage_dir) { Dir.mktmpdir("ingenic-files") }

  before { SiteSetting.ingenic_file_manager_path = storage_dir }
  after { FileUtils.remove_entry(storage_dir) if File.exist?(storage_dir) }

  def session_for(attributes = {})
    IngenicUploadSession.create!(
      {
        token: SecureRandom.urlsafe_base64(24),
        user_id: user.id,
        original_filename: "sdk.zip",
        expected_size: 4,
        received_size: 0,
        purpose: IngenicUploadSession::PURPOSE_FILES,
      }.merge(attributes),
    )
  end

  def old_session(attributes = {})
    session = session_for(attributes)
    session.update_columns(created_at: 25.hours.ago)
    session
  end

  it "sweeps the part file of an upload nobody finished" do
    session = old_session
    Ingenic::FileStorage.append(Ingenic::FileStorage.staging_relative(session.token), "part")

    described_class.new.execute({})

    expect(File.exist?(Ingenic::FileStorage.staging_path(session.token))).to eq(false)
    expect(IngenicUploadSession.find_by(id: session.id)).to be_nil
  end

  it "forgets a finished library upload without deleting its file" do
    stored =
      begin
        Ingenic::FileStorage.append(Ingenic::FileStorage.staging_relative("seed"), "data")
        Ingenic::FileStorage.finalize(Ingenic::FileStorage.staging_relative("seed"), "", "sdk.zip")
      end
    session =
      old_session(
        expected_size: stored[:size],
        received_size: stored[:size],
        status: "completed",
        storage_path: stored[:relative],
        sha256: stored[:sha256],
      )

    described_class.new.execute({})

    expect(Ingenic::FileStorage.exist?("sdk.zip")).to eq(true)
    expect(IngenicUploadSession.find_by(id: session.id)).to be_nil
  end

  it "leaves a recent upload alone" do
    session = session_for
    Ingenic::FileStorage.append(Ingenic::FileStorage.staging_relative(session.token), "part")

    described_class.new.execute({})

    expect(File.exist?(Ingenic::FileStorage.staging_path(session.token))).to eq(true)
    expect(IngenicUploadSession.find_by(id: session.id)).to be_present
  end
end
