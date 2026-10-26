# frozen_string_literal: true

require "rails_helper"

# The form branches on identity, and the profile is where the branching has to
# hold: a company cannot be saved without a company name, a student without a
# school, and changing identity clears the answers that belonged to the old one.
describe IngenicDeveloperProfile do
  fab!(:user) { Fabricate(:user) }

  def profile(attributes = {})
    described_class.new(
      {
        user: user,
        identity: "individual",
        full_name: "Ada",
        country: "UK",
        contact_email: "ada@example.com",
        use_case: "Set-top boxes",
      }.merge(attributes),
    )
  end

  it "accepts an individual developer with the universal answers alone" do
    expect(profile).to be_valid
    expect(profile.complete?).to eq(true)
  end

  it "needs a company name for a company" do
    record = profile(identity: "company")

    expect(record).not_to be_valid
    expect(record.errors[:company]).to be_present
    expect(record.complete?).to eq(false)
  end

  it "needs a school for a student" do
    record = profile(identity: "student")

    expect(record).not_to be_valid
    expect(record.errors[:school]).to be_present
  end

  it "refuses an identity it does not offer" do
    record = profile(identity: "partner")

    expect(record).not_to be_valid
    expect(record.errors[:identity]).to be_present
  end

  it "refuses an email that is not an address" do
    record = profile(contact_email: "not-an-email")

    expect(record).not_to be_valid
    expect(record.errors[:contact_email]).to be_present
  end

  it "is not complete while a newly required answer is missing" do
    record = profile(country: nil)

    expect(record.complete?).to eq(false)
  end

  it "clears the answers that belonged to the identity it left" do
    record = profile(identity: "company", company: "Acme", job_title: "Engineer")
    record.apply_answers(
      {
        "identity" => "individual",
        "full_name" => "Ada",
        "country" => "UK",
        "contact_email" => "ada@example.com",
        "use_case" => "Set-top boxes",
      },
    )

    expect(record.identity).to eq("individual")
    expect(record.company).to be_nil
    expect(record.job_title).to be_nil
  end

  it "stores an extra answer in the document and returns it with the rest" do
    SiteSetting.ingenic_developer_form_fields = [
      { "key" => "team_size", "label" => "Team size", "type" => "text" },
    ].to_json

    record = profile
    record.apply_answers(
      record.answers.merge(
        "identity" => "individual",
        "full_name" => "Ada",
        "country" => "UK",
        "contact_email" => "ada@example.com",
        "use_case" => "Set-top boxes",
        "team_size" => "12",
      ),
    )

    expect(record.data).to eq("team_size" => "12")
    expect(record.value_for("team_size")).to eq("12")
    expect(record.answers["full_name"]).to eq("Ada")
  end

  it "reads a core answer from its column even if the document holds a stale copy" do
    record = profile(identity: "company", company: "Acme")
    record.data = { "company" => "Old Name" }

    expect(record.value_for("company")).to eq("Acme")
    expect(record.answers["company"]).to eq("Acme")
  end

  it "names the identity in the summary instead of its stored value" do
    record = profile(identity: "company", company: "Acme")

    expect(record.summary).to include("I am a: Company")
  end
end
