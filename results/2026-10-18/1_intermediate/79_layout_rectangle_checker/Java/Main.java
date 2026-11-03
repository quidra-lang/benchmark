import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Locale;
import java.util.TreeMap;
import java.util.TreeSet;

public class Main {
    static class Problem extends RuntimeException {
        Problem(String message) {
            super("error: " + message);
        }
    }

    record Box(int x1, int y1, int x2, int y2) {
        int width() {
            return x2 - x1;
        }

        int height() {
            return y2 - y1;
        }

        long area() {
            return (long)width() * height();
        }

        public String toString() {
            return "(" + x1 + "," + y1 + ")-(" + x2 + "," + y2 + ")";
        }

        Box shift(int dx, int dy) {
            return new Box(x1 + dx, y1 + dy, x2 + dx, y2 + dy);
        }

        boolean contains(Box b) {
            return x1 <= b.x1 && y1 <= b.y1 && x2 >= b.x2 && y2 >= b.y2;
        }
    }

    record Rectangle(String name, String layer, Box box) { }

    record Saved(TreeMap<String, Rectangle> rectangles, String command) { }

    record Rule(String kind, String inner, String outer, int value) { }

    record Violation(Rectangle a, Rectangle b, int gap, String direction) { }

    record Interval(int left, int right) { }

    record Hole(long area, Box box, int anchorX, int anchorY) { }

    static class Relation {
        Box common;
        int ox, oy, gap, kind;
        String direction;

        Relation(Rectangle a, Rectangle b) {
            Box x = a.box, y = b.box;
            common = new Box(Math.max(x.x1, y.x1), Math.max(x.y1, y.y1), Math.min(x.x2, y.x2), Math.min(x.y2, y.y2));
            ox = common.width();
            oy = common.height();
            gap = Math.max(0, Math.max(-ox, -oy));
            kind = ox < 0 || oy < 0 ? 3 : ox > 0 && oy > 0 ? 0 : ox == 0 && oy == 0 ? 2 : 1;
            direction = kind == 2 ? "corner" : ox < 0 && oy < 0 ? "diagonal" : ox < 0 ? "x" : "y";
        }

        boolean connected() {
            return kind <= 1;
        }
    }

    static class Grid {
        int[] xs, ys;
        int[][] counts;

        Grid(List<Rectangle> rectangles) {
            TreeSet<Integer> x = new TreeSet<>(), y = new TreeSet<>();
            for (Rectangle r : rectangles) {
                x.add(r.box.x1);
                x.add(r.box.x2);
                y.add(r.box.y1);
                y.add(r.box.y2);
            }
            xs = x.stream().mapToInt(Integer::intValue).toArray();
            ys = y.stream().mapToInt(Integer::intValue).toArray();
            counts = new int[ys.length - 1][xs.length - 1];
            for (Rectangle r : rectangles) for (int j = 0; j < counts.length; j++) if (ys[j] >= r.box.y1 && ys[j + 1] <= r.box.y2) for (int i = 0; i < counts[j].length; i++) if (xs[i] >= r.box.x1 && xs[i + 1] <= r.box.x2) counts[j][i]++;
        }

        Box bounds() {
            return new Box(xs[0], ys[0], xs[xs.length - 1], ys[ys.length - 1]);
        }

        long area(int threshold) {
            long result = 0;
            for (int j = 0; j < counts.length; j++) for (int i = 0; i < counts[j].length; i++) if (counts[j][i] >= threshold) result += (long)(xs[i + 1] - xs[i]) * (ys[j + 1] - ys[j]);
            return result;
        }

        long clipped(Box b) {
            long result = 0;
            for (int j = 0; j < counts.length; j++) for (int i = 0; i < counts[j].length; i++) if (counts[j][i] > 0) result += (long)Math.max(0, Math.min(xs[i + 1], b.x2) - Math.max(xs[i], b.x1)) * Math.max(0, Math.min(ys[j + 1], b.y2) - Math.max(ys[j], b.y1));
            return result;
        }

        long perimeter() {
            long result = 0;
            for (int j = 0; j < counts.length; j++) for (int i = 0; i < counts[j].length; i++) if (counts[j][i] > 0) {
                if (i == 0 || counts[j][i - 1] == 0) result += ys[j + 1] - ys[j];
                if (i + 1 == counts[j].length || counts[j][i + 1] == 0) result += ys[j + 1] - ys[j];
                if (j == 0 || counts[j - 1][i] == 0) result += xs[i + 1] - xs[i];
                if (j + 1 == counts.length || counts[j + 1][i] == 0) result += xs[i + 1] - xs[i];
            }
            return result;
        }

        Box empty() {
            Box best = null;
            for (int left = 0; left + 1 < xs.length; left++) {
                boolean[] blocked = new boolean[counts.length];
                for (int right = left + 1; right < xs.length; right++) {
                    for (int j = 0; j < counts.length; j++) blocked[j] |= counts[j][right - 1] > 0;
                    int bottom = 0;
                    while (bottom < counts.length) {
                        if (blocked[bottom]) {
                            bottom++;
                            continue;
                        }
                        int top = bottom + 1;
                        while (top < counts.length && !blocked[top]) top++;
                        Box candidate = new Box(xs[left], ys[bottom], xs[right], ys[top]);
                        if (best == null || candidate.area() > best.area() || candidate.area() == best.area() && (candidate.x1 < best.x1 || candidate.x1 == best.x1 && (candidate.y1 < best.y1 || candidate.y1 == best.y1 && candidate.width() < best.width()))) best = candidate;
                        bottom = top;
                    }
                }
            }
            return best;
        }

        List<Hole> holes() {
            boolean[][] seen = new boolean[counts.length][xs.length - 1];
            List<Hole> result = new ArrayList<>();
            int[] dx = {-1, 1, 0, 0}, dy = {0, 0, -1, 1};
            for (int j = 0; j < counts.length; j++) for (int i = 0; i < counts[j].length; i++) if (counts[j][i] == 0 && !seen[j][i]) {
                ArrayDeque<int[]> queue = new ArrayDeque<>();
                queue.add(new int[]{i, j});
                seen[j][i] = true;
                boolean boundary = false;
                long area = 0;
                int x1 = xs[i], y1 = ys[j], x2 = xs[i + 1], y2 = ys[j + 1], ax = xs[i], ay = ys[j];
                while (!queue.isEmpty()) {
                    int[] cell = queue.remove();
                    int x = cell[0], y = cell[1];
                    boundary |= x == 0 || y == 0 || x + 1 == xs.length - 1 || y + 1 == counts.length;
                    area += (long)(xs[x + 1] - xs[x]) * (ys[y + 1] - ys[y]);
                    x1 = Math.min(x1, xs[x]);
                    y1 = Math.min(y1, ys[y]);
                    x2 = Math.max(x2, xs[x + 1]);
                    y2 = Math.max(y2, ys[y + 1]);
                    if (ys[y] < ay || ys[y] == ay && xs[x] < ax) {
                        ax = xs[x];
                        ay = ys[y];
                    }
                    for (int d = 0; d < 4; d++) {
                        int xx = x + dx[d], yy = y + dy[d];
                        if (xx >= 0 && xx + 1 < xs.length && yy >= 0 && yy < counts.length && counts[yy][xx] == 0 && !seen[yy][xx]) {
                            seen[yy][xx] = true;
                            queue.add(new int[]{xx, yy});
                        }
                    }
                }
                if (!boundary) result.add(new Hole(area, new Box(x1, y1, x2, y2), ax, ay));
            }
            result.sort(Comparator.comparingInt(Hole::anchorY).thenComparingInt(Hole::anchorX));
            return result;
        }

        List<Box> pieces() {
            Map<Interval, Box> active = new HashMap<>();
            List<Box> result = new ArrayList<>();
            for (int j = 0; j < counts.length; j++) {
                Map<Interval, Box> next = new HashMap<>();
                int i = 0;
                while (i + 1 < xs.length) {
                    if (counts[j][i] == 0) {
                        i++;
                        continue;
                    }
                    int right = i + 1;
                    while (right + 1 < xs.length && counts[j][right] > 0) right++;
                    Interval key = new Interval(xs[i], xs[right]);
                    Box old = active.remove(key);
                    next.put(key, new Box(xs[i], old == null ? ys[j] : old.y1, xs[right], ys[j + 1]));
                    i = right;
                }
                result.addAll(active.values());
                active = next;
            }
            result.addAll(active.values());
            result.sort(Comparator.comparingInt(Box::y1).thenComparingInt(Box::x1));
            return result;
        }
    }
    TreeMap<String, Rectangle> rectangles = new TreeMap<>();
    List<Saved> history = new ArrayList<>();
    TreeMap<String, Rule> rules = new TreeMap<>();

    static void fail(String message) {
        throw new Problem(message);
    }

    Rectangle get(String name) {
        Rectangle r = rectangles.get(name);
        if (r == null) fail("unknown rectangle " + name);
        return r;
    }

    List<Rectangle> layer(String name, boolean required) {
        List<Rectangle> result = rectangles.values().stream().filter(r -> r.layer.equals(name)).toList();
        if (required && result.isEmpty()) fail("no rectangles on " + name);
        return result;
    }

    static void bounds(Box b) {
        if (b.x1 < -10000 || b.y1 < -10000 || b.x2 > 10000 || b.y2 > 10000 || b.x1 > 10000 || b.y1 > 10000 || b.x2 < -10000 || b.y2 < -10000) fail("out of bounds");
    }

    void save(String line) {
        history.add(new Saved(new TreeMap<>(rectangles), line));
    }

    static String names(List<Rectangle> list) {
        return list.isEmpty() ? "none" : String.join(" ", list.stream().map(Rectangle::name).sorted().toList());
    }

    static String decimal(long scaled) {
        return scaled / 100 + "." + (scaled % 100 < 10 ? "0" : "") + scaled % 100;
    }

    static String density(long area, long total) {
        return decimal(10000L * area / total);
    }

    static int margin(Rectangle outer, Rectangle inner) {
        return Math.min(Math.min(inner.box.x1 - outer.box.x1, inner.box.y1 - outer.box.y1), Math.min(outer.box.x2 - inner.box.x2, outer.box.y2 - inner.box.y2));
    }

    static List<List<Rectangle>> nets(List<Rectangle> list) {
        boolean[] seen = new boolean[list.size()];
        List<List<Rectangle>> result = new ArrayList<>();
        for (int start = 0; start < list.size(); start++) if (!seen[start]) {
            List<Rectangle> net = new ArrayList<>();
            ArrayDeque<Integer> queue = new ArrayDeque<>();
            queue.add(start);
            seen[start] = true;
            while (!queue.isEmpty()) {
                int i = queue.remove();
                net.add(list.get(i));
                for (int j = 0; j < list.size(); j++) if (!seen[j] && new Relation(list.get(i), list.get(j)).connected()) {
                    seen[j] = true;
                    queue.add(j);
                }
            }
            net.sort(Comparator.comparing(Rectangle::name));
            result.add(net);
        }
        return result;
    }

    static List<Violation> spacing(List<Rectangle> list, int s) {
        List<Violation> result = new ArrayList<>();
        for (int i = 0; i < list.size(); i++) for (int j = i + 1; j < list.size(); j++) {
            Relation relation = new Relation(list.get(i), list.get(j));
            if (relation.kind == 2 || relation.kind == 3 && relation.gap < s) result.add(new Violation(list.get(i), list.get(j), relation.gap, relation.direction));
        }
        result.sort(Comparator.comparingInt(Violation::gap).thenComparing(v -> v.a.name).thenComparing(v -> v.b.name));
        return result;
    }

    static String violation(Violation v) {
        return v.a.name + " " + v.b.name + " gap " + v.gap + " " + v.direction;
    }

    static String info(Rectangle r) {
        return r.name + " " + r.layer + " " + r.box + " " + r.box.width() + "x" + r.box.height();
    }

    List<String> command(String line) {
        String[] a = line.split(" ");
        String c = a[0];
        List<String> out = new ArrayList<>();
        switch (c) {
            case "ADD" -> {
                if (rectangles.containsKey(a[1])) fail("duplicate rectangle " + a[1]);
                Box b = new Box(Integer.parseInt(a[3]), Integer.parseInt(a[4]), Integer.parseInt(a[5]), Integer.parseInt(a[6]));
                if (b.x1 >= b.x2 || b.y1 >= b.y2) fail("invalid rectangle");
                bounds(b);
                save(line);
                rectangles.put(a[1], new Rectangle(a[1], a[2], b));
                out.add("added " + a[1] + " " + a[2] + " " + b);
            }
            case "COPY", "MOVE", "RESIZE", "SPLIT", "LAYER", "DELETE" -> {
                Rectangle r = get(a[1]);
                Box b = r.box;
                String layer = r.layer;
                Rectangle extra = null;
                switch (c) {
                    case "COPY" -> {
                        if (rectangles.containsKey(a[2])) fail("duplicate rectangle " + a[2]);
                        b = b.shift(Integer.parseInt(a[3]), Integer.parseInt(a[4]));
                        bounds(b);
                        extra = new Rectangle(a[2], layer, b);
                        out.add("copied " + r.name + " to " + a[2] + " " + b);
                    }
                    case "MOVE" -> {
                        b = b.shift(Integer.parseInt(a[2]), Integer.parseInt(a[3]));
                        bounds(b);
                        out.add("moved " + r.name + " to " + b);
                    }
                    case "RESIZE" -> {
                        int w = Integer.parseInt(a[2]), h = Integer.parseInt(a[3]);
                        if (w <= 0 || h <= 0) fail("invalid size");
                        b = new Box(b.x1, b.y1, b.x1 + w, b.y1 + h);
                        bounds(b);
                        out.add("resized " + r.name + " to " + b);
                    }
                    case "SPLIT" -> {
                        if (rectangles.containsKey(a[4])) fail("duplicate rectangle " + a[4]);
                        int pos = Integer.parseInt(a[3]);
                        boolean x = a[2].equals("x");
                        if (pos <= (x ? b.x1 : b.y1) || pos >= (x ? b.x2 : b.y2)) fail("cut outside " + r.name);
                        Box second = x ? new Box(pos, b.y1, b.x2, b.y2) : new Box(b.x1, pos, b.x2, b.y2);
                        b = x ? new Box(b.x1, b.y1, pos, b.y2) : new Box(b.x1, b.y1, b.x2, pos);
                        extra = new Rectangle(a[4], layer, second);
                        out.add("split " + r.name + " at " + a[2] + "=" + pos + ": " + r.name + " " + b + ", " + a[4] + " " + second);
                    }
                    case "LAYER" -> {
                        if (layer.equals(a[2])) fail("already on " + layer);
                        out.add("layer " + r.name + " " + layer + " -> " + a[2]);
                        layer = a[2];
                    }
                    case "DELETE" -> out.add("deleted " + r.name);
                    default -> throw new IllegalStateException();
                }
                save(line);
                if (c.equals("DELETE")) rectangles.remove(r.name);
                else if (!c.equals("COPY")) rectangles.put(r.name, new Rectangle(r.name, layer, b));
                if (extra != null) rectangles.put(extra.name, extra);
            }
            case "UNDO" -> {
                if (history.isEmpty()) fail("nothing to undo");
                Saved saved = history.removeLast();
                rectangles = saved.rectangles;
                out.add("undo: " + saved.command);
            }
            case "LIST" -> {
                out.add("rectangles: " + rectangles.size());
                for (Rectangle r : rectangles.values()) out.add(info(r));
            }
            case "INFO" -> {
                Rectangle r = get(a[1]);
                out.add(info(r) + " area " + r.box.area());
                String[] labels = {"overlaps", "touches", "corners", "encloses", "enclosed by"};
                for (int k = 0; k < labels.length; k++) {
                    List<Rectangle> list = new ArrayList<>();
                    for (Rectangle other : rectangles.values()) if (!r.name.equals(other.name)) {
                        Relation relation = new Relation(r, other);
                        if (k < 3 ? r.layer.equals(other.layer) && relation.kind == k : k == 3 ? r.box.contains(other.box) : other.box.contains(r.box)) list.add(other);
                    }
                    out.add(labels[k] + ": " + names(list));
                }
            }
            case "LAYERS" -> {
                TreeSet<String> layers = new TreeSet<>();
                for (Rectangle r : rectangles.values()) layers.add(r.layer);
                out.add("layers: " + layers.size());
                for (String name : layers) {
                    List<Rectangle> list = layer(name, true);
                    out.add(name + ": " + list.size() + " rectangles, area " + new Grid(list).area(1) + ", nets " + nets(list).size());
                }
            }
            case "OVERLAPS" -> {
                List<String> details = new ArrayList<>();
                TreeSet<String> layers = new TreeSet<>();
                if (a.length == 2) {
                    layer(a[1], true);
                    layers.add(a[1]);
                } else for (Rectangle r : rectangles.values()) layers.add(r.layer);
                for (String name : layers) {
                    List<Rectangle> list = layer(name, true);
                    for (int i = 0; i < list.size(); i++) for (int j = i + 1; j < list.size(); j++) {
                        Rectangle x = list.get(i), y = list.get(j);
                        Relation relation = new Relation(x, y);
                        if (relation.kind == 0) details.add((a.length == 1 ? name + " " : "") + x.name + " " + y.name + " " + relation.common + " area " + relation.common.area());
                    }
                }
                out.add("overlaps " + (a.length == 1 ? "all layers" : a[1]) + ": " + details.size());
                out.addAll(details);
            }
            case "INTERSECT", "ADJACENT", "ENCLOSE", "PATH" -> {
                Rectangle x = get(a[1]), y = get(a[2]);
                if (x.name.equals(y.name)) fail("same rectangle " + x.name);
                Relation relation = new Relation(x, y);
                String prefix = c.toLowerCase(Locale.ROOT) + " " + x.name + " " + y.name + ": ";
                if (c.equals("PATH")) {
                    if (!x.layer.equals(y.layer)) fail("different layers");
                    List<Rectangle> list = layer(x.layer, true);
                    int start = list.indexOf(x), goal = list.indexOf(y);
                    int[] previous = new int[list.size()];
                    Arrays.fill(previous, -1);
                    previous[start] = start;
                    ArrayDeque<Integer> queue = new ArrayDeque<>();
                    queue.add(start);
                    while (!queue.isEmpty()) {
                        int i = queue.remove();
                        for (int j = 0; j < list.size(); j++) if (previous[j] < 0 && new Relation(list.get(i), list.get(j)).connected()) {
                            previous[j] = i;
                            queue.add(j);
                        }
                    }
                    List<String> path = new ArrayList<>();
                    if (previous[goal] >= 0) for (int at = goal;; at = previous[at]) {
                        path.add(0, list.get(at).name);
                        if (at == start) break;
                    }
                    out.add(prefix + (path.isEmpty() ? "none" : String.join(" -> ", path) + " (" + (path.size() - 1) + " steps)"));
                } else if (c.equals("ENCLOSE")) {
                    int left = y.box.x1 - x.box.x1, bottom = y.box.y1 - x.box.y1, right = x.box.x2 - y.box.x2, top = x.box.y2 - y.box.y2, min = margin(x, y);
                    out.add(prefix + (min >= 0 ? "yes" : "no") + ", margins left " + left + " bottom " + bottom + " right " + right + " top " + top + (min >= 0 ? ", min " + min : ""));
                } else if (c.equals("INTERSECT")) out.add(prefix + switch (relation.kind) {
                    case 0 -> relation.common + " area " + relation.common.area(); case 1 -> "segment " + relation.common + " length " + (relation.ox + relation.oy); case 2 -> "point (" + relation.common.x1 + "," + relation.common.y1 + ")"; default -> "none, gap " + relation.gap;
                });
                else out.add(prefix + switch (relation.kind) {
                    case 0 -> "overlapping"; case 1 -> x.name + " is " + (relation.ox == 0 ? x.box.x2 == relation.common.x1 ? "west" : "east" : x.box.y2 == relation.common.y1 ? "south" : "north") + " of " + y.name + ", edge " + relation.common + ", length " + (relation.ox + relation.oy); case 2 -> "corner only at (" + relation.common.x1 + "," + relation.common.y1 + ")"; default -> "not adjacent";
                });
            }
            case "AT" -> {
                int x = Integer.parseInt(a[1]), y = Integer.parseInt(a[2]);
                List<String> found = new ArrayList<>();
                for (Rectangle r : rectangles.values()) if (x >= r.box.x1 && x <= r.box.x2 && y >= r.box.y1 && y <= r.box.y2) {
                    boolean xx = x == r.box.x1 || x == r.box.x2, yy = y == r.box.y1 || y == r.box.y2;
                    found.add(r.name + " " + r.layer + " " + (xx && yy ? "corner" : xx || yy ? "edge" : "inside"));
                }
                out.add("at (" + x + "," + y + "): " + (found.isEmpty() ? "none" : String.join(", ", found)));
            }
            case "NEAREST" -> {
                Rectangle r = get(a[1]), best = null;
                int gap = Integer.MAX_VALUE;
                for (Rectangle other : layer(r.layer, true)) if (!r.name.equals(other.name)) {
                    int g = new Relation(r, other).gap;
                    if (g < gap) {
                        gap = g;
                        best = other;
                    }
                }
                out.add("nearest " + r.name + ": " + (best == null ? "none" : best.name + " gap " + gap));
            }
            case "RULE" -> {
                String kind = a[1].toLowerCase(Locale.ROOT), inner = a[2], outer = kind.equals("enclose") ? a[3] : "";
                int value = Integer.parseInt(a[kind.equals("enclose") ? 4 : 3]);
                if (kind.equals("enclose") && inner.equals(outer)) fail("same layer " + inner);
                rules.put(kind + " " + inner + " " + outer, new Rule(kind, inner, outer, value));
                out.add("rule " + kind + " " + inner + (outer.isEmpty() ? "" : " " + outer) + " " + value);
            }
            case "CHECK" -> {
                if (rules.isEmpty()) fail("no rules");
                int total = 0;
                for (Rule rule : rules.values()) {
                    List<String> violations = new ArrayList<>();
                    List<Rectangle> list = layer(rule.inner, false);
                    if (rule.kind.equals("spacing")) for (Violation v : spacing(list, rule.value)) violations.add(violation(v));
                    else if (rule.kind.equals("width")) for (Rectangle r : list) {
                        int width = Math.min(r.box.width(), r.box.height());
                        if (width < rule.value) violations.add(r.name + " width " + width);
                    } else {
                        List<Rectangle> outer = layer(rule.outer, false);
                        for (Rectangle r : list) {
                            Integer best = null;
                            for (Rectangle o : outer) best = best == null ? margin(o, r) : Math.max(best, margin(o, r));
                            if (best == null || best < rule.value) violations.add(r.name + " best margin " + (best == null ? "none" : best));
                        }
                    }
                    out.add(rule.kind + " " + rule.inner + (rule.outer.isEmpty() ? "" : " " + rule.outer) + " " + rule.value + ": " + violations.size() + " violations");
                    out.addAll(violations);
                    total += violations.size();
                }
                out.add("check: " + total + " violations in " + rules.size() + " rules");
            }
            default -> {
                String name = c.equals("COVER") ? a[2] : a[1];
                List<Rectangle> list = layer(name, true);
                Grid grid = new Grid(list);
                Box b = grid.bounds();
                switch (c) {
                    case "AREA" -> out.add("area " + name + ": " + grid.area(1));
                    case "COVER" -> out.add("cover " + name + " >= " + a[1] + ": " + grid.area(Integer.parseInt(a[1])));
                    case "PERIMETER" -> out.add("perimeter " + name + ": " + grid.perimeter());
                    case "NETS" -> {
                        List<List<Rectangle>> groups = nets(list);
                        out.add("nets " + name + ": " + groups.size());
                        for (int i = 0; i < groups.size(); i++) out.add("net " + (i + 1) + ": " + names(groups.get(i)) + " area " + new Grid(groups.get(i)).area(1));
                    }
                    case "DRC" -> {
                        int s = Integer.parseInt(a[2]);
                        List<Violation> violations = spacing(list, s);
                        out.add("drc " + name + " spacing " + s + ": " + violations.size() + " violations");
                        for (Violation v : violations) out.add(violation(v));
                    }
                    case "BBOX" -> out.add("bbox " + name + ": " + b + " " + b.width() + "x" + b.height() + ", " + list.size() + " rectangles, density " + density(grid.area(1), b.area()) + "%");
                    case "DENSITY" -> {
                        int w = Integer.parseInt(a[2]), columns = (b.width() + w - 1) / w, rows = (b.height() + w - 1) / w;
                        if (columns > 20 || rows > 20) fail("too many windows");
                        long[][] values = new long[rows][columns];
                        long min = Long.MAX_VALUE, max = -1;
                        int minX = 0, minY = 0, maxX = 0, maxY = 0;
                        for (int j = 0; j < rows; j++) for (int i = 0; i < columns; i++) {
                            values[j][i] = grid.clipped(new Box(b.x1 + i * w, b.y1 + j * w, b.x1 + (i + 1) * w, b.y1 + (j + 1) * w));
                            if (values[j][i] < min) {
                                min = values[j][i];
                                minX = i;
                                minY = j;
                            }
                            if (values[j][i] > max) {
                                max = values[j][i];
                                maxX = i;
                                maxY = j;
                            }
                        }
                        out.add("density " + name + " window " + w + ": " + columns + "x" + rows);
                        for (int j = rows - 1; j >= 0; j--) {
                            List<String> row = new ArrayList<>();
                            for (int i = 0; i < columns; i++) row.add(Long.toString(100L * values[j][i] / ((long)w * w)));
                            out.add(String.join(" ", row));
                        }
                        out.add("min " + density(min, (long)w * w) + "% at (" + (b.x1 + minX * w) + "," + (b.y1 + minY * w) + ")");
                        out.add("max " + density(max, (long)w * w) + "% at (" + (b.x1 + maxX * w) + "," + (b.y1 + maxY * w) + ")");
                    }
                    case "RENDER" -> {
                        Box window = new Box(Integer.parseInt(a[2]), Integer.parseInt(a[3]), Integer.parseInt(a[4]), Integer.parseInt(a[5]));
                        if (window.x1 >= window.x2 || window.y1 >= window.y2) fail("invalid window");
                        if (window.width() > 60 || window.height() > 40) fail("window too large");
                        out.add("render " + name + " " + window);
                        for (int y = window.y2 - 1; y >= window.y1; y--) {
                            StringBuilder row = new StringBuilder();
                            for (int x = window.x1; x < window.x2; x++) {
                                int count = 0;
                                for (Rectangle r : list) if (r.box.x1 <= x && x < r.box.x2 && r.box.y1 <= y && y < r.box.y2) count++;
                                row.append(count == 0 ? '.' : count < 10 ? (char)('0' + count) : '*');
                            }
                            out.add(row.toString());
                        }
                    }
                    case "EMPTY" -> {
                        Box empty = grid.empty();
                        out.add("empty " + name + ": " + (empty == null ? "none" : empty + " area " + empty.area()));
                    }
                    case "HOLES" -> {
                        List<Hole> holes = grid.holes();
                        out.add("holes " + name + ": " + holes.size());
                        for (int i = 0; i < holes.size(); i++) out.add("hole " + (i + 1) + ": area " + holes.get(i).area + ", bbox " + holes.get(i).box);
                    }
                    case "MERGE" -> {
                        List<Box> pieces = grid.pieces();
                        out.add("merge " + name + ": " + pieces.size() + " pieces");
                        for (Box piece : pieces) out.add(piece.toString());
                    }
                    default -> throw new IllegalStateException();
                }
            }
        }
        return out;
    }
    public static void main(String[] args) throws Exception {
        BufferedReader reader = new BufferedReader(new InputStreamReader(System.in));
        Main layout = new Main();
        int count = Integer.parseInt(reader.readLine());
        for (int i = 0; i < count; i++) {
            String line = reader.readLine();
            try {
                for (String row : layout.command(line)) System.out.println(row);
            } catch (Problem e) {
                System.out.println(e.getMessage());
            }
        }
    }
}
