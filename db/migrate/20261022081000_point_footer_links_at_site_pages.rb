# frozen_string_literal: true

# Footer links that used to leave the forum now land on the pages it publishes.
#
# The links were not broken before — they were editable, and an editor pointed
# them at whatever existed. What they pointed at was never the forum's own
# statement: /tos and /privacy are Discourse's generic pages, and the points
# link led to the member's balance rather than to the rules that explain it.
#
# Matching is by destination, not by label, so a column the team has renamed is
# still repointed. A destination written as an absolute URL on the forum's own
# host is matched too: both spellings mean the same page.
class PointFooterLinksAtSitePages < ActiveRecord::Migration[7.2]
  REPOINTS = {
    "terms" => %w[/tos /terms /terms-of-service /terms-of-use /user-agreement],
    "privacy" => %w[/privacy /privacy-policy /privacy_policy],
  }.freeze

  # The points link is only moved when its label says it is about the rules.
  # A footer that also offers "My points" must keep that button on the member's
  # balance; moving it would replace a working page with a different one.
  POINTS_LABELS = ["%rule%", "%benefit%", "%规则%", "%权益%", "%terms%"].freeze

  def up
    REPOINTS.each do |slug, destinations|
      execute <<~SQL
        UPDATE ingenic_footer_links
        SET href = #{quote("/ingenic/pages/#{slug}")}, updated_at = NOW()
        WHERE #{path_sql} IN (#{destinations.map { |destination| quote(destination) }.join(", ")})
      SQL
    end

    labels = POINTS_LABELS.map { |pattern| "label ILIKE #{quote(pattern)}" }.join(" OR ")
    execute <<~SQL
      UPDATE ingenic_footer_links
      SET href = '/ingenic/pages/points-rules', updated_at = NOW()
      WHERE #{path_sql} IN ('/ingenic/points')
        AND (#{labels})
    SQL
  end

  def down
    {
      "/ingenic/pages/terms" => "/tos",
      "/ingenic/pages/privacy" => "/privacy",
      "/ingenic/pages/points-rules" => "/ingenic/points",
    }.each do |from, to|
      execute <<~SQL
        UPDATE ingenic_footer_links
        SET href = #{quote(to)}, updated_at = NOW()
        WHERE TRIM(href) = #{quote(from)}
      SQL
    end
  end

  private

  # The path part of a link, lower-cased, with the host and any query or
  # fragment removed, and without a trailing slash. `/tos`, `/tos/` and
  # `https://forum.example.com/tos#top` are one destination.
  def path_sql
    "REGEXP_REPLACE(REGEXP_REPLACE(LOWER(REGEXP_REPLACE(TRIM(href), '^https?://[^/]+', '')), '[?#].*$', ''), '/+$', '')"
  end
end
