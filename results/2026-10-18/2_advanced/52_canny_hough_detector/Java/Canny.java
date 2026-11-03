import java.util.*;

final class Canny {
    static final class Result {
        int[][] direction, nms;
        boolean[][] edge;
        List<List<PgmIo.Point>> components = new ArrayList<>();
        int strong, weak, weakKept;
    }
    static boolean inside(int x, int y, int width, int height) {
        return x >= 0 && x < width && y >= 0 && y < height;
    }
    static List<PgmIo.Point> neighbors(PgmIo.Point p, int width, int height) {
        List<PgmIo.Point> result = new ArrayList<>();
        for (int dy = -1; dy <= 1; dy++)
            for (int dx = -1; dx <= 1; dx++)
                if ((dx != 0 || dy != 0) && inside(p.x() + dx, p.y() + dy, width, height))
                    result.add(new PgmIo.Point(p.x() + dx, p.y() + dy));
        return result;
    }
    static Result process(Filters.Gradient gradient, int low, int high) {
        int[][] m = gradient.magnitude();
        int height = m.length, width = m[0].length;
        Result result = new Result();
        result.direction = new int[height][width];
        result.nms = new int[height][width];
        result.edge = new boolean[height][width];
        Deque<PgmIo.Point> queue = new ArrayDeque<>();
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width; x++) {
                int gx = gradient.gx()[y][x], gy = gradient.gy()[y][x], ax = Math.abs(gx), ay = Math.abs(gy);
                int direction = 29 * ay <= 12 * ax ? 0 : 29 * ay >= 70 * ax ? 90 : gx * gy < 0 ? 45 : 135;
                result.direction[y][x] = direction;
                if (x == 0 || y == 0 || x == width - 1 || y == height - 1)
                    continue;
                int dx = direction == 90 ? 0 : direction == 45 ? 1 : -1, dy = direction == 0 ? 0 : -1;
                if (m[y][x] > m[y + dy][x + dx] && m[y][x] >= m[y - dy][x - dx])
                    result.nms[y][x] = m[y][x];
                if (result.nms[y][x] >= high) {
                    result.strong++;
                    result.edge[y][x] = true;
                    queue.add(new PgmIo.Point(x, y));
                } else if (result.nms[y][x] >= low)
                    result.weak++;
            }
        while (!queue.isEmpty()) {
            PgmIo.Point point = queue.removeFirst();
            for (PgmIo.Point next : neighbors(point, width, height))
                if (!result.edge[next.y()][next.x()] && result.nms[next.y()][next.x()] >= low) {
                    result.edge[next.y()][next.x()] = true;
                    queue.add(next);
                }
        }
        boolean[][] seen = new boolean[height][width];
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width; x++) {
                if (result.edge[y][x] && result.nms[y][x] < high)
                    result.weakKept++;
                if (!result.edge[y][x] || seen[y][x])
                    continue;
                List<PgmIo.Point> component = new ArrayList<>();
                queue.add(new PgmIo.Point(x, y));
                seen[y][x] = true;
                while (!queue.isEmpty()) {
                    PgmIo.Point point = queue.removeFirst();
                    component.add(point);
                    for (PgmIo.Point next : neighbors(point, width, height))
                        if (result.edge[next.y()][next.x()] && !seen[next.y()][next.x()]) {
                            seen[next.y()][next.x()] = true;
                            queue.add(next);
                        }
                }
                result.components.add(component);
            }
        return result;
    }
}
