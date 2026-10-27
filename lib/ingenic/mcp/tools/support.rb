# frozen_string_literal: true

module Ingenic
  module Mcp
    module Tools
      # What every tool in this set shares: which language to answer in, how a
      # name that resolves to nothing is reported, and the shape a successful
      # answer takes.
      module Support
        module_function

        # The catalogue follows the reader's language unless the caller names
        # one. A client speaking for a person uses the reader's locale; an
        # integration running on its own gets the site default through
        # Ingenic::Locales.reading.
        def catalog(arguments, request_context)
          Catalog.new(locale: locale_for(arguments, request_context))
        end

        def locale_for(arguments, request_context)
          arguments["locale"].presence || request_context.user&.effective_locale
        end

        # The catalogue reports a missing name by key; the tool turns it into
        # the message the model will read.
        def guard
          yield
        rescue NotFound => error
          raise DiscourseMcp::ToolError,
                I18n.t(
                  "ingenic.mcp.errors.#{error.key}",
                  **error.params,
                  default: error.key.to_s.humanize
                )
        end

        def respond(value)
          DiscourseMcp::ToolHelpers.text_and_structured(value)
        end

        def url(path)
          "#{Discourse.base_url.chomp("/")}#{path}"
        end
      end
    end
  end
end
