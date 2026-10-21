import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { ajax } from "../../lib/ingenic-content-api";
import { i18n } from "discourse-i18n";

const ENDPOINT = "/admin/plugins/discourse-ingenic/section-cards";

const BLANK = {
  label: "",
  category: "",
  href: "",
  description: "",
  icon: "",
  image_url: "",
  color: "",
  position: 0,
  published: true,
};

/**
 * The cards under "Popular sections" on the front page.
 *
 * A card naming a category draws that category's own name, colour, icon,
 * description and topic count, so the front page cannot drift from the section
 * page. A card without one is for something that is not a category at all —
 * the documentation reader is the reason this exists — and carries its own
 * name, destination, icon and colour.
 */
export default class IngenicSectionCardManager extends Component {
  @tracked records = this.args.sectionCards ?? [];
  @tracked draft = null;
  @tracked busy = false;
  @tracked message = null;
  @tracked error = null;

  @action
  startNew() {
    this.draft = { ...BLANK };
    this.message = null;
    this.error = null;
  }

  @action
  edit(record) {
    this.draft = { ...record };
    this.message = null;
    this.error = null;
  }

  @action
  cancel() {
    this.draft = null;
    this.message = null;
    this.error = null;
  }

  @action
  field(event) {
    const { name, type, value, checked } = event.target;
    if (!name || type === "file") {
      return;
    }

    this.draft[name] = type === "checkbox" ? checked : value;
  }

  @action
  async save(event) {
    event.preventDefault();
    this.busy = true;
    this.message = null;
    this.error = null;

    const form = new FormData(event.target);
    form.set("published", String(event.target.elements.published.checked));

    const id = this.draft.id;

    try {
      const response = await ajax(id ? `${ENDPOINT}/${id}` : ENDPOINT, {
        type: id ? "PUT" : "POST",
        data: form,
        processData: false,
        contentType: false,
      });

      const saved = response.section_card;
      this.records = id
        ? this.records.map((record) => (record.id === saved.id ? saved : record))
        : [...this.records, saved];
      this.draft = null;
      this.message = i18n("ingenic.saved");
    } catch (failure) {
      this.error = this.#errorMessage(failure);
    } finally {
      this.busy = false;
    }
  }

  @action
  async remove(record, event) {
    event.preventDefault();
    this.error = null;

    try {
      await ajax(`${ENDPOINT}/${record.id}`, { type: "DELETE" });
      this.records = this.records.filter((item) => item.id !== record.id);
    } catch (failure) {
      this.error = this.#errorMessage(failure);
    }
  }

  #errorMessage(failure) {
    const errors = failure?.jqXHR?.responseJSON?.errors;
    return errors?.join(", ") || i18n("ingenic.save_failed");
  }

  <template>
    <div class="ingenic-admin-panel">
      <p class="ingenic-admin-note">{{i18n "ingenic.section_cards.intro"}}</p>

      {{#if this.error}}<p class="ingenic-admin-note ingenic-admin-note--error">{{this.error}}</p>{{/if}}
      {{#if this.message}}<p class="ingenic-admin-note">{{this.message}}</p>{{/if}}

      <div class="ingenic-admin__toolbar">
        <button class="btn btn-primary" type="button" {{on "click" this.startNew}}>
          {{i18n "ingenic.section_cards.add"}}
        </button>
      </div>

      {{#if this.draft}}
        <form class="ingenic-admin-form" {{on "submit" this.save}} {{on "input" this.field}}>
          <h3>
            {{#if this.draft.id}}
              {{i18n "ingenic.section_cards.edit_title"}}
            {{else}}
              {{i18n "ingenic.section_cards.new_title"}}
            {{/if}}
          </h3>

          <label>
            <span>{{i18n "ingenic.section_cards.fields.category"}}</span>
            <input name="category" value={{this.draft.category}} placeholder="technical-discussions" />
          </label>

          <p class="ingenic-admin-form__hint">
            {{i18n "ingenic.section_cards.fields.category_hint"}}
          </p>

          <label>
            <span>{{i18n "ingenic.section_cards.fields.label"}}</span>
            <input name="label" value={{this.draft.label}} />
          </label>

          <label>
            <span>{{i18n "ingenic.section_cards.fields.href"}}</span>
            <input name="href" value={{this.draft.href}} placeholder="/ingenic/docs" />
          </label>

          <label>
            <span>{{i18n "ingenic.section_cards.fields.description"}}</span>
            <input name="description" value={{this.draft.description}} />
          </label>

          <label>
            <span>{{i18n "ingenic.section_cards.fields.icon"}}</span>
            <input name="icon" value={{this.draft.icon}} placeholder="book" />
          </label>

          <label>
            <span>{{i18n "ingenic.section_cards.fields.image_url"}}</span>
            <input name="image_url" value={{this.draft.image_url}} />
          </label>

          <label>
            <span>{{i18n "ingenic.section_cards.fields.color"}}</span>
            <input name="color" value={{this.draft.color}} placeholder="0088cc" />
          </label>

          <label>
            <span>{{i18n "ingenic.section_cards.fields.position"}}</span>
            <input type="number" name="position" value={{this.draft.position}} />
          </label>

          <label class="checkbox-label">
            <input type="checkbox" name="published" checked={{this.draft.published}} />
            <span>{{i18n "ingenic.section_cards.fields.published"}}</span>
          </label>

          <div class="ingenic-admin__toolbar">
            <button class="btn btn-primary" type="submit" disabled={{this.busy}}>
              {{i18n "ingenic.save"}}
            </button>
            <button class="btn" type="button" {{on "click" this.cancel}}>
              {{i18n "ingenic.cancel"}}
            </button>
          </div>
        </form>
      {{/if}}

      <div class="ingenic-admin-list">
        {{#each this.records as |record|}}
          <section class="ingenic-admin-list__row">
            <div>
              <strong>{{record.label}}</strong>
              <div class="ingenic-admin-list__meta">
                {{#if record.category}}/c/{{record.category}}{{/if}}
                {{#if record.href}}· {{record.href}}{{/if}}
                {{#unless record.published}}
                  · {{i18n "ingenic.section_cards.unpublished"}}
                {{/unless}}
              </div>
            </div>
            <div class="ingenic-admin__toolbar">
              <button class="btn" type="button" {{on "click" (fn this.edit record)}}>
                {{i18n "ingenic.edit"}}
              </button>
              <button class="btn btn-danger" type="button" {{on "click" (fn this.remove record)}}>
                {{i18n "ingenic.delete"}}
              </button>
            </div>
          </section>
        {{else}}
          <p>{{i18n "ingenic.section_cards.empty"}}</p>
        {{/each}}
      </div>
    </div>
  </template>
}
