/**
 * The content workbench.
 *
 * It sits outside `/admin` on purpose: the screens are for whoever looks after
 * a chip's documentation, boards or downloads, and an administrator is only one
 * of the people who might. The server decides who may open the page and which
 * tabs it offers; this map only names the addresses.
 */
export default function () {
  this.route("ingenic-manage", { path: "/ingenic/manage" }, function () {
    this.route("index", { path: "/" });
    this.route("documentation", { path: "documentation" });
    this.route("boards", { path: "boards" });
    this.route("downloads", { path: "downloads" });
    this.route("site", { path: "site" });
  });
}
