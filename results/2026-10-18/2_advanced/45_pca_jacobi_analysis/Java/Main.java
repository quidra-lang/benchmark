import java.io.IOException;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

public final class Main {
    static Dataset.Data data;
    static Dataset.Settings settings;
    static List<String> names;
    static int p, n, k, top;
    static double[] observedMeans, msa, parallel, ratio, cumulative, broken, se, communalities;
    static int[] observed, retention;
    static double[][] summary, loadings, circle, rotated;
    static double[] rotationSquares, congruences, criteria;
    static int[] closest;
    static Fit fit;
    static List<Observation> observations = new ArrayList<>(), projections = new ArrayList<>();
    static double total, average, kmo, determinant, bartlett;
    static String real(double value) {
        return format(value, 4);
    }
    static String format(double value, int digits) {
        String text = String.format(Locale.ROOT, "%." + digits + "f", value);
        return Double.parseDouble(text) == 0 && text.startsWith("-") ? text.substring(1) : text;
    }
    static String reals(double[] values) {
        List<String> result = new ArrayList<>();
        for (double value : values)
            result.add(real(value));
        return String.join(" ", result);
    }
    static void write(String name, List<String> lines) throws IOException {
        Files.writeString(Path.of("output", name), String.join("\n", lines) + "\n",
                          StandardCharsets.US_ASCII);
    }
    static List<String> components(String prefix, int count) {
        List<String> result = new ArrayList<>();
        for (int i = 1; i <= count; i++)
            result.add(prefix + i);
        return result;
    }
    static void section(List<String> out, List<String> part) {
        if (!out.isEmpty())
            out.add("");
        out.addAll(part);
    }
    static boolean missing(double[] row) {
        for (double value : row)
            if (Double.isNaN(value))
                return true;
        return false;
    }
    static int maximum(double[] values) {
        int best = 0;
        for (int i = 1; i < values.length; i++)
            if (values[i] > values[best])
                best = i;
        return best;
    }
    static int minimum(double[] values) {
        int best = 0;
        for (int i = 1; i < values.length; i++)
            if (values[i] < values[best])
                best = i;
        return best;
    }
    static List<Integer> top(double[] values, int count) {
        List<Integer> order = new ArrayList<>();
        for (int i = 0; i < values.length; i++)
            order.add(i);
        order.sort((left, right) -> {
            int comparison = Double.compare(values[right], values[left]);
            return comparison != 0 ? comparison : Integer.compare(left, right);
        });
        return new ArrayList<>(order.subList(0, Math.min(count, order.size())));
    }
    static double congruence(double[] first, double[] second) {
        return Matrix.dot(first, second) / Math.sqrt(Matrix.dot(first, first) * Matrix.dot(second, second));
    }
    static final class Fit {
        List<String> ids = new ArrayList<>();
        double[][] values;
        double[] means, scales;
        double[][] covariance, correlation, matrix;
        Eigen.Result eigen;
        Fit(String strategy, String scaling) {
            List<double[]> rows = new ArrayList<>();
            for (Dataset.Row row : data.data().rows()) {
                if (strategy.equals("listwise") && missing(row.values()))
                    continue;
                ids.add(row.id());
                double[] values = row.values().clone();
                for (int j = 0; j < p; j++)
                    if (Double.isNaN(values[j]))
                        values[j] = observedMeans[j];
                rows.add(values);
            }
            values = rows.toArray(new double[0][]);
            means = Pca.means(values);
            covariance = Pca.covariance(values, means);
            double[] sd = Pca.deviations(covariance);
            correlation = Pca.correlation(covariance, sd);
            matrix = scaling.equals("covariance") ? covariance : correlation;
            scales = new double[p];
            for (int j = 0; j < p; j++)
                scales[j] = scaling.equals("covariance") ? 1 : sd[j];
            eigen = Eigen.jacobi(matrix);
        }
    }
    static final class Observation {
        String id, flag;
        double[] z, scores, residuals, tContributions, qContributions;
        double t2, spe, quality;
        Observation(String id, double[] values) {
            this.id = id;
            z = Pca.standardize(values, fit.means, fit.scales);
            scores = Pca.scores(z, fit.eigen.vectors());
            t2 = Pca.t2(scores, fit.eigen.values(), k);
            residuals = Pca.residuals(z, scores, fit.eigen.vectors(), k);
            spe = Matrix.dot(residuals, residuals);
            double squares = 0;
            for (int h = 0; h < k; h++)
                squares += scores[h] * scores[h];
            quality = squares / Matrix.dot(z, z);
            flag = (t2 > settings.number("T2_LIMIT") ? "T" : "") +
                   (spe > settings.number("SPE_LIMIT") ? "Q" : "");
            if (flag.isEmpty())
                flag = "-";
            tContributions = new double[p];
            qContributions = new double[p];
            for (int j = 0; j < p; j++) {
                double weight = 0;
                for (int h = 0; h < k; h++)
                    weight += (scores[h] / fit.eigen.values()[h]) * fit.eigen.vectors()[h][j];
                tContributions[j] = z[j] * weight;
                qContributions[j] = residuals[j] * residuals[j];
            }
        }
    }
    static void summarize() {
        observed = new int[p];
        observedMeans = new double[p];
        summary = new double[p][4];
        for (int j = 0; j < p; j++) {
            double sum = 0, min = Double.POSITIVE_INFINITY, max = Double.NEGATIVE_INFINITY;
            for (Dataset.Row row : data.data().rows())
                if (!Double.isNaN(row.values()[j])) {
                    double value = row.values()[j];
                    observed[j]++;
                    sum += value;
                    min = Math.min(min, value);
                    max = Math.max(max, value);
                }
            double mean = sum / observed[j], variance = 0;
            observedMeans[j] = mean;
            for (Dataset.Row row : data.data().rows())
                if (!Double.isNaN(row.values()[j]))
                    variance += (row.values()[j] - mean) * (row.values()[j] - mean);
            summary[j] = new double[] {mean, Math.sqrt(variance / (observed[j] - 1)), min, max};
        }
    }
    static void adequacy() {
        Matrix.Inverse result = Matrix.inverse(fit.correlation);
        determinant = result.determinant();
        msa = new double[p];
        double rrTotal = 0, ppTotal = 0;
        for (int j = 0; j < p; j++) {
            double rr = 0, pp = 0;
            for (int h = 0; h < p; h++)
                if (j != h) {
                    double partial =
                        -result.matrix()[j][h] / Math.sqrt(result.matrix()[j][j] * result.matrix()[h][h]);
                    rr += fit.correlation[j][h] * fit.correlation[j][h];
                    pp += partial * partial;
                }
            msa[j] = rr / (rr + pp);
            rrTotal += rr;
            ppTotal += pp;
        }
        kmo = rrTotal / (rrTotal + ppTotal);
        bartlett = -(n - 1 - (2 * p + 5) / 6.0) * Math.log(determinant);
    }
    static void variances() {
        parallel = new double[p];
        long state = settings.second("PARALLEL");
        int iterations = settings.integer("PARALLEL");
        for (int iteration = 0; iteration < iterations; iteration++) {
            double[][] values = new double[n][p];
            for (int i = 0; i < n; i++)
                for (int j = 0; j < p; j++) {
                    state = 48271 * state % 2147483647;
                    values[i][j] = (double)state / 2147483647;
                }
            double[][] covariance = Pca.covariance(values, Pca.means(values));
            double[] eigen = Eigen.jacobi(Pca.correlation(covariance, Pca.deviations(covariance))).values();
            double sum = Matrix.sum(eigen);
            for (int h = 0; h < p; h++)
                parallel[h] += eigen[h] / sum;
        }
        for (int h = 0; h < p; h++)
            parallel[h] /= iterations;
        total = Matrix.sum(fit.eigen.values());
        average = total / p;
        ratio = new double[p];
        cumulative = new double[p];
        broken = new double[p];
        se = new double[p];
        retention = new int[] {0, p, p, p};
        double running = 0;
        for (int h = 0; h < p; h++) {
            double value = fit.eigen.values()[h];
            ratio[h] = value / total;
            running += ratio[h];
            cumulative[h] = running;
            double sum = 0;
            for (int i = h + 1; i <= p; i++)
                sum += 1.0 / i;
            broken[h] = sum / p;
            se[h] = value * Math.sqrt(2.0 / n);
            if (value > average)
                retention[0]++;
        }
        for (int h = 0; h < p; h++)
            if (ratio[h] <= broken[h]) {
                retention[1] = h;
                break;
            }
        for (int h = 0; h < p; h++)
            if (ratio[h] <= parallel[h]) {
                retention[2] = h;
                break;
            }
        for (int h = 0; h < p; h++)
            if (cumulative[h] >= settings.number("CUMULATIVE_TARGET")) {
                retention[3] = h + 1;
                break;
            }
        String rule = settings.text("COMPONENTS");
        List<String> rules = List.of("kaiser", "broken_stick", "parallel", "cumulative");
        k = rules.contains(rule) ? Math.max(1, retention[rules.indexOf(rule)]) : Integer.parseInt(rule);
    }
    static double criterion(double[][] g) {
        double value = 0;
        for (int h = 0; h < k; h++) {
            double q4 = 0, q2 = 0;
            for (int j = 0; j < p; j++) {
                q4 += (g[j][h] * g[j][h]) * (g[j][h] * g[j][h]);
                q2 += g[j][h] * g[j][h];
            }
            value += q4 / p - (q2 / p) * (q2 / p);
        }
        return value;
    }
    static void rotate(double[][] g, int a, int b) {
        double sa = 0, sb = 0, sc = 0, sd = 0;
        for (int j = 0; j < p; j++) {
            double phi = g[j][a] * g[j][a] - g[j][b] * g[j][b], psi = 2 * g[j][a] * g[j][b];
            sa += phi;
            sb += psi;
            sc += phi * phi - psi * psi;
            sd += 2 * phi * psi;
        }
        double num = sd - 2 * sa * sb / p, den = sc - (sa * sa - sb * sb) / p,
               omega = Math.sqrt(num * num + den * den);
        if (omega == 0)
            return;
        double cos4 = den / omega, sin4 = num / omega, cos2 = Math.sqrt((1 + cos4) / 2),
               sin2 = cos2 == 0 ? 1 : sin4 / (2 * cos2), cos1 = Math.sqrt((1 + cos2) / 2),
               sin1 = sin2 / (2 * cos1);
        for (int j = 0; j < p; j++) {
            double first = g[j][a], second = g[j][b];
            g[j][a] = cos1 * first + sin1 * second;
            g[j][b] = -sin1 * first + cos1 * second;
        }
    }
    static void loadings() {
        loadings = new double[p][p];
        circle = new double[p][2];
        communalities = new double[p];
        double[] etas = new double[p];
        double[][] g = new double[p][k];
        for (int j = 0; j < p; j++) {
            for (int h = 0; h < p; h++)
                loadings[j][h] = fit.eigen.vectors()[h][j] * Math.sqrt(fit.eigen.values()[h]);
            double sum = 0;
            for (int h = 0; h < k; h++)
                sum += loadings[j][h] * loadings[j][h];
            communalities[j] = sum / fit.matrix[j][j];
            etas[j] = Math.sqrt(sum);
            for (int h = 0; h < k; h++)
                g[j][h] = loadings[j][h] / etas[j];
            for (int h = 0; h < 2; h++)
                circle[j][h] = loadings[j][h] / Math.sqrt(fit.matrix[j][j]);
        }
        int cycles = settings.integer("VARIMAX_CYCLES");
        criteria = new double[cycles + 1];
        criteria[0] = criterion(g);
        for (int cycle = 1; cycle <= cycles; cycle++) {
            for (int a = 0; a < k - 1; a++)
                for (int b = a + 1; b < k; b++)
                    rotate(g, a, b);
            criteria[cycle] = criterion(g);
        }
        double[][] columns = new double[k][p];
        double[] squares = new double[k];
        for (int h = 0; h < k; h++) {
            for (int j = 0; j < p; j++)
                columns[h][j] = g[j][h] * etas[j];
            Matrix.orient(columns[h]);
            squares[h] = Matrix.dot(columns[h], columns[h]);
        }
        rotated = new double[k][];
        rotationSquares = new double[k];
        closest = new int[k];
        congruences = new double[k];
        List<Integer> order = top(squares, k);
        for (int h = 0; h < k; h++) {
            int index = order.get(h);
            rotated[h] = columns[index];
            rotationSquares[h] = squares[index];
            double[] values = new double[k];
            for (int q = 0; q < k; q++)
                values[q] = Math.abs(congruence(rotated[h], Matrix.column(loadings, q)));
            closest[h] = maximum(values);
            congruences[h] = values[closest[h]];
        }
    }
    static List<String> eigenReport() {
        List<String> out = new ArrayList<>();
        List<String> incomplete = new ArrayList<>();
        for (Dataset.Row row : data.data().rows())
            if (missing(row.values()))
                incomplete.add(row.id());
        section(out,
                List.of("pca rows " + data.data().rows().size() + " used " + n + " variables " + p +
                            " missing " + settings.text("MISSING") + " scaling " + settings.text("SCALING"),
                        "incomplete " + incomplete.size() + " " +
                            (incomplete.isEmpty() ? "-" : String.join(" ", incomplete))));
        List<String> part = new ArrayList<>(List.of("variable observed missing mean sd min max msa"));
        for (int j = 0; j < p; j++)
            part.add(names.get(j) + " " + observed[j] + " " + (data.data().rows().size() - observed[j]) +
                     " " + reals(summary[j]) + " " + real(msa[j]));
        part.add("adequacy kmo " + real(kmo) + " determinant " + format(determinant, 6) + " bartlett " +
                 real(bartlett) + " df " + (p * (p - 1) / 2));
        section(out, part);
        part = new ArrayList<>(List.of("matrix " + settings.text("SCALING")));
        for (int j = 0; j < p; j++)
            part.add(names.get(j) + " " + reals(fit.matrix[j]));
        List<int[]> pairs = new ArrayList<>();
        List<Double> strengths = new ArrayList<>();
        for (int j = 0; j < p; j++)
            for (int h = j + 1; h < p; h++) {
                pairs.add(new int[] {j, h});
                strengths.add(Math.abs(fit.correlation[j][h]));
            }
        double[] strength = new double[strengths.size()];
        for (int i = 0; i < strength.length; i++)
            strength[i] = strengths.get(i);
        String strongest = "strongest";
        for (int index : top(strength, top)) {
            int[] pair = pairs.get(index);
            strongest += " " + names.get(pair[0]) + ":" + names.get(pair[1]) + ":" +
                         real(fit.correlation[pair[0]][pair[1]]);
        }
        part.add(strongest);
        section(out, part);
        part = new ArrayList<>(List.of("jacobi sweeps " + fit.eigen.sweeps(),
                                       "eigenvalues total " + real(total) + " average " + real(average),
                                       "k eigenvalue ratio cumulative broken_stick parallel se separated"));
        for (int h = 0; h < p; h++) {
            boolean separated = true;
            if (h > 0 && Math.abs(fit.eigen.values()[h] - fit.eigen.values()[h - 1]) <= se[h])
                separated = false;
            if (h + 1 < p && Math.abs(fit.eigen.values()[h] - fit.eigen.values()[h + 1]) <= se[h])
                separated = false;
            part.add((h + 1) + " " +
                     reals(new double[] {fit.eigen.values()[h], ratio[h], cumulative[h], broken[h],
                                         parallel[h], se[h]}) +
                     " " + (separated ? "yes" : "no"));
        }
        part.add("retention kaiser " + retention[0] + " broken_stick " + retention[1] + " parallel " +
                 retention[2] + " cumulative " + retention[3] + " target " +
                 real(settings.number("CUMULATIVE_TARGET")));
        part.add("components " + k + " rule " + settings.text("COMPONENTS"));
        section(out, part);
        part = new ArrayList<>(List.of("eigenvectors", "variable " + String.join(" ", components("pc", p))));
        for (int j = 0; j < p; j++)
            part.add(names.get(j) + " " + reals(Matrix.column(fit.eigen.vectors(), j)));
        section(out, part);
        part = new ArrayList<>(List.of("power_iteration iterations 1000", "k jacobi power agree_at match"));
        List<Eigen.Power> powers = Eigen.power(fit.matrix, fit.eigen.vectors());
        int matches = 0;
        for (int h = 0; h < p; h++) {
            Eigen.Power power = powers.get(h);
            boolean match = Math.abs(power.value() - fit.eigen.values()[h]) <= 1e-8 * fit.eigen.values()[0] &&
                            Matrix.difference(power.vector(), fit.eigen.vectors()[h]) <= 0.000001;
            if (match)
                matches++;
            part.add((h + 1) + " " + real(fit.eigen.values()[h]) + " " + real(power.value()) + " " +
                     (power.agreement() == 0 ? "-" : Integer.toString(power.agreement())) + " " +
                     (match ? "yes" : "no"));
        }
        part.add("cross_check " + matches + "/" + p);
        section(out, part);
        part = new ArrayList<>(List.of("scores", "component sd min min_id max max_id contributors"));
        for (int h = 0; h < k; h++) {
            double[] scores = new double[n], contributions = new double[n];
            double sum = 0;
            for (int i = 0; i < n; i++) {
                scores[i] = observations.get(i).scores[h];
                sum += scores[i] * scores[i];
                contributions[i] = scores[i] * scores[i] / ((n - 1) * fit.eigen.values()[h]);
            }
            int low = minimum(scores), high = maximum(scores);
            String line = "pc" + (h + 1) + " " + real(Math.sqrt(sum / (n - 1))) + " " + real(scores[low]) +
                          " " + fit.ids.get(low) + " " + real(scores[high]) + " " + fit.ids.get(high);
            for (int i : top(contributions, top))
                line += " " + fit.ids.get(i) + ":" + real(contributions[i]);
            part.add(line);
        }
        section(out, part);
        part = new ArrayList<>(
            List.of("varimax components " + k + " cycles " + settings.integer("VARIMAX_CYCLES")));
        for (int c = 0; c < criteria.length; c++)
            part.add("cycle " + c + " criterion " + format(criteria[c], 6));
        for (int h = 0; h < k; h++)
            part.add("rc" + (h + 1) + " ss " + real(rotationSquares[h]) + " ratio " +
                     real(rotationSquares[h] / total) + " closest pc" + (closest[h] + 1) + " congruence " +
                     real(congruences[h]));
        section(out, part);
        part = new ArrayList<>(
            List.of("sensitivity", "missing scaling rows sweeps eigenvalues cumulative congruence"));
        for (String strategy : List.of("listwise", "mean"))
            for (String scaling : List.of("covariance", "correlation")) {
                Fit alternative = new Fit(strategy, scaling);
                double[] values = alternative.eigen.values();
                double sum = Matrix.sum(values), cum = 0;
                String line = strategy + " " + scaling + " " + alternative.ids.size() + " " +
                              alternative.eigen.sweeps();
                for (int h = 0; h < k; h++) {
                    line += " " + real(values[h]);
                    cum += values[h] / sum;
                }
                line += " " + real(cum);
                for (int h = 0; h < k; h++)
                    line +=
                        " " +
                        real(Math.abs(Matrix.dot(alternative.eigen.vectors()[h], fit.eigen.vectors()[h])));
                part.add(line);
            }
        section(out, part);
        return out;
    }
    static List<String> loadingsReport() {
        List<String> header = new ArrayList<>(List.of("variable"));
        header.addAll(components("pc", k));
        header.add("communality");
        header.addAll(components("rc", k));
        List<String> out = new ArrayList<>(List.of(String.join(",", header)));
        for (int j = 0; j < p; j++) {
            String line = names.get(j);
            for (int h = 0; h < k; h++)
                line += "," + real(loadings[j][h]);
            line += "," + real(communalities[j]);
            for (int h = 0; h < k; h++)
                line += "," + real(rotated[h][j]);
            out.add(line);
        }
        return out;
    }
    static List<String> scoresReport() {
        List<String> out = new ArrayList<>(List.of("id,set," + String.join(",", components("pc", k))));
        for (int set = 0; set < 2; set++)
            for (Observation observation : set == 0 ? observations : projections) {
                String line = observation.id + "," + (set == 0 ? "data" : "supplementary");
                for (int h = 0; h < k; h++)
                    line += "," + real(observation.scores[h]);
                out.add(line);
            }
        return out;
    }
    static List<String> outliersReport() {
        List<String> out = new ArrayList<>(List.of("diagnostics components " + k + " t2_limit " +
                                                       real(settings.number("T2_LIMIT")) + " spe_limit " +
                                                       real(settings.number("SPE_LIMIT")),
                                                   "id t2 spe quality flag"));
        int tCount = 0, qCount = 0, both = 0, any = 0;
        for (Observation row : observations) {
            out.add(row.id + " " + reals(new double[] {row.t2, row.spe, row.quality}) + " " + row.flag);
            if (row.flag.contains("T"))
                tCount++;
            if (row.flag.contains("Q"))
                qCount++;
            if (row.flag.equals("TQ"))
                both++;
            if (!row.flag.equals("-"))
                any++;
        }
        out.add("flagged t2 " + tCount + " spe " + qCount + " both " + both + " any " + any);
        for (int kind = 0; kind < 2; kind++) {
            String label = kind == 0 ? "t2" : "spe";
            List<String> part =
                new ArrayList<>(List.of("top " + label, "rank id " + label + " variable contribution"));
            double[] values = new double[n];
            for (int i = 0; i < n; i++)
                values[i] = kind == 0 ? observations.get(i).t2 : observations.get(i).spe;
            List<Integer> order = top(values, top);
            for (int position = 0; position < order.size(); position++) {
                int i = order.get(position);
                Observation row = observations.get(i);
                double[] contributions = kind == 0 ? row.tContributions : row.qContributions;
                int variable = maximum(contributions);
                part.add((position + 1) + " " + row.id + " " + real(values[i]) + " " + names.get(variable) +
                         " " + real(contributions[variable]));
            }
            section(out, part);
        }
        List<String> part = new ArrayList<>(List.of("reconstruction", "k mean_spe max_spe max_id"));
        for (int count = 1; count < p; count++) {
            double[] errors = new double[n];
            for (int i = 0; i < n; i++) {
                Observation row = observations.get(i);
                double[] residuals = Pca.residuals(row.z, row.scores, fit.eigen.vectors(), count);
                errors[i] = Matrix.dot(residuals, residuals);
            }
            int worst = maximum(errors);
            part.add(count + " " + real(Matrix.sum(errors) / n) + " " + real(errors[worst]) + " " +
                     fit.ids.get(worst));
        }
        section(out, part);
        part = new ArrayList<>(List.of("supplementary", "id " + String.join(" ", components("pc", k)) +
                                                            " t2 spe flag nearest distance"));
        for (Observation row : projections) {
            double[] distances = new double[n];
            for (int i = 0; i < n; i++)
                for (int h = 0; h < k; h++) {
                    double delta = row.scores[h] - observations.get(i).scores[h];
                    distances[i] += delta * delta;
                }
            int nearest = minimum(distances);
            String line = row.id;
            for (int h = 0; h < k; h++)
                line += " " + real(row.scores[h]);
            part.add(line + " " + real(row.t2) + " " + real(row.spe) + " " + row.flag + " " +
                     fit.ids.get(nearest) + " " + real(Math.sqrt(distances[nearest])));
        }
        section(out, part);
        return out;
    }
    static void axes(char[][] grid, Plot.Cell origin) {
        Arrays.fill(grid[origin.row()], '-');
        for (char[] row : grid)
            row[origin.col()] = '|';
        grid[origin.row()][origin.col()] = '+';
    }
    static void points(char[][] grid, List<Plot.Cell> cells) {
        int[][] counts = new int[grid.length][grid[0].length];
        for (Plot.Cell cell : cells)
            counts[cell.row()][cell.col()]++;
        for (int row = 0; row < grid.length; row++)
            for (int col = 0; col < grid[0].length; col++) {
                int count = counts[row][col];
                if (count > 0)
                    grid[row][col] = count == 1 ? '.' : count <= 3 ? 'o' : '@';
            }
    }
    static void mark(char[][] grid, Plot.Cell cell, char value) {
        grid[cell.row()][cell.col()] = value;
    }
    static boolean inside(int row, int col, int rc, int cc, int radius) {
        int x = col - cc, y = 2 * (row - rc);
        return x * x + y * y <= radius * radius;
    }
    static List<String> plots() {
        int width = settings.integer("SCREE_WIDTH"), kaiser =
                                                         Plot.rounded(average / fit.eigen.values()[0], width);
        List<String> out = new ArrayList<>(List.of("scree width " + width + " kaiser_column " + kaiser));
        for (int h = 0; h < p; h++)
            out.add(Plot.scree(Plot.rounded(fit.eigen.values()[h] / fit.eigen.values()[0], width), kaiser,
                               Plot.rounded(broken[h] * total / fit.eigen.values()[0], width), width) +
                    " pc" + (h + 1) + " " + real(fit.eigen.values()[h]));
        double mx = 0, my = 0, lx = 0, ly = 0;
        List<Observation> all = new ArrayList<>(observations);
        all.addAll(projections);
        for (Observation row : all) {
            mx = Math.max(mx, Math.abs(row.scores[0]));
            my = Math.max(my, Math.abs(row.scores[1]));
        }
        for (int j = 0; j < p; j++) {
            lx = Math.max(lx, Math.abs(loadings[j][0]));
            ly = Math.max(ly, Math.abs(loadings[j][1]));
        }
        double scale = 0.9 * Math.min(mx / lx, my / ly);
        width = settings.integer("BIPLOT_SIZE");
        int height = settings.second("BIPLOT_SIZE");
        char[][] grid = Plot.grid(height, width);
        Plot.Cell origin = Plot.biplot(0, 0, mx, my, width, height);
        axes(grid, origin);
        List<Plot.Cell> tips = new ArrayList<>(), cells = new ArrayList<>();
        for (int j = 0; j < p; j++) {
            Plot.Cell tip =
                Plot.biplot(scale * loadings[j][0], scale * loadings[j][1], mx, my, width, height);
            tips.add(tip);
            for (Plot.Cell cell : Plot.shaft(origin, tip))
                mark(grid, cell, Plot.shaftCharacter(origin, tip));
        }
        for (Observation row : observations)
            cells.add(Plot.biplot(row.scores[0], row.scores[1], mx, my, width, height));
        points(grid, cells);
        for (int i = 0; i < n; i++)
            if (!observations.get(i).flag.equals("-"))
                mark(grid, cells.get(i), 'X');
        for (Observation row : projections)
            mark(grid, Plot.biplot(row.scores[0], row.scores[1], mx, my, width, height), '*');
        for (int j = 0; j < p; j++)
            mark(grid, tips.get(j), (char)('A' + j));
        List<String> part = new ArrayList<>(List.of("biplot pc1 pc2 width " + width + " height " + height,
                                                    "x " + real(-mx) + " " + real(mx) + " y " + real(-my) +
                                                        " " + real(my) + " arrow_scale " + real(scale)));
        part.addAll(Plot.framed(grid));
        for (int j = 0; j < p; j++)
            part.add((char)('A' + j) + " " + names.get(j) + " " +
                     reals(new double[] {loadings[j][0], loadings[j][1]}));
        section(out, part);
        int radius = settings.integer("CIRCLE_RADIUS"), rc = radius / 2 + 1, cc = radius + 1;
        grid = Plot.grid(radius + 3, 2 * radius + 3);
        axes(grid, new Plot.Cell(rc, cc));
        for (int row = 0; row < grid.length; row++)
            for (int col = 0; col < grid[0].length; col++)
                if (inside(row, col, rc, cc, radius) &&
                    (!inside(row - 1, col, rc, cc, radius) || !inside(row + 1, col, rc, cc, radius) ||
                     !inside(row, col - 1, rc, cc, radius) || !inside(row, col + 1, rc, cc, radius)))
                    grid[row][col] = '.';
        for (int j = 0; j < p; j++)
            mark(grid, Plot.circle(circle[j][0], circle[j][1], radius), (char)('A' + j));
        part = new ArrayList<>(List.of("circle radius " + radius));
        part.addAll(Plot.framed(grid));
        for (int j = 0; j < p; j++)
            part.add((char)('A' + j) + " " + names.get(j) + " " + reals(circle[j]) + " " +
                     real(circle[j][0] * circle[j][0] + circle[j][1] * circle[j][1]));
        section(out, part);
        width = settings.integer("DIAGNOSTIC_SIZE");
        height = settings.second("DIAGNOSTIC_SIZE");
        double xmax = 2 * settings.number("T2_LIMIT"), ymax = 2 * settings.number("SPE_LIMIT");
        grid = Plot.grid(height, width);
        axes(grid, Plot.diagnostic(settings.number("T2_LIMIT"), settings.number("SPE_LIMIT"), xmax, ymax,
                                   width, height));
        cells = new ArrayList<>();
        for (Observation row : observations)
            cells.add(Plot.diagnostic(row.t2, row.spe, xmax, ymax, width, height));
        points(grid, cells);
        for (Observation row : projections)
            mark(grid, Plot.diagnostic(row.t2, row.spe, xmax, ymax, width, height), '*');
        part = new ArrayList<>(List.of("diagnostic width " + width + " height " + height + " t2_max " +
                                       real(xmax) + " spe_max " + real(ymax)));
        part.addAll(Plot.framed(grid));
        section(out, part);
        return out;
    }
    public static void main(String[] args) throws IOException {
        data = Dataset.read();
        settings = data.settings();
        names = data.data().names();
        p = names.size();
        top = settings.integer("TOP_ROWS");
        summarize();
        fit = new Fit(settings.text("MISSING"), settings.text("SCALING"));
        n = fit.ids.size();
        adequacy();
        variances();
        loadings();
        for (int i = 0; i < n; i++)
            observations.add(new Observation(fit.ids.get(i), fit.values[i]));
        for (Dataset.Row row : data.supplementary().rows())
            projections.add(new Observation(row.id(), row.values()));
        write("eigen.txt", eigenReport());
        write("loadings.csv", loadingsReport());
        write("scores.csv", scoresReport());
        write("outliers.txt", outliersReport());
        write("plots.txt", plots());
    }
}
