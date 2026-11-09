using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Program {
    public static readonly List<string> STRUCTURES =
        public["kdtree", "quadtree", "rtree", "str", "grid", "rtree_rect", "str_rect"];
    public static readonly List<string> SEARCHES =
        public["RANGE", "RADIUS", "KNN", "WINDOWCOUNT", "CONTAINS", "NEAREST", "JOIN"];
    public static Dataset.Data data;
    public static SortedDictionary<int, Dataset.Obj> points = new();
    public static List<Dataset.Obj> rectangles;
    public static Kdtree.Node kd;
    public static Quadtree.Node quad;
    public static Rtree.Tree rt, str, rectRt, rectStr;
    public static Grid.Index grid;
    public static int snapshot;
    public static List<string> answers = new(), visits = new(["query,command,structure,nodes,tests"]),
                               joins = new(["query,rect,point"]), structures = new(), stats = new();
    public static List<Visit> records = new();
    public sealed class View {
        public int type, axis, level, count;
        public string mark;
        public Dataset.Box region;
        public List<Dataset.Obj> held;
        public List<View> children;
        public View(int type, string mark, Dataset.Box region, List<Dataset.Obj> held, List<View> children,
                    int axis, int level) {
            this.type = type;
            this.mark = mark;
            this.region = region;
            this.held = held;
            this.children = children;
            this.axis = axis;
            this.level = level;
            count = held.Count;
            foreach (View child in children)
                count += child.count;
        }
    }
    public static Dataset.Box World() {
        return new Dataset.Box(0, 0, data.world - 1, data.world - 1);
    }
    public static View KdView(Kdtree.Node node, Dataset.Box box, string mark) {
        List<View> children = new();
        long split = node.axis == 0 ? node.point.box.x1 : node.point.box.y1;
        if (node.left != null) {
            Dataset.Box region = node.axis == 0 ? new Dataset.Box(box.x1, box.y1, split, box.y2)
                                                : new Dataset.Box(box.x1, box.y1, box.x2, split);
            children.Add(KdView(node.left, region, "L"));
        }
        if (node.right != null) {
            Dataset.Box region = node.axis == 0 ? new Dataset.Box(split, box.y1, box.x2, box.y2)
                                                : new Dataset.Box(box.x1, split, box.x2, box.y2);
            children.Add(KdView(node.right, region, "R"));
        }
        return new View(0, mark, box, [node.point], children, node.axis, 0);
    }
    public static View QuadView(Quadtree.Node node, string mark) {
        List<View> children = new();
        if (node.children != null)
            for (int i = 0; i < 4; i++)
                children.Add(QuadView(node.children[i], Quadtree.MARKS[i]));
        return new View(1, mark,
                        new Dataset.Box(node.x, node.y, node.x + node.size - 1, node.y + node.size - 1),
                        node.points, children, 0, 0);
    }
    public static View RView(Rtree.Node node) {
        List<View> children = new();
        List<Dataset.Obj> held = new();
        foreach (Rtree.Entry entry in node.entries)
            if (node.level == 0)
                held.Add(new Dataset.Obj(entry.id, entry.box));
            else
                children.Add(RView(entry.child));
        return new View(2, "", node.Box(), held, children, 0, node.level);
    }
    public static View GridView() {
        List<View> children = new();
        foreach (Grid.Cell cell in grid.cells) {
            long x = (long)cell.x * grid.size, y = (long)cell.y * grid.size;
            children.Add(new View(3, "", new Dataset.Box(x, y, x + grid.size - 1, y + grid.size - 1),
                                  cell.points, new(), 0, 0));
        }
        return new View(3, "", World(), new(), children, 0, 0);
    }
    public static List<View> Roots() {
        return new([
            KdView(kd, World(), "root"), QuadView(quad, "root"), RView(rt.root), RView(str.root), GridView(),
            RView(rectRt.root), RView(rectStr.root)
        ]);
    }
    public static long Distance(long x, long y, Dataset.Box box) {
        long dx = x < box.x1   ? box.x1 - x
                  : x > box.x2 ? x - box.x2
                               : 0,
             dy = y < box.y1   ? box.y1 - y
                  : y > box.y2 ? y - box.y2
                               : 0;
        return dx * dx + dy * dy;
    }
    public static Dataset.Box Window(int[] p) {
        return new Dataset.Box(p[0], p[1], p[2], p[3]);
    }
    public static bool Condition(string command, int[] p, Dataset.Box box, bool region) {
        if (command.Equals("RADIUS"))
            return Distance(p[0], p[1], box) <= (long)p[2] * p[2];
        if (command.Equals("CONTAINS"))
            return Rtree.Contains(box, new Dataset.Box(p[0], p[1], p[0], p[1]));
        return region ? Rtree.Intersects(box, Window(p)) : Rtree.Contains(Window(p), box);
    }
    public record Result(int id, long value) {
    }
    public sealed class Answer {
        public List<Result> items = new();
        public long nodes, tests;
        public int count;
    }
    public static void Conditional(View view, string command, int[] p, Answer answer) {
        answer.nodes++;
        answer.tests += view.held.Count;
        foreach (Dataset.Obj obj in view.held)
            if (Condition(command, p, obj.box, false))
                answer.items.Add(new Result(obj.id, 0));
        foreach (View child in view.children)
            if (Condition(command, p, child.region, true))
                Conditional(child, command, p, answer);
    }
    public static void Count(View view, Dataset.Box box, Answer answer) {
        answer.nodes++;
        if (Rtree.Contains(box, view.region)) {
            answer.count += view.count;
            return;
        }
        answer.tests += view.held.Count;
        foreach (Dataset.Obj obj in view.held)
            if (Rtree.Contains(box, obj.box))
                answer.count++;
        foreach (View child in view.children)
            if (Rtree.Intersects(box, child.region))
                Count(child, box, answer);
    }
    public record Element(long distance, int kind, long tie, View node, Dataset.Obj obj) public
        : IComparable<Element> {
        public int CompareTo(Element other) {
            int c = distance.CompareTo(other.distance);
            if (c == 0)
                c = kind.CompareTo(other.kind);
            return c != 0 ? c : tie.CompareTo(other.tie);
        }
    }
    public static Answer Nearest(View root, int[] p) {
        Answer answer = new Answer();
        SortedSet<Element> queue = new();
        long serial = 0;
        queue.Add(new Element(Distance(p[0], p[1], root.region), 0, serial++, root, null));
        while (answer.items.Count < p[2]) {
            Element entry = queue.Min;
            queue.Remove(entry);
            if (entry.kind == 1) {
                answer.items.Add(new Result(entry.obj.id, entry.distance));
                continue;
            }
            View node = entry.node;
            answer.nodes++;
            answer.tests += node.held.Count;
            foreach (Dataset.Obj obj in node.held)
                queue.Add(new Element(Distance(p[0], p[1], obj.box), 1, obj.id, null, obj));
            foreach (View child in node.children)
                queue.Add(new Element(Distance(p[0], p[1], child.region), 0, serial++, child, null));
        }
        return answer;
    }
    public static void Join(View a, View b, Answer answer) {
        answer.nodes++;
        if (a.children.Count == 0 && b.children.Count == 0) {
            answer.tests += (long)a.held.Count * b.held.Count;
            foreach (Dataset.Obj point in a.held)
                foreach (Dataset.Obj rectangle in b.held)
                    if (Rtree.Contains(rectangle.box, point.box))
                        answer.items.Add(new Result(rectangle.id, point.id));
        } else if (a.children.Count == 0) {
            foreach (View child in b.children)
                if (Rtree.Intersects(a.region, child.region))
                    Join(a, child, answer);
        } else if (b.children.Count == 0) {
            foreach (View child in a.children)
                if (Rtree.Intersects(child.region, b.region))
                    Join(child, b, answer);
        } else
            foreach (View first in a.children)
                foreach (View second in b.children)
                    if (Rtree.Intersects(first.region, second.region))
                        Join(first, second, answer);
    }
    public static void SortIds(Answer answer, bool pairs) {
        answer.items.Sort((a, b) => {
            int c = a.id.CompareTo(b.id);
            return c != 0 || !pairs ? c : a.value.CompareTo(b.value);
        });
    }
    public static Answer Search(View root, View rectangle, string command, int[] p) {
        Answer answer = new Answer();
        if (command.Equals("KNN") || command.Equals("NEAREST"))
            return Nearest(root, p);
        if (command.Equals("JOIN")) {
            Join(root, rectangle, answer);
            SortIds(answer, true);
        } else if (command.Equals("WINDOWCOUNT"))
            Count(root, Window(p), answer);
        else {
            Conditional(root, command, p, answer);
            SortIds(answer, false);
        }
        return answer;
    }
    public static Answer Brute(string command, int[] p) {
        Answer answer = new Answer();
        if (command.Equals("JOIN")) {
            foreach (Dataset.Obj rectangle in rectangles)
                foreach (Dataset.Obj point in points.Values)
                    if (Rtree.Contains(rectangle.box, point.box))
                        answer.items.Add(new Result(rectangle.id, point.id));
            SortIds(answer, true);
            return answer;
        }
        List<Dataset.Obj> objects =
            command.Equals("CONTAINS") || command.Equals("NEAREST") ? rectangles : new(points.Values);
        if (command.Equals("KNN") || command.Equals("NEAREST")) {
            foreach (Dataset.Obj obj in objects)
                answer.items.Add(new Result(obj.id, Distance(p[0], p[1], obj.box)));
            answer.items.Sort((a, b) => {
                int c = a.value.CompareTo(b.value);
                return c != 0 ? c : a.id.CompareTo(b.id);
            });
            answer.items = new(answer.items.GetRange(0, p[2] - (0)));
            return answer;
        }
        foreach (Dataset.Obj obj in objects)
            if (Condition(command, p, obj.box, false)) {
                if (command.Equals("WINDOWCOUNT"))
                    answer.count++;
                else
                    answer.items.Add(new Result(obj.id, 0));
            }
        SortIds(answer, false);
        return answer;
    }
    public record Visit(string command, int structure, long nodes, long tests) {
    }
    public static void Searches(int query, Dataset.Command command) {
        string name = command.name;
        int[] p = command.values;
        Answer expected = Brute(name, p);
        List<View> roots = Roots();
        List<int> performed = name.Equals("JOIN")                                 ? [2, 3]
                              : name.Equals("CONTAINS") || name.Equals("NEAREST") ? [5, 6]
                                                                                  : [0, 1, 2, 3, 4];
        List<string> mismatch = new();
        foreach (int index in performed) {
            View rect = name.Equals("JOIN") ? roots[index == 2 ? 5 : 6] : null;
            Answer actual = Search(roots[index], rect, name, p);
            if (name.Equals("WINDOWCOUNT") ? actual.count != expected.count
                                           : !actual.items.SequenceEqual(expected.items))
                mismatch.Add(STRUCTURES[index]);
            visits.Add(query + "," + name + "," + STRUCTURES[index] + "," + actual.nodes + "," +
                       actual.tests);
            records.Add(new Visit(name, index, actual.nodes, actual.tests));
        }
        string check = mismatch.Count == 0 ? "ok" : "mismatch " + string.Join(" ", mismatch);
        if (name.Equals("JOIN")) {
            answers.Add(query + " JOIN count " + expected.items.Count + " check " + check);
            foreach (Result result in expected.items)
                joins.Add(query + "," + result.id + "," + result.value);
        } else if (name.Equals("WINDOWCOUNT"))
            answers.Add(query + " WINDOWCOUNT count " + expected.count + " check " + check);
        else {
            List<string> ids = new();
            bool nearest = name.Equals("KNN") || name.Equals("NEAREST");
            foreach (Result result in expected.items)
                ids.Add(result.id + (nearest ? ":" + result.value : ""));
            answers.Add(query + " " + name + " count " + expected.items.Count + " ids " +
                        (ids.Count == 0 ? "-" : string.Join(" ", ids)) + " check " + check);
        }
    }
    public static string Box(Dataset.Box b) {
        return b.x1 + " " + b.y1 + " " + b.x2 + " " + b.y2;
    }
    public static void Dump(View view, int depth, List<string> output) {
        string line = "  ".Repeat(depth + 1);
        if (view.type == 0) {
            Dataset.Obj point = view.held[0];
            line += view.mark + " " + (view.axis == 0 ? "x" : "y") + " " + point.id + " " + point.box.x1 +
                    " " + point.box.y1 + " box " + Box(view.region);
        } else if (view.type == 1) {
            line += view.mark + " " + view.region.x1 + " " + view.region.y1 + " " +
                    (view.region.x2 - view.region.x1 + 1);
            line += view.children.Count == 0 ? " leaf " + Report.Ids(view.held) : " node count " + view.count;
        } else
            line += view.children.Count == 0
                        ? "leaf " + Box(view.region) + " ids " + Report.Ids(view.held)
                        : "node " + view.level + " " + Box(view.region) + " entries " + view.children.Count;
        output.Add(line);
        foreach (View child in view.children)
            Dump(child, depth + 1, output);
    }
    public record AtDepth(View view, int depth) {
    }
    public static void Flatten(View view, int depth, List<AtDepth> result) {
        result.Add(new AtDepth(view, depth));
        foreach (View child in view.children)
            Flatten(child, depth + 1, result);
    }
    public static List<AtDepth> Flat(View view) {
        List<AtDepth> result = new();
        Flatten(view, 0, result);
        return result;
    }
    public static void KdStats(View root) {
        List<AtDepth> nodes = Flat(root);
        int height = 0, leaves = 0, one = 0, ideal = 0, capacity = 0;
        long depthSum = 0;
        foreach (AtDepth node in nodes) {
            height = Math.Max(height, node.depth + 1);
            depthSum += node.depth;
            if (node.view.children.Count == 0)
                leaves++;
            if (node.view.children.Count == 1)
                one++;
        }
        while (capacity < nodes.Count) {
            capacity = 2 * capacity + 1;
            ideal++;
        }
        stats.Add("kdtree height " + height + " ideal " + ideal + " nodes " + nodes.Count + " leaves " +
                  leaves + " one_child " + one + " depth_sum " + depthSum + " avg_depth " +
                  Report.Fraction(depthSum, nodes.Count));
        for (int depth = 0; depth < height; depth++) {
            int count = 0, leaf = 0, single = 0;
            foreach (AtDepth node in nodes)
                if (node.depth == depth) {
                    count++;
                    if (node.view.children.Count == 0)
                        leaf++;
                    if (node.view.children.Count == 1)
                        single++;
                }
            stats.Add("  depth " + depth + " nodes " + count + " leaves " + leaf + " one_child " + single);
        }
    }
    public static void QuadStats(View root) {
        List<AtDepth> nodes = Flat(root);
        int height = 0, internal = 0, leaves = 0, empty = 0, max = 0;
        foreach (AtDepth node in nodes) {
            height = Math.Max(height, node.depth + 1);
            if (node.view.children.Count == 0) {
                leaves++;
                if (node.view.held.Count == 0)
                    empty++;
                max = Math.Max(max, node.view.held.Count);
            } else
                internal++;
        }
        stats.Add("quadtree height " + height + " internal " + internal + " leaves " + leaves + " empty " +
                  empty + " max_leaf " + max + " fill " +
                  Report.Fraction(points.Count, (long)leaves * data.bucket));
        for (int depth = 0; depth < height; depth++) {
            int inside = 0, leaf = 0, held = 0;
            foreach (AtDepth node in nodes)
                if (node.depth == depth) {
                    if (node.view.children.Count == 0) {
                        leaf++;
                        held += node.view.held.Count;
                    } else
                        inside++;
                }
            stats.Add("  depth " + depth + " internal " + inside + " leaves " + leaf + " points " + held);
        }
    }
    public static void RStats(string name, View root) {
        List<AtDepth> nodes = Flat(root);
        int leaves = 0, entries = 0;
        foreach (AtDepth node in nodes) {
            if (node.view.children.Count == 0)
                leaves++;
            entries += node.view.children.Count == 0 ? node.view.held.Count : node.view.children.Count;
        }
        stats.Add(name + " height " + (root.level + 1) + " nodes " + nodes.Count + " leaves " + leaves +
                  " entries " + entries + " fill " +
                  Report.Fraction(entries, (long)nodes.Count * data.maximum));
        for (int level = root.level; level >= 0; level--) {
            List<View> group = new();
            foreach (AtDepth node in nodes)
                if (node.view.level == level)
                    group.Add(node.view);
            int total = 0, min = int.MaxValue, max = 0, under = 0;
            long area = 0, overlap = 0;
            foreach (View node in group) {
                int count = node.children.Count == 0 ? node.held.Count : node.children.Count;
                total += count;
                min = Math.Min(min, count);
                max = Math.Max(max, count);
                if (count < data.minimum)
                    under++;
                area += Rtree.Area(node.region);
            }
            for (int i = 0; i < group.Count; i++)
                for (int j = i + 1; j < group.Count; j++)
                    overlap += Rtree.Overlap(group[i].region, group[j].region);
            stats.Add("  level " + level + " nodes " + group.Count + " entries " + total + " min " + min +
                      " max " + max + " under " + under + " area " + area + " overlap " + overlap);
        }
    }
    public static void GridStats() {
        SortedDictionary<int, int> occupancy = new();
        int used = 0, max = 0;
        foreach (Grid.Cell cell in grid.cells) {
            int count = cell.points.Count;
            if (count > 0)
                used++;
            max = Math.Max(max, count);
            occupancy[count] = occupancy.getOrDefault(count, 0) + 1;
        }
        stats.Add("grid cells " + grid.cells.Count + " used " + used + " max " + max);
        string line = "  occupancy";
        foreach (int count in occupancy.Keys)
            line += " " + count + ":" + occupancy[count];
        stats.Add(line);
    }
    public static void Snapshot(int query) {
        if (structures.Count != 0) {
            structures.Add("");
            stats.Add("");
        }
        string header = "snapshot " + snapshot + " query " + query + " points " + points.Count + " rects " +
                        rectangles.Count;
        structures.Add(header);
        stats.Add(header);
        List<View> roots = Roots();
        foreach (int i in new int[] { 0, 1, 2, 3, 5, 6 }) {
            structures.Add(STRUCTURES[i]);
            Dump(roots[i], 0, structures);
        }
        KdStats(roots[0]);
        QuadStats(roots[1]);
        foreach (int i in new int[] { 2, 3, 5, 6 })
            RStats(STRUCTURES[i], roots[i]);
        GridStats();
    }
    public static List<int> RPosition(Rtree.Node node, int id) {
        if (node.level == 0) {
            for (int i = 0; i < node.entries.Count; i++)
                if (node.entries[i].id == id)
                    return new([i + 1]);
        } else
            for (int i = 0; i < node.entries.Count; i++) {
                List<int> found = RPosition(node.entries[i].child, id);
                if (found != null) {
                    found.Insert(0, i + 1);
                    return found;
                }
            }
        return null;
    }
    public static string Positions(List<int> positions) {
        List<string> words = new();
        foreach (int value in positions)
            words.Add(Convert.ToString(value));
        return string.Join("/", words);
    }
    public static string Locate(Dataset.Obj point) {
        string path = "";
        Kdtree.Node node = kd;
        while (node.point.id != point.id) {
            if (Kdtree.Compare(point, node.point, node.axis) < 0) {
                path += "L";
                node = node.left;
            } else {
                path += "R";
                node = node.right;
            }
        }
        List<string> moves = new();
        Quadtree.Node q = quad;
        while (q.children != null) {
            int child = Quadtree.Destination(q, point);
            moves.Add(Quadtree.MARKS[child]);
            q = q.children[child];
        }
        return "kdtree " + (path.Length == 0 ? "-" : path) + " quadtree " +
               (moves.Count == 0 ? "-" : string.Join("/", moves)) + " rtree " +
               Positions(RPosition(rt.root, point.id)) + " str " + Positions(RPosition(str.root, point.id)) +
               " grid " + (point.box.x1 / grid.size) + " " + (point.box.y1 / grid.size);
    }
    public static void Process(int query, Dataset.Command command) {
        string name = command.name;
        int[] p = command.values;
        if (SEARCHES.Contains(name)) {
            Searches(query, command);
            return;
        }
        if (name.Equals("DUMP")) {
            snapshot++;
            Snapshot(query);
            answers.Add(query + " DUMP snapshot " + snapshot);
            return;
        }
        int id = p[0];
        Dataset.Obj point = points.GetValueOrDefault(id);
        if (name.Equals("LOCATE")) {
            answers.Add(query + " LOCATE " + id + " " + (point == null ? "missing" : Locate(point)));
            return;
        }
        if (name.Equals("INSERT")) {
            point = Dataset.Point(id, p[1], p[2]);
            points[id] = point;
            kd = Kdtree.Insert(kd, point, 0);
            Quadtree.Insert(quad, point, data.bucket);
            rt.Insert(new Rtree.Entry(point), 0);
            str.Insert(new Rtree.Entry(point), 0);
            grid.Insert(point);
            answers.Add(query + " INSERT " + id + " inserted points " + points.Count);
            return;
        }
        if (point == null)
            answers.Add(query + " DELETE " + id + " missing points " + points.Count);
        else {
            kd = Kdtree.Delete(kd, point);
            Quadtree.Delete(quad, point, data.bucket);
            rt.Delete(point);
            str.Delete(point);
            grid.Delete(point);
            points.Remove(id);
            answers.Add(query + " DELETE " + id + " deleted points " + points.Count);
        }
    }
    public sealed class Aggregate {
        public int executions;
        public long nodes, tests, maximum;
    }
    public static void VisitSummary() {
        stats.Add("");
        stats.Add("visits");
        foreach (string command in SEARCHES) {
            SortedDictionary<int, Aggregate> totals = new();
            foreach (Visit visit in records)
                if (visit.command.Equals(command)) {
                    if (!totals.ContainsKey(visit.structure))
                        totals[visit.structure] = new Aggregate();
                    Aggregate aggregate = totals[visit.structure];
                    aggregate.executions++;
                    aggregate.nodes += visit.nodes;
                    aggregate.tests += visit.tests;
                    aggregate.maximum = Math.Max(aggregate.maximum, visit.nodes);
                }
            if (totals.Count == 0)
                continue;
            foreach (int index in totals.Keys) {
                Aggregate a = totals[index];
                stats.Add(command + " " + STRUCTURES[index] + " queries " + a.executions + " nodes " +
                          a.nodes + " tests " + a.tests + " max_nodes " + a.maximum + " mean_nodes " +
                          Report.Fraction(a.nodes, a.executions));
            }
            List<int> ranked = new(totals.Keys);
            ranked.Sort((a, b) => {
                Aggregate x = totals[a], y = totals[b];
                int c = x.nodes.CompareTo(y.nodes);
                if (c == 0)
                    c = x.tests.CompareTo(y.tests);
                return c != 0 ? c : a.CompareTo(b);
            });
            string line = "rank " + command;
            foreach (int index in ranked)
                line += " " + STRUCTURES[index];
            stats.Add(line);
        }
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        data = Dataset.Read();
        foreach (Dataset.Obj point in data.points)
            points[point.id] = point;
        rectangles = new(data.rectangles);
        rectangles.Sort(Comparer<Dataset.Obj>.Create((a, b) => a.id.CompareTo(b.id)));
        kd = Kdtree.Build(data.points, 0);
        quad = new Quadtree.Node(0, 0, data.world);
        grid = new Grid.Index(data.world, data.grid);
        foreach (Dataset.Obj point in data.points) {
            Quadtree.Insert(quad, point, data.bucket);
            grid.Insert(point);
        }
        rt = Rtree.Build(data.points, data.maximum, data.minimum, false);
        str = Rtree.Build(data.points, data.maximum, data.minimum, true);
        rectRt = Rtree.Build(data.rectangles, data.maximum, data.minimum, false);
        rectStr = Rtree.Build(data.rectangles, data.maximum, data.minimum, true);
        Snapshot(0);
        for (int q = 0; q < data.commands.Count; q++)
            Process(q + 1, data.commands[q]);
        VisitSummary();
        Report.Write("answers.txt", answers);
        Report.Write("visits.csv", visits);
        Report.Write("join.csv", joins);
        Report.Write("structures.txt", structures);
        Report.Write("stats.txt", stats);
    }
}
