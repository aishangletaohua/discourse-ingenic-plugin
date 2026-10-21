import Component from "@glimmer/component";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DNativeSelect from "discourse/ui-kit/d-native-select";
import { i18n } from "discourse-i18n";

/**
 * The language the content screens are working in.
 *
 * It is the first thing on every screen because it changes what everything
 * below it means: a series created here belongs to the language chosen here,
 * and switching it shows the other language's catalogue, not a translated view
 * of this one.
 */
export default class IngenicContentLocaleBar extends Component {
  @service ingenicContentLocale;
  @service router;

  get locales() {
    return this.ingenicContentLocale.locales;
  }

  get current() {
    return this.ingenicContentLocale.current;
  }

  get visible() {
    return this.ingenicContentLocale.hasChoice;
  }

  // The route is refreshed rather than the page reloaded: every content model
  // is fetched with the language in the query string, so re-running the model
  // hooks is what replaces the data on screen.
  @action
  change(locale) {
    if (!locale || locale === this.current) {
      return;
    }

    this.ingenicContentLocale.select(locale);
    this.router.refresh();
  }

  <template>
    {{#if this.visible}}
      <div class="ingenic-content-locale">
        <label class="ingenic-content-locale__field">
          <span>{{i18n "ingenic.content_locale"}}</span>
          <DNativeSelect
            @includeNone={{false}}
            @value={{this.current}}
            @onChange={{this.change}}
            as |select|
          >
            {{#each this.locales as |locale|}}
              <select.Option @value={{locale.value}}>{{locale.name}}</select.Option>
            {{/each}}
          </DNativeSelect>
        </label>
        <p class="ingenic-content-locale__hint">{{i18n "ingenic.content_locale_hint"}}</p>
      </div>
    {{/if}}
  </template>
}
