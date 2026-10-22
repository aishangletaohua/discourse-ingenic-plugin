import { array } from "@ember/helper";
import IngenicSiteManagers from "../../components/ingenic-content/ingenic-site-managers";

// The language is the key: a refreshed model brings the other language's
// lists, and remounting is what clears the tracked copies each manager keeps.
const Site = <template>
  {{#each (array @model.locale) key="@identity" as |locale|}}
    <IngenicSiteManagers
      @homepageBlocks={{@model.homepage_blocks}}
      @sectionCards={{@model.section_cards}}
      @promotions={{@model.promotions}}
      @headerLinks={{@model.header_links}}
      @socialLinks={{@model.social_links}}
      @footerColumns={{@model.footer_columns}}
      @locale={{locale}}
    />
  {{/each}}
</template>;

export default Site;
