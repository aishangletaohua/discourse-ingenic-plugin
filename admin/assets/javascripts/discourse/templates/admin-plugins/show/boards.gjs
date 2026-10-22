import { array } from "@ember/helper";
import DPageSubheader from "discourse/ui-kit/d-page-subheader";
import IngenicBoardManager from "../../../components/ingenic-content/ingenic-board-manager";
import IngenicContentLocaleBar from "../../../components/ingenic-content-locale-bar";
import { i18n } from "discourse-i18n";

const Boards = <template>
  <div class="admin-detail">
    <DPageSubheader
      @titleLabel={{i18n "ingenic.boards.title"}}
      @descriptionLabel={{i18n "ingenic.boards.description"}}
    />
    <IngenicContentLocaleBar />
    {{#each (array @model.locale) key="@identity" as |locale|}}
      <IngenicBoardManager
        @boards={{@model.boards}}
        @chips={{@model.chips}}
        @locale={{locale}}
      />
    {{/each}}
  </div>
</template>;

export default Boards;
