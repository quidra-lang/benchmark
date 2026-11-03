import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.List;

final class Grid {
    final List<String> rows;
    final int height, width;
    final char[] cells;
    Grid(List<String> rows) { this.rows = rows; height = rows.size(); width = rows.getFirst().length(); cells = String.join("", rows).toCharArray(); }
    int size() { return height * width; }
    int cell(int row, int column) { return row * width + column; }
    String location(int cell) { return (cell / width + 1) + "," + (cell % width + 1); }
    boolean open(int row, int column) { return row >= 0 && row < height && column >= 0 && column < width && rows.get(row).charAt(column) != '#'; }
    boolean given(int cell) { return cells[cell] != '#' && cells[cell] != '.'; }
    List<Integer> whites() {
        List<Integer> cells = new ArrayList<>();
        for (int cell = 0; cell < size(); cell++) if (this.cells[cell] != '#') cells.add(cell);
        return cells;
    }
    int asymmetric(String symmetry) {
        for (int row = 0; row < height; row++) for (int column = 0; column < width; column++) {
            int otherRow = symmetry.equals("rot180") ? height - 1 - row : row, otherColumn = width - 1 - column;
            if (open(row, column) != open(otherRow, otherColumn)) return cell(row, column);
        }
        return -1;
    }
    int components() {
        boolean[] seen = new boolean[size()]; int count = 0;
        int[] dr = {-1, 1, 0, 0}, dc = {0, 0, -1, 1};
        for (int start : whites()) {
            if (seen[start]) continue;
            count++; seen[start] = true; Deque<Integer> stack = new ArrayDeque<>(); stack.push(start);
            while (!stack.isEmpty()) {
                int point = stack.pop(), row = point / width, column = point % width;
                for (int i = 0; i < 4; i++) if (open(row + dr[i], column + dc[i])) {
                    int neighbor = cell(row + dr[i], column + dc[i]);
                    if (!seen[neighbor]) { seen[neighbor] = true; stack.push(neighbor); }
                }
            }
        }
        return count;
    }
}
