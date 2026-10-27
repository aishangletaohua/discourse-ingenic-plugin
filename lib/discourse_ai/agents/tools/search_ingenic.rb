# frozen_string_literal: true

# A tool for Discourse AI's Forum Helper, so the assistant can reach the
# developer centre this plugin publishes.
#
# The class lives under Discourse AI's namespace because that is how
# AiAgent#class_instance looks tools up: the name stored on the agent is
# "search_ingenic", and the class is constantised from the catalogue it was
# registered into. The file itself is loaded by the plugin, and only when
# Discourse AI is present.
module DiscourseAi
  module Agents
    module Tools
      class SearchIngenic < Tool
        def self.signature
          {
            name: "search_ingenic",
            description:
              "Search the Ingenic developer centre: the documentation manuals, " \
                "the SDK / firmware download catalogue and the development boards. Use this " \
                "before answering any question about Ingenic chips, SDKs, firmware, tools or " \
                "boards — the forum's own search does not index these pages. Write technical " \
                "answers from the documentation it returns and link to the exact page.",
            parameters: [
              {
                name: "query",
                description:
                  "What the reader is looking for, in the words they used. A chip model and a " \
                    "topic work well, for example \"T33 SDK\" or \"SDK download\".",
                type: "string",
                required: true,
              },
              {
                name: "scope",
                description:
                  "Where to look. \"all\" searches everything and is usually right. Use " \
                    "\"documentation\" when the answer is an explanation or a procedure, " \
                    "\"downloads\" when the reader wants a file, and \"boards\" when they want " \
                    "hardware.",
                type: "string",
                enum: %w[all documentation downloads boards],
              },
              {
                name: "limit",
                description:
                  "How many results to return, 1 to 12. Leave it out unless the reader asks for " \
                    "more or fewer.",
                type: "integer",
              },
            ],
          }
        end

        def self.name
          "search_ingenic"
        end

        def self.help
          I18n.t(
            "ingenic.assistant.tool.help",
            default: "Search the Ingenic documentation, download catalogue and development boards.",
          )
        end

        def summary
          I18n.t("ingenic.assistant.tool.summary", default: "Search the Ingenic developer centre")
        end

        def details
          I18n.t(
            "ingenic.assistant.tool.details",
            query: query,
            default: "Searching the developer centre for “%{query}”",
          )
        end

        def query
          parameters[:query].to_s.strip
        end

        def scope
          value = parameters[:scope].to_s
          Ingenic::Assistant::Search::SCOPES.include?(value) ? value : "all"
        end

        def invoke
          return error_response("A query is required.") if query.blank?
          return error_response(search_unavailable) if !defined?(Ingenic::Assistant::Search)

          if block_given?
            yield(I18n.t("ingenic.assistant.tool.progress", default: "Reading the documentation"))
          end

          results =
            Ingenic::Assistant::Search.new(
              query: query,
              user: user,
              scope: scope,
              limit: limit,
            ).results

          return { results: [], message: start_here } if results.empty?

          format_results(
            results.map do |result|
              {
                title: result.title,
                type: type_label(result.kind),
                link: absolute(result.path),
                excerpt: result.excerpt,
                details: result.meta,
              }
            end,
            args: {
              query: query,
            },
          )
        end

        private

        def user
          context.user
        end

        def limit
          requested = parameters[:limit].to_i
          requested.positive? ? requested : Ingenic::Assistant::Search::DEFAULT_LIMIT
        end

        def absolute(path)
          "#{Discourse.base_url.chomp("/")}#{path}"
        end

        def type_label(kind)
          I18n.t("ingenic.assistant.tool.kind.#{kind}", default: kind.to_s.capitalize)
        end

        # Told to the model rather than to the reader: it is the difference
        # between "the forum has nothing" and "the answer is in a catalogue
        # the assistant cannot format as a post".
        def start_here
          I18n.t(
            "ingenic.assistant.tool.no_results",
            docs: absolute("/ingenic/docs"),
            downloads: absolute("/ingenic/downloads"),
            boards: absolute("/ingenic/boards"),
            default:
              "Nothing matched. Tell the reader so, and point them at the developer " \
                "centre to browse: %{docs}, %{downloads} and %{boards}.",
          )
        end

        def search_unavailable
          I18n.t(
            "ingenic.assistant.tool.unavailable",
            default: "The developer centre is not available on this site.",
          )
        end
      end
    end
  end
end
