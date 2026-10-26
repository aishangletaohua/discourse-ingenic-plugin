# frozen_string_literal: true

require "uri"

module Ingenic
  # The "tell us about yourself" form, as configured.
  #
  # The questions are fixed because the answers decide how the team reads the
  # request: a company, a student and an individual developer are three
  # different relationships, and the form asks each of them what matters for
  # that relationship. A site setting may add extra questions, but it cannot
  # remove or rename the core ones — the profile columns and the access rules
  # are built around them.
  #
  # No telephone number is asked for. The address that matters is the email, the
  # account already has one, and a field the team would only ever read past is
  # one more reason for a visitor to abandon the form. The same reasoning is
  # applied to extra questions: keys that ask for a telephone, a chat handle, a
  # postal address or a government identifier are refused when the setting is
  # parsed.
  module DeveloperForm
    IDENTITIES = %w[company student individual].freeze

    CORE = [
      {
        "key" => "identity",
        "label" => "I am a",
        "type" => "select",
        "required" => true,
        "options" => [
          { "value" => "company", "label" => "Company" },
          { "value" => "student", "label" => "Student" },
          { "value" => "individual", "label" => "Individual developer" },
        ],
      },
      { "key" => "full_name", "label" => "Full name", "type" => "text", "required" => true },
      {
        "key" => "country",
        "label" => "Country or region",
        "type" => "text",
        "required" => true,
      },
      { "key" => "contact_email", "label" => "Contact email", "type" => "text", "required" => true },
      { "key" => "use_case", "label" => "Intended use", "type" => "textarea", "required" => true },
      {
        "key" => "project_stage",
        "label" => "Project stage",
        "type" => "text",
        "required" => false,
      },
      {
        "key" => "company",
        "label" => "Company",
        "type" => "text",
        "required" => true,
        "when" => { "key" => "identity", "value" => "company" },
      },
      {
        "key" => "job_title",
        "label" => "Job title",
        "type" => "text",
        "required" => false,
        "when" => { "key" => "identity", "value" => "company" },
      },
      {
        "key" => "school",
        "label" => "School",
        "type" => "text",
        "required" => true,
        "when" => { "key" => "identity", "value" => "student" },
      },
      {
        "key" => "major",
        "label" => "Field of study",
        "type" => "text",
        "required" => false,
        "when" => { "key" => "identity", "value" => "student" },
      },
    ].freeze

    CORE_KEYS = CORE.map { |field| field["key"] }.freeze

    TYPES = %w[text textarea].freeze

    # Keys an extra question may not use. This is the list of things the form
    # deliberately does not collect, kept here so that re-adding one is a code
    # change with a reason rather than a settings edit without one.
    PRIVATE_KEY =
      /phone|mobile|whatsapp|wechat|weixin|telephone|\btel\b|fax|passport|id_?(?:number|card)|address|\Aqq\z/i

    module_function

    # Core questions first, in their fixed order, then whatever the site has
    # added. Localised here rather than at the edge so the visitor, the admin
    # summary and the email all read the same wording.
    def fields
      localise(CORE) + extra_fields
    end

    def extra_fields
      parse(SiteSetting.ingenic_developer_form_fields)
    end

    def core_keys
      CORE_KEYS
    end

    def required_keys
      fields.select { |field| field[:required] }.map { |field| field[:key].to_s }
    end

    # A conditional question only exists for the identity it belongs to. An
    # individual developer is never asked for a company, and a refusal that
    # names it would be a refusal for a question they were not shown.
    def visible?(field, data)
      condition = field[:when]
      return true if condition.nil?

      answers = data.respond_to?(:to_h) ? data.to_h : {}
      depends_on = (condition[:key] || condition["key"]).to_s
      expected = (condition[:value] || condition["value"]).to_s
      answers[depends_on].to_s == expected
    end

    # Answers are stored as columns and a document, so what comes back from a
    # request has to be reduced to exactly the configured fields. Without this a
    # visitor could post arbitrary keys into the profile and an admin would
    # later read them back as if the form had asked for them. Conditional
    # questions are included as nil when hidden, so that switching identity
    # clears the answers that no longer apply.
    def normalize(params)
      submitted = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : (params || {})

      fields.each_with_object({}) do |field, result|
        key = field[:key].to_s
        raw = submitted[key] || submitted[key.to_sym]
        value = raw.is_a?(String) ? raw.strip.first(2000) : nil
        result[key] = value.presence
      end
    end

    def errors_for(data)
      answers = data.respond_to?(:to_h) ? data.to_h.stringify_keys : {}

      fields.flat_map do |field|
        next [] unless visible?(field, answers)

        key = field[:key].to_s
        value = answers[key].presence
        if value.nil?
          field[:required] ? [I18n.t("ingenic.developer_form.missing", field: field[:label])] : []
        elsif select?(field) && !option_values(field).include?(value)
          [I18n.t("ingenic.developer_form.invalid_option", field: field[:label])]
        elsif key == "contact_email" && !email?(value)
          [I18n.t("ingenic.developer_form.invalid_email", field: field[:label])]
        else
          []
        end
      end
    end

    def select?(field)
      field[:type].to_s == "select"
    end

    def option_values(field)
      Array(field[:options]).map { |option| option_value(option) }
    end

    # The label a stored option value is shown under. Used wherever an answer
    # is read back, so the admin sees "Company" rather than the value stored in
    # the column.
    def option_label(field, value)
      option = Array(field[:options]).find { |candidate| option_value(candidate) == value.to_s }
      option ? option_label_text(option) : value
    end

    def email?(value)
      URI::MailTo::EMAIL_REGEXP.match?(value.to_s)
    end

    def parse(raw)
      return [] if raw.blank?

      parsed = JSON.parse(raw.to_s)
      return [] unless parsed.is_a?(Array)

      parsed.filter_map do |entry|
        next unless entry.is_a?(Hash)

        key = entry["key"].to_s.strip
        label = entry["label"].to_s.strip
        next if key.blank? || label.blank?
        next if CORE_KEYS.include?(key)
        next if PRIVATE_KEY.match?(key)

        type = TYPES.include?(entry["type"].to_s) ? entry["type"].to_s : "text"
        { key: key, label: label, type: type.to_sym, required: entry["required"] == true }
      end
    rescue JSON::ParserError
      []
    end

    def localise(fields)
      fields.map do |field|
        localised = field.merge(
          "label" => I18n.t(
            "ingenic.developer_form.fields.#{field["key"]}",
            default: field["label"],
          ),
        )
        if field["options"]
          localised["options"] =
            field["options"].map do |option|
              option.merge(
                "label" => I18n.t(
                  "ingenic.developer_form.identities.#{option["value"]}",
                  default: option["label"],
                ),
              )
            end
        end
        localised.transform_keys(&:to_sym)
      end
    end

    def option_value(option)
      (option[:value] || option["value"]).to_s
    end

    def option_label_text(option)
      option[:label] || option["label"]
    end
  end
end
