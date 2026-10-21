import getURL from "discourse/lib/get-url";
import { withPluginApi } from "discourse/lib/plugin-api";
import { i18n } from "discourse-i18n";

/**
 * A way into the content manager for members who are not administrators.
 *
 * The workbench lives at /ingenic/manage rather than inside /admin because the
 * people who write documentation and look after downloads are usually not
 * staff. Administrators already reach every screen from the plugin's own admin
 * navigation, so this row is only added for an account with a content grant and
 * no administrator flag; showing it to an administrator as well would be a
 * second door into the same room.
 *
 * The row sits in the community section, below the developer links, because the
 * theme owns that column. `shouldDisplay` is rechecked on every render: a grant
 * can be revoked while the page is open, and the row should disappear with it.
 */
export default {
  name: "ingenic-content-manager-link",

  initialize(container) {
    const currentUser = container.lookup("service:current-user");

    if (!currentUser?.can_manage_ingenic_content || currentUser.admin) {
      return;
    }

    withPluginApi((api) => {
      api.addCommunitySectionLink(
        (BaseCommunitySectionLink) =>
          class extends BaseCommunitySectionLink {
            get name() {
              return "ingenic-manage";
            }

            get text() {
              return i18n("ingenic.manage.title");
            }

            get title() {
              return this.text;
            }

            get href() {
              return getURL("/ingenic/manage");
            }

            get prefixType() {
              return "icon";
            }

            get prefixValue() {
              return "pen-to-square";
            }

            get shouldDisplay() {
              return !!this.currentUser?.can_manage_ingenic_content;
            }

            // Every content screen is nested under /ingenic/manage, so the row
            // stays highlighted while one of them is open.
            get currentWhen() {
              const current = (this.router.currentURL ?? "").split("?")[0];

              return (
                current === "/ingenic/manage" ||
                current.startsWith("/ingenic/manage/")
              );
            }
          },
      );
    });
  },
};
