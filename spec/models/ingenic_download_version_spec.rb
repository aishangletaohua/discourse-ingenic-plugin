# frozen_string_literal: true

require "rails_helper"

describe IngenicDownloadVersion do
  fab!(:download) do
    IngenicDownload.create!(
      name: "T33 SDK",
      family: IngenicDownload::FAMILY_ALGORITHM,
      locale: "en",
      access_level: IngenicDownload::LOGIN_ONLY,
    )
  end

  def version(**attrs)
    download.versions.new(
      { version: "1.0", file_url: "https://example.com/sdk.tgz" }.merge(attrs),
    )
  end

  it "accepts a file served from somewhere else" do
    expect(version).to be_valid
    expect(version).to be_external
    expect(version).not_to be_stored
  end

  it "accepts a file kept on this machine" do
    record = version(file_url: nil, storage_path: "ab/cd/sdk.tgz", original_filename: "sdk.tgz")

    expect(record).to be_valid
    expect(record).to be_stored
    expect(record).not_to be_external
  end

  it "refuses a version with no file behind it" do
    record = version(file_url: nil)

    expect(record).not_to be_valid
    expect(record.errors[:base]).to be_present
  end

  it "refuses two versions with the same label on one resource" do
    download.versions.create!(version: "1.0", file_url: "https://example.com/sdk.tgz")
    second = download.versions.build(version: "1.0", file_url: "https://example.com/b.tgz")

    expect(second).not_to be_valid
    expect(second.errors[:version]).to be_present
  end

  it "allows the same label on a different resource" do
    version.save!
    other =
      IngenicDownload.create!(
        name: "T33 firmware",
        family: IngenicDownload::FAMILY_ALGORITHM,
        locale: "en",
      )

    expect(other.versions.new(version: "1.0", file_url: "https://example.com/b.tgz")).to be_valid
  end

  it "does not count an unlabelled version against the label" do
    version(version: nil).save!
    second = version(version: nil)

    expect(second).to be_valid
  end

  # The column the server computed wins, so a hand-typed checksum cannot sit
  # beside it and disagree.
  it "keeps only one checksum, preferring the one the server computed" do
    record = version(file_sha256: "server", sha256: "typed")
    record.valid?

    expect(record.sha256).to be_nil
    expect(record.checksum).to eq("server")
  end

  it "takes a version released today" do
    expect(version(released_on: Date.current)).to be_valid
  end

  describe ".ordered" do
    it "reads in the order the admin chose, then newest release first" do
      first = version(version: "1.0", position: 1).tap(&:save!)
      second = version(version: "2.0", position: 0).tap(&:save!)
      third = version(version: "1.1", position: 1, released_on: Date.new(2026, 5, 1)).tap(&:save!)

      expect(download.versions.ordered.to_a).to eq([second, third, first])
    end
  end
end
