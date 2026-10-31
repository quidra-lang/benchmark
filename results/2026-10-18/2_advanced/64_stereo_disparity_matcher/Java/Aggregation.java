final class Aggregation {
    static final int[][] DIRECTIONS = {{1, 0}, {-1, 0},  {0, 1},  {0, -1},
                                       {1, 1}, {-1, -1}, {-1, 1}, {1, -1}};
    static long[][] path(long[][] base, int[] left, int w, int h, int direction, long p1, long p2,
                         long gamma) {
        int rx = DIRECTIONS[direction][0], ry = DIRECTIONS[direction][1], n = base[0].length;
        long[][] result = new long[base.length][n];
        for (int yi = 0; yi < h; yi++) {
            int y = ry < 0 ? h - 1 - yi : yi;
            for (int xi = 0; xi < w; xi++) {
                int x = rx < 0 ? w - 1 - xi : xi, p = y * w + x, qx = x - rx, qy = y - ry;
                if (qx < 0 || qx >= w || qy < 0 || qy >= h) {
                    result[p] = base[p].clone();
                    continue;
                }
                int q = qy * w + qx;
                long[] previous = result[q];
                long minimum = previous[0];
                for (long value : previous)
                    minimum = Math.min(minimum, value);
                long penalty = Math.max(p1, p2 * gamma / (gamma + Math.abs(left[p] - left[q])));
                for (int d = 0; d < n; d++) {
                    long best = Math.min(previous[d], minimum + penalty);
                    if (d > 0)
                        best = Math.min(best, previous[d - 1] + p1);
                    if (d + 1 < n)
                        best = Math.min(best, previous[d + 1] + p1);
                    result[p][d] = base[p][d] + best - minimum;
                }
            }
        }
        return result;
    }
    static void accumulate(long[][] total, long[][] path) {
        for (int p = 0; p < total.length; p++)
            for (int d = 0; d < total[p].length; d++)
                total[p][d] += path[p][d];
    }
}
