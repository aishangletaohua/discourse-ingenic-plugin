import { array } from "@ember/helper";
import IngenicDocManager from "../../components/ingenic-content/ingenic-doc-manager";

// Keyed by the language the server answered in. `router.refresh()` re-runs the
// model hook but keeps the component instance, and the manager reads its
// route arguments once; changing the key destroys that instance so the new
// language's catalogue is read from scratch instead of leaving the previous
// language's selection on screen.
const Documentation = <template>
  {{#each (array @model.locale) key="@identity" as |locale|}}
    <IngenicDocManager @series={{@model.series}} @locale={{locale}} />
  {{/each}}
</template>;

export default Documentation;
