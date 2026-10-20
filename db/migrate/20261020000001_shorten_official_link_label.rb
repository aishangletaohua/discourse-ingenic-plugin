# frozen_string_literal: true

# The official-site entry was seeded as "Ingenic" and later lengthened to
# "Ingenic Semiconductor" so the button beside the wordmark said what it opens.
# It now sits in the footer's platform row, under a wordmark that already names
# the company, where the long label only made the row uneven. "Official" is
# the word the rest of the site uses for the same destination.
#
# Both copies of the entry are rewritten: the button and the partner platform
# it duplicates. Only the seeded labels are touched, so a label an
# administrator has already chosen is left alone.
class ShortenOfficialLinkLabel < ActiveRecord::Migration[7.0]
  OLD_LABELS = ["Ingenic", "Ingenic Semiconductor"].freeze
  NEW_LABEL = "Official"

  def up
    rename_links("ingenic_header_links")
    rename_links("ingenic_social_links")
  end

  def down
    # The two rows did not start from the same word: the button was long, the
    # platform was short. "Ingenic" is the common previous value.
    revert_links("ingenic_header_links")
    revert_links("ingenic_social_links")
  end

  private

  def rename_links(table)
    execute <<~SQL
      UPDATE #{table}
      SET label = #{connection.quote(NEW_LABEL)}, updated_at = CURRENT_TIMESTAMP
      WHERE href LIKE '%ingenic.com%'
        AND label IN (#{OLD_LABELS.map { |label| connection.quote(label) }.join(", ")})
    SQL
  end

  def revert_links(table)
    execute <<~SQL
      UPDATE #{table}
      SET label = 'Ingenic', updated_at = CURRENT_TIMESTAMP
      WHERE href LIKE '%ingenic.com%'
        AND label = #{connection.quote(NEW_LABEL)}
    SQL
  end
end
