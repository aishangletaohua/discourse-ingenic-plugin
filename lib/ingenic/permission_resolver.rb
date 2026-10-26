# frozen_string_literal: true

module Ingenic
  class PermissionResolver
    # The management screen a class belongs to. A class that is not here — a
    # download, say — is still reachable through a per-record grant, but has no
    # feature that says "all of them"; `IngenicDownload` is in the map because a
    # group trusted with the download screen is trusted with every resource on
    # it, and the listing has to agree.
    FEATURE_FOR_CLASS = {
      "IngenicProduct" => "documentation",
      "IngenicDocVersion" => "documentation",
      "IngenicDocPage" => "documentation",
      "IngenicBoard" => "boards",
      "IngenicDownload" => "downloads",
    }.freeze

    # Which job a record belongs to when nobody has named one. A product is the
    # exception: it is shared by all three, so the caller passes the area it
    # means and the default here is only the documentation screen's reading of
    # "may this person manage this chip".
    # Literal strings, not `IngenicPermission::DOCUMENTATION`: this file is
    # required at plugin activation, before the `after_initialize` block has
    # loaded the models those constants live in.
    AREA_FOR_CLASS = {
      "IngenicProduct" => "documentation",
      "IngenicDocVersion" => "documentation",
      "IngenicDocPage" => "documentation",
      "IngenicBoard" => "boards",
      "IngenicDownload" => "downloads",
    }.freeze

    def initialize(user)
      @user = user
    end

    def admin?
      @user&.admin?
    end

    # The whole-screen grants this account holds, from either principal: its
    # own rows or any group it belongs to. One query rather than one per
    # feature, because the serializer asks for all six on every page load and
    # the navigation decides what to offer from the answer.
    #
    # The `everyone` auto-group is included for the same reason it is in
    # `group_ids` below: an administrator who grants it to everyone means it.
    def features
      return @features if defined?(@features)

      @features =
        if !@user
          []
        elsif admin?
          IngenicFeaturePermission::FEATURES
        else
          feature_grants.distinct.pluck(:feature)
        end
    end

    def can_manage_feature?(feature)
      return true if admin?
      return false unless @user

      features.include?(feature.to_s)
    end

    def can_manage?(record)
      can_manage_area?(record, AREA_FOR_CLASS[record.class.name])
    end

    # The per-chip question in one domain: may this account look after this
    # product's documentation, downloads or boards? A whole-screen grant counts
    # in every domain, because it is the same trust the screen represents.
    def can_manage_area?(record, area)
      return true if admin?
      return false if @user.nil? || record.nil?

      area = area.to_s
      return false unless IngenicPermission::AREAS.include?(area)
      return true if can_manage_feature?(area)

      scopes = scopes_for(record, area)
      scopes.any? do |resource_type, resource_ids|
        grants_for(resource_type, area).where(resource_id: resource_ids).exists?
      end
    end

    def visible_ids(klass)
      return klass.all if admin?

      feature = FEATURE_FOR_CLASS[klass.name]
      return klass.all if feature && can_manage_feature?(feature)

      case klass.name
      when "IngenicDownload"
        visible_downloads
      when "IngenicBoard"
        visible_boards
      when "IngenicDocVersion"
        direct_ids = grants_for("IngenicDocVersion", IngenicPermission::DOCUMENTATION).pluck(:resource_id)
        product_ids =
          descendant_ids(
            IngenicProduct,
            grants_for("IngenicProduct", IngenicPermission::DOCUMENTATION).pluck(:resource_id),
          )
        product_version_ids = IngenicDocVersion.where(product_id: product_ids).pluck(:id)
        klass.where(id: direct_ids + product_version_ids)
      when "IngenicDocPage"
        direct_ids = grants_for("IngenicDocPage", IngenicPermission::DOCUMENTATION).pluck(:resource_id)
        product_ids =
          descendant_ids(
            IngenicProduct,
            grants_for("IngenicProduct", IngenicPermission::DOCUMENTATION).pluck(:resource_id),
          )
        product_page_ids =
          IngenicDocPage.where(
            version_id: IngenicDocVersion.where(product_id: product_ids).select(:id),
          ).pluck(:id)
        page_ids = descendant_ids(IngenicDocPage, direct_ids)
        klass.where(id: page_ids + product_page_ids)
      else
        product_ids =
          descendant_ids(
            IngenicProduct,
            grants_for("IngenicProduct", IngenicPermission::DOCUMENTATION).pluck(:resource_id),
          )
        direct_ids = grants_for(klass.name, IngenicPermission::DOCUMENTATION).pluck(:resource_id)
        return klass.none if direct_ids.empty? && product_ids.empty?

        klass.where(id: descendant_ids(klass, direct_ids) + product_ids)
      end
    end

    def can_manage_permissions?
      admin?
    end

    # Whether a screen has anything this account may manage, without requiring
    # the whole-screen grant. The plugin's admin navigation asks this so a
    # downloads manager is not offered an empty documentation table: having
    # *some* grant is not the same as having one in this area.
    def can_manage_any_area?(area)
      return true if admin?
      return false unless @user
      return true if can_manage_feature?(area)

      IngenicPermission.where(permission: "manage", area: area.to_s)
        .where("user_id = :user_id OR group_id IN (:group_ids)", user_id: @user.id, group_ids: group_ids)
        .exists?
    end

    def can_manage_any_content?
      return true if admin?
      return false unless @user

      return true if feature_grants.exists?

      IngenicPermission.where(permission: "manage")
        .where("user_id = :user_id OR group_id IN (:group_ids)", user_id: @user.id, group_ids: group_ids)
        .exists?
    end

    private

    attr_reader :user

    # Downloads and boards are filed under a catalogue row by foreign key.
    # Both listings have to agree with what `can_manage_area?` would say about
    # one record, or a scoped manager sees an empty page for a chip they were
    # just granted.
    def visible_downloads
      direct_ids = grants_for("IngenicDownload", IngenicPermission::DOWNLOADS).pluck(:resource_id)
      product_ids =
        descendant_ids(
          IngenicProduct,
          grants_for("IngenicProduct", IngenicPermission::DOWNLOADS).pluck(:resource_id),
        )

      IngenicDownload.where(id: direct_ids).or(IngenicDownload.where(product_id: product_ids))
    end

    def visible_boards
      direct_ids = grants_for("IngenicBoard", IngenicPermission::BOARDS).pluck(:resource_id)
      product_ids =
        descendant_ids(
          IngenicProduct,
          grants_for("IngenicProduct", IngenicPermission::BOARDS).pluck(:resource_id),
        )

      IngenicBoard.where(id: direct_ids).or(IngenicBoard.where(product_id: product_ids))
    end

    def group_ids
      # `everyone` is an automatic group rather than a row anybody joins, and its
      # id is only known once Discourse has seeded its own groups — so the
      # constant to reach for is the one naming it. `Group::EVERYONE_GROUP_ID`
      # reads like it ought to exist and never has: written that way this raised
      # `NameError` on the first request that asked who may manage anything,
      # which is a 500 for a plain member opening a screen they should simply
      # have been kept out of.
      @group_ids ||= @user.groups.pluck(:id) + [Group::AUTO_GROUPS[:everyone]]
    end

    # Every whole-screen row that applies to this account. Used by both
    # `features` and `can_manage_any_content?`, so the two cannot disagree
    # about what counts as a grant.
    def feature_grants
      IngenicFeaturePermission
        .where(user_id: @user.id)
        .or(IngenicFeaturePermission.where(group_id: group_ids))
    end

    def grants_for(resource_type, area)
      IngenicPermission.where(permission: "manage", resource_type: resource_type, area: area)
        .where("user_id = :user_id OR group_id IN (:group_ids)", user_id: @user.id, group_ids: group_ids)
    end

    def scopes_for(record, area)
      case record
      when IngenicProduct
        [["IngenicProduct", product_ancestors(record).map(&:id)]]
      when IngenicDocVersion
        [["IngenicProduct", product_ancestors(record.product).map(&:id)]]
      when IngenicDocPage
        [
          ["IngenicProduct", product_ancestors(record.version.product).map(&:id)],
          ["IngenicDocPage", page_ancestors(record).map(&:id)],
        ]
      when IngenicBoard
        scopes = [["IngenicBoard", [record.id]]]
        scopes << ["IngenicProduct", product_ancestors(record.product).map(&:id)] if record.product
        scopes
      when IngenicDownload
        scopes = [["IngenicDownload", [record.id]]]
        scopes << ["IngenicProduct", product_ancestors(record.product).map(&:id)] if record.product
        scopes
      else
        [[record.class.name, [record.id]]]
      end
    end

    def product_ancestors(product)
      result = []
      while product
        result << product
        product = product.parent
      end
      result
    end

    def page_ancestors(page)
      result = []
      while page
        result << page
        page = page.parent
      end
      result
    end

    # Every id in the subtree, the given roots included. Walked one generation
    # at a time and only over ids not already seen: asking for the children of
    # the whole accumulated set re-finds the generation just added, because a
    # child's parent is still in the set, and grows the result forever.
    def descendant_ids(klass, ids)
      return ids if klass == IngenicBoard
      return [] if ids.blank?

      model =
        case klass.name
        when "IngenicProduct"
          IngenicProduct
        when "IngenicDocPage"
          IngenicDocPage
        else
          return ids
        end

      seen = ids.uniq
      frontier = seen

      loop do
        children = model.where(parent_id: frontier).pluck(:id) - seen
        break if children.empty?

        seen.concat(children)
        frontier = children
      end

      seen
    end
  end
end
