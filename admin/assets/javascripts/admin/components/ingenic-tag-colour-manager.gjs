import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { eq, fn } from "@ember/helper";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

const ENDPOINT = "/admin/plugins/discourse-ingenic/tag-colours";

/**
 * Tag colours.
 *
 * The forum classifies tags by subject, and this is where an administrator
 * changes that classification: every tag the site knows, each with the family
 * it draws in. The list is the tags themselves rather than a fixed vocabulary,
 * so a tag created this morning is here without a release — even before anybody
 * has classified it, in which case it is shown in the sky family it already
 * falls back to.
 */
export default class IngenicTagColourManager extends Component {
  @tracked tags = this.args.tags.map((tag) => ({ ...tag }));
  @tracked busy = false;
  @tracked message = null;

  get families() {
    return this.args.families;
  }

  familyLabel(family) {
    return i18n(`ingenic.tag_colours.families.${family}`);
  }

  @action
  setFamily(tag, event) {
    tag.family = event.target.value;
    this.tags = [...this.tags];
  }

  @action
  async save() {
    this.busy = true;
    this.message = null;

    const colours = {};
    for (const tag of this.tags) {
      colours[tag.name] = tag.family;
    }

    try {
      await ajax(ENDPOINT, {
        type: "PUT",
        data: { colours: JSON.stringify(colours) },
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
    <p class="ingenic-admin-form__hint">{{i18n "ingenic.tag_colours.hint"}}</p>

    {{#if this.tags.length}}
      <table class="ingenic-admin-table ingenic-tag-colours">
        <thead>
          <tr>
            <th>{{i18n "ingenic.tag_colours.tag"}}</th>
            <th>{{i18n "ingenic.tag_colours.family"}}</th>
          </tr>
        </thead>
        <tbody>
          {{#each this.tags as |tag|}}
            <tr>
              <td class="ingenic-tag-colours__name">{{tag.name}}</td>
              <td>
                <select
                  class="ingenic-tag-colours__select"
                  aria-label={{tag.name}}
                  {{on "change" (fn this.setFamily tag)}}
                >
                  {{#each this.families as |family|}}
                    <option value={{family}} selected={{eq family tag.family}}>
                      {{this.familyLabel family}}
                    </option>
                  {{/each}}
                </select>
              </td>
            </tr>
          {{/each}}
        </tbody>
      </table>

      <div class="ingenic-admin-form__actions">
        <button
          class="btn btn-primary"
          type="button"
          disabled={{this.busy}}
          {{on "click" this.save}}
        >
          {{i18n "ingenic.tag_colours.save"}}
        </button>
        {{#if this.message}}
          <span class="ingenic-admin-note">{{this.message}}</span>
        {{/if}}
      </div>
    {{else}}
      <p>{{i18n "ingenic.tag_colours.empty"}}</p>
    {{/if}}
  </template>
}
