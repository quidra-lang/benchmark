import java.util.*;
import java.io.IOException;

public final class Main {
    static int width, height;
    static int[][] image, trig;
    static PgmIo.Params params;
    static Filters.Gradient gradient;
    static Canny.Result canny;
    static Hough.CircleVotes circleVotes;
    static Hough.LineVotes lineVotes;
    static Corners.Result cornerResult;
    static List<PgmIo.Point> edges = new ArrayList<>(), lineEdges = new ArrayList<>();
    static List<Shape> circles = new ArrayList<>(), polygons = new ArrayList<>(), shapes = new ArrayList<>();
    static List<Line> lines = new ArrayList<>();
    static List<Segment> segments = new ArrayList<>();
    static Map<Pair, Junction> junctions = new HashMap<>();
    static List<List<Segment>> neighbors = new ArrayList<>();
    static boolean[][] claimed;
    static List<String> cornerMatches = new ArrayList<>();
    static final class Shape {
        boolean circle;
        int number, pixels, mean, contrast, gap, arcs, sigma;
        Hough.CircleCell cell;
        List<Segment> sides = new ArrayList<>();
        List<PgmIo.Point> vertices = new ArrayList<>();
        int[] angles, lengths, support, corners;
        String kind;
        Shape enclosing;
        boolean[][] explained;
    }
    static final class Line {
        Hough.LineCell cell;
        int number;
        List<Segment> segments = new ArrayList<>();
    }
    static final class Segment {
        int number, t, length;
        PgmIo.Point start, end;
        List<PgmIo.Point> pixels;
    }
    record Pair(int a, int b) {}
    record Junction(int a, int b, PgmIo.Point point, int endA, int endB) {}
    static int distance(PgmIo.Point a, PgmIo.Point b) {
        return Math.max(Math.abs(a.x() - b.x()), Math.abs(a.y() - b.y()));
    }
    static PgmIo.Point difference(PgmIo.Point a, PgmIo.Point b) {
        return new PgmIo.Point(a.x() - b.x(), a.y() - b.y());
    }
    static int cross(PgmIo.Point a, PgmIo.Point b) {
        return a.x() * b.y() - a.y() * b.x();
    }
    static int dot(PgmIo.Point a, PgmIo.Point b) {
        return a.x() * b.x() + a.y() * b.y();
    }
    static int angle(int a, int b) {
        int d = Math.abs(a - b);
        return Math.min(d, 180 - d);
    }
    static int round(int n, int d) {
        if (d < 0) {
            n = -n;
            d = -d;
        }
        return Math.floorDiv(2 * n + d, 2 * d);
    }
    static List<PgmIo.Point> bresenham(PgmIo.Point a, PgmIo.Point b) {
        int x = a.x(), y = a.y(), dx = Math.abs(b.x() - x), dy = -Math.abs(b.y() - y),
            sx = x < b.x() ? 1 : -1, sy = y < b.y() ? 1 : -1, e = dx + dy;
        List<PgmIo.Point> result = new ArrayList<>();
        while (true) {
            result.add(new PgmIo.Point(x, y));
            if (x == b.x() && y == b.y())
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
        return result;
    }
    static boolean edge(PgmIo.Point point) {
        return Canny.inside(point.x(), point.y(), width, height) && canny.edge[point.y()][point.x()];
    }
    static boolean nearEdge(PgmIo.Point point) {
        for (int dy = -1; dy <= 1; dy++)
            for (int dx = -1; dx <= 1; dx++)
                if (edge(new PgmIo.Point(point.x() + dx, point.y() + dy)))
                    return true;
        return false;
    }
    static int half(PgmIo.Point point) {
        return point.y() > 0 || point.y() == 0 && point.x() > 0 ? 0 : 1;
    }
    static PgmIo.Point translate(PgmIo.Point p, int x, int y) {
        return new PgmIo.Point(p.x() + x, p.y() + y);
    }
    static boolean circumference(Shape circle, PgmIo.Point point) {
        int dx = point.x() - circle.cell.x(), dy = point.y() - circle.cell.y(), r = circle.cell.r(),
            square = dx * dx + dy * dy;
        return (r - 1) * (r - 1) <= square && square <= (r + 1) * (r + 1);
    }
    static void determineCircles() {
        for (int i = 0; i < Math.min(params.get("circle_max_count"), circleVotes.peaks.size()); i++) {
            Shape shape = new Shape();
            shape.circle = true;
            shape.number = i + 1;
            shape.cell = circleVotes.peaks.get(i);
            List<PgmIo.Point> outline = new ArrayList<>(circleVotes.outlines.get(shape.cell.r()));
            outline.sort((a, b) -> {
                int c = Integer.compare(half(a), half(b));
                return c != 0 ? c : -Integer.signum(cross(a, b));
            });
            boolean[] hit = new boolean[outline.size()];
            int hits = 0;
            for (int j = 0; j < hit.length; j++) {
                hit[j] = edge(translate(outline.get(j), shape.cell.x(), shape.cell.y()));
                if (hit[j])
                    hits++;
            }
            if (hits == 0)
                shape.gap = hit.length;
            else if (hits == hit.length)
                shape.arcs = 1;
            else {
                int run = 0;
                for (int j = 0; j < 2 * hit.length; j++) {
                    if (hit[j % hit.length])
                        run = 0;
                    else {
                        run++;
                        shape.gap = Math.max(shape.gap, run);
                    }
                }
                for (int j = 0; j < hit.length; j++)
                    if (hit[j] && !hit[(j + hit.length - 1) % hit.length])
                        shape.arcs++;
            }
            circles.add(shape);
        }
        for (PgmIo.Point point : edges) {
            boolean circular = false;
            for (Shape shape : circles)
                if (circumference(shape, point))
                    circular = true;
            if (!circular)
                lineEdges.add(point);
        }
    }
    static int projection(PgmIo.Point p, int t) {
        return p.y() * trig[t][0] - p.x() * trig[t][1];
    }
    static void extract() {
        claimed = new boolean[height][width];
        for (Hough.LineCell cell : lineVotes.peaks) {
            if (lines.size() == params.get("hough_max_lines"))
                break;
            int t = cell.t();
            List<PgmIo.Point> selected = new ArrayList<>();
            for (PgmIo.Point point : lineEdges)
                if (!claimed[point.y()][point.x()] &&
                    Math.abs(Hough.rho(point, t, trig, params.get("hough_rho_step")) - cell.r()) <=
                        params.get("segment_tolerance"))
                    selected.add(point);
            selected.sort((a, b) -> {
                int c = Integer.compare(projection(a, t), projection(b, t));
                if (c == 0)
                    c = Integer.compare(a.x(), b.x());
                if (c == 0)
                    c = Integer.compare(a.y(), b.y());
                return c;
            });
            Line line = new Line();
            line.cell = cell;
            line.number = lines.size() + 1;
            int start = 0;
            while (start < selected.size()) {
                int end = start + 1;
                while (end < selected.size() &&
                       projection(selected.get(end), t) - projection(selected.get(end - 1), t) <=
                           params.get("segment_max_gap") * 16384)
                    end++;
                PgmIo.Point a = selected.get(start), b = selected.get(end - 1);
                int length = distance(a, b) + 1;
                if (length >= params.get("segment_min_length")) {
                    Segment segment = new Segment();
                    segment.number = segments.size() + 1;
                    segment.t = t;
                    segment.start = a;
                    segment.end = b;
                    segment.length = length;
                    segment.pixels = new ArrayList<>(selected.subList(start, end));
                    line.segments.add(segment);
                    segments.add(segment);
                    for (PgmIo.Point point : segment.pixels)
                        claimed[point.y()][point.x()] = true;
                }
                start = end;
            }
            if (!line.segments.isEmpty())
                lines.add(line);
        }
    }
    static Junction junction(Segment a, Segment b) {
        return junctions.get(new Pair(Math.min(a.number, b.number), Math.max(a.number, b.number)));
    }
    static int end(Junction j, Segment s) {
        return j.a() == s.number ? j.endA() : j.endB();
    }
    static void join() {
        for (Segment segment : segments)
            neighbors.add(new ArrayList<>());
        for (int a = 0; a < segments.size(); a++)
            for (int b = a + 1; b < segments.size(); b++) {
                Segment sa = segments.get(a), sb = segments.get(b);
                if (angle(sa.t, sb.t) < params.get("junction_min_angle"))
                    continue;
                PgmIo.Point da = difference(sa.end, sa.start), db = difference(sb.end, sb.start);
                int den = cross(da, db);
                if (den == 0)
                    continue;
                int lambda = cross(difference(sb.start, sa.start), db);
                PgmIo.Point point = new PgmIo.Point(round(sa.start.x() * den + lambda * da.x(), den),
                                                    round(sa.start.y() * den + lambda * da.y(), den));
                int ea = distance(sa.start, point) <= distance(sa.end, point) ? 0 : 1,
                    eb = distance(sb.start, point) <= distance(sb.end, point) ? 0 : 1;
                if (distance(ea == 0 ? sa.start : sa.end, point) > params.get("junction_distance") ||
                    distance(eb == 0 ? sb.start : sb.end, point) > params.get("junction_distance"))
                    continue;
                junctions.put(new Pair(sa.number, sb.number),
                              new Junction(sa.number, sb.number, point, ea, eb));
                neighbors.get(a).add(sb);
                neighbors.get(b).add(sa);
            }
        for (List<Segment> adjacent : neighbors)
            adjacent.sort(Comparator.comparingInt(s -> s.number));
    }
    static void enumerate(List<Segment> path, int count) {
        Segment first = path.getFirst(), last = path.getLast();
        if (path.size() == count) {
            if (path.get(1).number >= last.number || junction(first, last) == null)
                return;
            List<PgmIo.Point> vertices = new ArrayList<>();
            for (int i = 0; i < count; i++) {
                Segment current = path.get(i), previous = path.get((i + count - 1) % count),
                        next = path.get((i + 1) % count);
                Junction incoming = junction(previous, current), outgoing = junction(current, next);
                if (end(incoming, current) == end(outgoing, current))
                    return;
                vertices.add(incoming.point());
            }
            int sign = 0;
            for (int i = 0; i < count; i++) {
                int z = cross(difference(vertices.get((i + 1) % count), vertices.get(i)),
                              difference(vertices.get((i + 2) % count), vertices.get((i + 1) % count)));
                if (z == 0 || sign != 0 && Integer.signum(z) != sign)
                    return;
                sign = Integer.signum(z);
            }
            Shape polygon = new Shape();
            polygon.number = polygons.size() + 1;
            polygon.sides = new ArrayList<>(path);
            polygon.vertices = vertices;
            polygons.add(polygon);
            return;
        }
        for (Segment next : neighbors.get(last.number - 1))
            if (next.number > first.number && !path.contains(next)) {
                if (path.size() > 1 &&
                    end(junction(path.get(path.size() - 2), last), last) == end(junction(last, next), last))
                    continue;
                path.add(next);
                enumerate(path, count);
                path.removeLast();
            }
    }
    static void attributes(Shape polygon) {
        int k = polygon.sides.size(), tolerance = params.get("angle_tolerance");
        polygon.angles = new int[k];
        polygon.lengths = new int[k];
        polygon.support = new int[k];
        polygon.corners = new int[k];
        boolean sixty = true, right = false, allRight = true;
        int minimum = Integer.MAX_VALUE, maximum = 0;
        for (int i = 0; i < k; i++) {
            PgmIo.Point v = polygon.vertices.get(i), previous = polygon.vertices.get((i + k - 1) % k),
                        next = polygon.vertices.get((i + 1) % k);
            int phi = angle(polygon.sides.get((i + k - 1) % k).t, polygon.sides.get(i).t);
            int alpha = dot(difference(previous, v), difference(next, v)) < 0 ? 180 - phi : phi;
            polygon.angles[i] = alpha;
            sixty &= Math.abs(alpha - 60) <= tolerance;
            right |= Math.abs(alpha - 90) <= tolerance;
            allRight &= Math.abs(alpha - 90) <= tolerance;
            PgmIo.Point side = difference(next, v);
            int length = dot(side, side);
            polygon.lengths[i] = length;
            minimum = Math.min(minimum, length);
            maximum = Math.max(maximum, length);
            polygon.sigma += cross(v, next);
            List<PgmIo.Point> points = bresenham(v, next);
            int hits = 0;
            for (PgmIo.Point point : points)
                if (nearEdge(point))
                    hits++;
            polygon.support[i] = 100 * hits / points.size();
        }
        if (k == 3)
            polygon.kind = sixty ? "equilateral_triangle" : right ? "right_triangle" : "triangle";
        else {
            boolean a = angle(polygon.sides.get(0).t, polygon.sides.get(2).t) <= tolerance,
                    b = angle(polygon.sides.get(1).t, polygon.sides.get(3).t) <= tolerance;
            polygon.kind = !a && !b    ? "quadrilateral"
                           : a != b    ? "trapezoid"
                           : !allRight ? "parallelogram"
                           : 100 * (maximum - minimum) <= params.get("square_tolerance") * maximum
                               ? "square"
                               : "rectangle";
        }
    }
    static List<PgmIo.Point> representatives(Shape shape) {
        if (!shape.circle)
            return shape.vertices;
        int x = shape.cell.x(), y = shape.cell.y(), r = shape.cell.r();
        return List.of(new PgmIo.Point(x + r, y), new PgmIo.Point(x, y + r), new PgmIo.Point(x - r, y),
                       new PgmIo.Point(x, y - r));
    }
    static boolean contains(Shape shape, PgmIo.Point point) {
        if (shape.circle) {
            int dx = point.x() - shape.cell.x(), dy = point.y() - shape.cell.y();
            return dx * dx + dy * dy <= shape.cell.r() * shape.cell.r();
        }
        for (int i = 0; i < shape.vertices.size(); i++) {
            PgmIo.Point a = shape.vertices.get(i), b = shape.vertices.get((i + 1) % shape.vertices.size());
            int z = cross(difference(b, a), difference(point, a));
            if (z != 0 && Integer.signum(z) != Integer.signum(shape.sigma))
                return false;
        }
        return true;
    }
    static void measure() {
        shapes.addAll(polygons);
        shapes.addAll(circles);
        for (Shape shape : shapes) {
            int x0 = Integer.MAX_VALUE, x1 = Integer.MIN_VALUE, y0 = Integer.MAX_VALUE,
                y1 = Integer.MIN_VALUE;
            for (PgmIo.Point point : representatives(shape)) {
                x0 = Math.min(x0, point.x());
                x1 = Math.max(x1, point.x());
                y0 = Math.min(y0, point.y());
                y1 = Math.max(y1, point.y());
            }
            int margin = params.get("contrast_margin");
            x0 = Math.max(0, x0 - margin);
            x1 = Math.min(width - 1, x1 + margin);
            y0 = Math.max(0, y0 - margin);
            y1 = Math.min(height - 1, y1 + margin);
            int inner = 0, outer = 0, outerCount = 0;
            for (int y = y0; y <= y1; y++)
                for (int x = x0; x <= x1; x++)
                    if (contains(shape, new PgmIo.Point(x, y))) {
                        shape.pixels++;
                        inner += image[y][x];
                    } else {
                        outerCount++;
                        outer += image[y][x];
                    }
            shape.mean = shape.pixels == 0 ? 0 : inner / shape.pixels;
            shape.contrast = shape.mean - (outerCount == 0 ? 0 : outer / outerCount);
            shape.explained = new boolean[height][width];
            if (shape.circle) {
                for (PgmIo.Point point : edges)
                    if (circumference(shape, point))
                        shape.explained[point.y()][point.x()] = true;
            } else
                for (int i = 0; i < shape.vertices.size(); i++)
                    for (PgmIo.Point point : bresenham(shape.vertices.get(i),
                                                       shape.vertices.get((i + 1) % shape.vertices.size())))
                        for (int dy = -1; dy <= 1; dy++)
                            for (int dx = -1; dx <= 1; dx++) {
                                int x = point.x() + dx, y = point.y() + dy;
                                if (Canny.inside(x, y, width, height))
                                    shape.explained[y][x] = true;
                            }
        }
        for (Shape shape : shapes)
            for (Shape enclosing : shapes) {
                if (enclosing == shape || enclosing.pixels <= shape.pixels ||
                    shape.enclosing != null && enclosing.pixels >= shape.enclosing.pixels)
                    continue;
                boolean valid = true;
                for (PgmIo.Point point : representatives(shape))
                    if (!contains(enclosing, point))
                        valid = false;
                if (valid)
                    shape.enclosing = enclosing;
            }
    }
    static String label(Shape shape) {
        return shape == null ? "none" : (shape.circle ? "circle " : "polygon ") + shape.number;
    }
    static void matchCorners() {
        int limit = params.get("corner_match_distance");
        for (Corners.Corner corner : cornerResult.corners()) {
            PgmIo.Point point = new PgmIo.Point(corner.x(), corner.y());
            int best = limit + 1;
            String match = "none";
            for (Shape polygon : polygons)
                for (int i = 0; i < polygon.vertices.size(); i++) {
                    int distance = distance(point, polygon.vertices.get(i));
                    if (distance < best) {
                        best = distance;
                        match = "polygon " + polygon.number + " vertex " + (i + 1);
                    }
                }
            if (match.equals("none"))
                for (Segment segment : segments)
                    for (int i = 0; i < 2; i++) {
                        int distance = distance(point, i == 0 ? segment.start : segment.end);
                        if (distance < best) {
                            best = distance;
                            match = "segment " + segment.number + (i == 0 ? " start" : " end");
                        }
                    }
            cornerMatches.add(match);
        }
        for (Shape polygon : polygons)
            for (int i = 0; i < polygon.vertices.size(); i++) {
                int best = limit + 1;
                for (int c = 0; c < cornerResult.corners().size(); c++) {
                    Corners.Corner corner = cornerResult.corners().get(c);
                    int distance = distance(polygon.vertices.get(i), new PgmIo.Point(corner.x(), corner.y()));
                    if (distance < best) {
                        best = distance;
                        polygon.corners[i] = c + 1;
                    }
                }
            }
    }

    static List<String> lineReport() {
        List<String> out = new ArrayList<>(List.of("lines " + lines.size()));
        for (Line line : lines) {
            out.add("line " + line.number + " theta " + line.cell.t() + " rho " + line.cell.r() + " votes " +
                    line.cell.votes() + " segments " + line.segments.size());
            for (Segment segment : line.segments)
                out.add("segment " + segment.number + " start " + segment.start.x() + " " +
                        segment.start.y() + " end " + segment.end.x() + " " + segment.end.y() + " length " +
                        segment.length + " pixels " + segment.pixels.size());
        }
        return out;
    }
    static List<String> circleReport() {
        List<String> out = new ArrayList<>(List.of("circles " + circles.size()));
        for (Shape circle : circles)
            out.add("circle " + circle.number + " center " + circle.cell.x() + " " + circle.cell.y() +
                    " radius " + circle.cell.r() + " votes " + circle.cell.votes() + " points " +
                    circle.cell.total() + " gap " + circle.gap + " arcs " + circle.arcs + " pixels " +
                    circle.pixels + " mean " + circle.mean + " contrast " + circle.contrast + " inside " +
                    label(circle.enclosing));
        return out;
    }
    static List<String> polygonReport() {
        List<String> out = new ArrayList<>(List.of("polygons " + polygons.size()));
        for (Shape polygon : polygons) {
            String line = "polygon " + polygon.number + " " + polygon.kind + " segments";
            for (Segment segment : polygon.sides)
                line += " " + segment.number;
            int area = Math.abs(polygon.sigma);
            line += " area " + area / 2 + "." + (area % 2 == 0 ? 0 : 5) + " pixels " + polygon.pixels +
                    " mean " + polygon.mean + " contrast " + polygon.contrast + " inside " +
                    label(polygon.enclosing);
            out.add(line);
            for (int i = 0; i < polygon.vertices.size(); i++) {
                PgmIo.Point point = polygon.vertices.get(i);
                out.add("vertex " + (i + 1) + " " + point.x() + " " + point.y() + " angle " +
                        polygon.angles[i] + " corner " +
                        (polygon.corners[i] == 0 ? "none" : Integer.toString(polygon.corners[i])));
            }
            for (int i = 0; i < polygon.sides.size(); i++)
                out.add("side " + (i + 1) + " segment " + polygon.sides.get(i).number + " length2 " +
                        polygon.lengths[i] + " support " + polygon.support[i]);
        }
        return out;
    }
    static List<String> cornerReport() {
        List<String> out = new ArrayList<>(List.of("corners " + cornerResult.corners().size()));
        for (int i = 0; i < cornerResult.corners().size(); i++) {
            Corners.Corner c = cornerResult.corners().get(i);
            out.add("corner " + (i + 1) + " " + c.x() + " " + c.y() + " response " + c.response() +
                    " match " + cornerMatches.get(i));
        }
        return out;
    }
    static List<String> componentReport() {
        List<String> out = new ArrayList<>(List.of("components " + canny.components.size()));
        for (int i = 0; i < canny.components.size(); i++) {
            List<PgmIo.Point> component = canny.components.get(i);
            int x0 = width, x1 = 0, y0 = height, y1 = 0, ends = 0, strength = 0;
            int[] directions = new int[4];
            for (PgmIo.Point point : component) {
                x0 = Math.min(x0, point.x());
                x1 = Math.max(x1, point.x());
                y0 = Math.min(y0, point.y());
                y1 = Math.max(y1, point.y());
                int adjacent = 0;
                for (PgmIo.Point neighbor : Canny.neighbors(point, width, height))
                    if (edge(neighbor))
                        adjacent++;
                if (adjacent == 1)
                    ends++;
                strength += gradient.magnitude()[point.y()][point.x()];
                directions[canny.direction[point.y()][point.x()] / 45]++;
            }
            int main = 0;
            for (int d = 1; d < 4; d++)
                if (directions[d] > directions[main])
                    main = d;
            Shape best = null;
            int maximum = 0;
            for (Shape shape : shapes) {
                int count = 0;
                for (PgmIo.Point point : component)
                    if (shape.explained[point.y()][point.x()])
                        count++;
                if (count > maximum) {
                    best = shape;
                    maximum = count;
                }
            }
            out.add("component " + (i + 1) + " pixels " + component.size() + " box " + x0 + " " + y0 + " " +
                    x1 + " " + y1 + " ends " + ends + " strength " + strength / component.size() +
                    " direction " + (main * 45) + " shape " + label(best) + " explained " + maximum);
        }
        return out;
    }
    static List<String> report() {
        List<String> out = new ArrayList<>();
        out.add("image " + width + " " + height);
        int nonzero = 0, maximum = 0, kept = 0, claimedCount = 0;
        int[] directions = new int[4];
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width; x++) {
                int m = gradient.magnitude()[y][x];
                if (m > 0)
                    nonzero++;
                maximum = Math.max(maximum, m);
                if (canny.nms[y][x] > 0)
                    kept++;
                if (claimed[y][x])
                    claimedCount++;
                if (canny.edge[y][x])
                    directions[canny.direction[y][x] / 45]++;
            }
        out.add("gradient_nonzero " + nonzero);
        out.add("gradient_max " + maximum);
        out.add("nms_kept " + kept);
        out.add("strong " + canny.strong);
        out.add("weak " + canny.weak);
        out.add("edges " + edges.size());
        out.add("weak_kept " + canny.weakKept);
        out.add("weak_dropped " + (canny.weak - canny.weakKept));
        out.add("edge_components " + canny.components.size());
        for (int i = 0; i < 4; i++)
            out.add("direction_" + (i * 45) + " " + directions[i]);
        out.add("circle_candidates " + circleVotes.candidates);
        out.add("circle_peaks " + circleVotes.peaks.size());
        out.add("circles " + circles.size());
        out.add("circle_edge_pixels " + (edges.size() - lineEdges.size()));
        out.add("line_edge_pixels " + lineEdges.size());
        out.add("hough_max_votes " + lineVotes.maximum);
        out.add("hough_peaks " + lineVotes.peaks.size());
        out.add("lines " + lines.size());
        out.add("segments " + segments.size());
        out.add("claimed_pixels " + claimedCount);
        out.add("junctions " + junctions.size());
        out.add("polygons " + polygons.size());
        for (String kind : List.of("equilateral_triangle", "right_triangle", "triangle", "square",
                                   "rectangle", "parallelogram", "trapezoid", "quadrilateral")) {
            int count = 0;
            for (Shape polygon : polygons)
                if (polygon.kind.equals(kind))
                    count++;
            out.add(kind + " " + count);
        }
        int vertices = 0, onVertices = 0, onSegments = 0;
        for (Shape polygon : polygons)
            for (int corner : polygon.corners)
                if (corner != 0)
                    vertices++;
        for (String match : cornerMatches) {
            if (match.startsWith("polygon"))
                onVertices++;
            if (match.startsWith("segment"))
                onSegments++;
        }
        out.add("corner_candidates " + cornerResult.candidates());
        out.add("corners " + cornerResult.corners().size());
        out.add("corners_on_vertices " + onVertices);
        out.add("corners_on_segments " + onSegments);
        out.add("corners_unmatched " + (cornerMatches.size() - onVertices - onSegments));
        out.add("vertices_with_corner " + vertices);
        return out;
    }
    static void mark(int[][] overlay, PgmIo.Point point) {
        if (Canny.inside(point.x(), point.y(), width, height))
            overlay[point.y()][point.x()] = 255;
    }
    static void images() throws IOException {
        int[][] edgeImage = new int[height][width], overlay = new int[height][width];
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width; x++) {
                edgeImage[y][x] = canny.edge[y][x] ? 255 : 0;
                overlay[y][x] = image[y][x] / params.get("overlay_divisor");
            }
        for (Segment segment : segments)
            for (PgmIo.Point point : bresenham(segment.start, segment.end))
                mark(overlay, point);
        for (Shape circle : circles)
            for (PgmIo.Point point : circleVotes.outlines.get(circle.cell.r()))
                mark(overlay, translate(point, circle.cell.x(), circle.cell.y()));
        for (Corners.Corner c : cornerResult.corners())
            for (int e = -2; e <= 2; e++) {
                mark(overlay, new PgmIo.Point(c.x() + e, c.y()));
                mark(overlay, new PgmIo.Point(c.x(), c.y() + e));
            }
        int[][] votes = new int[lineVotes.high - lineVotes.low + 1][180];
        for (int r = lineVotes.low; r <= lineVotes.high; r++)
            for (int t = 0; t < 180; t++)
                votes[r - lineVotes.low][t] =
                    lineVotes.maximum == 0 ? 0 : 255 * lineVotes.count(t, r) / lineVotes.maximum;
        PgmIo.pgm("edges.pgm", edgeImage);
        PgmIo.pgm("hough.pgm", votes);
        PgmIo.pgm("overlay.pgm", overlay);
    }
    public static void main(String[] args) throws IOException {
        PgmIo.Data data = PgmIo.read();
        image = data.image();
        trig = data.trig();
        params = data.params();
        height = image.length;
        width = image[0].length;
        gradient = Filters.gradient(Filters.smooth(image, params));
        canny = Canny.process(gradient, params.get("canny_low"), params.get("canny_high"));
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width; x++)
                if (canny.edge[y][x])
                    edges.add(new PgmIo.Point(x, y));
        circleVotes = Hough.circles(edges, width, height, params);
        determineCircles();
        lineVotes = Hough.lines(lineEdges, width, height, trig, params.get("hough_rho_step"),
                                params.get("hough_threshold"));
        extract();
        join();
        for (int k = 3; k <= 4; k++)
            for (Segment first : segments)
                enumerate(new ArrayList<>(List.of(first)), k);
        for (Shape polygon : polygons)
            attributes(polygon);
        measure();
        cornerResult = Corners.detect(gradient, params.get("harris_window"), params.value("harris_threshold"),
                                      params.get("harris_max_count"));
        matchCorners();
        images();
        PgmIo.write("lines.txt", lineReport());
        PgmIo.write("circles.txt", circleReport());
        PgmIo.write("polygons.txt", polygonReport());
        PgmIo.write("corners.txt", cornerReport());
        PgmIo.write("components.txt", componentReport());
        PgmIo.write("report.txt", report());
    }
}
