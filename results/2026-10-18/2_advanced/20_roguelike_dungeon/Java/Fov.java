import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Deque;
import java.util.List;

final class Fov {
    static final List<String> NAMES = List.of("N", "NE", "E", "SE", "S", "SW", "W", "NW");
    static final int[][] DIRECTIONS = {{0, -1}, {1, -1}, {1, 0}, {1, 1}, {0, 1}, {-1, 1}, {-1, 0}, {-1, -1}};
    static boolean passable(Level level, int x, int y) { return ".#+<>".indexOf(level.terrain[y][x]) >= 0; }
    static boolean canMove(Level level, int x, int y, int dx, int dy) {
        return passable(level, x + dx, y + dy) && (dx == 0 || dy == 0 || level.terrain[y][x] != '+' && level.terrain[y + dy][x + dx] != '+');
    }
    static List<Position> line(int x0, int y0, int x1, int y1) {
        int dx = Math.abs(x1 - x0), dy = Math.abs(y1 - y0), sx = x1 > x0 ? 1 : -1, sy = y1 > y0 ? 1 : -1;
        int error = dx - dy, x = x0, y = y0;
        List<Position> cells = new ArrayList<>();
        while (x != x1 || y != y1) {
            int twice = 2 * error;
            if (twice > -dy) { error -= dy; x += sx; }
            if (twice < dx) { error += dx; y += sy; }
            cells.add(new Position(x, y));
        }
        return cells;
    }
    static boolean[][] fieldOfView(Level level, int px, int py, int radius) {
        boolean[][] visible = new boolean[level.height][level.width];
        for (int y = Math.max(0, py - radius); y < Math.min(level.height, py + radius + 1); y++) for (int x = Math.max(0, px - radius); x < Math.min(level.width, px + radius + 1); x++) {
            if ((x - px) * (x - px) + (y - py) * (y - py) > radius * radius) continue;
            List<Position> cells = line(px, py, x, y); boolean clear = true;
            for (int i = 0; i + 1 < cells.size(); i++) { Position point = cells.get(i); if (!passable(level, point.x(), point.y())) { clear = false; break; } }
            visible[y][x] = clear;
        }
        return visible;
    }
    static int[][] distances(Level level, int px, int py) {
        int[][] distance = new int[level.height][level.width]; for (int[] row : distance) Arrays.fill(row, -1);
        distance[py][px] = 0; Deque<Position> queue = new ArrayDeque<>(); queue.addLast(new Position(px, py));
        while (!queue.isEmpty()) {
            Position point = queue.removeFirst();
            for (int[] direction : DIRECTIONS) {
                int x = point.x() + direction[0], y = point.y() + direction[1];
                if (canMove(level, point.x(), point.y(), direction[0], direction[1]) && distance[y][x] < 0) { distance[y][x] = distance[point.y()][point.x()] + 1; queue.addLast(new Position(x, y)); }
            }
        }
        return distance;
    }
}
