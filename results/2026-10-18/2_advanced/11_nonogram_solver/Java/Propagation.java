import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.stream.Collectors;

record LineStep(boolean row, int index, int gain, boolean contradiction) {
    String label() { return Propagation.label(row,index); }
    String text() { return label() + (contradiction ? "!" : "+" + gain); }
}
final class Propagation {
    final List<LineStep> steps = new ArrayList<>();
    LineStep conflict;
    String record() { return steps.stream().map(LineStep::text).collect(Collectors.joining(" ")); }
    static String label(boolean row, int index) { return (row ? "R" : "C") + (index + 1); }
    static char[] cells(char[][] grid, boolean row, int index) { if (row) return grid[index].clone(); char[] cells = new char[grid.length]; for (int i = 0; i < grid.length; i++) cells[i] = grid[i][index]; return cells; }
    static int determined(char[][] grid) { int count = 0; for (char[] row : grid) for (char state : row) if (state != LineSolver.UNKNOWN) count++; return count; }
    static char[][] copy(char[][] grid) { return Arrays.stream(grid).map(char[]::clone).toArray(char[][]::new); }
    static int first(boolean[] marks) { for (int i = 0; i < marks.length; i++) if (marks[i]) return i; return -1; }
    static Propagation run(char[][] grid, List<int[]> rows, List<int[]> columns, boolean precise, boolean[] rowMarks, boolean[] columnMarks) {
        Propagation result = new Propagation();
        while (true) {
            int index = first(rowMarks); boolean row = index >= 0;
            if (row) rowMarks[index] = false; else { index = first(columnMarks); if (index < 0) return result; columnMarks[index] = false; }
            char[] cells = cells(grid,row,index), solved = LineSolver.solve(cells,row ? rows.get(index) : columns.get(index),precise);
            if (solved == null) { LineStep step = new LineStep(row,index,0,true); result.steps.add(step); result.conflict = step; return result; }
            int gain = 0;
            for (int i = 0; i < cells.length; i++) if (cells[i] == LineSolver.UNKNOWN && solved[i] != LineSolver.UNKNOWN) { gain++; if (row) { grid[index][i] = solved[i]; columnMarks[i] = true; } else { grid[i][index] = solved[i]; rowMarks[i] = true; } }
            result.steps.add(new LineStep(row,index,gain,false));
        }
    }
}
