# frozen_string_literal: true

module Ingenic
  module Mcp
    module Tools
      # One page of the manual, as the site's own reader would see it at that
      # version — including the version it was inherited from, if it was.
      class ReadDocumentationPage
        IDENTIFIER = "ingenic_read_documentation_page"
        TITLE = "Read an Ingenic documentation page"
        DESCRIPTION = <<~TEXT.strip
          Read one page of Ingenic's online documentation as Markdown, at a
          given chip and version. Use ingenic_list_documentation to discover
          slugs. The answer includes the page either side in reading order and
          says which version the text was inherited from when the version named
          did not edit it.
        TEXT

        SCOPE = Ingenic::Mcp.scope("documentation-page")
        REQUIRED_SCOPES = [SCOPE].freeze

        NULLABLE_OBJECT = { type: %w[object null] }.freeze

        INPUT_SCHEMA = {
          type: "object",
          properties: {
            chip: {
              type: "string",
              description: "Chip slug, such as t33."
            },
            page: {
              type: "string",
              description: "Page slug, as listed by ingenic_list_documentation."
            },
            series: {
              type: "string",
              description:
                "Series slug, used to disambiguate a chip name. Optional."
            },
            version: {
              type: "string",
              description:
                "Version slug, or latest. Defaults to the chip's latest version."
            },
            locale: {
              type: "string",
              description:
                "Catalogue language, such as en or zh_CN. Defaults to the reader's language."
            }
          },
          required: %w[chip page],
          additionalProperties: false
        }.freeze

        OUTPUT_SCHEMA =
          DiscourseMcp::OutputSchema.object(
            locale: DiscourseMcp::OutputSchema::STRING,
            series: DiscourseMcp::OutputSchema::OBJECT,
            chip: DiscourseMcp::OutputSchema::OBJECT,
            version: DiscourseMcp::OutputSchema::OBJECT,
            url: DiscourseMcp::OutputSchema::STRING,
            page: DiscourseMcp::OutputSchema::OBJECT,
            previous: NULLABLE_OBJECT,
            next: NULLABLE_OBJECT
          )

        def self.call(arguments:, request_context:)
          Support.guard do
            catalog = Support.catalog(arguments, request_context)
            document =
              catalog.page(
                chip_slug: arguments["chip"],
                page_slug: arguments["page"],
                series_slug: arguments["series"].presence,
                version_slug: arguments["version"].presence
              )

            Support.respond(document)
          end
        end
      end
    end
  end
end
