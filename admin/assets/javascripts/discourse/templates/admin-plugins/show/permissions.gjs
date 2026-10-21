import DPageSubheader from "discourse/ui-kit/d-page-subheader";
import IngenicPermissionManager from "../../../../admin/components/ingenic-permission-manager";
import { i18n } from "discourse-i18n";

const Permissions = <template>
  <div class="admin-detail">
    <DPageSubheader
      @titleLabel={{i18n "ingenic.permissions.title"}}
      @descriptionLabel={{i18n "ingenic.permissions.description"}}
    />
    <IngenicPermissionManager
      @permissions={{@model.permissions}}
      @products={{@model.products}}
    />
  </div>
</template>;

export default Permissions;
