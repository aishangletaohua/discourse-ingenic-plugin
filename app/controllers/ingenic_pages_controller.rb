# frozen_string_literal: true

# The standalone pages the footer links to: the terms, the privacy policy, the
# rules for points.
#
# They are served from their own address rather than drawn as the body of a
# topic, because they are not discussions: nothing here is replyable, nothing
# is moderated as a post, and the text belongs to the site rather than to
# whoever happened to write it.
#
# Each language is its own row. A row that has not been written in the reader's
# language does not fall back to another one — a legal notice answered in a
# language the reader did not ask for is worse than saying it is not published
# in theirs. The only fallback is the seeded copy, used while no row exists at
# all, and it exists in every language the site serves.
class IngenicPagesController < ::ApplicationController
  requires_plugin DiscourseIngenic::PLUGIN_NAME

  include DiscourseIngenic::AppShell

  # A footer link is an ordinary browser navigation, so the XHR check must not
  # answer the click with an empty body.
  skip_before_action :check_xhr, only: %i[show]

  def show
    return render_app_shell unless request.format.json?

    page = published_page
    return render_page_not_found if page.nil?

    render_json_dump(page: page)
  end

  private

  def locale
    @locale ||= ::Ingenic::Locales.reading(params[:locale])
  end

  # A row that exists is the answer, even when it is unpublished: turning a page
  # off has to take it off the site, and falling back to the seeded copy would
  # make the switch do nothing.
  def published_page
    slug = params[:slug].to_s
    record = IngenicSitePage.for_locale(locale).find_by(slug: slug)

    if record
      return record.published? ? page_json(record) : nil
    end

    copy = ::Ingenic::SitePageDefaults.find(locale, slug)
    copy && page_json_from_defaults(copy)
  end

  def page_json(record)
    {
      "slug" => record.slug,
      "locale" => record.locale,
      "title" => record.title,
      "html" => cooked(record.body),
      "updated_at" => record.updated_at.iso8601,
    }
  end

  def page_json_from_defaults(copy)
    {
      "slug" => copy["slug"],
      "locale" => locale,
      "title" => copy["title"],
      # Not a stored row, so there is no date of its own. The page is the copy
      # that ships with the plugin; showing today's date would claim an edit
      # nobody made.
      "html" => cooked(copy["body"]),
      "updated_at" => nil,
    }
  end

  # Oneboxing is off: a policy page is not a place to fetch other sites on the
  # reader's behalf.
  def cooked(body)
    PrettyText.cook(body.to_s, features: { Onebox: false })
  end

  def render_page_not_found
    render json: { errors: [I18n.t("ingenic.errors.site_page_not_found")] }, status: 404
  end
end
