import IngenicSiteManagers from "../../components/ingenic-content/ingenic-site-managers";

const Site = <template>
  <IngenicSiteManagers
    @homepageBlocks={{@model.homepage_blocks}}
    @sectionCards={{@model.section_cards}}
    @promotions={{@model.promotions}}
    @headerLinks={{@model.header_links}}
    @socialLinks={{@model.social_links}}
    @footerColumns={{@model.footer_columns}}
  />
</template>;

export default Site;
