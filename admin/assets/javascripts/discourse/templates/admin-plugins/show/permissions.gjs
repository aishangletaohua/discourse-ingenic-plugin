import DPageSubheader from "discourse/ui-kit/d-page-subheader";
import IngenicFeaturePermissions from "../../../../admin/components/ingenic-feature-permissions";
import IngenicPermissionManager from "../../../../admin/components/ingenic-permission-manager";
import { i18n } from "discourse-i18n";

const Permissions = <template>
  <div class="admin-detail">
    <DPageSubheader
      @titleLabel={{i18n "ingenic.permissions.title"}}
      @descriptionLabel={{i18n "ingenic.permissions.description"}}
    />

    <IngenicFeaturePermissions
      @groups={{@model.groups}}
      @users={{@model.users}}
      @features={{@model.features}}
    />

    <h2 class="ingenic-permission-section__title ingenic-permission-section__title--scope">
      {{i18n "ingenic.permissions.scope_heading"}}
    </h2>
    <p class="ingenic-admin-form__hint">
      {{i18n "ingenic.permissions.scope_hint"}}
    </p>

    <IngenicPermissionManager
      @permissions={{@model.permissions}}
      @products={{@model.products}}
    />
  </div>
</template>;

export default Permissions;
