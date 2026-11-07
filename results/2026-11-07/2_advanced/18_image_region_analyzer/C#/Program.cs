using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;


sealed record Rational : IComparable<Rational> {
    public long numerator { get; }
    public long denominator { get; }
    public Rational(long numerator, long denominator = 1) {
        if (denominator < 0) { numerator = -numerator; denominator = -denominator; }
        long first = Math.Abs(numerator), second = denominator;
        while (second != 0) { long remainder = first % second; first = second; second = remainder; }
        this.numerator = numerator / first; this.denominator = denominator / first;
    }
    public int CompareTo(Rational other) => (numerator * other.denominator).CompareTo(other.numerator * denominator);
}
class Program {
    public static readonly string SYMBOLS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
    public static readonly List<string> ORIENTATIONS = ["none", "horizontal", "vertical", "falling", "rising"];
    public static readonly string CSV_HEADER = "image,label,class,flags,area,x0,y0,x1,y1,cx,cy,mean,variance,min,max,contrast,border,perimeter,chain,straight,diagonal,turns,compactness,runs,holes,hole_area,euler,parent,depth,var_x,var_y,cov_xy,hu1,orientation,anisotropy,extent,mirror_lr,mirror_tb,hull_area,solidity,feret2,width2,elongation,bays,bay_area,skeleton,endpoints,branches,neighbor,distance2,codes";
    public static readonly List<Pixel> FOUR = [new Pixel(1, 0), new Pixel(0, -1), new Pixel(-1, 0), new Pixel(0, 1)];
    public static readonly List<Pixel> EIGHT = [new Pixel(1, 0), new Pixel(1, -1), new Pixel(0, -1), new Pixel(-1, -1), new Pixel(-1, 0), new Pixel(-1, 1), new Pixel(0, 1), new Pixel(1, 1)];
    public sealed record Setting(string name, int connectivity, string threshold, string polarity, List<string> operations) {
        public string method() { return threshold.Equals("otsu") || threshold.Equals("isodata") ? threshold : "fixed"; }
    }
    public sealed class Parameters {
        public int otsuTop, sweepStep, bayMin;
        public Rational isotropy = new Rational(0);
        public readonly Dictionary<string, List<Pixel>> elements = new();
        public readonly Dictionary<string, Setting> settings = new();
    }
    public sealed record Condition(string feature, string comparison, string text) {
        public bool holds(Region region) {
            int result = feature.Equals("orientation") ? StringComparer.Ordinal.Compare(region.orientation, text) : region.features[feature].CompareTo(parseRational(text));
            return comparison switch { "<" => result < 0, "<=" => result <= 0, ">" => result > 0, ">=" => result >= 0, "=" => result == 0, "!=" => result != 0, _ => throw new ArgumentException() };
        }
        public string words() { return feature + " " + comparison + " " + text; }
    }
    public sealed record Rule(string name, List<Condition> conditions) {
        public bool matches(Region region) { return conditions.All(condition => condition.holds(region)); }
    }
    public sealed class Rules {
        public readonly List<Condition> filters = new();
        public readonly List<Rule> classes = new(), flags = new();
        public List<string> classNames() {
            List<string> names = new();
            foreach (Rule rule in classes) if (!names.Contains(rule.name)) names.Add(rule.name);
            names.Add("other"); return names;
        }
    }
    public sealed record Hole(int number, List<Pixel> pixels, int owner);
    public sealed class Region {
        public readonly int number;
        public readonly List<Pixel> pixels;
        public readonly Dictionary<string, Rational> features = new();
        public List<int> codes = new();
        public HashSet<Pixel> skeleton = new();
        public long hullDoubled, distance;
        public Region parent;
        public int depth, droppedBy = -1, neighbor = -1;
        public readonly List<Region> children = new();
        public bool kept;
        public string className = "other", orientation = "none";
        public readonly List<string> flags = new();
        public Region(int number, List<Pixel> pixels) { this.number = number; this.pixels = pixels; }
        public void Add(string name, long value) { features.Add(name, new Rational(value)); }
        public void Add(string name, long numerator, long denominator) { features.Add(name, new Rational(numerator, denominator)); }
        public long integer(string name) { return features[name].numerator; }
    }
    public static Rational parseRational(string text) {
        string[] parts = text.Split('/');
        return new Rational(long.Parse(parts[0]), parts.Length == 1 ? 1 : long.Parse(parts[1]));
    }
    public static Parameters readParameters(string path) {
        Parameters result = new();
        foreach (string line in PgmReader.lines(path)) {
            List<string> words = line.Split(' ').ToList();
            switch (words[0]) {
                case "otsu_top": result.otsuTop = int.Parse(words[1]); break;
                case "sweep": result.sweepStep = int.Parse(words[1]); break;
                case "isotropy": result.isotropy = parseRational(words[1]); break;
                case "bay_min": result.bayMin = int.Parse(words[1]); break;
                case "element": {
                    int ox = int.Parse(words[4]), oy = int.Parse(words[5]);
                    List<Pixel> offsets = new();
                    for (int y = 6; y < words.Count; y++) for (int x = 0; x < words[y].Length; x++)
                        if (words[y][x] == '#') offsets.Add(new Pixel(x - ox, y - 6 - oy));
                    result.elements[words[1]] = offsets; break;
                }
                case "image": result.settings[words[1]] = new Setting(words[1], int.Parse(words[2]), words[3], words[4], words.Skip(5).ToList()); break;
                default: throw new ArgumentException();
            }
        }
        return result;
    }
    public static Rules readRules(string path)  {
        Rules result = new Rules();
        foreach (string line in PgmReader.lines(path)) {
            string[] words = line.Split(' ');
            if (words[0].Equals("filter")) result.filters.Add(new Condition(words[1], words[2], words[3]));
            else {
                List<Condition> conditions = new();
                for (int i = 2; i < words.Length; i += 3) conditions.Add(new Condition(words[i], words[i + 1], words[i + 2]));
                (words[0].Equals("class") ? result.classes : result.flags).Add(new Rule(words[1], conditions));
            }
        }
        return result;
    }
    public static int count(bool[][] mask) { int count = 0; foreach (bool[] row in mask) foreach (bool flag in row) if (flag) count++; return count; }
    public static List<List<Pixel>> groups(int[][] labels, int count) {
        List<List<Pixel>> groups = new(); for (int i = 0; i <= count; i++) groups.Add(new());
        for (int y = 0; y < labels.Length; y++) for (int x = 0; x < labels[0].Length; x++) groups[labels[y][x]].Add(new Pixel(x, y));
        return groups;
    }
    public static List<List<Pixel>> enclosed(bool[][] mask, int connectivity) {
        int height = mask.Length, width = mask[0].Length; bool[][] background = Enumerable.Range(0, height).Select(_ => new bool[width]).ToArray();
        for (int y = 0; y < height; y++) for (int x = 0; x < width; x++) background[y][x] = !mask[y][x];
        LabelResult result = Labeling.label(background, connectivity); List<List<Pixel>> enclosed = new();
        foreach (List<Pixel> pixels in groups(result.labels, result.count).Skip(1)) {
            bool onEdge = pixels.Any(point => point.x == 0 || point.y == 0 || point.x == width - 1 || point.y == height - 1);
            if (!onEdge) enclosed.Add(pixels);
        }
        return enclosed;
    }
    public static bool[][] fill(bool[][] mask, int connectivity) {
        bool[][] filled = mask.Select(row => row.ToArray()).ToArray();
        foreach (List<Pixel> pixels in enclosed(mask, connectivity)) foreach (Pixel point in pixels) filled[point.y][point.x] = true;
        return filled;
    }
    public static long cross(Pixel a, Pixel b, Pixel p) { return (long) (b.x - a.x) * (p.y - a.y) - (long) (b.y - a.y) * (p.x - a.x); }
    public static long distance(Pixel a, Pixel b) { long dx = a.x - b.x, dy = a.y - b.y; return dx * dx + dy * dy; }
    public static List<Pixel> halfHull(List<Pixel> points) {
        List<Pixel> chain = new();
        foreach (Pixel point in points) { while (chain.Count >= 2 && cross(chain[chain.Count - 2], chain[^1], point) <= 0) chain.RemoveAt(chain.Count - 1); chain.Add(point); }
        return chain;
    }
    public static List<Pixel> hull(List<Pixel> pixels) {
        HashSet<Pixel> corners = new();
        foreach (Pixel point in pixels) { corners.Add(point); corners.Add(new Pixel(point.x + 1, point.y)); corners.Add(new Pixel(point.x, point.y + 1)); corners.Add(new Pixel(point.x + 1, point.y + 1)); }
        List<Pixel> ordered = corners.OrderBy(point => point.x).ThenBy(point => point.y).ToList();
        List<Pixel> lower = halfHull(ordered), upper = halfHull(ordered.AsEnumerable().Reverse().ToList());
        List<Pixel> hull = lower.Take(lower.Count - 1).ToList(); hull.AddRange(upper.GetRange(0, upper.Count - 1)); return hull;
    }
    public static bool containsCenter(List<Pixel> hull, int x, int y) {
        Pixel center = new Pixel(2 * x + 1, 2 * y + 1);
        for (int i = 0; i < hull.Count; i++) { Pixel a = hull[i], b = hull[(i + 1) % hull.Count]; if (cross(new Pixel(2 * a.x, 2 * a.y), new Pixel(2 * b.x, 2 * b.y), center) < 0) return false; }
        return true;
    }
    public static string meanText(long total, int count) { return count == 0 ? "-" : Report.DecimalText(new Rational(total, count), 2); }
    public static string orientationLine(List<Region> regions) {
        List<string> parts = ["orientations"];
        foreach (string name in ORIENTATIONS) { parts.Add(name); parts.Add("" + regions.Count(region => region.orientation == name)); }
        return string.Join(" ", parts);
    }
    public sealed class Analysis {
        public readonly Image image;
        public readonly Setting setting;
        public readonly Parameters parameters;
        public readonly int width, height, connectivity, complement, cutoff;
        public readonly Histogram histogram;
        public readonly OtsuResult otsu;
        public readonly IsodataResult isodata;
        public readonly bool[][] initial, mask;
        public readonly List<int> morphCounts = new();
        public readonly List<int[]> sweep = new();
        public readonly int[][] labels, holeOf;
        public readonly int provisional, fourComponents, eightComponents, bitQuad;
        public readonly List<Region> regions = new();
        public readonly List<Hole> holes = new();
        public Analysis(Image image, Setting setting, Parameters parameters) {
            this.image = image; this.setting = setting; this.parameters = parameters; width = image.width; height = image.height; connectivity = setting.connectivity; complement = 12 - connectivity;
            histogram = new Histogram(image); otsu = Threshold.otsu(histogram); isodata = Threshold.isodata(histogram);
            cutoff = setting.threshold switch { "otsu" => otsu.cutoff, "isodata" => isodata.cutoff, _ => int.Parse(setting.threshold) };
            initial = binarize(cutoff); bool[][] current = initial;
            foreach (string operation in setting.operations) { current = this.operation(current, operation); morphCounts.Add(count(current)); }
            mask = current;
            for (int t = parameters.sweepStep; t < image.maxval; t += parameters.sweepStep) { bool[][] binary = binarize(t); sweep.Add(new int[] {t, count(binary), Labeling.label(binary, connectivity).count}); }
            LabelResult labeled = Labeling.label(mask, connectivity); labels = labeled.labels; provisional = labeled.provisional;
            List<List<Pixel>> pixels = groups(labels, labeled.count); for (int j = 1; j <= labeled.count; j++) regions.Add(new Region(j, pixels[j]));
            fourComponents = Labeling.label(mask, 4).count; eightComponents = Labeling.label(mask, 8).count; bitQuad = Labeling.bitQuad(mask, connectivity);
            holeOf = Enumerable.Range(0, height).Select(_ => new int[width]).ToArray();
            foreach (List<Pixel> holePixels in enclosed(mask, complement)) {
                Pixel first = holePixels[0]; Hole hole = new Hole(holes.Count + 1, holePixels, labels[first.y - 1][first.x]);
                holes.Add(hole); foreach (Pixel point in holePixels) holeOf[point.y][point.x] = hole.number;
            }
            foreach (Region region in regions) {
                Pixel first = region.pixels[0];
                if (first.y >= 1 && holeOf[first.y - 1][first.x] > 0) {
                    int owner = holes[holeOf[first.y - 1][first.x] - 1].owner; region.parent = regions[owner - 1]; region.depth = region.parent.depth + 1; region.parent.children.Add(region);
                }
            }
            foreach (Region region in regions) measure(region);
        }
        public bool[][] binarize(int threshold) {
            bool[][] binary = Enumerable.Range(0, height).Select(_ => new bool[width]).ToArray();
            for (int y = 0; y < height; y++) for (int x = 0; x < width; x++) binary[y][x] = setting.polarity.Equals("bright") ? image.pixels[y][x] > threshold : image.pixels[y][x] <= threshold;
            return binary;
        }
        public bool[][] operation(bool[][] source, string operation) {
            if (operation.Equals("fill")) return fill(source, complement);
            string[] words = operation.Split(':'); List<Pixel> offsets = parameters.elements[words[1]];
            return words[0] switch { "erode" => Morphology.erode(source, offsets), "dilate" => Morphology.dilate(source, offsets), "open" => Morphology.opening(source, offsets), "close" => Morphology.closing(source, offsets), _ => throw new ArgumentException() };
        }
        public int labelAt(int x, int y) { return x >= 0 && x < width && y >= 0 && y < height ? labels[y][x] : -1; }
        public void measure(Region region) {
            long area = region.pixels.Count, sumI = 0, sumII = 0, sumX = 0, sumY = 0, sumXX = 0, sumYY = 0, sumXY = 0;
            int x0 = width, y0 = height, x1 = -1, y1 = -1, minimum = image.maxval, maximum = 0, perimeter = 0, runs = 0;
            HashSet<Pixel> surrounding = new(); List<Pixel> neighbors = complement == 4 ? FOUR : EIGHT;
            foreach (Pixel point in region.pixels) {
                int x = point.x, y = point.y, value = image.pixels[y][x];
                x0 = Math.Min(x0, x); y0 = Math.Min(y0, y); x1 = Math.Max(x1, x); y1 = Math.Max(y1, y); minimum = Math.Min(minimum, value); maximum = Math.Max(maximum, value);
                sumI += value; sumII += (long) value * value; sumX += x; sumY += y; sumXX += x * x; sumYY += y * y; sumXY += x * y;
                foreach (Pixel offset in EIGHT) if (labelAt(x + offset.x, y + offset.y) == 0) surrounding.Add(new Pixel(x + offset.x, y + offset.y));
                foreach (Pixel offset in neighbors) if (labelAt(x + offset.x, y + offset.y) != region.number) { perimeter++; break; }
                if (labelAt(x - 1, y) != region.number) runs++;
            }
            region.Add("area", area); region.Add("x0", x0); region.Add("y0", y0); region.Add("x1", x1); region.Add("y1", y1);
            region.Add("width", x1 - x0 + 1); region.Add("height", y1 - y0 + 1); region.Add("border", x0 == 0 || y0 == 0 || x1 == width - 1 || y1 == height - 1 ? 1 : 0);
            region.Add("mean", sumI, area); region.Add("variance", area * sumII - sumI * sumI, area * area); region.Add("min", minimum); region.Add("max", maximum);
            long sumSurrounding = 0; foreach (Pixel point in surrounding) sumSurrounding += image.pixels[point.y][point.x];
            if (surrounding.Count == 0) region.Add("contrast", 0); else region.Add("contrast", sumI * surrounding.Count - sumSurrounding * area, area * surrounding.Count);
            region.Add("perimeter", perimeter); region.Add("runs", runs); region.codes = chainCode(region);
            int straight = connectivity == 4 ? region.codes.Count : (int) region.codes.Count(code => code % 2 == 0), diagonal = region.codes.Count - straight, turns = 0;
            for (int i = 0; i < region.codes.Count; i++) if (!region.codes[i].Equals(region.codes[(i + region.codes.Count - 1) % region.codes.Count])) turns++;
            region.Add("chain", region.codes.Count); region.Add("straight", straight); region.Add("diagonal", diagonal); region.Add("turns", turns);
            long length = 5L * straight + 7L * diagonal; region.Add("compactness", length * length, 25 * area);
            int owned = 0, holeArea = 0; foreach (Hole hole in holes) if (hole.owner == region.number) { owned++; holeArea += hole.pixels.Count; }
            region.Add("holes", owned); region.Add("hole_area", holeArea); region.Add("euler", 1 - owned); region.Add("depth", region.depth);
            long m20 = area * sumXX - sumX * sumX, m02 = area * sumYY - sumY * sumY, m11 = area * sumXY - sumX * sumY;
            region.Add("cx", sumX, area); region.Add("cy", sumY, area); region.Add("var_x", m20, area * area); region.Add("var_y", m02, area * area); region.Add("cov_xy", m11, area * area); region.Add("hu1", m20 + m02, area * area * area);
            Rational anisotropy = m20 + m02 == 0 ? new Rational(0) : new Rational(Math.Abs(m20 - m02) + 2 * Math.Abs(m11), m20 + m02); region.features.Add("anisotropy", anisotropy);
            long u = m20 - m02, v = 2 * m11;
            if (anisotropy.CompareTo(parameters.isotropy) > 0) region.orientation = Math.Abs(v) >= Math.Abs(u) ? (v > 0 ? "falling" : "rising") : (u > 0 ? "horizontal" : "vertical");
            region.Add("extent", area, (long) (x1 - x0 + 1) * (y1 - y0 + 1)); int lr = 0, tb = 0;
            foreach (Pixel point in region.pixels) { if (labelAt(x0 + x1 - point.x, point.y) == region.number) lr++; if (labelAt(point.x, y0 + y1 - point.y) == region.number) tb++; }
            region.Add("mirror_lr", lr, area); region.Add("mirror_tb", tb, area); measureHull(region, x0, y0, x1, y1);
            region.skeleton = Morphology.thin(region.pixels); int endpoints = 0, branches = 0;
            foreach (Pixel point in region.skeleton) { int crossing = Morphology.crossing(region.skeleton, point); if (crossing == 1) endpoints++; if (crossing >= 3) branches++; }
            region.Add("skeleton", region.skeleton.Count); region.Add("endpoints", endpoints); region.Add("branches", branches);
        }
        public List<int> chainCode(Region region) {
            List<Pixel> directions = connectivity == 4 ? FOUR : EIGHT, visited = [region.pixels[0]]; List<int> codes = new(); int heading = directions.Count - 1;
            while (true) {
                Pixel point = visited[^1]; int start = connectivity == 4 ? (heading + 3) % 4 : (heading + (heading % 2 == 0 ? 7 : 6)) % 8, chosen = -1;
                for (int offset = 0; offset < directions.Count; offset++) { int direction = (start + offset) % directions.Count; Pixel delta = directions[direction]; if (labelAt(point.x + delta.x, point.y + delta.y) == region.number) { chosen = direction; break; } }
                if (chosen < 0) return new();
                Pixel step = directions[chosen]; visited.Add(new Pixel(point.x + step.x, point.y + step.y)); codes.Add(chosen); heading = chosen;
                int moves = codes.Count; if (moves >= 2 && visited[moves].Equals(visited[1]) && visited[moves - 1].Equals(visited[0])) return codes.Take(moves - 1).ToList();
            }
        }
        public void measureHull(Region region, int x0, int y0, int x1, int y1) {
            List<Pixel> hull = Program.hull(region.pixels); long doubled = 0, feret = 0; Rational width2 = null;
            for (int i = 0; i < hull.Count; i++) {
                Pixel a = hull[i], b = hull[(i + 1) % hull.Count]; doubled += (long) a.x * b.y - (long) b.x * a.y; long reach = 0;
                foreach (Pixel point in hull) { reach = Math.Max(reach, Math.Abs(cross(a, b, point))); feret = Math.Max(feret, distance(a, point)); }
                Rational trial = new Rational(reach * reach, distance(a, b)); if (width2 == null || trial.CompareTo(width2) < 0) width2 = trial;
            }
            region.hullDoubled = Math.Abs(doubled); region.Add("solidity", 2L * region.pixels.Count, region.hullDoubled); region.Add("feret2", feret); region.features.Add("width2", width2); region.Add("elongation", feret * width2.denominator, width2.numerator);
            bool[][] bayMask = Enumerable.Range(0, y1 - y0 + 1).Select(_ => new bool[x1 - x0 + 1]).ToArray();
            for (int y = y0; y <= y1; y++) for (int x = x0; x <= x1; x++) bayMask[y - y0][x - x0] = labels[y][x] == 0 && holeOf[y][x] == 0 && containsCenter(hull, x, y);
            LabelResult bays = Labeling.label(bayMask, complement); int[] sizes = new int[bays.count + 1]; foreach (int[] row in bays.labels) foreach (int label in row) sizes[label]++;
            int bayCount = 0, bayArea = 0; for (int j = 1; j < sizes.Length; j++) { if (sizes[j] >= parameters.bayMin) bayCount++; bayArea += sizes[j]; }
            region.Add("bays", bayCount); region.Add("bay_area", bayArea);
        }
        public List<Region> kept() { return regions.Where(region => region.kept).ToList(); }
        public void applyRules(Rules rules) {
            foreach (Region region in regions) {
                for (int i = 0; i < rules.filters.Count; i++) if (!rules.filters[i].holds(region)) { region.droppedBy = i; break; }
                if (region.droppedBy >= 0) continue;
                region.kept = true; foreach (Rule rule in rules.classes) if (rule.matches(region)) { region.className = rule.name; break; }
                foreach (Rule rule in rules.flags) if (rule.matches(region)) region.flags.Add(rule.name);
            }
            List<Region> kept = this.kept();
            foreach (Region region in kept) foreach (Region other in kept) if (other != region) {
                long dx = region.integer("x0") + region.integer("x1") - other.integer("x0") - other.integer("x1"), dy = region.integer("y0") + region.integer("y1") - other.integer("y0") - other.integer("y1"); long distance = dx * dx + dy * dy;
                if (region.neighbor < 0 || distance < region.distance) { region.neighbor = other.number; region.distance = distance; }
            }
        }
        public string tree(Region region) { return region.children.Count == 0 ? "" + region.number : region.number + "(" + string.Join(" ", region.children.Select(tree).ToList()) + ")"; }
        public List<string> thresholdLines() {
            List<string> lines = new List<string>(["image " + image.name + " size " + width + " " + height + " maxval " + image.maxval,
                "histogram pixels " + histogram.pixels + " min " + histogram.minimum + " max " + histogram.maximum + " mean " + meanText(histogram.total, histogram.pixels) + " median " + histogram.median + " mode " + histogram.mode + " levels " + histogram.levels]);
            List<string> bins = ["bins", "" + histogram.binWidth]; foreach (int bin in histogram.bins) bins.Add("" + bin); lines.Add(string.Join(" ", bins));
            lines.Add("otsu threshold " + otsu.cutoff + " upper " + otsu.upper + " candidates " + otsu.candidates.Count);
            for (int i = 0; i < Math.Min(parameters.otsuTop, otsu.candidates.Count); i++) {
                Candidate candidate = otsu.candidates[i]; Split split = candidate.split; Rational gap = new Rational(split.sumAbove * split.below - split.sumBelow * split.above, (long) split.below * split.above);
                lines.Add("rank " + (i + 1) + " t " + candidate.cutoff + " below " + split.below + " above " + split.above + " mean_below " + meanText(split.sumBelow, split.below) + " mean_above " + meanText(split.sumAbove, split.above) + " gap " + Report.DecimalText(gap, 2));
            }
            lines.Add("isodata threshold " + isodata.cutoff + " iterations " + isodata.iterations); lines.Add("threshold " + cutoff + " " + setting.method() + " " + setting.polarity + " foreground " + count(initial));
            for (int i = 0; i < morphCounts.Count; i++) lines.Add("morph " + setting.operations[i] + " foreground " + morphCounts[i]);
            foreach (int[] result in sweep) lines.Add("sweep " + result[0] + " foreground " + result[1] + " regions " + result[2]); return lines;
        }
        public char symbol(int x, int y, bool skeletonOnly) {
            int label = labels[y][x]; if (label == 0) return holeOf[y][x] > 0 ? ':' : '.';
            Region region = regions[label - 1]; if (skeletonOnly && !region.skeleton.Contains(new Pixel(x, y))) return '+'; return region.kept ? SYMBOLS[label % 62] : '#';
        }
        public List<string> mapLines() {
            string size = image.name + " " + width + " " + height; List<string> lines = ["morphology " + size];
            for (int y = 0; y < height; y++) { StringBuilder row = new StringBuilder(); for (int x = 0; x < width; x++) row.Append(mask[y][x] ? (initial[y][x] ? '#' : '+') : (initial[y][x] ? '-' : '.')); lines.Add(row.ToString()); }
            foreach (bool skeletonOnly in new bool[] {false, true}) { lines.Add((skeletonOnly ? "skeleton " : "labels ") + size); for (int y = 0; y < height; y++) { StringBuilder row = new StringBuilder(); for (int x = 0; x < width; x++) row.Append(symbol(x, y, skeletonOnly)); lines.Add(row.ToString()); } }
            return lines;
        }
        public string csv(Region region) {
            List<string> fields = new();
            foreach (string field in CSV_HEADER.Split(',')) fields.Add(field switch {
                "image" => image.name, "label" => "" + region.number, "class" => region.className, "flags" => region.flags.Count == 0 ? "-" : string.Join("+", region.flags),
                "parent" => region.parent == null ? "-" : "" + region.parent.number, "orientation" => region.orientation, "hull_area" => Report.hullArea(region.hullDoubled),
                "neighbor" => region.neighbor < 0 ? "-" : "" + region.neighbor, "distance2" => region.neighbor < 0 ? "-" : Report.DecimalText(new Rational(region.distance, 4), 2),
                "codes" => region.codes.Count == 0 ? "-" : string.Join("", region.codes.Select(code => code.ToString(CultureInfo.InvariantCulture)).ToList()),
                "cx" or "cy" or "compactness" or "var_x" or "var_y" or "cov_xy" or "anisotropy" or "extent" or "mirror_lr" or "mirror_tb" or "solidity" or "width2" or "elongation" => Report.DecimalText(region.features[field], 3),
                "mean" or "variance" or "contrast" => Report.DecimalText(region.features[field], 2), "hu1" => Report.DecimalText(region.features[field], 4), _ => "" + region.integer(field),
            });
            return string.Join(",", fields);
        }
        public string intensity(bool foreground) {
            long total = 0; int count = 0; for (int y = 0; y < height; y++) for (int x = 0; x < width; x++) if (mask[y][x] == foreground) { total += image.pixels[y][x]; count++; } return meanText(total, count);
        }
        public List<string> summary(Rules rules) {
            List<Region> kept = this.kept(); int holePixels = holes.Sum(hole => hole.pixels.Count);
            List<string> lines = new List<string>(["image " + image.name, "threshold " + cutoff + " " + setting.method() + " " + setting.polarity + " conn " + connectivity,
                "foreground " + count(initial) + " " + count(mask), "regions " + regions.Count + " provisional " + provisional + " kept " + kept.Count + " dropped " + (regions.Count - kept.Count),
                "connectivity four " + fourComponents + " eight " + eightComponents, "holes " + holes.Count + " hole_pixels " + holePixels + " euler " + (regions.Count - holes.Count) + " bitquad " + bitQuad]);
            foreach (Hole hole in holes) {
                int x0 = width, y0 = height, x1 = -1, y1 = -1; foreach (Pixel point in hole.pixels) { x0 = Math.Min(x0, point.x); y0 = Math.Min(y0, point.y); x1 = Math.Max(x1, point.x); y1 = Math.Max(y1, point.y); }
                lines.Add("hole " + hole.number + " owner " + hole.owner + " area " + hole.pixels.Count + " box " + x0 + " " + y0 + " " + x1 + " " + y1);
            }
            lines.Add("depth_max " + regions.Select(region => region.depth).DefaultIfEmpty(0).Max()); List<string> trees = regions.Where(region => region.parent == null).Select(tree).ToList(); lines.Add(trees.Count == 0 ? "tree" : "tree " + string.Join(" ", trees));
            lines.Add("intensity foreground " + intensity(true) + " background " + intensity(false));
            if (kept.Count == 0) lines.Add("area total 0 mean - largest - smallest -");
            else {
                Region largest = kept[0], smallest = largest; long total = 0;
                foreach (Region region in kept) { total += region.integer("area"); if (region.integer("area") > largest.integer("area")) largest = region; if (region.integer("area") < smallest.integer("area")) smallest = region; }
                lines.Add("area total " + total + " mean " + meanText(total, kept.Count) + " largest " + largest.number + " " + largest.integer("area") + " smallest " + smallest.number + " " + smallest.integer("area"));
            }
            List<string> classes = ["classes"]; foreach (string name in rules.classNames()) { classes.Add(name); classes.Add("" + kept.Count(region => region.className == name)); } lines.Add(string.Join(" ", classes)); lines.Add(orientationLine(kept));
            List<string> flags = ["flags"]; foreach (Rule rule in rules.flags) { flags.Add(rule.name); flags.Add("" + kept.Count(region => region.flags.Contains(rule.name))); } lines.Add(string.Join(" ", flags)); return lines;
        }
    }
    public static List<string> overall(List<Analysis> analyses, Rules rules) {
        List<Region> regions = new(); int holeCount = 0; foreach (Analysis analysis in analyses) { regions.AddRange(analysis.regions); holeCount += analysis.holes.Count; }
        List<Region> kept = regions.Where(region => region.kept).ToList();
        List<string> lines = ["overall", "images " + analyses.Count, "regions " + regions.Count + " kept " + kept.Count + " dropped " + (regions.Count - kept.Count), "holes " + holeCount + " euler " + (regions.Count - holeCount)];
        for (int i = 0; i < rules.filters.Count; i++) { int filter = i; lines.Add("filter " + (i + 1) + " " + rules.filters[i].words() + " dropped " + regions.Count(region => region.droppedBy == filter)); }
        foreach (string name in rules.classNames()) { List<Region> members = kept.Where(region => region.className == name).ToList(); long total = members.Sum(region => region.integer("area")); lines.Add("class " + name + " count " + members.Count + " area " + total + " mean " + meanText(total, members.Count)); }
        foreach (Rule rule in rules.flags) lines.Add("flag " + rule.name + " count " + kept.Count(region => region.flags.Contains(rule.name))); lines.Add(orientationLine(kept));
        Region largest = null; string imageName = null;
        foreach (Analysis analysis in analyses) foreach (Region region in analysis.kept()) if (largest == null || region.integer("area") > largest.integer("area")) { largest = region; imageName = analysis.image.name; }
        lines.Add(largest == null ? "largest -" : "largest " + imageName + " " + largest.number + " " + largest.integer("area")); return lines;
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Parameters parameters = readParameters("input/params.txt"); Rules rules = readRules("input/rules.txt"); List<Analysis> analyses = new();
        foreach (Image image in PgmReader.read("input/images.txt")) { Analysis analysis = new Analysis(image, parameters.settings[image.name], parameters); analysis.applyRules(rules); analyses.Add(analysis); }
        List<string> thresholds = new(), maps = new(), rows = [CSV_HEADER], summary = new();
        foreach (Analysis analysis in analyses) { thresholds.AddRange(analysis.thresholdLines()); maps.AddRange(analysis.mapLines()); foreach (Region region in analysis.kept()) rows.Add(analysis.csv(region)); summary.AddRange(analysis.summary(rules)); }
        summary.AddRange(overall(analyses, rules)); Dictionary<string, List<string>> files = new(); files.Add("thresholds.txt", thresholds); files.Add("labels.txt", maps); files.Add("regions.csv", rows); files.Add("summary.txt", summary); Report.write(files);
    }
}
