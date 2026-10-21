import DiscourseRoute from "discourse/routes/discourse";
import { service } from "@ember/service";
import { ajax } from "../../../lib/ingenic-content-api";

const ENDPOINT = "/admin/plugins/discourse-ingenic";

export default class AdminPluginsShowDownloads extends DiscourseRoute {
  @service ingenicContentLocale;

  async model() {
    const [resources, requests, grants] = await Promise.all([
      this.ingenicContentLocale.load(`${ENDPOINT}/downloads`),
      // Deciding an application is an administrator's act, so a scoped content
      // manager is refused here. That is not a failure of the page they did ask
      // for, so the refusal is caught and the tab is simply not offered.
      ajax(`${ENDPOINT}/download-requests`).catch(() => null),
      ajax(`${ENDPOINT}/download-grants`).catch(() => null),
    ]);

    return { resources, requests, grants };
  }
}
