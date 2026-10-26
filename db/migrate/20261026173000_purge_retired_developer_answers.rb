# frozen_string_literal: true

# The built-in form used to ask two questions the identity-based form does not:
# an estimated annual volume and a free-text "anything else". Neither is read by
# the team, neither is shown anywhere now, and leaving them in the document is
# an answer nobody asked for sitting beside answers that are asked for. They are
# removed here rather than in the form code, because the decision is about the
# data already collected, once, and not about every future submission: an extra
# question a site adds and later removes from the setting keeps its answers.
class PurgeRetiredDeveloperAnswers < ActiveRecord::Migration[7.2]
  RETIRED_KEYS = %w[estimated_volume notes].freeze

  def up
    execute <<~SQL
      UPDATE ingenic_developer_profiles
      SET data = data - ARRAY[#{RETIRED_KEYS.map { |key| "'#{key}'" }.join(", ")}]::text[]
    SQL
  end

  # The answers are not put back: they were retired by the owner, and this
  # migration's whole purpose is that they are gone. Rolling back the schema
  # change does not restore data that was deliberately deleted.
  def down; end
end
