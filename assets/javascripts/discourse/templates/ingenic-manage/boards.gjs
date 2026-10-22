import { array } from "@ember/helper";
import IngenicBoardManager from "../../components/ingenic-content/ingenic-board-manager";

// Keyed by language for the same reason as the documentation screen: a
// refreshed model changes the arguments, but only a new component instance
// re-reads the tracked copies the manager builds from them.
const Boards = <template>
  {{#each (array @model.locale) key="@identity" as |locale|}}
    <IngenicBoardManager
      @boards={{@model.boards}}
      @chips={{@model.chips}}
      @locale={{locale}}
    />
  {{/each}}
</template>;

export default Boards;
