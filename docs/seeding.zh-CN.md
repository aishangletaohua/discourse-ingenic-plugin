# 录入文档、下载资源与开发板

内容保存在插件自己的数据表中。日常编辑在 **管理后台 → 插件 → Ingenic** 中完成，
控制台（console）适合首次导入和批量操作。两条路径走的是同一套模型，因此这里
能建出来的记录，管理页面也一定能建出来，反之亦然。

```bash
cd /var/discourse
./launcher enter app
rails c
```

本文与英文版 `docs/seeding.md` 内容一致，可对照阅读。

## 论坛版块

站点上并不是每个版块都是插件表里的内容：官方公告、技术讨论、开源版块就是
Discourse 原生的分类，因为它们是给人发帖的地方。侧边栏链接指向它们，而全新安装
的 Discourse 一个分类都没有 —— 所以它们由 rake 任务创建，而不是在控制台里建：

```bash
cd /var/discourse
./launcher enter app
rake ingenic:seed_categories
```

技术讨论这棵树有三层，和在线文档的产品选择器、下载筛选是同一个形状：技术讨论
下面是各系列，系列下面是型号。开源版块与它平级，在导航里紧跟其后，下面是两个
子版块。

| 版块 | 上级 | 谁可以发帖 |
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

第三层要求 `max_category_nesting` 为 3；Discourse 默认的 2 会拒绝型号这一层。
这个设置不在后台界面上，所以任务会在创建之前自己设好：

```ruby
SiteSetting.max_category_nesting = 3
```

每个分类还带一个中文名和中文简介（`官方公告`、`技术讨论`……）。只有开启内容
本地化、并把 `zh_CN` 加进支持语言之后，Discourse 才会显示它们，所以首次运行前
先把两者打开：

```ruby
SiteSetting.content_localization_enabled = true
SiteSetting.content_localization_supported_locales = "zh_CN"
```

如果分类是在这两个设置打开之前建的，再跑一次任务：它会为已存在的分类补上
缺失的 `locale` 和 `zh_CN` 名称，不会第二次改英文名，也不会多出一行。本地化
关闭时不会写入任何翻译行 —— 写了也没有地方读。

再跑一次，已经存在的分类会原样保留 —— 改名、换颜色都随你。唯一由这张表决定的
是归属：slug 在表里、但上级不是表里写的那个，就会被改挂过去，因为树就是这张表
的形状。早先版本放到技术讨论下面的开源版块，就是这样被挪回顶层，而不是再复制
一份。slug 在全站唯一，所以按旧地址找到的那一行就是同一个版块。另一个会在被
要求时重新写回的，是上面这张表里的权限：

```bash
rake ingenic:seed_categories[permissions]
```

改动上面这张表之后、或者有人能在"官方开源"里发帖需要修回来时，跑这一条。
`rake ingenic:doctor` 会报出十六个里缺了哪一个（在控制台里调
`Ingenic::ForumCategories.missing` 得到的是同一份名单）。

## 产品树

其他所有内容都挂在这棵树上，所以先建它。产品分为 `series`（系列）和 `chip`
（型号）两种，形状由数据库约束保证：系列没有父级，型号的父级必须是系列。
`position` 决定两个层级内部的顺序。

这个区分是有实际作用的。在线文档的两级选择器、下载中心的系列与型号筛选、
开发板目录都读它，所以树建反了的表现是"筛选怎么点都筛不出东西"。

```ruby
series = IngenicProduct.create!(
  slug: "t-series",
  name: "T Series",
  kind: "series",
  locale: "en",
  description: "Vision SoCs for cameras and set-top boxes",
  position: 0,
)

chip = IngenicProduct.create!(
  slug: "t32pro",
  name: "T32Pro",
  kind: "chip",
  parent: series,
  locale: "en",
  position: 0,
)
```

## 在线文档

版本挂在型号下，页面挂在版本下。页面的 `parent_id` 用来构建左栏目录树，
一个有子页面的页面就成为一个可折叠的分组。

```ruby
latest = IngenicDocVersion.create!(
  product: chip,
  slug: "2.1.0",
  label: "2.1.0",
  latest: true,
  released_on: Date.new(2026, 9, 1),
  position: 0,
)

previous = IngenicDocVersion.create!(
  product: chip,
  slug: "2.0.0",
  label: "2.0.0",
  released_on: Date.new(2026, 3, 1),
  position: 1,
)

overview = IngenicDocPage.create!(
  version: previous,
  slug: "overview",
  title: "Overview",
  position: 0,
  body: <<~MD,
    ## Chip introduction

    The T32Pro series is a highly integrated vision SoC.

    | Item | Value |
    | --- | --- |
    | CPU | ... |
  MD
)

IngenicDocPage.create!(
  version: latest,
  parent: nil,
  slug: "quick-start",
  title: "Quick Start",
  position: 1,
  body: "How to build and flash your first image.",
)
```

### 版本继承

一个版本只保存"在本版本中编辑过的页面"。上面的 `overview` 是在 2.0.0 里写的，
2.1.0 里没有动过，但 2.1.0 仍然会显示它——解析器按版本从旧到新遍历，同一个 slug
以最新的一版定义为准。因此发布新版本不需要复制整套手册，也就不需要维护多份副本
保持同步。

顺序由 `position` 决定，数值小的在前。调整版本顺序会改变继承关系，这本身就是
机制的一部分：把某个版本排到 2.0.0 之后，它就什么都继承不到了。

如果一个页面存在于某个版本，而它的父页面只存在于更早的版本，它仍然会挂在那
个父页面下，所以在某个版本里单独覆盖一个页面不会让它脱离目录树。

### 地址规则

```text
/ingenic/docs/<系列>/<型号>/<版本>/<页面>
```

系列之后的每一段都可以省略。缺少的段落会解析为该层级下第一个已发布条目
（`position` 最小的那个），`latest` 是"被标记为 `latest: true` 的版本"的别名。
因此 `/ingenic/docs` 打开第一个系列的第一个型号，`/ingenic/docs/t-series`
打开 T 系列下的第一个型号。

注意第一段永远按"系列"解析。`/ingenic/docs/t32pro` 不会打开型号 `t32pro`，
它会去找同名系列，找不到，然后回退到第一个系列。要链接到型号请写
`/ingenic/docs/t-series/t32pro`。

页面可以关联到一个已有的论坛主题，设置 `topic_url` 即可：

```ruby
overview.update!(topic_url: "/t/getting-started-with-t32pro/123")
```

## 下载资源

资源分类是一张表而不是固定列表，可以在 **Ingenic → Downloads → Classifications**
中增删改名。迁移已经把这批分类写成数据行：`sdk`、`firmware`、`manual`、
`datasheet`、`toolchain`、`example`、`release_notes`、`other`。所以通常只需要
挑一个用，不需要新建。

```ruby
sdk = IngenicDownloadCategory.find_or_create_by!(name: "sdk", locale: "en")
```

资源就是卡片：名称、型号、分类、图片和访问规则。文件作为版本挂在卡片下面，卡片
展示访客选中的那个版本。先建卡片：

```ruby
sdk_card = IngenicDownload.create!(
  product: chip,
  category: sdk,
  locale: "en",
  name: "T32Pro SDK",
  access_level: "public_login",
  published: true,
)
```

没有版本之前这张卡片不能下载。一个版本要么指向存放在别处的文件，要么自己带一个
上传的文件；指向外部文件时：

```ruby
sdk_card.versions.create!(
  version: "2.1.0",
  description: "Linux SDK including toolchain and examples.",
  platform: "Linux",
  architecture: "x86_64",
  file_url: "https://download.ingenic.com/t32pro/sdk-2.1.0-en.tar.gz",
  file_size: "1.4 GB",
  file_sha256: "0000000000000000000000000000000000000000000000000000000000000000",
  released_on: Date.new(2026, 9, 1),
  published: true,
)
```

第二个版本是同一张卡片下的另一行，各有自己的描述、文件和发布日期：

```ruby
sdk_card.versions.create!(
  version: "2.2.0",
  description: "新增 T33 摄像头通路，工具链更新。",
  platform: "Linux",
  architecture: "x86_64",
  file_url: "https://download.ingenic.com/t32pro/sdk-2.2.0-en.tar.gz",
  file_size: "1.5 GB",
  released_on: Date.new(2026, 10, 1),
  published: true,
)
```

`product` 填产品树里的型号记录。芯片资料必须挂一个型号，不能挂在系列上。版本号
在同一张卡片内唯一，两张卡片可以各有一个 `1.0`；草稿版本允许不填版本号，此时选择器
显示它的发布日期。

访问规则、积分和申请都属于卡片：给某个账号批准 `T32Pro SDK`，就同时覆盖 2.1.0、
2.2.0，以及之后新发布的版本。

`family` 是下载目录的顶层归类：`chip`（默认，芯片资料）或 `algorithm`（算法）。
算法面向多个芯片、不归属某一个型号，因此 `product` 留空：

```ruby
algorithms = IngenicDownloadCategory.find_or_create_by!(name: "algorithm", locale: "en")

h264 = IngenicDownload.create!(
  family: "algorithm",
  category: algorithms,
  locale: "en",
  name: "智能 H.264 编码库",
  access_level: "public_login",
  published: true,
)
h264.versions.create!(
  version: "2.1",
  description: "带 T 系列码率控制补丁的编码库。",
  platform: "Linux",
  file_url: "https://download.ingenic.com/algorithms/h264-2.1.tar.gz",
  published: true,
)
```

下载页的“芯片系列”一行来自产品树，算法作为与各系列并列的一个选项出现在这一行；
只有当已发布的资源里存在 `algorithm` 时它才会出现。若产品树里有一个 slug 为
`algorithm` 的系列，就用它的名称作为该选项的文字，这样可以在文档管理页里重命名；
没有时使用界面文案“算法”。选中算法后，“具体型号”一行会隐藏，资源分类只列出算法
资源实际使用的分类。

`access_level` 取三个值之一：`public_login`（登录即可）、`login_form`（登录，
并且已填写开发者信息）、`login_form_request`（登录、已填写开发者信息，并且申请
已通过审核）。默认值是 `public_login`。

无论级别是什么，版本的 `file_url` 都不会由列表接口发给浏览器——页面给出的是插件
自己的接口地址，由接口决定是否放行。下载接口接受 `version_id`；不带时返回最新的
已发布版本。凡是需要管控的文件，建议改用上传：放在对象存储上的地址，任何拿到这个
地址的人都能直接下载。

通过管理页面上传的文件会写到 `ingenic_download_storage_path`，并记录为
`storage_path` 和 `original_filename`。如果要在控制台里做同样的事，需要走控制器
用的那个辅助方法：

```ruby
stored = Ingenic::DownloadStorage.store(uploaded_file)
sdk_card.versions.create!(
  version: "2.3.0",
  storage_path: stored[:path],
  original_filename: uploaded_file.original_filename,
  file_sha256: stored[:sha256],
  file_size: stored[:size],
  file_url: nil,
  published: true,
)
```

同一行不能同时带 `file_sha256` 和 `sha256`：前者是服务器在上传时算出的摘要，后者
是随外部链接手填的校验值。

卡片图片同样是一个上传记录，通过引用而不是 URL 指定：

```ruby
sdk_card.update!(image_upload: Upload.find_by(id: upload_id))
```

卡片按固定 4:3 比例裁切显示；没有上传图片的卡片显示目录占位图。已发布但所有版本
都未发布的卡片不会出现在列表中——它没有东西可以交付。

### 申请与授权

一次申请是 `ingenic_download_requests` 中的一行，挂在卡片上。批准它会在同一个事务
里签发 `ingenic_download_grants`。授权没有到期时间：申请通过后该账号可以一直下载
这个资源，包括之后新发布的版本。真正说明“文件被取走”的是下载日志，而不是授权记录。

```ruby
request = IngenicDownloadRequest.create!(user: someone, download: sdk_card)
request.approve!(admin, note: "welcome")

# 不经申请、直接授权，也是同一件事。
IngenicDownloadGrant.issue!(someone, sdk_card, granted_by: admin)
IngenicDownloadGrant.find_by(user: someone, download: sdk_card).revoke!(admin)
```

同样的操作在 **Ingenic → Downloads → Applications** 和 **Grants** 中都有，谁在什么
时候下载了什么记录在 **Ingenic → Downloads → Log**。

## 开发板

一块开发板属于产品树里的某一个型号，这正是目录能按系列和型号两级筛选、并决定
卡片语言的原因。要先建型号：没有型号、或挂到"系列"而不是"型号"的开发板都会被
拒绝，因为那样它会在该系列的每个型号下都出现一次。

```ruby
IngenicBoard.create!(
  slug: "t32pro-evk",
  name: "T32Pro EVK",
  product: chip,
  description: "Evaluation kit for the T32Pro series.",
  details: "参见 [T32Pro 文档](/ingenic/docs/t-series/t32pro)。",
  specs: "2 GB DDR3 · dual Gigabit Ethernet · camera interface",
  image_url: "https://download.ingenic.com/boards/t32pro-evk.png",
  application_url: "https://www.ingenic.com.cn/apply?board=t32pro-evk",
  purchase_url: "https://www.ingenic.com.cn/buy?board=t32pro-evk",
  sold_out: false,
  position: 0,
)
```

`chip` 会从关联的产品自动填入，不需要手工设置；它仍然是一个字段，是为了支持
"开发板先上线、型号稍后再建"的情况。`application_url` 和 `purchase_url` 都是
站外链接，渲染时会带上 `rel="noopener noreferrer"` 并在新标签页打开。两个链接
都不是必填：卡片始终显示**申请**和**立即购买**，缺链接的按钮置灰。`sold_out`
是独立的售罄开关，打开后卡片盖印章、两个按钮都禁用，链接仍然保留。`details`
使用 Markdown，显示在弹窗里。

## 积分

积分是成员通过贡献获得的，也是下载资源可以标价消耗的。涉及三张表：
`ingenic_point_rules`（价目表）、`ingenic_point_entries`（流水账，每次变动一行，
只增不改）、`ingenic_point_balances`（每个账号的累计余额，由流水账推导得出，
也可以由流水账重新算出来）。

迁移会写入四条规则，这是插件的起点，不是必须保持不变的值：

| `event` | 积分 | 名称 |
| --- | ---: | --- |
| `topic_created` | 5 | Opening a discussion |
| `post_created` | 2 | Answering in one |
| `like_received` | 1 | A post of yours being liked |
| `solution_accepted` | 15 | Your answer being accepted |

"有哪些事件"是插件决定的——每个事件都需要 Discourse 里有地方会上报它——而分值、
名称和顺序是你们决定的。这四项都可以在 **Ingenic → Points** 页面修改，日常修改
建议在那里做，不必进控制台：

```ruby
IngenicPointRule.for(IngenicPointRule::SOLUTION_ACCEPTED).update!(points: 25)

# 停用一个动作但保留数据行：流水账里仍然会引用它。
IngenicPointRule.for(IngenicPointRule::LIKE_RECEIVED).update!(published: false)
```

`IngenicPointRule.amount_for(event)` 返回某个动作"当前"一次值多少分；对于已停用
或从未写入的规则返回 `0`。这正是停用一个动作之所以安全的原因。

### 流水账

没有任何地方需要手工写流水。每一次变动都经过 `Ingenic::Points`，它在同一个事务里
写入流水行并同步余额：

```ruby
Ingenic::Points.award(user: someone, event: IngenicPointRule::TOPIC_CREATED, subject: post)
Ingenic::Points.reverse(entry, reason: "the post went away", by: admin)
Ingenic::Points.reverse_subject(post, reason: "the post went away")
Ingenic::Points.spend(user: someone, points: 50, subject: resource, reason: "unlocked")
Ingenic::Points.adjust(user: someone, points: 25, note: "helped with a bug", by: admin)
Ingenic::Points.total_for(someone)          # 该账号的余额
Ingenic::Points.unlocked_download_ids(someone)
Ingenic::Points.rebuild!                    # 重新计算全部余额
```

一次奖励对同一个对象只记一次：奖励所对应的对象是唯一索引的一部分，所以同一个事件
第二次到达时不会重复发放，而是什么都不写。`award` 返回写入的流水行，或者在没有
任何东西需要记录时返回 `nil`——没有对应规则、规则分值为 0、积分功能已关闭、
或者这个对象已经发放过。`nil` 是正常结果，不是失败。

`spend` 用返回值表达结果而不是抛异常，因为调用方是一次下载，"积分不够"是一种需要
展示给用户的状态，而不是一个报错页面。返回值有三种：`:spent`（已扣分，资源归该
账号）、`:already`（之前已经买过，不再重复收费）、`:insufficient`（积分不足，
没有写入任何记录）。

流水行不会被修改。要撤回一次奖励，是再写一条方向相反的记录，因此流水账忠实反映
"发生过什么"——先发了分，之后又收了回来——而原来那条奖励记录仍然留在那里可以查看。

`ingenic_point_balances` 是一份缓存。如果它和流水账对不上——比如恢复备份之后，
或者有人直接改过数据库——执行 `Ingenic::Points.rebuild!` 就会把它算回来，并返回
修正了多少行。这也是"余额可以信任，但它不是权威"的原因。

### 资源标价

给资源标价就是在资源本身上设置一个字段。默认值 0 表示免费：

```ruby
resource.update!(point_cost: 50)
```

价格是在访问级别"之后"才询问的，而不是替代访问级别：一个标价 50 分、
级别为 `login_form_request` 的资源，对于新访客仍然是先登录、先填开发者信息、
先通过审核，然后才会提到积分。账号积分足够时列表显示 **Unlock for N points**，
不够时显示 **Needs N points**；购买会写入一条流水，所以同一个资源第二次下载
不再收费。

### 成员页面

`/ingenic/points` 向已登录成员显示自己的余额、价目表和自己的变动记录。这个页面
在前端是只读的，也不会显示其他人的记录。是否把它放进导航是主题的事情，不是插件
的事情：主题自带一个"积分"入口；如果站点已经配置了自己的 `ingenic_nav_items`，
需要自己补上这一项，因为一旦配置了列表，它会整体替换主题自带的默认列表。

## 增加第二种语言

第二种语言是第二套产品目录，不是加一列翻译。所有内容从创建那一刻起就属于某一种
语言：先建产品行，再建它的版本和页面，最后建引用它的开发板和下载。

```ruby
chinese_series = IngenicProduct.create!(
  slug: "t-series",
  name: "T 系列",
  kind: "series",
  locale: "zh_CN",
  position: 0,
)

chinese_chip = IngenicProduct.create!(
  slug: "t32pro",
  name: "T32Pro 中文",
  kind: "chip",
  parent: chinese_series,
  locale: "zh_CN",
  position: 0,
)
```

语言代码必须使用 Discourse 自己的写法——`zh_CN`、`pt_BR`、`zh_TW`，不要写成
`zh-CN`。这个值会和 `I18n.locale` 比较，也就是访问者在 *偏好设置 → 界面语言*
中选择的语言，带连字符的代码匹配不上任何东西，那条记录就等于不存在。

两套目录之间不互相回退。只有英文的页面，在中文读者的目录里就是不出现，直到有人
写下同 slug 的中文页面；没有中文记录的产品也不会出现在中文选择器里。同一语言
内部仍然有版本继承：新版本没有重写的页面，继续显示上一版本的内容。

产品、版本、页面、下载资源、开发板、下载分类和站点内容都遵循这套规则。管理界面
先选语言，之后创建的一切都属于该语言。
