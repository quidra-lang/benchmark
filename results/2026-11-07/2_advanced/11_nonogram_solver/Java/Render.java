import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.stream.Collectors;

record DisplayGrid(String name, char[][] grid) {}
final class Render {
    static char stateChar(char state) { return state; }
    static String stateString(char[] cells) { StringBuilder text = new StringBuilder(); for (char state : cells) text.append(stateChar(state)); return text.toString(); }
    static List<String> gridDisplay(List<DisplayGrid> grids) {
        if (grids.isEmpty()) return List.of(); List<String> lines = new ArrayList<>(); lines.add("grid " + grids.stream().map(DisplayGrid::name).collect(Collectors.joining(" ")));
        for (int r = 0; r < grids.getFirst().grid().length; r++) { List<String> cells = new ArrayList<>(); for (DisplayGrid grid : grids) cells.add(stateString(grid.grid()[r])); lines.add(String.join(" | ",cells)); } return lines;
    }
    static List<String> answerSheet(List<int[]> rows, List<int[]> columns, char[][] grid) {
        List<String[]> tokens = columns.stream().map(c -> Clues.text(c).split(" ")).toList(); int width = tokens.stream().flatMap(Arrays::stream).mapToInt(String::length).max().orElseThrow() + 1, depth = tokens.stream().mapToInt(c -> c.length).max().orElseThrow(), margin = rows.stream().mapToInt(c -> Clues.text(c).length()).max().orElseThrow(); List<String> lines = new ArrayList<>();
        for (int i = 0; i < depth; i++) { StringBuilder text = new StringBuilder(" ".repeat(margin)); for (String[] column : tokens) { int index = i - depth + column.length; String token = index < 0 ? "" : column[index]; text.append(" ".repeat(width - token.length())).append(token); } lines.add(text.toString().stripTrailing()); }
        for (int r = 0; r < rows.size(); r++) { String clue = Clues.text(rows.get(r)); StringBuilder text = new StringBuilder(" ".repeat(margin - clue.length()) + clue); for (char state : grid[r]) text.append(" ".repeat(width - 1)).append(stateChar(state)); lines.add(text.toString()); } return lines;
    }
}
