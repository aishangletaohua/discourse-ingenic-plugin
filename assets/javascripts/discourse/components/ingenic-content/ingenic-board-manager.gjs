import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { ajax } from "../../lib/ingenic-content-api";
import DNativeSelect from "discourse/ui-kit/d-native-select";
import { i18n } from "discourse-i18n";

const ENDPOINT = "/admin/plugins/discourse-ingenic/boards";

// A new board starts unpublished. The application link is what a card is for,
// so a half-filled row is not something to put on the site by default.
const BLANK = {
  slug: "",
  name: "",
  kind: "board",
  product_id: "",
  description: "",
  details: "",
  specs: "",
  image_url: "",
  application_url: "",
  purchase_url: "",
  sold_out: false,
  published: false,
  position: 0,
};

/**
 * The development board catalogue.
 *
 * A board is filed against a chip in the shared product catalogue, which is
 * what gives the public page its series and chip filters. The chip can also be
 * left unset: a board may be listed before anything else exists for it, and
 * boards do not depend on documentation.
 *
 * The language is not a field here. The screen was opened in one language, the
 * listing contains that language's boards, and a new board joins them there.
 */
export default class IngenicBoardManager extends Component {
  @tracked records = this.args.boards ?? [];
  @tracked draft = null;
  @tracked busy = false;
  @tracked message = null;
  @tracked error = null;

  get chips() {
    return this.args.chips ?? [];
  }

  get chipLabel() {
    return (chip) =>
      chip.series_name ? `${chip.series_name} › ${chip.name}` : chip.name;
  }

  // Kept in one place so the list and the select cannot disagree about what a
  // stored value means.
  get kindLabel() {
    return (record) =>
      i18n(
        record.kind === "sample"
          ? "ingenic.boards.fields.kind_sample"
          : "ingenic.boards.fields.kind_board"
      );
  }

  @action
  startNew() {
    this.draft = { ...BLANK };
    this.message = null;
    this.error = null;
  }

  @action
  edit(record) {
    this.draft = { ...record, product_id: record.product_id ?? "" };
    this.message = null;
    this.error = null;
  }

  @action
  cancel() {
    this.draft = null;
    this.message = null;
    this.error = null;
  }

  // The ui-kit select drives the draft, and the draft is what the form was
  // built from, so the two are kept in step. The value still travels as a form
  // field: the select carries a name and the browser reads the choice back out
  // of it when the form is submitted.
  @action
  pickKind(value) {
    this.draft = { ...this.draft, kind: value || "board" };
  }

  @action
  pickChip(value) {
    this.draft = { ...this.draft, product_id: value ?? "" };
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
    // An unchecked box is absent from FormData, which the server reads as
    // "leave it alone" — the opposite of what unchecking means here.
    form.set("published", String(event.target.elements.published.checked));
    form.set("sold_out", String(event.target.elements.sold_out.checked));

    const id = this.draft.id;

    try {
      const response = await ajax(id ? `${ENDPOINT}/${id}` : ENDPOINT, {
        type: id ? "PUT" : "POST",
        data: form,
        // A file is not uploaded here, but the payload is sent as multipart so
        // the picker's null choice survives as an empty field rather than being
        // dropped, which would read as "unchanged".
        processData: false,
        contentType: false,
      });

      const saved = response.board;
      this.records = id
        ? this.records.map((record) => (record.id === saved.id ? saved : record))
        : [...this.records, saved];
      this.draft = null;
      this.message = i18n("ingenic.saved");
    } catch (failure) {
      this.error =
        failure?.jqXHR?.responseJSON?.errors?.join(", ") ||
        i18n("ingenic.save_failed");
    } finally {
      this.busy = false;
    }
  }

  @action
  async withdraw(record, event) {
    event.preventDefault();
    this.error = null;

    try {
      await ajax(`${ENDPOINT}/${record.id}`, { type: "DELETE" });
      this.records = this.records.map((item) =>
        item.id === record.id ? { ...item, published: false } : item
      );
    } catch (failure) {
      this.error =
        failure?.jqXHR?.responseJSON?.errors?.join(", ") ||
        i18n("ingenic.save_failed");
    }
  }

  <template>
    <div class="ingenic-admin-panel">
      {{#if this.error}}<p class="ingenic-admin-note ingenic-admin-note--error">{{this.error}}</p>{{/if}}
      {{#if this.message}}<p class="ingenic-admin-note">{{this.message}}</p>{{/if}}

      <div class="ingenic-admin__toolbar">
        <button class="btn btn-primary" type="button" {{on "click" this.startNew}}>
          {{i18n "ingenic.boards.add"}}
        </button>
      </div>

      {{#if this.draft}}
        <form class="ingenic-admin-form" {{on "submit" this.save}} {{on "input" this.field}}>
          <h3>
            {{#if this.draft.id}}
              {{i18n "ingenic.boards.edit_title"}}
            {{else}}
              {{i18n "ingenic.boards.new_title"}}
            {{/if}}
          </h3>

          <label>
            <span>{{i18n "ingenic.boards.fields.name"}}</span>
            <input name="name" value={{this.draft.name}} required />
          </label>

          <label>
            <span>{{i18n "ingenic.boards.fields.slug"}}</span>
            <input name="slug" value={{this.draft.slug}} required />
          </label>

          <label>
            <span>{{i18n "ingenic.boards.fields.kind"}}</span>
            <DNativeSelect
              name="kind"
              @value={{this.draft.kind}}
              @onChange={{this.pickKind}}
              as |select|
            >
              <select.Option @value="board">
                {{i18n "ingenic.boards.fields.kind_board"}}
              </select.Option>
              <select.Option @value="sample">
                {{i18n "ingenic.boards.fields.kind_sample"}}
              </select.Option>
            </DNativeSelect>
          </label>

          <label>
            <span>{{i18n "ingenic.boards.fields.chip_from_tree"}}</span>
            {{! A Glimmer-rendered `selected` attribute does not survive
                re-rendering, which is the bug DNativeSelect exists to work
                around. The blank option it adds is how a board is left
                unfiled. }}
            <DNativeSelect
              name="product_id"
              @value={{this.draft.product_id}}
              @onChange={{this.pickChip}}
              as |select|
            >
              {{#each this.chips as |chip|}}
                <select.Option @value={{chip.id}}>
                  {{this.chipLabel chip}}
                </select.Option>
              {{/each}}
            </DNativeSelect>
          </label>

          <label>
            <span>{{i18n "ingenic.boards.fields.application_url"}}</span>
            <input name="application_url" value={{this.draft.application_url}} />
          </label>

          <p class="ingenic-admin-form__hint">
            {{i18n "ingenic.boards.fields.application_url_hint"}}
          </p>

          <label>
            <span>{{i18n "ingenic.boards.fields.purchase_url"}}</span>
            <input name="purchase_url" value={{this.draft.purchase_url}} />
          </label>

          <p class="ingenic-admin-form__hint">
            {{i18n "ingenic.boards.fields.purchase_url_hint"}}
          </p>

          <label>
            <span>{{i18n "ingenic.boards.fields.image_url"}}</span>
            <input name="image_url" value={{this.draft.image_url}} />
          </label>

          <label>
            <span>{{i18n "ingenic.boards.fields.position"}}</span>
            <input type="number" name="position" value={{this.draft.position}} />
          </label>

          <label class="ingenic-admin-form__wide">
            <span>{{i18n "ingenic.boards.fields.description"}}</span>
            <textarea name="description">{{this.draft.description}}</textarea>
          </label>

          <label class="ingenic-admin-form__wide">
            <span>{{i18n "ingenic.boards.fields.details"}}</span>
            <textarea name="details" rows="5">{{this.draft.details}}</textarea>
          </label>

          <p class="ingenic-admin-form__hint">
            {{i18n "ingenic.boards.fields.details_hint"}}
          </p>

          <label class="ingenic-admin-form__wide">
            <span>{{i18n "ingenic.boards.fields.specs"}}</span>
            <textarea name="specs">{{this.draft.specs}}</textarea>
          </label>

          <p class="ingenic-admin-form__hint">
            {{i18n "ingenic.boards.fields.specs_hint"}}
          </p>

          <label class="checkbox-label">
            <input type="checkbox" name="sold_out" checked={{this.draft.sold_out}} />
            <span>{{i18n "ingenic.boards.fields.sold_out"}}</span>
          </label>

          <p class="ingenic-admin-form__hint">
            {{i18n "ingenic.boards.fields.sold_out_hint"}}
          </p>

          <label class="checkbox-label">
            <input type="checkbox" name="published" checked={{this.draft.published}} />
            <span>{{i18n "ingenic.boards.fields.published"}}</span>
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
              <strong>{{record.name}}</strong>
              <div class="ingenic-admin-list__meta">
                {{record.slug}}
                · {{this.kindLabel record}}
                {{#if record.chip_name}}· {{record.chip_name}}{{/if}}
                {{#if record.series_name}}· {{record.series_name}}{{/if}}
                {{#unless record.published}}
                  · {{i18n "ingenic.boards.withdrawn"}}
                {{/unless}}
              </div>
            </div>
            <div class="ingenic-admin__toolbar">
              <button class="btn" type="button" {{on "click" (fn this.edit record)}}>
                {{i18n "ingenic.edit"}}
              </button>
              {{#if record.published}}
                <button
                  class="btn btn-danger"
                  type="button"
                  {{on "click" (fn this.withdraw record)}}
                >
                  {{i18n "ingenic.boards.withdraw"}}
                </button>
              {{/if}}
            </div>
          </section>
        {{else}}
          <p>{{i18n "ingenic.boards.empty"}}</p>
        {{/each}}
      </div>
    </div>
  </template>
}
