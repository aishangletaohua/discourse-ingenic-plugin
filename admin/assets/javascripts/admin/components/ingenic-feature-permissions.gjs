import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { debounce } from "@ember/runloop";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

const ENDPOINT = "/admin/plugins/discourse-ingenic/feature-permissions";
const PRINCIPALS = "/admin/plugins/discourse-ingenic/permission-principals";

/**
 * Who may manage which screen, once for accounts and once for groups.
 *
 * The two matrices mean the same thing: a tick is "everything on this screen".
 * They are drawn apart because they are used differently. A group is the batch
 * layer — one click gives a team a screen and keeps giving it to everyone who
 * joins. An account is the exception: one contractor, one chip owner, one
 * engineer covering downloads for a quarter, none of whom deserves a group of
 * their own.
 *
 * A "screen" is all of it. The per-chip grants below this component stay
 * narrower: an account can be given T33's documentation without the
 * documentation screen at all, and a group ticked here can still lend a single
 * product to somebody it does not contain.
 *
 * Only custom groups are offered. The automatic ones (staff, trust levels,
 * everyone) are membership the site maintains; a tick on `everyone` would hand
 * a management screen to every visitor, which is not a decision a checkbox
 * should make by accident. Accounts are searched by name rather than picked
 * from a list, because the account table is the whole forum and the answer to
 * "who?" is a name, not an id.
 */
export default class IngenicFeaturePermissions extends Component {
  @tracked groups = this.args.groups.map((group) => ({
    ...group,
    features: [...group.features],
  }));
  @tracked users = (this.args.users ?? []).map((user) => ({
    ...user,
    features: [...user.features],
  }));
  @tracked query = "";
  @tracked results = [];
  @tracked busy = false;
  @tracked message = null;

  get features() {
    return this.args.features;
  }

  get assignableResults() {
    const added = new Set(this.users.map((user) => user.id));
    return this.results.filter((user) => !added.has(user.id));
  }

  get hasUsers() {
    return this.users.length > 0;
  }

  get hasGroups() {
    return this.groups.length > 0;
  }

  featureLabel(feature) {
    return i18n(`ingenic.group_permissions.features.${feature}`);
  }

  accountLabel(user) {
    return user.name?.trim() ? `${user.name} (@${user.username})` : `@${user.username}`;
  }

  has(principal, feature) {
    return principal.features.includes(feature);
  }

  // `fn` does not bind `this`: a plain method here is called unbound and the
  // assignment to `this.users` below throws. `@action` is what makes the
  // handler carry its component.
  @action
  toggle(principal, feature) {
    principal.features = this.has(principal, feature)
      ? principal.features.filter((item) => item !== feature)
      : [...principal.features, feature];

    if (this.users.includes(principal)) {
      this.users = [...this.users];
    } else {
      this.groups = [...this.groups];
    }
  }

  @action
  removeUser(user) {
    this.users = this.users.filter((row) => row.id !== user.id);
  }

  @action
  search(event) {
    this.query = event.target.value;
    debounce(this, this.runSearch, 250);
  }

  async runSearch() {
    const query = this.query.trim();

    if (!query) {
      this.results = [];
      return;
    }

    try {
      const response = await ajax(PRINCIPALS, { data: { q: query } });
      this.results = response.users ?? [];
    } catch {
      this.results = [];
    }
  }

  @action
  addUser(user) {
    this.users = [
      ...this.users,
      {
        id: user.id,
        username: user.username,
        name: user.name,
        features: [],
      },
    ];
    this.query = "";
    this.results = [];
  }

  @action
  async save() {
    this.busy = true;
    this.message = null;

    // The server replaces the table with this snapshot, so every account that
    // currently holds a grant is in the list: removing one row here is how a
    // grant is taken away.
    const grants = [
      ...this.groups.map((group) => ({
        type: "group",
        id: group.id,
        features: group.features,
      })),
      ...this.users.map((user) => ({
        type: "user",
        id: user.id,
        features: user.features,
      })),
    ];

    try {
      await ajax(ENDPOINT, {
        type: "PUT",
        data: { grants: JSON.stringify(grants) },
      });
      this.message = i18n("ingenic.saved");
    } catch (error) {
      this.message =
        error.jqXHR?.responseJSON?.errors?.join(", ") ||
        i18n("ingenic.save_failed");
    } finally {
      this.busy = false;
    }
  }

  <template>
    <section class="ingenic-permission-section">
      <h3 class="ingenic-permission-section__title">
        {{i18n "ingenic.permissions.accounts_heading"}}
      </h3>
      <p class="ingenic-admin-form__hint">
        {{i18n "ingenic.permissions.accounts_hint"}}
      </p>

      <div class="ingenic-account-picker">
        <input
          type="text"
          class="ingenic-account-picker__input"
          value={{this.query}}
          placeholder={{i18n "ingenic.permissions.search_accounts"}}
          aria-label={{i18n "ingenic.permissions.search_accounts"}}
          {{on "input" this.search}}
        />

        {{#if this.assignableResults.length}}
          <ul class="ingenic-account-picker__results">
            {{#each this.assignableResults as |user|}}
              <li>
                <button
                  type="button"
                  class="btn btn-small"
                  {{on "click" (fn this.addUser user)}}
                >
                  {{this.accountLabel user}}
                </button>
              </li>
            {{/each}}
          </ul>
        {{/if}}
      </div>

      {{#if this.hasUsers}}
        <div class="ingenic-matrix-wrap">
          <table class="ingenic-admin-table ingenic-matrix">
            <thead>
              <tr>
                <th>{{i18n "ingenic.permissions.account"}}</th>
                {{#each this.features as |feature|}}
                  <th class="ingenic-matrix__feature">
                    {{this.featureLabel feature}}
                  </th>
                {{/each}}
                <th></th>
              </tr>
            </thead>
            <tbody>
              {{#each this.users as |user|}}
                <tr>
                  <td>
                    <strong>{{this.accountLabel user}}</strong>
                  </td>
                  {{#each this.features as |feature|}}
                    <td class="ingenic-matrix__cell">
                      <input
                        type="checkbox"
                        checked={{this.has user feature}}
                        aria-label={{this.featureLabel feature}}
                        {{on "change" (fn this.toggle user feature)}}
                      />
                    </td>
                  {{/each}}
                  <td>
                    <button
                      type="button"
                      class="btn btn-small btn-flat"
                      {{on "click" (fn this.removeUser user)}}
                    >
                      {{i18n "ingenic.permissions.remove_account"}}
                    </button>
                  </td>
                </tr>
              {{/each}}
            </tbody>
          </table>
        </div>
      {{else}}
        <p class="ingenic-admin-note">
          {{i18n "ingenic.permissions.no_accounts"}}
        </p>
      {{/if}}
    </section>

    <section class="ingenic-permission-section">
      <h3 class="ingenic-permission-section__title">
        {{i18n "ingenic.permissions.groups_heading"}}
      </h3>
      <p class="ingenic-admin-form__hint">
        {{i18n "ingenic.permissions.groups_hint"}}
      </p>

      {{#if this.hasGroups}}
        <div class="ingenic-matrix-wrap">
          <table class="ingenic-admin-table ingenic-matrix">
            <thead>
              <tr>
                <th>{{i18n "ingenic.group_permissions.group"}}</th>
                {{#each this.features as |feature|}}
                  <th class="ingenic-matrix__feature">
                    {{this.featureLabel feature}}
                  </th>
                {{/each}}
              </tr>
            </thead>
            <tbody>
              {{#each this.groups as |group|}}
                <tr>
                  <td>
                    <strong>{{group.name}}</strong>
                    <div class="ingenic-admin-list__meta">
                      {{i18n "ingenic.group_permissions.members" count=group.members}}
                    </div>
                  </td>
                  {{#each this.features as |feature|}}
                    <td class="ingenic-matrix__cell">
                      <input
                        type="checkbox"
                        checked={{this.has group feature}}
                        aria-label={{this.featureLabel feature}}
                        {{on "change" (fn this.toggle group feature)}}
                      />
                    </td>
                  {{/each}}
                </tr>
              {{/each}}
            </tbody>
          </table>
        </div>
      {{else}}
        <p class="ingenic-admin-note">
          {{i18n "ingenic.group_permissions.empty"}}
        </p>
      {{/if}}
    </section>

    <div class="ingenic-admin-form__actions">
      <button
        class="btn btn-primary"
        type="button"
        disabled={{this.busy}}
        {{on "click" this.save}}
      >
        {{i18n "ingenic.permissions.save_matrix"}}
      </button>
      {{#if this.message}}
        <span class="ingenic-admin-note">{{this.message}}</span>
      {{/if}}
    </div>
  </template>
}
