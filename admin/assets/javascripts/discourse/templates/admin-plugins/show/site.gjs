import DPageSubheader from "discourse/ui-kit/d-page-subheader";
import IngenicSiteManagers from "../../../components/ingenic-content/ingenic-site-managers";
import IngenicContentLocaleBar from "../../../components/ingenic-content-locale-bar";
import { i18n } from "discourse-i18n";

const Site = <template>
  <div class="admin-detail">
    <DPageSubheader
      @titleLabel={{i18n "ingenic.site.title"}}
      @descriptionLabel={{i18n "ingenic.site.description"}}
    />

    <IngenicContentLocaleBar />
    <IngenicSiteManagers
      @homepageBlocks={{@model.homepage_blocks}}
      @sectionCards={{@model.section_cards}}
      @promotions={{@model.promotions}}
      @headerLinks={{@model.header_links}}
      @socialLinks={{@model.social_links}}
      @footerColumns={{@model.footer_columns}}
    />
  </div>
</template>;

export default Site;
