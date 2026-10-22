import DiscourseRoute from "discourse/routes/discourse";
import { service } from "@ember/service";

export default class IngenicManageBoardsRoute extends DiscourseRoute {
  @service ingenicContentLocale;
  @service router;

  beforeModel() {
    if (!this.modelFor("ingenic-manage").areas.boards) {
      return this.router.replaceWith("ingenic-manage.index");
    }
  }

  model() {
    return this.ingenicContentLocale.load("/admin/plugins/discourse-ingenic/boards");
  }
}
