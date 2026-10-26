import { service } from "@ember/service";
import DiscourseRoute from "discourse/routes/discourse";

// The same order the tabs are drawn in: the reader's first permitted screen,
// not the first screen in the abstract.
const AREAS = ["documentation", "boards", "downloads", "files", "site"];

export default class IngenicManageIndexRoute extends DiscourseRoute {
  @service router;

  beforeModel(transition) {
    const { areas } = this.modelFor("ingenic-manage");
    const area = AREAS.find((key) => areas[key]);

    if (area) {
      return this.router.replaceWith(`ingenic-manage.${area}`);
    } else {
      // Reaching the workbench means the server found *something* this account
      // may manage; an empty set here means the grants changed under an open
      // tab. Stopping is honest, and the shell says why.
      transition.abort();
    }
  }
}
