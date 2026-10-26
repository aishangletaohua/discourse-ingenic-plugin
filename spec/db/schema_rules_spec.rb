# frozen_string_literal: true

require "rails_helper"

# The rules the database itself holds, checked by writing to it directly.
#
# Every one of these has a model validation as well. That is the point of
# checking the database separately: an import, a console session or a future
# code path can write without the model, and the audit found places where the
# database would have accepted a value the plugin has no branch for.
describe "The Ingenic schema" do
  fab!(:user)

  def refusal(sql, **params)
    DB.exec(sql, **params)
    flunk("the database accepted a row the plugin cannot read")
  rescue ActiveRecord::StatementInvalid, PG::Error => e
    e.message
  end

  def resource(name: "SDK")
    IngenicDownload.create!(
      name: name,
      locale: "en",
      access_level: IngenicDownload::LOGIN_ONLY,
      family: IngenicDownload::FAMILY_ALGORITHM,
      file_url: "https://example.com/sdk.tgz",
    )
  end

  it "refuses a whole-screen feature the code has no branch for" do
    message =
      refusal(<<~SQL, user_id: user.id)
        INSERT INTO ingenic_feature_permissions (user_id, feature, created_at, updated_at)
        VALUES (:user_id, 'everything', now(), now())
      SQL

    expect(message).to include("ingenic_feature_permissions_feature_known")
  end

  it "refuses an access level outside the three tiers" do
    message =
      refusal(<<~SQL)
        INSERT INTO ingenic_downloads (name, family, access_level, created_at, updated_at)
        VALUES ('SDK', 'algorithm', 'anyone', now(), now())
      SQL

    expect(message).to include("ingenic_downloads_access_level_known")
  end

  it "refuses two checksums on one resource" do
    message =
      refusal(<<~SQL)
        INSERT INTO ingenic_downloads (name, family, sha256, file_sha256, created_at, updated_at)
        VALUES ('SDK', 'algorithm', 'by-hand', 'by-server', now(), now())
      SQL

    expect(message).to include("ingenic_downloads_one_checksum")
  end

  it "keeps the log, and the name of who took the file, when the account goes" do
    download = resource
    log = IngenicDownloadLog.record!(user: user, download: download)
    username = user.username

    DB.exec("DELETE FROM users WHERE id = :id", id: user.id)

    log.reload
    expect(log.user_id).to be_nil
    expect(log.username).to eq(username)
  end

  it "takes the queue and the grants with the resource they are about" do
    download = resource
    request_id =
      DB.query_single(
        "INSERT INTO ingenic_download_requests (download_id, created_at, updated_at)
         VALUES (:id, now(), now()) RETURNING id",
        id: download.id,
      ).first
    DB.exec(
      "INSERT INTO ingenic_download_grants (download_id, request_id, created_at, updated_at)
       VALUES (:download_id, :request_id, now(), now())",
      download_id: download.id,
      request_id: request_id,
    )

    DB.exec("DELETE FROM ingenic_downloads WHERE id = :id", id: download.id)

    expect(IngenicDownloadRequest.where(download_id: download.id).count).to eq(0)
    expect(IngenicDownloadGrant.where(download_id: download.id).count).to eq(0)
  end

  it "clears the accepted answer on a bounty when that post is deleted for good" do
    topic = Fabricate(:topic)
    post = Fabricate(:post, topic: topic)
    bounty = IngenicBounty.create!(
      topic: topic,
      user: user,
      points: 50,
      state: IngenicBounty::ACCEPTED,
      accepted_post: post,
      expires_at: 1.day.from_now,
    )

    DB.exec("DELETE FROM posts WHERE id = :id", id: post.id)

    expect(bounty.reload.accepted_post_id).to be_nil
  end
end
