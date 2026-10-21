import IngenicBoardManager from "../../components/ingenic-content/ingenic-board-manager";

const Boards = <template>
  <IngenicBoardManager @boards={{@model.boards}} @chips={{@model.chips}} />
</template>;

export default Boards;
