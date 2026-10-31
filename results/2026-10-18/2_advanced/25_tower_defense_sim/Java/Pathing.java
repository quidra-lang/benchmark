import java.util.*;

final class Pathing {
    static final int[][] DIRECTIONS = {{0, -1}, {1, 0}, {0, 1}, {-1, 0}};
    static Cell neighbor(Cell cell, int direction) { return new Cell(cell.x() + DIRECTIONS[direction][0], cell.y() + DIRECTIONS[direction][1]); }
}

final class DistanceField {
    final GridMap grid;
    final int[][] distances;

    DistanceField(GridMap grid, Set<Cell> towers) {
        this.grid = grid;
        distances = new int[grid.height][grid.width];
        for (int[] row : distances) Arrays.fill(row, -1);
        distances[grid.exit.y()][grid.exit.x()] = 0;
        Queue<Cell> queue = new ArrayDeque<>();
        queue.add(grid.exit);
        while (!queue.isEmpty()) {
            Cell cell = queue.remove();
            for (int direction = 0; direction < 4; direction++) {
                Cell next = Pathing.neighbor(cell, direction);
                if (grid.inside(next) && !grid.rock(next) && !towers.contains(next) && at(next) < 0) {
                    distances[next.y()][next.x()] = at(cell) + 1;
                    queue.add(next);
                }
            }
        }
    }

    int at(Cell cell) { return distances[cell.y()][cell.x()]; }
    int direction(Cell cell) {
        int best = -1, distance = 0;
        for (int direction = 0; direction < 4; direction++) {
            Cell next = Pathing.neighbor(cell, direction);
            if (!grid.inside(next) || at(next) < 0) continue;
            if (best < 0 || at(next) < distance) { best = direction; distance = at(next); }
        }
        return best;
    }
    Cell next(Cell cell) { return Pathing.neighbor(cell, direction(cell)); }
    List<Cell> path(Cell start) {
        List<Cell> path = new ArrayList<>(List.of(start));
        while (!path.getLast().equals(grid.exit)) path.add(next(path.getLast()));
        return path;
    }
}
