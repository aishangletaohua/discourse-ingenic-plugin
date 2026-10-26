import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

const ENDPOINT = "/admin/plugins/discourse-ingenic/download-logs";

/**
 * Who downloaded what.
 *
 * Every other screen in this plugin is about permission — who may have a file.
 * This one is about fact, and it exists because an approval is permanent now:
 * once access is granted it stays, so the grant no longer says anything about
 * whether the file was ever collected. This is the record that does.
 *
 * Read-only on purpose. It is evidence, and an editable evidence log is not
 * evidence.
 */
export default class IngenicDownloadLog extends Component {
  @tracked logs = [];
  @tracked byResource = [];
  @tracked total = 0;
  @tracked filter = "";
  @tracked loading = true;
  @tracked error = null;

  get rows() {
    if (!this.filter) {
      return this.logs;
    }

    const wanted = String(this.filter);
    return this.logs.filter((log) => String(log.download_id) === wanted);
  }

  @action
  async load() {
    await this.#fetch();
  }

  @action
  async selectResource(event) {
    this.filter = event.target.value;
    await this.#fetch();
  }

  async #fetch() {
    this.loading = true;
    this.error = null;

    const params = new URLSearchParams();
    if (this.filter) {
      params.set("download_id", this.filter);
    }

    const query = params.toString();
    const url = `${ENDPOINT}${query ? `?${query}` : ""}`;

    try {
      const response = await ajax(url);
      this.logs = response.logs ?? [];
      this.total = response.total ?? 0;
      // The summary is of the whole log, so it is only replaced by a response
      // that also covered the whole log.
      if (!query) {
        this.byResource = response.by_resource ?? [];
      }
    } catch {
      this.error = i18n("ingenic.save_failed");
      this.logs = [];
    } finally {
      this.loading = false;
    }
  }

  <template>
    <div class="ingenic-admin-panel" {{didInsert this.load}}>
      {{#if this.error}}
        <p class="ingenic-admin-note ingenic-admin-note--error">{{this.error}}</p>
      {{/if}}

      <p class="ingenic-admin-note">
        {{i18n "ingenic.logs.total" count=this.total}}
      </p>

      <div class="ingenic-admin__toolbar">
        <label class="ingenic-admin-inline-field">
          <span>{{i18n "ingenic.logs.filter"}}</span>
          <select {{on "change" this.selectResource}}>
            <option value="">{{i18n "ingenic.logs.all_resources"}}</option>
            {{#each this.byResource as |row|}}
              <option value={{row.download_id}}>
                {{row.name}} ({{row.count}})
              </option>
            {{/each}}
          </select>
        </label>
      </div>

      {{#if this.loading}}
        <p class="ingenic-admin-note">{{i18n "ingenic.logs.loading"}}</p>
      {{else if this.rows.length}}
        <table class="ingenic-admin-table">
          <thead>
            <tr>
              <th>{{i18n "ingenic.logs.columns.taken_at"}}</th>
              <th>{{i18n "ingenic.logs.columns.account"}}</th>
              <th>{{i18n "ingenic.logs.columns.resource"}}</th>
              <th>{{i18n "ingenic.logs.columns.version"}}</th>
              <th>{{i18n "ingenic.logs.columns.address"}}</th>
            </tr>
          </thead>
          <tbody>
            {{#each this.rows as |log|}}
              <tr>
                <td>{{log.created_at}}</td>
                <td>{{if log.anonymised (i18n "ingenic.logs.anonymised") log.username}}</td>
                <td>{{log.resource_name}}</td>
                <td>{{log.version}}</td>
                <td>{{if log.anonymised "—" log.ip_address}}</td>
              </tr>
            {{/each}}
          </tbody>
        </table>
      {{else}}
        <p>{{i18n "ingenic.logs.empty"}}</p>
      {{/if}}
    </div>
  </template>
}
