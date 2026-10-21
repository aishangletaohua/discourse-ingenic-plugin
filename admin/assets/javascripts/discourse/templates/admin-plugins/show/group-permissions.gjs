import DPageSubheader from "discourse/ui-kit/d-page-subheader";
import IngenicGroupPermissionMatrix from "../../../../admin/components/ingenic-group-permission-matrix";
import { i18n } from "discourse-i18n";

const GroupPermissions = <template>
  <div class="admin-detail">
    <DPageSubheader
      @titleLabel={{i18n "ingenic.group_permissions.title"}}
      @descriptionLabel={{i18n "ingenic.group_permissions.description"}}
    />
    <IngenicGroupPermissionMatrix
      @groups={{@model.groups}}
      @features={{@model.features}}
    />
  </div>
</template>;

export default GroupPermissions;
