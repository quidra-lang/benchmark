using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
public static class Program {
    public static readonly string[] NAMES = { "sad",    "ssd",       "census",   "sgm",
                                              "fusion", "wta_final", "sgm_final" },
                                    SOURCES = { "kept", "median", "background", "interpolated",
                                                "none" };
    public static readonly int[] REASONS = { 50, 100, 150, 200, 255 };
    public static readonly string[] REASON_NAMES = { "textureless", "nonunique", "outside",
                                                     "mismatch", "occluded" };
    public static int w, h, size, min, max;
    public static long focal, baseline;
    public static int[] left, right, truth;
    public static long[] strengths;
    public static PgmIo.Parameters settings;
    public static Evaluation.Regions regions;
    public static readonly Method[] methods = new Method[7];
    public static long[][] summed;
    public static readonly List<string> sweeps = new();
    public sealed class Method {
        public int[] image, reasons, lr, sources, votes;
        public long[] margins;
        public int window, bounds, speckles, specklePixels, medianChanged;
        public Method(int[] image) { this.image = image; }
    }
    public sealed class ObjectInfo {
        public int count, x0, y0, x1, y1, min, max, median, layer, hits, union
        , first;
        public long total;
    }
    public static int P(string name) { return settings.Integer(name); }
    public static string Two(long a, long b) { return Refinement.Two(a, b); }
    public static string Ratio(long a, long b) { return Evaluation.Ratio(a, b); }
    public static int Median(List<int> values) {
        values.Sort();
        return values[(values.Count - 1) / 2];
    }
    public static int Valid(int[] image) {
        int count = 0;
        foreach (int d in image)
            if (d != 0)
                count++;
        return count;
    }
    public static bool Consistent(int pixel, int d, int[] rightDisparity) {
        return pixel % w >= d && Math.Abs(d - rightDisparity[pixel - d]) <= P("lr_max_diff");
    }
    public static Method Select(long[][] volume) {
        int[] rightDisparity = new int[size];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++) {
                int pixel = y * w + x;
                long best = long.MaxValue;
                for (int d = min; d <= max && x + d < w; d++)
                    if (volume[pixel + d][d - min] < best) {
                        best = volume[pixel + d][d - min];
                        rightDisparity[pixel] = d;
                    }
            }
        Method result = new Method(new int[size]);
        result.reasons = new int[size];
        result.margins = new long[size];
        result.lr = new int[4];
        for (int pixel = 0; pixel < size; pixel++) {
            long[] row = volume[pixel];
            int d1 = min;
            for (int d = min + 1; d <= max; d++)
                if (row[d - min] < row[d1 - min])
                    d1 = d;
            long first = row[d1 - min], second = long.MaxValue;
            for (int d = min; d <= max; d++)
                if (Math.Abs(d - d1) >= 2)
                    second = Math.Min(second, row[d - min]);
            if (d1 == min || d1 == max)
                result.bounds++;
            int reason = 0;
            if (strengths[pixel] < P("texture_threshold"))
                reason = 50;
            else if (100 * second <= (100L + P("uniqueness")) * first)
                reason = 100;
            else if (pixel % w < d1)
                reason = 150;
            else if (!Consistent(pixel, d1, rightDisparity)) {
                bool found = false;
                for (int d = min; d <= max; d++)
                    if (Consistent(pixel, d, rightDisparity))
                        found = true;
                reason = found ? 200 : 255;
            } else {
                result.image[pixel] = d1;
                result.margins[pixel] = second - first;
            }
            result.reasons[pixel] = reason;
            if (reason == 0 || reason == 200 || reason == 255)
                result.lr[Math.Min(3, Math.Abs(d1 - rightDisparity[pixel - d1]))]++;
        }
        return result;
    }
    public static long[][] Costs(int[] cl, int[] cr, string kind, int window) {
        return Costs.Volume(left, right, cl, cr, w, h, kind, window, min, max);
    }
    public static void Estimate() {
        int[] cl = Costs.Census(left, w, h), cr = Costs.Census(right, w, h);
        for (int k = 0; k < 3; k++) {
            Evaluation.Metrics best = null;
            foreach (int window in settings.Integers(NAMES[k] + "_windows")) {
                Method method = Select(Costs(cl, cr, NAMES[k], window));
                method.window = window;
                Evaluation.Metrics score = Evaluation.Evaluate(method.image, truth, regions.nonocc);
                sweeps.Add("sweep " + NAMES[k] + " window " + window + " valid " +
                           Valid(method.image) + " bad1 " + Ratio(score.bad1, score.pixels) +
                           " bad2 " + Ratio(score.bad2, score.pixels));
                if (best == null || score.bad1 < best.bad1 ||
                    (score.bad1 == best.bad1 && score.bad2 < best.bad2)) {
                    best = score;
                    methods[k] = method;
                }
            }
        }
        long[][] baseCosts = Costs(cl, cr, settings.Text("sgm_cost"), P("sgm_window"));
        summed = Enumerable.Range(0, size)
                     .Select(
                         _ => new long[max - min + 1])
                     .ToArray();
        for (int i = 0; i < P("sgm_paths"); i++) {
            Aggregation.Accumulate(summed, Aggregation.Path(baseCosts, left, w, h, i, P("p1"),
                                                            P("p2"), P("p2_gamma")));
            methods[3] = Select(summed);
            Evaluation.Metrics score = Evaluation.Evaluate(methods[3].image, truth, regions.nonocc);
            sweeps.Add("paths " + (i + 1) + " valid " + Valid(methods[3].image) + " bad1 " +
                       Ratio(score.bad1, score.pixels) + " bad2 " +
                       Ratio(score.bad2, score.pixels));
        }
        methods[3].window = P("sgm_window");
    }
    public static List<List<int>> Components(int[] image, int range) {
        bool[] visited = new bool[size];
        List<List<int>> result = new();
        for (int start = 0; start < size; start++)
            if (image[start] != 0 && !visited[start]) {
                List<int> part = new();
                Stack<int> stack = new();
                stack.Push(start);
                visited[start] = true;
                while (stack.Count != 0) {
                    int pixel = stack.Pop(), x = pixel % w, y = pixel / w;
                    part.Add(pixel);
                    for (int k = 0; k < 4; k++) {
                        int xx = x + Aggregation.DIRECTIONS[k][0],
                            yy = y + Aggregation.DIRECTIONS[k][1];
                        if (xx >= 0 && xx < w && yy >= 0 && yy < h) {
                            int q = yy * w + xx;
                            if (!visited[q] && image[q] != 0 &&
                                Math.Abs(image[q] - image[pixel]) <= range) {
                                visited[q] = true;
                                stack.Push(q);
                            }
                        }
                    }
                }
                result.Add(part);
            }
        return result;
    }
    public static List<int> Rays(int[] image, int pixel, bool background) {
        int x = pixel % w, y = pixel / w;
        List<int> result = new();
        int count = background ? 2 : 8;
        for (int k = 0; k < count; k++) {
            int dx = Aggregation.DIRECTIONS[k][0], dy = Aggregation.DIRECTIONS[k][1], xx = x + dx,
                yy = y + dy;
            while (xx >= 0 && xx < w && yy >= 0 && yy < h) {
                int value = image[yy * w + xx];
                if (value != 0) {
                    result.Add(value);
                    break;
                }
                xx += dx;
                yy += dy;
            }
        }
        return result;
    }
    public static Method Postprocess(Method source) {
        int[] original = source.image, filtered = original.ToArray();
        Method result = new Method(new int[size]);
        foreach (List<int> part in Components(original, P("speckle_range")))
            if (part.Count < P("speckle_size")) {
                result.speckles++;
                result.specklePixels += part.Count;
                foreach (int pixel in part)
                    filtered[pixel] = 0;
            }
        int[] medians = new int[size];
        for (int pixel = 0; pixel < size; pixel++)
            if (filtered[pixel] != 0) {
                int x = pixel % w, y = pixel / w;
                List<int> values = new();
                for (int yy = Math.Max(0, y - 1); yy <= Math.Min(h - 1, y + 1); yy++)
                    for (int xx = Math.Max(0, x - 1); xx <= Math.Min(w - 1, x + 1); xx++)
                        if (filtered[yy * w + xx] != 0)
                            values.Add(filtered[yy * w + xx]);
                medians[pixel] = Median(values);
                if (medians[pixel] != filtered[pixel])
                    result.medianChanged++;
            }
        result.image = medians.ToArray();
        result.sources = new int[size];
        Array.Fill(result.sources, 4);
        for (int pixel = 0; pixel < size; pixel++) {
            if (medians[pixel] != 0)
                result.sources[pixel] = medians[pixel] == original[pixel] ? 0 : 1;
            else {
                bool background = source.reasons[pixel] == 150 || source.reasons[pixel] == 255;
                List<int> values = Rays(medians, pixel, background);
                if (values.Count != 0) {
                    result.image[pixel] = background ? values.Min() : Median(values);
                    result.sources[pixel] = background ? 2 : 3;
                }
            }
        }
        return result;
    }
    public static void Fuse() {
        Method result = new Method(new int[size]);
        result.votes = new int[5];
        for (int pixel = 0; pixel < size; pixel++) {
            List<int> values = new();
            for (int k = 0; k < 4; k++)
                if (methods[k].image[pixel] != 0)
                    values.Add(methods[k].image[pixel]);
            result.votes[values.Count]++;
            if (values.Count != 0) {
                int median = Median(values), agree = 0;
                foreach (int value in values)
                    if (Math.Abs(value - median) <= 1)
                        agree++;
                if (agree >= P("fusion_min_votes"))
                    result.image[pixel] = median;
            }
        }
        methods[4] = result;
        int selected = Array.IndexOf(NAMES, settings.Text("wta_cost"));
        methods[5] = Postprocess(methods[selected]);
        methods[6] = Postprocess(methods[3]);
    }
    public static List<string> Objects() {
        List<ObjectInfo> objects = new();
        int small = 0, totalPixels = 0;
        int[] trueCounts = new int[max + 1];
        foreach (int d in truth)
            if (d != 0)
                trueCounts[d]++;
        foreach (List<int> part in Components(methods[6].image, P("object_range"))) {
            if (part.Count < P("object_min_size")) {
                small++;
                continue;
            }
            ObjectInfo item = new ObjectInfo();
            item.count = part.Count;
            item.x0 = w;
            item.y0 = h;
            item.first = size;
            List<int> disparities = new();
            int[] counts = new int[max + 1];
            foreach (int pixel in part) {
                item.x0 = Math.Min(item.x0, pixel % w);
                item.x1 = Math.Max(item.x1, pixel % w);
                item.y0 = Math.Min(item.y0, pixel / w);
                item.y1 = Math.Max(item.y1, pixel / w);
                item.first = Math.Min(item.first, pixel);
                int d = methods[6].image[pixel];
                disparities.Add(d);
                item.total += d;
                if (truth[pixel] != 0)
                    counts[truth[pixel]]++;
            }
            item.median = Median(disparities);
            item.min = disparities[0];
            item.max = disparities[^1];
            for (int g = min; g <= max; g++)
                if (counts[g] > item.hits) {
                    item.layer = g;
                    item.hits = counts[g];
                }
            if (item.layer != 0)
                item.union
            = item.count + trueCounts[item.layer] - item.hits;
            objects.Add(item);
            totalPixels += item.count;
        }
        objects.Sort((a, b) => {
            int c = b.median.CompareTo(a.median);
            if (c != 0)
                return c;
            c = b.count.CompareTo(a.count);
            return c != 0 ? c : a.first.CompareTo(b.first);
        });
        List<string> lines = new();
        lines.Add("objects " + objects.Count + " small " + small + " pixels " + totalPixels);
        bool[] detected = new bool[max + 1];
        for (int i = 0; i < objects.Count; i++) {
            ObjectInfo o = objects[i];
            string line = "object " + (i + 1) + " pixels " + o.count + " box " + o.x0 + " " + o.y0 +
                          " " + o.x1 + " " + o.y1 + " disparity " + o.min + " " + o.max +
                          " median " + o.median + " mean " + Two(o.total, o.count) + " depth " +
                          Two(focal * baseline * o.count, o.total) + " size " +
                          Two((o.x1 - o.x0 + 1) * baseline, o.median) + " " +
                          Two((o.y1 - o.y0 + 1) * baseline, o.median);
            if (o.layer == 0)
                line += " truth - iou -";
            else {
                line += " truth " + o.layer + " iou " + Ratio(o.hits, o.union);
                if (2 * o.hits > o.union)
                    detected[o.layer] = true;
            }
            lines.Add(line);
        }
        int layerCount = 0, detectedCount = 0;
        List<string> missed = new();
        for (int g = min; g <= max; g++)
            if (trueCounts[g] != 0) {
                layerCount++;
                if (detected[g])
                    detectedCount++;
                else
                    missed.Add(Convert.ToString(g));
            }
        lines.Add("layers " + layerCount + " detected " + detectedCount + " missed " +
                  (missed.Count == 0 ? "-" : string.Join(" ", missed)));
        return lines;
    }
    public static List<string> Samples() {
        List<string> lines = new();
        lines.Add("x,y,sad,ssd,census,sgm,disparity,source,subpixel,depth,truth,truth_depth");
        foreach (int[] point in settings.samples) {
            int pixel = point[1] * w + point[0];
            string line = point[0] + "," + point[1];
            for (int k = 0; k < 4; k++)
                line += "," + (methods[k].image[pixel] == 0
                                   ? "-"
                                   : Convert.ToString(methods[k].image[pixel]));
            int d = methods[6].image[pixel];
            if (d == 0)
                line += ",-,none,-,-";
            else {
                string[] refined = Refinement.Subpixel(d, summed[pixel], min, max, focal, baseline);
                line += "," + d + "," + SOURCES[methods[6].sources[pixel]] + "," + refined[0] +
                        "," + refined[1];
            }
            line += truth[pixel] == 0
                        ? ",-,-"
                        : "," + truth[pixel] + "," + Two(focal * baseline, truth[pixel]);
            lines.Add(line);
        }
        return lines;
    }
    public static string ImageSummary(string name, int[] image) {
        long total = 0;
        int low = 255, high = 0;
        foreach (int value in image) {
            total += value;
            low = Math.Min(low, value);
            high = Math.Max(high, value);
        }
        return name + " mean " + Two(total, size) + " min " + low + " max " + high;
    }
    public static string RegionLine(string name, Evaluation.Metrics m) {
        return "region " + name + " pixels " + m.pixels + " valid " + m.valid + " bad1 " +
               Ratio(m.bad1, m.pixels) + " bad2 " + Ratio(m.bad2, m.pixels) + " mae " + m.Mae() +
               " exact " + m.exact;
    }
    public static List<string> MethodLines(int k, Evaluation.Metrics[] metrics) {
        Method method = methods[k];
        int[] image = method.image;
        List<int> values = new();
        HashSet<int> distinct = new();
        int horizontal = 0, vertical = 0;
        for (int pixel = 0; pixel < size; pixel++)
            if (image[pixel] != 0) {
                values.Add(image[pixel]);
                distinct.Add(image[pixel]);
                if (pixel % w + 1 < w && image[pixel + 1] != 0 &&
                    Math.Abs(image[pixel] - image[pixel + 1]) >= 2)
                    horizontal++;
                if (pixel / w + 1 < h && image[pixel + w] != 0 &&
                    Math.Abs(image[pixel] - image[pixel + w]) >= 2)
                    vertical++;
            }
        List<string> lines = new();
        lines.Add("method " + NAMES[k] + " valid " + values.Count + " invalid " +
                  (size - values.Count));
        if (values.Count == 0)
            lines.Add("disparity min - max - median - distinct 0");
        else {
            int median = Median(values);
            lines.Add("disparity min " + values[0] + " max " + values[^1] + " median " + median +
                      " distinct " + distinct.Count);
        }
        lines.Add("jumps horizontal " + horizontal + " vertical " + vertical);
        if (k < 4) {
            lines.Add("window " + method.window + " bounds " + method.bounds);
            string reasons = "reasons";
            for (int i = 0; i < 5; i++) {
                int reasonCount = 0;
                foreach (int reason in method.reasons)
                    if (reason == REASONS[i])
                        reasonCount++;
                reasons += " " + REASON_NAMES[i] + " " + reasonCount;
            }
            lines.Add(reasons);
            lines.Add("lr 0 " + method.lr[0] + " 1 " + method.lr[1] + " 2 " + method.lr[2] +
                      " 3+ " + method.lr[3]);
        } else if (k == 4) {
            string votes = "votes";
            for (int i = 0; i < 5; i++)
                votes += " " + i + " " + method.votes[i];
            lines.Add(votes);
        } else {
            int[] counts = new int[5];
            foreach (int source in method.sources)
                counts[source]++;
            lines.Add("postprocess speckles " + method.speckles + " " + method.specklePixels +
                      " median " + method.medianChanged + " background " + counts[2] +
                      " interpolated " + counts[3] + " unfilled " + counts[4]);
            for (int source = 0; source < 5; source++) {
                List<int> region = new();
                foreach (int pixel in regions.all)
                    if (method.sources[pixel] == source)
                        region.Add(pixel);
                Evaluation.Metrics m = Evaluation.Evaluate(image, truth, region);
                lines.Add("source " + SOURCES[source] + " pixels " + m.pixels + " bad1 " +
                          Ratio(m.bad1, m.pixels));
            }
        }
        for (int i = 0; i < 3; i++)
            lines.Add(RegionLine(Evaluation.REGIONS[i], metrics[i]));
        int count = 0;
        long total = 0, maximum = 0;
        foreach (int pixel in regions.nonocc)
            if (image[pixel] != 0) {
                long error = Math.Abs(Refinement.DepthHundredths(image[pixel], focal, baseline) -
                                      Refinement.DepthHundredths(truth[pixel], focal, baseline));
                count++;
                total += error;
                maximum = Math.Max(maximum, error);
            }
        lines.Add(count == 0 ? "depth_error pixels 0 mean - max -"
                             : "depth_error pixels " + count + " mean " + Two(total, 100L * count) +
                                   " max " + Two(maximum, 100));
        int[] errors = new int[6];
        foreach (int pixel in regions.all)
            errors[image[pixel] == 0 ? 5 : Math.Min(4, Math.Abs(image[pixel] - truth[pixel]))]++;
        lines.Add("errors 0 " + errors[0] + " 1 " + errors[1] + " 2 " + errors[2] + " 3 " +
                  errors[3] + " 4+ " + errors[4] + " invalid " + errors[5]);
        return lines;
    }
    public static int CompareMetrics(Evaluation.Metrics a, Evaluation.Metrics b) {
        int c = (a.bad1).CompareTo(b.bad1);
        if (c != 0)
            return c;
        c = (a.bad2).CompareTo(b.bad2);
        if (c != 0)
            return c;
        if (a.valid == 0 || b.valid == 0)
            return a.valid == b.valid ? 0 : a.valid == 0 ? 1 : -1;
        return (a.error * b.valid).CompareTo(b.error * a.valid);
    }
    public static List<string> EvaluationLines() {
        List<string> lines = new();
        lines.Add("image " + w + " " + h);
        lines.Add("disparities " + min + " " + max);
        lines.Add(ImageSummary("left", left));
        lines.Add(ImageSummary("right", right));
        long textureTotal = 0;
        int textureless = 0;
        foreach (long value in strengths) {
            textureTotal += value;
            if (value < P("texture_threshold"))
                textureless++;
        }
        lines.Add("texture mean " + Two(textureTotal, size) + " textureless " + textureless);
        lines.Add("ground_truth known " + regions.all.Count + " nonocc " + regions.nonocc.Count +
                  " occluded " + regions.occluded.Count + " disc " + regions.disc.Count +
                  " unknown " + (size - regions.all.Count));
        long absolute = 0, biasSum = 0;
        foreach (int pixel in regions.nonocc) {
            int delta = right[pixel - truth[pixel]] - left[pixel];
            absolute += Math.Abs(delta);
            biasSum += delta;
        }
        string bias = Two(Math.Abs(biasSum), regions.nonocc.Count);
        if (biasSum < 0 && !bias.Equals("0.00"))
            bias = "-" + bias;
        lines.Add("photometric pixels " + regions.nonocc.Count + " mean_abs " +
                  Two(absolute, regions.nonocc.Count) + " bias " + bias);
        lines.AddRange(sweeps);
        Evaluation.Metrics[][] metrics = Enumerable.Range(0, 7)
                                             .Select(
                                                 _ => new Evaluation.Metrics[3])
                                             .ToArray();
        for (int k = 0; k < 7; k++) {
            for (int i = 0; i < 3; i++)
                metrics[k][i] = Evaluation.Evaluate(methods[k].image, truth, regions.At(i));
            lines.AddRange(MethodLines(k, metrics[k]));
        }
        for (int i = 0; i < 3; i++) {
            int region = i;
            List<int> order = new();
            for (int k = 0; k < 7; k++)
                order.Add(k);
            order.Sort((a, b) => {
                int c = CompareMetrics(metrics[a][region], metrics[b][region]);
                return c != 0 ? c : (a).CompareTo(b);
            });
            string ranking = "ranking " + Evaluation.REGIONS[i];
            foreach (int k in order)
                ranking += " " + NAMES[k];
            lines.Add(ranking);
        }
        for (int k = 0; k < 4; k++) {
            int tp = 0, fp = 0;
            foreach (int pixel in regions.occluded)
                if (methods[k].reasons[pixel] == 150 || methods[k].reasons[pixel] == 255)
                    tp++;
            foreach (int pixel in regions.nonocc)
                if (methods[k].reasons[pixel] == 150 || methods[k].reasons[pixel] == 255)
                    fp++;
            int fn = regions.occluded.Count - tp;
            lines.Add("occlusion " + NAMES[k] + " tp " + tp + " fp " + fp + " fn " + fn +
                      " precision " + Ratio(tp, tp + fp) + " recall " + Ratio(tp, tp + fn));
        }
        for (int k = 0; k < 4; k++) {
            Method method = methods[k];
            List<int> pixels = new();
            foreach (int pixel in regions.nonocc)
                if (method.image[pixel] != 0)
                    pixels.Add(pixel);
            pixels.Sort((a, b) => {
                int c = (method.margins[b]).CompareTo(method.margins[a]);
                return c != 0 ? c : (a).CompareTo(b);
            });
            foreach (int percentage in new int[] { 25, 50, 75, 100 }) {
                int count = (pixels.Count * percentage + 99) / 100, bad = 0;
                for (int i = 0; i < count; i++) {
                    int pixel = pixels[i];
                    if (Math.Abs(method.image[pixel] - truth[pixel]) > 1)
                        bad++;
                }
                lines.Add("confidence " + NAMES[k] + " " + percentage + " pixels " + count +
                          " margin " +
                          (count == 0 ? "-" : Convert.ToString(method.margins[pixels[count - 1]])) +
                          " bad1 " + Ratio(bad, count));
            }
        }
        for (int g = min; g <= max; g++) {
            int count = 0;
            List<int> region = new();
            foreach (int pixel in regions.all)
                if (truth[pixel] == g)
                    count++;
            if (count == 0)
                continue;
            foreach (int pixel in regions.nonocc)
                if (truth[pixel] == g)
                    region.Add(pixel);
            string line = "layer " + g + " pixels " + count + " nonocc " + region.Count + " bad1";
            foreach (Method method in methods)
                line += " " + Evaluation.Evaluate(method.image, truth, region).bad1;
            lines.Add(line);
        }
        for (int d = min; d <= max; d++) {
            int count = 0;
            foreach (int value in methods[6].image)
                if (value == d)
                    count++;
            lines.Add("histogram " + d + " " + count);
        }
        return lines;
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        PgmIo.Image image = PgmIo.Read("left.pgm");
        w = image.width;
        h = image.height;
        size = w * h;
        left = image.pixels;
        right = PgmIo.Read("right.pgm").pixels;
        truth = PgmIo.Read("ground_truth.pgm").pixels;
        settings = PgmIo.ReadParameters();
        min = P("disparity_min");
        max = P("disparity_max");
        focal = P("focal_length");
        baseline = P("baseline");
        regions = Evaluation.ComputeRegions(truth, w, h);
        strengths = Costs.Texture(left, w, h, P("texture_window"));
        Estimate();
        Fuse();
        int[] wta = new int[size], sgm = new int[size], errors = new int[size];
        for (int pixel = 0; pixel < size; pixel++) {
            wta[pixel] = 8 * methods[5].image[pixel];
            sgm[pixel] = 8 * methods[6].image[pixel];
            errors[pixel] =
                truth[pixel] == 0 ? 0
                : methods[6].image[pixel] == 0
                    ? 255
                    : 50 * (Math.Min(3, Math.Abs(methods[6].image[pixel] - truth[pixel])) + 1);
        }
        PgmIo.Write("disparity_wta.pgm", w, h, wta);
        PgmIo.Write("disparity_sgm.pgm", w, h, sgm);
        PgmIo.Write("occlusion.pgm", w, h, methods[3].reasons);
        PgmIo.Write("error_sgm.pgm", w, h, errors);
        PgmIo.Text("depth.csv", Samples());
        PgmIo.Text("evaluation.txt", EvaluationLines());
        PgmIo.Text("objects.txt", Objects());
    }
}
