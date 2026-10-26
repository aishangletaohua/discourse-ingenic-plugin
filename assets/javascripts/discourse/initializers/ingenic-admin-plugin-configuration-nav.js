import { withPluginApi } from "discourse/lib/plugin-api";

const PLUGIN_ID = "discourse-ingenic";

/**
 * The Ingenic entries in the plugin's own admin navigation.
 *
 * The order is the order the work is done in: the permission page first,
 * because deciding who may do what comes before doing it; the five content
 * screens next; the forum-level configuration last. An administrator reading
 * the sidebar top to bottom sees the same structure as the workbench a scoped
 * manager opens at /ingenic/manage, minus the permission page and the
 * configuration screens — those decide who else may act, and delegating either
 * would let its holder widen their own grant.
 *
 * A member reaches only the screens they were given, through a whole-screen
 * grant (to their account or a group) or, for documentation and boards,
 * through a grant on a single product or board. Only those screens are offered:
 * everything else is decided on the server by `authorize_ingenic_feature!` and
 * `authorize_admin_only!`, and a link to a page that answers 404 is worse than
 * no link.
 */
export default {
  name: "ingenic-admin-plugin-configuration-nav",

  initialize(container) {
    const currentUser = container.lookup("service:current-user");
    if (!currentUser) {
      return;
    }

    const features = currentUser.ingenic_features ?? {};
    // A grant on one product or board is not a whole-screen feature, so the
    // server reports those two separately. Without them a documentation or
    // boards manager granted one chip would be offered an empty screen.
    const scoped = currentUser.ingenic_scoped_content ?? {};
    const canContent = currentUser.can_manage_ingenic_content;
    const anyFeature =
      features.documentation ||
      features.boards ||
      features.downloads ||
      features.files ||
      features.points ||
      features.site;

    if (!currentUser.admin && !canContent && !anyFeature) {
      return;
    }

    withPluginApi((api) => {
      api.setAdminPluginIcon(PLUGIN_ID, "book");

      const entries = [];

      if (currentUser.admin) {
        entries.push({
          label: "ingenic.permissions.title",
          route: "adminPlugins.show.permissions",
          currentWhen: "adminPlugins.show.permissions",
        });
      }

      if (currentUser.admin || features.documentation || scoped.documentation) {
        entries.push({
          label: "ingenic.documentation.title",
          route: "adminPlugins.show.documentation",
          currentWhen: "adminPlugins.show.documentation",
        });
      }

      if (currentUser.admin || features.boards || scoped.boards) {
        entries.push({
          label: "ingenic.boards.title",
          route: "adminPlugins.show.boards",
          currentWhen: "adminPlugins.show.boards",
        });
      }

      if (currentUser.admin || features.downloads) {
        entries.push({
          label: "ingenic.downloads.title",
          route: "adminPlugins.show.downloads",
          currentWhen: "adminPlugins.show.downloads",
        });
      }

      if (currentUser.admin || features.files) {
        entries.push({
          label: "ingenic.files.title",
          route: "adminPlugins.show.files",
          currentWhen: "adminPlugins.show.files",
        });
      }

      if (currentUser.admin || features.site) {
        entries.push({
          label: "ingenic.site.title",
          route: "adminPlugins.show.site",
          currentWhen: "adminPlugins.show.site",
        });
      }

      if (currentUser.admin || features.points) {
        entries.push({
          label: "ingenic.points.title",
          route: "adminPlugins.show.points",
          currentWhen: "adminPlugins.show.points",
        });
      }

      if (currentUser.admin) {
        entries.push(
          {
            label: "ingenic.tag_colours.title",
            route: "adminPlugins.show.tag-colours",
            currentWhen: "adminPlugins.show.tag-colours",
          },
          {
            label: "ingenic.category_permissions.title",
            route: "adminPlugins.show.category-permissions",
            currentWhen: "adminPlugins.show.category-permissions",
          },
          {
            label: "ingenic.settings.title",
            route: "adminPlugins.show.settings",
            currentWhen: "adminPlugins.show.settings",
          },
        );
      }

      api.addAdminPluginConfigurationNav(PLUGIN_ID, entries);
    });
  },
};
