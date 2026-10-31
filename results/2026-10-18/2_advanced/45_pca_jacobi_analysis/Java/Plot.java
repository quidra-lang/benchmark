import java.util.*;

final class Plot {
    record Cell(int row, int col) {}
    static char[][] grid(int rows, int cols) {
        char[][] grid = new char[rows][cols];
        for (char[] row : grid)
            Arrays.fill(row, ' ');
        return grid;
    }
    static List<String> framed(char[][] grid) {
        String border = "+"
                        + "-".repeat(grid[0].length) + "+";
        List<String> output = new ArrayList<>();
        output.add(border);
        for (char[] row : grid)
            output.add("|" + new String(row) + "|");
        output.add(border);
        return output;
    }
    static int index(double fraction, int size) {
        return Math.min((int)Math.floor(fraction * size), size - 1);
    }
    static int rounded(double fraction, int size) {
        return (int)Math.floor(fraction * size + 0.5);
    }
    static Cell biplot(double x, double y, double mx, double my, int width, int height) {
        return new Cell(index((my - y) / (2 * my), height), index((x + mx) / (2 * mx), width));
    }
    static Cell circle(double first, double second, int radius) {
        return new Cell(radius / 2 + 1 - rounded(second, radius / 2), radius + 1 + rounded(first, radius));
    }
    static Cell diagnostic(double t2, double spe, double xmax, double ymax, int width, int height) {
        return new Cell(height - 1 - index(spe / ymax, height), index(t2 / xmax, width));
    }
    static List<Cell> shaft(Cell origin, Cell tip) {
        int dr = tip.row() - origin.row(), dc = tip.col() - origin.col(),
            steps = Math.max(Math.abs(dc), Math.abs(dr));
        List<Cell> result = new ArrayList<>();
        for (int s = 1; s < steps; s++)
            result.add(
                new Cell(origin.row() + Integer.signum(dr) * ((2 * s * Math.abs(dr) + steps) / (2 * steps)),
                         origin.col() + Integer.signum(dc) * ((2 * s * Math.abs(dc) + steps) / (2 * steps))));
        return result;
    }
    static char shaftCharacter(Cell origin, Cell tip) {
        int dr = tip.row() - origin.row(), dc = tip.col() - origin.col();
        return 2 * Math.abs(dr) <= Math.abs(dc) ? '-'
        : 2 * Math.abs(dc) <= Math.abs(dr)      ? '|'
        : dc * dr < 0                           ? '/'
                                                : '\\';
    }
    static String scree(int length, int kaiser, int broken, int width) {
        String line = "|";
        for (int p = 1; p <= width; p++)
            line += p == broken ? 'o' : p == kaiser ? ':' : p <= length ? '#' : ' ';
        return line + "|";
    }
}
