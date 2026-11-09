import java.util.ArrayList;
import java.util.List;

final class LineSolver {
    static final char UNKNOWN = '?', FILLED = '#', EMPTY = '.';
    static boolean[][] fitTable(char[] cells, int[] clue) {
        int n = cells.length, k = clue.length; int[] empties = new int[n + 1]; for (int i = 0; i < n; i++) empties[i + 1] = empties[i] + (cells[i] == EMPTY ? 1 : 0);
        boolean[][] table = new boolean[n + 1][k + 1]; table[0][0] = true;
        for (int end = 1; end <= n; end++) for (int count = 0; count <= k; count++) {
            boolean fits = cells[end - 1] != FILLED && table[end - 1][count];
            if (!fits && count > 0) { int start = end - clue[count - 1]; if (start >= 0 && empties[end] == empties[start]) fits = start == 0 ? count == 1 : cells[start - 1] != FILLED && table[start - 1][count - 1]; } table[end][count] = fits;
        }
        return table;
    }
    static final class Placements {
        final char[] cells;
        final int[] clue;
        final boolean[][] before, after;
        Placements(char[] cells, int[] clue) {
            this.cells = cells; this.clue = clue; before = fitTable(cells,clue); char[] reversedCells = new char[cells.length]; int[] reversedClue = new int[clue.length];
            for (int i = 0; i < cells.length; i++) reversedCells[i] = cells[cells.length - 1 - i]; for (int i = 0; i < clue.length; i++) reversedClue[i] = clue[clue.length - 1 - i]; after = fitTable(reversedCells,reversedClue);
        }
        boolean consistent() { return before[cells.length][clue.length]; }
        List<Integer> starts(int block) {
            List<Integer> starts = new ArrayList<>(); int n = cells.length;
            for (int start = 0; start + clue[block] <= n; start++) {
                int end = start + clue[block], rest = clue.length - block - 1; boolean clear = true; for (int i = start; i < end; i++) if (cells[i] == EMPTY) clear = false; if (!clear) continue;
                boolean left = start == 0 ? block == 0 : cells[start - 1] != FILLED && before[start - 1][block];
                boolean right = end == n ? rest == 0 : cells[end] != FILLED && after[n - end - 1][rest]; if (left && right) starts.add(start);
            }
            return starts;
        }
        boolean canBeEmpty(int index) { if (cells[index] == FILLED) return false; for (int k = 0; k <= clue.length; k++) if (before[index][k] && after[cells.length - index - 1][clue.length - k]) return true; return false; }
    }
    static boolean hasPlacement(char[] cells, int[] clue) { return new Placements(cells,clue).consistent(); }
    static char[] solve(char[] cells, int[] clue, boolean precise) {
        Placements placements = new Placements(cells,clue); if (!placements.consistent()) return null; char[] solved = cells.clone(); boolean[] covered = new boolean[cells.length];
        for (int block = 0; block < clue.length; block++) {
            List<Integer> starts = placements.starts(block); int length = clue[block];
            if (precise) { for (int start : starts) for (int i = start; i < start + length; i++) covered[i] = true; }
            else { for (int i = starts.getLast(); i < starts.getFirst() + length; i++) if (solved[i] == UNKNOWN) solved[i] = FILLED; for (int i = starts.getFirst(); i < starts.getLast() + length; i++) covered[i] = true; }
        }
        for (int i = 0; i < cells.length; i++) if (solved[i] == UNKNOWN) { if (!covered[i]) solved[i] = EMPTY; else if (precise && !placements.canBeEmpty(i)) solved[i] = FILLED; } return solved;
    }
}
