# frozen_string_literal: true

# name: discourse-ingenic
# about: Ingenic community extension. Chip-scoped documentation with version selection, download center, and development board links.
# version: 1.0.0
# authors: Ingenic
# url: https://forum.ingenic.com

enabled_site_setting :ingenic_enabled

# Only the management screens. The public pages are drawn entirely by the
# companion theme's components, so their styles live with those components and
# there is no second copy here to fight over load order.
register_asset "stylesheets/common/ingenic-admin.scss"

module ::DiscourseIngenic
  PLUGIN_NAME = "discourse-ingenic"
end

require_relative "lib/discourse_ingenic/config_parser"
require_relative "lib/discourse_ingenic/app_shell"
require_relative "lib/discourse_ingenic/guardian_extensions"
require_relative "lib/discourse_ingenic/management_constraint"
require_relative "lib/ingenic/permission_resolver"
require_relative "lib/ingenic/resolved_page"
require_relative "lib/ingenic/documentation_resolver"
require_relative "lib/ingenic/document_importer"
require_relative "lib/ingenic/developer_form"
require_relative "lib/ingenic/download_access"
require_relative "lib/ingenic/download_storage"
require_relative "lib/ingenic/forum_categories"
require_relative "lib/ingenic/official_flair"
require_relative "lib/ingenic/points"
require_relative "lib/ingenic/point_events"
require_relative "lib/ingenic/contributions"
require_relative "lib/ingenic/contribution_events"
require_relative "lib/ingenic/status_tags"
require_relative "lib/ingenic/tag_policy"
require_relative "lib/ingenic/bounties"
require_relative "lib/ingenic/config_export"

# A plugin's `app/` tree is not autoloaded. Discourse either namespaces it
# behind a Rails::Engine or expects the plugin to require each file, and this
# one uses flat top-level constants, so every file has to be named here. A
# missing line is not a subtle bug: the constant is simply undefined the first
# time a route or a job reaches for it. `spec/plugin_requires_spec.rb` fails if
# a file under app/ stops being listed.
after_initialize do
require_relative "app/models/ingenic_doc_product"
require_relative "app/models/ingenic_doc_version"
require_relative "app/models/ingenic_doc_page"
require_relative "app/models/ingenic_download_category"
require_relative "app/models/ingenic_download"
require_relative "app/models/ingenic_download_request"
require_relative "app/models/ingenic_download_grant"
require_relative "app/models/ingenic_download_log"
require_relative "app/models/ingenic_developer_profile"
require_relative "app/models/ingenic_board"
require_relative "app/models/ingenic_permission"
require_relative "app/models/ingenic_tag_colour"
require_relative "app/models/ingenic_group_permission"
require_relative "app/models/ingenic_promotion"
require_relative "app/models/ingenic_social_link"
require_relative "app/models/ingenic_header_link"
require_relative "app/models/ingenic_section_card"
require_relative "app/models/ingenic_footer_column"
require_relative "app/models/ingenic_footer_link"
require_relative "app/models/ingenic_point_rule"
require_relative "app/models/ingenic_point_entry"
require_relative "app/models/ingenic_point_balance"
require_relative "app/models/ingenic_contribution"
require_relative "app/models/ingenic_bounty"

require_relative "app/serializers/ingenic_version_serializer"
require_relative "app/serializers/ingenic_product_serializer"
require_relative "app/serializers/ingenic_page_serializer"
require_relative "app/serializers/ingenic_page_list_serializer"
require_relative "app/serializers/ingenic_board_serializer"
# Before the bounty serializer, which names it in the class body: `serializer:`
# is read while the class is being defined, so the constant has to be there by
# then rather than by the time a bounty is serialized.
require_relative "app/serializers/ingenic_bounty_topic_serializer"
require_relative "app/serializers/ingenic_bounty_serializer"

require_relative "app/mailers/ingenic_download_mailer"
require_relative "app/jobs/regular/ingenic_download_request_email"
require_relative "app/jobs/regular/ingenic_download_decision_email"
require_relative "app/jobs/regular/ingenic_official_flair_sync"
require_relative "app/jobs/scheduled/ingenic_bounty_expiry"
require_relative "app/jobs/scheduled/ingenic_high_like_tag"

require_relative "app/controllers/admin/ingenic/base_controller"
require_relative "app/controllers/admin/ingenic_controller"
require_relative "app/controllers/ingenic_docs_controller"
require_relative "app/controllers/ingenic_downloads_controller"
require_relative "app/controllers/ingenic_boards_controller"
require_relative "app/controllers/ingenic_mcp_controller"
require_relative "app/controllers/ingenic_site_controller"
require_relative "app/controllers/ingenic_points_controller"
require_relative "app/controllers/ingenic_home_controller"
require_relative "app/controllers/ingenic_bounties_controller"
require_relative "app/controllers/ingenic_leaderboard_controller"
require_relative "app/controllers/ingenic_popular_controller"
end

add_admin_route "admin.ingenic.documentation.title", "discourse-ingenic", use_new_show_route: true

# The two icons the theme draws that Discourse's own sprite does not carry.
#
# The served sprite is core's own icon list plus everything code and settings
# ask for — `SvgSprite.bundle` is `core_svgs.slice(*all_icons)`. An icon an
# administrator names in `ingenic_nav_items` is collected from the setting
# itself, but the list the theme falls back to when that setting is empty lives
# in the theme's source, so those names have to be given here or they render as
# nothing at all.
#
# Of the theme's defaults, `plus`, `house`, `comments`, `book`, `code`,
# `download`, `gift`, `star`, `circle` and `angle-down` are in core's subset
# (lib/svg_sprite.rb) and need no help. These two are not:
#
#   bullhorn   Official Announcements
#   microchip  Development Boards
#
# Both symbols exist in the vendored SVG set — this is only about which ones are
# copied into the bundle that is served.
register_svg_icon "bullhorn"
register_svg_icon "microchip"

after_initialize do
  reloadable_patch do
    Guardian.prepend DiscourseIngenic::GuardianExtensions
  end

  # The official identity badge.
  #
  # Discourse already draws a group's flair beside a member's username; what it
  # does not do is hand that flair out on membership, because its own route to
  # it runs through the group being the member's primary group, which decides
  # rather more than a badge. These four events are every way a member and a
  # listing can come apart: joining, leaving, the group's own flair changing,
  # and the list of official groups changing. The rules and the reasons are in
  # Ingenic::OfficialFlair; what is here is only what notices.
  #
  # Each is guarded on the extension being on. The handlers outlive the setting
  # — Rails has already loaded this file — and a forum that has switched the
  # extension off should not go on handing out badges in the background.
  on(:user_added_to_group) do |user, _group, **_opts|
    Ingenic::OfficialFlair.sync_user(user) if SiteSetting.ingenic_enabled
  end

  on(:user_removed_from_group) do |user, _group|
    Ingenic::OfficialFlair.sync_user(user) if SiteSetting.ingenic_enabled
  end

  on(:group_updated) do |group|
    Ingenic::OfficialFlair.after_group_change(group) if SiteSetting.ingenic_enabled
  end

  on(:site_setting_changed) do |name, old_value, _new_value|
    if SiteSetting.ingenic_enabled && name.to_s == "ingenic_official_groups"
      Ingenic::OfficialFlair.after_list_change(old_value)
    end
  end

  # The points ledger.
  #
  # Six events, and between them every way points are earned or taken back:
  # something is written, something is liked, an answer is accepted, and the
  # three ways any of those goes away. What counts and who earns is in
  # Ingenic::PointEvents; this is only the subscribing.
  #
  # `discourse-solved` owns the two solution events and may not be enabled. A
  # handler for an event nothing fires costs nothing, which is why these are
  # registered unconditionally rather than behind a check for a plugin this one
  # does not otherwise depend on.
  on(:post_created) { |post, _opts, _user| Ingenic::PointEvents.post_created(post) }
  on(:post_destroyed) { |post, _opts, _user| Ingenic::PointEvents.post_destroyed(post) }
  on(:like_created) { |post_action, _creator| Ingenic::PointEvents.like_created(post_action) }
  on(:like_destroyed) { |post_action, _creator| Ingenic::PointEvents.like_destroyed(post_action) }
  on(:accepted_solution) { |post| Ingenic::PointEvents.solution_accepted(post) }
  on(:unaccepted_solution) { |post| Ingenic::PointEvents.solution_unaccepted(post) }

  # The contribution score, listening to the same forum as the ledger above and
  # writing to a table of its own. They are separate subscriptions rather than
  # one handler writing both, so that either can be switched off, and so that a
  # failure in one cannot take the other with it.
  #
  # `user_seen` is the one event points do not use: contribution counts turning
  # up, points do not. It is deduplicated per day by the table's own index, so
  # the handler can be called as often as Discourse sees the member.
  on(:post_created) { |post, _opts, _user| Ingenic::ContributionEvents.post_created(post) }
  on(:post_destroyed) { |post, _opts, _user| Ingenic::ContributionEvents.post_destroyed(post) }
  on(:like_created) { |post_action, _creator| Ingenic::ContributionEvents.like_created(post_action) }
  on(:like_destroyed) do |post_action, _creator|
    Ingenic::ContributionEvents.like_destroyed(post_action)
  end
  on(:accepted_solution) { |post| Ingenic::ContributionEvents.solution_accepted(post) }
  on(:unaccepted_solution) { |post| Ingenic::ContributionEvents.solution_unaccepted(post) }
  on(:user_seen) { |user, previous_seen_at| Ingenic::ContributionEvents.user_seen(user, previous_seen_at) }

  # The visible half of the same two events: 已解决 is put on the topic when an
  # answer is accepted and taken off when it is not. Guarded on the plugin's
  # switch for the same reason as the handlers above — these outlive the
  # setting, and a forum that has switched the plugin off should not go on
  # editing topics in the background.
  on(:accepted_solution) do |post|
    Ingenic::StatusTags.solved!(post.topic, solved: true) if SiteSetting.ingenic_enabled
  end

  on(:unaccepted_solution) do |post|
    Ingenic::StatusTags.solved!(post.topic, solved: false) if SiteSetting.ingenic_enabled
  end

  # Deleting a topic takes its 高分悬赏 with it, and the points behind a standing
  # one come back on the way out.
  #
  # The foreign key cascades, because a bounty is read through its topic — the
  # topic page asks what stands on it, the board reaches offers by way of the
  # topics the viewer may see, accepting an answer looks one up by the post's
  # topic — so an offer standing on nothing is not a record of anything. That is
  # only safe alongside this handler: the points behind a standing offer are
  # escrowed, off the asker's balance since the offer was opened, so a row
  # removed without being closed takes the only thing that would ever have moved
  # them back with it. The refund runs inside the deletion's own transaction, so
  # the topic, the bounty rows and the movements that close them either all
  # happen or none of them do.
  #
  # `before_destroy` rather than the `:topic_destroyed` event, because of when
  # that event fires: `PostDestroyer` destroys the topic row inside its own
  # transaction and triggers the event afterwards, by which time the row is gone
  # — and it fires for a topic that was only moved to the trash as well, which is
  # not a deletion the offer cares about.
  #
  # Asked of the database only while a topic is being destroyed, and answered by
  # one indexed lookup that finds nothing for all but a handful of topics. Two
  # ways past it, both worth knowing: a `delete_all` runs no callbacks at all,
  # and `add_model_callback` stands aside while the whole plugin is switched off
  # — in either case the cascade removes the rows without giving anything back.
  # The escrow entry stays in the ledger, so what was lost is still visible, but
  # it has stopped being recoverable. `DEPLOY.md` says so where administrators
  # are told what they may do with a topic.
  add_model_callback(Topic, :before_destroy) { Ingenic::Bounties.refund_for_topic!(self) }

  # Navigation and homepage layout are admin-editable, so they are shipped to
  # the client through the site serializer rather than baked into the theme.
  add_to_serializer(:site, :ingenic_nav_items, include_condition: -> { SiteSetting.ingenic_enabled }) do
    DiscourseIngenic::ConfigParser.nav_items
  end

  add_to_serializer(:site, :ingenic_homepage_blocks, include_condition: -> { SiteSetting.ingenic_enabled }) do
    DiscourseIngenic::ConfigParser.homepage_blocks
  end

  # The external buttons and the section cards are content, and both are drawn
  # before anything can be fetched: the header is the first thing on every page
  # and the cards sit above the fold. They come in the site payload so the
  # first paint already has them, rather than showing an empty header and
  # filling it in a moment later.
  add_to_serializer(:site, :ingenic_header_links, include_condition: -> { SiteSetting.ingenic_enabled }) do
    IngenicHeaderLink.published.ordered.map do |link|
      {
        "id" => link.id,
        "label" => link.label,
        "href" => link.href,
        "icon" => link.icon,
        "image_url" => link.image_url,
        "show_label" => link.show_label,
        "external" => link.external?,
      }
    end
  end

  # Tag colours changed in the admin screen. Only the overrides travel: the
  # theme already knows the built-in families, and the client turns this map
  # into a stylesheet after boot. Sending it with `site` means the first paint
  # of a topic list is already coloured rather than flashing the fallback.
  add_to_serializer(:site, :ingenic_tag_colours, include_condition: -> { SiteSetting.ingenic_enabled }) do
    IngenicTagColour.override_map
  end

  add_to_serializer(:site, :ingenic_section_cards, include_condition: -> { SiteSetting.ingenic_enabled }) do
    IngenicSectionCard.published.ordered.map do |card|
      {
        "id" => card.id,
        "label" => card.label,
        "category" => card.category,
        "href" => card.href,
        "description" => card.description,
        "icon" => card.icon,
        "image_url" => card.image_url,
        "color" => card.color,
      }
    end
  end

  add_to_serializer(:current_user, :can_manage_ingenic_content) do
    scope.can_manage_ingenic_content?
  end

  # Which management screens this account may reach in full, so the plugin's
  # admin navigation offers exactly those. Without it the navigation would have
  # to guess, and the guess that shipped before was "administrator", which left
  # a group granted the download screen with no link to it.
  add_to_serializer(:current_user, :ingenic_features) do
    resolver = ::Ingenic::PermissionResolver.new(object)
    ::IngenicGroupPermission::FEATURES.index_with do |feature|
      resolver.can_manage_feature?(feature)
    end
  end

  # The two screens that can also be reached through a grant on a single
  # product or board. `ingenic_features` answers for whole-screen grants, and
  # `can_manage_ingenic_content` is true for a downloads manager too, so
  # neither can say whether this account has anything on the documentation or
  # boards screen to look after.
  add_to_serializer(:current_user, :ingenic_scoped_content) do
    resolver = ::Ingenic::PermissionResolver.new(object)
    {
      "documentation" => resolver.can_manage_any_area?("documentation"),
      "boards" => resolver.can_manage_any_area?("boards"),
    }
  end

  # The 高分悬赏 on this topic — standing or settled — so the topic page can
  # draw its banner without a second request. One lookup against the index on
  # `topic_id`, and null — rather than absent — for the overwhelming majority of
  # topics, which have no bounty and never will. The front end checks for the
  # value; the attribute is always there when bounties are switched on, so the
  # browser never has to tell "no bounty" from "the server did not say".
  #
  # Serialized here rather than returned as the row, so the page gets the shape
  # `IngenicBountiesController` sends and not whatever the table happens to hold.
  #
  # The `include_condition` asks only about bounties: whether this plugin is on
  # at all is already part of `add_to_serializer`, which leaves the attribute out
  # when it is off.
  add_to_serializer(
    :topic_view,
    :ingenic_bounty,
    include_condition: -> { SiteSetting.ingenic_bounties_enabled },
  ) do
    bounty = Ingenic::Bounties.for_topic(object.topic)
    bounty && IngenicBountySerializer.new(bounty, scope: scope, root: false).as_json
  end

  # Whether to offer the viewer the control that opens one. Answered here rather
  # than worked out in the browser, which would be a guess about permissions the
  # server has not granted yet.
  add_to_serializer(
    :topic_view,
    :can_open_ingenic_bounty,
    include_condition: -> { SiteSetting.ingenic_bounties_enabled },
  ) { scope.can_open_ingenic_bounty?(object.topic) }

  # The front page, offered to Discourse's own `default_homepage` setting.
  #
  # Discourse resolves `/` from that setting, and a plugin can put a page of its
  # own there instead of one of the built-in topic lists. That is what makes
  # this a front page rather than a panel on somebody else's: `/` is the Ingenic
  # home and nothing else, with no topic list under it and no filter bar above
  # it, while the topic lists keep the addresses they always had — /latest,
  # /top — and the sidebar keeps them one click away.
  #
  # The theme used to draw this page into the discovery route's
  # `before-topic-list` outlet instead. An outlet is a guest on another route's
  # page, which is why picking "Latest" took the home page away with it.
  #
  # `enabled` rather than nothing: with the plugin switched off the setting
  # falls back to the top menu homepage instead of offering a page that is not
  # there. Anonymous visitors get it too — a forum whose front page needs an
  # account has no front page.
  register_homepage(
    "ingenic-home",
    name: "ingenic.homepage_option",
    path: "/ingenic/home",
    route: "ingenic_home#index",
    anonymous: true,
    enabled: -> { SiteSetting.ingenic_enabled },
  )

  # Keep the public surface under /ingenic so the plugin can coexist with
  # Discourse's own routes and be replaced without changing core URLs.
  #
  # Documentation uses one glob rather than three nested routes: the theme
  # registers a single matching client route, and the controller splits the path
  # into product / version / page. Fewer moving parts on both sides, and the same
  # URL shape as the version picker produces.
  #
  # The bare path is declared first because a Rails glob only matches when the
  # slash is present — without this line /ingenic/docs is a 404 at the routing
  # layer, before any controller sees it.
  Discourse::Application.routes.append do
    # These are JSON endpoints like the rest of Discourse's admin API, so they
    # keep the format segment and are reached as /boards.json. Declaring them
    # `format: false` looked tidier and was wrong in a way that only shows up
    # under test: the route then has no `(.:format)`, so a request that is not
    # an XHR and does not ask for JSON on the path matches nothing and never
    # reaches the controller. What a browser sees is an empty 200 page from
    # `check_xhr`, which reads exactly like the controller answering with
    # nothing.
    scope "/admin/plugins/discourse-ingenic", constraints: DiscourseIngenic::ManagementConstraint.new do
      get "/documentation" => "admin/ingenic#documentation"
      get "/documentation/products/:id" => "admin/ingenic#product"
      post "/documentation/products" => "admin/ingenic#create_product"
      put "/documentation/products/:id" => "admin/ingenic#update_product"
      delete "/documentation/products/:id" => "admin/ingenic#destroy_product"
      post "/documentation/versions" => "admin/ingenic#create_version"
      put "/documentation/versions/:id" => "admin/ingenic#update_version"
      delete "/documentation/versions/:id" => "admin/ingenic#destroy_version"
      get "/documentation/versions/:id/tree" => "admin/ingenic#version_tree"
      post "/documentation/versions/:id/import" => "admin/ingenic#import_pages"
      post "/documentation/preview" => "admin/ingenic#preview_page"
      post "/documentation/versions/:version_id/pages/:slug/override" => "admin/ingenic#override_page"
      delete "/documentation/versions/:version_id/pages/:slug" => "admin/ingenic#revert_page"
      post "/documentation/pages" => "admin/ingenic#create_page"
      put "/documentation/pages/:id" => "admin/ingenic#update_page"
      delete "/documentation/pages/:id" => "admin/ingenic#destroy_page"
      get "/boards" => "admin/ingenic#board_list"
      post "/boards" => "admin/ingenic#create_board"
      put "/boards/:id" => "admin/ingenic#update_board"
      delete "/boards/:id" => "admin/ingenic#destroy_board"
      get "/permissions" => "admin/ingenic#permissions"
      get "/permission-principals" => "admin/ingenic#permission_principals"
      post "/permissions" => "admin/ingenic#create_permission"
      delete "/permissions/:id" => "admin/ingenic#destroy_permission"
      get "/group-permissions" => "admin/ingenic#group_permissions"
      put "/group-permissions" => "admin/ingenic#update_group_permissions"
      get "/category-permissions" => "admin/ingenic#category_permissions"
      put "/category-permissions" => "admin/ingenic#update_category_permissions"
      get "/tag-colours" => "admin/ingenic#tag_colours"
      put "/tag-colours" => "admin/ingenic#update_tag_colours"

      get "/downloads" => "admin/ingenic#download_list"
      post "/downloads" => "admin/ingenic#create_download"
      put "/downloads/:id" => "admin/ingenic#update_download"
      delete "/downloads/:id" => "admin/ingenic#destroy_download"
      get "/download-requests" => "admin/ingenic#download_requests"
      put "/download-requests/:id/approve" => "admin/ingenic#approve_request"
      put "/download-requests/:id/reject" => "admin/ingenic#reject_request"
      get "/download-grants" => "admin/ingenic#download_grants"
      delete "/download-grants/:id" => "admin/ingenic#revoke_grant"

      get "/download-logs" => "admin/ingenic#download_logs"

      # Points. Reading is administrator-only too: the ledger names accounts,
      # and an adjustment moves a member's standing.
      get "/points" => "admin/ingenic#points"
      put "/points/rules/:id" => "admin/ingenic#update_point_rule"
      post "/points/adjust" => "admin/ingenic#adjust_points"
      post "/points/rebuild" => "admin/ingenic#rebuild_points"
      get "/point-entries" => "admin/ingenic#point_entries"

      post "/download-categories" => "admin/ingenic#create_download_category"
      put "/download-categories/:id" => "admin/ingenic#update_download_category"
      delete "/download-categories/:id" => "admin/ingenic#destroy_download_category"

      # The homepage and footer lists. One path returns all three because they
      # are drawn on one screen; the writes are separate because each list has
      # its own fields.
      get "/site" => "admin/ingenic#site"

      # The front page's block list, replaced whole: a block is a place in the
      # list, not a record with an address of its own.
      put "/homepage-blocks" => "admin/ingenic#update_homepage_blocks"

      post "/promotions" => "admin/ingenic#create_promotion"
      put "/promotions/:id" => "admin/ingenic#update_promotion"
      delete "/promotions/:id" => "admin/ingenic#destroy_promotion"

      post "/header-links" => "admin/ingenic#create_header_link"
      put "/header-links/:id" => "admin/ingenic#update_header_link"
      delete "/header-links/:id" => "admin/ingenic#destroy_header_link"

      post "/section-cards" => "admin/ingenic#create_section_card"
      put "/section-cards/:id" => "admin/ingenic#update_section_card"
      delete "/section-cards/:id" => "admin/ingenic#destroy_section_card"

      post "/social-links" => "admin/ingenic#create_social_link"
      put "/social-links/:id" => "admin/ingenic#update_social_link"
      delete "/social-links/:id" => "admin/ingenic#destroy_social_link"

      post "/footer-columns" => "admin/ingenic#create_footer_column"
      put "/footer-columns/:id" => "admin/ingenic#update_footer_column"
      delete "/footer-columns/:id" => "admin/ingenic#destroy_footer_column"

      post "/footer-links" => "admin/ingenic#create_footer_link"
      put "/footer-links/:id" => "admin/ingenic#update_footer_link"
      delete "/footer-links/:id" => "admin/ingenic#destroy_footer_link"
    end

    # The front page at its canonical address. Discourse mounts the page chosen
    # in `default_homepage` at `/` itself; this is the same page under a path of
    # its own, which is what the client route and every link to the home page
    # use, and what makes the address survive a refresh.
    get "/ingenic/home", to: "ingenic_home#index", as: :ingenic_home

    # `format: /json/` is not decoration: a version slug is a version number,
    # and Rails otherwise reads the last dot in the path as the start of a
    # format. `/t-series/t33/1.1` reached the controller as `t-series/t33/1`
    # with the format `1`, so every version selection 404ed while the version
    # before it was the only one that could be opened. Constraining the format
    # to the one extension this endpoint actually accepts keeps the dot in the
    # path and still lets `/.../1.1.json` ask for JSON explicitly.
    get "/ingenic/docs", to: "ingenic_docs#show", constraints: { format: /json/ }, as: :ingenic_documentation_root
    get "/ingenic/docs/*path", to: "ingenic_docs#show", constraints: { format: /json/ }, as: :ingenic_documentation

    # A sibling of the documentation glob rather than a path inside it: a route
    # like /ingenic/docs/search would be swallowed by the glob above, and
    # reordering to avoid that would make a chip called "search" unusable.
    get "/ingenic/docs-search", to: "ingenic_docs#search", as: :ingenic_documentation_search
    get "/ingenic/downloads", to: "ingenic_downloads#index", as: :ingenic_downloads

    # The developer information is a sibling of the listing rather than a path
    # under a resource: it belongs to the account, and one copy of it serves
    # every gated resource.
    post "/ingenic/downloads/profile", to: "ingenic_downloads#save_profile", as: :ingenic_download_profile
    post "/ingenic/downloads/:id/request", to: "ingenic_downloads#request_access", as: :ingenic_download_request
    get "/ingenic/downloads/:id/file", to: "ingenic_downloads#deliver", as: :ingenic_download_file

    get "/ingenic/boards", to: "ingenic_boards#index", as: :ingenic_boards

    # The MCP landing page. `/mcp` itself belongs to core and answers POST (a
    # GET there is deliberately 405), so the human-readable page lives under
    # the plugin's own prefix and points at the endpoint rather than replacing
    # it.
    get "/ingenic/mcp", to: "ingenic_mcp#index", as: :ingenic_mcp

    # The homepage slots, the footer's partner strip and the footer's link
    # columns. One address because the theme asks for them together, and there is
    # no page here: every one of them is drawn inside a layout the theme already
    # owns.
    get "/ingenic/site", to: "ingenic_site#show", as: :ingenic_site

    # The member's own points. Read-only from the front end: points are earned
    # by contributing and spent on a download, and neither happens through this
    # address.
    get "/ingenic/points", to: "ingenic_points#show", as: :ingenic_points

    # 高分悬赏. Two writes and no third: accepting an answer — which is what pays
    # a bounty — is Discourse's own accepted answer and has no endpoint here, so
    # there is no second way for the forum to be told which answer won.
    #
    # `:id` on the withdrawal is the bounty's, not the topic's: a topic can have
    # a settled bounty and a standing one, and the withdrawal has to name which.
    get "/ingenic/bounties", to: "ingenic_bounties#show", as: :ingenic_bounties
    post "/ingenic/bounties", to: "ingenic_bounties#create", as: :ingenic_bounty_create
    post "/ingenic/bounties/:id/cancel", to: "ingenic_bounties#cancel", as: :ingenic_bounty_cancel

    # The weekly contribution ranking on the front page. Read-only, and public:
    # a ranking nobody can see is a ranking that does not encourage anything.
    get "/ingenic/leaderboard", to: "ingenic_leaderboard#index", as: :ingenic_leaderboard

    # The popular topics behind its card, and the page the card links to. Likes
    # first within a recent window; the controller says why.
    get "/ingenic/popular", to: "ingenic_popular#index", as: :ingenic_popular
  end
end
