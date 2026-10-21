import { ajax as coreAjax } from "discourse/lib/ajax";

/**
 * The content APIs are scoped to one language, and that language is the screen's
 * rather than the administrator's interface language. Threading it through every
 * request by hand is how a save ends up in the wrong language: one call site
 * forgets, the row is written under the default, and nothing on screen says so.
 *
 * So the selected language is kept here, set once by the selector at the top of
 * the workbench, and every content request appends it. Call sites keep naming
 * the resource they are changing; they no longer name the language.
 */
let contentLocale = null;

export function setContentLocale(locale) {
  contentLocale = locale || null;
}

export function getContentLocale() {
  return contentLocale;
}

export function ajax(path, options = {}) {
  if (!contentLocale) {
    return coreAjax(path, options);
  }

  const separator = path.includes("?") ? "&" : "?";
  const scopedPath = `${path}${separator}locale=${encodeURIComponent(contentLocale)}`;

  return coreAjax(scopedPath, options);
}
