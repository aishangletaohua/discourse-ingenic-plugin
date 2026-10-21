import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn, hash } from "@ember/helper";
import { ajax } from "discourse/lib/ajax";
import UserChooser from "discourse/select-kit/components/user-chooser";
import { i18n } from "discourse-i18n";

const ENDPOINT = "/admin/plugins/discourse-ingenic";

/**
 * The points screen: what each action pays, who is holding what, and every
 * movement that got them there.
 *
 * The rules are edited in place rather than opened in a form, because there are
 * four of them and the only thing an admin ever changes is the number and the
 * wording. Retiring one is a matter of switching it off or setting it to zero,
 * which is why there is no delete: a rule that was deleted would leave every
 * entry already written under its name pointing at nothing.
 *
 * The adjustment form is separate from the rules because it is a different kind
 * of act: not "what is a reply worth" but "this account, this many points, and
 * here is why". The note is required by the server if the reason is to be
 * readable later, so it is asked for here as well.
 */
export default class IngenicPointsManager extends Component {
  @tracked rules = this.args.rules ?? [];
  @tracked balances = this.args.balances ?? [];
  @tracked entries = this.args.entries ?? [];
  @tracked totals = this.args.totals ?? {};
  @tracked busy = false;
  @tracked message = null;
  @tracked error = null;

  // A username, resolved through the site's own user search, so an
  // administrator does not have to know an account's numeric id.
  @tracked username = null;
  @tracked amount = null;
  @tracked note = "";

  get enabled() {
    return this.args.enabled !== false;
  }

  get excludeStaff() {
    return this.args.excludeStaff === true;
  }

  get totalRows() {
    return [
      { key: "earned", label: i18n("ingenic.points.totals.earned"), value: this.totals.earned },
      { key: "spent", label: i18n("ingenic.points.totals.spent"), value: this.totals.spent },
      {
        key: "reversed",
        label: i18n("ingenic.points.totals.reversed"),
        value: this.totals.reversed,
      },
      {
        key: "adjusted",
        label: i18n("ingenic.points.totals.adjusted"),
        value: this.totals.adjusted,
      },
      // Points behind a standing 悬赏 are not in anybody's balance — they were
      // taken off the asker when the offer was opened — so without this figure
      // the four above and the balances would look like they disagreed.
      {
        key: "escrowed",
        label: i18n("ingenic.points.totals.escrowed"),
        value: this.totals.escrowed,
      },
      { key: "holders", label: i18n("ingenic.points.totals.holders"), value: this.totals.holders },
    ].map((row) => ({ ...row, value: row.value ?? 0 }));
  }

  @action
  async saveRule(rule, event) {
    event.preventDefault();
    this.#clear();

    const form = event.target;
    // Checkboxes are absent from FormData when unchecked, which the server
    // reads as "leave it alone" — the opposite of what unchecking means.
    const data = new FormData(form);
    data.set("published", String(form.elements.published.checked));

    try {
      const response = await ajax(`${ENDPOINT}/points/rules/${rule.id}`, {
        type: "PUT",
        data,
        processData: false,
        contentType: false,
      });
      this.rules = this.rules.map((item) =>
        item.id === rule.id ? response.rule : item
      );
      this.message = i18n("ingenic.saved");
    } catch (failure) {
      this.error = this.#errorMessage(failure);
    }
  }

  // The account picker is the site's own user chooser, which hands back the
  // usernames it selected. It is a single-value picker (`maximum=1`), so the
  // array always has one entry.
  @action
  pickUser(selected) {
    this.username = selected?.firstObject ?? null;
  }

  @action
  setAmount(event) {
    this.amount = event.target.value;
  }

  @action
  setNote(event) {
    this.note = event.target.value;
  }

  @action
  async adjust(event) {
    event.preventDefault();

    const username = this.username;
    if (!username) {
      this.error = i18n("ingenic.points.pick_account");
      return;
    }

    const points = Number.parseInt(this.amount, 10);
    if (!points) {
      this.error = i18n("ingenic.points.amount_required");
      return;
    }

    this.busy = true;
    this.#clear();

    try {
      const response = await ajax(`${ENDPOINT}/points/adjust`, {
        type: "POST",
        data: {
          username,
          points,
          note: this.note,
        },
      });

      if (response.entry) {
        this.entries = [response.entry, ...this.entries];
      }
      this.balances = this.#mergeBalance(response.entry, response.balance);
      this.totals = this.#bumpTotals(points);
      this.amount = null;
      this.note = "";
      this.username = null;
      this.message = i18n("ingenic.points.adjusted", {
        username,
        points: response.balance,
      });
    } catch (failure) {
      this.error = this.#errorMessage(failure);
    } finally {
      this.busy = false;
    }
  }

  // Recomputes every balance from the ledger. Answers with how many rows were
  // looked at and how many had drifted, so a run that changes nothing says so
  // rather than looking like it did not happen.
  @action
  async rebuild() {
    this.busy = true;
    this.#clear();

    try {
      const response = await ajax(`${ENDPOINT}/points/rebuild`, { type: "POST" });
      this.message = i18n("ingenic.points.rebuilt", {
        checked: response.checked,
        corrected: response.corrected,
      });
    } catch (failure) {
      this.error = this.#errorMessage(failure);
    } finally {
      this.busy = false;
    }
  }

  #mergeBalance(entry, points) {
    if (!entry) {
      return this.balances;
    }

    const existing = this.balances.find((row) => row.user_id === entry.user_id);
    const updated = {
      user_id: entry.user_id,
      username: entry.username,
      points,
      updated_at: entry.created_at,
    };

    const merged = existing
      ? this.balances.map((row) => (row.user_id === entry.user_id ? updated : row))
      : [...this.balances, updated];

    return merged.sort((a, b) => b.points - a.points);
  }

  #bumpTotals(points) {
    const adjusted = (this.totals.adjusted ?? 0) + points;
    return { ...this.totals, adjusted };
  }

  #clear() {
    this.message = null;
    this.error = null;
  }

  #errorMessage(failure) {
    const errors = failure?.jqXHR?.responseJSON?.errors;
    return errors?.join(", ") || i18n("ingenic.save_failed");
  }

  <template>
    <div class="ingenic-admin-panel">
      {{#unless this.enabled}}
        <p class="ingenic-admin-note ingenic-admin-note--error">
          {{i18n "ingenic.points.disabled_notice"}}
        </p>
      {{/unless}}

      {{#if this.excludeStaff}}
        <p class="ingenic-admin-note">{{i18n "ingenic.points.staff_notice"}}</p>
      {{/if}}

      {{#if this.error}}<p class="ingenic-admin-note ingenic-admin-note--error">{{this.error}}</p>{{/if}}
      {{#if this.message}}<p class="ingenic-admin-note">{{this.message}}</p>{{/if}}

      <div class="ingenic-admin__toolbar">
        {{#each this.totalRows as |row|}}
          <div class="ingenic-points__total">
            <span class="ingenic-points__total-value">{{row.value}}</span>
            <span class="ingenic-points__total-label">{{row.label}}</span>
          </div>
        {{/each}}
      </div>

      <h3>{{i18n "ingenic.points.rules_title"}}</h3>
      <p class="ingenic-admin-form__hint">{{i18n "ingenic.points.rules_hint"}}</p>

      <div class="ingenic-admin-list">
        {{#each this.rules as |rule|}}
          <section class="ingenic-admin-list__row">
            <form class="ingenic-admin-form ingenic-points__rule" {{on "submit" (fn this.saveRule rule)}}>
              <label>
                <span>{{i18n "ingenic.points.fields.event"}}</span>
                <input value={{rule.event}} disabled />
              </label>

              <label>
                <span>{{i18n "ingenic.points.fields.label"}}</span>
                <input name="label" value={{rule.label}} required />
              </label>

              <label>
                <span>{{i18n "ingenic.points.fields.points"}}</span>
                <input type="number" name="points" min="0" value={{rule.points}} required />
              </label>

              <label>
                <span>{{i18n "ingenic.points.fields.position"}}</span>
                <input type="number" name="position" value={{rule.position}} />
              </label>

              <label class="checkbox-label">
                <input type="checkbox" name="published" checked={{rule.published}} />
                <span>{{i18n "ingenic.points.fields.published"}}</span>
              </label>

              <div class="ingenic-admin__toolbar">
                <button class="btn btn-primary" type="submit" disabled={{this.busy}}>
                  {{i18n "ingenic.save"}}
                </button>
              </div>
            </form>
          </section>
        {{else}}
          <p>{{i18n "ingenic.points.no_rules"}}</p>
        {{/each}}
      </div>

      <h3>{{i18n "ingenic.points.adjust_title"}}</h3>
      <form class="ingenic-admin-form" {{on "submit" this.adjust}}>
        <label>
          <span>{{i18n "ingenic.points.fields.account"}}</span>
          <UserChooser
            @value={{this.username}}
            @onChange={{this.pickUser}}
            @options={{hash maximum=1}}
          />
        </label>

        <label>
          <span>{{i18n "ingenic.points.fields.amount"}}</span>
          <input type="number" value={{this.amount}} {{on "input" this.setAmount}} />
        </label>

        <label>
          <span>{{i18n "ingenic.points.fields.note"}}</span>
          <input value={{this.note}} {{on "input" this.setNote}} />
        </label>

        <p class="ingenic-admin-form__hint">{{i18n "ingenic.points.amount_hint"}}</p>

        <div class="ingenic-admin__toolbar">
          <button class="btn btn-primary" type="submit" disabled={{this.busy}}>
            {{i18n "ingenic.points.adjust"}}
          </button>
        </div>
      </form>

      <h3>{{i18n "ingenic.points.balances_title"}}</h3>
      <table class="ingenic-admin-table">
        <thead>
          <tr>
            <th>{{i18n "ingenic.points.columns.account"}}</th>
            <th>{{i18n "ingenic.points.columns.points"}}</th>
            <th>{{i18n "ingenic.points.columns.updated_at"}}</th>
          </tr>
        </thead>
        <tbody>
          {{#each this.balances as |row|}}
            <tr>
              <td>{{row.username}}</td>
              <td>{{row.points}}</td>
              <td>{{row.updated_at}}</td>
            </tr>
          {{else}}
            <tr><td colspan="3">{{i18n "ingenic.points.no_balances"}}</td></tr>
          {{/each}}
        </tbody>
      </table>

      <h3>{{i18n "ingenic.points.entries_title"}}</h3>
      <p class="ingenic-admin-form__hint">{{i18n "ingenic.points.entries_hint"}}</p>

      <table class="ingenic-admin-table">
        <thead>
          <tr>
            <th>{{i18n "ingenic.points.columns.taken_at"}}</th>
            <th>{{i18n "ingenic.points.columns.account"}}</th>
            <th>{{i18n "ingenic.points.columns.points"}}</th>
            <th>{{i18n "ingenic.points.columns.event"}}</th>
            <th>{{i18n "ingenic.points.columns.reason"}}</th>
            <th>{{i18n "ingenic.points.columns.by"}}</th>
          </tr>
        </thead>
        <tbody>
          {{#each this.entries as |entry|}}
            <tr>
              <td>{{entry.created_at}}</td>
              <td>
                {{#if entry.username}}
                  {{entry.username}}
                {{else}}
                  {{i18n "ingenic.deleted_member"}}
                {{/if}}
              </td>
              <td>{{entry.points}}</td>
              <td>{{entry.event}}</td>
              <td>{{entry.reason}}</td>
              <td>{{entry.awarded_by}}</td>
            </tr>
          {{else}}
            <tr><td colspan="6">{{i18n "ingenic.points.no_entries"}}</td></tr>
          {{/each}}
        </tbody>
      </table>

      <h3>{{i18n "ingenic.points.rebuild_title"}}</h3>
      <p class="ingenic-admin-form__hint">{{i18n "ingenic.points.rebuild_hint"}}</p>
      <div class="ingenic-admin__toolbar">
        <button class="btn" type="button" disabled={{this.busy}} {{on "click" this.rebuild}}>
          {{i18n "ingenic.points.rebuild"}}
        </button>
      </div>
    </div>
  </template>
}
