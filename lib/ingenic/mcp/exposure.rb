# frozen_string_literal: true

module Ingenic
  module Mcp
    # Puts the developer centre's read-only tools into core's MCP registry.
    #
    # Core keeps one registry per process and a plugin adds to it the same way
    # core's own primitives are added — through the plugin instance, which also
    # ties each primitive's availability to the plugin being enabled. Nothing
    # becomes reachable by this alone: an administrator still has to enable the
    # primitives under Admin → MCP → Capabilities, and grant the scope to a
    # group under Access. That is deliberate on core's part, and it is the right
    # default for a surface that outside clients can call.
    module Exposure
      READ_ONLY = {
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false
      }.freeze

      TOOLS = [
        Tools::Search,
        Tools::ListDocumentation,
        Tools::ReadDocumentationPage,
        Tools::ListDownloads,
        Tools::ListBoards
      ].freeze

      module_function

      def register!(plugin)
        return if !defined?(DiscourseMcp::Registry)

        TOOLS.each do |implementation|
          identifier = implementation::IDENTIFIER
          # after_initialize is not meant to run twice in one process, but a
          # duplicated registry entry raises and takes the whole boot down. A
          # cheap check here is worth more than that failure mode.
          next if DiscourseMcp.registry.find(:tool, identifier)

          plugin.register_mcp_tool(
            identifier,
            title: implementation::TITLE,
            description: implementation::DESCRIPTION,
            implementation:,
            input_schema: implementation::INPUT_SCHEMA,
            output_schema: implementation::OUTPUT_SCHEMA,
            required_scopes: implementation::REQUIRED_SCOPES,
            annotations: READ_ONLY,
            risk: :read
          )
        end
      end
    end
  end
end
