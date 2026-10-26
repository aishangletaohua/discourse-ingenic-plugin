import { service } from "@ember/service";
import DiscourseRoute from "discourse/routes/discourse";

/**
 * The group matrix used to be a page of its own. It is now the second half of
 * the Permissions page, beside the account matrix and the per-chip grants, so
 * this address forwards rather than 404ing an administrator's bookmark.
 */
export default class AdminPluginsShowGroupPermissions extends DiscourseRoute {
  @service router;

  beforeModel() {
    // Ember 7 keeps `replaceWith` on the router service, not on the route.
    return this.router.replaceWith("adminPlugins.show.permissions");
  }
}
