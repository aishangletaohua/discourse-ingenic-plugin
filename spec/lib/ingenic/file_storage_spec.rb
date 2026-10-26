# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

# The official-file library on disk.
#
# The tests here are about the two boundaries the screen relies on: a name that
# came from a browser stays a name, and a path that came from the screen cannot
# leave the configured root. Everything else — listing, folders, the upload's
# last step — is checked against a real temporary directory rather than a mock,
# because the point is what ends up on the disk.
describe Ingenic::FileStorage do
  # Assigned in a `before`, not an `around`: Discourse resets its settings
  # cache as each example's transaction opens, so a write made outside that
  # boundary is not what the example reads back.
  let(:storage_dir) { Dir.mktmpdir("ingenic-files") }

  before { SiteSetting.ingenic_file_manager_path = storage_dir }
  after { FileUtils.remove_entry(storage_dir) if File.exist?(storage_dir) }

  def store(name, content, directory: "")
    token = SecureRandom.hex(8)
    described_class.append(described_class.staging_relative(token), content)
    described_class.finalize(described_class.staging_relative(token), directory, name)
  end

  it "keeps folders ahead of files in a listing" do
    store("firmware.bin", "binary")
    described_class.create_folder("", "SDK")

    entries = described_class.list("")[:entries]

    expect(entries.map { |entry| [entry[:kind], entry[:name]] }).to eq(
      [%w[dir SDK], %w[file firmware.bin]],
    )
  end

  it "reports the path and escaped address of a nested file" do
    described_class.create_folder("", "开发板 资料")
    stored = store("引脚 说明.pdf", "%PDF", directory: "开发板 资料")

    expect(stored[:relative]).to eq("开发板 资料/引脚 说明.pdf")
    expect(stored[:size]).to eq(4)
    expect(described_class.url_for(stored[:relative])).to eq(
      "/ingenic/files/%E5%BC%80%E5%8F%91%E6%9D%BF%20%E8%B5%84%E6%96%99/%E5%BC%95%E8%84%9A%20%E8%AF%B4%E6%98%8E.pdf",
    )
  end

  it "refuses a path that climbs out of the root" do
    expect { described_class.normalize_relative("../etc/passwd") }.to raise_error(
      described_class::Error,
    ) { |error| expect(error.code).to eq(:path_invalid) }
    expect { described_class.absolute_path("a/../../b") }.to raise_error(described_class::Error)
    expect { described_class.absolute_path("/etc/passwd") }.to raise_error(described_class::Error)
  end

  it "refuses a name that would be a path or a hidden file" do
    ["../../etc/passwd", "a/b.zip", "C:\\x.zip", ".hidden", ".", ".."].each do |name|
      expect { described_class.clean_name(name) }.to raise_error(
        described_class::Error,
      ) { |error| expect(error.code).to eq(:name_invalid) }
    end

    expect(described_class.clean_name("  SDK 说明.pdf ")).to eq("SDK 说明.pdf")
  end

  it "refuses an extension the site has not allowed" do
    expect { store("payload.exe", "MZ") }.to raise_error(described_class::Error) { |error|
      expect(error.code).to eq(:extension)
    }
  end

  it "does not overwrite an existing file" do
    store("sdk.zip", "one")

    expect { store("sdk.zip", "two") }.to raise_error(described_class::Error) { |error|
      expect(error.code).to eq(:exists)
    }
    expect(described_class.list("")[:entries].first[:size]).to eq(3)
  end

  it "renames and moves a file, reporting the new path" do
    described_class.create_folder("", "archive")
    stored = store("sdk.zip", "zip")

    renamed = described_class.rename(stored[:relative], "sdk-1.2.zip")
    expect(renamed).to eq("sdk-1.2.zip")

    moved = described_class.move(renamed, "archive")
    expect(moved).to eq("archive/sdk-1.2.zip")
    expect(described_class.exist?(moved)).to eq(true)
  end

  it "refuses to move a folder inside itself" do
    described_class.create_folder("", "outer")
    described_class.create_folder("outer", "inner")

    expect { described_class.move("outer", "outer/inner") }.to raise_error(
      described_class::Error,
    ) { |error| expect(error.code).to eq(:move_into_self) }
  end

  it "deletes a file and an empty folder, but not a full one" do
    described_class.create_folder("", "folder")
    store("sdk.zip", "zip", directory: "folder")

    expect { described_class.delete("folder") }.to raise_error(described_class::Error) { |error|
      expect(error.code).to eq(:not_empty)
    }

    described_class.delete("folder/sdk.zip")
    described_class.delete("folder")

    expect(described_class.list("")[:entries]).to be_empty
  end

  it "hides the staging directory from the listing and from the path rules" do
    described_class.append(described_class.staging_relative("abc"), "part")

    names = described_class.list("")[:entries].map { |entry| entry[:name] }
    expect(names).not_to include(".uploads")
    expect { described_class.existing_path(".uploads/abc.part") }.to raise_error(
      described_class::Error,
    )
  end

  it "will not follow a symlink out of the root" do
    FileUtils.mkdir_p(described_class.root_path)
    File.symlink("/etc", described_class.root_path.join("escape"))

    expect(described_class.list("")[:entries]).to be_empty
    expect { described_class.existing_path("escape/passwd") }.to raise_error(
      described_class::Error,
    ) { |error| expect(error.code).to eq(:not_found) }
  end
end
