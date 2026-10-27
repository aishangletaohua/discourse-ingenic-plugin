# frozen_string_literal: true

require "rails_helper"

describe Ingenic::Assistant::GeneralTools do
  def tool_names
    DiscourseAi::Agents::General.new.tools.map { |tool| tool.name.to_s }
  end

  it "gives Forum Helper the developer-centre search" do
    expect(tool_names).to include("search_ingenic")
  end

  it "leaves the assistant's own tools in place" do
    expect(tool_names).to include("search", "read", "categories")
  end

  it "takes the developer centre away when the switch is off" do
    SiteSetting.ingenic_assistant_search_enabled = false

    expect(tool_names).not_to include("search_ingenic")
    expect(tool_names).to include("search")
  end
end
