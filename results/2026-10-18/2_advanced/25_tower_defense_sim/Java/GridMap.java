import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

record Cell(int x, int y) { Point center() { return new Point(100 * x, 100 * y); } }
record Point(int x, int y) {}

final class GridMap {
    final int width, height;
    final List<String> rows;
    final List<Cell> spawns;
    final Cell exit;

    GridMap(int width, int height, List<String> rows) {
        this.width = width;
        this.height = height;
        this.rows = rows;
        Map<Integer, Cell> found = new TreeMap<>();
        Cell destination = null;
        for (int y = 0; y < height; y++) for (int x = 0; x < width; x++) {
            char terrain = rows.get(y).charAt(x);
            if (terrain >= '1' && terrain <= '9') found.put(terrain - '0', new Cell(x, y));
            else if (terrain == 'E') destination = new Cell(x, y);
        }
        spawns = new ArrayList<>(found.values());
        exit = destination;
    }

    boolean inside(Cell cell) { return cell.x() >= 0 && cell.x() < width && cell.y() >= 0 && cell.y() < height; }
    char terrain(Cell cell) { return rows.get(cell.y()).charAt(cell.x()); }
    boolean rock(Cell cell) { return terrain(cell) == '#'; }
    boolean water(Cell cell) { return terrain(cell) == '~'; }
    boolean buildable(Cell cell) { return terrain(cell) == '.'; }

    static GridMap read() throws IOException {
        List<String> lines = Files.readAllLines(Path.of("input", "map.txt"), StandardCharsets.US_ASCII);
        String[] dimensions = lines.getFirst().split(" ");
        int width = Integer.parseInt(dimensions[0]), height = Integer.parseInt(dimensions[1]);
        return new GridMap(width, height, lines.subList(1, height + 1));
    }
}
