import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn, mut } from "@ember/helper";
import { eq, or } from "discourse/truth-helpers";
import { ajax } from "../../lib/ingenic-content-api";
import DNativeSelect from "discourse/ui-kit/d-native-select";
import { i18n } from "discourse-i18n";

const ENDPOINT = "/admin/plugins/discourse-ingenic/homepage-blocks";
const PREFIX = "ingenic.site.homepage";

// The same list the theme knows how to draw. The server refuses anything else,
// so this is what the picker offers rather than a second source of truth.
const TYPES = [
  "categories",
  "promotions",
  "announcements",
  "discussions",
  "latest",
  "hot",
  "downloads",
  "boards",
  "bounties",
  "leaderboard",
];

// "Automatic" is the control's own empty option, not a fourth layout.
const LAYOUTS = ["full", "main", "side"];

// The layout the theme draws when nothing has been saved. Shown here so the
// first visit to this screen is what the front page actually looks like, not an
// empty list that hides it.
const DEFAULT_BLOCKS = [
  { type: "categories", limit: 3 },
  { type: "latest", limit: 8 },
  { type: "promotions", limit: 3 },
  { type: "hot", limit: 5 },
  { type: "bounties", limit: 5 },
  { type: "leaderboard", limit: 5 },
];

/**
 * The home page's layout.
 *
 * A block is a place in an ordered list rather than a record with an address,
 * so the whole list is edited together and saved together: moving one block
 * above another is one change, and half of it must never reach the database.
 */
export default class IngenicHomepageManager extends Component {
  get typeOptions() {
    return TYPES.map((type) => ({
      type,
      label: i18n(`${PREFIX}.types.${type}`),
    }));
  }

  get layoutOptions() {
    return LAYOUTS.map((layout) => ({
      layout,
      label: i18n(`${PREFIX}.fields.layout_${layout}`),
    }));
  }

  @tracked stored = this.args.homepageBlocks ?? [];
  @tracked blocks = this.#normalize(this.stored);
  @tracked newType = "latest";
  @tracked busy = false;
  @tracked message = null;
  @tracked error = null;

  // Whether the page below is the theme's default rather than a saved layout.
  // It is not the same as "the list is empty": the editor is filled with the
  // defaults so they can be adjusted instead of retyped.
  get usingDefaults() {
    return this.stored.length === 0;
  }

  #normalize(source) {
    return source.map((block) => ({
      type: block.type,
      layout: block.layout ?? "",
      title: block.title ?? "",
      limit: block.limit ?? 5,
      category: block.category ?? "",
      // A one-line field, so the list is edited as the comma-separated line an
      // admin would type. The server splits it back out.
      categories: Array.isArray(block.categories)
        ? block.categories.join(", ")
        : (block.categories ?? ""),
      show_all: block.show_all !== false,
    }));
  }

  @action
  update(index, event) {
    const { name, type, value, checked } = event.target;
    const next = type === "checkbox" ? checked : value;

    this.blocks = this.blocks.map((block, position) =>
      position === index ? { ...block, [name]: next } : block
    );
    this.message = null;
  }

  @action
  pickType(index, value) {
    this.blocks = this.blocks.map((block, position) =>
      position === index ? { ...block, type: value } : block
    );
  }

  @action
  pickLayout(index, value) {
    this.blocks = this.blocks.map((block, position) =>
      position === index ? { ...block, layout: value ?? "" } : block
    );
  }

  @action
  add(event) {
    event.preventDefault();
    this.blocks = [...this.blocks, { ...this.#normalize([{ type: this.newType }])[0] }];
    this.message = null;
    this.error = null;
  }

  @action
  remove(index) {
    this.blocks = this.blocks.filter((_block, position) => position !== index);
    this.message = null;
  }

  @action
  move(index, offset) {
    const target = index + offset;
    if (target < 0 || target >= this.blocks.length) {
      return;
    }

    const next = [...this.blocks];
    [next[index], next[target]] = [next[target], next[index]];
    this.blocks = next;
    this.message = null;
  }

  @action
  async save(event) {
    event.preventDefault();
    this.busy = true;
    this.message = null;
    this.error = null;

    try {
      const response = await ajax(ENDPOINT, {
        type: "PUT",
        data: { blocks: JSON.stringify(this.blocks) },
      });

      this.stored = response.homepage_blocks ?? [];
      this.blocks = this.#normalize(this.stored);
      this.message = i18n(`${PREFIX}.saved`);
    } catch (failure) {
      const errors = failure?.jqXHR?.responseJSON?.errors;
      this.error = errors?.join(", ") || i18n("ingenic.save_failed");
    } finally {
      this.busy = false;
    }
  }

  <template>
    <div class="ingenic-admin-panel">
      {{#if this.error}}
        <p class="ingenic-admin-note ingenic-admin-note--error">{{this.error}}</p>
      {{/if}}
      {{#if this.message}}
        <p class="ingenic-admin-note">{{this.message}}</p>
      {{/if}}

      <p class="ingenic-admin-form__hint">
        {{i18n "ingenic.site.homepage.intro"}}
      </p>

      {{#if this.usingDefaults}}
        <p class="ingenic-admin-note">
          {{i18n "ingenic.site.homepage.default_hint"}}
        </p>
      {{/if}}

      <form {{on "submit" this.save}}>
        <div class="ingenic-admin-list">
          {{#each this.blocks as |block index|}}
            <section class="ingenic-admin-list__row ingenic-admin-block">
              <div class="ingenic-admin-block__fields">
                <label>
                  <span>{{i18n "ingenic.site.homepage.fields.type"}}</span>
                  <DNativeSelect
                    @value={{block.type}}
                    @includeNone={{false}}
                    @onChange={{fn this.pickType index}}
                    as |select|
                  >
                    {{#each this.typeOptions as |option|}}
                      <select.Option @value={{option.type}}>
                        {{option.label}}
                      </select.Option>
                    {{/each}}
                  </DNativeSelect>
                </label>

                <label>
                  <span>{{i18n "ingenic.site.homepage.fields.title"}}</span>
                  <input
                    name="title"
                    value={{block.title}}
                    placeholder={{i18n
                      "ingenic.site.homepage.fields.title_hint"
                    }}
                    {{on "input" (fn this.update index)}}
                  />
                </label>

                <label>
                  <span>{{i18n "ingenic.site.homepage.fields.layout"}}</span>
                  <DNativeSelect
                    @value={{block.layout}}
                    @nonePlaceholder={{i18n
                      "ingenic.site.homepage.fields.layout_auto"
                    }}
                    @onChange={{fn this.pickLayout index}}
                    as |select|
                  >
                    {{#each this.layoutOptions as |option|}}
                      <select.Option @value={{option.layout}}>
                        {{option.label}}
                      </select.Option>
                    {{/each}}
                  </DNativeSelect>
                </label>

                <label>
                  <span>{{i18n "ingenic.site.homepage.fields.limit"}}</span>
                  <input
                    type="number"
                    min="1"
                    max="50"
                    name="limit"
                    value={{block.limit}}
                    {{on "input" (fn this.update index)}}
                  />
                </label>

                {{#if (eq block.type "categories")}}
                  <label class="ingenic-admin-block__wide">
                    <span>{{i18n "ingenic.site.homepage.fields.categories"}}</span>
                    <input
                      name="categories"
                      value={{block.categories}}
                      {{on "input" (fn this.update index)}}
                    />
                  </label>

                  <label class="checkbox-label">
                    <input
                      type="checkbox"
                      name="show_all"
                      checked={{block.show_all}}
                      {{on "input" (fn this.update index)}}
                    />
                    <span>{{i18n "ingenic.site.homepage.fields.show_all"}}</span>
                  </label>
                {{/if}}

                {{#if
                  (or
                    (eq block.type "announcements") (eq block.type "discussions")
                  )
                }}
                  <label>
                    <span>{{i18n "ingenic.site.homepage.fields.category"}}</span>
                    <input
                      name="category"
                      value={{block.category}}
                      {{on "input" (fn this.update index)}}
                    />
                  </label>
                {{/if}}
              </div>

              <div class="ingenic-admin__toolbar">
                <button
                  class="btn btn-small"
                  type="button"
                  title={{i18n "ingenic.site.homepage.move_up"}}
                  {{on "click" (fn this.move index -1)}}
                >
                  ↑
                </button>
                <button
                  class="btn btn-small"
                  type="button"
                  title={{i18n "ingenic.site.homepage.move_down"}}
                  {{on "click" (fn this.move index 1)}}
                >
                  ↓
                </button>
                <button
                  class="btn btn-danger btn-small"
                  type="button"
                  {{on "click" (fn this.remove index)}}
                >
                  {{i18n "ingenic.site.homepage.remove"}}
                </button>
              </div>
            </section>
          {{else}}
            <p>{{i18n "ingenic.empty"}}</p>
          {{/each}}
        </div>

        <div class="ingenic-admin__toolbar">
          <button class="btn btn-primary" type="submit" disabled={{this.busy}}>
            {{i18n "ingenic.site.homepage.save"}}
          </button>
        </div>
      </form>

      <div class="ingenic-admin__toolbar ingenic-admin-block__add">
        <DNativeSelect
          @value={{this.newType}}
          @includeNone={{false}}
          @onChange={{fn (mut this.newType)}}
          as |select|
        >
          {{#each this.typeOptions as |option|}}
            <select.Option @value={{option.type}}>{{option.label}}</select.Option>
          {{/each}}
        </DNativeSelect>

        <button class="btn" type="button" {{on "click" this.add}}>
          {{i18n "ingenic.site.homepage.add_button"}}
        </button>
      </div>
    </div>
  </template>
}
