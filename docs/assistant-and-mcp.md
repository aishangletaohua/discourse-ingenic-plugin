# Using the AI assistant and the MCP developer-centre tools

Two features share this guide because they are often confused: the **AI
assistant** people talk to on the forum, and the **MCP tools** that let an
outside AI client read the developer centre. They are separate switches with
separate audiences.

- Administrators: Part 1 and Part 2.1–2.2 tell you what to turn on and where.
- Whoever owns the integration (an internal tool, a partner's agent, a support
  bot): Part 2.3 onward is the handover.

The reference material lives in `usage.md` §10. This file is the walkthrough.

---

## Part 1 — Forum Helper, the forum's own assistant

### 1.1 What it is

Forum Helper is the AI bot that answers from the forum. Members reach it
through the robot button in the bottom-right corner, which opens
`/discourse-ai/ai-bot/conversations`. It is a **system agent**: Discourse AI
builds its prompt and tool list from code, not from the database, so the AI
agent editor can neither show it nor save changes to it.

Two things about it can be switched, and they are independent:

| Switch | What it controls | Where the value lives |
| --- | --- | --- |
| Let Forum Helper answer | Whether the agent exists to answer at all | The `AiAgent` record's `enabled` flag |
| Developer-centre knowledge | Whether it can read the documentation, downloads and boards | Site setting `ingenic_assistant_search_enabled` |

### 1.2 Seeing its state

**Admin → Plugins → Ingenic → Settings**, the block at the bottom of the page.

It reports three rows:

- **Assistant** — the agent's name and whether it is on. Off means it will not
  answer.
- **AI bot feature** — the site-wide `ai_bot_enabled` setting. This one is
  read-only here; it is changed under **Admin → Settings → AI**. If it is off
  there, the robot button does not appear for anyone, whatever this page says.
- **Developer-centre knowledge** — *Attached* means the switch is on **and** the
  plugin's search tool is loaded into the agent. *Not attached* means the
  assistant answers from the forum only.

If the site has no discourse-ai, the block says so and shows no switches —
there is nothing to configure.

### 1.3 Turning the assistant off

Untick **Let Forum Helper answer**. The status row turns to *Off* and the page
says *Saved.*

What changes immediately:

- Forum Helper stops answering. A new conversation has no agent behind it.
- Nothing is deleted. Its prompt, tools and history are untouched.
- The robot button still follows the **AI bot feature** row, not this one. If
  that setting is on, the button is still there; the assistant simply has no
  agent to answer with.

Use it when the assistant is giving bad answers during an incident, or while
the developer centre is being restructured and you do not want half-published
content quoted. Re-tick the box to restore it; there is no restart and no
migration.

### 1.4 Taking the developer centre away from the assistant

Untick **Let Forum Helper read the documentation, downloads and boards**. The
knowledge row turns to *Not attached*.

What changes:

- The plugin's `search_ingenic` tool is removed from Forum Helper's tool list.
  The assistant keeps its own tools — forum search, topic reading, categories —
  and goes on answering about the forum.
- It can no longer see the online documentation, the SDK and firmware catalogue
  or the development boards, so it will not cite them and will not invent page
  links.
- This does **not** touch the MCP tools in Part 2. Those are separate
  registrations with their own scopes; an outside client keeps whatever its
  group was granted.

Use it when the documentation is being rewritten, or when the assistant's
answers about a product line are not yet trustworthy, while leaving the
assistant useful for ordinary forum questions.

### 1.5 Which switch for which situation

| Situation | Assistant | Knowledge |
| --- | --- | --- |
| Assistant unusable or misbehaving | off | leave as is |
| Documentation under a large rewrite | leave on | off |
| A product line must not be quoted yet | leave on | off |
| Site evaluating whether the assistant is wanted at all | off | leave as is |
| discourse-ai not installed | — | — (block reports it) |

### 1.6 Requirements

- discourse-ai installed and enabled, with the AI bot feature on.
- A model configured in Discourse AI; without one the agent cannot answer even
  when both switches are on.
- The developer-centre knowledge additionally needs the plugin's tool to load,
  which it does at boot. If the row says *Not attached* with the switch on, the
  plugin has not loaded its tool — check that the plugin is enabled and restart
  the app.

---

## Part 2 — The developer centre over MCP

### 2.1 One tool, one scope

Five read-only tools, each with a scope of its own. Nothing here writes, and
nothing here can read posts, private messages or site settings.

| Tool | Scope | Reads |
| --- | --- | --- |
| `ingenic_search` | `mcp:developer-centre:search` | All three catalogues, ranked together |
| `ingenic_list_documentation` | `mcp:developer-centre:documentation` | The product tree; one chip's versions and table of contents |
| `ingenic_read_documentation_page` | `mcp:developer-centre:documentation-page` | One page as Markdown, with the pages either side |
| `ingenic_list_downloads` | `mcp:developer-centre:downloads` | SDK and firmware cards, with release, access rule and size |
| `ingenic_list_boards` | `mcp:developer-centre:boards` | Board and sample cards, with specifications and links |

Because the scopes are separate, a group can be given the documentation
without the SDK catalogue, or the boards without anything else. The scopes
share the `mcp:developer-centre:` prefix so they sit together in the access
screen.

A grant names a **group**, never an account. Everyone in the group has the
tools; someone who leaves the group loses them at their next authorization.

### 2.2 Administrator setup

Four steps, in this order.

**1. Turn the server on.** **Admin → Settings → MCP** → `mcp_server_enabled`.
The sidebar's MCP page stays hidden until this is on.

**2. Enable the tools.** **Admin → MCP → Capabilities**. Find the five Ingenic
tools, tick them, save. A tool that is registered but not enabled is invisible
to every client, however generously you grant scopes.

**3. Grant the scopes.** **Admin → MCP → Access** → **Add group access** (or
**Edit** on an existing row) → tick the developer-centre scopes the group
needs → **Save access**.

The chooser lists groups, not people. Two groups have no membership rows and
therefore do not appear: **everyone** and **logged_in_users**. To open a tool to
every signed-in member, grant it to `trust_level_0`, which contains them (or to
a custom group you maintain).

**4. Confirm.** The Access page lists the group with the scopes as removable
chips. If a scope is missing there, it is not granted, whatever the Capabilities
page says.

Three grant patterns that cover most requests:

| Who | Scopes | Effect |
| --- | --- | --- |
| Documentation readers | `:documentation`, `:documentation-page`, `:search` | Browse and read pages; search also returns downloads and boards, without their tools |
| A partner evaluating an SDK | `:downloads` | The SDK catalogue and access rules, no documentation |
| Sales or support | `:boards`, `:search` | Board cards and search across everything they are allowed to see |

Note on `:search`: it searches the catalogues the site publishes, and returns
excerpts, so a group holding only `:search` still learns that a download exists
and what it is for. Grant `:search` together with the scopes you intend, not as
a harmless extra.

### 2.3 Handing over to the integration owner

Give them three things: the endpoint, the scopes their group was granted, and
this section.

**Endpoint.** The forum's own address followed by `/mcp`, for example
`https://forum.example.com/mcp`. There is no plugin-specific endpoint.

**Connecting.** The MCP page in the sidebar shows a copy button and ready-made
commands. The two common ones:

```bash
claude mcp add --transport http ingenic-forum https://forum.example.com/mcp
```

```json
{
  "servers": {
    "ingenic-forum": {
      "type": "http",
      "url": "https://forum.example.com/mcp"
    }
  }
}
```

Any client that supports remote MCP over HTTP works the same way. On the first
connection the client opens a browser; the person approves **as their own
account** and sees exactly which scopes the client asked for. Approving is what
creates the grant — an administrator cannot approve on someone else's behalf.

**How a session goes.** The client sends JSON-RPC over HTTP with a Bearer
token. It must call `initialize` first, sending an `MCP-Protocol-Version`
header; the server answers with the version it negotiated, and every later call
uses that version. Access tokens last 60 minutes and refresh tokens 30 days by
default (`mcp_access_token_lifetime_minutes`,
`mcp_refresh_token_lifetime_days`); the client handles both.

**What the client sees.** It acts as the account that approved it. It sees the
categories and topics that account can see, and the developer-centre tools its
group was granted. It stops working when the authorization is revoked or the
account is suspended.

### 2.4 Checking a connection by hand

Useful when a client reports an empty tool list. Replace the token.

```bash
TOKEN=...   # the client's access token
URL=https://forum.example.com/mcp

curl -s "$URL" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "MCP-Protocol-Version: 2026-07-28" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{
        "protocolVersion":"2026-07-28","capabilities":{},
        "clientInfo":{"name":"check","version":"1"}}}'
```

The reply carries `result.protocolVersion` — use that value in the header from
now on. Then:

```bash
curl -s "$URL" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "MCP-Protocol-Version: 2025-11-25" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
```

`result.tools` lists exactly the tools this token may call. One Ingenic tool
means one scope was granted; five means five.

A call:

```bash
curl -s "$URL" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "MCP-Protocol-Version: 2025-11-25" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{
        "name":"ingenic_search","arguments":{"query":"T33"}}}'
```

The answer is JSON in `result.structuredContent`, with the same text in
`result.content[0].text`. Errors come back as `result.isError` (a tool said no)
or a JSON-RPC `error` (the server said no).

### 2.5 The tools, with arguments

| Tool | Arguments | Notes |
| --- | --- | --- |
| `ingenic_search` | `query` (2+ characters), `scope` (`all`, `documentation`, `downloads`, `boards`), `limit`, `locale` | Ranked, each result carrying the address a person would open |
| `ingenic_list_documentation` | `series`, `chip`, `version`, `locale` | No arguments: the whole product tree. `chip`: that chip's versions and table of contents |
| `ingenic_read_documentation_page` | `chip`, `page`, `series`, `version`, `locale` | `chip` and `page` are slugs from the listing; `version` accepts a slug or `latest` |
| `ingenic_list_downloads` | `locale` | Cards and access rules — never the file address |
| `ingenic_list_boards` | `locale` | Cards, specifications, apply and buy links |

`locale` is `en` or `zh_CN`; omitted, it follows the approving account's
language. Slugs are the ones in the page URLs: `/ingenic/docs/t-series/t33/1.0/getting-started`
gives series `t-series`, chip `t33`, version `1.0`, page `getting-started`.

The tools apply the public rules: unpublished series, chips, versions, pages and
downloads are absent; a withdrawn folder takes its articles with it; a page
inherited from an older version is read at the version currently showing it.
Downloads are returned as cards with their access rule, so an integration
cannot skip the sign-in, developer information or approval the download centre
asks for.

### 2.6 When access changes

| Change | How to make it take effect |
| --- | --- |
| Add a scope to a group | Edit the group's access, tick it, save. The member re-approves the client (or a new token is issued) and the tool appears. |
| Remove a scope from a group | Edit and untick. Tokens already issued keep the scopes they were issued with until they expire or are refreshed, so also revoke the client under **Admin → MCP → Authorizations** when the change is urgent. |
| Remove a person from a group | Same as above: the grant is by group, so removal takes effect the same way. |
| Stop one client entirely | **Admin → MCP → Authorizations** → revoke. Its tokens stop working immediately. |
| Turn a tool off for everyone | **Admin → MCP → Capabilities** → untick. No scope grant overrides it. |

A revoked authorization cannot be refreshed: the person has to approve again.

### 2.7 Security notes

- Anonymous clients cannot connect. A token always belongs to a person, and the
  client can read exactly what that person can.
- The developer-centre scopes are not `mcp:content:read`. An integration allowed
  to read the documentation still cannot read posts.
- Download cards reveal that a resource exists and what it costs in access
  steps; they never reveal a file address.
- Every call is visible under **Admin → MCP → Activity**, and scope changes are
  recorded in the staff action log.

---

## Part 3 — Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| The Settings block says the assistant is unavailable | discourse-ai is not installed | Install and enable it, then reload |
| Knowledge says *Not attached* although the switch is on | The plugin did not load its tool at boot | Confirm the plugin is enabled and restart the app |
| Assistant answers about the forum but never cites documentation | Knowledge switch is off, or the tool did not load | Turn it on; check the row says *Attached* |
| Assistant does not answer at all | Agent off, or the AI bot feature off, or no model configured | Check all three; the first is on the Ingenic Settings page |
| Client lists no Ingenic tools | Server off, tools not enabled, or no scope granted | Steps 1–3 in §2.2; then `tools/list` again |
| Client calls a tool and gets `Insufficient scope` | The token lacks that tool's scope | Grant it to the group, then re-approve the client |
| Tool missing after a grant | The client cached the tool list | Reconnect the client, or call `tools/list` again |
| `Unsupported protocol version` | The header is missing or does not match the negotiated version | Send `MCP-Protocol-Version` with the value `initialize` returned |
| A scope cannot be granted to *everyone* | `everyone` and `logged_in_users` have no membership rows | Grant to `trust_level_0` or a custom group |
| The tool returns "unknown chip" or "unknown page" | Slug mismatch | List first (`ingenic_list_documentation`), then read |
