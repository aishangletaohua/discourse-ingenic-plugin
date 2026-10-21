import DiscourseRoute from "discourse/routes/discourse";
import { service } from "@ember/service";

export default class AdminPluginsShowSite extends DiscourseRoute {
  @service ingenicContentLocale;

  model() {
    // One request: the lists are short, and they are drawn on one screen.
    return this.ingenicContentLocale.load("/admin/plugins/discourse-ingenic/site");
  }
}
