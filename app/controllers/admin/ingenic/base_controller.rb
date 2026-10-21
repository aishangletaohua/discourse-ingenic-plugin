# frozen_string_literal: true

module Admin
  module Ingenic
    class BaseController < ::ApplicationController
      requires_login
      requires_plugin "discourse-ingenic"

      private

      def authorize_ingenic!(record = nil, permissions: false)
        allowed = if permissions
          guardian.can_manage_ingenic_permissions?
        else
          record && ::Ingenic::PermissionResolver.new(current_user).can_manage?(record)
        end
        raise Discourse::NotFound unless allowed
      end

      # A record with a parent is created under the scope that has to permit it.
      # A record without one has no scope of its own, so it belongs to whoever
      # holds the screen-wide feature — or to an administrator.
      def authorize_create!(parent = nil, feature: nil)
        resolver = ::Ingenic::PermissionResolver.new(current_user)
        allowed = if parent
          resolver.can_manage?(parent)
        elsif feature
          resolver.can_manage_feature?(feature)
        else
          current_user.admin?
        end
        raise Discourse::NotFound unless allowed
      end

      # A coarse check for screens whose records are not filed under a product
      # or a board: the download queue, the points ledger, the site blocks. The
      # feature is one of `IngenicGroupPermission::FEATURES`.
      def authorize_ingenic_feature!(feature)
        allowed = ::Ingenic::PermissionResolver.new(current_user).can_manage_feature?(feature)
        raise Discourse::NotFound unless allowed
      end

      # A record that is about to be filed under a chip, in one named domain.
      # The whole-screen grant still counts; the chip grant is what lets one
      # person look after T33's downloads without being able to touch T32 or
      # T33's documentation.
      def authorize_area_create!(record, area)
        resolver = ::Ingenic::PermissionResolver.new(current_user)
        allowed = resolver.can_manage_feature?(area)

        unless allowed
          product = record.product if record.respond_to?(:product)
          allowed = product.present? && resolver.can_manage_area?(product, area)
        end

        raise Discourse::NotFound unless allowed
      end

      # Site-wide content — the homepage slots, the footer, the classification
      # list, the download record — is not filed under a product or a board, so
      # there is no scope for a content manager to be granted over it. It is an
      # administrator's, and this says so rather than leaving each action to
      # discover that a record it cannot describe falls through to nobody.
      def authorize_admin_only!
        raise Discourse::NotFound unless current_user.admin?
      end

      def render_record_error(record)
        render_json_error(record)
      end

      def boolean_param(value, default = false)
        return default if value.nil?

        ActiveModel::Type::Boolean.new.cast(value)
      end
    end
  end
end
