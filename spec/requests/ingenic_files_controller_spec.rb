# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

# The official-file library: the management API under the plugin's admin scope
# and the public address files are linked at.
describe "the file library" do
  fab!(:admin) { Fabricate(:admin) }
  fab!(:user) { Fabricate(:user) }

  let(:storage_dir) { Dir.mktmpdir("ingenic-files") }

  before { SiteSetting.ingenic_file_manager_path = storage_dir }
  after { FileUtils.remove_entry(storage_dir) if File.exist?(storage_dir) }

  def store(name, content, directory: "")
    token = SecureRandom.hex(8)
    Ingenic::FileStorage.append(Ingenic::FileStorage.staging_relative(token), content)
    Ingenic::FileStorage.finalize(Ingenic::FileStorage.staging_relative(token), directory, name)
  end

  def open_upload(filename, bytes, directory: "")
    post "/admin/plugins/discourse-ingenic/files/uploads.json",
         params: {
           filename: filename,
           size: bytes.bytesize,
           directory: directory,
         }
    response
  end

  def send_piece(token, offset, bytes)
    post "/admin/plugins/discourse-ingenic/files/uploads/#{token}/chunks.json?offset=#{offset}",
         params: bytes,
         headers: {
           "CONTENT_TYPE" => "application/octet-stream",
         }
    response
  end

  describe "the management screen" do
    before { sign_in(admin) }

    it "lists an empty library and says what it accepts" do
      get "/admin/plugins/discourse-ingenic/files.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["entries"]).to eq([])
      expect(response.parsed_body["breadcrumbs"]).to eq([{ "name" => "", "path" => "" }])
      expect(response.parsed_body["extensions"]).to include("zip", "pdf", "png")
    end

    it "creates a folder and lists it" do
      post "/admin/plugins/discourse-ingenic/files/folders.json",
           params: {
             path: "",
             name: "SDK",
           }

      expect(response.status).to eq(200)
      expect(response.parsed_body["folder"]["path"]).to eq("SDK")

      get "/admin/plugins/discourse-ingenic/files.json?path=SDK"

      expect(response.parsed_body["breadcrumbs"].map { |crumb| crumb["name"] }).to eq(
        ["", "SDK"],
      )
    end

    it "refuses a name that is a path" do
      post "/admin/plugins/discourse-ingenic/files/folders.json",
           params: {
             path: "",
             name: "../escape",
           }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"].first).to eq(
        I18n.t("ingenic.files.errors.name_invalid"),
      )
    end

    it "renames, moves and deletes" do
      store("sdk.zip", "zip")
      post "/admin/plugins/discourse-ingenic/files/folders.json",
           params: {
             path: "",
             name: "archive",
           }

      post "/admin/plugins/discourse-ingenic/files/rename.json",
           params: {
             path: "sdk.zip",
             name: "sdk-1.0.zip",
           }
      expect(response.parsed_body["entry"]["name"]).to eq("sdk-1.0.zip")

      post "/admin/plugins/discourse-ingenic/files/move.json",
           params: {
             path: "sdk-1.0.zip",
             directory: "archive",
           }
      expect(response.parsed_body["entry"]["path"]).to eq("archive/sdk-1.0.zip")

      delete "/admin/plugins/discourse-ingenic/files.json", params: { path: "archive" }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"].first).to eq(
        I18n.t("ingenic.files.errors.not_empty"),
      )

      delete "/admin/plugins/discourse-ingenic/files.json",
             params: {
               path: "archive/sdk-1.0.zip",
             }

      expect(response.status).to eq(204)
      expect(Ingenic::FileStorage.exist?("archive/sdk-1.0.zip")).to eq(false)
    end

    it "answers 404 for a path that is not there" do
      get "/admin/plugins/discourse-ingenic/files.json?path=missing"

      expect(response.status).to eq(404)
    end

    it "assembles an upload and lands it under the name the operator chose" do
      content = "firmware-" * 1000
      token = open_upload("sdk.zip", content).parsed_body["upload"]["token"]

      expect(send_piece(token, 0, content.byteslice(0, 3000)).status).to eq(200)
      send_piece(token, 3000, content.byteslice(3000..))

      post "/admin/plugins/discourse-ingenic/files/uploads/#{token}/complete.json",
           params: {
             directory: "",
             filename: "sdk-1.0.zip",
             sha256: Digest::SHA256.hexdigest(content),
           }

      expect(response.status).to eq(200)
      file = response.parsed_body["file"]
      expect(file["path"]).to eq("sdk-1.0.zip")
      expect(file["url"]).to eq("/ingenic/files/sdk-1.0.zip")
      expect(file["sha256"]).to eq(Digest::SHA256.hexdigest(content))
      expect(Pathname.new(storage_dir).join("sdk-1.0.zip").read).to eq(content)
      expect(IngenicUploadSession.find_by_token(token)).to be_completed
    end

    it "answers a repeated completion with the same file" do
      content = "firmware-" * 1000
      token = open_upload("sdk.zip", content).parsed_body["upload"]["token"]
      send_piece(token, 0, content)

      params = {
        directory: "",
        filename: "sdk-1.0.zip",
      }

      post "/admin/plugins/discourse-ingenic/files/uploads/#{token}/complete.json", params: params
      first = response.parsed_body["file"]

      post "/admin/plugins/discourse-ingenic/files/uploads/#{token}/complete.json", params: params

      expect(response.status).to eq(200)
      expect(response.parsed_body["file"]).to eq(first)
      expect(Ingenic::FileStorage.exist?("sdk-1.0.zip")).to eq(true)
      expect(Pathname.new(storage_dir).join("sdk-1.0.zip").read).to eq(content)
    end

    it "refuses a piece that announces more than one chunk before reading it" do
      token = open_upload("sdk.zip", "bytes").parsed_body["upload"]["token"]

      post "/admin/plugins/discourse-ingenic/files/uploads/#{token}/chunks.json?offset=0",
           params: "x",
           headers: {
             "CONTENT_LENGTH" => (9.megabytes).to_s,
             "CONTENT_TYPE" => "application/octet-stream",
           }

      expect(response.status).to eq(413)
      expect(response.parsed_body["errors"].first).to eq(
        I18n.t("ingenic.errors.upload_chunk_too_large"),
      )
    end

    it "refuses a checksum that does not match and leaves nothing behind" do
      token = open_upload("sdk.zip", "bytes").parsed_body["upload"]["token"]
      send_piece(token, 0, "bytes")

      post "/admin/plugins/discourse-ingenic/files/uploads/#{token}/complete.json",
           params: {
             directory: "",
             sha256: "0" * 64,
           }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"].first).to eq(
        I18n.t("ingenic.errors.upload_checksum"),
      )
      expect(Ingenic::FileStorage.exist?("sdk.zip")).to eq(false)
    end

    it "refuses an extension the library does not take" do
      response = open_upload("payload.exe", "MZ")

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"].first).to eq(
        I18n.t("ingenic.files.errors.extension"),
      )
    end
  end

  describe "who may use it" do
    it "keeps the library away from an ordinary account" do
      sign_in(user)

      get "/admin/plugins/discourse-ingenic/files.json"

      expect(response.status).to eq(404)
    end

    it "opens it for a group granted the files screen, and only that screen" do
      group = Fabricate(:group)
      group.add(user)
      IngenicFeaturePermission.create!(group: group, feature: "files")
      sign_in(user)

      get "/admin/plugins/discourse-ingenic/files.json"
      expect(response.status).to eq(200)

      get "/admin/plugins/discourse-ingenic/download-requests.json"
      expect(response.status).to eq(404)
    end

    it "offers the tab on the workbench only to that group" do
      group = Fabricate(:group)
      group.add(user)
      IngenicFeaturePermission.create!(group: group, feature: "files")
      sign_in(user)

      get "/ingenic/manage.json"
      expect(response.parsed_body["areas"]["files"]).to eq(true)

      sign_in(Fabricate(:user))
      get "/ingenic/manage.json"
      expect(response.status).to eq(404)
    end
  end

  describe "the public link" do
    it "serves an image to anyone, extension and all" do
      store("logo.png", "\x89PNG\r\n\x1a\n".b)

      get "/ingenic/files/logo.png"

      expect(response.status).to eq(200)
      expect(response.media_type).to eq("image/png")
    end

    it "finds a file in a folder whose name is not ASCII" do
      Ingenic::FileStorage.create_folder("", "开发板 资料")
      store("引脚 图.png", "\x89PNG\r\n\x1a\n".b, directory: "开发板 资料")

      get "/ingenic/files/%E5%BC%80%E5%8F%91%E6%9D%BF%20%E8%B5%84%E6%96%99/%E5%BC%95%E8%84%9A%20%E5%9B%BE.png"

      expect(response.status).to eq(200)
      expect(response.media_type).to eq("image/png")
    end

    it "sends a signed-out visitor to the login page for anything else" do
      store("sdk.zip", "zip")

      get "/ingenic/files/sdk.zip"

      expect(response.status).to eq(302)
      expect(response.location).to include("/login")
    end

    it "serves a signed-in account the file as an attachment" do
      store("sdk.zip", "zip")
      sign_in(user)

      get "/ingenic/files/sdk.zip"

      expect(response.status).to eq(200)
      expect(response.headers["Content-Disposition"]).to include("attachment")
    end

    it "does not follow a link out of the library" do
      FileUtils.mkdir_p(Ingenic::FileStorage.root_path)
      File.symlink("/etc", Ingenic::FileStorage.root_path.join("escape"))

      get "/ingenic/files/escape/passwd"

      expect(response.status).to eq(404)
    end
  end
end
