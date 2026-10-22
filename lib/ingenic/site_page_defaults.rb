# frozen_string_literal: true

module Ingenic
  # The policy pages a forum has to have before anyone can be pointed at them.
  #
  # The footer used to send readers to whichever address an editor typed — a
  # Discourse default, an external document, or nothing at all. The link is the
  # same either way; what was missing was the page at the end of it. These are
  # the starting words for the three the footer names, written in both site
  # languages, and they are only a starting point: the moment the forum is
  # installed the copy becomes rows an administrator edits.
  #
  # They are also the answer when a row is missing, so an installation that has
  # not opened the management screen yet still serves a readable page rather
  # than a 404 behind a link that is on every page of the site.
  module SitePageDefaults
    # The order the pages are listed in the management screen and seeded in.
    SLUGS = %w[terms privacy points-rules].freeze

    PAGES = {
      "terms" => {
        en: {
          title: "Terms of Service",
          body: <<~MARKDOWN,
            These terms apply to the Ingenic Developer Community and to the documentation, software and other material published on it. By using the forum you agree to them.

            ## Using the forum

            The forum is a place to ask questions, report problems and share work with other developers. Read and post in the language the category asks for, keep questions in the category that fits them, and search before opening a new topic.

            ## Accounts

            You are responsible for what is posted from your account and for keeping its password private. One person should not hold several accounts to vote, award points to themselves or bypass a restriction. Tell the moderators if you believe an account has been used without its owner's consent.

            ## What you post

            You keep the rights you had in what you write. By posting you give the forum permission to store it, show it and keep it available to readers. Do not post material you have no right to publish, other people's confidential information, or code you are not allowed to share.

            ## Documentation, SDKs and firmware

            Manuals, SDKs, firmware and development-board material are provided for use with Ingenic products. Their own licence, if one is supplied with the files, governs that use. Where no licence is supplied, use them only to develop, evaluate and support Ingenic products, and do not redistribute them.

            Downloads that need approval are granted to the account that applied. Do not pass a granted file to another party.

            ## Acceptable use

            Do not attack the service, attempt to reach accounts or data you have not been given, scrape the site at a rate that degrades it for others, or use it to distribute malware or unlawful material. Moderators may remove content or restrict an account that does.

            ## Changes

            These terms may be updated as the community and the service change. The date at the foot of this page says when they last did.

            ## Contact

            Questions about these terms can be raised in the Site Feedback category or with the forum moderators.
          MARKDOWN
        },
        zh: {
          title: "用户协议",
          body: <<~MARKDOWN,
            本协议适用于 Ingenic 开发者社区以及社区发布的文档、软件和其他资料。使用本论坛即表示你同意以下条款。

            ## 使用论坛

            论坛用于提问、反馈问题和与其他开发者交流成果。请使用分类所要求的语言发言，把问题发在合适的分类中，并在发新帖前先搜索已有内容。

            ## 账号

            你对自己账号发布的内容负责，并有责任保管好密码。不应使用多个账号刷票、给自己发放积分或规避限制。如发现账号在未经本人同意的情况下被使用，请告知版主。

            ## 你发布的内容

            你保留自己所写内容的原有权利。发布内容即表示允许论坛存储、展示并持续向读者提供该内容。请勿发布你无权公开的材料、他人的保密信息，或你不被允许分享的代码。

            ## 文档、SDK 与固件

            手册、SDK、固件和开发板资料供配合 Ingenic 产品使用。随文件提供的许可证优先适用；未附许可证的，仅可用于开发、评估和支持 Ingenic 产品，不得再分发。需要审核的下载只会授权给提交申请的账号，请勿将获准下载的文件转交他人。

            ## 合理使用

            不得攻击本服务、尝试访问未获授权的账号或数据、以影响他人使用的频率抓取站点，或利用本站传播恶意软件及违法内容。版主有权删除此类内容或限制相关账号。

            ## 协议变更

            本协议可能随社区和服务的变化而更新，最后更新日期见本页末尾。

            ## 联系我们

            对协议有疑问，可在「站点反馈」分类提出，或联系论坛版主。
          MARKDOWN
        },
      },
      "privacy" => {
        en: {
          title: "Privacy Policy",
          body: <<~MARKDOWN,
            This page explains what the Ingenic Developer Community records, why, and what you can ask it to do with that information.

            ## What we collect

            - The account details you provide when you register, such as your username, email address and, if you add one, your profile picture.
            - The topics, replies, messages and reactions you post.
            - The developer information you submit before downloading a gated resource, and the requests you make for one.
            - Technical records the server keeps to run the site: the address you connected from, the browser you used, and when.

            ## Why we keep it

            To run your account, show the forum, review download requests, moderate the community, prevent abuse and understand which parts of the site are used. Aggregate statistics are what we look at; they do not identify a person.

            ## Cookies

            The forum sets cookies to keep you signed in, to remember your reading preferences and to protect forms against cross-site requests. Cookies are not used to follow you across other sites.

            ## Who sees it

            Forum staff can see account and moderation records. A download request is seen by the reviewers of that resource. We do not sell personal information, and we share it outside the community only where the law requires it or where it is needed to provide the service.

            ## How long we keep it

            Posts stay for as long as the forum is published, because removing one breaks the threads that refer to it. Account records are kept while the account exists. Server logs are kept for a limited period and then discarded.

            ## Your choices

            You can change your profile and email address in your account settings, and you can ask an administrator to remove your account. Where the law gives you a right to see, correct or delete your information, ask the forum staff and they will help.

            ## Contact

            Privacy questions can be raised in the Site Feedback category or with the forum moderators.
          MARKDOWN
        },
        zh: {
          title: "隐私政策",
          body: <<~MARKDOWN,
            本页说明 Ingenic 开发者社区会记录哪些信息、为什么记录，以及你可以要求我们如何处理这些信息。

            ## 我们收集什么

            - 注册时填写的账号信息，如用户名、邮箱，以及你自行上传的头像。
            - 你发布的话题、回复、私信和互动记录。
            - 下载受限资源前提交的开发者信息，以及你提交的下载申请。
            - 服务器为运行站点保留的技术记录：连接地址、浏览器类型和时间。

            ## 收集的目的

            用于登录账号、展示论坛、审核下载申请、管理社区、防止滥用，以及了解站点的使用情况。我们查看的是汇总统计，不会用它识别个人。

            ## Cookie

            论坛使用 Cookie 保持登录状态、记住阅读偏好，并保护表单免受跨站请求。Cookie 不会用于在其他网站跟踪你。

            ## 谁能看到

            论坛管理人员可以查看账号与管理记录；某资源的下载申请由该资源的审核人员查看。我们不会出售个人信息，仅在法律要求或提供服务所必需时，才会在社区之外共享。

            ## 保存期限

            帖子在论坛发布期间持续保留，因为删除一条会让引用它的讨论失去上下文。账号记录在账号存续期间保留；服务器日志仅在有限期限内保留。

            ## 你的选择

            你可以在账号设置中修改资料和邮箱，也可以请管理员删除账号。若法律赋予你查询、更正或删除个人信息的权利，请联系论坛管理人员协助处理。

            ## 联系我们

            对隐私有疑问，可在「站点反馈」分类提出，或联系论坛版主。
          MARKDOWN
        },
      },
      "points-rules" => {
        en: {
          title: "Points & Benefits Rules",
          body: <<~MARKDOWN,
            Members earn contribution points by taking part in the forum and can spend them on resources in the download centre. This page is the rule for both directions.

            ## Earning points

            - Opening a topic, replying and having your reply accepted all earn points. The amounts are set in the management screen and can be changed.
            - Only posts that add to the discussion count. Deleted, hidden or spam posts do not, and points already awarded for them are taken back.
            - Weekly contribution rankings are based on the same records. A ranking can change while the week is running.

            ## Spending points

            - A resource marked with a price is unlocked for your account once the points are paid, and stays unlocked.
            - Points are not refunded when a file is removed from the download centre after you unlocked it.
            - A bounty holds points until an answer is accepted. If nobody answers before it expires, the points return to the asker.

            ## Abuse

            Points exist to reward taking part, not to be farmed. Voting for yourself with several accounts, posting filler replies, or trading points for anything outside the forum breaks these rules. Points earned that way are removed, and an account that repeats it can be restricted.

            ## Changes

            Point values and the list of resources that cost points can change. The rule in force is the one on this page when the action happened.
          MARKDOWN
        },
        zh: {
          title: "积分与权益规则",
          body: <<~MARKDOWN,
            会员通过参与论坛获得贡献积分，并在下载中心使用积分兑换资源。本页说明获得与使用两个方向的规则。

            ## 获得积分

            - 发布话题、回复以及回复被采纳都会获得积分。具体分值由管理页面配置，可随时调整。
            - 只有对讨论有贡献的内容计入积分。被删除、隐藏或判定为垃圾内容的帖子不计入，已发放的积分会被扣回。
            - 每周贡献排行依据同一套记录生成，周内的排名可能发生变化。

            ## 使用积分

            - 标注了积分价格的资源，支付后即对当前账号永久解锁。
            - 资源解锁后若从下载中心下架，积分不再退还。
            - 悬赏会先冻结相应积分，答复被采纳后支付给答复者；到期无人答复时积分退回提问者。

            ## 违规处理

            积分的目的是奖励参与，而不是被刷取。使用多个账号为自己投票、发布无意义回复，或用积分在论坛之外进行交易，都属于违规。因此获得的积分会被扣除，屡次违规的账号可能被限制。

            ## 规则变更

            积分分值和需要积分的资源列表可能调整。以行为发生时本页面的规则为准。
          MARKDOWN
        },
      },
    }.freeze

    module_function

    # The copy for one page in one language. A language with no translation of
    # its own reads the English text: a policy page that exists in the wrong
    # language is still more use than a 404 behind a footer link.
    def find(locale, slug)
      page = PAGES[slug.to_s]
      return if page.nil?

      language = locale.to_s.start_with?("zh") ? :zh : :en
      copy = page[language] || page[:en]

      { "slug" => slug.to_s, "title" => copy[:title], "body" => copy[:body] }
    end

    # One row per page per language, for the migration that puts the editable
    # copy in place. Position follows the list order so the management screen
    # starts in the order a reader would expect.
    def rows_for(locales)
      Array(locales).uniq.flat_map do |locale|
        SLUGS.each_with_index.filter_map do |slug, position|
          copy = find(locale, slug)
          copy && copy.merge("locale" => locale, "position" => position)
        end
      end
    end
  end
end
