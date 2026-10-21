# discourse-ingenic

Ingenic 社区论坛的 Discourse 扩展插件。论坛本身保持 Discourse 原样——话题、分类、标签、搜索和原生侧边栏都仍由核心负责——插件在其下增加一个开发者专区：

- **在线文档**：以芯片为范围，带「系列 → 芯片」两级产品选择器、版本选择、全文检索、可折叠目录树，正文用 Markdown 编写。一个版本只保存它真正改动过的页面，其余页面沿版本链继承，阅读器会标明当前页面实际来自哪个版本。
- **下载中心**：SDK、固件、手册、数据手册和工具链，分三层访问权限（见下文）；文件存放在 `public/` 之外，权限校验通过后才由插件流式返回。
- **开发板目录**：每块开发板都归到产品树里的某个芯片下，卡片上的操作按钮跳转到君正的申请／购买页面。
- **积分**：通过贡献获得，可用于下载，记在只追加的流水里；规则可编辑，会员有自己的积分页面。
- **高分悬赏**：会员在自己的问题上托管积分，采纳答案时全额支付给答主；论坛另有一个悬赏板，列出全站正在悬赏的问题。
- **范围管理**：可以只授予某位管理员一个产品系列，他只能编辑该范围内的内容；每一次写入都由服务端强制执行。
- **只读 JSON 接口**位于 `/ingenic` 下，由配套主题渲染；此外还有管理上述全部内容的后台页面。

插件有意**不碰认证**。Google、GitHub 和邮箱登录完全保持 Discourse 核心的配置。

English: [README.md](README.md).

## 分支

| 分支 | 内容 |
| --- | --- |
| `develop` | 当前版本——所有改动都提交到这里，论坛安装并跟踪的也是这个分支 |
| `main` | 留给正式版本，两次发布之间只保留一行说明 |

`develop` 是仓库的默认分支，直接克隆拿到的就是当前版本。下文安装步骤都显式使用它。

## 文档

- [`docs/usage.zh-CN.md`](docs/usage.zh-CN.md) —— 论坛有哪些功能、会员和管理员怎么用；[English](docs/usage.md)。
- [`DEPLOY.zh-CN.md`](DEPLOY.zh-CN.md) —— 安装、设置与回滚；[English](DEPLOY.md)。
- [`docs/seeding.zh-CN.md`](docs/seeding.zh-CN.md) —— 从控制台批量导入内容；[English](docs/seeding.md)。

## 访问级别

每条下载记录带有三个级别之一：

| 级别 | 访客要做什么 | 服务端要求 |
| --- | --- | --- |
| `public_login` | 登录后即可下载 | 已登录账号 |
| `login_form` | 登录并提交一次开发者信息表单 | 已登录账号，且已保存资料 |
| `login_form_request` | 登录、提交表单，再针对该资源提交申请 | 已登录账号、已保存资料，**并且**对该资源有有效授权 |

申请会发邮件到 `ingenic_download_admin_email` 配置的团队邮箱，并进入后台申请队列，由管理员通过或拒绝。通过会创建一条授权；授权可以按资源和按账号撤销，所以批准一个 SDK 不会顺带开放其他资源。

资源还可以带 `point_cost`，积分是在访问级别**之后**再问的，而不是替代级别：一个 `login_form_request` 且需要 500 积分的资源，新访客仍然要先登录、填资料、等审批，之后才会看到积分要求。购买会写一条流水，所以无论下载多少次，只扣一次。

## 积分

会员发起讨论、回复、被点赞、答案被采纳都能获得积分；每一个动作都有对应的事件，在帖子被删除、点赞被取消、答案被取消采纳时把积分扣回。

`IngenicPointRule` 是价目表——它是一张表而不是常量，所以数值、文案和顺序都由团队决定，改规则不需要发版。停用一个动作是把规则下架，而不是删除，因为流水仍然引用它。

`Ingenic::Points` 是进入流水的唯一入口：`award`、`reverse`、`reverse_subject`、`spend`、`adjust`、`total_for`、`unlocked_download_ids` 和 `rebuild!`。每一次变动都在 `ingenic_point_entries` 写一行，并在同一事务里让 `ingenic_point_balances` 变动相同的数额，所以余额永远可以从它背后的流水解释——也可以从流水重新算出来。

流水行永远不改。收回一笔奖励是再写一条方向相反的行，账本记录的是「发生了什么」，而不只是「现在是什么状态」。

这里的任何事都不允许让论坛动作失败：挂在发帖上的处理器捕获所有异常并写日志，因为丢一个积分比丢掉挣来这个积分的帖子要好。

## 高分悬赏

会员在**自己的**话题上托管积分，并在采纳答案时全额支付给答主。它买到的是一个标了价的问题：回答一个难题要花掉某人一个下午，而一个公开的悬赏板才让这个下午值得花。

积分是**托管，不是承诺**。发起悬赏时，积分在同一事务里从提问者余额中扣除，记为一条以该悬赏为对象的负数流水，所以悬赏存续期间这些积分不能被拿去买下载。如果改成结算时再查余额，一个会员就能在五个问题上各挂同样的 1000 分，然后只结算最先被回答的那个。

| 状态 | 含义 | 流水 |
| --- | --- | --- |
| `open` | 悬赏有效 | 从提问者余额扣除（`bounty`） |
| `accepted` | 答案已被采纳 | 全额支付给答主（`bounty_award`） |
| `cancelled` | 提问者撤回 | 退回提问者（`bounty_refund`） |
| `expired` | 到期无人回答 | 退回提问者（`bounty_refund`） |

`open` 是悬赏唯一会离开的状态，而且离开后不会再回来：每个话题只能有一个有效悬赏，由部分唯一索引和代码检查双重保证，所以同时提交两个表单不可能都成功。已结算的记录留在原地，话题页会把它画出来——一个答案值多少，正是悬赏板值得读的一半原因。哪个答案胜出、钱付给了谁，都从被采纳的帖子读出，不另存一份。

**采纳答案就是付款，而且不可逆。** 那个 ✓ 是 discourse-solved 自己的，悬赏跟着它走：采纳会把话题标记为已解决、关闭悬赏并在同一事务里转移积分，行锁保证即使同时到达多个采纳请求，同一个悬赏也不可能付两次。事后取消采纳不会把积分追回。答主可能已经花掉了它们，而从没有做错事的人手里拿走积分，比容忍一个未标记的答案更糟——管理员可以手工调整两个账号，但没人能修复一个软件拒绝进入的状态。工作人员可以代替提问者采纳；提问者是悬赏**存在的原因**，而不是机制的前提。

无人回答的悬赏会自己回来：一个定时任务每小时（而不是精确到分钟，反正积分已经在托管中）退回到期的悬赏（`ingenic_bounty_expiry_days`，默认 14 天）。提问者也可以提前撤回，那是同样退款、不同原因。

悬赏也会随话题结束。永久删除话题时，仍然有效的悬赏在删除自己的事务里退回：悬赏关闭、积分回到提问者，然后记录随话题一起删除。顺序就是重点——托管是一条流水，一条没有关闭就消失的悬赏会带走「欠了多少积分」的唯一记录。已结算的悬赏只是随话题消失：答主保留已经拿到的钱，失去的是「这个问题值多少」的备注。把话题移入回收站不是删除——悬赏仍然有效直到到期，只是这期间悬赏板不再展示它。

这个功能依赖积分系统和 discourse-solved，任一个关闭它就关闭。关闭悬赏会停止接受新悬赏，但仍让现有悬赏到期退款——关闭开关不能把任何人的积分困住。话题删除同理：无论悬赏功能是否开启，积分都要退回，因为设置永远不能成为「保留会员当初托管积分」的手段。

## 环境要求

- Discourse `2026.10.0-latest` 或更高版本（本插件基于该版本开发）
- 配套主题 [`discourse-ingenic-theme`](https://github.com/aishangletaohua/discourse-ingenic-theme)，用于界面，作为 Discourse 主题单独安装

## 安装

插件和主题是两个独立仓库。本仓库是插件，克隆到 `plugins/discourse-ingenic`。

加入 `containers/app.yml`：

```yaml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          - git clone https://github.com/aishangletaohua/discourse-ingenic-plugin.git discourse-ingenic
```

以后升级时，在重建前拉取：

```yaml
hooks:
  after_code:
    - exec:
        cd: $home/plugins/discourse-ingenic
        cmd:
          - git pull --ff-only
```

然后重建：

```bash
cd /var/discourse
./launcher rebuild app
```

重建后插件会自动执行迁移，新表随之建立。

主题在**后台 → 自定义 → 主题 → 安装**里用它自己的仓库地址安装，所以以后更新主题只是该页面上的一个按钮，不需要重建。具体步骤见主题仓库的 README。

## 管理

管理员可以打开**后台 → 插件 → Ingenic**，管理文档、开发板、下载、申请队列、授权、积分、站点内容和权限。文档和开发板也可以由被授予权限的会员打开——来源可以是权限矩阵里的整屏授权，也可以是某个产品或某块开发板上的单条授权。下载、积分和站点内容同样可以通过整屏授权开放。权限、权限矩阵、版块权限和标签配色四个页面始终是管理员专属，因为它们决定的都是「谁还能做什么」。

权限矩阵把某一整块管理页面授予一个自定义用户组：在线文档、开发板、下载中心、积分或站点内容。它是粗粒度的一层——勾选表示「所有产品」，而不是「这个产品」。「权限」页里的按记录授权叠加在其下，仍然更窄，所以单个产品依然可以只借给某位成员，而不必交出整个页面。自动组（版主、信任级别、所有人）不在列表中：给「所有人」打勾等于把管理页面交给每一位访客，这不该由一个复选框顺手决定。

标签配色为每个标签指定五种颜色系列之一：天蓝用于一般讨论，科技蓝用于平台、工具与硬件，已解决用于有答案的问题，公告用于官方通知，高赞用于社区认可的好帖。颜色系列是固定的，以保证全站视觉语言一致；标签列表则来自站点本身——今天新建的标签无需发版就会出现在页面上。没有指定颜色的标签按名称推断，推断不出时使用天蓝。

版块权限是论坛一侧的对应物：按分类写入 `category_groups` 行，规定每个自定义用户组能读、能回复还是能发帖。没有任何行的分类对所有人开放，所以一次会把原本有行的分类清空的保存会被拒绝，而不是悄悄开放它。自动组保持原样，本页只修改自定义组。

标签词表是策略，不是约定：新建标签是管理员的工作，发帖时选用已有标签不是。公告、已解决、高赞组成一个只有管理团队可以打标的标签组。已解决跟随 discourse-solved 的采纳状态；定时任务按 `ingenic_high_like_threshold`（默认 20）统计点赞，达标打上高赞、回落撤回，管理员手工打上的不会被移除。

悬赏没有独立的后台页面，因为悬赏没有什么是管理员需要决定的：会员在自己的话题上发起，并通过采纳答案结算。管理员需要的信息在积分页面上——有多少积分被有效悬赏托管着——付错了也在那里修，通过调整两个账号完成。

文档管理页编辑目录树、决定文章归属哪个节点，并可以在任意版本下编辑文章。某个版本没有编辑过的页面会从前一个版本继承，页面会明确说明：每一页都显示它当前来自哪个版本，并提供「在本版本覆盖」或「取消覆盖、恢复继承」的操作。正文带 Markdown 工具栏（加粗、斜体、标题、引用、列表、代码、链接），图片可以通过按钮、粘贴或拖拽加入；图片走 Discourse 上传并以 `upload://` 形式的 Markdown 插入，和帖子里的图片一样渲染。

权限可以授予用户或群组。产品权限会被它的版本和页面继承；页面权限只被该页面的子页面继承。服务端会检查每一次创建、读取、更新、删除和权限变更，所以在后台界面上隐藏一个按钮并不是授权边界。

产品树明确区分两级：把 `T Series` 建成 `series`，把 `T33` 建成它下面的 `chip`。同一棵树同时驱动文档选择器、下载筛选和开发板所属芯片，所以三处对芯片名称的理解不会不一致。授予 `T Series` 可以让管理员编辑它的后代；授予 `T33` 不会顺带获得它的兄弟或父级的权限。

## 接口

公开、只读，另有标注的除外：

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/ingenic/home` | 首页。返回应用外壳；页面本身在浏览器里组装 |
| GET | `/ingenic/docs` | 第一个已发布的系列、它的第一个芯片，以及该芯片的默认版本 |
| GET | `/ingenic/docs/*path` | `/<series>[/<chip>[/<version>[/<page>]]]` —— 省略的层级由上一级补全 |
| GET | `/ingenic/docs-search` | 跨文档全文检索 |
| GET | `/ingenic/downloads` | 下载记录；接受 `product`、`kind`、`version`、`platform` |
| GET | `/ingenic/downloads/:id/file` | 文件本身，权限校验通过后流式返回 |
| POST | `/ingenic/downloads/profile` | 保存开发者信息表单（需登录） |
| POST | `/ingenic/downloads/:id/request` | 申请受限资源（需登录） |
| GET | `/ingenic/boards` | 已发布的开发板；接受 `series` 和 `chip` |
| GET | `/ingenic/points` | 当前读者的余额、价目表和他自己的记录 |
| GET | `/ingenic/bounties` | 有效悬赏，金额从高到低，附带新悬赏的允许范围和读者余额 |
| POST | `/ingenic/bounties` | 在读者自己的某个话题上发起悬赏（需登录） |
| POST | `/ingenic/bounties/:id/cancel` | 撤回有效悬赏并退款（需登录） |

POST 需要已登录账号；其余接口未登录也可读。每个 GET 有两种回答——前端带 `Accept: application/json` 时返回 JSON，访客直接打开或刷新地址时返回应用外壳。这才让文档或下载链接可以被分享，而不是只能在应用里点进来。

文档路径是一条 Rails glob，而不是四层嵌套路由：控制器自己拆分路径，所以以后增加层级不需要动路由表。裸的 `/ingenic/docs` 单独声明，因为 glob 只在有斜杠时才匹配。搜索是 glob 的兄弟路径而不是它内部的一段，这样即使有芯片叫 `search` 也仍然可用。

## 首页

插件把 Ingenic 首页注册为 Discourse 的一个候选**首页**——`plugin.rb` 里的 `register_homepage`，在插件自己的设置可用之后调用，以便选项可以依赖这些设置：

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

这带来的好处，按重要程度排列：

- 该选项会出现在站点的 **`default_homepage`** 设置里，选中后由 Discourse 自己把页面挂到 `/`。因此首页是一个独立的目的地，而不是盖在话题列表上的一个区块，在导航里选「最新」会去最新话题，不会把首页一起带走。
- `/ingenic/home` 仍然是这个页面自己的地址。Discourse 把选中的首页挂到 `/`，但选项的 `path` 才是链接、刷新和分享 URL 使用的地址。
- `anonymous: true` 意味着未登录访客看到的是首页，而不是被重定向到最新话题。
- `enabled` 在每次解析首页时读取，所以关闭 `ingenic_enabled` 会把站点交还给普通首页，不需要再改第二个设置。

`IngenicHomeController#index` 只渲染应用外壳。页面内容——区块以及它们列出的分区——在浏览器里用站点已经发送的数据组装：首页区块通过站点序列化器，分类来自 `site.json`（服务端已经按读者权限过滤过）。没有第二个接口，也没有第二份分类列表。

## 站点设置

| 设置 | 用途 |
| --- | --- |
| `ingenic_enabled` | 总开关 |
| `ingenic_nav_items` | JSON 数组——侧边栏条目：图标、目标、分组（`forum` / `resources` / `member`）、组内顺序和可见性 |
| `ingenic_homepage_blocks` | JSON 数组——首页渲染哪些区块、以什么顺序 |
| `ingenic_default_locale` | 文档、下载和开发板的回退语言 |
| `ingenic_docs_discussion_category` | 页面没有关联话题时，「在论坛讨论」使用的分类 |
| `ingenic_download_storage_path` | 上传的 SDK 和固件存放位置，必须在 `public/` 之外 |
| `ingenic_download_admin_email` | 接收受限下载申请的邮箱 |
| `ingenic_developer_form_fields` | 描述开发者信息表单的 JSON 数组 |
| `ingenic_points_enabled` | 积分系统总开关；关闭后流水保持完整 |
| `ingenic_points_exclude_staff` | 管理员和版主是否获得积分 |
| `ingenic_bounties_enabled` | 悬赏总开关。关闭后停止新悬赏，仍会退回到期的悬赏 |
| `ingenic_bounty_min_points` | 一次悬赏的最低积分 |
| `ingenic_bounty_max_points` | 一次悬赏的最高积分 |
| `ingenic_bounty_expiry_days` | 悬赏有效天数，到期后关闭并退款 |
| `ingenic_high_like_enabled` | 是否由定时任务维护「高赞」标签 |
| `ingenic_high_like_threshold` | 话题所有正常回复的点赞数达到多少时获得「高赞」（默认 20） |

三个 JSON 设置的格式写在 `config/settings.yml` 的注释里。语言设置只列出这个 Discourse 能提供的语言，所以在 Discourse 里启用一种语言，这里就能选，不需要改文件。

## 数据模型

```
ingenic_doc_products        系列和芯片，按语言区分，一棵两层的树
ingenic_doc_versions        某个芯片的版本，其中一个标记为 `latest`
ingenic_doc_pages           版本实际改动过的页面，parent_id 构成目录树
ingenic_downloads           可下载资源、访问级别和 point_cost
ingenic_developer_profiles  开发者信息表单，每个账号一份
ingenic_download_requests   申请及其审核状态
ingenic_download_grants     审批结果，按账号、按资源
ingenic_boards              开发板，归属到某个芯片
ingenic_permissions         授予用户或群组的范围权限
ingenic_group_permissions   授予用户组的一整块管理页面
ingenic_tag_colours         按标签名保存的颜色系列指定
ingenic_point_rules         每个动作值多少分，以及它的名称
ingenic_point_entries       流水：每次变动一行，只追加
ingenic_point_balances      每个账号的累计余额，由流水推导
ingenic_bounties            某个会员在某个话题上的悬赏，以及它的结局
```

`ingenic_doc_pages` 是**每个改动过它的版本**一行，而不是每个版本一行：某个版本没有某个 slug 的行，就继承最近一个更早、有该行的版本。这避免了文档集随版本数成倍膨胀。

会员可以被删除。这里对 `users` 的每一处引用要么**置空**——行保留、账号置空，流水、申请、授权和悬赏都是这样——要么**级联删除**，用于那些属于个人而非属于论坛的记录：开发者资料、缓存的余额、授予一个已不存在的人的权限。普通引用会让删除一个活跃会员因外键冲突而失败，而管理后台没有办法解释这件事。账号被置空的地方，界面显示**已删除账号**，而不是空白。`Ingenic::Points.record` 会为两条会走到这里的路径写一条没有账号的流水：删除会员后收回其奖励，以及退回他留下的有效悬赏——托管是一条流水，所以关闭它的变动也必须是一条流水。

话题是另一种引用。`ingenic_bounties.topic_id` **级联删除**，因为悬赏的每一种读法都要经过它的话题——话题页问有什么悬赏，悬赏板通过访客可见的话题找到悬赏，采纳答案也按帖子的所属话题查找——所以一条不挂在任何东西上的悬赏不记录任何事。级联与 `Topic` 上的 `before_destroy` 回调配合，先关闭有效悬赏，从而不会销毁托管的积分：`Ingenic::Bounties.refund_for_topic!`。

每张内容表都有 `locale` 列，所以以后启用更多语言不需要迁移表结构。语言代码使用 Discourse 自己的（`zh_CN`、`pt_BR`），因为它们要与 `I18n.locale`——读者在偏好设置里选择的语言——比较。请求先按读者语言解析内容，再逐页回退到 `ingenic_default_locale`，所以只翻译了一半的版本仍然能渲染，一个页面在目录里也只出现一次，而不是每种语言一次。

## 添加内容

文档页面在 `ingenic_doc_pages.body` 里用 Markdown 编写，通过 `PrettyText.cook` 渲染，所以支持与论坛帖子相同的格式。

完整示例见 `docs/seeding.zh-CN.md`，英文版是 `docs/seeding.md`。

## 开发

本仓库不含 Discourse 源码。要运行插件测试套件，需要一个 Discourse 开发环境——Discourse `2026.10.0-latest` 的检出并把插件放在 `plugins/` 下，或者使用它的开发容器：

```bash
bin/docker/boot_dev --init    # 在 Discourse 检出目录里执行
bin/docker/rspec plugins/discourse-ingenic/spec
```

## 支持

请联系 Ingenic 社区团队。
