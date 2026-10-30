using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Numerics;
using System.Text;
public static class Program {
    public static readonly string[] NJ_METHODS = { "NJ_P", "NJ_JC", "NJ_K2P" },
                                    METHODS = { "NJ_P", "NJ_JC", "NJ_K2P",
                                                "ME",   "MP",    "CONSENSUS" };
    public static Dictionary<string, List<string>> parameters = new();
    public static List<Alignment.Record> records;
    public static List<string> names = new(), sequences = new(), rejected = new();
    public static Alignment.Patterns patterns;
    public static int count, length, outgroup;
    public static string mainMethod;
    public static Dictionary<string, TreeBuilding.Tree> trees = new();
    public static Dictionary<string, Distances.Matrix> matrices = new();
    public static Dictionary<string, double[][]> patristic = new();
    public static Dictionary<string, double[]> siteLogs = new();
    public static Dictionary<string, int> njScores = new();
    public static double[][] mainMatrix;
    public static Dictionary<int, int> support = new();
    public record Bounds(int minimum, int maximum, int[] minima) {}
    public record Addition(int taxon, int mask, int score, int ties) {}
    public record Stepwise(TreeBuilding.Tree tree, int initial, int score, int evaluated,
                           List<Addition> additions, List<int> taxa) {}
    public record Move(int mask, int swap, double value) {}
    public record Hill(TreeBuilding.Tree tree, double value, int evaluated, List<Move> moves) {}
    public record SearchRecord(TreeBuilding.Tree tree, int score, double bme, string newick,
                               HashSet<int> splits) {}
    public sealed class Exhaustive {
        public List<int> taxa;
        public List<SearchRecord> records = new(), optimal = new();
        public SortedDictionary<int, int> histogram = new();
        public int bestScore, heuristic;
        public TreeBuilding.Tree strict;
        public SearchRecord bestBme;
        public double secondBme;
    }
    public static string Parameter(string key) { return parameters[key][0]; }
    public static int Integer(string key) { return int.Parse(Parameter(key)); }
    public static double RealParameter(string key) { return double.Parse(Parameter(key)); }
    public static string F(double value, int places) { return TreeIo.Real(value, places); }
    public static string Symbols(int mask) { return TreeIo.Symbols(mask, count); }
    public static string Yes(bool value) { return value ? "yes" : "no"; }
    public static double Square(double value) { return value * value; }
    public static List<int> Taxa() {
        List<int> result = new();
        for (int i = 0; i < count; i++)
            result.Add(i);
        return result;
    }
    public static double Sum(double[] values) {
        double total = 0;
        foreach (double value in values)
            total += value;
        return total;
    }
    public static int Rf(HashSet<int> a, HashSet<int> b) {
        int n = 0;
        foreach (int v in a)
            if (!b.Contains(v))
                n++;
        foreach (int v in b)
            if (!a.Contains(v))
                n++;
        return n;
    }
    public static List<int> SymbolOrder(IEnumerable<int> masks) {
        List<int> result = new(masks);
        result.Sort((a, b) => string.CompareOrdinal(Symbols(a), Symbols(b)));
        return result;
    }
    public static void Read() {
        foreach (string line in File.ReadAllLines(Path.Combine("input", "params.txt")).ToList()) {
            List<string> w = line.Split(" ").ToList();
            parameters[w[0]] = new(w.GetRange(1, w.Count - 1));
        }
        records = Alignment.Read();
        length = records[0].sequence.Length;
        HashSet<string> seen = new();
        foreach (Alignment.Record record in records) {
            string reason = null, sequence = record.sequence;
            if (!seen.Add(record.name))
                reason = "duplicate name";
            if (reason == null)
                for (int c = 0; c < sequence.Length; c++)
                    if (!Alignment.SETS.ContainsKey(sequence[c])) {
                        reason = "invalid character " + sequence[c] + " at column " + (c + 1);
                        break;
                    }
            if (reason == null && sequence.Length != length)
                reason = "length mismatch " + sequence.Length;
            if (reason == null) {
                int missing = 0;
                foreach (char c in sequence.ToCharArray())
                    if (c == '-' || c == 'N')
                        missing++;
                if (100 * missing > Integer("max_missing_percent") * length)
                    reason = "too many missing " + missing;
            }
            if (reason == null) {
                names.Add(record.name);
                sequences.Add(sequence);
            } else
                rejected.Add("REJECT line " + record.line + " " + record.name + " " + reason);
        }
        count = names.Count;
        outgroup = names.IndexOf(Parameter("outgroup"));
        mainMethod = "NJ_" + Parameter("model");
        patterns = new Alignment.Patterns(sequences);
    }
    public static List<string> Summary() {
        List<string> lines = new();
        lines.Add("INPUT records " + records.Count + " accepted " + count + " rejected " +
                  rejected.Count + " columns " + length);
        lines.AddRange(rejected);
        int[][] columns = Enumerable.Range(0, length)
                              .Select(
                                  _ => new int[4])
                              .ToArray();
        foreach (string sequence in sequences)
            for (int c = 0; c < length; c++) {
                int baseIndex = Alignment.BASES.IndexOf(sequence[c]);
                if (baseIndex >= 0)
                    columns[c][baseIndex]++;
            }
        int[] composition = new int[4];
        for (int i = 0; i < count; i++) {
            string sequence = sequences[i];
            int bases = 0, ambiguous = 0, missing = 0, unique = 0, gc = 0;
            for (int c = 0; c < length; c++) {
                char value = sequence[c];
                int baseIndex = Alignment.BASES.IndexOf(value);
                if (baseIndex >= 0) {
                    bases++;
                    composition[baseIndex]++;
                    if (baseIndex == 1 || baseIndex == 2)
                        gc++;
                    int columnTotal = 0;
                    foreach (int n in columns[c])
                        columnTotal += n;
                    if (columns[c][baseIndex] == 1 && columnTotal > 1)
                        unique++;
                } else if (Alignment.AMBIGUOUS.IndexOf(value) >= 0)
                    ambiguous++;
                else
                    missing++;
            }
            lines.Add("TAXON " + names[i] + " bases " + bases + " ambiguous " + ambiguous +
                      " missing " + missing + " unique " + unique + " gc " +
                      F(gc / (double)bases, 4));
        }
        int[] classes = Alignment.Classify(sequences);
        lines.Add("COLUMNS constant " + classes[0] + " variable " + classes[1] + " informative " +
                  classes[2] + " gapped " + classes[3] + " empty " + classes[4]);
        lines.Add("PATTERNS " + patterns.patterns.Count);
        int total = composition.Sum();
        string line = "COMPOSITION";
        for (int i = 0; i < 4; i++)
            line += " " + Alignment.BASES[i] + " " + F(composition[i] / (double)total, 4);
        lines.Add(line);
        return lines;
    }
    public static List<string> MatrixLines(double[][] matrix) {
        List<string> lines = new();
        int width = 0;
        foreach (string name in names)
            width = Math.Max(width, name.Length);
        for (int i = 0; i < count; i++) {
            StringBuilder line =
                new StringBuilder(names[i] + new string(' ', width - names[i].Length));
            for (int j = 0; j < count; j++)
                line.Append(" ").Append(F(matrix[i][j], 5));
            lines.Add(line.ToString());
        }
        return lines;
    }
    public static Bounds ComputeBounds() {
        int[] minima = new int[patterns.patterns.Count];
        int maximum = 0;
        for (int i = 0; i < minima.Length; i++) {
            int[] pattern = patterns.encoded[i];
            int minimum = 4;
            for (int mask = 1; mask < 16; mask++) {
                bool hits = true;
                foreach (int bases in pattern)
                    if ((mask & bases) == 0)
                        hits = false;
                if (hits)
                    minimum = Math.Min(minimum, BitOperations.PopCount((uint)(mask)));
            }
            minima[i] = minimum - 1;
            int greatest = count;
            for (int baseIndex = 1; baseIndex <= 8; baseIndex *= 2) {
                int absent = 0;
                foreach (int bases in pattern)
                    if ((bases & baseIndex) == 0)
                        absent++;
                greatest = Math.Min(greatest, absent);
            }
            maximum += greatest * patterns.weights[i];
        }
        int[] columns = new int[length];
        int totalMinimum = 0;
        for (int c = 0; c < length; c++) {
            columns[c] = minima[patterns.columns[c]];
            totalMinimum += columns[c];
        }
        return new Bounds(totalMinimum, maximum, columns);
    }
    public static double Bme(TreeBuilding.Tree tree) {
        List<int> taxa = tree.Taxa();
        double total = 0;
        for (int i = 0; i < taxa.Count; i++) {
            int a = taxa[i];
            double[] steps = TreeBuilding.Paths(tree, a, true);
            for (int j = i + 1; j < taxa.Count; j++) {
                int b = taxa[j];
                total += Math.ScaleB(mainMatrix[a][b], 1 - (int)steps[b]);
            }
        }
        return total;
    }
    public static Stepwise BuildStepwise(List<int> taxa) {
        TreeBuilding.Tree tree = TreeBuilding.Star(count, taxa.GetRange(0, 3 - 0));
        int initial = Parsimony.Score(tree, patterns, outgroup), score = initial, evaluated = 0;
        List<Addition> additions = new();
        for (int i = 3; i < taxa.Count; i++) {
            int taxon = taxa[i], best = int.MaxValue, mask = 0, ties = 0;
            TreeBuilding.Tree chosen = null;
            foreach (Parsimony.Branch edge in Parsimony.Branches(tree, outgroup)) {
                TreeBuilding.Tree candidate =
                    Parsimony.Insert(tree, edge.first, edge.second, taxon);
                int value = Parsimony.Score(candidate, patterns, outgroup);
                evaluated++;
                if (value < best) {
                    best = value;
                    chosen = candidate;
                    mask = edge.mask;
                    ties = 1;
                } else if (value == best)
                    ties++;
            }
            tree = chosen;
            score = best;
            additions.Add(new Addition(taxon, mask, score, ties));
        }
        return new Stepwise(tree, initial, score, evaluated, additions, taxa);
    }
    public static Hill Climb(TreeBuilding.Tree initial, Func<TreeBuilding.Tree, double> objective,
                             double value) {
        TreeBuilding.Tree tree = initial.Copy();
        List<Move> moves = new();
        int evaluated = 0;
        while (true) {
            bool moved = false;
            foreach (Parsimony.Candidate candidate in Parsimony.Nni(tree, outgroup)) {
                double result = objective(candidate.tree);
                evaluated++;
                if (result < value) {
                    tree = candidate.tree;
                    value = result;
                    moves.Add(new Move(candidate.mask, candidate.swap, value));
                    moved = true;
                    break;
                }
            }
            if (!moved)
                break;
        }
        return new Hill(tree, value, evaluated, moves);
    }
    public static TreeBuilding.Tree Consensus(List<int> taxa, HashSet<int> clades) {
        TreeBuilding.Tree tree = new TreeBuilding.Tree(count, taxa);
        int root = tree.Internal();
        SortedDictionary<int, int> nodes = new();
        List<int> masks = new(clades);
        masks.Sort();
        foreach (int mask in masks)
            nodes[mask] = tree.Internal();
        foreach (var entry in nodes) {
            int mask = entry.Key, parent = root, best = count + 1;
            foreach (var other in nodes)
                if (other.Key != mask && (other.Key & mask) == mask &&
                    BitOperations.PopCount((uint)(other.Key)) < best) {
                    parent = other.Value;
                    best = BitOperations.PopCount((uint)(other.Key));
                }
            tree.Connect(parent, entry.Value);
        }
        foreach (int taxon in taxa) {
            int parent = root, best = count + 1;
            foreach (var entry in nodes)
                if ((entry.Key & (1 << taxon)) != 0 &&
                    BitOperations.PopCount((uint)(entry.Key)) < best) {
                    parent = entry.Value;
                    best = BitOperations.PopCount((uint)(entry.Key));
                }
            tree.Connect(parent, taxon);
        }
        return tree;
    }
    public static Exhaustive SearchExhaustive(List<int> taxa) {
        Exhaustive result = new Exhaustive();
        result.taxa = taxa;
        List<TreeBuilding.Tree> trees = new();
        trees.Add(TreeBuilding.Star(count, taxa.GetRange(0, 3 - 0)));
        for (int i = 3; i < taxa.Count; i++) {
            List<TreeBuilding.Tree> expanded = new();
            foreach (TreeBuilding.Tree tree in trees)
                foreach (Parsimony.Branch edge in Parsimony.Branches(tree, outgroup))
                    expanded.Add(Parsimony.Insert(tree, edge.first, edge.second, taxa[i]));
            trees = expanded;
        }
        foreach (TreeBuilding.Tree tree in trees) {
            int score = Parsimony.Score(tree, patterns, outgroup);
            result.histogram.AddCount(score, 1);
            result.records.Add(new SearchRecord(tree, score, Bme(tree),
                                                TreeIo.Newick(tree, names, outgroup),
                                                tree.Rooted(outgroup).Splits()));
        }
        result.bestScore = result.histogram.First().Key;
        foreach (SearchRecord record in result.records)
            if (record.score == result.bestScore)
                result.optimal.Add(record);
        result.optimal.Sort((a, b) => string.CompareOrdinal(a.newick, b.newick));
        HashSet<int> common = new(result.optimal[0].splits);
        foreach (SearchRecord record in result.optimal)
            common.IntersectWith(record.splits);
        result.strict = Consensus(taxa, common);
        result.bestBme = result.records.OrderBy(record => record.bme)
                             .ThenBy(record => record.newick, StringComparer.Ordinal)
                             .First();
        result.secondBme = double.PositiveInfinity;
        foreach (SearchRecord record in result.records)
            if (record != result.bestBme)
                result.secondBme = Math.Min(result.secondBme, record.bme);
        Stepwise initial = BuildStepwise(taxa);
        result.heuristic =
            (int)Climb(initial.tree, tree => Parsimony.Score(tree, patterns, outgroup),
                       initial.score)
                .value;
        return result;
    }
    public static double[] Likelihood(TreeBuilding.Tree tree) {
        TreeBuilding.Rooted rooted = tree.Rooted(outgroup);
        List<List<int>> children = TreeIo.ChildOrder(rooted, names);
        double[][][] transition = Enumerable.Range(0, tree.nextNode)
                                      .Select(
                                          _ => Enumerable.Range(0, 4)
                                                   .Select(
                                                       _ => new double[4])
                                                   .ToArray())
                                      .ToArray();
        foreach (int node in rooted.order)
            if (node != rooted.root) {
                double branch = tree.adjacent[node][rooted.parents[node]],
                       e = Math.Exp(-4 * branch / 3);
                for (int a = 0; a < 4; a++)
                    for (int b = 0; b < 4; b++)
                        transition[node][a][b] = a == b ? 0.25 + 0.75 * e : 0.25 - 0.25 * e;
            }
        double[] values = new double[patterns.patterns.Count];
        for (int p = 0; p < values.Length; p++) {
            int[] pattern = patterns.encoded[p];
            double[][] partial = Enumerable.Range(0, tree.nextNode)
                                     .Select(
                                         _ => new double[4])
                                     .ToArray(),
                       upward = Enumerable.Range(0, tree.nextNode)
                                    .Select(
                                        _ => new double[4])
                                    .ToArray();
            for (int i = rooted.order.Count - 1; i >= 0; i--) {
                int node = rooted.order[i];
                if (node < tree.size) {
                    for (int a = 0; a < 4; a++)
                        partial[node][a] = (pattern[node] & (1 << a)) != 0 ? 1 : 0;
                } else {
                    Array.Fill(partial[node], 1);
                    foreach (int child in children[node])
                        for (int a = 0; a < 4; a++)
                            partial[node][a] *= upward[child][a];
                }
                if (node != rooted.root)
                    for (int a = 0; a < 4; a++)
                        for (int b = 0; b < 4; b++)
                            upward[node][a] += transition[node][a][b] * partial[node][b];
            }
            double probability = 0;
            foreach (double value in partial[rooted.root])
                probability += 0.25 * value;
            values[p] = Math.Log(probability);
        }
        double[] sites = new double[length];
        for (int c = 0; c < length; c++)
            sites[c] = values[patterns.columns[c]];
        return sites;
    }
    public static List<string> LikelihoodLines() {
        List<string> lines = new();
        lines.Add("LIKELIHOOD columns " + length + " patterns " + patterns.patterns.Count);
        foreach (string method in NJ_METHODS) {
            double total = Sum(siteLogs[method]);
            lines.Add("TREE " + method + " loglik " + F(total, 4) + " per_site " +
                      F(total / length, 4));
        }
        for (int i = 0; i < 3; i++)
            for (int j = i + 1; j < 3; j++) {
                string a = NJ_METHODS[i], b = NJ_METHODS[j];
                double[] deltas = new double[length];
                for (int c = 0; c < length; c++)
                    deltas[c] = siteLogs[a][c] - siteLogs[b][c];
                double difference = Sum(deltas), mean = difference / length, ss = 0;
                foreach (double delta in deltas)
                    ss += Square(delta - mean);
                double se = Math.Sqrt(length / (double)(length - 1) * ss);
                lines.Add("KH " + a + " " + b + " difference " + F(difference, 4) + " se " +
                          F(se, 4) + " z " + F(difference / se, 4));
            }
        List<int> columns = new();
        for (int c = 0; c < length; c++)
            columns.Add(c);
        columns.Sort((a, b) => {
            int order = double.Parse(F(siteLogs[mainMethod][a], 4))
                            .CompareTo(double.Parse(F(siteLogs[mainMethod][b], 4)));
            return order != 0 ? order : a.CompareTo(b);
        });
        int[] changes = Parsimony.PatternScores(trees[mainMethod], patterns, outgroup);
        int low = Integer("low_sites");
        lines.Add("LOWEST " + mainMethod + " sites " + low);
        for (int i = 0; i < low; i++) {
            int c = columns[i], p = patterns.columns[c];
            lines.Add("SITE " + (c + 1) + " loglik " + F(siteLogs[mainMethod][c], 4) + " changes " +
                      changes[p] + " pattern " + patterns.patterns[p]);
        }
        return lines;
    }
    public static List<string> Bootstrap() {
        List<string> lines = new();
        int replicates = Integer("replicates");
        long state = long.Parse(Parameter("seed"));
        HashSet<int> mainSplits = trees[mainMethod].Rooted(outgroup).Splits();
        lines.Add("BOOTSTRAP model " + Parameter("model") + " replicates " + replicates + " seed " +
                  state);
        int identical = 0;
        for (int b = 1; b <= replicates; b++) {
            int[] weights = new int[length];
            for (int i = 0; i < length; i++) {
                state = 48271 * state % 2147483647;
                weights[(int)(state % length)]++;
            }
            double[][] matrix =
                Distances
                    .BuildMatrix(Distances.Pairs(sequences, weights), count, Parameter("model"),
                                 RealParameter("saturation_distance"))
                    .values;
            TreeBuilding.Tree tree = TreeBuilding.Nj(matrix, Taxa());
            HashSet<int> splits = tree.Rooted(outgroup).Splits();
            foreach (int mask in splits)
                support.AddCount(mask, 1);
            int difference = Rf(splits, mainSplits), distinct = 0;
            foreach (int weight in weights)
                if (weight > 0)
                    distinct++;
            if (difference == 0)
                identical++;
            lines.Add("REPLICATE " + b + " distinct " + distinct + " rf " + difference);
        }
        lines.Add("IDENTICAL " + identical);
        foreach (int mask in SymbolOrder(mainSplits))
            lines.Add("SUPPORT " + Symbols(mask) + " " + support.GetValueOrDefault(mask, 0));
        List<int> orderedSplits = new(support.Keys);
        orderedSplits.Sort((a, b) => {
            int order = support[b].CompareTo(support[a]);
            return order != 0 ? order : string.CompareOrdinal(Symbols(a), Symbols(b));
        });
        HashSet<int> majority = new();
        foreach (int mask in orderedSplits) {
            lines.Add("SPLIT " + Symbols(mask) + " " + support[mask]);
            if (2 * support[mask] > replicates)
                majority.Add(mask);
        }
        TreeBuilding.Tree consensus = Consensus(Taxa(), majority);
        trees["CONSENSUS"] = consensus;
        lines.Add("CONSENSUS " + TreeIo.Newick(consensus, names, outgroup, false, support));
        for (int taxon = 0; taxon < count; taxon++)
            if (taxon != outgroup) {
                List<int> taxa = Taxa();
                taxa.Remove(taxon);
                TreeBuilding.Tree tree = TreeBuilding.Nj(mainMatrix, taxa);
                HashSet<int> reduced = new();
                foreach (int mask in mainSplits) {
                    int next = mask & ~(1 << taxon), size = BitOperations.PopCount((uint)(next));
                    if (size >= 2 && size <= count - 3)
                        reduced.Add(next);
                }
                lines.Add("JACKKNIFE " + names[taxon] + " rf " +
                          Rf(tree.Rooted(outgroup).Splits(), reduced));
            }
        return lines;
    }
    public static List<string> Clock() {
        List<string> pairs = new();
        int rejected = 0;
        List<int> ingroup = Taxa();
        ingroup.Remove(outgroup);
        for (int i = 0; i < ingroup.Count; i++)
            for (int j = i + 1; j < ingroup.Count; j++) {
                int a = ingroup[i], b = ingroup[j], m1 = 0, m2 = 0;
                for (int c = 0; c < length; c++) {
                    char x = sequences[a][c], y = sequences[b][c], o = sequences[outgroup][c];
                    if (Alignment.BASES.IndexOf(x) >= 0 && Alignment.BASES.IndexOf(y) >= 0 &&
                        Alignment.BASES.IndexOf(o) >= 0 && x != y) {
                        if (y == o)
                            m1++;
                        if (x == o)
                            m2++;
                    }
                }
                int difference = m1 - m2, total = m1 + m2;
                bool reject = 1000 * difference * difference > 3841 * total;
                if (reject)
                    rejected++;
                pairs.Add("RRT " + names[a] + " " + names[b] + " m1 " + m1 + " m2 " + m2 +
                          " chi2 " +
                          (total == 0 ? "-" : F(difference * (double)difference / total, 4)) + " " +
                          (reject ? "reject" : "ok"));
            }
        List<string> lines = new();
        lines.Add("RELATIVE_RATE outgroup " + names[outgroup] + " pairs " + pairs.Count +
                  " rejected " + rejected);
        lines.AddRange(pairs);
        TreeBuilding.Tree tree = trees[mainMethod];
        double[] paths = TreeBuilding.Paths(tree, tree.Rooted(outgroup).root, false);
        double mean = 0, ss = 0;
        foreach (int t in ingroup)
            mean += paths[t];
        mean /= ingroup.Count;
        foreach (int t in ingroup)
            ss += Square(paths[t] - mean);
        double sd = Math.Sqrt(ss / (ingroup.Count - 1));
        lines.Add("ROOT_TO_TIP " + mainMethod + " mean " + F(mean, 5) + " sd " + F(sd, 5) + " cv " +
                  F(sd / mean, 4));
        foreach (int t in ingroup)
            lines.Add("TIP " + names[t] + " " + F(paths[t], 5));
        return lines;
    }
    public static int[] Quartets(HashSet<int> splits) {
        List<int> values = new();
        for (int a = 0; a < count; a++)
            for (int b = a + 1; b < count; b++)
                for (int c = b + 1; c < count; c++)
                    for (int d = c + 1; d < count; d++) {
                        int quartet = (1 << a) | (1 << b) | (1 << c) | (1 << d), topology = 0;
                        int[] others = { b, c, d };
                        for (int i = 0; i < 3 && topology == 0; i++) {
                            int side = (1 << a) | (1 << others[i]);
                            foreach (int mask in splits) {
                                int part = mask & quartet;
                                if (part == side || part == (quartet ^ side)) {
                                    topology = i + 1;
                                    break;
                                }
                            }
                        }
                        values.Add(topology);
                    }
        return values.ToArray();
    }
    public static List<string> Comparison(Hill mp, Parsimony.Reconstruction reconstruction) {
        Dictionary<string, HashSet<int>> splits = new();
        foreach (string method in METHODS)
            splits[method] = trees[method].Rooted(outgroup).Splits();
        List<string> lines = new();
        int replicates = Integer("replicates");
        foreach (string method in METHODS) {
            TreeBuilding.Tree tree = trees[method];
            int supported = 0;
            foreach (int mask in splits[method])
                if (2 * support.GetValueOrDefault(mask, 0) > replicates)
                    supported++;
            string score = "-", bme = "-", length = "-", negative = "-", residual = "-",
                   likelihood = "-";
            if (!method.Equals("CONSENSUS")) {
                score = Convert.ToString(method.Equals("MP") ? (int)mp.value
                                         : method.Equals("ME")
                                             ? Parsimony.Score(tree, patterns, outgroup)
                                             : njScores[method]);
                bme = F(Bme(tree), 5);
            }
            if (method.StartsWith("NJ_")) {
                double total = 0, ss = 0;
                foreach (Parsimony.Branch edge in Parsimony.Branches(tree, outgroup))
                    total += tree.adjacent[edge.first][edge.second];
                length = F(total, 5);
                negative = Convert.ToString(tree.negative);
                double[][] matrix = matrices[method.Substring(3)].values, paths = patristic[method];
                for (int i = 0; i < count; i++)
                    for (int j = i + 1; j < count; j++)
                        ss += Square(matrix[i][j] - paths[i][j]);
                residual = F(ss, 6);
                likelihood = F(Sum(siteLogs[method]), 4);
            } else if (method.Equals("MP"))
                length = F(mp.value / Program.length, 5);
            lines.Add("TREE " + method + " splits " + splits[method].Count + " supported " +
                      supported + " parsimony " + score + " bme " + bme + " length " + length +
                      " negative " + negative + " sse " + residual + " loglik " + likelihood);
        }
        lines.Add("RF " + string.Join(" ", METHODS));
        foreach (string a in METHODS) {
            string line = a;
            foreach (string b in METHODS)
                line += " " + Rf(splits[a], splits[b]);
            lines.Add(line);
        }
        Dictionary<string, int[]> quartets = new();
        foreach (string method in METHODS)
            quartets[method] = Quartets(splits[method]);
        lines.Add("QUARTET " + string.Join(" ", METHODS));
        foreach (string a in METHODS) {
            string line = a;
            foreach (string b in METHODS) {
                int difference = 0;
                int[] first = quartets[a], second = quartets[b];
                for (int i = 0; i < first.Length; i++)
                    if (first[i] != second[i])
                        difference++;
                line += " " + difference;
            }
            lines.Add(line);
        }
        HashSet<int> all = new();
        foreach (HashSet<int> set in splits.values)
            all.AddRange(set);
        Dictionary<int, Double> lengths = trees[mainMethod].Rooted(outgroup).BranchLengths();
        Dictionary<int, int> changes = new();
        foreach (Parsimony.Branch edge in Parsimony.Branches(trees["MP"], outgroup))
            changes[edge.mask] =
                reconstruction.branchChanges[Parsimony.Ends.Of(edge.first, edge.second)];
        foreach (int mask in SymbolOrder(all)) {
            string marks = "";
            foreach (string method in METHODS)
                marks += splits[method].Contains(mask) ? "+" : "-";
            lines.Add("CLADE " + Symbols(mask) + " support " + support.GetValueOrDefault(mask, 0) +
                      " trees " + marks + " length " +
                      (lengths.ContainsKey(mask) ? F(lengths[mask], 5) : "-") + " changes " +
                      (changes.ContainsKey(mask) ? changes[mask] : "-"));
        }
        return lines;
    }
    public static List<string> Hypotheses(Exhaustive exhaustive) {
        Dictionary<string, int> numbers = new();
        for (int i = 0; i < count; i++)
            numbers[names[i]] = i;
        int ingroup = ((1 << count) - 1) ^ (1 << outgroup), exhaustiveIngroup = 0;
        foreach (int t in exhaustive.taxa)
            if (t != outgroup)
                exhaustiveIngroup |= 1 << t;
        Dictionary<string, HashSet<int>> splits = new();
        foreach (string method in METHODS)
            splits[method] = trees[method].Rooted(outgroup).Splits();
        List<string> lines = new();
        foreach (string line in File.ReadAllLines(Path.Combine("input", "clades.txt")).ToList()) {
            string[] w = line.Split(" ");
            string hypothesis = w[0], unknown = null;
            int mask = 0;
            for (int i = 1; i < w.Length; i++)
                if (!numbers.ContainsKey(w[i])) {
                    unknown = w[i];
                    break;
                }
            if (unknown != null) {
                lines.Add("INVALID " + hypothesis + " unknown taxon " + unknown);
                continue;
            }
            for (int i = 1; i < w.Length; i++)
                mask |= 1 << numbers[w[i]];
            if ((mask & (1 << outgroup)) != 0) {
                lines.Add("INVALID " + hypothesis + " contains outgroup");
                continue;
            }
            lines.Add("CLADE " + hypothesis + " taxa " + BitOperations.PopCount((uint)(mask)) +
                      " support " + support.GetValueOrDefault(mask, 0));
            foreach (string method in METHODS) {
                int common = ingroup;
                foreach (int clade in splits[method])
                    if ((clade & mask) == mask && BitOperations.PopCount((uint)(clade)) <
                                                      BitOperations.PopCount((uint)(common)))
                        common = clade;
                List<string> intruders = new();
                for (int t = 0; t < count; t++)
                    if ((common & ~mask & (1 << t)) != 0)
                        intruders.Add(names[t]);
                lines.Add("TEST " + hypothesis + " " + method + " monophyletic " +
                          Yes(common == mask) + " mrca " + BitOperations.PopCount((uint)(common)) +
                          " intruders " +
                          (intruders.Count == 0 ? "-" : string.Join(",", intruders)));
            }
            int subset = mask & exhaustiveIngroup, size = BitOperations.PopCount((uint)(subset));
            if (size < 2 || size >= BitOperations.PopCount((uint)(exhaustiveIngroup))) {
                lines.Add("SUBSET " + hypothesis + " untestable");
                continue;
            }
            int with = int.MaxValue, without = int.MaxValue;
            double withBme = double.PositiveInfinity, withoutBme = double.PositiveInfinity;
            foreach (SearchRecord record in exhaustive.records)
                if (record.splits.Contains(subset)) {
                    with = Math.Min(with, record.score);
                    withBme = Math.Min(withBme, record.bme);
                } else {
                    without = Math.Min(without, record.score);
                    withoutBme = Math.Min(withoutBme, record.bme);
                }
            lines.Add("SUBSET " + hypothesis + " taxa " + size + " with " + with + " without " +
                      without + " bme_with " + F(withBme, 5) + " bme_without " + F(withoutBme, 5));
        }
        return lines;
    }
    public static List<string> DistanceLines(List<Distances.Pair> pairs, double start, Hill me,
                                             Exhaustive exhaustive) {
        List<string> lines = new();
        int n = 0, s = 0, v = 0;
        foreach (Distances.Pair pair in pairs) {
            lines.Add("PAIR " + names[pair.first] + " " + names[pair.second] + " sites " +
                      pair.sites + " transitions " + pair.transitions + " transversions " +
                      pair.transversions);
            n += pair.sites;
            s += pair.transitions;
            v += pair.transversions;
        }
        lines.Add("TOTAL sites " + n + " transitions " + s + " transversions " + v);
        foreach (string model in Distances.MODELS) {
            lines.Add("");
            lines.Add("MODEL " + model);
            lines.AddRange(MatrixLines(matrices[model].values));
            foreach (Distances.Pair pair in matrices[model].saturated)
                lines.Add("SATURATED " + names[pair.first] + " " + names[pair.second] + " sites " +
                          pair.sites);
        }
        lines.Add("");
        lines.Add("PATRISTIC " + mainMethod);
        lines.AddRange(MatrixLines(patristic[mainMethod]));
        lines.Add("");
        lines.Add("ME start " + mainMethod + " length " + F(start, 5));
        foreach (Move move in me.moves)
            lines.Add("NNI edge " + Symbols(move.mask) + " swap " + move.swap + " length " +
                      F(move.value, 5));
        lines.Add("ME moves " + me.moves.Count + " evaluated " + me.evaluated + " length " +
                  F(me.value, 5));
        lines.Add("EXHAUSTIVE taxa " + exhaustive.taxa.Count + " trees " +
                  exhaustive.records.Count + " best " + F(exhaustive.bestBme.bme, 5) + " second " +
                  F(exhaustive.secondBme, 5));
        lines.Add("BEST " + exhaustive.bestBme.newick + " parsimony " + exhaustive.bestBme.score);
        return lines;
    }
    public static string ScoreLine(string method, int score, Bounds bounds) {
        return "TREE " + method + " score " + score + " ci " +
               F(bounds.minimum / (double)score, 4) + " ri " +
               F((bounds.maximum - score) / (double)(bounds.maximum - bounds.minimum), 4);
    }
    public static List<string> ParsimonyLines(Bounds bounds, Stepwise initial, Hill search,
                                              Parsimony.Reconstruction reconstruction,
                                              Exhaustive exhaustive) {
        List<string> lines = new();
        lines.Add("BOUNDS minimum " + bounds.minimum + " maximum " + bounds.maximum);
        foreach (string method in NJ_METHODS)
            lines.Add(ScoreLine(method, njScores[method], bounds));
        List<string> start = new();
        foreach (int t in initial.taxa.GetRange(0, 3 - 0))
            start.Add(names[t]);
        lines.Add("START " + string.Join(" ", start) + " score " + initial.initial);
        foreach (Addition a in initial.additions)
            lines.Add("ADD " + names[a.taxon] + " edge " + Symbols(a.mask) + " score " + a.score +
                      " ties " + a.ties);
        lines.Add("STEPWISE score " + initial.score + " evaluated " + initial.evaluated);
        foreach (Move move in search.moves)
            lines.Add("NNI edge " + Symbols(move.mask) + " swap " + move.swap + " score " +
                      (int)move.value);
        int score = (int)search.value;
        lines.Add("SEARCH moves " + search.moves.Count + " evaluated " + search.evaluated +
                  " score " + score);
        lines.Add(ScoreLine("MP", score, bounds));
        lines.Add("MP " + TreeIo.Newick(search.tree, names, outgroup, true, null));
        int[] changes = reconstruction.siteChanges;
        int maximum = changes.Max(), homoplasy = 0;
        int[] histogram = new int[maximum + 1];
        for (int c = 0; c < length; c++) {
            histogram[changes[c]]++;
            if (changes[c] > bounds.minima[c])
                homoplasy++;
        }
        for (int k = 0; k <= maximum; k++)
            lines.Add("CHANGES " + k + " columns " + histogram[k]);
        lines.Add("HOMOPLASY columns " + homoplasy + " extra " + (score - bounds.minimum));
        TreeBuilding.Rooted rooted = search.tree.Rooted(outgroup);
        SortedDictionary<string, string> ancestors = new(StringComparer.Ordinal);
        foreach (var entry in reconstruction.ancestors)
            ancestors[Symbols(entry.Key == rooted.root ? rooted.ingroup
                                                       : rooted.masks[entry.Key])] = entry.Value;
        foreach (var entry in ancestors)
            lines.Add("ANCESTOR " + entry.Key + " " + entry.Value);
        lines.Add("");
        lines.Add("EXHAUSTIVE taxa " + exhaustive.taxa.Count + " trees " +
                  exhaustive.records.Count + " best " + exhaustive.bestScore + " optimal " +
                  exhaustive.optimal.Count);
        foreach (var entry in exhaustive.histogram)
            lines.Add("SCORE " + entry.Key + " trees " + entry.Value);
        foreach (SearchRecord record in exhaustive.optimal)
            lines.Add("OPTIMAL " + record.newick + " bme " + F(record.bme, 5));
        lines.Add("STRICT " + TreeIo.Newick(exhaustive.strict, names, outgroup));
        lines.Add("HEURISTIC score " + exhaustive.heuristic + " optimal " +
                  Yes(exhaustive.heuristic == exhaustive.bestScore));
        return lines;
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Read();
        int[] weights = new int[length];
        Array.Fill(weights, 1);
        List<Distances.Pair> pairs = Distances.Pairs(sequences, weights);
        for (int i = 0; i < 3; i++) {
            string model = Distances.MODELS[i], method = NJ_METHODS[i];
            Distances.Matrix matrix =
                Distances.BuildMatrix(pairs, count, model, RealParameter("saturation_distance"));
            matrices[model] = matrix;
            trees[method] = TreeBuilding.Nj(matrix.values, Taxa());
        }
        mainMatrix = matrices[Parameter("model")].values;
        double start = Bme(trees[mainMethod]);
        Hill me = Climb(trees[mainMethod], Bme, start);
        List<int> order = Taxa();
        order.Remove(outgroup);
        order.Insert(0, outgroup);
        Stepwise initial = BuildStepwise(order);
        Hill mp =
            Climb(initial.tree, tree => Parsimony.Score(tree, patterns, outgroup), initial.score);
        Parsimony.Reconstruction reconstruction =
            Parsimony.Reconstruct(mp.tree, patterns, outgroup);
        foreach (var entry in reconstruction.branchChanges)
            mp.tree.Connect(entry.Key.first, entry.Key.second, entry.Value / (double)length);
        Bounds bounds = ComputeBounds();
        foreach (string method in NJ_METHODS)
            njScores[method] = Parsimony.Score(trees[method], patterns, outgroup);
        HashSet<string> exhaustiveNames = new(parameters["exhaustive_taxa"]);
        List<int> exhaustiveTaxa = new();
        exhaustiveTaxa.Add(outgroup);
        for (int t = 0; t < count; t++)
            if (t != outgroup && exhaustiveNames.Contains(names[t]))
                exhaustiveTaxa.Add(t);
        Exhaustive exhaustive = SearchExhaustive(exhaustiveTaxa);
        foreach (string method in NJ_METHODS) {
            siteLogs[method] = Likelihood(trees[method]);
            patristic[method] = TreeBuilding.Patristic(trees[method]);
        }
        trees["ME"] = me.tree;
        trees["MP"] = mp.tree;
        List<string> bootstrap = Bootstrap(), newicks = new(), diagrams = new();
        foreach (string method in METHODS) {
            TreeBuilding.Tree tree = trees[method];
            bool lengths = method.StartsWith("NJ_") || method.Equals("MP");
            newicks.Add(method + " " +
                        TreeIo.Newick(tree, names, outgroup, lengths,
                                      method.Equals("CONSENSUS") ? support : null));
            if (diagrams.Count != 0)
                diagrams.Add("");
            diagrams.Add("TREE " + method);
            diagrams.AddRange(TreeIo.Cladogram(tree, names, outgroup, support));
        }
        TreeIo.Write("summary.txt", Summary());
        TreeIo.Write("distances.txt", DistanceLines(pairs, start, me, exhaustive));
        TreeIo.Write("trees.nwk", newicks);
        TreeIo.Write("cladograms.txt", diagrams);
        TreeIo.Write("parsimony.txt",
                     ParsimonyLines(bounds, initial, mp, reconstruction, exhaustive));
        TreeIo.Write("likelihood.txt", LikelihoodLines());
        TreeIo.Write("bootstrap.txt", bootstrap);
        TreeIo.Write("clock.txt", Clock());
        TreeIo.Write("comparison.txt", Comparison(mp, reconstruction));
        TreeIo.Write("hypotheses.txt", Hypotheses(exhaustive));
    }
}
