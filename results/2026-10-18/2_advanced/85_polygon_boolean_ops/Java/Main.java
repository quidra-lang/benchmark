import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
public final class Main {
    static final List<String> KINDS =
        List.of("UNION", "INTERSECTION", "DIFFERENCE", "XOR", "CLIP", "AREA", "MOVE", "ROTATE",
                "MIRROR", "SNAP", "LOCATE", "RENDER");
    static final Set<String> BINARY = Set.of("UNION", "INTERSECTION", "DIFFERENCE", "XOR", "CLIP"),
                             DEFINITIONS = Set.of("MOVE", "ROTATE", "MIRROR", "SNAP");
    static final class Rejected extends RuntimeException {
        Rejected(String reason) { super(reason); }
    }
    record Line(int number, String text) {}
    record Parsed(List<List<Rational.Point>> rings, Integer error) {}
    static boolean digits(String word) {
        if (word.isEmpty() || word.length() > 9)
            return false;
        for (char c : word.toCharArray())
            if (c < '0' || c > '9')
                return false;
        return true;
    }
    static boolean integerWord(String word) {
        return digits(word.startsWith("-") ? word.substring(1) : word);
    }
    static boolean validName(String word) {
        if (word.isEmpty() || word.length() > 16)
            return false;
        for (char c : word.toCharArray())
            if (!(c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '_'))
                return false;
        return true;
    }
    static List<Line> records(String name) throws Exception {
        List<Line> result = new ArrayList<>();
        List<String> lines = Files.readAllLines(Path.of("input", name), StandardCharsets.US_ASCII);
        for (int i = 0; i < lines.size(); i++) {
            String line = lines.get(i);
            if (!line.isEmpty() && !line.startsWith("#"))
                result.add(new Line(i + 1, line));
        }
        return result;
    }
    static Parsed parseRings(List<Line> content, int endLine) {
        List<List<Rational.Point>> result = new ArrayList<>();
        int position = 0;
        while (position < content.size()) {
            Line header = content.get(position);
            String[] words = header.text().split(" ");
            if (words.length != 2 || !Set.of("OUTER", "HOLE").contains(words[0]) ||
                !digits(words[1]) || Integer.parseInt(words[1]) < 1)
                return new Parsed(null, header.number());
            if (words[0].equals("OUTER") && !result.isEmpty() ||
                words[0].equals("HOLE") && result.isEmpty())
                return new Parsed(null, header.number());
            int count = Integer.parseInt(words[1]);
            position++;
            List<Rational.Point> vertices = new ArrayList<>();
            for (int i = 0; i < count; i++) {
                if (position == content.size())
                    return new Parsed(null, endLine);
                Line line = content.get(position++);
                String[] coordinates = line.text().split(" ");
                if (coordinates.length != 2 || !integerWord(coordinates[0]) ||
                    !integerWord(coordinates[1]))
                    return new Parsed(null, line.number());
                vertices.add(new Rational.Point(Long.parseLong(coordinates[0]),
                                                Long.parseLong(coordinates[1])));
            }
            result.add(vertices);
        }
        return result.isEmpty() ? new Parsed(null, endLine) : new Parsed(result, null);
    }
    static boolean inRange(Rational.Point point) {
        return point.x().compareTo(Rational.ZERO) >= 0 &&
            point.x().compareTo(new Rational.Fraction(1000)) <= 0 &&
            point.y().compareTo(Rational.ZERO) >= 0 &&
            point.y().compareTo(new Rational.Fraction(1000)) <= 0;
    }
    static String checkRing(List<Rational.Point> ring, int number) {
        int count = ring.size();
        if (count < 3)
            return "too_few_vertices ring " + number;
        for (Rational.Point point : ring)
            if (!inRange(point))
                return "out_of_range ring " + number + " " + point;
        Set<Rational.Point> seen = new HashSet<>();
        for (Rational.Point point : ring)
            if (!seen.add(point))
                return "duplicate_vertex ring " + number + " " + point;
        for (int i = 0; i < count; i++)
            if (Rational
                    .cross(ring.get((i + count - 1) % count), ring.get(i),
                           ring.get((i + 1) % count))
                    .sign() == 0)
                return "collinear ring " + number + " " + ring.get(i);
        List<Rings.Edge> edges = Rings.edges(ring);
        for (int first = 0; first < count; first++)
            for (int second = first + 2; second < count; second++) {
                if (first == 0 && second == count - 1)
                    continue;
                Rings.Edge a = edges.get(first), b = edges.get(second);
                if (Intersections.touch(a.first(), a.second(), b.first(), b.second()))
                    return "self_intersection ring " + number + " " +
                        Rational.segment(a.first(), a.second()) + " " +
                        Rational.segment(b.first(), b.second());
            }
        return null;
    }
    static String checkPolygon(List<List<Rational.Point>> sequence) {
        for (int i = 0; i < sequence.size(); i++) {
            String error = checkRing(sequence.get(i), i + 1);
            if (error != null)
                return error;
        }
        for (int first = 0; first < sequence.size(); first++)
            for (int second = first + 1; second < sequence.size(); second++)
                for (Rings.Edge a : Rings.edges(sequence.get(first)))
                    for (Rings.Edge b : Rings.edges(sequence.get(second)))
                        if (Intersections.touch(a.first(), a.second(), b.first(), b.second()))
                            return "rings_touch rings " + (first + 1) + " " + (second + 1) + " " +
                                Rational.segment(a.first(), a.second()) + " " +
                                Rational.segment(b.first(), b.second());
        for (int i = 1; i < sequence.size(); i++)
            if (!Rings.inside(sequence.getFirst(), sequence.get(i).getFirst()))
                return "hole_outside ring " + (i + 1) + " " + sequence.get(i).getFirst();
        for (int first = 1; first < sequence.size(); first++)
            for (int second = first + 1; second < sequence.size(); second++) {
                Rational.Point point;
                if (Rings.inside(sequence.get(first), sequence.get(second).getFirst()))
                    point = sequence.get(second).getFirst();
                else if (Rings.inside(sequence.get(second), sequence.get(first).getFirst()))
                    point = sequence.get(first).getFirst();
                else
                    continue;
                return "hole_in_hole rings " + (first + 1) + " " + (second + 1) + " " + point;
            }
        return null;
    }
    static final class PolygonDef {
        String name;
        List<List<Rational.Point>> inputRings, rings;
        PolygonDef(String name, List<List<Rational.Point>> inputRings) {
            this.name = name;
            this.inputRings = inputRings;
            List<List<Rational.Point>> holes = new ArrayList<>();
            for (List<Rational.Point> ring : inputRings.subList(1, inputRings.size()))
                holes.add(Rings.normalize(ring, false));
            holes.sort(Comparator.comparing(List::getFirst));
            rings = new ArrayList<>();
            rings.add(Rings.normalize(inputRings.getFirst(), true));
            rings.addAll(holes);
        }
    }
    static final class Registry {
        Set<String> used = new HashSet<>();
        Map<String, PolygonDef> polygons = new HashMap<>();
        List<String> invalid = new ArrayList<>();
        int blockCount, validBlocks;
        Registry() throws Exception {
            List<Line> lines = records("polygons.txt");
            int position = 0;
            while (position < lines.size()) {
                Line start = lines.get(position++);
                String name = start.text().split(" ")[1];
                List<Line> content = new ArrayList<>();
                while (!lines.get(position).text().equals("END"))
                    content.add(lines.get(position++));
                int end = lines.get(position++).number();
                blockCount++;
                if (!used.add(name)) {
                    invalid.add("polygon " + name + " duplicate_name line " + start.number());
                    continue;
                }
                Parsed parsed = parseRings(content, end);
                if (parsed.error() != null) {
                    invalid.add("polygon " + name + " format line " + parsed.error());
                    continue;
                }
                String error = checkPolygon(parsed.rings());
                if (error != null) {
                    invalid.add("polygon " + name + " " + error);
                    continue;
                }
                polygons.put(name, new PolygonDef(name, parsed.rings()));
                validBlocks++;
            }
        }
        PolygonDef resolve(String name) {
            if (!used.contains(name))
                throw new Rejected("unknown_polygon " + name);
            if (!polygons.containsKey(name))
                throw new Rejected("invalid_polygon " + name);
            return polygons.get(name);
        }
        void define(PolygonDef polygon) {
            used.add(polygon.name);
            polygons.put(polygon.name, polygon);
        }
    }
    record Region(List<Rings.Polygon> polygons, PolygonDef first, PolygonDef second) {}
    record Checked(PolygonDef a, PolygonDef b, Region target, PolygonDef defined) {}
    record BinaryResult(Region region, GreinerHormann.Graph graph, String relation, double iou) {}
    record ClipCheck(String decision, int rings, int vertices) {}
    static boolean argumentsValid(String[] w) {
        String kind = w[0];
        int expected = switch (kind) {
            case "UNION", "INTERSECTION", "DIFFERENCE", "XOR", "CLIP", "SNAP" -> 3;
            case "AREA" -> 2;
            case "LOCATE" -> 4;
            case "MOVE", "MIRROR" -> 5;
            case "ROTATE" -> 6;
            default -> 8;
        };
        if (w.length != expected)
            return false;
        if (BINARY.contains(kind) || kind.equals("AREA"))
            return true;
        if (kind.equals("SNAP"))
            return validName(w[2]);
        if (kind.equals("MIRROR"))
            return validName(w[4]) && (w[2].equals("x") || w[2].equals("y")) && integerWord(w[3]) &&
                Long.parseLong(w[3]) >= 0 && Long.parseLong(w[3]) <= 1000;
        int end = switch (kind) {
            case "MOVE" -> 4;
            case "ROTATE" -> 5;
            default -> w.length;
        };
        for (int i = 2; i < end; i++)
            if (!integerWord(w[i]))
                return false;
        if (kind.equals("LOCATE"))
            return Long.parseLong(w[2]) >= 0 && Long.parseLong(w[2]) <= 1000 &&
                Long.parseLong(w[3]) >= 0 && Long.parseLong(w[3]) <= 1000;
        if (kind.equals("MOVE"))
            return validName(w[4]) && Math.abs(Long.parseLong(w[2])) <= 1000 &&
                Math.abs(Long.parseLong(w[3])) <= 1000;
        if (kind.equals("ROTATE"))
            return validName(w[5]) && Long.parseLong(w[2]) >= 0 && Long.parseLong(w[2]) <= 1000 &&
                Long.parseLong(w[3]) >= 0 && Long.parseLong(w[3]) <= 1000 &&
                Long.parseLong(w[4]) >= 1 && Long.parseLong(w[4]) <= 3;
        long x0 = Long.parseLong(w[2]), y0 = Long.parseLong(w[3]), width = Long.parseLong(w[4]),
             height = Long.parseLong(w[5]), columns = Long.parseLong(w[6]),
             rows = Long.parseLong(w[7]);
        return x0 >= 0 && y0 >= 0 && width >= 1 && width <= 100 && height >= 1 && height <= 100 &&
            columns >= 1 && columns <= 100 && rows >= 1 && rows <= 60 &&
            x0 + width * columns <= 1000 && y0 + height * rows <= 1000;
    }
    static List<Rational.Point> vertices(List<List<Rational.Point>> rings) {
        List<Rational.Point> result = new ArrayList<>();
        for (List<Rational.Point> ring : rings)
            result.addAll(ring);
        return result;
    }
    static List<Rings.Edge> edges(List<List<Rational.Point>> rings) {
        List<Rings.Edge> result = new ArrayList<>();
        for (List<Rational.Point> ring : rings)
            result.addAll(Rings.edges(ring));
        return result;
    }
    static String generalPosition(PolygonDef first, PolygonDef second) {
        List<Rational.Point> firstVertices = vertices(first.rings), secondVertices =
                                                                        vertices(second.rings);
        Set<Rational.Point> secondSet = new HashSet<>(secondVertices);
        for (Rational.Point point : firstVertices)
            if (secondSet.contains(point))
                return "shared_vertex " + point;
        List<Rings.Edge> firstEdges = edges(first.rings), secondEdges = edges(second.rings);
        for (Rings.Edge a : firstEdges)
            for (Rings.Edge b : secondEdges)
                if (Intersections.overlap(a.first(), a.second(), b.first(), b.second()))
                    return "overlapping_edges " + Rational.segment(a.first(), a.second()) + " " +
                        Rational.segment(b.first(), b.second());
        for (int side = 0; side < 2; side++) {
            PolygonDef source = side == 0 ? first : second, other = side == 0 ? second : first;
            List<Rational.Point> points = side == 0 ? firstVertices : secondVertices;
            List<Rings.Edge> targetEdges = side == 0 ? secondEdges : firstEdges;
            for (Rational.Point point : points)
                for (Rings.Edge edge : targetEdges)
                    if (Intersections.onSegment(point, edge.first(), edge.second()))
                        return "vertex_on_edge " + source.name + " " + point + " " + other.name +
                            " " + Rational.segment(edge.first(), edge.second());
        }
        return null;
    }
    static List<List<Rational.Point>> transformedRings(PolygonDef polygon, String[] w) {
        List<List<Rational.Point>> result = new ArrayList<>();
        for (List<Rational.Point> ring : polygon.inputRings) {
            List<Rational.Point> transformed = new ArrayList<>();
            for (Rational.Point point : ring) {
                Rational.Fraction x = point.x(), y = point.y();
                if (w[0].equals("MOVE")) {
                    x = x.add(new Rational.Fraction(Long.parseLong(w[2])));
                    y = y.add(new Rational.Fraction(Long.parseLong(w[3])));
                } else if (w[0].equals("ROTATE")) {
                    Rational.Fraction cx = new Rational.Fraction(Long.parseLong(w[2])),
                                      cy = new Rational.Fraction(Long.parseLong(w[3]));
                    for (int q = 0; q < Integer.parseInt(w[4]); q++) {
                        Rational.Fraction nextX = cx.subtract(y.subtract(cy));
                        y = cy.add(x.subtract(cx));
                        x = nextX;
                    }
                } else if (w[2].equals("x"))
                    x = new Rational.Fraction(2 * Long.parseLong(w[3])).subtract(x);
                else
                    y = new Rational.Fraction(2 * Long.parseLong(w[3])).subtract(y);
                transformed.add(new Rational.Point(x, y));
            }
            result.add(transformed);
        }
        return result;
    }
    static List<List<Rational.Point>> roundedRings(Rings.Polygon polygon) {
        List<List<Rational.Point>> result = new ArrayList<>();
        for (List<Rational.Point> ring : polygon.rings()) {
            List<Rational.Point> rounded = new ArrayList<>();
            for (Rational.Point point : ring)
                rounded.add(new Rational.Point(point.x().rounded(), point.y().rounded()));
            result.add(rounded);
        }
        return result;
    }
    static double totalArea(List<Rings.Polygon> polygons) {
        double total = 0;
        for (Rings.Polygon polygon : polygons)
            for (List<Rational.Point> ring : polygon.rings())
                total += Rings.area(ring);
        return total;
    }
    static BinaryResult binaryResult(String kind, PolygonDef first, PolygonDef second) {
        GreinerHormann.Graph graph = new GreinerHormann.Graph(first.rings, second.rings);
        List<Rings.Polygon> intersection = Rings.assemble(graph.traverse(false, false)),
                            union = Rings.assemble(graph.traverse(true, true)), polygons;
        if (kind.equals("UNION"))
            polygons = union;
        else if (kind.equals("INTERSECTION") || kind.equals("CLIP"))
            polygons = intersection;
        else {
            polygons = Rings.assemble(graph.traverse(true, false));
            if (kind.equals("XOR")) {
                GreinerHormann.Graph reverse = new GreinerHormann.Graph(second.rings, first.rings);
                polygons.addAll(Rings.assemble(reverse.traverse(true, false)));
                polygons.sort(Comparator.comparing(p -> p.rings().getFirst().getFirst()));
            }
        }
        String relation = !graph.crossings.isEmpty()                         ? "overlap"
                          : graph.nA == first.rings.size() && graph.nB == 0  ? "within"
                          : graph.nB == second.rings.size() && graph.nA == 0 ? "contains"
                          : graph.nA == 0 && graph.nB == 0                   ? "disjoint"
                                                                             : "overlap";
        return new BinaryResult(new Region(polygons, first, second), graph, relation,
                                totalArea(intersection) / totalArea(union));
    }
    static boolean cyclicEqual(List<Rational.Point> a, List<Rational.Point> b) {
        if (a.size() != b.size())
            return false;
        for (int start = 0; start < b.size(); start++)
            if (b.get(start).equals(a.getFirst())) {
                boolean equal = true;
                for (int i = 0; i < a.size(); i++)
                    if (!a.get(i).equals(b.get((start + i) % b.size())))
                        equal = false;
                if (equal)
                    return true;
            }
        return false;
    }
    static ClipCheck crosscheckClip(PolygonDef first, PolygonDef window,
                                    List<Rings.Polygon> polygons) {
        List<List<Rational.Point>> clipped = new ArrayList<>();
        for (List<Rational.Point> ring : first.rings) {
            List<Rational.Point> points = new ArrayList<>(ring);
            for (Rings.Edge edge : Rings.edges(window.rings.getFirst())) {
                List<Rational.Point> replacement = new ArrayList<>();
                for (int i = 0; i < points.size(); i++) {
                    Rational.Point current = points.get(i),
                                   previous = points.get((i + points.size() - 1) % points.size());
                    Rational.Fraction a = Rational.cross(edge.first(), edge.second(), previous),
                                      b = Rational.cross(edge.first(), edge.second(), current);
                    if ((a.sign() > 0) != (b.sign() > 0))
                        replacement.add(Intersections.clippingPoint(previous, current, a, b));
                    if (b.sign() > 0)
                        replacement.add(current);
                }
                points = replacement;
            }
            List<Rational.Point> deduplicated = new ArrayList<>();
            for (int i = 0; i < points.size(); i++)
                if (!points.get(i).equals(points.get((i + points.size() - 1) % points.size())))
                    deduplicated.add(points.get(i));
            if (deduplicated.size() >= 3)
                clipped.add(deduplicated);
        }
        List<List<Rational.Point>> resultRings = Rings.flatten(polygons);
        boolean matches = resultRings.size() == clipped.size();
        for (List<Rational.Point> ring : resultRings) {
            boolean found = false;
            for (List<Rational.Point> other : clipped)
                if (cyclicEqual(ring, other))
                    found = true;
            if (!found)
                matches = false;
        }
        int vertices = clipped.stream().mapToInt(List::size).sum();
        return new ClipCheck(matches ? "match" : "mismatch", clipped.size(), vertices);
    }
    static String f3(double value) { return String.format(Locale.ROOT, "%.3f", value); }
    static String f6(double value) { return String.format(Locale.ROOT, "%.6f", value); }
    record RingItem(int polygon, int hole, List<Rational.Point> ring, double area) {}
    static final class ResultValues {
        int polygonCount, ringCount, holeCount, vertexCount;
        List<RingItem> ringItems = new ArrayList<>();
        double area, perimeter, centroidX, centroidY;
        int[] origins = new int[3];
        Rational.Point low, high;
        ResultValues(List<Rings.Polygon> polygons, PolygonDef first, PolygonDef second) {
            polygonCount = polygons.size();
            Set<Rational.Point> firstVertices = new HashSet<>(vertices(first.rings)),
                                secondVertices = second == null
                                                     ? Set.of()
                                                     : new HashSet<>(vertices(second.rings));
            List<Rational.Point> vertices = new ArrayList<>();
            double sx = 0, sy = 0;
            for (int p = 0; p < polygons.size(); p++) {
                List<List<Rational.Point>> rings = polygons.get(p).rings();
                for (int h = 0; h < rings.size(); h++) {
                    List<Rational.Point> ring = rings.get(h);
                    double ringArea = Rings.area(ring);
                    area += ringArea;
                    perimeter += Rings.perimeter(ring);
                    ringItems.add(new RingItem(p + 1, h, ring, ringArea));
                    vertices.addAll(ring);
                    for (Rings.Edge edge : Rings.edges(ring)) {
                        Rational.Point a = edge.first(), b = edge.second();
                        origins[firstVertices.contains(a)    ? 0
                                : secondVertices.contains(a) ? 1
                                                             : 2]++;
                        double x1 = a.x().real(), y1 = a.y().real(), x2 = b.x().real(),
                               y2 = b.y().real(), c = x1 * y2 - x2 * y1;
                        sx += (x1 + x2) * c;
                        sy += (y1 + y2) * c;
                    }
                }
            }
            ringCount = ringItems.size();
            holeCount = ringCount - polygonCount;
            vertexCount = vertices.size();
            if (!vertices.isEmpty()) {
                Rational.Fraction minX = vertices.getFirst().x(), minY = vertices.getFirst().y(),
                                  maxX = minX, maxY = minY;
                for (Rational.Point point : vertices) {
                    minX = Rational.min(minX, point.x());
                    minY = Rational.min(minY, point.y());
                    maxX = Rational.max(maxX, point.x());
                    maxY = Rational.max(maxY, point.y());
                }
                low = new Rational.Point(minX, minY);
                high = new Rational.Point(maxX, maxY);
                centroidX = sx / (6 * area);
                centroidY = sy / (6 * area);
            }
        }
        List<String> lines() {
            List<String> lines = new ArrayList<>();
            lines.add("polygons " + polygonCount + " rings " + ringCount + " holes " + holeCount +
                      " vertices " + vertexCount + " area " + f3(area));
            for (RingItem item : ringItems) {
                String prefix = item.hole() == 0 ? "outer " + item.polygon()
                                                 : "hole " + item.polygon() + " " + item.hole();
                StringBuilder line =
                    new StringBuilder(prefix + " " + item.ring().size() + " " + f3(item.area()));
                for (Rational.Point point : item.ring())
                    line.append(' ').append(point);
                lines.add(line.toString());
            }
            if (low == null) {
                lines.add("bbox none");
                lines.add("centroid none");
            } else {
                lines.add("bbox " + low + " " + high);
                lines.add("centroid (" + f3(centroidX) + "," + f3(centroidY) + ")");
            }
            lines.add("perimeter " + f3(perimeter));
            lines.add("origins a " + origins[0] + " b " + origins[1] + " crossing " + origins[2]);
            return lines;
        }
    }
    static List<Rational.Point> convexHull(List<Rational.Point> outer) {
        List<Rational.Point> ordered = new ArrayList<>(outer);
        ordered.sort(Comparator.comparing(Rational.Point::x).thenComparing(Rational.Point::y));
        List<List<Rational.Point>> chains = new ArrayList<>();
        for (int side = 0; side < 2; side++) {
            List<Rational.Point> sequence = new ArrayList<>(ordered);
            if (side == 1)
                Collections.reverse(sequence);
            List<Rational.Point> chain = new ArrayList<>();
            for (Rational.Point point : sequence) {
                while (chain.size() >= 2 &&
                       Rational.cross(chain.get(chain.size() - 2), chain.getLast(), point).sign() <=
                           0)
                    chain.removeLast();
                chain.add(point);
            }
            chains.add(chain);
        }
        List<Rational.Point> hull =
            new ArrayList<>(chains.get(0).subList(0, chains.get(0).size() - 1));
        hull.addAll(chains.get(1).subList(0, chains.get(1).size() - 1));
        return hull;
    }
    static Rational.Fraction twiceArea(List<Rational.Point> ring) {
        Rational.Fraction total = Rational.ZERO;
        for (Rings.Edge edge : Rings.edges(ring))
            total = total.add(edge.first()
                                  .x()
                                  .multiply(edge.second().y())
                                  .subtract(edge.second().x().multiply(edge.first().y())));
        return total;
    }
    static List<String> propertyLines(PolygonDef polygon, double area) {
        List<String> orientations = new ArrayList<>();
        for (List<Rational.Point> ring : polygon.inputRings)
            orientations.add(twiceArea(ring).sign() > 0 ? "ccw" : "cw");
        int reflex = 0;
        for (List<Rational.Point> ring : polygon.rings)
            for (int i = 0; i < ring.size(); i++)
                if (Rational
                        .cross(ring.get((i + ring.size() - 1) % ring.size()), ring.get(i),
                               ring.get((i + 1) % ring.size()))
                        .sign() < 0)
                    reflex++;
        List<Rational.Point> hull = convexHull(polygon.rings.getFirst());
        double hullArea = twiceArea(hull).divide(new Rational.Fraction(2)).real();
        return List.of("input " + String.join(" ", orientations), "reflex " + reflex,
                       "hull " + hull.size() + " " + f3(hullArea) + " solidity " +
                           f6(area / hullArea));
    }
    static String locate(List<Rings.Polygon> polygons, Rational.Point point) {
        for (int k = 0; k < polygons.size(); k++) {
            List<List<Rational.Point>> rings = polygons.get(k).rings();
            if (Rings.boundary(rings.getFirst(), point))
                return "boundary outer " + (k + 1);
            for (int h = 1; h < rings.size(); h++)
                if (Rings.boundary(rings.get(h), point))
                    return "boundary hole " + (k + 1) + " " + h;
        }
        for (int k = 0; k < polygons.size(); k++) {
            List<List<Rational.Point>> rings = polygons.get(k).rings();
            boolean hole = false;
            for (int h = 1; h < rings.size(); h++)
                if (Rings.inside(rings.get(h), point))
                    hole = true;
            if (Rings.inside(rings.getFirst(), point) && !hole)
                return "inside polygon " + (k + 1);
        }
        return "outside";
    }
    static String operandLocation(PolygonDef polygon, Rational.Point point) {
        for (List<Rational.Point> ring : polygon.rings)
            if (Rings.boundary(ring, point))
                return "boundary";
        return Rings.interior(polygon.rings, point) ? "inside" : "outside";
    }
    static final class Processor {
        Registry registry;
        List<String> operations = new ArrayList<>();
        Map<Integer, Region> regions = new HashMap<>();
        List<String> results = new ArrayList<>(), areas = new ArrayList<>(),
                     drawings = new ArrayList<>(), rejectedOperations = new ArrayList<>();
        Map<String, Integer> kindTotals = new HashMap<>(), kindSucceeded = new HashMap<>();
        int succeeded, defined, crossings;
        Processor() throws Exception {
            registry = new Registry();
            for (Line line : records("operations.txt"))
                operations.add(line.text());
            areas.add("operation,rings,holes,vertices,area");
        }
        Region resolveTarget(String word) {
            if (word.startsWith("@")) {
                String number = word.substring(1);
                if (!digits(number) || !regions.containsKey(Integer.parseInt(number)))
                    throw new Rejected("bad_target " + word);
                return regions.get(Integer.parseInt(number));
            }
            PolygonDef polygon = registry.resolve(word);
            return new Region(List.of(new Rings.Polygon(polygon.rings)), null, null);
        }
        Checked checkOperation(String[] w) {
            String kind = w[0];
            if (!KINDS.contains(kind))
                throw new Rejected("unknown_operation " + kind);
            if (!argumentsValid(w))
                throw new Rejected("bad_arguments");
            PolygonDef a = null, b = null, defined = null;
            Region target = null;
            if (BINARY.contains(kind)) {
                a = registry.resolve(w[1]);
                b = registry.resolve(w[2]);
            } else if (Set.of("AREA", "MOVE", "ROTATE", "MIRROR").contains(kind))
                a = registry.resolve(w[1]);
            else
                target = resolveTarget(w[1]);
            String name = w[w.length - 1];
            if (DEFINITIONS.contains(kind) && registry.used.contains(name))
                throw new Rejected("duplicate_name " + name);
            if (kind.equals("SNAP") && target.polygons().size() != 1)
                throw new Rejected("not_single " + w[1]);
            if (kind.equals("CLIP")) {
                if (b.rings.size() > 1)
                    throw new Rejected("not_convex " + w[2]);
                List<Rational.Point> ring = b.rings.getFirst();
                for (int i = 0; i < ring.size(); i++)
                    if (Rational
                            .cross(ring.get((i + ring.size() - 1) % ring.size()), ring.get(i),
                                   ring.get((i + 1) % ring.size()))
                            .sign() <= 0)
                        throw new Rejected("not_convex " + w[2]);
            }
            if (BINARY.contains(kind)) {
                String error = generalPosition(a, b);
                if (error != null)
                    throw new Rejected(error);
            }
            if (Set.of("MOVE", "ROTATE", "MIRROR").contains(kind)) {
                List<List<Rational.Point>> sequence = transformedRings(a, w);
                for (List<Rational.Point> ring : sequence)
                    for (Rational.Point point : ring)
                        if (!inRange(point))
                            throw new Rejected("out_of_range " + name);
                defined = new PolygonDef(name, sequence);
            } else if (kind.equals("SNAP")) {
                List<List<Rational.Point>> sequence = roundedRings(target.polygons().getFirst());
                String error = checkPolygon(sequence);
                if (error != null)
                    throw new Rejected("invalid_result " + error);
                defined = new PolygonDef(name, sequence);
            }
            return new Checked(a, b, target, defined);
        }
        void recordRegion(int number, String line, String[] words, Checked checked) {
            String kind = words[0];
            results.add("op " + number + " " + line);
            PolygonDef first, second;
            Region region;
            if (BINARY.contains(kind)) {
                first = checked.a();
                second = checked.b();
                BinaryResult result = binaryResult(kind, first, second);
                region = result.region();
                GreinerHormann.Graph graph = result.graph();
                results.add("relation " + result.relation() + " iou " + f6(result.iou()));
                results.add("crossings " + graph.crossings.size());
                crossings += graph.crossings.size();
                for (GreinerHormann.Crossing crossing : graph.crossings)
                    results.add("crossing " + crossing.point + " " +
                                (crossing.first.entering ? "in" : "out"));
            } else {
                first = DEFINITIONS.contains(kind) ? checked.defined() : checked.a();
                second = null;
                region = new Region(List.of(new Rings.Polygon(first.rings)), null, null);
            }
            regions.put(number, region);
            ResultValues values = new ResultValues(region.polygons(), first, second);
            results.addAll(values.lines());
            if (!BINARY.contains(kind))
                results.addAll(propertyLines(first, values.area));
            if (kind.equals("CLIP")) {
                ClipCheck check = crosscheckClip(first, second, region.polygons());
                results.add("crosscheck " + check.decision() + " rings " + check.rings() +
                            " vertices " + check.vertices());
            }
            areas.add(number + ":" + String.join(":", words) + "," + values.ringCount + "," +
                      values.holeCount + "," + values.vertexCount + "," + f3(values.area));
        }
        void recordLocation(int number, String line, String[] words, Region target) {
            Rational.Point point =
                new Rational.Point(Long.parseLong(words[2]), Long.parseLong(words[3]));
            results.add("op " + number + " " + line);
            results.add("location " + locate(target.polygons(), point));
            if (target.first() != null)
                results.add("operands a " + operandLocation(target.first(), point) + " b " +
                            operandLocation(target.second(), point));
        }
        void recordRender(int number, String[] words, Region target) {
            int[] p = new int[6];
            for (int i = 0; i < 6; i++)
                p[i] = Integer.parseInt(words[i + 2]);
            Render.Picture picture =
                Render.grid(target.polygons(), target.first() == null ? null : target.first().rings,
                            target.second() == null ? null : target.second().rings, p[0], p[1],
                            p[2], p[3], p[4], p[5]);
            drawings.add("render " + number + " " + words[1] + " cols " + p[4] + " rows " + p[5] +
                         " result " + picture.result() + " a " + picture.a() + " b " + picture.b() +
                         " both " + picture.both());
            drawings.addAll(picture.lines());
        }
        void process() {
            for (int index = 0; index < operations.size(); index++) {
                int number = index + 1;
                String line = operations.get(index);
                String[] words = line.split(" ");
                String kind = words[0];
                if (KINDS.contains(kind))
                    kindTotals.merge(kind, 1, Integer::sum);
                Checked checked;
                try {
                    checked = checkOperation(words);
                } catch (Rejected error) {
                    rejectedOperations.add("op " + number + " " + error.getMessage());
                    continue;
                }
                succeeded++;
                kindSucceeded.merge(kind, 1, Integer::sum);
                if (DEFINITIONS.contains(kind)) {
                    registry.define(checked.defined());
                    defined++;
                }
                if (kind.equals("RENDER"))
                    recordRender(number, words, checked.target());
                else if (kind.equals("LOCATE"))
                    recordLocation(number, line, words, checked.target());
                else
                    recordRegion(number, line, words, checked);
            }
            results.add("summary polygons " + registry.blockCount + " valid " +
                        registry.validBlocks + " invalid " + registry.invalid.size() + " defined " +
                        defined);
            results.add("summary operations " + operations.size() + " succeeded " + succeeded +
                        " rejected " + rejectedOperations.size());
            results.add("summary crossings " + crossings);
            for (String kind : KINDS)
                results.add("kind " + kind + " " + kindTotals.getOrDefault(kind, 0) + " " +
                            kindSucceeded.getOrDefault(kind, 0));
        }
        void write() throws Exception {
            List<String> rejections = new ArrayList<>();
            rejections.add("rejections " + (registry.invalid.size() + rejectedOperations.size()));
            rejections.addAll(registry.invalid);
            rejections.addAll(rejectedOperations);
            Files.createDirectories(Path.of("output"));
            Map<String, List<String>> outputs = new LinkedHashMap<>();
            outputs.put("results.txt", results);
            outputs.put("areas.csv", areas);
            outputs.put("render.txt", drawings);
            outputs.put("rejections.txt", rejections);
            for (var entry : outputs.entrySet())
                Files.writeString(
                    Path.of("output", entry.getKey()),
                    entry.getValue().isEmpty() ? "" : String.join("\n", entry.getValue()) + "\n",
                    StandardCharsets.US_ASCII);
        }
    }
    public static void main(String[] args) throws Exception {
        Processor processor = new Processor();
        processor.process();
        processor.write();
    }
}
