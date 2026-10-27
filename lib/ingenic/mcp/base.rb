# frozen_string_literal: true

module Ingenic
  module Mcp
    # One scope for everything the developer centre exposes over MCP. The tools
    # are read-only and all three catalogues are public on the site, so a single
    # scope keeps an administrator's grant list short — but it is deliberately
    # not `mcp:content:read`: an integration that is allowed to read the
    # developer centre has no business reading posts, and vice versa.
    SCOPE = "mcp:developer-centre:read"

    # Raised by Ingenic::Mcp::Catalog when a name in the arguments resolves to
    # nothing. The catalogue does not know how to phrase a tool error, and the
    # tools do not know how to walk the product tree, so the key travels between
    # them and the tool translates it.
    class NotFound < StandardError
      attr_reader :key, :params

      def initialize(key, **params)
        @key = key
        @params = params
        super(key.to_s)
      end
    end
  end
end
