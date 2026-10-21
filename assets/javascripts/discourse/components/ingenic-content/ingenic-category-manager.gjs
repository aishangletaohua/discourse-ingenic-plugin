import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { ajax } from "../../lib/ingenic-content-api";
import { i18n } from "discourse-i18n";

const ENDPOINT = "/admin/plugins/discourse-ingenic/download-categories";

const BLANK = {
  name: "",
  position: 0,
  published: true,
};

/**
 * The classifications a download can be filed under.
 *
 * This used to be a list in the plugin's code, which meant a rename needed a
 * rebuild. It is Ingenic's own vocabulary — the Chinese forum files one chip
 * under CP020 while everything else says CW020 — so they are the ones who
 * should be able to change it.
 */
export default class IngenicCategoryManager extends Component {
  @tracked records = this.args.categories ?? [];
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

  // The text fields are bound one way, and a re-render puts the draft back
  // into them, over whatever was typed: the draft never heard about the
  // typing. Keeping it in step as the form is filled in is what stops a click
  // on a select - or a save the server refuses - from emptying the form.
  @action
  field(event) {
    const { name, type, value, checked } = event.target;

    // The selects keep the draft in step in their own handlers, and a file
    // input's value is a fake path rather than a filename.
    if (!name || type === "file" || type.startsWith("select")) {
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

      const saved = response.category;
      if (id) {
        this.records = this.records.map((record) => (record.id === saved.id ? saved : record));
      } else {
        // The count arrives with the listing query, so a category that has just
        // been created has none yet. Saying zero rather than nothing keeps the
        // column the same shape on every row.
        this.records = [...this.records, { ...saved, download_count: 0 }];
      }
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

    if (record.download_count > 0 && !this.#confirmRemoval(record)) {
      return;
    }

    try {
      await ajax(`${ENDPOINT}/${record.id}`, { type: "DELETE" });
      this.records = this.records.filter((item) => item.id !== record.id);
      this.message = i18n("ingenic.saved");
    } catch (failure) {
      this.error = this.#errorMessage(failure);
    }
  }

  // Deleting a category does not delete what is filed under it, but it does
  // take the label off those resources, and an editor who is not told that will
  // find out later from an empty column on the download centre.
  #confirmRemoval(record) {
    return window.confirm(
      i18n("ingenic.categories.delete_confirm", { count: record.download_count })
    );
  }

  #errorMessage(failure) {
    const errors = failure?.jqXHR?.responseJSON?.errors;
    return errors?.join(", ") || i18n("ingenic.save_failed");
  }

  <template>
    <div class="ingenic-admin-panel">
      {{#if this.error}}<p class="ingenic-admin-note ingenic-admin-note--error">{{this.error}}</p>{{/if}}
      {{#if this.message}}<p class="ingenic-admin-note">{{this.message}}</p>{{/if}}

      <div class="ingenic-admin__toolbar">
        <button class="btn btn-primary" type="button" {{on "click" this.startNew}}>
          {{i18n "ingenic.categories.add"}}
        </button>
      </div>

      {{#if this.draft}}
        <form class="ingenic-admin-form" {{on "submit" this.save}} {{on "input" this.field}}>
          <h3>
            {{#if this.draft.id}}
              {{i18n "ingenic.categories.edit_title"}}
            {{else}}
              {{i18n "ingenic.categories.new_title"}}
            {{/if}}
          </h3>

          <label>
            <span>{{i18n "ingenic.categories.fields.name"}}</span>
            <input name="name" value={{this.draft.name}} required />
          </label>

          <label>
            <span>{{i18n "ingenic.categories.fields.position"}}</span>
            <input type="number" name="position" value={{this.draft.position}} />
          </label>

          <label class="checkbox-label">
            <input type="checkbox" name="published" checked={{this.draft.published}} />
            <span>{{i18n "ingenic.categories.fields.published"}}</span>
          </label>

          <p class="ingenic-admin-form__hint">
            {{i18n "ingenic.categories.fields.published_hint"}}
          </p>

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
              <strong>{{record.name}}</strong>
              <div class="ingenic-admin-list__meta">
                {{i18n "ingenic.categories.resource_count" count=record.download_count}}
                {{#unless record.published}}
                  · {{i18n "ingenic.categories.unpublished"}}
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
          <p>{{i18n "ingenic.categories.empty"}}</p>
        {{/each}}
      </div>
    </div>
  </template>
}
