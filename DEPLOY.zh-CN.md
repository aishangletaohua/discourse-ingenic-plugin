# Ingenic 社区主题和插件部署说明

本项目包含两个独立的仓库，需要分别安装：

| 仓库 | 作用 | 安装方式 |
|---|---|---|
| [`discourse-ingenic-plugin`](https://github.com/aishangletaohua/discourse-ingenic-plugin) | Rails 插件：在线文档、下载中心、开发板、站点设置 | 克隆到 `plugins/` 后重建 Discourse |
| [`discourse-ingenic-theme`](https://github.com/aishangletaohua/discourse-ingenic-theme) | 主题：布局、导航、首页、文档界面、MCP 页面、AI 助手 | 从 Git 地址安装主题，不需要重建 |

本项目不会修改登录认证。Google、GitHub 和邮箱登录仍然按照当前
Discourse 的配置运行。

目标版本：Discourse `2026.10.0-latest`。主题和插件均按照这个版本的源代码开发
并完成了静态校验。

---

## 1. 安装插件

### 方式 A：从 Git 仓库安装（推荐）

在 `containers/app.yml` 中增加：

```yaml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          - git clone --branch develop https://github.com/aishangletaohua/discourse-ingenic-plugin.git discourse-ingenic
```

以后升级插件时，在重建前先拉取：

```yaml
hooks:
  after_code:
    - exec:
        cd: $home/plugins/discourse-ingenic
        cmd:
          - git pull --ff-only
```

### 方式 B：直接复制文件

在本地执行：

```bash
scp -r discourse-ingenic <用户名>@<服务器>:/tmp/discourse-ingenic
```

然后在服务器上执行：

```bash
sudo mv /tmp/discourse-ingenic /var/discourse/plugins/discourse-ingenic
```

这里的 `<用户名>`、`<服务器>` 由部署人员在服务器上自行填写，不需要发给我。

### 重建 Discourse

```bash
cd /var/discourse
./launcher rebuild app
```

重建时会执行插件迁移并创建 19 张 `ingenic_*` 数据表。通常需要几分钟，
重建期间论坛会暂时无法访问。`discourse_docker` 的普通 rebuild 不提供零停机。

这里必须用 **rebuild**，不能只重启容器：这次新增了首页控制器和路由，
而 Discourse 只在启动时读取插件的文件。只更新主题是另一种情况——
上传主题 zip 完全不需要重建。

进入容器确认插件已加载：

```bash
./launcher enter app
rails c
SiteSetting.ingenic_enabled          # 应为 true
IngenicDocProduct.count              # 尚未录入内容时应为 0
```

接着应用本论坛固定的站点默认值：

```bash
rake ingenic:setup
```

任务会逐条打印改了什么，第二次运行不会做任何改动：

- `title` 改为 **Ingenic**：浏览器标题显示 Ingenic，而不是默认的 “Discourse”。
- 上传 **Ingenic 字标** 并设为 `logo`、`logo_small`、`mobile_logo`。页头显示的是
  上传的 logo 而不是站点标题，而 Discourse 默认已经上传了自己的字标，所以只改
  `title` 的话左上角仍然是 Discourse 的图标。图片位于
  `discourse-ingenic/assets/images/ingenic-logo.png`。
- `enable_powered_by_discourse` 关闭：页面底部不再出现 “Powered by Discourse”。
  主题样式也会隐藏该元素，即使某次部署漏配了设置也不会露出来。
- `default_homepage` 改为 **ingenic-home**：`/` 是 Ingenic 首页（见下文「首页」）。
  原生 latest 列表仍在 `/latest` 和侧边栏中。
- 写入页脚默认内容：两个合作平台（ingenic.com 与中文论坛）和两个链接栏目
  （Developers、Community）。主题在页脚列表为空时整块不显示，所以新装站点需要
  这些初始内容。只在两个列表都为空时写入，已经自行配置过合作方的站点不会被覆盖。

之后 `rake ingenic:doctor` 会连同语言、版块和存储设置一起检查。

---

## 2. 安装主题

主题有独立仓库：
<https://github.com/aishangletaohua/discourse-ingenic-theme>。

进入：

**管理后台 → 自定义 → 主题 → 安装 → 从 Git 仓库安装**

填写：

```text
https://github.com/aishangletaohua/discourse-ingenic-theme.git
```

分支填 `develop`。两个仓库在两次发布之间都只在 `main` 上保留一行说明，因此不指定
分支的安装不能依赖它。

这样安装后，主题更新只需要在 **管理后台 → 自定义 → 主题 → 检查更新**，
不需要重建，也不需要重新上传文件。如果服务器访问不了 GitHub，也可以在
“From your device（从设备安装）”里上传仓库打出的 zip 包。

然后：

1. 打开主题并选择 **Ingenic Light** 配色方案。强调色在这个配色方案中，
   可以使用 Discourse 标准颜色选择器修改；没有单独的颜色设置。
   配色方案内置的是天空淡蓝色：强调色 `#2FC1FF`、正文 `#12263a`、
   顶栏 `#f2f9fd`、高亮 `#cfe8fb`。如果顶栏是灰色而不是淡蓝，
   说明主题仍在用站点原有配色方案，这一步没做。

   这个强调色是刻意调淡的，因此它是"面"而不是"字"。主题自己处理了这个
   问题：链接和按钮文字用的是同色系中更深一档的颜色（见主题 README 的
   **Colours** 一节）。如果你把强调色改深，主题照样能用，只是链接颜色
   会比它需要的更深。
2. 可以直接把它设置为网站默认主题，也可以先作为可选主题，确认效果后再切换。

这是完整主题，不是组件，因此不需要另外安装组件。

---

## 3. 安装后的设置

### 插件站点设置

在管理后台的插件设置中配置：

| 设置 | 建议值 |
|---|---|
| `ingenic_enabled` | 开启 |
| `ingenic_default_locale` | 文档主要使用的语言 |
| `ingenic_docs_discussion_category` | 文档讨论所属分类的 slug |
| `ingenic_download_storage_path` | 大容量卷上的目录，必须位于 `public/` 之外；留空则使用 `<app>/ingenic-downloads` |
| `ingenic_download_admin_email` | 接收下载申请通知的邮箱 |
| `ingenic_developer_form_fields` | JSON 配置；留空则使用内置的开发者信息表单 |
| `ingenic_official_groups` | 需要显示官方认证图标的群组名称，例如 `admins` |
| `ingenic_points_enabled` | 开启；如果还没准备好上线可以关闭 |
| `ingenic_points_exclude_staff` | 开启 |
| `ingenic_bounties_enabled` | 开启；在允许成员挂悬赏之后再打开 |
| `ingenic_bounty_min_points` | 10 |
| `ingenic_bounty_max_points` | 1000 |
| `ingenic_bounty_expiry_days` | 14 |

`ingenic_download_storage_path` 决定上传的 SDK 和固件存放在哪里。这个目录必须
放在 `public/` 之外：如果文件能被 Web 服务器直接访问，任何猜到地址的人都能下载，
插件再怎么做权限判断也没有意义，因此文件统一由插件转发。下载量增长后可以把
这个路径指向更大的数据盘。

`ingenic_download_admin_email` 是收到下载申请时发信的目标地址。留空时申请记录
仍然会写入并在后台申请列表中显示，只是不会发出邮件通知。

`ingenic_developer_form_fields` 用于替换内置的开发者信息表单，格式为 JSON 数组，
每一项包含 `key`、`label`、`type`、`required`，其中 `type` 取值为 `text` 或
`textarea`：

```json
[
  { "key": "full_name", "label": "Full name", "type": "text", "required": true },
  { "key": "use_case",  "label": "Intended use", "type": "textarea", "required": true }
]
```

访客看到的表单、提交时的必填校验、后台查看答案的展示都来自这一份配置，因此三者
不会互相不一致。留空则使用内置字段。如果之后从配置中删除某个字段，已经填写的
答案会保留而不会被清空。

内置表单和上面的示例都不会询问手机号。账号本身已经有可用于联系的邮箱，而团队
不会去看的字段只会让开发者更容易放弃填写表单。

`ingenic_official_groups` 用于指定哪些群组的成员会在用户名旁显示官方认证图标。
每行填一个群组名称，写法与该群组自己的页面一致；大小写和多余空格不影响结果。
图标本身就是 Discourse 的群组 flair，可以在群组设置中上传图片或选择图标，这个
设置只决定"谁佩戴"。已经自己选择了其他图标的成员会保留自己的选择，也可以之后
在个人偏好页面自行切换到官方图标。填写多个群组相当于约定优先级：排在前面的群组
优先。图标还没准备好时也可以先填写这个设置——已列出但尚未配置 flair 的群组不会
授予任何图标，等到图片上传后图标会自动出现。

`ingenic_points_enabled` 是整个积分系统的总开关。关闭后，论坛不再发放积分，
标了价的资源对所有已获准的账号都免费。它不会清空流水账：已有的流水和余额原样保留，
重新打开后从当前状态继续累计。关闭期间，管理员手工调整积分仍然可用——那是"有人
有意为之"，与"论坛自动决定"是两件事。

`ingenic_points_exclude_staff` 决定管理员和版主是否参与积分。默认开启（即不参与），
理由是：在这里回答问题属于站务人员的本职工作，而不是他们的社区贡献；而且一个社区
里没人能登顶的排行榜意义不大。试用这个功能时需要注意：用版主账号发帖测试会
"什么都看不到"。这个设置不阻止站务人员"给出"积分——版主点的赞，对被点赞的作者
仍然照常计分。

两个设置都可以随时修改。把 `ingenic_points_exclude_staff` 关掉不会追溯补发站务
人员之前发过的帖子，只对之后的帖子生效。

`ingenic_bounties_enabled` 允许成员在自己的主题上挂出积分悬赏，采纳答案后全额
支付给答主。它依赖积分系统和已解决插件，两者任一关闭时它也会自动关闭——悬赏本质
是积分在流动，而结算依据是已解决插件的那个 ✓。关闭它只会停止接受新的悬赏，已经
挂出的悬赏仍会到期并退回：这是有意为之，一个用来"停止新悬赏"的开关不应该把已经
托管的积分卡死。

`ingenic_bounty_min_points` 和 `ingenic_bounty_max_points` 是成员可以挂出的积分
区间。`ingenic_bounty_expiry_days` 是悬赏的挂出天数，到期后自动结束并把积分退回
给挂出悬赏的成员——要让"回答"这件事比悬赏本身更快。没有按版块区分的设置：悬赏
属于主题，主题归属哪个版块只是附带信息。

开启前需要知道的一点：积分是**托管**的。成员挂出 500 积分的悬赏后，在悬赏结束
之前他就少了 500 积分可用于下载解锁。这是机制本身而不是副作用——正是它挡住了
"同一个人把同样的 500 积分挂在十个问题上"——但也是第一次使用时最容易让人意外的
地方。

`ingenic_nav_items` 和 `ingenic_homepage_blocks` 都是 JSON 配置，可选填。
如果 `ingenic_nav_items` 留空，主题会使用自带的默认导航 —— 与下面的 JSON 完全
相同的三块、相同的顺序。

**一旦配置了 `ingenic_nav_items`，它会整体替换主题自带的列表**，而不是与之合并。
因此在悬赏功能上线之前就已经配置过导航的站点，不会有"高分悬赏"入口，也不会自动
多出一个：需要自己在 JSON 里补上，或者清空这个设置、以上面的列表为起点重新配置。

导航分为三块，用 `section` 指定某一项属于哪一块：

| `section` | 呈现方式 | 内容 |
| --- | --- | --- |
| `forum` | 最上方的一段列表，不带标题 | 发帖入口、首页、论坛自己的版块 |
| `resources` | 带独立标题的一组 | 开发者页面、对应的论坛版块和 MCP |
| `member` | 会员块中的行，排在话题下面，不带标题 | 会员自己的悬赏与积分 |

中间那块的标题取自主题设置 `ingenic_nav_title`，默认是 **Developer Resources**
（中文界面显示"开发者资源"）。上面的论坛块和下面的会员块刻意不带标题：给主题
列表加标题等于给论坛贴标签，而给"高分悬赏 / 积分"加标题会把它们并到上面的开发者
资源里去。会员块本身就是 Discourse 的社区分区，话题和"更多"由核心提供；主题在
话题上面补站点反馈，在话题下面补高分悬赏、积分和全部分类。

`position` 决定**块内**的先后顺序；三块本身永远按上表的顺序出现。`section`
写了不存在的分组名时，这一项会被当作 `forum`，而不是被丢掉 —— 写错分组只会让
一行换位置，不会让一行消失。站点反馈和全部分类不可配置：它们是论坛里的位置，
会员块始终带着它们。

一个可直接修改的 `ingenic_nav_items` 示例：

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

**New Post**（新帖子）指向 `/new-topic`，这是 Discourse 自带的发帖路由：在当前
页面直接打开编辑器；未登录的访客会被先引导去登录。

使用 `category` 的导航项会在服务端解析成该分类的真实地址（`/c/<slug>/<id>`），
因此可以把导航指向论坛分类，而不必自己查分类 id、也不必直接填写 URL ——
Discourse 的分类地址必须带 id，只写 `/c/<slug>` 会 404。每个芯片产品可以设置
自己的论坛分类和对应的 `/ingenic/docs/<product>` 文档入口。

### 导航指向的论坛版块

上面那份列表里有三个 slug 指的是论坛分类，而全新的 Discourse 一个都没有 ——
`category` 项指向不存在的分类，点进去是一个"页面不存在"，而侧边栏其他部分看着
一切正常。所以由插件负责创建，连同它们下面的整棵树：

```bash
./launcher enter app
rake ingenic:seed_categories
```

| 分类 | 上级 | 谁可以发帖 |
| --- | --- | --- |
| 官方公告（`official-announcements`） | — | 站务组 |
| 技术讨论（`technical-discussions`） | — | 所有人 |
| 开源版块（`open-source`） | — | 无人：它只是容器 |
| 三方开源（`third-party`） | `open-source` | 所有人 |
| 官方开源（`official`） | `open-source` | 只有管理员 |
| T 系列（`t-series`） | `technical-discussions` | 无人：它只是容器 |
| T33（`t33`）、T32Pro（`t32pro`）、T41（`t41`） | `t-series` | 所有人 |
| C 系列（`c-series`） | `technical-discussions` | 无人：它只是容器 |
| CW020（`cw020`）、CW080（`cw080`） | `c-series` | 所有人 |
| X 系列（`x-series`） | `technical-discussions` | 无人：它只是容器 |
| X2600（`x2600`） | `x-series` | 所有人 |
| MCU 系列（`mcu-series`） | `technical-discussions` | 无人：它只是容器 |
| G32S10（`g32s10`） | `mcu-series` | 所有人 |

技术讨论就是侧边栏那一行打开的地方；鼠标停上去，面板里是各系列，鼠标再停在
某个系列上，该系列下的型号在旁边的第二个面板里展开。开源版块是导航里紧挨着它
下面的那一行 —— 自己是顶层的一个版块，不是技术讨论面板里的一行 —— 悬停面板里
是它的两个子版块：放自己的开源项目，还是看君正官方的开源发布。技术讨论这棵树
有三层，所以任务在创建之前会把
`max_category_nesting` 设为 3 —— Discourse 默认的 2 会拒绝型号这一层，而这个
设置不在后台界面上。

"只有管理员"就是 Discourse 普通的分类权限：编辑该分类，在 **Security（安全）**
里给 `everyone` 只保留 *See（查看）*、不勾 *Create / Reply（发帖/回复）*，再把
*Create / Reply* 给 `admins`。

每个分类还带一个中文名和中文简介，所以中文界面的首页卡片显示的是 `技术讨论`，
而不是 `Technical Discussions`，下面那段说明也是中文。只有开启内容本地化、并把
`zh_CN` 列入支持语言之后，Discourse 才会读取分类的翻译，所以首次建分类前先打开
两者：

```ruby
SiteSetting.content_localization_enabled = true
SiteSetting.content_localization_supported_locales = "zh_CN"
```

如果分类是在这两个设置打开之前建的，再跑一次 `rake ingenic:seed_categories`。
它会为已有的行补上缺失的 `locale`、中文名和中文简介，其他一律不动；跑两次也
不会多出第二条翻译。本地化关闭时不会写入翻译行，因为写了也没有地方读。

这个任务只创建缺失的分类，其余保留论坛现状 —— 建好之后改名、换颜色都随你，再跑
一次不会把它们改回去。归属是这张表唯一决定的事：slug 在表里、上级却不是表里
写的那个，就会被改挂过去，因为树就是这张表的形状。所以早先版本放到技术讨论下面
的开源版块会被挪回顶层，而不是变成第二个开源版块。另一个会在被要求时重新写回的，
是上面这张表里的权限：

```bash
rake ingenic:seed_categories[permissions]
```

`rake ingenic:doctor` 同样会列出缺失的分类（以及插件和主题需要的其他设置）。

`ingenic_homepage_blocks` 配置 Ingenic 首页（`/` 和 `/ingenic/home`）。它可以在
**管理后台 → 插件 → Ingenic → 站点内容 → 首页** 中编辑：新增、删除、上下移动区块，
并逐块设置标题、宽度和显示数量。站点设置里保存的是同一份列表的 JSON，便于导出，
也便于一次性写入。

留空时首页使用下面的默认布局：

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

已经保存过自定义首页布局的站点不需要手动添加新卡片：升级插件时，数据库迁移会把
`leaderboard` 补到列表末尾，并把右侧四个卡片调整为「活动位 → 热门 → 悬赏 → 每周贡献」
的顺序；其他区块的位置不动。留空（默认值）的站点始终跟随上面的默认布局。

可用类型：`categories`（版块卡片，并带「全部分类」入口）、`latest`（最新讨论）、
`hot`（本周热门）、`bounties`（积分最高的进行中悬赏）、`promotions`（在
**Ingenic → 站点内容 → 推广位** 中维护的活动位）、`leaderboard`（本周获得积分的
成员排行）、`announcements` 与 `discussions`
（各读取一个分类下的主题）、`downloads`、`boards`。没有内容的区块不显示——活动位在
没有活动时、悬赏在没有悬赏时都不会留下空面板。`layout` 取 `full`、`main` 或
`side`；留空则按该类型的默认宽度。

`categories` 加
`"categories": ["official-announcements", "technical-discussions"]` 可以指定显示哪些
版块及其顺序；不加则按主题数取最活跃的一级版块，数量由 `limit` 决定。
`"show_all": false` 会去掉标题末尾的 **全部分类** 链接。

### 首页

首页是 Ingenic 自己的页面，注册名为 **ingenic-home**：欢迎语与搜索框、热门分区卡片、
最新讨论、右侧的活动与热门主题栏、合作平台与页脚分区跳转，以及底部的 高分悬赏。
整体形状参照 meta.discourse.org，内容与区块都可以按上一节增删改。

| 设置 | 取值 | 作用 |
|---|---|---|
| `default_homepage` | `ingenic-home`（实际存储值为 `ingenic-home`） | 让 `/` 成为 Ingenic 首页 |

在 **管理后台 → 设置 → 界面** 中设置，或用命令行：

```bash
./launcher enter app
rails c
SiteSetting.default_homepage = "ingenic-home"
```

`rake ingenic:setup` 会连同站点名称、字标和 powered-by 开关一起设置。只有
`ingenic_enabled` 开启时这个选项才会出现在列表里；如果站点选中过它、之后又关掉了
插件，站点会回落到普通首页，而不是报错。

原生 latest 列表仍在侧边栏和 `/latest` 中。


### 界面语言

界面语言是 Discourse 自带的能力，所以下面三项是核心设置，不是插件设置。它们决定
页头的语言切换器能不能用：

| 设置 | 取值 | 原因 |
|---|---|---|
| `default_locale` | `en` | 首次访问的访客看到的语言 |
| `allow_user_locale` | 开（默认已经是开） | 关闭后任何人都不能选择语言，切换器会自动隐藏 |
| `set_locale_from_cookie` | 开 | 未登录访客的选择保存在 cookie 里；这一项关闭时 Discourse 不会回读该 cookie，表现就是"点了没反应" |

切换器位于页头最右侧——未登录时在 **登录** 按钮左边，已登录时在头像左边——提供的
语言来自主题设置 `ingenic_locales`，默认为 `en|zh_CN`。每一项都用该语言自己的写法
显示，所以看不懂当前界面语言的访客也能找到自己要选的那一项。

Discourse 把语言记在两个地方，切换器写的是当前生效的那一个：已登录账号使用账号自己
的语言偏好（在个人偏好设置里也能改），未登录访客则读 cookie。已登录的访客不会读
cookie——这是 Discourse 的规则，不是插件的行为。

### 页面底部

在主题自己的页脚（第三方平台区与链接列，在 **Ingenic → 站点内容** 中配置）下面，
Discourse 还会画一行自己的内容：**由 Discourse 提供技术支持**，它出现在大多数页面的
最底部。隐藏它只需要改一项核心设置，不需要动主题：

| 设置 | 取值 | 原因 |
|---|---|---|
| `enable_powered_by_discourse` | 关闭 | 去掉 **由 Discourse 提供技术支持** 这一行，页面就结束在本站自己的页脚 |

位置在 **管理后台 → 设置 → 站点管理员**，也可以在设置页直接搜索 `powered by`
（搜索框匹配的是设置项名称与英文说明，中文界面下也建议用 `powered by`）。主题自己的
页脚是另一回事——它由 **Ingenic → 站点内容** 配置，不受这一项影响。

### 主题设置

| 设置 | 默认值 | 作用 |
|---|---:|---|
| `ingenic_locales` | `en\|zh_CN` | 页头切换器提供的语言；少于两项时切换器不显示 |
| `ingenic_sidebar_width` | 272 | 桌面端侧边栏宽度，单位为像素 |
| `ingenic_sidebar_position` | `left` | 侧边栏位置，可改为 `right` |
| `ingenic_nav_order` | `first` | Ingenic 导航位于 Discourse 原生区段之前或之后 |
| `ingenic_nav_title` | 空 | 导航上方的可选标题；留空时显示无标题列表 |
| `ingenic_hero_title` | 空 | 首页模块上方的可选标题 |
| `ingenic_hero_subtitle` | 空 | 首页标题下方的可选说明 |

### MCP 与 AI 助手

这两项都是 Discourse 自带的功能，主题只是把它们呈现出来，因此都不是插件设置。

| 设置 | 值 | 作用 |
|---|---|---|
| `mcp_server_enabled` | 开 | 提供 `/mcp`，并在侧边栏的论坛条目与 **更多** 之间显示 **MCP**。关闭时该入口隐藏，`/ingenic/mcp` 会说明服务尚未启用 |
| `ai_bot_enabled` | 开 | 在右下角显示悬浮助手。它来自 `discourse-ai` 插件；关闭时主题不显示启动按钮 |

**MCP** 在 **管理后台 → 设置 → MCP** 开启；已授权的客户端、开放的
工具和服务运行情况在 **管理后台 → MCP** 管理。主题的 `/ingenic/mcp`
页面是给开发者看的说明：要填进客户端的服务地址、接入的三步流程，以及 Claude
Code 和 VS Code 的现成配置。服务本身在 `/mcp`，只接受 `POST`，`GET` 会返回
`405`，所以面向人的页面放在插件自己的路径下，而不是替换它。

**AI 助手** 是 `discourse-ai` 的机器人。右下角按钮打开一个简短面板，并进入
`/discourse-ai/ai-bot/conversations`；未登录读者看到的是登录链接，登录后回到该
页面。没有安装 `discourse-ai` 时，按钮不会出现。

---

## 4. 录入内容

在线文档、下载资源、开发板、积分、范围权限和站点首页内容都可以直接在 Discourse 管理后台维护，不必每次进入 Rails 控制台。进入 **管理后台 → 插件 → Ingenic**，这里有六个标签页。管理员可以看到全部六个标签页；版主，以及只被授予某个产品或某块开发板范围权限的账号，只会看到该权限覆盖的两个页面（Documentation 和 Development boards），其余四个页面在服务端就限定为管理员，不给入口好过给一个点进去会被拒绝的链接。另外，Discourse 自己的“插件”页面仅限站务人员访问，因此打开这些页面的实际操作者是管理员或版主。

**Documentation（在线文档）**：管理产品树（系列 → 型号）、每个产品的版本，以及某个版本下的页面树。在某个版本中编辑过的页面，可以在之后的版本中选择覆盖；没有覆盖的页面会从上一个版本继承，因此新建版本相当于自动沿用上一版的内容，不需要手工复制。编辑器会标明当前页面来自哪个版本，并提供 **Override in this version**（在本版本中覆盖）和 **Restore inheritance**（恢复继承）。

读者端的版本下拉框列出该型号的全部版本，按 `position` 排序，并标出被标记为 `latest`
的那一个。切换版本会改写地址 `/ingenic/docs/<系列>/<型号>/<版本>/<页面>`；目标版本
有该页面（自己的记录或继承来的）时停留在原页面。尚未建版本的型号会明确显示"该型号
的文档尚未编写"，而不是一个空阅读器；不带路径的 `/ingenic/docs` 会落在第一个真正
有文档的型号上。

后台界面目前只有英文语言包，中文界面下会回退显示英文，上面的按钮名称即为实际显示的文字。

**Downloads（下载中心）**：内部还有五个标签页。*Resources* 是资源目录，维护名称、产品、版本、平台、分类、文件（上传或外部链接）、发布日期和访问级别。*Applications* 是需要审核的申请队列，显示申请人填写的开发者信息，可以批准或驳回。*Access* 是当前持有下载授权的账号，可以撤销。*Download record* 是"谁在什么时候下载了什么"的记录。*Categories* 是可增删改的资源分类列表，可以新增、改名、调整顺序和停用。

**Boards（开发板）**：维护开发板卡片，包括图片、芯片、简介、规格、文档链接和 **Buy now（立即购买）** 链接。

**Permissions（权限）**：文档的范围权限。授予 T 系列后，该用户可以管理 T 系列下的版本和页面；只授予 T33 时，不能管理 T32 或 T 系列父级。授权对象可以是用户或群组。服务端会对所有新增、修改、删除请求再次校验，前端隐藏按钮不是权限边界。

**Points（积分）**：成员通过贡献获得的积分，以及下载资源可以标价消耗的积分。同一个页面分四块。*What earns points* 是价目表：每个动作值多少分、在成员记录里显示成什么名称、显示顺序，以及论坛是否还发放它。*Adjust one account* 手工调整某个账号的积分，按用户名挑选，填写的备注会成为流水记录上的原因。*Repair the balances* 依据流水重新计算所有余额，用于两者对不上的情况——流水是记录，余额只是它的缓存。*Recent movements* 是最近一百条流水，上方的 *Balances* 列出当前谁持有多少积分。

这个页面**连查看也是仅限管理员**的，不只是修改：流水账里会出现账号名，而一次调整会改变某个成员在站内的状态。产品或开发板的范围权限到不了这里——积分余额不属于任何产品或开发板。

**Site（站点内容）**：站点中属于"内容"而不是"论坛"的部分，分六个标签页。*Home page* 是首页布局：决定首页绘制哪些区块、顺序，以及每个区块的标题、宽度和显示数量。区块在这里新增、用箭头上下移动、删除或就地编辑，整份列表一次保存。*Home cards* 是"热门分区"下面的卡片：填写分类即可沿用该分类的地址、颜色、图标和主题数，也可以只填链接——在线文档的卡片就是这样来的，不必为它凭空建一个分类。*Promotions* 是首页的活动推广位，每项包含图片、标题和跳转地址。*External buttons* 是 Logo 旁边和页脚“关注我们”一栏的按钮：每项有名称、内置图标或图片地址、跳转地址，也可以只显示图标。*Partner platforms* 是页脚的第三方平台区，每一项可以是跳转链接，也可以是二维码图片——网页类平台用链接，App 类平台用二维码让访客扫码；也可以只显示图标。*Footer columns* 是页脚链接列与页面底部的分区跳转链接，列数不限，每列有自己的标题和按顺序排列的链接。

### 下载访问级别

每个资源属于三个级别之一。判断在文件接口上执行，而不是在页面上执行，因此按钮和文件本身不会出现不一致。

| 级别 | 访客需要先完成什么 |
|---|---|
| `public_login` | 登录 |
| `login_form` | 登录，并已填写开发者信息 |
| `login_form_request` | 登录、已填写开发者信息，并且申请已通过审核 |

开发者信息只需要填写一次，之后所有受限资源共用，不是每个文件填一次。审核通过后授权长期有效（授权记录没有到期时间），所以"谁下载过"以日志为准，而不是以授权记录为准。访客没有被放行的资源不会在页面上出现任何直链，列表只给出插件接口地址，由接口决定是否放行。

### 资源标价

在访问级别之上，资源还可以带一个**积分价格**，在 **Ingenic → Downloads → Resources** 的同一个表单里设置。默认值 0，表示免费。

价格是在访问级别**之后**才询问的，而不是替代它：一个标价 500 分、级别为 `login_form_request` 的资源，对于新访客仍然是先登录、先填开发者信息、先通过审核，然后才会提到积分。没有被放行的账号，出多少分都买不到。

购买记录是一条流水，而不是在别处新增一个字段，这正是它具备幂等性的原因：买过之后，无论下载多少次都不会重复扣分；即使之后余额被花到 0，这次购买依然算数。积分足够时列表显示 **Unlock for N points**，不够时显示 **Needs N points**，所以按钮不会给出接口会拒绝的承诺。

扣分只发生在文件接口中**真正把文件发出去**的那个分支，绝不会发生在"报告资源不可用"的分支——所以一个从存储里找不到的文件不会扣任何积分。

积分通过贡献获得：发起讨论、回帖、帖子被点赞、回答被采纳。这四个动作也各自有对应的事件，在帖子被删除、点赞被取消、采纳被撤销时把积分收回来。成员在 **`/ingenic/points`** 可以看到自己的余额、价目表和自己的变动记录；这个页面在前端是只读的——积分靠贡献获得、靠下载消耗，这两件事都不通过这个地址发生。未登录的访客也能看到价目表，所以这个页面对他们是一个回答，而不是一扇锁着的门。

积分是插件功能，页面入口由主题提供。主题自带一个"积分"入口；如果站点已经配置了自己的 `ingenic_nav_items`，需要自己补上这一项。

### 删除成员

在 **管理后台 → 用户** 里删除账号，对一个已经在论坛里活动过的成员同样可以完成。以前不是这样：只要该成员挣过积分、申请过下载或挂过悬赏，就有外键指着他的账号不放，而插件没有任何地方在监听删除事件——于是后台给出的是一句数据库报错。现在插件对 `users` 的引用分成两种：**置空**（行保留，账号一栏清空）和**级联删除**（这一行说的是这个人，而不是论坛）。

| 数据表 | 成员被删除后这些行的去向 |
| --- | --- |
| `ingenic_point_entries` | 保留，账号置空——台账必须仍然能对得上 |
| `ingenic_bounties` | 保留，账号置空；已结算的悬赏留在原帖上 |
| `ingenic_download_requests` | 保留，账号置空——申请和给它的答复就是这次决定的记录 |
| `ingenic_download_grants` | 保留，账号置空——它不再放任何人进来，但仍说明这里曾经授权过 |
| `ingenic_developer_profiles` | 删除——这是关于某个人的资料，不是关于论坛的 |
| `ingenic_point_balances` | 删除——没人持有的余额缓存，可以从台账重算 |
| `ingenic_permissions` | 删除——授权对象（账号或用户组）已经不存在 |
| `ingenic_download_logs` | 删除（原本就是这样） |

删除成员之前，有两件事值得知道：

- 挂出悬赏的成员被删除后，悬赏在有人被采纳答案时照付，到期也照样结束并退回积分。如果到期时挂出者已经不在了，这笔退款没有账号可以落，会记在"无账号"名下——托管时是从一个账号扣走的，而现在没有账号可以收回来。台账会把它记下来，而不是丢掉。
- 已被删除账号的申请无法通过审核：没有账号可以持有这份权限。队列里该行的名字位置显示 **账号已删除**，点通过会给出原因说明；拒绝仍然可用。台账和授权列表里用的是同一个称呼。

### 删除主题

即使主题上挂有 **高分悬赏**（进行中的或已结算的），主题也可以被永久删除。以前不行：`ingenic_bounties.topic_id` 是一条普通外键，数据库会拒绝删除挂过悬赏的主题——包括很早以前就结算过的悬赏，因为已结算的悬赏按设计留在原帖上，作为"这个答案值多少"的记录。而且这个拒绝造成的后果比"删不掉"更糟：`PostDestroyer` 会先逐个删除主题下的回复（每一条各自一个事务、各自提交），最后才销毁主题本身，于是报错发生在最后一步，留下的是一个回复全没了、主题却还在的半残主题，配上一句什么也没解释的错误页。

现在外键改为级联，插件在行的消失之前把积分退回去：

| 主题上的悬赏 | 主题被删除时的处理 |
| --- | --- |
| 进行中 | 在主题消失前关闭，积分退回提问者 |
| 已结算 | 随主题一起消失；被支付的一方保留已得的积分 |
| 没有 | 无需处理 |

这笔退款和台账里其他记录一样，所以提问者的积分记录里会写明 **悬赏所在主题已删除，积分退回**，余额恢复原样。它与删除在同一个事务内完成：主题、悬赏行、以及关闭它们的那笔账目，要么全部成立，要么都不发生。

两点需要注意：

- **请通过界面、rake 任务或 `destroy` / `destroy_all` 删除主题。** 在控制台执行 `Topic.where(...).delete_all` 不会触发任何回调：级联会把悬赏行直接删掉而不退款，积分就凭空消失了，台账里没有任何记录可以解释它。把整个插件关掉（`ingenic_enabled`）也会如此——关闭状态的插件不会注册回调——所以"关掉整个插件"是唯一可能让成员损失托管积分的操作。只关掉 `ingenic_bounties_enabled` 不会：悬赏照常退款。把主题移入回收站不算删除——悬赏继续有效，悬赏榜不再展示它，到期后按正常流程结束并退款。
- 删除主题会引起积分变动，所以提问者的台账里会写明原因，但不会记录**是谁**删的——`before_destroy` 回调不会被告诉是哪个管理员执行的操作，写上一个名字就只是猜测。**管理后台 → 日志 → 员工操作** 里记录了这件事。

插件目录中的 `docs/seeding.md` 包含四类内容（文档、下载、开发板、积分）的完整录入示例，适合首次导入和批量初始化。中文版见 `docs/seeding.zh-CN.md`，两份内容一致，交给实际执行录入的人用中文那份即可。

进入 Rails 控制台：

```bash
cd /var/discourse
./launcher enter app
rails c
```

然后按照 `docs/seeding.md`（或中文版 `docs/seeding.zh-CN.md`）创建产品、版本和文档页面。

在至少创建一个已发布产品前，访问 `/ingenic/docs` 显示“文档不可用”是正常的，
不是部署错误。

### 语言代码注意事项

内容记录中的语言代码必须使用 Discourse 的格式：

```text
正确：zh_CN、pt_BR
错误：zh-CN、pt-BR
```

访问者的界面语言优先匹配；如果某个页面没有对应翻译，则使用
`ingenic_default_locale`。因此可以先翻译一部分页面，不需要一次性完成全部内容。
同一个页面 slug 在目录中只显示一次，不会因为存在中英文两条记录而重复显示。

### 哪些能在后台改，哪些固定在代码里

站点上的东西分两类，改的地方不一样。分清这两类，部署之后的调整就是改设置，而不是重新发版。

**内容与外观，在管理后台改，不需要部署：**

| 改什么 | 在哪里 |
|---|---|
| 站点 Logo（桌面、小尺寸、移动端）、favicon、大图标 | **管理后台 → 设置 → 品牌**（`logo`、`logo_small`、`mobile_logo`、`favicon`、`large_icon`） |
| 首页区块——增删、排序、标题、宽度、显示数量 | **Ingenic → 站点内容 → 首页** |
| 「热门分区」下的卡片，包括指向在线文档的那张 | **Ingenic → 站点内容 → 首页卡片** |
| 外链按钮——名称、图标或图片、跳转、是否只显示图标 | **Ingenic → 站点内容 → 外链按钮** |
| 推广位的图片、标题、按钮和跳转 | **Ingenic → 站点内容 → 推广位** |
| 合作平台的图标或二维码、名称、跳转、是否只显示图标 | **Ingenic → 站点内容 → 合作平台** |
| 页脚链接栏目，以及每个页面右下方的板块跳转 | **Ingenic → 站点内容 → 页脚栏目** |
| 开发板图片、规格、文档链接、购买链接 | **Ingenic → 开发板** |
| SDK 与固件文件、下载权限、积分价格 | **Ingenic → 下载中心** |
| 文档的系列、型号、版本、页面 | **Ingenic → 文档** |
| 侧边栏条目、名称和跳转 | 插件设置 `ingenic_nav_items`（JSON；留空用自带列表） |
| 首页标题与副标题 | 主题设置 `ingenic_hero_title` / `ingenic_hero_subtitle` |
| 侧边栏宽度、左右、顺序、标题；可切换的语言 | 主题设置 |
| 下载存储路径、申请邮箱、开发者表单、积分规则、悬赏上限 | 插件站点设置 |

关于图片，有三点需要知道：

- 插件里带的 `assets/images/ingenic-logo.png` 是**测试用占位图**，是我自己画的，不是君正的品牌文件。请到「品牌」里换成正式 Logo。`rake ingenic:setup` 只在 Logo 为空时填入，不会覆盖你上传的正式 Logo。
- favicon 必须是正方形。把 `assets/images/ingenic-favicon.png`（512 × 512）**同时**上传到 `favicon` 和 `large_icon`。横版字标不能放这里：Discourse 会从中间裁成正方形，标签页里只剩一小段笔画。`large_icon` 是手机主屏图标和安装版应用图标的来源。
- 推广位、合作平台、外链按钮、首页卡片、开发板里的图片填的是 **URL**，不是上传。先把图片上传到论坛（或放到 CDN），再把地址粘贴进去。只有 Logo 和 favicon 是直接上传。

**固定在代码里，改这些等于改代码、需要重新部署：**

- 配色、字体、间距和天蓝色主题（主题 SCSS）。
- 尚未创建任何卡片时首页绘制的三张默认卡片：技术讨论、在线文档、官方公告。
- 渲染器认识的九种区块类型和三种宽度（整行、主栏、侧栏）。不认识的类型会被拒绝，不会只画一半。
- 界面文案及其中英文翻译。
- 侧边栏的图标和三个块（论坛 / 开发者资源 / 会员块）。
- 占位 Logo 文件本身。

---

## 5. 部署后验证

请逐项打开并检查：

- [ ] `/` 显示 Ingenic 首页：标题、搜索、版块卡片和讨论列表；论坛原生的主题列表在 `/latest`
- [ ] 页面左上角显示 **Ingenic**，页面底部没有 “Powered by Discourse”
- [ ] 顶部语言切换器显示 **EN** 和 **中文**，每种语言用其自身的语言命名
- [ ] `/ingenic/docs` 打开第一个真正有文档的型号，并将地址替换为该型号的规范地址
- [ ] 系列 → 型号两级选择器正常联动，选中系列后型号列表随之收窄
- [ ] 文档目录树正常显示，上一页 / 下一页按顺序切换
- [ ] 版本选择器列出该型号的全部版本，并标出 latest；切换版本后，目标版本有同名页面（自己的或继承来的）时停留在该页面
- [ ] 在新版本中未编辑的页面显示的是上一版本的内容，编辑器标明该页面来自哪个版本
- [ ] `/ingenic/downloads` 可以按系列、型号、分类、版本、平台筛选
- [ ] `public_login` 资源登录后即可下载；`login_form_request` 资源会先要求提交申请
- [ ] 在后台批准申请后，该账号可以下载，且 **Ingenic → Downloads → Download record** 中能看到该账号
- [ ] 普通成员发帖后余额发生变化，**Ingenic → Points → Recent movements** 中能看到这条流水
- [ ] 删除该帖后积分被收回，且原来那条奖励记录仍然留在流水账中，与收回记录并列可见
- [ ] 给某个资源设置了积分价格后，余额足够的账号看到 **Unlock for N points**，不足的看到 **Needs N points**
- [ ] 购买时扣一次分；同一个资源第二次下载不再扣分
- [ ] `/ingenic/points` 向已登录成员显示自己的余额、价目表和自己的变动记录，且看不到别人的
- [ ] 管理员手工调整某个账号后余额随之变化，填写的备注成为该条流水的原因
- [ ] 删除一个测试成员（该成员有积分、有申请或挂过悬赏）时不会出现数据库报错，且他的流水仍然留在 **Ingenic → Points → Recent movements** 中，名字位置显示 **账号已删除**
- [ ] 永久删除一个挂有进行中悬赏的测试主题可以正常完成，提问者的余额恢复原样，**Ingenic → Points → Recent movements** 中出现一条原因为 **悬赏所在主题已删除，积分退回** 的记录
- [ ] 关闭 `ingenic_points_enabled` 后，标价资源免费下载且不再发放积分；重新打开后余额仍在
- [ ] 在自己的主题上，**为本帖挂出悬赏** 会显示可挂区间和当前余额；挂出后积分立即从余额中扣除，**Ingenic → Points** 中能看到这部分被托管
- [ ] 进行中的悬赏会同时显示在主题页、首页悬赏版块和 `/ingenic/bounties` 上；不是本人的访问者看不到撤回入口
- [ ] 在该主题采纳答案后，积分全额支付给答主、悬赏关闭，主题上会显示支付了多少、支付给了谁
- [ ] 撤回进行中的悬赏会把积分退回；无人回答的悬赏在 `ingenic_bounty_expiry_days` 到期后的一个小时内自动退回
- [ ] `/ingenic/boards` 显示开发板，配置了购买链接的卡片会显示 **Buy now** 按钮
- [ ] 页头最右侧出现语言切换器——未登录时在 **登录** 按钮旁，已登录时在头像旁；选 **中文** 后页面以中文重新加载，选 **English** 能切回
- [ ] 登录状态下的切换同样有效——该选择在退出再登录后依然保留
- [ ] Ingenic 导航出现在 Discourse 侧边栏中，移动端抽屉中也能看到
- [ ] 侧边栏分为三块——论坛、开发者资源、会员块；MCP 紧跟开发板商店下面，最后一块的顺序为 站点反馈 · 话题 · 高分悬赏 · 积分 · 全部分类 · 更多；点击 **MCP** 进入 `/ingenic/mcp`，该行高亮
- [ ] `/ingenic/mcp` 显示 `https://<你的论坛>/mcp`、可用的 **复制** 按钮、接入步骤和客户端配置；切换到中文后整页都是中文
- [ ] 关闭 `mcp_server_enabled` 后，侧边栏不再出现 **MCP**，`/ingenic/mcp` 提示服务尚未启用
- [ ] 右下角出现机器人按钮，点击打开面板，按 **Esc** 可关闭；按钮进入 AI 机器人对话页（未登录时先登录再返回）
- [ ] 关闭 `ai_bot_enabled` 后按钮消失，页面其他部分不受影响
- [ ] 把文档地址复制到新浏览器标签页，可以直接打开
- [ ] `/ingenic/home` 与 `/` 是同一个首页
- [ ] 在导航里选 **最新** 会进入论坛原生的主题列表，返回首页时首页仍然在
- [ ] 版块模块默认显示三张卡片：技术讨论、在线文档、官方公告；标题末尾的 **所有版块** 链接进入 `/categories`
- [ ] 点击版块卡片会进入对应分类；在 **Ingenic → 站点内容 → 首页卡片** 新建的卡片会替换默认三张，选中分类的卡片沿用该分类的颜色和主题数
- [ ] **Ingenic → 站点内容 → 外链按钮** 中配置的按钮显示在 Logo 旁边和页脚“关注我们”一栏；只显示图标的按钮仍有可供朗读的名称；勾选“跳转到论坛外部”的按钮在新标签页打开
- [ ] 右侧栏自上而下是最新活动、高分悬赏、热门主题，且三者都出现在首屏，无需滚动
- [ ] 如果配置了 `promotions` 模块，**Ingenic → 站点内容** 中配置的活动推广位出现在右侧栏
- [ ] 页脚显示第三方平台区（网页类为链接、App 类为可扫描的二维码）以及配置好的链接列
- [ ] 关闭 `enable_powered_by_discourse` 后，页面结束在该页脚处，底部不再有 **由 Discourse 提供技术支持**
- [ ] `ingenic_official_groups` 中列出的群组成员，用户名旁显示对应图标；自己选择过其他图标的成员保留原图标
- [ ] Google、GitHub 和邮箱登录仍然正常
- [ ] **管理后台 → 自定义 → 主题** 没有主题编译错误

在容器中运行插件 RSpec：

```bash
bundle exec rspec plugins/discourse-ingenic/spec
```

这会执行插件接口测试，是检查后端接口最快的方式。

---

## 6. 回滚

### 回滚主题

进入：

**管理后台 → 自定义 → 主题**

把网站默认主题切回原来的主题即可。不需要 rebuild，也不会造成停机。

### 回滚插件

如果使用 Git 安装：

1. 从 `app.yml` 中删除 `git clone` 配置；或
2. 从 `/var/discourse/plugins/` 删除 `discourse-ingenic` 目录；
3. 执行：

```bash
cd /var/discourse
./launcher rebuild app
```

插件数据表会保留。它们全部以 `ingenic_` 开头，其他功能不会读取这些表，
保留它们不会影响现有论坛，并且之后重新安装插件时内容仍然存在。

---

## 7. 把配置搬到另一台机器

本论坛的配置由两部分组成：插件的设置与内容，以及主题的设置。两者分开导出，因为它们
属于不同的对象。

### 主题设置

**管理后台 → 自定义 → 主题 → Ingenic Community → 导出** 会生成一个 zip，其中
settings 字段带的是主题当前的值，所以在另一台机器上导入这个 zip 就能带上主题设置。
zip 里没有别的——主题的文件来自本仓库。

### 插件设置与内容

```bash
cd /var/www/discourse

# 创建导航指向的论坛版块 —— 见上文
rake ingenic:seed_categories

# 把这个插件拥有的全部配置写进一个文件
rake ingenic:export_config[/shared/ingenic-config.yml]

# 只看文件里有什么，不改动任何数据
rake ingenic:show_config[/shared/ingenic-config.yml]

# 应用它——第二个参数表示执行后整体回滚
rake ingenic:import_config[/shared/ingenic-config.yml,dry]
rake ingenic:import_config[/shared/ingenic-config.yml]
```

文件里包含插件的站点设置（你改过的那些，仍处于默认值的不会写进去），以及管理员在后台
录入的内容：产品树、版本、页面、下载目录与分类、开发板、文档权限、活动推广位、页脚、
社交链接和积分规则。

文件里**刻意不包含任何成员产生的数据**。积分余额、积分流水、高分悬赏、下载申请、
授权记录、开发者资料、下载记录，记录的都是人做过什么，其中开发者资料还是个人信息。
那些东西属于数据库备份，是另一类副本、另一套保管方式，需要的话请直接做数据库备份。

`import_config` 按自然键 upsert——产品由 slug 与语言标识，版本由所属产品与 slug 标识，
依此类推——所以同一个文件导入两次，第二次不会有任何改动。它从不删除：存在于论坛但不在
文件里的记录会原样保留，并在结尾以 `Left alone` 列出，由你决定怎么处理。整个导入在一个
事务里完成，文件被拒绝时论坛保持原样。

上传的 SDK 与固件文件本身也不在文件里，只有指向它们的记录，包括每个文件被写入的路径。
把下载目录一起拷过来的机器可以直接恢复出可用的下载中心；没有那些文件的机器会得到指向
不存在文件的记录。

### 每次部署之后

```bash
rake ingenic:doctor
```

它会检查那几个"设错了也不会报错"的设置——插件被关掉、没人能切换语言、下载目录不可写、
导航指向的版块论坛里没有——并指出需要改哪一项。

---

## 8. 当前验证范围

以下内容已在 Discourse 开发容器中实际验证——`2026.10.0-latest`、PostgreSQL，
插件与主题以开发目录挂载——并且是向运行中的服务器发请求（HTTP）验证的，不是只读代码：

- migration 已在开发库和测试库中真正执行，建出了数据表、外键，以及积分账本依赖的
  那条部分唯一索引；
- 插件 RSpec 测试实际运行通过：548 个用例，0 失败；
- `rake ingenic:seed_categories` 已在真实实例上跑过，三层分类树和它说会设成的权限一致 ——
  包括把早先版本放到技术讨论下面的开源版块挪回顶层；`rake ingenic:doctor` 报告无失败项；
- 主题已作为站点默认主题安装，其导航已在浏览器中检查：三块、顺序、图标，以及
  哪个页面点亮哪个链接；
- 44 项检查跑在真实 PostgreSQL 和真实的删除路径上（`PostDestroyer` 的
  `force_destroy`、`UserDestroyer`）：托管积分从余额中扣除、永久删除主题时退回、
  已支付的悬赏不退回、仅移入回收站则分文不动、绕过回调直接删行时由数据库级联清理、
  成员销号后其账本行保留为无主状态。每一项余额都与它背后的账本求和结果对照过；
- 86 项检查通过 HTTP 打在服务器上：登录、悬赏榜、成员自己的页面、通过插件接口挂出与
  撤回悬赏、两种拒绝（同一主题的第二笔悬赏、超过上限的悬赏），以及由两位管理员完成的
  永久删除——论坛不允许把主题移入回收站的人自己清空回收站——删除之后托管积分确实退回。
  七个页面返回 200 并带应用外壳，分类树里的每个版块都从 `/site.json` 读出，成员可以（200）在
  "三方开源"发布自己的项目、在"官方开源"被拒绝（403），导航设置通过管理页面所用的
  同一个接口写入并读回；
- 另有 89 项检查通过 HTTP 打在管理页面和它背后的写入上，每一项问的不只是"打得开吗"，
  而是"刚写进去的东西，读回来是不是它"：每个管理端点及其对普通成员的拒绝、系列、型号、
  版本、页面，以及第二个版本继承第一个版本的页面（覆盖后不再继承、恢复后重新继承）、
  开发板、下载分类与资源、权限、首页推广位、社交链接、页脚栏目及其中的链接、积分规则
  与手动调整、文档全文检索，以及四个指向不存在内容的文档地址返回 404 而不是别人的页面。

仍然没有验证的部分，是因为容器不是一个有人在用的论坛：

- 没有任何页面被人看过。导航是按浏览器加载的方式检查的，但没有真正打开过页面，
  所以布局、配色、比例都还只是"按设计如此"，没有经过确认；
- 没有发出过任何邮件：容器里没有邮件服务，申请下载的流程停在邮件将要发出的那一步；
- 下载中心已用一个真实的 200 MB 文件试过：公开层完整流式下载，校验和与记录一致；
  表单层在填写开发者信息前拒绝，填写后放行；审批层在申请获批前拒绝，获批后放行，
  撤销授权后又拒绝。文件字节由控制器转发，而不是静态地址直出；
- 管理后台页面尚未在浏览器中打开过：它们背后的接口能应答，Ember 代码也能编译，
  但没有人点过；
- 没有验证过升级路径。这是新建出来的表结构，不是后续版本修改过的表结构。

第一次 rebuild 和浏览器验证是最终的实机测试。如果主题出现编译错误，管理后台
的主题页面会显示具体文件和行号，将错误信息发回即可继续修复。
