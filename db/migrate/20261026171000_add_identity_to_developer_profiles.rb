# frozen_string_literal: true

# The developer form now branches on who is answering: a company, a student or
# an individual developer. The answers they share are the ones the team sorts
# and reads, so they move out of the `data` document and into columns. Anything
# a site adds on top of the form stays in `data`.
#
# Existing profiles are carried over rather than discarded. The identity is
# inferred from what they already said — a company answer makes them a company,
# a school answer a student, anything else an individual developer — and the old
# keys are then removed from `data` so an answer has exactly one home.
#
# The checks make the columns tell the truth even when a console session or an
# import skips the model: an identity outside the three, a company without a
# company name, or a student without a school is refused by the table itself.
class AddIdentityToDeveloperProfiles < ActiveRecord::Migration[7.2]
  CORE_COLUMNS = %w[
    full_name
    country
    contact_email
    use_case
    project_stage
    company
    job_title
    school
    major
  ].freeze

  ALL_COLUMNS = (["identity"] + CORE_COLUMNS).freeze

  def up
    add_column :ingenic_developer_profiles, :identity, :string
    CORE_COLUMNS.each { |column| add_column :ingenic_developer_profiles, column, :text }

    execute <<~SQL
      UPDATE ingenic_developer_profiles
      SET identity = CASE
            WHEN data->>'identity' IN ('company', 'student', 'individual')
              THEN data->>'identity'
            WHEN NULLIF(btrim(COALESCE(data->>'company', '')), '') IS NOT NULL
              THEN 'company'
            WHEN NULLIF(btrim(COALESCE(data->>'school', '')), '') IS NOT NULL
              THEN 'student'
            ELSE 'individual'
          END,
          full_name = NULLIF(btrim(COALESCE(data->>'full_name', '')), ''),
          country = NULLIF(btrim(COALESCE(data->>'country', '')), ''),
          contact_email = NULLIF(btrim(COALESCE(data->>'contact_email', '')), ''),
          use_case = NULLIF(btrim(COALESCE(data->>'use_case', '')), ''),
          project_stage = NULLIF(btrim(COALESCE(data->>'project_stage', '')), ''),
          company = NULLIF(btrim(COALESCE(data->>'company', '')), ''),
          job_title = NULLIF(btrim(COALESCE(data->>'job_title', '')), ''),
          school = NULLIF(btrim(COALESCE(data->>'school', '')), ''),
          major = NULLIF(btrim(COALESCE(data->>'major', '')), '')
    SQL

    change_column_null :ingenic_developer_profiles, :identity, false

    add_check_constraint :ingenic_developer_profiles,
                         "identity IN ('company', 'student', 'individual')",
                         name: "ingenic_developer_profiles_identity_known"
    add_check_constraint :ingenic_developer_profiles,
                         "identity <> 'company' OR (company IS NOT NULL AND btrim(company) <> '')",
                         name: "ingenic_developer_profiles_company_required"
    add_check_constraint :ingenic_developer_profiles,
                         "identity <> 'student' OR (school IS NOT NULL AND btrim(school) <> '')",
                         name: "ingenic_developer_profiles_school_required"

    # Answers now have a column, so the document keeps only the extra questions.
    execute <<~SQL
      UPDATE ingenic_developer_profiles
      SET data = data - ARRAY[#{ALL_COLUMNS.map { |column| "'#{column}'" }.join(", ")}]::text[]
    SQL
  end

  def down
    remove_check_constraint :ingenic_developer_profiles,
                            name: "ingenic_developer_profiles_school_required"
    remove_check_constraint :ingenic_developer_profiles,
                            name: "ingenic_developer_profiles_company_required"
    remove_check_constraint :ingenic_developer_profiles,
                            name: "ingenic_developer_profiles_identity_known"

    # The answers are not copied back into `data`: they would be a second copy
    # of a form the down migration cannot know the shape of, and the old form
    # would then be reading some fields from a document and writing all of them
    # into it. Rolling back loses the answers, which is why it is a deliberate
    # rollback step rather than something the code does.
    ALL_COLUMNS.each { |column| remove_column :ingenic_developer_profiles, column }
  end
end
