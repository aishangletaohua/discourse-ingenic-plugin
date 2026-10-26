# frozen_string_literal: true

module Ingenic
  # Answers one question: may this account download this resource right now, and
  # if not, what is the next thing they have to do?
  #
  # Every surface asks it the same way — the listing that decides which button
  # to draw, the endpoint that serves the bytes, and the admin queue — so there
  # is no path on which the button and the file disagree.
  class DownloadAccess
    # anonymous       not signed in
    # needs_profile   signed in, developer information not on file
    # needs_request   eligible to apply and has not
    # pending         applied, waiting on the team
    # rejected        applied, turned down
    # needs_points    cleared, but the resource costs points they have not got
    # granted         may download
    STATES = %i[anonymous needs_profile needs_request pending rejected needs_points granted].freeze

    Result = Struct.new(:state, :download, :request, :grant, keyword_init: true) do
      def allowed?
        state == :granted
      end

      def gated?
        state != :granted
      end
    end

    # Everything the policy needs to know about one account, read once.
    #
    # A listing asks the same question about every resource on the page, and
    # answering it the ordinary way would be three queries per card. Loading the
    # facts up front keeps the page's cost independent of how many resources are
    # on it, without giving the listing its own copy of the rules.
    class Context
      attr_reader :profile, :balance, :unlocked_download_ids

      def initialize(user)
        @user = user
        # A visitor with no account has no points and has unlocked nothing.
        @balance = 0
        @unlocked_download_ids = Set.new
        return if user.nil?

        @profile = IngenicDeveloperProfile.for(user)
        @grants = IngenicDownloadGrant.active.where(user_id: user.id).index_by(&:download_id)
        @requests =
          IngenicDownloadRequest
            .where(user_id: user.id)
            .recent
            .group_by(&:download_id)
            .transform_values(&:first)
        @balance = IngenicPointBalance.total_for(user)
        @unlocked_download_ids = Ingenic::Points.unlocked_download_ids(user)
      end

      def grant_for(download)
        @grants && @grants[download.id]
      end

      def request_for(download)
        @requests && @requests[download.id]
      end
    end

    # Every resource on a page, decided in one pass.
    def self.for_list(user, downloads)
      context = Context.new(user)
      downloads.map { |download| new(user, download, context: context).result }
    end

    def initialize(user, download, context: nil)
      @user = user
      @download = download
      @context = context
    end

    # Collects the price of a resource, if it has one.
    #
    # Called from the two branches of the delivery endpoint that actually
    # release a file, and deliberately not from the third: a resource somebody
    # is cleared for and which then turns out to be missing from storage must
    # not cost them anything.
    #
    #   :free         nothing to pay, which is every resource until one is
    #                 priced and every resource when points are switched off
    #   :spent        paid now
    #   :already      paid on an earlier visit, so nothing more is owed
    #   :insufficient short, and nothing was written
    def self.charge(user, download)
      return :free unless download.costs_points? && Ingenic::Points.enabled?

      Ingenic::Points.spend(
        user: user,
        points: download.point_cost,
        subject: download,
        reason: I18n.t("ingenic.points.unlocked", resource: download.name),
      )
    end

    def result
      clearance = clearance_result
      return clearance unless clearance.state == :granted
      return clearance if unlocked?
      return clearance if balance >= download.point_cost

      Result.new(state: :needs_points, download: download)
    end

    private

    attr_reader :user, :download, :context

    # Where the account stands on the resource's own terms, before its price.
    # The price is the last question asked, because a resource somebody has not
    # been cleared for is not for sale at any number.
    def clearance_result
      return Result.new(state: :anonymous, download: download) if user.nil?
      return Result.new(state: :granted, download: download) if download.login_only?
      # A stored profile written before the form gained a question is not a
      # completed one; the visitor is sent back to the form rather than through
      # it.
      if profile.nil? || !profile.complete?
        return Result.new(state: :needs_profile, download: download)
      end
      return Result.new(state: :granted, download: download) if download.form_required?

      # Approval tier: an active grant is the whole answer. Everything below it
      # only describes where the applicant is in the queue.
      return Result.new(state: :granted, download: download, grant: grant) if grant

      request = latest_request

      state =
        case request&.status
        when IngenicDownloadRequest::PENDING then :pending
        when IngenicDownloadRequest::REJECTED then :rejected
        else :needs_request
        end

      Result.new(state: state, download: download, request: request)
    end

    # Whether this resource has already been paid for.
    #
    # Paying is a one-off. What was bought once stays theirs to download again,
    # so a firmware image fetched a second time on a flaky connection is not
    # charged for twice — and the ledger's own record of the purchase is what
    # says so, rather than a second table that could disagree with it.
    def unlocked?
      return true unless download.costs_points?
      return true unless Ingenic::Points.enabled?

      unlocked_download_ids.include?(download.id)
    end

    def unlocked_download_ids
      context ? context.unlocked_download_ids : Ingenic::Points.unlocked_download_ids(user)
    end

    def balance
      context ? context.balance : IngenicPointBalance.total_for(user)
    end

    def profile
      return context.profile if context

      @profile ||= IngenicDeveloperProfile.for(user)
    end

    def grant
      return context.grant_for(download) if context

      @grant ||= IngenicDownloadGrant.active.find_by(user_id: user.id, download_id: download.id)
    end

    # The most recent application, whatever its outcome. A rejection is
    # information the applicant is owed; hiding it behind a fresh "Apply" button
    # would let them reapply into a queue that already answered them.
    def latest_request
      return context.request_for(download) if context

      @latest_request ||=
        IngenicDownloadRequest.where(user_id: user.id, download_id: download.id).recent.first
    end
  end
end
