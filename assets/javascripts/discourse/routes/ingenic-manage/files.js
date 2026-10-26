import DiscourseRoute from "discourse/routes/discourse";
import { service } from "@ember/service";
import { ajax } from "../../lib/ingenic-content-api";

// The library has no per-language content — a file's name is its name — so the
// listing is fetched as it is, without the locale the other workbench screens
// pass along.
export default class IngenicManageFilesRoute extends DiscourseRoute {
  @service router;

  beforeModel() {
    if (!this.modelFor("ingenic-manage").areas.files) {
      return this.router.replaceWith("ingenic-manage.index");
    }
  }

  model() {
    return ajax("/admin/plugins/discourse-ingenic/files");
  }
}
