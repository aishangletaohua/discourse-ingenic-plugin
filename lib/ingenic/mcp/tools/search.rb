# frozen_string_literal: true

module Ingenic
  module Mcp
    module Tools
      # One query across the documentation, the download catalogue and the
      # boards, ranked together. It is the same search the forum's own assistant
      # uses, so an outside client and the floating robot agree about what the
      # developer centre contains.
      class Search
        IDENTIFIER = "ingenic_search"
        TITLE = "Search the Ingenic developer centre"
        DESCRIPTION = <<~TEXT.strip
          Search Ingenic's online documentation, SDK and firmware downloads, and
          development boards. Call this before answering any question about an
          Ingenic chip, SDK, firmware, board or sample. Results are ordered by
          relevance and carry the page address a person would open.
        TEXT

        SCOPE = Ingenic::Mcp.scope("search")
        REQUIRED_SCOPES = [SCOPE].freeze

        INPUT_SCHEMA = {
          type: "object",
          properties: {
            query: {
              type: "string",
              minLength: 2,
              description: "Words to look for, in any supported language."
            },
            scope: {
              type: "string",
              enum: Ingenic::Assistant::Search::SCOPES,
              description:
                "Restrict the search to one catalogue. Defaults to all."
            },
            limit: {
              type: "integer",
              minimum: 1,
              maximum: Ingenic::Assistant::Search::MAX_LIMIT,
              description:
                "How many results to return. Defaults to #{Ingenic::Assistant::Search::DEFAULT_LIMIT}."
            },
            locale: {
              type: "string",
              description:
                "Catalogue language, such as en or zh_CN. Defaults to the reader's language."
            }
          },
          required: %w[query],
          additionalProperties: false
        }.freeze

        OUTPUT_SCHEMA =
          DiscourseMcp::OutputSchema.object(
            query: DiscourseMcp::OutputSchema::STRING,
            locale: DiscourseMcp::OutputSchema::STRING,
            count: DiscourseMcp::OutputSchema::INTEGER,
            results: DiscourseMcp::OutputSchema::OBJECT_ARRAY
          )

        def self.call(arguments:, request_context:)
          Support.guard do
            query = arguments["query"].to_s.strip
            if query.length < Ingenic::Assistant::Search::MIN_QUERY_LENGTH
              raise NotFound.new(:query_too_short)
            end

            catalog = Support.catalog(arguments, request_context)
            results =
              Ingenic::Assistant::Search.new(
                query:,
                user: request_context.user,
                locale: catalog.locale,
                scope: arguments.fetch("scope", "all"),
                limit:
                  arguments.fetch(
                    "limit",
                    Ingenic::Assistant::Search::DEFAULT_LIMIT
                  )
              ).results

            Support.respond(
              query:,
              locale: catalog.locale,
              count: results.length,
              results:
                results.map do |result|
                  {
                    kind: result.kind.to_s,
                    title: result.title,
                    url: Support.url(result.path),
                    excerpt: result.excerpt,
                    description: result.meta
                  }
                end
            )
          end
        end
      end
    end
  end
end
