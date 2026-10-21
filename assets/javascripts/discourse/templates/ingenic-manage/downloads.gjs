import IngenicDownloadManager from "../../components/ingenic-content/ingenic-download-manager";
import IngenicCategoryManager from "../../components/ingenic-content/ingenic-category-manager";
import { i18n } from "discourse-i18n";

/**
 * The resource list and, underneath it, the classifications it is filed under.
 * They are two sections on one page rather than two tabs: the classifications
 * are three or four rows, and a manager who has just classified a resource
 * should be able to see the list they were choosing from.
 */
const Downloads = <template>
  <IngenicDownloadManager
    @downloads={{@model.downloads}}
    @categories={{@model.categories}}
    @accessLevels={{@model.access_levels}}
    @chips={{@model.chips}}
    @storageWritable={{@model.storage_writable}}
  />

  <h2 class="ingenic-manage__section">{{i18n "ingenic.downloads.tab_categories"}}</h2>
  <IngenicCategoryManager @categories={{@model.categories}} />
</template>;

export default Downloads;
