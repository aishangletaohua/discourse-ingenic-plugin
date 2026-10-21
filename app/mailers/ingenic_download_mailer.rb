# frozen_string_literal: true
require_dependency "email/build_email_helper"

require_dependency "email/message_builder"

# Emails the download centre sends.
#
# Bodies and subjects come from locale keys rather than from view templates:
# that is the mechanism `Email::MessageBuilder` already implements for mailers
# whose text lives in `server.yml`, and it avoids a plugin needing its own view
# path appended to ActionMailer.
class IngenicDownloadMailer < ActionMailer::Base
  include Email::BuildEmailHelper

  # To the team, when a developer applies for a gated resource.
  def request_received(to_address, request)
    build_email(
      to_address,
      template: "ingenic_download_request_received",
      applicant_username: request.user.username,
      applicant_name: request.user.name.presence || request.user.username,
      resource_name: request.download.name,
      resource_product: request.download.product&.name,
      resource_version: request.download.version,
      applicant_message: request.message,
      profile_summary: profile_summary(request.user),
      review_url: "#{Discourse.base_url}/admin/plugins/discourse-ingenic/downloads",
    )
  end

  # To the applicant, when the team decides.
  def request_decided(to_address, request)
    # Built in the applicant's language, the way core's own mailers are. The
    # template's headings and the fallback note below have to agree, and a
    # Chinese sentence under an English heading is worse than either alone.
    I18n.with_locale(request.user.effective_locale) do
      build_email(
        to_address,
        template:
          "ingenic_download_request_#{request.approved? ? "approved" : "rejected"}",
        recipient_username: request.user.username,
        resource_name: request.download.name,
        # The template always prints the "Notes from the team" heading, so a
        # decision made without a note would otherwise leave a label pointing
        # at nothing.
        review_note: request.review_note.presence || I18n.t("ingenic_download_request_no_note"),
        downloads_url: "#{Discourse.base_url}/ingenic/downloads",
      )
    end
  end

  private

  def profile_summary(user)
    profile = IngenicDeveloperProfile.for(user)
    profile&.summary(limit: 4).presence || "-"
  end
end
