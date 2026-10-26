# frozen_string_literal: true

require "rails_helper"

# The form definition is read by the visitor's page, the validation and the
# admin's summary, so it is tested once here rather than separately in each.
describe Ingenic::DeveloperForm do
  after { SiteSetting.ingenic_developer_form_fields = "" }

  it "asks everyone the same questions, in one order" do
    expect(described_class.fields.map { |field| field[:key].to_s }).to eq(
      %w[
        identity
        full_name
        country
        contact_email
        use_case
        project_stage
        company
        job_title
        school
        major
      ],
    )
  end

  it "asks the company questions only of a company" do
    company = described_class.errors_for("identity" => "company")
    expect(company.join).to include(I18n.t("ingenic.developer_form.fields.company"))
    expect(company.join).not_to include(I18n.t("ingenic.developer_form.fields.school"))

    individual = described_class.errors_for("identity" => "individual")
    expect(individual.join).not_to include(I18n.t("ingenic.developer_form.fields.company"))
  end

  it "asks the universal questions before it knows the identity" do
    errors = described_class.errors_for({})

    expect(errors).to include(I18n.t("ingenic.developer_form.missing", field: "I am a"))
    expect(errors.join).not_to include(I18n.t("ingenic.developer_form.fields.company"))
  end

  it "refuses an identity it does not offer" do
    errors = described_class.errors_for("identity" => "partner")

    expect(errors).to include(
      I18n.t(
        "ingenic.developer_form.invalid_option",
        field: I18n.t("ingenic.developer_form.fields.identity"),
      ),
    )
  end

  it "refuses an email that is not an address" do
    errors = described_class.errors_for("identity" => "individual", "contact_email" => "not-an-email")

    expect(errors).to include(
      I18n.t(
        "ingenic.developer_form.invalid_email",
        field: I18n.t("ingenic.developer_form.fields.contact_email"),
      ),
    )
  end

  it "adds the site's own questions without letting them replace the core ones" do
    SiteSetting.ingenic_developer_form_fields = [
      { "key" => "full_name", "label" => "Name", "type" => "text" },
      { "key" => "team_size", "label" => "Team size", "type" => "text" },
      { "key" => "phone_number", "label" => "Phone", "type" => "text" },
    ].to_json

    keys = described_class.fields.map { |field| field[:key].to_s }

    expect(keys).to include("team_size")
    expect(keys.count("full_name")).to eq(1)
    expect(keys).not_to include("phone_number")
  end

  it "reads the labels in the reader's language" do
    I18n.with_locale(:zh_CN) do
      expect(described_class.fields.first[:label]).to eq("您的身份")
    end
  end

  it "keeps only the answers it asked for" do
    answers = described_class.normalize("full_name" => "  Ada  ", "injected" => "<script>")

    expect(answers["full_name"]).to eq("Ada")
    expect(answers).not_to have_key("injected")
  end
end
