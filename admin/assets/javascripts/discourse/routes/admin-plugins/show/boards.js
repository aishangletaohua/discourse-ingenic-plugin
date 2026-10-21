import DiscourseRoute from "discourse/routes/discourse";
import { service } from "@ember/service";

export default class AdminPluginsShowBoards extends DiscourseRoute {
  @service ingenicContentLocale;

  model() {
    return this.ingenicContentLocale.load("/admin/plugins/discourse-ingenic/boards");
  }
}
