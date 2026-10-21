# frozen_string_literal: true

# The SDK and firmware download centre.
#
# Every resource answers one question — may this account have the bytes right
# now — and the answer comes from a single place, Ingenic::DownloadAccess. The
# listing asks it to decide which control to draw and the file endpoint asks it
# before serving, so the button and the file cannot disagree.
#
# Nothing here hands out a URL to a file the visitor has not been cleared for.
# A resource with an external URL is redirected to from the endpoint rather than
# published in the listing, because a link in the page is a link in the page
# source.
class IngenicDownloadsController < ::ApplicationController
  requires_plugin DiscourseIngenic::PLUGIN_NAME

  include DiscourseIngenic::AppShell

  # A download is followed as an ordinary browser navigation, so the XHR check
  # would answer a click with an empty body.
  skip_before_action :check_xhr, only: %i[index deliver]

  before_action :find_download, only: %i[request_access deliver]
  before_action :ensure_logged_in, only: %i[save_profile request_access]

  def index
    return render_app_shell unless request.format.json?

    render_json_dump(
      downloads: downloads_json,
      filters: filters,
      form: form_json,
      signed_in: current_user.present?,
      # What the reader has, so a card can say what a resource costs and whether
      # they can already afford it without a request per card.
      points: Ingenic::Points.total_for(current_user),
      points_enabled: Ingenic::Points.enabled?,
    )
  end

  # The developer information is asked for once and reused by every gated
  # resource, which is why it has its own endpoint rather than being part of an
  # application for one file.
  def save_profile
    answers = Ingenic::DeveloperForm.normalize(params[:profile])
    errors = Ingenic::DeveloperForm.errors_for(answers)
    return render_json_error(errors.join(" "), status: 422) if errors.any?

    profile =
      IngenicDeveloperProfile.for(current_user) ||
        IngenicDeveloperProfile.new(user: current_user)
    # Merged rather than replaced: the form is admin-configurable, and dropping
    # a field from the configuration later should not erase what was already
    # answered under it.
    profile.data = profile.data.to_h.merge(answers)
    profile.save!

    render_json_dump(form: form_json, notice: I18n.t("ingenic.downloads.profile_saved"))
  end

  def request_access
    return render_json_error(I18n.t("ingenic.downloads.not_published"), status: 404) if !@download.published?
    if !@download.approval_required?
      return render_json_error(I18n.t("ingenic.downloads.request_not_needed"), status: 422)
    end

    access = access_for(@download)
    # Already cleared: there is nothing to apply for and nothing to report. The
    # caller reloads the list and finds the download button where Apply was.
    return render_json_dump(allowed: true) if access.allowed?
    if access.state == :needs_profile
      return render_json_error(I18n.t("ingenic.downloads.profile_required"), status: 422)
    end
    if access.state == :pending
      return render_json_error(I18n.t("ingenic.downloads.already_requested"), status: 422)
    end

    request =
      IngenicDownloadRequest.new(
        user: current_user,
        download: @download,
        message: params[:message].to_s.strip.first(2_000).presence,
      )

    begin
      request.save!
    rescue ActiveRecord::RecordNotUnique
      # The unique index on open applications is the real guard: two submissions
      # arriving together both pass the check above, and one of them lands here.
      return render_json_error(I18n.t("ingenic.downloads.already_requested"), status: 422)
    end

    # Mailed from a job so a slow mail server cannot turn "the applicant pressed
    # Apply" into an error page. The application is already recorded, and the
    # admin queue shows it whether or not the message ever leaves.
    Jobs.enqueue(:ingenic_download_request_email, request_id: request.id)

    # The listing is not sent back with this: it would be the unfiltered one,
    # and the caller is holding a filter the applicant chose. It reloads.
    render_json_dump(notice: I18n.t("ingenic.downloads.request_created"))
  end

  # The one place bytes leave the server.
  def deliver
    return render_json_error(I18n.t("ingenic.downloads.not_published"), status: 404) if !@download.published?

    access = access_for(@download)
    return render_denied(access) unless access.allowed?

    if @download.stored?
      stream_stored_file
    elsif @download.file_url.present?
      deliver_external(@download.file_url)
    else
      # Allowed, but there is nowhere to send them. A row like this should not
      # exist, and saying so is more useful than a redirect that looks like a
      # permission problem.
      render_unavailable
    end
  end

  private

  # Collects the price of a resource, if it has one, and reports the outcome the
  # way the delivery branches need it: true means the bytes may leave.
  #
  # A short balance is the only failure that is about the reader rather than
  # about the server, so it comes back as a state the page already knows how to
  # draw rather than as an error string.
  def charge
    case Ingenic::DownloadAccess.charge(current_user, @download)
    when :insufficient
      render_state(:needs_points)
      false
    else
      true
    end
  end

  def find_download
    @download = IngenicDownload.find_by(id: params[:id])
    raise Discourse::NotFound if @download.nil?
  end

  def access_for(download)
    Ingenic::DownloadAccess.new(current_user, download).result
  end

  # A visitor refused the file lands back on the centre, where the card for that
  # resource shows the same state and the control that moves it forward. A JSON
  # caller gets the reason instead, because there is no page to land on.
  def render_denied(access)
    render_state(access.state)
  end

  def render_state(state)
    if request.format.json?
      render_json_error(state_message(state), status: 403)
    else
      redirect_to "/ingenic/downloads"
    end
  end

  def state_message(state)
    # The one state whose message carries a number, so it is spelled out rather
    # than looked up from the table below.
    if state == :needs_points
      return I18n.t("ingenic.downloads.not_enough_points", points: @download.point_cost)
    end

    key =
      {
        anonymous: "not_signed_in",
        needs_profile: "profile_required",
        needs_request: "request_required",
        pending: "request_pending",
        rejected: "request_rejected",
      }[
        state
      ]
    I18n.t("ingenic.downloads.#{key || "not_available"}")
  end

  # Cleared to download, but there is nothing to hand over: the row points at a
  # file that is no longer on disk. The visitor has not done anything wrong, so
  # this is not the refusal path with its redirect back to the listing.
  def render_unavailable
    if request.format.json?
      render_json_error(I18n.t("ingenic.downloads.not_available"), status: 404)
    else
      redirect_to "/ingenic/downloads"
    end
  end

  def stream_stored_file
    relative = @download.storage_path
    if !Ingenic::DownloadStorage.exist?(relative)
      Rails.logger.warn(
        "Ingenic: download #{@download.id} is missing from storage at #{relative.inspect}",
      )
      return render_unavailable
    end

    return if !charge

    record_download

    path = Ingenic::DownloadStorage.absolute_path(relative)
    response.headers["Content-Type"] = "application/octet-stream"
    response.headers["Content-Length"] = path.size.to_s
    response.headers["Content-Disposition"] =
      ActionDispatch::Http::ContentDisposition.format(
        disposition: "attachment",
        filename: @download.original_filename.presence || "#{@download.name}",
      )

    # Streamed through the controller rather than handed to the web server: the
    # storage root deliberately sits outside public/, so there is no URL for the
    # web server to serve. An Enumerator body is also what keeps this from
    # reading a firmware image into memory — Rack::Sendfile leaves a body that
    # does not respond to #to_path alone.
    self.response_body =
      Enumerator.new do |yielder|
        File.open(path, "rb") do |file|
          while (chunk = file.read(Ingenic::DownloadStorage::CHUNK))
            yielder << chunk
          end
        end
      end
  end

  # Only two shapes of value are sent to a browser: a path on this site, and an
  # http(s) address. Anything else is a typo or worse, and neither deserves a
  # Location header.
  def deliver_external(url)
    local = url.start_with?("/")
    if !local && !url.match?(%r{\Ahttps?://}i)
      Rails.logger.warn("Ingenic: download #{@download.id} has an unusable file URL")
      return render_unavailable
    end

    return if !charge

    record_download

    if local
      redirect_to url
    else
      # Told outright, because Rails refuses to redirect off-site otherwise —
      # the address here is the partner's own, which is the whole point of a
      # resource held elsewhere.
      redirect_to url, allow_other_host: true
    end
  end

  # The record of the hand-over, written from the two branches of `deliver` that
  # actually release the file rather than once at the top of it. The third branch
  # is the resource that is allowed and no longer in storage, and nobody
  # received that one: recording it would put a name in the audit trail against
  # a file that never left.
  #
  # Deliberately not guarded here: `IngenicDownloadLog.record!` never raises,
  # because a download somebody is entitled to must not fail over a row in a
  # log.
  def record_download
    IngenicDownloadLog.record!(user: current_user, download: @download, request: request)
  end

  # A resource is filed in exactly one language, and that is the language of
  # the chip it belongs to. The listing therefore shows the reader's language
  # and nothing else: no fallback row means a Chinese reader never gets an
  # English card, and an untranslated catalogue is visibly empty rather than
  # quietly mixed.
  def downloads
    @downloads ||=
      begin
        rows = IngenicDownload.published.for_locale(locale)

        rows = rows.where(family: params[:family]) if params[:family].present?
        rows = rows.where(product_id: product_ids_for_params) if product_ids_for_params
        rows = rows.where(category_id: params[:category]) if params[:category].present?
        rows = rows.where(version: params[:version]) if params[:version].present?
        rows = rows.where(platform: params[:platform]) if params[:platform].present?

        rows.ordered
      end
  end

  # Both filters address the catalogue rather than the string in the row, so a
  # chip is found by its slug in this language and a series covers both itself
  # and every chip under it.
  def product_ids_for_params
    return @product_ids_for_params if defined?(@product_ids_for_params)

    @product_ids_for_params =
      if params[:product].present?
        product = IngenicProduct.where(locale: locale).find_by(slug: params[:product])
        product ? [product.id] : []
      elsif params[:series].present?
        series = IngenicProduct.series.where(locale: locale).find_by(slug: params[:series])
        series ? [series.id] + series.children.pluck(:id) : []
      end
  end

  def downloads_json
    Ingenic::DownloadAccess
      .for_list(current_user, downloads)
      .map { |result| download_json(result.download, result.state) }
  end

  # Whether this account has already unlocked the resource, asked of the ledger
  # rather than of the row. Reading it once for the whole page keeps a listing
  # from running one query per priced card.
  def unlocked?(download)
    return true unless download.costs_points?
    return true unless Ingenic::Points.enabled?

    @unlocked_ids ||= Ingenic::Points.unlocked_download_ids(current_user)
    @unlocked_ids.include?(download.id)
  end

  def download_json(download, state)
    {
      "id" => download.id,
      # What the card needs to talk about price: what it costs, and whether this
      # account has already bought it. Both are read from the same ledger the
      # endpoint charges against, so the card cannot promise a free download the
      # endpoint will refuse.
      "point_cost" => download.point_cost,
      "unlocked" => unlocked?(download),
      "family" => download.family,
      "product_slug" => download.product&.slug,
      "product_name" => download.product&.name,
      "category_id" => download.category_id,
      "category_name" => download.category_name,
      "version" => download.version,
      "platform" => download.platform,
      "architecture" => download.architecture,
      "name" => download.name,
      "description" => download.description,
      "file_size" => download.file_size,
      "sha256" => download.file_sha256.presence || download.sha256,
      "released_on" => download.released_on&.iso8601,
      "access_level" => download.access_level,
      "access_state" => state.to_s,
      "external" => download.external?,
      # Where the browser should go for the bytes, whatever the state: the
      # endpoint is what decides, and it is the only address the page needs.
      "file_path" => "#{Discourse.base_path}/ingenic/downloads/#{download.id}/file",
    }
  end

  # Options come from the unfiltered set so a narrowed selection can be widened
  # again without a reload.
  #
  # The products are the product tree rather than the slugs on the resources, so
  # a chip is offered under its name and not as the string that happens to be in
  # the row. That also gives the page its second level: choosing a series narrows
  # the chips, which is how the same catalogue is browsed in the documentation.
  #
  # The classifications are sent only when something is filed under them. The
  # list is editable and grows, and a filter whose every option returns an empty
  # page is worse than no filter — it reads as a broken page rather than an
  # unused label.
  def filters
    all = IngenicDownload.published.for_locale(locale)
    {
      # Only the families that actually have a published resource. A tab that
      # always opens on an empty page is the filter version of a dead link.
      families: IngenicDownload::FAMILIES.select { |family| all.exists?(family: family) },
      series: product_tree[:series],
      chips: product_tree[:chips],
      categories: used_categories,
      versions: all.distinct.order(version: :desc).pluck(:version).compact,
      platforms: all.distinct.pluck(:platform).compact.sort,
    }
  end

  def product_tree
    @product_tree ||=
      begin
        # Only the part of the catalogue that has something to download. A
        # series offered here with no resource under it is the same dead end
        # the families filter avoids.
        used_ids =
          IngenicDownload.published.for_locale(locale).where.not(product_id: nil).distinct.pluck(
            :product_id,
          )
        chips =
          IngenicProduct.chips
            .published
            .where(locale: locale, id: used_ids)
            .order(position: :asc, name: :asc)
            .to_a
        series = chips.filter_map(&:parent).select(&:published?).uniq
        chips = chips.select { |chip| series.include?(chip.parent) }

        {
          series:
            series
              .sort_by { |record| [record.position.to_i, record.name.to_s] }
              .map { |record| { "slug" => record.slug, "name" => record.name } },
          chips:
            chips.map do |chip|
              { "slug" => chip.slug, "name" => chip.name, "series_slug" => chip.parent.slug }
            end,
        }
      end
  end

  # The categories, with where they are used. The type chips are drawn from
  # this: a chip has its own list of material types, and offering every type on
  # the site for a chip that has none of them is how a filter produces an empty
  # page that looks like a bug. The usage map is small — one row per published
  # resource in this language — and building it here saves the theme a second
  # request.
  def used_categories
    usage =
      IngenicDownload.published.for_locale(locale).includes(:product).map do |row|
        [row.category_id, row.product&.slug, row.family]
      end
    grouped = usage.group_by(&:first)
    ids = grouped.keys.compact

    IngenicDownloadCategory.where(id: ids).ordered.map do |category|
      rows = grouped[category.id] || []

      {
        "id" => category.id,
        "name" => category.name,
        "product_slugs" => rows.filter_map { |row| row[1] }.uniq,
        "families" => rows.filter_map { |row| row[2] }.uniq,
      }
    end
  end

  def locale
    @locale ||= Ingenic::Locales.reading
  end

  def form_json
    fields =
      Ingenic::DeveloperForm.fields.map do |field|
        {
          "key" => field[:key].to_s,
          "label" => field[:label],
          "type" => field[:type].to_s,
          "required" => field[:required] ? true : false,
        }
      end

    profile = IngenicDeveloperProfile.for(current_user)

    {
      "fields" => fields,
      "values" => profile ? profile.data.to_h : {},
      "completed" => profile.present?,
    }
  end
end
