import DPageSubheader from "discourse/ui-kit/d-page-subheader";
import IngenicCategoryPermissionMatrix from "../../../../admin/components/ingenic-category-permission-matrix";
import { i18n } from "discourse-i18n";

const CategoryPermissions = <template>
  <div class="admin-detail">
    <DPageSubheader
      @titleLabel={{i18n "ingenic.category_permissions.title"}}
      @descriptionLabel={{i18n
        "ingenic.category_permissions.description"
      }}
    />
    <IngenicCategoryPermissionMatrix
      @categories={{@model.categories}}
      @groups={{@model.groups}}
    />
  </div>
</template>;

export default CategoryPermissions;
