import Component from "@glimmer/component";
import { action } from "@ember/object";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { eq } from "discourse/truth-helpers";
import { ajax } from "../../lib/ingenic-content-api";
import { i18n } from "discourse-i18n";
import dIcon from "discourse/ui-kit/helpers/d-icon";

const BASE = "/admin/plugins/discourse-ingenic";
const TOOLBAR_KEY = "ingenic.documentation.workbench.toolbar";

/**
 * Editor for a single page.
 *
 * Everything that locates a page is decided above the pane: the top bar picks
 * the chip and the language, the version list narrows it to one manual, and the
 * tree on the left owns the structure — the + menu says whether a row is an
 * article or a folder, indentation and drag decide where it sits, and
 * double-clicking the name renames it. A page's address is derived when it is
 * created; the editor does not ask for it again.
 *
 * What is left is the article itself. Apart from its name, the pane is the
 * writing surface: one large textarea, with save, published state and delete
 * kept in a single compact toolbar so they never push the text into a corner.
 *
 * The textarea is Markdown, so the tools row writes Markdown into it the way a
 * composer does: bold, italic, heading, quote, code, link and list act on the
 * selection or start a block at the caret. Images are the one thing Markdown
 * cannot supply by itself, so the image button uploads through Discourse's own
 * `/uploads.json`, the same endpoint the composer uses, and inserts the
 * returned short URL as `![alt](url)`. Pasting or dropping an image file does
 * the same, because that is how screenshots usually arrive.
 *
 * A page that this version only inherits is edited like any other. Saving it
 * first materialises the row into this version (see the manager), so the user
 * never has to know whether a row is inherited before typing into it.
 *
 * The body has an edit and a preview tab. The preview is cooked by the server
 * with the same pipeline the reader's page uses, because approximating Markdown
 * in the browser is how an editor and the article it produces drift apart.
 */
export default class IngenicDocPageForm extends Component {
  @tracked bodyDraft = null;
  @tracked publishedDraft = null;
  @tracked tabDraft = null;
  @tracked preview = null;
  @tracked previewBusy = false;
  @tracked uploading = false;
  @tracked uploadError = null;

  #bodyElement = null;
  #fileInput = null;

  // The tree decides whether a row is an article or a folder (the + menu asks
  // once, at creation). The editor only needs to know which form to show.
  get folder() {
    return this.args.page.kind === "folder";
  }

  get body() {
    if (this.bodyDraft?.id === this.args.page.id) {
      return this.bodyDraft.body;
    }

    return this.args.page.body ?? "";
  }

  // Read through the page's id, not a bare flag: selecting another row has to
  // forget a draft left on this one, or the next save writes it to the wrong
  // article.
  get published() {
    if (this.publishedDraft?.id === this.args.page.id) {
      return this.publishedDraft.published;
    }

    return this.args.page.published;
  }

  get tab() {
    if (this.tabDraft?.id === this.args.page.id) {
      return this.tabDraft.tab;
    }

    return "edit";
  }

  get previewing() {
    return this.tab === "preview";
  }

  get previewHtml() {
    if (this.preview?.id !== this.args.page.id) {
      return "";
    }

    return this.preview.html;
  }

  // An upload must finish before the article is saved: the URL it inserts is
  // the only part of the image the page stores, and saving around it would
  // leave the textarea and the saved body disagreeing.
  get saveDisabled() {
    return this.args.busy || this.uploading;
  }

  // Keyed to the page, like the drafts: an error from the previous article
  // must not follow the author to the next one.
  get uploadErrorMessage() {
    if (this.uploadError?.id !== this.args.page.id) {
      return null;
    }

    return this.uploadError.message;
  }

  @action
  registerBody(element) {
    this.#bodyElement = element;
  }

  @action
  registerFileInput(element) {
    this.#fileInput = element;
  }

  @action
  updateBody(event) {
    this.bodyDraft = { id: this.args.page.id, body: event.target.value };
  }

  @action
  updatePublished(event) {
    this.publishedDraft = {
      id: this.args.page.id,
      published: event.target.checked,
    };
  }

  @action
  showEdit(event) {
    event?.preventDefault();
    this.tabDraft = { id: this.args.page.id, tab: "edit" };
  }

  @action
  async showPreview(event) {
    event?.preventDefault();
    this.tabDraft = { id: this.args.page.id, tab: "preview" };
    this.previewBusy = true;

    try {
      const response = await ajax(`${BASE}/documentation/preview`, {
        type: "POST",
        data: {
          version_id: this.args.page.version_id,
          body: this.body,
        },
      });

      this.preview = { id: this.args.page.id, html: response.html ?? "" };
    } catch {
      this.preview = {
        id: this.args.page.id,
        html: `<p class="ingenic-doc-editor__preview-error">${i18n(
          "ingenic.documentation.workbench.preview_failed"
        )}</p>`,
      };
    } finally {
      this.previewBusy = false;
    }
  }

  // The editor sends only what it owns. Title, kind, parent, slug and locale
  // are not in this pane: the tree named the row, the + menu picked the kind,
  // the structure is the row's place in the tree, and the address and language
  // come from the top bar and the version being edited.
  @action
  save(event) {
    event?.preventDefault();

    this.args.onSave(this.args.page, {
      body: this.folder ? null : this.body,
      published: this.published,
    });

    // The preview was rendered from text that no longer matches the saved
    // article; drop it rather than show a stale page.
    this.preview = null;
    this.showEdit();
  }

  // Markdown tools -----------------------------------------------------------
  // One entry point for every toolbar button: a button is a `kind`, and this
  // maps it to the edit it performs. Keeping the mapping here rather than in
  // seven template closures means the placeholder wording lives with the
  // action that needs it.
  @action
  format(kind, event) {
    event?.preventDefault();

    switch (kind) {
      case "bold":
        this.#wrap("**", "**", "placeholder_bold");
        break;
      case "italic":
        this.#wrap("*", "*", "placeholder_italic");
        break;
      case "heading":
        this.#prefix("## ");
        break;
      case "quote":
        this.#prefix("> ");
        break;
      case "list":
        this.#prefix("- ");
        break;
      case "code":
        this.#code();
        break;
      case "link":
        this.#link();
        break;
    }
  }

  // Images -------------------------------------------------------------------
  @action
  pickImage(event) {
    event?.preventDefault();

    if (!this.uploading) {
      this.#fileInput?.click();
    }
  }

  @action
  async uploadFromInput(event) {
    const files = this.#imageFiles(event.target.files);

    // The picker keeps the previous choice so the same file can be sent twice;
    // clearing it here also makes the field reusable after an upload.
    event.target.value = "";

    await this.uploadImages(files);
  }

  // A screenshot is normally pasted, not chosen from disk. Only an image file
  // is intercepted: text pastes keep their ordinary behaviour.
  @action
  pasteImage(event) {
    const files = this.#imageFiles(event.clipboardData);

    if (!files.length) {
      return;
    }

    event.preventDefault();
    this.uploadImages(files);
  }

  @action
  allowDrop(event) {
    const types = Array.from(event.dataTransfer?.types ?? []);

    if (types.includes("Files")) {
      event.preventDefault();
      event.dataTransfer.dropEffect = "copy";
    }
  }

  @action
  dropImage(event) {
    const files = this.#imageFiles(event.dataTransfer);

    if (!files.length) {
      return;
    }

    event.preventDefault();
    this.uploadImages(files);
  }

  async uploadImages(files) {
    if (!files.length || this.uploading) {
      return;
    }

    // Uploading takes a moment, and the author can switch rows while it runs.
    // Remember which page asked, so the URLs are never written into another
    // article when the request comes back.
    const pageId = this.args.page.id;
    this.uploading = true;
    this.uploadError = null;

    try {
      const snippets = [];

      for (const file of files) {
        const data = new FormData();
        data.append("file", file);
        data.append("upload_type", "composer");

        const upload = await ajax("/uploads.json", {
          type: "POST",
          data,
          processData: false,
          contentType: false,
        });

        if (this.args.page.id !== pageId) {
          return;
        }

        const url = upload.short_url || upload.url;

        if (url) {
          snippets.push(`![${this.#altText(file.name)}](${url})`);
        }
      }

      if (snippets.length && this.args.page.id === pageId) {
        this.#insertAtCaret(snippets.join("\n\n"));
      }
    } catch (error) {
      if (this.args.page.id === pageId) {
        this.uploadError = {
          id: pageId,
          message:
            error?.jqXHR?.responseJSON?.errors?.[0] ||
            error?.message ||
            i18n(`${TOOLBAR_KEY}.upload_failed`),
        };
      }
    } finally {
      this.uploading = false;
    }
  }

  #imageFiles(list) {
    const files = Array.from(list ?? []);

    // `files` is the normal path; `items` is how a screenshot arrives in some
    // browsers, with the file only as an item rather than an entry in `files`.
    const images = files.filter((file) => file.type?.startsWith("image/"));

    if (images.length || !list?.items) {
      return images;
    }

    return Array.from(list.items)
      .filter((item) => item.kind === "file" && item.type?.startsWith("image/"))
      .map((item) => item.getAsFile())
      .filter(Boolean);
  }

  #altText(name) {
    return String(name || "image")
      .replace(/\.[^.]*$/, "")
      .replace(/[[\]\\]/g, "")
      .trim() || "image";
  }

  #selection() {
    const element = this.#bodyElement;
    const value = this.body;

    return {
      start: element?.selectionStart ?? value.length,
      end: element?.selectionEnd ?? value.length,
    };
  }

  // The textarea is bound to a tracked draft, so a write survives the pane's
  // re-render but the caret does not. Both helpers that edit the text put the
  // selection back after the render rather than before it, when the browser
  // has already applied the new value.
  #selectLater(start, end) {
    requestAnimationFrame(() => {
      const element = this.#bodyElement;

      if (!element) {
        return;
      }

      element.focus();
      element.setSelectionRange(start, end);
    });
  }

  #write(value, start, end) {
    this.bodyDraft = { id: this.args.page.id, body: value };
    this.#selectLater(start, end);
  }

  #wrap(before, after, placeholderKey) {
    const value = this.body;
    const { start, end } = this.#selection();
    const selected =
      value.slice(start, end) || i18n(`${TOOLBAR_KEY}.${placeholderKey}`);
    const next =
      value.slice(0, start) + before + selected + after + value.slice(end);

    this.#write(next, start + before.length, start + before.length + selected.length);
  }

  // Line tools apply to every line the selection touches, the way a Markdown
  // editor's block commands do; a bare caret gets the prefix on its own line.
  #prefix(prefix) {
    const value = this.body;
    const { start, end } = this.#selection();
    const lineStart = value.lastIndexOf("\n", start - 1) + 1;
    const nextBreak = value.indexOf("\n", end);
    const lineEnd = nextBreak === -1 ? value.length : nextBreak;
    const block = value.slice(lineStart, lineEnd);
    const prefixed = block
      .split("\n")
      .map((line) => `${prefix}${line}`)
      .join("\n");
    const linesBeforeEnd = block.slice(0, end - lineStart).split("\n").length;

    const next = value.slice(0, lineStart) + prefixed + value.slice(lineEnd);
    const nextStart = start + prefix.length;
    const nextEnd = end + prefix.length * Math.max(linesBeforeEnd, 1);

    this.#write(next, nextStart, nextEnd);
  }

  // A single line is inline code; several lines become a fenced block, which
  // is the only way backticks survive their own contents.
  #code() {
    const value = this.body;
    const { start, end } = this.#selection();

    if (value.slice(start, end).includes("\n")) {
      this.#wrap("```\n", "\n```", "placeholder_code");
    } else {
      this.#wrap("`", "`", "placeholder_code");
    }
  }

  #link() {
    const value = this.body;
    const { start, end } = this.#selection();
    const selected =
      value.slice(start, end) || i18n(`${TOOLBAR_KEY}.placeholder_link`);
    const url = "https://";
    const next = `${value.slice(0, start)}[${selected}](${url})${value.slice(
      end
    )}`;
    const urlStart = start + selected.length + 3;

    // The address is what the author fills in next, so the caret lands on it
    // rather than after the closing parenthesis.
    this.#write(next, urlStart, urlStart + url.length);
  }

  // An image belongs on its own lines: pasted into the middle of a sentence,
  // Markdown would keep it in the paragraph and the text would wrap around it.
  #insertAtCaret(snippet) {
    const value = this.body;
    const { start, end } = this.#selection();
    const lead = start === 0 || value[start - 1] === "\n" ? "" : "\n\n";
    const trail = end === value.length || value[end] === "\n" ? "" : "\n\n";
    const insertion = `${lead}${snippet}${trail}`;
    const next = value.slice(0, start) + insertion + value.slice(end);

    this.#write(next, start + insertion.length, start + insertion.length);
  }

  <template>
    <div class="ingenic-doc-editor">
      <div class="ingenic-doc-editor__toolbar">
        {{#unless this.folder}}
          <div class="ingenic-doc-editor__tabs" role="tablist">
            <button
              type="button"
              class="ingenic-doc-editor__tab {{if (eq this.tab 'edit') 'is-active'}}"
              {{on "click" this.showEdit}}
            >{{i18n "ingenic.documentation.workbench.edit_tab"}}</button>
            <button
              type="button"
              class="ingenic-doc-editor__tab {{if (eq this.tab 'preview') 'is-active'}}"
              disabled={{this.previewBusy}}
              {{on "click" this.showPreview}}
            >{{i18n "ingenic.documentation.workbench.preview_tab"}}</button>
          </div>
        {{/unless}}

        <span class="ingenic-doc-editor__toolbar-spacer"></span>

        <label class="checkbox-label ingenic-doc-editor__published">
          <input
            type="checkbox"
            checked={{this.published}}
            disabled={{@busy}}
            {{on "change" this.updatePublished}}
          />
          <span>{{i18n "ingenic.documentation.published"}}</span>
        </label>

        <button type="button" class="btn btn-primary btn-small" disabled={{this.saveDisabled}} {{on "click" this.save}}>
          {{i18n "ingenic.save"}}
        </button>

        {{#unless @page.inherited}}
          <button
            type="button"
            class="btn btn-danger btn-small"
            disabled={{@busy}}
            {{on "click" (fn @onDestroy @page)}}
          >{{i18n "ingenic.documentation.delete_page"}}</button>
        {{/unless}}
      </div>

      {{#if this.previewing}}
        <div class="ingenic-doc-editor__preview">
          {{#if this.previewBusy}}
            <p class="ingenic-admin-note">
              {{i18n "ingenic.documentation.workbench.preview_loading"}}
            </p>
          {{else}}
            {{{this.previewHtml}}}
          {{/if}}
        </div>
      {{else if this.folder}}
        <p class="ingenic-admin-form__notice">
          {{i18n "ingenic.documentation.folder_hint"}}
        </p>
      {{else}}
        <div class="ingenic-doc-editor__tools">
          <button
            type="button"
            class="ingenic-doc-editor__tool"
            title={{i18n "ingenic.documentation.workbench.toolbar.bold"}}
            aria-label={{i18n "ingenic.documentation.workbench.toolbar.bold"}}
            {{on "click" (fn this.format "bold")}}
          >{{dIcon "bold"}}</button>
          <button
            type="button"
            class="ingenic-doc-editor__tool"
            title={{i18n "ingenic.documentation.workbench.toolbar.italic"}}
            aria-label={{i18n "ingenic.documentation.workbench.toolbar.italic"}}
            {{on "click" (fn this.format "italic")}}
          >{{dIcon "italic"}}</button>
          <button
            type="button"
            class="ingenic-doc-editor__tool"
            title={{i18n "ingenic.documentation.workbench.toolbar.heading"}}
            aria-label={{i18n "ingenic.documentation.workbench.toolbar.heading"}}
            {{on "click" (fn this.format "heading")}}
          >{{dIcon "heading"}}</button>
          <span class="ingenic-doc-editor__tool-divider" aria-hidden="true"></span>
          <button
            type="button"
            class="ingenic-doc-editor__tool"
            title={{i18n "ingenic.documentation.workbench.toolbar.quote"}}
            aria-label={{i18n "ingenic.documentation.workbench.toolbar.quote"}}
            {{on "click" (fn this.format "quote")}}
          >{{dIcon "quote-right"}}</button>
          <button
            type="button"
            class="ingenic-doc-editor__tool"
            title={{i18n "ingenic.documentation.workbench.toolbar.list"}}
            aria-label={{i18n "ingenic.documentation.workbench.toolbar.list"}}
            {{on "click" (fn this.format "list")}}
          >{{dIcon "list-ul"}}</button>
          <button
            type="button"
            class="ingenic-doc-editor__tool"
            title={{i18n "ingenic.documentation.workbench.toolbar.code"}}
            aria-label={{i18n "ingenic.documentation.workbench.toolbar.code"}}
            {{on "click" (fn this.format "code")}}
          >{{dIcon "code"}}</button>
          <button
            type="button"
            class="ingenic-doc-editor__tool"
            title={{i18n "ingenic.documentation.workbench.toolbar.link"}}
            aria-label={{i18n "ingenic.documentation.workbench.toolbar.link"}}
            {{on "click" (fn this.format "link")}}
          >{{dIcon "link"}}</button>
          <span class="ingenic-doc-editor__tool-divider" aria-hidden="true"></span>
          <button
            type="button"
            class="ingenic-doc-editor__tool"
            title={{i18n "ingenic.documentation.workbench.toolbar.image"}}
            aria-label={{i18n "ingenic.documentation.workbench.toolbar.image"}}
            disabled={{this.uploading}}
            {{on "click" this.pickImage}}
          >{{dIcon "image"}}</button>

          {{#if this.uploading}}
            <span class="ingenic-doc-editor__tool-status">
              {{i18n "ingenic.documentation.workbench.toolbar.uploading"}}
            </span>
          {{/if}}
        </div>

        <input
          type="file"
          accept="image/*"
          multiple
          class="ingenic-doc-editor__file-input"
          {{didInsert this.registerFileInput}}
          {{on "change" this.uploadFromInput}}
        />

        <textarea
          class="ingenic-doc-editor__body"
          value={{this.body}}
          placeholder={{i18n "ingenic.documentation.workbench.body_placeholder"}}
          {{didInsert this.registerBody}}
          {{on "input" this.updateBody}}
          {{on "paste" this.pasteImage}}
          {{on "dragover" this.allowDrop}}
          {{on "drop" this.dropImage}}
        ></textarea>

        {{#if this.uploadErrorMessage}}
          <p class="ingenic-admin-note ingenic-admin-note--error">
            {{this.uploadErrorMessage}}
          </p>
        {{/if}}
      {{/if}}
    </div>
  </template>
}
