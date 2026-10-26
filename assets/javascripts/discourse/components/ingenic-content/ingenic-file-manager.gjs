import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { ajax } from "../../lib/ingenic-content-api";
import { i18n } from "discourse-i18n";
import dIcon from "discourse/ui-kit/helpers/d-icon";

const ENDPOINT = "/admin/plugins/discourse-ingenic/files";
const UPLOADS = `${ENDPOINT}/uploads`;

// Eight megabytes a request, the same limit the download centre's uploads use:
// the web server in front of the forum refuses bodies over ten, and an SDK
// archive can be three gigabytes.
const CHUNK_SIZE = 8 * 1024 * 1024;

/**
 * The official-file library.
 *
 * Folders here are real directories on the server and files keep the names the
 * operator gave them, so the screen is a file browser rather than a catalogue:
 * the address a link has is the path under the library root, and renaming a
 * file changes its link. That is worth knowing before using it — a link already
 * pasted into a post follows the folder it was in, not the row.
 *
 * Uploads go up in pieces through the same session mechanism the download
 * centre uses, with `purpose: files`, so an SDK archive does not have to fit in
 * one request. The session is opened with the folder it is for; the last step
 * only names the file.
 *
 * Nothing here decides who may download a file. Images are served publicly,
 * because they are meant to appear in posts; everything else requires a
 * session. The operator takes the link and applies the download centre's tiers
 * where they use it, which is a separate screen and a separate decision.
 */
export default class IngenicFileManager extends Component {
  @tracked path = "";
  @tracked entries = [];
  @tracked breadcrumbs = [];
  @tracked truncated = false;
  @tracked writable = true;
  @tracked extensions = [];
  @tracked loading = false;
  @tracked error = null;
  @tracked notice = null;

  // The inline new-folder field: null when closed, the typed name when open.
  @tracked folderDraft = null;
  // The row being renamed, and what has been typed into it.
  @tracked renaming = null;
  @tracked renameDraft = "";

  // Files in this visit's upload queue. Each one keeps its own progress so a
  // slow archive does not hide the state of the file after it.
  @tracked uploads = [];

  // The file whose preview is open, and the folder picker for a move.
  @tracked preview = null;
  @tracked moving = null;
  @tracked movingPath = "";
  @tracked movingEntries = [];
  @tracked movingBreadcrumbs = [];

  constructor() {
    super(...arguments);
    if (this.args.initial) {
      this.#apply(this.args.initial);
    }
  }

  get canWrite() {
    return this.writable;
  }

  // What the browser's file picker offers. `accept` is an optimisation, not a
  // rule: the server checks the extension again, and a file chosen by drag or
  // by an older picker still has to pass.
  get accept() {
    return this.extensions.map((extension) => `.${extension}`).join(",");
  }

  get hasFinishedUploads() {
    return this.uploads.some((job) => job.state !== "uploading" && job.state !== "queued");
  }

  get previewUrl() {
    return this.preview ? this.#absolute(this.preview.url) : "";
  }

  get canMoveHere() {
    if (!this.moving) {
      return false;
    }

    const source = this.moving.entry;
    const separator = source.path.lastIndexOf("/");
    const parent = separator === -1 ? "" : source.path.slice(0, separator);

    // The folder it is already in, and for a folder its own address and
    // anything under it: the server refuses both, so the button is not offered.
    if (this.movingPath === parent || this.movingPath === source.path) {
      return false;
    }

    return source.kind !== "dir" || !this.movingPath.startsWith(`${source.path}/`);
  }

  @action
  async openDirectory(entry) {
    if (entry.kind === "dir") {
      await this.load(entry.path);
    }
  }

  @action
  async load(path) {
    this.loading = true;
    this.error = null;

    try {
      const listing = await ajax(`${ENDPOINT}?path=${encodeURIComponent(path ?? "")}`);
      this.#apply(listing);
    } catch (failure) {
      this.error = this.#errorMessage(failure);
    } finally {
      this.loading = false;
    }
  }

  @action
  refresh() {
    return this.load(this.path);
  }

  @action
  startFolder() {
    this.folderDraft = "";
    this.error = null;
  }

  @action
  cancelFolder() {
    this.folderDraft = null;
  }

  @action
  fieldFolder(event) {
    this.folderDraft = event.target.value;
  }

  @action
  async createFolder(event) {
    event?.preventDefault();
    const name = (this.folderDraft ?? "").trim();
    if (!name) {
      this.folderDraft = null;
      return;
    }

    try {
      await ajax(`${ENDPOINT}/folders`, {
        type: "POST",
        data: { path: this.path, name },
      });
      this.folderDraft = null;
      this.notice = i18n("ingenic.files.folder_created", { name });
      await this.load(this.path);
    } catch (failure) {
      this.error = this.#errorMessage(failure);
    }
  }

  @action
  startRename(entry) {
    this.renaming = entry;
    this.renameDraft = entry.name;
    this.error = null;
  }

  @action
  cancelRename() {
    this.renaming = null;
    this.renameDraft = "";
  }

  @action
  fieldRename(event) {
    this.renameDraft = event.target.value;
  }

  @action
  async rename(event) {
    event?.preventDefault();
    const entry = this.renaming;
    const name = (this.renameDraft ?? "").trim();

    if (!entry || !name || name === entry.name) {
      this.cancelRename();
      return;
    }

    try {
      await ajax(`${ENDPOINT}/rename`, {
        type: "POST",
        data: { path: entry.path, name },
      });
      this.cancelRename();
      this.notice = i18n("ingenic.files.renamed", { name });
      await this.load(this.path);
    } catch (failure) {
      this.error = this.#errorMessage(failure);
    }
  }

  @action
  async remove(entry) {
    if (!window.confirm(i18n("ingenic.files.delete_confirm", { name: entry.name }))) {
      return;
    }

    try {
      await ajax(`${ENDPOINT}?path=${encodeURIComponent(entry.path)}`, { type: "DELETE" });
      this.notice = i18n("ingenic.files.deleted", { name: entry.name });
      await this.load(this.path);
    } catch (failure) {
      this.error = this.#errorMessage(failure);
    }
  }

  @action
  async copyLink(entry) {
    const url = this.#absolute(entry.url);

    try {
      await navigator.clipboard.writeText(url);
      this.notice = i18n("ingenic.files.copied");
    } catch {
      this.error = i18n("ingenic.files.copy_failed");
    }
  }

  @action
  showPreview(entry) {
    this.preview = entry;
  }

  @action
  closePreview() {
    this.preview = null;
  }

  @action
  async startMove(entry) {
    this.moving = { entry };
    await this.#loadMoveFolder(this.path);
  }

  @action
  async moveInto(folder) {
    if (folder?.kind === "dir") {
      await this.#loadMoveFolder(folder.path);
    }
  }

  @action
  async moveUp() {
    const parent = this.movingBreadcrumbs[this.movingBreadcrumbs.length - 2];
    await this.#loadMoveFolder(parent?.path ?? "");
  }

  @action
  async moveToBreadcrumb(crumb) {
    await this.#loadMoveFolder(crumb.path);
  }

  @action
  closeMove() {
    this.moving = null;
    this.movingPath = "";
    this.movingEntries = [];
    this.movingBreadcrumbs = [];
  }

  @action
  async confirmMove() {
    if (!this.moving || !this.canMoveHere) {
      return;
    }

    try {
      await ajax(`${ENDPOINT}/move`, {
        type: "POST",
        data: { path: this.moving.entry.path, directory: this.movingPath },
      });
      this.notice = i18n("ingenic.files.moved", { name: this.moving.entry.name });
      this.closeMove();
      await this.load(this.path);
    } catch (failure) {
      this.error = this.#errorMessage(failure);
    }
  }

  @action
  chooseFiles(event) {
    const files = Array.from(event.target.files ?? []);
    // Cleared immediately so choosing the same file again is still a change.
    event.target.value = "";
    return this.#enqueue(files);
  }

  @action
  dismissUpload(job) {
    this.uploads = this.uploads.filter((item) => item.id !== job.id);
  }

  @action
  clearUploads() {
    this.uploads = this.uploads.filter(
      (job) => job.state === "uploading" || job.state === "queued",
    );
  }

  async #loadMoveFolder(path) {
    this.movingPath = path ?? "";

    try {
      const listing = await ajax(`${ENDPOINT}?path=${encodeURIComponent(this.movingPath)}`);
      this.movingEntries = listing.entries.filter((entry) => entry.kind === "dir");
      this.movingBreadcrumbs = listing.breadcrumbs;
    } catch (failure) {
      this.error = this.#errorMessage(failure);
    }
  }

  // One file at a time. Parallel uploads share one uplink, so starting them
  // together only makes every progress bar slow; in order, the first file
  // finishes and can be linked while the next is still going.
  async #enqueue(files) {
    let uploaded = false;

    for (const file of files) {
      const extension = (file.name.split(".").pop() ?? "").toLowerCase();
      if (!this.extensions.includes(extension)) {
        this.error = i18n("ingenic.files.unsupported", { name: file.name });
        continue;
      }

      const job = {
        id: `${Date.now()}-${Math.random()}-${file.name}`,
        name: file.name,
        size: file.size,
        progress: 0,
        state: "uploading",
        message: null,
      };
      this.uploads = [...this.uploads, job];

      if (await this.#upload(file, job)) {
        uploaded = true;
      }
    }

    if (uploaded) {
      await this.load(this.path);
    }
  }

  async #upload(file, job) {
    try {
      const created = await ajax(UPLOADS, {
        type: "POST",
        data: { filename: file.name, size: file.size, directory: this.path },
      });
      const token = created.upload.token;
      let offset = created.upload.received_size ?? 0;

      while (offset < file.size) {
        const piece = file.slice(offset, Math.min(offset + CHUNK_SIZE, file.size));

        try {
          const result = await ajax(`${UPLOADS}/${token}/chunks?offset=${offset}`, {
            type: "POST",
            data: piece,
            processData: false,
            contentType: "application/octet-stream",
          });
          offset = result.upload.received_size;
        } catch (failure) {
          // A lost response leaves the server ahead of what the browser last
          // heard. Its byte count is the truth; anything else is a real
          // failure and ends this file.
          const reported = failure?.jqXHR?.responseJSON?.received_size;
          if (failure?.jqXHR?.status === 409 && Number.isInteger(reported)) {
            offset = reported;
          } else {
            throw failure;
          }
        }

        this.#updateJob(job.id, {
          progress: file.size ? Math.round((offset / file.size) * 100) : 0,
        });
      }

      await ajax(`${UPLOADS}/${token}/complete`, {
        type: "POST",
        data: { directory: this.path, filename: file.name },
      });

      this.#updateJob(job.id, { state: "done", progress: 100 });
      this.notice = i18n("ingenic.files.uploaded", { name: file.name });
      return true;
    } catch (failure) {
      this.#updateJob(job.id, {
        state: "failed",
        message: this.#errorMessage(failure),
      });
      return false;
    }
  }

  #updateJob(id, attributes) {
    this.uploads = this.uploads.map((job) =>
      job.id === id ? { ...job, ...attributes } : job,
    );
  }

  #apply(listing) {
    this.path = listing.path ?? "";
    this.entries = listing.entries ?? [];
    this.breadcrumbs = listing.breadcrumbs ?? [];
    this.truncated = Boolean(listing.truncated);
    this.writable = listing.writable !== false;
    this.extensions = listing.extensions ?? [];
  }

  #absolute(url) {
    try {
      return new URL(url, window.location.origin).href;
    } catch {
      return url;
    }
  }

  #errorMessage(failure) {
    const errors = failure?.jqXHR?.responseJSON?.errors;
    return errors?.join(", ") || i18n("ingenic.files.save_failed");
  }

  get folderOpen() {
    return this.folderDraft !== null;
  }

  get isEmpty() {
    return this.entries.length === 0;
  }

  get noMoveFolders() {
    return this.movingEntries.length === 0;
  }

  get moveHasParent() {
    return this.movingBreadcrumbs.length > 1;
  }

  get moveDisabled() {
    return !this.canMoveHere;
  }

  @action
  isDirectory(entry) {
    return entry.kind === "dir";
  }

  @action
  isRenaming(entry) {
    return this.renaming?.path === entry.path;
  }

  @action
  jobDone(job) {
    return job.state === "done";
  }

  @action
  jobFailed(job) {
    return job.state === "failed";
  }

  @action
  formattedDate(entry) {
    if (!entry.modified_at) {
      return "";
    }

    const date = new Date(entry.modified_at);
    return Number.isNaN(date.getTime()) ? "" : date.toLocaleString();
  }

  <template>
    <div class="ingenic-file-manager">
      {{#if this.error}}
        <p class="ingenic-admin-note ingenic-admin-note--error">{{this.error}}</p>
      {{/if}}
      {{#if this.notice}}
        <p class="ingenic-admin-note">{{this.notice}}</p>
      {{/if}}
      {{#unless this.canWrite}}
        <p class="ingenic-admin-note ingenic-admin-note--error">
          {{i18n "ingenic.files.not_writable"}}
        </p>
      {{/unless}}

      <div class="ingenic-file-manager__crumbs">
        {{#each this.breadcrumbs as |crumb|}}
          <button
            class="ingenic-file-manager__crumb"
            type="button"
            {{on "click" (fn this.load crumb.path)}}
          >
            {{#if crumb.name}}{{crumb.name}}{{else}}{{i18n "ingenic.files.path_root"}}{{/if}}
          </button>
          <span class="ingenic-file-manager__separator">/</span>
        {{/each}}
      </div>

      <div class="ingenic-admin__toolbar">
        {{#if this.canWrite}}
          {{#if this.folderOpen}}
            <form class="ingenic-file-manager__inline" {{on "submit" this.createFolder}}>
              <input
                type="text"
                value={{this.folderDraft}}
                placeholder={{i18n "ingenic.files.folder_name"}}
                {{on "input" this.fieldFolder}}
                autofocus={{true}}
              />
              <button class="btn btn-primary" type="submit">
                {{i18n "ingenic.files.create"}}
              </button>
              <button class="btn" type="button" {{on "click" this.cancelFolder}}>
                {{i18n "ingenic.files.cancel"}}
              </button>
            </form>
          {{else}}
            <button class="btn" type="button" {{on "click" this.startFolder}}>
              {{dIcon "plus"}}{{i18n "ingenic.files.new_folder"}}
            </button>
          {{/if}}

          <label class="btn btn-primary ingenic-file-manager__upload">
            {{dIcon "upload"}}{{i18n "ingenic.files.upload"}}
            <input type="file" multiple accept={{this.accept}} {{on "change" this.chooseFiles}} />
          </label>
        {{/if}}

        <button class="btn" type="button" {{on "click" this.refresh}}>
          {{dIcon "rotate"}}{{i18n "ingenic.files.refresh"}}
        </button>
      </div>

      {{#if this.uploads.length}}
        <div class="ingenic-file-manager__uploads">
          {{#each this.uploads as |job|}}
            <div class="ingenic-file-manager__upload-row">
              <span class="ingenic-file-manager__upload-name">{{job.name}}</span>
              {{#if (this.jobFailed job)}}
                <span class="ingenic-file-manager__upload-error">{{job.message}}</span>
                <button class="btn btn-small" type="button" {{on "click" (fn this.dismissUpload job)}}>
                  {{dIcon "xmark"}}
                </button>
              {{else if (this.jobDone job)}}
                <span class="ingenic-file-manager__upload-done">
                  {{dIcon "check"}}{{i18n "ingenic.files.upload_done"}}
                </span>
                <button class="btn btn-small" type="button" {{on "click" (fn this.dismissUpload job)}}>
                  {{dIcon "xmark"}}
                </button>
              {{else}}
                <progress value={{job.progress}} max="100"></progress>
                <span>{{job.progress}}%</span>
              {{/if}}
            </div>
          {{/each}}
          {{#if this.hasFinishedUploads}}
            <button class="btn btn-small" type="button" {{on "click" this.clearUploads}}>
              {{i18n "ingenic.files.clear_uploads"}}
            </button>
          {{/if}}
        </div>
      {{/if}}

      {{#if this.loading}}
        <p class="ingenic-admin-note">{{i18n "ingenic.files.loading"}}</p>
      {{else if this.isEmpty}}
        <p class="ingenic-admin-note">{{i18n "ingenic.files.empty"}}</p>
      {{else}}
        <table class="ingenic-file-manager__table">
          <thead>
            <tr>
              <th>{{i18n "ingenic.files.name"}}</th>
              <th>{{i18n "ingenic.files.size"}}</th>
              <th>{{i18n "ingenic.files.modified"}}</th>
              <th>{{i18n "ingenic.files.actions"}}</th>
            </tr>
          </thead>
          <tbody>
            {{#each this.entries as |entry|}}
              <tr>
                <td class="ingenic-file-manager__name">
                  {{#if (this.isRenaming entry)}}
                    <form class="ingenic-file-manager__inline" {{on "submit" this.rename}}>
                      <input
                        type="text"
                        value={{this.renameDraft}}
                        {{on "input" this.fieldRename}}
                        autofocus={{true}}
                      />
                      <button class="btn btn-small btn-primary" type="submit">
                        {{i18n "ingenic.files.save"}}
                      </button>
                      <button class="btn btn-small" type="button" {{on "click" this.cancelRename}}>
                        {{i18n "ingenic.files.cancel"}}
                      </button>
                    </form>
                  {{else if (this.isDirectory entry)}}
                    <button
                      class="ingenic-file-manager__entry"
                      type="button"
                      {{on "click" (fn this.openDirectory entry)}}
                    >
                      {{dIcon "folder"}}<span>{{entry.name}}</span>
                    </button>
                  {{else}}
                    <span class="ingenic-file-manager__entry">
                      {{#if entry.image}}
                        <img class="ingenic-file-manager__thumb" src={{entry.url}} alt="" />
                      {{else}}
                        {{dIcon "file"}}
                      {{/if}}
                      <span>{{entry.name}}</span>
                    </span>
                  {{/if}}
                </td>
                <td>{{entry.human_size}}</td>
                <td>{{this.formattedDate entry}}</td>
                <td class="ingenic-file-manager__actions">
                  {{#unless (this.isDirectory entry)}}
                    {{#if entry.previewable}}
                      <button class="btn btn-small" type="button" {{on "click" (fn this.showPreview entry)}}>
                        {{dIcon "eye"}}{{i18n "ingenic.files.preview"}}
                      </button>
                    {{/if}}
                    <button class="btn btn-small" type="button" {{on "click" (fn this.copyLink entry)}}>
                      {{dIcon "link"}}{{i18n "ingenic.files.copy_link"}}
                    </button>
                  {{/unless}}
                  {{#if this.canWrite}}
                    <button class="btn btn-small" type="button" {{on "click" (fn this.startRename entry)}}>
                      {{dIcon "pencil"}}{{i18n "ingenic.files.rename"}}
                    </button>
                    <button class="btn btn-small" type="button" {{on "click" (fn this.startMove entry)}}>
                      {{dIcon "folder"}}{{i18n "ingenic.files.move"}}
                    </button>
                    <button class="btn btn-small" type="button" {{on "click" (fn this.remove entry)}}>
                      {{dIcon "trash-can"}}{{i18n "ingenic.files.delete"}}
                    </button>
                  {{/if}}
                </td>
              </tr>
            {{/each}}
          </tbody>
        </table>

        {{#if this.truncated}}
          <p class="ingenic-admin-note">{{i18n "ingenic.files.truncated"}}</p>
        {{/if}}
      {{/if}}

      {{#if this.preview}}
        <div class="ingenic-file-manager__overlay" role="dialog" aria-modal="true">
          <div class="ingenic-file-manager__dialog">
            <header>
              <h3>{{this.preview.name}}</h3>
              <button class="btn btn-small" type="button" {{on "click" this.closePreview}}>
                {{i18n "ingenic.files.close"}}
              </button>
            </header>
            <div class="ingenic-file-manager__preview">
              {{#if this.preview.image}}
                <img src={{this.preview.url}} alt={{this.preview.name}} />
              {{else}}
                <iframe src={{this.preview.url}} title={{this.preview.name}}></iframe>
              {{/if}}
            </div>
            <footer>
              <input type="text" readonly value={{this.previewUrl}} />
              <button class="btn btn-small" type="button" {{on "click" (fn this.copyLink this.preview)}}>
                {{i18n "ingenic.files.copy_link"}}
              </button>
              <a class="btn btn-small" href={{this.previewUrl}} target="_blank" rel="noopener">
                {{i18n "ingenic.files.open"}}
              </a>
            </footer>
          </div>
        </div>
      {{/if}}

      {{#if this.moving}}
        <div class="ingenic-file-manager__overlay" role="dialog" aria-modal="true">
          <div class="ingenic-file-manager__dialog">
            <header>
              <h3>{{i18n "ingenic.files.move_title" name=this.moving.entry.name}}</h3>
              <button class="btn btn-small" type="button" {{on "click" this.closeMove}}>
                {{i18n "ingenic.files.close"}}
              </button>
            </header>
            <div class="ingenic-file-manager__crumbs">
              {{#each this.movingBreadcrumbs as |crumb|}}
                <button
                  class="ingenic-file-manager__crumb"
                  type="button"
                  {{on "click" (fn this.moveToBreadcrumb crumb)}}
                >
                  {{#if crumb.name}}{{crumb.name}}{{else}}{{i18n "ingenic.files.path_root"}}{{/if}}
                </button>
                <span class="ingenic-file-manager__separator">/</span>
              {{/each}}
            </div>
            <div class="ingenic-file-manager__move-list">
              {{#if this.noMoveFolders}}
                <p class="ingenic-admin-note">{{i18n "ingenic.files.no_subfolders"}}</p>
              {{else}}
                {{#each this.movingEntries as |folder|}}
                  <button
                    class="ingenic-file-manager__crumb"
                    type="button"
                    {{on "click" (fn this.moveInto folder)}}
                  >
                    {{dIcon "folder"}}{{folder.name}}
                  </button>
                {{/each}}
              {{/if}}
            </div>
            <footer>
              {{#if this.moveHasParent}}
                <button class="btn btn-small" type="button" {{on "click" this.moveUp}}>
                  {{i18n "ingenic.files.parent"}}
                </button>
              {{/if}}
              <button
                class="btn btn-primary btn-small"
                type="button"
                disabled={{this.moveDisabled}}
                {{on "click" this.confirmMove}}
              >
                {{i18n "ingenic.files.move_here"}}
              </button>
            </footer>
          </div>
        </div>
      {{/if}}
    </div>
  </template>
}
