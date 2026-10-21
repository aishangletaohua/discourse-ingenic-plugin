import Component from "@glimmer/component";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { debounce } from "@ember/runloop";
import { tracked } from "@glimmer/tracking";
import { eq } from "discourse/truth-helpers";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

const AREAS = ["documentation", "downloads", "boards"];

/**
 * Who may look after which chip, and in which of the three jobs.
 *
 * A chip is one row in the product tree and up to three grants: its
 * documentation, its downloads, its boards. That is the shape the team works
 * in — T33's documentation and T33's SDK are often different people — so the
 * screen is a tree and three tabs, not a list of record ids.
 *
 * A grant on a series reaches every chip under it. Those show in the child's
 * tab marked as inherited and are revoked at the series, which is where they
 * were given; there is no second, child-level copy that could drift.
 *
 * The picker searches on the server as you type. Asking an administrator to
 * type a user id was the old screen's central flaw: the number is not
 * something anybody knows, and a wrong one is a grant to a stranger.
 */
export default class IngenicPermissionManager extends Component {
  @tracked permissions = this.args.permissions ?? [];
  @tracked products = this.args.products ?? [];
  @tracked selectedProductId = null;
  @tracked area = "documentation";
  @tracked query = "";
  @tracked results = { users: [], groups: [] };
  @tracked selectedPrincipal = null;
  @tracked busy = false;
  @tracked message = null;
  @tracked error = null;

  constructor(owner, args) {
    super(owner, args);

    const chips = this.products.filter((product) => product.kind === "chip");
    this.selectedProductId = chips[0]?.id ?? this.products[0]?.id ?? null;
    this.runSearch();
  }

  get areas() {
    return AREAS;
  }

  get series() {
    return this.products
      .filter((product) => product.kind !== "chip")
      .map((series) => ({
        ...series,
        chips: this.products.filter((product) => product.parent_id === series.id),
      }));
  }

  get orphanChips() {
    return this.products.filter(
      (product) => product.kind === "chip" && !product.parent_id
    );
  }

  get selectedProduct() {
    return this.products.find((product) => product.id === this.selectedProductId);
  }

  get ancestors() {
    const ancestors = [];
    let current = this.selectedProduct;

    while (current?.parent_id) {
      current = this.products.find((product) => product.id === current.parent_id);
      if (current) {
        ancestors.push(current);
      }
    }

    return ancestors;
  }

  get parentName() {
    return this.ancestors[0]?.name;
  }

  get directGrants() {
    return this.grantsFor((permission) => permission.resource_id === this.selectedProductId);
  }

  get inheritedGrants() {
    const ancestorIds = this.ancestors.map((product) => product.id);

    return this.grantsFor((permission) =>
      ancestorIds.includes(permission.resource_id)
    ).map((permission) => ({
      ...permission,
      inheritedFrom: this.products.find(
        (product) => product.id === permission.resource_id
      ),
    }));
  }

  // Grants that are not on a chip at all — a page, a board, a download. They
  // predate this screen and the API still accepts them, so they are listed
  // rather than hidden; the tree is where new ones are made.
  get resourceGrants() {
    return this.permissions.filter(
      (permission) => permission.resource_type !== "IngenicProduct"
    );
  }

  get pickerOpen() {
    return this.results.users.length > 0 || this.results.groups.length > 0;
  }

  grantsFor(predicate) {
    return this.permissions.filter(
      (permission) =>
        permission.area === this.area &&
        permission.resource_type === "IngenicProduct" &&
        predicate(permission)
    );
  }

  areaLabel(area) {
    return i18n(`ingenic.group_permissions.features.${area}`);
  }

  principalLabel(principal) {
    if (!principal) {
      return "";
    }

    if (principal.type === "group") {
      return principal.name;
    }

    return principal.name
      ? `${principal.username} (${principal.name})`
      : principal.username;
  }

  @action
  selectProduct(productId) {
    this.selectedProductId = productId;
    this.selectedPrincipal = null;
    this.message = null;
    this.error = null;
  }

  @action
  selectArea(area) {
    this.area = area;
    this.selectedPrincipal = null;
    this.message = null;
    this.error = null;
  }

  @action
  search(event) {
    this.query = event.target.value;
    this.selectedPrincipal = null;
    debounce(this, this.runSearch, 250);
  }

  @action
  async runSearch() {
    try {
      const results = await ajax(
        `/admin/plugins/discourse-ingenic/permission-principals?q=${encodeURIComponent(
          this.query
        )}`
      );
      this.results = {
        users: results.users ?? [],
        groups: results.groups ?? [],
      };
    } catch {
      this.results = { users: [], groups: [] };
    }
  }

  @action
  chooseUser(user) {
    this.selectedPrincipal = { type: "user", ...user };
    this.results = { users: [], groups: [] };
    this.query = user.username;
  }

  @action
  chooseGroup(group) {
    this.selectedPrincipal = { type: "group", ...group };
    this.results = { users: [], groups: [] };
    this.query = group.name;
  }

  @action
  async grant() {
    if (!this.selectedPrincipal || !this.selectedProductId || this.busy) {
      return;
    }

    this.busy = true;
    this.error = null;
    this.message = null;

    const data = {
      area: this.area,
      resource_type: "IngenicProduct",
      resource_id: this.selectedProductId,
      permission: "manage",
    };

    if (this.selectedPrincipal.type === "user") {
      data.user_id = this.selectedPrincipal.id;
    } else {
      data.group_id = this.selectedPrincipal.id;
    }

    try {
      const response = await ajax(
        "/admin/plugins/discourse-ingenic/permissions",
        { type: "POST", data }
      );
      this.permissions = [...this.permissions, response.permission];
      this.selectedPrincipal = null;
      this.query = "";
      this.results = { users: [], groups: [] };
      this.message = i18n("ingenic.permissions.granted");
    } catch (error) {
      this.error =
        error.jqXHR?.responseJSON?.errors?.join(", ") ||
        i18n("ingenic.save_failed");
    } finally {
      this.busy = false;
    }
  }

  @action
  async revoke(permission) {
    this.error = null;
    this.message = null;

    try {
      await ajax(
        `/admin/plugins/discourse-ingenic/permissions/${permission.id}`,
        { type: "DELETE" }
      );
      this.permissions = this.permissions.filter(
        (item) => item.id !== permission.id
      );
      this.message = i18n("ingenic.permissions.revoked");
    } catch {
      this.error = i18n("ingenic.save_failed");
    }
  }

  <template>
    <div class="ingenic-perm">
      <div class="ingenic-perm__layout">
        <aside class="ingenic-perm__tree">
          <h3 class="ingenic-perm__tree-title">
            {{i18n "ingenic.permissions.products"}}
          </h3>

          {{#each this.series as |series|}}
            <div class="ingenic-perm__series">
              <button
                type="button"
                class="ingenic-perm__node ingenic-perm__node--series
                  {{if (eq series.id this.selectedProductId) 'is-selected'}}"
                {{on "click" (fn this.selectProduct series.id)}}
              >
                {{series.name}}
              </button>

              {{#each series.chips as |chip|}}
                <button
                  type="button"
                  class="ingenic-perm__node ingenic-perm__node--chip
                    {{if (eq chip.id this.selectedProductId) 'is-selected'}}"
                  {{on "click" (fn this.selectProduct chip.id)}}
                >
                  {{chip.name}}
                </button>
              {{/each}}
            </div>
          {{/each}}

          {{#each this.orphanChips as |chip|}}
            <button
              type="button"
              class="ingenic-perm__node ingenic-perm__node--chip
                {{if (eq chip.id this.selectedProductId) 'is-selected'}}"
              {{on "click" (fn this.selectProduct chip.id)}}
            >
              {{chip.name}}
            </button>
          {{/each}}

          {{#unless this.products.length}}
            <p class="ingenic-admin-tree__empty">
              {{i18n "ingenic.permissions.no_products"}}
            </p>
          {{/unless}}
        </aside>

        <section class="ingenic-perm__panel">
          {{#if this.selectedProduct}}
            <header class="ingenic-perm__header">
              <h3>{{this.selectedProduct.name}}</h3>
              {{#if this.ancestors.length}}
                <p class="ingenic-admin-list__meta">
                  {{i18n "ingenic.permissions.belongs_to"}}
                  {{this.parentName}}
                </p>
              {{/if}}
            </header>

            <div class="ingenic-perm__tabs">
              {{#each this.areas as |area|}}
                <button
                  type="button"
                  class="ingenic-perm__tab {{if (eq area this.area) 'is-active'}}"
                  {{on "click" (fn this.selectArea area)}}
                >
                  {{this.areaLabel area}}
                </button>
              {{/each}}
            </div>

            <div class="ingenic-perm__picker">
              <label class="ingenic-perm__search">
                <span>{{i18n "ingenic.permissions.pick_principal"}}</span>
                <input
                  type="text"
                  value={{this.query}}
                  placeholder={{i18n
                    "ingenic.permissions.search_placeholder"
                  }}
                  {{on "input" this.search}}
                />
              </label>

              {{#if this.pickerOpen}}
                <div class="ingenic-perm__results">
                  {{#each this.results.users as |user|}}
                    <button
                      type="button"
                      class="ingenic-perm__result"
                      {{on "click" (fn this.chooseUser user)}}
                    >
                      <strong>{{user.username}}</strong>
                      {{#if user.name}}<span>{{user.name}}</span>{{/if}}
                    </button>
                  {{/each}}

                  {{#each this.results.groups as |group|}}
                    <button
                      type="button"
                      class="ingenic-perm__result ingenic-perm__result--group"
                      {{on "click" (fn this.chooseGroup group)}}
                    >
                      <strong>{{group.name}}</strong>
                      <span>{{i18n "ingenic.permissions.group"}}</span>
                    </button>
                  {{/each}}
                </div>
              {{/if}}

              {{#if this.selectedPrincipal}}
                <div class="ingenic-perm__chosen">
                  <span>
                    {{i18n "ingenic.permissions.selected"}}
                    <strong>{{this.principalLabel this.selectedPrincipal}}</strong>
                  </span>
                  <button
                    type="button"
                    class="btn btn-primary"
                    disabled={{this.busy}}
                    {{on "click" this.grant}}
                  >
                    {{i18n "ingenic.permissions.grant"}}
                  </button>
                </div>
              {{/if}}
            </div>

            {{#if this.message}}
              <p class="ingenic-admin-note">{{this.message}}</p>
            {{/if}}
            {{#if this.error}}
              <p class="ingenic-admin-note ingenic-admin-note--error">
                {{this.error}}
              </p>
            {{/if}}

            <h4 class="ingenic-perm__section-title">
              {{i18n "ingenic.permissions.direct"}}
            </h4>
            <div class="ingenic-admin-list">
              {{#each this.directGrants as |permission|}}
                <section class="ingenic-admin-list__row">
                  <div>
                    <strong>{{this.principalLabel permission.principal}}</strong>
                    <div class="ingenic-admin-list__meta">
                      {{permission.resource.label}}
                    </div>
                  </div>
                  <button
                    type="button"
                    class="btn btn-danger"
                    {{on "click" (fn this.revoke permission)}}
                  >
                    {{i18n "ingenic.revoke"}}
                  </button>
                </section>
              {{else}}
                <p>{{i18n "ingenic.permissions.empty_area"}}</p>
              {{/each}}
            </div>

            {{#if this.inheritedGrants.length}}
              <h4 class="ingenic-perm__section-title">
                {{i18n "ingenic.permissions.inherited"}}
              </h4>
              <div class="ingenic-admin-list">
                {{#each this.inheritedGrants as |permission|}}
                  <section class="ingenic-admin-list__row">
                    <div>
                      <strong>{{this.principalLabel permission.principal}}</strong>
                      <div class="ingenic-admin-list__meta">
                        {{i18n "ingenic.permissions.inherited_from"}}
                        {{permission.inheritedFrom.name}}
                      </div>
                    </div>
                  </section>
                {{/each}}
              </div>
            {{/if}}
          {{else}}
            <p class="ingenic-admin-tree__empty">
              {{i18n "ingenic.permissions.pick_product"}}
            </p>
          {{/if}}
        </section>
      </div>

      {{#if this.resourceGrants.length}}
        <section class="ingenic-perm__other">
          <h4 class="ingenic-perm__section-title">
            {{i18n "ingenic.permissions.other_grants"}}
          </h4>
          <div class="ingenic-admin-list">
            {{#each this.resourceGrants as |permission|}}
              <section class="ingenic-admin-list__row">
                <div>
                  <strong>{{this.principalLabel permission.principal}}</strong>
                  <div class="ingenic-admin-list__meta">
                    {{permission.resource.label}} ·
                    {{this.areaLabel permission.area}}
                  </div>
                </div>
                <button
                  type="button"
                  class="btn btn-danger"
                  {{on "click" (fn this.revoke permission)}}
                >
                  {{i18n "ingenic.revoke"}}
                </button>
              </section>
            {{/each}}
          </div>
        </section>
      {{/if}}
    </div>
  </template>
}
