import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
final class GridMap {
    record Cell(int x, int y) {
        public String toString() { return Report.cell(this); }
    }
    record Agent(int id, Cell start, Cell goal) {
        char name() { return (char)('A' + id); }
    }
    static final int[][] DIRECTIONS = {{0, 0}, {0, -1}, {1, 0}, {0, 1}, {-1, 0}};
    int width, height;
    List<String> rows;
    Set<Cell> free = new HashSet<>();
    GridMap() throws Exception {
        List<String> lines =
            Files.readAllLines(Path.of("input/map.txt"), StandardCharsets.US_ASCII);
        String[] f = lines.getFirst().split(" ");
        width = Integer.parseInt(f[0]);
        height = Integer.parseInt(f[1]);
        rows = lines.subList(1, lines.size());
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width; x++)
                if (rows.get(y).charAt(x) == '.')
                    free.add(new Cell(x, y));
    }
    List<Cell> destinations(Cell cell) {
        List<Cell> result = new ArrayList<>();
        for (int[] delta : DIRECTIONS) {
            Cell next = new Cell(cell.x() + delta[0], cell.y() + delta[1]);
            if (free.contains(next))
                result.add(next);
        }
        return result;
    }
    List<Cell> neighbors(Cell cell) {
        List<Cell> result = destinations(cell);
        result.remove(cell);
        return result;
    }
    Map<Cell, Integer> distances(Cell goal) {
        Map<Cell, Integer> distances = new HashMap<>();
        distances.put(goal, 0);
        Deque<Cell> queue = new ArrayDeque<>();
        queue.add(goal);
        while (!queue.isEmpty()) {
            Cell cell = queue.remove();
            for (Cell next : neighbors(cell))
                if (!distances.containsKey(next)) {
                    distances.put(next, distances.get(cell) + 1);
                    queue.add(next);
                }
        }
        return distances;
    }
    static List<Agent> agents() throws Exception {
        List<Agent> agents = new ArrayList<>();
        List<String> lines =
            Files.readAllLines(Path.of("input/agents.csv"), StandardCharsets.US_ASCII);
        for (String line : lines.subList(1, lines.size())) {
            String[] f = line.split(",");
            agents.add(new Agent(Integer.parseInt(f[0]),
                                 new Cell(Integer.parseInt(f[1]), Integer.parseInt(f[2])),
                                 new Cell(Integer.parseInt(f[3]), Integer.parseInt(f[4]))));
        }
        return agents;
    }
}
