import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn, get } from "@ember/helper";
import { ajax } from "../../lib/ingenic-content-api";
import DNativeSelect from "discourse/ui-kit/d-native-select";
import { i18n } from "discourse-i18n";

const ENDPOINT = "/admin/plugins/discourse-ingenic/downloads";

// A new resource starts at the lowest tier and unpublished. Both defaults are
// the ones that cannot leak a file by accident.
const BLANK = {
  family: "chip",
  product_id: "",
  category_id: "",
  version: "",
  name: "",
  description: "",
  platform: "",
  architecture: "",
  access_level: "public_login",
  point_cost: 0,
  file_url: "",
  file_size: "",
  sha256: "",
  released_on: "",
  position: 0,
  published: false,
};

/**
 * SDK and firmware resources: the list, and the form that creates and edits
 * them, including the upload.
 *
 * The file input is the reason the form is submitted as FormData rather than as
 * a plain object: a firmware image cannot be sent as a URL-encoded field. The
 * server decides between the upload and the URL, and clears the URL when a file
 * arrives, so the form does not have to arbitrate between them.
 */
export default class IngenicDownloadManager extends Component {
  @tracked records = this.args.downloads ?? [];
  @tracked draft = null;
  @tracked busy = false;
  @tracked message = null;
  @tracked error = null;
  // The file that has been chosen but not saved yet. A browser will not
  // let a filename be written into a file input, so the name is kept here
  // and drawn in the form rather than by the control.
  @tracked chosenFile = null;

  // The classification list is editable, so it arrives with the listing rather
  // than being a fixed set here. An empty list is a normal state: nothing has
  // been filed yet, and the field offers "none" until the list is populated.
  get categories() {
    return this.args.categories ?? [];
  }

  get accessLevels() {
    return this.args.accessLevels ?? [];
  }

  get accessLevelKeys() {
    return {
      public_login: "ingenic.downloads.access.public_login",
      login_form: "ingenic.downloads.access.login_form",
      login_form_request: "ingenic.downloads.access.login_form_request",
    };
  }

  get accessLevelHint() {
    const key = this.accessLevelKeys[this.draft?.access_level];
    return key ? i18n(`${key}_hint`) : null;
  }

  // An algorithm is offered across chips, so the part-number field would be a
  // false attachment. The server does not require one for that family either.
  get isAlgorithm() {
    return this.draft?.family === "algorithm";
  }

  // The chips this account may file a resource under, in the screen's language.
  // A resource takes its language from the chip; an algorithm, which has no
  // chip, stays in the language the screen is working in.
  get chips() {
    return this.args.chips ?? [];
  }

  get chipLabel() {
    return (chip) =>
      chip.series_name ? `${chip.series_name} › ${chip.name}` : chip.name;
  }

  // An uploaded file carries its own digest; the legacy column is what a
  // hand-entered URL used to come with. Showing whichever exists is what
  // keeps this field from reading blank on a file the server hashed.
  get checksum() {
    return this.draft?.file_sha256 || this.draft?.sha256 || "";
  }

  // What the row already holds. The file input cannot say it - a browser
  // will not let a filename be written into one - so the form says it.
  get storedFileLabel() {
    const name = this.draft?.original_filename;

    if (!name) {
      return null;
    }

    return this.draft?.file_size ? `${name} (${this.draft.file_size})` : name;
  }

  @action
  startNew() {
    this.draft = { ...BLANK };
    this.chosenFile = null;
    this.message = null;
    this.error = null;
  }

  @action
  edit(record) {
    this.draft = {
      ...record,
      file_url: record.file_url ?? "",
      product_id: record.product_id ?? "",
    };
    this.chosenFile = null;
    this.message = null;
    this.error = null;
  }

  @action
  cancel() {
    this.draft = null;
    this.chosenFile = null;
    this.message = null;
    this.error = null;
  }

  // The ui-kit selects drive the draft rather than the form, so the values they
  // own are kept in step here. They are still submitted as form fields: the
  // select carries a name and the browser reads the chosen option back out.
  @action
  pickFamily(value) {
    this.draft = {
      ...this.draft,
      family: value,
      // Switching an existing chip resource to an algorithm drops the chip
      // rather than leaving a stale one behind a field that is not drawn.
      product_id: value === "algorithm" ? "" : this.draft.product_id,
    };
  }

  @action
  pickChip(value) {
    this.draft = { ...this.draft, product_id: value ?? "" };
  }

  @action
  pickCategory(value) {
    this.draft = { ...this.draft, category_id: value };
  }

  @action
  pickAccessLevel(value) {
    this.draft = { ...this.draft, access_level: value };
  }

  // A chosen file is not a draft value: it is the browser's FileList on
  // the control, and the filename is the only part of it the form can
  // usefully show.
  @action
  pickFile(event) {
    this.chosenFile = event.target.files?.[0]?.name ?? null;
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
    // Checkboxes are absent from FormData when unchecked, which the server reads
    // as "leave it alone" — the opposite of what unchecking means here.
    form.set("published", String(event.target.elements.published.checked));

    const id = this.draft.id;

    try {
      const response = await ajax(id ? `${ENDPOINT}/${id}` : ENDPOINT, {
        type: id ? "PUT" : "POST",
        data: form,
        // Both are required for a multipart body: jQuery would otherwise
        // url-encode the FormData and drop the browser's boundary header.
        processData: false,
        contentType: false,
      });

      const saved = response.download;
      this.records = id
        ? this.records.map((record) => (record.id === saved.id ? saved : record))
        : [...this.records, saved];
      this.draft = null;
      this.chosenFile = null;
      this.message = i18n("ingenic.saved");
    } catch (failure) {
      this.error = this.#errorMessage(failure);
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
      this.error = this.#errorMessage(failure);
    }
  }

  #errorMessage(failure) {
    const errors = failure?.jqXHR?.responseJSON?.errors;
    return errors?.join(", ") || i18n("ingenic.save_failed");
  }

  <template>
    <div class="ingenic-admin-panel">
      {{#if @storageWritable}}
        <p class="ingenic-admin-note">{{i18n "ingenic.downloads.storage_ok"}}</p>
      {{else}}
        <p class="ingenic-admin-note ingenic-admin-note--error">
          {{i18n "ingenic.downloads.storage_unavailable"}}
        </p>
      {{/if}}

      {{#if this.error}}<p class="ingenic-admin-note ingenic-admin-note--error">{{this.error}}</p>{{/if}}
      {{#if this.message}}<p class="ingenic-admin-note">{{this.message}}</p>{{/if}}

      <div class="ingenic-admin__toolbar">
        <button class="btn btn-primary" type="button" {{on "click" this.startNew}}>
          {{i18n "ingenic.downloads.add"}}
        </button>
      </div>

      {{#if this.draft}}
        <form class="ingenic-admin-form" {{on "submit" this.save}} {{on "input" this.field}}>
          <h3>
            {{#if this.draft.id}}
              {{i18n "ingenic.downloads.edit_title"}}
            {{else}}
              {{i18n "ingenic.downloads.new_title"}}
            {{/if}}
          </h3>

          <label>
            <span>{{i18n "ingenic.downloads.fields.name"}}</span>
            <input name="name" value={{this.draft.name}} required />
          </label>

          <label>
            <span>{{i18n "ingenic.downloads.fields.family"}}</span>
            <DNativeSelect
              name="family"
              @includeNone={{false}}
              @value={{this.draft.family}}
              @onChange={{this.pickFamily}}
              as |select|
            >
              <select.Option @value="chip">{{i18n "ingenic.downloads.families.chip"}}</select.Option>
              <select.Option @value="algorithm">{{i18n "ingenic.downloads.families.algorithm"}}</select.Option>
            </DNativeSelect>
          </label>

          {{#unless this.isAlgorithm}}
            <label>
              <span>{{i18n "ingenic.downloads.fields.chip_from_tree"}}</span>
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
          {{/unless}}

          <label>
            <span>{{i18n "ingenic.downloads.fields.kind"}}</span>
            {{! The ui-kit select rather than a bare <select>: a Glimmer-rendered
                `selected` attribute does not survive re-rendering, which is the
                bug DNativeSelect exists to work around. }}
            <DNativeSelect
              name="category_id"
              @includeNone={{true}}
              @nonePlaceholder={{i18n "ingenic.downloads.fields.no_category"}}
              @value={{this.draft.category_id}}
              @onChange={{this.pickCategory}}
              as |select|
            >
              {{#each this.categories as |category|}}
                <select.Option @value={{category.id}}>{{category.name}}</select.Option>
              {{/each}}
            </DNativeSelect>
          </label>

          <label>
            <span>{{i18n "ingenic.downloads.fields.version"}}</span>
            <input name="version" value={{this.draft.version}} />
          </label>

          <label>
            <span>{{i18n "ingenic.downloads.fields.platform"}}</span>
            <input name="platform" value={{this.draft.platform}} />
          </label>

          <label>
            <span>{{i18n "ingenic.downloads.fields.architecture"}}</span>
            <input name="architecture" value={{this.draft.architecture}} />
          </label>

          <label>
            <span>{{i18n "ingenic.downloads.fields.access_level"}}</span>
            <DNativeSelect
              name="access_level"
              @includeNone={{false}}
              @value={{this.draft.access_level}}
              @onChange={{this.pickAccessLevel}}
              as |select|
            >
              {{#each this.accessLevels as |level|}}
                <select.Option @value={{level}}>
                  {{i18n (get this.accessLevelKeys level)}}
                </select.Option>
              {{/each}}
            </DNativeSelect>
          </label>

          {{#if this.accessLevelHint}}
            <p class="ingenic-admin-form__hint">{{this.accessLevelHint}}</p>
          {{/if}}

          <label>
            <span>{{i18n "ingenic.downloads.fields.point_cost"}}</span>
            <input type="number" name="point_cost" min="0" value={{this.draft.point_cost}} />
          </label>

          <p class="ingenic-admin-form__hint">
            {{i18n "ingenic.downloads.fields.point_cost_hint"}}
          </p>

          <label class="ingenic-admin-upload">
            <span>{{i18n "ingenic.downloads.fields.file"}}</span>
            {{! The control is kept for what it does - a click anywhere
                in this label opens the picker - and taken out of the
                layout: a browser prints its own caption beside a file
                input and no property sets that text. }}
            <input
              class="ingenic-admin-upload__input"
              type="file"
              name="file"
              {{on "change" this.pickFile}}
            />
            <span class="ingenic-admin-upload__button">
              {{i18n "ingenic.downloads.fields.choose_file"}}
            </span>
          </label>

          {{#if this.chosenFile}}
            <p class="ingenic-admin-form__hint">
              {{i18n "ingenic.downloads.fields.replacing_file" file=this.chosenFile}}
            </p>
          {{else if this.storedFileLabel}}
            <p class="ingenic-admin-form__hint">
              {{i18n "ingenic.downloads.fields.stored_file" file=this.storedFileLabel}}
            </p>
          {{/if}}

          <p class="ingenic-admin-form__hint">
            {{i18n "ingenic.downloads.fields.file_hint"}}
          </p>

          <label>
            <span>{{i18n "ingenic.downloads.fields.file_url"}}</span>
            <input name="file_url" value={{this.draft.file_url}} />
          </label>

          <label>
            <span>{{i18n "ingenic.downloads.fields.file_size"}}</span>
            <input name="file_size" value={{this.draft.file_size}} />
          </label>

          <label>
            <span>{{i18n "ingenic.downloads.fields.sha256"}}</span>
            <input name="sha256" value={{this.checksum}} />
          </label>

          <p class="ingenic-admin-form__hint">
            {{i18n "ingenic.downloads.fields.sha256_hint"}}
          </p>

          <label>
            <span>{{i18n "ingenic.downloads.fields.released_on"}}</span>
            <input type="date" name="released_on" value={{this.draft.released_on}} />
          </label>

          <label>
            <span>{{i18n "ingenic.downloads.fields.position"}}</span>
            <input type="number" name="position" value={{this.draft.position}} />
          </label>

          <label>
            <span>{{i18n "ingenic.downloads.fields.description"}}</span>
            <textarea name="description">{{this.draft.description}}</textarea>
          </label>

          <label class="checkbox-label">
            <input type="checkbox" name="published" checked={{this.draft.published}} />
            <span>{{i18n "ingenic.downloads.fields.published"}}</span>
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
                {{record.product_name}}
                {{#if record.category_name}}· {{record.category_name}}{{/if}}
                {{#if record.version}}· {{record.version}}{{/if}}
                · {{i18n (get this.accessLevelKeys record.access_level)}}
                {{#if record.point_cost}}
                  · {{i18n "ingenic.downloads.costs_points" points=record.point_cost}}
                {{/if}}
                {{#if record.stored}}
                  · {{i18n "ingenic.downloads.stored"}}
                {{/if}}
                {{#unless record.published}}
                  · {{i18n "ingenic.downloads.withdrawn"}}
                {{/unless}}
              </div>
              <div class="ingenic-admin-list__meta">
                {{i18n "ingenic.downloads.pending_count" count=record.pending_requests}}
                ·
                {{i18n "ingenic.downloads.grant_count" count=record.active_grants}}
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
                  {{i18n "ingenic.downloads.withdraw"}}
                </button>
              {{/if}}
            </div>
          </section>
        {{else}}
          <p>{{i18n "ingenic.downloads.empty"}}</p>
        {{/each}}
      </div>
    </div>
  </template>
}
