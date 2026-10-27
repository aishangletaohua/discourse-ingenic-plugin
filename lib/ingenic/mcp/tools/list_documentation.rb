# frozen_string_literal: true

module Ingenic
  module Mcp
    module Tools
      # The product tree, and — once a chip is named — the table of contents a
      # reader of one version sees.
      #
      # The two halves are one tool because they are one question in two steps:
      # "what documentation is there" is answered by the series list, and
      # "what is in T33 1.1" is the same answer narrowed. A caller that knows
      # the chip goes straight there; a caller that does not reads the series
      # list first.
      class ListDocumentation
        IDENTIFIER = "ingenic_list_documentation"
        TITLE = "List Ingenic documentation"
        DESCRIPTION = <<~TEXT.strip
          List Ingenic's published documentation. Without `chip` it returns the
          product tree: every series, its chips and each chip's versions. With
          `chip` it returns that chip's versions and the table of contents of
          one version, in reading order, with the address of every page.
          Inherited pages are included at the version that resolves them;
          withdrawn sections are not.
        TEXT

        SCOPE = Ingenic::Mcp.scope("documentation")
        REQUIRED_SCOPES = [SCOPE].freeze

        NULLABLE_OBJECT = { type: %w[object null] }.freeze

        INPUT_SCHEMA = {
          type: "object",
          properties: {
            series: {
              type: "string",
              description:
                "Series slug, used to disambiguate a chip name. Optional."
            },
            chip: {
              type: "string",
              description:
                "Chip slug, such as t33. Omit to list the whole product tree."
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
          additionalProperties: false
        }.freeze

        OUTPUT_SCHEMA =
          DiscourseMcp::OutputSchema.object(
            locale: DiscourseMcp::OutputSchema::STRING,
            documentation_url: DiscourseMcp::OutputSchema::STRING,
            series: DiscourseMcp::OutputSchema::OBJECT_ARRAY,
            chip: NULLABLE_OBJECT,
            version: NULLABLE_OBJECT,
            pages: DiscourseMcp::OutputSchema::OBJECT_ARRAY
          )

        def self.call(arguments:, request_context:)
          Support.guard do
            catalog = Support.catalog(arguments, request_context)

            if arguments["chip"].blank?
              catalogue = catalog.catalogue
              return(
                Support.respond(
                  locale: catalogue[:locale],
                  documentation_url: catalogue[:documentation_url],
                  series: catalogue[:series],
                  chip: nil,
                  version: nil,
                  pages: []
                )
              )
            end

            document =
              catalog.chip_document(
                chip_slug: arguments["chip"],
                series_slug: arguments["series"].presence,
                version_slug: arguments["version"].presence
              )

            Support.respond(
              locale: document[:locale],
              documentation_url: document[:documentation_url],
              series: document[:series],
              chip: document[:chip],
              version: document[:version],
              pages: document[:pages]
            )
          end
        end
      end
    end
  end
end
