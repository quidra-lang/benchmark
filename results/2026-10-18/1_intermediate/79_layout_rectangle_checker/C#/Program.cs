using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
class Problem(string message) : Exception("error: " + message) { }

record Box(int X1, int Y1, int X2, int Y2)
{
    public int Width => X2 - X1;
    public int Height => Y2 - Y1;
    public long Area => (long)Width * Height;

    public override string ToString() => $"({X1},{Y1})-({X2},{Y2})";

    public Box Shift(int dx, int dy) => new(X1 + dx, Y1 + dy, X2 + dx, Y2 + dy);

    public bool Contains(Box other) => X1 <= other.X1 && Y1 <= other.Y1 && X2 >= other.X2 && Y2 >= other.Y2;
}
record Rectangle(string Name, string Layer, Box Box);
record Saved(SortedDictionary<string, Rectangle> Rectangles, string Command);
record Rule(string Kind, string Inner, string Outer, int Value);
record Violation(Rectangle A, Rectangle B, int Gap, string Direction);
record Interval(int Left, int Right);
record Hole(long Area, Box Box, int AnchorX, int AnchorY);
class Relation
{
    public Box Common;
    public int Ox, Oy, Gap, Kind;
    public string Direction;

    public Relation(Rectangle a, Rectangle b)
    {
        Box x = a.Box, y = b.Box;
        Common = new(Math.Max(x.X1, y.X1), Math.Max(x.Y1, y.Y1), Math.Min(x.X2, y.X2), Math.Min(x.Y2, y.Y2));
        Ox = Common.Width;
        Oy = Common.Height;
        Gap = Math.Max(0, Math.Max(-Ox, -Oy));
        Kind = Ox < 0 || Oy < 0 ? 3 : Ox > 0 && Oy > 0 ? 0 : Ox == 0 && Oy == 0 ? 2 : 1;
        Direction = Kind == 2 ? "corner" : Ox < 0 && Oy < 0 ? "diagonal" : Ox < 0 ? "x" : "y";
    }
    public bool Connected => Kind <= 1;
}
class Grid
{
    public int[] Xs, Ys;
    readonly int[,] counts;
    int Rows => Ys.Length - 1;
    int Columns => Xs.Length - 1;

    public Grid(List<Rectangle> rectangles)
    {
        Xs = rectangles.SelectMany(r => new[] { r.Box.X1, r.Box.X2 }).Distinct().Order().ToArray();
        Ys = rectangles.SelectMany(r => new[] { r.Box.Y1, r.Box.Y2 }).Distinct().Order().ToArray();
        counts = new int[Rows, Columns];
        foreach (Rectangle r in rectangles) for (int j = 0; j < Rows; j++) if (Ys[j] >= r.Box.Y1 && Ys[j + 1] <= r.Box.Y2) for (int i = 0; i < Columns; i++) if (Xs[i] >= r.Box.X1 && Xs[i + 1] <= r.Box.X2) counts[j, i]++;
    }
    public Box Bounds => new(Xs[0], Ys[0], Xs[^1], Ys[^1]);

    public long Area(int threshold)
    {
        long result = 0;
        for (int j = 0; j < Rows; j++) for (int i = 0; i < Columns; i++) if (counts[j, i] >= threshold) result += (long)(Xs[i + 1] - Xs[i]) * (Ys[j + 1] - Ys[j]);
        return result;
    }

    public long Clipped(Box box)
    {
        long result = 0;
        for (int j = 0; j < Rows; j++) for (int i = 0; i < Columns; i++) if (counts[j, i] > 0) result += (long)Math.Max(0, Math.Min(Xs[i + 1], box.X2) - Math.Max(Xs[i], box.X1)) * Math.Max(0, Math.Min(Ys[j + 1], box.Y2) - Math.Max(Ys[j], box.Y1));
        return result;
    }

    public long Perimeter()
    {
        long result = 0;
        for (int j = 0; j < Rows; j++) for (int i = 0; i < Columns; i++) if (counts[j, i] > 0)
        {
            if (i == 0 || counts[j, i - 1] == 0) result += Ys[j + 1] - Ys[j];
            if (i + 1 == Columns || counts[j, i + 1] == 0) result += Ys[j + 1] - Ys[j];
            if (j == 0 || counts[j - 1, i] == 0) result += Xs[i + 1] - Xs[i];
            if (j + 1 == Rows || counts[j + 1, i] == 0) result += Xs[i + 1] - Xs[i];
        }
        return result;
    }

    public Box Empty()
    {
        Box best = null;
        for (int left = 0; left < Columns; left++)
        {
            bool[] blocked = new bool[Rows];
            for (int right = left + 1; right <= Columns; right++)
            {
                for (int j = 0; j < Rows; j++) blocked[j] |= counts[j, right - 1] > 0;
                int bottom = 0;
                while (bottom < Rows)
                {
                    if (blocked[bottom])
                    {
                        bottom++;
                        continue;
                    }
                    int top = bottom + 1;
                    while (top < Rows && !blocked[top]) top++;
                    Box candidate = new(Xs[left], Ys[bottom], Xs[right], Ys[top]);
                    if (best == null || candidate.Area > best.Area || candidate.Area == best.Area && (candidate.X1 < best.X1 || candidate.X1 == best.X1 && (candidate.Y1 < best.Y1 || candidate.Y1 == best.Y1 && candidate.Width < best.Width))) best = candidate;
                    bottom = top;
                }
            }
        }
        return best;
    }

    public List<Hole> Holes()
    {
        bool[,] seen = new bool[Rows, Columns];
        List<Hole> result = new();
        int[] dx = { -1, 1, 0, 0 }, dy = { 0, 0, -1, 1 };
        for (int j = 0; j < Rows; j++) for (int i = 0; i < Columns; i++) if (counts[j, i] == 0 && !seen[j, i])
        {
            Queue<(int X, int Y)> queue = new();
            queue.Enqueue((i, j));
            seen[j, i] = true;
            bool boundary = false;
            long area = 0;
            int x1 = Xs[i], y1 = Ys[j], x2 = Xs[i + 1], y2 = Ys[j + 1], ax = Xs[i], ay = Ys[j];
            while (queue.Count > 0)
            {
                var (x, y) = queue.Dequeue();
                boundary |= x == 0 || y == 0 || x + 1 == Columns || y + 1 == Rows;
                area += (long)(Xs[x + 1] - Xs[x]) * (Ys[y + 1] - Ys[y]);
                x1 = Math.Min(x1, Xs[x]);
                y1 = Math.Min(y1, Ys[y]);
                x2 = Math.Max(x2, Xs[x + 1]);
                y2 = Math.Max(y2, Ys[y + 1]);
                if (Ys[y] < ay || Ys[y] == ay && Xs[x] < ax)
                {
                    ax = Xs[x];
                    ay = Ys[y];
                }
                for (int d = 0; d < 4; d++)
                {
                    int xx = x + dx[d], yy = y + dy[d];
                    if (xx >= 0 && xx < Columns && yy >= 0 && yy < Rows && counts[yy, xx] == 0 && !seen[yy, xx])
                    {
                        seen[yy, xx] = true;
                        queue.Enqueue((xx, yy));
                    }
                }
            }
            if (!boundary) result.Add(new(area, new(x1, y1, x2, y2), ax, ay));
        }
        return result.OrderBy(h => h.AnchorY).ThenBy(h => h.AnchorX).ToList();
    }

    public List<Box> Pieces()
    {
        Dictionary<Interval, Box> active = new();
        List<Box> result = new();
        for (int j = 0; j < Rows; j++)
        {
            Dictionary<Interval, Box> next = new();
            int i = 0;
            while (i < Columns)
            {
                if (counts[j, i] == 0)
                {
                    i++;
                    continue;
                }
                int right = i + 1;
                while (right < Columns && counts[j, right] > 0) right++;
                Interval key = new(Xs[i], Xs[right]);
                active.Remove(key, out Box old);
                next[key] = new(Xs[i], old == null ? Ys[j] : old.Y1, Xs[right], Ys[j + 1]);
                i = right;
            }
            result.AddRange(active.Values);
            active = next;
        }
        result.AddRange(active.Values);
        return result.OrderBy(b => b.Y1).ThenBy(b => b.X1).ToList();
    }
}
class Program
{
    SortedDictionary<string, Rectangle> rectangles = new(StringComparer.Ordinal);
    readonly List<Saved> history = new();
    readonly SortedDictionary<string, Rule> rules = new(StringComparer.Ordinal);

    static void Fail(string message) => throw new Problem(message);

    Rectangle Get(string name)
    {
        if (!rectangles.TryGetValue(name, out Rectangle rectangle)) Fail("unknown rectangle " + name);
        return rectangle;
    }

    List<Rectangle> Layer(string name, bool required)
    {
        List<Rectangle> list = rectangles.Values.Where(r => r.Layer == name).ToList();
        if (required && list.Count == 0) Fail("no rectangles on " + name);
        return list;
    }

    static void Bounds(Box box)
    {
        if (box.X1 < -10000 || box.Y1 < -10000 || box.X2 > 10000 || box.Y2 > 10000 || box.X1 > 10000 || box.Y1 > 10000 || box.X2 < -10000 || box.Y2 < -10000) Fail("out of bounds");
    }

    void Save(string line) => history.Add(new(new(rectangles, StringComparer.Ordinal), line));

    static string Names(List<Rectangle> list) => list.Count == 0 ? "none" : string.Join(" ", list.Select(r => r.Name).Order(StringComparer.Ordinal));

    static string Decimal(long scaled) => $"{scaled / 100}.{scaled % 100:00}";

    static string Density(long area, long total) => Decimal(10000L * area / total);

    static int Margin(Rectangle outer, Rectangle inner) => Math.Min(Math.Min(inner.Box.X1 - outer.Box.X1, inner.Box.Y1 - outer.Box.Y1), Math.Min(outer.Box.X2 - inner.Box.X2, outer.Box.Y2 - inner.Box.Y2));

    static List<List<Rectangle>> Nets(List<Rectangle> list)
    {
        bool[] seen = new bool[list.Count];
        List<List<Rectangle>> result = new();
        for (int start = 0; start < list.Count; start++) if (!seen[start])
        {
            List<Rectangle> net = new();
            Queue<int> queue = new();
            queue.Enqueue(start);
            seen[start] = true;
            while (queue.Count > 0)
            {
                int i = queue.Dequeue();
                net.Add(list[i]);
                for (int j = 0; j < list.Count; j++) if (!seen[j] && new Relation(list[i], list[j]).Connected)
                {
                    seen[j] = true;
                    queue.Enqueue(j);
                }
            }
            net.Sort((a, b) => StringComparer.Ordinal.Compare(a.Name, b.Name));
            result.Add(net);
        }
        return result;
    }

    static List<Violation> Spacing(List<Rectangle> list, int space)
    {
        List<Violation> result = new();
        for (int i = 0; i < list.Count; i++) for (int j = i + 1; j < list.Count; j++)
        {
            Relation relation = new(list[i], list[j]);
            if (relation.Kind == 2 || relation.Kind == 3 && relation.Gap < space) result.Add(new(list[i], list[j], relation.Gap, relation.Direction));
        }
        return result.OrderBy(v => v.Gap).ThenBy(v => v.A.Name, StringComparer.Ordinal).ThenBy(v => v.B.Name, StringComparer.Ordinal).ToList();
    }

    static string ViolationText(Violation violation) => $"{violation.A.Name} {violation.B.Name} gap {violation.Gap} {violation.Direction}";

    static string Info(Rectangle rectangle) => $"{rectangle.Name} {rectangle.Layer} {rectangle.Box} {rectangle.Box.Width}x{rectangle.Box.Height}";

    List<string> Command(string line)
    {
        string[] a = line.Split(' ');
        string c = a[0];
        List<string> output = new();
        switch (c)
        {
            case "ADD":
            {
                if (rectangles.ContainsKey(a[1])) Fail("duplicate rectangle " + a[1]);
                Box box = new(int.Parse(a[3]), int.Parse(a[4]), int.Parse(a[5]), int.Parse(a[6]));
                if (box.X1 >= box.X2 || box.Y1 >= box.Y2) Fail("invalid rectangle");
                Bounds(box);
                Save(line);
                rectangles[a[1]] = new(a[1], a[2], box);
                output.Add($"added {a[1]} {a[2]} {box}");
                break;
            }
            case "COPY":
            case "MOVE":
            case "RESIZE":
            case "SPLIT":
            case "LAYER":
            case "DELETE":
            {
                Rectangle rectangle = Get(a[1]);
                Box box = rectangle.Box;
                string layer = rectangle.Layer;
                Rectangle extra = null;
                switch (c)
                {
                    case "COPY":
                        if (rectangles.ContainsKey(a[2])) Fail("duplicate rectangle " + a[2]);
                        box = box.Shift(int.Parse(a[3]), int.Parse(a[4]));
                        Bounds(box);
                        extra = new(a[2], layer, box);
                        output.Add($"copied {rectangle.Name} to {a[2]} {box}");
                        break;
                    case "MOVE":
                        box = box.Shift(int.Parse(a[2]), int.Parse(a[3]));
                        Bounds(box);
                        output.Add($"moved {rectangle.Name} to {box}");
                        break;
                    case "RESIZE":
                    {
                        int w = int.Parse(a[2]), h = int.Parse(a[3]);
                        if (w <= 0 || h <= 0) Fail("invalid size");
                        box = new(box.X1, box.Y1, box.X1 + w, box.Y1 + h);
                        Bounds(box);
                        output.Add($"resized {rectangle.Name} to {box}");
                        break;
                    }
                    case "SPLIT":
                    {
                        if (rectangles.ContainsKey(a[4])) Fail("duplicate rectangle " + a[4]);
                        int pos = int.Parse(a[3]);
                        bool x = a[2] == "x";
                        if (pos <= (x ? box.X1 : box.Y1) || pos >= (x ? box.X2 : box.Y2)) Fail("cut outside " + rectangle.Name);
                        Box second = x ? new(pos, box.Y1, box.X2, box.Y2) : new(box.X1, pos, box.X2, box.Y2);
                        box = x ? new(box.X1, box.Y1, pos, box.Y2) : new(box.X1, box.Y1, box.X2, pos);
                        extra = new(a[4], layer, second);
                        output.Add($"split {rectangle.Name} at {a[2]}={pos}: {rectangle.Name} {box}, {a[4]} {second}");
                        break;
                    }
                    case "LAYER":
                        if (layer == a[2]) Fail("already on " + layer);
                        output.Add($"layer {rectangle.Name} {layer} -> {a[2]}");
                        layer = a[2];
                        break;
                    case "DELETE":
                        output.Add("deleted " + rectangle.Name);
                        break;
                }
                Save(line);
                if (c == "DELETE") rectangles.Remove(rectangle.Name);
                else if (c != "COPY") rectangles[rectangle.Name] = new(rectangle.Name, layer, box);
                if (extra != null) rectangles[extra.Name] = extra;
                break;
            }
            case "UNDO":
                if (history.Count == 0) Fail("nothing to undo");
                Saved saved = history[^1];
                history.RemoveAt(history.Count - 1);
                rectangles = saved.Rectangles;
                output.Add("undo: " + saved.Command);
                break;
            case "LIST":
                output.Add("rectangles: " + rectangles.Count);
                foreach (Rectangle rectangle in rectangles.Values) output.Add(Info(rectangle));
                break;
            case "INFO":
            {
                Rectangle rectangle = Get(a[1]);
                output.Add(Info(rectangle) + " area " + rectangle.Box.Area);
                string[] labels = { "overlaps", "touches", "corners", "encloses", "enclosed by" };
                for (int k = 0; k < labels.Length; k++)
                {
                    List<Rectangle> list = new();
                    foreach (Rectangle other in rectangles.Values) if (rectangle.Name != other.Name)
                    {
                        Relation relation = new(rectangle, other);
                        if (k < 3 ? rectangle.Layer == other.Layer && relation.Kind == k : k == 3 ? rectangle.Box.Contains(other.Box) : other.Box.Contains(rectangle.Box)) list.Add(other);
                    }
                    output.Add(labels[k] + ": " + Names(list));
                }
                break;
            }
            case "LAYERS":
            {
                List<string> layers = rectangles.Values.Select(r => r.Layer).Distinct().Order(StringComparer.Ordinal).ToList();
                output.Add("layers: " + layers.Count);
                foreach (string name in layers)
                {
                    List<Rectangle> list = Layer(name, true);
                    output.Add($"{name}: {list.Count} rectangles, area {new Grid(list).Area(1)}, nets {Nets(list).Count}");
                }
                break;
            }
            case "OVERLAPS":
            {
                List<string> details = new();
                List<string> layers;
                if (a.Length == 2)
                {
                    Layer(a[1], true);
                    layers = new() { a[1] };
                }
                else layers = rectangles.Values.Select(r => r.Layer).Distinct().Order(StringComparer.Ordinal).ToList();
                foreach (string name in layers)
                {
                    List<Rectangle> list = Layer(name, true);
                    for (int i = 0; i < list.Count; i++) for (int j = i + 1; j < list.Count; j++)
                    {
                        Rectangle x = list[i], y = list[j];
                        Relation relation = new(x, y);
                        if (relation.Kind == 0) details.Add((a.Length == 1 ? name + " " : "") + $"{x.Name} {y.Name} {relation.Common} area {relation.Common.Area}");
                    }
                }
                output.Add($"overlaps {(a.Length == 1 ? "all layers" : a[1])}: {details.Count}");
                output.AddRange(details);
                break;
            }
            case "INTERSECT":
            case "ADJACENT":
            case "ENCLOSE":
            case "PATH":
            {
                Rectangle x = Get(a[1]), y = Get(a[2]);
                if (x.Name == y.Name) Fail("same rectangle " + x.Name);
                Relation relation = new(x, y);
                string prefix = $"{c.ToLowerInvariant()} {x.Name} {y.Name}: ";
                if (c == "PATH")
                {
                    if (x.Layer != y.Layer) Fail("different layers");
                    List<Rectangle> list = Layer(x.Layer, true);
                    int start = list.IndexOf(x), goal = list.IndexOf(y);
                    int[] previous = Enumerable.Repeat(-1, list.Count).ToArray();
                    previous[start] = start;
                    Queue<int> queue = new();
                    queue.Enqueue(start);
                    while (queue.Count > 0)
                    {
                        int i = queue.Dequeue();
                        for (int j = 0; j < list.Count; j++) if (previous[j] < 0 && new Relation(list[i], list[j]).Connected)
                        {
                            previous[j] = i;
                            queue.Enqueue(j);
                        }
                    }
                    List<string> path = new();
                    if (previous[goal] >= 0) for (int at = goal;; at = previous[at])
                    {
                        path.Insert(0, list[at].Name);
                        if (at == start) break;
                    }
                    output.Add(prefix + (path.Count == 0 ? "none" : string.Join(" -> ", path) + $" ({path.Count - 1} steps)"));
                }
                else if (c == "ENCLOSE")
                {
                    int left = y.Box.X1 - x.Box.X1, bottom = y.Box.Y1 - x.Box.Y1, right = x.Box.X2 - y.Box.X2, top = x.Box.Y2 - y.Box.Y2, min = Margin(x, y);
                    output.Add(prefix + (min >= 0 ? "yes" : "no") + $", margins left {left} bottom {bottom} right {right} top {top}" + (min >= 0 ? $", min {min}" : ""));
                }
                else if (c == "INTERSECT") output.Add(prefix + (relation.Kind switch
                {
                    0 => $"{relation.Common} area {relation.Common.Area}",
                    1 => $"segment {relation.Common} length {relation.Ox + relation.Oy}",
                    2 => $"point ({relation.Common.X1},{relation.Common.Y1})",
                    _ => $"none, gap {relation.Gap}"
                }));
                else output.Add(prefix + (relation.Kind switch
                {
                    0 => "overlapping",
                    1 => $"{x.Name} is {(relation.Ox == 0 ? x.Box.X2 == relation.Common.X1 ? "west" : "east" : x.Box.Y2 == relation.Common.Y1 ? "south" : "north")} of {y.Name}, edge {relation.Common}, length {relation.Ox + relation.Oy}",
                    2 => $"corner only at ({relation.Common.X1},{relation.Common.Y1})",
                    _ => "not adjacent"
                }));
                break;
            }
            case "AT":
            {
                int x = int.Parse(a[1]), y = int.Parse(a[2]);
                List<string> found = new();
                foreach (Rectangle rectangle in rectangles.Values) if (x >= rectangle.Box.X1 && x <= rectangle.Box.X2 && y >= rectangle.Box.Y1 && y <= rectangle.Box.Y2)
                {
                    bool xx = x == rectangle.Box.X1 || x == rectangle.Box.X2, yy = y == rectangle.Box.Y1 || y == rectangle.Box.Y2;
                    found.Add($"{rectangle.Name} {rectangle.Layer} " + (xx && yy ? "corner" : xx || yy ? "edge" : "inside"));
                }
                output.Add($"at ({x},{y}): " + (found.Count == 0 ? "none" : string.Join(", ", found)));
                break;
            }
            case "NEAREST":
            {
                Rectangle rectangle = Get(a[1]), best = null;
                int gap = int.MaxValue;
                foreach (Rectangle other in Layer(rectangle.Layer, true)) if (rectangle.Name != other.Name)
                {
                    int g = new Relation(rectangle, other).Gap;
                    if (g < gap)
                    {
                        gap = g;
                        best = other;
                    }
                }
                output.Add($"nearest {rectangle.Name}: " + (best == null ? "none" : $"{best.Name} gap {gap}"));
                break;
            }
            case "RULE":
            {
                string kind = a[1].ToLowerInvariant(), inner = a[2], outer = kind == "enclose" ? a[3] : "";
                int value = int.Parse(a[kind == "enclose" ? 4 : 3]);
                if (kind == "enclose" && inner == outer) Fail("same layer " + inner);
                rules[kind + " " + inner + " " + outer] = new(kind, inner, outer, value);
                output.Add($"rule {kind} {inner}" + (outer.Length == 0 ? "" : " " + outer) + $" {value}");
                break;
            }
            case "CHECK":
            {
                if (rules.Count == 0) Fail("no rules");
                int total = 0;
                foreach (Rule rule in rules.Values)
                {
                    List<string> violations = new();
                    List<Rectangle> list = Layer(rule.Inner, false);
                    if (rule.Kind == "spacing") foreach (Violation violation in Spacing(list, rule.Value)) violations.Add(ViolationText(violation));
                    else if (rule.Kind == "width") foreach (Rectangle rectangle in list)
                    {
                        int width = Math.Min(rectangle.Box.Width, rectangle.Box.Height);
                        if (width < rule.Value) violations.Add($"{rectangle.Name} width {width}");
                    }
                    else
                    {
                        List<Rectangle> outer = Layer(rule.Outer, false);
                        foreach (Rectangle rectangle in list)
                        {
                            int? best = null;
                            foreach (Rectangle o in outer) best = !best.HasValue ? Margin(o, rectangle) : Math.Max(best.Value, Margin(o, rectangle));
                            if (!best.HasValue || best.Value < rule.Value) violations.Add($"{rectangle.Name} best margin " + (best.HasValue ? best.Value.ToString() : "none"));
                        }
                    }
                    output.Add($"{rule.Kind} {rule.Inner}" + (rule.Outer.Length == 0 ? "" : " " + rule.Outer) + $" {rule.Value}: {violations.Count} violations");
                    output.AddRange(violations);
                    total += violations.Count;
                }
                output.Add($"check: {total} violations in {rules.Count} rules");
                break;
            }
            default:
            {
                string name = c == "COVER" ? a[2] : a[1];
                List<Rectangle> list = Layer(name, true);
                Grid grid = new(list);
                Box box = grid.Bounds;
                switch (c)
                {
                    case "AREA":
                        output.Add($"area {name}: {grid.Area(1)}");
                        break;
                    case "COVER":
                        output.Add($"cover {name} >= {a[1]}: {grid.Area(int.Parse(a[1]))}");
                        break;
                    case "PERIMETER":
                        output.Add($"perimeter {name}: {grid.Perimeter()}");
                        break;
                    case "NETS":
                    {
                        List<List<Rectangle>> groups = Nets(list);
                        output.Add($"nets {name}: {groups.Count}");
                        for (int i = 0; i < groups.Count; i++) output.Add($"net {i + 1}: {Names(groups[i])} area {new Grid(groups[i]).Area(1)}");
                        break;
                    }
                    case "DRC":
                    {
                        int s = int.Parse(a[2]);
                        List<Violation> violations = Spacing(list, s);
                        output.Add($"drc {name} spacing {s}: {violations.Count} violations");
                        foreach (Violation violation in violations) output.Add(ViolationText(violation));
                        break;
                    }
                    case "BBOX":
                        output.Add($"bbox {name}: {box} {box.Width}x{box.Height}, {list.Count} rectangles, density {Density(grid.Area(1), box.Area)}%");
                        break;
                    case "DENSITY":
                    {
                        int w = int.Parse(a[2]), columns = (box.Width + w - 1) / w, rows = (box.Height + w - 1) / w;
                        if (columns > 20 || rows > 20) Fail("too many windows");
                        long[,] values = new long[rows, columns];
                        long min = long.MaxValue, max = -1;
                        int minX = 0, minY = 0, maxX = 0, maxY = 0;
                        for (int j = 0; j < rows; j++) for (int i = 0; i < columns; i++)
                        {
                            values[j, i] = grid.Clipped(new(box.X1 + i * w, box.Y1 + j * w, box.X1 + (i + 1) * w, box.Y1 + (j + 1) * w));
                            if (values[j, i] < min)
                            {
                                min = values[j, i];
                                minX = i;
                                minY = j;
                            }
                            if (values[j, i] > max)
                            {
                                max = values[j, i];
                                maxX = i;
                                maxY = j;
                            }
                        }
                        output.Add($"density {name} window {w}: {columns}x{rows}");
                        for (int j = rows - 1; j >= 0; j--)
                        {
                            List<string> row = new();
                            for (int i = 0; i < columns; i++) row.Add((100L * values[j, i] / ((long)w * w)).ToString());
                            output.Add(string.Join(" ", row));
                        }
                        output.Add($"min {Density(min, (long)w * w)}% at ({box.X1 + minX * w},{box.Y1 + minY * w})");
                        output.Add($"max {Density(max, (long)w * w)}% at ({box.X1 + maxX * w},{box.Y1 + maxY * w})");
                        break;
                    }
                    case "RENDER":
                    {
                        Box window = new(int.Parse(a[2]), int.Parse(a[3]), int.Parse(a[4]), int.Parse(a[5]));
                        if (window.X1 >= window.X2 || window.Y1 >= window.Y2) Fail("invalid window");
                        if (window.Width > 60 || window.Height > 40) Fail("window too large");
                        output.Add($"render {name} {window}");
                        for (int y = window.Y2 - 1; y >= window.Y1; y--)
                        {
                            char[] row = new char[window.Width];
                            for (int x = window.X1; x < window.X2; x++)
                            {
                                int count = list.Count(r => r.Box.X1 <= x && x < r.Box.X2 && r.Box.Y1 <= y && y < r.Box.Y2);
                                row[x - window.X1] = count == 0 ? '.' : count < 10 ? (char)('0' + count) : '*';
                            }
                            output.Add(new string(row));
                        }
                        break;
                    }
                    case "EMPTY":
                    {
                        Box empty = grid.Empty();
                        output.Add($"empty {name}: " + (empty == null ? "none" : $"{empty} area {empty.Area}"));
                        break;
                    }
                    case "HOLES":
                    {
                        List<Hole> holes = grid.Holes();
                        output.Add($"holes {name}: {holes.Count}");
                        for (int i = 0; i < holes.Count; i++) output.Add($"hole {i + 1}: area {holes[i].Area}, bbox {holes[i].Box}");
                        break;
                    }
                    case "MERGE":
                    {
                        List<Box> pieces = grid.Pieces();
                        output.Add($"merge {name}: {pieces.Count} pieces");
                        foreach (Box piece in pieces) output.Add(piece.ToString());
                        break;
                    }
                }
                break;
            }
        }
        return output;
    }

    static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Program layout = new();
        int count = int.Parse(Console.ReadLine());
        for (int i = 0; i < count; i++)
        {
            string line = Console.ReadLine();
            try
            {
                foreach (string row in layout.Command(line)) Console.WriteLine(row);
            }
            catch (Problem problem)
            {
                Console.WriteLine(problem.Message);
            }
        }
    }
}
