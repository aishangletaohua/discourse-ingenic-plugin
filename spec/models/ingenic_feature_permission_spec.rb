# frozen_string_literal: true

require "rails_helper"

# A row here says "this account or group may manage this whole screen". The
# screen vocabulary is closed, so a typo is a validation failure rather than a
# grant that silently matches nothing, and exactly one principal is named so a
# grant cannot be both an account's and a group's.
describe IngenicFeaturePermission do
  fab!(:group) { Fabricate(:group) }
  fab!(:user) { Fabricate(:user) }

  it "requires a known feature" do
    expect(described_class.new(group: group, feature: "documentation")).to be_valid
    expect(described_class.new(group: group, feature: "everything")).not_to be_valid
  end

  it "refuses the same group and feature twice" do
    described_class.create!(group: group, feature: "downloads")

    expect(described_class.new(group: group, feature: "downloads")).not_to be_valid
  end

  it "refuses the same account and feature twice" do
    described_class.create!(user: user, feature: "downloads")

    expect(described_class.new(user: user, feature: "downloads")).not_to be_valid
  end

  it "allows one group to hold several screens" do
    described_class.create!(group: group, feature: "downloads")
    described_class.create!(group: group, feature: "points")

    expect(described_class.where(group: group).count).to eq(2)
  end

  it "allows one account to hold several screens" do
    described_class.create!(user: user, feature: "downloads")
    described_class.create!(user: user, feature: "files")

    expect(described_class.where(user: user).count).to eq(2)
  end

  it "names exactly one principal" do
    expect(described_class.new(feature: "downloads")).not_to be_valid
    expect(described_class.new(user: user, group: group, feature: "downloads")).not_to be_valid
  end

  it "offers only groups an administrator can meaningfully tick" do
    names = described_class.assignable_groups.map(&:name)

    expect(names).to include(group.name)
    expect(names).not_to include("everyone")
    expect(names).not_to include("admins")
    expect(names).not_to include("trust_level_0")
  end
end
