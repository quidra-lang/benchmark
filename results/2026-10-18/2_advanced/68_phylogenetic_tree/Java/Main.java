import java.nio.file.*;
import java.util.*;
import java.util.function.ToDoubleFunction;
public class Main {
    static final String[] NJ_METHODS = {"NJ_P", "NJ_JC", "NJ_K2P"},
                          METHODS = {"NJ_P", "NJ_JC", "NJ_K2P", "ME", "MP", "CONSENSUS"};
    static Map<String, List<String>> parameters = new HashMap<>();
    static List<Alignment.Record> records;
    static List<String> names = new ArrayList<>(), sequences = new ArrayList<>(),
                        rejected = new ArrayList<>();
    static Alignment.Patterns patterns;
    static int count, length, outgroup;
    static String mainMethod;
    static Map<String, TreeBuilding.Tree> trees = new LinkedHashMap<>();
    static Map<String, Distances.Matrix> matrices = new LinkedHashMap<>();
    static Map<String, double[][]> patristic = new HashMap<>();
    static Map<String, double[]> siteLogs = new HashMap<>();
    static Map<String, Integer> njScores = new HashMap<>();
    static double[][] mainMatrix;
    static Map<Integer, Integer> support = new HashMap<>();
    record Bounds(int minimum, int maximum, int[] minima) {}
    record Addition(int taxon, int mask, int score, int ties) {}
    record Stepwise(TreeBuilding.Tree tree, int initial, int score, int evaluated,
                    List<Addition> additions, List<Integer> taxa) {}
    record Move(int mask, int swap, double value) {}
    record Hill(TreeBuilding.Tree tree, double value, int evaluated, List<Move> moves) {}
    record SearchRecord(TreeBuilding.Tree tree, int score, double bme, String newick,
                        Set<Integer> splits) {}
    static final class Exhaustive {
        List<Integer> taxa;
        List<SearchRecord> records = new ArrayList<>(), optimal = new ArrayList<>();
        TreeMap<Integer, Integer> histogram = new TreeMap<>();
        int bestScore, heuristic;
        TreeBuilding.Tree strict;
        SearchRecord bestBme;
        double secondBme;
    }
    static String parameter(String key) { return parameters.get(key).getFirst(); }
    static int integer(String key) { return Integer.parseInt(parameter(key)); }
    static double realParameter(String key) { return Double.parseDouble(parameter(key)); }
    static String f(double value, int places) { return TreeIo.real(value, places); }
    static String symbols(int mask) { return TreeIo.symbols(mask, count); }
    static String yes(boolean value) { return value ? "yes" : "no"; }
    static double square(double value) { return value * value; }
    static List<Integer> taxa() {
        List<Integer> result = new ArrayList<>();
        for (int i = 0; i < count; i++)
            result.add(i);
        return result;
    }
    static double sum(double[] values) {
        double total = 0;
        for (double value : values)
            total += value;
        return total;
    }
    static int rf(Set<Integer> a, Set<Integer> b) {
        int n = 0;
        for (int v : a)
            if (!b.contains(v))
                n++;
        for (int v : b)
            if (!a.contains(v))
                n++;
        return n;
    }
    static List<Integer> symbolOrder(Collection<Integer> masks) {
        List<Integer> result = new ArrayList<>(masks);
        result.sort(Comparator.comparing(Main::symbols));
        return result;
    }
    static void read() throws Exception {
        for (String line : Files.readAllLines(Path.of("input", "params.txt"))) {
            List<String> w = Arrays.asList(line.split(" "));
            parameters.put(w.getFirst(), new ArrayList<>(w.subList(1, w.size())));
        }
        records = Alignment.read();
        length = records.getFirst().sequence().length();
        Set<String> seen = new HashSet<>();
        for (Alignment.Record record : records) {
            String reason = null, sequence = record.sequence();
            if (!seen.add(record.name()))
                reason = "duplicate name";
            if (reason == null)
                for (int c = 0; c < sequence.length(); c++)
                    if (!Alignment.SETS.containsKey(sequence.charAt(c))) {
                        reason =
                            "invalid character " + sequence.charAt(c) + " at column " + (c + 1);
                        break;
                    }
            if (reason == null && sequence.length() != length)
                reason = "length mismatch " + sequence.length();
            if (reason == null) {
                int missing = 0;
                for (char c : sequence.toCharArray())
                    if (c == '-' || c == 'N')
                        missing++;
                if (100 * missing > integer("max_missing_percent") * length)
                    reason = "too many missing " + missing;
            }
            if (reason == null) {
                names.add(record.name());
                sequences.add(sequence);
            } else
                rejected.add("REJECT line " + record.line() + " " + record.name() + " " + reason);
        }
        count = names.size();
        outgroup = names.indexOf(parameter("outgroup"));
        mainMethod = "NJ_" + parameter("model");
        patterns = new Alignment.Patterns(sequences);
    }
    static List<String> summary() {
        List<String> lines = new ArrayList<>();
        lines.add("INPUT records " + records.size() + " accepted " + count + " rejected " +
                  rejected.size() + " columns " + length);
        lines.addAll(rejected);
        int[][] columns = new int[length][4];
        for (String sequence : sequences)
            for (int c = 0; c < length; c++) {
                int base = Alignment.BASES.indexOf(sequence.charAt(c));
                if (base >= 0)
                    columns[c][base]++;
            }
        int[] composition = new int[4];
        for (int i = 0; i < count; i++) {
            String sequence = sequences.get(i);
            int bases = 0, ambiguous = 0, missing = 0, unique = 0, gc = 0;
            for (int c = 0; c < length; c++) {
                char value = sequence.charAt(c);
                int base = Alignment.BASES.indexOf(value);
                if (base >= 0) {
                    bases++;
                    composition[base]++;
                    if (base == 1 || base == 2)
                        gc++;
                    int total = 0;
                    for (int n : columns[c])
                        total += n;
                    if (columns[c][base] == 1 && total > 1)
                        unique++;
                } else if (Alignment.AMBIGUOUS.indexOf(value) >= 0)
                    ambiguous++;
                else
                    missing++;
            }
            lines.add("TAXON " + names.get(i) + " bases " + bases + " ambiguous " + ambiguous +
                      " missing " + missing + " unique " + unique + " gc " +
                      f(gc / (double)bases, 4));
        }
        int[] classes = Alignment.classify(sequences);
        lines.add("COLUMNS constant " + classes[0] + " variable " + classes[1] + " informative " +
                  classes[2] + " gapped " + classes[3] + " empty " + classes[4]);
        lines.add("PATTERNS " + patterns.patterns.size());
        int total = Arrays.stream(composition).sum();
        String line = "COMPOSITION";
        for (int i = 0; i < 4; i++)
            line += " " + Alignment.BASES.charAt(i) + " " + f(composition[i] / (double)total, 4);
        lines.add(line);
        return lines;
    }
    static List<String> matrixLines(double[][] matrix) {
        List<String> lines = new ArrayList<>();
        int width = 0;
        for (String name : names)
            width = Math.max(width, name.length());
        for (int i = 0; i < count; i++) {
            StringBuilder line =
                new StringBuilder(names.get(i) + " ".repeat(width - names.get(i).length()));
            for (int j = 0; j < count; j++)
                line.append(" ").append(f(matrix[i][j], 5));
            lines.add(line.toString());
        }
        return lines;
    }
    static Bounds bounds() {
        int[] minima = new int[patterns.patterns.size()];
        int maximum = 0;
        for (int i = 0; i < minima.length; i++) {
            int[] pattern = patterns.encoded.get(i);
            int minimum = 4;
            for (int mask = 1; mask < 16; mask++) {
                boolean hits = true;
                for (int bases : pattern)
                    if ((mask & bases) == 0)
                        hits = false;
                if (hits)
                    minimum = Math.min(minimum, Integer.bitCount(mask));
            }
            minima[i] = minimum - 1;
            int greatest = count;
            for (int base = 1; base <= 8; base *= 2) {
                int absent = 0;
                for (int bases : pattern)
                    if ((bases & base) == 0)
                        absent++;
                greatest = Math.min(greatest, absent);
            }
            maximum += greatest * patterns.weights.get(i);
        }
        int[] columns = new int[length];
        int minimum = 0;
        for (int c = 0; c < length; c++) {
            columns[c] = minima[patterns.columns[c]];
            minimum += columns[c];
        }
        return new Bounds(minimum, maximum, columns);
    }
    static double bme(TreeBuilding.Tree tree) {
        List<Integer> taxa = tree.taxa();
        double total = 0;
        for (int i = 0; i < taxa.size(); i++) {
            int a = taxa.get(i);
            double[] steps = TreeBuilding.paths(tree, a, true);
            for (int j = i + 1; j < taxa.size(); j++) {
                int b = taxa.get(j);
                total += Math.scalb(mainMatrix[a][b], 1 - (int)steps[b]);
            }
        }
        return total;
    }
    static Stepwise stepwise(List<Integer> taxa) {
        TreeBuilding.Tree tree = TreeBuilding.star(count, taxa.subList(0, 3));
        int initial = Parsimony.score(tree, patterns, outgroup), score = initial, evaluated = 0;
        List<Addition> additions = new ArrayList<>();
        for (int i = 3; i < taxa.size(); i++) {
            int taxon = taxa.get(i), best = Integer.MAX_VALUE, mask = 0, ties = 0;
            TreeBuilding.Tree chosen = null;
            for (Parsimony.Branch edge : Parsimony.branches(tree, outgroup)) {
                TreeBuilding.Tree candidate =
                    Parsimony.insert(tree, edge.first(), edge.second(), taxon);
                int value = Parsimony.score(candidate, patterns, outgroup);
                evaluated++;
                if (value < best) {
                    best = value;
                    chosen = candidate;
                    mask = edge.mask();
                    ties = 1;
                } else if (value == best)
                    ties++;
            }
            tree = chosen;
            score = best;
            additions.add(new Addition(taxon, mask, score, ties));
        }
        return new Stepwise(tree, initial, score, evaluated, additions, taxa);
    }
    static Hill hill(TreeBuilding.Tree initial, ToDoubleFunction<TreeBuilding.Tree> objective,
                     double value) {
        TreeBuilding.Tree tree = initial.copy();
        List<Move> moves = new ArrayList<>();
        int evaluated = 0;
        while (true) {
            boolean moved = false;
            for (Parsimony.Candidate candidate : Parsimony.nni(tree, outgroup)) {
                double result = objective.applyAsDouble(candidate.tree());
                evaluated++;
                if (result < value) {
                    tree = candidate.tree();
                    value = result;
                    moves.add(new Move(candidate.mask(), candidate.swap(), value));
                    moved = true;
                    break;
                }
            }
            if (!moved)
                break;
        }
        return new Hill(tree, value, evaluated, moves);
    }
    static TreeBuilding.Tree consensus(List<Integer> taxa, Set<Integer> clades) {
        TreeBuilding.Tree tree = new TreeBuilding.Tree(count, taxa);
        int root = tree.internal();
        TreeMap<Integer, Integer> nodes = new TreeMap<>();
        List<Integer> masks = new ArrayList<>(clades);
        Collections.sort(masks);
        for (int mask : masks)
            nodes.put(mask, tree.internal());
        for (var entry : nodes.entrySet()) {
            int mask = entry.getKey(), parent = root, best = count + 1;
            for (var other : nodes.entrySet())
                if (other.getKey() != mask && (other.getKey() & mask) == mask &&
                    Integer.bitCount(other.getKey()) < best) {
                    parent = other.getValue();
                    best = Integer.bitCount(other.getKey());
                }
            tree.connect(parent, entry.getValue());
        }
        for (int taxon : taxa) {
            int parent = root, best = count + 1;
            for (var entry : nodes.entrySet())
                if ((entry.getKey() & (1 << taxon)) != 0 &&
                    Integer.bitCount(entry.getKey()) < best) {
                    parent = entry.getValue();
                    best = Integer.bitCount(entry.getKey());
                }
            tree.connect(parent, taxon);
        }
        return tree;
    }
    static Exhaustive exhaustive(List<Integer> taxa) {
        Exhaustive result = new Exhaustive();
        result.taxa = taxa;
        List<TreeBuilding.Tree> trees = new ArrayList<>();
        trees.add(TreeBuilding.star(count, taxa.subList(0, 3)));
        for (int i = 3; i < taxa.size(); i++) {
            List<TreeBuilding.Tree> expanded = new ArrayList<>();
            for (TreeBuilding.Tree tree : trees)
                for (Parsimony.Branch edge : Parsimony.branches(tree, outgroup))
                    expanded.add(Parsimony.insert(tree, edge.first(), edge.second(), taxa.get(i)));
            trees = expanded;
        }
        for (TreeBuilding.Tree tree : trees) {
            int score = Parsimony.score(tree, patterns, outgroup);
            result.histogram.merge(score, 1, Integer::sum);
            result.records.add(new SearchRecord(tree, score, bme(tree),
                                                TreeIo.newick(tree, names, outgroup),
                                                tree.rooted(outgroup).splits()));
        }
        result.bestScore = result.histogram.firstKey();
        for (SearchRecord record : result.records)
            if (record.score() == result.bestScore)
                result.optimal.add(record);
        result.optimal.sort(Comparator.comparing(SearchRecord::newick));
        Set<Integer> common = new HashSet<>(result.optimal.getFirst().splits());
        for (SearchRecord record : result.optimal)
            common.retainAll(record.splits());
        result.strict = consensus(taxa, common);
        result.bestBme = Collections.min(
            result.records,
            Comparator.comparingDouble(SearchRecord::bme).thenComparing(SearchRecord::newick));
        result.secondBme = Double.POSITIVE_INFINITY;
        for (SearchRecord record : result.records)
            if (record != result.bestBme)
                result.secondBme = Math.min(result.secondBme, record.bme());
        Stepwise initial = stepwise(taxa);
        result.heuristic =
            (int)hill(initial.tree(),
                      tree -> Parsimony.score(tree, patterns, outgroup), initial.score())
                .value();
        return result;
    }
    static double[] likelihood(TreeBuilding.Tree tree) {
        TreeBuilding.Rooted rooted = tree.rooted(outgroup);
        List<List<Integer>> children = TreeIo.childOrder(rooted, names);
        double[][][] transition = new double[tree.nextNode][4][4];
        for (int node : rooted.order)
            if (node != rooted.root) {
                double branch = tree.adjacent.get(node).get(rooted.parents[node]),
                       e = Math.exp(-4 * branch / 3);
                for (int a = 0; a < 4; a++)
                    for (int b = 0; b < 4; b++)
                        transition[node][a][b] = a == b ? 0.25 + 0.75 * e : 0.25 - 0.25 * e;
            }
        double[] values = new double[patterns.patterns.size()];
        for (int p = 0; p < values.length; p++) {
            int[] pattern = patterns.encoded.get(p);
            double[][] partial = new double[tree.nextNode][4], upward =
                                                                   new double[tree.nextNode][4];
            for (int i = rooted.order.size() - 1; i >= 0; i--) {
                int node = rooted.order.get(i);
                if (node < tree.size) {
                    for (int a = 0; a < 4; a++)
                        partial[node][a] = (pattern[node] & (1 << a)) != 0 ? 1 : 0;
                } else {
                    Arrays.fill(partial[node], 1);
                    for (int child : children.get(node))
                        for (int a = 0; a < 4; a++)
                            partial[node][a] *= upward[child][a];
                }
                if (node != rooted.root)
                    for (int a = 0; a < 4; a++)
                        for (int b = 0; b < 4; b++)
                            upward[node][a] += transition[node][a][b] * partial[node][b];
            }
            double probability = 0;
            for (double value : partial[rooted.root])
                probability += 0.25 * value;
            values[p] = Math.log(probability);
        }
        double[] sites = new double[length];
        for (int c = 0; c < length; c++)
            sites[c] = values[patterns.columns[c]];
        return sites;
    }
    static List<String> likelihoodLines() {
        List<String> lines = new ArrayList<>();
        lines.add("LIKELIHOOD columns " + length + " patterns " + patterns.patterns.size());
        for (String method : NJ_METHODS) {
            double total = sum(siteLogs.get(method));
            lines.add("TREE " + method + " loglik " + f(total, 4) + " per_site " +
                      f(total / length, 4));
        }
        for (int i = 0; i < 3; i++)
            for (int j = i + 1; j < 3; j++) {
                String a = NJ_METHODS[i], b = NJ_METHODS[j];
                double[] deltas = new double[length];
                for (int c = 0; c < length; c++)
                    deltas[c] = siteLogs.get(a)[c] - siteLogs.get(b)[c];
                double difference = sum(deltas), mean = difference / length, ss = 0;
                for (double delta : deltas)
                    ss += square(delta - mean);
                double se = Math.sqrt(length / (double)(length - 1) * ss);
                lines.add("KH " + a + " " + b + " difference " + f(difference, 4) + " se " +
                          f(se, 4) + " z " + f(difference / se, 4));
            }
        List<Integer> columns = new ArrayList<>();
        for (int c = 0; c < length; c++)
            columns.add(c);
        columns.sort(Comparator
                         .comparingDouble(
                             (Integer c) -> Double.parseDouble(f(siteLogs.get(mainMethod)[c], 4)))
                         .thenComparingInt(c -> c));
        int[] changes = Parsimony.patternScores(trees.get(mainMethod), patterns, outgroup);
        int low = integer("low_sites");
        lines.add("LOWEST " + mainMethod + " sites " + low);
        for (int i = 0; i < low; i++) {
            int c = columns.get(i), p = patterns.columns[c];
            lines.add("SITE " + (c + 1) + " loglik " + f(siteLogs.get(mainMethod)[c], 4) +
                      " changes " + changes[p] + " pattern " + patterns.patterns.get(p));
        }
        return lines;
    }
    static List<String> bootstrap() {
        List<String> lines = new ArrayList<>();
        int replicates = integer("replicates");
        long state = Long.parseLong(parameter("seed"));
        Set<Integer> mainSplits = trees.get(mainMethod).rooted(outgroup).splits();
        lines.add("BOOTSTRAP model " + parameter("model") + " replicates " + replicates + " seed " +
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
                    .matrix(Distances.pairs(sequences, weights), count, parameter("model"),
                            realParameter("saturation_distance"))
                    .values();
            TreeBuilding.Tree tree = TreeBuilding.nj(matrix, taxa());
            Set<Integer> splits = tree.rooted(outgroup).splits();
            for (int mask : splits)
                support.merge(mask, 1, Integer::sum);
            int difference = rf(splits, mainSplits), distinct = 0;
            for (int weight : weights)
                if (weight > 0)
                    distinct++;
            if (difference == 0)
                identical++;
            lines.add("REPLICATE " + b + " distinct " + distinct + " rf " + difference);
        }
        lines.add("IDENTICAL " + identical);
        for (int mask : symbolOrder(mainSplits))
            lines.add("SUPPORT " + symbols(mask) + " " + support.getOrDefault(mask, 0));
        List<Integer> splits = new ArrayList<>(support.keySet());
        splits.sort(Comparator.comparingInt((Integer mask) -> - support.get(mask))
                        .thenComparing(Main::symbols));
        Set<Integer> majority = new HashSet<>();
        for (int mask : splits) {
            lines.add("SPLIT " + symbols(mask) + " " + support.get(mask));
            if (2 * support.get(mask) > replicates)
                majority.add(mask);
        }
        TreeBuilding.Tree consensus = consensus(taxa(), majority);
        trees.put("CONSENSUS", consensus);
        lines.add("CONSENSUS " + TreeIo.newick(consensus, names, outgroup, false, support));
        for (int taxon = 0; taxon < count; taxon++)
            if (taxon != outgroup) {
                List<Integer> taxa = taxa();
                taxa.remove(Integer.valueOf(taxon));
                TreeBuilding.Tree tree = TreeBuilding.nj(mainMatrix, taxa);
                Set<Integer> reduced = new HashSet<>();
                for (int mask : mainSplits) {
                    int next = mask & ~(1 << taxon), size = Integer.bitCount(next);
                    if (size >= 2 && size <= count - 3)
                        reduced.add(next);
                }
                lines.add("JACKKNIFE " + names.get(taxon) + " rf " +
                          rf(tree.rooted(outgroup).splits(), reduced));
            }
        return lines;
    }
    static List<String> clock() {
        List<String> pairs = new ArrayList<>();
        int rejected = 0;
        List<Integer> ingroup = taxa();
        ingroup.remove(Integer.valueOf(outgroup));
        for (int i = 0; i < ingroup.size(); i++)
            for (int j = i + 1; j < ingroup.size(); j++) {
                int a = ingroup.get(i), b = ingroup.get(j), m1 = 0, m2 = 0;
                for (int c = 0; c < length; c++) {
                    char x = sequences.get(a).charAt(c), y = sequences.get(b).charAt(c),
                         o = sequences.get(outgroup).charAt(c);
                    if (Alignment.BASES.indexOf(x) >= 0 && Alignment.BASES.indexOf(y) >= 0 &&
                        Alignment.BASES.indexOf(o) >= 0 && x != y) {
                        if (y == o)
                            m1++;
                        if (x == o)
                            m2++;
                    }
                }
                int difference = m1 - m2, total = m1 + m2;
                boolean reject = 1000 * difference * difference > 3841 * total;
                if (reject)
                    rejected++;
                pairs.add("RRT " + names.get(a) + " " + names.get(b) + " m1 " + m1 + " m2 " + m2 +
                          " chi2 " +
                          (total == 0 ? "-" : f(difference * (double)difference / total, 4)) + " " +
                          (reject ? "reject" : "ok"));
            }
        List<String> lines = new ArrayList<>();
        lines.add("RELATIVE_RATE outgroup " + names.get(outgroup) + " pairs " + pairs.size() +
                  " rejected " + rejected);
        lines.addAll(pairs);
        TreeBuilding.Tree tree = trees.get(mainMethod);
        double[] paths = TreeBuilding.paths(tree, tree.rooted(outgroup).root, false);
        double mean = 0, ss = 0;
        for (int t : ingroup)
            mean += paths[t];
        mean /= ingroup.size();
        for (int t : ingroup)
            ss += square(paths[t] - mean);
        double sd = Math.sqrt(ss / (ingroup.size() - 1));
        lines.add("ROOT_TO_TIP " + mainMethod + " mean " + f(mean, 5) + " sd " + f(sd, 5) + " cv " +
                  f(sd / mean, 4));
        for (int t : ingroup)
            lines.add("TIP " + names.get(t) + " " + f(paths[t], 5));
        return lines;
    }
    static int[] quartets(Set<Integer> splits) {
        List<Integer> values = new ArrayList<>();
        for (int a = 0; a < count; a++)
            for (int b = a + 1; b < count; b++)
                for (int c = b + 1; c < count; c++)
                    for (int d = c + 1; d < count; d++) {
                        int quartet = (1 << a) | (1 << b) | (1 << c) | (1 << d), topology = 0;
                        int[] others = {b, c, d};
                        for (int i = 0; i < 3 && topology == 0; i++) {
                            int side = (1 << a) | (1 << others[i]);
                            for (int mask : splits) {
                                int part = mask & quartet;
                                if (part == side || part == (quartet ^ side)) {
                                    topology = i + 1;
                                    break;
                                }
                            }
                        }
                        values.add(topology);
                    }
        return values.stream().mapToInt(Integer::intValue).toArray();
    }
    static List<String> comparison(Hill mp, Parsimony.Reconstruction reconstruction) {
        Map<String, Set<Integer>> splits = new LinkedHashMap<>();
        for (String method : METHODS)
            splits.put(method, trees.get(method).rooted(outgroup).splits());
        List<String> lines = new ArrayList<>();
        int replicates = integer("replicates");
        for (String method : METHODS) {
            TreeBuilding.Tree tree = trees.get(method);
            int supported = 0;
            for (int mask : splits.get(method))
                if (2 * support.getOrDefault(mask, 0) > replicates)
                    supported++;
            String score = "-", bme = "-", length = "-", negative = "-", residual = "-",
                   likelihood = "-";
            if (!method.equals("CONSENSUS")) {
                score = Integer.toString(method.equals("MP") ? (int)mp.value()
                                         : method.equals("ME")
                                             ? Parsimony.score(tree, patterns, outgroup)
                                             : njScores.get(method));
                bme = f(bme(tree), 5);
            }
            if (method.startsWith("NJ_")) {
                double total = 0, ss = 0;
                for (Parsimony.Branch edge : Parsimony.branches(tree, outgroup))
                    total += tree.adjacent.get(edge.first()).get(edge.second());
                length = f(total, 5);
                negative = Integer.toString(tree.negative);
                double[][] matrix = matrices.get(method.substring(3)).values(),
                           paths = patristic.get(method);
                for (int i = 0; i < count; i++)
                    for (int j = i + 1; j < count; j++)
                        ss += square(matrix[i][j] - paths[i][j]);
                residual = f(ss, 6);
                likelihood = f(sum(siteLogs.get(method)), 4);
            } else if (method.equals("MP"))
                length = f(mp.value() / Main.length, 5);
            lines.add("TREE " + method + " splits " + splits.get(method).size() + " supported " +
                      supported + " parsimony " + score + " bme " + bme + " length " + length +
                      " negative " + negative + " sse " + residual + " loglik " + likelihood);
        }
        lines.add("RF " + String.join(" ", METHODS));
        for (String a : METHODS) {
            String line = a;
            for (String b : METHODS)
                line += " " + rf(splits.get(a), splits.get(b));
            lines.add(line);
        }
        Map<String, int[]> quartets = new HashMap<>();
        for (String method : METHODS)
            quartets.put(method, quartets(splits.get(method)));
        lines.add("QUARTET " + String.join(" ", METHODS));
        for (String a : METHODS) {
            String line = a;
            for (String b : METHODS) {
                int difference = 0;
                int[] first = quartets.get(a), second = quartets.get(b);
                for (int i = 0; i < first.length; i++)
                    if (first[i] != second[i])
                        difference++;
                line += " " + difference;
            }
            lines.add(line);
        }
        Set<Integer> all = new HashSet<>();
        for (Set<Integer> set : splits.values())
            all.addAll(set);
        Map<Integer, Double> lengths = trees.get(mainMethod).rooted(outgroup).branchLengths();
        Map<Integer, Integer> changes = new HashMap<>();
        for (Parsimony.Branch edge : Parsimony.branches(trees.get("MP"), outgroup))
            changes.put(edge.mask(), reconstruction.branchChanges().get(
                                         Parsimony.Ends.of(edge.first(), edge.second())));
        for (int mask : symbolOrder(all)) {
            String marks = "";
            for (String method : METHODS)
                marks += splits.get(method).contains(mask) ? "+" : "-";
            lines.add("CLADE " + symbols(mask) + " support " + support.getOrDefault(mask, 0) +
                      " trees " + marks + " length " +
                      (lengths.containsKey(mask) ? f(lengths.get(mask), 5) : "-") + " changes " +
                      (changes.containsKey(mask) ? changes.get(mask) : "-"));
        }
        return lines;
    }
    static List<String> hypotheses(Exhaustive exhaustive) throws Exception {
        Map<String, Integer> numbers = new HashMap<>();
        for (int i = 0; i < count; i++)
            numbers.put(names.get(i), i);
        int ingroup = ((1 << count) - 1) ^ (1 << outgroup), exhaustiveIngroup = 0;
        for (int t : exhaustive.taxa)
            if (t != outgroup)
                exhaustiveIngroup |= 1 << t;
        Map<String, Set<Integer>> splits = new HashMap<>();
        for (String method : METHODS)
            splits.put(method, trees.get(method).rooted(outgroup).splits());
        List<String> lines = new ArrayList<>();
        for (String line : Files.readAllLines(Path.of("input", "clades.txt"))) {
            String[] w = line.split(" ");
            String hypothesis = w[0], unknown = null;
            int mask = 0;
            for (int i = 1; i < w.length; i++)
                if (!numbers.containsKey(w[i])) {
                    unknown = w[i];
                    break;
                }
            if (unknown != null) {
                lines.add("INVALID " + hypothesis + " unknown taxon " + unknown);
                continue;
            }
            for (int i = 1; i < w.length; i++)
                mask |= 1 << numbers.get(w[i]);
            if ((mask & (1 << outgroup)) != 0) {
                lines.add("INVALID " + hypothesis + " contains outgroup");
                continue;
            }
            lines.add("CLADE " + hypothesis + " taxa " + Integer.bitCount(mask) + " support " +
                      support.getOrDefault(mask, 0));
            for (String method : METHODS) {
                int common = ingroup;
                for (int clade : splits.get(method))
                    if ((clade & mask) == mask &&
                        Integer.bitCount(clade) < Integer.bitCount(common))
                        common = clade;
                List<String> intruders = new ArrayList<>();
                for (int t = 0; t < count; t++)
                    if ((common & ~mask & (1 << t)) != 0)
                        intruders.add(names.get(t));
                lines.add("TEST " + hypothesis + " " + method + " monophyletic " +
                          yes(common == mask) + " mrca " + Integer.bitCount(common) +
                          " intruders " +
                          (intruders.isEmpty() ? "-" : String.join(",", intruders)));
            }
            int subset = mask & exhaustiveIngroup, size = Integer.bitCount(subset);
            if (size < 2 || size >= Integer.bitCount(exhaustiveIngroup)) {
                lines.add("SUBSET " + hypothesis + " untestable");
                continue;
            }
            int with = Integer.MAX_VALUE, without = Integer.MAX_VALUE;
            double withBme = Double.POSITIVE_INFINITY, withoutBme = Double.POSITIVE_INFINITY;
            for (SearchRecord record : exhaustive.records)
                if (record.splits().contains(subset)) {
                    with = Math.min(with, record.score());
                    withBme = Math.min(withBme, record.bme());
                } else {
                    without = Math.min(without, record.score());
                    withoutBme = Math.min(withoutBme, record.bme());
                }
            lines.add("SUBSET " + hypothesis + " taxa " + size + " with " + with + " without " +
                      without + " bme_with " + f(withBme, 5) + " bme_without " + f(withoutBme, 5));
        }
        return lines;
    }
    static List<String> distanceLines(List<Distances.Pair> pairs, double start, Hill me,
                                      Exhaustive exhaustive) {
        List<String> lines = new ArrayList<>();
        int n = 0, s = 0, v = 0;
        for (Distances.Pair pair : pairs) {
            lines.add("PAIR " + names.get(pair.first()) + " " + names.get(pair.second()) +
                      " sites " + pair.sites() + " transitions " + pair.transitions() +
                      " transversions " + pair.transversions());
            n += pair.sites();
            s += pair.transitions();
            v += pair.transversions();
        }
        lines.add("TOTAL sites " + n + " transitions " + s + " transversions " + v);
        for (String model : Distances.MODELS) {
            lines.add("");
            lines.add("MODEL " + model);
            lines.addAll(matrixLines(matrices.get(model).values()));
            for (Distances.Pair pair : matrices.get(model).saturated())
                lines.add("SATURATED " + names.get(pair.first()) + " " + names.get(pair.second()) +
                          " sites " + pair.sites());
        }
        lines.add("");
        lines.add("PATRISTIC " + mainMethod);
        lines.addAll(matrixLines(patristic.get(mainMethod)));
        lines.add("");
        lines.add("ME start " + mainMethod + " length " + f(start, 5));
        for (Move move : me.moves())
            lines.add("NNI edge " + symbols(move.mask()) + " swap " + move.swap() + " length " +
                      f(move.value(), 5));
        lines.add("ME moves " + me.moves().size() + " evaluated " + me.evaluated() + " length " +
                  f(me.value(), 5));
        lines.add("EXHAUSTIVE taxa " + exhaustive.taxa.size() + " trees " +
                  exhaustive.records.size() + " best " + f(exhaustive.bestBme.bme(), 5) +
                  " second " + f(exhaustive.secondBme, 5));
        lines.add("BEST " + exhaustive.bestBme.newick() + " parsimony " +
                  exhaustive.bestBme.score());
        return lines;
    }
    static String scoreLine(String method, int score, Bounds bounds) {
        return "TREE " + method + " score " + score + " ci " +
            f(bounds.minimum() / (double)score, 4) + " ri " +
            f((bounds.maximum() - score) / (double)(bounds.maximum() - bounds.minimum()), 4);
    }
    static List<String> parsimonyLines(Bounds bounds, Stepwise initial, Hill search,
                                       Parsimony.Reconstruction reconstruction,
                                       Exhaustive exhaustive) {
        List<String> lines = new ArrayList<>();
        lines.add("BOUNDS minimum " + bounds.minimum() + " maximum " + bounds.maximum());
        for (String method : NJ_METHODS)
            lines.add(scoreLine(method, njScores.get(method), bounds));
        List<String> start = new ArrayList<>();
        for (int t : initial.taxa().subList(0, 3))
            start.add(names.get(t));
        lines.add("START " + String.join(" ", start) + " score " + initial.initial());
        for (Addition a : initial.additions())
            lines.add("ADD " + names.get(a.taxon()) + " edge " + symbols(a.mask()) + " score " +
                      a.score() + " ties " + a.ties());
        lines.add("STEPWISE score " + initial.score() + " evaluated " + initial.evaluated());
        for (Move move : search.moves())
            lines.add("NNI edge " + symbols(move.mask()) + " swap " + move.swap() + " score " +
                      (int)move.value());
        int score = (int)search.value();
        lines.add("SEARCH moves " + search.moves().size() + " evaluated " + search.evaluated() +
                  " score " + score);
        lines.add(scoreLine("MP", score, bounds));
        lines.add("MP " + TreeIo.newick(search.tree(), names, outgroup, true, null));
        int[] changes = reconstruction.siteChanges();
        int maximum = Arrays.stream(changes).max().orElse(0), homoplasy = 0;
        int[] histogram = new int[maximum + 1];
        for (int c = 0; c < length; c++) {
            histogram[changes[c]]++;
            if (changes[c] > bounds.minima()[c])
                homoplasy++;
        }
        for (int k = 0; k <= maximum; k++)
            lines.add("CHANGES " + k + " columns " + histogram[k]);
        lines.add("HOMOPLASY columns " + homoplasy + " extra " + (score - bounds.minimum()));
        TreeBuilding.Rooted rooted = search.tree().rooted(outgroup);
        TreeMap<String, String> ancestors = new TreeMap<>();
        for (var entry : reconstruction.ancestors().entrySet())
            ancestors.put(symbols(entry.getKey() == rooted.root ? rooted.ingroup
                                                                : rooted.masks[entry.getKey()]),
                          entry.getValue());
        for (var entry : ancestors.entrySet())
            lines.add("ANCESTOR " + entry.getKey() + " " + entry.getValue());
        lines.add("");
        lines.add("EXHAUSTIVE taxa " + exhaustive.taxa.size() + " trees " +
                  exhaustive.records.size() + " best " + exhaustive.bestScore + " optimal " +
                  exhaustive.optimal.size());
        for (var entry : exhaustive.histogram.entrySet())
            lines.add("SCORE " + entry.getKey() + " trees " + entry.getValue());
        for (SearchRecord record : exhaustive.optimal)
            lines.add("OPTIMAL " + record.newick() + " bme " + f(record.bme(), 5));
        lines.add("STRICT " + TreeIo.newick(exhaustive.strict, names, outgroup));
        lines.add("HEURISTIC score " + exhaustive.heuristic + " optimal " +
                  yes(exhaustive.heuristic == exhaustive.bestScore));
        return lines;
    }
    public static void main(String[] args) throws Exception {
        read();
        int[] weights = new int[length];
        Arrays.fill(weights, 1);
        List<Distances.Pair> pairs = Distances.pairs(sequences, weights);
        for (int i = 0; i < 3; i++) {
            String model = Distances.MODELS[i], method = NJ_METHODS[i];
            Distances.Matrix matrix =
                Distances.matrix(pairs, count, model, realParameter("saturation_distance"));
            matrices.put(model, matrix);
            trees.put(method, TreeBuilding.nj(matrix.values(), taxa()));
        }
        mainMatrix = matrices.get(parameter("model")).values();
        double start = bme(trees.get(mainMethod));
        Hill me = hill(trees.get(mainMethod), Main::bme, start);
        List<Integer> order = taxa();
        order.remove(Integer.valueOf(outgroup));
        order.addFirst(outgroup);
        Stepwise initial = stepwise(order);
        Hill mp = hill(initial.tree(),
                       tree -> Parsimony.score(tree, patterns, outgroup), initial.score());
        Parsimony.Reconstruction reconstruction =
            Parsimony.reconstruct(mp.tree(), patterns, outgroup);
        for (var entry : reconstruction.branchChanges().entrySet())
            mp.tree().connect(entry.getKey().first(), entry.getKey().second(),
                              entry.getValue() / (double)length);
        Bounds bounds = bounds();
        for (String method : NJ_METHODS)
            njScores.put(method, Parsimony.score(trees.get(method), patterns, outgroup));
        Set<String> exhaustiveNames = new HashSet<>(parameters.get("exhaustive_taxa"));
        List<Integer> exhaustiveTaxa = new ArrayList<>();
        exhaustiveTaxa.add(outgroup);
        for (int t = 0; t < count; t++)
            if (t != outgroup && exhaustiveNames.contains(names.get(t)))
                exhaustiveTaxa.add(t);
        Exhaustive exhaustive = exhaustive(exhaustiveTaxa);
        for (String method : NJ_METHODS) {
            siteLogs.put(method, likelihood(trees.get(method)));
            patristic.put(method, TreeBuilding.patristic(trees.get(method)));
        }
        trees.put("ME", me.tree());
        trees.put("MP", mp.tree());
        List<String> bootstrap = bootstrap(), newicks = new ArrayList<>(),
                     diagrams = new ArrayList<>();
        for (String method : METHODS) {
            TreeBuilding.Tree tree = trees.get(method);
            boolean lengths = method.startsWith("NJ_") || method.equals("MP");
            newicks.add(method + " " +
                        TreeIo.newick(tree, names, outgroup, lengths,
                                      method.equals("CONSENSUS") ? support : null));
            if (!diagrams.isEmpty())
                diagrams.add("");
            diagrams.add("TREE " + method);
            diagrams.addAll(TreeIo.cladogram(tree, names, outgroup, support));
        }
        TreeIo.write("summary.txt", summary());
        TreeIo.write("distances.txt", distanceLines(pairs, start, me, exhaustive));
        TreeIo.write("trees.nwk", newicks);
        TreeIo.write("cladograms.txt", diagrams);
        TreeIo.write("parsimony.txt",
                     parsimonyLines(bounds, initial, mp, reconstruction, exhaustive));
        TreeIo.write("likelihood.txt", likelihoodLines());
        TreeIo.write("bootstrap.txt", bootstrap);
        TreeIo.write("clock.txt", clock());
        TreeIo.write("comparison.txt", comparison(mp, reconstruction));
        TreeIo.write("hypotheses.txt", hypotheses(exhaustive));
    }
}
