import java.util.*;

final class Hough {
    record CircleCell(int r, int x, int y, int votes, int total) {}
    record LineCell(int t, int r, int votes) {}
    static final class CircleVotes {
        Map<Integer, List<PgmIo.Point>> outlines = new HashMap<>();
        Map<Integer, int[][]> votes = new HashMap<>();
        List<CircleCell> peaks = new ArrayList<>();
        int candidates;
    }
    static final class LineVotes {
        int low, high, maximum;
        int[][] votes;
        List<LineCell> peaks = new ArrayList<>();
        int count(int t, int r) {
            return t < 0 || t >= 180 || r < low || r > high ? 0 : votes[t][r - low];
        }
    }
    static int rho(PgmIo.Point p, int t, int[][] trig, int step) {
        return Math.floorDiv(p.x() * trig[t][0] + p.y() * trig[t][1], 16384 * step);
    }
    static List<PgmIo.Point> circlePoints(int radius) {
        Set<PgmIo.Point> points = new LinkedHashSet<>();
        int a = radius, b = 0, e = 1 - radius;
        while (a >= b) {
            points.add(new PgmIo.Point(a, b));
            points.add(new PgmIo.Point(b, a));
            points.add(new PgmIo.Point(-b, a));
            points.add(new PgmIo.Point(-a, b));
            points.add(new PgmIo.Point(-a, -b));
            points.add(new PgmIo.Point(-b, -a));
            points.add(new PgmIo.Point(b, -a));
            points.add(new PgmIo.Point(a, -b));
            b++;
            if (e < 0)
                e += 2 * b + 1;
            else {
                a--;
                e += 2 * (b - a) + 1;
            }
        }
        return new ArrayList<>(points);
    }
    static int compare(CircleCell a, CircleCell b) {
        int c = Integer.compare(b.votes() * a.total(), a.votes() * b.total());
        if (c == 0)
            c = Integer.compare(a.r(), b.r());
        if (c == 0)
            c = Integer.compare(a.y(), b.y());
        if (c == 0)
            c = Integer.compare(a.x(), b.x());
        return c;
    }
    static CircleVotes circles(List<PgmIo.Point> edges, int width, int height, PgmIo.Params params) {
        CircleVotes result = new CircleVotes();
        int minimum = params.get("circle_min_radius"), maximum = params.get("circle_max_radius");
        for (int r = minimum; r <= maximum; r++) {
            List<PgmIo.Point> offsets = circlePoints(r);
            result.outlines.put(r, offsets);
            int[][] votes = new int[height][width];
            for (PgmIo.Point p : edges)
                for (PgmIo.Point o : offsets) {
                    int x = p.x() + o.x(), y = p.y() + o.y();
                    if (Canny.inside(x, y, width, height))
                        votes[y][x]++;
                }
            result.votes.put(r, votes);
        }
        for (int r = minimum; r <= maximum; r++)
            for (int y = 0; y < height; y++)
                for (int x = 0; x < width; x++) {
                    int votes = result.votes.get(r)[y][x], total = result.outlines.get(r).size();
                    if (100 * votes < params.get("circle_min_percent") * total)
                        continue;
                    result.candidates++;
                    boolean peak = true;
                    for (int rr = Math.max(minimum, r - 2); rr <= Math.min(maximum, r + 2); rr++)
                        for (int yy = Math.max(0, y - 2); yy <= Math.min(height - 1, y + 2); yy++)
                            for (int xx = Math.max(0, x - 2); xx <= Math.min(width - 1, x + 2); xx++) {
                                if (rr == r && xx == x && yy == y)
                                    continue;
                                int left = votes * result.outlines.get(rr).size(),
                                    right = result.votes.get(rr)[yy][xx] * total;
                                boolean before = rr < r || rr == r && (yy < y || yy == y && xx < x);
                                if (left < right || left == right && before)
                                    peak = false;
                            }
                    if (peak)
                        result.peaks.add(new CircleCell(r, x, y, votes, total));
                }
        result.peaks.sort(Hough::compare);
        return result;
    }
    static LineVotes lines(List<PgmIo.Point> edges, int width, int height, int[][] trig, int step,
                           int threshold) {
        LineVotes result = new LineVotes();
        result.low = Integer.MAX_VALUE;
        result.high = Integer.MIN_VALUE;
        List<PgmIo.Point> corners =
            List.of(new PgmIo.Point(0, 0), new PgmIo.Point(width - 1, 0), new PgmIo.Point(0, height - 1),
                    new PgmIo.Point(width - 1, height - 1));
        for (int t = 0; t < 180; t++)
            for (PgmIo.Point p : corners) {
                int r = rho(p, t, trig, step);
                result.low = Math.min(result.low, r);
                result.high = Math.max(result.high, r);
            }
        result.votes = new int[180][result.high - result.low + 1];
        for (PgmIo.Point p : edges)
            for (int t = 0; t < 180; t++) {
                int r = rho(p, t, trig, step);
                result.maximum = Math.max(result.maximum, ++result.votes[t][r - result.low]);
            }
        for (int t = 0; t < 180; t++)
            for (int r = result.low; r <= result.high; r++) {
                int count = result.count(t, r);
                if (count < threshold)
                    continue;
                boolean peak = true;
                for (int tt = t - 2; tt <= t + 2; tt++)
                    for (int rr = r - 2; rr <= r + 2; rr++) {
                        if (tt == t && rr == r)
                            continue;
                        int other = result.count(tt, rr);
                        if (other > count || other == count && (tt < t || tt == t && rr < r))
                            peak = false;
                    }
                if (peak)
                    result.peaks.add(new LineCell(t, r, count));
            }
        result.peaks.sort(Comparator.comparingInt(LineCell::votes)
                              .reversed()
                              .thenComparingInt(LineCell::t)
                              .thenComparingInt(LineCell::r));
        return result;
    }
}
