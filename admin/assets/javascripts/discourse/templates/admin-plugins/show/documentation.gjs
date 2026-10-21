import DPageSubheader from "discourse/ui-kit/d-page-subheader";
import IngenicDocManager from "../../../components/ingenic-content/ingenic-doc-manager";
import IngenicContentLocaleBar from "../../../components/ingenic-content-locale-bar";
import { i18n } from "discourse-i18n";

const Documentation = <template>
  <div class="admin-detail">
    <DPageSubheader
      @titleLabel={{i18n "ingenic.documentation.title"}}
      @descriptionLabel={{i18n "ingenic.documentation.description"}}
    />
    <IngenicContentLocaleBar />
    <IngenicDocManager @series={{@model.series}} />
  </div>
</template>;

export default Documentation;
