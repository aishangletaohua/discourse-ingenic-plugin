import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

const ENDPOINT = "/admin/plugins/discourse-ingenic/assistant";

/**
 * Forum Helper, the forum's own AI assistant.
 *
 * It is a system agent, which is why it has no row in the AI agent editor: its
 * prompt and tools come from code. An administrator still has to be able to see
 * whether it is answering and whether it can read the developer centre, and to
 * switch either off — so both live here, next to the rest of the plugin's
 * switches, rather than in a place that cannot show them.
 *
 * The two switches are independent on purpose. Turning off the knowledge leaves
 * a normal forum assistant behind; turning off the agent stops it answering at
 * all. Neither deletes anything.
 *
 * The component loads its own state: core owns the `adminPlugins.show.settings`
 * route and its model, so there is no place to hang this off the route.
 *
 * The class prefix is `ingenic-helper`, not `ingenic-assistant`: the theme uses
 * `ingenic-assistant` for the floating launcher, and sharing the name made this
 * block inherit its `position: fixed`.
 */
export default class IngenicHelperSettings extends Component {
  @tracked status = null;
  @tracked busy = false;
  @tracked message = null;

  constructor() {
    super(...arguments);
    this.load();
  }

  get loaded() {
    return this.status !== null;
  }

  get available() {
    return Boolean(this.status?.available);
  }

  get agentEnabled() {
    return Boolean(this.status?.agent?.enabled);
  }

  get knowledgeEnabled() {
    return Boolean(this.status?.knowledge?.enabled);
  }

  get knowledgeAttached() {
    return Boolean(this.status?.knowledge?.attached);
  }

  get botEnabled() {
    return Boolean(this.status?.bot_enabled);
  }

  get agentName() {
    return this.status?.agent?.name || i18n("ingenic.assistant.agent_name");
  }

  async load() {
    try {
      this.status = await ajax(ENDPOINT);
    } catch {
      this.status = { available: false };
    }
  }

  async save(payload) {
    this.busy = true;
    this.message = null;

    try {
      this.status = await ajax(ENDPOINT, {
        type: "PUT",
        data: JSON.stringify(payload),
        contentType: "application/json",
      });
      this.message = i18n("ingenic.saved");
    } catch (error) {
      this.status = { ...this.status };
      this.message =
        error.jqXHR?.responseJSON?.errors?.join(", ") ||
        i18n("ingenic.save_failed");
    } finally {
      this.busy = false;
    }
  }

  @action
  toggleAgent(event) {
    this.save({ agent_enabled: event.target.checked });
  }

  @action
  toggleKnowledge(event) {
    this.save({ search_enabled: event.target.checked });
  }

  <template>
    <section class="ingenic-helper">
      <h3 class="ingenic-helper__title">{{i18n "ingenic.assistant.title"}}</h3>
      <p class="ingenic-admin-form__hint">
        {{i18n "ingenic.assistant.hint"}}
      </p>

      {{#unless this.loaded}}
        <p class="ingenic-admin-form__hint">{{i18n "ingenic.loading"}}</p>
      {{else}}
        {{#if this.available}}
          <dl class="ingenic-helper__status">
            <div class="ingenic-helper__row">
              <dt>{{i18n "ingenic.assistant.agent"}}</dt>
              <dd>
                <span class="ingenic-helper__name">{{this.agentName}}</span>
                <span
                  class="ingenic-helper__badge {{if this.agentEnabled 'is-on' 'is-off'}}"
                >
                  {{#if this.agentEnabled}}
                    {{i18n "ingenic.assistant.state_on"}}
                  {{else}}
                    {{i18n "ingenic.assistant.state_off"}}
                  {{/if}}
                </span>
              </dd>
            </div>

            <div class="ingenic-helper__row">
              <dt>{{i18n "ingenic.assistant.bot"}}</dt>
              <dd>
                <span
                  class="ingenic-helper__badge {{if this.botEnabled 'is-on' 'is-off'}}"
                >
                  {{#if this.botEnabled}}
                    {{i18n "ingenic.assistant.state_on"}}
                  {{else}}
                    {{i18n "ingenic.assistant.state_off"}}
                  {{/if}}
                </span>
              </dd>
            </div>

            <div class="ingenic-helper__row">
              <dt>{{i18n "ingenic.assistant.knowledge"}}</dt>
              <dd>
                <span
                  class="ingenic-helper__badge {{if this.knowledgeAttached 'is-on' 'is-off'}}"
                >
                  {{#if this.knowledgeAttached}}
                    {{i18n "ingenic.assistant.attached"}}
                  {{else}}
                    {{i18n "ingenic.assistant.detached"}}
                  {{/if}}
                </span>
              </dd>
            </div>
          </dl>

          <label class="ingenic-helper__switch">
            <input
              type="checkbox"
              checked={{this.agentEnabled}}
              disabled={{this.busy}}
              {{on "change" this.toggleAgent}}
            />
            <span>{{i18n "ingenic.assistant.agent_switch"}}</span>
          </label>

          <label class="ingenic-helper__switch">
            <input
              type="checkbox"
              checked={{this.knowledgeEnabled}}
              disabled={{this.busy}}
              {{on "change" this.toggleKnowledge}}
            />
            <span>{{i18n "ingenic.assistant.knowledge_switch"}}</span>
          </label>

          {{#if this.message}}
            <p class="ingenic-admin-form__hint">{{this.message}}</p>
          {{/if}}
        {{else}}
          <p class="ingenic-admin-form__hint">
            {{i18n "ingenic.assistant.unavailable"}}
          </p>
        {{/if}}
      {{/unless}}
    </section>
  </template>
}
