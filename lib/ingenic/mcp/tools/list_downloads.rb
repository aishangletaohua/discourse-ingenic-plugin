# frozen_string_literal: true

module Ingenic
  module Mcp
    module Tools
      # What the download centre offers. The catalogue is metadata on purpose:
      # it names the access rule each card applies and the address of the card,
      # and never the file itself, so an integration cannot walk around the
      # approval the download centre exists to give.
      class ListDownloads
        IDENTIFIER = "ingenic_list_downloads"
        TITLE = "List Ingenic SDK and firmware downloads"
        DESCRIPTION = <<~TEXT.strip
          List Ingenic's published SDK and firmware downloads with their
          releases, platform, architecture, size and checksum. Each entry says
          what the card requires before the file opens — sign-in, developer
          information, or an approved application — and how many points it
          costs. The file is not part of this answer: send the reader to the
          download centre at `url` to claim it.
        TEXT

        REQUIRED_SCOPES = [Ingenic::Mcp::SCOPE].freeze

        INPUT_SCHEMA = {
          type: "object",
          properties: {
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
            downloads_url: DiscourseMcp::OutputSchema::STRING,
            downloads: DiscourseMcp::OutputSchema::OBJECT_ARRAY
          )

        def self.call(arguments:, request_context:)
          Support.guard do
            catalog = Support.catalog(arguments, request_context)
            Support.respond(catalog.downloads)
          end
        end
      end
    end
  end
end
