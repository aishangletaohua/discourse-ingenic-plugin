import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { ajax } from "../../lib/ingenic-content-api";
import { i18n } from "discourse-i18n";

const ENDPOINT = "/admin/plugins/discourse-ingenic/header-links";

const BLANK = {
  label: "",
  href: "",
  icon: "",
  image_url: "",
  show_label: true,
  external: false,
  position: 0,
  published: true,
};

/**
 * The buttons in the header, beside the logo.
 *
 * A destination here is usually outside the forum — the Chinese site, a GitHub
 * organisation — so `external` defaults to on for a save the editor did not
 * touch, and the label is what a screen reader reads when the button is drawn
 * as its icon alone.
 */
export default class IngenicHeaderLinkManager extends Component {
  @tracked records = this.args.headerLinks ?? [];
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

  // Keeps the draft in step with the fields, so a refused save or a click on a
  // checkbox does not empty what was typed. The checkboxes are read from the
  // form on submit; this only stops the form from writing stale values back.
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
    for (const name of ["show_label", "external", "published"]) {
      form.set(name, String(event.target.elements[name].checked));
    }

    const id = this.draft.id;

    try {
      const response = await ajax(id ? `${ENDPOINT}/${id}` : ENDPOINT, {
        type: id ? "PUT" : "POST",
        data: form,
        processData: false,
        contentType: false,
      });

      const saved = response.header_link;
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
      <p class="ingenic-admin-note">{{i18n "ingenic.header_links.intro"}}</p>

      {{#if this.error}}<p class="ingenic-admin-note ingenic-admin-note--error">{{this.error}}</p>{{/if}}
      {{#if this.message}}<p class="ingenic-admin-note">{{this.message}}</p>{{/if}}

      <div class="ingenic-admin__toolbar">
        <button class="btn btn-primary" type="button" {{on "click" this.startNew}}>
          {{i18n "ingenic.header_links.add"}}
        </button>
      </div>

      {{#if this.draft}}
        <form class="ingenic-admin-form" {{on "submit" this.save}} {{on "input" this.field}}>
          <h3>
            {{#if this.draft.id}}
              {{i18n "ingenic.header_links.edit_title"}}
            {{else}}
              {{i18n "ingenic.header_links.new_title"}}
            {{/if}}
          </h3>

          <label>
            <span>{{i18n "ingenic.header_links.fields.label"}}</span>
            <input name="label" value={{this.draft.label}} required />
          </label>

          <label>
            <span>{{i18n "ingenic.header_links.fields.href"}}</span>
            <input name="href" value={{this.draft.href}} required placeholder="https://..." />
          </label>

          <label>
            <span>{{i18n "ingenic.header_links.fields.icon"}}</span>
            <input name="icon" value={{this.draft.icon}} placeholder="code-branch" />
          </label>

          <p class="ingenic-admin-form__hint">
            {{i18n "ingenic.header_links.fields.icon_hint"}}
          </p>

          <label>
            <span>{{i18n "ingenic.header_links.fields.image_url"}}</span>
            <input name="image_url" value={{this.draft.image_url}} />
          </label>

          <p class="ingenic-admin-form__hint">
            {{i18n "ingenic.header_links.fields.image_hint"}}
          </p>

          <label class="checkbox-label">
            <input type="checkbox" name="show_label" checked={{this.draft.show_label}} />
            <span>{{i18n "ingenic.header_links.fields.show_label"}}</span>
          </label>

          <label class="checkbox-label">
            <input type="checkbox" name="external" checked={{this.draft.external}} />
            <span>{{i18n "ingenic.header_links.fields.external"}}</span>
          </label>

          <label>
            <span>{{i18n "ingenic.header_links.fields.position"}}</span>
            <input type="number" name="position" value={{this.draft.position}} />
          </label>

          <label class="checkbox-label">
            <input type="checkbox" name="published" checked={{this.draft.published}} />
            <span>{{i18n "ingenic.header_links.fields.published"}}</span>
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
                {{record.href}}
                {{#if record.icon}}· {{record.icon}}{{/if}}
                {{#if record.position}}· {{record.position}}{{/if}}
                {{#unless record.show_label}}· {{i18n "ingenic.header_links.icon_only"}}{{/unless}}
                {{#unless record.published}}
                  · {{i18n "ingenic.header_links.unpublished"}}
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
          <p>{{i18n "ingenic.header_links.empty"}}</p>
        {{/each}}
      </div>
    </div>
  </template>
}
