sealed record Polygon(Rings Input, Rings Canonical);
sealed record Target(Region Region, (Rings A, Rings B)? Operands = null);
sealed class Rejection(string reason) : Exception(reason)
{
    public string Reason { get; } = reason;
}
sealed class Polygons
{
    public HashSet<string> Used { get; } = new(StringComparer.Ordinal);
    public Dictionary<string, Polygon> Valid { get; } = new(StringComparer.Ordinal);
    public List<string> Rejected { get; } = new();
    public int Blocks { get; private set; }
    public int ValidBlocks { get; private set; }
    public void Read()
    {
        string[] lines = File.ReadAllLines("input/polygons.txt");
        int i = 0;
        while (i < lines.Length)
        {
            if (lines[i].Length == 0 || lines[i].StartsWith('#')) { i++; continue; }
            string name = lines[i].Split(' ')[1];
            int start = i + 1;
            i++;
            List<(int Line, string Text)> content = new();
            while (lines[i] != "END")
            {
                if (lines[i].Length > 0 && !lines[i].StartsWith('#')) content.Add((i + 1, lines[i]));
                i++;
            }
            int end = i + 1;
            i++;
            Blocks++;
            if (!Used.Add(name)) { Rejected.Add($"polygon {name} duplicate_name line {start}"); continue; }
            try
            {
                Rings input = Program.ParseBlock(content, end);
                if (Program.Validate(input) is { } reason) throw new Rejection(reason);
                Valid[name] = new Polygon(input, RingOps.Canonical(input));
                ValidBlocks++;
            }
            catch (Rejection e) { Rejected.Add($"polygon {name} {e.Reason}"); }
        }
    }
    public Polygon Get(string name)
    {
        if (!Used.Contains(name)) throw new Rejection($"unknown_polygon {name}");
        return Valid.TryGetValue(name, out Polygon? polygon) ? polygon : throw new Rejection($"invalid_polygon {name}");
    }
}
sealed record Values(List<string> Lines, int Rings, int Holes, int Vertices, double Area);
sealed class Operation
{
    public List<string> Lines { get; } = new();
    public string? Area { get; set; }
    public List<string> Drawing { get; set; } = new();
    public Target? Target { get; set; }
    public (string Name, Polygon Polygon)? Definition { get; set; }
    public int Crossings { get; set; }
}

static class Program
{
    static readonly string[] Kinds = ["UNION", "INTERSECTION", "DIFFERENCE", "XOR", "CLIP", "AREA", "MOVE", "ROTATE", "MIRROR", "SNAP", "LOCATE", "RENDER"];
    static long? Integer(string text)
    {
        string digits = text.StartsWith('-') ? text[1..] : text;
        return digits.Length is >= 1 and <= 9 && digits.All(c => c is >= '0' and <= '9') && long.TryParse(text, NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out long n) ? n : null;
    }
    static bool ValidName(string text) => text.Length is >= 1 and <= 16 && text.All(c => c is >= 'a' and <= 'z' or >= '0' and <= '9' or '_');
    public static string? Validate(Rings rings)
    {
        for (int k = 0; k < rings.Count; k++)
        {
            Ring r = rings[k];
            int n = r.Count;
            if (n < 3) return $"too_few_vertices ring {k + 1}";
            Point? outside = r.FirstOrDefault(p => p.X < 0 || p.Y < 0 || p.X > 1000 * p.D || p.Y > 1000 * p.D);
            if (outside is not null) return $"out_of_range ring {k + 1} {outside}";
            HashSet<Point> seen = new();
            foreach (Point p in r) if (!seen.Add(p)) return $"duplicate_vertex ring {k + 1} {p}";
            for (int i = 0; i < n; i++) if (Cross(r[(i + n - 1) % n], r[i], r[(i + 1) % n]).IsZero) return $"collinear ring {k + 1} {r[i]}";
            for (int i = 0; i < n; i++) for (int j = i + 1; j < n; j++) if (j != i + 1 && !(i == 0 && j == n - 1))
            {
                if (Intersections.Touch(r[i], r[(i + 1) % n], r[j], r[(j + 1) % n])) return $"self_intersection ring {k + 1} {Intersections.Segment(r[i], r[(i + 1) % n])} {Intersections.Segment(r[j], r[(j + 1) % n])}";
            }
        }
        for (int i = 0; i < rings.Count; i++) for (int j = i + 1; j < rings.Count; j++)
            for (int e = 0; e < rings[i].Count; e++) for (int f = 0; f < rings[j].Count; f++)
            {
                Point a = rings[i][e], b = rings[i][(e + 1) % rings[i].Count], c = rings[j][f], d = rings[j][(f + 1) % rings[j].Count];
                if (Intersections.Touch(a, b, c, d)) return $"rings_touch rings {i + 1} {j + 1} {Intersections.Segment(a, b)} {Intersections.Segment(c, d)}";
            }
        for (int k = 1; k < rings.Count; k++) if (!RingOps.Inside(rings[k][0], rings[0])) return $"hole_outside ring {k + 1} {rings[k][0]}";
        for (int i = 1; i < rings.Count; i++) for (int j = i + 1; j < rings.Count; j++)
        {
            if (RingOps.Inside(rings[j][0], rings[i])) return $"hole_in_hole rings {i + 1} {j + 1} {rings[j][0]}";
            if (RingOps.Inside(rings[i][0], rings[j])) return $"hole_in_hole rings {i + 1} {j + 1} {rings[i][0]}";
        }
        return null;
    }
    public static Rings ParseBlock(List<(int Line, string Text)> content, int end)
    {
        Rings rings = new();
        int i = 0;
        while (i < content.Count)
        {
            var (line, text) = content[i];
            string[] a = text.Split(' ');
            if (a.Length != 2 || !(a[0] == "OUTER" && rings.Count == 0 || a[0] == "HOLE" && rings.Count > 0) ||
                a[1].Length is < 1 or > 9 || !a[1].All(c => c is >= '0' and <= '9') || int.Parse(a[1], CultureInfo.InvariantCulture) == 0) throw new Rejection($"format line {line}");
            int n = int.Parse(a[1], CultureInfo.InvariantCulture);
            i++;
            Ring ring = new();
            for (int j = 0; j < n; j++)
            {
                if (i == content.Count) throw new Rejection($"format line {end}");
                var (at, vertex) = content[i];
                string[] words = vertex.Split(' ');
                if (words.Length != 2 || Integer(words[0]) is not { } x || Integer(words[1]) is not { } y) throw new Rejection($"format line {at}");
                ring.Add(new Point(x, y));
                i++;
            }
            rings.Add(ring);
        }
        if (rings.Count == 0) throw new Rejection($"format line {end}");
        return rings;
    }
    static Target ResolveTarget(string text, Polygons polygons, Dictionary<int, Target> results)
    {
        if (text.StartsWith('@'))
        {
            string n = text[1..];
            if (n.Length is < 1 or > 9 || !n.All(c => c is >= '0' and <= '9') || !results.TryGetValue(int.Parse(n, CultureInfo.InvariantCulture), out Target? value)) throw new Rejection($"bad_target {text}");
            return value;
        }
        return new Target(new Region { polygons.Get(text).Canonical });
    }
    static string? General(Rings a, Rings b, string an, string bn)
    {
        foreach (Ring r in a) foreach (Point p in r) if (b.Any(q => q.Contains(p))) return $"shared_vertex {p}";
        foreach (Ring r in a) for (int i = 0; i < r.Count; i++) foreach (Ring s in b) for (int j = 0; j < s.Count; j++)
        {
            Point u = r[i], v = r[(i + 1) % r.Count], w = s[j], z = s[(j + 1) % s.Count];
            if (Intersections.Overlap(u, v, w, z)) return $"overlapping_edges {Intersections.Segment(u, v)} {Intersections.Segment(w, z)}";
        }
        for (int side = 0; side < 2; side++)
        {
            Rings left = side == 0 ? a : b, right = side == 0 ? b : a;
            string pn = side == 0 ? an : bn, qn = side == 0 ? bn : an;
            foreach (Ring r in left) foreach (Point v in r) foreach (Ring s in right) for (int e = 0; e < s.Count; e++)
            {
                Point u = s[e], w = s[(e + 1) % s.Count];
                if (Intersections.On(u, w, v)) return $"vertex_on_edge {pn} {v} {qn} {Intersections.Segment(u, w)}";
            }
        }
        return null;
    }
    static bool Convex(Rings rings) => rings.Count == 1 && Enumerable.Range(0, rings[0].Count).All(i => Cross(rings[0][(i + rings[0].Count - 1) % rings[0].Count], rings[0][i], rings[0][(i + 1) % rings[0].Count]) > 0);
    static Rings Clip(Rings a, Ring window)
    {
        Rings result = new();
        foreach (Ring ring in a)
        {
            Ring list = ring;
            for (int j = 0; j < window.Count; j++)
            {
                Point c1 = window[j], c2 = window[(j + 1) % window.Count];
                Ring next = new();
                for (int i = 0; i < list.Count; i++)
                {
                    Point prev = list[(i + list.Count - 1) % list.Count], cur = list[i];
                    bool pin = Cross(c1, c2, prev) > 0, cin = Cross(c1, c2, cur) > 0;
                    if (pin != cin) next.Add(Intersections.LineIntersection(prev, cur, c1, c2));
                    if (cin) next.Add(cur);
                }
                list = next;
            }
            Ring clean = Enumerable.Range(0, list.Count).Where(i => list[i] != list[(i + list.Count - 1) % list.Count]).Select(i => list[i]).ToList();
            if (clean.Count >= 3) result.Add(clean);
        }
        return result;
    }
    static bool Cyclic(Ring a, Ring b) => a.Count == b.Count && Enumerable.Range(0, b.Count).Any(k => Enumerable.Range(0, a.Count).All(i => a[i] == b[(i + k) % b.Count]));
    static string Locate(Region region, Point p)
    {
        for (int k = 0; k < region.Count; k++) for (int j = 0; j < region[k].Count; j++) if (RingOps.Boundary(p, region[k][j])) return j == 0 ? $"boundary outer {k + 1}" : $"boundary hole {k + 1} {j}";
        for (int k = 0; k < region.Count; k++) if (RingOps.Inside(p, region[k][0]) && region[k].Skip(1).All(r => !RingOps.Inside(p, r))) return $"inside polygon {k + 1}";
        return "outside";
    }
    static string OperandLocation(Point p, Rings rings) => rings.Any(r => RingOps.Boundary(p, r)) ? "boundary" : RingOps.Interior(p, rings) ? "inside" : "outside";
    static Ring ConvexHull(Ring ring)
    {
        Ring sorted = ring.OrderBy(p => p, Comparer<Point>.Create((a, b) => XCompare(a, b) != 0 ? XCompare(a, b) : YCompare(a, b))).ToList();
        Ring Half(IEnumerable<Point> points)
        {
            Ring result = new();
            foreach (Point p in points)
            {
                while (result.Count >= 2 && Cross(result[^2], result[^1], p) <= 0) result.RemoveAt(result.Count - 1);
                result.Add(p);
            }
            return result.Take(result.Count - 1).ToList();
        }
        return Half(sorted).Concat(Half(sorted.AsEnumerable().Reverse())).ToList();
    }
    static BigInteger TwiceArea(Ring ring)
    {
        BigInteger sum = 0;
        for (int i = 0; i < ring.Count; i++) sum += ring[i].X * ring[(i + 1) % ring.Count].Y - ring[(i + 1) % ring.Count].X * ring[i].Y;
        return sum;
    }
    static Values ResultValues(Region region, Rings a, Rings? b)
    {
        int rings = region.Sum(p => p.Count), holes = rings - region.Count, vertices = region.SelectMany(p => p).Sum(r => r.Count);
        double area = RingOps.TotalArea(region);
        List<string> lines = new() { $"polygons {region.Count} rings {rings} holes {holes} vertices {vertices} area {RealText(area)}" };
        double sx = 0, sy = 0, perimeter = 0;
        int[] origins = new int[3];
        Ring points = new();
        for (int k = 0; k < region.Count; k++) for (int j = 0; j < region[k].Count; j++)
        {
            Ring ring = region[k][j];
            string label = j == 0 ? $"outer {k + 1}" : $"hole {k + 1} {j}";
            lines.Add($"{label} {ring.Count} {RealText(RingOps.Area(ring))} " + string.Join(" ", ring));
            perimeter += RingOps.Perimeter(ring);
            for (int i = 0; i < ring.Count; i++)
            {
                var (x1, y1) = ring[i].Real();
                var (x2, y2) = ring[(i + 1) % ring.Count].Real();
                double c = x1 * y2 - x2 * y1;
                sx += (x1 + x2) * c;
                sy += (y1 + y2) * c;
                Point v = ring[i];
                origins[a.Any(r => r.Contains(v)) ? 0 : b?.Any(r => r.Contains(v)) == true ? 1 : 2]++;
                points.Add(v);
            }
        }
        if (points.Count == 0) { lines.Add("bbox none"); lines.Add("centroid none"); }
        else
        {
            Point minX = points.MinBy(p => p, Comparer<Point>.Create(XCompare))!, maxX = points.MaxBy(p => p, Comparer<Point>.Create(XCompare))!;
            Point minY = points.MinBy(p => p, Comparer<Point>.Create(YCompare))!, maxY = points.MaxBy(p => p, Comparer<Point>.Create(YCompare))!;
            Point low = new(minX.X * minY.D, minY.Y * minX.D, minX.D * minY.D);
            Point high = new(maxX.X * maxY.D, maxY.Y * maxX.D, maxX.D * maxY.D);
            lines.Add($"bbox {low} {high}");
            lines.Add($"centroid ({RealText(sx / (6 * area))},{RealText(sy / (6 * area))})");
        }
        lines.Add($"perimeter {RealText(perimeter)}");
        lines.Add($"origins a {origins[0]} b {origins[1]} crossing {origins[2]}");
        return new Values(lines, rings, holes, vertices, area);
    }
    static List<string> Properties(Polygon polygon, double area)
    {
        string orientations = string.Join(" ", polygon.Input.Select(r => TwiceArea(r) > 0 ? "ccw" : "cw"));
        int reflex = polygon.Canonical.Sum(r => Enumerable.Range(0, r.Count).Count(i => Cross(r[(i + r.Count - 1) % r.Count], r[i], r[(i + 1) % r.Count]) < 0));
        Ring hull = ConvexHull(polygon.Canonical[0]);
        double hullArea = (double)TwiceArea(hull) / 2;
        return [$"input {orientations}", $"reflex {reflex}", $"hull {hull.Count} {RealText(hullArea)} solidity {RealText(area / hullArea, 6)}"];
    }
    static bool Arguments(string[] a)
    {
        int expected = a[0] switch
        {
            "UNION" or "INTERSECTION" or "DIFFERENCE" or "XOR" or "CLIP" or "SNAP" => 3,
            "AREA" => 2, "LOCATE" => 4, "MOVE" or "MIRROR" => 5, "ROTATE" => 6, "RENDER" => 8, _ => 0
        };
        if (a.Length != expected) return false;
        bool Valid(int i, long low, long high) => Integer(a[i]) is { } n && n >= low && n <= high;
        switch (a[0])
        {
            case "LOCATE": return Valid(2, 0, 1000) && Valid(3, 0, 1000);
            case "RENDER":
                if (!(Valid(2, 0, 1000) && Valid(3, 0, 1000) && Valid(4, 1, 100) && Valid(5, 1, 100) && Valid(6, 1, 100) && Valid(7, 1, 60))) return false;
                long[] v = a.Skip(2).Select(s => Integer(s)!.Value).ToArray();
                return v[0] + v[2] * v[4] <= 1000 && v[1] + v[3] * v[5] <= 1000;
            case "MOVE": return Valid(2, -1000, 1000) && Valid(3, -1000, 1000) && ValidName(a[4]);
            case "ROTATE": return Valid(2, 0, 1000) && Valid(3, 0, 1000) && Valid(4, 1, 3) && ValidName(a[5]);
            case "MIRROR": return a[2] is "x" or "y" && Valid(3, 0, 1000) && ValidName(a[4]);
            case "SNAP": return ValidName(a[2]);
            default: return true;
        }
    }
    static Operation Execute(int number, string text, Polygons polygons, Dictionary<int, Target> results)
    {
        string[] a = text.Split(' ');
        string kind = a[0];
        if (!Kinds.Contains(kind)) throw new Rejection($"unknown_operation {kind}");
        if (!Arguments(a)) throw new Rejection("bad_arguments");
        bool binary = Kinds.Take(5).Contains(kind), defining = kind is "MOVE" or "ROTATE" or "MIRROR" or "SNAP";
        Polygon? input = binary || kind is "AREA" or "MOVE" or "ROTATE" or "MIRROR" ? polygons.Get(a[1]) : null;
        Polygon? b = binary ? polygons.Get(a[2]) : null;
        Target? resolved = kind is "LOCATE" or "RENDER" or "SNAP" ? ResolveTarget(a[1], polygons, results) : null;
        string? newName = defining ? a[^1] : null;
        if (newName is not null && polygons.Used.Contains(newName)) throw new Rejection($"duplicate_name {newName}");
        if (kind == "SNAP" && resolved!.Region.Count != 1) throw new Rejection($"not_single {a[1]}");
        if (kind == "CLIP" && !Convex(b!.Canonical)) throw new Rejection($"not_convex {a[2]}");
        if (binary && General(input!.Canonical, b!.Canonical, a[1], a[2]) is { } reason) throw new Rejection(reason);
        Operation op = new();
        op.Lines.Add($"op {number} {text}");
        if (kind == "LOCATE")
        {
            Point p = new(Integer(a[2])!.Value, Integer(a[3])!.Value);
            op.Lines.Add($"location {Locate(resolved!.Region, p)}");
            if (resolved.Operands is { } operands) op.Lines.Add($"operands a {OperandLocation(p, operands.A)} b {OperandLocation(p, operands.B)}");
            return op;
        }
        if (kind == "RENDER")
        {
            long[] v = a.Skip(2).Select(s => Integer(s)!.Value).ToArray();
            var (drawing, counts) = Render.Draw(resolved!.Region, resolved.Operands, v);
            op.Drawing.Add($"render {number} {a[1]} cols {v[4]} rows {v[5]} result {counts[0]} a {counts[1]} b {counts[2]} both {counts[3]}");
            op.Drawing.AddRange(drawing);
            op.Lines.Clear();
            return op;
        }
        Polygon? polygon = input;
        if (defining)
        {
            Rings inputRings;
            if (kind == "SNAP") inputRings = resolved!.Region[0].Select(r => r.Select(p => p.Snapped()).ToList()).ToList();
            else inputRings = input!.Input.Select(r => r.Select(p =>
            {
                BigInteger x = p.X, y = p.Y;
                if (kind == "MOVE") { x += Integer(a[2])!.Value; y += Integer(a[3])!.Value; }
                else if (kind == "ROTATE")
                {
                    BigInteger cx = Integer(a[2])!.Value, cy = Integer(a[3])!.Value;
                    for (int q = 0; q < Integer(a[4])!.Value; q++) { BigInteger nx = cx - (y - cy), ny = cy + (x - cx); x = nx; y = ny; }
                }
                else { BigInteger c = Integer(a[3])!.Value; if (a[2] == "x") x = 2 * c - x; else y = 2 * c - y; }
                return new Point(x, y);
            }).ToList()).ToList();
            if (kind == "SNAP") { if (Validate(inputRings) is { } invalid) throw new Rejection($"invalid_result {invalid}"); }
            else if (inputRings.SelectMany(r => r).Any(p => p.X < 0 || p.Y < 0 || p.X > 1000 || p.Y > 1000)) throw new Rejection($"out_of_range {newName}");
            polygon = new Polygon(inputRings, RingOps.Canonical(inputRings));
            op.Definition = (newName!, polygon);
        }
        Region region;
        if (binary)
        {
            Rings ar = input!.Canonical, br = b!.Canonical;
            Graph graph = new(ar, br);
            string relation = graph.Ordered.Count > 0 ? "overlap" : graph.Na == ar.Count && graph.Nb == 0 ? "within" : graph.Nb == br.Count && graph.Na == 0 ? "contains" : graph.Na == 0 && graph.Nb == 0 ? "disjoint" : "overlap";
            Region union = graph.Result("UNION"), intersection = graph.Result("INTERSECTION");
            double iou = RingOps.TotalArea(intersection) / RingOps.TotalArea(union);
            op.Crossings = graph.Ordered.Count;
            op.Lines.Add($"relation {relation} iou {RealText(iou, 6)}");
            op.Lines.Add($"crossings {op.Crossings}");
            foreach (var (p, enter) in graph.Ordered) op.Lines.Add($"crossing {p} {(enter ? "in" : "out")}");
            region = kind switch
            {
                "UNION" => union, "INTERSECTION" or "CLIP" => intersection, "DIFFERENCE" => graph.Result("DIFFERENCE"),
                _ => graph.Result("DIFFERENCE").Concat(new Graph(br, ar).Result("DIFFERENCE")).OrderBy(p => p[0][0]).ToList()
            };
            op.Target = new Target(region, (ar, br));
        }
        else { region = new Region { polygon!.Canonical }; op.Target = new Target(region); }
        Rings operandA = binary ? input!.Canonical : polygon!.Canonical;
        Values values = ResultValues(region, operandA, b?.Canonical);
        op.Lines.AddRange(values.Lines);
        op.Area = $"{number}:{string.Join(":", a)},{values.Rings},{values.Holes},{values.Vertices},{RealText(values.Area)}";
        if (!binary) op.Lines.AddRange(Properties(polygon!, values.Area));
        if (kind == "CLIP")
        {
            Rings clipped = Clip(operandA, b!.Canonical[0]);
            Rings resultRings = region.SelectMany(p => p).ToList();
            bool match = resultRings.Count == clipped.Count && resultRings.All(r => clipped.Any(c => Cyclic(r, c)));
            op.Lines.Add($"crosscheck {(match ? "match" : "mismatch")} rings {clipped.Count} vertices {clipped.Sum(r => r.Count)}");
        }
        return op;
    }
    static void Write(string name, List<string> lines)
    {
        Directory.CreateDirectory("output");
        File.WriteAllText("output/" + name, lines.Count == 0 ? "" : string.Join("\n", lines) + "\n", new System.Text.UTF8Encoding(false));
    }
    static void Main()
    {
        Polygons polygons = new();
        polygons.Read();
        Dictionary<int, Target> targets = new();
        List<string> rejections = new(polygons.Rejected), result = new(), areas = new() { "operation,rings,holes,vertices,area" }, drawing = new();
        int total = 0, succeeded = 0, defined = 0, crossings = 0;
        int[][] counts = Kinds.Select(_ => new int[2]).ToArray();
        foreach (string line in File.ReadLines("input/operations.txt")) if (line.Length > 0 && !line.StartsWith('#'))
        {
            total++;
            string kind = line.Split(' ')[0];
            int index = Array.IndexOf(Kinds, kind);
            if (index >= 0) counts[index][0]++;
            try
            {
                Operation op = Execute(total, line, polygons, targets);
                succeeded++;
                counts[index][1]++;
                crossings += op.Crossings;
                result.AddRange(op.Lines);
                if (op.Area is { } area) areas.Add(area);
                drawing.AddRange(op.Drawing);
                if (op.Target is { } target) targets[total] = target;
                if (op.Definition is { } definition) { polygons.Used.Add(definition.Name); polygons.Valid[definition.Name] = definition.Polygon; defined++; }
            }
            catch (Rejection e) { rejections.Add($"op {total} {e.Reason}"); }
        }
        result.Add($"summary polygons {polygons.Blocks} valid {polygons.ValidBlocks} invalid {polygons.Blocks - polygons.ValidBlocks} defined {defined}");
        result.Add($"summary operations {total} succeeded {succeeded} rejected {total - succeeded}");
        result.Add($"summary crossings {crossings}");
        for (int i = 0; i < Kinds.Length; i++) result.Add($"kind {Kinds[i]} {counts[i][0]} {counts[i][1]}");
        rejections.Insert(0, $"rejections {rejections.Count}");
        Write("results.txt", result);
        Write("areas.csv", areas);
        Write("render.txt", drawing);
        Write("rejections.txt", rejections);
    }
}
