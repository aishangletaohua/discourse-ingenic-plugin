import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import IngenicHomepageManager from "./ingenic-homepage-manager";
import IngenicSectionCardManager from "./ingenic-section-card-manager";
import IngenicPromotionManager from "./ingenic-promotion-manager";
import IngenicHeaderLinkManager from "./ingenic-header-link-manager";
import IngenicSocialLinkManager from "./ingenic-social-link-manager";
import IngenicFooterManager from "./ingenic-footer-manager";
import { i18n } from "discourse-i18n";

/**
 * The parts of the site that are content rather than forum: the layout of the
 * front page, its promotion slots, the navigation strip, and the footer.
 *
 * They share a screen because they are the same kind of thing — short ordered
 * lists of things with a picture, a label and a destination — and because an
 * editor changing the site's front page is usually changing more than one of
 * them at a time. The screen is also the same for an administrator and for a
 * member given the site-content feature, so it lives in the shared bundle.
 */
export default class IngenicSiteManagers extends Component {
  // The layout comes first: it decides what the front page is, and the other
  // tabs fill the slots it places.
  @tracked tab = "homepage";

  get isHomepage() {
    return this.tab === "homepage";
  }

  get isSectionCards() {
    return this.tab === "section-cards";
  }

  get isPromotions() {
    return this.tab === "promotions";
  }

  get isHeaderLinks() {
    return this.tab === "header-links";
  }

  get isSocialLinks() {
    return this.tab === "social-links";
  }

  get isFooter() {
    return this.tab === "footer";
  }

  @action
  show(tab, event) {
    event.preventDefault();
    this.tab = tab;
  }

  <template>
    <div class="ingenic-admin__tabs">
      <button
        class="btn {{if this.isHomepage 'btn-primary'}}"
        type="button"
        {{on "click" (fn this.show "homepage")}}
      >
        {{i18n "ingenic.site.tab_homepage"}}
      </button>
      <button
        class="btn {{if this.isSectionCards 'btn-primary'}}"
        type="button"
        {{on "click" (fn this.show "section-cards")}}
      >
        {{i18n "ingenic.site.tab_section_cards"}}
      </button>
      <button
        class="btn {{if this.isPromotions 'btn-primary'}}"
        type="button"
        {{on "click" (fn this.show "promotions")}}
      >
        {{i18n "ingenic.site.tab_promotions"}}
      </button>
      <button
        class="btn {{if this.isHeaderLinks 'btn-primary'}}"
        type="button"
        {{on "click" (fn this.show "header-links")}}
      >
        {{i18n "ingenic.site.tab_header_links"}}
      </button>
      <button
        class="btn {{if this.isSocialLinks 'btn-primary'}}"
        type="button"
        {{on "click" (fn this.show "social-links")}}
      >
        {{i18n "ingenic.site.tab_social_links"}}
      </button>
      <button
        class="btn {{if this.isFooter 'btn-primary'}}"
        type="button"
        {{on "click" (fn this.show "footer")}}
      >
        {{i18n "ingenic.site.tab_footer"}}
      </button>
    </div>

    {{#if this.isHomepage}}
      <IngenicHomepageManager @homepageBlocks={{@homepageBlocks}} />
    {{else if this.isSectionCards}}
      <IngenicSectionCardManager @sectionCards={{@sectionCards}} />
    {{else if this.isHeaderLinks}}
      <IngenicHeaderLinkManager @headerLinks={{@headerLinks}} />
    {{else if this.isSocialLinks}}
      <IngenicSocialLinkManager @socialLinks={{@socialLinks}} />
    {{else if this.isFooter}}
      <IngenicFooterManager @footerColumns={{@footerColumns}} />
    {{else}}
      <IngenicPromotionManager @promotions={{@promotions}} />
    {{/if}}
  </template>
}
