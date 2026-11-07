import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;

public class Main {
    static final long MODULUS = 2147483647L;
    static final String FEATURES_HEADER = "customer,recency,frequency,monetary,basket,categories,tenure,z_recency,z_frequency,z_monetary,z_basket,z_categories,z_tenure";
    static final String SEGMENTS_HEADER = "customer,segment,name,distance,other,other_distance,silhouette,recommend";
    static final class Minstd {
        long state;
        Minstd(long seed) { state = seed; }
        long draw() { state = state * 48271 % MODULUS; return state; }
    }
    record Improvement(int[] labels, int passes, int transfers, double sse) {}
    static final class Run {
        final String method;
        final int number;
        final int[] seeds;
        final LloydResult lloyd;
        final double lloydSse;
        final Improvement improved;
        Run(String method, int number, int[] seeds, List<double[]> points, int limit) {
            this.method = method; this.number = number; this.seeds = seeds;
            List<double[]> initial = new ArrayList<>();
            for (int seed : seeds) initial.add(points.get(seed));
            lloyd = KMeans.lloyd(points, initial, limit);
            lloydSse = KMeans.sse(points, lloyd.labels(), lloyd.centers());
            improved = improve(points, lloyd.labels(), seeds.length, limit);
        }
    }
    static final class Solution {
        final int k;
        final List<List<Integer>> members = new ArrayList<>();
        final int[] sizes, labels;
        final List<double[]> centers;
        final double sse;
        Solution(List<double[]> points, int[] original, int k) {
            this.k = k;
            for (int j = 0; j < k; j++) members.add(new ArrayList<>());
            for (int i = 0; i < original.length; i++) members.get(original[i]).add(i);
            members.sort(Comparator.<List<Integer>>comparingInt(List::size).reversed().thenComparingInt(List::getFirst));
            sizes = new int[k]; labels = new int[original.length];
            for (int j = 0; j < k; j++) {
                sizes[j] = members.get(j).size();
                for (int i : members.get(j)) labels[i] = j;
            }
            centers = KMeans.centers(points, labels, k);
            sse = KMeans.sse(points, labels, centers);
        }
    }
    static final class Candidate {
        final int k;
        final List<Run> runs, methodBests;
        final Run best;
        final Solution solution;
        double[] silhouettes;
        double silhouette, calinskiHarabasz, daviesBouldin, elbow;
        Double hartigan;
        int[] ruleNumbers;
        List<String> names;
        Candidate(int k, List<Run> runs, List<Run> methodBests, Run best, Solution solution) {
            this.k = k; this.runs = runs; this.methodBests = methodBests; this.best = best; this.solution = solution;
        }
    }
    static double[] nearestGaps(List<double[]> points, List<Integer> chosen) {
        double[] gaps = new double[points.size()];
        for (int i = 0; i < points.size(); i++) {
            gaps[i] = Double.POSITIVE_INFINITY;
            for (int j : chosen) gaps[i] = Math.min(gaps[i], KMeans.squaredDistance(points.get(i), points.get(j)));
        }
        return gaps;
    }
    static int[] seeds(String method, List<double[]> points, int k, int number, Minstd random) {
        List<Integer> chosen = new ArrayList<>();
        if (method.equals("forgy")) {
            while (chosen.size() < k) {
                int index = (int) (random.draw() % points.size());
                if (!chosen.contains(index)) chosen.add(index);
            }
        } else if (method.equals("maximin")) {
            double[] center = KMeans.meanPoint(points);
            List<Integer> order = new ArrayList<>();
            for (int i = 0; i < points.size(); i++) order.add(i);
            order.sort(Comparator.<Integer>comparingDouble(i -> KMeans.squaredDistance(points.get(i), center)).thenComparingInt(i -> i));
            chosen.add(order.get(number - 1));
            while (chosen.size() < k) {
                double[] gaps = nearestGaps(points, chosen);
                int best = 0;
                for (int i = 1; i < gaps.length; i++) if (gaps[i] > gaps[best]) best = i;
                chosen.add(best);
            }
        } else {
            chosen.add((int) (random.draw() % points.size()));
            while (chosen.size() < k) {
                double[] gaps = nearestGaps(points, chosen);
                double threshold = (random.draw() / (double) MODULUS) * Features.sum(gaps);
                double total = 0;
                int selected = -1;
                for (int i = 0; i < gaps.length; i++) {
                    total += gaps[i];
                    if (total > threshold) { selected = i; break; }
                }
                if (selected < 0) for (int i = 0; i < gaps.length; i++) if (gaps[i] > 0) selected = i;
                chosen.add(selected);
            }
        }
        return chosen.stream().mapToInt(Integer::intValue).toArray();
    }
    static Improvement improve(List<double[]> points, int[] original, int k, int limit) {
        int[] labels = original.clone(), sizes = KMeans.sizes(labels, k);
        List<double[]> centers = KMeans.centers(points, labels, k);
        int passes = 0, transfers = 0;
        boolean moved = true;
        while (moved && passes < limit) {
            moved = false; passes++;
            for (int i = 0; i < points.size(); i++) {
                int own = labels[i];
                if (sizes[own] == 1) continue;
                double removal = (sizes[own] / (double) (sizes[own] - 1)) * KMeans.squaredDistance(points.get(i), centers.get(own));
                int target = -1;
                double targetCost = 0;
                for (int q = 0; q < k; q++) if (q != own) {
                    double cost = (sizes[q] / (double) (sizes[q] + 1)) * KMeans.squaredDistance(points.get(i), centers.get(q));
                    if (target < 0 || cost < targetCost) { target = q; targetCost = cost; }
                }
                if (targetCost < removal) {
                    labels[i] = target; sizes[own]--; sizes[target]++;
                    centers.set(own, KMeans.center(points, labels, own));
                    centers.set(target, KMeans.center(points, labels, target));
                    transfers++; moved = true;
                }
            }
        }
        return new Improvement(labels, passes, transfers, KMeans.sse(points, labels, KMeans.centers(points, labels, k)));
    }
    static Run bestRun(List<Run> runs) {
        Run best = runs.getFirst();
        for (Run run : runs) if (Report.fourDecimal(run.improved.sse()) < Report.fourDecimal(best.improved.sse())) best = run;
        return best;
    }
    static double gini(List<Customer> customers) {
        long[] spends = customers.stream().mapToLong(customer -> customer.spend).sorted().toArray();
        long total = 0, weighted = 0;
        for (int i = 0; i < spends.length; i++) { total += spends[i]; weighted += (i + 1L) * spends[i]; }
        return (2 * weighted - (spends.length + 1L) * total) / (double) (spends.length * total);
    }
    static Map<String, Integer> categoryTotals(List<Customer> customers) {
        Map<String, Integer> totals = new TreeMap<>();
        for (Customer customer : customers) for (var entry : customer.categorySpend.entrySet()) totals.merge(entry.getKey(), entry.getValue(), Integer::sum);
        return totals;
    }
    static List<String> ranking(Map<String, Integer> totals) {
        return totals.keySet().stream().filter(category -> totals.get(category) > 0)
            .sorted(Comparator.<String>comparingInt(totals::get).reversed().thenComparing(Comparator.naturalOrder())).toList();
    }
    static String yesNo(boolean flag) { return flag ? "yes" : "no"; }
    static String ints(int[] values) { return String.join(" ", Arrays.stream(values).mapToObj(Integer::toString).toList()); }
    static List<String> blocks(List<List<String>> blocks) {
        List<String> lines = new ArrayList<>();
        for (List<String> block : blocks) { if (!lines.isEmpty()) lines.add(""); lines.addAll(block); }
        return lines;
    }
    static final class Analysis {
        final Params params;
        final TransactionData data;
        final List<NamingRule> rules;
        final Minstd random;
        final List<Order> referenceOrders;
        final Map<String, List<Order>> customerOrders;
        final List<Customer> customers;
        final Map<String, Integer> numbers = new HashMap<>();
        final int n;
        final double[] means, sds;
        final List<double[]> points = new ArrayList<>();
        final List<Candidate> candidates = new ArrayList<>();
        final Map<String, Integer> votes = new LinkedHashMap<>();
        Candidate chosen;
        int finalVotes, k;
        int[] labels, other, scoresR, scoresF, scoresM;
        String[] codes;
        List<double[]> centers;
        List<String> names, categoryNames;
        double[] silhouettes, distances, otherDistances, segmentSse;
        int totalSpend;
        Map<String, Integer> overallCategories;
        final List<List<Customer>> segmentCustomers = new ArrayList<>();
        final List<Map<String, Integer>> segmentCategories = new ArrayList<>();
        final List<List<String>> rankings = new ArrayList<>();
        int[] segmentSpends;
        double[][] jaccards;
        Analysis(Params params, TransactionData data, List<NamingRule> rules) {
            this.params = params; this.data = data; this.rules = rules; random = new Minstd(params.seed());
            referenceOrders = Transactions.groupOrders(data.validRows, 1, params.referenceDay());
            customerOrders = Transactions.byCustomer(referenceOrders);
            customers = Features.eligible(referenceOrders, params.referenceDay()); n = customers.size();
            List<double[]> transformed = new ArrayList<>();
            for (int i = 0; i < n; i++) { numbers.put(customers.get(i).id, i); transformed.add(customers.get(i).transformed()); }
            Standardization standard = Features.standardization(transformed); means = standard.means(); sds = standard.sds();
            for (double[] values : transformed) points.add(Features.standardize(values, means, sds));
        }
        String ids(int[] indices) {
            List<String> values = new ArrayList<>();
            for (int index : indices) values.add(customers.get(index).id);
            return String.join(" ", values);
        }
        Candidate candidate(int count) { return candidates.get(count - params.kMin()); }
        void analyze() {
            for (int count = params.kMin(); count <= params.kMax(); count++) candidates.add(search(count));
            evaluate(); chooseK(); describeFinal(); subsamples();
        }
        Candidate search(int count) {
            List<Run> runs = new ArrayList<>(), bests = new ArrayList<>();
            for (String method : params.methods()) {
                List<Run> methodRuns = new ArrayList<>();
                for (int number = 1; number <= params.restarts(); number++)
                    methodRuns.add(new Run(method, number, seeds(method, points, count, number, random), points, params.maxIterations()));
                runs.addAll(methodRuns); bests.add(bestRun(methodRuns));
            }
            Run best = bestRun(bests);
            return new Candidate(count, runs, bests, best, new Solution(points, best.improved.labels(), count));
        }
        void evaluate() {
            double[][] table = Validation.distanceTable(points);
            double first = candidates.getFirst().solution.sse, last = candidates.getLast().solution.sse;
            for (int position = 0; position < candidates.size(); position++) {
                Candidate c = candidates.get(position); Solution s = c.solution;
                c.silhouettes = Validation.silhouettes(table, s.labels, s.sizes);
                c.silhouette = Features.sum(c.silhouettes) / n;
                c.calinskiHarabasz = Validation.calinskiHarabasz(points, s.centers, s.sizes, s.sse);
                c.daviesBouldin = Validation.daviesBouldin(points, s.labels, s.centers, s.sizes);
                c.elbow = Validation.elbow(c.k, params.kMin(), params.kMax(), s.sse, first, last);
                if (c.k < params.kMax()) c.hartigan = Validation.hartigan(s.sse, candidates.get(position + 1).solution.sse, n, c.k);
                c.ruleNumbers = new int[c.k]; c.names = new ArrayList<>();
                Map<Integer, Integer> repeats = new HashMap<>();
                for (int j = 0; j < c.k; j++) {
                    int rule = Profiles.ruleNumber(rules, s.centers.get(j)); c.ruleNumbers[j] = rule;
                    int repeat = repeats.merge(rule, 1, Integer::sum);
                    c.names.add(rules.get(rule - 1).name() + (repeat == 1 ? "" : "_" + repeat));
                }
            }
        }
        void chooseK() {
            Candidate elbow = candidates.get(1), silhouette = candidates.getFirst(), ch = silhouette, db = silhouette;
            int hartigan = params.kMax(); boolean found = false;
            for (int i = 0; i < candidates.size(); i++) {
                Candidate c = candidates.get(i);
                if (i > 0 && i < candidates.size() - 1 && Report.fourDecimal(c.elbow) > Report.fourDecimal(elbow.elbow)) elbow = c;
                if (Report.fourDecimal(c.silhouette) > Report.fourDecimal(silhouette.silhouette)) silhouette = c;
                if (Report.fourDecimal(c.calinskiHarabasz) > Report.fourDecimal(ch.calinskiHarabasz)) ch = c;
                if (Report.fourDecimal(c.daviesBouldin) < Report.fourDecimal(db.daviesBouldin)) db = c;
                if (!found && c.hartigan != null && c.hartigan <= 10) { hartigan = c.k; found = true; }
            }
            votes.put("elbow", elbow.k); votes.put("silhouette", silhouette.k); votes.put("calinski_harabasz", ch.k);
            votes.put("davies_bouldin", db.k); votes.put("hartigan", hartigan);
            chosen = candidates.getFirst(); finalVotes = -1;
            for (Candidate c : candidates) {
                int count = 0; for (int vote : votes.values()) if (vote == c.k) count++;
                if (count > finalVotes || count == finalVotes && Report.fourDecimal(c.silhouette) > Report.fourDecimal(chosen.silhouette)) {
                    chosen = c; finalVotes = count;
                }
            }
        }
        void describeFinal() {
            Solution s = chosen.solution; k = s.k; labels = s.labels; centers = s.centers; names = chosen.names; silhouettes = chosen.silhouettes;
            distances = new double[n]; otherDistances = new double[n]; other = new int[n];
            scoresR = new int[n]; scoresF = new int[n]; scoresM = new int[n]; codes = new String[n];
            for (int i = 0; i < n; i++) {
                int nearest = -1;
                for (int j = 0; j < k; j++) if (j != labels[i] && (nearest < 0 || KMeans.squaredDistance(points.get(i), centers.get(j)) < KMeans.squaredDistance(points.get(i), centers.get(nearest)))) nearest = j;
                distances[i] = Math.sqrt(KMeans.squaredDistance(points.get(i), centers.get(labels[i])));
                other[i] = nearest; otherDistances[i] = Math.sqrt(KMeans.squaredDistance(points.get(i), centers.get(nearest)));
                Customer customer = customers.get(i); int older = 0, fewer = 0, smaller = 0;
                for (Customer peer : customers) {
                    if (peer.recency > customer.recency) older++;
                    if (peer.frequency < customer.frequency) fewer++;
                    if (peer.spend < customer.spend) smaller++;
                }
                scoresR[i] = 1 + 5 * older / n; scoresF[i] = 1 + 5 * fewer / n; scoresM[i] = 1 + 5 * smaller / n;
                codes[i] = "" + scoresR[i] + scoresF[i] + scoresM[i]; totalSpend += customer.spend;
            }
            overallCategories = categoryTotals(customers); categoryNames = new ArrayList<>(overallCategories.keySet());
            segmentSpends = new int[k]; segmentSse = new double[k];
            for (int j = 0; j < k; j++) {
                List<Customer> group = new ArrayList<>();
                for (int i : s.members.get(j)) { group.add(customers.get(i)); segmentSpends[j] += customers.get(i).spend; segmentSse[j] += KMeans.squaredDistance(points.get(i), centers.get(j)); }
                segmentCustomers.add(group); Map<String, Integer> totals = categoryTotals(group);
                segmentCategories.add(totals); rankings.add(ranking(totals));
            }
        }
        void subsamples() {
            int size = n * params.subsamplePercent() / 100; jaccards = new double[k][params.subsamples()];
            for (int b = 0; b < params.subsamples(); b++) {
                int[] order = new int[n]; for (int i = 0; i < n; i++) order[i] = i;
                for (int t = 0; t < size; t++) { int j = t + (int) (random.draw() % (n - t)); int swap = order[t]; order[t] = order[j]; order[j] = swap; }
                int[] sample = Arrays.copyOf(order, size); Arrays.sort(sample);
                List<double[]> subset = new ArrayList<>(); for (int i : sample) subset.add(points.get(i));
                int[] sampledLabels = KMeans.lloyd(subset, centers, params.maxIterations()).labels();
                for (int segment = 0; segment < k; segment++) for (int j = 0; j < k; j++) {
                    int both = 0, either = 0;
                    for (int t = 0; t < size; t++) {
                        boolean member = labels[sample[t]] == segment, assigned = sampledLabels[t] == j;
                        if (member && assigned) both++; if (member || assigned) either++;
                    }
                    if (either > 0) jaccards[segment][b] = Math.max(jaccards[segment][b], both / (double) either);
                }
            }
        }
        String recommendation(int i) {
            for (String category : rankings.get(labels[i])) if (customers.get(i).categorySpend.getOrDefault(category, 0) <= 0) return category;
            return "-";
        }
        List<String> featuresLines() {
            List<String> lines = new ArrayList<>(List.of(FEATURES_HEADER));
            for (int i = 0; i < n; i++) {
                Customer c = customers.get(i);
                List<String> fields = new ArrayList<>(List.of(c.id, "" + c.recency, "" + c.frequency, Report.amount(c.spend), Report.real(c.basket), "" + c.categories, "" + c.tenure));
                for (double value : points.get(i)) fields.add(Report.real(value)); lines.add(String.join(",", fields));
            }
            return lines;
        }
        String runSummary(Run run) { return run.method + " restart " + run.number + " sse " + Report.real(run.improved.sse()); }
        String runLine(Run run) {
            return "run " + run.method + " " + run.number + " seeds " + ids(run.seeds) + " iterations " + run.lloyd.iterations()
                + " converged " + yesNo(run.lloyd.converged()) + " reseeds " + run.lloyd.reseeds() + " sse " + Report.real(run.lloydSse)
                + " passes " + run.improved.passes() + " transfers " + run.improved.transfers() + " refined " + Report.real(run.improved.sse());
        }
        List<String> runsLines() {
            List<List<String>> blocks = new ArrayList<>();
            for (Candidate c : candidates) {
                List<String> lines = new ArrayList<>(List.of("k " + c.k));
                for (Run run : c.runs) lines.add(runLine(run));
                for (Run run : c.methodBests) lines.add("best " + runSummary(run));
                lines.add("chosen " + runSummary(c.best)); lines.add("sizes " + ints(c.solution.sizes)); blocks.add(lines);
            }
            return blocks(blocks);
        }
        List<String> selectionLines() {
            List<String> indices = new ArrayList<>(List.of("indices")), voteLines = new ArrayList<>(List.of("votes"));
            List<String> segments = new ArrayList<>(List.of("segments")), stability = new ArrayList<>(List.of("stability"));
            for (int position = 0; position < candidates.size(); position++) {
                Candidate c = candidates.get(position);
                indices.add("k=" + c.k + " sse " + Report.real(c.solution.sse) + " elbow " + Report.real(c.elbow) + " silhouette " + Report.real(c.silhouette)
                    + " calinski_harabasz " + Report.real(c.calinskiHarabasz) + " davies_bouldin " + Report.real(c.daviesBouldin) + " hartigan " + (c.hartigan == null ? "-" : Report.real(c.hartigan)));
                List<String> parts = new ArrayList<>(); for (int j = 0; j < c.k; j++) parts.add(c.names.get(j) + ":" + c.solution.sizes[j]);
                segments.add("k=" + c.k + " " + String.join(" ", parts));
                parts = new ArrayList<>(List.of("k=" + c.k));
                for (int i = 0; i < c.methodBests.size(); i++) for (int j = i + 1; j < c.methodBests.size(); j++) {
                    Run a = c.methodBests.get(i), b = c.methodBests.get(j);
                    parts.add(a.method + ":" + b.method + " " + Report.real(Validation.ari(a.improved.labels(), b.improved.labels())));
                }
                parts.add("final");
                for (Run run : c.methodBests) parts.add(run.method + " " + Report.real(Validation.ari(run.improved.labels(), c.solution.labels)));
                parts.add(position + 1 < candidates.size() ? "next " + Report.real(Validation.ari(c.solution.labels, candidates.get(position + 1).solution.labels)) : "next -");
                stability.add(String.join(" ", parts));
            }
            for (var entry : votes.entrySet()) voteLines.add(entry.getKey() + " k=" + entry.getValue());
            voteLines.add("chosen k=" + chosen.k + " votes " + finalVotes);
            return blocks(List.of(indices, voteLines, segments, stability));
        }
        List<String> segmentsLines() {
            List<String> lines = new ArrayList<>(List.of(SEGMENTS_HEADER));
            for (int i = 0; i < n; i++) lines.add(String.join(",", customers.get(i).id, "" + (labels[i] + 1), names.get(labels[i]), Report.real(distances[i]),
                "" + (other[i] + 1), Report.real(otherDistances[i]), Report.real(silhouettes[i]), recommendation(i)));
            return lines;
        }
        String medianLine(List<Customer> group) {
            int index = (group.size() - 1) / 2;
            int recency = group.stream().mapToInt(c -> c.recency).sorted().toArray()[index];
            int frequency = group.stream().mapToInt(c -> c.frequency).sorted().toArray()[index];
            int spend = group.stream().mapToInt(c -> c.spend).sorted().toArray()[index];
            double basket = group.stream().mapToDouble(c -> c.basket).sorted().toArray()[index];
            int categories = group.stream().mapToInt(c -> c.categories).sorted().toArray()[index];
            int tenure = group.stream().mapToInt(c -> c.tenure).sorted().toArray()[index];
            return "  median recency " + recency + " frequency " + frequency + " monetary " + Report.amount(spend) + " basket " + Report.real(basket) + " categories " + categories + " tenure " + tenure;
        }
        String related(List<Integer> members, int count) {
            if (count < params.kMin() || count > params.kMax()) return "k=" + count + " -";
            int[] counts = new int[count], related = candidate(count).solution.labels;
            for (int i : members) counts[related[i]]++;
            int best = 0; for (int i = 1; i < count; i++) if (counts[i] > counts[best]) best = i;
            return "k=" + count + " segment " + (best + 1) + " shared " + counts[best];
        }
        String cadenceLine(List<Customer> group) {
            List<Double> gaps = new ArrayList<>(); int overdue = 0;
            for (Customer c : group) if (c.frequency >= 2) {
                int active = c.tenure - c.recency, intervals = c.frequency - 1; gaps.add(active / (double) intervals);
                if (c.recency * intervals > params.overdueFactor() * active) overdue++;
            }
            return "  cadence customers " + gaps.size() + " mean_gap " + (gaps.isEmpty() ? "-" : Report.real(Features.mean(gaps.stream().mapToDouble(Double::doubleValue).toArray()))) + " overdue " + overdue;
        }
        String orderSizesLine(List<Customer> group) {
            int[] bins = new int[params.orderBins().length + 1];
            for (Customer c : group) for (Order order : c.orders) { int bin = 0; for (int bound : params.orderBins()) if (order.net >= bound * 100) bin++; bins[bin]++; }
            return "  order_sizes " + ints(bins);
        }
        String returnsLine(List<Customer> group) {
            int gross = 0, returned = 0, cancelled = 0;
            for (Customer c : group) for (Order order : customerOrders.get(c.id)) {
                if (!order.valid()) cancelled++;
                for (Transaction row : order.rows) { if (row.amount() > 0) gross += row.amount(); else if (row.amount() < 0) returned -= row.amount(); }
            }
            return "  returns rate " + Report.real(returned / (double) gross) + " returned " + Report.amount(returned) + " cancelled " + cancelled;
        }
        String rfmLine(List<Integer> members) {
            int r = 0, f = 0, m = 0; Map<String, Integer> counts = new TreeMap<>();
            for (int i : members) { r += scoresR[i]; f += scoresF[i]; m += scoresM[i]; counts.merge(codes[i], 1, Integer::sum); }
            String mode = counts.keySet().iterator().next();
            for (String code : counts.keySet()) if (counts.get(code) > counts.get(mode)) mode = code;
            return "  rfm r " + Report.real(r / (double) members.size()) + " f " + Report.real(f / (double) members.size()) + " m " + Report.real(m / (double) members.size()) + " mode " + mode + " " + counts.get(mode);
        }
        String categoriesLine(int segment) {
            List<String> parts = new ArrayList<>(List.of("  categories")); int added = 0;
            for (String category : rankings.get(segment)) {
                if (added++ >= params.topCategories()) break;
                double share = segmentCategories.get(segment).get(category) / (double) segmentSpends[segment];
                double lift = share / (overallCategories.get(category) / (double) totalSpend);
                parts.add(category); parts.add(Report.real(share)); parts.add(Report.real(lift));
            }
            return String.join(" ", parts);
        }
        String outliersLine(List<Integer> members) {
            List<String> outliers = new ArrayList<>();
            if (members.size() >= 2) {
                double[] values = members.stream().mapToDouble(i -> distances[i]).toArray();
                double limit = Features.mean(values) + params.outlierSd() * Features.sampleSd(values);
                for (int i : members) if (distances[i] > limit) outliers.add(customers.get(i).id);
            }
            List<String> parts = new ArrayList<>(List.of("  outliers", "" + outliers.size())); parts.addAll(outliers); return String.join(" ", parts);
        }
        List<String> segmentProfile(int segment) {
            List<Integer> members = chosen.solution.members.get(segment); List<Customer> group = segmentCustomers.get(segment);
            int size = members.size(), spend = segmentSpends[segment]; double[] center = centers.get(segment);
            List<String> lines = new ArrayList<>(List.of("segment " + (segment + 1) + " " + names.get(segment) + " rule " + chosen.ruleNumbers[segment]
                + " size " + size + " share " + Report.real(size / (double) n) + " revenue " + Report.amount(spend) + " revenue_share " + Report.real(spend / (double) totalSpend)));
            lines.add("  center " + Report.reals(center));
            double[] values = Profiles.originalScale(center, means, sds); List<String> parts = new ArrayList<>();
            for (int f = 0; f < 6; f++) parts.add(Features.NAMES.get(f) + " " + Report.real(values[f])); lines.add("  value " + String.join(" ", parts));
            List<Integer> order = new ArrayList<>(); for (int f = 0; f < 6; f++) order.add(f);
            order.sort(Comparator.<Integer>comparingDouble(f -> -Math.abs(center[f])).thenComparingInt(f -> f)); parts.clear();
            for (int f : order.subList(0, 2)) parts.add((center[f] > 0 ? "high_" : "low_") + Features.NAMES.get(f)); lines.add("  traits " + String.join(" ", parts));
            lines.add(medianLine(group)); lines.add("  related " + related(members, k - 1) + " " + related(members, k + 1));
            List<Integer> top = new ArrayList<>(members); top.sort(Comparator.<Integer>comparingInt(i -> customers.get(i).spend).reversed().thenComparingInt(i -> i));
            parts = new ArrayList<>(List.of("  top_customers"));
            for (int i : top.subList(0, Math.min(top.size(), params.topCustomers()))) { parts.add(customers.get(i).id); parts.add(Report.amount(customers.get(i).spend)); }
            lines.add(String.join(" ", parts)); lines.add(cadenceLine(group)); lines.add(orderSizesLine(group));
            lines.add("  sse " + Report.real(segmentSse[segment]) + " share " + Report.real(segmentSse[segment] / chosen.solution.sse));
            lines.add("  gini " + Report.real(gini(group))); lines.add(returnsLine(group));
            double[] sil = members.stream().mapToDouble(i -> silhouettes[i]).toArray(); int negative = 0; for (double value : sil) if (value < 0) negative++;
            lines.add("  silhouette " + Report.real(Features.mean(sil)) + " negative " + negative);
            lines.add(rfmLine(members)); lines.add(categoriesLine(segment)); lines.add(outliersLine(members)); return lines;
        }
        String segmentNumbers() { int[] values = new int[k]; for (int j = 0; j < k; j++) values[j] = j + 1; return ints(values); }
        List<String> profilesLines() {
            List<List<String>> groups = new ArrayList<>();
            groups.add(List.of("segments k=" + k + " customers " + n + " revenue " + Report.amount(totalSpend) + " gini " + Report.real(gini(customers))));
            for (int j = 0; j < k; j++) groups.add(segmentProfile(j));
            List<String> mix = new ArrayList<>(List.of("category_mix " + segmentNumbers()));
            for (String category : categoryNames) {
                double[] shares = new double[k]; for (int j = 0; j < k; j++) shares[j] = segmentCategories.get(j).getOrDefault(category, 0) / (double) segmentSpends[j];
                mix.add(category + " " + Report.reals(shares));
            }
            groups.add(mix); List<String> recency = new ArrayList<>(List.of("rfm_recency " + segmentNumbers()));
            for (int score = 5; score >= 1; score--) { int[] counts = new int[k]; for (int i = 0; i < n; i++) if (scoresR[i] == score) counts[labels[i]]++; recency.add("r=" + score + " " + ints(counts)); }
            int[] numericCodes = Arrays.stream(codes).mapToInt(Integer::parseInt).toArray();
            recency.add("ari rfm_codes " + Report.real(Validation.ari(numericCodes, labels))); groups.add(recency);
            List<String> centerLines = new ArrayList<>(List.of("center_distances"));
            for (int j = 0; j < k; j++) {
                double[] values = new double[k]; for (int q = 0; q < k; q++) values[q] = Math.sqrt(KMeans.squaredDistance(centers.get(j), centers.get(q)));
                centerLines.add((j + 1) + " " + Report.reals(values));
            }
            groups.add(centerLines); return blocks(groups);
        }
        List<String> robustnessLines() {
            List<String> sample = new ArrayList<>(List.of("subsamples " + params.subsamples() + " size " + n * params.subsamplePercent() / 100));
            for (int j = 0; j < k; j++) sample.add("segment " + (j + 1) + " " + names.get(j) + " mean_jaccard " + Report.real(Features.mean(jaccards[j])) + " min_jaccard " + Report.real(Arrays.stream(jaccards[j]).min().orElseThrow()));
            List<String> ablation = new ArrayList<>(List.of("ablation"));
            for (int f = 0; f < 6; f++) {
                List<double[]> subset = new ArrayList<>();
                for (double[] point : points) { double[] reduced = new double[5]; int position = 0; for (int q = 0; q < 6; q++) if (q != f) reduced[position++] = point[q]; subset.add(reduced); }
                int[] seed = seeds("maximin", subset, k, 1, random); Run run = new Run("maximin", 1, seed, subset, params.maxIterations());
                ablation.add("without " + Features.NAMES.get(f) + " seeds " + ids(seed) + " iterations " + run.lloyd.iterations() + " converged " + yesNo(run.lloyd.converged())
                    + " transfers " + run.improved.transfers() + " sse " + Report.real(run.improved.sse()) + " ari " + Report.real(Validation.ari(run.improved.labels(), labels)));
            }
            List<Integer> members = chosen.solution.members.getFirst(); List<double[]> subset = new ArrayList<>(); for (int i : members) subset.add(points.get(i));
            int[] seed = seeds("maximin", subset, 2, 1, random); Run run = new Run("maximin", 1, seed, subset, params.maxIterations()); Solution parts = new Solution(subset, run.improved.labels(), 2);
            int[] originalSeeds = Arrays.stream(seed).map(members::get).toArray();
            List<String> drilldown = new ArrayList<>(List.of("drilldown segment 1 " + names.getFirst() + " size " + members.size() + " seeds " + ids(originalSeeds)
                + " iterations " + run.lloyd.iterations() + " converged " + yesNo(run.lloyd.converged()) + " transfers " + run.improved.transfers(),
                "sse before " + Report.real(segmentSse[0]) + " after " + Report.real(run.improved.sse()) + " gain " + Report.real(segmentSse[0] - run.improved.sse())));
            for (int j = 0; j < 2; j++) drilldown.add("part " + (j + 1) + " size " + parts.sizes[j] + " center " + Report.reals(parts.centers.get(j)));
            return blocks(List.of(sample, ablation, drilldown));
        }
        List<String> periodLines() {
            int day = params.referenceDay(), days = params.periodDays(); List<String> lines = new ArrayList<>(List.of("periods " + params.periods() + " days " + days));
            for (int q = 1; q <= params.periods(); q++) {
                int first = day - q * days + 1, last = day - (q - 1) * days;
                int[] revenue = new int[k], active = new int[k], acquired = new int[k];
                for (int i = 0; i < n; i++) {
                    Customer c = customers.get(i); int label = labels[i]; boolean bought = false;
                    for (Order order : c.orders) if (order.day >= first && order.day <= last) { revenue[label] += order.net; bought = true; }
                    if (bought) active[label]++; if (day - c.tenure >= first && day - c.tenure <= last) acquired[label]++;
                }
                List<String> parts = new ArrayList<>(List.of("period " + q + " days " + first + " " + last + " revenue"));
                for (int value : revenue) parts.add(Report.amount(value)); parts.add("active"); parts.add(ints(active)); parts.add("acquired"); parts.add(ints(acquired)); lines.add(String.join(" ", parts));
            }
            return lines;
        }
        List<String> migrationLines() {
            int day = params.snapshotDay(); Map<String, Integer> snapshot = new TreeMap<>();
            for (Customer c : Features.eligible(Transactions.groupOrders(data.validRows, 1, day), day)) {
                double[] point = Features.standardize(c.transformed(), means, sds); int best = 0;
                for (int j = 1; j < k; j++) if (KMeans.squaredDistance(point, centers.get(j)) < KMeans.squaredDistance(point, centers.get(best))) best = j;
                snapshot.put(c.id, best);
            }
            int[][] table = new int[k + 1][k]; int stayed = 0, fresh = 0, lost = 0; List<String> moved = new ArrayList<>();
            for (int i = 0; i < n; i++) {
                Integer origin = snapshot.get(customers.get(i).id); int label = labels[i];
                if (origin == null) { table[k][label]++; fresh++; }
                else { table[origin][label]++; if (origin == label) stayed++; else moved.add(customers.get(i).id + " " + (origin + 1) + " " + (label + 1)); }
            }
            for (String id : snapshot.keySet()) if (!numbers.containsKey(id)) lost++;
            List<String> lines = new ArrayList<>(List.of("migration day " + day + " customers " + snapshot.size(), "from\\to " + segmentNumbers()));
            for (int j = 0; j <= k; j++) lines.add((j == k ? "none" : "" + (j + 1)) + " " + ints(table[j]));
            lines.add("moved_customers"); lines.addAll(moved); lines.add("stayed " + stayed + " moved " + moved.size() + " new " + fresh + " lost " + lost); return lines;
        }
        List<String> outcomeLines() {
            int first = params.referenceDay() + 1, last = params.referenceDay() + params.outcomeDays();
            Map<String, List<Order>> purchases = Transactions.byCustomer(Transactions.groupOrders(data.validRows, first, last).stream().filter(Order::valid).toList());
            List<String> lines = new ArrayList<>(List.of("outcome days " + first + " " + last));
            for (int j = 0; j < k; j++) {
                int buyers = 0, spend = 0, size = segmentCustomers.get(j).size();
                for (Customer c : segmentCustomers.get(j)) if (purchases.containsKey(c.id)) { buyers++; for (Order order : purchases.get(c.id)) spend += order.net; }
                lines.add("segment " + (j + 1) + " " + names.get(j) + " size " + size + " buyers " + buyers + " rate " + Report.real(buyers / (double) size)
                    + " revenue " + Report.amount(spend) + " per_customer " + Report.real((spend / 100.0) / size));
            }
            int outsiders = 0, spend = 0;
            for (var entry : purchases.entrySet()) if (!numbers.containsKey(entry.getKey())) { outsiders++; for (Order order : entry.getValue()) spend += order.net; }
            lines.add("unsegmented buyers " + outsiders + " revenue " + Report.amount(spend)); return lines;
        }
        List<String> summaryLines() {
            int used = 0, returned = 0, later = 0, valid = 0;
            for (Transaction row : data.validRows) if (row.day() <= params.referenceDay()) { used++; if (row.amount() < 0) returned++; } else later++;
            for (Order order : referenceOrders) if (order.valid()) valid++;
            List<String> excluded = data.customers.stream().filter(id -> !numbers.containsKey(id)).toList();
            List<String> dataLines = List.of("rows " + data.rowCount + " duplicates " + data.duplicates + " zero " + data.free + " used " + used + " returns " + returned + " later " + later,
                "orders " + referenceOrders.size() + " valid " + valid + " cancelled " + (referenceOrders.size() - valid),
                "customers " + data.customers.size() + " clustered " + n + " excluded " + excluded.size(), "excluded_ids " + (excluded.isEmpty() ? "-" : String.join(" ", excluded)));
            List<String> categoryLines = new ArrayList<>();
            for (String category : categoryNames) {
                int buyers = 0; for (Customer c : customers) if (c.categorySpend.getOrDefault(category, 0) > 0) buyers++;
                int total = overallCategories.get(category); categoryLines.add("category " + category + " revenue " + Report.amount(total) + " share " + Report.real(total / (double) totalSpend) + " customers " + buyers);
            }
            List<String> features = new ArrayList<>(), correlations = new ArrayList<>(List.of("correlation " + String.join(" ", Features.NAMES)));
            for (int f = 0; f < 6; f++) {
                double[] column = new double[n]; for (int i = 0; i < n; i++) column[i] = customers.get(i).values()[f];
                features.add("feature " + Features.NAMES.get(f) + " transform " + (Features.SQRT[f] ? "sqrt" : "none") + " raw_mean " + Report.real(Features.mean(column))
                    + " raw_sd " + Report.real(Features.sampleSd(column)) + " mean " + Report.real(means[f]) + " sd " + Report.real(sds[f]));
                double[] values = new double[6]; for (int q = 0; q < 6; q++) values[q] = Features.correlation(points, f, q);
                correlations.add(Features.NAMES.get(f) + " " + Report.reals(values));
            }
            return blocks(List.of(dataLines, categoryLines, features, correlations));
        }
    }
    public static void main(String[] args) throws Exception {
        Analysis analysis = new Analysis(Transactions.readParams("input/params.txt"), Transactions.read("input/transactions.csv"), Profiles.read("input/segment_rules.txt"));
        analysis.analyze(); Map<String, List<String>> files = new LinkedHashMap<>();
        files.put("features.csv", analysis.featuresLines()); files.put("runs.txt", analysis.runsLines()); files.put("selection.txt", analysis.selectionLines());
        files.put("segments.csv", analysis.segmentsLines()); files.put("profiles.txt", analysis.profilesLines()); files.put("robustness.txt", analysis.robustnessLines());
        files.put("tracking.txt", blocks(List.of(analysis.periodLines(), analysis.migrationLines(), analysis.outcomeLines()))); files.put("summary.txt", analysis.summaryLines());
        Report.writeFiles(files);
    }
}
