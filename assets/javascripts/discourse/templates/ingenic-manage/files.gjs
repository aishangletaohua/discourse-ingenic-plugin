import IngenicFileManager from "../../components/ingenic-content/ingenic-file-manager";
import { i18n } from "discourse-i18n";

const Files = <template>
  <h2 class="ingenic-manage__section">{{i18n "ingenic.files.title"}}</h2>
  <p class="ingenic-manage__hint">{{i18n "ingenic.files.workbench_hint"}}</p>
  <IngenicFileManager @initial={{@model}} />
</template>;

export default Files;
