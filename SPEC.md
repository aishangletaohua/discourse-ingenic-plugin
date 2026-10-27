# Ingenic Discourse — spec and verification checklist

## Delivered

Two installable pieces:

```
discourse-ingenic-plugin/   plugin — data, models, JSON endpoints, admin screens
                            (files at the repository root; installed as plugins/discourse-ingenic)
discourse-ingenic-theme/    theme  — layout, sidebar, homepage, docs/downloads/boards UI
                            (its own repository, installed as a Discourse theme)
```

Authentication is untouched: Google, GitHub and email stay as configured in
Discourse core. No other login method is added.

## Behaviour

### Navigation and layout

Discourse's own sidebar is kept whole — the visitor's own sections, the category
list and tags are core's, and so are the show/hide, collapse and filter controls
around them. The Ingenic navigation is added to the same panel as three
first-class sidebar sections, so the mobile drawer, the section filter, the
collapse state and active-link handling all come from core rather than being
reimplemented.

Three, because the navigation is three things, and the heading is what says so:

| Group (`section`) | Drawn as | Entries |
| --- | --- | --- |
| `forum` | a plain list at the top, no heading | New Post (`/new-topic`), Home, Official Announcements, Technical Discussions |
| `resources` | under the heading *Developer Resources* | Online Documentation, SDK & Firmware Downloads, Development Boards |
| `member` | a plain list at the bottom, no heading | Bounties, Points |

Only the middle group is drawn with a heading. A heading over the topic list
would be a label on the forum, and one over Bounties and Points would file them
under the developer resources — which is where they are not: they are what a
member has earned or set aside.

A link stays highlighted for the whole subtree it points at, so a reader on
`/ingenic/docs/t-series/t33/2.1.0/overview` still sees Documentation
highlighted. Core's own comparison is exact, and these links are plain URLs
rather than routes, so the section decides this itself from the current URL.
An external entry is never highlighted.

Navigation items live in the `ingenic_nav_items` site setting as JSON, so the
Ingenic team can reorder, relabel, hide or repoint entries from the admin UI.
Entries may target a category slug, an internal path or an external URL, and
carry the group they belong to. An unknown group name is read as `forum`, so a
typo moves a row rather than losing it; `position` orders entries within their
group.

An entry that names a `category` is resolved to the address the forum actually
serves — `/c/<slug>/<id>`. Discourse has no slug-only category route
(`c/*category_slug_path_with_id` requires the id and the only catch-all is the
permalink handler), so `/c/<slug>` is a 404; the id is looked up on the server
for the JSON and from `site.categories` in the theme, and a slug the site does
not have keeps the plain path as a last resort. This is why the entry resolves
rather than stores a URL.

The three categories the shipped navigation points at are created by the plugin
rather than by hand, because a fresh Discourse install has none and a category
entry pointing at a missing category is a dead link on a page that otherwise
looks finished. Open Source is a top-level section in its own right, directly
after Technical Discussions in the navigation; the rest of the tree hangs beneath
them — the series and their chips under Technical Discussions, and the two
sub-forums under Open Source:

| Section | Parent | Who may start a topic |
| --- | --- | --- |
| Official Announcements (`official-announcements`) | — | Staff |
| Technical Discussions (`technical-discussions`) | — | Everyone |
| Open Source (`open-source`) | — | Nobody: it is a container |
| Third-Party Open Source (`third-party`) | `open-source` | Everyone |
| Official Open Source (`official`) | `open-source` | Administrators only |
| T Series (`t-series`) | `technical-discussions` | Nobody: it is a container |
| T33 (`t33`), T32Pro (`t32pro`), T41 (`t41`) | `t-series` | Everyone |
| C Series (`c-series`) | `technical-discussions` | Nobody: it is a container |
| CW020 (`cw020`), CW080 (`cw080`) | `c-series` | Everyone |
| X Series (`x-series`) | `technical-discussions` | Nobody: it is a container |
| X2600 (`x2600`) | `x-series` | Everyone |
| MCU Series (`mcu-series`) | `technical-discussions` | Nobody: it is a container |
| G32S10 (`g32s10`) | `mcu-series` | Everyone |

The tree is three levels deep, so `seed!` sets `max_category_nesting` to 3
before creating anything; Discourse's default of 2 refuses the chip level and
the setting is hidden from the admin screens.

`rake ingenic:seed_categories` creates what is absent and reports one row per
category (`created`, `kept`, `moved` or `skipped`); a second run leaves an
existing category's name and colour exactly as the forum has them. Parentage is
the list's: a category whose slug is in the list but whose parent is not the one
above is re-parented, so an Open Source that an earlier version of the list
placed under Technical Discussions moves back to the top level rather than being
left behind as a second page.
`rake ingenic:seed_categories[permissions]` is the only thing that writes
permissions back, and `rake ingenic:doctor` reports any of the sixteen that is
missing. The containers are read-only so that their children can carry different
permissions at all: Discourse validates a sub-category's permissions against its
parent's, and a parent with `everyone` at any level is what lets a child be
anything.

Because core renders its own sections around the API-registered ones, "above
Discourse's own sections" is a stylesheet decision rather than an order of
registration: `ingenic_nav_order` puts the two Ingenic sections at the top of the
flex column (with the sidebar's filter box above them) or leaves them where they
land. The third block is core's community section, which closes the column
either way.

Theme settings control the sidebar's width and which side it renders on, whether
the Ingenic sections sit above or below Discourse's own sections, and the heading
over the resources block (`ingenic_nav_title`, default *Developer Resources* /
「开发者资源」). The position flip re-points the container grid's areas and is
scoped to the `md` breakpoint and up, because below that core takes the sidebar
out of the grid entirely and shows it as a drawer — there is no column to move.

Two of the icons the navigation draws are not in Discourse's own sprite subset:
`microchip` (Development Boards) and `bullhorn` (Official Announcements). Both
are declared in the plugin with `register_svg_icon`, because a list that lives in
the theme's source is not collected for the sprite the way an icon named in a
site setting is.

### Homepage

The front page at `/` is Discourse's own **latest** topic list — the table with
Topic / Replies / Views / Activity columns and the Latest / Hot / New tabs — the
same page meta.discourse.org opens on. `rake ingenic:setup` selects it as
`default_homepage`.

The theme also ships a card-style home page, registered with Discourse as the
homepage **ingenic-home** and served at `/ingenic/home`. It carries a banner,
five tool links and blocks listed in `ingenic_homepage_blocks`. Supported types:
`categories`, `bounties`, `promotions`, `announcements`, `discussions`,
`downloads`, `boards`. Order and visibility are admin-controlled; unknown types
are ignored rather than rendered broken. It is available as a homepage choice
but is not what a visitor lands on by default.

The same rake task names the site **Ingenic** (`title`) and switches
`enable_powered_by_discourse` off. The theme's stylesheet also hides
`.powered-by-discourse`, so a deployment that misses the setting does not show
the badge.

The header's language switcher names each language in its own language: **EN**
for English and **中文** for Chinese, with Discourse's native name as the
fallback for any other locale.

### Documentation

Chip families are forum sections; the documentation browser itself has a
**two-level product picker** — series, then a flyout of that series' chips —
plus a version selector, full-text search and a collapsible contents tree. The
right-hand column renders the page body as Markdown, and previous/next follow
reading order.

URLs:

```
/ingenic/docs                                     first series with documentation → its first documented chip → latest version
/ingenic/docs/<series>                            first chip of that series
/ingenic/docs/<series>/<chip>                     that chip's latest version
/ingenic/docs/<series>/<chip>/<version>           a specific version
/ingenic/docs/<series>/<chip>/<version>/<page>    a single page
```

Each level is filled in from the one before when omitted, so a link shared at
any depth still lands somewhere real. The bare URL answers with the first series
whose chips have versions, and the first chip that has them, so a series or chip
created before its documentation is written is skipped rather than shown as an
empty reader. The client then replaces the address with the canonical path, so
what a visitor copies is the canonical URL rather than the redirect stub.

Every URL answers as JSON to a fetch and as the application shell to a browser
navigation, which is what makes a documentation link shareable and refreshable
instead of only reachable by clicking through the app.

#### Version inheritance

A version stores only the pages it changed. `ingenic_doc_pages` therefore has
one row per page **per version it was edited in**, and a version with no row for
a slug resolves to the nearest earlier version that has one. The resolution
lives in `Ingenic::DocumentationResolver`, not in a controller, and each
resolved page carries where it came from so the reader can label it and the
management screen can offer "override here" and "go back to inheriting".

Without this, a documentation set would multiply by its version count, and every
typographical fix would have to be repeated in every version or silently
diverge.

The chain order comes from `ingenic_doc_versions.position`, which already
existed — no extra dependency.

The reader's version dropdown lists every version of the chip in that order and
marks the one flagged `latest`. Choosing one rewrites the URL to
`/ingenic/docs/<series>/<chip>/<version>/<page>`; the page stays put when the
chosen version has it, its own copy or an inherited one. A chip with no versions
shows "this chip's documentation has not been written yet" rather than an empty
reader.

### Downloads

A resource is a card and its files are versions. `ingenic_downloads` holds what
the visitor sees before choosing a file — name, uploaded picture, chip,
category, publish flag and one access rule. `ingenic_download_versions` holds
the releases: label, description, platform, architecture, size, checksum,
release date and source (an uploaded file or an external URL). A card with no
published version is not listed; a version that is unpublished is invisible to
the catalogue and refused by the file endpoint.

The card is horizontal: a 4:3 picture, the selected version's description in
the middle, and one button on the right labelled **Download** for every access
state. The version selector changes the description and the file the button
points at. What varies is the hint under the button and what the server asks for
first — sign-in, developer information, an application, or points — never the
button's label.

Requests, grants, points and delivery logs stay keyed to the resource, so one
approval covers every version, including ones published afterwards. Delivery
takes an optional `version_id`; it must belong to the card and be published, and
the newest published version is used when none is named.

Three tiers, stored as `ingenic_downloads.access_level`:

| Level | Visitor | Server |
| --- | --- | --- |
| `public_login` | Signs in, then downloads | Signed in |
| `login_form` | Signs in, submits the developer information form once | Signed in with a stored profile |
| `login_form_request` | Signs in, submits the form, applies for that resource | Signed in, with a profile **and** a live grant for that resource |

The developer information form is one record per account, shared by every gated
resource. It branches on identity: everyone is asked their name, country or
region, contact email, intended use and project stage; a company adds its name
and the applicant's job title, a student adds the school and field of study, and
an individual developer adds nothing. The core questions are fixed in code — the
profile columns and the conditional database checks are built around them —
while `ingenic_developer_form_fields` adds extra questions and cannot remove or
rename the core ones. A question asking for a phone number, a chat handle, a
postal address or a government identifier is ignored.

An application is recorded in `ingenic_download_requests` and emailed to
`ingenic_download_admin_email`. Approving writes an `ingenic_download_grants`
row; grants are per account and per resource, and can be revoked, so an approval
for one SDK does not open the rest and a revocation is auditable.

Files are stored under `ingenic_download_storage_path`, which defaults to a
directory beside the application rather than under `public/`: a file the web
server would hand to anyone who guesses its URL cannot be gated by anything the
plugin does. Delivery goes through the controller, which checks access first and
then streams the file with an explicit `Content-Type`, `Content-Length` and
`Content-Disposition`.

Metadata is recorded per version — label, description, platform, architecture,
size, SHA-256 and release date — while the category is the card's. The admin
creates the card first (picture included) and adds versions beneath it; the
picture is an ordinary Discourse upload, kept by `image_upload_id` and cleared
when the upload is deleted.

A resource may also carry `point_cost`, 0 by default. The price is asked after
the access level rather than instead of it, so a `login_form_request` resource
that costs points still sends a new visitor through sign-in, developer details
and approval first. Charging happens in the branch of the file endpoint that
releases the file, never in the one that reports a resource unavailable, so a
download missing from storage costs nothing.

### Official file library

A management screen over a directory on the server, separate from the download
centre and from post attachments. It uploads, files, previews and hands out
links; it does not set an access level, publish anything, or read attachments.

Folders are real directories and files keep their names, so a link is
`/ingenic/files/<path>` and renaming or moving a file changes the link. Image
extensions are served without a check, because an image in a post has to render
for a signed-out reader; every other extension is streamed only to a signed-in
account. Restricting a file is the download record's job, not the library's.

Uploads use the chunked session mechanism with `purpose: files` (eight-megabyte
pieces, 8 GB cap, resume from the byte the server reports on 409). Sessions for
this purpose are destroyed when the upload is finalised, so the only rows that
remain are pending ones, whose part files the scheduled cleanup removes after a
day. The accepted extensions come from `ingenic_file_manager_extensions` and are
enforced on the server as well as in the picker.

Access is one screen-level grant, `files`, on the Permission matrix. There is no
per-folder grant: a group either works in the library or does not see it, and an
account without the grant gets the forum's 404 on both the workbench address and
the admin route.

### Points

Three tables. `ingenic_point_rules` is the price list — what each action is
worth, its label, its order and whether it is still paid. `ingenic_point_entries`
is the ledger: one append-only row per movement, never edited.
`ingenic_point_balances` is a running total per account, derived from the entries
and rebuildable from them.

Four events, seeded by the migration at 5 / 2 / 1 / 15: `topic_created`,
`post_created`, `like_received`, `solution_accepted`. Each is an event Discourse
core (or `discourse-solved`, for the last) actually fires. Retiring an action is
`published: false` rather than a delete, because the ledger keeps referring to
it; `IngenicPointRule.amount_for` reads a retired rule as 0, which is what makes
that safe.

`Ingenic::Points` is the only door into the ledger — `award`, `reverse`,
`reverse_subject`, `spend`, `adjust`, `total_for`, `unlocked_download_ids`,
`rebuild!`. Every movement writes the entry and moves the balance in the same
transaction, so the two cannot come apart.

Reversal is a second, opposite entry rather than an edit, so the ledger says
what happened. `spend` answers `:spent`, `:already` or `:insufficient` rather
than raising, because the caller is a download and "you have not got enough" is
a state to show. An award is once per subject, enforced by a unique index rather
than by a check — including manual adjustments, which have no subject, so
Postgres's treatment of NULLs as distinct is what lets an administrator adjust
the same account twice.

The hooks that subscribe to posting events rescue everything and report to the
log: a point is not worth failing the post that earned it.

A member sees their own balance, the price list and their own history at
`/ingenic/points`, read-only from the front end. The admin screen at
**Ingenic → Points** is administrator-only for reading as well as writing,
because the ledger names accounts and an adjustment moves a member's standing.

### Development boards

A board is filed against a **chip in the product tree** and reads its name from
there, so the catalogue and the documentation cannot disagree about what a chip
is called. A board not yet filed keeps the name typed into it, so nothing
already entered is lost; deleting a chip retires it from the documentation
without taking the board off the site.

The catalogue filters by series — through the chips filed under it — and by
chip. Both filter option lists come from the tree rather than from the boards on
the page, so choosing a series does not remove the control that undoes the
choice.

Cards carry an image, name, chip, description, a specification list, an optional
documentation link and a required outbound `application_url`. Outbound links
render with `target="_blank"` and `rel="noopener noreferrer"`.

### Scoped permissions

A permission grants a user or group access to a product, a page, or a board. A
product permission is inherited by its versions and pages; a page permission is
inherited only by that page's children. Granting `T Series` lets a manager edit
its descendants; granting `T33` does not grant access to its siblings or its
parent.

Enforcement is server-side in `Ingenic::PermissionResolver` plus a Guardian
extension. Hiding a button in the admin UI is presentation, not the boundary.

## Multi-language readiness

A product is one row in `ingenic_products` per language. Each row carries its
own `locale`, and `kind` marks it as a series or a chip; the same chip is a
separate row under each language. Documentation, boards and downloads reference
those rows, so a product catalogue — not one module — is the shared anchor. A
product may have documentation, boards, downloads, any combination, or none: a
board does not require a documentation entry.

The catalogue owns the language of everything filed under it: versions and
pages inherit their product's `locale`, and a board inherits its chip's.
Downloads, download categories and site-content rows carry their own `locale`
column, so a second language needs no schema change. Codes are Discourse's own
(`zh_CN`, `pt_BR`) because they are compared against `I18n.locale`. The admin
picks a language first, and every series, version, page, board, download,
category and site-content row created or edited while that language is selected
belongs to it. Editing the other language means switching the selector; there
is no per-record locale picker and no dual-locale field.

Public reads are strict: a request serves only rows of the resolved locale,
with no cross-language fallback. Within one product, a version that does not
override a page inherits the page from the previous version of the same
language. A language therefore never shows another language's text; an
untranslated page is simply absent until it is written.

Theme strings live in `locales/en.yml` and are looked up through `themePrefix`,
because Discourse registers theme translations under a theme-specific namespace.
Adding a language means adding a file with the same keys.

## Compatibility

The target is Discourse `2026.10.0-latest`, and the extension surface was chosen
so an upgrade is a check rather than a rewrite:

- No core JavaScript is overridden and no core template is replaced. The
  integration points are `api.addSidebarSection`, `api.renderInOutlet`, a
  plugin-side route map and standard Rails routes.
- Styles are namespaced: the plugin and the theme each style only their own
  `ingenic-*` classes, using Discourse's CSS custom properties for colour rather
  than hard-coding a palette. No core class is redefined.
- Admin screens are ordinary plugin routes under
  `/admin/plugins/discourse-ingenic`, guarded by a constraint that asks the
  Guardian, rather than monkey-patching the admin router.
- `spec/plugin_requires_spec.rb` and `.tools/check/requirecheck.mjs` fail if an
  `app/` or `lib/` file is added without being required in `plugin.rb`, which is
  the failure mode that would otherwise appear only at runtime.

Known couplings, each of which fails loudly rather than silently:

- `common.scss` uses `$d-sidebar-narrow-width` to reset the sidebar width below
  the large breakpoint. A rename upstream is an "Undefined variable" error in
  the theme editor — visible, but it does block the theme until fixed.
- Two routes must stay in step: Rails serves `/ingenic/docs*` and the theme
  registers the matching client routes. If the plugin is disabled while the
  theme stays installed, the client route exists but its fetch 404s and the page
  shows its not-found state rather than failing loudly.
- `2026.10.0-latest` tracks upstream. Pin a known-good version before deploying
  to production.

## Not included in this version

- post/reply translation between Chinese and English (separate project)
- migrating content out of the existing Chinese forum
- a chip selector in the documentation *header* — the picker is in the control
  column, per the approved design

## Verification checklist

Everything below was checked statically against a Discourse `2026.10.0-latest`
checkout: Babel and Glimmer parsing for the JavaScript, tree-sitter for Ruby,
YAML parsing for the locales and settings, a scan for classes the markup names
that no rule defines, and a scan for `i18n`/`themePrefix` lookups with no
translation — plus reading the core source for every API used. The items below
are what still has to be run on a real instance.

### Plugin

- [ ] `./launcher rebuild app` completes and the migrations create the tables
- [ ] `/ingenic/docs.json` resolves the first published series and its first chip
- [ ] `/ingenic/docs.json` returns 404 when no product is published
- [ ] `/ingenic/docs/<series>/<chip>.json` returns the latest version and page tree
- [ ] `/ingenic/docs/<series>/<chip>/<version>.json` resolves an explicit version
- [ ] a page not edited in a version resolves to the version that last changed it
- [x] unknown series, chip, version or page returns 404
- [ ] unpublished pages are absent from the tree and 404 when requested directly
- [x] `/ingenic/docs-search` finds a phrase in a page body
- [ ] `/ingenic/downloads` filters correctly and returns filter options
- [x] a `login_form` resource refuses the file until a profile is stored
- [x] a `login_form_request` resource refuses the file until a grant exists
- [ ] approving a request creates a grant and emails the team address
- [x] revoking a grant closes that resource and leaves the others open
- [x] `/ingenic/downloads/:id/file` streams the file and never exposes its path
- [ ] `/ingenic/boards` returns only published boards, and filters by series and chip
- [ ] a board reads its chip name from the tree and survives that chip's deletion
- [ ] a post moves its author's balance, and deleting it leaves both the award and
      the reversal in the ledger
- [ ] a priced resource refuses the file when the balance is short, and charges once
- [ ] a priced resource is never charged when the file turns out to be missing
- [ ] `/ingenic/points` shows the reader their own history and nobody else's
- [ ] `Ingenic::Points.rebuild!` corrects a balance that has been edited by hand
- [x] `rake ingenic:seed_categories` creates the section tree and reports each row
      as `created`; a second run reports `kept`
- [x] the tree is three levels deep: a chip is under its series, which is under
      Technical Discussions, and `max_category_nesting` is 3
- [x] a section still at an old address is reported as `moved` and re-parented
      rather than duplicated
- [x] the two sub-forums are filed under `open-source`, which reports
      `has_children` and a subcategory count of 2 in `/categories.json`
- [x] a member POSTs a topic into `third-party` and gets 200, and into `official`
      and gets 403 — readable but refused, not 404
- [x] `GET /c/open-source/<id>` serves the section, and the full-chain
      `/c/technical-discussions/<series>/<chip>/<id>` address serves a chip
- [ ] malformed `ingenic_nav_items` / `ingenic_homepage_blocks` /
      `ingenic_developer_form_fields` degrade to an empty list instead of raising
- [x] `bundle exec rspec plugins/discourse-ingenic/spec` passes

### Theme

- [ ] theme installs from git and compiles without JS or SCSS errors
- [ ] the sidebar shows New Post, Home, Official Announcements, Technical
      Discussions and Open Source; then **Developer Resources** over Online
      Documentation, SDK & Firmware Downloads, Development Boards and MCP; then
      Site Feedback, Topics, Bounties, Points, All Categories and More
- [ ] only the Developer Resources block is drawn with a heading — the forum
      block above it and the member block below it are plain lists
- [ ] the Development Boards row draws a chip icon and the Official Announcements
      row draws a megaphone (both need `register_svg_icon` in the plugin)
- [ ] New Post opens the composer, and asks a signed-out visitor to sign in
- [ ] all three blocks appear in the mobile drawer
- [ ] `ingenic_sidebar_position=right` moves the sidebar, above `md` only
- [ ] `ingenic_sidebar_width` changes the column width
- [ ] `ingenic_nav_order=first` puts the Ingenic sections above Discourse's own
      sections, with the sidebar's filter box above them all
- [ ] reordering `ingenic_nav_items` reorders the sidebar after a reload, within
      the group each entry names
- [ ] an entry whose `section` is misspelled appears in the forum list rather than
      disappearing
- [ ] an external nav entry is never highlighted; a docs entry stays highlighted
      on nested documentation pages
- [x] the Technical Discussions row opens the section's own page, at the address
      carrying the id, and every category row's link answers 200
- [x] only Technical Discussions and Open Source draw a chevron and open a hover
      panel; the resources rows carry none
- [x] the Technical Discussions panel lists each series, and pointing at a
      series opens its chips in a second panel beside the first, so a long chip
      list never lengthens the series panel; the Open Source row below it opens
      its own panel with its two sub-forums, and is not a row inside the
      Technical Discussions panel
- [x] `/` is the native latest topic list, with the Topic / Replies / Views /
      Activity columns
- [x] the page title is **Ingenic**, and no `powered-by-discourse` element is
      drawn
- [x] the language switcher labels the two languages **EN** and **中文**
- [x] `/ingenic/home` draws the card page, and its blocks render in the
      configured order
- [ ] disabling a block removes it without leaving a gap
- [ ] the docs picker opens on hover for the series flyout and by keyboard
- [ ] switching version keeps the reader on the equivalent page when it exists
- [ ] a page inherited from an earlier version says which version it came from
- [x] opening `/ingenic/docs` lands on the first series with documentation and
      rewrites the address to the canonical URL
- [x] a chip with no versions says so instead of showing an empty reader
- [ ] download centre filters combine correctly
- [ ] each access tier shows the right prompt and the right button
- [ ] a priced resource shows **Unlock for N points** when affordable and
      **Needs N points** when not, and the button never links where the endpoint refuses
- [ ] `/ingenic/points` renders the balance, the price list and the reader's history
- [ ] a points URL can be pasted into a fresh tab and opens directly
- [ ] board cards lay out on the grid, with the photo framed rather than oversized
- [ ] the board filters narrow the catalogue and can be cleared
- [ ] a board application button opens the external link in a new tab
- [ ] mobile layout drops to a single column at Discourse's own breakpoint

### Admin

- [ ] the documentation screen edits products, versions, the contents tree and page bodies
- [ ] overriding a page in a version, and reverting to inheritance, both persist
- [ ] the download screen uploads a file and sets one of the three access levels
- [x] the file library lists a folder, creates one, uploads a 20 MB file in
      pieces, previews an image and shows the absolute link
- [x] a group granted `files` reaches `/ingenic/manage/files` and no other screen
- [x] an account without the grant gets 404 at both file-library addresses
- [ ] the queue approves and rejects an application
- [ ] the grant list revokes a grant
- [ ] the board screen creates, edits and withdraws a board, and files it against a chip
- [ ] the points screen reprices a rule, adjusts an account and rebuilds the balances
- [ ] a manager granted only `T33` cannot write to `T Series` or to `T32`, and
      cannot reach the points screen at all

### Integration

- [ ] Google, GitHub and email login still work
- [ ] no additional login providers appear
- [ ] content in a second locale renders for a reader whose interface language
      matches, and falls back per record where it does not

## Known risks

- **Visual judgement is the site owner's.** The migrations, the specs (626
  examples) and the HTTP paths have all been run against a Discourse development
  container, and every screen and write is exercised over HTTP by the audit. No
  message has been sent — the development container has no mail server — so the
  request-to-download flow is covered by specs up to the point a message would
  leave.
- **The developer form is the owner's design, not a copy of the Chinese
  forum's.** `forum.ingenic.com` is behind a login, so the form follows the
  identity-based specification (company, student, individual developer) given
  for this site. Further questions can be added through
  `ingenic_developer_form_fields` once someone can read the original.
- **The board-store reference URL does not resolve.** The address supplied
  (`forum.ingeinc.com`) is a typo for a domain that does not exist, so the
  board card's fields were designed from the Chinese forum's board module
  instead of from that page.
- **The card home page is a choice, not the default.** A deployment that wants
  it as the front page selects `ingenic-home` under `default_homepage`; the
  shipped default is the native latest list.
