# Deploying the Ingenic community theme and plugin

Two independent repositories, installed separately:

| Repository | What it is | How it installs |
| --- | --- | --- |
| [`discourse-ingenic-plugin`](https://github.com/aishangletaohua/discourse-ingenic-plugin) | Rails plugin — documentation, downloads, boards, admin settings | cloned into `plugins/`, then rebuild |
| [`discourse-ingenic-theme`](https://github.com/aishangletaohua/discourse-ingenic-theme) | Theme — layout, navigation, homepage, documentation UI, MCP page, AI assistant | installed from its git URL, no rebuild |

Nothing here touches authentication. Google, GitHub and email login stay exactly
as your Discourse is configured today.

Target: Discourse `2026.10.0-latest`. Both pieces were developed and statically
verified against that version.

---

## 1. Plugin

### Option A — from the git repository (recommended)

Add it to `containers/app.yml`:

```yaml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          - git clone --branch develop https://github.com/aishangletaohua/discourse-ingenic-plugin.git discourse-ingenic
```

To update it later, pull before the rebuild:

```yaml
hooks:
  after_code:
    - exec:
        cd: $home/plugins/discourse-ingenic
        cmd:
          - git pull --ff-only
```

### Option B — copy the files

```bash
# from this machine
scp -r discourse-ingenic <user>@<host>:/tmp/discourse-ingenic

# on the server
sudo mv /tmp/discourse-ingenic /var/discourse/plugins/discourse-ingenic
```

### Then rebuild

```bash
cd /var/discourse
./launcher rebuild app
```

The rebuild runs the plugin's migrations and creates its nineteen tables. It
takes a few minutes, and the forum is offline while it runs — there is no
zero-downtime rebuild in `discourse_docker`.

A **rebuild** is what is needed here, not a container restart: the front page
added a controller and a route, and Discourse reads a plugin's files at boot.
Updating only the theme is the other case — a theme zip upload needs no rebuild
at all.

Confirm the plugin loaded:

```bash
./launcher enter app
rails c
SiteSetting.ingenic_enabled          # => true
IngenicProduct.count              # => 0, no content yet
```

Then apply the site defaults this forum always wants:

```bash
rake ingenic:setup
```

It prints every change it makes and changes nothing on a second run:

- `title` becomes **Ingenic** — the page title. Without this a fresh site still
  says "Discourse".
- The **Ingenic wordmark** is uploaded and set as `logo`, `logo_small` and
  `mobile_logo`. The header draws the uploaded logo instead of the site title,
  and a stock Discourse ships with its own wordmark already uploaded, so
  changing the title alone leaves the Discourse logo in the top-left corner.
  The image is `discourse-ingenic/assets/images/ingenic-logo.png`.
- `enable_powered_by_discourse` is switched **off** — the "Powered by Discourse"
  strip at the foot of every page. The theme also hides that element, so a
  setting left behind by a deployment does not bring it back.
- `default_homepage` becomes **ingenic-home** — the Ingenic home page at `/`,
  described under *The front page* below. The native latest list remains at
  `/latest` and in the sidebar.
- The **footer is seeded** with two partner platforms (ingenic.com and the
  Chinese forum) and two link columns (Developers, Community), because the
  theme hides the footer until those lists have content. Seeded only while both
  lists are empty: a forum that has chosen its own partners is not overridden.

`rake ingenic:doctor` checks the settings afterwards, along with the language,
category and storage settings.

---

## 2. Theme

The theme has its own repository:
<https://github.com/aishangletaohua/discourse-ingenic-theme>.

**Admin → Customize → Themes → Install → From a git repository**, and enter:

```
https://github.com/aishangletaohua/discourse-ingenic-theme.git
```

with the branch set to `develop`. (Both repositories keep `main` free of code
between releases, so a branch-less install must not rely on it.)

Installing it this way means later updates are **Admin → Customize → Themes →
Check for updates**, with no rebuild and no file upload. A zip built from the
repository can still be uploaded under *From your device* on a server that cannot
reach GitHub.

Then:

1. Open the theme and pick the **Ingenic Light** colour scheme. This is where the
   accent colour lives — the standard colour pickers edit it, and there is no
   separate brand-colour setting. It ships a light sky blue: accent
   `#2FC1FF`, text `#12263a`, header `#f2f9fd`, highlight `#cfe8fb`. If the
   header comes out grey rather than faintly blue, the theme is still on the
   site's old colour scheme and this step was missed.

   The accent is deliberately pale, which means it is a surface rather than a
   letter. The theme handles that itself: links and button labels are painted
   with a readable sibling of the same hue (see **Colours** in the theme's
   README). If you change the accent to a deeper blue, the theme still works —
   you will simply have a darker link colour than it needs.
2. Set it as the site's default theme, or make it a selectable one first and
   switch over once you are happy with it.

The theme is not a component and does not need one.

---

## 3. Settings to set after installing

### Site settings (plugin)

| Setting | Suggested value |
| --- | --- |
| `ingenic_enabled` | on |
| `ingenic_docs_discussion_category` | slug of the category that documentation discussions belong in |
| `ingenic_download_storage_path` | a directory on a large volume, outside `public/`; empty means `<app>/ingenic-downloads` |
| `ingenic_download_admin_email` | the address that should receive download applications |
| `ingenic_developer_form_fields` | JSON; empty uses the built-in developer form |
| `ingenic_official_groups` | the groups whose members should wear the official badge, e.g. `admins` |
| `ingenic_points_enabled` | on, unless you are not ready for it yet |
| `ingenic_points_exclude_staff` | on |
| `ingenic_bounties_enabled` | on, once you are ready to let members offer points |
| `ingenic_bounty_min_points` | 10 |
| `ingenic_bounty_max_points` | 1000 |
| `ingenic_bounty_expiry_days` | 14 |

`ingenic_download_storage_path` holds the uploaded SDKs and firmware. It has to
be outside `public/`: a file the web server will serve to anyone who guesses
its URL cannot be gated by anything the plugin does, so the files are streamed
through the plugin instead. Point it at a larger volume when the downloads
outgrow the application disk.

`ingenic_download_admin_email` is where an application for a restricted
resource is sent. Left empty, applications are still recorded and shown in the
admin queue — nobody is emailed about them.

`ingenic_developer_form_fields` replaces the built-in developer form. It is a
JSON array of `{ "key", "label", "type", "required" }`, where `type` is `text`
or `textarea`:

```json
[
  { "key": "full_name", "label": "Full name", "type": "text", "required": true },
  { "key": "use_case",  "label": "Intended use", "type": "textarea", "required": true }
]
```

The form the visitor sees, the validation on submit and the admin's view of an
answer all come from this one definition, so the three cannot disagree. Leave
it empty for the built-in set. Answers to a field that is later removed from
the configuration are kept rather than erased, so dropping a question does not
destroy what was already answered under it.

No telephone number is asked for, in the built-in form or in the example
above. An account already has an email address the team can write to, and a
field nobody reads is one more reason for a developer to abandon the form.

`ingenic_official_groups` names the groups whose members wear an official
identity badge beside their username. One group name per entry, spelled as the
group is spelled on its own page; case and stray spaces do not matter. The
badge is Discourse's own group flair, which the group's own settings already
let you upload or pick from an icon set — this setting only decides who wears
it. A member who already wears a badge they chose keeps it, and can pick up
the official one from their preferences page instead. Listing more than one
group is a way of saying which badge outranks which: the first listed group a
member belongs to is the one that wins. The setting is safe to fill in before
the artwork exists — a listed group with no flair configured grants nothing,
and the badges appear once it is uploaded.

`ingenic_points_enabled` is the whole points system's switch. Off, the forum
stops handing points out and a resource that carries a price is free to
whoever is cleared for it. It does not clear the ledger: the entries and the
balances are left where they were, and switching it back on resumes from
there. An administrator adjusting an account by hand still works while it is
off, because that is somebody deciding on purpose rather than the forum
deciding for them.

`ingenic_points_exclude_staff` keeps administrators and moderators off the
ledger. It is on by default, on the grounds that answering here is a member of
staff's job rather than their contribution, and a leaderboard nobody in the
community can reach the top of is not much of a leaderboard. Worth knowing
while trying the feature out: a moderator posting to test it will see nothing
happen. It does not stop staff *giving* points — a like from a moderator still
counts for the member who wrote the post.

Both settings can be changed at any time. Turning `ingenic_points_exclude_staff`
off does not back-pay the posts staff have already written; it applies from the
next one.

`ingenic_bounties_enabled` lets a member offer points on their own question,
paid in full to whoever writes the answer they accept. It needs the points system
and discourse-solved, and is off on its own if either of those is off — a bounty
is points moving, and the answer it settles on is discourse-solved's ✓.
Switching it off stops the forum taking new offers and still lets the standing
ones run out and refund; that is deliberate, because a switch meant to stop new
offers should not strand points that are already set aside.

The floor and the ceiling are what a member may offer, in points.
`ingenic_bounty_expiry_days` is how long an offer stands before it is closed and
the points go back to whoever offered them — long enough that answering takes
less time than the offer does. There is no per-category setting: a bounty belongs
to a topic, and a topic belongs to a category only incidentally.

Worth knowing before switching this on: the points are **escrowed**, so a member
who offers 500 points has 500 fewer to spend on a download until the offer is
settled. That is the mechanism rather than a side effect — it is what stops one
member offering the same 500 points on ten questions — but it is the part that
surprises people the first time.

`ingenic_nav_items` and `ingenic_homepage_blocks` are JSON. Both are optional —
with `ingenic_nav_items` left empty the theme falls back to its shipped
navigation, which is the same blocks in the same order as the JSON below.

**A configured `ingenic_nav_items` replaces the shipped list wholesale**, it does
not merge with it. So a site that configured its navigation before Bounties
existed has no Bounties entry and will not grow one: add it to the JSON, or clear
the setting and start from the list below.

The navigation is three blocks. `section` says which one an entry belongs to:

| `section` | Drawn as | Holds |
| --- | --- | --- |
| `forum` | a plain list at the top, no heading | starting a post, the front page, the forum's own sections |
| `resources` | a list under its own heading | the developer pages, their forum sections, and MCP |
| `member` | rows in the member block, below Topics, no heading | what a member has earned or set aside |

The heading over the middle block is the theme's `ingenic_nav_title`, defaulting
to **Developer Resources**. The forum block above and the member block below are
deliberately heading-less: a heading over the topic list would be a label on the
forum, and one over Bounties and Points would file them under the developer
resources. The member block itself is Discourse's community section, so its
Topics and More rows come from core; the theme adds Site Feedback above Topics
and Bounties, Points and All Categories below it.

`position` orders entries **within** their block; the blocks themselves are
always drawn in the order above. An entry naming a group that does not exist is
read as `forum` rather than dropped, so a mistyped group moves a row instead of
losing it. Site Feedback and All Categories are not configurable: they are places
in the forum, and the member block always carries them.

A starting `ingenic_nav_items`:

```json
[
  { "key": "new-post",    "label": "New Post",                 "icon": "plus",      "href": "/new-topic",                "section": "forum",     "position": 0,  "enabled": true },
  { "key": "home",        "label": "Home",                     "icon": "house",     "href": "/",                         "section": "forum",     "position": 1,  "enabled": true },
  { "key": "announce",    "label": "Official Announcements",   "icon": "bullhorn",  "category": "official-announcements", "section": "forum",    "position": 2,  "enabled": true },
  { "key": "discuss",     "label": "Technical Discussions",    "icon": "comments",  "category": "technical-discussions",  "section": "forum",    "position": 3,  "enabled": true },
  { "key": "open-source", "label": "Open Source",              "icon": "code",      "category": "open-source",            "section": "forum",    "position": 4,  "enabled": true },
  { "key": "docs",        "label": "Online Documentation",     "icon": "book",      "href": "/ingenic/docs",             "section": "resources", "position": 5,  "enabled": true },
  { "key": "downloads",   "label": "SDK & Firmware Downloads", "icon": "download",  "href": "/ingenic/downloads",        "section": "resources", "position": 6,  "enabled": true },
  { "key": "boards",      "label": "Development Boards",       "icon": "microchip", "href": "/ingenic/boards",           "section": "resources", "position": 7,  "enabled": true },
  { "key": "mcp",         "label": "MCP",                      "icon": "robot",     "href": "/ingenic/mcp",              "section": "resources", "position": 8,  "enabled": true },
  { "key": "bounties",    "label": "Bounties",                 "icon": "gift",      "href": "/ingenic/bounties",         "section": "member",    "position": 9,  "enabled": true },
  { "key": "points",      "label": "Points",                   "icon": "star",      "href": "/ingenic/points",           "section": "member",    "position": 10, "enabled": true }
]
```

**New Post** is `/new-topic`, Discourse's own route for starting a post: it opens
the composer where you are, and asks a signed-out visitor to sign in first.

`category` entries resolve to `/c/<slug>`, so navigation can point at a forum
section instead of a URL. Each chip gets its own category, and its own
documentation entry pointing at that chip's `/ingenic/docs/<product>`.

### Forum sections the navigation points at

Three slugs in the list above name a category, and a fresh Discourse install has
none of them — a `category` entry pointing at a category that does not exist is a
link to a not-found page on a sidebar that otherwise looks finished. So the
plugin creates them, and the rest of the tree beneath them:

```bash
./launcher enter app
rake ingenic:seed_categories
```

| Category | Parent | Who may post |
| --- | --- | --- |
| Official Announcements (`official-announcements`) | — | staff |
| Technical Discussions (`technical-discussions`) | — | everyone |
| Open Source (`open-source`) | — | nobody: it is a container |
| Third-party Open Source (`third-party`) | `open-source` | everyone |
| Official Open Source (`official`) | `open-source` | administrators |
| T Series (`t-series`) | `technical-discussions` | nobody: it is a container |
| T33 (`t33`), T32Pro (`t32pro`), T41 (`t41`) | `t-series` | everyone |
| C Series (`c-series`) | `technical-discussions` | nobody: it is a container |
| CW020 (`cw020`), CW080 (`cw080`) | `c-series` | everyone |
| X Series (`x-series`) | `technical-discussions` | nobody: it is a container |
| X2600 (`x2600`) | `x-series` | everyone |
| MCU Series (`mcu-series`) | `technical-discussions` | nobody: it is a container |
| G32S10 (`g32s10`) | `mcu-series` | everyone |

Technical Discussions is what its sidebar row opens, and its hover panel shows
each series; pointing at a series opens that series' chips in a second panel
beside the first. Open Source is the row directly below it in
the navigation — a top-level section of its own, not a row inside that panel —
and its hover panel shows its two sub-forums: a project of their own, or
Ingenic's own releases. The Technical Discussions tree is three levels deep, so
the task sets `max_category_nesting` to 3 before it creates anything —
Discourse's default of 2 refuses the chip level, and the setting is not on the
admin screens.

"Administrators" is Discourse's ordinary category security: edit the category,
and under **Security** give `everyone` *See* but not *Create / Reply*, with
`admins` holding *Create / Reply*.

Every section also carries a Chinese name and description, so a reader whose
interface is Chinese sees `技术讨论` on the home card rather than `Technical
Discussions`, with a matching description under it. Discourse only serves a
category's translation when content localization is enabled and `zh_CN` is
listed as a supported language, so set both before seeding:

```ruby
SiteSetting.content_localization_enabled = true
SiteSetting.content_localization_supported_locales = "zh_CN"
```

If the categories were seeded before those settings were on, run
`rake ingenic:seed_categories` again. It adds the missing `locale` and Chinese
name to the existing rows and leaves everything else untouched; running it twice
does not create a second translation. With localization switched off it writes
no translation rows, because nothing would read them.

The task creates what is missing and leaves everything else as the forum has it —
renaming and re-colouring a category afterwards is expected, and a second run
will not undo it. Parentage is the one thing the list owns: a category whose
slug is in the list but whose parent is not the one above is re-parented, because
the tree is the list's shape. An Open Source that an earlier version of the list
filed under Technical Discussions therefore moves back to the top level instead
of becoming a second open-source page.
The one thing it will put back, when asked, is the permissions above:

```bash
rake ingenic:seed_categories[permissions]
```

`rake ingenic:doctor` reports the same slugs when they are missing, along with
the settings the plugin and the theme need.

`ingenic_homepage_blocks` configures the Ingenic home page at `/`
and `/ingenic/home`. It is edited on **Admin → Plugins → Ingenic → Site
content → Home page**, which can add, remove and reorder blocks and set each
one's heading, width and size. The setting holds the same list as JSON for
export and for a deployment that would rather write it in one go.

A starting `ingenic_homepage_blocks` — the layout a fresh install draws when the
setting is empty:

```json
[
  { "type": "categories",  "limit": 3, "layout": "full" },
  { "type": "latest",      "limit": 8, "layout": "main" },
  { "type": "promotions",  "limit": 3, "layout": "side" },
  { "type": "hot",         "limit": 5, "layout": "side" },
  { "type": "bounties",    "limit": 4, "layout": "side" },
  { "type": "leaderboard", "limit": 5, "layout": "side" }
]
```

A site that has already saved a custom layout does not need to add the new card
by hand: the plugin's migration appends `leaderboard` to the saved list and puts
the four rail blocks in the order promotions → hot → bounties → leaderboard,
leaving every other block where it was. An empty setting always follows the
default layout above.

The types are `categories` (the forum's sections as cards, plus a link to all of
them), `latest` (newest discussions), `hot` (busiest this week), `bounties`
(the richest standing 高分悬赏), `promotions` (the activity slots managed in
**Ingenic → Site content → Promotions**), `leaderboard` (this week's earning
members), `announcements` and `discussions`
(topics from one category each), `downloads`, and `boards`. A block with no
content draws nothing — promotions before a campaign, bounties before an offer —
so a quiet front page is never a page of empty panels. `layout` is `full`,
`main` or `side`; leaving it empty uses the theme's default for that type.

### The front page

The front page is the Ingenic home page, registered as **ingenic-home**: a
welcome and a search box, the popular sections as cards, the latest
discussions, a rail of activity and hot topics, the partner platforms and the
footer's section links, and 高分悬赏 across the bottom. It follows
meta.discourse.org's shape without copying its content, and every block is
editable from the admin screen above.

| Setting | Value | Why |
| --- | --- | --- |
| `default_homepage` | `ingenic-home` (stored value `ingenic-home`) | Makes `/` the Ingenic home page |

Admin → Settings → Interface, or by console:

```bash
./launcher enter app
rails c
SiteSetting.default_homepage = "ingenic-home"
```

`rake ingenic:setup` sets it, together with the site's name, logo and the
powered-by switch. The plugin lists the option only while `ingenic_enabled` is
on, and a site that had it selected and then switches the plugin off falls back
to the ordinary homepage instead of showing an error.

The native latest list is still one click away in the sidebar and at `/latest`.

### Language

The interface language is Discourse's own feature, so these are core settings
rather than plugin ones. Three of them decide whether the header's language
switcher works at all:

| Setting | Value | Why |
| --- | --- | --- |
| `default_locale` | `en` | The language a first-time visitor gets |
| `allow_user_locale` | on (already the default) | With it off nobody may choose a language, and the switcher hides itself |
| `set_locale_from_cookie` | on | A signed-out reader's choice is kept in a cookie, and Discourse does not read that cookie back while this is off — the switch then looks like it does nothing |

The switcher sits at the far right of the header — signed out, just left of the
**Log in** button; signed in, immediately left of the avatar — and offers the
languages listed in the theme's `ingenic_locales` setting, `en` and `zh_CN` by
default. Each language is labelled in its own language, so a reader who cannot
read the current one can still find theirs.

Discourse remembers a language in two places and the switcher writes to
whichever one applies: a signed-in account carries its own preference (the same
one under the account's preferences), and a signed-out visitor is served from
the cookie. A reader who is signed in never sees the cookie — that is
Discourse's rule, not the plugin's.

### The foot of the page

Below the theme's own footer (the partner platform strip and the link columns,
configured in **Ingenic → Site content**) Discourse draws a line of its own: **Powered by
Discourse**, the last thing on most pages. Hiding it is one core setting, not a
theme change:

| Setting | Value | Why |
| --- | --- | --- |
| `enable_powered_by_discourse` | off | Removes the **Powered by Discourse** line, leaving the end of the page to this forum's own footer |

It is under **Admin → Settings → Site admin**, or search the settings screen for
`powered by`. The theme's own footer is a separate thing — it comes from
**Ingenic → Site content** and is unaffected by this setting.

### Theme settings

| Setting | Default | Effect |
| --- | --- | --- |
| `ingenic_locales` | `en\|zh_CN` | The languages the header's switcher offers; it stays hidden with fewer than two |
| `ingenic_sidebar_width` | 272 | Sidebar width on desktop |
| `ingenic_sidebar_position` | left | Move the sidebar to the right |
| `ingenic_nav_order` | first | Ingenic navigation above or below Discourse's own sections |
| `ingenic_nav_title` | empty | Optional heading above the navigation; empty renders a plain list |
| `ingenic_hero_title` | empty | Optional headline above the homepage blocks |
| `ingenic_hero_subtitle` | empty | Optional supporting line |

### MCP and the assistant

Both are Discourse features the theme surfaces; neither is a plugin setting.

| Setting | Value | Why |
| --- | --- | --- |
| `mcp_server_enabled` | on | Serves `/mcp` and shows **MCP** in the sidebar between the forum links and **More**. Off, the link is hidden and `/ingenic/mcp` explains that the server is not enabled |
| `ai_bot_enabled` | on | Shows the floating assistant in the bottom-right corner. It comes from `discourse-ai`; the theme hides the launcher when the bot is off |

**MCP** is set under **Admin → Settings → MCP**; approved clients, the exposed
tools and the server's activity are managed under **Admin → MCP**. The theme's
page at `/ingenic/mcp` is documentation for a developer — the endpoint to paste
into a client, the three steps of connecting one, and snippets for Claude Code
and VS Code. The endpoint itself is `/mcp`, which only answers `POST`; a `GET`
there is deliberately `405`, so the human-readable page lives under the plugin's
own prefix.

**The assistant** is `discourse-ai`'s bot. The launcher opens a short panel and
leads into `/discourse-ai/ai-bot/conversations`; a signed-out reader gets a
sign-in link that returns to that page. If `discourse-ai` is not installed, the
launcher does not appear.

---

## 4. Content

Documentation, downloads, boards, points, scoped permissions and the site's own
front page are all managed from **Admin → Plugins → Ingenic**, which has six
tabs. An administrator is offered all six. A moderator, or anyone granted a
scoped permission over a product or a board, is offered only the two screens
that grant covers — Documentation and Development boards — because the other
four are decided on the server as an administrator's, and a link to a page that
refuses you is worse than no link. Discourse's own Plugins page is staff-only,
so it is an administrator or a moderator who reaches these screens at all.

**Documentation** — the product tree (series → chips), the versions of each
product, and the page tree of a version. A page edited under one version can be
overridden in a later one; a page that is not overridden is inherited from the
version before it, so a new version starts as the last one without anybody
copying anything. The editor says which version a page currently comes from and
offers **Override in this version** and **Restore inheritance**.

The reader's version dropdown lists every version of the chip, in `position`
order, and marks the one flagged `latest`. Choosing one rewrites the address —
`/ingenic/docs/<series>/<chip>/<version>/<page>` — and the page stays put when
the chosen version has it (its own copy or an inherited one). A chip with no
versions yet says so instead of showing an empty reader, and the bare
`/ingenic/docs` lands on the first chip that actually has documentation.

**Downloads** — five tabs. *Resources* is the catalogue: name, product, version,
platform, classification, the file (uploaded, or a URL held elsewhere), release
date and access level. *Applications* is the queue for restricted resources,
showing each applicant's developer information, with Approve and Reject.
*Access* is who currently holds a grant, with Revoke. *Download record* is who
downloaded what, and when. *Categories* is the editable list of classifications
— add, rename, order and retire.

**Boards** — the development board cards: picture, chip, description,
specifications, the documentation link and the **Buy now** link.

**Permissions** — scoped access to documentation. A product-family grant is
inherited by its versions and pages; a page grant is limited to that page and
its child pages. Assignments can target a user or group, and the server enforces
every write operation.

**Points** — what members earn for contributing, and what a resource can cost to
unlock. One screen, four parts. *What earns points* is the price list: what each
action is worth, what to call it on a member's history, the order they are shown
in, and whether the forum still pays it at all. *Adjust one account* moves a
balance by hand, picked by username, with a note that becomes the reason on the
ledger row. *Repair the balances* re-derives every running total from the
entries, for when the two have drifted — the entries are the record, the balances
are only a cache of them. *Recent movements* is the last hundred rows, with
*Balances* above it naming who is holding what.

Reading this screen is administrator-only, not just writing it: the ledger names
accounts, and an adjustment moves a member's standing. A product or board scoped
permission does not reach it — there is no product a points balance belongs to.

**Site** — the parts of the site that are content rather than forum, in six
tabs. *Home page* is the layout: which blocks the front page draws, in what
order, each one's heading, width and size. A block is added from this tab, moved
with the arrows, removed, or edited in place, and the whole list is saved
together. *Home cards* are the cards under Popular sections: each names a
category to borrow its address, colour, icon and topic count, or carries a link
of its own — which is how the documentation reader gets a card without the
forum inventing a category for it. *Promotions* are the homepage activity slots,
each with a picture, a headline and a destination. *External buttons* are drawn
beside the wordmark and in the footer's partner strip: each is a label, a
built-in icon or an image URL, and a destination, and can be drawn as its icon
alone. *Partner platforms* is the strip in the footer, which takes
either a link or a QR code image — a platform whose home is a web page gets a
link, one that lives in an app gets a code the visitor scans; a platform can
also be drawn as its icon alone. *Footer columns* are the footer's link columns
and the section jump links at the bottom of every page: as many as you want,
each with its own heading and its own ordered links.

### Access levels

Every resource carries one of three levels, and the plugin enforces it on the
file endpoint rather than in the page, so the button and the file cannot
disagree.

| Level | What a visitor has to do first |
| --- | --- |
| `public_login` | sign in |
| `login_form` | sign in, and have developer information on file |
| `login_form_request` | sign in, have developer information on file, and have an application approved |

The developer information is asked for once and reused by every restricted
resource — it is not a form per file. An approval lasts: a grant has no end
date, so the log, not the grant, is what says a file was collected. Nothing
hands a URL to a resource the visitor has not been cleared for; the listing
shows the endpoint and the endpoint decides.

### What a resource costs

Above the level, a resource can also carry a **point cost**, set on the same
form in **Ingenic → Downloads → Resources**. Zero is the default and means free.

The price is asked *after* the level, never instead of it: a `login_form_request`
resource that costs 500 points still asks a new visitor to sign in, fill in
their details and be approved before it mentions points. Nothing is for sale to
an account that has not been cleared for it.

A purchase is recorded as a ledger entry, not as a new column somewhere, which
is what makes it idempotent: once bought, the resource is never charged for
again, however many times it is downloaded, and the purchase survives the
visitor's balance being spent down to nothing in the meantime. The listing draws
**Unlock for N points** when the balance suffices and **Needs N points** when it
does not, so the button never offers what the endpoint will refuse.

Charging happens in the branch of the file endpoint that actually releases the
file, never in the one that reports a resource unavailable — so a download that
turns out to be missing from storage costs nothing.

Points are earned by contributing: opening a discussion, replying, having a post
liked, having an answer accepted. Each of those also has a matching event that
takes the points back when the post is deleted, the like is removed or the
answer is unmarked. A member sees their own balance, the price list and their
own history at **`/ingenic/points`**, which is read-only from the front end —
points are earned by contributing and spent on a download, and neither happens
through that address. A visitor with no account still gets the price list, so
the page has an answer for them rather than a locked door.

Points are a plugin feature; the page is reached through the theme's navigation.
The theme ships a Points entry, and a site that has configured its own
`ingenic_nav_items` needs to add one itself.

### Deleting a member

Deleting an account in **Admin → Users** works even for a member who has been
here a while. It did not always: anyone who had earned a point, applied for a
download or set a bounty had rows pointing at their account with a key that
refused to let go, and nothing in the plugin was listening for the deletion —
so the admin screen answered with a database error instead. The plugin's
references to `users` are now either **nullifying**, where the row stays and the
account is blanked, or **cascading**, where the row is about the person rather
than about the forum.

| Table | What happens to their rows |
| --- | --- |
| `ingenic_point_entries` | kept, account blanked — the ledger still has to add up |
| `ingenic_bounties` | kept, account blanked; a settled bounty stays on its topic |
| `ingenic_download_requests` | kept, account blanked — the application and the answer it got are the record of a decision |
| `ingenic_download_grants` | kept, account blanked — it lets nobody in, and still says access was granted once |
| `ingenic_developer_profiles` | deleted — it is answers about a person, not about the forum |
| `ingenic_point_balances` | deleted — a cached total nobody holds, recomputable from the ledger |
| `ingenic_permissions` | deleted — a grant to an account or a group that no longer exists |
| `ingenic_download_logs` | deleted (this was already the case) |

Two consequences worth knowing before deleting somebody:

- A standing bounty whose asker has gone is still paid if an answer is accepted,
  and still expires at its deadline and returns the points. If the asker is gone
  at that point the refund has nowhere to land and is recorded against nobody —
  the escrow left an account, and there is no account left to return it to. The
  ledger shows it rather than losing it.
- An application from a deleted account cannot be approved: there would be no
  account to hold the access. The queue shows the row with **deleted account**
  where the name was, approving it says why it cannot be, and declining it still
  works. The same label appears in the points ledger and the access list.

### Deleting a topic

Permanently deleting a topic works even when it carries a **高分悬赏**, standing
or settled. It did not always: `ingenic_bounties.topic_id` was a plain key, and
the database refused to delete a topic that had a bounty on it — including one
settled long ago, since a settled bounty stays on its topic as the record of what
an answer was worth. The refusal came out worse than a refusal. `PostDestroyer`
deletes a topic's replies first, each in its own transaction, and only then
destroys the topic, so the error landed on the last step and left the topic
stripped of its answers and still standing, behind an error page that explained
none of it.

Now the key cascades, and the plugin refunds on the way out:

| The topic's bounty | What happens when the topic is deleted |
| --- | --- |
| standing | closed and the points returned to the asker before the topic goes |
| settled | removed with the topic; the answerer keeps what they were paid |
| none | nothing to do |

The refund is a ledger entry like any other, so the asker's history says
**Bounty returned because its topic was deleted** and their balance is whole
again. It runs inside the deletion's own transaction: either the topic, its
bounty rows and the movements that close them all go, or none of them do.

Two things to know:

- **Delete topics through the interface, a rake task, or `destroy` /
  `destroy_all`.** A `Topic.where(...).delete_all` from the console runs no
  callbacks at all: the cascade removes the bounty rows without refunding
  anybody, and the points are gone with no movement to account for them. The
  same happens if the plugin itself is switched off with `ingenic_enabled` —
  a switched-off plugin registers no callbacks — so switching the whole
  extension off is the one act that can cost a member their escrow. Switching
  off only `ingenic_bounties_enabled` costs nothing: the offer still comes back.
  Moving a topic to the trash is not a deletion at all — the offer stands, the
  board stops drawing it, and it ends at its deadline as usual.
- Deleting a topic moves points, so the asker's ledger tells them why. It does
  not record *who* deleted it — a `before_destroy` callback is not told which
  administrator pressed the button, and naming one would be a guess. **Admin →
  Logs → Staff actions** is where that is kept.

Use `docs/seeding.md` for console examples and migration/bootstrap workflows —
in English, or `docs/seeding.zh-CN.md` in Chinese. They cover the same ground:
both are worth skimming, and the Chinese one is the one to hand to somebody who
will be doing the seeding. The console remains useful for bulk imports, but
normal editing should use the management pages.

Short version:

```bash
cd /var/discourse
./launcher enter app
rails c
```

Then create a product, a version and pages, as in `docs/seeding.md`. Until there
is at least one published product, `/ingenic/docs` shows its "not available"
state — that is expected, not a bug.

### What a site can change, and what is written into the code

There are two kinds of thing here, and they are changed in two different places.
Knowing which is which is what makes a deployment a settings change rather than
a release.

**Content and appearance, edited in the admin screens — no deployment:**

| What | Where |
| --- | --- |
| Wordmark, small and mobile logo, favicon and large icon | **Admin → Site settings → Branding** (`logo`, `logo_small`, `mobile_logo`, `favicon`, `large_icon`) |
| Front page blocks — add, remove, reorder, heading, width, count | **Ingenic → Site content → Home page** |
| The cards under Popular sections, including one for the docs reader | **Ingenic → Site content → Home cards** |
| External buttons — name, icon or image, destination, icon-only | **Ingenic → Site content → External buttons** |
| Promotion picture, headline, button and destination | **Ingenic → Site content → Promotions** |
| Partner platform icon or QR image, label, destination | **Ingenic → Site content → Partner platforms** |
| Footer columns and the section jump links at the bottom of every page | **Ingenic → Site content → Footer columns** |
| Board picture, specifications, documentation and Buy links | **Ingenic → Boards** |
| SDK and firmware files, their access level and price | **Ingenic → Downloads** |
| Documentation series, chips, versions and pages | **Ingenic → Documentation** |
| Sidebar entries, labels and destinations | plugin setting `ingenic_nav_items` (JSON; empty uses the shipped list) |
| Hero headline and supporting line | theme setting `ingenic_hero_title` / `ingenic_hero_subtitle` |
| Sidebar width, side, order and heading; languages offered | theme settings |
| Download storage path, application email, developer form, points values, bounty limits | plugin site settings |

Three details worth knowing about the images:

- The wordmark shipped in the plugin (`assets/images/ingenic-logo.png`) is a
  **stand-in drawn for testing**, not an Ingenic brand file. Replace it under
  Branding. `rake ingenic:setup` fills the logo only when it is empty, so it
  will not put the stand-in back over an upload of your own.
- A favicon is a square. Upload `assets/images/ingenic-favicon.png` (512 × 512)
  to **both** `favicon` and `large_icon`. The horizontal wordmark must not go
  there: Discourse crops it to a square from the center, so the browser tab
  shows a fragment of the letters rather than the mark. `large_icon` is what the
  phone's home-screen icon and the installed app's icon are made from.
- Pictures inside promotions, partner platforms, external buttons, home cards and
  boards are **URLs**, not uploads. Upload the image to the forum first (or host
  it on a CDN) and paste its address. The logo and favicon are the two places
  that take an upload.

**Fixed in the code — changing any of these is a code change and a redeploy:**

- Colours, type, spacing and the sky-blue palette (theme SCSS).
- The three cards the home page draws before any have been created: technical
  discussions, the documentation reader and announcements.
- The nine block types and the three widths (full, main, side) the renderer
  understands. A type it does not know is refused rather than half-drawn.
- Interface labels and their English and Chinese translations.
- The sidebar's icons and its three blocks (forum / developer resources / the
  member block).
- The stand-in wordmark file.

---

## 5. Verify

Open these and check each one:

- [ ] `/` shows the Ingenic home page — headline, search, the section cards and
      the discussion feed — and `/latest` is the forum's own topic table
- [ ] the corner of the page says **Ingenic**, and the foot has no
      "Powered by Discourse"
- [ ] the header's language switcher reads **EN** and **中文**
- [ ] `/ingenic/docs` lands on the first chip that has documentation and rewrites
      the address to it
- [ ] the series → chip picker narrows the chips under the series you point at
- [ ] the page tree expands, and previous/next move through the pages in order
- [ ] the version picker switches versions and stays on the same page where it exists
- [ ] a page left unedited in a later version shows the earlier version's text, and the editor names the version it came from
- [ ] `/ingenic/downloads` filters by series, chip, classification, version and platform
- [ ] a `public_login` resource downloads after signing in; a `login_form_request` one asks for an application first
- [ ] approving an application in the queue lets that account download, and **Ingenic → Downloads → Download record** names the account
- [ ] a post written by a member moves their balance, and **Ingenic → Points → Recent movements** shows the entry
- [ ] deleting that post takes the points back, and the original entry is still in the ledger beside the reversal
- [ ] a resource you gave a point cost to shows **Unlock for N points** to an account that can afford it and **Needs N points** to one that cannot
- [ ] buying it costs the points once; downloading it a second time costs nothing
- [ ] `/ingenic/points` shows the signed-in member their balance, the price list and their own history — and nobody else's
- [ ] an administrator adjusting an account by hand moves the balance and writes the note as the reason
- [ ] deleting a test member who has points, an application or a bounty goes through without a database error, and their movements are still in **Ingenic → Points → Recent movements** with **deleted account** where the name was
- [ ] permanently deleting a test topic that carries a standing bounty goes through, the asker's balance is whole again, and **Ingenic → Points → Recent movements** shows it with **Bounty returned because its topic was deleted** as the reason
- [ ] with `ingenic_points_enabled` off, a priced resource downloads free and nobody earns anything; the balances are still there when it goes back on
- [ ] on a question of your own, **Set a bounty on this question** names the range and your balance, and setting one takes the points off your balance at once — **Ingenic → Points** then shows them set aside
- [ ] the standing offer shows on the topic itself, on the front page's bounty panel and on `/ingenic/bounties`, and a member who is not you sees no way to withdraw it
- [ ] accepting an answer on that topic pays the answerer in full, closes the offer, and the topic then says what was paid and to whom
- [ ] withdrawing a standing offer hands the points back, and one nobody answers comes back on its own within the hour after `ingenic_bounty_expiry_days`
- [ ] `/ingenic/boards` shows boards, and a board with a purchase link shows a **Buy now** button
- [ ] the header shows a language switcher at its right end — beside **Log in** when signed out, beside the avatar when signed in; its labels are **EN** and **中文**, each language named in its own language; picking 中文 reloads the page in Chinese, and picking EN brings it back
- [ ] the same switch works when signed in — the choice then survives signing out and back in
- [ ] the Ingenic navigation appears in the sidebar, and in the mobile drawer on a phone
- [ ] the sidebar reads as three blocks — forum, developer resources, member — with MCP directly below Development Boards, and the last block in the order Site Feedback · Topics · Bounties · Points · All Categories · More; clicking **MCP** opens `/ingenic/mcp` with that row highlighted
- [ ] `/ingenic/mcp` shows the address `https://<your forum>/mcp`, a **Copy** button that copies it, and the steps and client snippets; the same page in 中文 is fully translated
- [ ] with `mcp_server_enabled` off, **MCP** disappears from the sidebar and `/ingenic/mcp` says the server is not enabled
- [ ] the robot launcher sits in the bottom-right corner, opens a panel, closes with **Escape**, and its button leads to the AI bot's conversations (or to sign-in first when signed out)
- [ ] with `ai_bot_enabled` off, the launcher is gone and the rest of the page is unaffected
- [ ] a docs URL can be pasted into a fresh tab and opens directly
- [ ] `/ingenic/home` opens the same page as `/`
- [ ] the section block shows three cards out of the box — Technical Discussions, Online Documentation, Official Announcements — and **All sections** opens `/categories`
- [ ] a card added in **Ingenic → Site content → Home cards** replaces the built-in three, and a card naming a category shows that category's colour and topic count
- [ ] the buttons from **Ingenic → Site content → External buttons** appear beside the wordmark and in the footer's partner strip; an icon-only one still has its name as its accessible label, and both open their destination in a new tab when marked external
- [ ] the right-hand rail reads Latest activity, then the bounty panel, then Hot topics, all on the first screen without scrolling
- [ ] the promotions you configured in **Ingenic → Site content** appear in that rail if you added a `promotions` block
- [ ] the footer shows the partner platform strip — a link for one kind, a scannable code for the other — and the link columns you configured
- [ ] with `enable_powered_by_discourse` off, the page ends at that footer and the **Powered by Discourse** line is gone
- [ ] a member of a listed `ingenic_official_groups` group wears its badge beside their username, and a member who picked a badge of their own keeps it
- [ ] Google, GitHub and email sign-in all still work
- [ ] **Admin → Customize → Themes** shows no theme errors

`bundle exec rspec plugins/discourse-ingenic/spec` runs the plugin's spec suite
inside the container and is the fastest way to check the endpoints.

---

## 6. Rollback

- **Theme**: switch the default theme back in **Admin → Customize → Themes**.
  No rebuild, no downtime.
- **Plugin**: remove the `git clone` line from `app.yml` (or the directory from
  `plugins/`) and rebuild. The plugin's tables are left in place — they are
  named `ingenic_*` and nothing else reads them, so leaving them costs nothing
  and keeps the content if you reinstall.

---

## 7. Moving a configuration to another machine

Two things make up this forum's configuration: the plugin's settings and content,
and the theme's settings. They are exported separately because they belong to
different objects.

### Theme settings

**Admin → Customize → Themes → Ingenic Community → Export** writes a zip whose
settings field carries the values currently in the theme, so importing that zip
on another machine brings the theme's settings with it. Nothing else is in there
— the theme's files come from this repository.

### Plugin settings and content

```bash
cd /var/www/discourse

# create the forum sections the navigation links to — see above
rake ingenic:seed_categories

# write everything this plugin owns into one file
rake ingenic:export_config[/shared/ingenic-config.yml]

# see what a file holds, without touching anything
rake ingenic:show_config[/shared/ingenic-config.yml]

# apply it — the second argument rolls the whole thing back afterwards
rake ingenic:import_config[/shared/ingenic-config.yml,dry]
rake ingenic:import_config[/shared/ingenic-config.yml]
```

The file holds the plugin's site settings (the ones you changed, not the ones
still on their defaults) and the content an administrator typed in: the product
tree, versions, pages, the download catalogue and its categories, boards,
documentation permissions, promotions, the footer, social links and point rules.

It deliberately holds **nothing members produced**. Point balances, point
entries, bounties, download applications, access grants, developer profiles and
the download record are a record of what people did, and one of those tables
holds personal data about them. A copy of that is a database dump, which is a
different thing with a different lifetime; take one of those if you need it.

`import_config` is an upsert by natural key — a product is identified by its
slug and locale, a version by its product and slug, and so on — so importing the
same file twice changes nothing the second time. It never deletes: a row that
exists in the forum but not in the file is left alone and reported as
`Left alone` at the end, for you to decide about. The whole import runs in one
transaction, so a file it refuses leaves the forum exactly as it was.

Uploaded SDK and firmware files are not in the file either — only the rows that
point at them, including the path each upload was written to. A machine whose
download directory was copied across restores to a working download centre; a
machine without those files gets rows pointing at files that are not there.

### After any deployment

```bash
rake ingenic:doctor
```

It checks the handful of settings whose wrong value produces no error anywhere —
the plugin switched off, a language nobody can switch, a download directory
nothing can be written to, a forum section the navigation links to and the forum
does not have — and names what to change.

---

## What has and has not been tested

Verified in a Discourse development container — `2026.10.0-latest`, PostgreSQL,
the plugin and the theme mounted as the development ones — and by asking the
running server itself, over HTTP, rather than by reading the code:

- the migrations ran, in the development database and in the test one, creating
  the tables, the foreign keys and the partial unique index the ledger relies on
- the plugin's spec suite passes: 548 examples, 0 failures
- `rake ingenic:seed_categories` ran against a real installation and built the
  three-level tree with the permissions it says it has — including moving an
  Open Source that an earlier version had placed under Technical Discussions
  back to the top level — and `rake ingenic:doctor` reports no failures
- the theme was installed as the site's default theme, and its navigation was
  checked in a browser: the three blocks, their order, their icons, and which
  link lights up on which page
- 44 checks ran against a real PostgreSQL and the real destruction paths —
  `PostDestroyer` with `force_destroy`, `UserDestroyer` — covering the escrow
  leaving the balance, the refund on a permanently deleted topic, no refund for a
  settled one and nothing at all for a trashed one, the database's own cascade
  when a row is deleted behind the callbacks, and a deleted member's rows staying
  behind with no owner. Every balance was read back against the sum of the ledger
  behind it
- 86 checks ran against the server over HTTP: signing in, the board, a member's
  own page, opening and withdrawing an offer through the plugin's own endpoints,
  both refusals — a second offer on one topic, an offer above the ceiling — and a
  topic permanently deleted by two administrators, because the forum will not let
  the one who trashed it empty the trash. The escrow came back afterwards. Seven
  pages answered 200 with the application shell, every section in the tree was
  read out
  of `/site.json`, a member published a project in Third-Party Open Source (200)
  and was refused in Official Open Source (403), and the navigation setting was
  written and read back through the endpoint the admin screens write through
- 89 more checks went over HTTP at the screens and the writes behind them,
  asking of each not only whether it opened but whether what it wrote was what
  came back reading: every administrator screen and its refusal to a member, a
  series, a chip, a version, a page, and a second version inheriting the first
  one's page until it overrides it and again once it reverts, a board, a
  download category and a resource, a permission, a promotion, a social link, a
  footer column and the links inside it, a point rule and an adjustment,
  documentation search, and the four documentation addresses that name nothing
  answering 404 rather than somebody else's page

What that leaves unverified, because a container is not a forum with people on
it:

- nothing has been looked at in a browser. The navigation was checked as a
  browser loads it, but no page has been seen, so the layout, the palette and the
  proportions are as designed rather than as confirmed
- no message has been sent: the container has no mail server, so the
  request-to-download flow stops where a message would leave
- the download centre was tried with a real 200 MB file: the open tier streamed
  it whole and it hashed to the checksum on the row, the form tier refused the
  file until the developer information was submitted, and the approval tier
  refused until an application was approved, streamed the file once it was, and
  refused again after the grant was revoked. The bytes went through the
  controller, not a static URL
- the admin screens have not been opened: the endpoints behind them answer and
  the Ember code compiles, but nobody has clicked through them
- nothing has been upgraded. This is the schema as created, not as altered by a
  later release of the plugin

Expect the first rebuild to be where anything that is wrong shows up. If the
theme reports a compile error, it will name the file and line in
**Admin → Customize → Themes**.
