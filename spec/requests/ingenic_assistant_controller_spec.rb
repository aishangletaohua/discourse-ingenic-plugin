# frozen_string_literal: true

require "rails_helper"

describe Admin::Ingenic::AssistantController do
  fab!(:admin) { Fabricate(:admin) }
  fab!(:moderator) { Fabricate(:moderator) }

  let(:endpoint) { "/admin/plugins/discourse-ingenic/assistant" }

  before { sign_in(admin) }

  describe "GET /admin/plugins/discourse-ingenic/assistant" do
    it "reports the assistant, the bot switch and the knowledge switch" do
      get "#{endpoint}.json"

      expect(response.status).to eq(200)

      body = response.parsed_body
      expect(body["available"]).to eq(true)
      expect(body["bot_enabled"]).to eq(SiteSetting.ai_bot_enabled)
      expect(body["agent"]).to include("id" => -1, "name" => "Forum Helper")
      expect(body["knowledge"]).to include(
        "available" => true,
        "enabled" => true,
        "attached" => true,
      )
    end
  end

  describe "PUT /admin/plugins/discourse-ingenic/assistant" do
    it "takes the developer centre away from the assistant without disabling it" do
      put "#{endpoint}.json", params: { search_enabled: false }

      expect(response.status).to eq(200)
      expect(SiteSetting.ingenic_assistant_search_enabled).to eq(false)
      expect(response.parsed_body["knowledge"]["attached"]).to eq(false)
      expect(AiAgent.find(-1).enabled).to eq(true)
    end

    it "switches the assistant itself off and back on" do
      put "#{endpoint}.json", params: { agent_enabled: false }

      expect(response.status).to eq(200)
      expect(AiAgent.find(-1).enabled).to eq(false)
      expect(response.parsed_body["agent"]["enabled"]).to eq(false)

      put "#{endpoint}.json", params: { agent_enabled: true }

      expect(AiAgent.find(-1).enabled).to eq(true)
    end

    it "answers with the state it saved, not with what it was asked for" do
      put "#{endpoint}.json", params: { search_enabled: false }

      expect(response.parsed_body["knowledge"]["enabled"]).to eq(false)
    end
  end

  describe "authorization" do
    it "is an administrator's screen, not a content manager's" do
      sign_in(moderator)

      get "#{endpoint}.json"

      expect(response.status).to eq(404)
    end
  end
end
