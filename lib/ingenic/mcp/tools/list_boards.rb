# frozen_string_literal: true

module Ingenic
  module Mcp
    module Tools
      # The board and sample catalogue: what exists, for which chip, and where
      # the site sends someone who wants one. The forum never takes the order,
      # so the links are the answer, not a checkout.
      class ListBoards
        IDENTIFIER = "ingenic_list_boards"
        TITLE = "List Ingenic development boards"
        DESCRIPTION = <<~TEXT.strip
          List Ingenic's published development boards and sample chips, with
          the chip and series each belongs to, its description and
          specifications, whether it is sold out, and the apply and purchase
          links the catalogue card offers. The forum does not take orders; send
          the reader to those links.
        TEXT

        SCOPE = Ingenic::Mcp.scope("boards")
        REQUIRED_SCOPES = [SCOPE].freeze

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
            boards_url: DiscourseMcp::OutputSchema::STRING,
            boards: DiscourseMcp::OutputSchema::OBJECT_ARRAY
          )

        def self.call(arguments:, request_context:)
          Support.guard do
            catalog = Support.catalog(arguments, request_context)
            Support.respond(catalog.boards)
          end
        end
      end
    end
  end
end
