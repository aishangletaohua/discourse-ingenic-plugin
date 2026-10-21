import DiscourseRoute from "discourse/routes/discourse";
import { service } from "@ember/service";

export default class IngenicManageDownloadsRoute extends DiscourseRoute {
  @service ingenicContentLocale;

  beforeModel() {
    if (!this.modelFor("ingenic-manage").areas.downloads) {
      this.replaceWith("ingenic-manage.index");
    }
  }

  model() {
    return this.ingenicContentLocale.load("/admin/plugins/discourse-ingenic/downloads");
  }
}
