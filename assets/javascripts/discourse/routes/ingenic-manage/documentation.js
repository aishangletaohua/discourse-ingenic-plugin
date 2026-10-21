import DiscourseRoute from "discourse/routes/discourse";
import { service } from "@ember/service";

export default class IngenicManageDocumentationRoute extends DiscourseRoute {
  @service ingenicContentLocale;

  beforeModel() {
    if (!this.modelFor("ingenic-manage").areas.documentation) {
      this.replaceWith("ingenic-manage.index");
    }
  }

  model() {
    return this.ingenicContentLocale.load("/admin/plugins/discourse-ingenic/documentation");
  }
}
