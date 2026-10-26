import java.io.*;
import java.math.BigInteger;
import java.nio.file.*;
import java.util.*;

public final class Main {
    static String real(Double value) {
        if (value == null) return "-";
        String text = String.format(Locale.ROOT, "%.4f", value);
        return text.equals("-0.0000") ? "0.0000" : text;
    }
    static double fourDigit(double value) { return Double.parseDouble(real(value)); }
    static String reals(double[] values) { return String.join(" ", Arrays.stream(values).mapToObj(value -> real(value)).toList()); }
    static String integers(int[] values) { return String.join(" ", Arrays.stream(values).mapToObj(Integer::toString).toList()); }
    static String ariText(Fraction value) { return value + " " + real(value.value()); }
    static double[] pairValues(double[][] matrix) {
        double[] values = new double[matrix.length * (matrix.length - 1) / 2]; int position = 0;
        for (int i = 0; i < matrix.length; i++) for (int j = i + 1; j < matrix.length; j++) values[position++] = matrix[i][j];
        return values;
    }
    static int histogramBin(double value, double maximum) { return Math.min(9, (int) Math.floor(10 * value / maximum)); }
    static List<List<Integer>> clusterMembers(int[] partition, int groups) {
        List<List<Integer>> members = new ArrayList<>(); for (int g = 0; g < groups; g++) members.add(new ArrayList<>());
        for (int i = 0; i < partition.length; i++) members.get(partition[i] - 1).add(i);
        return members;
    }
    static double[] centroid(double[][] vectors) {
        double[] center = new double[vectors[0].length];
        for (int f = 0; f < center.length; f++) { double total = 0.0; for (double[] vector : vectors) total += vector[f]; center[f] = total / vectors.length; }
        return center;
    }
    static int maximum(int[] values) { return Arrays.stream(values).max().orElseThrow(); }
    static int majorityClass(int[] row) { int best = 0; for (int t = 1; t < row.length; t++) if (row[t] > row[best]) best = t; return best; }
    static List<String> joinParts(List<List<String>> parts) {
        List<String> lines = new ArrayList<>(); for (List<String> part : parts) { if (!lines.isEmpty()) lines.add(""); lines.addAll(part); } return lines;
    }
    static int[] connectedComponents(int count, List<Agglomerative.Edge> edges) {
        int[] components = new int[count]; for (int u = 0; u < count; u++) components[u] = u;
        for (Agglomerative.Edge edge : edges) { int old = components[edge.child()], replacement = components[edge.parent()]; for (int u = 0; u < count; u++) if (components[u] == old) components[u] = replacement; }
        return components;
    }
    static final class Minstd {
        long state;
        Minstd(int seed) { state = seed; }
        long draw() { state = 48271 * state % 2147483647; return state; }
    }
    static final class Settings {
        final String distance, standardize, compareLinkage;
        final List<String> linkages;
        final double[] cutHeights;
        final int[] cutCounts;
        final BigInteger inconsistencyDepth;
        final int inconsistencyCount, gapMaxK, listSize, width, replicates, percent, seed, refineIterations;
        Settings(Map<String, List<String>> entries) {
            distance = entries.get("DISTANCE").getFirst(); standardize = entries.get("STANDARDIZE").getFirst(); linkages = entries.get("LINKAGES");
            cutHeights = entries.get("CUT_HEIGHTS").stream().mapToDouble(Double::parseDouble).toArray(); cutCounts = entries.get("CUT_K").stream().mapToInt(Integer::parseInt).toArray();
            inconsistencyDepth = new BigInteger(entries.get("INCONSISTENCY").get(0)); inconsistencyCount = Integer.parseInt(entries.get("INCONSISTENCY").get(1));
            gapMaxK = Integer.parseInt(entries.get("GAP_MAX_K").getFirst()); listSize = Integer.parseInt(entries.get("LIST_SIZE").getFirst()); width = Integer.parseInt(entries.get("DENDROGRAM_WIDTH").getFirst());
            compareLinkage = entries.get("COMPARE_LINKAGE").getFirst(); replicates = Integer.parseInt(entries.get("SUBSAMPLES").get(0)); percent = Integer.parseInt(entries.get("SUBSAMPLES").get(1)); seed = Integer.parseInt(entries.get("SUBSAMPLES").get(2));
            refineIterations = Integer.parseInt(entries.get("REFINE_ITERATIONS").getFirst());
        }
    }
    static final class Tree {
        final List<Agglomerative.Merge> merges;
        final int count;
        final double[] heights, subtreeHeights;
        final int[][] children;
        final int[] order, depths;
        final List<int[]> members = new ArrayList<>();
        Tree(List<Agglomerative.Merge> merges, int count) {
            this.merges = merges; this.count = count; heights = merges.stream().mapToDouble(Agglomerative.Merge::height).toArray(); children = Dendrogram.children(merges, count); order = Dendrogram.leafOrder(children, count);
            depths = new int[2 * count - 1]; subtreeHeights = new double[merges.size()];
            for (int u = 0; u < count; u++) members.add(new int[]{u});
            for (int step = 0; step < merges.size(); step++) {
                Agglomerative.Merge merge = merges.get(step); int[] first = members.get(merge.a()), second = members.get(merge.b()), all = Arrays.copyOf(first, first.length + second.length);
                System.arraycopy(second, 0, all, first.length, second.length); members.add(all);
                depths[count + step] = 1 + Math.max(depths[merge.a()], depths[merge.b()]); subtreeHeights[step] = Math.max(merge.height(), Math.max(subtreeHeight(merge.a()), subtreeHeight(merge.b())));
            }
        }
        int root() { return 2 * count - 2; }
        double height(int node) { return node < count ? 0.0 : heights[node - count]; }
        double subtreeHeight(int node) { return node < count ? 0.0 : subtreeHeights[node - count]; }
        int[] partition(boolean[] selected) {
            int[] owner = new int[count]; for (int u = 0; u < count; u++) owner[u] = u;
            for (int step = 0; step < selected.length; step++) if (selected[step]) for (int u : members.get(count + step)) owner[u] = count + step;
            int[] numbers = new int[2 * count - 1]; int groups = 0;
            for (int u : order) if (numbers[owner[u]] == 0) numbers[owner[u]] = ++groups;
            return Arrays.stream(owner).map(node -> numbers[node]).toArray();
        }
        int[] cutAtHeight(double height) { boolean[] chosen = new boolean[merges.size()]; for (int step = 0; step < chosen.length; step++) chosen[step] = subtreeHeights[step] <= height; return partition(chosen); }
        int[] cutInto(int groups) { boolean[] chosen = new boolean[merges.size()]; for (int step = 0; step < count - groups; step++) chosen[step] = true; return partition(chosen); }
        double[][] cophenetic() {
            double[][] matrix = new double[count][count];
            for (Agglomerative.Merge merge : merges) for (int i : members.get(merge.a())) for (int j : members.get(merge.b())) matrix[i][j] = matrix[j][i] = merge.height();
            return matrix;
        }
        double[] joiningHeights() {
            double[] values = new double[count];
            for (Agglomerative.Merge merge : merges) { if (merge.a() < count) values[merge.a()] = merge.height(); if (merge.b() < count) values[merge.b()] = merge.height(); }
            return values;
        }
        List<Double> heightSequence(int step, int depth) {
            List<Double> sequence = new ArrayList<>(); if (depth == 0) return sequence;
            Agglomerative.Merge merge = merges.get(step); sequence.add(merge.height());
            for (int child : new int[]{merge.a(), merge.b()}) if (child >= count) sequence.addAll(heightSequence(child - count, depth - 1));
            return sequence;
        }
        String newick(int node, String[] idents) {
            if (node < count) return idents[node]; int upper = children[node - count][0], lower = children[node - count][1];
            return "(" + newick(upper, idents) + ":" + real(height(node) - height(upper)) + "," + newick(lower, idents) + ":" + real(height(node) - height(lower)) + ")";
        }
    }
    record PartitionEvaluation(int[] partition, int[] sizes, Double silhouette, Double dunn, double wss, Double ch, Fraction ari) {
        String text() { return "sizes " + integers(sizes) + " silhouette " + real(silhouette) + " dunn " + real(dunn) + " wss " + real(wss) + " ch " + real(ch) + " ari " + ariText(ari); }
    }
    record LinkageResult(String method, Tree tree, double[] cophenetic, double correlation, List<PartitionEvaluation> heightCuts, List<PartitionEvaluation> countCuts, int[] labelPartition) {}

    static final class Study {
        final String[] featureNames, idents, labels, classes;
        final Settings settings;
        final int count;
        final int[] targets, neighbors;
        final double[][] raw, vectors, distances;
        final double[] means, deviations, distancePairs;
        final double distanceMax;
        final List<LinkageResult> results = new ArrayList<>();
        final LinkageResult chosen;
        final int kappa;
        final PartitionEvaluation selectedCut;
        final int[] selected, majority;
        final List<List<Integer>> members;
        final double[] silhouettes;
        final int[][] table;

        Study(InputData input) {
            featureNames = input.features(); settings = new Settings(input.settings()); count = input.observations().size();
            idents = input.observations().stream().map(Observation::ident).toArray(String[]::new); labels = input.observations().stream().map(Observation::label).toArray(String[]::new);
            classes = Arrays.stream(labels).distinct().sorted().toArray(String[]::new); targets = Arrays.stream(labels).mapToInt(label -> Arrays.binarySearch(classes, label)).toArray();
            raw = input.observations().stream().map(Observation::values).toArray(double[][]::new); Distances.Statistics statistics = Distances.statistics(raw); means = statistics.means(); deviations = statistics.deviations();
            vectors = settings.standardize.equals("yes") ? Distances.standardize(raw, statistics) : raw; distances = Distances.matrix(vectors, settings.distance); distancePairs = pairValues(distances); distanceMax = Arrays.stream(distancePairs).max().orElseThrow();
            neighbors = new int[count]; for (int i = 0; i < count; i++) neighbors[i] = nearestNeighbor(i);
            for (String method : settings.linkages) results.add(analyseLinkage(method));
            int bestResult = 0, bestPosition = 0;
            for (int r = 0; r < results.size(); r++) for (int position = 0; position < settings.cutCounts.length; position++) if (results.get(r).countCuts.get(position).ari.compareTo(results.get(bestResult).countCuts.get(bestPosition).ari) > 0) { bestResult = r; bestPosition = position; }
            chosen = results.get(bestResult); kappa = settings.cutCounts[bestPosition]; selectedCut = chosen.countCuts.get(bestPosition); selected = selectedCut.partition;
            members = clusterMembers(selected, kappa); silhouettes = Validation.silhouettes(selected, kappa, distances); table = classTable(selected); majority = Arrays.stream(table).mapToInt(Main::majorityClass).toArray();
        }
        int nearestNeighbor(int i) { int best = -1; for (int j = 0; j < count; j++) if (j != i && (best < 0 || distances[i][j] < distances[i][best])) best = j; return best; }
        int[][] classTable(int[] partition) { return Validation.contingency(Arrays.stream(partition).map(number -> number - 1).toArray(), targets, maximum(partition), classes.length); }
        Fraction labelAri(int[] partition) { return Validation.adjustedRand(classTable(partition)); }
        Fraction partitionAri(int[] first, int[] second) { return Validation.adjustedRand(Validation.contingency(Arrays.stream(first).map(number -> number - 1).toArray(), Arrays.stream(second).map(number -> number - 1).toArray(), maximum(first), maximum(second))); }
        int matchCount(int[] partition) { int matches = 0; for (int[] row : classTable(partition)) matches += maximum(row); return matches; }
        Double meanSilhouette(int[] partition, double[][] delta) { int groups = maximum(partition); return groups < 2 ? null : Distances.sum(Validation.silhouettes(partition, groups, delta)) / partition.length; }
        double[][] centroids(int[] partition) {
            List<List<Integer>> groups = clusterMembers(partition, maximum(partition)); double[][] centers = new double[groups.size()][];
            for (int g = 0; g < groups.size(); g++) centers[g] = centroid(groups.get(g).stream().map(i -> vectors[i]).toArray(double[][]::new));
            return centers;
        }
        double withinSum(int[] partition) {
            double[][] centers = centroids(partition); double total = 0.0;
            for (int i = 0; i < count; i++) total += Distances.squared(vectors[i], centers[partition[i] - 1]);
            return total;
        }
        Double dunnIndex(int[] partition, int groups) {
            double diameter = 0.0, separation = Double.POSITIVE_INFINITY;
            for (int i = 0; i < count; i++) for (int j = i + 1; j < count; j++) if (partition[i] == partition[j]) diameter = Math.max(diameter, distances[i][j]); else separation = Math.min(separation, distances[i][j]);
            return groups >= 2 && diameter > 0 ? separation / diameter : null;
        }
        PartitionEvaluation evaluate(int[] partition) {
            int groups = maximum(partition); int[] sizes = clusterMembers(partition, groups).stream().mapToInt(List::size).toArray(); double wss = withinSum(partition); Double ch = null;
            if (groups >= 2 && groups < count) { double[] overall = centroid(vectors); double[][] centers = centroids(partition); double bss = 0.0; for (int g = 0; g < groups; g++) bss += sizes[g] * Distances.squared(centers[g], overall); ch = (bss / (groups - 1)) / (wss / (count - groups)); }
            return new PartitionEvaluation(partition, sizes, meanSilhouette(partition, distances), dunnIndex(partition, groups), wss, ch, labelAri(partition));
        }
        LinkageResult analyseLinkage(String method) {
            Tree tree = new Tree(Agglomerative.cluster(distances, method), count); double[] cophenetic = pairValues(tree.cophenetic());
            List<PartitionEvaluation> heightCuts = new ArrayList<>(), countCuts = new ArrayList<>();
            for (double height : settings.cutHeights) heightCuts.add(evaluate(tree.cutAtHeight(height)));
            for (int k : settings.cutCounts) countCuts.add(evaluate(tree.cutInto(k)));
            return new LinkageResult(method, tree, cophenetic, Validation.correlation(distancePairs, cophenetic), heightCuts, countCuts, tree.cutInto(classes.length));
        }
        List<String> linkageTable() {
            List<String> lines = new ArrayList<>(List.of("method,step,a,b,height,size"));
            for (LinkageResult result : results) for (int step = 0; step < result.tree.merges.size(); step++) {
                Agglomerative.Merge merge = result.tree.merges.get(step);
                lines.add(result.method + "," + (step + 1) + "," + merge.a() + "," + merge.b() + "," + real(merge.height()) + "," + merge.size());
            }
            return lines;
        }
        List<String> clustersTable() {
            List<String> header = new ArrayList<>(List.of("id", "label"));
            for (LinkageResult result : results) { for (int j = 1; j <= settings.cutHeights.length; j++) header.add(result.method + "_h" + j); for (int k : settings.cutCounts) header.add(result.method + "_k" + k); }
            List<String> lines = new ArrayList<>(List.of(String.join(",", header)));
            for (int i = 0; i < count; i++) {
                List<String> fields = new ArrayList<>(List.of(idents[i], labels[i]));
                for (LinkageResult result : results) { for (PartitionEvaluation cut : result.heightCuts) fields.add(Integer.toString(cut.partition[i])); for (PartitionEvaluation cut : result.countCuts) fields.add(Integer.toString(cut.partition[i])); }
                lines.add(String.join(",", fields));
            }
            return lines;
        }
        List<String> dendrogramReport() {
            List<List<String>> blocks = new ArrayList<>();
            for (LinkageResult result : results) {
                Tree tree = result.tree; double maximum = Arrays.stream(tree.heights).max().orElseThrow(); int[] columns = Arrays.stream(settings.cutHeights).mapToInt(height -> Dendrogram.column(height, maximum, settings.width)).toArray();
                List<String> lines = new ArrayList<>(List.of("dendrogram " + result.method + " height_max " + real(maximum) + " width " + settings.width));
                lines.addAll(Dendrogram.rows(tree.merges, tree.children, tree.order, idents, labels, maximum, columns, settings.width));
                for (int j = 0; j < columns.length; j++) lines.add("cut " + real(settings.cutHeights[j]) + " column " + (columns[j] <= settings.width ? Integer.toString(columns[j]) : "-"));
                blocks.add(lines);
            }
            return joinParts(blocks);
        }
        List<String> treesReport() { return results.stream().map(result -> result.method + " " + result.tree.newick(result.tree.root(), idents) + ";").toList(); }
        String pairText(int first, int second) { return real(distances[first][second]) + " " + idents[first] + " " + idents[second]; }
        List<String> dataPart() {
            List<String> lines = new ArrayList<>(List.of("data n " + count + " features " + featureNames.length + " classes " + classes.length + " distance " + settings.distance + " standardize " + settings.standardize));
            for (int f = 0; f < featureNames.length; f++) lines.add("feature " + featureNames[f] + " mean " + real(means[f]) + " sd " + real(deviations[f]));
            int minFirst = 0, minSecond = 1, maxFirst = 0, maxSecond = 1;
            for (int i = 0; i < count; i++) for (int j = i + 1; j < count; j++) {
                if (distances[i][j] < distances[minFirst][minSecond]) { minFirst = i; minSecond = j; }
                if (distances[i][j] > distances[maxFirst][maxSecond]) { maxFirst = i; maxSecond = j; }
            }
            lines.add("distances pairs " + distancePairs.length + " min " + pairText(minFirst, minSecond) + " max " + pairText(maxFirst, maxSecond) + " mean " + real(Distances.sum(distancePairs) / distancePairs.length));
            double nearestTotal = 0.0; int reciprocal = 0;
            for (int i = 0; i < count; i++) { nearestTotal += distances[i][neighbors[i]]; if (i < neighbors[i] && neighbors[neighbors[i]] == i) reciprocal++; }
            lines.add("nearest_neighbors mean " + real(nearestTotal / count) + " reciprocal_pairs " + reciprocal);
            lines.add("labels " + evaluate(Arrays.stream(targets).map(target -> target + 1).toArray()).text());
            return lines;
        }
        List<String> correlationPart() {
            double[][] columns = new double[featureNames.length][count]; for (int f = 0; f < columns.length; f++) for (int i = 0; i < count; i++) columns[f][i] = raw[i][f];
            List<String> lines = new ArrayList<>(List.of("correlation " + String.join(" ", featureNames)));
            for (int f = 0; f < featureNames.length; f++) { double[] values = new double[featureNames.length]; for (int g = 0; g < values.length; g++) values[g] = Validation.correlation(columns[f], columns[g]); lines.add(featureNames[f] + " " + reals(values)); }
            return lines;
        }
        List<String> histogramPart() {
            int[] counts = new int[10]; for (double value : distancePairs) counts[histogramBin(value, distanceMax)]++;
            int highest = maximum(counts); List<String> lines = new ArrayList<>(List.of("histogram"));
            for (int bin = 0; bin < 10; bin++) {
                String line = real(bin * distanceMax / 10) + " " + real((bin + 1) * distanceMax / 10) + " " + counts[bin];
                int length = counts[bin] * 50 / highest; if (length > 0) line += " " + "#".repeat(length); lines.add(line);
            }
            return lines;
        }
        double[] gaps(Tree tree) {
            double[] ordered = tree.subtreeHeights.clone(); Arrays.sort(ordered); double[] gaps = new double[settings.gapMaxK - 1];
            for (int k = 2; k <= settings.gapMaxK; k++) gaps[k - 2] = ordered[count - k] - ordered[count - k - 1];
            return gaps;
        }
        String inconsistencyLine(Tree tree, int step) {
            int depth = settings.inconsistencyDepth.min(BigInteger.valueOf(count)).intValueExact();
            double[] sequence = tree.heightSequence(step, depth).stream().mapToDouble(Double::doubleValue).toArray(); int size = sequence.length;
            double mean = Distances.sum(sequence) / size, deviation = 0.0, coefficient = 0.0;
            if (size >= 2) { double squares = 0.0; for (double value : sequence) { double difference = value - mean; squares += difference * difference; } deviation = Math.sqrt(squares / (size - 1)); coefficient = (tree.heights[step] - mean) / deviation; }
            return "step " + (step + 1) + " height " + real(tree.heights[step]) + " mean " + real(mean) + " sd " + real(deviation) + " count " + size + " coefficient " + real(coefficient);
        }
        List<String> linkagePart(LinkageResult result) {
            Tree tree = result.tree; double leafPath = 0.0; for (int r = 0; r < count - 1; r++) leafPath += distances[tree.order[r]][tree.order[r + 1]];
            List<Integer> inversions = new ArrayList<>(); for (int step = 1; step < tree.heights.length; step++) if (tree.heights[step] < tree.heights[step - 1]) inversions.add(step);
            List<String> lines = new ArrayList<>(List.of("linkage " + result.method, "cophenetic " + real(result.correlation) + " leaf_path " + real(leafPath), "heights min " + real(Arrays.stream(tree.heights).min().orElseThrow()) + " max " + real(Arrays.stream(tree.heights).max().orElseThrow()) + " inversions " + inversions.size()));
            for (int step : inversions) lines.add("inversion step " + (step + 1) + " height " + real(tree.heights[step]) + " previous " + real(tree.heights[step - 1]));
            double[] gaps = gaps(tree); int suggested = 2;
            for (int k = 3; k <= settings.gapMaxK; k++) if (fourDigit(gaps[k - 2]) > fourDigit(gaps[suggested - 2])) suggested = k;
            lines.add("gaps " + reals(gaps)); lines.add("suggested_k " + suggested);
            double[] joining = tree.joiningHeights(); List<Integer> late = new ArrayList<>(); for (int i = 0; i < count; i++) late.add(i);
            late.sort(Comparator.<Integer>comparingDouble(i -> joining[i]).reversed().thenComparingInt(i -> i));
            List<String> lateNames = new ArrayList<>(); for (int i : late.subList(0, settings.listSize)) lateNames.add(idents[i] + ":" + real(joining[i]));
            lines.add("late_joiners " + String.join(" ", lateNames));
            int[] kinds = new int[3]; for (Agglomerative.Merge merge : tree.merges) { int leaves = (merge.a() < count ? 1 : 0) + (merge.b() < count ? 1 : 0); kinds[2 - leaves]++; }
            lines.add("merges leaf_leaf " + kinds[0] + " leaf_cluster " + kinds[1] + " cluster_cluster " + kinds[2] + " depth " + tree.depths[tree.root()]);
            int matches = matchCount(result.labelPartition); lines.add("label_cut k " + classes.length + " purity " + matches + "/" + count + " " + real((double) matches / count));
            lines.add("inconsistency depth " + settings.inconsistencyDepth);
            for (int step = count - settings.inconsistencyCount - 1; step < count - 1; step++) lines.add(inconsistencyLine(tree, step));
            for (int j = 0; j < settings.cutHeights.length; j++) { PartitionEvaluation cut = result.heightCuts.get(j); lines.add("cut height " + real(settings.cutHeights[j]) + " clusters " + cut.sizes.length + " " + cut.text()); }
            for (int j = 0; j < settings.cutCounts.length; j++) lines.add("cut k " + settings.cutCounts[j] + " " + result.countCuts.get(j).text());
            return lines;
        }
        LinkageResult resultOf(String method) { return results.stream().filter(result -> result.method.equals(method)).findFirst().orElse(null); }
        List<String> mstPart() {
            LinkageResult single = resultOf("single"); List<Agglomerative.Edge> edges = Agglomerative.minimumSpanningTree(distances);
            double total = 0.0; for (Agglomerative.Edge edge : edges) total += edge.weight();
            double[] weights = edges.stream().mapToDouble(Agglomerative.Edge::weight).sorted().toArray(); boolean heightsMatch = true;
            for (int step = 0; step < weights.length; step++) if (Math.abs(weights[step] - single.tree.heights[step]) > 0.000000001) heightsMatch = false;
            boolean[][] linked = new boolean[count][count]; for (Agglomerative.Edge edge : edges) linked[edge.parent()][edge.child()] = linked[edge.child()][edge.parent()] = true;
            int nearestEdges = 0; for (int i = 0; i < count; i++) if (linked[i][neighbors[i]]) nearestEdges++;
            List<String> lines = new ArrayList<>(List.of("mst total " + real(total) + " heights " + (heightsMatch ? "match" : "mismatch") + " nn_edges " + nearestEdges + "/" + count));
            List<Integer> edgeNumbers = new ArrayList<>(); for (int i = 0; i < edges.size(); i++) edgeNumbers.add(i);
            edgeNumbers.sort(Comparator.<Integer>comparingDouble(i -> edges.get(i).weight()).thenComparingInt(i -> i)); List<Agglomerative.Edge> ordered = edgeNumbers.stream().map(edges::get).toList();
            for (int position = 0; position < settings.cutCounts.length; position++) {
                int k = settings.cutCounts[position]; int[] component = connectedComponents(count, ordered.subList(0, count - k)), partition = single.countCuts.get(position).partition; boolean match = true;
                for (int i = 0; i < count; i++) for (int j = i + 1; j < count; j++) if ((component[i] == component[j]) != (partition[i] == partition[j])) match = false;
                lines.add("mst partition k " + k + " " + (match ? "match" : "mismatch"));
            }
            return lines;
        }
        List<String> comparePart() {
            List<String> lines = new ArrayList<>(List.of("compare linkage " + settings.compareLinkage + " k " + classes.length));
            for (String type : Distances.TYPES) {
                double[][] delta = Distances.matrix(vectors, type); Tree tree = new Tree(Agglomerative.cluster(delta, settings.compareLinkage), count); int[] partition = tree.cutInto(classes.length);
                double coefficient = Validation.correlation(pairValues(delta), pairValues(tree.cophenetic()));
                lines.add("metric " + type + " cophenetic " + real(coefficient) + " silhouette " + real(meanSilhouette(partition, delta)) + " ari " + ariText(labelAri(partition)));
            }
            return lines;
        }
        List<String> copheneticPart() {
            List<String> lines = new ArrayList<>(List.of("cophenetic_matrix", "linkage " + String.join(" ", settings.linkages)));
            for (LinkageResult first : results) { double[] values = new double[results.size()]; for (int r = 0; r < values.length; r++) values[r] = Validation.correlation(first.cophenetic, results.get(r).cophenetic); lines.add(first.method + " " + reals(values)); }
            return lines;
        }
        List<String> agreementPart() {
            List<String> lines = new ArrayList<>(List.of("agreement k " + classes.length, "linkage " + String.join(" ", settings.linkages)));
            for (LinkageResult first : results) { double[] values = new double[results.size()]; for (int r = 0; r < values.length; r++) values[r] = partitionAri(first.labelPartition, results.get(r).labelPartition).value(); lines.add(first.method + " " + reals(values)); }
            return lines;
        }
        List<String> summaryPart() {
            List<Integer> ranking = new ArrayList<>(); for (int r = 0; r < results.size(); r++) ranking.add(r);
            ranking.sort(Comparator.<Integer>comparingDouble(r -> fourDigit(results.get(r).correlation)).reversed().thenComparingInt(r -> r));
            List<String> lines = new ArrayList<>(List.of("summary", "cophenetic_ranking " + String.join(" ", ranking.stream().map(r -> results.get(r).method).toList())));
            for (int position = 0; position < settings.cutCounts.length; position++) {
                LinkageResult best = results.getFirst(); for (LinkageResult result : results) if (result.countCuts.get(position).ari.compareTo(best.countCuts.get(position).ari) > 0) best = result;
                lines.add("best_ari k " + settings.cutCounts[position] + " " + best.method + " " + ariText(best.countCuts.get(position).ari));
            }
            for (LinkageResult result : results) {
                int best = 0; for (int position = 1; position < settings.cutCounts.length; position++) if (fourDigit(result.countCuts.get(position).silhouette) > fourDigit(result.countCuts.get(best).silhouette)) best = position;
                lines.add("best_silhouette " + result.method + " k " + settings.cutCounts[best] + " " + real(result.countCuts.get(best).silhouette));
            }
            lines.add("selected " + chosen.method + " k " + kappa); return lines;
        }
        List<String> validationReport() {
            List<List<String>> parts = new ArrayList<>(List.of(dataPart(), correlationPart(), histogramPart())); for (LinkageResult result : results) parts.add(linkagePart(result));
            if (resultOf("single") != null) parts.add(mstPart()); parts.add(comparePart()); parts.add(copheneticPart()); parts.add(agreementPart()); parts.add(summaryPart()); return joinParts(parts);
        }
        double separation(List<Integer> first, List<Integer> second) {
            double best = Double.POSITIVE_INFINITY;
            for (int i : first) for (int j : second) best = Math.min(best, distances[i][j]);
            return best;
        }
        List<String> clusterLines(int g) {
            List<Integer> group = members.get(g); int size = group.size(), majorityClass = majority[g], majorityCount = table[g][majorityClass];
            double silhouette = 0.0; for (int i : group) silhouette += silhouettes[i]; silhouette /= size;
            double[] averages = new double[featureNames.length]; for (int f = 0; f < averages.length; f++) { double total = 0.0; for (int i : group) total += raw[i][f]; averages[f] = total / size; }
            int medoid = -1; double medoidSum = 0.0;
            for (int i : group) { double total = 0.0; for (int j : group) total += distances[i][j]; if (medoid < 0 || total < medoidSum) { medoid = i; medoidSum = total; } }
            int widestFirst = -1, widestSecond = -1;
            for (int position = 0; position < group.size(); position++) for (int later = position + 1; later < group.size(); later++) {
                int i = group.get(position), j = group.get(later);
                if (widestFirst < 0 || distances[i][j] > distances[widestFirst][widestSecond]) { widestFirst = i; widestSecond = j; }
            }
            String diameter = widestFirst < 0 ? "0.0000 - -" : pairText(widestFirst, widestSecond);
            int nearest = -1; double nearestSeparation = 0.0;
            for (int h = 0; h < kappa; h++) if (h != g) { double value = separation(group, members.get(h)); if (nearest < 0 || value < nearestSeparation) { nearest = h; nearestSeparation = value; } }
            return List.of("cluster " + (g + 1) + " size " + size + " silhouette " + real(silhouette) + " majority " + classes[majorityClass] + " purity " + majorityCount + "/" + size + " " + real((double) majorityCount / size),
                "  mean " + reals(averages), "  medoid " + idents[medoid] + " diameter " + diameter + " nearest " + (nearest + 1) + " separation " + real(nearestSeparation));
        }
        List<String> selectionPart() {
            List<String> lines = new ArrayList<>(List.of("selected linkage " + chosen.method + " k " + kappa + " ari " + ariText(selectedCut.ari) + " silhouette " + real(selectedCut.silhouette)));
            for (int g = 0; g < kappa; g++) lines.addAll(clusterLines(g)); return lines;
        }
        List<String> centroidPart() {
            double[][] centers = centroids(selected); List<String> lines = new ArrayList<>(List.of("centroid_distances"));
            for (int g = 0; g < centers.length; g++) { double[] values = new double[centers.length]; for (int h = 0; h < values.length; h++) values[h] = Math.sqrt(Distances.squared(centers[g], centers[h])); lines.add((g + 1) + " " + reals(values)); }
            return lines;
        }
        List<String> profilePart() {
            int nameWidth = Arrays.stream(featureNames).mapToInt(String::length).max().orElseThrow(); List<String> lines = new ArrayList<>(List.of("profile_bars"));
            for (int g = 0; g < kappa; g++) {
                List<Integer> group = members.get(g); lines.add("cluster " + (g + 1));
                for (int f = 0; f < featureNames.length; f++) {
                    double total = 0.0; for (int i : group) total += (raw[i][f] - means[f]) / deviations[f]; double zeta = total / group.size();
                    int length = Math.min(10, (int) Math.floor(Math.abs(zeta) * 4)); String bar = "#".repeat(length), blank = " ".repeat(10);
                    String left = zeta < 0 ? " ".repeat(10 - length) + bar : blank, right = zeta < 0 ? blank : bar + " ".repeat(10 - length);
                    lines.add(featureNames[f] + " ".repeat(nameWidth - featureNames[f].length()) + " " + left + "|" + right + " " + real(zeta));
                }
            }
            return lines;
        }
        List<String> contingencyPart() {
            List<String> lines = new ArrayList<>(List.of("contingency", "cluster " + String.join(" ", classes) + " total")); int[] totals = new int[classes.length];
            for (int g = 0; g < table.length; g++) { int total = 0; for (int t = 0; t < table[g].length; t++) { total += table[g][t]; totals[t] += table[g][t]; } lines.add((g + 1) + " " + integers(table[g]) + " " + total); }
            int matches = matchCount(selected); lines.add("total " + integers(totals) + " " + count); lines.add("purity " + matches + "/" + count + " " + real((double) matches / count)); return lines;
        }
        List<String> misplacedPart() {
            List<String> lines = new ArrayList<>(List.of("misplaced")); int misplaced = 0;
            for (int i = 0; i < count; i++) if (targets[i] != majority[selected[i] - 1]) { misplaced++; lines.add(idents[i] + " label " + labels[i] + " cluster " + selected[i] + " majority " + classes[majority[selected[i] - 1]]); }
            lines.add("count " + misplaced); return lines;
        }
        List<String> weakestPart() {
            List<Integer> order = new ArrayList<>(); for (int i = 0; i < count; i++) order.add(i); order.sort(Comparator.<Integer>comparingDouble(i -> silhouettes[i]).thenComparingInt(i -> i));
            List<String> lines = new ArrayList<>(List.of("weakest"));
            for (int i : order.subList(0, settings.listSize)) lines.add(idents[i] + " label " + labels[i] + " cluster " + selected[i] + " silhouette " + real(silhouettes[i])); return lines;
        }
        List<String> featurePart() {
            double[] ratios = new double[featureNames.length];
            for (int f = 0; f < ratios.length; f++) {
                double overall = 0.0; for (double[] vector : vectors) overall += vector[f]; overall /= count;
                double[] averages = new double[kappa];
                for (int g = 0; g < kappa; g++) { double total = 0.0; for (int i : members.get(g)) total += vectors[i][f]; averages[g] = total / members.get(g).size(); }
                double between = 0.0; for (int g = 0; g < kappa; g++) { double difference = averages[g] - overall; between += members.get(g).size() * difference * difference; }
                double within = 0.0; for (int i = 0; i < count; i++) { double difference = vectors[i][f] - averages[selected[i] - 1]; within += difference * difference; }
                ratios[f] = (between / (kappa - 1)) / (within / (count - kappa));
            }
            List<Integer> ranking = new ArrayList<>(); for (int f = 0; f < ratios.length; f++) ranking.add(f);
            ranking.sort(Comparator.<Integer>comparingDouble(f -> fourDigit(ratios[f])).reversed().thenComparingInt(f -> f));
            List<String> lines = new ArrayList<>(List.of("features")); for (int rank = 0; rank < ranking.size(); rank++) { int f = ranking.get(rank); lines.add((rank + 1) + " " + featureNames[f] + " f_ratio " + real(ratios[f])); } return lines;
        }
        String classCounts(Tree tree, int node) {
            int[] counts = new int[classes.length]; for (int i : tree.members.get(node)) counts[targets[i]]++;
            return String.join("/", Arrays.stream(counts).mapToObj(Integer::toString).toList());
        }
        List<String> topMergesPart() {
            Tree tree = chosen.tree; List<String> lines = new ArrayList<>(List.of("top_merges"));
            for (int step = count - settings.inconsistencyCount - 1; step < count - 1; step++) {
                Agglomerative.Merge merge = tree.merges.get(step);
                lines.add("step " + (step + 1) + " height " + real(merge.height()) + " a " + merge.a() + " " + tree.members.get(merge.a()).length + " " + classCounts(tree, merge.a()) + " b " + merge.b() + " " + tree.members.get(merge.b()).length + " " + classCounts(tree, merge.b()));
            }
            return lines;
        }
        List<String> dropFeaturePart() {
            List<String> lines = new ArrayList<>(List.of("drop_feature"));
            for (int f = 0; f < featureNames.length; f++) {
                double[][] reduced = new double[count][featureNames.length - 1];
                for (int i = 0; i < count; i++) { int position = 0; for (int g = 0; g < featureNames.length; g++) if (g != f) reduced[i][position++] = vectors[i][g]; }
                int[] partition = new Tree(Agglomerative.cluster(Distances.matrix(reduced, settings.distance), chosen.method), count).cutInto(kappa);
                lines.add(featureNames[f] + " ari_selected " + ariText(partitionAri(partition, selected)) + " ari_labels " + ariText(labelAri(partition)));
            }
            return lines;
        }
        int nearestCenter(double[] vector, double[][] centers) {
            int best = 0; double bestValue = Distances.squared(vector, centers[0]);
            for (int g = 1; g < centers.length; g++) { double value = Distances.squared(vector, centers[g]); if (value < bestValue) { best = g; bestValue = value; } }
            return best + 1;
        }
        List<String> refinementPart() {
            double[][] centers = centroids(selected); int[] previous = selected; int iterations = settings.refineIterations;
            for (int t = 1; t <= settings.refineIterations; t++) {
                int[] assignment = new int[count]; for (int i = 0; i < count; i++) assignment[i] = nearestCenter(vectors[i], centers);
                if (Arrays.equals(assignment, previous)) { iterations = t; break; }
                List<List<Integer>> groups = clusterMembers(assignment, kappa);
                for (int g = 0; g < kappa; g++) if (!groups.get(g).isEmpty()) centers[g] = centroid(groups.get(g).stream().map(i -> vectors[i]).toArray(double[][]::new));
                previous = assignment;
            }
            int[] refined = previous; int changed = 0; for (int i = 0; i < count; i++) if (selected[i] != refined[i]) changed++;
            int[] sizes = clusterMembers(refined, kappa).stream().mapToInt(List::size).toArray();
            return List.of("refinement max_iterations " + settings.refineIterations, "iterations " + iterations + " changed " + changed + " wss " + real(withinSum(selected)) + " -> " + real(withinSum(refined)),
                "sizes " + integers(sizes) + " silhouette " + real(meanSilhouette(refined, distances)), "ari_selected " + ariText(partitionAri(refined, selected)) + " ari_labels " + ariText(labelAri(refined)));
        }
        double[] jaccard(int[] samplePartition, int[] restricted) {
            int[][] table = Validation.contingency(Arrays.stream(restricted).map(number -> number - 1).toArray(), Arrays.stream(samplePartition).map(number -> number - 1).toArray(), kappa, maximum(samplePartition));
            int[] columns = new int[table[0].length]; for (int[] row : table) for (int h = 0; h < row.length; h++) columns[h] += row[h];
            double[] values = new double[kappa];
            for (int g = 0; g < kappa; g++) {
                int size = Arrays.stream(table[g]).sum(); if (size == 0) continue;
                long bestNumerator = 0, bestDenominator = 1;
                for (int h = 0; h < columns.length; h++) { long numerator = table[g][h], denominator = size + columns[h] - numerator; if (numerator * bestDenominator > bestNumerator * denominator) { bestNumerator = numerator; bestDenominator = denominator; } }
                values[g] = (double) bestNumerator / bestDenominator;
            }
            return values;
        }
        List<String> stabilityPart() {
            Minstd generator = new Minstd(settings.seed); int size = count * settings.percent / 100;
            double ariTotal = 0.0; double[] jaccardTotals = new double[kappa];
            List<String> lines = new ArrayList<>(List.of("stability replicates " + settings.replicates + " percent " + settings.percent + " seed " + settings.seed));
            for (int b = 1; b <= settings.replicates; b++) {
                int[] array = new int[count]; for (int i = 0; i < count; i++) array[i] = i;
                for (int t = 0; t < size; t++) { int j = t + (int) (generator.draw() % (count - t)), old = array[t]; array[t] = array[j]; array[j] = old; }
                int[] sample = Arrays.copyOf(array, size); Arrays.sort(sample); double[][] delta = new double[size][size];
                for (int u = 0; u < size; u++) for (int w = 0; w < size; w++) delta[u][w] = distances[sample[u]][sample[w]];
                int[] partition = new Tree(Agglomerative.cluster(delta, chosen.method), size).cutInto(kappa), restricted = Arrays.stream(sample).map(u -> selected[u]).toArray();
                Fraction ari = partitionAri(partition, restricted); double[] jaccard = jaccard(partition, restricted); ariTotal += ari.value(); for (int g = 0; g < kappa; g++) jaccardTotals[g] += jaccard[g];
                lines.add("replicate " + b + " size " + size + " ari " + ariText(ari) + " jaccard " + reals(jaccard));
            }
            for (int g = 0; g < kappa; g++) jaccardTotals[g] /= settings.replicates;
            lines.add("mean_ari " + real(ariTotal / settings.replicates)); lines.add("mean_jaccard " + reals(jaccardTotals)); return lines;
        }
        List<String> distanceMapPart() {
            String frame = "+" + "-".repeat(count) + "+"; List<String> lines = new ArrayList<>(List.of("distance_map " + chosen.method, frame));
            for (int u : chosen.tree.order) { StringBuilder row = new StringBuilder("|"); for (int w : chosen.tree.order) row.append("@%#*+=-:. ".charAt(histogramBin(distances[u][w], distanceMax))); lines.add(row.append('|').toString()); }
            lines.add(frame); return lines;
        }
        List<String> profilesReport() { return joinParts(List.of(selectionPart(), centroidPart(), profilePart(), contingencyPart(), misplacedPart(), weakestPart(), featurePart(), topMergesPart(), dropFeaturePart(), refinementPart(), stabilityPart(), distanceMapPart())); }
        void writeOutputs() throws IOException {
            Files.createDirectories(Path.of("output"));
            Dataset.write("linkage.csv", linkageTable()); Dataset.write("clusters.csv", clustersTable()); Dataset.write("dendrogram.txt", dendrogramReport()); Dataset.write("trees.txt", treesReport()); Dataset.write("validation.txt", validationReport()); Dataset.write("profiles.txt", profilesReport());
        }
    }

    public static void main(String[] args) throws IOException {
        Study study = new Study(Dataset.read());
        study.writeOutputs();
    }
}
