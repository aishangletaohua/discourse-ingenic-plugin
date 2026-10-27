# frozen_string_literal: true

require "rails_helper"

describe "Ingenic MCP tools" do
  fab!(:series) do
    IngenicProduct.create!(
      slug: "t-series",
      name: "T Series",
      kind: "series",
      locale: "en"
    )
  end
  fab!(:chip) do
    IngenicProduct.create!(
      slug: "t33",
      name: "T33",
      kind: "chip",
      parent: series,
      locale: "en"
    )
  end
  fab!(:version) do
    IngenicDocVersion.create!(
      product: chip,
      slug: "1.0",
      label: "1.0",
      position: 0,
      latest: true
    )
  end

  # The tools only read the language and the id off the request context here;
  # the scope check belongs to core and has already happened by the time a tool
  # runs.
  let(:request_context) { Struct.new(:user).new(nil) }

  def call(tool, arguments = {})
    tool.call(arguments: arguments, request_context: request_context)
  end

  before do
    IngenicDocPage.create!(
      version: version,
      slug: "flash-image",
      title: "Flashing the image",
      body: "Use the USB boot tool."
    )
    IngenicDocPage.create!(
      version: version,
      slug: "getting-started",
      title: "Getting started",
      body: "Install the SDK."
    )
  end

  describe Ingenic::Mcp::Exposure do
    it "registers every developer-centre tool under one read scope" do
      identifiers =
        DiscourseMcp.registry.all(:tool).map(&:identifier).grep(/\Aingenic_/)

      expect(identifiers).to contain_exactly(
        "ingenic_search",
        "ingenic_list_documentation",
        "ingenic_read_documentation_page",
        "ingenic_list_downloads",
        "ingenic_list_boards"
      )

      primitive = DiscourseMcp.registry.find(:tool, "ingenic_search")
      expect(primitive.required_scopes).to eq([Ingenic::Mcp::SCOPE])
      expect(primitive.annotations["readOnlyHint"]).to eq(true)
    end

    it "can run again without raising" do
      plugin =
        Discourse.plugins.find do |candidate|
          candidate.name == "discourse-ingenic"
        end

      expect { described_class.register!(plugin) }.not_to raise_error
    end
  end

  describe Ingenic::Mcp::Tools::Search do
    it "finds a page and returns its absolute address" do
      result =
        call(described_class, "query" => "USB boot").dig(
          :structuredContent,
          :results
        ).first

      expect(result[:kind]).to eq("documentation")
      expect(result[:title]).to eq("Flashing the image")
      expect(result[:url]).to eq(
        "#{Discourse.base_url}/ingenic/docs/t-series/t33/1.0/flash-image"
      )
    end

    it "answers a query with nothing but spaces with a tool error" do
      expect { call(described_class, "query" => "  ") }.to raise_error(
        DiscourseMcp::ToolError
      )
    end

    it "reports how many results it returned" do
      answer = call(described_class, "query" => "USB boot")

      expect(answer[:structuredContent][:count]).to eq(1)
      expect(answer[:structuredContent][:locale]).to eq("en")
    end
  end

  describe Ingenic::Mcp::Tools::ListDocumentation do
    it "returns the product tree when no chip is named" do
      answer = call(described_class)[:structuredContent]

      expect(answer[:series].first[:slug]).to eq("t-series")
      expect(answer[:chip]).to be_nil
      expect(answer[:pages]).to be_empty
    end

    it "returns the table of contents when a chip is named" do
      answer = call(described_class, "chip" => "t33")[:structuredContent]

      expect(answer[:chip][:slug]).to eq("t33")
      expect(answer[:version][:slug]).to eq("1.0")
      expect(answer[:pages].map { |page| page[:slug] }).to eq(
        %w[flash-image getting-started]
      )
    end

    it "turns a missing chip into a message rather than a crash" do
      expect { call(described_class, "chip" => "nope") }.to raise_error(
        DiscourseMcp::ToolError,
        /No published Ingenic chip named nope/
      )
    end
  end

  describe Ingenic::Mcp::Tools::ReadDocumentationPage do
    it "returns the page and the one after it" do
      answer =
        call(described_class, "chip" => "t33", "page" => "flash-image")[
          :structuredContent
        ]

      expect(answer[:page][:body]).to eq("Use the USB boot tool.")
      expect(answer[:next][:slug]).to eq("getting-started")
      expect(answer[:previous]).to be_nil
    end
  end

  describe Ingenic::Mcp::Tools::ListDownloads do
    it "returns the catalogue under the URL a reader would open" do
      IngenicDownload.create!(
        name: "T33 SDK",
        product: chip,
        locale: "en",
        access_level: IngenicDownload::LOGIN_ONLY
      )

      answer = call(described_class)[:structuredContent]

      expect(answer[:downloads_url]).to eq(
        "#{Discourse.base_url}/ingenic/downloads"
      )
      expect(answer[:downloads].first[:name]).to eq("T33 SDK")
    end
  end

  describe Ingenic::Mcp::Tools::ListBoards do
    it "returns the board catalogue under its own URL" do
      IngenicBoard.create!(
        slug: "halley-t33",
        name: "Halley T33",
        kind: "board",
        product: chip
      )

      answer = call(described_class)[:structuredContent]

      expect(answer[:boards_url]).to eq("#{Discourse.base_url}/ingenic/boards")
      expect(answer[:boards].first[:name]).to eq("Halley T33")
    end
  end
end
