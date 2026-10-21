import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { ajax } from "discourse/lib/ajax";
import getURL from "discourse/lib/get-url";
import { i18n } from "discourse-i18n";

const ENDPOINT = "/admin/plugins/discourse-ingenic/group-permissions";

/**
 * Groups down the side, management screens across the top.
 *
 * A tick means the group may manage that screen in full. Someone holding one
 * screen's feature is not a site administrator: they still cannot open the
 * matrix, change permissions, or reach a screen they were not given. The
 * per-record grants on the Permissions screen sit underneath this and stay
 * narrower — a group ticked for documentation can manage every product, while
 * one product can still be lent to a single member without giving them the
 * screen.
 *
 * Only custom groups are offered. The automatic ones (staff, trust levels,
 * everyone) are membership the site maintains; a tick on `everyone` would hand
 * a management screen to every visitor, which is not a decision a checkbox
 * should make by accident.
 */
export default class IngenicGroupPermissionMatrix extends Component {
  @tracked groups = this.args.groups.map((group) => ({
    ...group,
    features: [...group.features],
  }));
  @tracked busy = false;
  @tracked message = null;

  get features() {
    return this.args.features;
  }

  featureLabel(feature) {
    return i18n(`ingenic.group_permissions.features.${feature}`);
  }

  has(group, feature) {
    return group.features.includes(feature);
  }

  @action
  toggle(group, feature) {
    group.features = this.has(group, feature)
      ? group.features.filter((item) => item !== feature)
      : [...group.features, feature];
    this.groups = [...this.groups];
  }

  @action
  async save() {
    this.busy = true;
    this.message = null;

    const grants = {};
    for (const group of this.groups) {
      grants[group.id] = group.features;
    }

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
    <p class="ingenic-admin-form__hint">
      {{i18n "ingenic.group_permissions.hint"}}
    </p>

    {{#if this.groups.length}}
      <div class="ingenic-matrix-wrap">
        <table class="ingenic-admin-table ingenic-matrix">
          <thead>
            <tr>
              <th>{{i18n "ingenic.group_permissions.group"}}</th>
              {{#each this.features as |feature|}}
                <th class="ingenic-matrix__feature">{{this.featureLabel feature}}</th>
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

      <div class="ingenic-admin-form__actions">
        <button
          class="btn btn-primary"
          type="button"
          disabled={{this.busy}}
          {{on "click" this.save}}
        >
          {{i18n "ingenic.group_permissions.save"}}
        </button>
        {{#if this.message}}
          <span class="ingenic-admin-note">{{this.message}}</span>
        {{/if}}
      </div>
    {{else}}
      <p>{{i18n "ingenic.group_permissions.empty"}}</p>
    {{/if}}

    <p class="ingenic-admin-form__hint">
      <a href={{getURL "/admin/groups"}}>
        {{i18n "ingenic.group_permissions.groups_link"}}
      </a>
    </p>
  </template>
}
