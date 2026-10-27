# frozen_string_literal: true

module Ingenic
  module Mcp
    # Every tool carries its own scope, so an administrator can hand the
    # documentation to everybody and the SDK catalogue to one partner group
    # without handing over both. They share a prefix for the same reason: the
    # MCP access screen groups scopes by name, and these belong together.
    #
    # None of them is `mcp:content:read`: an integration allowed to read the
    # developer centre has no business reading posts, and vice versa.
    SCOPE_PREFIX = "mcp:developer-centre"

    def self.scope(name)
      "#{SCOPE_PREFIX}:#{name}"
    end

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
