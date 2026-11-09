import java.util.*;

final class Corners {
    record Corner(int x, int y, long response) {}
    record Result(int candidates, List<Corner> corners) {}
    static Result detect(Filters.Gradient gradient, int window, long threshold, int maximum) {
        int height = gradient.gx().length, width = gradient.gx()[0].length, half = window / 2;
        long[][] response = new long[height][width];
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width; x++) {
                long xx = 0, yy = 0, xy = 0;
                for (int j = -half; j <= half; j++)
                    for (int i = -half; i <= half; i++) {
                        long gx = Filters.clamped(gradient.gx(), x + i, y + j),
                             gy = Filters.clamped(gradient.gy(), x + i, y + j);
                        xx += gx * gx;
                        yy += gy * gy;
                        xy += gx * gy;
                    }
                response[y][x] = xx * yy - xy * xy - (xx + yy) * (xx + yy) / 25;
            }
        List<Corner> candidates = new ArrayList<>();
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width; x++) {
                long value = response[y][x];
                if (value < threshold)
                    continue;
                boolean peak = true;
                for (PgmIo.Point p : Canny.neighbors(new PgmIo.Point(x, y), width, height)) {
                    long other = response[p.y()][p.x()];
                    if (other > value || other == value && (p.y() < y || p.y() == y && p.x() < x))
                        peak = false;
                }
                if (peak)
                    candidates.add(new Corner(x, y, value));
            }
        candidates.sort(Comparator.comparingLong(Corner::response)
                            .reversed()
                            .thenComparingInt(Corner::y)
                            .thenComparingInt(Corner::x));
        return new Result(candidates.size(),
                          new ArrayList<>(candidates.subList(0, Math.min(maximum, candidates.size()))));
    }
}
