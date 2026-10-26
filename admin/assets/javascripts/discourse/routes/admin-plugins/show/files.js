import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "../../../lib/ingenic-content-api";

// The library is the same one the workbench shows; this address exists so an
// administrator who is already in the admin area does not have to leave it.
export default class AdminPluginsShowFiles extends DiscourseRoute {
  model() {
    return ajax("/admin/plugins/discourse-ingenic/files");
  }
}
