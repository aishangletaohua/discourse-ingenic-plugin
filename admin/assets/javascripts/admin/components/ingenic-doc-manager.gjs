import Component from "@glimmer/component";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { tracked } from "@glimmer/tracking";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { eq } from "discourse/truth-helpers";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";
import IngenicDocPageForm from "./ingenic-doc-page-form";
import IngenicDocPageTree from "./ingenic-doc-page-tree";

const BASE = "/admin/plugins/discourse-ingenic";

/**
 * Authoring workbench for the documentation tree.
 *
 * The shape is series -> chip -> version -> pages, with a language that picks
 * which manual of that chip is being written. The four filters are chosen once,
 * at the top; language sits last in the bar but still narrows the version list,
 * because a chip plus a language names one manual. The left pane is always the
 * page tree of the chosen version, and the right pane is always the editor of
 * the selected row. Series, chips and versions are changed in a drawer so that
 * the two columns stay reserved for the two things an editor does all day:
 * find a page, write it.
 */
export default class IngenicDocManager extends Component {
  @tracked series = this.args.series;
  @tracked selectedSeriesId = null;
  @tracked selectedChipId = null;
  // A chip's documentation is located by language before version: the same
  // chip can carry an English and a Chinese manual, and their release lists
  // are independent. The picker is mandatory, so there is always one language
  // in effect and the version list never mixes two of them.
  @tracked selectedLocale = null;
  @tracked selectedVersionId = null;
  @tracked pages = [];
  @tracked selectedPageSlug = null;
  @tracked busy = false;
  @tracked error = null;
  @tracked importMessage = null;

  // { kind: "series" | "chip" | "version", action: "create" | "edit", record }
  @tracked drawer = null;

  // Whether the + in the tree heading is showing its article/folder menu.
  @tracked topAddMenu = false;

  // The tree registers its inline-create entry here so the + in the heading
  // and the buttons under the tree start the same draft a row's + does.
  treeApi = null;

  // The first series/chip/version is picked after the first paint rather than
  // in the constructor: `selectChip` reads `selectedLocale` to decide the next
  // one and then writes it back, and doing that while the component is still
  // being rendered is a read followed by a write in the same computation —
  // which Glimmer refuses, aborting the whole screen.
  @action
  startUp() {
    if (this.selectedSeriesId === null) {
      this.#selectFirst();
    }
  }

  get selectedSeries() {
    return this.series.find((entry) => entry.id === this.selectedSeriesId) ?? null;
  }

  get chips() {
    return this.selectedSeries?.chips ?? [];
  }

  get selectedChip() {
    return this.chips.find((entry) => entry.id === this.selectedChipId) ?? null;
  }

  get versions() {
    return (this.selectedChip?.versions ?? []).filter(
      (version) => this.#localeOf(version) === this.selectedLocale
    );
  }

  // The languages this chip actually has versions in. When it has none yet,
  // the site's documentation default still appears, so the mandatory picker is
  // never empty.
  get languageOptions() {
    const values = [
      ...new Set((this.selectedChip?.versions ?? []).map((version) => this.#localeOf(version))),
    ].filter(Boolean);

    // The language being shown stays in the picker while it has no version, or
    // deleting the last one would silently switch the workbench elsewhere.
    if (this.selectedLocale && !values.includes(this.selectedLocale)) {
      values.push(this.selectedLocale);
    }

    if (values.length === 0) {
      const fallback = this.selectedChip?.locale || this.args.defaultLocale;

      if (!fallback) {
        return [];
      }

      values.push(fallback);
    }

    return values.map((value) => ({
      value,
      name: (this.args.locales ?? []).find((locale) => locale.value === value)?.name ?? value,
    }));
  }

  get selectedVersion() {
    return this.versions.find((entry) => entry.id === this.selectedVersionId) ?? null;
  }

  get selectedPage() {
    return this.pages.find((page) => page.slug === this.selectedPageSlug) ?? null;
  }

  get noSeries() {
    return this.series.length === 0;
  }

  get noSelectedSeries() {
    return !this.selectedSeries;
  }

  get noSelectedChip() {
    return !this.selectedChip;
  }

  get noSelectedVersion() {
    return !this.selectedVersion;
  }

  get drawerTitle() {
    if (!this.drawer) {
      return "";
    }

    return i18n(
      `admin.ingenic.documentation.workbench.${this.drawer.action}_${this.drawer.kind}`
    );
  }

  // The language a drawer's form starts on. Creating a version starts in the
  // language the workbench is showing — a new release of the same manual is
  // the common case — while editing uses the row's own value.
  get drawerLocale() {
    return this.drawer?.record?.locale ?? this.selectedLocale;
  }

  // The site's served languages, plus the row's own value when it is not one
  // of them: a row filed under "en" on a Chinese site has to show "en" in the
  // picker, or saving any other field would silently move it to the first
  // option and take it off the reader's screen.
  localeOptions(current) {
    const options = this.args.locales ?? [];

    if (current && !options.some((option) => option.value === current)) {
      return [{ value: current, name: current }, ...options];
    }

    return options;
  }

  // The drawer's picker asks for one fixed list, so it is a getter rather than
  // a method call with an argument in the template: Glimmer invokes such calls
  // without `this`, and a method that reads `this.args` would throw and render
  // an empty select.
  get drawerLanguageOptions() {
    return this.localeOptions(this.drawerLocale);
  }

  #selectFirst() {
    const firstSeries = this.series[0];

    if (!firstSeries) {
      return;
    }

    this.selectedSeriesId = firstSeries.id;

    const chip = (firstSeries.chips ?? [])[0];

    if (chip) {
      this.selectChip(chip);
    }
  }

  // Rows written before the language default was fixed may have no locale at
  // all. The documentation default is the language they were meant for.
  #localeOf(version) {
    return version.locale || this.args.defaultLocale || "";
  }

  // The language kept across chip switches when the new chip has it, the site
  // default next, and the chip's first language otherwise. Never blank.
  #localeFor(chip) {
    const locales = (chip.versions ?? [])
      .map((version) => this.#localeOf(version))
      .filter(Boolean);

    if (this.selectedLocale && locales.includes(this.selectedLocale)) {
      return this.selectedLocale;
    }

    if (this.args.defaultLocale && locales.includes(this.args.defaultLocale)) {
      return this.args.defaultLocale;
    }

    // A chip with no versions yet still has a language of its own; start there
    // so the first version is filed where the chip says it belongs.
    return locales[0] ?? chip.locale ?? this.args.defaultLocale ?? null;
  }

  #preferredVersion() {
    return this.versions.find((version) => version.latest) ?? this.versions[0] ?? null;
  }

  @action
  async reload() {
    const payload = await ajax(`${BASE}/documentation`);
    this.series = payload.series;
  }

  @action
  selectSeries(event) {
    const id = Number(event.target.value);
    this.selectedSeriesId = id || null;
    this.selectedChipId = null;
    this.selectedLocale = null;
    this.selectedVersionId = null;
    this.selectedPageSlug = null;
    this.pages = [];
    this.importMessage = null;

    const chip = this.chips[0];

    if (chip) {
      this.selectChip(chip);
    }
  }

  @action
  selectChipById(event) {
    const chip = this.chips.find((entry) => entry.id === Number(event.target.value));

    if (chip) {
      this.selectChip(chip);
    }
  }

  @action
  async selectChip(chip) {
    this.selectedChipId = chip.id;
    this.selectedLocale = this.#localeFor(chip);
    this.selectedVersionId = null;
    this.selectedPageSlug = null;
    this.pages = [];
    this.importMessage = null;

    const version = this.#preferredVersion();

    if (version) {
      await this.selectVersion(version);
    }
  }

  // Language sits last in the bar, but changing it still selects that
  // language's latest version. A version list mixing two languages would make
  // "latest" and the position arrows ambiguous — releasing the English v2 must
  // not renumber the Chinese manual.
  @action
  async selectLanguageById(event) {
    const locale = event.target.value;

    if (!locale || locale === this.selectedLocale) {
      return;
    }

    this.selectedLocale = locale;
    this.selectedVersionId = null;
    this.selectedPageSlug = null;
    this.pages = [];
    this.importMessage = null;

    const version = this.#preferredVersion();

    if (version) {
      await this.selectVersion(version);
    }
  }

  @action
  selectVersionById(event) {
    const version = this.versions.find((entry) => entry.id === Number(event.target.value));

    if (version) {
      this.selectVersion(version);
    }
  }

  @action
  async selectVersion(version) {
    this.selectedVersionId = version.id;
    this.selectedPageSlug = null;
    this.importMessage = null;
    await this.loadTree();
  }

  @action
  async loadTree() {
    if (!this.selectedVersionId) {
      return;
    }

    this.busy = true;
    this.error = null;

    try {
      // The server resolves the tree in the language it is told, which is the
      // one picked at the top of this screen — not the admin's UI language.
      const locale = this.selectedLocale;
      const query = locale ? `?locale=${encodeURIComponent(locale)}` : "";
      const payload = await ajax(
        `${BASE}/documentation/versions/${this.selectedVersionId}/tree${query}`
      );
      this.pages = payload.pages;
    } catch {
      this.error = i18n("admin.ingenic.save_failed");
    } finally {
      this.busy = false;
    }
  }

  @action
  selectPage(page) {
    this.selectedPageSlug = page.slug;
  }

  // Creation and renaming happen in the tree, the way a file explorer works:
  // + inserts a row with a name input, Enter commits it, and the right pane is
  // already the editor of what was just named. The pane never asks for a title
  // or a kind — the + menu already said which, and the tree row holds the name.
  @action
  registerTree(api) {
    this.treeApi = api;
  }

  @action
  toggleTopAdd(event) {
    event.preventDefault();
    this.topAddMenu = !this.topAddMenu;
  }

  @action
  addFromTop(kind, event) {
    event.preventDefault();
    event.stopPropagation();
    this.startDraft(null, kind);
  }

  @action
  startDraft(parent, kind) {
    this.topAddMenu = false;
    this.treeApi?.startDraft(parent, kind);
  }

  @action
  async createPage(parent, kind, title) {
    const name = title?.trim();

    if (!name) {
      return;
    }

    this.busy = true;
    this.error = null;

    try {
      const response = await ajax(`${BASE}/documentation/pages`, {
        type: "POST",
        data: {
          title: name,
          slug: this.#slugFor(name),
          kind,
          parent_id: parent?.id ?? null,
          locale: this.selectedLocale,
          published: true,
          body: kind === "folder" ? null : "",
          version_id: this.selectedVersionId,
        },
      });

      await this.loadTree();

      if (response?.page?.slug) {
        this.selectedPageSlug = response.page.slug;
      }
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  @action
  async renamePage(page, title) {
    const name = title?.trim();

    if (!name || name === page.title) {
      return;
    }

    this.busy = true;
    this.error = null;

    try {
      const owned = await this.#ownPage(page);
      await ajax(`${BASE}/documentation/pages/${owned.id}`, {
        type: "PUT",
        data: { title: name },
      });
      await this.loadTree();
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  // A row this version only inherits is edited like any other. The first write
  // copies it into this version and the write lands on the copy, so the earlier
  // version keeps its text and the user never meets the word "inherit".
  async #ownPage(page) {
    if (!page.inherited) {
      return page;
    }

    const response = await ajax(
      `${BASE}/documentation/versions/${this.selectedVersionId}/pages/${page.slug}/override`,
      { type: "POST", data: { locale: this.selectedLocale } }
    );

    return response?.page ?? page;
  }

  // A Latin title keeps a readable slug. A Chinese one has nothing to
  // transliterate in the browser, so it gets a short fallback. The slug is
  // derived once, never asked for again, and only has to be unique within the
  // version and locale.
  #slugFor(title) {
    const ascii = title
      .normalize("NFKD")
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "");

    return ascii || `page-${Math.random().toString(36).slice(2, 8)}`;
  }

  // A file is a whole page, not a field: a team that already has its manual as
  // Markdown or Word should not have to copy each file's text in by hand.
  @action
  async importPages(event) {
    event.preventDefault();
    this.busy = true;
    this.error = null;
    this.importMessage = null;

    try {
      const response = await ajax(
        `${BASE}/documentation/versions/${this.selectedVersionId}/import`,
        {
          type: "POST",
          data: new FormData(event.target),
          processData: false,
          contentType: false,
        }
      );

      this.importMessage = i18n("admin.ingenic.documentation.imported", {
        count: response.imported?.length ?? 0,
      });

      if (response.errors?.length) {
        this.error = response.errors
          .map((entry) => `${entry.file}: ${entry.error}`)
          .join("; ");
      }

      event.target.reset();
      await this.loadTree();
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  @action
  async savePage(page, values) {
    this.busy = true;
    this.error = null;

    try {
      const owned = await this.#ownPage(page);
      await ajax(`${BASE}/documentation/pages/${owned.id}`, { type: "PUT", data: values });
      await this.loadTree();
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  // Dragging does both structural jobs the tree offers. Dropping on a row's
  // upper or lower half reorders it among that parent's children; dropping on
  // the middle of a folder moves it inside the folder. The second is the only
  // way to change a page's parent now that the editor no longer has a picker.
  //
  // The new sibling order is rewritten for the whole list: rows created before
  // positions existed all carry 0, and swapping two zeroes moves nothing.
  // Inherited rows are left out of the request — their position belongs to the
  // version that owns them — and the tree only offers the grip on rows this
  // version owns.
  @action
  async dropPage(dragged, target, after, into) {
    if (!dragged || !target || dragged.id === target.id || dragged.inherited) {
      return;
    }

    if (into) {
      if (
        target.kind !== "folder" ||
        this.#descendantSlugs(dragged.slug).has(target.slug)
      ) {
        return;
      }

      await this.#moveUnder(dragged, target);
      return;
    }

    if (
      target.inherited ||
      (dragged.parent_slug ?? null) !== (target.parent_slug ?? null)
    ) {
      return;
    }

    const siblings = this.pages.filter(
      (entry) =>
        (entry.parent_slug ?? null) === (dragged.parent_slug ?? null) && !entry.inherited
    );
    const reordered = siblings.filter((entry) => entry.id !== dragged.id);
    const index = reordered.findIndex((entry) => entry.id === target.id);

    if (index < 0) {
      return;
    }

    reordered.splice(after ? index + 1 : index, 0, dragged);

    this.busy = true;
    this.error = null;

    try {
      await Promise.all(
        reordered.map((entry, position) =>
          ajax(`${BASE}/documentation/pages/${entry.id}`, {
            type: "PUT",
            data: { position },
          })
        )
      );
      await this.loadTree();
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  // Appends the page to the folder's children. A folder lower in the tree than
  // the page is fine; one inside the page's own subtree is refused above,
  // because a loop in the parent chain makes every tree walk recurse forever.
  async #moveUnder(page, folder) {
    const children = this.pages.filter(
      (entry) => entry.parent_id === folder.id && entry.id !== page.id
    );
    const position = children.length
      ? Math.max(...children.map((entry) => entry.position ?? 0)) + 1
      : 0;

    this.busy = true;
    this.error = null;

    try {
      await ajax(`${BASE}/documentation/pages/${page.id}`, {
        type: "PUT",
        data: { parent_id: folder.id, position },
      });
      await this.loadTree();
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  #descendantSlugs(slug) {
    const found = new Set();
    let changed = true;

    while (changed) {
      changed = false;

      for (const entry of this.pages) {
        if (
          entry.parent_slug &&
          (entry.parent_slug === slug || found.has(entry.parent_slug)) &&
          !found.has(entry.slug)
        ) {
          found.add(entry.slug);
          changed = true;
        }
      }
    }

    return found;
  }

  @action
  async destroyPage(page) {
    if (!window.confirm(i18n("admin.ingenic.documentation.delete_page_confirm"))) {
      return;
    }

    this.busy = true;
    this.error = null;

    try {
      await ajax(`${BASE}/documentation/pages/${page.id}`, { type: "DELETE" });
      this.selectedPageSlug = null;
      await this.loadTree();
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  // Which version a reader lands on when the URL names none. Flagging one
  // clears the flag on its siblings: two "latest" versions is not a state the
  // reader can interpret.
  @action
  async toggleLatest(event) {
    const latest = event.target.checked;

    this.busy = true;
    this.error = null;

    try {
      await Promise.all(
        this.versions
          .filter((version) => version.id !== this.selectedVersionId && version.latest)
          .map((version) =>
            ajax(`${BASE}/documentation/versions/${version.id}`, {
              type: "PUT",
              data: { latest: false },
            })
          )
      );

      await ajax(`${BASE}/documentation/versions/${this.selectedVersionId}`, {
        type: "PUT",
        data: { latest },
      });
      await this.reload();
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  // Version order is not cosmetic: a version inherits from the ones before it,
  // so swapping two rows changes what a reader sees at each version.
  @action
  async moveVersion(version, direction) {
    const index = this.versions.findIndex((entry) => entry.id === version.id);
    const target = index + direction;

    if (index < 0 || target < 0 || target >= this.versions.length) {
      return;
    }

    const reordered = [...this.versions];
    reordered.splice(index, 1);
    reordered.splice(target, 0, version);

    this.busy = true;
    this.error = null;

    try {
      await Promise.all(
        reordered.map((entry, position) =>
          ajax(`${BASE}/documentation/versions/${entry.id}`, {
            type: "PUT",
            data: { position },
          })
        )
      );
      await this.reload();
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  @action
  async saveVersion(event, version) {
    event.preventDefault();
    const form = event.target;
    const values = Object.fromEntries(new FormData(form));

    this.busy = true;
    this.error = null;

    try {
      await ajax(`${BASE}/documentation/versions/${version.id}`, {
        type: "PUT",
        data: {
          label: values.label?.trim(),
          slug: values.slug?.trim(),
          locale: values.locale,
          // An empty date input is "no date", not the epoch.
          released_on: values.released_on || null,
          deprecated: form.elements.deprecated.checked,
        },
      });
      await this.reload();

      // A version moved to another language leaves the current picker, so the
      // picker follows it rather than emptying the workbench.
      if (version.id === this.selectedVersionId) {
        const updated = (this.selectedChip?.versions ?? []).find(
          (entry) => entry.id === version.id
        );

        if (updated) {
          this.selectedLocale = this.#localeOf(updated);
        }
      }
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  @action
  async destroyVersion(version) {
    if (!window.confirm(i18n("admin.ingenic.documentation.delete_version_confirm"))) {
      return;
    }

    this.busy = true;
    this.error = null;

    try {
      await ajax(`${BASE}/documentation/versions/${version.id}`, { type: "DELETE" });

      if (version.id === this.selectedVersionId) {
        this.selectedVersionId = null;
        this.selectedPageSlug = null;
        this.pages = [];
      }

      await this.reload();
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  // Series and chips are the front end's first two filter rows, so the words a
  // visitor picks from — and the slug the address spells, the language a reader
  // must be using to see it, and whether it is on the site at all — are edited
  // here rather than in code.
  @action
  async saveProduct(event, record) {
    event.preventDefault();
    const form = event.target;
    const values = Object.fromEntries(new FormData(form));

    this.busy = true;
    this.error = null;

    try {
      await ajax(`${BASE}/documentation/products/${record.id}`, {
        type: "PUT",
        data: {
          name: values.name?.trim(),
          slug: values.slug?.trim(),
          locale: values.locale,
          published: form.elements.published.checked,
        },
      });
      await this.reload();
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  // Positions are rewritten for the whole sibling list rather than swapped
  // with the neighbour: rows created before this control existed all have
  // position 0, and swapping two zeroes moves nothing.
  @action
  async moveProduct(record, direction) {
    const siblings =
      record.kind === "series"
        ? this.series
        : this.series.find((entry) => entry.id === record.parent_id)?.chips ?? [];
    const index = siblings.findIndex((entry) => entry.id === record.id);
    const target = index + direction;

    if (index < 0 || target < 0 || target >= siblings.length) {
      return;
    }

    const reordered = [...siblings];
    reordered.splice(index, 1);
    reordered.splice(target, 0, record);

    this.busy = true;
    this.error = null;

    try {
      await Promise.all(
        reordered.map((entry, position) =>
          ajax(`${BASE}/documentation/products/${entry.id}`, {
            type: "PUT",
            data: { position },
          })
        )
      );
      await this.reload();
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  @action
  async destroyProduct(record) {
    if (!window.confirm(i18n("admin.ingenic.documentation.delete_confirm"))) {
      return;
    }

    this.busy = true;
    this.error = null;

    try {
      await ajax(`${BASE}/documentation/products/${record.id}`, {
        type: "DELETE",
      });

      if (record.id === this.selectedSeriesId) {
        this.selectedSeriesId = null;
        this.selectedChipId = null;
        this.selectedVersionId = null;
        this.pages = [];
        this.selectedPageSlug = null;
      } else if (record.id === this.selectedChipId) {
        this.selectedChipId = null;
        this.selectedVersionId = null;
        this.pages = [];
        this.selectedPageSlug = null;
      }

      await this.reload();
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  @action
  openDrawer(kind, action = "edit", record = null) {
    this.error = null;
    this.drawer = { kind, action, record };
  }

  @action
  closeDrawer() {
    this.drawer = null;
  }

  @action
  async submitDrawer(event) {
    event.preventDefault();
    const form = event.target;
    const values = Object.fromEntries(new FormData(form));
    const { kind, action, record } = this.drawer;

    if (kind === "version") {
      if (action === "create") {
        const response = await this.#createRecord("documentation/versions", {
          label: values.label?.trim(),
          slug: values.slug?.trim(),
          locale: values.locale,
          released_on: values.released_on || null,
          deprecated: form.elements.deprecated?.checked ?? false,
          product_id: this.selectedChipId,
        });

        if (response?.version) {
          // The new version decides which language the workbench shows: the
          // drawer just said so, and the version would otherwise be hidden by
          // the current filter.
          this.selectedLocale = this.#localeOf(response.version);
          this.selectedVersionId = response.version.id;
          await this.loadTree();
        }
      } else {
        await this.saveVersion(event, record);
      }
    } else if (action === "create") {
      const response = await this.#createRecord("documentation/products", {
        name: values.name?.trim(),
        slug: values.slug?.trim(),
        locale: values.locale,
        published: form.elements.published?.checked ?? true,
        kind,
        parent_id: kind === "chip" ? this.selectedSeriesId : null,
      });

      if (response?.product) {
        if (kind === "series") {
          this.selectedSeriesId = response.product.id;
          this.selectedChipId = null;
          this.selectedLocale = null;
          this.selectedVersionId = null;
          this.selectedPageSlug = null;
          this.pages = [];
        } else {
          // A new chip starts on its own language, not the previous chip's.
          this.selectChip(response.product);
        }
      }
    } else {
      await this.saveProduct(event, record);
    }

    if (!this.error) {
      this.drawer = null;
    }
  }

  @action
  async deleteFromDrawer() {
    const { kind, record } = this.drawer;

    if (kind === "version") {
      await this.destroyVersion(record);
    } else {
      await this.destroyProduct(record);
    }

    this.drawer = null;
  }

  async #createRecord(endpoint, data) {
    this.busy = true;
    this.error = null;

    try {
      const response = await ajax(`${BASE}/${endpoint}`, { type: "POST", data });
      await this.reload();
      return response;
    } catch (error) {
      this.error = this.#errorMessage(error);
      return null;
    } finally {
      this.busy = false;
    }
  }

  #errorMessage(error) {
    return error.jqXHR?.responseJSON?.errors?.join(", ") || i18n("admin.ingenic.save_failed");
  }

  <template>
    {{#if this.error}}
      <p class="ingenic-admin-note ingenic-admin-note--error">{{this.error}}</p>
    {{/if}}

    <div class="ingenic-doc-workbench" {{didInsert this.startUp}}>
      <header class="ingenic-doc-workbench__bar">
        <div class="ingenic-doc-workbench__field">
          <span>{{i18n "admin.ingenic.documentation.workbench.series"}}</span>
          <select {{on "change" this.selectSeries}} disabled={{this.noSeries}}>
            {{#each this.series as |entry|}}
              <option value={{entry.id}} selected={{eq entry.id this.selectedSeriesId}}>
                {{entry.name}}
              </option>
            {{/each}}
          </select>
        </div>
        <button
          type="button"
          class="ingenic-doc-workbench__icon"
          title={{i18n "admin.ingenic.documentation.workbench.new_series"}}
          {{on "click" (fn this.openDrawer "series" "create")}}
        >＋</button>
        <button
          type="button"
          class="ingenic-doc-workbench__icon"
          title={{i18n "admin.ingenic.documentation.workbench.edit_series"}}
          disabled={{this.noSelectedSeries}}
          {{on "click" (fn this.openDrawer "series" "edit" this.selectedSeries)}}
        >⚙</button>

        <span class="ingenic-doc-workbench__sep">/</span>

        <div class="ingenic-doc-workbench__field">
          <span>{{i18n "admin.ingenic.documentation.workbench.chip"}}</span>
          <select {{on "change" this.selectChipById}} disabled={{this.noSelectedSeries}}>
            {{#each this.chips as |chip|}}
              <option value={{chip.id}} selected={{eq chip.id this.selectedChipId}}>
                {{chip.name}}
              </option>
            {{/each}}
          </select>
        </div>
        <button
          type="button"
          class="ingenic-doc-workbench__icon"
          title={{i18n "admin.ingenic.documentation.workbench.new_chip"}}
          disabled={{this.noSelectedSeries}}
          {{on "click" (fn this.openDrawer "chip" "create")}}
        >＋</button>
        <button
          type="button"
          class="ingenic-doc-workbench__icon"
          title={{i18n "admin.ingenic.documentation.workbench.edit_chip"}}
          disabled={{this.noSelectedChip}}
          {{on "click" (fn this.openDrawer "chip" "edit" this.selectedChip)}}
        >⚙</button>

        <span class="ingenic-doc-workbench__sep">/</span>

        <div class="ingenic-doc-workbench__field">
          <span>{{i18n "admin.ingenic.documentation.workbench.version"}}</span>
          <select {{on "change" this.selectVersionById}} disabled={{this.noSelectedChip}}>
            {{#each this.versions as |version|}}
              <option value={{version.id}} selected={{eq version.id this.selectedVersionId}}>
                {{version.label}}{{#if version.latest}} · {{i18n "admin.ingenic.documentation.latest"}}{{/if}}
              </option>
            {{/each}}
          </select>
        </div>
        <button
          type="button"
          class="ingenic-doc-workbench__icon"
          title={{i18n "admin.ingenic.documentation.workbench.new_version"}}
          disabled={{this.noSelectedChip}}
          {{on "click" (fn this.openDrawer "version" "create")}}
        >＋</button>
        <button
          type="button"
          class="ingenic-doc-workbench__icon"
          title={{i18n "admin.ingenic.documentation.workbench.edit_version"}}
          disabled={{this.noSelectedVersion}}
          {{on "click" (fn this.openDrawer "version" "edit" this.selectedVersion)}}
        >⚙</button>

        <span class="ingenic-doc-workbench__sep">/</span>

        {{! Language sits at the end of the bar but is still mandatory: a chip
            plus a language names one manual, and it narrows the version list.
            It has no + of its own — a language appears the moment a version is
            created in it, and that happens in the version drawer. }}
        <div class="ingenic-doc-workbench__field">
          <span>{{i18n "admin.ingenic.documentation.workbench.language"}}</span>
          <select
            class="ingenic-doc-workbench__language"
            {{on "change" this.selectLanguageById}}
            disabled={{this.noSelectedChip}}
            required
          >
            {{#each this.languageOptions as |locale|}}
              <option value={{locale.value}} selected={{eq locale.value this.selectedLocale}}>
                {{locale.name}}
              </option>
            {{/each}}
          </select>
        </div>

        <span class="ingenic-doc-workbench__spacer"></span>

        {{#if this.selectedVersion}}
          <label class="ingenic-doc-workbench__latest">
            <input
              type="checkbox"
              checked={{this.selectedVersion.latest}}
              disabled={{this.busy}}
              {{on "change" this.toggleLatest}}
            />
            <span>{{i18n "admin.ingenic.documentation.latest"}}</span>
          </label>
        {{/if}}
      </header>

      <div class="ingenic-doc-workbench__body">
        <aside class="ingenic-doc-workbench__tree">
          <div class="ingenic-doc-workbench__tree-head">
            <h3>{{i18n "admin.ingenic.documentation.workbench.tree"}}</h3>
            <button
              type="button"
              class="ingenic-doc-workbench__icon"
              title={{i18n "admin.ingenic.documentation.workbench.new_entry"}}
              disabled={{this.noSelectedVersion}}
              {{on "click" this.toggleTopAdd}}
            >＋</button>

            {{#if this.topAddMenu}}
              <span class="ingenic-admin-tree__add-menu">
                <button type="button" {{on "click" (fn this.addFromTop "page")}}>
                  📄 {{i18n "admin.ingenic.documentation.workbench.new_article"}}
                </button>
                <button type="button" {{on "click" (fn this.addFromTop "folder")}}>
                  📁 {{i18n "admin.ingenic.documentation.workbench.new_folder"}}
                </button>
              </span>
            {{/if}}
          </div>

          {{#if this.selectedVersion}}
            <IngenicDocPageTree
              @pages={{this.pages}}
              @selectedSlug={{this.selectedPageSlug}}
              @onSelect={{this.selectPage}}
              @onDrop={{this.dropPage}}
              @onCreate={{this.createPage}}
              @onRename={{this.renamePage}}
              @onReady={{this.registerTree}}
            />
          {{else}}
            <p class="ingenic-admin-tree__empty">
              {{i18n "admin.ingenic.documentation.workbench.pick_version"}}
            </p>
          {{/if}}

          <div class="ingenic-doc-workbench__tree-foot">
            <button
              type="button"
              class="ingenic-doc-workbench__ghost"
              disabled={{this.noSelectedVersion}}
              {{on "click" (fn this.startDraft null "page")}}
            >＋ {{i18n "admin.ingenic.documentation.workbench.new_article"}}</button>
            <button
              type="button"
              class="ingenic-doc-workbench__ghost"
              disabled={{this.noSelectedVersion}}
              {{on "click" (fn this.startDraft null "folder")}}
            >＋ {{i18n "admin.ingenic.documentation.workbench.new_folder"}}</button>
          </div>

          {{#if this.selectedVersion}}
            <details class="ingenic-doc-workbench__import">
              <summary>{{i18n "admin.ingenic.documentation.import_action"}}</summary>
              <form class="ingenic-admin-form" {{on "submit" this.importPages}}>
                <input type="file" name="files[]" accept=".md,.markdown,.txt,.docx" multiple required />
                <button type="submit" disabled={{this.busy}}>
                  {{i18n "admin.ingenic.documentation.import_action"}}
                </button>
              </form>
              <p class="ingenic-admin-note">
                {{i18n "admin.ingenic.documentation.import_hint"}}
              </p>
              {{#if this.importMessage}}
                <p class="ingenic-admin-note">{{this.importMessage}}</p>
              {{/if}}
            </details>
          {{/if}}
        </aside>

        <section class="ingenic-doc-workbench__editor">
          {{#if this.selectedPage}}
            {{! The right pane edits the page chosen on the left. Adding a child
                is a tree action, so that button lives on the row's + menu. }}
            <div class="ingenic-doc-workbench__editor-head">
              <h3>{{this.selectedPage.title}}</h3>
            </div>

            <IngenicDocPageForm
              @page={{this.selectedPage}}
              @busy={{this.busy}}
              @onSave={{this.savePage}}
              @onDestroy={{this.destroyPage}}
            />
          {{else}}
            <div class="ingenic-doc-workbench__empty">
              <p>{{i18n "admin.ingenic.documentation.workbench.empty_editor"}}</p>
              {{#if this.noSeries}}
                <p class="ingenic-admin-note">
                  {{i18n "admin.ingenic.documentation.workbench.empty_series"}}
                </p>
              {{/if}}
            </div>
          {{/if}}
        </section>
      </div>
    </div>

    {{#if this.drawer}}
      <div class="ingenic-doc-drawer__backdrop" role="presentation" {{on "click" this.closeDrawer}}></div>

      <aside class="ingenic-doc-drawer" role="dialog" aria-modal="true">
        <header class="ingenic-doc-drawer__head">
          <h3>{{this.drawerTitle}}</h3>
          <button type="button" class="ingenic-doc-drawer__close" {{on "click" this.closeDrawer}}>×</button>
        </header>

        <form class="ingenic-admin-form ingenic-doc-drawer__form" {{on "submit" this.submitDrawer}}>
          {{#if this.error}}
            <p class="ingenic-admin-note ingenic-admin-note--error">{{this.error}}</p>
          {{/if}}

          {{#if (eq this.drawer.kind "version")}}
            <label>
              <span>{{i18n "admin.ingenic.documentation.version_label"}}</span>
              <input name="label" value={{this.drawer.record.label}} required />
            </label>
            <label>
              <span>{{i18n "admin.ingenic.documentation.version_slug"}}</span>
              <input name="slug" value={{this.drawer.record.slug}} required />
            </label>
            <label>
              <span>{{i18n "admin.ingenic.documentation.locale"}}</span>
              <select name="locale" required>
                {{#each this.drawerLanguageOptions as |locale|}}
                  <option value={{locale.value}} selected={{eq locale.value this.drawerLocale}}>
                    {{locale.name}}
                  </option>
                {{/each}}
              </select>
            </label>
            <label>
              <span>{{i18n "admin.ingenic.documentation.released_on"}}</span>
              <input type="date" name="released_on" value={{this.drawer.record.released_on}} />
            </label>
            <label class="checkbox-label">
              <input type="checkbox" name="deprecated" checked={{this.drawer.record.deprecated}} />
              <span>{{i18n "admin.ingenic.documentation.deprecated"}}</span>
            </label>
          {{else}}
            <label>
              <span>
                {{#if (eq this.drawer.kind "series")}}
                  {{i18n "admin.ingenic.documentation.series_name"}}
                {{else}}
                  {{i18n "admin.ingenic.documentation.chip_name"}}
                {{/if}}
              </span>
              <input name="name" value={{this.drawer.record.name}} required />
            </label>
            <label>
              <span>
                {{#if (eq this.drawer.kind "series")}}
                  {{i18n "admin.ingenic.documentation.series_slug"}}
                {{else}}
                  {{i18n "admin.ingenic.documentation.chip_slug"}}
                {{/if}}
              </span>
              <input name="slug" value={{this.drawer.record.slug}} required />
            </label>
            <label>
              <span>{{i18n "admin.ingenic.documentation.locale"}}</span>
              <select name="locale" required>
                {{#each this.drawerLanguageOptions as |locale|}}
                  <option value={{locale.value}} selected={{eq locale.value this.drawerLocale}}>
                    {{locale.name}}
                  </option>
                {{/each}}
              </select>
            </label>
            <label class="checkbox-label">
              <input type="checkbox" name="published" checked={{this.drawer.record.published}} />
              <span>{{i18n "admin.ingenic.documentation.published"}}</span>
            </label>
          {{/if}}

          <div class="ingenic-doc-drawer__actions">
            <button type="submit" disabled={{this.busy}}>{{i18n "admin.ingenic.save"}}</button>
            <button type="button" class="btn" {{on "click" this.closeDrawer}}>
              {{i18n "admin.ingenic.documentation.cancel"}}
            </button>
          </div>
        </form>

        {{#if (eq this.drawer.action "edit")}}
          <div class="ingenic-doc-drawer__danger">
            {{#if (eq this.drawer.kind "version")}}
              <button
                type="button"
                class="btn btn-small"
                disabled={{this.busy}}
                {{on "click" (fn this.moveVersion this.drawer.record -1)}}
              >↑ {{i18n "admin.ingenic.documentation.move_up"}}</button>
              <button
                type="button"
                class="btn btn-small"
                disabled={{this.busy}}
                {{on "click" (fn this.moveVersion this.drawer.record 1)}}
              >↓ {{i18n "admin.ingenic.documentation.move_down"}}</button>
            {{else}}
              <button
                type="button"
                class="btn btn-small"
                disabled={{this.busy}}
                {{on "click" (fn this.moveProduct this.drawer.record -1)}}
              >↑ {{i18n "admin.ingenic.documentation.move_up"}}</button>
              <button
                type="button"
                class="btn btn-small"
                disabled={{this.busy}}
                {{on "click" (fn this.moveProduct this.drawer.record 1)}}
              >↓ {{i18n "admin.ingenic.documentation.move_down"}}</button>
            {{/if}}
            <button
              type="button"
              class="btn btn-danger"
              disabled={{this.busy}}
              {{on "click" this.deleteFromDrawer}}
            >{{i18n "admin.ingenic.documentation.delete"}}</button>
          </div>
        {{/if}}
      </aside>
    {{/if}}
  </template>
}
