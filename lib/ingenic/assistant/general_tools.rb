# frozen_string_literal: true

module Ingenic
  module Assistant
    # Binds the developer centre to Discourse AI's Forum Helper.
    #
    # The tool cannot be attached through settings. Forum Helper is a system
    # agent: its tool list is written in Ruby, and AiAgent refuses to save a
    # different one (`system_agent_unchangeable`), so a plugin that wants it to
    # know about another source has to add the tool where the list is built.
    #
    # `prepend` and `super` rather than replacing the list: whatever Discourse
    # AI ships stays there, and a later release adding or dropping a tool does
    # not have to be mirrored here.
    module GeneralTools
      def tools
        return super unless defined?(DiscourseAi::Agents::Tools::SearchIngenic)

        super | [DiscourseAi::Agents::Tools::SearchIngenic]
      end
    end
  end
end
