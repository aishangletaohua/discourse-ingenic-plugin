# frozen_string_literal: true

# The parts of the site the Ingenic team edits rather than writes into the theme:
# the homepage promotion slots, the partner platforms in the footer strip, and
# the footer's link columns.
#
# One endpoint for all three because the theme fetches them once per page load
# and draws them in two places — the homepage and the footer — and two requests
# for the same screen would be two chances for the page to be half-drawn.
#
# This is a data endpoint rather than a page: there is no /ingenic/site route in
# the theme, and a browser arriving here is asking for something that does not
# exist. Saying so is more useful than an app shell that draws an empty page.
class IngenicSiteController < ::ApplicationController
  requires_plugin DiscourseIngenic::PLUGIN_NAME

  # Without this a browser navigation is answered by the XHR guard, which renders
  # an empty 200. An empty page that looks like a working one is a worse answer
  # than a 404 for an address that was never meant to be visited.
  skip_before_action :check_xhr, only: %i[show]

  def show
    raise Discourse::NotFound unless request.format.json?

    render_json_dump(
      promotions: promotions_json,
      social_links: social_links_json,
      footer_columns: footer_columns_json,
    )
  end

  private

  # Only what is on now. A promotion carries a window so a campaign can take
  # itself down, and the same list is what the admin screen previews — which is
  # why the window is evaluated here rather than left to the browser's clock.
  def promotions_json
    IngenicPromotion.live.ordered.map do |promotion|
      {
        "id" => promotion.id,
        "corner_label" => promotion.corner_label,
        "title" => promotion.title,
        "description" => promotion.description,
        "button_label" => promotion.button_label,
        "button_href" => promotion.button_href,
        "external" => promotion.external?,
        "image_url" => promotion.image_url,
        # The card shows when the campaign runs. `created_at` is sent as the
        # fallback so a slot with no window still carries the date it went up
        # rather than looking undated beside the others.
        "starts_at" => promotion.starts_at&.iso8601,
        "ends_at" => promotion.ends_at&.iso8601,
        "created_at" => promotion.created_at.iso8601,
      }
    end
  end

  def social_links_json
    IngenicSocialLink.published.ordered.map do |link|
      {
        "id" => link.id,
        "label" => link.label,
        # Both spellings travel to the browser: the page it lands on has already
        # chosen a language, and the footer should not need a second request to
        # know which one.
        "label_zh" => link.label_zh,
        "kind" => link.kind,
        "href" => link.href,
        "image_url" => link.image_url,
        "qr_image_url" => link.qr_image_url,
        "qr_caption" => link.qr_caption,
        "qr_caption_zh" => link.qr_caption_zh,
        "icon_only" => link.icon_only,
      }
    end
  end

  # Columns carry their links, because a heading and its list are drawn as one
  # block and a column that arrived without its links would render as a heading
  # over nothing.
  #
  # Only published links come with them: hiding one link is not the same as
  # retiring the column it sits in.
  def footer_columns_json
    IngenicFooterColumn.published.includes(:published_links).ordered.map do |column|
      {
        "id" => column.id,
        "title" => column.title,
        "title_zh" => column.title_zh,
        "links" =>
          column.published_links.map do |link|
            {
              "id" => link.id,
              "label" => link.label,
              "label_zh" => link.label_zh,
              "href" => link.href,
              "external" => link.external?,
            }
          end,
      }
    end
  end
end
