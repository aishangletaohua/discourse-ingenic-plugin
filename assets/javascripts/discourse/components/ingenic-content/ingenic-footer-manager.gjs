import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { ajax } from "../../lib/ingenic-content-api";
import { i18n } from "discourse-i18n";

const COLUMN_ENDPOINT = "/admin/plugins/discourse-ingenic/footer-columns";
const LINK_ENDPOINT = "/admin/plugins/discourse-ingenic/footer-links";

const BLANK_COLUMN = {
  type: "column",
  title: "",
  position: 0,
  published: true,
};
const BLANK_LINK = {
  type: "link",
  column_id: null,
  label: "",
  href: "",
  external: false,
  position: 0,
  published: true,
};

/**
 * The link columns in the footer.
 *
 * Columns and their links are two tables but one screen: a column is a heading
 * with a list under it, and an editor adding "Developer Services · Downloads"
 * is doing one thing, not two. The links are therefore edited inside the column
 * they belong to, and the form is one form with a type rather than two screens
 * to move between.
 */
export default class IngenicFooterManager extends Component {
  @tracked records = this.args.footerColumns ?? [];
  @tracked draft = null;
  @tracked busy = false;
  @tracked message = null;
  @tracked error = null;

  get isLink() {
    return this.draft?.type === "link";
  }

  @action
  addColumn() {
    this.draft = { ...BLANK_COLUMN };
    this.message = null;
    this.error = null;
  }

  @action
  editColumn(column) {
    this.draft = { type: "column", ...column };
    this.message = null;
    this.error = null;
  }

  @action
  addLink(column) {
    this.draft = { ...BLANK_LINK, column_id: column.id };
    this.message = null;
    this.error = null;
  }

  @action
  editLink(link) {
    this.draft = { type: "link", ...link };
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
    // Only a link has this control, so reading it unguarded would throw on the
    // column form.
    if (this.isLink) {
      form.set("external", String(event.target.elements.external.checked));
    }

    const id = this.draft.id;
    const endpoint = this.isLink ? LINK_ENDPOINT : COLUMN_ENDPOINT;

    try {
      const response = await ajax(id ? `${endpoint}/${id}` : endpoint, {
        type: id ? "PUT" : "POST",
        data: form,
        processData: false,
        contentType: false,
      });

      if (this.isLink) {
        const saved = response.footer_link;
        this.records = this.records.map((column) =>
          column.id === saved.column_id
            ? {
                ...column,
                links: id
                  ? column.links.map((link) => (link.id === saved.id ? saved : link))
                  : [...column.links, saved],
              }
            : column
        );
      } else {
        const saved = response.footer_column;
        this.records = id
          ? this.records.map((column) => (column.id === saved.id ? { ...column, ...saved } : column))
          : [...this.records, { ...saved, links: [] }];
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
  async removeColumn(column, event) {
    event.preventDefault();
    this.error = null;

    if (column.links.length && !this.#confirmRemoval(column.links.length)) {
      return;
    }

    try {
      await ajax(`${COLUMN_ENDPOINT}/${column.id}`, { type: "DELETE" });
      this.records = this.records.filter((item) => item.id !== column.id);
    } catch (failure) {
      this.error = this.#errorMessage(failure);
    }
  }

  @action
  async removeLink(column, link, event) {
    event.preventDefault();
    this.error = null;

    try {
      await ajax(`${LINK_ENDPOINT}/${link.id}`, { type: "DELETE" });
      this.records = this.records.map((item) =>
        item.id === column.id
          ? { ...item, links: item.links.filter((row) => row.id !== link.id) }
          : item
      );
    } catch (failure) {
      this.error = this.#errorMessage(failure);
    }
  }

  // The links go with the column rather than being orphaned, and an editor who
  // has just spent a minute typing six of them should be told before they are.
  #confirmRemoval(count) {
    return window.confirm(
      i18n("ingenic.footer.delete_confirm", { count })
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
        <button class="btn btn-primary" type="button" {{on "click" this.addColumn}}>
          {{i18n "ingenic.footer.add_column"}}
        </button>
      </div>

      {{#if this.draft}}
        <form class="ingenic-admin-form" {{on "submit" this.save}} {{on "input" this.field}}>
          <h3>
            {{#if this.isLink}}
              {{#if this.draft.id}}
                {{i18n "ingenic.footer.edit_link"}}
              {{else}}
                {{i18n "ingenic.footer.new_link"}}
              {{/if}}
            {{else if this.draft.id}}
              {{i18n "ingenic.footer.edit_column"}}
            {{else}}
              {{i18n "ingenic.footer.new_column"}}
            {{/if}}
          </h3>

          {{#if this.isLink}}
            <input type="hidden" name="column_id" value={{this.draft.column_id}} />

            <label>
              <span>{{i18n "ingenic.footer.fields.label"}}</span>
              <input name="label" value={{this.draft.label}} required />
            </label>

            <label>
              <span>{{i18n "ingenic.footer.fields.href"}}</span>
              <input name="href" value={{this.draft.href}} required />
            </label>

            <label class="checkbox-label">
              <input type="checkbox" name="external" checked={{this.draft.external}} />
              <span>{{i18n "ingenic.footer.fields.external"}}</span>
            </label>
          {{else}}
            <label>
              <span>{{i18n "ingenic.footer.fields.title"}}</span>
              <input name="title" value={{this.draft.title}} required />
            </label>
          {{/if}}

          <label>
            <span>{{i18n "ingenic.footer.fields.position"}}</span>
            <input type="number" name="position" value={{this.draft.position}} />
          </label>

          <label class="checkbox-label">
            <input type="checkbox" name="published" checked={{this.draft.published}} />
            <span>{{i18n "ingenic.footer.fields.published"}}</span>
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
        {{#each this.records as |column|}}
          <section class="ingenic-admin-list__row">
            <div>
              <strong>{{column.title}}</strong>
              <div class="ingenic-admin-list__meta">
                {{i18n "ingenic.footer.link_count" count=column.links.length}}
                {{#unless column.published}}
                  · {{i18n "ingenic.footer.unpublished"}}
                {{/unless}}
              </div>

              <ul class="ingenic-admin-sublist">
                {{#each column.links as |link|}}
                  <li class="ingenic-admin-sublist__row">
                    <span>
                      {{link.label}}
                      <span class="ingenic-admin-list__meta">{{link.href}}</span>
                      {{#unless link.published}}
                        <span class="ingenic-admin-list__meta">
                          · {{i18n "ingenic.footer.unpublished"}}
                        </span>
                      {{/unless}}
                    </span>
                    <span class="ingenic-admin__toolbar">
                      <button class="btn btn-small" type="button" {{on "click" (fn this.editLink link)}}>
                        {{i18n "ingenic.edit"}}
                      </button>
                      <button
                        class="btn btn-small btn-danger"
                        type="button"
                        {{on "click" (fn this.removeLink column link)}}
                      >
                        {{i18n "ingenic.delete"}}
                      </button>
                    </span>
                  </li>
                {{/each}}
              </ul>
            </div>

            <div class="ingenic-admin__toolbar">
              <button class="btn" type="button" {{on "click" (fn this.addLink column)}}>
                {{i18n "ingenic.footer.add_link"}}
              </button>
              <button class="btn" type="button" {{on "click" (fn this.editColumn column)}}>
                {{i18n "ingenic.edit"}}
              </button>
              <button class="btn btn-danger" type="button" {{on "click" (fn this.removeColumn column)}}>
                {{i18n "ingenic.delete"}}
              </button>
            </div>
          </section>
        {{else}}
          <p>{{i18n "ingenic.footer.empty"}}</p>
        {{/each}}
      </div>
    </div>
  </template>
}
