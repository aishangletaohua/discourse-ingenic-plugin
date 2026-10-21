import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

const ENDPOINT = "/admin/plugins/discourse-ingenic/download-grants";

/**
 * Who currently holds access to which restricted resource.
 *
 * Revoked grants stay in the list rather than disappearing: the row is the
 * record that someone was once let in, and hiding it would leave the only trace
 * of that decision in the request it came from.
 */
export default class IngenicGrantList extends Component {
  @tracked grants = this.args.grants ?? [];
  @tracked error = null;

  @action
  async revoke(grant, event) {
    event.preventDefault();
    this.error = null;

    try {
      const response = await ajax(`${ENDPOINT}/${grant.id}`, { type: "DELETE" });
      const revoked = response.grant;
      this.grants = this.grants.map((item) =>
        item.id === revoked.id ? revoked : item
      );
    } catch (failure) {
      this.error =
        failure?.jqXHR?.responseJSON?.errors?.join(", ") ||
        i18n("ingenic.save_failed");
    }
  }

  <template>
    <div class="ingenic-admin-panel">
      {{#if this.error}}<p class="ingenic-admin-note ingenic-admin-note--error">{{this.error}}</p>{{/if}}

      <div class="ingenic-admin-list">
        {{#each this.grants as |grant|}}
          <section class="ingenic-admin-list__row">
            <div>
              <strong>
                {{#if grant.username}}
                  {{grant.username}}
                {{else}}
                  {{i18n "ingenic.deleted_member"}}
                {{/if}}
              </strong>
              <div class="ingenic-admin-list__meta">
                {{grant.download_name}} ·
                {{#if grant.active}}
                  {{i18n "ingenic.downloads.grant_active"}}
                {{else}}
                  {{i18n "ingenic.downloads.grant_revoked"}}
                {{/if}}
                {{#if grant.expires_at}}· {{grant.expires_at}}{{/if}}
              </div>
              {{#if grant.note}}
                <div class="ingenic-admin-list__meta">{{grant.note}}</div>
              {{/if}}
            </div>
            {{#if grant.active}}
              <div class="ingenic-admin__toolbar">
                <button
                  class="btn btn-danger"
                  type="button"
                  {{on "click" (fn this.revoke grant)}}
                >
                  {{i18n "ingenic.revoke"}}
                </button>
              </div>
            {{/if}}
          </section>
        {{else}}
          <p>{{i18n "ingenic.downloads.no_grants"}}</p>
        {{/each}}
      </div>
    </div>
  </template>
}
