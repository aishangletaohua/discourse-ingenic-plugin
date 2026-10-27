# frozen_string_literal: true

module Admin
  module Ingenic
    # Forum Helper — the forum's own AI assistant.
    #
    # It is a system agent: Discourse AI builds it from Ruby and refuses to
    # change it (`system_agent_unchangeable`), so the agent editor is the wrong
    # place to look for it and the wrong place to switch it off. This screen
    # reports what the assistant actually is and offers the two switches an
    # administrator needs: whether it answers at all, and whether it can read
    # the developer centre.
    #
    # The knowledge switch is a site setting rather than a column here because
    # the tool list is built in Ruby on every call; the agent switch goes to the
    # agent's own record because that is what Discourse AI reads when it decides
    # whether the bot is available.
    class AssistantController < BaseController
      def show
        authorize_admin_only!

        render_json_dump(assistant_json)
      end

      def update
        authorize_admin_only!

        if params.key?(:search_enabled)
          SiteSetting.ingenic_assistant_search_enabled =
            boolean_param(params[:search_enabled], true)
        end

        if params.key?(:agent_enabled)
          if agent_record.blank?
            return(
              render_json_error(
                I18n.t("ingenic.admin_errors.assistant_unavailable"),
                status: 422,
              )
            )
          end

          agent_record.update!(
            enabled: boolean_param(params[:agent_enabled], true),
          )
        end

        render_json_dump(assistant_json)
      end

      private

      def ai_available?
        !!defined?(DiscourseAi::Agents::General)
      end

      def agent_record
        return if !ai_available?

        ::AiAgent.find_by(
          id: DiscourseAi::Agents::Agent.system_agents[DiscourseAi::Agents::General],
        )
      end

      def bot_enabled?
        SiteSetting.respond_to?(:ai_bot_enabled) && SiteSetting.ai_bot_enabled
      end

      # Whether the assistant's live tool list carries the developer centre
      # tool. Asked of the agent instance rather than of the module, so the
      # answer is what the bot will do on its next reply, not what the code
      # intends.
      def knowledge_attached?
        return false if !defined?(DiscourseAi::Agents::Tools::SearchIngenic)

        DiscourseAi::Agents::General.new.tools.any? do |tool|
          tool.name.to_s == "search_ingenic"
        end
      rescue StandardError
        false
      end

      def assistant_json
        agent = agent_record

        {
          available: ai_available?,
          bot_enabled: bot_enabled?,
          agent:
            agent && {
              id: agent.id,
              name: agent.name,
              enabled: agent.enabled?,
            },
          knowledge: {
            available: !!defined?(DiscourseAi::Agents::Tools::SearchIngenic),
            enabled: SiteSetting.ingenic_assistant_search_enabled,
            attached: knowledge_attached?,
          },
        }
      end
    end
  end
end
