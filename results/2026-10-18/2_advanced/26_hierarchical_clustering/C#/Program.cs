using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Globalization;
using System.Numerics;
using System.Text;

static class Program
{
    static string Real(double? value)
    {
        if (value is null) return "-";
        string text = value.Value.ToString("F4", CultureInfo.InvariantCulture);
        return text == "-0.0000" ? "0.0000" : text;
    }
    static double FourDigit(double value) => double.Parse(Real(value), CultureInfo.InvariantCulture);
    static string Reals(IEnumerable<double> values) => string.Join(" ", values.Select(value => Real(value)));
    static string Integers(IEnumerable<int> values) => string.Join(" ", values);
    static string AriText(Fraction value) => value + " " + Real(value.Value);
    static double[] PairValues(double[][] matrix)
    {
        double[] values = new double[matrix.Length * (matrix.Length - 1) / 2];
        int position = 0;
        for (int i = 0; i < matrix.Length; i++) for (int j = i + 1; j < matrix.Length; j++) values[position++] = matrix[i][j];
        return values;
    }
    static int HistogramBin(double value, double maximum) => Math.Min(9, (int)Math.Floor(10 * value / maximum));
    static List<List<int>> ClusterMembers(int[] partition, int groups)
    {
        List<List<int>> members = Enumerable.Range(0, groups).Select(_ => new List<int>()).ToList();
        for (int i = 0; i < partition.Length; i++) members[partition[i] - 1].Add(i);
        return members;
    }
    static double[] Centroid(double[][] vectors)
    {
        double[] center = new double[vectors[0].Length];
        for (int f = 0; f < center.Length; f++)
        {
            double total = 0.0;
            foreach (double[] vector in vectors) total += vector[f];
            center[f] = total / vectors.Length;
        }
        return center;
    }
    static int MajorityClass(int[] row)
    {
        int best = 0;
        for (int t = 1; t < row.Length; t++) if (row[t] > row[best]) best = t;
        return best;
    }
    static List<string> JoinParts(IEnumerable<List<string>> parts)
    {
        List<string> lines = [];
        foreach (List<string> part in parts) { if (lines.Count > 0) lines.Add(""); lines.AddRange(part); }
        return lines;
    }
    static int[] ConnectedComponents(int count, IEnumerable<Agglomerative.Edge> edges)
    {
        int[] components = Enumerable.Range(0, count).ToArray();
        foreach (Agglomerative.Edge edge in edges)
        {
            int old = components[edge.Child], replacement = components[edge.Parent];
            for (int u = 0; u < count; u++) if (components[u] == old) components[u] = replacement;
        }
        return components;
    }
    sealed class Minstd(int seed)
    {
        long state = seed;
        public long Draw() { state = 48271 * state % 2147483647; return state; }
    }
    sealed class Settings
    {
        public readonly string Distance, Standardize, CompareLinkage;
        public readonly string[] Linkages;
        public readonly double[] CutHeights;
        public readonly int[] CutCounts;
        public readonly BigInteger InconsistencyDepth;
        public readonly int InconsistencyCount, GapMaxK, ListSize, Width, Replicates, Percent, Seed, RefineIterations;
        public Settings(Dictionary<string, string[]> entries)
        {
            Distance = entries["DISTANCE"][0]; Standardize = entries["STANDARDIZE"][0]; Linkages = entries["LINKAGES"];
            CutHeights = entries["CUT_HEIGHTS"].Select(value => double.Parse(value, CultureInfo.InvariantCulture)).ToArray();
            CutCounts = entries["CUT_K"].Select(int.Parse).ToArray();
            InconsistencyDepth = BigInteger.Parse(entries["INCONSISTENCY"][0], CultureInfo.InvariantCulture);
            InconsistencyCount = int.Parse(entries["INCONSISTENCY"][1], CultureInfo.InvariantCulture);
            GapMaxK = int.Parse(entries["GAP_MAX_K"][0], CultureInfo.InvariantCulture); ListSize = int.Parse(entries["LIST_SIZE"][0], CultureInfo.InvariantCulture);
            Width = int.Parse(entries["DENDROGRAM_WIDTH"][0], CultureInfo.InvariantCulture); CompareLinkage = entries["COMPARE_LINKAGE"][0];
            Replicates = int.Parse(entries["SUBSAMPLES"][0], CultureInfo.InvariantCulture); Percent = int.Parse(entries["SUBSAMPLES"][1], CultureInfo.InvariantCulture);
            Seed = int.Parse(entries["SUBSAMPLES"][2], CultureInfo.InvariantCulture); RefineIterations = int.Parse(entries["REFINE_ITERATIONS"][0], CultureInfo.InvariantCulture);
        }
    }
    sealed class Tree
    {
        public readonly List<Agglomerative.Merge> Merges;
        public readonly int Count;
        public readonly double[] Heights, SubtreeHeights;
        public readonly int[][] Children;
        public readonly int[] Order, Depths;
        public readonly List<int[]> Members = [];
        public Tree(List<Agglomerative.Merge> merges, int count)
        {
            Merges = merges; Count = count; Heights = merges.Select(merge => merge.Height).ToArray(); Children = Dendrogram.Children(merges, count); Order = Dendrogram.LeafOrder(Children, count);
            Depths = new int[2 * count - 1]; SubtreeHeights = new double[merges.Count];
            for (int u = 0; u < count; u++) Members.Add([u]);
            for (int step = 0; step < merges.Count; step++)
            {
                Agglomerative.Merge merge = merges[step];
                Members.Add([.. Members[merge.A], .. Members[merge.B]]);
                Depths[count + step] = 1 + Math.Max(Depths[merge.A], Depths[merge.B]);
                SubtreeHeights[step] = Math.Max(merge.Height, Math.Max(SubtreeHeight(merge.A), SubtreeHeight(merge.B)));
            }
        }
        public int Root => 2 * Count - 2;
        public double Height(int node) => node < Count ? 0.0 : Heights[node - Count];
        public double SubtreeHeight(int node) => node < Count ? 0.0 : SubtreeHeights[node - Count];
        int[] Partition(bool[] selected)
        {
            int[] owner = Enumerable.Range(0, Count).ToArray();
            for (int step = 0; step < selected.Length; step++) if (selected[step]) foreach (int u in Members[Count + step]) owner[u] = Count + step;
            int[] numbers = new int[2 * Count - 1];
            int groups = 0;
            foreach (int u in Order) if (numbers[owner[u]] == 0) numbers[owner[u]] = ++groups;
            return owner.Select(node => numbers[node]).ToArray();
        }
        public int[] CutAtHeight(double height) => Partition(SubtreeHeights.Select(value => value <= height).ToArray());
        public int[] CutInto(int groups) => Partition(Enumerable.Range(0, Merges.Count).Select(step => step < Count - groups).ToArray());
        public double[][] Cophenetic()
        {
            double[][] matrix = Enumerable.Range(0, Count).Select(_ => new double[Count]).ToArray();
            foreach (Agglomerative.Merge merge in Merges)
                foreach (int i in Members[merge.A]) foreach (int j in Members[merge.B]) matrix[i][j] = matrix[j][i] = merge.Height;
            return matrix;
        }
        public double[] JoiningHeights()
        {
            double[] values = new double[Count];
            foreach (Agglomerative.Merge merge in Merges) { if (merge.A < Count) values[merge.A] = merge.Height; if (merge.B < Count) values[merge.B] = merge.Height; }
            return values;
        }
        public List<double> HeightSequence(int step, int depth)
        {
            List<double> sequence = [];
            if (depth == 0) return sequence;
            Agglomerative.Merge merge = Merges[step];
            sequence.Add(merge.Height);
            foreach (int child in new[] { merge.A, merge.B }) if (child >= Count) sequence.AddRange(HeightSequence(child - Count, depth - 1));
            return sequence;
        }
        public string Newick(int node, string[] idents)
        {
            if (node < Count) return idents[node];
            int upper = Children[node - Count][0], lower = Children[node - Count][1];
            return "(" + Newick(upper, idents) + ":" + Real(Height(node) - Height(upper)) + "," + Newick(lower, idents) + ":" + Real(Height(node) - Height(lower)) + ")";
        }
    }
    sealed record PartitionEvaluation(int[] Partition, int[] Sizes, double? Silhouette, double? Dunn, double Wss, double? Ch, Fraction Ari)
    {
        public string Text() => "sizes " + Integers(Sizes) + " silhouette " + Real(Silhouette) + " dunn " + Real(Dunn) + " wss " + Real(Wss) + " ch " + Real(Ch) + " ari " + AriText(Ari);
    }
    sealed record LinkageResult(string Method, Tree Tree, double[] Cophenetic, double Correlation, List<PartitionEvaluation> HeightCuts, List<PartitionEvaluation> CountCuts, int[] LabelPartition);

    sealed class Study
    {
        readonly string[] featureNames, idents, labels, classes;
        readonly Settings settings;
        readonly int count;
        readonly int[] targets, neighbors;
        readonly double[][] raw, vectors, distances;
        readonly double[] means, deviations, distancePairs;
        readonly double distanceMax;
        readonly List<LinkageResult> results = [];
        readonly LinkageResult chosen;
        readonly int kappa;
        readonly PartitionEvaluation selectedCut;
        readonly int[] selected, majority;
        readonly List<List<int>> members;
        readonly double[] silhouettes;
        readonly int[][] table;

        public Study(InputData input)
        {
            featureNames = input.Features; settings = new Settings(input.Settings); count = input.Observations.Count;
            idents = input.Observations.Select(row => row.Ident).ToArray(); labels = input.Observations.Select(row => row.Label).ToArray();
            classes = labels.Distinct(StringComparer.Ordinal).Order(StringComparer.Ordinal).ToArray(); targets = labels.Select(label => Array.BinarySearch(classes, label, StringComparer.Ordinal)).ToArray();
            raw = input.Observations.Select(row => row.Values).ToArray(); Distances.Statistics statistics = Distances.FeatureStatistics(raw); means = statistics.Means; deviations = statistics.Deviations;
            vectors = settings.Standardize == "yes" ? Distances.Standardize(raw, statistics) : raw; distances = Distances.Matrix(vectors, settings.Distance); distancePairs = PairValues(distances); distanceMax = distancePairs.Max();
            neighbors = Enumerable.Range(0, count).Select(NearestNeighbor).ToArray();
            foreach (string method in settings.Linkages) results.Add(AnalyseLinkage(method));
            int bestResult = 0, bestPosition = 0;
            for (int r = 0; r < results.Count; r++)
                for (int position = 0; position < settings.CutCounts.Length; position++)
                    if (results[r].CountCuts[position].Ari.CompareTo(results[bestResult].CountCuts[bestPosition].Ari) > 0) { bestResult = r; bestPosition = position; }
            chosen = results[bestResult]; kappa = settings.CutCounts[bestPosition]; selectedCut = chosen.CountCuts[bestPosition]; selected = selectedCut.Partition;
            members = ClusterMembers(selected, kappa); silhouettes = Validation.Silhouettes(selected, kappa, distances); table = ClassTable(selected); majority = table.Select(MajorityClass).ToArray();
        }
        int NearestNeighbor(int i)
        {
            int best = -1;
            for (int j = 0; j < count; j++) if (j != i && (best < 0 || distances[i][j] < distances[i][best])) best = j;
            return best;
        }
        int[][] ClassTable(int[] partition) => Validation.Contingency(partition.Select(number => number - 1).ToArray(), targets, partition.Max(), classes.Length);
        Fraction LabelAri(int[] partition) => Validation.AdjustedRand(ClassTable(partition));
        static Fraction PartitionAri(int[] first, int[] second) => Validation.AdjustedRand(Validation.Contingency(first.Select(number => number - 1).ToArray(), second.Select(number => number - 1).ToArray(), first.Max(), second.Max()));
        int MatchCount(int[] partition) => ClassTable(partition).Sum(row => row.Max());
        static double? MeanSilhouette(int[] partition, double[][] delta)
        {
            int groups = partition.Max();
            return groups < 2 ? null : Distances.Sum(Validation.Silhouettes(partition, groups, delta)) / partition.Length;
        }
        double[][] Centroids(int[] partition) => ClusterMembers(partition, partition.Max()).Select(group => Centroid(group.Select(i => vectors[i]).ToArray())).ToArray();
        double WithinSum(int[] partition)
        {
            double[][] centers = Centroids(partition);
            double total = 0.0;
            for (int i = 0; i < count; i++) total += Distances.Squared(vectors[i], centers[partition[i] - 1]);
            return total;
        }
        double? DunnIndex(int[] partition, int groups)
        {
            double diameter = 0.0, separation = double.PositiveInfinity;
            for (int i = 0; i < count; i++)
                for (int j = i + 1; j < count; j++)
                    if (partition[i] == partition[j]) diameter = Math.Max(diameter, distances[i][j]); else separation = Math.Min(separation, distances[i][j]);
            return groups >= 2 && diameter > 0 ? separation / diameter : null;
        }
        PartitionEvaluation Evaluate(int[] partition)
        {
            int groups = partition.Max();
            int[] sizes = ClusterMembers(partition, groups).Select(group => group.Count).ToArray();
            double wss = WithinSum(partition);
            double? ch = null;
            if (groups >= 2 && groups < count)
            {
                double[] overall = Centroid(vectors);
                double[][] centers = Centroids(partition);
                double bss = 0.0;
                for (int g = 0; g < groups; g++) bss += sizes[g] * Distances.Squared(centers[g], overall);
                ch = (bss / (groups - 1)) / (wss / (count - groups));
            }
            return new PartitionEvaluation(partition, sizes, MeanSilhouette(partition, distances), DunnIndex(partition, groups), wss, ch, LabelAri(partition));
        }
        LinkageResult AnalyseLinkage(string method)
        {
            Tree tree = new(Agglomerative.Cluster(distances, method), count);
            double[] cophenetic = PairValues(tree.Cophenetic());
            List<PartitionEvaluation> heightCuts = settings.CutHeights.Select(height => Evaluate(tree.CutAtHeight(height))).ToList();
            List<PartitionEvaluation> countCuts = settings.CutCounts.Select(k => Evaluate(tree.CutInto(k))).ToList();
            return new LinkageResult(method, tree, cophenetic, Validation.Correlation(distancePairs, cophenetic), heightCuts, countCuts, tree.CutInto(classes.Length));
        }
        List<string> LinkageTable()
        {
            List<string> lines = ["method,step,a,b,height,size"];
            foreach (LinkageResult result in results)
                for (int step = 0; step < result.Tree.Merges.Count; step++)
                {
                    Agglomerative.Merge merge = result.Tree.Merges[step];
                    lines.Add(result.Method + "," + (step + 1) + "," + merge.A + "," + merge.B + "," + Real(merge.Height) + "," + merge.Size);
                }
            return lines;
        }
        List<string> ClustersTable()
        {
            List<string> header = ["id", "label"];
            foreach (LinkageResult result in results)
            {
                for (int j = 1; j <= settings.CutHeights.Length; j++) header.Add(result.Method + "_h" + j);
                foreach (int k in settings.CutCounts) header.Add(result.Method + "_k" + k);
            }
            List<string> lines = [string.Join(",", header)];
            for (int i = 0; i < count; i++)
            {
                List<string> fields = [idents[i], labels[i]];
                foreach (LinkageResult result in results)
                {
                    foreach (PartitionEvaluation cut in result.HeightCuts) fields.Add(cut.Partition[i].ToString(CultureInfo.InvariantCulture));
                    foreach (PartitionEvaluation cut in result.CountCuts) fields.Add(cut.Partition[i].ToString(CultureInfo.InvariantCulture));
                }
                lines.Add(string.Join(",", fields));
            }
            return lines;
        }
        List<string> DendrogramReport()
        {
            List<List<string>> blocks = [];
            foreach (LinkageResult result in results)
            {
                Tree tree = result.Tree;
                double maximum = tree.Heights.Max();
                int[] columns = settings.CutHeights.Select(height => Dendrogram.Column(height, maximum, settings.Width)).ToArray();
                List<string> lines = ["dendrogram " + result.Method + " height_max " + Real(maximum) + " width " + settings.Width];
                lines.AddRange(Dendrogram.Rows(tree.Merges, tree.Children, tree.Order, idents, labels, maximum, columns, settings.Width));
                for (int j = 0; j < columns.Length; j++) lines.Add("cut " + Real(settings.CutHeights[j]) + " column " + (columns[j] <= settings.Width ? columns[j].ToString(CultureInfo.InvariantCulture) : "-"));
                blocks.Add(lines);
            }
            return JoinParts(blocks);
        }
        List<string> TreesReport() => results.Select(result => result.Method + " " + result.Tree.Newick(result.Tree.Root, idents) + ";").ToList();
        string PairText(int first, int second) => Real(distances[first][second]) + " " + idents[first] + " " + idents[second];
        List<string> DataPart()
        {
            List<string> lines = ["data n " + count + " features " + featureNames.Length + " classes " + classes.Length + " distance " + settings.Distance + " standardize " + settings.Standardize];
            for (int f = 0; f < featureNames.Length; f++) lines.Add("feature " + featureNames[f] + " mean " + Real(means[f]) + " sd " + Real(deviations[f]));
            int minFirst = 0, minSecond = 1, maxFirst = 0, maxSecond = 1;
            for (int i = 0; i < count; i++)
                for (int j = i + 1; j < count; j++)
                {
                    if (distances[i][j] < distances[minFirst][minSecond]) { minFirst = i; minSecond = j; }
                    if (distances[i][j] > distances[maxFirst][maxSecond]) { maxFirst = i; maxSecond = j; }
                }
            lines.Add("distances pairs " + distancePairs.Length + " min " + PairText(minFirst, minSecond) + " max " + PairText(maxFirst, maxSecond) + " mean " + Real(Distances.Sum(distancePairs) / distancePairs.Length));
            double nearestTotal = 0.0;
            int reciprocal = 0;
            for (int i = 0; i < count; i++) { nearestTotal += distances[i][neighbors[i]]; if (i < neighbors[i] && neighbors[neighbors[i]] == i) reciprocal++; }
            lines.Add("nearest_neighbors mean " + Real(nearestTotal / count) + " reciprocal_pairs " + reciprocal);
            lines.Add("labels " + Evaluate(targets.Select(target => target + 1).ToArray()).Text());
            return lines;
        }
        List<string> CorrelationPart()
        {
            double[][] columns = Enumerable.Range(0, featureNames.Length).Select(f => raw.Select(row => row[f]).ToArray()).ToArray();
            List<string> lines = ["correlation " + string.Join(" ", featureNames)];
            for (int f = 0; f < featureNames.Length; f++) lines.Add(featureNames[f] + " " + Reals(columns.Select(column => Validation.Correlation(columns[f], column))));
            return lines;
        }
        List<string> HistogramPart()
        {
            int[] counts = new int[10];
            foreach (double value in distancePairs) counts[HistogramBin(value, distanceMax)]++;
            int highest = counts.Max();
            List<string> lines = ["histogram"];
            for (int bin = 0; bin < 10; bin++)
            {
                string line = Real(bin * distanceMax / 10) + " " + Real((bin + 1) * distanceMax / 10) + " " + counts[bin];
                int length = counts[bin] * 50 / highest;
                if (length > 0) line += " " + new string('#', length);
                lines.Add(line);
            }
            return lines;
        }
        double[] Gaps(Tree tree)
        {
            double[] ordered = tree.SubtreeHeights.Order().ToArray();
            double[] gaps = new double[settings.GapMaxK - 1];
            for (int k = 2; k <= settings.GapMaxK; k++) gaps[k - 2] = ordered[count - k] - ordered[count - k - 1];
            return gaps;
        }
        string InconsistencyLine(Tree tree, int step)
        {
            int depth = (int)BigInteger.Min(settings.InconsistencyDepth, count);
            double[] sequence = tree.HeightSequence(step, depth).ToArray();
            int size = sequence.Length;
            double mean = Distances.Sum(sequence) / size, deviation = 0.0, coefficient = 0.0;
            if (size >= 2)
            {
                double squares = 0.0;
                foreach (double value in sequence) { double difference = value - mean; squares += difference * difference; }
                deviation = Math.Sqrt(squares / (size - 1)); coefficient = (tree.Heights[step] - mean) / deviation;
            }
            return "step " + (step + 1) + " height " + Real(tree.Heights[step]) + " mean " + Real(mean) + " sd " + Real(deviation) + " count " + size + " coefficient " + Real(coefficient);
        }
        List<string> LinkagePart(LinkageResult result)
        {
            Tree tree = result.Tree;
            double leafPath = 0.0;
            for (int r = 0; r < count - 1; r++) leafPath += distances[tree.Order[r]][tree.Order[r + 1]];
            int[] inversions = Enumerable.Range(1, tree.Heights.Length - 1).Where(step => tree.Heights[step] < tree.Heights[step - 1]).ToArray();
            List<string> lines = ["linkage " + result.Method, "cophenetic " + Real(result.Correlation) + " leaf_path " + Real(leafPath), "heights min " + Real(tree.Heights.Min()) + " max " + Real(tree.Heights.Max()) + " inversions " + inversions.Length];
            foreach (int step in inversions) lines.Add("inversion step " + (step + 1) + " height " + Real(tree.Heights[step]) + " previous " + Real(tree.Heights[step - 1]));
            double[] gaps = Gaps(tree);
            int suggested = 2;
            for (int k = 3; k <= settings.GapMaxK; k++) if (FourDigit(gaps[k - 2]) > FourDigit(gaps[suggested - 2])) suggested = k;
            lines.Add("gaps " + Reals(gaps)); lines.Add("suggested_k " + suggested);
            double[] joining = tree.JoiningHeights();
            int[] late = Enumerable.Range(0, count).OrderByDescending(i => joining[i]).ThenBy(i => i).Take(settings.ListSize).ToArray();
            lines.Add("late_joiners " + string.Join(" ", late.Select(i => idents[i] + ":" + Real(joining[i]))));
            int[] kinds = new int[3];
            foreach (Agglomerative.Merge merge in tree.Merges) { int leaves = (merge.A < count ? 1 : 0) + (merge.B < count ? 1 : 0); kinds[2 - leaves]++; }
            lines.Add("merges leaf_leaf " + kinds[0] + " leaf_cluster " + kinds[1] + " cluster_cluster " + kinds[2] + " depth " + tree.Depths[tree.Root]);
            int matches = MatchCount(result.LabelPartition);
            lines.Add("label_cut k " + classes.Length + " purity " + matches + "/" + count + " " + Real((double)matches / count));
            lines.Add("inconsistency depth " + settings.InconsistencyDepth);
            for (int step = count - settings.InconsistencyCount - 1; step < count - 1; step++) lines.Add(InconsistencyLine(tree, step));
            for (int j = 0; j < settings.CutHeights.Length; j++) { PartitionEvaluation cut = result.HeightCuts[j]; lines.Add("cut height " + Real(settings.CutHeights[j]) + " clusters " + cut.Sizes.Length + " " + cut.Text()); }
            for (int j = 0; j < settings.CutCounts.Length; j++) lines.Add("cut k " + settings.CutCounts[j] + " " + result.CountCuts[j].Text());
            return lines;
        }
        LinkageResult? ResultOf(string method) => results.FirstOrDefault(result => result.Method == method);
        List<string> MstPart()
        {
            LinkageResult single = ResultOf("single")!;
            List<Agglomerative.Edge> edges = Agglomerative.MinimumSpanningTree(distances);
            double total = 0.0;
            foreach (Agglomerative.Edge edge in edges) total += edge.Weight;
            double[] weights = edges.Select(edge => edge.Weight).Order().ToArray();
            bool heightsMatch = true;
            for (int step = 0; step < weights.Length; step++) if (Math.Abs(weights[step] - single.Tree.Heights[step]) > 0.000000001) heightsMatch = false;
            bool[][] linked = Enumerable.Range(0, count).Select(_ => new bool[count]).ToArray();
            foreach (Agglomerative.Edge edge in edges) linked[edge.Parent][edge.Child] = linked[edge.Child][edge.Parent] = true;
            int nearestEdges = Enumerable.Range(0, count).Count(i => linked[i][neighbors[i]]);
            List<string> lines = ["mst total " + Real(total) + " heights " + (heightsMatch ? "match" : "mismatch") + " nn_edges " + nearestEdges + "/" + count];
            List<Agglomerative.Edge> ordered = edges.Select((edge, index) => (edge, index)).OrderBy(item => item.edge.Weight).ThenBy(item => item.index).Select(item => item.edge).ToList();
            for (int position = 0; position < settings.CutCounts.Length; position++)
            {
                int k = settings.CutCounts[position];
                int[] component = ConnectedComponents(count, ordered.Take(count - k)), partition = single.CountCuts[position].Partition;
                bool match = true;
                for (int i = 0; i < count; i++) for (int j = i + 1; j < count; j++) if ((component[i] == component[j]) != (partition[i] == partition[j])) match = false;
                lines.Add("mst partition k " + k + " " + (match ? "match" : "mismatch"));
            }
            return lines;
        }
        List<string> ComparePart()
        {
            List<string> lines = ["compare linkage " + settings.CompareLinkage + " k " + classes.Length];
            foreach (string type in Distances.Types)
            {
                double[][] delta = Distances.Matrix(vectors, type);
                Tree tree = new(Agglomerative.Cluster(delta, settings.CompareLinkage), count);
                int[] partition = tree.CutInto(classes.Length);
                double coefficient = Validation.Correlation(PairValues(delta), PairValues(tree.Cophenetic()));
                lines.Add("metric " + type + " cophenetic " + Real(coefficient) + " silhouette " + Real(MeanSilhouette(partition, delta)) + " ari " + AriText(LabelAri(partition)));
            }
            return lines;
        }
        List<string> CopheneticPart()
        {
            List<string> lines = ["cophenetic_matrix", "linkage " + string.Join(" ", settings.Linkages)];
            foreach (LinkageResult first in results) lines.Add(first.Method + " " + Reals(results.Select(second => Validation.Correlation(first.Cophenetic, second.Cophenetic))));
            return lines;
        }
        List<string> AgreementPart()
        {
            List<string> lines = ["agreement k " + classes.Length, "linkage " + string.Join(" ", settings.Linkages)];
            foreach (LinkageResult first in results) lines.Add(first.Method + " " + Reals(results.Select(second => PartitionAri(first.LabelPartition, second.LabelPartition).Value)));
            return lines;
        }
        List<string> SummaryPart()
        {
            IEnumerable<LinkageResult> ranking = results.Select((result, index) => (result, index)).OrderByDescending(item => FourDigit(item.result.Correlation)).ThenBy(item => item.index).Select(item => item.result);
            List<string> lines = ["summary", "cophenetic_ranking " + string.Join(" ", ranking.Select(result => result.Method))];
            for (int position = 0; position < settings.CutCounts.Length; position++)
            {
                LinkageResult best = results[0];
                foreach (LinkageResult result in results) if (result.CountCuts[position].Ari.CompareTo(best.CountCuts[position].Ari) > 0) best = result;
                lines.Add("best_ari k " + settings.CutCounts[position] + " " + best.Method + " " + AriText(best.CountCuts[position].Ari));
            }
            foreach (LinkageResult result in results)
            {
                int best = 0;
                for (int position = 1; position < settings.CutCounts.Length; position++) if (FourDigit(result.CountCuts[position].Silhouette!.Value) > FourDigit(result.CountCuts[best].Silhouette!.Value)) best = position;
                lines.Add("best_silhouette " + result.Method + " k " + settings.CutCounts[best] + " " + Real(result.CountCuts[best].Silhouette));
            }
            lines.Add("selected " + chosen.Method + " k " + kappa);
            return lines;
        }
        List<string> ValidationReport()
        {
            List<List<string>> parts = [DataPart(), CorrelationPart(), HistogramPart()];
            foreach (LinkageResult result in results) parts.Add(LinkagePart(result));
            if (ResultOf("single") is not null) parts.Add(MstPart());
            parts.AddRange([ComparePart(), CopheneticPart(), AgreementPart(), SummaryPart()]);
            return JoinParts(parts);
        }
        double Separation(List<int> first, List<int> second)
        {
            double best = double.PositiveInfinity;
            foreach (int i in first) foreach (int j in second) best = Math.Min(best, distances[i][j]);
            return best;
        }
        List<string> ClusterLines(int g)
        {
            List<int> group = members[g];
            int size = group.Count, majorityClass = majority[g], majorityCount = table[g][majorityClass];
            double silhouette = 0.0;
            foreach (int i in group) silhouette += silhouettes[i];
            silhouette /= size;
            double[] averages = new double[featureNames.Length];
            for (int f = 0; f < averages.Length; f++) { double total = 0.0; foreach (int i in group) total += raw[i][f]; averages[f] = total / size; }
            int medoid = -1;
            double medoidSum = 0.0;
            foreach (int i in group)
            {
                double total = 0.0;
                foreach (int j in group) total += distances[i][j];
                if (medoid < 0 || total < medoidSum) { medoid = i; medoidSum = total; }
            }
            int widestFirst = -1, widestSecond = -1;
            for (int position = 0; position < group.Count; position++)
                for (int later = position + 1; later < group.Count; later++)
                {
                    int i = group[position], j = group[later];
                    if (widestFirst < 0 || distances[i][j] > distances[widestFirst][widestSecond]) { widestFirst = i; widestSecond = j; }
                }
            string diameter = widestFirst < 0 ? "0.0000 - -" : PairText(widestFirst, widestSecond);
            int nearest = -1;
            double nearestSeparation = 0.0;
            for (int h = 0; h < kappa; h++) if (h != g)
            {
                double value = Separation(group, members[h]);
                if (nearest < 0 || value < nearestSeparation) { nearest = h; nearestSeparation = value; }
            }
            return ["cluster " + (g + 1) + " size " + size + " silhouette " + Real(silhouette) + " majority " + classes[majorityClass] + " purity " + majorityCount + "/" + size + " " + Real((double)majorityCount / size),
                "  mean " + Reals(averages), "  medoid " + idents[medoid] + " diameter " + diameter + " nearest " + (nearest + 1) + " separation " + Real(nearestSeparation)];
        }
        List<string> SelectionPart()
        {
            List<string> lines = ["selected linkage " + chosen.Method + " k " + kappa + " ari " + AriText(selectedCut.Ari) + " silhouette " + Real(selectedCut.Silhouette)];
            for (int g = 0; g < kappa; g++) lines.AddRange(ClusterLines(g));
            return lines;
        }
        List<string> CentroidPart()
        {
            double[][] centers = Centroids(selected);
            List<string> lines = ["centroid_distances"];
            for (int g = 0; g < centers.Length; g++) lines.Add((g + 1) + " " + Reals(centers.Select(center => Math.Sqrt(Distances.Squared(centers[g], center)))));
            return lines;
        }
        List<string> ProfilePart()
        {
            int nameWidth = featureNames.Max(name => name.Length);
            List<string> lines = ["profile_bars"];
            for (int g = 0; g < kappa; g++)
            {
                List<int> group = members[g];
                lines.Add("cluster " + (g + 1));
                for (int f = 0; f < featureNames.Length; f++)
                {
                    double total = 0.0;
                    foreach (int i in group) total += (raw[i][f] - means[f]) / deviations[f];
                    double zeta = total / group.Count;
                    int length = Math.Min(10, (int)Math.Floor(Math.Abs(zeta) * 4));
                    string bar = new('#', length), blank = new(' ', 10);
                    string left = zeta < 0 ? new string(' ', 10 - length) + bar : blank;
                    string right = zeta < 0 ? blank : bar + new string(' ', 10 - length);
                    lines.Add(featureNames[f].PadRight(nameWidth) + " " + left + "|" + right + " " + Real(zeta));
                }
            }
            return lines;
        }
        List<string> ContingencyPart()
        {
            List<string> lines = ["contingency", "cluster " + string.Join(" ", classes) + " total"];
            int[] totals = new int[classes.Length];
            for (int g = 0; g < table.Length; g++)
            {
                int total = 0;
                for (int t = 0; t < table[g].Length; t++) { total += table[g][t]; totals[t] += table[g][t]; }
                lines.Add((g + 1) + " " + Integers(table[g]) + " " + total);
            }
            int matches = MatchCount(selected);
            lines.Add("total " + Integers(totals) + " " + count); lines.Add("purity " + matches + "/" + count + " " + Real((double)matches / count));
            return lines;
        }
        List<string> MisplacedPart()
        {
            List<string> lines = ["misplaced"];
            int misplaced = 0;
            for (int i = 0; i < count; i++) if (targets[i] != majority[selected[i] - 1])
            {
                misplaced++;
                lines.Add(idents[i] + " label " + labels[i] + " cluster " + selected[i] + " majority " + classes[majority[selected[i] - 1]]);
            }
            lines.Add("count " + misplaced);
            return lines;
        }
        List<string> WeakestPart()
        {
            List<string> lines = ["weakest"];
            foreach (int i in Enumerable.Range(0, count).OrderBy(i => silhouettes[i]).ThenBy(i => i).Take(settings.ListSize)) lines.Add(idents[i] + " label " + labels[i] + " cluster " + selected[i] + " silhouette " + Real(silhouettes[i]));
            return lines;
        }
        List<string> FeaturePart()
        {
            double[] ratios = new double[featureNames.Length];
            for (int f = 0; f < ratios.Length; f++)
            {
                double overall = 0.0;
                foreach (double[] vector in vectors) overall += vector[f];
                overall /= count;
                double[] averages = new double[kappa];
                for (int g = 0; g < kappa; g++) { double total = 0.0; foreach (int i in members[g]) total += vectors[i][f]; averages[g] = total / members[g].Count; }
                double between = 0.0;
                for (int g = 0; g < kappa; g++) { double difference = averages[g] - overall; between += members[g].Count * difference * difference; }
                double within = 0.0;
                for (int i = 0; i < count; i++) { double difference = vectors[i][f] - averages[selected[i] - 1]; within += difference * difference; }
                ratios[f] = (between / (kappa - 1)) / (within / (count - kappa));
            }
            int[] ranking = Enumerable.Range(0, ratios.Length).OrderByDescending(f => FourDigit(ratios[f])).ThenBy(f => f).ToArray();
            List<string> lines = ["features"];
            for (int rank = 0; rank < ranking.Length; rank++) { int f = ranking[rank]; lines.Add((rank + 1) + " " + featureNames[f] + " f_ratio " + Real(ratios[f])); }
            return lines;
        }
        string ClassCounts(Tree tree, int node)
        {
            int[] counts = new int[classes.Length];
            foreach (int i in tree.Members[node]) counts[targets[i]]++;
            return string.Join("/", counts);
        }
        List<string> TopMergesPart()
        {
            Tree tree = chosen.Tree;
            List<string> lines = ["top_merges"];
            for (int step = count - settings.InconsistencyCount - 1; step < count - 1; step++)
            {
                Agglomerative.Merge merge = tree.Merges[step];
                lines.Add("step " + (step + 1) + " height " + Real(merge.Height) + " a " + merge.A + " " + tree.Members[merge.A].Length + " " + ClassCounts(tree, merge.A) + " b " + merge.B + " " + tree.Members[merge.B].Length + " " + ClassCounts(tree, merge.B));
            }
            return lines;
        }
        List<string> DropFeaturePart()
        {
            List<string> lines = ["drop_feature"];
            for (int f = 0; f < featureNames.Length; f++)
            {
                double[][] reduced = vectors.Select(vector => vector.Where((_, index) => index != f).ToArray()).ToArray();
                int[] partition = new Tree(Agglomerative.Cluster(Distances.Matrix(reduced, settings.Distance), chosen.Method), count).CutInto(kappa);
                lines.Add(featureNames[f] + " ari_selected " + AriText(PartitionAri(partition, selected)) + " ari_labels " + AriText(LabelAri(partition)));
            }
            return lines;
        }
        static int NearestCenter(double[] vector, double[][] centers)
        {
            int best = 0;
            double bestValue = Distances.Squared(vector, centers[0]);
            for (int g = 1; g < centers.Length; g++) { double value = Distances.Squared(vector, centers[g]); if (value < bestValue) { best = g; bestValue = value; } }
            return best + 1;
        }
        List<string> RefinementPart()
        {
            double[][] centers = Centroids(selected);
            int[] previous = selected;
            int iterations = settings.RefineIterations;
            for (int t = 1; t <= settings.RefineIterations; t++)
            {
                int[] assignment = vectors.Select(vector => NearestCenter(vector, centers)).ToArray();
                if (assignment.SequenceEqual(previous)) { iterations = t; break; }
                List<List<int>> groups = ClusterMembers(assignment, kappa);
                for (int g = 0; g < kappa; g++) if (groups[g].Count > 0) centers[g] = Centroid(groups[g].Select(i => vectors[i]).ToArray());
                previous = assignment;
            }
            int[] refined = previous;
            int changed = Enumerable.Range(0, count).Count(i => selected[i] != refined[i]);
            int[] sizes = ClusterMembers(refined, kappa).Select(group => group.Count).ToArray();
            return ["refinement max_iterations " + settings.RefineIterations,
                "iterations " + iterations + " changed " + changed + " wss " + Real(WithinSum(selected)) + " -> " + Real(WithinSum(refined)),
                "sizes " + Integers(sizes) + " silhouette " + Real(MeanSilhouette(refined, distances)),
                "ari_selected " + AriText(PartitionAri(refined, selected)) + " ari_labels " + AriText(LabelAri(refined))];
        }
        double[] Jaccard(int[] samplePartition, int[] restricted)
        {
            int[][] counts = Validation.Contingency(restricted.Select(number => number - 1).ToArray(), samplePartition.Select(number => number - 1).ToArray(), kappa, samplePartition.Max());
            int[] columns = new int[counts[0].Length];
            foreach (int[] row in counts) for (int h = 0; h < row.Length; h++) columns[h] += row[h];
            double[] values = new double[kappa];
            for (int g = 0; g < kappa; g++)
            {
                int size = counts[g].Sum();
                if (size == 0) continue;
                long bestNumerator = 0, bestDenominator = 1;
                for (int h = 0; h < columns.Length; h++)
                {
                    long numerator = counts[g][h], denominator = size + columns[h] - numerator;
                    if (numerator * bestDenominator > bestNumerator * denominator) { bestNumerator = numerator; bestDenominator = denominator; }
                }
                values[g] = (double)bestNumerator / bestDenominator;
            }
            return values;
        }
        List<string> StabilityPart()
        {
            Minstd generator = new(settings.Seed);
            int size = count * settings.Percent / 100;
            double ariTotal = 0.0;
            double[] jaccardTotals = new double[kappa];
            List<string> lines = ["stability replicates " + settings.Replicates + " percent " + settings.Percent + " seed " + settings.Seed];
            for (int b = 1; b <= settings.Replicates; b++)
            {
                int[] array = Enumerable.Range(0, count).ToArray();
                for (int t = 0; t < size; t++) { int j = t + (int)(generator.Draw() % (count - t)); (array[t], array[j]) = (array[j], array[t]); }
                int[] sample = array[..size].Order().ToArray();
                double[][] delta = sample.Select(u => sample.Select(w => distances[u][w]).ToArray()).ToArray();
                int[] partition = new Tree(Agglomerative.Cluster(delta, chosen.Method), size).CutInto(kappa), restricted = sample.Select(u => selected[u]).ToArray();
                Fraction ari = PartitionAri(partition, restricted);
                double[] jaccard = Jaccard(partition, restricted);
                ariTotal += ari.Value;
                for (int g = 0; g < kappa; g++) jaccardTotals[g] += jaccard[g];
                lines.Add("replicate " + b + " size " + size + " ari " + AriText(ari) + " jaccard " + Reals(jaccard));
            }
            for (int g = 0; g < kappa; g++) jaccardTotals[g] /= settings.Replicates;
            lines.Add("mean_ari " + Real(ariTotal / settings.Replicates)); lines.Add("mean_jaccard " + Reals(jaccardTotals));
            return lines;
        }
        List<string> DistanceMapPart()
        {
            string frame = "+" + new string('-', count) + "+";
            List<string> lines = ["distance_map " + chosen.Method, frame];
            foreach (int u in chosen.Tree.Order)
            {
                StringBuilder row = new("|");
                foreach (int w in chosen.Tree.Order) row.Append("@%#*+=-:. "[HistogramBin(distances[u][w], distanceMax)]);
                lines.Add(row.Append('|').ToString());
            }
            lines.Add(frame);
            return lines;
        }
        List<string> ProfilesReport() => JoinParts([SelectionPart(), CentroidPart(), ProfilePart(), ContingencyPart(), MisplacedPart(), WeakestPart(), FeaturePart(), TopMergesPart(), DropFeaturePart(), RefinementPart(), StabilityPart(), DistanceMapPart()]);
        public void WriteOutputs()
        {
            Directory.CreateDirectory("output");
            Dataset.Write("linkage.csv", LinkageTable()); Dataset.Write("clusters.csv", ClustersTable()); Dataset.Write("dendrogram.txt", DendrogramReport());
            Dataset.Write("trees.txt", TreesReport()); Dataset.Write("validation.txt", ValidationReport()); Dataset.Write("profiles.txt", ProfilesReport());
        }
    }

    static void Main() => new Study(Dataset.Read()).WriteOutputs();
}
