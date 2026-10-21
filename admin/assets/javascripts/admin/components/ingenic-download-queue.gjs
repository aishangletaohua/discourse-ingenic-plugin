import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { ajax } from "discourse/lib/ajax";
import { eq } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";

const ENDPOINT = "/admin/plugins/discourse-ingenic/download-requests";

/**
 * Applications for access-restricted downloads.
 *
 * Approving is what writes the grant, and the server does both in one
 * transaction, so the row this replaces is the server's answer rather than a
 * guess made here about what approving implies.
 *
 * A note is offered on both answers: it is the only place the team's reasoning
 * is recorded for the applicant to read, and the mail that follows quotes it.
 */
export default class IngenicDownloadQueue extends Component {
  @tracked requests = this.args.requests ?? [];
  @tracked busyId = null;
  @tracked error = null;

  get pendingCount() {
    return this.requests.filter((request) => request.status === "pending").length;
  }

  @action
  async decide(request, decision, event) {
    event.preventDefault();
    this.busyId = request.id;
    this.error = null;

    // The click lands on the button, so the form is reached through it rather
    // than through event.target.
    const form = event.target.form;
    const data = {
      note: form?.elements.note?.value ?? "",
      expires_at: form?.elements.expires_at?.value ?? "",
    };

    try {
      const response = await ajax(`${ENDPOINT}/${request.id}/${decision}`, {
        type: "PUT",
        data,
      });
      const decided = response.request;
      this.requests = this.requests.map((item) =>
        item.id === decided.id ? decided : item
      );
    } catch (failure) {
      this.error =
        failure?.jqXHR?.responseJSON?.errors?.join(", ") ||
        i18n("ingenic.save_failed");
    } finally {
      this.busyId = null;
    }
  }

  <template>
    <div class="ingenic-admin__queue">
      {{#if this.error}}<p class="ingenic-admin-note ingenic-admin-note--error">{{this.error}}</p>{{/if}}

      <p class="ingenic-admin-note">
        {{i18n "ingenic.downloads.queue_pending" count=this.pendingCount}}
      </p>

      <div class="ingenic-admin-list">
        {{#each this.requests as |request|}}
          <section class="ingenic-admin-list__row">
            <div>
              <strong>
                {{#if request.username}}
                  {{request.username}}
                {{else}}
                  {{i18n "ingenic.deleted_member"}}
                {{/if}}
              </strong>
              <span class="ingenic-admin-list__badge">{{request.status}}</span>
              <div class="ingenic-admin-list__meta">
                {{request.download_name}} · {{request.user_email}} · {{request.created_at}}
              </div>
              {{#if request.profile_summary}}
                <div class="ingenic-admin-list__meta">{{request.profile_summary}}</div>
              {{/if}}
              {{#if request.message}}
                <p>{{request.message}}</p>
              {{/if}}
              {{#if request.review_note}}
                <div class="ingenic-admin-list__meta">
                  {{i18n "ingenic.downloads.review_note"}}: {{request.review_note}}
                </div>
              {{/if}}
            </div>

            {{#if (eq request.status "pending")}}
              <form class="ingenic-admin-form ingenic-admin-form--inline">
                <label>
                  <span>{{i18n "ingenic.downloads.note"}}</span>
                  <input name="note" />
                </label>
                <label>
                  <span>{{i18n "ingenic.downloads.expires_at"}}</span>
                  <input type="date" name="expires_at" />
                </label>
                <div class="ingenic-admin__toolbar">
                  <button
                    class="btn btn-primary"
                    type="button"
                    disabled={{eq this.busyId request.id}}
                    {{on "click" (fn this.decide request "approve")}}
                  >
                    {{i18n "ingenic.downloads.approve"}}
                  </button>
                  <button
                    class="btn btn-danger"
                    type="button"
                    disabled={{eq this.busyId request.id}}
                    {{on "click" (fn this.decide request "reject")}}
                  >
                    {{i18n "ingenic.downloads.reject"}}
                  </button>
                </div>
              </form>
            {{/if}}
          </section>
        {{else}}
          <p>{{i18n "ingenic.downloads.no_requests"}}</p>
        {{/each}}
      </div>
    </div>
  </template>
}
