using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Program {
    public static int width, height;
    public static int[][] image, trig;
    public static PgmIo.Params settings;
    public static Filters.Gradient gradient;
    public static Canny.Result canny;
    public static Hough.CircleVotes circleVotes;
    public static Hough.LineVotes lineVotes;
    public static Corners.Result cornerResult;
    public static List<PgmIo.Point> edges = new(), lineEdges = new();
    public static List<Shape> circles = new(), polygons = new(), shapes = new();
    public static List<Line> lines = new();
    public static List<Segment> segments = new();
    public static Dictionary<Pair, Junction> junctions = new();
    public static List<List<Segment>> neighbors = new();
    public static bool[][] claimed;
    public static List<string> cornerMatches = new();
    public sealed class Shape {
        public bool circle;
        public int number, pixels, mean, contrast, gap, arcs, sigma;
        public Hough.CircleCell cell;
        public List<Segment> sides = new();
        public List<PgmIo.Point> vertices = new();
        public int[] angles, lengths, support, corners;
        public string kind;
        public Shape enclosing;
        public bool[][] explained;
    }
    public sealed class Line {
        public Hough.LineCell cell;
        public int number;
        public List<Segment> segments = new();
    }
    public sealed class Segment {
        public int number, t, length;
        public PgmIo.Point start, end;
        public List<PgmIo.Point> pixels;
    }
    public record Pair(int a, int b) {
    }
    public record Junction(int a, int b, PgmIo.Point point, int endA, int endB) {
    }
    public static int Distance(PgmIo.Point a, PgmIo.Point b) {
        return Math.Max(Math.Abs(a.x - b.x), Math.Abs(a.y - b.y));
    }
    public static PgmIo.Point Difference(PgmIo.Point a, PgmIo.Point b) {
        return new PgmIo.Point(a.x - b.x, a.y - b.y);
    }
    public static int Cross(PgmIo.Point a, PgmIo.Point b) {
        return a.x * b.y - a.y * b.x;
    }
    public static int Dot(PgmIo.Point a, PgmIo.Point b) {
        return a.x * b.x + a.y * b.y;
    }
    public static int Angle(int a, int b) {
        int d = Math.Abs(a - b);
        return Math.Min(d, 180 - d);
    }
    public static int Round(int n, int d) {
        if (d < 0) {
            n = -n;
            d = -d;
        }
        return Hough.FloorDivision(2 * n + d, 2 * d);
    }
    public static List<PgmIo.Point> Bresenham(PgmIo.Point a, PgmIo.Point b) {
        int x = a.x, y = a.y, dx = Math.Abs(b.x - x), dy = -Math.Abs(b.y - y), sx = x < b.x ? 1 : -1,
            sy = y < b.y ? 1 : -1, e = dx + dy;
        List<PgmIo.Point> result = new();
        while (true) {
            result.Add(new PgmIo.Point(x, y));
            if (x == b.x && y == b.y)
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
    public static bool Edge(PgmIo.Point point) {
        return Canny.Inside(point.x, point.y, width, height) && canny.edge[point.y][point.x];
    }
    public static bool NearEdge(PgmIo.Point point) {
        for (int dy = -1; dy <= 1; dy++)
            for (int dx = -1; dx <= 1; dx++)
                if (Edge(new PgmIo.Point(point.x + dx, point.y + dy)))
                    return true;
        return false;
    }
    public static int Half(PgmIo.Point point) {
        return point.y > 0 || point.y == 0 && point.x > 0 ? 0 : 1;
    }
    public static PgmIo.Point Translate(PgmIo.Point p, int x, int y) {
        return new PgmIo.Point(p.x + x, p.y + y);
    }
    public static bool Circumference(Shape circle, PgmIo.Point point) {
        int dx = point.x - circle.cell.x, dy = point.y - circle.cell.y, r = circle.cell.r,
            square = dx * dx + dy * dy;
        return (r - 1) * (r - 1) <= square && square <= (r + 1) * (r + 1);
    }
    public static void DetermineCircles() {
        for (int i = 0; i < Math.Min(settings.Get("circle_max_count"), circleVotes.peaks.Count); i++) {
            Shape shape = new Shape();
            shape.circle = true;
            shape.number = i + 1;
            shape.cell = circleVotes.peaks[i];
            List<PgmIo.Point> outline = new(circleVotes.outlines[shape.cell.r]);
            outline.Sort((a, b) => {
                int c = Half(a).CompareTo(Half(b));
                return c != 0 ? c : -Math.Sign(Cross(a, b));
            });
            bool[] hit = new bool[outline.Count];
            int hits = 0;
            for (int j = 0; j < hit.Length; j++) {
                hit[j] = Edge(Translate(outline[j], shape.cell.x, shape.cell.y));
                if (hit[j])
                    hits++;
            }
            if (hits == 0)
                shape.gap = hit.Length;
            else if (hits == hit.Length)
                shape.arcs = 1;
            else {
                int run = 0;
                for (int j = 0; j < 2 * hit.Length; j++) {
                    if (hit[j % hit.Length])
                        run = 0;
                    else {
                        run++;
                        shape.gap = Math.Max(shape.gap, run);
                    }
                }
                for (int j = 0; j < hit.Length; j++)
                    if (hit[j] && !hit[(j + hit.Length - 1) % hit.Length])
                        shape.arcs++;
            }
            circles.Add(shape);
        }
        foreach (PgmIo.Point point in edges) {
            bool circular = false;
            foreach (Shape shape in circles)
                if (Circumference(shape, point))
                    circular = true;
            if (!circular)
                lineEdges.Add(point);
        }
    }
    public static int Projection(PgmIo.Point p, int t) {
        return p.y * trig[t][0] - p.x * trig[t][1];
    }
    public static void Extract() {
        claimed = Enumerable.Range(0, height)
                      .Select(
                          _ => new bool[width])
                      .ToArray();
        foreach (Hough.LineCell cell in lineVotes.peaks) {
            if (lines.Count == settings.Get("hough_max_lines"))
                break;
            int t = cell.t;
            List<PgmIo.Point> selected = new();
            foreach (PgmIo.Point point in lineEdges)
                if (!claimed[point.y][point.x] &&
                    Math.Abs(Hough.Rho(point, t, trig, settings.Get("hough_rho_step")) - cell.r) <=
                        settings.Get("segment_tolerance"))
                    selected.Add(point);
            selected.Sort((a, b) => {
                int c = Projection(a, t).CompareTo(Projection(b, t));
                if (c == 0)
                    c = a.x.CompareTo(b.x);
                if (c == 0)
                    c = a.y.CompareTo(b.y);
                return c;
            });
            Line line = new Line();
            line.cell = cell;
            line.number = lines.Count + 1;
            int start = 0;
            while (start < selected.Count) {
                int end = start + 1;
                while (end < selected.Count &&
                       Projection(selected[end], t) - Projection(selected[end - 1], t) <=
                           settings.Get("segment_max_gap") * 16384)
                    end++;
                PgmIo.Point a = selected[start], b = selected[end - 1];
                int length = Distance(a, b) + 1;
                if (length >= settings.Get("segment_min_length")) {
                    Segment segment = new Segment();
                    segment.number = segments.Count + 1;
                    segment.t = t;
                    segment.start = a;
                    segment.end = b;
                    segment.Length = length;
                    segment.pixels = new(selected.GetRange(start, end - (start)));
                    line.segments.Add(segment);
                    segments.Add(segment);
                    foreach (PgmIo.Point point in segment.pixels)
                        claimed[point.y][point.x] = true;
                }
                start = end;
            }
            if (line.segments.Count != 0)
                lines.Add(line);
        }
    }
    public static Junction FindJunction(Segment a, Segment b) {
        return junctions.GetValueOrDefault(
            new Pair(Math.Min(a.number, b.number), Math.Max(a.number, b.number)));
    }
    public static int End(Junction j, Segment s) {
        return j.a == s.number ? j.endA : j.endB;
    }
    public static void Join() {
        foreach (Segment segment in segments)
            neighbors.Add(new());
        for (int a = 0; a < segments.Count; a++)
            for (int b = a + 1; b < segments.Count; b++) {
                Segment sa = segments[a], sb = segments[b];
                if (Angle(sa.t, sb.t) < settings.Get("junction_min_angle"))
                    continue;
                PgmIo.Point da = Difference(sa.end, sa.start), db = Difference(sb.end, sb.start);
                int den = Cross(da, db);
                if (den == 0)
                    continue;
                int lambda = Cross(Difference(sb.start, sa.start), db);
                PgmIo.Point point = new PgmIo.Point(Round(sa.start.x * den + lambda * da.x, den),
                                                    Round(sa.start.y * den + lambda * da.y, den));
                int ea = Distance(sa.start, point) <= Distance(sa.end, point) ? 0 : 1,
                    eb = Distance(sb.start, point) <= Distance(sb.end, point) ? 0 : 1;
                if (Distance(ea == 0 ? sa.start : sa.end, point) > settings.Get("junction_distance") ||
                    Distance(eb == 0 ? sb.start : sb.end, point) > settings.Get("junction_distance"))
                    continue;
                junctions[new Pair(sa.number, sb.number)] = new Junction(sa.number, sb.number, point, ea, eb);
                neighbors[a].Add(sb);
                neighbors[b].Add(sa);
            }
        foreach (List<Segment> adjacent in neighbors)
            adjacent.Sort(Comparer<Segment>.Create((a, b) => a.number.CompareTo(b.number)));
    }
    public static void Enumerate(List<Segment> path, int count) {
        Segment first = path[0], last = path[^1];
        if (path.Count == count) {
            if (path[1].number >= last.number || FindJunction(first, last) == null)
                return;
            List<PgmIo.Point> vertices = new();
            for (int i = 0; i < count; i++) {
                Segment current = path[i], previous = path[(i + count - 1) % count],
                        next = path[(i + 1) % count];
                Junction incoming = FindJunction(previous, current), outgoing = FindJunction(current, next);
                if (End(incoming, current) == End(outgoing, current))
                    return;
                vertices.Add(incoming.point);
            }
            int sign = 0;
            for (int i = 0; i < count; i++) {
                int z = Cross(Difference(vertices[(i + 1) % count], vertices[i]),
                              Difference(vertices[(i + 2) % count], vertices[(i + 1) % count]));
                if (z == 0 || sign != 0 && Math.Sign(z) != sign)
                    return;
                sign = Math.Sign(z);
            }
            Shape polygon = new Shape();
            polygon.number = polygons.Count + 1;
            polygon.sides = new(path);
            polygon.vertices = vertices;
            polygons.Add(polygon);
            return;
        }
        foreach (Segment next in neighbors[last.number - 1])
            if (next.number > first.number && !path.Contains(next)) {
                if (path.Count > 1 && End(FindJunction(path[path.Count - 2], last), last) ==
                                          End(FindJunction(last, next), last))
                    continue;
                path.Add(next);
                Enumerate(path, count);
                path.RemoveAt(path.Count - 1);
            }
    }
    public static void Attributes(Shape polygon) {
        int k = polygon.sides.Count, tolerance = settings.Get("angle_tolerance");
        polygon.angles = new int[k];
        polygon.Lengths = new int[k];
        polygon.support = new int[k];
        polygon.corners = new int[k];
        bool sixty = true, right = false, allRight = true;
        int minimum = int.MaxValue, maximum = 0;
        for (int i = 0; i < k; i++) {
            PgmIo.Point v = polygon.vertices[i], previous = polygon.vertices[(i + k - 1) % k],
                        next = polygon.vertices[(i + 1) % k];
            int phi = Angle(polygon.sides[(i + k - 1) % k].t, polygon.sides[i].t);
            int alpha = Dot(Difference(previous, v), Difference(next, v)) < 0 ? 180 - phi : phi;
            polygon.angles[i] = alpha;
            sixty &= Math.Abs(alpha - 60) <= tolerance;
            right |= Math.Abs(alpha - 90) <= tolerance;
            allRight &= Math.Abs(alpha - 90) <= tolerance;
            PgmIo.Point side = Difference(next, v);
            int length = Dot(side, side);
            polygon.Lengths[i] = length;
            minimum = Math.Min(minimum, length);
            maximum = Math.Max(maximum, length);
            polygon.sigma += Cross(v, next);
            List<PgmIo.Point> points = Bresenham(v, next);
            int hits = 0;
            foreach (PgmIo.Point point in points)
                if (NearEdge(point))
                    hits++;
            polygon.support[i] = 100 * hits / points.Count;
        }
        if (k == 3)
            polygon.kind = sixty ? "equilateral_triangle" : right ? "right_triangle" : "triangle";
        else {
            bool a = Angle(polygon.sides[0].t, polygon.sides[2].t) <= tolerance,
                 b = Angle(polygon.sides[1].t, polygon.sides[3].t) <= tolerance;
            polygon.kind = !a && !b    ? "quadrilateral"
                           : a != b    ? "trapezoid"
                           : !allRight ? "parallelogram"
                           : 100 * (maximum - minimum) <= settings.Get("square_tolerance") * maximum
                               ? "square"
                               : "rectangle";
        }
    }
    public static List<PgmIo.Point> Representatives(Shape shape) {
        if (!shape.circle)
            return shape.vertices;
        int x = shape.cell.x, y = shape.cell.y, r = shape.cell.r;
        return [
            new PgmIo.Point(x + r, y), new PgmIo.Point(x, y + r), new PgmIo.Point(x - r, y),
            new PgmIo.Point(x, y - r)
        ];
    }
    public static bool Contains(Shape shape, PgmIo.Point point) {
        if (shape.circle) {
            int dx = point.x - shape.cell.x, dy = point.y - shape.cell.y;
            return dx * dx + dy * dy <= shape.cell.r * shape.cell.r;
        }
        for (int i = 0; i < shape.vertices.Count; i++) {
            PgmIo.Point a = shape.vertices[i], b = shape.vertices[(i + 1) % shape.vertices.Count];
            int z = Cross(Difference(b, a), Difference(point, a));
            if (z != 0 && Math.Sign(z) != Math.Sign(shape.sigma))
                return false;
        }
        return true;
    }
    public static void Measure() {
        shapes.AddRange(polygons);
        shapes.AddRange(circles);
        foreach (Shape shape in shapes) {
            int x0 = int.MaxValue, x1 = int.MinValue, y0 = int.MaxValue, y1 = int.MinValue;
            foreach (PgmIo.Point point in Representatives(shape)) {
                x0 = Math.Min(x0, point.x);
                x1 = Math.Max(x1, point.x);
                y0 = Math.Min(y0, point.y);
                y1 = Math.Max(y1, point.y);
            }
            int margin = settings.Get("contrast_margin");
            x0 = Math.Max(0, x0 - margin);
            x1 = Math.Min(width - 1, x1 + margin);
            y0 = Math.Max(0, y0 - margin);
            y1 = Math.Min(height - 1, y1 + margin);
            int inner = 0, outer = 0, outerCount = 0;
            for (int y = y0; y <= y1; y++)
                for (int x = x0; x <= x1; x++)
                    if (Contains(shape, new PgmIo.Point(x, y))) {
                        shape.pixels++;
                        inner += image[y][x];
                    } else {
                        outerCount++;
                        outer += image[y][x];
                    }
            shape.mean = shape.pixels == 0 ? 0 : inner / shape.pixels;
            shape.contrast = shape.mean - (outerCount == 0 ? 0 : outer / outerCount);
            shape.explained = Enumerable.Range(0, height)
                                  .Select(
                                      _ => new bool[width])
                                  .ToArray();
            if (shape.circle) {
                foreach (PgmIo.Point point in edges)
                    if (Circumference(shape, point))
                        shape.explained[point.y][point.x] = true;
            } else
                for (int i = 0; i < shape.vertices.Count; i++)
                    foreach (PgmIo.Point point in Bresenham(shape.vertices[i],
                                                            shape.vertices[(i + 1) % shape.vertices.Count]))
                        for (int dy = -1; dy <= 1; dy++)
                            for (int dx = -1; dx <= 1; dx++) {
                                int x = point.x + dx, y = point.y + dy;
                                if (Canny.Inside(x, y, width, height))
                                    shape.explained[y][x] = true;
                            }
        }
        foreach (Shape shape in shapes)
            foreach (Shape enclosing in shapes) {
                if (enclosing == shape || enclosing.pixels <= shape.pixels ||
                    shape.enclosing != null && enclosing.pixels >= shape.enclosing.pixels)
                    continue;
                bool valid = true;
                foreach (PgmIo.Point point in Representatives(shape))
                    if (!Contains(enclosing, point))
                        valid = false;
                if (valid)
                    shape.enclosing = enclosing;
            }
    }
    public static string Label(Shape shape) {
        return shape == null ? "none" : (shape.circle ? "circle " : "polygon ") + shape.number;
    }
    public static void MatchCorners() {
        int limit = settings.Get("corner_match_distance");
        foreach (Corners.Corner corner in cornerResult.corners) {
            PgmIo.Point point = new PgmIo.Point(corner.x, corner.y);
            int best = limit + 1;
            string match = "none";
            foreach (Shape polygon in polygons)
                for (int i = 0; i < polygon.vertices.Count; i++) {
                    int distance = Distance(point, polygon.vertices[i]);
                    if (distance < best) {
                        best = distance;
                        match = "polygon " + polygon.number + " vertex " + (i + 1);
                    }
                }
            if (match.Equals("none"))
                foreach (Segment segment in segments)
                    for (int i = 0; i < 2; i++) {
                        int distance = Distance(point, i == 0 ? segment.start : segment.end);
                        if (distance < best) {
                            best = distance;
                            match = "segment " + segment.number + (i == 0 ? " start" : " end");
                        }
                    }
            cornerMatches.Add(match);
        }
        foreach (Shape polygon in polygons)
            for (int i = 0; i < polygon.vertices.Count; i++) {
                int best = limit + 1;
                for (int c = 0; c < cornerResult.corners.Count; c++) {
                    Corners.Corner corner = cornerResult.corners[c];
                    int distance = Distance(polygon.vertices[i], new PgmIo.Point(corner.x, corner.y));
                    if (distance < best) {
                        best = distance;
                        polygon.corners[i] = c + 1;
                    }
                }
            }
    }

    public static List<string> LineReport() {
        List<string> output = new(["lines " + lines.Count]);
        foreach (Line line in lines) {
            output.Add("line " + line.number + " theta " + line.cell.t + " rho " + line.cell.r + " votes " +
                       line.cell.votes + " segments " + line.segments.Count);
            foreach (Segment segment in line.segments)
                output.Add("segment " + segment.number + " start " + segment.start.x + " " + segment.start.y +
                           " end " + segment.end.x + " " + segment.end.y + " length " + segment.Length +
                           " pixels " + segment.pixels.Count);
        }
        return output;
    }
    public static List<string> CircleReport() {
        List<string> output = new(["circles " + circles.Count]);
        foreach (Shape circle in circles)
            output.Add("circle " + circle.number + " center " + circle.cell.x + " " + circle.cell.y +
                       " radius " + circle.cell.r + " votes " + circle.cell.votes + " points " +
                       circle.cell.total + " gap " + circle.gap + " arcs " + circle.arcs + " pixels " +
                       circle.pixels + " mean " + circle.mean + " contrast " + circle.contrast + " inside " +
                       Label(circle.enclosing));
        return output;
    }
    public static List<string> PolygonReport() {
        List<string> output = new(["polygons " + polygons.Count]);
        foreach (Shape polygon in polygons) {
            string line = "polygon " + polygon.number + " " + polygon.kind + " segments";
            foreach (Segment segment in polygon.sides)
                line += " " + segment.number;
            int area = Math.Abs(polygon.sigma);
            line += " area " + area / 2 + "." + (area % 2 == 0 ? 0 : 5) + " pixels " + polygon.pixels +
                    " mean " + polygon.mean + " contrast " + polygon.contrast + " inside " +
                    Label(polygon.enclosing);
            output.Add(line);
            for (int i = 0; i < polygon.vertices.Count; i++) {
                PgmIo.Point point = polygon.vertices[i];
                output.Add("vertex " + (i + 1) + " " + point.x + " " + point.y + " angle " +
                           polygon.angles[i] + " corner " +
                           (polygon.corners[i] == 0 ? "none" : Convert.ToString(polygon.corners[i])));
            }
            for (int i = 0; i < polygon.sides.Count; i++)
                output.Add("side " + (i + 1) + " segment " + polygon.sides[i].number + " length2 " +
                           polygon.Lengths[i] + " support " + polygon.support[i]);
        }
        return output;
    }
    public static List<string> CornerReport() {
        List<string> output = new(["corners " + cornerResult.corners.Count]);
        for (int i = 0; i < cornerResult.corners.Count; i++) {
            Corners.Corner c = cornerResult.corners[i];
            output.Add("corner " + (i + 1) + " " + c.x + " " + c.y + " response " + c.response + " match " +
                       cornerMatches[i]);
        }
        return output;
    }
    public static List<string> ComponentReport() {
        List<string> output = new(["components " + canny.components.Count]);
        for (int i = 0; i < canny.components.Count; i++) {
            List<PgmIo.Point> component = canny.components[i];
            int x0 = width, x1 = 0, y0 = height, y1 = 0, ends = 0, strength = 0;
            int[] directions = new int[4];
            foreach (PgmIo.Point point in component) {
                x0 = Math.Min(x0, point.x);
                x1 = Math.Max(x1, point.x);
                y0 = Math.Min(y0, point.y);
                y1 = Math.Max(y1, point.y);
                int adjacent = 0;
                foreach (PgmIo.Point neighbor in Canny.Neighbors(point, width, height))
                    if (Edge(neighbor))
                        adjacent++;
                if (adjacent == 1)
                    ends++;
                strength += gradient.magnitude[point.y][point.x];
                directions[canny.direction[point.y][point.x] / 45]++;
            }
            int main = 0;
            for (int d = 1; d < 4; d++)
                if (directions[d] > directions[main])
                    main = d;
            Shape best = null;
            int maximum = 0;
            foreach (Shape shape in shapes) {
                int count = 0;
                foreach (PgmIo.Point point in component)
                    if (shape.explained[point.y][point.x])
                        count++;
                if (count > maximum) {
                    best = shape;
                    maximum = count;
                }
            }
            output.Add("component " + (i + 1) + " pixels " + component.Count + " box " + x0 + " " + y0 + " " +
                       x1 + " " + y1 + " ends " + ends + " strength " + strength / component.Count +
                       " direction " + (main * 45) + " shape " + Label(best) + " explained " + maximum);
        }
        return output;
    }
    public static List<string> Report() {
        List<string> output = new();
        output.Add("image " + width + " " + height);
        int nonzero = 0, maximum = 0, kept = 0, claimedCount = 0;
        int[] directions = new int[4];
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width; x++) {
                int m = gradient.magnitude[y][x];
                if (m > 0)
                    nonzero++;
                maximum = Math.Max(maximum, m);
                if (canny.nms[y][x] > 0)
                    kept++;
                if (claimed[y][x])
                    claimedCount++;
                if (canny.edge[y][x])
                    directions[canny.direction[y][x] / 45]++;
            }
        output.Add("gradient_nonzero " + nonzero);
        output.Add("gradient_max " + maximum);
        output.Add("nms_kept " + kept);
        output.Add("strong " + canny.strong);
        output.Add("weak " + canny.weak);
        output.Add("edges " + edges.Count);
        output.Add("weak_kept " + canny.weakKept);
        output.Add("weak_dropped " + (canny.weak - canny.weakKept));
        output.Add("edge_components " + canny.components.Count);
        for (int i = 0; i < 4; i++)
            output.Add("direction_" + (i * 45) + " " + directions[i]);
        output.Add("circle_candidates " + circleVotes.candidates);
        output.Add("circle_peaks " + circleVotes.peaks.Count);
        output.Add("circles " + circles.Count);
        output.Add("circle_edge_pixels " + (edges.Count - lineEdges.Count));
        output.Add("line_edge_pixels " + lineEdges.Count);
        output.Add("hough_max_votes " + lineVotes.maximum);
        output.Add("hough_peaks " + lineVotes.peaks.Count);
        output.Add("lines " + lines.Count);
        output.Add("segments " + segments.Count);
        output.Add("claimed_pixels " + claimedCount);
        output.Add("junctions " + junctions.Count);
        output.Add("polygons " + polygons.Count);
        foreach (string kind in new string[] { "equilateral_triangle", "right_triangle", "triangle", "square",
                                               "rectangle", "parallelogram", "trapezoid", "quadrilateral" }) {
            int count = 0;
            foreach (Shape polygon in polygons)
                if (polygon.kind.Equals(kind))
                    count++;
            output.Add(kind + " " + count);
        }
        int vertices = 0, onVertices = 0, onSegments = 0;
        foreach (Shape polygon in polygons)
            foreach (int corner in polygon.corners)
                if (corner != 0)
                    vertices++;
        foreach (string match in cornerMatches) {
            if (match.StartsWith("polygon"))
                onVertices++;
            if (match.StartsWith("segment"))
                onSegments++;
        }
        output.Add("corner_candidates " + cornerResult.candidates);
        output.Add("corners " + cornerResult.corners.Count);
        output.Add("corners_on_vertices " + onVertices);
        output.Add("corners_on_segments " + onSegments);
        output.Add("corners_unmatched " + (cornerMatches.Count - onVertices - onSegments));
        output.Add("vertices_with_corner " + vertices);
        return output;
    }
    public static void Mark(int[][] overlay, PgmIo.Point point) {
        if (Canny.Inside(point.x, point.y, width, height))
            overlay[point.y][point.x] = 255;
    }
    public static void Images() {
        int[][] edgeImage = Enumerable.Range(0, height)
                                .Select(
                                    _ => new int[width])
                                .ToArray(),
                overlay = Enumerable.Range(0, height)
                              .Select(
                                  _ => new int[width])
                              .ToArray();
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width; x++) {
                edgeImage[y][x] = canny.edge[y][x] ? 255 : 0;
                overlay[y][x] = image[y][x] / settings.Get("overlay_divisor");
            }
        foreach (Segment segment in segments)
            foreach (PgmIo.Point point in Bresenham(segment.start, segment.end))
                Mark(overlay, point);
        foreach (Shape circle in circles)
            foreach (PgmIo.Point point in circleVotes.outlines[circle.cell.r])
                Mark(overlay, Translate(point, circle.cell.x, circle.cell.y));
        foreach (Corners.Corner c in cornerResult.corners)
            for (int e = -2; e <= 2; e++) {
                Mark(overlay, new PgmIo.Point(c.x + e, c.y));
                Mark(overlay, new PgmIo.Point(c.x, c.y + e));
            }
        int[][] votes = Enumerable.Range(0, lineVotes.high - lineVotes.low + 1)
                            .Select(
                                _ => new int[180])
                            .ToArray();
        for (int r = lineVotes.low; r <= lineVotes.high; r++)
            for (int t = 0; t < 180; t++)
                votes[r - lineVotes.low][t] =
                    lineVotes.maximum == 0 ? 0 : 255 * lineVotes.Count(t, r) / lineVotes.maximum;
        PgmIo.Pgm("edges.pgm", edgeImage);
        PgmIo.Pgm("hough.pgm", votes);
        PgmIo.Pgm("overlay.pgm", overlay);
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        PgmIo.Data data = PgmIo.Read();
        image = data.image;
        trig = data.trig;
        settings = data.settings;
        height = image.Length;
        width = image[0].Length;
        gradient = Filters.ComputeGradient(Filters.Smooth(image, settings));
        canny = Canny.Process(gradient, settings.Get("canny_low"), settings.Get("canny_high"));
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width; x++)
                if (canny.edge[y][x])
                    edges.Add(new PgmIo.Point(x, y));
        circleVotes = Hough.Circles(edges, width, height, settings);
        DetermineCircles();
        lineVotes = Hough.Lines(lineEdges, width, height, trig, settings.Get("hough_rho_step"),
                                settings.Get("hough_threshold"));
        Extract();
        Join();
        for (int k = 3; k <= 4; k++)
            foreach (Segment first in segments)
                Enumerate(new([first]), k);
        foreach (Shape polygon in polygons)
            Attributes(polygon);
        Measure();
        cornerResult = Corners.Detect(gradient, settings.Get("harris_window"),
                                      settings.Value("harris_threshold"), settings.Get("harris_max_count"));
        MatchCorners();
        Images();
        PgmIo.Write("lines.txt", LineReport());
        PgmIo.Write("circles.txt", CircleReport());
        PgmIo.Write("polygons.txt", PolygonReport());
        PgmIo.Write("corners.txt", CornerReport());
        PgmIo.Write("components.txt", ComponentReport());
        PgmIo.Write("report.txt", Report());
    }
}
