import DiscourseRoute from "discourse/routes/discourse";
import { service } from "@ember/service";

/**
 * The workbench's own payload: who this account is here, and which tabs it may
 * open. The tabs are decided by the server so that a link is never drawn for a
 * screen whose endpoints would answer with a 404.
 */
export default class IngenicManageRoute extends DiscourseRoute {
  @service ingenicContentLocale;

  model() {
    return this.ingenicContentLocale.load("/ingenic/manage");
  }
}
