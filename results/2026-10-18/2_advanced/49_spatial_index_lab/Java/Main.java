import java.io.IOException;
import java.util.*;

public final class Main {
    static final List<String> STRUCTURES =
        List.of("kdtree", "quadtree", "rtree", "str", "grid", "rtree_rect", "str_rect");
    static final List<String> SEARCHES =
        List.of("RANGE", "RADIUS", "KNN", "WINDOWCOUNT", "CONTAINS", "NEAREST", "JOIN");
    static Dataset.Data data;
    static SortedMap<Integer, Dataset.Obj> points = new TreeMap<>();
    static List<Dataset.Obj> rectangles;
    static Kdtree.Node kd;
    static Quadtree.Node quad;
    static Rtree.Tree rt, str, rectRt, rectStr;
    static Grid.Index grid;
    static int snapshot;
    static List<String> answers = new ArrayList<>(),
                        visits = new ArrayList<>(List.of("query,command,structure,nodes,tests")),
                        joins = new ArrayList<>(List.of("query,rect,point")), structures = new ArrayList<>(),
                        stats = new ArrayList<>();
    static List<Visit> records = new ArrayList<>();
    static final class View {
        int type, axis, level, count;
        String mark;
        Dataset.Box region;
        List<Dataset.Obj> held;
        List<View> children;
        View(int type, String mark, Dataset.Box region, List<Dataset.Obj> held, List<View> children, int axis,
             int level) {
            this.type = type;
            this.mark = mark;
            this.region = region;
            this.held = held;
            this.children = children;
            this.axis = axis;
            this.level = level;
            count = held.size();
            for (View child : children)
                count += child.count;
        }
    }
    static Dataset.Box world() {
        return new Dataset.Box(0, 0, data.world() - 1, data.world() - 1);
    }
    static View kdView(Kdtree.Node node, Dataset.Box box, String mark) {
        List<View> children = new ArrayList<>();
        long split = node.axis == 0 ? node.point.box().x1() : node.point.box().y1();
        if (node.left != null) {
            Dataset.Box region = node.axis == 0 ? new Dataset.Box(box.x1(), box.y1(), split, box.y2())
                                                : new Dataset.Box(box.x1(), box.y1(), box.x2(), split);
            children.add(kdView(node.left, region, "L"));
        }
        if (node.right != null) {
            Dataset.Box region = node.axis == 0 ? new Dataset.Box(split, box.y1(), box.x2(), box.y2())
                                                : new Dataset.Box(box.x1(), split, box.x2(), box.y2());
            children.add(kdView(node.right, region, "R"));
        }
        return new View(0, mark, box, List.of(node.point), children, node.axis, 0);
    }
    static View quadView(Quadtree.Node node, String mark) {
        List<View> children = new ArrayList<>();
        if (node.children != null)
            for (int i = 0; i < 4; i++)
                children.add(quadView(node.children[i], Quadtree.MARKS.get(i)));
        return new View(1, mark,
                        new Dataset.Box(node.x, node.y, node.x + node.size - 1, node.y + node.size - 1),
                        node.points, children, 0, 0);
    }
    static View rView(Rtree.Node node) {
        List<View> children = new ArrayList<>();
        List<Dataset.Obj> held = new ArrayList<>();
        for (Rtree.Entry entry : node.entries)
            if (node.level == 0)
                held.add(new Dataset.Obj(entry.id, entry.box));
            else
                children.add(rView(entry.child));
        return new View(2, "", node.box(), held, children, 0, node.level);
    }
    static View gridView() {
        List<View> children = new ArrayList<>();
        for (Grid.Cell cell : grid.cells) {
            long x = (long)cell.x * grid.size, y = (long)cell.y * grid.size;
            children.add(new View(3, "", new Dataset.Box(x, y, x + grid.size - 1, y + grid.size - 1),
                                  cell.points, new ArrayList<>(), 0, 0));
        }
        return new View(3, "", world(), new ArrayList<>(), children, 0, 0);
    }
    static List<View> roots() {
        return new ArrayList<>(List.of(kdView(kd, world(), "root"), quadView(quad, "root"), rView(rt.root),
                                       rView(str.root), gridView(), rView(rectRt.root), rView(rectStr.root)));
    }
    static long distance(long x, long y, Dataset.Box box) {
        long dx = x < box.x1()   ? box.x1() - x
                  : x > box.x2() ? x - box.x2()
                                 : 0,
             dy = y < box.y1()   ? box.y1() - y
                  : y > box.y2() ? y - box.y2()
                                 : 0;
        return dx * dx + dy * dy;
    }
    static Dataset.Box window(int[] p) {
        return new Dataset.Box(p[0], p[1], p[2], p[3]);
    }
    static boolean condition(String command, int[] p, Dataset.Box box, boolean region) {
        if (command.equals("RADIUS"))
            return distance(p[0], p[1], box) <= (long)p[2] * p[2];
        if (command.equals("CONTAINS"))
            return Rtree.contains(box, new Dataset.Box(p[0], p[1], p[0], p[1]));
        return region ? Rtree.intersects(box, window(p)) : Rtree.contains(window(p), box);
    }
    record Result(int id, long value) {}
    static final class Answer {
        List<Result> items = new ArrayList<>();
        long nodes, tests;
        int count;
    }
    static void conditional(View view, String command, int[] p, Answer answer) {
        answer.nodes++;
        answer.tests += view.held.size();
        for (Dataset.Obj object : view.held)
            if (condition(command, p, object.box(), false))
                answer.items.add(new Result(object.id(), 0));
        for (View child : view.children)
            if (condition(command, p, child.region, true))
                conditional(child, command, p, answer);
    }
    static void count(View view, Dataset.Box box, Answer answer) {
        answer.nodes++;
        if (Rtree.contains(box, view.region)) {
            answer.count += view.count;
            return;
        }
        answer.tests += view.held.size();
        for (Dataset.Obj object : view.held)
            if (Rtree.contains(box, object.box()))
                answer.count++;
        for (View child : view.children)
            if (Rtree.intersects(box, child.region))
                count(child, box, answer);
    }
    record Element(long distance, int kind, long tie, View node, Dataset.Obj object)
        implements Comparable<Element> {
        public int compareTo(Element other) {
            int c = Long.compare(distance, other.distance());
            if (c == 0)
                c = Integer.compare(kind, other.kind());
            return c != 0 ? c : Long.compare(tie, other.tie());
        }
    }
    static Answer nearest(View root, int[] p) {
        Answer answer = new Answer();
        SortedSet<Element> queue = new TreeSet<>();
        long serial = 0;
        queue.add(new Element(distance(p[0], p[1], root.region), 0, serial++, root, null));
        while (answer.items.size() < p[2]) {
            Element entry = queue.first();
            queue.remove(entry);
            if (entry.kind() == 1) {
                answer.items.add(new Result(entry.object().id(), entry.distance()));
                continue;
            }
            View node = entry.node();
            answer.nodes++;
            answer.tests += node.held.size();
            for (Dataset.Obj object : node.held)
                queue.add(new Element(distance(p[0], p[1], object.box()), 1, object.id(), null, object));
            for (View child : node.children)
                queue.add(new Element(distance(p[0], p[1], child.region), 0, serial++, child, null));
        }
        return answer;
    }
    static void join(View a, View b, Answer answer) {
        answer.nodes++;
        if (a.children.isEmpty() && b.children.isEmpty()) {
            answer.tests += (long)a.held.size() * b.held.size();
            for (Dataset.Obj point : a.held)
                for (Dataset.Obj rectangle : b.held)
                    if (Rtree.contains(rectangle.box(), point.box()))
                        answer.items.add(new Result(rectangle.id(), point.id()));
        } else if (a.children.isEmpty()) {
            for (View child : b.children)
                if (Rtree.intersects(a.region, child.region))
                    join(a, child, answer);
        } else if (b.children.isEmpty()) {
            for (View child : a.children)
                if (Rtree.intersects(child.region, b.region))
                    join(child, b, answer);
        } else
            for (View first : a.children)
                for (View second : b.children)
                    if (Rtree.intersects(first.region, second.region))
                        join(first, second, answer);
    }
    static void sortIds(Answer answer, boolean pairs) {
        answer.items.sort((a, b) -> {
            int c = Integer.compare(a.id(), b.id());
            return c != 0 || !pairs ? c : Long.compare(a.value(), b.value());
        });
    }
    static Answer search(View root, View rectangle, String command, int[] p) {
        Answer answer = new Answer();
        if (command.equals("KNN") || command.equals("NEAREST"))
            return nearest(root, p);
        if (command.equals("JOIN")) {
            join(root, rectangle, answer);
            sortIds(answer, true);
        } else if (command.equals("WINDOWCOUNT"))
            count(root, window(p), answer);
        else {
            conditional(root, command, p, answer);
            sortIds(answer, false);
        }
        return answer;
    }
    static Answer brute(String command, int[] p) {
        Answer answer = new Answer();
        if (command.equals("JOIN")) {
            for (Dataset.Obj rectangle : rectangles)
                for (Dataset.Obj point : points.values())
                    if (Rtree.contains(rectangle.box(), point.box()))
                        answer.items.add(new Result(rectangle.id(), point.id()));
            sortIds(answer, true);
            return answer;
        }
        List<Dataset.Obj> objects = command.equals("CONTAINS") || command.equals("NEAREST")
                                        ? rectangles
                                        : new ArrayList<>(points.values());
        if (command.equals("KNN") || command.equals("NEAREST")) {
            for (Dataset.Obj object : objects)
                answer.items.add(new Result(object.id(), distance(p[0], p[1], object.box())));
            answer.items.sort((a, b) -> {
                int c = Long.compare(a.value(), b.value());
                return c != 0 ? c : Integer.compare(a.id(), b.id());
            });
            answer.items = new ArrayList<>(answer.items.subList(0, p[2]));
            return answer;
        }
        for (Dataset.Obj object : objects)
            if (condition(command, p, object.box(), false)) {
                if (command.equals("WINDOWCOUNT"))
                    answer.count++;
                else
                    answer.items.add(new Result(object.id(), 0));
            }
        sortIds(answer, false);
        return answer;
    }
    record Visit(String command, int structure, long nodes, long tests) {}
    static void searches(int query, Dataset.Command command) {
        String name = command.name();
        int[] p = command.values();
        Answer expected = brute(name, p);
        List<View> roots = roots();
        List<Integer> performed = name.equals("JOIN") ? List.of(2, 3)
                                  : name.equals("CONTAINS") || name.equals("NEAREST")
                                      ? List.of(5, 6)
                                      : List.of(0, 1, 2, 3, 4);
        List<String> mismatch = new ArrayList<>();
        for (int index : performed) {
            View rect = name.equals("JOIN") ? roots.get(index == 2 ? 5 : 6) : null;
            Answer actual = search(roots.get(index), rect, name, p);
            if (name.equals("WINDOWCOUNT") ? actual.count != expected.count
                                           : !actual.items.equals(expected.items))
                mismatch.add(STRUCTURES.get(index));
            visits.add(query + "," + name + "," + STRUCTURES.get(index) + "," + actual.nodes + "," +
                       actual.tests);
            records.add(new Visit(name, index, actual.nodes, actual.tests));
        }
        String check = mismatch.isEmpty() ? "ok" : "mismatch " + String.join(" ", mismatch);
        if (name.equals("JOIN")) {
            answers.add(query + " JOIN count " + expected.items.size() + " check " + check);
            for (Result result : expected.items)
                joins.add(query + "," + result.id() + "," + result.value());
        } else if (name.equals("WINDOWCOUNT"))
            answers.add(query + " WINDOWCOUNT count " + expected.count + " check " + check);
        else {
            List<String> ids = new ArrayList<>();
            boolean nearest = name.equals("KNN") || name.equals("NEAREST");
            for (Result result : expected.items)
                ids.add(result.id() + (nearest ? ":" + result.value() : ""));
            answers.add(query + " " + name + " count " + expected.items.size() + " ids " +
                        (ids.isEmpty() ? "-" : String.join(" ", ids)) + " check " + check);
        }
    }
    static String box(Dataset.Box b) {
        return b.x1() + " " + b.y1() + " " + b.x2() + " " + b.y2();
    }
    static void dump(View view, int depth, List<String> output) {
        String line = "  ".repeat(depth + 1);
        if (view.type == 0) {
            Dataset.Obj point = view.held.get(0);
            line += view.mark + " " + (view.axis == 0 ? "x" : "y") + " " + point.id() + " " +
                    point.box().x1() + " " + point.box().y1() + " box " + box(view.region);
        } else if (view.type == 1) {
            line += view.mark + " " + view.region.x1() + " " + view.region.y1() + " " +
                    (view.region.x2() - view.region.x1() + 1);
            line += view.children.isEmpty() ? " leaf " + Report.ids(view.held) : " node count " + view.count;
        } else
            line += view.children.isEmpty()
                        ? "leaf " + box(view.region) + " ids " + Report.ids(view.held)
                        : "node " + view.level + " " + box(view.region) + " entries " + view.children.size();
        output.add(line);
        for (View child : view.children)
            dump(child, depth + 1, output);
    }
    record AtDepth(View view, int depth) {}
    static void flatten(View view, int depth, List<AtDepth> result) {
        result.add(new AtDepth(view, depth));
        for (View child : view.children)
            flatten(child, depth + 1, result);
    }
    static List<AtDepth> flat(View view) {
        List<AtDepth> result = new ArrayList<>();
        flatten(view, 0, result);
        return result;
    }
    static void kdStats(View root) {
        List<AtDepth> nodes = flat(root);
        int height = 0, leaves = 0, one = 0, ideal = 0, capacity = 0;
        long depthSum = 0;
        for (AtDepth node : nodes) {
            height = Math.max(height, node.depth() + 1);
            depthSum += node.depth();
            if (node.view().children.isEmpty())
                leaves++;
            if (node.view().children.size() == 1)
                one++;
        }
        while (capacity < nodes.size()) {
            capacity = 2 * capacity + 1;
            ideal++;
        }
        stats.add("kdtree height " + height + " ideal " + ideal + " nodes " + nodes.size() + " leaves " +
                  leaves + " one_child " + one + " depth_sum " + depthSum + " avg_depth " +
                  Report.fraction(depthSum, nodes.size()));
        for (int depth = 0; depth < height; depth++) {
            int count = 0, leaf = 0, single = 0;
            for (AtDepth node : nodes)
                if (node.depth() == depth) {
                    count++;
                    if (node.view().children.isEmpty())
                        leaf++;
                    if (node.view().children.size() == 1)
                        single++;
                }
            stats.add("  depth " + depth + " nodes " + count + " leaves " + leaf + " one_child " + single);
        }
    }
    static void quadStats(View root) {
        List<AtDepth> nodes = flat(root);
        int height = 0, internal = 0, leaves = 0, empty = 0, max = 0;
        for (AtDepth node : nodes) {
            height = Math.max(height, node.depth() + 1);
            if (node.view().children.isEmpty()) {
                leaves++;
                if (node.view().held.isEmpty())
                    empty++;
                max = Math.max(max, node.view().held.size());
            } else
                internal++;
        }
        stats.add("quadtree height " + height + " internal " + internal + " leaves " + leaves + " empty " +
                  empty + " max_leaf " + max + " fill " +
                  Report.fraction(points.size(), (long)leaves * data.bucket()));
        for (int depth = 0; depth < height; depth++) {
            int inside = 0, leaf = 0, held = 0;
            for (AtDepth node : nodes)
                if (node.depth() == depth) {
                    if (node.view().children.isEmpty()) {
                        leaf++;
                        held += node.view().held.size();
                    } else
                        inside++;
                }
            stats.add("  depth " + depth + " internal " + inside + " leaves " + leaf + " points " + held);
        }
    }
    static void rStats(String name, View root) {
        List<AtDepth> nodes = flat(root);
        int leaves = 0, entries = 0;
        for (AtDepth node : nodes) {
            if (node.view().children.isEmpty())
                leaves++;
            entries += node.view().children.isEmpty() ? node.view().held.size() : node.view().children.size();
        }
        stats.add(name + " height " + (root.level + 1) + " nodes " + nodes.size() + " leaves " + leaves +
                  " entries " + entries + " fill " +
                  Report.fraction(entries, (long)nodes.size() * data.maximum()));
        for (int level = root.level; level >= 0; level--) {
            List<View> group = new ArrayList<>();
            for (AtDepth node : nodes)
                if (node.view().level == level)
                    group.add(node.view());
            int total = 0, min = Integer.MAX_VALUE, max = 0, under = 0;
            long area = 0, overlap = 0;
            for (View node : group) {
                int count = node.children.isEmpty() ? node.held.size() : node.children.size();
                total += count;
                min = Math.min(min, count);
                max = Math.max(max, count);
                if (count < data.minimum())
                    under++;
                area += Rtree.area(node.region);
            }
            for (int i = 0; i < group.size(); i++)
                for (int j = i + 1; j < group.size(); j++)
                    overlap += Rtree.overlap(group.get(i).region, group.get(j).region);
            stats.add("  level " + level + " nodes " + group.size() + " entries " + total + " min " + min +
                      " max " + max + " under " + under + " area " + area + " overlap " + overlap);
        }
    }
    static void gridStats() {
        SortedMap<Integer, Integer> occupancy = new TreeMap<>();
        int used = 0, max = 0;
        for (Grid.Cell cell : grid.cells) {
            int count = cell.points.size();
            if (count > 0)
                used++;
            max = Math.max(max, count);
            occupancy.put(count, occupancy.getOrDefault(count, 0) + 1);
        }
        stats.add("grid cells " + grid.cells.size() + " used " + used + " max " + max);
        String line = "  occupancy";
        for (int count : occupancy.keySet())
            line += " " + count + ":" + occupancy.get(count);
        stats.add(line);
    }
    static void snapshot(int query) {
        if (!structures.isEmpty()) {
            structures.add("");
            stats.add("");
        }
        String header = "snapshot " + snapshot + " query " + query + " points " + points.size() + " rects " +
                        rectangles.size();
        structures.add(header);
        stats.add(header);
        List<View> roots = roots();
        for (int i : List.of(0, 1, 2, 3, 5, 6)) {
            structures.add(STRUCTURES.get(i));
            dump(roots.get(i), 0, structures);
        }
        kdStats(roots.get(0));
        quadStats(roots.get(1));
        for (int i : List.of(2, 3, 5, 6))
            rStats(STRUCTURES.get(i), roots.get(i));
        gridStats();
    }
    static List<Integer> rPosition(Rtree.Node node, int id) {
        if (node.level == 0) {
            for (int i = 0; i < node.entries.size(); i++)
                if (node.entries.get(i).id == id)
                    return new ArrayList<>(List.of(i + 1));
        } else
            for (int i = 0; i < node.entries.size(); i++) {
                List<Integer> found = rPosition(node.entries.get(i).child, id);
                if (found != null) {
                    found.add(0, i + 1);
                    return found;
                }
            }
        return null;
    }
    static String positions(List<Integer> positions) {
        List<String> words = new ArrayList<>();
        for (int value : positions)
            words.add(Integer.toString(value));
        return String.join("/", words);
    }
    static String locate(Dataset.Obj point) {
        String path = "";
        Kdtree.Node node = kd;
        while (node.point.id() != point.id()) {
            if (Kdtree.compare(point, node.point, node.axis) < 0) {
                path += "L";
                node = node.left;
            } else {
                path += "R";
                node = node.right;
            }
        }
        List<String> moves = new ArrayList<>();
        Quadtree.Node q = quad;
        while (q.children != null) {
            int child = Quadtree.destination(q, point);
            moves.add(Quadtree.MARKS.get(child));
            q = q.children[child];
        }
        return "kdtree " + (path.isEmpty() ? "-" : path) + " quadtree " +
            (moves.isEmpty() ? "-" : String.join("/", moves)) + " rtree " +
            positions(rPosition(rt.root, point.id())) + " str " + positions(rPosition(str.root, point.id())) +
            " grid " + (point.box().x1() / grid.size) + " " + (point.box().y1() / grid.size);
    }
    static void process(int query, Dataset.Command command) {
        String name = command.name();
        int[] p = command.values();
        if (SEARCHES.contains(name)) {
            searches(query, command);
            return;
        }
        if (name.equals("DUMP")) {
            snapshot++;
            snapshot(query);
            answers.add(query + " DUMP snapshot " + snapshot);
            return;
        }
        int id = p[0];
        Dataset.Obj point = points.get(id);
        if (name.equals("LOCATE")) {
            answers.add(query + " LOCATE " + id + " " + (point == null ? "missing" : locate(point)));
            return;
        }
        if (name.equals("INSERT")) {
            point = Dataset.point(id, p[1], p[2]);
            points.put(id, point);
            kd = Kdtree.insert(kd, point, 0);
            Quadtree.insert(quad, point, data.bucket());
            rt.insert(new Rtree.Entry(point), 0);
            str.insert(new Rtree.Entry(point), 0);
            grid.insert(point);
            answers.add(query + " INSERT " + id + " inserted points " + points.size());
            return;
        }
        if (point == null)
            answers.add(query + " DELETE " + id + " missing points " + points.size());
        else {
            kd = Kdtree.delete(kd, point);
            Quadtree.delete(quad, point, data.bucket());
            rt.delete(point);
            str.delete(point);
            grid.delete(point);
            points.remove(id);
            answers.add(query + " DELETE " + id + " deleted points " + points.size());
        }
    }
    static final class Aggregate {
        int executions;
        long nodes, tests, maximum;
    }
    static void visitSummary() {
        stats.add("");
        stats.add("visits");
        for (String command : SEARCHES) {
            Map<Integer, Aggregate> totals = new TreeMap<>();
            for (Visit visit : records)
                if (visit.command().equals(command)) {
                    Aggregate aggregate = totals.computeIfAbsent(visit.structure(), key -> new Aggregate());
                    aggregate.executions++;
                    aggregate.nodes += visit.nodes();
                    aggregate.tests += visit.tests();
                    aggregate.maximum = Math.max(aggregate.maximum, visit.nodes());
                }
            if (totals.isEmpty())
                continue;
            for (int index : totals.keySet()) {
                Aggregate a = totals.get(index);
                stats.add(command + " " + STRUCTURES.get(index) + " queries " + a.executions + " nodes " +
                          a.nodes + " tests " + a.tests + " max_nodes " + a.maximum + " mean_nodes " +
                          Report.fraction(a.nodes, a.executions));
            }
            List<Integer> ranked = new ArrayList<>(totals.keySet());
            ranked.sort((a, b) -> {
                Aggregate x = totals.get(a), y = totals.get(b);
                int c = Long.compare(x.nodes, y.nodes);
                if (c == 0)
                    c = Long.compare(x.tests, y.tests);
                return c != 0 ? c : Integer.compare(a, b);
            });
            String line = "rank " + command;
            for (int index : ranked)
                line += " " + STRUCTURES.get(index);
            stats.add(line);
        }
    }
    public static void main(String[] args) throws IOException {
        data = Dataset.read();
        for (Dataset.Obj point : data.points())
            points.put(point.id(), point);
        rectangles = new ArrayList<>(data.rectangles());
        rectangles.sort(Comparator.comparingInt(Dataset.Obj::id));
        kd = Kdtree.build(data.points(), 0);
        quad = new Quadtree.Node(0, 0, data.world());
        grid = new Grid.Index(data.world(), data.grid());
        for (Dataset.Obj point : data.points()) {
            Quadtree.insert(quad, point, data.bucket());
            grid.insert(point);
        }
        rt = Rtree.build(data.points(), data.maximum(), data.minimum(), false);
        str = Rtree.build(data.points(), data.maximum(), data.minimum(), true);
        rectRt = Rtree.build(data.rectangles(), data.maximum(), data.minimum(), false);
        rectStr = Rtree.build(data.rectangles(), data.maximum(), data.minimum(), true);
        snapshot(0);
        for (int q = 0; q < data.commands().size(); q++)
            process(q + 1, data.commands().get(q));
        visitSummary();
        Report.write("answers.txt", answers);
        Report.write("visits.csv", visits);
        Report.write("join.csv", joins);
        Report.write("structures.txt", structures);
        Report.write("stats.txt", stats);
    }
}
