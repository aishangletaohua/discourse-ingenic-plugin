import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn, get } from "@ember/helper";
import { ajax } from "discourse/lib/ajax";
import DNativeSelect from "discourse/ui-kit/d-native-select";
import { i18n } from "discourse-i18n";

const ENDPOINT = "/admin/plugins/discourse-ingenic/social-links";

const LINK = "link";
const QR = "qr";

const BLANK = {
  label: "",
  label_zh: "",
  kind: LINK,
  href: "",
  image_url: "",
  qr_image_url: "",
  qr_caption: "",
  qr_caption_zh: "",
  icon_only: false,
  position: 0,
  published: true,
};

/**
 * The partner platforms in the footer strip.
 *
 * Two shapes, and the form shows the fields for the one that was chosen: a link
 * needs somewhere to go, a QR code needs an image. The server refuses an entry
 * that has neither, so what this screen does is make the requirement visible
 * before it is submitted rather than after.
 */
export default class IngenicSocialLinkManager extends Component {
  @tracked records = this.args.socialLinks ?? [];
  @tracked draft = null;
  @tracked busy = false;
  @tracked uploading = false;
  @tracked message = null;
  @tracked error = null;

  get kinds() {
    return [LINK, QR];
  }

  get kindKeys() {
    return {
      link: "admin.ingenic.social_links.kinds.link",
      qr: "admin.ingenic.social_links.kinds.qr",
    };
  }

  get isQr() {
    return this.draft?.kind === QR;
  }

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
  pickKind(value) {
    this.draft = { ...this.draft, kind: value };
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

  // An upload URL comes back with an origin (`//localhost:3000/uploads/…`).
  // Keep the path for local uploads so the picture survives being viewed on a
  // different host; leave anything else — a CDN, an external icon — untouched.
  #localPath(url) {
    if (!url) {
      return null;
    }

    try {
      const parsed = new URL(url, window.location.origin);
      return parsed.pathname.startsWith("/uploads/") ? parsed.pathname : url;
    } catch {
      return url;
    }
  }

  // The strip's entries are usually an icon the team already has on disk, not a
  // URL somebody has published. The file goes to Discourse's own upload
  // endpoint, the same one the composer uses, and the URL it returns is what
  // the record stores. `field` says which of the two pictures was replaced.
  @action
  async uploadImage(field, event) {
    const file = event.target.files?.[0];

    // Clearing the picker lets the same file be chosen twice, and keeps the
    // input from remembering a path that no longer means anything.
    event.target.value = "";

    if (!file || this.uploading) {
      return;
    }

    this.uploading = true;
    this.error = null;

    try {
      const data = new FormData();
      data.append("file", file);
      data.append("upload_type", "composer");

      const upload = await ajax("/uploads.json", {
        type: "POST",
        data,
        processData: false,
        contentType: false,
      });

      // The upload endpoint answers with both a short URL (`upload://…`, a
      // composer-side reference) and the real one. This field is drawn as an
      // image tag, so it needs the real URL — and a path rather than the host
      // the upload happened to run on, which is what a preview or a second
      // domain would otherwise break.
      const url = this.#localPath(upload.url);

      if (url) {
        this.draft = { ...this.draft, [field]: url };
      }
    } catch (uploadError) {
      this.error =
        uploadError?.jqXHR?.responseJSON?.errors?.[0] ||
        uploadError?.message ||
        i18n("admin.ingenic.social_links.upload_failed");
    } finally {
      this.uploading = false;
    }
  }

  @action
  async save(event) {
    event.preventDefault();
    this.busy = true;
    this.message = null;
    this.error = null;

    const form = new FormData(event.target);
    form.set("published", String(event.target.elements.published.checked));
    form.set("icon_only", String(event.target.elements.icon_only.checked));

    const id = this.draft.id;

    try {
      const response = await ajax(id ? `${ENDPOINT}/${id}` : ENDPOINT, {
        type: id ? "PUT" : "POST",
        data: form,
        processData: false,
        contentType: false,
      });

      const saved = response.social_link;
      this.records = id
        ? this.records.map((record) => (record.id === saved.id ? saved : record))
        : [...this.records, saved];
      this.draft = null;
      this.message = i18n("admin.ingenic.saved");
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
    return errors?.join(", ") || i18n("admin.ingenic.save_failed");
  }

  <template>
    <div class="ingenic-admin-panel">
      {{#if this.error}}<p class="ingenic-admin-note ingenic-admin-note--error">{{this.error}}</p>{{/if}}
      {{#if this.message}}<p class="ingenic-admin-note">{{this.message}}</p>{{/if}}
      {{#if this.uploading}}
        <p class="ingenic-admin-note">{{i18n "admin.ingenic.social_links.uploading"}}</p>
      {{/if}}

      <div class="ingenic-admin__toolbar">
        <button class="btn btn-primary" type="button" {{on "click" this.startNew}}>
          {{i18n "admin.ingenic.social_links.add"}}
        </button>
      </div>

      {{#if this.draft}}
        <form class="ingenic-admin-form" {{on "submit" this.save}} {{on "input" this.field}}>
          <h3>
            {{#if this.draft.id}}
              {{i18n "admin.ingenic.social_links.edit_title"}}
            {{else}}
              {{i18n "admin.ingenic.social_links.new_title"}}
            {{/if}}
          </h3>

          <label>
            <span>{{i18n "admin.ingenic.social_links.fields.label"}}</span>
            <input name="label" value={{this.draft.label}} required />
          </label>

          <label>
            <span>{{i18n "admin.ingenic.social_links.fields.label_zh"}}</span>
            <input name="label_zh" value={{this.draft.label_zh}} />
          </label>

          <label>
            <span>{{i18n "admin.ingenic.social_links.fields.kind"}}</span>
            <DNativeSelect
              name="kind"
              @includeNone={{false}}
              @value={{this.draft.kind}}
              @onChange={{this.pickKind}}
              as |select|
            >
              {{#each this.kinds as |kind|}}
                <select.Option @value={{kind}}>{{i18n (get this.kindKeys kind)}}</select.Option>
              {{/each}}
            </DNativeSelect>
          </label>

          {{#if this.isQr}}
            <label>
              <span>{{i18n "admin.ingenic.social_links.fields.qr_image_url"}}</span>
              <input name="qr_image_url" value={{this.draft.qr_image_url}} />
            </label>

            <label>
              <span>{{i18n "admin.ingenic.social_links.fields.upload_qr_image"}}</span>
              <input
                type="file"
                accept="image/*"
                disabled={{this.uploading}}
                {{on "change" (fn this.uploadImage "qr_image_url")}}
              />
            </label>

            <label>
              <span>{{i18n "admin.ingenic.social_links.fields.qr_caption"}}</span>
              <input name="qr_caption" value={{this.draft.qr_caption}} />
            </label>

            <label>
              <span>{{i18n "admin.ingenic.social_links.fields.qr_caption_zh"}}</span>
              <input name="qr_caption_zh" value={{this.draft.qr_caption_zh}} />
            </label>
          {{else}}
            <label>
              <span>{{i18n "admin.ingenic.social_links.fields.href"}}</span>
              <input name="href" value={{this.draft.href}} />
            </label>
          {{/if}}

          <label>
            <span>{{i18n "admin.ingenic.social_links.fields.image_url"}}</span>
            <input name="image_url" value={{this.draft.image_url}} />
          </label>

          <label>
            <span>{{i18n "admin.ingenic.social_links.fields.upload_image"}}</span>
            <input
              type="file"
              accept="image/*"
              disabled={{this.uploading}}
              {{on "change" (fn this.uploadImage "image_url")}}
            />
          </label>

          <p class="ingenic-admin-form__hint">
            {{i18n "admin.ingenic.social_links.fields.image_hint"}}
          </p>

          <label class="checkbox-label">
            <input type="checkbox" name="icon_only" checked={{this.draft.icon_only}} />
            <span>{{i18n "admin.ingenic.social_links.fields.icon_only"}}</span>
          </label>

          <p class="ingenic-admin-form__hint">
            {{i18n "admin.ingenic.social_links.fields.icon_only_hint"}}
          </p>

          <label>
            <span>{{i18n "admin.ingenic.social_links.fields.position"}}</span>
            <input type="number" name="position" value={{this.draft.position}} />
          </label>

          <label class="checkbox-label">
            <input type="checkbox" name="published" checked={{this.draft.published}} />
            <span>{{i18n "admin.ingenic.social_links.fields.published"}}</span>
          </label>

          <div class="ingenic-admin__toolbar">
            <button class="btn btn-primary" type="submit" disabled={{or this.busy this.uploading}}>
              {{i18n "admin.ingenic.save"}}
            </button>
            <button class="btn" type="button" {{on "click" this.cancel}}>
              {{i18n "admin.ingenic.cancel"}}
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
                {{i18n (get this.kindKeys record.kind)}}
                {{#if record.href}}· {{record.href}}{{/if}}
                {{#if record.position}}· {{record.position}}{{/if}}
                {{#unless record.published}}
                  · {{i18n "admin.ingenic.social_links.unpublished"}}
                {{/unless}}
              </div>
            </div>
            <div class="ingenic-admin__toolbar">
              <button class="btn" type="button" {{on "click" (fn this.edit record)}}>
                {{i18n "admin.ingenic.edit"}}
              </button>
              <button class="btn btn-danger" type="button" {{on "click" (fn this.remove record)}}>
                {{i18n "admin.ingenic.delete"}}
              </button>
            </div>
          </section>
        {{else}}
          <p>{{i18n "admin.ingenic.social_links.empty"}}</p>
        {{/each}}
      </div>
    </div>
  </template>
}
