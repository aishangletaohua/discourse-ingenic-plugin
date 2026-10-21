import Component from "@glimmer/component";
import DPageSubheader from "discourse/ui-kit/d-page-subheader";
import IngenicPointsManager from "../../../../admin/components/ingenic-points-manager";
import { i18n } from "discourse-i18n";

export default class AdminPluginsShowPoints extends Component {
  <template>
    <div class="admin-detail">
      <DPageSubheader
        @titleLabel={{i18n "ingenic.points.title"}}
        @descriptionLabel={{i18n "ingenic.points.description"}}
      />

      <IngenicPointsManager
        @rules={{@model.rules}}
        @balances={{@model.balances}}
        @entries={{@model.entries}}
        @totals={{@model.totals}}
        @enabled={{@model.enabled}}
        @excludeStaff={{@model.exclude_staff}}
      />
    </div>
  </template>
}
