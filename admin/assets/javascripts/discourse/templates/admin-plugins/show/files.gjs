import DPageSubheader from "discourse/ui-kit/d-page-subheader";
import IngenicFileManager from "../../../components/ingenic-content/ingenic-file-manager";
import { i18n } from "discourse-i18n";

const Files = <template>
  <div class="admin-detail">
    <DPageSubheader
      @titleLabel={{i18n "ingenic.files.title"}}
      @descriptionLabel={{i18n "ingenic.files.description"}}
    />
    <IngenicFileManager @initial={{@model}} />
  </div>
</template>;

export default Files;
