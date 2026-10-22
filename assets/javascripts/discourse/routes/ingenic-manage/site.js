import DiscourseRoute from "discourse/routes/discourse";
import { service } from "@ember/service";

export default class IngenicManageSiteRoute extends DiscourseRoute {
  @service ingenicContentLocale;
  @service router;

  beforeModel() {
    if (!this.modelFor("ingenic-manage").areas.site) {
      this.router.replaceWith("ingenic-manage.index");
    }
  }

  model() {
    return this.ingenicContentLocale.load("/admin/plugins/discourse-ingenic/site");
  }
}
