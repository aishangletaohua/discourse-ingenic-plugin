import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { ajax } from "../../lib/ingenic-content-api";
import { i18n } from "discourse-i18n";

const ENDPOINT = "/admin/plugins/discourse-ingenic/site-pages";

const BLANK_PAGE = {
  slug: "",
  title: "",
  body: "",
  position: 0,
  published: true,
};

/**
 * The standalone pages the footer links to.
 *
 * A page is a title, an address and Markdown. The address is not copied from
 * the title: the footer links already name it, and changing the title of the
 * terms must not break the link in a column nobody is looking at.
 *
 * The language is the screen's, like every other content row, so switching the
 * language at the top of the workbench switches which language's copy of a page
 * is being written. The same slug exists once per language.
 */
export default class IngenicSitePageManager extends Component {
  @tracked records = this.args.sitePages ?? [];
  @tracked draft = null;
  @tracked busy = false;
  @tracked message = null;
  @tracked error = null;

  get editing() {
    return Boolean(this.draft?.id);
  }

  @action
  add() {
    this.draft = { ...BLANK_PAGE, position: this.records.length };
    this.message = null;
    this.error = null;
  }

  @action
  edit(page) {
    this.draft = { ...page };
    this.message = null;
    this.error = null;
  }

  @action
  cancel() {
    this.draft = null;
    this.message = null;
    this.error = null;
  }

  // Keeps the draft in step with the form so a refused save or a re-render
  // does not put the old text back into the fields.
  @action
  field(event) {
    const { name, type, value, checked } = event.target;

    if (!name) {
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

    const id = this.draft.id;
    const payload = {
      slug: this.draft.slug,
      title: this.draft.title,
      body: this.draft.body,
      position: this.draft.position,
      published: this.draft.published,
    };

    try {
      const response = await ajax(id ? `${ENDPOINT}/${id}` : ENDPOINT, {
        type: id ? "PUT" : "POST",
        data: payload,
      });

      const saved = response.site_page;
      this.records = id
        ? this.records.map((page) => (page.id === saved.id ? saved : page))
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
  async remove(page, event) {
    event.preventDefault();
    this.error = null;

    if (!window.confirm(i18n("ingenic.site_pages.delete_confirm"))) {
      return;
    }

    try {
      await ajax(`${ENDPOINT}/${page.id}`, { type: "DELETE" });
      this.records = this.records.filter((row) => row.id !== page.id);
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

      <p class="ingenic-admin-note">{{i18n "ingenic.site_pages.hint"}}</p>

      <div class="ingenic-admin__toolbar">
        <button class="btn btn-primary" type="button" {{on "click" this.add}}>
          {{i18n "ingenic.site_pages.add"}}
        </button>
      </div>

      {{#if this.draft}}
        <form class="ingenic-admin-form" {{on "submit" this.save}} {{on "input" this.field}}>
          <h3>
            {{#if this.editing}}
              {{i18n "ingenic.site_pages.edit"}}
            {{else}}
              {{i18n "ingenic.site_pages.new"}}
            {{/if}}
          </h3>

          <label>
            <span>{{i18n "ingenic.site_pages.fields.title"}}</span>
            <input name="title" value={{this.draft.title}} required />
          </label>

          <label>
            <span>{{i18n "ingenic.site_pages.fields.slug"}}</span>
            <input name="slug" value={{this.draft.slug}} required />
            <small>{{i18n "ingenic.site_pages.fields.slug_hint"}}</small>
          </label>

          <label class="ingenic-admin-form__wide">
            <span>{{i18n "ingenic.site_pages.fields.body"}}</span>
            <textarea name="body" rows="14" value={{this.draft.body}}></textarea>
            <small>{{i18n "ingenic.site_pages.fields.body_hint"}}</small>
          </label>

          <label>
            <span>{{i18n "ingenic.site_pages.fields.position"}}</span>
            <input type="number" name="position" value={{this.draft.position}} />
          </label>

          <label class="checkbox-label">
            <input type="checkbox" name="published" checked={{this.draft.published}} />
            <span>{{i18n "ingenic.site_pages.fields.published"}}</span>
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
        {{#each this.records as |page|}}
          <section class="ingenic-admin-list__row">
            <div>
              <strong>{{page.title}}</strong>
              <div class="ingenic-admin-list__meta">
                <a href="/ingenic/pages/{{page.slug}}" target="_blank" rel="noopener noreferrer">
                  /ingenic/pages/{{page.slug}}
                </a>
                {{#unless page.published}}
                  · {{i18n "ingenic.site_pages.unpublished"}}
                {{/unless}}
              </div>
            </div>

            <div class="ingenic-admin__toolbar">
              <button class="btn" type="button" {{on "click" (fn this.edit page)}}>
                {{i18n "ingenic.edit"}}
              </button>
              <button class="btn btn-danger" type="button" {{on "click" (fn this.remove page)}}>
                {{i18n "ingenic.delete"}}
              </button>
            </div>
          </section>
        {{else}}
          <p class="ingenic-admin-note">{{i18n "ingenic.site_pages.empty"}}</p>
        {{/each}}
      </div>
    </div>
  </template>
}
