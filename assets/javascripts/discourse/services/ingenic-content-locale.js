import Service from "@ember/service";
import { tracked } from "@glimmer/tracking";
import { ajax, setContentLocale } from "../lib/ingenic-content-api";

const STORAGE_KEY = "ingenic:content-locale";

/**
 * The language the content screens are working in.
 *
 * It is stored, not passed around: an editor writes the English manual, opens
 * the boards screen, and expects to still be writing English. Every request
 * reads it through `lib/ingenic-content-api`, so the pages do not each have to
 * carry a locale argument into their components.
 *
 * It is not the interface language. Someone reading the admin panel in Chinese
 * may still be editing the English documentation, which is the whole point of
 * choosing it separately.
 */
export default class IngenicContentLocale extends Service {
  @tracked current = null;
  @tracked locales = [];

  constructor() {
    super(...arguments);

    const stored = window.localStorage.getItem(STORAGE_KEY);
    this.current = stored || null;
    setContentLocale(this.current);
  }

  get hasChoice() {
    return this.locales.length > 1;
  }

  /**
   * Loads a content endpoint and takes the language the server answered in.
   *
   * Every content route needs both halves — the data and the list of languages
   * the picker offers — so they are one call rather than a convention each
   * route has to remember.
   */
  async load(path) {
    const payload = await ajax(path);
    this.configure(payload.locales, payload.locale);
    return payload;
  }

  /**
   * Called with a server payload. The stored language wins while the site still
   * serves it; otherwise the language the server answered in is adopted, so a
   * language switched off in site settings does not leave the screen asking for
   * a language the endpoint will not serve.
   */
  configure(locales, servedLocale) {
    this.locales = locales ?? [];

    const values = this.locales.map((locale) => locale.value);
    const stillServed = this.current && values.includes(this.current);

    this.current = stillServed ? this.current : servedLocale || values[0] || null;
    setContentLocale(this.current);

    return this.current;
  }

  select(locale) {
    this.current = locale;
    window.localStorage.setItem(STORAGE_KEY, locale);
    setContentLocale(locale);
  }
}
