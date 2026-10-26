# frozen_string_literal: true

module Jobs
  # Forgets who took a file, once the answer has stopped being useful.
  #
  # A delivery log exists so the team can answer "who collected this gated
  # file" while the question is live. The account name, account id, address and
  # browser are all answers about a person, and keeping them forever turns an
  # audit trail into a permanent record of individuals who may long since have
  # left. After the retention window the row stays — the resource, the version
  # and the moment are still worth counting — and the identifying columns are
  # cleared. Clearing `username` alone would not be enough: `user_id` still
  # points at the account, so both go together, as do the address and browser.
  #
  # Rows already disowned by a deleted account are swept too; the update is
  # idempotent and cheap.
  class IngenicDownloadLogRetention < ::Jobs::Scheduled
    every 1.day

    def execute(_args)
      return unless SiteSetting.ingenic_enabled

      months = SiteSetting.ingenic_download_log_retention_months.to_i
      return if months <= 0

      cutoff = months.months.ago
      cleared =
        IngenicDownloadLog.where(created_at: ...cutoff).update_all(
          username: nil,
          user_id: nil,
          ip_address: nil,
          user_agent: nil,
        )

      Rails.logger.info(
        "Ingenic: cleared identifying columns on #{cleared} download logs older than #{months} months",
      ) if cleared.positive?
    end
  end
end
