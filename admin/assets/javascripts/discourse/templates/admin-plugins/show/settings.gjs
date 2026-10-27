import DPageSubheader from "discourse/ui-kit/d-page-subheader";
import IngenicAssistantSettings from "../../../../admin/components/ingenic-assistant-settings";
import getURL from "discourse/lib/get-url";
import { i18n } from "discourse-i18n";

const Settings = <template>
  <div class="admin-detail">
    <DPageSubheader
      @titleLabel={{i18n "ingenic.settings.title"}}
      @descriptionLabel={{i18n "ingenic.settings.description"}}
    />

    <p class="ingenic-admin-form__hint">
      {{i18n "ingenic.settings.hint"}}
    </p>

    <div class="ingenic-admin-form__actions">
      <a class="btn btn-primary" href={{getURL "/admin/site_settings?filter=ingenic"}}>
        {{i18n "ingenic.settings.plugin_settings"}}
      </a>
      <a class="btn" href={{getURL "/admin/groups"}}>
        {{i18n "ingenic.settings.groups"}}
      </a>
      <a class="btn" href={{getURL "/admin/customize/site_texts"}}>
        {{i18n "ingenic.settings.texts"}}
      </a>
    </div>

    <IngenicAssistantSettings />
  </div>
</template>;

export default Settings;
