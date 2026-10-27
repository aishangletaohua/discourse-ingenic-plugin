# AI 助手与 MCP 开发者资源工具：使用说明

这份说明把两个容易混淆的功能放在一起：论坛里和人对话的 **AI 助手**，以及让外部 AI 客户端读取开发者资源的 **MCP 工具**。它们是两套开关、两类使用对象。

- 管理员：看第一部分，以及 2.1–2.2，确定开什么、在哪里开。
- 对接方（内部工具、合作方的智能体、客服机器人）：从 2.3 开始，可以直接转交。

参考细节在 `usage.zh-CN.md` 第 10 节；本文是可照着做的操作步骤。

---

## 第一部分——Forum Helper，论坛自带的助手

### 1.1 它是什么

Forum Helper 是论坛里负责回答问题的 AI 机器人。会员通过右下角的机器人按钮进入，落到 `/discourse-ai/ai-bot/conversations`。它是 **系统智能体**：提示词和工具列表由 Discourse AI 写在代码里，不在数据库里，因此 Discourse AI 的「智能体」编辑器既看不到它，也保存不了对它的修改。

它可以被关掉的地方有两处，互相独立：

| 开关 | 控制什么 | 值存在哪里 |
| --- | --- | --- |
| 允许 Forum Helper 回答问题 | 智能体本身是否可用 | `AiAgent` 记录的 `enabled` |
| 开发者专区知识 | 它能否检索在线文档、SDK 下载和开发板 | 站点设置 `ingenic_assistant_search_enabled` |

### 1.2 在哪里看状态

**后台 → 插件 → Ingenic → 设置**，页面底部的区块。

三行状态：

- **助手状态**——智能体名称，以及是否开启。关闭表示它不再回答。
- **AI 机器人功能**——站点级 `ai_bot_enabled`。这里只读，要在 **后台 → 设置 → AI** 修改。它若关闭，任何人都看不到机器人按钮，与本页的状态无关。
- **开发者专区知识**——「已接入」表示开关打开**且**插件的检索工具已加载进智能体；「未接入」表示助手只从论坛作答。

未安装 discourse-ai 时，区块会直接说明，不显示开关——没有可配置的东西。

### 1.3 关掉助手本身

取消勾选 **允许 Forum Helper 回答问题**，状态行变为「已关闭」，页面提示「已保存」。

立即发生的变化：

- Forum Helper 不再回答，新会话背后没有智能体。
- 不删除任何东西，提示词、工具和历史都保留。
- 机器人按钮跟随的是 **AI 机器人功能** 那一行，不是这个开关。那一项开着，按钮就还在，只是没有智能体来回答。

适用场景：助手在故障期间答得不对；或开发者专区正在调整，不希望它引用只发布了一半的内容。要恢复，重新勾选即可，不需要重启，也不需要迁移。

### 1.4 不让助手读开发者专区

取消勾选 **允许 Forum Helper 检索在线文档、SDK 下载和开发板**，知识一行变为「未接入」。

变化：

- 插件的 `search_ingenic` 工具从 Forum Helper 的工具列表中移除。助手保留自己的工具——论坛搜索、读帖、版块——继续回答论坛内的问题。
- 它看不到在线文档、SDK 与固件目录、开发板，因此不会引用，也不会编造页面链接。
- 这**不影响**第二部分的 MCP 工具。那些是另一套注册，有自己的范围；外部客户端仍持有其所在组被授予的权限。

适用场景：文档正在大改；或某个产品线的答案还不可靠，但希望助手继续处理普通论坛问题。

### 1.5 什么情况用哪个开关

| 情况 | 助手 | 开发者专区知识 |
| --- | --- | --- |
| 助手不可用或回答失准 | 关 | 保持原样 |
| 文档在大规模重写 | 保持开 | 关 |
| 某个产品线暂不允许引用 | 保持开 | 关 |
| 站点在评估是否保留助手 | 关 | 保持原样 |
| 未安装 discourse-ai | — | —（区块会说明） |

### 1.6 前提

- 已安装并启用 discourse-ai，且 AI 机器人功能已打开。
- Discourse AI 里配置了模型；没有模型时，即使两个开关都打开，助手也答不了。
- 开发者专区知识还需要插件在启动时加载它的工具。如果开关是开的而状态显示「未接入」，说明工具没有加载——确认插件已启用并重启应用。

---

## 第二部分——通过 MCP 读取开发者资源

### 2.1 一个工具一个范围

五个只读工具，各有一个范围。它们都不写数据，也读不到帖子、私信或站点设置。

| 工具 | 范围 | 读取内容 |
| --- | --- | --- |
| `ingenic_search` | `mcp:developer-centre:search` | 三个目录一起检索，统一排序 |
| `ingenic_list_documentation` | `mcp:developer-centre:documentation` | 产品树；某个型号的版本与目录 |
| `ingenic_read_documentation_page` | `mcp:developer-centre:documentation-page` | 单页 Markdown 正文，以及前后页 |
| `ingenic_list_downloads` | `mcp:developer-centre:downloads` | SDK 与固件卡片，含发布信息、访问级别、大小 |
| `ingenic_list_boards` | `mcp:developer-centre:boards` | 开发板与样片卡片，含规格和链接 |

范围分开的好处是：可以只给在线文档、不给 SDK 目录，也可以只给开发板。它们共用 `mcp:developer-centre:` 前缀，在授权页面上排在一起。

授权对象是**用户组**，不是某个账号。组里的成员都有这些工具；离开组的人在他下一次授权时失去它们。

### 2.2 管理员配置

四步，按顺序做。

**1. 打开服务器。** **后台 → 设置 → MCP** → `mcp_server_enabled`。未打开之前，侧边栏的 MCP 页面是隐藏的。

**2. 启用工具。** **后台 → MCP → Capabilities**，勾选五个 Ingenic 工具并保存。只注册、未启用的工具对所有客户端都不可见，授权再多也没用。

**3. 授予范围。** **后台 → MCP → Access** → **Add group access**（或对已有行点 **Edit**）→ 勾选该组需要的开发者资源范围 → **Save access**。

选择器列的是用户组，不是个人。有两个组没有成员记录，因此不会出现：**everyone** 和 **logged_in_users**。如果想让所有已登录会员都能用，授权给 `trust_level_0`（它包含他们），或者自己维护一个自定义组。

**4. 确认。** Access 页面会列出该组以及可逐个移除的范围标签。标签里没有的范围，就是没有授予——Capabilities 页面的勾选不代表已授权。

三种常见的授权组合：

| 对象 | 范围 | 效果 |
| --- | --- | --- |
| 只读文档的人 | `:documentation`、`:documentation-page`、`:search` | 浏览并阅读页面；搜索也会返回下载和开发板，但没有对应的工具 |
| 评估 SDK 的合作方 | `:downloads` | 只有 SDK 目录和访问级别，没有文档 |
| 销售或客服 | `:boards`、`:search` | 开发板卡片，以及在其可见范围内的全站搜索 |

关于 `:search`：它检索站点已发布的内容并返回摘要，因此只持有 `:search` 的组，仍然能知道某个下载存在、是做什么的。请按实际需要一并授予，不要把它当成无副作用的小赠品。

### 2.3 交给对接方

交给对方三样东西：端点、他们所在组被授予的范围，以及这一节。

**端点。** 论坛自己的地址加 `/mcp`，例如 `https://forum.example.com/mcp`。没有插件专用的端点。

**连接方式。** 侧边栏的 MCP 页面有复制按钮和现成的命令，最常用的两条：

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

任何支持远程 MCP over HTTP 的客户端都一样。第一次连接时客户端会打开浏览器，由本人**以自己的账号**登录并确认，确认页会列出客户端申请的范围。授权就是这样产生的——管理员不能替别人批准。

**一次会话的流程。** 客户端用 JSON-RPC over HTTP 加 Bearer 令牌。必须先调 `initialize`，并带上 `MCP-Protocol-Version` 请求头；服务器返回协商后的版本，之后的每次调用都用那个版本。访问令牌默认 60 分钟、刷新令牌默认 30 天（`mcp_access_token_lifetime_minutes`、`mcp_refresh_token_lifetime_days`），由客户端自行处理。

**客户端能看到什么。** 它以授权人的身份行事：能看到该账号能看的版块和帖子，以及其所在组被授予的开发者资源工具。授权被撤销或账号被停用时，立即失效。

### 2.4 手工检查连接

客户端报「工具列表为空」时用得上。把令牌替换成客户端的访问令牌。

```bash
TOKEN=...   # 客户端的访问令牌
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

返回里的 `result.protocolVersion` 就是协商结果，之后的请求头用它。然后：

```bash
curl -s "$URL" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "MCP-Protocol-Version: 2025-11-25" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
```

`result.tools` 就是这个令牌能调用的全部工具。一个 Ingenic 工具，说明只授予了一个范围；五个就是五个。

调用：

```bash
curl -s "$URL" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "MCP-Protocol-Version: 2025-11-25" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{
        "name":"ingenic_search","arguments":{"query":"T33"}}}'
```

结果在 `result.structuredContent`，`result.content[0].text` 是同样的 JSON 文本。出错有两种：`result.isError`（工具拒绝执行）和 JSON-RPC `error`（服务器拒绝请求）。

### 2.5 工具与参数

| 工具 | 参数 | 说明 |
| --- | --- | --- |
| `ingenic_search` | `query`（至少 2 个字符）、`scope`（`all`、`documentation`、`downloads`、`boards`）、`limit`、`locale` | 按相关度排序，每条带可打开的地址 |
| `ingenic_list_documentation` | `series`、`chip`、`version`、`locale` | 不传参数返回整棵产品树；传 `chip` 返回该型号的版本与目录 |
| `ingenic_read_documentation_page` | `chip`、`page`、`series`、`version`、`locale` | `chip` 与 `page` 用列表里的 slug；`version` 可填 slug 或 `latest` |
| `ingenic_list_downloads` | `locale` | 只有卡片和访问级别，绝不含文件地址 |
| `ingenic_list_boards` | `locale` | 卡片、规格、申请与购买链接 |

`locale` 取 `en` 或 `zh_CN`；不传则跟随授权账号的语言。slug 就是页面地址里的那几段：`/ingenic/docs/t-series/t33/1.0/getting-started` 对应系列 `t-series`、型号 `t33`、版本 `1.0`、页面 `getting-started`。

工具遵循公开页面的规则：未发布的系列、型号、版本、页面和下载不会出现；已撤下的目录连同其文章一起消失；从旧版本继承的页面，按当前展示它的版本读取。下载只以卡片形式返回访问规则，集成方无法绕过下载中心的登录、资料或审批。

### 2.6 权限变更何时生效

| 变更 | 怎么让它生效 |
| --- | --- |
| 给组增加范围 | 编辑该组的授权，勾选并保存。成员重新确认客户端（或拿到新令牌）后，工具出现。 |
| 从组里去掉范围 | 编辑并取消勾选。已签发的令牌在过期或被刷新之前仍持有签发时的范围，所以要立即生效，还要在 **后台 → MCP → Authorizations** 撤销该客户端。 |
| 把某人移出组 | 同上：授权按组，移除的生效方式一样。 |
| 彻底停掉一个客户端 | **后台 → MCP → Authorizations** → 撤销。它的令牌立即失效。 |
| 对所有人关掉某个工具 | **后台 → MCP → Capabilities** 取消勾选。任何范围授权都覆盖不了。 |

被撤销的授权无法刷新，本人必须重新确认一次。

### 2.7 安全说明

- 匿名客户端无法连接。令牌永远属于某个人，客户端能读到的就是这个人能读到的。
- 开发者资源的范围不是 `mcp:content:read`。能读文档的集成，仍然读不到帖子。
- 下载卡片会透露资源存在、需要哪些访问条件，但绝不透露文件地址。
- 每次调用都记录在 **后台 → MCP → Activity**，范围变更记入管理操作日志。

---

## 第三部分——排查

| 现象 | 可能原因 | 处理 |
| --- | --- | --- |
| 设置区块显示助手不可用 | 未安装 discourse-ai | 安装并启用后刷新 |
| 开关是开的，知识却显示「未接入」 | 插件启动时没有加载工具 | 确认插件已启用，重启应用 |
| 助手只答论坛，不引用文档 | 知识开关关闭，或工具未加载 | 打开开关；确认状态为「已接入」 |
| 助手完全不回答 | 智能体关闭、AI 机器人功能关闭，或没有配置模型 | 三项都查；第一项在 Ingenic 设置页 |
| 客户端列不出任何 Ingenic 工具 | 服务器未开、工具未启用，或没有授权范围 | 按 2.2 的第 1–3 步处理，再 `tools/list` |
| 调用工具返回 `Insufficient scope` | 令牌缺少该工具的范围 | 给组授予该范围，然后让客户端重新确认 |
| 授权后工具仍不出现 | 客户端缓存了工具列表 | 重连客户端，或再调一次 `tools/list` |
| `Unsupported protocol version` | 缺少请求头，或与协商版本不一致 | 用 `initialize` 返回的值填 `MCP-Protocol-Version` |
| 无法给「所有人」授权 | `everyone` 与 `logged_in_users` 没有成员记录 | 授权给 `trust_level_0` 或自定义组 |
| 工具返回 unknown chip / unknown page | slug 不一致 | 先用 `ingenic_list_documentation` 查，再读 |
