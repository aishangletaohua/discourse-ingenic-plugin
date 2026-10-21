import Component from "@glimmer/component";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { tracked } from "@glimmer/tracking";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { eq } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";

// How many indentation steps the plugin's stylesheet defines, so a page nested
// deeper than the last one keeps the last one's indentation rather than
// falling back to none.
const MAX_INDENT = 8;

/**
 * The resolved page list for one version.
 *
 * The API already returns it depth-first with a depth per row, so the tree is
 * rendered as an indented list rather than nested markup — that keeps a page
 * whose parent lives in an earlier version in the right place.
 *
 * Naming works like a file explorer: the + at the end of a row (or in the
 * heading, or under the tree) starts a draft row with a name input — inside a
 * folder, but beside an article, because an article has no level below it.
 * Enter creates the page and the right pane immediately edits it. There is no
 * title or kind field in the editor — the tree owns the name, and the + menu
 * already asked which kind this is. Double-clicking a row's name renames it in
 * place.
 *
 * A folder with children folds. A row can be dragged by the grip in front of
 * it: onto another row's edge to change its order among its siblings, onto the
 * middle of a folder to move inside it. That drop is the only parent control —
 * the editor deliberately has none. Inherited rows have no grip (their order
 * belongs to the version that owns them), but renaming one still works: the
 * write materialises it into this version, as editing its body does.
 */
export default class IngenicDocPageTree extends Component {
  @tracked collapsed = new Set();

  // Which row's article/folder chooser is open.
  @tracked addSlug = null;

  @tracked dragging = null;
  @tracked dropSlug = null;
  @tracked dropAfter = false;
  // True when the pointer is on the middle of a folder row: dropping there
  // moves the page inside the folder instead of beside it.
  @tracked dropInto = false;

  // The row being typed into: { parent, parentSlug, kind, depth }.
  @tracked draft = null;
  @tracked draftName = "";

  @tracked renamingSlug = null;
  @tracked renameDraft = "";

  // The heading's + and the buttons under the tree live in the manager, but
  // they must start the same draft a row's + does.
  @action
  announceReady() {
    this.args.onReady?.({
      startDraft: (parent, kind) => this.startDraft(parent, kind),
    });
  }

  get rows() {
    const hidden = new Set();
    const rows = [];

    for (const page of this.args.pages) {
      // A row under a collapsed folder is not shown, but its own slug still
      // has to be blacklisted so its children disappear with it.
      if (page.parent_slug && hidden.has(page.parent_slug)) {
        hidden.add(page.slug);
        continue;
      }

      rows.push({
        ...page,
        folder: page.kind === "folder",
        indent: Math.min(page.depth ?? 0, MAX_INDENT),
        hasChildren: this.#hasChildren(page),
        isCollapsed: this.collapsed.has(page.slug),
        isDragging: this.dragging?.slug === page.slug,
        isDropBefore: this.dropSlug === page.slug && !this.dropAfter && !this.dropInto,
        isDropAfter: this.dropSlug === page.slug && this.dropAfter && !this.dropInto,
        isDropInto: this.dropSlug === page.slug && this.dropInto,
      });

      if (page.kind === "folder" && this.collapsed.has(page.slug)) {
        hidden.add(page.slug);
      }
    }

    if (this.draft) {
      let index = rows.length;

      if (this.draft.anchorSlug) {
        const anchorIndex = rows.findIndex(
          (row) => row.slug === this.draft.anchorSlug
        );

        if (anchorIndex >= 0) {
          // The draft sits right after the row whose + was pressed and, when
          // that row is a folder, after its whole subtree — which in a flat
          // depth-first list is the last following row deeper than it.
          index = anchorIndex + 1;

          while (index < rows.length && rows[index].depth > rows[anchorIndex].depth) {
            index++;
          }
        }
      } else if (this.draft.parentSlug) {
        const parentIndex = rows.findIndex(
          (row) => row.slug === this.draft.parentSlug
        );

        if (parentIndex >= 0) {
          index = parentIndex + 1;

          while (index < rows.length && rows[index].depth > rows[parentIndex].depth) {
            index++;
          }
        }
      }

      rows.splice(index, 0, {
        isDraft: true,
        kind: this.draft.kind,
        indent: Math.min(this.draft.depth, MAX_INDENT),
        slug: "__draft__",
      });
    }

    return rows;
  }

  #hasChildren(page) {
    return this.args.pages.some((entry) => entry.parent_slug === page.slug);
  }

  @action
  toggle(page) {
    const next = new Set(this.collapsed);

    if (next.has(page.slug)) {
      next.delete(page.slug);
    } else {
      next.add(page.slug);
    }

    this.collapsed = next;
  }

  @action
  toggleAdd(page, event) {
    event.preventDefault();
    event.stopPropagation();
    this.addSlug = this.addSlug === page.slug ? null : page.slug;
  }

  @action
  addChild(page, kind, event) {
    event.preventDefault();
    event.stopPropagation();
    this.startDraft(page, kind);
  }

  // Called both by a row's + menu and, through onReady, by the manager's
  // heading + and footer buttons (row = null).
  //
  // A folder's + adds a child inside it. An article has no level below it, so
  // its + adds a sibling at the same depth under the article's own parent —
  // the draft still appears right after the article, because the row that was
  // pressed is the anchor, not the parent.
  startDraft(row, kind) {
    let parent = row;
    let depth = row ? (row.depth ?? 0) + 1 : 0;

    if (row && !row.folder) {
      parent = row.parent_slug
        ? this.args.pages.find((entry) => entry.slug === row.parent_slug) ?? null
        : null;
      depth = row.depth ?? 0;
    }

    const parentSlug = parent?.slug ?? null;

    if (parent?.kind === "folder" && this.collapsed.has(parentSlug)) {
      const next = new Set(this.collapsed);
      next.delete(parentSlug);
      this.collapsed = next;
    }

    this.addSlug = null;
    this.renamingSlug = null;

    this.draft = {
      parent,
      parentSlug,
      anchorSlug: row?.slug ?? null,
      kind,
      depth,
    };
    this.draftName = "";
  }

  @action
  focusDraft(element) {
    element.focus();
    element.select?.();
  }

  @action
  updateDraftName(event) {
    this.draftName = event.target.value;
  }

  @action
  draftKeydown(event) {
    if (event.key === "Enter") {
      event.preventDefault();
      this.commitDraft();
    } else if (event.key === "Escape") {
      event.preventDefault();
      this.cancelDraft();
    }
  }

  // Clicking away commits a named row and discards an empty one, the way a
  // file explorer does. Enter clears the draft first, so the blur it causes
  // finds nothing left to commit.
  @action
  draftBlur() {
    if (!this.draft) {
      return;
    }

    if (this.draftName.trim()) {
      this.commitDraft();
    } else {
      this.cancelDraft();
    }
  }

  @action
  commitDraft() {
    const draft = this.draft;
    const name = this.draftName.trim();

    if (!draft || !name) {
      return;
    }

    this.draft = null;
    this.draftName = "";
    this.args.onCreate(draft.parent, draft.kind, name);
  }

  @action
  cancelDraft() {
    this.draft = null;
    this.draftName = "";
  }

  // Renaming an inherited row is allowed: the write materialises the row into
  // this version first, exactly as editing its body does.
  @action
  startRename(page, event) {
    event.preventDefault();
    event.stopPropagation();
    this.addSlug = null;
    this.renamingSlug = page.slug;
    this.renameDraft = page.title;
  }

  @action
  focusRename(element) {
    element.focus();
    element.select?.();
  }

  @action
  updateRename(event) {
    this.renameDraft = event.target.value;
  }

  @action
  renameKeydown(page, event) {
    if (event.key === "Enter") {
      event.preventDefault();
      this.commitRename(page);
    } else if (event.key === "Escape") {
      event.preventDefault();
      this.cancelRename();
    }
  }

  @action
  renameBlur(page) {
    if (this.renamingSlug === page.slug) {
      this.commitRename(page);
    }
  }

  @action
  commitRename(page) {
    const name = this.renameDraft.trim();
    this.renamingSlug = null;
    this.renameDraft = "";

    if (name) {
      this.args.onRename(page, name);
    }
  }

  @action
  cancelRename() {
    this.renamingSlug = null;
    this.renameDraft = "";
  }

  // The grip is the only draggable part of the row: making the whole row
  // draggable would swallow the click that selects a page.
  @action
  startDrag(page, event) {
    if (page.inherited) {
      return;
    }

    this.dragging = page;
    event.dataTransfer.effectAllowed = "move";
    // Firefox refuses to start a drag without payload, even when the payload
    // is never read.
    event.dataTransfer.setData("text/plain", page.slug);
  }

  @action
  dragOver(page, event) {
    const dragged = this.dragging;

    if (!dragged || dragged.id === page.id) {
      return;
    }

    const rect = event.currentTarget.getBoundingClientRect();
    const ratio = (event.clientY - rect.top) / rect.height;
    // The middle of a folder row means "put it inside"; its edges mean
    // "put it before or after", which only makes sense among siblings.
    const into = page.folder && ratio > 0.3 && ratio < 0.7;

    if (
      !into &&
      (page.inherited ||
        (dragged.parent_slug ?? null) !== (page.parent_slug ?? null))
    ) {
      return;
    }

    event.preventDefault();
    event.dataTransfer.dropEffect = "move";

    this.dropSlug = page.slug;
    this.dropInto = into;
    this.dropAfter = !into && ratio > 0.5;
  }

  @action
  drop(page, event) {
    event.preventDefault();

    const dragged = this.dragging;
    const after = this.dropAfter;
    const into = this.dropInto;

    // A page dropped into a folder would otherwise disappear from view when
    // that folder is collapsed, which reads as "the drag deleted it".
    if (into && this.collapsed.has(page.slug)) {
      const next = new Set(this.collapsed);
      next.delete(page.slug);
      this.collapsed = next;
    }

    this.endDrag();

    if (dragged && dragged.id !== page.id) {
      this.args.onDrop(dragged, page, after, into);
    }
  }

  @action
  endDrag() {
    this.dragging = null;
    this.dropSlug = null;
    this.dropInto = false;
  }

  <template>
    <div class="ingenic-admin-tree" {{didInsert this.announceReady}}>
      {{#each this.rows as |page|}}
        {{#if page.isDraft}}
          <div class="ingenic-admin-tree__row ingenic-admin-tree__row--indent-{{page.indent}} is-draft">
            <span class="ingenic-admin-tree__handle ingenic-admin-tree__handle--empty"></span>
            <span class="ingenic-admin-tree__chevron ingenic-admin-tree__chevron--empty"></span>
            <span class="ingenic-admin-tree__kind" aria-hidden="true">
              {{if (eq page.kind "folder") "📁" "📄"}}
            </span>
            <input
              class="ingenic-admin-tree__name-input"
              type="text"
              value={{this.draftName}}
              placeholder={{i18n "ingenic.documentation.workbench.name_placeholder"}}
              {{on "input" this.updateDraftName}}
              {{on "keydown" this.draftKeydown}}
              {{on "blur" this.draftBlur}}
              {{didInsert this.focusDraft}}
            />
            <span class="ingenic-admin-tree__name-hint">
              {{i18n "ingenic.documentation.workbench.name_hint"}}
            </span>
          </div>
        {{else}}
          <div
            class="ingenic-admin-tree__row ingenic-admin-tree__row--indent-{{page.indent}} {{if (eq page.slug @selectedSlug) 'is-selected'}} {{if page.folder 'is-folder'}} {{if page.isDragging 'is-dragging'}} {{if page.isDropBefore 'is-drop-before'}} {{if page.isDropAfter 'is-drop-after'}} {{if page.isDropInto 'is-drop-into'}}"
            {{on "dragover" (fn this.dragOver page)}}
            {{on "drop" (fn this.drop page)}}
          >
            {{#unless page.inherited}}
              <span
                class="ingenic-admin-tree__handle"
                draggable="true"
                title={{i18n "ingenic.documentation.workbench.drag"}}
                {{on "dragstart" (fn this.startDrag page)}}
                {{on "dragend" this.endDrag}}
              >⠿</span>
            {{else}}
              <span class="ingenic-admin-tree__handle ingenic-admin-tree__handle--empty"></span>
            {{/unless}}

            {{#if page.hasChildren}}
              <button
                type="button"
                class="ingenic-admin-tree__chevron"
                aria-expanded={{if page.isCollapsed "false" "true"}}
                {{on "click" (fn this.toggle page)}}
              >{{if page.isCollapsed "▸" "▾"}}</button>
            {{else}}
              <span class="ingenic-admin-tree__chevron ingenic-admin-tree__chevron--empty"></span>
            {{/if}}

            {{#if (eq this.renamingSlug page.slug)}}
              <input
                class="ingenic-admin-tree__name-input"
                type="text"
                value={{this.renameDraft}}
                {{on "input" this.updateRename}}
                {{on "keydown" (fn this.renameKeydown page)}}
                {{on "blur" (fn this.renameBlur page)}}
                {{didInsert this.focusRename}}
              />
            {{else}}
              <button
                type="button"
                class="ingenic-admin-tree__select"
                title={{i18n "ingenic.documentation.workbench.rename_hint"}}
                {{on "click" (fn @onSelect page)}}
                {{on "dblclick" (fn this.startRename page)}}
              >
                <span class="ingenic-admin-tree__title">
                  <span class="ingenic-admin-tree__kind" aria-hidden="true">
                    {{if page.folder "📁" "📄"}}
                  </span>
                  {{page.title}}
                </span>
                {{#if page.inherited}}
                  <span class="ingenic-admin-tree__badge">
                    {{i18n "ingenic.documentation.inherited_from"}} {{page.inherited_from_label}}
                  </span>
                {{/if}}
              </button>
            {{/if}}

            <span class="ingenic-admin-tree__tools">
              <button
                type="button"
                class="ingenic-admin-tree__add"
                title={{if
                  page.folder
                  (i18n "ingenic.documentation.workbench.new_child")
                  (i18n "ingenic.documentation.workbench.new_sibling")
                }}
                {{on "click" (fn this.toggleAdd page)}}
              >＋</button>
            </span>

            {{#if (eq this.addSlug page.slug)}}
              <span class="ingenic-admin-tree__add-menu">
                <button type="button" {{on "click" (fn this.addChild page "page")}}>
                  📄 {{i18n "ingenic.documentation.workbench.new_article"}}
                </button>
                <button type="button" {{on "click" (fn this.addChild page "folder")}}>
                  📁 {{i18n "ingenic.documentation.workbench.new_folder"}}
                </button>
              </span>
            {{/if}}
          </div>
        {{/if}}
      {{else}}
        <p class="ingenic-admin-tree__empty">{{i18n "ingenic.documentation.no_pages"}}</p>
      {{/each}}
    </div>
  </template>
}
