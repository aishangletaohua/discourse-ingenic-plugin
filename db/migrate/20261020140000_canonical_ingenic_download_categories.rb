# frozen_string_literal: true

# The material types the download centre starts with.
#
# The plugin seeded a list of its own invention — sdk, firmware, manual,
# toolchain — and the demo catalogue then added a second spelling of two of
# them, so the filter offered "sdk" beside "SDK" and "firmware" beside
# "Firmware". One shelf split into two chips is worse than a short list: a
# visitor cannot tell which half holds what, and neither half looks complete.
#
# The six below are the set the Ingenic team asked for. The table remains an
# editable list, so adding or retiring a type later is the admin page's job
# rather than another migration's.
#
# Existing resources keep their filing: an alias row is folded into its
# canonical row before it is deleted, never simply removed. A category the
# team made that is not one of these is left alone — this migration repairs
# the vocabulary it shipped, it does not curate theirs.
class CanonicalIngenicDownloadCategories < ActiveRecord::Migration[7.2]
  CANONICAL = [
    "SDK Release",
    "Product Brief",
    "Algorithm Platform",
    "Algorithm Applications",
    "Datasheet",
    "Version Description",
  ].freeze

  # Keyed by the lower-cased, stripped name. "sdk" and "SDK" are the same
  # shelf; so are "release notes" and "Version Description".
  ALIASES = {
    "sdk" => "SDK Release",
    "sdk release" => "SDK Release",
    "sdk releases" => "SDK Release",
    "firmware" => "SDK Release",
    "firmware release" => "SDK Release",
    "product brief" => "Product Brief",
    "product briefs" => "Product Brief",
    "algorithm platform" => "Algorithm Platform",
    "algorithm magik platform" => "Algorithm Platform",
    "algorithm" => "Algorithm Platform",
    "algorithm applications" => "Algorithm Applications",
    "algorithm application" => "Algorithm Applications",
    "datasheet" => "Datasheet",
    "datasheets" => "Datasheet",
    "version description" => "Version Description",
    "version descriptions" => "Version Description",
    "release notes" => "Version Description",
    "release_notes" => "Version Description",
  }.freeze

  # Names the plugin itself seeded that no longer belong in the default list.
  # Only removed when nothing is filed under them, so an administrator who has
  # since used one of these keeps their category and their resources.
  RETIRED_SEED_NAMES = %w[manual toolchain example other algorithm].freeze

  def up
    now = Time.zone.now

    CANONICAL.each_with_index do |name, index|
      execute <<~SQL
        INSERT INTO ingenic_download_categories (name, locale, position, published, created_at, updated_at)
        VALUES (#{quote(name)}, 'en', #{index}, true, #{quote(now)}, #{quote(now)})
        ON CONFLICT (name, locale) DO UPDATE
        SET position = EXCLUDED.position,
            published = true,
            updated_at = EXCLUDED.updated_at
      SQL
    end

    # name → id, read back rather than assumed: an earlier canonical row may
    # already exist and keep its id.
    canonical_ids =
      select_rows(<<~SQL).to_h
        SELECT name, id FROM ingenic_download_categories
        WHERE name IN (#{CANONICAL.map { |name| quote(name) }.join(", ")})
        AND locale = 'en'
      SQL

    rows =
      select_rows(<<~SQL)
        SELECT id, name FROM ingenic_download_categories
        WHERE locale = 'en'
      SQL

    rows.each do |id, name|
      target = ALIASES[name.to_s.strip.downcase]
      next if target.nil?

      target_id = canonical_ids[target]
      next if target_id.nil? || target_id.to_i == id.to_i

      execute <<~SQL
        UPDATE ingenic_downloads
        SET category_id = #{quote(target_id)}
        WHERE category_id = #{quote(id)}
      SQL

      execute <<~SQL
        DELETE FROM ingenic_download_categories WHERE id = #{quote(id)}
      SQL
    end

    RETIRED_SEED_NAMES.each do |name|
      execute <<~SQL
        DELETE FROM ingenic_download_categories
        WHERE locale = 'en'
          AND lower(name) = #{quote(name)}
          AND NOT EXISTS (
            SELECT 1 FROM ingenic_downloads
            WHERE ingenic_downloads.category_id = ingenic_download_categories.id
          )
      SQL
    end
  end

  # The rows this migration deleted are gone, and the aliases they held were
  # spellings, not facts. There is nothing to restore that would not put the
  # duplicate chips back.
  def down; end
end
