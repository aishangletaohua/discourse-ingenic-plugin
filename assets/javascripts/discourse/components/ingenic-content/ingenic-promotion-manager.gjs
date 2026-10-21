import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { ajax } from "../../lib/ingenic-content-api";
import { i18n } from "discourse-i18n";

const ENDPOINT = "/admin/plugins/discourse-ingenic/promotions";

// A new slot starts unpublished and without a window, so it is invisible until
// someone decides it is ready. Both defaults are the ones that cannot put an
// unfinished campaign on the homepage.
const BLANK = {
  corner_label: "",
  title: "",
  description: "",
  button_label: "",
  button_href: "",
  button_external: false,
  image_url: "",
  starts_at: "",
  ends_at: "",
  position: 0,
  published: false,
};

/**
 * The promotion slots at the top of the homepage.
 *
 * The Chinese forum runs three of these — GitHub, the download centre and the
 * documentation centre — and all three are the same shape: a corner tag, a
 * headline, a paragraph, a button and a background image. This screen is where
 * a fourth is added, or one taken down, without a deploy.
 */
export default class IngenicPromotionManager extends Component {
  @tracked records = this.args.promotions ?? [];
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
    // A datetime-local input only accepts minutes precision and no offset, so
    // the value the server sent is cut back to what the control can hold.
    this.draft = {
      ...record,
      starts_at: record.starts_at ? record.starts_at.slice(0, 16) : "",
      ends_at: record.ends_at ? record.ends_at.slice(0, 16) : "",
    };
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
    // An unchecked checkbox is absent from FormData, which the server reads as
    // "leave it alone" — the opposite of what unchecking means.
    form.set("published", String(event.target.elements.published.checked));
    form.set("button_external", String(event.target.elements.button_external.checked));

    const id = this.draft.id;

    try {
      const response = await ajax(id ? `${ENDPOINT}/${id}` : ENDPOINT, {
        type: id ? "PUT" : "POST",
        data: form,
        // Both are needed for a multipart body: jQuery would otherwise
        // url-encode the FormData and drop the browser's boundary header.
        processData: false,
        contentType: false,
      });

      const saved = response.promotion;
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
      {{#if this.error}}<p class="ingenic-admin-note ingenic-admin-note--error">{{this.error}}</p>{{/if}}
      {{#if this.message}}<p class="ingenic-admin-note">{{this.message}}</p>{{/if}}

      <div class="ingenic-admin__toolbar">
        <button class="btn btn-primary" type="button" {{on "click" this.startNew}}>
          {{i18n "ingenic.promotions.add"}}
        </button>
      </div>

      {{#if this.draft}}
        <form class="ingenic-admin-form" {{on "submit" this.save}} {{on "input" this.field}}>
          <h3>
            {{#if this.draft.id}}
              {{i18n "ingenic.promotions.edit_title"}}
            {{else}}
              {{i18n "ingenic.promotions.new_title"}}
            {{/if}}
          </h3>

          <label>
            <span>{{i18n "ingenic.promotions.fields.title"}}</span>
            <input name="title" value={{this.draft.title}} required />
          </label>

          <label>
            <span>{{i18n "ingenic.promotions.fields.corner_label"}}</span>
            <input name="corner_label" value={{this.draft.corner_label}} />
          </label>

          <label>
            <span>{{i18n "ingenic.promotions.fields.description"}}</span>
            <textarea name="description">{{this.draft.description}}</textarea>
          </label>

          <label>
            <span>{{i18n "ingenic.promotions.fields.button_label"}}</span>
            <input name="button_label" value={{this.draft.button_label}} />
          </label>

          <label>
            <span>{{i18n "ingenic.promotions.fields.button_href"}}</span>
            <input name="button_href" value={{this.draft.button_href}} />
          </label>

          <label class="checkbox-label">
            <input type="checkbox" name="button_external" checked={{this.draft.button_external}} />
            <span>{{i18n "ingenic.promotions.fields.button_external"}}</span>
          </label>

          <label>
            <span>{{i18n "ingenic.promotions.fields.image_url"}}</span>
            <input name="image_url" value={{this.draft.image_url}} />
          </label>

          <p class="ingenic-admin-form__hint">
            {{i18n "ingenic.promotions.fields.image_hint"}}
          </p>

          <label>
            <span>{{i18n "ingenic.promotions.fields.starts_at"}}</span>
            <input type="datetime-local" name="starts_at" value={{this.draft.starts_at}} />
          </label>

          <label>
            <span>{{i18n "ingenic.promotions.fields.ends_at"}}</span>
            <input type="datetime-local" name="ends_at" value={{this.draft.ends_at}} />
          </label>

          <p class="ingenic-admin-form__hint">
            {{i18n "ingenic.promotions.fields.window_hint"}}
          </p>

          <label>
            <span>{{i18n "ingenic.promotions.fields.position"}}</span>
            <input type="number" name="position" value={{this.draft.position}} />
          </label>

          <label class="checkbox-label">
            <input type="checkbox" name="published" checked={{this.draft.published}} />
            <span>{{i18n "ingenic.promotions.fields.published"}}</span>
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
              <strong>{{record.title}}</strong>
              <div class="ingenic-admin-list__meta">
                {{#if record.corner_label}}· {{record.corner_label}}{{/if}}
                {{#if record.button_label}}· {{record.button_label}}{{/if}}
                {{#if record.position}}· {{record.position}}{{/if}}
              </div>
              <div class="ingenic-admin-list__meta">
                {{#if record.live}}
                  {{i18n "ingenic.promotions.live"}}
                {{else}}
                  {{i18n "ingenic.promotions.not_live"}}
                {{/if}}
                {{#unless record.published}}
                  · {{i18n "ingenic.promotions.unpublished"}}
                {{/unless}}
              </div>
            </div>
            <div class="ingenic-admin__toolbar">
              <button class="btn" type="button" {{on "click" (fn this.edit record)}}>
                {{i18n "ingenic.edit"}}
              </button>
              <button
                class="btn btn-danger"
                type="button"
                {{on "click" (fn this.remove record)}}
              >
                {{i18n "ingenic.delete"}}
              </button>
            </div>
          </section>
        {{else}}
          <p>{{i18n "ingenic.promotions.empty"}}</p>
        {{/each}}
      </div>
    </div>
  </template>
}
