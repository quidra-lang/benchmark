import java.util.*;
import java.math.BigDecimal;
import java.io.IOException;

public final class Main {
    static List<Dataset.Point> points;
    static Dataset.Params params;
    static Map<Integer, Em.Model> initial;
    static int[] ks;
    static String[] types;
    static List<Summary> models = new ArrayList<>();
    static Map<Integer, Kmeans.Run> kmeans = new HashMap<>();
    static Summary selected;
    static final class Summary {
        int k, typeIndex, p, settled, largest;
        String type;
        Em.Run run;
        int[] assignment, sizes;
        double bic, aic, icl, entropy, increase;
        List<Integer> violations = new ArrayList<>();
    }
    record Metrics(double silhouette, double ch, double db, double[] cluster) {}
    record Ari(long numerator, long denominator) {
        String text() {
            return numerator + "/" + denominator + " " + Report.f((double)numerator / denominator);
        }
    }
    static String f(double value) {
        return Report.f(value);
    }
    static String ints(int[] values, boolean oneBased) {
        List<String> words = new ArrayList<>();
        for (int value : values)
            words.add(Integer.toString(value + (oneBased ? 1 : 0)));
        return String.join(" ", words);
    }
    static String decimals(double[] values) {
        List<String> words = new ArrayList<>();
        for (double value : values)
            words.add(f(value));
        return String.join(" ", words);
    }
    static double entropy(double[] row) {
        double sum = 0;
        for (double value : row)
            if (value != 0)
                sum += value * Math.log(value);
        return -sum;
    }
    static int maximum(double[] row) {
        int best = 0;
        for (int j = 1; j < row.length; j++)
            if (row[j] > row[best])
                best = j;
        return best;
    }
    static Summary summarize(int k, int typeIndex, Em.Run run) {
        Summary result = new Summary();
        result.k = k;
        result.typeIndex = typeIndex;
        result.type = types[typeIndex];
        result.p = switch (result.type) {
            case "FULL" -> 6 * k - 1;
            case "TIED" -> 3 * k + 2;
            case "DIAG" -> 5 * k - 1;
            default -> 4 * k - 1;
        };
        result.run = run;
        result.assignment = new int[run.step().density().length];
        result.sizes = new int[k];
        for (int i = 0; i < result.assignment.length; i++) {
            double[] row = run.step().responsibilities()[i];
            result.assignment[i] = maximum(row);
            result.sizes[result.assignment[i]]++;
            result.entropy += entropy(row);
        }
        double loglik = run.step().loglik();
        result.bic = -2 * loglik + result.p * Math.log(result.assignment.length);
        result.aic = -2 * loglik + 2 * result.p;
        result.icl = result.bic + 2 * result.entropy;
        List<Double> trace = run.trace();
        double last = trace.getLast();
        result.settled = 0;
        for (int t = 0; t < trace.size(); t++)
            if (Math.abs(trace.get(t) - last) > params.get("SETTLE_TOLERANCE"))
                result.settled = t + 1;
        result.largest = 1;
        result.increase = trace.get(1) - trace.get(0);
        for (int t = 1; t < trace.size(); t++) {
            double increase = trace.get(t) - trace.get(t - 1);
            if (increase > result.increase) {
                result.increase = increase;
                result.largest = t;
            }
            if (trace.get(t) < trace.get(t - 1) - 0.000001 * Math.abs(trace.get(t - 1)))
                result.violations.add(t);
        }
        return result;
    }
    static Em.Run fit(List<Dataset.Point> data, Em.Model source, String type) {
        return Em.fit(data, source, type, params.integer("ITERATIONS"), params.get("REGULARIZATION"));
    }
    static double criterion(Summary s, int kind) {
        return kind == 0 ? s.bic : kind == 1 ? s.aic : s.icl;
    }
    static int compare(Summary a, Summary b, int kind) {
        int c = Report.rounded(criterion(a, kind)).compareTo(Report.rounded(criterion(b, kind)));
        if (c == 0)
            c = Integer.compare(a.p, b.p);
        if (c == 0)
            c = Integer.compare(a.k, b.k);
        if (c == 0)
            c = Integer.compare(a.typeIndex, b.typeIndex);
        return c;
    }
    static List<Summary> ranking(int kind) {
        List<Summary> result = new ArrayList<>(models);
        result.sort((a, b) -> compare(a, b, kind));
        return result;
    }
    static Summary bestK(int k) {
        Summary best = null;
        for (Summary model : models)
            if (model.k == k && (best == null || compare(model, best, 0) < 0))
                best = model;
        return best;
    }
    static int[][] contingency(int[] a, int ka, int[] b, int kb) {
        int[][] result = new int[ka][kb];
        for (int i = 0; i < a.length; i++)
            result[a[i]][b[i]]++;
        return result;
    }
    static long pairs(long n) {
        return n * (n - 1) / 2;
    }
    static long gcd(long a, long b) {
        while (b != 0) {
            long r = a % b;
            a = b;
            b = r;
        }
        return a;
    }
    static Ari ari(int[][] table) {
        long s = 0, a = 0, b = 0, n = 0;
        long[] columns = new long[table[0].length];
        for (int[] row : table) {
            long sum = 0;
            for (int c = 0; c < row.length; c++) {
                s += pairs(row[c]);
                sum += row[c];
                columns[c] += row[c];
            }
            a += pairs(sum);
            n += sum;
        }
        for (long value : columns)
            b += pairs(value);
        long z = pairs(n), numerator = 2 * (z * s - a * b), denominator = z * (a + b) - 2 * a * b;
        if (denominator == 0)
            return new Ari(1, 1);
        long g = gcd(Math.abs(numerator), Math.abs(denominator));
        numerator /= g;
        denominator /= g;
        if (denominator < 0) {
            numerator = -numerator;
            denominator = -denominator;
        }
        return new Ari(numerator, denominator);
    }
    static Metrics metrics(int[] assignment, int k) {
        int n = points.size();
        int[] counts = new int[k];
        double[][] centers = new double[k][2];
        double[] center = new double[2];
        for (int i = 0; i < n; i++) {
            Dataset.Point point = points.get(i);
            int j = assignment[i];
            counts[j]++;
            centers[j][0] += point.x();
            centers[j][1] += point.y();
            center[0] += point.x();
            center[1] += point.y();
        }
        int groups = 0;
        for (int j = 0; j < k; j++)
            if (counts[j] > 0) {
                groups++;
                centers[j][0] /= counts[j];
                centers[j][1] /= counts[j];
            }
        double[] cluster = new double[k];
        Arrays.fill(cluster, Double.NaN);
        if (groups < 2)
            return new Metrics(Double.NaN, Double.NaN, Double.NaN, cluster);
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
                        double distance = Kmeans.distance(points.get(i), points.get(q));
                        if (assignment[q] == j)
                            own += distance;
                        else
                            others[assignment[q]] += distance;
                    }
                double a = own / (counts[j] - 1), b = Double.POSITIVE_INFINITY;
                for (int c = 0; c < k; c++)
                    if (c != j && counts[c] > 0)
                        b = Math.min(b, others[c] / counts[c]);
                s = (b - a) / Math.max(a, b);
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
                between += counts[j] * Kmeans.squared(centers[j][0], centers[j][1], center);
        double[] scatters = new double[k];
        for (int i = 0; i < n; i++) {
            Dataset.Point point = points.get(i);
            int j = assignment[i];
            double square = Kmeans.squared(point.x(), point.y(), centers[j]);
            within += square;
            scatters[j] += Math.sqrt(square);
        }
        for (int j = 0; j < k; j++)
            if (counts[j] > 0)
                scatters[j] /= counts[j];
        double db = 0;
        for (int j = 0; j < k; j++)
            if (counts[j] > 0) {
                double maximum = Double.NEGATIVE_INFINITY;
                for (int c = 0; c < k; c++)
                    if (c != j && counts[c] > 0)
                        maximum = Math.max(
                            maximum, (scatters[j] + scatters[c]) /
                                         Math.sqrt(Kmeans.squared(centers[j][0], centers[j][1], centers[c])));
                db += maximum;
            }
        return new Metrics(silhouette / n, (between / (groups - 1)) / (within / (n - groups)), db / groups,
                           cluster);
    }
    static List<String> modelReport() {
        List<String> out = new ArrayList<>();
        for (Summary model : models) {
            if (!out.isEmpty())
                out.add("");
            Em.Model m = model.run.model();
            out.add("model K=" + model.k + " type=" + model.type);
            out.add("parameters " + model.p);
            out.add("loglik " + f(model.run.step().loglik()));
            out.add("bic " + f(model.bic));
            out.add("aic " + f(model.aic));
            out.add("icl " + f(model.icl));
            out.add("mean_entropy " + f(model.entropy / points.size()));
            out.add("settled_at " + model.settled);
            out.add("largest_increase iteration " + model.largest + " value " + f(model.increase));
            out.add("violations " + model.violations.size());
            out.add("sizes " + ints(model.sizes, false));
            for (int j = 0; j < model.k; j++) {
                Gaussian.Eigen e = Gaussian.eigen(m.cov[j]);
                out.add("component " + (j + 1) + " weight " + f(m.weights[j]) + " mean " +
                        decimals(m.means[j]) + " cov " + decimals(m.cov[j]) + " axes " + f(e.major()) + " " +
                        f(e.minor()) + " angle " + f(e.angle()));
            }
        }
        return out;
    }
    static List<String> traceReport() {
        List<String> out = new ArrayList<>(List.of("K,type,iteration,loglik"));
        for (Summary model : models)
            for (int t = 0; t < model.run.trace().size(); t++)
                out.add(model.k + "," + model.type + "," + t + "," + f(model.run.trace().get(t)));
        return out;
    }
    static List<String> assignmentsReport() {
        List<String> out =
            new ArrayList<>(List.of("id,component,max_responsibility,log_density,kmeans_cluster"));
        for (int i = 0; i < points.size(); i++)
            out.add(points.get(i).id() + "," + (selected.assignment[i] + 1) + "," +
                    f(selected.run.step().responsibilities()[i][selected.assignment[i]]) + "," +
                    f(selected.run.step().density()[i]) + "," + (kmeans.get(selected.k).assignment()[i] + 1));
        return out;
    }
    static void block(List<String> out, String heading) {
        if (!out.isEmpty())
            out.add("");
        out.add(heading);
    }
    static void ranks(List<String> out) {
        List<Summary> bic = ranking(0), aic = ranking(1), icl = ranking(2);
        out.add("ranking by bic");
        out.add("rank K type parameters loglik bic delta_bic aic aic_rank icl icl_rank");
        for (int i = 0; i < bic.size(); i++) {
            Summary model = bic.get(i);
            String delta = Report.rounded(model.bic).subtract(Report.rounded(selected.bic)).toPlainString();
            out.add((i + 1) + " " + model.k + " " + model.type + " " + model.p + " " +
                    f(model.run.step().loglik()) + " " + f(model.bic) + " " + delta + " " + f(model.aic) +
                    " " + (aic.indexOf(model) + 1) + " " + f(model.icl) + " " + (icl.indexOf(model) + 1));
        }
        out.add("selected K=" + selected.k + " type=" + selected.type);
        out.add("best_aic K=" + aic.getFirst().k + " type=" + aic.getFirst().type);
        out.add("best_icl K=" + icl.getFirst().k + " type=" + icl.getFirst().type);
        block(out, "best K per type");
        for (String type : types) {
            int[] best = new int[3];
            for (int kind = 0; kind < 3; kind++)
                for (Summary model : ranking(kind))
                    if (model.type.equals(type)) {
                        best[kind] = model.k;
                        break;
                    }
            out.add(type + " bic " + best[0] + " aic " + best[1] + " icl " + best[2]);
        }
    }
    static void compareK(List<String> out) {
        Summary previous = null;
        for (int k : ks) {
            Summary best = bestK(k);
            Kmeans.Run km = kmeans.get(k);
            Metrics g = metrics(best.assignment, k), m = metrics(km.assignment(), k);
            block(out, "K=" + k + " type=" + best.type + " bic " + f(best.bic));
            out.add("  kmeans iterations " + km.iterations() + " inertia " + f(km.inertia()));
            out.add("  ari " + ari(contingency(best.assignment, k, km.assignment(), k)).text());
            out.add("  silhouette gmm " + f(g.silhouette()) + " kmeans " + f(m.silhouette()));
            out.add("  calinski_harabasz gmm " + f(g.ch()) + " kmeans " + f(m.ch()));
            out.add("  davies_bouldin gmm " + f(g.db()) + " kmeans " + f(m.db()));
            if (previous != null) {
                int[][] table = contingency(previous.assignment, previous.k, best.assignment, k);
                List<String> parents = new ArrayList<>();
                int[] shared = new int[k];
                for (int j = 0; j < k; j++) {
                    int parent = -1;
                    for (int a = 0; a < previous.k; a++)
                        if (table[a][j] > shared[j]) {
                            shared[j] = table[a][j];
                            parent = a;
                        }
                    parents.add(parent < 0 ? "-" : Integer.toString(parent + 1));
                }
                out.add("  parents K=" + previous.k + " " + String.join(" ", parents) + " shared " +
                        ints(shared, false));
            }
            previous = best;
        }
    }
    static void violations(List<String> out) {
        block(out, "violations");
        boolean any = false;
        for (Summary model : models)
            for (int t : model.violations) {
                any = true;
                out.add("K=" + model.k + " type=" + model.type + " iteration " + t + " previous " +
                        f(model.run.trace().get(t - 1)) + " current " + f(model.run.trace().get(t)));
            }
        if (!any)
            out.add("none");
    }
    static void components(List<String> out) {
        block(out, "selected components");
        Em.Model model = selected.run.model();
        double[][] r = selected.run.step().responsibilities();
        Metrics metrics = metrics(selected.assignment, selected.k);
        double[] boundaries = params.row("GOF_EDGES");
        for (int j = 0; j < selected.k; j++) {
            Gaussian.Eigen e = Gaussian.eigen(model.cov[j]);
            double soft = 0;
            int inside1 = 0, inside2 = 0;
            int[] observed = new int[boundaries.length + 1];
            for (int i = 0; i < points.size(); i++) {
                soft += r[i][j];
                if (selected.assignment[i] != j)
                    continue;
                Dataset.Point p = points.get(i);
                double q = Gaussian.q(p.x(), p.y(), model.means[j], model.cov[j]);
                if (q <= 1)
                    inside1++;
                if (q <= 4)
                    inside2++;
                double rho = Math.sqrt(q);
                int bucket = 0;
                while (bucket < boundaries.length && rho >= boundaries[bucket])
                    bucket++;
                observed[bucket]++;
            }
            double[] expected = new double[observed.length];
            double chi = 0;
            for (int b = 0; b < observed.length; b++) {
                double lo = b == 0 ? 0 : boundaries[b - 1],
                       right = b == boundaries.length ? 0 : Math.exp(-boundaries[b] * boundaries[b] / 2);
                expected[b] = selected.sizes[j] * (Math.exp(-lo * lo / 2) - right);
                chi += (observed[b] - expected[b]) * (observed[b] - expected[b]) / expected[b];
            }
            out.add("component " + (j + 1) + " weight " + f(model.weights[j]) + " size " + selected.sizes[j] +
                    " soft_size " + f(soft) + " mean " + decimals(model.means[j]));
            out.add("  cov " + decimals(model.cov[j]) + " corr " + f(e.correlation()));
            out.add("  eigen " + f(e.leading()) + " " + f(e.trailing()) + " direction " + f(e.ux()) + " " +
                    f(e.uy()) + " angle " + f(e.angle()));
            out.add("  axes_1sigma " + f(e.major()) + " " + f(e.minor()) + " axes_2sigma " +
                    f(2 * e.major()) + " " + f(2 * e.minor()));
            out.add("  inside_1sigma " + inside1 + " inside_2sigma " + inside2 + " area_1sigma " +
                    f(e.area()));
            out.add("  silhouette " + f(metrics.cluster()[j]));
            out.add("  gof observed " + ints(observed, false) + " expected " + decimals(expected) + " chi2 " +
                    f(chi));
        }
        block(out, "overlap");
        if (selected.k == 1)
            out.add("none");
        for (int a = 0; a < selected.k; a++)
            for (int b = a + 1; b < selected.k; b++) {
                double distance =
                           Gaussian.bhattacharyya(model.means[a], model.cov[a], model.means[b], model.cov[b]),
                       shared = 0;
                for (int i = 0; i < points.size(); i++)
                    shared += r[i][a] * r[i][b];
                out.add((a + 1) + "-" + (b + 1) + " bhattacharyya " + f(distance) + " coefficient " +
                        f(Math.exp(-distance)) + " shared " + f(shared));
            }
    }

    static List<List<Integer>> merge(List<List<Integer>> clusters, int a, int b) {
        List<List<Integer>> result = new ArrayList<>(clusters);
        List<Integer> union = new ArrayList<>(clusters.get(a));
        union.addAll(clusters.get(b));
        Collections.sort(union);
        result.set(a, union);
        result.remove(b);
        return result;
    }
    static double[][] collapsed(List<List<Integer>> clusters) {
        double[][] result = new double[points.size()][clusters.size()];
        for (int i = 0; i < points.size(); i++)
            for (int c = 0; c < clusters.size(); c++)
                for (int j : clusters.get(c))
                    result[i][c] += selected.run.step().responsibilities()[i][j];
        return result;
    }
    static double mergedEntropy(List<List<Integer>> clusters) {
        double sum = 0;
        for (double[] row : collapsed(clusters))
            sum += entropy(row);
        return sum;
    }
    static String clusterName(List<Integer> cluster) {
        List<String> words = new ArrayList<>();
        for (int j : cluster)
            words.add(Integer.toString(j + 1));
        return String.join("+", words);
    }
    static void merging(List<String> out) {
        block(out, "merging");
        List<List<Integer>> clusters = new ArrayList<>();
        for (int j = 0; j < selected.k; j++)
            clusters.add(List.of(j));
        out.add("start entropy " + f(mergedEntropy(clusters)));
        for (int step = 1; clusters.size() > 1; step++) {
            int ba = 0, bb = 1;
            double best = Double.POSITIVE_INFINITY;
            for (int a = 0; a < clusters.size(); a++)
                for (int b = a + 1; b < clusters.size(); b++) {
                    double value = mergedEntropy(merge(clusters, a, b));
                    if (Double.isInfinite(best) ||
                        Report.rounded(value).compareTo(Report.rounded(best)) < 0) {
                        best = value;
                        ba = a;
                        bb = b;
                    }
                }
            String a = clusterName(clusters.get(ba)), b = clusterName(clusters.get(bb));
            clusters = merge(clusters, ba, bb);
            double[][] r = collapsed(clusters);
            int[] sizes = new int[clusters.size()];
            for (double[] row : r)
                sizes[maximum(row)]++;
            out.add("step " + step + " merge " + a + " " + b + " entropy " + f(best) + " sizes " +
                    ints(sizes, false));
        }
    }
    record Matching(int[] permutation, int agreement) {}
    static void permutations(int[][] table, int depth, int[] current, boolean[] used, int[] best,
                             int[] largest) {
        if (depth == current.length) {
            int agreement = 0;
            for (int j = 0; j < current.length; j++)
                agreement += table[current[j]][j];
            if (agreement > largest[0]) {
                largest[0] = agreement;
                System.arraycopy(current, 0, best, 0, current.length);
            }
            return;
        }
        for (int j = 0; j < current.length; j++)
            if (!used[j]) {
                used[j] = true;
                current[depth] = j;
                permutations(table, depth + 1, current, used, best, largest);
                used[j] = false;
            }
    }
    static Matching matching(int[][] table) {
        int k = table.length;
        int[] best = new int[k], largest = {-1};
        permutations(table, 0, new int[k], new boolean[k], best, largest);
        return new Matching(best, largest[0]);
    }
    static void compareKmeans(List<String> out) {
        Kmeans.Run km = kmeans.get(selected.k);
        block(out, "kmeans K=" + selected.k);
        out.add("iterations " + km.iterations());
        out.add("inertia " + f(km.inertia()));
        int[] sizes = new int[selected.k];
        for (int value : km.assignment())
            sizes[value]++;
        out.add("sizes " + ints(sizes, false));
        for (int j = 0; j < selected.k; j++)
            out.add("center " + (j + 1) + " " + decimals(km.centers()[j]));
        int[][] table = contingency(selected.assignment, selected.k, km.assignment(), selected.k);
        out.add("contingency");
        for (int[] row : table)
            out.add(ints(row, false));
        out.add("ari " + ari(table).text());
        Matching match = matching(table);
        out.add("matching " + ints(match.permutation(), true));
        out.add("agreement " + match.agreement() + "/" + points.size() + " " +
                f((double)match.agreement() / points.size()));
        int disagreements = 0;
        for (int i = 0; i < points.size(); i++)
            if (match.permutation()[km.assignment()[i]] != selected.assignment[i]) {
                disagreements++;
                out.add("disagree " + points.get(i).id() + " gmm " + (selected.assignment[i] + 1) +
                        " kmeans " + (km.assignment()[i] + 1) + " max " +
                        f(selected.run.step().responsibilities()[i][selected.assignment[i]]));
            }
        out.add("disagreements " + disagreements);
    }
    static void refit(List<String> out) {
        Kmeans.Run km = kmeans.get(selected.k);
        Em.Model source = new Em.Model(selected.k);
        int[] counts = new int[selected.k];
        for (int value : km.assignment())
            counts[value]++;
        double eps = params.get("REGULARIZATION");
        for (int j = 0; j < selected.k; j++) {
            source.weights[j] = (double)counts[j] / points.size();
            source.means[j] = km.centers()[j].clone();
            for (int i = 0; i < points.size(); i++)
                if (km.assignment()[i] == j) {
                    double dx = points.get(i).x() - source.means[j][0],
                           dy = points.get(i).y() - source.means[j][1];
                    source.cov[j][0] += dx * dx;
                    source.cov[j][1] += dx * dy;
                    source.cov[j][2] += dy * dy;
                }
            source.cov[j][0] = source.cov[j][0] / counts[j] + eps;
            source.cov[j][1] /= counts[j];
            source.cov[j][2] = source.cov[j][2] / counts[j] + eps;
        }
        Summary result = summarize(selected.k, selected.typeIndex, fit(points, source, selected.type));
        block(out, "refit_from_kmeans K=" + selected.k + " type=" + selected.type);
        out.add("loglik " + f(result.run.step().loglik()) + " bic " + f(result.bic) + " settled_at " +
                result.settled);
        out.add("sizes " + ints(result.sizes, false));
        out.add("ari_vs_selected " +
                ari(contingency(selected.assignment, selected.k, result.assignment, selected.k)).text());
    }
    static void crossValidation(List<String> out) {
        int folds = params.integer("CV_FOLDS");
        block(out, "cross_validation K=" + selected.k + " type=" + selected.type + " folds " + folds);
        double sum = 0;
        for (int fold = 0; fold < folds; fold++) {
            List<Dataset.Point> train = new ArrayList<>(), test = new ArrayList<>();
            for (int i = 0; i < points.size(); i++)
                if (i % folds == fold)
                    test.add(points.get(i));
                else
                    train.add(points.get(i));
            Em.Run run = fit(train, initial.get(selected.k), selected.type);
            double score = Em.expectation(test, run.model()).loglik() / test.size();
            sum += score;
            out.add("fold " + (fold + 1) + " train " + train.size() + " test " + test.size() +
                    " train_loglik " + f(run.step().loglik() / train.size()) + " test_loglik " + f(score));
        }
        out.add("mean_test_loglik " + f(sum / folds));
    }
    static void unusual(List<String> out) {
        List<Integer> uncertain = new ArrayList<>(), outliers = new ArrayList<>();
        double[][] r = selected.run.step().responsibilities();
        double[] lp = selected.run.step().density();
        double threshold = params.get("UNCERTAIN_THRESHOLD"), low = params.get("LOW_DENSITY_THRESHOLD");
        for (int i = 0; i < points.size(); i++) {
            if (r[i][selected.assignment[i]] < threshold)
                uncertain.add(i);
            if (lp[i] < low)
                outliers.add(i);
        }
        uncertain.sort((a, b) -> {
            int c = Report.rounded(r[a][selected.assignment[a]])
                        .compareTo(Report.rounded(r[b][selected.assignment[b]]));
            return c != 0 ? c : Integer.compare(a, b);
        });
        outliers.sort((a, b) -> {
            int c = Report.rounded(lp[a]).compareTo(Report.rounded(lp[b]));
            return c != 0 ? c : Integer.compare(a, b);
        });
        block(out, "uncertain threshold " + f(threshold));
        for (int i : uncertain)
            out.add(points.get(i).id() + " component " + (selected.assignment[i] + 1) + " max " +
                    f(r[i][selected.assignment[i]]) + " responsibilities " + decimals(r[i]));
        out.add("count " + uncertain.size());
        block(out, "outliers threshold " + f(low));
        Em.Model model = selected.run.model();
        for (int i : outliers) {
            Dataset.Point point = points.get(i);
            int j = selected.assignment[i];
            out.add(point.id() + " component " + (j + 1) + " log_density " + f(lp[i]) + " q " +
                    f(Gaussian.q(point.x(), point.y(), model.means[j], model.cov[j])));
        }
        out.add("count " + outliers.size());
    }
    static List<String> selectionReport() {
        List<String> out = new ArrayList<>();
        ranks(out);
        compareK(out);
        violations(out);
        components(out);
        merging(out);
        compareKmeans(out);
        refit(out);
        crossValidation(out);
        unusual(out);
        return out;
    }
    static int[] cell(double x, double y, double[] rx, double[] ry, double sx, double sy, int width,
                      int height) {
        int col = (int)Math.floor((x - rx[0]) / sx), row = (int)Math.floor((ry[1] - y) / sy);
        return col < 0 || col >= width || row < 0 || row >= height ? null : new int[] {col, row};
    }
    static List<String> maps() {
        double[] rx = params.row("MAP_X"), ry = params.row("MAP_Y"), size = params.row("MAP_SIZE");
        int width = (int)size[0], height = (int)size[1];
        double sx = (rx[1] - rx[0]) / width, sy = (ry[1] - ry[0]) / height;
        String characters = " .:-=+*#%@";
        char[][] density = new char[height][width], regions = new char[height][width],
                 uncertainty = new char[height][width], pointMap = new char[height][width];
        double[][] values = new double[height][width];
        double maximum = 0, sum = 0;
        Em.Model model = selected.run.model();
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width; x++) {
                double cx = rx[0] + (x + 0.5) * sx, cy = ry[1] - (y + 0.5) * sy;
                Em.Step step = Em.expectation(List.of(new Dataset.Point("", cx, cy)), model);
                double value = 0;
                for (double score : step.scores()[0])
                    value += Math.exp(score);
                values[y][x] = value;
                maximum = Math.max(maximum, value);
                sum += value;
                regions[y][x] = (char)('1' + maximum(step.scores()[0]));
                int level =
                    selected.k == 1
                        ? 0
                        : (int)Math.floor(10 * entropy(step.responsibilities()[0]) / Math.log(selected.k));
                level = Math.max(0, Math.min(9, level));
                uncertainty[y][x] = characters.charAt(level);
                pointMap[y][x] = ' ';
                for (int j = 0; j < selected.k; j++)
                    if (Gaussian.q(cx, cy, model.means[j], model.cov[j]) <= 4) {
                        for (int[] d : new int[][] {{-1, 0}, {1, 0}, {0, -1}, {0, 1}}) {
                            int xx = x + d[0], yy = y + d[1];
                            if (xx >= 0 && xx < width && yy >= 0 && yy < height &&
                                Gaussian.q(rx[0] + (xx + 0.5) * sx, ry[1] - (yy + 0.5) * sy, model.means[j],
                                           model.cov[j]) > 4)
                                pointMap[y][x] = '.';
                        }
                    }
            }
        int[] counts = new int[10];
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width; x++) {
                int level = Math.min(9, (int)Math.floor(10 * values[y][x] / maximum));
                counts[level]++;
                density[y][x] = characters.charAt(level);
            }
        for (int j = 0; j < selected.k; j++) {
            int[] cell = cell(model.means[j][0], model.means[j][1], rx, ry, sx, sy, width, height);
            if (cell != null)
                density[cell[1]][cell[0]] = (char)('1' + j);
        }
        int outside = 0;
        for (int i = 0; i < points.size(); i++) {
            Dataset.Point point = points.get(i);
            int[] cell = cell(point.x(), point.y(), rx, ry, sx, sy, width, height);
            if (cell == null) {
                outside++;
                continue;
            }
            char old = pointMap[cell[1]][cell[0]], symbol = (char)('1' + selected.assignment[i]);
            pointMap[cell[1]][cell[0]] = old == ' ' || old == '.' || old == symbol ? symbol : '*';
        }
        List<String> out = new ArrayList<>();
        out.add("density K=" + selected.k + " type=" + selected.type);
        out.add("x " + f(rx[0]) + " " + f(rx[1]) + " y " + f(ry[0]) + " " + f(ry[1]) + " grid " + width +
                "x" + height);
        out.add("max_density " + Report.decimal(maximum, 6) + " mass_in_map " + f(sum * sx * sy));
        out.addAll(Report.frame(density));
        for (int level = 0; level < 10; level++)
            out.add("level " + level + " \"" + characters.charAt(level) + "\" from " +
                    Report.decimal(level * maximum / 10, 6) + " cells " + counts[level]);
        block(out, "regions");
        out.addAll(Report.frame(regions));
        block(out, "uncertainty");
        out.addAll(Report.frame(uncertainty));
        block(out, "points");
        out.addAll(Report.frame(pointMap));
        out.add("outside " + outside);
        return out;
    }
    public static void main(String[] args) throws IOException {
        Dataset.Data data = Dataset.read();
        points = data.points();
        initial = data.initial();
        params = data.params();
        types = params.words("TYPES");
        String[] sequence = params.words("K");
        ks = new int[sequence.length];
        for (int i = 0; i < ks.length; i++)
            ks[i] = Integer.parseInt(sequence[i]);
        for (int k : ks) {
            for (int t = 0; t < types.length; t++)
                models.add(summarize(k, t, fit(points, initial.get(k), types[t])));
            kmeans.put(k, Kmeans.fit(points, initial.get(k).means, params.integer("KMEANS_MAX_ITERATIONS")));
        }
        selected = ranking(0).getFirst();
        Report.write("models.txt", modelReport());
        Report.write("loglik_trace.csv", traceReport());
        Report.write("assignments.csv", assignmentsReport());
        Report.write("selection.txt", selectionReport());
        Report.write("density_map.txt", maps());
    }
}
