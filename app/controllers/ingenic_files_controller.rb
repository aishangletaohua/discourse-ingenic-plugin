# frozen_string_literal: true

# The link an operator copies out of the file library.
#
# Images are public: they are meant to be pasted into posts and documentation,
# where a reader who is not signed in still sees them. Everything else — an SDK
# archive, a PDF — answers only to a signed-in account. That is not the download
# centre's three-tier gate and does not pretend to be: the operator takes this
# link and applies the tier where it is used. What the gate here prevents is an
# anonymous visitor walking a shared archive link, or a search engine indexing
# it.
#
# The library root sits outside public/, so there is no address the web server
# serves on its own; every byte comes through this controller after the path has
# been checked.
class IngenicFilesController < ::ApplicationController
  requires_plugin DiscourseIngenic::PLUGIN_NAME

  # A file is followed as an ordinary browser navigation — an <img>, an <a>, a
  # download — so the XHR guard would answer it with an empty body.
  skip_before_action :check_xhr

  rescue_from ::Ingenic::FileStorage::Error do
    raise Discourse::NotFound
  end

  def show
    relative = ::Ingenic::FileStorage.normalize_relative(params[:path])
    path = ::Ingenic::FileStorage.existing_path(relative)
    raise Discourse::NotFound unless path.file?

    name = path.basename.to_s
    image = ::Ingenic::FileStorage.image?(name)

    # Signed out, an archive link leads to the login page rather than to a 404
    # that looks like a broken link. `ensure_logged_in` is not used here: for a
    # plain browser navigation it answers 404, which is the wrong story for a
    # link somebody put in a post.
    return redirect_to("/login") if !image && current_user.blank?

    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Content-Security-Policy"] = "default-src 'none'"
    response.headers["Cache-Control"] =
      image ? "public, max-age=300" : "private, max-age=0, must-revalidate"

    send_file(
      path.to_s,
      filename: name,
      type: ::Ingenic::FileStorage.mime_for(name),
      disposition: ::Ingenic::FileStorage.previewable?(name) ? "inline" : "attachment",
    )
  end
end
