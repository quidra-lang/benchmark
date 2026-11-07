using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Program {
    public static List<Dataset.Point> points;
    public static Dataset.Params settings;
    public static Dictionary<int, Em.Model> initial;
    public static int[] ks;
    public static string[] types;
    public static List<Summary> models = new();
    public static Dictionary<int, Kmeans.Run> kmeans = new();
    public static Summary selected;
    public sealed class Summary {
        public int k, typeIndex, p, settled, largest;
        public string type;
        public Em.Run run;
        public int[] assignment, sizes;
        public double bic, aic, icl, entropy, increase;
        public List<int> violations = new();
    }
    public record Metrics(double silhouette, double ch, double db, double[] cluster) {
    }
    public record Ari(long numerator, long denominator) {
        public string Text() {
            return numerator + "/" + denominator + " " + Report.F((double)numerator / denominator);
        }
    }
    public static string F(double value) {
        return Report.F(value);
    }
    public static string Ints(int[] values, bool oneBased) {
        List<string> words = new();
        foreach (int value in values)
            words.Add(Convert.ToString(value + (oneBased ? 1 : 0)));
        return string.Join(" ", words);
    }
    public static string Decimals(double[] values) {
        List<string> words = new();
        foreach (double value in values)
            words.Add(F(value));
        return string.Join(" ", words);
    }
    public static double Entropy(double[] row) {
        double sum = 0;
        foreach (double value in row)
            if (value != 0)
                sum += value * Math.Log(value);
        return -sum;
    }
    public static int Maximum(double[] row) {
        int best = 0;
        for (int j = 1; j < row.Length; j++)
            if (row[j] > row[best])
                best = j;
        return best;
    }
    public static Summary Summarize(int k, int typeIndex, Em.Run run) {
        Summary result = new Summary();
        result.k = k;
        result.typeIndex = typeIndex;
        result.type = types[typeIndex];
        result.p = result.type switch { "FULL" => 6 * k - 1, "TIED" => 3 * k + 2, "DIAG" => 5 * k - 1,
                                        _ => 4 * k - 1 };
        result.run = run;
        result.assignment = new int[run.step.density.Length];
        result.sizes = new int[k];
        for (int i = 0; i < result.assignment.Length; i++) {
            double[] row = run.step.responsibilities[i];
            result.assignment[i] = Maximum(row);
            result.sizes[result.assignment[i]]++;
            result.entropy += Entropy(row);
        }
        double loglik = run.step.loglik;
        result.bic = -2 * loglik + result.p * Math.Log(result.assignment.Length);
        result.aic = -2 * loglik + 2 * result.p;
        result.icl = result.bic + 2 * result.entropy;
        List<Double> trace = run.trace;
        double last = trace[^1];
        result.settled = 0;
        for (int t = 0; t < trace.Count; t++)
            if (Math.Abs(trace[t] - last) > settings.Get("SETTLE_TOLERANCE"))
                result.settled = t + 1;
        result.largest = 1;
        result.increase = trace[1] - trace[0];
        for (int t = 1; t < trace.Count; t++) {
            double increase = trace[t] - trace[t - 1];
            if (increase > result.increase) {
                result.increase = increase;
                result.largest = t;
            }
            if (trace[t] < trace[t - 1] - 0.000001 * Math.Abs(trace[t - 1]))
                result.violations.Add(t);
        }
        return result;
    }
    public static Em.Run Fit(List<Dataset.Point> data, Em.Model source, string type) {
        return Em.Fit(data, source, type, settings.Integer("ITERATIONS"), settings.Get("REGULARIZATION"));
    }
    public static double Criterion(Summary s, int kind) {
        return kind == 0 ? s.bic : kind == 1 ? s.aic : s.icl;
    }
    public static int Compare(Summary a, Summary b, int kind) {
        int c = Report.Rounded(Criterion(a, kind)).CompareTo(Report.Rounded(Criterion(b, kind)));
        if (c == 0)
            c = (a.p).CompareTo(b.p);
        if (c == 0)
            c = (a.k).CompareTo(b.k);
        if (c == 0)
            c = (a.typeIndex).CompareTo(b.typeIndex);
        return c;
    }
    public static List<Summary> Ranking(int kind) {
        List<Summary> result = new(models);
        result.Sort((a, b) => Compare(a, b, kind));
        return result;
    }
    public static Summary BestK(int k) {
        Summary best = null;
        foreach (Summary model in models)
            if (model.k == k && (best == null || Compare(model, best, 0) < 0))
                best = model;
        return best;
    }
    public static int[][] Contingency(int[] a, int ka, int[] b, int kb) {
        int[][] result = Enumerable.Range(0, ka)
                             .Select(
                                 _ => new int[kb])
                             .ToArray();
        for (int i = 0; i < a.Length; i++)
            result[a[i]][b[i]]++;
        return result;
    }
    public static long Pairs(long n) {
        return n * (n - 1) / 2;
    }
    public static long Gcd(long a, long b) {
        while (b != 0) {
            long r = a % b;
            a = b;
            b = r;
        }
        return a;
    }
    public static Ari AdjustedRand(int[][] table) {
        long s = 0, a = 0, b = 0, n = 0;
        long[] columns = new long[table[0].Length];
        foreach (int[] row in table) {
            long sum = 0;
            for (int c = 0; c < row.Length; c++) {
                s += Pairs(row[c]);
                sum += row[c];
                columns[c] += row[c];
            }
            a += Pairs(sum);
            n += sum;
        }
        foreach (long value in columns)
            b += Pairs(value);
        long z = Pairs(n), numerator = 2 * (z * s - a * b), denominator = z * (a + b) - 2 * a * b;
        if (denominator == 0)
            return new Ari(1, 1);
        long g = Gcd(Math.Abs(numerator), Math.Abs(denominator));
        numerator /= g;
        denominator /= g;
        if (denominator < 0) {
            numerator = -numerator;
            denominator = -denominator;
        }
        return new Ari(numerator, denominator);
    }
    public static Metrics PartitionMetrics(int[] assignment, int k) {
        int n = points.Count;
        int[] counts = new int[k];
        double[][] centers = Enumerable.Range(0, k)
                                 .Select(
                                     _ => new double[2])
                                 .ToArray();
        double[] center = new double[2];
        for (int i = 0; i < n; i++) {
            Dataset.Point point = points[i];
            int j = assignment[i];
            counts[j]++;
            centers[j][0] += point.x;
            centers[j][1] += point.y;
            center[0] += point.x;
            center[1] += point.y;
        }
        int groups = 0;
        for (int j = 0; j < k; j++)
            if (counts[j] > 0) {
                groups++;
                centers[j][0] /= counts[j];
                centers[j][1] /= counts[j];
            }
        double[] cluster = new double[k];
        Array.Fill(cluster, double.NaN);
        if (groups < 2)
            return new Metrics(double.NaN, double.NaN, double.NaN, cluster);
        center[0] /= n;
        center[1] /= n;
        double silhouette = 0;
        double[] sums = new double[k];
        for (int i = 0; i < n; i++) {
            int j = assignment[i];
            double s = 0;
            if (counts[j] > 1) {
                double own = 0;
                double[] others = new double[k];
                for (int q = 0; q < n; q++)
                    if (q != i) {
                        double distance = Kmeans.Distance(points[i], points[q]);
                        if (assignment[q] == j)
                            own += distance;
                        else
                            others[assignment[q]] += distance;
                    }
                double a = own / (counts[j] - 1), b = double.PositiveInfinity;
                for (int c = 0; c < k; c++)
                    if (c != j && counts[c] > 0)
                        b = Math.Min(b, others[c] / counts[c]);
                s = (b - a) / Math.Max(a, b);
            }
            silhouette += s;
            sums[j] += s;
        }
        for (int j = 0; j < k; j++)
            if (counts[j] > 0)
                cluster[j] = sums[j] / counts[j];
        double between = 0, within = 0;
        for (int j = 0; j < k; j++)
            if (counts[j] > 0)
                between += counts[j] * Kmeans.Squared(centers[j][0], centers[j][1], center);
        double[] scatters = new double[k];
        for (int i = 0; i < n; i++) {
            Dataset.Point point = points[i];
            int j = assignment[i];
            double square = Kmeans.Squared(point.x, point.y, centers[j]);
            within += square;
            scatters[j] += Math.Sqrt(square);
        }
        for (int j = 0; j < k; j++)
            if (counts[j] > 0)
                scatters[j] /= counts[j];
        double db = 0;
        for (int j = 0; j < k; j++)
            if (counts[j] > 0) {
                double maximum = double.NegativeInfinity;
                for (int c = 0; c < k; c++)
                    if (c != j && counts[c] > 0)
                        maximum = Math.Max(
                            maximum, (scatters[j] + scatters[c]) /
                                         Math.Sqrt(Kmeans.Squared(centers[j][0], centers[j][1], centers[c])));
                db += maximum;
            }
        return new Metrics(silhouette / n, (between / (groups - 1)) / (within / (n - groups)), db / groups,
                           cluster);
    }
    public static List<string> ModelReport() {
        List<string> output = new();
        foreach (Summary model in models) {
            if (output.Count != 0)
                output.Add("");
            Em.Model m = model.run.model;
            output.Add("model K=" + model.k + " type=" + model.type);
            output.Add("parameters " + model.p);
            output.Add("loglik " + F(model.run.step.loglik));
            output.Add("bic " + F(model.bic));
            output.Add("aic " + F(model.aic));
            output.Add("icl " + F(model.icl));
            output.Add("mean_entropy " + F(model.entropy / points.Count));
            output.Add("settled_at " + model.settled);
            output.Add("largest_increase iteration " + model.largest + " value " + F(model.increase));
            output.Add("violations " + model.violations.Count);
            output.Add("sizes " + Ints(model.sizes, false));
            for (int j = 0; j < model.k; j++) {
                Gaussian.Eigen e = Gaussian.EigenData(m.cov[j]);
                output.Add("component " + (j + 1) + " weight " + F(m.weights[j]) + " mean " +
                           Decimals(m.means[j]) + " cov " + Decimals(m.cov[j]) + " axes " + F(e.major) + " " +
                           F(e.minor) + " angle " + F(e.angle));
            }
        }
        return output;
    }
    public static List<string> TraceReport() {
        List<string> output = new(["K,type,iteration,loglik"]);
        foreach (Summary model in models)
            for (int t = 0; t < model.run.trace.Count; t++)
                output.Add(model.k + "," + model.type + "," + t + "," + F(model.run.trace[t]));
        return output;
    }
    public static List<string> AssignmentsReport() {
        List<string> output = new(["id,component,max_responsibility,log_density,kmeans_cluster"]);
        for (int i = 0; i < points.Count; i++)
            output.Add(points[i].id + "," + (selected.assignment[i] + 1) + "," +
                       F(selected.run.step.responsibilities[i][selected.assignment[i]]) + "," +
                       F(selected.run.step.density[i]) + "," + (kmeans[selected.k].assignment[i] + 1));
        return output;
    }
    public static void Block(List<string> output, string heading) {
        if (output.Count != 0)
            output.Add("");
        output.Add(heading);
    }
    public static void Ranks(List<string> output) {
        List<Summary> bic = Ranking(0), aic = Ranking(1), icl = Ranking(2);
        output.Add("ranking by bic");
        output.Add("rank K type parameters loglik bic delta_bic aic aic_rank icl icl_rank");
        for (int i = 0; i < bic.Count; i++) {
            Summary model = bic[i];
            string delta = F(Report.Rounded(model.bic) - Report.Rounded(selected.bic));
            output.Add((i + 1) + " " + model.k + " " + model.type + " " + model.p + " " +
                       F(model.run.step.loglik) + " " + F(model.bic) + " " + delta + " " + F(model.aic) +
                       " " + (aic.IndexOf(model) + 1) + " " + F(model.icl) + " " + (icl.IndexOf(model) + 1));
        }
        output.Add("selected K=" + selected.k + " type=" + selected.type);
        output.Add("best_aic K=" + aic[0].k + " type=" + aic[0].type);
        output.Add("best_icl K=" + icl[0].k + " type=" + icl[0].type);
        Block(output, "best K per type");
        foreach (string type in types) {
            int[] best = new int[3];
            for (int kind = 0; kind < 3; kind++)
                foreach (Summary model in Ranking(kind))
                    if (model.type.Equals(type)) {
                        best[kind] = model.k;
                        break;
                    }
            output.Add(type + " bic " + best[0] + " aic " + best[1] + " icl " + best[2]);
        }
    }
    public static void CompareK(List<string> output) {
        Summary previous = null;
        foreach (int k in ks) {
            Summary best = BestK(k);
            Kmeans.Run km = kmeans[k];
            Metrics g = PartitionMetrics(best.assignment, k), m = PartitionMetrics(km.assignment, k);
            Block(output, "K=" + k + " type=" + best.type + " bic " + F(best.bic));
            output.Add("  kmeans iterations " + km.iterations + " inertia " + F(km.inertia));
            output.Add("  ari " + AdjustedRand(Contingency(best.assignment, k, km.assignment, k)).Text());
            output.Add("  silhouette gmm " + F(g.silhouette) + " kmeans " + F(m.silhouette));
            output.Add("  calinski_harabasz gmm " + F(g.ch) + " kmeans " + F(m.ch));
            output.Add("  davies_bouldin gmm " + F(g.db) + " kmeans " + F(m.db));
            if (previous != null) {
                int[][] table = Contingency(previous.assignment, previous.k, best.assignment, k);
                List<string> parents = new();
                int[] shared = new int[k];
                for (int j = 0; j < k; j++) {
                    int parent = -1;
                    for (int a = 0; a < previous.k; a++)
                        if (table[a][j] > shared[j]) {
                            shared[j] = table[a][j];
                            parent = a;
                        }
                    parents.Add(parent < 0 ? "-" : Convert.ToString(parent + 1));
                }
                output.Add("  parents K=" + previous.k + " " + string.Join(" ", parents) + " shared " +
                           Ints(shared, false));
            }
            previous = best;
        }
    }
    public static void Violations(List<string> output) {
        Block(output, "violations");
        bool any = false;
        foreach (Summary model in models)
            foreach (int t in model.violations) {
                any = true;
                output.Add("K=" + model.k + " type=" + model.type + " iteration " + t + " previous " +
                           F(model.run.trace[t - 1]) + " current " + F(model.run.trace[t]));
            }
        if (!any)
            output.Add("none");
    }
    public static void Components(List<string> output) {
        Block(output, "selected components");
        Em.Model model = selected.run.model;
        double[][] r = selected.run.step.responsibilities;
        Metrics metrics = PartitionMetrics(selected.assignment, selected.k);
        double[] boundaries = settings.Row("GOF_EDGES");
        for (int j = 0; j < selected.k; j++) {
            Gaussian.Eigen e = Gaussian.EigenData(model.cov[j]);
            double soft = 0;
            int inside1 = 0, inside2 = 0;
            int[] observed = new int[boundaries.Length + 1];
            for (int i = 0; i < points.Count; i++) {
                soft += r[i][j];
                if (selected.assignment[i] != j)
                    continue;
                Dataset.Point p = points[i];
                double q = Gaussian.Q(p.x, p.y, model.means[j], model.cov[j]);
                if (q <= 1)
                    inside1++;
                if (q <= 4)
                    inside2++;
                double rho = Math.Sqrt(q);
                int bucket = 0;
                while (bucket < boundaries.Length && rho >= boundaries[bucket])
                    bucket++;
                observed[bucket]++;
            }
            double[] expected = new double[observed.Length];
            double chi = 0;
            for (int b = 0; b < observed.Length; b++) {
                double lo = b == 0 ? 0 : boundaries[b - 1],
                       right = b == boundaries.Length ? 0 : Math.Exp(-boundaries[b] * boundaries[b] / 2);
                expected[b] = selected.sizes[j] * (Math.Exp(-lo * lo / 2) - right);
                chi += (observed[b] - expected[b]) * (observed[b] - expected[b]) / expected[b];
            }
            output.Add("component " + (j + 1) + " weight " + F(model.weights[j]) + " size " +
                       selected.sizes[j] + " soft_size " + F(soft) + " mean " + Decimals(model.means[j]));
            output.Add("  cov " + Decimals(model.cov[j]) + " corr " + F(e.correlation));
            output.Add("  eigen " + F(e.leading) + " " + F(e.trailing) + " direction " + F(e.ux) + " " +
                       F(e.uy) + " angle " + F(e.angle));
            output.Add("  axes_1sigma " + F(e.major) + " " + F(e.minor) + " axes_2sigma " + F(2 * e.major) +
                       " " + F(2 * e.minor));
            output.Add("  inside_1sigma " + inside1 + " inside_2sigma " + inside2 + " area_1sigma " +
                       F(e.area));
            output.Add("  silhouette " + F(metrics.cluster[j]));
            output.Add("  gof observed " + Ints(observed, false) + " expected " + Decimals(expected) +
                       " chi2 " + F(chi));
        }
        Block(output, "overlap");
        if (selected.k == 1)
            output.Add("none");
        for (int a = 0; a < selected.k; a++)
            for (int b = a + 1; b < selected.k; b++) {
                double distance =
                           Gaussian.Bhattacharyya(model.means[a], model.cov[a], model.means[b], model.cov[b]),
                       shared = 0;
                for (int i = 0; i < points.Count; i++)
                    shared += r[i][a] * r[i][b];
                output.Add((a + 1) + "-" + (b + 1) + " bhattacharyya " + F(distance) + " coefficient " +
                           F(Math.Exp(-distance)) + " shared " + F(shared));
            }
    }

    public static List<List<int>> Merge(List<List<int>> clusters, int a, int b) {
        List<List<int>> result = new(clusters);
        List<int> union
        = new(clusters[a]);
        union
        .AddRange(clusters[b]);
        union
        .Sort();
        result[a] = union;
        result.RemoveAt(b);
        return result;
    }
    public static double[][] Collapsed(List<List<int>> clusters) {
        double[][] result = Enumerable.Range(0, points.Count)
                                .Select(
                                    _ => new double[clusters.Count])
                                .ToArray();
        for (int i = 0; i < points.Count; i++)
            for (int c = 0; c < clusters.Count; c++)
                foreach (int j in clusters[c])
                    result[i][c] += selected.run.step.responsibilities[i][j];
        return result;
    }
    public static double MergedEntropy(List<List<int>> clusters) {
        double sum = 0;
        foreach (double[] row in Collapsed(clusters))
            sum += Entropy(row);
        return sum;
    }
    public static string ClusterName(List<int> cluster) {
        List<string> words = new();
        foreach (int j in cluster)
            words.Add(Convert.ToString(j + 1));
        return string.Join("+", words);
    }
    public static void Merging(List<string> output) {
        Block(output, "merging");
        List<List<int>> clusters = new();
        for (int j = 0; j < selected.k; j++)
            clusters.Add([j]);
        output.Add("start entropy " + F(MergedEntropy(clusters)));
        for (int step = 1; clusters.Count > 1; step++) {
            int ba = 0, bb = 1;
            double best = double.PositiveInfinity;
            for (int a = 0; a < clusters.Count; a++)
                for (int b = a + 1; b < clusters.Count; b++) {
                    double value = MergedEntropy(Merge(clusters, a, b));
                    if (double.IsInfinity(best) ||
                        Report.Rounded(value).CompareTo(Report.Rounded(best)) < 0) {
                        best = value;
                        ba = a;
                        bb = b;
                    }
                }
            string firstName = ClusterName(clusters[ba]), secondName = ClusterName(clusters[bb]);
            clusters = Merge(clusters, ba, bb);
            double[][] r = Collapsed(clusters);
            int[] sizes = new int[clusters.Count];
            foreach (double[] row in r)
                sizes[Maximum(row)]++;
            output.Add("step " + step + " merge " + firstName + " " + secondName + " entropy " + F(best) +
                       " sizes " + Ints(sizes, false));
        }
    }
    public record Matching(int[] permutation, int agreement) {
    }
    public static void Permutations(int[][] table, int depth, int[] current, bool[] used, int[] best,
                                    int[] largest) {
        if (depth == current.Length) {
            int agreement = 0;
            for (int j = 0; j < current.Length; j++)
                agreement += table[current[j]][j];
            if (agreement > largest[0]) {
                largest[0] = agreement;
                Array.Copy(current, 0, best, 0, current.Length);
            }
            return;
        }
        for (int j = 0; j < current.Length; j++)
            if (!used[j]) {
                used[j] = true;
                current[depth] = j;
                Permutations(table, depth + 1, current, used, best, largest);
                used[j] = false;
            }
    }
    public static Matching FindMatching(int[][] table) {
        int k = table.Length;
        int[] best = new int[k], largest = { -1 };
        Permutations(table, 0, new int[k], new bool[k], best, largest);
        return new Matching(best, largest[0]);
    }
    public static void CompareKmeans(List<string> output) {
        Kmeans.Run km = kmeans[selected.k];
        Block(output, "kmeans K=" + selected.k);
        output.Add("iterations " + km.iterations);
        output.Add("inertia " + F(km.inertia));
        int[] sizes = new int[selected.k];
        foreach (int value in km.assignment)
            sizes[value]++;
        output.Add("sizes " + Ints(sizes, false));
        for (int j = 0; j < selected.k; j++)
            output.Add("center " + (j + 1) + " " + Decimals(km.centers[j]));
        int[][] table = Contingency(selected.assignment, selected.k, km.assignment, selected.k);
        output.Add("contingency");
        foreach (int[] row in table)
            output.Add(Ints(row, false));
        output.Add("ari " + AdjustedRand(table).Text());
        Matching match = FindMatching(table);
        output.Add("matching " + Ints(match.permutation, true));
        output.Add("agreement " + match.agreement + "/" + points.Count + " " +
                   F((double)match.agreement / points.Count));
        int disagreements = 0;
        for (int i = 0; i < points.Count; i++)
            if (match.permutation[km.assignment[i]] != selected.assignment[i]) {
                disagreements++;
                output.Add("disagree " + points[i].id + " gmm " + (selected.assignment[i] + 1) + " kmeans " +
                           (km.assignment[i] + 1) + " max " +
                           F(selected.run.step.responsibilities[i][selected.assignment[i]]));
            }
        output.Add("disagreements " + disagreements);
    }
    public static void Refit(List<string> output) {
        Kmeans.Run km = kmeans[selected.k];
        Em.Model source = new Em.Model(selected.k);
        int[] counts = new int[selected.k];
        foreach (int value in km.assignment)
            counts[value]++;
        double eps = settings.Get("REGULARIZATION");
        for (int j = 0; j < selected.k; j++) {
            source.weights[j] = (double)counts[j] / points.Count;
            source.means[j] = km.centers[j].ToArray();
            for (int i = 0; i < points.Count; i++)
                if (km.assignment[i] == j) {
                    double dx = points[i].x - source.means[j][0], dy = points[i].y - source.means[j][1];
                    source.cov[j][0] += dx * dx;
                    source.cov[j][1] += dx * dy;
                    source.cov[j][2] += dy * dy;
                }
            source.cov[j][0] = source.cov[j][0] / counts[j] + eps;
            source.cov[j][1] /= counts[j];
            source.cov[j][2] = source.cov[j][2] / counts[j] + eps;
        }
        Summary result = Summarize(selected.k, selected.typeIndex, Fit(points, source, selected.type));
        Block(output, "refit_from_kmeans K=" + selected.k + " type=" + selected.type);
        output.Add("loglik " + F(result.run.step.loglik) + " bic " + F(result.bic) + " settled_at " +
                   result.settled);
        output.Add("sizes " + Ints(result.sizes, false));
        output.Add(
            "ari_vs_selected " +
            AdjustedRand(Contingency(selected.assignment, selected.k, result.assignment, selected.k)).Text());
    }
    public static void CrossValidation(List<string> output) {
        int folds = settings.Integer("CV_FOLDS");
        Block(output, "cross_validation K=" + selected.k + " type=" + selected.type + " folds " + folds);
        double sum = 0;
        for (int fold = 0; fold < folds; fold++) {
            List<Dataset.Point> train = new(), test = new();
            for (int i = 0; i < points.Count; i++)
                if (i % folds == fold)
                    test.Add(points[i]);
                else
                    train.Add(points[i]);
            Em.Run run = Fit(train, initial[selected.k], selected.type);
            double score = Em.Expectation(test, run.model).loglik / test.Count;
            sum += score;
            output.Add("fold " + (fold + 1) + " train " + train.Count + " test " + test.Count +
                       " train_loglik " + F(run.step.loglik / train.Count) + " test_loglik " + F(score));
        }
        output.Add("mean_test_loglik " + F(sum / folds));
    }
    public static void Unusual(List<string> output) {
        List<int> uncertain = new(), outliers = new();
        double[][] r = selected.run.step.responsibilities;
        double[] lp = selected.run.step.density;
        double threshold = settings.Get("UNCERTAIN_THRESHOLD"), low = settings.Get("LOW_DENSITY_THRESHOLD");
        for (int i = 0; i < points.Count; i++) {
            if (r[i][selected.assignment[i]] < threshold)
                uncertain.Add(i);
            if (lp[i] < low)
                outliers.Add(i);
        }
        uncertain.Sort((a, b) => {
            int c = Report.Rounded(r[a][selected.assignment[a]])
                        .CompareTo(Report.Rounded(r[b][selected.assignment[b]]));
            return c != 0 ? c : (a).CompareTo(b);
        });
        outliers.Sort((a, b) => {
            int c = Report.Rounded(lp[a]).CompareTo(Report.Rounded(lp[b]));
            return c != 0 ? c : (a).CompareTo(b);
        });
        Block(output, "uncertain threshold " + F(threshold));
        foreach (int i in uncertain)
            output.Add(points[i].id + " component " + (selected.assignment[i] + 1) + " max " +
                       F(r[i][selected.assignment[i]]) + " responsibilities " + Decimals(r[i]));
        output.Add("count " + uncertain.Count);
        Block(output, "outliers threshold " + F(low));
        Em.Model model = selected.run.model;
        foreach (int i in outliers) {
            Dataset.Point point = points[i];
            int j = selected.assignment[i];
            output.Add(point.id + " component " + (j + 1) + " log_density " + F(lp[i]) + " q " +
                       F(Gaussian.Q(point.x, point.y, model.means[j], model.cov[j])));
        }
        output.Add("count " + outliers.Count);
    }
    public static List<string> SelectionReport() {
        List<string> output = new();
        Ranks(output);
        CompareK(output);
        Violations(output);
        Components(output);
        Merging(output);
        CompareKmeans(output);
        Refit(output);
        CrossValidation(output);
        Unusual(output);
        return output;
    }
    public static int[] Cell(double x, double y, double[] rx, double[] ry, double sx, double sy, int width,
                             int height) {
        int col = (int)Math.Floor((x - rx[0]) / sx), row = (int)Math.Floor((ry[1] - y) / sy);
        return col < 0 || col >= width || row < 0 || row >= height ? null : new int[] { col, row };
    }
    public static List<string> Maps() {
        double[] rx = settings.Row("MAP_X"), ry = settings.Row("MAP_Y"), size = settings.Row("MAP_SIZE");
        int width = (int)size[0], height = (int)size[1];
        double sx = (rx[1] - rx[0]) / width, sy = (ry[1] - ry[0]) / height;
        string characters = " .:-=+*#%@";
        char[][] density = Enumerable.Range(0, height)
                               .Select(
                                   _ => new char[width])
                               .ToArray(),
                 regions = Enumerable.Range(0, height)
                               .Select(
                                   _ => new char[width])
                               .ToArray(),
                 uncertainty = Enumerable.Range(0, height)
                                   .Select(
                                       _ => new char[width])
                                   .ToArray(),
                 pointMap = Enumerable.Range(0, height)
                                .Select(
                                    _ => new char[width])
                                .ToArray();
        double[][] values = Enumerable.Range(0, height)
                                .Select(
                                    _ => new double[width])
                                .ToArray();
        double maximum = 0, sum = 0;
        Em.Model model = selected.run.model;
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width; x++) {
                double cx = rx[0] + (x + 0.5) * sx, cy = ry[1] - (y + 0.5) * sy;
                Em.Step step = Em.Expectation([new Dataset.Point("", cx, cy)], model);
                double value = 0;
                foreach (double score in step.scores[0])
                    value += Math.Exp(score);
                values[y][x] = value;
                maximum = Math.Max(maximum, value);
                sum += value;
                regions[y][x] = (char)('1' + Maximum(step.scores[0]));
                int level =
                    selected.k == 1
                        ? 0
                        : (int)Math.Floor(10 * Entropy(step.responsibilities[0]) / Math.Log(selected.k));
                level = Math.Max(0, Math.Min(9, level));
                uncertainty[y][x] = characters[level];
                pointMap[y][x] = ' ';
                for (int j = 0; j < selected.k; j++)
                    if (Gaussian.Q(cx, cy, model.means[j], model.cov[j]) <= 4) {
                        foreach (int[] d in new int[][] { new int[] { -1, 0 }, new int[] { 1, 0 },
                                                          new int[] { 0, -1 }, new int[] { 0, 1 } }) {
                            int xx = x + d[0], yy = y + d[1];
                            if (xx >= 0 && xx < width && yy >= 0 && yy < height &&
                                Gaussian.Q(rx[0] + (xx + 0.5) * sx, ry[1] - (yy + 0.5) * sy, model.means[j],
                                           model.cov[j]) > 4)
                                pointMap[y][x] = '.';
                        }
                    }
            }
        int[] counts = new int[10];
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width; x++) {
                int level = Math.Min(9, (int)Math.Floor(10 * values[y][x] / maximum));
                counts[level]++;
                density[y][x] = characters[level];
            }
        for (int j = 0; j < selected.k; j++) {
            int[] cell = Cell(model.means[j][0], model.means[j][1], rx, ry, sx, sy, width, height);
            if (cell != null)
                density[cell[1]][cell[0]] = (char)('1' + j);
        }
        int outside = 0;
        for (int i = 0; i < points.Count; i++) {
            Dataset.Point point = points[i];
            int[] cell = Cell(point.x, point.y, rx, ry, sx, sy, width, height);
            if (cell == null) {
                outside++;
                continue;
            }
            char old = pointMap[cell[1]][cell[0]], symbol = (char)('1' + selected.assignment[i]);
            pointMap[cell[1]][cell[0]] = old == ' ' || old == '.' || old == symbol ? symbol : '*';
        }
        List<string> output = new();
        output.Add("density K=" + selected.k + " type=" + selected.type);
        output.Add("x " + F(rx[0]) + " " + F(rx[1]) + " y " + F(ry[0]) + " " + F(ry[1]) + " grid " + width +
                   "x" + height);
        output.Add("max_density " + Report.Decimal(maximum, 6) + " mass_in_map " + F(sum * sx * sy));
        output.AddRange(Report.Frame(density));
        for (int level = 0; level < 10; level++)
            output.Add("level " + level + " \"" + characters[level] + "\" from " +
                       Report.Decimal(level * maximum / 10, 6) + " cells " + counts[level]);
        Block(output, "regions");
        output.AddRange(Report.Frame(regions));
        Block(output, "uncertainty");
        output.AddRange(Report.Frame(uncertainty));
        Block(output, "points");
        output.AddRange(Report.Frame(pointMap));
        output.Add("outside " + outside);
        return output;
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Dataset.Data data = Dataset.Read();
        points = data.points;
        initial = data.initial;
        settings = data.settings;
        types = settings.Words("TYPES");
        string[] sequence = settings.Words("K");
        ks = new int[sequence.Length];
        for (int i = 0; i < ks.Length; i++)
            ks[i] = int.Parse(sequence[i]);
        foreach (int k in ks) {
            for (int t = 0; t < types.Length; t++)
                models.Add(Summarize(k, t, Fit(points, initial[k], types[t])));
            kmeans[k] = Kmeans.Fit(points, initial[k].means, settings.Integer("KMEANS_MAX_ITERATIONS"));
        }
        selected = Ranking(0)[0];
        Report.Write("models.txt", ModelReport());
        Report.Write("loglik_trace.csv", TraceReport());
        Report.Write("assignments.csv", AssignmentsReport());
        Report.Write("selection.txt", SelectionReport());
        Report.Write("density_map.txt", Maps());
    }
}
