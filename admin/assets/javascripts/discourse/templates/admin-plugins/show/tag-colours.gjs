import DPageSubheader from "discourse/ui-kit/d-page-subheader";
import IngenicTagColourManager from "../../../../admin/components/ingenic-tag-colour-manager";
import { i18n } from "discourse-i18n";

const TagColours = <template>
  <div class="admin-detail">
    <DPageSubheader
      @titleLabel={{i18n "ingenic.tag_colours.title"}}
      @descriptionLabel={{i18n "ingenic.tag_colours.description"}}
    />
    <IngenicTagColourManager
      @tags={{@model.tags}}
      @families={{@model.families}}
    />
  </div>
</template>;

export default TagColours;
