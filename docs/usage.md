# Ingenic Community Forum — Usage Guide

This guide is for everyone who uses the English Ingenic forum: members who read
documentation, download SDKs, ask questions or answer them, and administrators
who publish content and decide who may download what.

It covers what the forum does, how each feature is used, where the administrator
screens are, and which requirement each part of the site was built to satisfy.
It is the companion to:

- [`README.md`](../README.md) — architecture, endpoints and data model
- [`DEPLOY.md`](../DEPLOY.md) — installation, settings and rollback
- [`docs/seeding.md`](seeding.md) — bulk content import from the console

Chinese version: [`usage.zh-CN.md`](usage.zh-CN.md).

## Contents

1. [What this forum is](#1-what-this-forum-is)
2. [Requirements summary](#2-requirements-summary)
3. [Feature map](#3-feature-map)
4. [Getting started as a member](#4-getting-started-as-a-member)
5. [Online documentation](#5-online-documentation)
6. [Downloads](#6-downloads)
7. [Development boards and samples](#7-development-boards-and-samples)
8. [Points](#8-points)
9. [Bounties (高分悬赏)](#9-bounties-高分悬赏)
10. [MCP and the AI assistant](#10-mcp-and-the-ai-assistant)
11. [Administrator guide](#11-administrator-guide)
12. [Troubleshooting](#12-troubleshooting)
13. [Repository and support](#13-repository-and-support)

## 1. What this forum is

The Ingenic community forum is a standard Discourse forum with a developer area
added underneath it. Topics, categories, tags, search, notifications, flags and
the rest of the forum are Discourse's own; the extension adds four things that
are specific to Ingenic:

- **Chip documentation** that follows the product tree and is versioned.
- **A download centre** for SDKs, firmware, manuals and tools, with three levels
  of access and an approval workflow.
- **A catalogue of development boards and sample chips**, with application and
  purchase links.
- **A contribution economy** — points for helping, and bounties that let a
  member put points behind a question.

Two optional integrations connect the forum to AI tools: an **MCP server** page
and a **floating assistant**. Both depend on features that a site administrator
enables separately.

The forum is bilingual. The interface switches between English and Chinese in
the header. Content is language-first: the shared product catalogue, its
documentation, downloads and the editable site text are written and read one
language at a time, with no cross-language fallback. Authentication is
untouched: the sign-in methods are whichever ones the site has configured
(email, Google, GitHub and so on).

## 2. Requirements summary

The project grew in stages. Each row is the requirement as it was agreed, what
was built for it, and where a reader can see it.

| # | Requirement | What was delivered | Where to see it |
| --- | --- | --- | --- |
| 1 | Keep Discourse native; add an Ingenic developer area rather than replace the forum | Native topics, categories, tags and sidebar kept; plugin plus theme installed alongside | The whole forum |
| 2 | Online documentation with a product hierarchy | Series → chip product tree, versioned pages, Markdown reader, contents tree, full-text search | `/ingenic/docs` |
| 3 | Versions must not duplicate every page | A version stores only the pages it changed; other pages are inherited from the nearest earlier version | Version selector; Admin → Documentation |
| 4 | Manage documentation from the admin UI | Create series, chips, versions and pages; reorder; rename; override or restore inheritance | Admin → Plugins → Ingenic |
| 5 | SDK/firmware downloads with three access levels | Sign-in, developer information, and application plus approval; files stored outside the web root and streamed after a check; uploads sent in eight-megabyte pieces so multi-gigabyte images pass the web server's limit | `/ingenic/downloads` |
| 6 | Application workflow with email and per-account grants | Application queue, email to the team address, approve/decline, revocable grants with optional expiry | Admin → Downloads → Applications / Access |
| 7 | Development board catalogue | Boards and samples filed against chips, filters, cards and a detail dialog | `/ingenic/boards` |
| 8 | Application and purchase are separate actions | Apply and Buy drawn side by side; a button without a link is grey, and the separate Sold out switch stamps the board and disables both | Board card and dialog |
| 9 | Scoped management | A user or group can be granted management of a product, page, board or download; enforced on the server | Admin → Permissions |
| 10 | Points for contribution | Rules table, append-only ledger, balances, member history, spending on downloads | `/ingenic/points`; Admin → Points |
| 11 | High-value bounties on questions | Points escrowed on the asker's topic, paid on accepted answer, refunded on withdrawal, expiry or topic deletion | `/ingenic/bounties`; topic banner |
| 12 | A front page that is a page, not a topic list | Registered homepage, configurable blocks, section cards, promotions, external buttons, partner platforms, footer columns | `/` and `/ingenic/home` |
| 13 | A forum that reads as Ingenic, in both languages | Sky-blue palette, three-block sidebar, bilingual strings, language switcher, wider layout and clearer borders | Theme |
| 14 | Connect the forum to AI clients | MCP landing page with endpoint and client steps; floating assistant into the AI bot | `/ingenic/mcp`; bottom-right robot |
| 15 | Ship it and explain it | Plugin and theme in separate repositories; deployment, seeding and this usage guide in both languages | Repositories and `docs/` |
| 16 | Footer links that go somewhere of their own | Terms of service, privacy policy and points rules are standalone pages at `/ingenic/pages/<slug>`, seeded in both languages and edited in Site content → Pages | `/ingenic/pages/terms`; Admin → Site content → Pages |

### Not included

These were considered and deliberately left out of this version:

- Translating posts and replies between Chinese and English (a separate project).
- Migrating existing content out of the Chinese forum into this one.
- A chip selector inside the documentation header — the picker lives in the
  documentation control column, as approved.

## 3. Feature map

| Area | Members can | Administrators can |
| --- | --- | --- |
| Forum | Read, post, reply, like, flag, bookmark, message, search; choose existing tags on a topic | Categories, groups, trust levels, site settings — all core Discourse; per-section permissions and the tag vocabulary |
| Tags and status | Choose a tag while posting; see 公告, 已解决 and 高赞 beside titles | Create tags, assign their colours, and leave acceptance and likes to apply the status tags |
| Documentation | Pick a series and chip, switch version, search, read, follow previous/next, open the forum discussion | Create the product tree, versions and pages; control publishing; grant scoped edit rights |
| Downloads | Filter the catalogue; download, fill in developer details, apply for access, unlock with points | Upload files, set access and price, review applications, grant or revoke access, read the download record |
| Official files | Nothing — the library is internal | Upload SDK archives, PDFs and images into folders, preview them, copy a link. Access levels are set where the link is used |
| Boards | Filter by type and chip, read the dialog, follow Apply or Buy | Create cards, set type, chip, links, sold-out switch, specifications, publication and order |
| Points | See their balance, the price list and their own history | Edit rules, adjust an account, inspect balances and movements, recompute balances |
| Bounties | Put points on their own question, withdraw, accept an answer | Nothing specific: settle by accepting; repair mistakes through points adjustments |
| Site content | See the home page, promotions, footer and standalone pages the team configured | Edit home blocks, home cards, promotions, external buttons, partner platforms, footer columns and standalone pages |
| MCP / assistant | Copy the MCP endpoint and connect a client; open the assistant | Enable or disable the core MCP server and the AI bot |

## 4. Getting started as a member

### 4.1 Signing in

Use the sign-in methods the site offers. The Ingenic extension does not add or
change authentication, so the account, password reset, email verification and
social login all behave as they do on any Discourse forum.

Some downloads and all bounties require an account. Reading the forum,
documentation and the board catalogue does not.

### 4.2 Finding your way

The left sidebar has three blocks:

- **Forum** (no heading): New Post, Home, Official Announcements, Technical
  Discussions, Open Source.
- **Developer Resources** (under a heading): Online Documentation, SDK &
  Firmware Downloads, Development Boards, MCP.
- **Member** (no heading, Discourse's community section): Site Feedback,
  Topics, Bounties, Points, All Categories, More.

MCP appears below Development Boards, and only while the site's MCP server is
enabled. Site Feedback appears when the site has that category.

Hovering **Technical Discussions** opens a panel with the chip series (T, C, X,
MCU). Pointing at a series opens that series' chips in a second panel beside the
first, so the series list stays one row each however many chips a series holds.
**Open Source** is the next row of the sidebar, not a row inside that panel: it
is a top-level section of its own, and hovering it opens its two sub-forums.
Only those two rows carry a chevron and open on hover; the rest of the sidebar is
a plain list.

Discourse's own **Tags** and **Chat** sections are not shown. A tag here labels
or dates a topic; it is not a second way to browse, so the tag list stays out of
the sidebar (see 4.4). The forum does not use chat.

The site may let you collapse sections or filter the sidebar; those controls are
Discourse's own. The developer-resources heading can be renamed by an
administrator, and the whole list can be replaced in the site settings, so a
particular site's labels may differ slightly from the ones above.

### 4.3 The front page

The front page is assembled from blocks: popular sections, latest or hot
discussions, downloads, boards, promotions, bounties and the weekly contributor
ranking. Which blocks appear, their order, width and row count are set by the
administrators.

The **weekly contributors** block ranks members by the points they earned in
the current week. It is a display of the points ledger, not a separate score.

### 4.4 Posting and discussions

Posting, replying, quoting, mentions, likes, bookmarks, notifications and
flags are all standard Discourse behaviour. Three Ingenic features attach to
topics:

- A **bounty banner** appears above the posts when the topic carries a standing
  offer (see section 9). A **Bounty** field in the composer lets you set one
  aside while writing the first post (see 9.2).
- The **official identity badge** appears beside the names of members of the
  groups an administrator listed for it.
- **Tags** say what a topic is about and what state it is in. When posting you
  may choose from the tags that already exist; creating a new tag is an
  administrator's job, so the vocabulary stays a vocabulary rather than a
  collection of one-off spellings.

Three tags are status rather than subject: **公告** (official notice),
**已解决** (solved) and **高赞** (well liked). Only staff may apply them.
**已解决** is put on a question when its author accepts an answer — staff can
accept on the author's behalf — and comes off if the acceptance is undone.
**高赞** is applied automatically when the likes across the topic's live posts
reach the threshold, 20 by default, and is taken off again if the count falls
below it. A 高赞 that a moderator applied by hand is never removed by that
automatic pass.

In a topic list, the first line of each row is its section, and that badge is
the way into the category; tags are not a second navigation list.

**Open Source** is a section rather than a place to post. Its page shows the two
sub-sections as cards at the top — Third-Party Open Source and Official Open
Source — and below them the topics of both together. A card opens its
sub-section; the merged list is for readers who do not care which one a project
belongs to. The parent itself is read-only and takes no topics: posting happens
in one of the two sub-sections. By default Official Open Source accepts topics
from administrators only, while anyone with an account may publish in
Third-Party Open Source.

**Technical Discussions** goes one level further: each series (T, C, X, MCU) is
a read-only container, and discussions happen in the chip under it.
A topic's category line therefore names the chip — T33, T32Pro, T41, CW020,
CW080, X2600 or G32S10 — and the series page gathers all of its chips' topics.

### 4.5 Language

Use the language menu in the header. Each language is written in its own
language — **EN** and **中文** — so the menu is readable whichever language is
currently active. The choice changes the interface; content such as
documentation pages and downloads follows the same language. Each language has
its own catalogue rows, so a translation is written rather than fallen back to.

## 5. Online documentation

### 5.1 Opening the reader

Choose **Online Documentation** in the sidebar. The page has:

- a **product picker** in the left control column: choose a series first, then a
  chip from that series;
- a **version selector** for the chosen chip;
- a **search box** that searches page bodies;
- a collapsible **contents tree** built from the page hierarchy;
- the **page body**, rendered from Markdown, with previous and next links.

A chip whose documentation has not been written yet says so instead of showing
an empty reader.

### 5.2 Products and versions

The product tree has exactly two levels: a **series** (for example `T Series`)
and a **chip** under it (for example `T33`). The same tree drives the download
filters and each board's chip, so all three agree about the name of a chip.

A version stores only the pages that were edited in it. If a page was not
touched in the selected version, the reader shows the version of that page from
the nearest earlier version that did edit it. This is why a new version does not
need a copy of the whole manual, and why a typo fixed in an old version can
still be inherited by a newer one. The administrator's page list shows which
version each inherited page currently comes from.

The version marked **latest** is the one the chip opens on. Older versions stay
readable, and a version can be marked as no longer maintained by the team.

### 5.3 Search and navigation

Search checks the pages of the selected chip and version and lists the pages
where the text appears. The
contents tree follows the parent/child structure set in the admin screen;
previous and next follow the same reading order. **Discuss in forum** opens the
topic linked to the page, or the site's documentation discussion category when
no topic is linked.

### 5.4 Sharing links

Documentation addresses are shareable and refreshable:

```text
/ingenic/docs
/ingenic/docs/<series>
/ingenic/docs/<series>/<chip>
/ingenic/docs/<series>/<chip>/<version>
/ingenic/docs/<series>/<chip>/<version>/<page>
```

Each level fills in from the one before when it is omitted, so a short link
still lands on real content. The reader replaces a short address with the
canonical one, so what you copy from the address bar is the full path.

### 5.5 On a phone

The control column collapses into the reader's mobile layout; the contents tree
and product picker remain reachable, and the page body takes the full width.
The sidebar itself becomes Discourse's standard drawer.

## 6. Downloads

### 6.1 Filtering the catalogue

The download centre has three filter rows:

1. **Chip series** — including the catalogue entry for algorithms.
2. **Model** — the chips inside the chosen series.
3. **Resource type** — SDK, firmware, manual, datasheet, toolchain, example,
   release notes or another type the team defined.

Each result is a horizontal card: the picture on the left, the selected
version's description in the middle, and one **Download** button on the right.
The filters are buttons, not drop-downs; the current choice is filled in, and
choosing another button changes the list immediately.

A card can carry several versions. The selector above the description lists
them; choosing another version changes the description and the file the button
hands over, without changing the card or the access already granted for it. The
card shows the version's platform, size, release date and SHA-256 checksum, and
a placeholder picture stands in when the team has not uploaded one.

### 6.2 The three access levels

Every card is published at one of three levels:

| Level | What you see | What you do |
| --- | --- | --- |
| Anyone signed in | **Download** after signing in; a sign-in link otherwise | Sign in |
| Signed in with developer information | **Download**, with a prompt to add your details the first time | Fill in the developer form once; it is reused for every gated download |
| Signed in with information and approval | **Download**, with a prompt to apply for that resource | Fill in the form, send an application, wait for the team to approve |

The developer form first asks who you are — a company, a student or an
individual developer — and then the questions that follow from it. Everyone
gives full name, country or region, contact email, intended use and project
stage; a company adds its name and your job title, a student adds the school and
field of study, and an individual developer adds nothing. The answers are
stored with your account, not with one download. The team can add further
questions in the site settings, but the core questions are fixed.

An application is visible in the administrator queue and is emailed to the
team's configured address. When it is approved you receive an email and can
download that resource. Approval is **per account and per resource**: an
approval for one SDK does not open another, and the team can revoke a grant. A
grant may also carry an expiry date.

While an application is waiting, the button says **Waiting for review**. If it is
declined, the card says **Access was declined** and explains how to follow up.

### 6.3 Resources that cost points

Some resources also carry a point price. The price is asked **after** the access
level, not instead of it: a resource that needs approval and costs points still
requires sign-in, developer information and approval before the points are
mentioned.

When you are eligible, the action becomes **Unlock for N points** if you can
afford it, or **Needs N points** if you cannot. Unlocking is a one-off payment —
once bought, the resource stays yours to download again. Points are spent from
the balance shown on the downloads page and on the points page.

### 6.4 Downloading

Choose the version first if the card offers more than one. **Download** then
settles whatever that card asks for — sign in, developer details, an
application, points — and the file starts as soon as the requirement is met; a
form you submit does not send you back to press the button again.

The file is streamed through the forum after the access check; it is not a
public link that can be shared around the gate. The stored SHA-256 lets you
confirm that the bytes arrived intact. If a file is missing from storage, the
forum reports the resource as unavailable and does not charge points. One
approval covers every version of that card, including releases published later.

## 7. Development boards and samples

### 7.1 The catalogue

**Development Boards** lists two kinds of item: **development boards** and
**sample chips**. Three filter rows match the download centre's style:

1. **Type** — Development boards or Sample chips.
2. **Series** — All series, or one series of the chosen type.
3. **Chip** — All chips, or one chip inside the chosen series.

Every option is a button; the current choice is filled in the accent colour and
the others keep a visible border. The chip row offers only the chips that belong
to the chosen type and series, so every option leads somewhere. Choosing a new
type clears both rows below it, because they describe the kind of item that was
just left.

The rows narrow the list in the browser: the catalogue is fetched once and the
cards are filtered without asking the server again. While it arrives, the grid
draws placeholder cards at their final size, so the page does not jump when the
real cards appear.

### 7.2 Cards and the detail dialog

Each card shows an image, name, chip, short introduction and a short
specification list. Selecting a card opens a dialog with the longer
description, the full specification list and the same two actions.

The description in the dialog is written in Markdown: links, images, lists and
tables all render, so a documentation link or a diagram belongs in the
description itself rather than in a field of its own.

### 7.3 Apply, Buy now and Sold out

The bottom of the card and the dialog always show both buttons:

- **Apply** — opens the application page for the board.
- **Buy now** — opens the purchase page.
- Both buttons are drawn in the accent colour. A button whose link is empty is
  faded and disabled; the other stays active. Two empty links therefore give
  two faded buttons, and the board is not sold out.
- **Sold out** is a separate switch. When it is on, the card and the dialog
  carry a grey-black sold-out stamp in the top-left corner and both buttons are
  faded and disabled. The links are kept, so switching it off restores the board
  as it was.

Links open in a new tab. An administrator can change either link at any time,
and the card follows on the next page load.

## 8. Points

### 8.1 Earning points

The default rules are:

| Action | Points |
| --- | --- |
| Opening a discussion | 5 |
| Answering in one | 2 |
| A post of yours being liked | 1 |
| Your answer being accepted | 15 |

The amounts, labels and order are editable in the admin screen. A rule can be
switched off or set to zero without deleting the entries already written under
it. By default administrators and moderators do not earn points, but a like from
a staff member still counts for the member who wrote the post.

If a post is deleted, a like removed or an accepted answer unmarked, the points
that action earned are taken back with a second, opposite ledger entry. The
history shows both rows, so a balance can always be explained.

### 8.2 Seeing your points

**Points** in the sidebar shows your balance, the current price list and your
own recent movements. It is read-only and shows nobody else's rows. Signed-out
visitors are asked to sign in.

### 8.3 Spending points

Points are spent in the download centre, on resources that carry a price.
Unlocking is permanent for that account. Points are not transferable between
members; the one exception is a bounty, which moves points to whoever writes the
accepted answer.

## 9. Bounties (高分悬赏)

### 9.1 What a bounty is

A bounty is points a member sets aside on **their own topic** and pays, in full,
to whoever writes the answer they accept. It is a way to make a hard question
worth somebody's afternoon.

The points are **escrowed**, not merely promised: opening a bounty takes them off
your balance immediately, so they cannot be spent on a download while the offer
stands. The default limits are 50 to 5000 points per offer, and an offer stands
for 14 days before it expires; both limits and the number of days are site
settings.

Each topic can carry one standing bounty at a time. A bounty can only be opened
in a category that allows accepted answers, and the feature needs the points
system and the solved plugin to be enabled.

### 9.2 Opening and settling

A new topic can carry a bounty from the moment it is posted: the composer's
**Bounty** field holds the amount, and the offer opens as soon as the topic
exists. If the amount is more than your balance, the composer asks whether to
adjust it or to post without a bounty — a topic posted without one can still get
an offer afterwards. If the amount is above the forum's ceiling, the field says
so and waits for a smaller number.

To do it from an existing topic:

1. Open your own topic.
2. Choose **Set a bounty on this question**, enter an amount within the allowed
   range and submit. The points leave your balance at that moment.
3. When an answer is accepted, the full amount is paid to its author. Accepting
   the answer is the payment; there is no separate release step.
4. Un-accepting an answer afterwards does **not** take the points back. The
   answerer may already have spent them. An administrator can adjust the two
   accounts by hand if a mistake must be repaired.

Staff can accept an answer on the asker's behalf when necessary.

### 9.3 Withdrawing, expiry and deletion

- The asker can withdraw a standing offer; the points return immediately.
- If nobody answers before the deadline, a scheduled job closes the offer and
  refunds the points.
- Permanently deleting the topic closes the offer and refunds whatever is still
  standing. Moving a topic to the trash does not refund it; the offer stands
  until its deadline and disappears from the board while trashed.
- Switching bounties off stops new offers but still refunds the ones already
  standing.

### 9.4 The bounty board

**Bounties** in the sidebar lists the standing offers across the forum, richest
first, with the question, the amount and the time left. On the topic itself, a
banner shows the offer, who made it, and — for the asker — a way to withdraw it.
Once settled, the banner says what was paid and to whom.

## 10. MCP and the AI assistant

### 10.1 The MCP page

The Model Context Protocol (MCP) lets an AI assistant reach the forum's tools
and data. **MCP** in the community section opens a landing page with:

- the server endpoint, which is the site's own address followed by `/mcp`;
- a copy button;
- the three steps of connecting a client: add the endpoint, sign in and approve,
  then start asking;
- ready-made commands for Claude Code and Visual Studio Code, and a note for
  any other client that supports remote MCP over HTTP;
- a description of what an approved client can see.

An approved client acts as the account that approved it. It sees only the
categories, topics and posts that account can see, and it stops working when the
authorization is revoked. The site administrator manages the server and the
approved clients under **Admin → MCP**.

If the site has not enabled the MCP server, the page explains that and the
sidebar link is hidden.

### 10.2 The assistant

The robot button in the bottom-right corner opens the Ingenic assistant panel.
It explains what the assistant is for and leads into the AI bot's conversations.
A signed-out visitor is asked to sign in first and is returned to the assistant
afterwards.

The assistant answers from the forum and points to documentation when it can.
Answers are generated by AI; check anything important against the documentation.
The button only appears while the AI bot is enabled for the site.

## 11. Administrator guide

### 11.1 Where the screens are

Everything the plugin owns is under **Admin → Plugins → Ingenic**. Opening any
one of them draws the plugin's tab bar under the page heading —
**Documentation**, **Development boards**, **Permissions**, **Permission
matrix**, **Section permissions**, **Tag colours**, **Downloads**, **Official
files**, **Points** and **Site content** — so the screens can be reached by clicking a tab. The
admin sidebar's single **Ingenic** entry opens **Documentation** first. Each
screen also has its own address, which is what to bookmark or link to:

| Screen | Address | What it manages |
| --- | --- | --- |
| Documentation | `/admin/plugins/discourse-ingenic/documentation` | Series, chips, versions, pages |
| Development boards | `/admin/plugins/discourse-ingenic/boards` | Board and sample cards |
| Permissions | `/admin/plugins/discourse-ingenic/permissions` | Per-chip grants for documentation, downloads and boards |
| Permission matrix | `/admin/plugins/discourse-ingenic/group-permissions` | Which management screens a custom group may use |
| Section permissions | `/admin/plugins/discourse-ingenic/category-permissions` | Category × group posting and reading levels |
| Tag colours | `/admin/plugins/discourse-ingenic/tag-colours` | The colour family of each tag |
| Downloads | `/admin/plugins/discourse-ingenic/downloads` | Resources, applications, access, categories, download record |
| Official files | `/admin/plugins/discourse-ingenic/files` | SDK archives, PDFs and images: folders, uploads, previews, links |
| Points | `/admin/plugins/discourse-ingenic/points` | Rules, adjustments, balances, movements |
| Site content | `/admin/plugins/discourse-ingenic/site` | Home layout, home cards, promotions, external buttons, partner platforms, footer, standalone pages |

Scoped managers see the documentation, boards, downloads and file library they
were granted, at `/ingenic/manage`.
The application queue, access list, download record, points and site content
remain administrator-only. The Permissions, Permission matrix, Section
permissions and Tag colours screens are administrator-only as well, because
each of them decides who else may do something. The server enforces this;
hiding a button is not the boundary.

Before the first content is added, deploy the plugin and theme and run the
category seeding task — see [`DEPLOY.md`](../DEPLOY.md) and
[`docs/seeding.md`](seeding.md).

### 11.2 Documentation

1. **Create a series.** Give it a name, a slug and a locale picked from the
   list of languages this site actually serves. A series is one row in the
   product tree. The ✎ control edits the name, slug, locale and published
   state; an old row stored as `en` can be moved onto the site's language there,
   without deleting it and writing its content again. Rows below it that still
   carry the old language follow; one deliberately filed under another language
   is left alone.
2. **Add a chip under the series.** A chip must have a series as its parent;
   the admin screen and the database both refuse a chip without one.
3. **Add a version to the chip.** Give it a version slug (for example `1.1.0`),
   a label and an order. One version can be flagged **latest**.
4. **Add pages to the version.** Choose a type first: a **folder** only groups
   content and expands in the contents; an **article** has a Markdown body. The
   parent is picked from a list, so a parent that does not exist can no longer
   be silently dropped to the top level. The published switch decides what a
   reader sees.
5. **Order and edit** rows with the arrows and the ✎ control. Pages move within
   their parent only; version order decides what inherits from what, and page
   order decides the contents. The edit form covers a series/chip's name, slug,
   locale and published state, and a version's label, slug, locale, release date
   and deprecated flag. A row with children cannot be deleted; remove or move
   the children first.
6. **Override an inherited page** by choosing **Override in this version**; the
   page becomes editable in this version. **Restore inheritance** deletes the
   copy in this version and returns to the earlier source.

An article's body is written in Markdown with a toolbar above it: bold, italic,
heading, quote, list, code and link. Select text and press a tool to wrap it;
with nothing selected the tool inserts placeholder text already selected, so
typing replaces it. A selection that spans lines becomes a fenced code block
rather than inline code, and **Link** leaves the caret where the address goes.
Images enter the page three ways — the toolbar's image button, pasting into the
body, or dropping a file onto it. They are uploaded through Discourse's own
`/uploads.json` and inserted as `![name](upload://…)`, so the reader and the
preview resolve them exactly as they resolve images in a post; nothing extra
has to be configured. Saving stays disabled while an upload is running, and a
refused upload (wrong format or over the size limit) says why under the body.
Several images can be chosen or dropped at once; they are inserted one after
another, separated by a blank line.

A published page is visible to readers; an unpublished page is absent from the
tree and returns not-found when requested directly. Unpublishing a folder takes
its whole section down, articles below it included — it does not move them up to
the top level. A version with no page of its own simply inherits the pages of
the version before it.

The product tree is shared by three features, so build it before downloads or
boards: documentation uses it for the picker, downloads for the series/model
filters, and boards for each card's chip.

### 11.3 Downloads

The Downloads screen has up to five tabs:

- **Resources** — add and edit a card. Fields include name, catalogue (`chip`
  or `algorithm`), product, category, picture, access level, point cost, order
  and published. Saving the card opens its versions list, where each release
  has a label, description, platform, architecture, file upload or URL, file
  size, checksum, release date, order and published flag.

The picture is uploaded from the card form and cropped to 4:3 on the card; a
card without one shows a placeholder. Cards are horizontal — picture, selected
version's description, one **Download** button — and the version selector
changes the description and the file without changing the access rule. The
version form is where a release's description is written, so SDK 1.0 and SDK 1.1
can say different things under the same card.

Deleting a version removes the file it kept as well.
- **Applications** — the queue of access requests. Open one to read the
  applicant's developer information, add a note, then **Approve and grant** or
  **Decline**. An optional expiry can be set on the grant.
- **Access** — every live grant, per account and per resource, with the option
  to revoke it.
- **Categories** — the labels used by the resource-type filter. Retiring a label
  leaves its resources in the list, unfiled, so they can be reclassified one at
  a time.
- **Download record** — who downloaded what and when. Administrator-only,
  because it names accounts.

Uploading a file stores it under the configured download directory (outside the
web root) and computes its SHA-256. The file is streamed through the forum only
after the access check. If the configured storage directory is not writable,
the screen says so before an upload is attempted; set
`ingenic_download_storage_path` to a writable volume.

Large files are sent in eight-megabyte pieces rather than as one request, so an
SDK or firmware image of several gigabytes uploads past the web server's
request-size limit. The screen shows a percentage while the transfer runs. A
piece refused because the connection dropped is resumed from the byte the
server reports, not from the beginning; closing the form discards the pieces,
and a transfer abandoned for a day is removed by a scheduled cleanup. The
largest accepted file is 8 GB.

The three access levels are explained in section 6.2. The point price is
optional and is charged only when the file is actually released.

**Withdrawing a resource is not a delete.** Switching **Published** off stops
the download centre from offering the file; nothing else is removed. The row
stays in the Resources list with its description, links, stored file and
checksum, and the applications, grants and download record that refer to it
remain in their tabs, so an audit still reads correctly. Switch **Published**
back on to offer the file again, with the existing grants still in force.
Nothing in the downloads screen physically deletes a resource.

### 11.4 Official files

A library for the files the team hands out — SDK archives, official PDFs,
datasheets and images — separate from the download centre and from anything
members attach to posts. Open it from the **Official files** tab, or at
`/ingenic/manage/files` if you were given the `files` grant without being an
administrator.

The screen is a file browser over a directory on the server:

- **New folder** creates a real directory in the folder you are looking at.
  Paths are shown as breadcrumbs; click one to go back up.
- **Upload** accepts the extensions in `ingenic_file_manager_extensions`, one or
  many files at a time. Files go up one after another, each with its own
  progress bar; an archive of several gigabytes is sent in eight-megabyte pieces
  and resumed from the byte the server reports if a piece is lost.
- **Preview** opens images in the page and PDFs and text in a frame. Files the
  browser cannot show are still previewable through the same address — open it
  to let the browser decide.
- **Copy link** puts the absolute address on the clipboard, for pasting into a
  post, a documentation page or a download record.
- **Rename**, **Move** and **Delete** work on the row. A folder can be moved
  into another folder but not into itself or its own child; the picker does not
  offer those.

Things to know before the first upload:

- **The path is the address.** `/ingenic/files/<path>` is what a link says, so
  renaming or moving a file changes its link. A link already pasted elsewhere
  still points at the old path.
- **Images are public; everything else needs a session.** Image files are served
  to anyone who has the URL, because a picture in a post must load for a
  signed-out reader. Other types are served only to a signed-in account. The
  library is not a second access-control system: to restrict a file, put its
  link on a download record and choose the level there.
- **It does not touch post attachments.** Attachments members add while posting
  are stored by Discourse itself, separately.
- **Deleting is immediate.** There is no recycle bin. A file deleted here is
  gone from the server; the link stops working.

The grant is one screen, `files`, on the Permission matrix. There is no
per-folder grant: a group either works in the library or does not see it. A
member without the grant gets the forum's ordinary 404 at the address.

### 11.5 Development boards and samples

Add a card, then set:

- **Type** — development board or sample chip.
- **Chip** — a chip in the product tree. This files the card under its series,
  keeps the chip name in step with the documentation, and is what the Chip
  filter uses. A card whose chip is not in the tree yet can keep a typed name.
- **Application URL** and **Purchase URL** — each button is disabled when its
  link is empty. The board is not sold out just because a link is missing.
- **Sold out** — the switch that stamps the card and the dialog and disables
  both buttons. The links are kept for when the board is restocked.
- **Introduction**, **Details**, **Specifications** (one per line), **Image
  URL**, **Order** and **Published**. **Details** is Markdown and is what the
  dialog shows; links and images can be inserted there.

**Withdrawing a card is not a delete.** Switching **Published** off removes the
card from the public catalogue and leaves everything else in place: the row
with its text, specifications, image and both links is still in the Boards
list, and it can be published again at any time. Nothing in the boards screen
physically deletes a card.

### 11.6 Points

- **Rules** — edit what each action is worth, its label and order, and whether
  it is in use. Setting a value to zero or switching the rule off stops future
  awards without touching the ledger. There is no delete, because old entries
  refer to the rule.
- **Adjust one account** — choose a member, enter a positive or negative number
  and a reason. The adjustment is written into the ledger like any other
  movement.
- **Balances** — every account holding points and when it last moved.
- **Recent movements** — the last hundred entries, newest first. An award that
  was reversed appears twice.
- **Recompute every balance** — rebuilds the balance cache from the ledger.
  Run it after a restore or import, or if a number looks wrong.

Points can be switched off in the site settings. Existing balances and entries
are untouched, and an administrator's manual adjustment still works.

### 11.7 Permissions

Permissions come in two layers, and they answer different questions.

**What a group may manage.** The **Permission matrix** grants a whole
management screen to a custom group: documentation, development boards,
downloads, official files, points or site content. A tick means "every
product", not "this product". Automatic groups (staff, trust levels, everyone) are not listed: a
tick on `everyone` would hand a management screen to every visitor, which is
not a decision a checkbox should make by accident.

**Which chip a person looks after.** The **Permissions** screen is built around
the product tree. A chip can have three independent owners — its documentation,
its downloads and its development boards — because T33's documentation and
T33's SDK are often different people. Choose a series or a chip on the left,
then the tab for the job, then search for a member or a group by username, full
name or group name. A grant on a series is inherited by every chip under it; the
chip's tab shows those as inherited, and they are revoked on the series, where
they were given, rather than copied down. Grants on individual pages, boards and
downloads made before the tree existed are listed separately at the bottom and
can still be revoked.

Every create, read, update and delete is checked on the server, so a hidden
button is only presentation.

**Forum sections.** The **Section permissions** screen sets, for each category,
what each custom group may do there. The levels are Discourse's own and are not
three shades of one verb: **No grant**, **Can read**, **Can reply** (reply
without starting a topic) and **Can post** (start a topic and reply). A category
with no group rows at all is open to every group; a save that would leave a
category that had rows with none is refused, because that would quietly open it
to everyone. Automatic groups keep whatever they already have — the screen only
edits custom groups.

### 11.8 Tags and status

The **Tag colours** screen assigns each tag one of five colour families: sky for
general discussion, tech for platforms, tools and hardware, resolved for
answered questions, announcement for official notices, and hot for topics the
community liked. The families are fixed so the forum keeps one visual language,
while the tag list is the site's own — a tag created this morning appears on
the screen without a release. A tag with no assignment falls back to the family
its name suggests, and then to sky.

The vocabulary is a site policy, not a convention:

- Only administrators may create a tag; any signed-in account may choose an
  existing one while posting.
- **公告**, **已解决** and **高赞** belong to a tag group only staff may apply.
  Members see them and cannot add them.
- **已解决** follows discourse-solved's accepted answer. **高赞** is applied by
  a scheduled pass that counts likes across the topic's live posts and compares
  them with `ingenic_high_like_threshold` (20 by default); it adds the tag at
  the threshold and removes it when the count falls back, but never removes one
  a moderator applied by hand.
- Tags are not navigation: Discourse's Tags section is hidden from the sidebar,
  and the category badge on a topic remains the way into its section.

### 11.9 Site content

The **Site content** screen has seven tabs:

- **Home page** — the ordered list of blocks: block type, heading, width
  (automatic, full, main or side), row count, category or section list, and
  whether the "All categories" link is shown. Saving replaces the theme's default
  layout.
- **Home cards** — the cards under Popular sections. Name a category to borrow
  its address, colour, icon and topic count, or give a label, link, description,
  icon, image, colour and order of your own.
- **Promotions** — headline, corner label, description, button, background
  image, locale, show-from/show-until window, order and publication. A slot with
  no dates stays until it is unpublished.
- **External buttons** — the buttons drawn in the footer's "Find us" strip,
  beside the partner platforms: label, link, built-in icon or image, whether the
  name is drawn, external flag, order and visibility.
- **Partner platforms** — the footer's "Find us" strip. Each entry is a link or
  a QR code, with a label, image or QR picture, optional caption and order. The
  Chinese name and caption can be stored beside the English ones.
- **Footer columns** — headings and their links (label, address, external flag,
  order, visibility). Columns and links also take an optional Chinese heading or
  label.
- **Pages** — the standalone documents the footer links to: terms of service,
  privacy policy and the points rules ship with each language and can be edited
  here. A page has a title, a slug, Markdown body, order and publication. Its
  address is `/ingenic/pages/<slug>`, so a footer link can point at it with an
  ordinary link. Unpublishing one makes that address answer 404 rather than
  leaving a stale copy in place.

The three shipped pages are seeded in both languages by the plugin's migrations.
The footer links to them already; retitling a page does not break the link,
because the link names the slug and the slug is what the editor keeps stable.

The footer follows the language the forum is being read in: English text is
required, Chinese is optional, and anything without a Chinese spelling falls
back to English rather than disappearing. This is why both spellings live on
the same record — a translator fills in the Chinese fields, and nothing else on
the screen changes.

The home page block types are: section cards, promotions, announcements,
discussions, latest topics, hot topics, popular posts, recent activity from a
category, downloads, development boards, bounties and the weekly contributor
leaderboard.

### 11.10 Site settings

The settings that matter most are under **Admin → Settings** (search for
`ingenic`):

| Setting | Purpose |
| --- | --- |
| `ingenic_enabled` | Master switch for the extension |
| `ingenic_nav_items` | JSON list of sidebar entries: label, icon, target, group, order, visibility |
| `ingenic_homepage_blocks` | JSON list of home-page blocks (the Site content screen edits the same list) |
| `ingenic_docs_discussion_category` | Category used by "Discuss in forum" when a page has no linked topic |
| `ingenic_download_storage_path` | Where uploaded files are stored; must be outside `public/` |
| `ingenic_file_manager_path` | Where the official file library lives; must be outside `public/` |
| `ingenic_file_manager_extensions` | Extensions the library accepts |
| `ingenic_download_admin_email` | Address notified when an application is submitted |
| `ingenic_developer_form_fields` | Extra questions for the developer information form; the core questions are fixed |
| `ingenic_official_groups` | Groups whose members wear the official identity badge |
| `ingenic_points_enabled` | Turns earning and spending on or off without clearing balances |
| `ingenic_points_exclude_staff` | Whether staff are excluded from earning points (on by default) |
| `ingenic_bounties_enabled` | Turns new bounties on or off; standing offers still expire and refund |
| `ingenic_bounty_min_points` | Smallest allowed bounty (default 50) |
| `ingenic_bounty_max_points` | Largest allowed bounty (default 5000) |
| `ingenic_bounty_expiry_days` | Days before an unanswered bounty is refunded (default 14) |
| `ingenic_high_like_enabled` | Turns the automatic 高赞 pass on or off |
| `ingenic_high_like_threshold` | Likes across a topic's live posts that earn 高赞 (default 20) |

`ingenic_nav_items` is a JSON array. An entry looks like this:

```json
{
  "key": "docs",
  "label": "Online Documentation",
  "icon": "book",
  "href": "/ingenic/docs",
  "section": "resources",
  "position": 4,
  "enabled": true
}
```

`section` is `forum`, `resources` or `member`; `position` orders entries within
the group. Use `"category": "technical-discussions"` instead of `href` to point
at a Discourse category. An empty setting uses the theme's default list. A
configured list replaces the default wholesale.

### 11.11 Theme settings

Under **Admin → Customize → Themes → Ingenic Community → Settings**:

| Setting | Purpose |
| --- | --- |
| `ingenic_locales` | Languages offered by the header switcher, in order |
| `ingenic_sidebar_width` | Desktop sidebar width in pixels |
| `ingenic_sidebar_position` | Left or right |
| `ingenic_nav_order` | Ingenic navigation above or below Discourse's own sidebar sections |
| `ingenic_nav_title` | Heading over the developer-resources group |
| `ingenic_hero_title` | Optional headline above the home blocks |
| `ingenic_hero_subtitle` | Optional supporting line |

The language switcher also needs Discourse's `allow_user_locale` and
`set_locale_from_cookie` settings. The accent colour is the **Ingenic Light**
colour scheme, editable with Discourse's normal colour pickers.

### 11.12 Content languages

The languages offered in the management screens are the site's own: its
`default_locale`, plus every language in
`content_localization_supported_locales` when content localisation is on.
Content is filed under those exact codes — `en`, `zh_CN` — because they are
compared with the reader's interface language; `zh-CN` is not the same code and
will not match.

Pick a language at the top of a management screen before creating anything.
Products, versions, pages, boards, downloads, categories and site content
created while it is selected belong to that language. The other language is
built by switching the selector and creating its own rows; there is no
per-record language field and no cross-language fallback. A Chinese reader sees
the Chinese catalogue, and a product nobody has translated yet is simply absent
from it.

The theme's interface strings live in `locales/en.yml` and `locales/zh_CN.yml`;
adding another language means adding a file with the same keys. The header
switcher only offers languages listed in `ingenic_locales`.

### 11.13 Housekeeping

- Run `rake ingenic:doctor` after a restore or a category change; it reports
  missing forum sections.
- The plugin exports and imports its content through `ingenic:config` tasks
  described in `DEPLOY.md`; use them to move content between sites.
- A permanently deleted member leaves ledger entries, applications and grants
  behind with the account blanked; the screens say **deleted account**.
- A permanently deleted topic refunds any standing bounty before the topic row
  is removed.

## 12. Troubleshooting

| Symptom | Likely cause | What to do |
| --- | --- | --- |
| MCP link is missing from the sidebar | `mcp_server_enabled` is off | Enable it under Admin → Settings → MCP |
| Assistant button does not appear | `ai_bot_enabled` is off, or discourse-ai is not installed | Enable the AI bot; the button hides rather than linking nowhere |
| A download says "Sign in to download" | The resource needs an account at minimum | Sign in |
| A download asks for developer information every time | The profile did not save, or the site's form fields changed | Submit the form again; check the required fields |
| An application stays "Waiting for review" | Nobody has decided it, or the notification email address is empty | Check Admin → Downloads → Applications; set `ingenic_download_admin_email` |
| "Access was declined" | The team declined this application | Contact the team; a new application may be possible after the situation changes |
| "Needs N points" | The balance is below the resource price | Earn points by contributing, or ask the team |
| A bounty cannot be opened | Points or solved is off, the topic is not yours, the category does not allow accepted answers, or a bounty already stands | Check the category and the site settings |
| A documentation page cannot be edited | It is inherited from an earlier version | Choose **Override in this version**, or edit the source version |
| A page is missing from the reader | It is unpublished, or its parent is unpublished | Publish it in Admin → Documentation |
| Uploads fail | The download storage directory is not writable | Point `ingenic_download_storage_path` at a writable volume outside `public/` |
| The home page looks empty | The extension or theme is disabled, or no blocks are configured | Check `ingenic_enabled`, the default homepage setting and Site content → Home page |
| Content appears in the wrong language | The row was created under another language | Switch the language selector in the management screen and create the row there |

## 13. Repository and support

- Plugin: <https://github.com/aishangletaohua/discourse-ingenic-plugin>
- Theme: <https://github.com/aishangletaohua/discourse-ingenic-theme>
- Deployment: [`DEPLOY.md`](../DEPLOY.md) · [中文](../DEPLOY.zh-CN.md)
- Bulk seeding: [`docs/seeding.md`](seeding.md) · [中文](seeding.zh-CN.md)

For account, content or access problems, contact the Ingenic community team
through the forum's **Site Feedback** category or the address the team
publishes on the site.
