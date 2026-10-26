import Component from "@glimmer/component";
import { LinkTo } from "@ember/routing";
import IngenicContentLocaleBar from "../components/ingenic-content-locale-bar";
import { i18n } from "discourse-i18n";

// Drawn in the order a content editor is most likely to need them. The server
// sends which areas this account may open; `areas` filters this list rather
// than the list deciding anything.
const TABS = [
  {
    route: "ingenic-manage.documentation",
    area: "documentation",
    label: "ingenic.documentation.title",
  },
  { route: "ingenic-manage.boards", area: "boards", label: "ingenic.boards.title" },
  {
    route: "ingenic-manage.downloads",
    area: "downloads",
    label: "ingenic.downloads.title",
  },
  { route: "ingenic-manage.files", area: "files", label: "ingenic.files.title" },
  { route: "ingenic-manage.site", area: "site", label: "ingenic.site.title" },
];

export default class IngenicManageTemplate extends Component {
  get tabs() {
    const areas = this.args.model.areas ?? {};
    return TABS.filter((tab) => areas[tab.area]);
  }

  get hasTabs() {
    return this.tabs.length > 0;
  }

  // Permissions are staff-only, so they are not one of the workbench's tabs: a
  // scoped manager is here because they were granted one area, not because
  // they may hand that grant to somebody else. An administrator still needs a
  // way across to the screen that does, without remembering the address.
  get isAdmin() {
    return Boolean(this.args.model.admin);
  }

  <template>
    <div class="ingenic-manage">
      <header class="ingenic-manage__header">
        <div class="ingenic-manage__intro">
          <h1>{{i18n "ingenic.manage.title"}}</h1>
          <p>{{i18n "ingenic.manage.description"}}</p>
        </div>
        <IngenicContentLocaleBar />
      </header>

      {{#if this.isAdmin}}
        <p class="ingenic-manage__admin">
          <a href="/admin/plugins/discourse-ingenic">{{i18n "ingenic.manage.admin_link"}}</a>
        </p>
      {{/if}}

      {{#if this.hasTabs}}
        <nav class="ingenic-admin__tabs">
          {{#each this.tabs as |tab|}}
            <LinkTo @route={{tab.route}} class="btn">{{i18n tab.label}}</LinkTo>
          {{/each}}
        </nav>

        {{outlet}}
      {{else}}
        <p class="ingenic-admin-note">{{i18n "ingenic.manage.empty"}}</p>
      {{/if}}
    </div>
  </template>
}
