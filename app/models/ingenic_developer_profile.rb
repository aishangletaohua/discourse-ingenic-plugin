# frozen_string_literal: true

# The information a developer supplies once in exchange for access to gated
# downloads.
#
# A profile is filled in once and reused for every resource at the "login plus
# information" level and above, which is the point of the tier: the team wants
# to know who is downloading, not to interrogate them per file.
#
# The questions branch on identity. Everyone is asked who they are and what
# they are building; a company is then asked about the company, a student about
# the school, and an individual developer nothing more. The universal answers
# live in columns because they are the ones the team filters and reads, while
# anything the site has added to the form stays in `data`.
class IngenicDeveloperProfile < ActiveRecord::Base
  self.table_name = "ingenic_developer_profiles"

  CORE_COLUMNS = %w[
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
  ].freeze

  # Required, and deleted with the account rather than kept without it. The
  # ledger keeps a deleted member's movements because the forum's books are not
  # about that person; a profile is the opposite — it is answers about somebody,
  # collected for the team to read, and there is no reading to be done once they
  # are gone.
  belongs_to :user

  validates :user_id, uniqueness: true
  validates :identity, inclusion: { in: Ingenic::DeveloperForm::IDENTITIES }
  validates :full_name, :country, :contact_email, :use_case, presence: true
  validates :contact_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :company, presence: true, if: -> { identity == "company" }
  validates :school, presence: true, if: -> { identity == "student" }

  def self.for(user)
    return nil if user.nil?

    find_by(user_id: user.id)
  end

  # Every answer, universal ones from their columns and any site-added ones from
  # the document. Columns win: they are the constrained copy.
  def answers
    data.to_h.except(*CORE_COLUMNS).merge(
      CORE_COLUMNS.index_with { |column| public_send(column) }.compact,
    )
  end

  def value_for(key)
    key = key.to_s
    return public_send(key) if CORE_COLUMNS.include?(key)

    data.to_h[key]
  end

  # Takes the normalised answers and writes them where they belong. A question
  # that is not shown for the chosen identity is cleared rather than left
  # behind: an individual developer who used to work at a company should not
  # keep that company on file, and an old answer must not reappear if they
  # switch back.
  def apply_answers(answers)
    incoming = answers.to_h.stringify_keys

    CORE_COLUMNS.each { |column| public_send("#{column}=", incoming[column]) }

    unless identity == "company"
      self.company = nil
      self.job_title = nil
    end
    unless identity == "student"
      self.school = nil
      self.major = nil
    end

    extra = data.to_h.except(*CORE_COLUMNS)
    Ingenic::DeveloperForm.extra_fields.each do |field|
      key = field[:key].to_s
      next unless Ingenic::DeveloperForm.visible?(field, incoming)

      if incoming[key].present?
        extra[key] = incoming[key]
      else
        extra.delete(key)
      end
    end
    self.data = extra

    self
  end

  # Stored is not the same as answered: a profile written before this form
  # gained a question would otherwise pass as complete and open the download
  # without the new answer ever being given.
  def complete?
    identity.present? && Ingenic::DeveloperForm.errors_for(answers).empty?
  end

  # A one-line summary for the admin queue, without assuming which extra
  # questions the site has added: it walks the configured order and takes the
  # first few answers.
  def summary(limit: 3)
    Ingenic::DeveloperForm.fields
      .filter_map do |field|
        value = value_for(field[:key])
        next if value.blank?

        value = Ingenic::DeveloperForm.option_label(field, value)
        "#{field[:label]}: #{value}"
      end
      .first(limit)
      .join(" · ")
  end
end
