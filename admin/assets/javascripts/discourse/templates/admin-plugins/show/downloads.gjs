import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { array, fn } from "@ember/helper";
import DPageSubheader from "discourse/ui-kit/d-page-subheader";
import IngenicDownloadManager from "../../../components/ingenic-content/ingenic-download-manager";
import IngenicDownloadQueue from "../../../../admin/components/ingenic-download-queue";
import IngenicGrantList from "../../../../admin/components/ingenic-grant-list";
import IngenicCategoryManager from "../../../components/ingenic-content/ingenic-category-manager";
import IngenicDownloadLog from "../../../../admin/components/ingenic-download-log";
import IngenicContentLocaleBar from "../../../components/ingenic-content-locale-bar";
import { i18n } from "discourse-i18n";

/**
 * The surfaces of the download centre on one page.
 *
 * They sit together because they are read together: a resource's access level
 * is the reason its queue exists, the queue is the reason a grant exists, and
 * the log is what says whether the grant was ever used. Switching between them
 * does not refetch, so a decision made in one is visible in the others.
 *
 * A scoped content manager is refused the queue, the grant list and the log —
 * deciding an application is an administrative act rather than a content edit,
 * and the log names accounts — so those arrive as null and their tabs are not
 * offered. The classification list is content, so it is offered to everyone who
 * can reach this page.
 */
export default class AdminPluginsShowDownloads extends Component {
  @tracked tab = "resources";

  get canReview() {
    return Boolean(this.args.model.requests) && Boolean(this.args.model.grants);
  }

  // Not read from the model: the log is fetched by its own component when the
  // tab is opened, so a page load does not pull five hundred rows nobody asked
  // for. What the model carries is whether this account may read it at all.
  get canReadLog() {
    return this.args.model.resources.can_read_log === true;
  }

  // The fallback as well as the default: a tab that is not offered cannot be
  // the one on screen, and showing the resource list is better than showing
  // nothing if a tab is somehow selected without permission.
  get isResources() {
    return !this.isRequests && !this.isGrants && !this.isCategories && !this.isLog;
  }

  get isRequests() {
    return this.tab === "requests" && this.canReview;
  }

  get isGrants() {
    return this.tab === "grants" && this.canReview;
  }

  get isCategories() {
    return this.tab === "categories";
  }

  get isLog() {
    return this.tab === "log" && this.canReadLog;
  }

  @action
  show(tab, event) {
    event.preventDefault();
    this.tab = tab;
  }

  <template>
    <div class="admin-detail">
      <DPageSubheader
        @titleLabel={{i18n "ingenic.downloads.title"}}
        @descriptionLabel={{i18n "ingenic.downloads.description"}}
      />

      <IngenicContentLocaleBar />

      <div class="ingenic-admin__tabs">
        <button
          class="btn {{if this.isResources 'btn-primary'}}"
          type="button"
          {{on "click" (fn this.show "resources")}}
        >
          {{i18n "ingenic.downloads.tab_resources"}}
        </button>
        {{#if this.canReview}}
          <button
            class="btn {{if this.isRequests 'btn-primary'}}"
            type="button"
            {{on "click" (fn this.show "requests")}}
          >
            {{i18n "ingenic.downloads.tab_requests"}}
          </button>
          <button
            class="btn {{if this.isGrants 'btn-primary'}}"
            type="button"
            {{on "click" (fn this.show "grants")}}
          >
            {{i18n "ingenic.downloads.tab_grants"}}
          </button>
          {{#if this.canReadLog}}
            <button
              class="btn {{if this.isLog 'btn-primary'}}"
              type="button"
              {{on "click" (fn this.show "log")}}
            >
              {{i18n "ingenic.downloads.tab_log"}}
            </button>
          {{/if}}
        {{/if}}
        <button
          class="btn {{if this.isCategories 'btn-primary'}}"
          type="button"
          {{on "click" (fn this.show "categories")}}
        >
          {{i18n "ingenic.downloads.tab_categories"}}
        </button>
      </div>

      {{#each (array this.args.model.resources.locale) key="@identity" as |locale|}}
        {{#if this.isRequests}}
          <IngenicDownloadQueue @requests={{this.args.model.requests.requests}} />
        {{else if this.isGrants}}
          <IngenicGrantList @grants={{this.args.model.grants.grants}} />
        {{else if this.isCategories}}
          <IngenicCategoryManager
            @categories={{this.args.model.resources.categories}}
            @locale={{locale}}
          />
        {{else if this.isLog}}
          <IngenicDownloadLog />
        {{else}}
          <IngenicDownloadManager
            @downloads={{this.args.model.resources.downloads}}
            @categories={{this.args.model.resources.categories}}
            @accessLevels={{this.args.model.resources.access_levels}}
            @chips={{this.args.model.resources.chips}}
            @storageWritable={{this.args.model.resources.storage_writable}}
            @locale={{locale}}
          />
        {{/if}}
      {{/each}}
    </div>
  </template>
}
