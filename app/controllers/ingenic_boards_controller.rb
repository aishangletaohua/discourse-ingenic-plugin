# frozen_string_literal: true

# The development board catalogue.
#
# This page sells nothing and takes no orders: a board is applied for or bought
# from the Ingenic team, so every card ends in a link that leaves the forum.
class IngenicBoardsController < ::ApplicationController
  requires_plugin DiscourseIngenic::PLUGIN_NAME

  include DiscourseIngenic::AppShell

  # Direct navigations to /ingenic/boards must reach the app shell; the
  # homepage block's fetch stays AJAX and keeps hitting JSON.
  skip_before_action :check_xhr, only: %i[index]

  def index
    return render_app_shell unless request.format.json?

    render_json_dump(
      boards: ActiveModel::ArraySerializer.new(boards, each_serializer: IngenicBoardSerializer),
      filters: filters,
    )
  end

  private

  # A board belongs to one catalogue row, and that row is one language. The
  # listing therefore shows exactly this reader's language: no fallback means a
  # Chinese reader never gets an English card, and an untranslated catalogue is
  # visibly empty rather than quietly mixed.
  def boards
    @boards ||=
      begin
        rows = IngenicBoard.for_locale(locale).published.includes(product: :parent)

        # The first filter is the kind of thing — a board or a sample — and the
        # second is the chip. An unknown kind is ignored rather than turned
        # into an empty page, so a stale bookmark still shows the catalogue.
        rows = rows.for_kind(params[:kind]) if IngenicBoard::KINDS.include?(params[:kind])
        rows = rows.for_chip(params[:chip]) if params[:chip].present?

        rows.ordered
      end
  end

  # The filter options come from the tree, not from the boards on the page, so
  # choosing a chip does not make the other chips disappear from the control
  # that would undo the choice. The chip carries its series' name because the
  # selector no longer has a series filter to narrow it down: "T33" alone is
  # not enough context when every series is listed together.
  def filters
    chips =
      IngenicProduct.chips.includes(:parent).published.where(locale: locale).ordered.map do |record|
        {
          "slug" => record.slug,
          "name" => record.name,
          "series_slug" => record.parent&.slug,
          "series_name" => record.parent&.name,
        }
      end

    { kinds: IngenicBoard::KINDS, chips: chips }
  end

  def locale
    @locale ||= Ingenic::Locales.reading
  end
end
