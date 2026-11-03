using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;


class Program {
    public static readonly long MODULUS = 2147483647L;
    public static readonly string FEATURES_HEADER = "customer,recency,frequency,monetary,basket,categories,tenure,z_recency,z_frequency,z_monetary,z_basket,z_categories,z_tenure";
    public static readonly string SEGMENTS_HEADER = "customer,segment,name,distance,other,other_distance,silhouette,recommend";
    public sealed class Minstd {
        public long state;
        public Minstd(long seed) { state = seed; }
        public long draw() { state = state * 48271 % MODULUS; return state; }
    }
    public sealed record Improvement(int[] labels, int passes, int transfers, double sse);
    public sealed class Run {
        public readonly string method;
        public readonly int number;
        public readonly int[] seeds;
        public readonly LloydResult lloyd;
        public readonly double lloydSse;
        public readonly Improvement improved;
        public Run(string method, int number, int[] seeds, List<double[]> points, int limit) {
            this.method = method; this.number = number; this.seeds = seeds;
            List<double[]> initial = new();
            foreach (int seed in seeds) initial.Add(points[seed]);
            lloyd = KMeans.lloyd(points, initial, limit);
            lloydSse = KMeans.sse(points, lloyd.labels, lloyd.centers);
            improved = improve(points, lloyd.labels, seeds.Length, limit);
        }
    }
    public sealed class Solution {
        public readonly int k;
        public readonly List<List<int>> members = new();
        public readonly int[] sizes, labels;
        public readonly List<double[]> centers;
        public readonly double sse;
        public Solution(List<double[]> points, int[] original, int k) {
            this.k = k;
            for (int j = 0; j < k; j++) members.Add(new());
            for (int i = 0; i < original.Length; i++) members[original[i]].Add(i);
            members.Sort((a, b) => a.Count != b.Count ? b.Count.CompareTo(a.Count) : a[0].CompareTo(b[0]));
            sizes = new int[k]; labels = new int[original.Length];
            for (int j = 0; j < k; j++) {
                sizes[j] = members[j].Count;
                foreach (int i in members[j]) labels[i] = j;
            }
            centers = KMeans.centers(points, labels, k);
            sse = KMeans.sse(points, labels, centers);
        }
    }
    public sealed class Candidate {
        public readonly int k;
        public readonly List<Run> runs, methodBests;
        public readonly Run best;
        public readonly Solution solution;
        public double[] silhouettes;
        public double silhouette, calinskiHarabasz, daviesBouldin, elbow;
        public double? hartigan;
        public int[] ruleNumbers;
        public List<string> names;
        public Candidate(int k, List<Run> runs, List<Run> methodBests, Run best, Solution solution) {
            this.k = k; this.runs = runs; this.methodBests = methodBests; this.best = best; this.solution = solution;
        }
    }
    public static double[] nearestGaps(List<double[]> points, List<int> chosen) {
        double[] gaps = new double[points.Count];
        for (int i = 0; i < points.Count; i++) {
            gaps[i] = double.PositiveInfinity;
            foreach (int j in chosen) gaps[i] = Math.Min(gaps[i], KMeans.squaredDistance(points[i], points[j]));
        }
        return gaps;
    }
    public static int[] seeds(string method, List<double[]> points, int k, int number, Minstd random) {
        List<int> chosen = new();
        if (method.Equals("forgy")) {
            while (chosen.Count < k) {
                int index = (int) (random.draw() % points.Count);
                if (!chosen.Contains(index)) chosen.Add(index);
            }
        } else if (method.Equals("maximin")) {
            double[] center = KMeans.meanPoint(points);
            List<int> order = new();
            for (int i = 0; i < points.Count; i++) order.Add(i);
            order = order.OrderBy(i => KMeans.squaredDistance(points[i], center)).ThenBy(i => i).ToList();
            chosen.Add(order[number - 1]);
            while (chosen.Count < k) {
                double[] gaps = nearestGaps(points, chosen);
                int best = 0;
                for (int i = 1; i < gaps.Length; i++) if (gaps[i] > gaps[best]) best = i;
                chosen.Add(best);
            }
        } else {
            chosen.Add((int) (random.draw() % points.Count));
            while (chosen.Count < k) {
                double[] gaps = nearestGaps(points, chosen);
                double threshold = (random.draw() / (double) MODULUS) * Features.sum(gaps);
                double total = 0;
                int selected = -1;
                for (int i = 0; i < gaps.Length; i++) {
                    total += gaps[i];
                    if (total > threshold) { selected = i; break; }
                }
                if (selected < 0) for (int i = 0; i < gaps.Length; i++) if (gaps[i] > 0) selected = i;
                chosen.Add(selected);
            }
        }
        return chosen.ToArray();
    }
    public static Improvement improve(List<double[]> points, int[] original, int k, int limit) {
        int[] labels = original.ToArray(), sizes = KMeans.sizes(labels, k);
        List<double[]> centers = KMeans.centers(points, labels, k);
        int passes = 0, transfers = 0;
        bool moved = true;
        while (moved && passes < limit) {
            moved = false; passes++;
            for (int i = 0; i < points.Count; i++) {
                int own = labels[i];
                if (sizes[own] == 1) continue;
                double removal = (sizes[own] / (double) (sizes[own] - 1)) * KMeans.squaredDistance(points[i], centers[own]);
                int target = -1;
                double targetCost = 0;
                for (int q = 0; q < k; q++) if (q != own) {
                    double cost = (sizes[q] / (double) (sizes[q] + 1)) * KMeans.squaredDistance(points[i], centers[q]);
                    if (target < 0 || cost < targetCost) { target = q; targetCost = cost; }
                }
                if (targetCost < removal) {
                    labels[i] = target; sizes[own]--; sizes[target]++;
                    centers[own] = KMeans.center(points, labels, own);
                    centers[target] = KMeans.center(points, labels, target);
                    transfers++; moved = true;
                }
            }
        }
        return new Improvement(labels, passes, transfers, KMeans.sse(points, labels, KMeans.centers(points, labels, k)));
    }
    public static Run bestRun(List<Run> runs) {
        Run best = runs[0];
        foreach (Run run in runs) if (Report.fourDecimal(run.improved.sse) < Report.fourDecimal(best.improved.sse)) best = run;
        return best;
    }
    public static double gini(List<Customer> customers) {
        long[] spends = customers.Select(customer => (long) customer.spend).OrderBy(value => value).ToArray();
        long total = 0, weighted = 0;
        for (int i = 0; i < spends.Length; i++) { total += spends[i]; weighted += (i + 1L) * spends[i]; }
        return (2 * weighted - (spends.Length + 1L) * total) / (double) (spends.Length * total);
    }
    public static Dictionary<string, int> categoryTotals(List<Customer> customers) {
        Dictionary<string, int> totals = new(StringComparer.Ordinal);
        foreach (Customer customer in customers) foreach (var entry in customer.categorySpend) totals[entry.Key] = totals.GetValueOrDefault(entry.Key) + entry.Value;
        return totals;
    }
    public static List<string> ranking(Dictionary<string, int> totals) {
        return totals.Keys.Where(category => totals[category] > 0).OrderByDescending(category => totals[category]).ThenBy(category => category, StringComparer.Ordinal).ToList();
    }
    public static string yesNo(bool flag) { return flag ? "yes" : "no"; }
    public static string ints(int[] values) { return string.Join(" ", values.Select(value => value.ToString(CultureInfo.InvariantCulture))); }
    public static List<string> blocks(List<List<string>> blocks) {
        List<string> lines = new();
        foreach (List<string> block in blocks) { if (lines.Count != 0) lines.Add(""); lines.AddRange(block); }
        return lines;
    }
    public sealed class Analysis {
        public readonly Params settings;
        public readonly TransactionData data;
        public readonly List<NamingRule> rules;
        public readonly Minstd random;
        public readonly List<Order> referenceOrders;
        public readonly Dictionary<string, List<Order>> customerOrders;
        public readonly List<Customer> customers;
        public readonly Dictionary<string, int> numbers = new();
        public readonly int n;
        public readonly double[] means, sds;
        public readonly List<double[]> points = new();
        public readonly List<Candidate> candidates = new();
        public readonly Dictionary<string, int> votes = new();
        public Candidate chosen;
        public int finalVotes, k;
        public int[] labels, other, scoresR, scoresF, scoresM;
        public string[] codes;
        public List<double[]> centers;
        public List<string> names, categoryNames;
        public double[] silhouettes, distances, otherDistances, segmentSse;
        public int totalSpend;
        public Dictionary<string, int> overallCategories;
        public readonly List<List<Customer>> segmentCustomers = new();
        public readonly List<Dictionary<string, int>> segmentCategories = new();
        public readonly List<List<string>> rankings = new();
        public int[] segmentSpends;
        public double[][] jaccards;
        public Analysis(Params settings, TransactionData data, List<NamingRule> rules) {
            this.settings = settings; this.data = data; this.rules = rules; random = new Minstd(settings.seed);
            referenceOrders = Transactions.groupOrders(data.validRows, 1, settings.referenceDay);
            customerOrders = Transactions.byCustomer(referenceOrders);
            customers = Features.eligible(referenceOrders, settings.referenceDay); n = customers.Count;
            List<double[]> transformed = new();
            for (int i = 0; i < n; i++) { numbers.Add(customers[i].id, i); transformed.Add(customers[i].transformed()); }
            Standardization standard = Features.standardization(transformed); means = standard.means; sds = standard.sds;
            foreach (double[] values in transformed) points.Add(Features.standardize(values, means, sds));
        }
        public string ids(int[] indices) {
            List<string> values = new();
            foreach (int index in indices) values.Add(customers[index].id);
            return string.Join(" ", values);
        }
        public Candidate candidate(int count) { return candidates[count - settings.kMin]; }
        public void analyze() {
            for (int count = settings.kMin; count <= settings.kMax; count++) candidates.Add(search(count));
            evaluate(); chooseK(); describeFinal(); subsamples();
        }
        public Candidate search(int count) {
            List<Run> runs = new(), bests = new();
            foreach (string method in settings.methods) {
                List<Run> methodRuns = new();
                for (int number = 1; number <= settings.restarts; number++)
                    methodRuns.Add(new Run(method, number, seeds(method, points, count, number, random), points, settings.maxIterations));
                runs.AddRange(methodRuns); bests.Add(bestRun(methodRuns));
            }
            Run best = bestRun(bests);
            return new Candidate(count, runs, bests, best, new Solution(points, best.improved.labels, count));
        }
        public void evaluate() {
            double[][] table = Validation.distanceTable(points);
            double first = candidates[0].solution.sse, last = candidates[^1].solution.sse;
            for (int position = 0; position < candidates.Count; position++) {
                Candidate c = candidates[position]; Solution s = c.solution;
                c.silhouettes = Validation.silhouettes(table, s.labels, s.sizes);
                c.silhouette = Features.sum(c.silhouettes) / n;
                c.calinskiHarabasz = Validation.calinskiHarabasz(points, s.centers, s.sizes, s.sse);
                c.daviesBouldin = Validation.daviesBouldin(points, s.labels, s.centers, s.sizes);
                c.elbow = Validation.elbow(c.k, settings.kMin, settings.kMax, s.sse, first, last);
                if (c.k < settings.kMax) c.hartigan = Validation.hartigan(s.sse, candidates[position + 1].solution.sse, n, c.k);
                c.ruleNumbers = new int[c.k]; c.names = new();
                Dictionary<int, int> repeats = new();
                for (int j = 0; j < c.k; j++) {
                    int rule = Profiles.ruleNumber(rules, s.centers[j]); c.ruleNumbers[j] = rule;
                    int repeat = repeats.GetValueOrDefault(rule) + 1; repeats[rule] = repeat;
                    c.names.Add(rules[rule - 1].name + (repeat == 1 ? "" : "_" + repeat));
                }
            }
        }
        public void chooseK() {
            Candidate elbow = candidates[1], silhouette = candidates[0], ch = silhouette, db = silhouette;
            int hartigan = settings.kMax; bool found = false;
            for (int i = 0; i < candidates.Count; i++) {
                Candidate c = candidates[i];
                if (i > 0 && i < candidates.Count - 1 && Report.fourDecimal(c.elbow) > Report.fourDecimal(elbow.elbow)) elbow = c;
                if (Report.fourDecimal(c.silhouette) > Report.fourDecimal(silhouette.silhouette)) silhouette = c;
                if (Report.fourDecimal(c.calinskiHarabasz) > Report.fourDecimal(ch.calinskiHarabasz)) ch = c;
                if (Report.fourDecimal(c.daviesBouldin) < Report.fourDecimal(db.daviesBouldin)) db = c;
                if (!found && c.hartigan.HasValue && c.hartigan.Value <= 10) { hartigan = c.k; found = true; }
            }
            votes.Add("elbow", elbow.k); votes.Add("silhouette", silhouette.k); votes.Add("calinski_harabasz", ch.k);
            votes.Add("davies_bouldin", db.k); votes.Add("hartigan", hartigan);
            chosen = candidates[0]; finalVotes = -1;
            foreach (Candidate c in candidates) {
                int count = 0; foreach (int vote in votes.Values) if (vote == c.k) count++;
                if (count > finalVotes || count == finalVotes && Report.fourDecimal(c.silhouette) > Report.fourDecimal(chosen.silhouette)) {
                    chosen = c; finalVotes = count;
                }
            }
        }
        public void describeFinal() {
            Solution s = chosen.solution; k = s.k; labels = s.labels; centers = s.centers; names = chosen.names; silhouettes = chosen.silhouettes;
            distances = new double[n]; otherDistances = new double[n]; other = new int[n];
            scoresR = new int[n]; scoresF = new int[n]; scoresM = new int[n]; codes = new string[n];
            for (int i = 0; i < n; i++) {
                int nearest = -1;
                for (int j = 0; j < k; j++) if (j != labels[i] && (nearest < 0 || KMeans.squaredDistance(points[i], centers[j]) < KMeans.squaredDistance(points[i], centers[nearest]))) nearest = j;
                distances[i] = Math.Sqrt(KMeans.squaredDistance(points[i], centers[labels[i]]));
                other[i] = nearest; otherDistances[i] = Math.Sqrt(KMeans.squaredDistance(points[i], centers[nearest]));
                Customer customer = customers[i]; int older = 0, fewer = 0, smaller = 0;
                foreach (Customer peer in customers) {
                    if (peer.recency > customer.recency) older++;
                    if (peer.frequency < customer.frequency) fewer++;
                    if (peer.spend < customer.spend) smaller++;
                }
                scoresR[i] = 1 + 5 * older / n; scoresF[i] = 1 + 5 * fewer / n; scoresM[i] = 1 + 5 * smaller / n;
                codes[i] = "" + scoresR[i] + scoresF[i] + scoresM[i]; totalSpend += customer.spend;
            }
            overallCategories = categoryTotals(customers); categoryNames = overallCategories.Keys.OrderBy(category => category, StringComparer.Ordinal).ToList();
            segmentSpends = new int[k]; segmentSse = new double[k];
            for (int j = 0; j < k; j++) {
                List<Customer> group = new();
                foreach (int i in s.members[j]) { group.Add(customers[i]); segmentSpends[j] += customers[i].spend; segmentSse[j] += KMeans.squaredDistance(points[i], centers[j]); }
                segmentCustomers.Add(group); Dictionary<string, int> totals = categoryTotals(group);
                segmentCategories.Add(totals); rankings.Add(ranking(totals));
            }
        }
        public void subsamples() {
            int size = n * settings.subsamplePercent / 100; jaccards = Enumerable.Range(0, k).Select(_ => new double[settings.subsamples]).ToArray();
            for (int b = 0; b < settings.subsamples; b++) {
                int[] order = new int[n]; for (int i = 0; i < n; i++) order[i] = i;
                for (int t = 0; t < size; t++) { int j = t + (int) (random.draw() % (n - t)); int swap = order[t]; order[t] = order[j]; order[j] = swap; }
                int[] sample = order.Take(size).ToArray(); Array.Sort(sample);
                List<double[]> subset = new(); foreach (int i in sample) subset.Add(points[i]);
                int[] sampledLabels = KMeans.lloyd(subset, centers, settings.maxIterations).labels;
                for (int segment = 0; segment < k; segment++) for (int j = 0; j < k; j++) {
                    int both = 0, either = 0;
                    for (int t = 0; t < size; t++) {
                        bool member = labels[sample[t]] == segment, assigned = sampledLabels[t] == j;
                        if (member && assigned) both++; if (member || assigned) either++;
                    }
                    if (either > 0) jaccards[segment][b] = Math.Max(jaccards[segment][b], both / (double) either);
                }
            }
        }
        public string recommendation(int i) {
            foreach (string category in rankings[labels[i]]) if (customers[i].categorySpend.GetValueOrDefault(category, 0) <= 0) return category;
            return "-";
        }
        public List<string> featuresLines() {
            List<string> lines = [FEATURES_HEADER];
            for (int i = 0; i < n; i++) {
                Customer c = customers[i];
                List<string> fields = [c.id, "" + c.recency, "" + c.frequency, Report.amount(c.spend), Report.real(c.basket), "" + c.categories, "" + c.tenure];
                foreach (double value in points[i]) fields.Add(Report.real(value)); lines.Add(string.Join(",", fields));
            }
            return lines;
        }
        public string runSummary(Run run) { return run.method + " restart " + run.number + " sse " + Report.real(run.improved.sse); }
        public string runLine(Run run) {
            return "run " + run.method + " " + run.number + " seeds " + ids(run.seeds) + " iterations " + run.lloyd.iterations
                + " converged " + yesNo(run.lloyd.converged) + " reseeds " + run.lloyd.reseeds + " sse " + Report.real(run.lloydSse)
                + " passes " + run.improved.passes + " transfers " + run.improved.transfers + " refined " + Report.real(run.improved.sse);
        }
        public List<string> runsLines() {
            List<List<string>> blocks = new();
            foreach (Candidate c in candidates) {
                List<string> lines = ["k " + c.k];
                foreach (Run run in c.runs) lines.Add(runLine(run));
                foreach (Run run in c.methodBests) lines.Add("best " + runSummary(run));
                lines.Add("chosen " + runSummary(c.best)); lines.Add("sizes " + ints(c.solution.sizes)); blocks.Add(lines);
            }
            return Program.blocks(blocks);
        }
        public List<string> selectionLines() {
            List<string> indices = ["indices"], voteLines = ["votes"];
            List<string> segments = ["segments"], stability = ["stability"];
            for (int position = 0; position < candidates.Count; position++) {
                Candidate c = candidates[position];
                indices.Add("k=" + c.k + " sse " + Report.real(c.solution.sse) + " elbow " + Report.real(c.elbow) + " silhouette " + Report.real(c.silhouette)
                    + " calinski_harabasz " + Report.real(c.calinskiHarabasz) + " davies_bouldin " + Report.real(c.daviesBouldin) + " hartigan " + (c.hartigan == null ? "-" : Report.real(c.hartigan.Value)));
                List<string> parts = new(); for (int j = 0; j < c.k; j++) parts.Add(c.names[j] + ":" + c.solution.sizes[j]);
                segments.Add("k=" + c.k + " " + string.Join(" ", parts));
                parts = ["k=" + c.k];
                for (int i = 0; i < c.methodBests.Count; i++) for (int j = i + 1; j < c.methodBests.Count; j++) {
                    Run a = c.methodBests[i], b = c.methodBests[j];
                    parts.Add(a.method + ":" + b.method + " " + Report.real(Validation.ari(a.improved.labels, b.improved.labels)));
                }
                parts.Add("final");
                foreach (Run run in c.methodBests) parts.Add(run.method + " " + Report.real(Validation.ari(run.improved.labels, c.solution.labels)));
                parts.Add(position + 1 < candidates.Count ? "next " + Report.real(Validation.ari(c.solution.labels, candidates[position + 1].solution.labels)) : "next -");
                stability.Add(string.Join(" ", parts));
            }
            foreach (string criterion in new[] { "elbow", "silhouette", "calinski_harabasz", "davies_bouldin", "hartigan" }) voteLines.Add(criterion + " k=" + votes[criterion]);
            voteLines.Add("chosen k=" + chosen.k + " votes " + finalVotes);
            return blocks([indices, voteLines, segments, stability]);
        }
        public List<string> segmentsLines() {
            List<string> lines = [SEGMENTS_HEADER];
            for (int i = 0; i < n; i++) lines.Add(string.Join(",", customers[i].id, "" + (labels[i] + 1), names[labels[i]], Report.real(distances[i]),
                "" + (other[i] + 1), Report.real(otherDistances[i]), Report.real(silhouettes[i]), recommendation(i)));
            return lines;
        }
        public string medianLine(List<Customer> group) {
            int index = (group.Count - 1) / 2;
            int recency = group.Select(c => c.recency).OrderBy(value => value).ToArray()[index];
            int frequency = group.Select(c => c.frequency).OrderBy(value => value).ToArray()[index];
            int spend = group.Select(c => c.spend).OrderBy(value => value).ToArray()[index];
            double basket = group.Select(c => c.basket).OrderBy(value => value).ToArray()[index];
            int categories = group.Select(c => c.categories).OrderBy(value => value).ToArray()[index];
            int tenure = group.Select(c => c.tenure).OrderBy(value => value).ToArray()[index];
            return "  median recency " + recency + " frequency " + frequency + " monetary " + Report.amount(spend) + " basket " + Report.real(basket) + " categories " + categories + " tenure " + tenure;
        }
        public string related(List<int> members, int count) {
            if (count < settings.kMin || count > settings.kMax) return "k=" + count + " -";
            int[] counts = new int[count], related = candidate(count).solution.labels;
            foreach (int i in members) counts[related[i]]++;
            int best = 0; for (int i = 1; i < count; i++) if (counts[i] > counts[best]) best = i;
            return "k=" + count + " segment " + (best + 1) + " shared " + counts[best];
        }
        public string cadenceLine(List<Customer> group) {
            List<double> gaps = new(); int overdue = 0;
            foreach (Customer c in group) if (c.frequency >= 2) {
                int active = c.tenure - c.recency, intervals = c.frequency - 1; gaps.Add(active / (double) intervals);
                if (c.recency * intervals > settings.overdueFactor * active) overdue++;
            }
            return "  cadence customers " + gaps.Count + " mean_gap " + (gaps.Count == 0 ? "-" : Report.real(Features.mean(gaps.ToArray()))) + " overdue " + overdue;
        }
        public string orderSizesLine(List<Customer> group) {
            int[] bins = new int[settings.orderBins.Length + 1];
            foreach (Customer c in group) foreach (Order order in c.orders) { int bin = 0; foreach (int bound in settings.orderBins) if (order.net >= bound * 100) bin++; bins[bin]++; }
            return "  order_sizes " + ints(bins);
        }
        public string returnsLine(List<Customer> group) {
            int gross = 0, returned = 0, cancelled = 0;
            foreach (Customer c in group) foreach (Order order in customerOrders[c.id]) {
                if (!order.valid()) cancelled++;
                foreach (Transaction row in order.rows) { if (row.amount > 0) gross += row.amount; else if (row.amount < 0) returned -= row.amount; }
            }
            return "  returns rate " + Report.real(returned / (double) gross) + " returned " + Report.amount(returned) + " cancelled " + cancelled;
        }
        public string rfmLine(List<int> members) {
            int r = 0, f = 0, m = 0; Dictionary<string, int> counts = new(StringComparer.Ordinal);
            foreach (int i in members) { r += scoresR[i]; f += scoresF[i]; m += scoresM[i]; counts[codes[i]] = counts.GetValueOrDefault(codes[i]) + 1; }
            string mode = counts.Keys.OrderBy(code => code, StringComparer.Ordinal).First();
            foreach (string code in counts.Keys.OrderBy(code => code, StringComparer.Ordinal)) if (counts[code] > counts[mode]) mode = code;
            return "  rfm r " + Report.real(r / (double) members.Count) + " f " + Report.real(f / (double) members.Count) + " m " + Report.real(m / (double) members.Count) + " mode " + mode + " " + counts[mode];
        }
        public string categoriesLine(int segment) {
            List<string> parts = ["  categories"]; int added = 0;
            foreach (string category in rankings[segment]) {
                if (added++ >= settings.topCategories) break;
                double share = segmentCategories[segment][category] / (double) segmentSpends[segment];
                double lift = share / (overallCategories[category] / (double) totalSpend);
                parts.Add(category); parts.Add(Report.real(share)); parts.Add(Report.real(lift));
            }
            return string.Join(" ", parts);
        }
        public string outliersLine(List<int> members) {
            List<string> outliers = new();
            if (members.Count >= 2) {
                double[] values = members.Select(i => distances[i]).ToArray();
                double limit = Features.mean(values) + settings.outlierSd * Features.sampleSd(values);
                foreach (int i in members) if (distances[i] > limit) outliers.Add(customers[i].id);
            }
            List<string> parts = ["  outliers", "" + outliers.Count]; parts.AddRange(outliers); return string.Join(" ", parts);
        }
        public List<string> segmentProfile(int segment) {
            List<int> members = chosen.solution.members[segment]; List<Customer> group = segmentCustomers[segment];
            int size = members.Count, spend = segmentSpends[segment]; double[] center = centers[segment];
            List<string> lines = new List<string>(["segment " + (segment + 1) + " " + names[segment] + " rule " + chosen.ruleNumbers[segment]
                + " size " + size + " share " + Report.real(size / (double) n) + " revenue " + Report.amount(spend) + " revenue_share " + Report.real(spend / (double) totalSpend)]);
            lines.Add("  center " + Report.reals(center));
            double[] values = Profiles.originalScale(center, means, sds); List<string> parts = new();
            for (int f = 0; f < 6; f++) parts.Add(Features.NAMES[f] + " " + Report.real(values[f])); lines.Add("  value " + string.Join(" ", parts));
            List<int> order = new(); for (int f = 0; f < 6; f++) order.Add(f);
            order = order.OrderBy(f => -Math.Abs(center[f])).ThenBy(f => f).ToList(); parts.Clear();
            foreach (int f in order.GetRange(0, 2)) parts.Add((center[f] > 0 ? "high_" : "low_") + Features.NAMES[f]); lines.Add("  traits " + string.Join(" ", parts));
            lines.Add(medianLine(group)); lines.Add("  related " + related(members, k - 1) + " " + related(members, k + 1));
            List<int> top = new List<int>(members); top = top.OrderByDescending(i => customers[i].spend).ThenBy(i => i).ToList();
            parts = ["  top_customers"];
            foreach (int i in top.Take(settings.topCustomers)) { parts.Add(customers[i].id); parts.Add(Report.amount(customers[i].spend)); }
            lines.Add(string.Join(" ", parts)); lines.Add(cadenceLine(group)); lines.Add(orderSizesLine(group));
            lines.Add("  sse " + Report.real(segmentSse[segment]) + " share " + Report.real(segmentSse[segment] / chosen.solution.sse));
            lines.Add("  gini " + Report.real(gini(group))); lines.Add(returnsLine(group));
            double[] sil = members.Select(i => silhouettes[i]).ToArray(); int negative = 0; foreach (double value in sil) if (value < 0) negative++;
            lines.Add("  silhouette " + Report.real(Features.mean(sil)) + " negative " + negative);
            lines.Add(rfmLine(members)); lines.Add(categoriesLine(segment)); lines.Add(outliersLine(members)); return lines;
        }
        public string segmentNumbers() { int[] values = new int[k]; for (int j = 0; j < k; j++) values[j] = j + 1; return ints(values); }
        public List<string> profilesLines() {
            List<List<string>> groups = new();
            groups.Add(["segments k=" + k + " customers " + n + " revenue " + Report.amount(totalSpend) + " gini " + Report.real(gini(customers))]);
            for (int j = 0; j < k; j++) groups.Add(segmentProfile(j));
            List<string> mix = ["category_mix " + segmentNumbers()];
            foreach (string category in categoryNames) {
                double[] shares = new double[k]; for (int j = 0; j < k; j++) shares[j] = segmentCategories[j].GetValueOrDefault(category, 0) / (double) segmentSpends[j];
                mix.Add(category + " " + Report.reals(shares));
            }
            groups.Add(mix); List<string> recency = ["rfm_recency " + segmentNumbers()];
            for (int score = 5; score >= 1; score--) { int[] counts = new int[k]; for (int i = 0; i < n; i++) if (scoresR[i] == score) counts[labels[i]]++; recency.Add("r=" + score + " " + ints(counts)); }
            int[] numericCodes = codes.Select(int.Parse).ToArray();
            recency.Add("ari rfm_codes " + Report.real(Validation.ari(numericCodes, labels))); groups.Add(recency);
            List<string> centerLines = ["center_distances"];
            for (int j = 0; j < k; j++) {
                double[] values = new double[k]; for (int q = 0; q < k; q++) values[q] = Math.Sqrt(KMeans.squaredDistance(centers[j], centers[q]));
                centerLines.Add((j + 1) + " " + Report.reals(values));
            }
            groups.Add(centerLines); return blocks(groups);
        }
        public List<string> robustnessLines() {
            List<string> sample = ["subsamples " + settings.subsamples + " size " + n * settings.subsamplePercent / 100];
            for (int j = 0; j < k; j++) sample.Add("segment " + (j + 1) + " " + names[j] + " mean_jaccard " + Report.real(Features.mean(jaccards[j])) + " min_jaccard " + Report.real(jaccards[j].Min()));
            List<string> ablation = ["ablation"];
            for (int f = 0; f < 6; f++) {
                List<double[]> subset = new();
                foreach (double[] point in points) { double[] reduced = new double[5]; int position = 0; for (int q = 0; q < 6; q++) if (q != f) reduced[position++] = point[q]; subset.Add(reduced); }
                int[] seed = seeds("maximin", subset, k, 1, random); Run run = new Run("maximin", 1, seed, subset, settings.maxIterations);
                ablation.Add("without " + Features.NAMES[f] + " seeds " + ids(seed) + " iterations " + run.lloyd.iterations + " converged " + yesNo(run.lloyd.converged)
                    + " transfers " + run.improved.transfers + " sse " + Report.real(run.improved.sse) + " ari " + Report.real(Validation.ari(run.improved.labels, labels)));
            }
            List<int> members = chosen.solution.members[0]; List<double[]> drillPoints = new(); foreach (int i in members) drillPoints.Add(points[i]);
            int[] drillSeeds = seeds("maximin", drillPoints, 2, 1, random); Run drillRun = new Run("maximin", 1, drillSeeds, drillPoints, settings.maxIterations); Solution parts = new Solution(drillPoints, drillRun.improved.labels, 2);
            int[] originalSeeds = drillSeeds.Select(i => members[i]).ToArray();
            List<string> drilldown = new List<string>(["drilldown segment 1 " + names[0] + " size " + members.Count + " seeds " + ids(originalSeeds)
                + " iterations " + drillRun.lloyd.iterations + " converged " + yesNo(drillRun.lloyd.converged) + " transfers " + drillRun.improved.transfers,
                "sse before " + Report.real(segmentSse[0]) + " after " + Report.real(drillRun.improved.sse) + " gain " + Report.real(segmentSse[0] - drillRun.improved.sse)]);
            for (int j = 0; j < 2; j++) drilldown.Add("part " + (j + 1) + " size " + parts.sizes[j] + " center " + Report.reals(parts.centers[j]));
            return blocks([sample, ablation, drilldown]);
        }
        public List<string> periodLines() {
            int day = settings.referenceDay, days = settings.periodDays; List<string> lines = ["periods " + settings.periods + " days " + days];
            for (int q = 1; q <= settings.periods; q++) {
                int first = day - q * days + 1, last = day - (q - 1) * days;
                int[] revenue = new int[k], active = new int[k], acquired = new int[k];
                for (int i = 0; i < n; i++) {
                    Customer c = customers[i]; int label = labels[i]; bool bought = false;
                    foreach (Order order in c.orders) if (order.day >= first && order.day <= last) { revenue[label] += order.net; bought = true; }
                    if (bought) active[label]++; if (day - c.tenure >= first && day - c.tenure <= last) acquired[label]++;
                }
                List<string> parts = ["period " + q + " days " + first + " " + last + " revenue"];
                foreach (int value in revenue) parts.Add(Report.amount(value)); parts.Add("active"); parts.Add(ints(active)); parts.Add("acquired"); parts.Add(ints(acquired)); lines.Add(string.Join(" ", parts));
            }
            return lines;
        }
        public List<string> migrationLines() {
            int day = settings.snapshotDay; Dictionary<string, int> snapshot = new(StringComparer.Ordinal);
            foreach (Customer c in Features.eligible(Transactions.groupOrders(data.validRows, 1, day), day)) {
                double[] point = Features.standardize(c.transformed(), means, sds); int best = 0;
                for (int j = 1; j < k; j++) if (KMeans.squaredDistance(point, centers[j]) < KMeans.squaredDistance(point, centers[best])) best = j;
                snapshot.Add(c.id, best);
            }
            int[][] table = Enumerable.Range(0, k + 1).Select(_ => new int[k]).ToArray(); int stayed = 0, fresh = 0, lost = 0; List<string> moved = new();
            for (int i = 0; i < n; i++) {
                int? origin = snapshot.TryGetValue(customers[i].id, out int previous) ? previous : null; int label = labels[i];
                if (origin == null) { table[k][label]++; fresh++; }
                else { table[origin.Value][label]++; if (origin == label) stayed++; else moved.Add(customers[i].id + " " + (origin.Value + 1) + " " + (label + 1)); }
            }
            foreach (string id in snapshot.Keys) if (!numbers.ContainsKey(id)) lost++;
            List<string> lines = ["migration day " + day + " customers " + snapshot.Count, "from\\to " + segmentNumbers()];
            for (int j = 0; j <= k; j++) lines.Add((j == k ? "none" : "" + (j + 1)) + " " + ints(table[j]));
            lines.Add("moved_customers"); lines.AddRange(moved); lines.Add("stayed " + stayed + " moved " + moved.Count + " new " + fresh + " lost " + lost); return lines;
        }
        public List<string> outcomeLines() {
            int first = settings.referenceDay + 1, last = settings.referenceDay + settings.outcomeDays;
            Dictionary<string, List<Order>> purchases = Transactions.byCustomer(Transactions.groupOrders(data.validRows, first, last).Where(order => order.valid()).ToList());
            List<string> lines = ["outcome days " + first + " " + last];
            for (int j = 0; j < k; j++) {
                int buyers = 0, spend = 0, size = segmentCustomers[j].Count;
                foreach (Customer c in segmentCustomers[j]) if (purchases.ContainsKey(c.id)) { buyers++; foreach (Order order in purchases[c.id]) spend += order.net; }
                lines.Add("segment " + (j + 1) + " " + names[j] + " size " + size + " buyers " + buyers + " rate " + Report.real(buyers / (double) size)
                    + " revenue " + Report.amount(spend) + " per_customer " + Report.real((spend / 100.0) / size));
            }
            int outsiders = 0, outsiderSpend = 0;
            foreach (var entry in purchases) if (!numbers.ContainsKey(entry.Key)) { outsiders++; foreach (Order order in entry.Value) outsiderSpend += order.net; }
            lines.Add("unsegmented buyers " + outsiders + " revenue " + Report.amount(outsiderSpend)); return lines;
        }
        public List<string> summaryLines() {
            int used = 0, returned = 0, later = 0, valid = 0;
            foreach (Transaction row in data.validRows) if (row.day <= settings.referenceDay) { used++; if (row.amount < 0) returned++; } else later++;
            foreach (Order order in referenceOrders) if (order.valid()) valid++;
            List<string> excluded = data.customers.Where(id => !numbers.ContainsKey(id)).ToList();
            List<string> dataLines = ["rows " + data.rowCount + " duplicates " + data.duplicates + " zero " + data.free + " used " + used + " returns " + returned + " later " + later,
                "orders " + referenceOrders.Count + " valid " + valid + " cancelled " + (referenceOrders.Count - valid),
                "customers " + data.customers.Count + " clustered " + n + " excluded " + excluded.Count, "excluded_ids " + (excluded.Count == 0 ? "-" : string.Join(" ", excluded))];
            List<string> categoryLines = new();
            foreach (string category in categoryNames) {
                int buyers = 0; foreach (Customer c in customers) if (c.categorySpend.GetValueOrDefault(category, 0) > 0) buyers++;
                int total = overallCategories[category]; categoryLines.Add("category " + category + " revenue " + Report.amount(total) + " share " + Report.real(total / (double) totalSpend) + " customers " + buyers);
            }
            List<string> features = new(), correlations = ["correlation " + string.Join(" ", Features.NAMES)];
            for (int f = 0; f < 6; f++) {
                double[] column = new double[n]; for (int i = 0; i < n; i++) column[i] = customers[i].values()[f];
                features.Add("feature " + Features.NAMES[f] + " transform " + (Features.SQRT[f] ? "sqrt" : "none") + " raw_mean " + Report.real(Features.mean(column))
                    + " raw_sd " + Report.real(Features.sampleSd(column)) + " mean " + Report.real(means[f]) + " sd " + Report.real(sds[f]));
                double[] values = new double[6]; for (int q = 0; q < 6; q++) values[q] = Features.correlation(points, f, q);
                correlations.Add(Features.NAMES[f] + " " + Report.reals(values));
            }
            return blocks([dataLines, categoryLines, features, correlations]);
        }
    }
    public static void Main(string[] args)  {
        Analysis analysis = new Analysis(Transactions.readParams("input/params.txt"), Transactions.read("input/transactions.csv"), Profiles.read("input/segment_rules.txt"));
        analysis.analyze(); Dictionary<string, List<string>> files = new();
        files.Add("features.csv", analysis.featuresLines()); files.Add("runs.txt", analysis.runsLines()); files.Add("selection.txt", analysis.selectionLines());
        files.Add("segments.csv", analysis.segmentsLines()); files.Add("profiles.txt", analysis.profilesLines()); files.Add("robustness.txt", analysis.robustnessLines());
        files.Add("tracking.txt", blocks([analysis.periodLines(), analysis.migrationLines(), analysis.outcomeLines()])); files.Add("summary.txt", analysis.summaryLines());
        Report.writeFiles(files);
    }
}
