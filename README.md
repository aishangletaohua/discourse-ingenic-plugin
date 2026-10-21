# discourse-ingenic

Ingenic community extension for Discourse. It keeps the forum as it is —
topics, categories, tags, search and the native sidebar all stay core's own —
and adds a developer area below them:

- **Online documentation**: chip-scoped, with a series → chip product picker, a
  version selector, full-text search, a collapsible contents tree, and page
  bodies authored in Markdown. A version only stores the pages that changed in
  it; everything else is inherited from the version before, and the reader says
  which version a page actually came from.
- **Download centre** for SDKs, firmware, manuals, datasheets and toolchains,
  behind three tiers of access (see below), with the files themselves stored
  outside `public/` and streamed through the plugin once access is checked.
- **Development board catalogue**, with each board filed against a chip in the
  product tree and an action button that links out to the Ingenic
  application/purchase page.
- **Points**, earned by contributing and spendable on a download, kept in an
  append-only ledger with editable rules and a member-facing page of their own.
- **高分悬赏 (bounties)**: a member sets points aside on their own question and
  pays them in full to whoever writes the answer they accept, with a board of
  what is on offer across the forum.
- **Scoped management**: a manager can be granted one product family and edit
  only that, enforced on the server for every write.
- Read-only JSON endpoints under `/ingenic` that the companion theme renders,
  plus the admin screens that manage all of the above.

It intentionally does **not** touch authentication. Google, GitHub and email
login stay exactly as configured in Discourse core.

中文说明：[README.zh-CN.md](README.zh-CN.md).

## Branches

| Branch | Holds |
| --- | --- |
| `develop` | The current version — every change lands here, and it is what a forum installs and tracks |
| `main` | Reserved for formal releases; between releases it holds only a short note |

`develop` is the repository's default branch, so a plain clone gets the current
version. Installation instructions below use it explicitly.

## Documentation

- [`docs/usage.md`](docs/usage.md) — what the forum does and how to use it, for
  members and administrators; [中文](docs/usage.zh-CN.md).
- [`DEPLOY.md`](DEPLOY.md) — installation, settings and rollback;
  [中文](DEPLOY.zh-CN.md).
- [`docs/seeding.md`](docs/seeding.md) — bulk content import from the console;
  [中文](docs/seeding.zh-CN.md).

## Access tiers

Each download record carries one of three levels:

| Level | What a visitor does | What the server requires |
| --- | --- | --- |
| `public_login` | Signs in, then downloads | A signed-in account |
| `login_form` | Signs in and submits the developer information form once | A signed-in account with a stored profile |
| `login_form_request` | Signs in, submits the form, then applies for that resource | A signed-in account with a stored profile **and** a live grant for that resource |

An application emails the team address in `ingenic_download_admin_email` and
appears in the admin queue, where it is approved or rejected. Approving creates
a grant, which can be revoked — per resource and per account, so an approval for
one SDK does not open the rest.

A resource can also carry a `point_cost`, asked *after* the level rather than
instead of it: a `login_form_request` resource that costs 500 points still sends
a new visitor through sign-in, developer details and approval before it mentions
points. The purchase is a ledger entry, so it is charged once however many times
the file is downloaded.

## Points

Members earn points for opening a discussion, replying, being liked and having an
answer accepted; each of those has a matching event that takes the points back
when the post is deleted, the like removed or the answer unmarked.

`IngenicPointRule` is the price list — a table, not constants, so the amounts, the
wording and the order are the team's and change without a deploy. Retiring an
action is unpublishing its rule rather than deleting it, because the ledger keeps
referring to it.

`Ingenic::Points` is the only door into the ledger: `award`, `reverse`,
`reverse_subject`, `spend`, `adjust`, `total_for`, `unlocked_download_ids` and
`rebuild!`. Every movement writes one row in `ingenic_point_entries` and moves
`ingenic_point_balances` by the same amount in the same transaction, so a balance
can always be argued from the rows behind it — and recomputed from them.

An entry is never edited. Taking an award back writes a second, opposite row, so
the ledger says what happened rather than only what the current state is.

Nothing here is allowed to fail a forum action: the handlers that hook into
posting rescue everything and report to the log, because losing a point is a
smaller harm than losing the post that earned it.

## Bounties (高分悬赏)

A member sets points aside on **their own** topic and pays them, in full, to
whoever writes the answer they accept. What that buys is a question with a price
on it: answering a hard one costs somebody an afternoon, and a board of what is
on offer is what makes spending one worth it.

The points are **escrowed, not promised**. Opening a bounty takes them off the
asker's balance in the same transaction, as a negative ledger entry carrying the
offer as its subject, so what has been offered cannot be spent on a download
while it stands. Checking the balance at settlement time instead would let one
member offer the same thousand points on five questions and settle whichever
happened to be answered first.

| State | What it means | The ledger |
| --- | --- | --- |
| `open` | The offer stands | Off the asker's balance (`bounty`) |
| `accepted` | An answer was accepted | Paid to the answerer in full (`bounty_award`) |
| `cancelled` | The asker withdrew it | Returned to the asker (`bounty_refund`) |
| `expired` | Nobody answered in time | Returned to the asker (`bounty_refund`) |

`open` is the only state a bounty leaves, and it never returns to it: one
standing offer per topic, enforced by a partial unique index as well as by a
check, so two forms submitted together cannot both open one. A settled row stays
where it is, and the topic page draws it — what an answer was worth is half of
what makes the board worth reading. Which answer won and who was paid are read
off the accepted post rather than stored twice.

**Accepting an answer is the payment, and it is final.** The ✓ is
discourse-solved's own, so the bounty follows it: accepting marks the topic
solved, closes the offer and moves the points in one transaction, under a row
lock that makes the same bounty impossible to pay twice however many acceptances
arrive at once. Unmarking the answer afterwards does not claw the points back.
The answerer may have spent them, and taking them from somebody who did nothing
wrong is a worse rule than living with an unmarked answer — an administrator can
adjust two accounts by hand, but nobody can repair a state the software will not
leave. Staff can accept on the asker's behalf; being the asker is what the offer
is *for*, not a requirement of the mechanism.

An offer nobody answers comes back on its own: a scheduled job refunds every open
bounty past its deadline (`ingenic_bounty_expiry_days`, 14 by default), hourly
rather than to the minute, since the points are in escrow either way. The asker
may withdraw it before that, which is the same refund under a different reason.

An offer also ends with its topic. Permanently deleting a topic returns whatever
is still standing on it, in the deletion's own transaction: the offer is closed,
the points go back to the asker and the row is then removed with the topic. That
order is the whole point — the escrow is a ledger row, and a bounty row that
disappeared without being closed would take the only record of points owed with
it. A settled offer just goes with the topic: the answerer keeps what they were
paid, and what is lost is the note of what the question was worth. Moving a topic
to the trash is not a deletion — the offer stands until its deadline, and the
board stops drawing it in the meantime.

The feature needs the points system and discourse-solved, and is off if either is
off. Switching bounties off stops the forum taking new offers and still lets the
standing ones expire and refund — switching it off must not strand anybody's
points. The same holds for a topic being deleted: the points come back whether or
not bounties are switched on, since a setting must never be a way to keep what a
member set aside while it was on.

## Requirements

- Discourse `2026.10.0-latest` or later (developed against this version)
- The companion theme [`discourse-ingenic-theme`](https://github.com/aishangletaohua/discourse-ingenic-theme)
  for the UI, installed separately as a Discourse theme

## Installation

The plugin and the theme are two independent repositories. This one is the
plugin; it is cloned into `plugins/discourse-ingenic`.

Add it to `containers/app.yml`:

```yaml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          - git clone https://github.com/aishangletaohua/discourse-ingenic-plugin.git discourse-ingenic
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

Then rebuild:

```bash
cd /var/discourse
./launcher rebuild app
```

After the rebuild the plugin runs its migrations automatically and the new
tables are created.

The theme is installed in **Admin → Customize → Themes → Install** from its own
repository URL, so later theme updates are a button in that screen and need no
rebuild. See the theme repository's README for the exact steps.

## Management

Administrators can open **Admin → Plugins → Ingenic** to manage documentation,
development boards, downloads, the application queue, grants, points, site
content and permissions. Documentation and boards can also be opened by a member
who was given either the screen's feature on the Permission matrix or a grant on
one product or board. Downloads, points and site content are reachable through a
feature grant too. The Permissions, Permission matrix, Section permissions and
Tag colours screens stay administrator-only, because each of them decides who
may do something else.

The Permission matrix grants a whole management screen to a custom group:
documentation, development boards, downloads, points or site content. It is the
coarse layer — a tick says "every product", not "this product". The per-record
grants on the Permissions screen sit underneath it and stay narrower, so one
product can still be lent to a single member without giving them the screen.
Automatic groups (staff, trust levels, everyone) are not listed: a tick on
`everyone` would hand a management screen to every visitor, which is not a
decision a checkbox should make by accident.

Tag colours assigns each tag one of five colour families: sky for general
discussion, tech for platforms, tools and hardware, resolved for answered
questions, announcement for official notices, and hot for topics the community
liked. The families are fixed so the forum keeps one visual language, while the
tag list is the site's own — a tag created this morning appears on the screen
without a release. A tag with no assignment keeps the family its name suggests,
and then sky.

The Section permissions screen is the forum-side counterpart: for each category,
it writes the `category_groups` rows that say what each custom group may do —
read, reply, or post. A category with no rows is open to everyone, so a save
that would empty a category that had rows is refused rather than silently
opening it. Automatic groups are left alone; only custom groups are edited.

The tag vocabulary is policy, not convention. Creating a tag is administrator
work; choosing an existing one while posting is not. 公告, 已解决 and 高赞 form
a staff-only tag group. 已解决 follows discourse-solved's accepted answer, and a
scheduled pass adds 高赞 at `ingenic_high_like_threshold` likes (20 by default)
and removes it when the count falls, without touching a tag a moderator applied
by hand.

Bounties have no screen of their own, because nothing about them is an
administrator's decision: members open them on their own topics and settle them
by accepting an answer. What an administrator needs from them is on the points
screen — how much is set aside behind the standing offers — and a payment that
went wrong is repaired there, by adjusting the two accounts.

The documentation screen edits the contents tree, decides which node an article
belongs to, and edits articles under any version. A version that has not edited
a page inherits it from the version before, and the screen says so: each page
shows the version it currently comes from, with controls to override it in this
version or drop the override and go back to inheriting. The article body has a
Markdown toolbar (bold, italic, heading, quote, list, code, link) and accepts
images by button, paste or drop; they are uploaded through Discourse and
inserted as `upload://` Markdown, so they render as they would in a post.

A permission can be granted to a user or a group. A product permission is
inherited by its versions and pages; a page permission is inherited only by that
page's children. The server checks every create, read, update, delete and
permission mutation, so hiding a button in the admin UI is not the authorization
boundary.

The product tree is explicit about its two levels: create `T Series` as a
`series` and `T33` as a `chip` under it. The same tree drives the documentation
picker, the download filters and each board's chip, so the three cannot disagree
about what a chip is called. Granting `T Series` lets a manager edit its
descendants; granting `T33` does not grant access to its siblings or its parent.

## Endpoints

Public, read-only except where noted:

| Method | Path | Description |
| --- | --- | --- |
| GET | `/ingenic/home` | The front page. Serves the shell; the page itself is built in the browser |
| GET | `/ingenic/docs` | The first published series, its first chip, and that chip's default version |
| GET | `/ingenic/docs/*path` | `/<series>[/<chip>[/<version>[/<page>]]]` — each level filled in from the one before when omitted |
| GET | `/ingenic/docs-search` | Full-text search across the documentation |
| GET | `/ingenic/downloads` | Download records; accepts `product`, `kind`, `version`, `platform` |
| GET | `/ingenic/downloads/:id/file` | The file itself, streamed after the access check |
| POST | `/ingenic/downloads/profile` | Stores the developer information form (signed in) |
| POST | `/ingenic/downloads/:id/request` | Applies for an access-restricted resource (signed in) |
| GET | `/ingenic/boards` | Published development boards; accepts `series` and `chip` |
| GET | `/ingenic/points` | The reader's own balance, the price list and their own history |
| GET | `/ingenic/bounties` | The standing offers, richest first, with the range a new one may be and the reader's balance |
| POST | `/ingenic/bounties` | Opens an offer on one of the reader's own topics (signed in) |
| POST | `/ingenic/bounties/:id/cancel` | Withdraws a standing offer and refunds it (signed in) |

The POSTs need a signed-in account; everything else is readable signed out.
Each GET answers two ways — JSON when the frontend asks for it with
`Accept: application/json`, and the application shell when a visitor opens or
refreshes the address directly. That is what makes a documentation or download
link shareable rather than only reachable by clicking through the app.

The documentation paths are one Rails glob rather than four nested routes: the
controller splits the path itself, so adding a level later does not mean
touching the route table. The bare `/ingenic/docs` is declared separately
because a glob only matches when the slash is present. Search is a sibling of
the glob rather than a path inside it, so a chip called `search` stays usable.

## The front page

The plugin registers the Ingenic home page with Discourse as a candidate
**homepage** — `register_homepage` in `plugin.rb`, called after the plugin's
own settings are available so the option can be conditioned on them:

```ruby
register_homepage(
  "ingenic-home",
  name: "ingenic.homepage_option",
  path: "/ingenic/home",
  route: "ingenic_home#index",
  anonymous: true,
  enabled: -> { SiteSetting.ingenic_enabled },
)
```

What that buys, in the order it matters:

- The option appears in the site's **`default_homepage`** setting, and
  Discourse mounts the page at `/` itself when it is selected. The front page is
  therefore a destination of its own, not a block drawn over a topic list, so
  choosing *Latest* in the navigation goes to the latest topics and does not
  take the front page with it.
- `/ingenic/home` remains the page's own address. Discourse mounts the chosen
  homepage at `/` but the option's `path` is what a link, a refresh and a
  shared URL use.
- `anonymous: true` means a signed-out visitor gets the front page rather than
  being redirected to the latest topics.
- `enabled` is read whenever the homepage is resolved, so switching
  `ingenic_enabled` off hands the site back to its ordinary homepage without
  anyone having to edit a second setting.

`IngenicHomeController#index` renders nothing but the application shell. The
page's content — the blocks and the sections they list — is assembled in the
browser from data the site already sends: the homepage blocks through the site
serializer, and the categories from `site.json`, which the server has already
filtered for the reader's permissions. There is no second endpoint and no second
copy of the category list.

## Site settings

| Setting | Purpose |
| --- | --- |
| `ingenic_enabled` | Master switch |
| `ingenic_nav_items` | JSON array — sidebar entries: their icon, target, group (`forum` / `resources` / `member`), order within that group and visibility |
| `ingenic_homepage_blocks` | JSON array — which homepage blocks render and in what order |
| `ingenic_docs_discussion_category` | Category used for "Discuss in forum" when a page has no linked topic |
| `ingenic_download_storage_path` | Where uploaded SDKs and firmware are written. Must be outside `public/` |
| `ingenic_download_admin_email` | Address that receives an application for a restricted download |
| `ingenic_developer_form_fields` | JSON array describing the developer information form |
| `ingenic_points_enabled` | Master switch for the points system; off leaves the ledger intact |
| `ingenic_points_exclude_staff` | Whether administrators and moderators earn points |
| `ingenic_bounties_enabled` | Master switch for bounties. Off stops new offers and still refunds the standing ones |
| `ingenic_bounty_min_points` | The smallest offer a bounty may be |
| `ingenic_bounty_max_points` | The largest offer a bounty may be |
| `ingenic_bounty_expiry_days` | Days an offer stands before it is closed and refunded |
| `ingenic_high_like_enabled` | Whether the scheduled pass maintains 高赞 |
| `ingenic_high_like_threshold` | Likes across a topic's live posts that earn 高赞 (20 by default) |

The three JSON settings accept the shapes documented inline in
`config/settings.yml`.

Content languages are not a setting of this plugin. The language list is the
site's own: `default_locale`, plus every language in
`content_localization_supported_locales` while content localisation is enabled.
Enabling a language in Discourse therefore makes it selectable in the content
manager without touching this repository.

## Data model

```
ingenic_products          the shared catalogue: series and chips, per language,
                          one two-level tree. Documentation, boards and
                          downloads all file their rows against it.
ingenic_doc_versions      versions of a chip, one flagged `latest`
ingenic_doc_pages         the pages a version actually changed, with parent_id
                          forming the contents tree
ingenic_downloads         downloadable resources, their access level and point_cost
ingenic_download_categories  the shelves the download list is filtered by, per language
ingenic_developer_profiles  the developer information form, one per account
ingenic_download_requests   applications, with their review state
ingenic_download_grants     approvals, per account and per resource
ingenic_boards            development boards, filed against a chip
ingenic_header_links      header buttons, per language
ingenic_section_cards     home-page cards, per language
ingenic_promotions        promotion slots, per language
ingenic_social_links      social strip entries, per language
ingenic_footer_columns    footer link columns, per language
ingenic_footer_links      the links inside a footer column (language follows the column)
ingenic_permissions       scoped grants to a user or group
ingenic_group_permissions a whole management screen, granted to a group
ingenic_tag_colours       explicit colour-family assignments per tag name
ingenic_point_rules       what each action is worth, and what to call it
ingenic_point_entries     the ledger: one append-only row per movement
ingenic_point_balances    a running total per account, derived from the entries
ingenic_bounties          one member's offer on one topic, and what became of it
```

A product row is one language's entry in the catalogue: an English T33 and a
Chinese T33 are two products. Versions, pages and boards follow the language of
the product they belong to rather than carrying a second copy of it, so the two
can never disagree. A download carries its own `locale`, checked against its
product's; an algorithm has no product and keeps its language on the row. A
product may have documentation, boards, downloads, any combination, or none;
none of the three owns the catalogue.

`ingenic_doc_pages` holds one row per page **per version it changed in**, not
per version: a version with no row for a slug inherits the nearest earlier
version that has one. That is what keeps a documentation set from multiplying
by its version count.

A member can be deleted. Every reference to `users` here either **nullifies** —
the row stays with the account blanked, which is what a ledger entry, an
application, a grant and a bounty do — or **cascades**, where the row is about
the person rather than about the forum: a developer profile, a cached balance, a
permission granted to someone who no longer exists. Plain references would make
deleting an active member fail with a foreign key violation, in an admin screen
that has no way to explain itself. Where the account is blanked the screens show
*a deleted account* rather than a blank. `Ingenic::Points.record` writes a
movement with no account behind it for the two paths that meet this: the
reversal of a deleted member's award, and the refund of a bounty they left
standing — the escrow is a ledger row, so the movement that closes it has to be
one too.

A topic is the other kind of reference. `ingenic_bounties.topic_id` **cascades**,
because every way a bounty is read goes through its topic — the topic page asks
what is on offer, the board reaches offers by way of the topics the viewer may
see, and accepting an answer looks one up by the post's topic — so a bounty
standing on nothing is not a record of anything. The cascade is paired with a
`before_destroy` callback on `Topic` that closes the standing offers first, which
is what keeps it from destroying escrowed points: `Ingenic::Bounties.refund_for_topic!`.

Content rows carry one `locale`, so additional languages can be enabled later
without a schema migration. Codes are Discourse's own (`zh_CN`, `pt_BR`),
because they are compared against `I18n.locale` — the language the reader picked
in their preferences. A request answers in the reader's language only: a page
or product written in another language is not served as a fallback. A language
the site does not publish is answered with the site default, and within a
language there is no second fallback.

Versions and pages do inherit **within** a product's version chain: a page a
version did not change is read from the nearest earlier version that did. That
is a version concern, not a language one, and it never crosses products.

## Adding content

Documentation pages are authored as Markdown in `ingenic_doc_pages.body` and are
rendered through `PrettyText.cook`, so they support the same formatting as
forum posts.

See `docs/seeding.md` for a worked example, or `docs/seeding.zh-CN.md` for the
same document in Chinese.

## Development

There is no local Discourse checkout in this repository. To run the plugin test
suite you need a Discourse development environment — either a checkout of
Discourse `2026.10.0-latest` with the plugin under `plugins/`, or its dev
container:

```bash
bin/docker/boot_dev --init    # from a Discourse checkout
bin/docker/rspec plugins/discourse-ingenic/spec
```

## Support

Contact the Ingenic community team.
