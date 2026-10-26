# frozen_string_literal: true

# The content workbench.
#
# Administrators reach it from the plugin's admin page; a scoped content
# manager reaches the same screens here, without being made a moderator or an
# administrator. That is the whole reason the address exists: the admin plugin
# page is staff-only, and delegating one chip's documentation should not mean
# delegating the forum.
#
# The APIs themselves stay under `/admin/plugins/discourse-ingenic`. Their
# routes are guarded by the same resolver, so a manager who can open this page
# can call the endpoints behind it — and nothing else.
class IngenicManageController < ::ApplicationController
  requires_plugin DiscourseIngenic::PLUGIN_NAME

  include DiscourseIngenic::AppShell

  # A manager opening the address directly is a browser navigation, and the
  # XHR guard would answer it with an empty body.
  skip_before_action :check_xhr, only: %i[index]

  def index
    resolver = ::Ingenic::PermissionResolver.new(current_user)
    allowed = current_user.present? && (current_user.admin? || resolver.can_manage_any_content?)
    raise Discourse::NotFound unless allowed

    return render_app_shell unless request.format.json?

    render_json_dump(
      admin: current_user.admin?,
      locales: ::Ingenic::Locales.options,
      # The language this request was answered in, so the picker and the stored
      # choice agree even when the stored one is no longer served.
      locale: ::Ingenic::Locales.resolve(params[:locale]),
      # Which workbench tabs this account may open. Sent so the page can draw
      # only the sections the endpoints will accept, rather than offering a
      # tab that answers with a 404.
      areas:
        ::IngenicPermission::AREAS.index_with do |area|
          current_user.admin? || resolver.can_manage_any_area?(area)
        end.merge(
          "site" => current_user.admin? || resolver.can_manage_feature?("site"),
          "files" => current_user.admin? || resolver.can_manage_feature?("files"),
        ),
    )
  end
end
