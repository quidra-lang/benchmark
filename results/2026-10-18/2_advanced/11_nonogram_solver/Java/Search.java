import java.util.ArrayList;
import java.util.List;

record Cell(int row, int column) {}
record Guess(int number, int depth, int row, int column, char value, int solves, int known, String result) {}
final class Search {
    final List<Guess> guesses = new ArrayList<>();
    final List<char[][]> solutions = new ArrayList<>();
    final List<int[]> rows, columns;
    int backtracks, maxDepth, lineSolves;
    Search(List<int[]> rows, List<int[]> columns) { this.rows = rows; this.columns = columns; }
    static Cell guessCell(char[][] grid) {
        int h = grid.length, w = grid[0].length; int[] rows = new int[h], columns = new int[w];
        for (int r = 0; r < h; r++) for (int c = 0; c < w; c++) if (grid[r][c] == LineSolver.UNKNOWN) { rows[r]++; columns[c]++; }
        Cell best = new Cell(-1,-1); int score = Integer.MAX_VALUE;
        for (int r = 0; r < h; r++) for (int c = 0; c < w; c++) if (grid[r][c] == LineSolver.UNKNOWN && rows[r] + columns[c] < score) { best = new Cell(r,c); score = rows[r] + columns[c]; } return best;
    }
    boolean visit(char[][] parent, int depth) {
        Cell cell = guessCell(parent); int h = rows.size(), w = columns.size();
        for (char value : new char[] { LineSolver.FILLED,LineSolver.EMPTY }) {
            char[][] child = Propagation.copy(parent); child[cell.row()][cell.column()] = value; boolean[] rowMarks = new boolean[h], columnMarks = new boolean[w]; rowMarks[cell.row()] = true; columnMarks[cell.column()] = true;
            Propagation propagation = Propagation.run(child,rows,columns,true,rowMarks,columnMarks); int known = Propagation.determined(child); String outcome = "open";
            if (propagation.conflict != null) { outcome = "contradiction at=" + propagation.conflict.label(); backtracks++; }
            else if (known == h * w) { solutions.add(child); outcome = "solution" + solutions.size(); }
            lineSolves += propagation.steps.size(); maxDepth = Math.max(maxDepth,depth); guesses.add(new Guess(guesses.size() + 1,depth,cell.row(),cell.column(),value,propagation.steps.size(),known,outcome));
            if (outcome.equals("open")) { if (visit(child,depth + 1)) return true; } else if (solutions.size() == 2) return true;
        }
        return false;
    }
}
