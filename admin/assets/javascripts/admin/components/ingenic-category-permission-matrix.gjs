import Component from "@glimmer/component";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { tracked } from "@glimmer/tracking";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

const ENDPOINT = "/admin/plugins/discourse-ingenic/category-permissions";
const LEVELS = ["none", "readonly", "create_post", "full"];
const NAMES = { 1: "full", 2: "create_post", 3: "readonly" };

/**
 * Who may do what in each forum category.
 *
 * The levels are Discourse's own, and they are not three shades of the same
 * verb: full is "start a topic and reply", create_post is "reply only", and
 * readonly is "read". That is why the labels say what a person can do rather
 * than ranking them — an official-announcements group that may reply but not
 * start a topic is a real arrangement, not a half-grant.
 *
 * An empty cell is no row. Discourse reads no rows as everyone-full, so
 * clearing a category back to the default is a deliberate "none" in the
 * matrix rather than something the screen has to special-case.
 */
export default class IngenicCategoryPermissionMatrix extends Component {
  @tracked matrix = {};
  @tracked busy = false;
  @tracked message = null;
  @tracked error = null;

  constructor(owner, args) {
    super(owner, args);
    this.matrix = this.initialMatrix();
  }

  get groups() {
    return this.args.groups ?? [];
  }

  // A child is drawn under its section, not in a second alphabetical list:
  // "Official Open Source" reads as part of "Open Source" only when it sits
  // directly beneath it.
  get categories() {
    const all = this.args.categories ?? [];
    const parents = all.filter((category) => !category.parent_id);
    const ordered = [];

    for (const parent of parents) {
      ordered.push(parent);
      ordered.push(
        ...all.filter((category) => category.parent_id === parent.id)
      );
    }

    const known = new Set(parents.map((parent) => parent.id));
    ordered.push(
      ...all.filter(
        (category) => category.parent_id && !known.has(category.parent_id)
      )
    );

    return ordered;
  }

  get levels() {
    return LEVELS;
  }

  // Arrow fields, because the template calls these without a receiver: as
  // ordinary methods they arrive with `this` undefined and the row stops
  // rendering at the first cell.
  key = (categoryId, groupId) => `${categoryId}:${groupId}`;

  initialMatrix() {
    const byName = new Map(this.groups.map((group) => [group.name, group.id]));
    const matrix = {};

    for (const category of this.args.categories ?? []) {
      for (const group of this.groups) {
        matrix[this.key(category.id, group.id)] = "none";
      }

      for (const [name, type] of Object.entries(category.permissions ?? {})) {
        const groupId = byName.get(name);
        if (groupId) {
          matrix[this.key(category.id, groupId)] = NAMES[type] ?? "none";
        }
      }
    }

    return matrix;
  }

  valueFor = (categoryId, groupId) =>
    this.matrix[this.key(categoryId, groupId)] ?? "none";

  levelLabel = (level) =>
    i18n(`ingenic.category_permissions.levels.${level}`);

  swatchStyle = (category) => `background: #${category.color || "999999"}`;

  @action
  change(category, group, event) {
    this.matrix = {
      ...this.matrix,
      [this.key(category.id, group.id)]: event.target.value,
    };
    this.message = null;
    this.error = null;
  }

  @action
  async save() {
    if (this.busy) {
      return;
    }

    this.busy = true;
    this.message = null;
    this.error = null;

    const changes = [];
    for (const category of this.args.categories ?? []) {
      for (const group of this.groups) {
        changes.push({
          category_id: category.id,
          group_id: group.id,
          permission: this.valueFor(category.id, group.id),
        });
      }
    }

    try {
      await ajax(ENDPOINT, {
        type: "PUT",
        data: { changes: JSON.stringify(changes) },
      });
      this.message = i18n("ingenic.category_permissions.saved");
    } catch (error) {
      this.error =
        error.jqXHR?.responseJSON?.errors?.join(", ") ||
        i18n("ingenic.save_failed");
    } finally {
      this.busy = false;
    }
  }

  <template>
    <p class="ingenic-admin-form__hint">
      {{i18n "ingenic.category_permissions.hint"}}
    </p>

    {{#if this.groups.length}}
      <div class="ingenic-matrix-wrap">
        <table class="ingenic-admin-table ingenic-category-matrix">
          <thead>
            <tr>
              <th>{{i18n "ingenic.category_permissions.section"}}</th>
              {{#each this.groups as |group|}}
                <th class="ingenic-category-matrix__group">{{group.name}}</th>
              {{/each}}
            </tr>
          </thead>
          <tbody>
            {{#each this.categories as |category|}}
              <tr>
                <td class="ingenic-category-matrix__section">
                  {{#if category.parent_id}}<span
                      class="ingenic-category-matrix__child"
                    >↳</span>{{/if}}
                  <span
                    class="ingenic-category-matrix__swatch"
                    style={{this.swatchStyle category}}
                  ></span>
                  {{category.name}}
                </td>
                {{#each this.groups as |group|}}
                  <td>
                    <select
                      class="ingenic-category-matrix__select"
                      value={{this.valueFor category.id group.id}}
                      {{on "change" (fn this.change category group)}}
                    >
                      {{#each this.levels as |level|}}
                        <option value={{level}}>{{this.levelLabel level}}</option>
                      {{/each}}
                    </select>
                  </td>
                {{/each}}
              </tr>
            {{/each}}
          </tbody>
        </table>
      </div>

      <div class="ingenic-admin-form__actions">
        <button
          type="button"
          class="btn btn-primary"
          disabled={{this.busy}}
          {{on "click" this.save}}
        >
          {{i18n "ingenic.category_permissions.save"}}
        </button>
      </div>

      {{#if this.message}}
        <p class="ingenic-admin-note">{{this.message}}</p>
      {{/if}}
      {{#if this.error}}
        <p class="ingenic-admin-note ingenic-admin-note--error">
          {{this.error}}
        </p>
      {{/if}}
    {{else}}
      <p>{{i18n "ingenic.category_permissions.no_groups"}}</p>
    {{/if}}
  </template>
}
