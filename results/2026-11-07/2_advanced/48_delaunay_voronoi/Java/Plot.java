import java.util.*;

final class Plot {
    record Cell(int col, int row) {}
    static char[][] canvas(int width, int height) {
        char[][] grid = new char[height][width];
        for (char[] row : grid)
            Arrays.fill(row, ' ');
        return grid;
    }
    static Cell map(Predicates.Point point, int width, int height) {
        return new Cell((int)((2 * point.x() * (width - 1) + 1000) / 2000),
                        height - 1 - (int)((2 * point.y() * (height - 1) + 1000) / 2000));
    }
    static Cell center(Predicates.Center point, int width, int height) {
        return new Cell((int)((2 * point.x() * (width - 1) + 1000 * point.d()) / (2000 * point.d())),
                        height - 1 -
                            (int)((2 * point.y() * (height - 1) + 1000 * point.d()) / (2000 * point.d())));
    }
    static void line(char[][] grid, Cell from, Cell to, char ch) {
        int x = from.col(), y = from.row(), dx = Math.abs(to.col() - x), dy = -Math.abs(to.row() - y),
            sx = x < to.col() ? 1 : -1, sy = y < to.row() ? 1 : -1, e = dx + dy;
        while (true) {
            grid[y][x] = ch;
            if (x == to.col() && y == to.row())
                break;
            int e2 = 2 * e;
            if (e2 >= dy) {
                e += dy;
                x += sx;
            }
            if (e2 <= dx) {
                e += dx;
                y += sy;
            }
        }
    }
    static List<String> frame(char[][] grid) {
        String border = "+"
                        + "-".repeat(grid[0].length) + "+";
        List<String> result = new ArrayList<>();
        result.add(border);
        for (char[] row : grid)
            result.add("|" + new String(row) + "|");
        result.add(border);
        return result;
    }
    static char[][] voronoi(List<Predicates.Point> points, int width, int height) {
        char[][] grid = canvas(width, height);
        int[][] owners = new int[height][width];
        for (int row = 0; row < height; row++)
            for (int col = 0; col < width; col++) {
                long best = Long.MAX_VALUE;
                int owner = 0;
                for (int site = 1; site < points.size(); site++) {
                    Predicates.Point p = points.get(site);
                    long x = (col * 1000 - p.x() * (width - 1)) * (height - 1),
                         y = ((height - 1 - row) * 1000 - p.y() * (height - 1)) * (width - 1),
                         delta = x * x + y * y;
                    if (delta < best) {
                        best = delta;
                        owner = site;
                    }
                }
                owners[row][col] = owner;
            }
        for (int row = 0; row < height; row++)
            for (int col = 0; col < width; col++)
                if (col + 1 < width && owners[row][col] != owners[row][col + 1] ||
                    row + 1 < height && owners[row][col] != owners[row + 1][col])
                    grid[row][col] = '#';
        for (int site = 1; site < points.size(); site++) {
            Cell cell = map(points.get(site), width, height);
            grid[cell.row()][cell.col()] = 'o';
        }
        return grid;
    }
}
