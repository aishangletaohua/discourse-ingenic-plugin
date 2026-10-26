export default {
  resource: "admin.adminPlugins.show",
  path: "/plugins",
  map() {
    this.route("documentation", { path: "documentation" });
    this.route("boards", { path: "boards" });
    this.route("permissions", { path: "permissions" });
    this.route("group-permissions", { path: "group-permissions" });
    this.route("category-permissions", { path: "category-permissions" });
    this.route("tag-colours", { path: "tag-colours" });
    this.route("downloads", { path: "downloads" });
    this.route("files", { path: "files" });
    this.route("points", { path: "points" });
    this.route("site", { path: "site" });
    this.route("settings", { path: "settings" });
  },
};
