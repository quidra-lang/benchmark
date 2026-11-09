import java.io.IOException;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

public final class Main {
    static List<Dataset.Subject> subjects;
    static Dataset.Settings settings;
    static List<List<Dataset.Subject>> groups = new ArrayList<>();
    static List<CollectionSummary> collections = new ArrayList<>();
    static String real(double value) {
        if (Double.isNaN(value))
            return "NA";
        String s = String.format(Locale.ROOT, "%.4f", value);
        return s.equals("-0.0000") ? "0.0000" : s;
    }
    static String one(double value) {
        return String.format(Locale.ROOT, "%.1f", value);
    }
    static String day(int value) {
        return value < 0 ? "NA" : Integer.toString(value);
    }
    static String pad(String s, int width) {
        return " ".repeat(Math.max(0, width - s.length())) + s;
    }
    static String reals(double[] values) {
        List<String> result = new ArrayList<>();
        for (double value : values)
            result.add(real(value));
        return String.join(" ", result);
    }
    static void section(List<String> output, List<String> section) {
        if (!output.isEmpty())
            output.add("");
        output.addAll(section);
    }
    static void write(String name, List<String> lines) throws IOException {
        Files.writeString(Path.of("output", name), String.join("\n", lines) + "\n",
                          StandardCharsets.US_ASCII);
    }
    static int events(List<Dataset.Subject> rows) {
        int result = 0;
        for (Dataset.Subject s : rows)
            result += s.event();
        return result;
    }
    static List<Dataset.Subject> subset(List<Dataset.Subject> rows, String variable, String value) {
        List<Dataset.Subject> result = new ArrayList<>();
        for (Dataset.Subject s : rows)
            if (level(s, variable).equals(value))
                result.add(s);
        return result;
    }
    static String level(Dataset.Subject s, String variable) {
        return variable.equals("sex") ? s.sex() : Integer.toString(s.stage());
    }
    static List<String> levels(String variable) {
        SortedSet<String> result = new TreeSet<>();
        for (Dataset.Subject s : subjects)
            result.add(level(s, variable));
        return new ArrayList<>(result);
    }
    static final class CollectionSummary {
        String name;
        List<Dataset.Subject> subjects;
        List<Estimators.Row> rows;
        List<Estimators.Life> life;
        int events, personDays, maximum, followup = -1;
        double rate, rateLo, rateHi, lifeMedian = Double.NaN, rmst, se;
    }
    static CollectionSummary summarize(String name, List<Dataset.Subject> rows) {
        CollectionSummary c = new CollectionSummary();
        c.name = name;
        c.subjects = rows;
        c.rows = Estimators.km(rows, false);
        c.life = Estimators.life(rows, settings.lifeWidth, settings.lifeCount);
        c.events = events(rows);
        for (Dataset.Subject s : rows) {
            c.personDays += s.time();
            c.maximum = Math.max(c.maximum, s.time());
        }
        c.rate = (double)(1000 * c.events) / c.personDays;
        double eta = Numerics.Z / Math.sqrt(c.events);
        c.rateLo = Math.exp(Math.log(c.rate) - eta);
        c.rateHi = Math.exp(Math.log(c.rate) + eta);
        for (Estimators.Row r : Estimators.km(rows, true))
            if (r.survival <= 0.5) {
                c.followup = r.time;
                break;
            }
        double previous = 1;
        for (Estimators.Life r : c.life) {
            if (r.survival <= 0.5) {
                c.lifeMedian = r.start + settings.lifeWidth * (previous - 0.5) / (previous - r.survival);
                break;
            }
            previous = r.survival;
        }
        List<Estimators.Row> kept = new ArrayList<>();
        for (Estimators.Row r : c.rows)
            if (r.time <= settings.tau)
                kept.add(r);
        double[] tails = new double[kept.size() + 1];
        for (int i = kept.size(); i >= 0; i--) {
            int start = i == 0 ? 0 : kept.get(i - 1).time, end = i == kept.size() ? settings.tau
                                                                                  : kept.get(i).time;
            double survival = i == 0 ? 1 : kept.get(i - 1).survival;
            tails[i] = survival * (end - start) + (i == kept.size() ? 0 : tails[i + 1]);
        }
        c.rmst = tails[0];
        double variance = 0;
        for (int i = 1; i < tails.length; i++) {
            Estimators.Row r = kept.get(i - 1);
            variance += tails[i] * tails[i] * ((double)r.events / (r.risk * (r.risk - r.events)));
        }
        c.se = Math.sqrt(variance);
        return c;
    }
    static int percentile(CollectionSummary c, double q, int field) {
        for (Estimators.Row r : c.rows) {
            double value = field == 0 ? r.survival : r.survival == 0 ? 0 : field == 1 ? r.lower : r.upper;
            if (value <= q)
                return r.time;
        }
        return -1;
    }
    static void kmReport() throws IOException {
        List<String> output = new ArrayList<>(),
                     life = new ArrayList<>(List.of(
                         "group,interval,at_risk,events,withdrawn,exposed,q,survival,std_err,hazard"));
        for (CollectionSummary c : collections) {
            List<String> block = new ArrayList<>(
                List.of("group " + c.name + " subjects " + c.subjects.size() + " events " + c.events +
                            " censored " + (c.subjects.size() - c.events) + " max_time " + c.maximum,
                        "person_days " + c.personDays + " rate " + real(c.rate) + " lower " + real(c.rateLo) +
                            " upper " + real(c.rateHi),
                        "followup_median " + day(c.followup), "life_table_median " + real(c.lifeMedian)));
            for (int p : List.of(25, 50, 75)) {
                double q = 1 - p / 100.0;
                block.add("percentile " + p + " time " + day(percentile(c, q, 0)) + " lower " +
                          day(percentile(c, q, 1)) + " upper " + day(percentile(c, q, 2)));
            }
            block.add("rmst tau " + settings.tau + " estimate " + real(c.rmst) + " se " + real(c.se) +
                      " lower " + real(c.rmst - Numerics.Z * c.se) + " upper " +
                      real(c.rmst + Numerics.Z * c.se));
            for (int time : settings.report) {
                Estimators.Row r = Estimators.at(c.rows, time);
                int events = 0;
                for (Dataset.Subject s : c.subjects)
                    if (s.time() <= time)
                        events += s.event();
                block.add("at " + time + " at_risk " + Estimators.risk(c.subjects, time) + " events " +
                          events + " survival " + real(r.survival) + " std_err " + real(r.se) + " lower " +
                          real(r.lower) + " upper " + real(r.upper) + " cum_hazard " + real(r.hazard) +
                          " hazard_se " + real(r.hazardSe));
            }
            String header = "";
            for (String name : List.of("time", "at_risk", "events", "censored", "survival", "std_err",
                                       "lower", "upper", "cum_haz", "haz_se"))
                header += pad(name, 9);
            block.add(header);
            for (Estimators.Row r : c.rows) {
                List<String> fields =
                    List.of(Integer.toString(r.time), Integer.toString(r.risk), Integer.toString(r.events),
                            Integer.toString(r.censored), real(r.survival), real(r.se), real(r.lower),
                            real(r.upper), real(r.hazard), real(r.hazardSe));
                String line = "";
                for (String value : fields)
                    line += pad(value, 9);
                block.add(line);
            }
            section(output, block);
            for (Estimators.Life r : c.life)
                life.add(c.name + "," + r.start + "-" + r.end + "," + r.risk + "," + r.events + "," +
                         r.withdrawn + "," + one(r.exposed2 / 2.0) + "," + real(r.q) + "," +
                         real(r.survival) + "," + real(r.se) + "," + real(r.hazard));
        }
        write("km_tables.txt", output);
        write("life_table.csv", life);
    }
    static List<String> baseline() {
        List<String> output = new ArrayList<>(List.of("baseline"));
        for (CollectionSummary c : collections) {
            int n = c.subjects.size(), sum = 0, male = 0;
            int[] stage = new int[4];
            List<Integer> ages = new ArrayList<>();
            for (Dataset.Subject s : c.subjects) {
                sum += s.age();
                male += s.sex().equals("M") ? 1 : 0;
                stage[s.stage() - 1]++;
                ages.add(s.age());
            }
            double mean = (double)sum / n, variance = 0;
            for (Dataset.Subject s : c.subjects)
                variance += (s.age() - mean) * (s.age() - mean);
            Collections.sort(ages);
            double median = (ages.get((n - 1) / 2) + ages.get(n / 2)) / 2.0;
            output.add("  group " + c.name + " subjects " + n + " age_mean " + real(mean) + " age_sd " +
                       real(Math.sqrt(variance / (n - 1))) + " age_median " + one(median) + " male " + male +
                       " stage " + stage[0] + " " + stage[1] + " " + stage[2] + " " + stage[3]);
        }
        List<Dataset.Subject> sorted = new ArrayList<>(subjects);
        sorted.sort(Comparator.comparingInt(Dataset.Subject::age).thenComparingInt(Dataset.Subject::id));
        Map<Integer, Double> ranks = new HashMap<>();
        int position = 0, ties = 0;
        while (position < sorted.size()) {
            int end = position + 1;
            while (end < sorted.size() && sorted.get(end).age() == sorted.get(position).age())
                end++;
            int t = end - position;
            ties += t * t * t - t;
            double rank = (position + 1 + end) / 2.0;
            for (int i = position; i < end; i++)
                ranks.put(sorted.get(i).id(), rank);
            position = end;
        }
        double[] rankSum = new double[groups.size()];
        for (Dataset.Subject s : subjects)
            rankSum[settings.groups.indexOf(s.group())] += ranks.get(s.id());
        double sum = 0;
        for (int g = 0; g < groups.size(); g++)
            sum += rankSum[g] * rankSum[g] / groups.get(g).size();
        int n = subjects.size();
        double w0 = 12 * sum / (n * (n + 1)) - 3 * (n + 1), w = w0 / (1 - (double)ties / (n * n * n - n));
        output.add("  age kruskal_wallis chisq " + real(w) + " df " + (groups.size() - 1) + " p " +
                   real(Numerics.pvalue(w, groups.size() - 1)));
        for (String variable : List.of("sex", "stage")) {
            List<String> levels = levels(variable);
            double chi2 = 0;
            for (int g = 0; g < groups.size(); g++)
                for (String value : levels) {
                    int observed = subset(groups.get(g), variable, value).size(),
                        column = subset(subjects, variable, value).size();
                    double expected = (double)(groups.get(g).size() * column) / n;
                    chi2 += (observed - expected) * (observed - expected) / expected;
                }
            int df = (groups.size() - 1) * (levels.size() - 1);
            output.add("  " + variable + " chisq " + real(chi2) + " df " + df + " p " +
                       real(Numerics.pvalue(chi2, df)));
        }
        return output;
    }
    static String testLine(String prefix, GroupTests.Result r) {
        return prefix + " chisq " + real(r.chi2) + " df " + r.degrees + " p " + real(r.pvalue);
    }
    static void groupLines(List<String> output, GroupTests.Result r) {
        for (int g = 0; g < r.groups.size(); g++)
            output.add("  group " + r.groups.get(g) + " events " + r.events[g] + " observed " +
                       real(r.observed[g]) + " expected " + real(r.expected[g]) + " o_minus_e " +
                       real(r.observed[g] - r.expected[g]) + " variance " + real(r.covariance[g][g]));
    }
    static final class Pair {
        GroupTests.Result test;
        double hr, phi, lower, upper, adjusted;
        int a, b;
    }
    static Pair pair(List<Dataset.Subject> rows, int a, int b) {
        Pair result = new Pair();
        result.a = a;
        result.b = b;
        result.test = GroupTests.weighted(rows, List.of(settings.groups.get(a), settings.groups.get(b)), 0,
                                          subjects.size());
        double[] o = result.test.observed, x = result.test.expected;
        result.hr = (o[1] / x[1]) / (o[0] / x[0]);
        result.phi = 1 / x[0] + 1 / x[1];
        double log = Math.log(result.hr), se = Math.sqrt(result.phi);
        result.lower = Math.exp(log - Numerics.Z * se);
        result.upper = Math.exp(log + Numerics.Z * se);
        return result;
    }
    static List<Dataset.Subject> pairRows(List<Dataset.Subject> rows, int a, int b) {
        List<Dataset.Subject> result = new ArrayList<>();
        for (Dataset.Subject s : rows)
            if (s.group().equals(settings.groups.get(a)) || s.group().equals(settings.groups.get(b)))
                result.add(s);
        return result;
    }
    static String difference(double delta, double se) {
        double z = delta / se;
        return "difference " + real(delta) + " se " + real(se) + " lower " + real(delta - Numerics.Z * se) +
            " upper " + real(delta + Numerics.Z * se) + " z " + real(z) + " p " +
            real(Numerics.pvalue(z * z, 1));
    }
    static void testsReport() throws IOException {
        List<String> output = baseline(), part = new ArrayList<>();
        GroupTests.Result logrank = null;
        for (int weight = 0; weight < 3; weight++) {
            GroupTests.Result r = GroupTests.weighted(subjects, settings.groups, weight, subjects.size());
            part.add(testLine("test " + GroupTests.WEIGHTS.get(weight), r));
            groupLines(part, r);
            if (weight == 0)
                logrank = r;
        }
        double u = 0, variance = 0;
        for (int g = 0; g < groups.size(); g++) {
            u += (g + 1) * (logrank.observed[g] - logrank.expected[g]);
            double inner = 0;
            for (int h = 0; h < groups.size(); h++)
                inner += (g + 1) * (h + 1) * logrank.covariance[g][h];
            variance += inner;
        }
        double trend = u * u / variance;
        part.add("test logrank_trend chisq " + real(trend) + " df 1 p " + real(Numerics.pvalue(trend, 1)));
        section(output, part);
        part = new ArrayList<>();
        List<String> strata = levels(settings.strata);
        for (int weight = 0; weight < 3; weight++) {
            List<GroupTests.Result> results = new ArrayList<>();
            List<List<Dataset.Subject>> rows = new ArrayList<>();
            for (String level : strata) {
                List<Dataset.Subject> stratum = subset(subjects, settings.strata, level);
                rows.add(stratum);
                results.add(GroupTests.weighted(stratum, settings.groups, weight, subjects.size()));
            }
            GroupTests.Result combined = GroupTests.combined(results, settings.groups);
            part.add(testLine("stratified " + GroupTests.WEIGHTS.get(weight) + " by " + settings.strata,
                              combined));
            for (int i = 0; i < strata.size(); i++) {
                GroupTests.Result r = results.get(i);
                part.add("  stratum " + strata.get(i) + " subjects " + rows.get(i).size() + " events " +
                         events(rows.get(i)) + " chisq " + real(r.chi2) + " p " + real(r.pvalue));
            }
            groupLines(part, combined);
        }
        section(output, part);
        List<Dataset.Subject> landmark = new ArrayList<>();
        for (Dataset.Subject s : subjects)
            if (s.time() > settings.landmark)
                landmark.add(s);
        GroupTests.Result lm = GroupTests.weighted(landmark, settings.groups, 0, subjects.size());
        part = new ArrayList<>(
            List.of(testLine("landmark " + settings.landmark + " subjects " + landmark.size(), lm)));
        groupLines(part, lm);
        section(output, part);
        List<Pair> pairs = new ArrayList<>();
        for (int a = 0; a < groups.size(); a++)
            for (int b = a + 1; b < groups.size(); b++)
                pairs.add(pair(pairRows(subjects, a, b), a, b));
        List<Integer> order = new ArrayList<>();
        for (int i = 0; i < pairs.size(); i++)
            order.add(i);
        order.sort((a, b)
                       -> pairs.get(a).test.pvalue != pairs.get(b).test.pvalue
                              ? Double.compare(pairs.get(a).test.pvalue, pairs.get(b).test.pvalue)
                              : Integer.compare(a, b));
        double previous = 0;
        for (int r = 0; r < order.size(); r++) {
            Pair p = pairs.get(order.get(r));
            p.adjusted = Math.max(previous, Math.min(1, (pairs.size() - r) * p.test.pvalue));
            previous = p.adjusted;
        }
        part = new ArrayList<>(List.of("pairwise logrank adjust holm"));
        for (Pair p : pairs)
            part.add("  " + settings.groups.get(p.a) + " " + settings.groups.get(p.b) + " chisq " +
                     real(p.test.chi2) + " p " + real(p.test.pvalue) + " p_holm " + real(p.adjusted) +
                     " hr " + real(p.hr) + " lower " + real(p.lower) + " upper " + real(p.upper));
        section(output, part);
        part = new ArrayList<>(List.of("subgroups reference " + settings.groups.get(0)));
        for (String variable : settings.subgroups)
            for (int b = 1; b < groups.size(); b++) {
                List<String> levels = levels(variable);
                List<Pair> estimates = new ArrayList<>();
                for (String level : levels) {
                    List<Dataset.Subject> rows = pairRows(subset(subjects, variable, level), 0, b);
                    Pair p = pair(rows, 0, b);
                    estimates.add(p);
                    part.add("  " + variable + " " + level + " " + settings.groups.get(b) + " subjects " +
                             rows.size() + " events " + events(rows) + " hr " + real(p.hr) + " lower " +
                             real(p.lower) + " upper " + real(p.upper) + " p " + real(p.test.pvalue));
                }
                double numerator = 0, denominator = 0;
                for (Pair p : estimates) {
                    numerator += (1 / p.phi) * Math.log(p.hr);
                    denominator += 1 / p.phi;
                }
                double mean = numerator / denominator, q = 0;
                for (Pair p : estimates) {
                    double delta = Math.log(p.hr) - mean;
                    q += (1 / p.phi) * delta * delta;
                }
                int df = levels.size() - 1;
                part.add("  " + variable + " " + settings.groups.get(b) + " heterogeneity chisq " + real(q) +
                         " df " + df + " p " + real(Numerics.pvalue(q, df)));
            }
        section(output, part);
        CollectionSummary control = collections.get(0);
        part = new ArrayList<>(List.of("rmst_difference tau " + settings.tau + " reference " + control.name));
        for (int g = 1; g < groups.size(); g++) {
            CollectionSummary c = collections.get(g);
            part.add("  " + c.name + " " +
                     difference(c.rmst - control.rmst, Math.sqrt(c.se * c.se + control.se * control.se)));
        }
        section(output, part);
        part = new ArrayList<>(List.of("rate_ratio reference " + control.name));
        for (int g = 1; g < groups.size(); g++) {
            CollectionSummary c = collections.get(g);
            double ratio = c.rate / control.rate, se = Math.sqrt(1.0 / c.events + 1.0 / control.events),
                   log = Math.log(ratio), z = log / se;
            part.add("  " + c.name + " ratio " + real(ratio) + " lower " +
                     real(Math.exp(log - Numerics.Z * se)) + " upper " +
                     real(Math.exp(log + Numerics.Z * se)) + " z " + real(z) + " p " +
                     real(Numerics.pvalue(z * z, 1)));
        }
        section(output, part);
        part = new ArrayList<>(List.of("survival_difference reference " + control.name));
        for (int time : settings.report)
            for (int g = 1; g < groups.size(); g++) {
                Estimators.Row a = Estimators.at(control.rows, time),
                               b = Estimators.at(collections.get(g).rows, time);
                part.add("  at " + time + " " + settings.groups.get(g) + " " +
                         difference(b.survival - a.survival, Math.sqrt(b.se * b.se + a.se * a.se)));
            }
        section(output, part);
        write("tests.txt", output);
    }
    static double covariate(Dataset.Subject s, String name) {
        return name.equals("age") ? s.age()
        : name.equals("male")     ? (s.sex().equals("M") ? 1 : 0)
        : name.equals("stage")    ? s.stage()
        : s.group().equals(name)  ? 1
                                  : 0;
    }
    static String coefficient(double beta, double se) {
        double z = beta / se;
        return "coef " + real(beta) + " se " + real(se) + " z " + real(z) + " p " +
            real(Numerics.pvalue(z * z, 1)) + " hr " + real(Math.exp(beta)) + " lower " +
            real(Math.exp(beta - Numerics.Z * se)) + " upper " + real(Math.exp(beta + Numerics.Z * se));
    }
    static double hazard(SortedMap<Integer, Double> hazards, int time) {
        double value = 0;
        for (var e : hazards.entrySet()) {
            if (e.getKey() > time)
                break;
            value = e.getValue();
        }
        return value;
    }
    record Residual(int index, double martingale, double deviance) {}
    static void coxReport() throws IOException {
        int n = subjects.size(), p = settings.covariates.size();
        double[][] x = new double[n][p];
        for (int j = 0; j < n; j++)
            for (int c = 0; c < p; c++)
                x[j][c] = covariate(subjects.get(j), settings.covariates.get(c));
        Cox.Fit fit = Cox.fit(subjects, x);
        Cox.Evaluation end = fit.finalEvaluation, start = fit.initial;
        double[][] covariance = Numerics.inverse(end.information);
        List<String> output =
            new ArrayList<>(List.of("cox covariates " + String.join(" ", settings.covariates) + " subjects " +
                                    n + " events " + events(subjects) + " event_times " + end.times.size()));
        for (Cox.Iteration i : fit.iterations)
            output.add("iter " + i.number() + " loglik " + real(i.likelihood()) + " beta " + reals(i.beta()));
        output.add("final loglik " + real(end.likelihood) + " null_loglik " + real(start.likelihood));
        for (int c = 0; c < p; c++)
            output.add("term " + settings.covariates.get(c) + " " +
                       coefficient(fit.beta[c], Math.sqrt(covariance[c][c])));
        for (int a = 0; a < p; a++)
            if (settings.groups.contains(settings.covariates.get(a)))
                for (int b = a + 1; b < p; b++)
                    if (settings.groups.contains(settings.covariates.get(b)))
                        output.add("contrast " + settings.covariates.get(b) + " vs " +
                                   settings.covariates.get(a) + " " +
                                   coefficient(fit.beta[b] - fit.beta[a],
                                               Math.sqrt(covariance[b][b] + covariance[a][a] -
                                                         2 * covariance[a][b])));
        double likelihoodRatio = 2 * (end.likelihood - start.likelihood), wald = 0, score = 0;
        for (int c = 0; c < p; c++) {
            double inner = 0;
            for (int d = 0; d < p; d++)
                inner += end.information[c][d] * fit.beta[d];
            wald += fit.beta[c] * inner;
        }
        double[] solved = Numerics.solve(start.information, start.score);
        for (int c = 0; c < p; c++)
            score += start.score[c] * solved[c];
        for (String name : List.of("likelihood_ratio", "wald", "score")) {
            double chi2 = name.equals("likelihood_ratio") ? likelihoodRatio
                          : name.equals("wald")           ? wald
                                                          : score;
            output.add(name + " chisq " + real(chi2) + " df " + p + " p " + real(Numerics.pvalue(chi2, p)));
        }
        for (int c = 0; c < p; c++) {
            double ll = start.likelihood;
            if (p > 1) {
                double[][] reduced = new double[n][p - 1];
                for (int j = 0; j < n; j++) {
                    int target = 0;
                    for (int d = 0; d < p; d++)
                        if (d != c)
                            reduced[j][target++] = x[j][d];
                }
                ll = Cox.fit(subjects, reduced).finalEvaluation.likelihood;
            }
            double chi2 = 2 * (end.likelihood - ll);
            output.add("drop " + settings.covariates.get(c) + " loglik " + real(ll) + " chisq " + real(chi2) +
                       " df 1 p " + real(Numerics.pvalue(chi2, 1)));
        }
        int comparable = 0, concordant = 0, tied = 0;
        for (int i = 0; i < n; i++)
            if (subjects.get(i).event() == 1)
                for (int j = 0; j < n; j++)
                    if (i != j && (subjects.get(i).time() < subjects.get(j).time() ||
                                   (subjects.get(i).time() == subjects.get(j).time() &&
                                    subjects.get(j).event() == 0))) {
                        comparable++;
                        boolean equal = true;
                        for (int c = 0; c < p; c++)
                            if (x[i][c] != x[j][c])
                                equal = false;
                        if (equal)
                            tied++;
                        else if (end.theta[i] > end.theta[j])
                            concordant++;
                    }
        output.add("concordance " + real((double)(2 * concordant + tied) / (2 * comparable)) +
                   " comparable " + comparable + " concordant " + concordant + " tied " + tied);
        List<Integer> eventOrder = new ArrayList<>();
        for (int i = 0; i < n; i++)
            if (subjects.get(i).event() == 1)
                eventOrder.add(i);
        eventOrder.sort((a, b)
                            -> subjects.get(a).time() != subjects.get(b).time()
                                   ? Integer.compare(subjects.get(a).time(), subjects.get(b).time())
                                   : Integer.compare(subjects.get(a).id(), subjects.get(b).id()));
        int timeSum = 0;
        for (int i : eventOrder)
            timeSum += subjects.get(i).time();
        double timeMean = (double)timeSum / eventOrder.size();
        for (int c = 0; c < p; c++) {
            double[] residual = new double[eventOrder.size()];
            double sum = 0;
            for (int j = 0; j < eventOrder.size(); j++) {
                int i = eventOrder.get(j);
                Cox.Risk r = end.times.get(subjects.get(i).time());
                residual[j] = x[i][c] - r.s1()[c] / r.s0();
                sum += residual[j];
            }
            double mean = sum / eventOrder.size(), sxy = 0, sxx = 0, syy = 0;
            for (int j = 0; j < eventOrder.size(); j++) {
                double dx = residual[j] - mean, dy = subjects.get(eventOrder.get(j)).time() - timeMean;
                sxy += dx * dy;
                sxx += dx * dx;
                syy += dy * dy;
            }
            double rho = sxy / Math.sqrt(sxx * syy),
                   z = 0.5 * Math.log((1 + rho) / (1 - rho)) * Math.sqrt(eventOrder.size() - 3);
            output.add("ph_check " + settings.covariates.get(c) + " rho " + real(rho) + " z " + real(z) +
                       " p " + real(Numerics.pvalue(z * z, 1)));
        }
        SortedMap<Integer, Double> cumulative = new TreeMap<>();
        double lambda = 0;
        for (var e : end.times.entrySet()) {
            lambda += e.getValue().events() / e.getValue().s0();
            cumulative.put(e.getKey(), lambda);
        }
        List<Residual> residuals = new ArrayList<>();
        for (int i = 0; i < n; i++) {
            Dataset.Subject s = subjects.get(i);
            double m = s.event() - hazard(cumulative, s.time()) * Math.exp(end.theta[i]);
            double deviance = Math.sqrt(s.event() == 1 ? -2 * (m + Math.log(1 - m)) : -2 * m);
            if (!(m > 0))
                deviance = -deviance;
            residuals.add(new Residual(i, m, deviance));
        }
        residuals.sort(
            (a, b)
                -> Math.abs(a.deviance()) != Math.abs(b.deviance())
                       ? Double.compare(Math.abs(b.deviance()), Math.abs(a.deviance()))
                       : Integer.compare(subjects.get(a.index()).id(), subjects.get(b.index()).id()));
        output.add("residuals top " + settings.residuals);
        for (int j = 0; j < settings.residuals; j++) {
            Residual r = residuals.get(j);
            Dataset.Subject s = subjects.get(r.index());
            output.add("  id " + s.id() + " group " + s.group() + " time " + s.time() + " event " +
                       s.event() + " martingale " + real(r.martingale()) + " deviance " + real(r.deviance()));
        }
        double[] means = new double[p];
        String meanLine = "adjusted_survival mean";
        int standard = 0;
        for (int c = 0; c < p; c++)
            if (List.of("age", "male", "stage").contains(settings.covariates.get(c))) {
                int sum = 0;
                for (int i = 0; i < n; i++)
                    sum += (int)x[i][c];
                means[c] = (double)sum / n;
                meanLine += " " + settings.covariates.get(c) + " " + real(means[c]);
                standard++;
            }
        output.add(meanLine + (standard == 0 ? " none" : ""));
        double[] risks = new double[groups.size()];
        for (int g = 0; g < groups.size(); g++) {
            double theta = 0;
            for (int c = 0; c < p; c++) {
                String name = settings.covariates.get(c);
                double value =
                    settings.groups.contains(name) ? (name.equals(settings.groups.get(g)) ? 1 : 0) : means[c];
                theta += fit.beta[c] * value;
            }
            risks[g] = Math.exp(theta);
        }
        for (int time : settings.report) {
            String line = "  at " + time;
            for (int g = 0; g < groups.size(); g++)
                line +=
                    " " + settings.groups.get(g) + " " + real(Math.exp(-hazard(cumulative, time) * risks[g]));
            output.add(line);
        }
        String line = "  median";
        for (int g = 0; g < groups.size(); g++) {
            int median = -1;
            for (var e : cumulative.entrySet())
                if (Math.exp(-e.getValue() * risks[g]) <= 0.5) {
                    median = e.getKey();
                    break;
                }
            line += " " + settings.groups.get(g) + " " + day(median);
        }
        output.add(line);
        write("cox.txt", output);
    }
    static void plotReport() throws IOException {
        List<List<Estimators.Row>> tables = new ArrayList<>();
        for (int g = 0; g < groups.size(); g++)
            tables.add(collections.get(g).rows);
        List<String> output = new ArrayList<>(List.of("km_plot width " + settings.width + " height " +
                                                      settings.height + " time " + settings.horizon));
        String legend = "legend";
        for (int g = 0; g < groups.size(); g++)
            legend += " " + (char)('A' + g) + " " + settings.groups.get(g);
        output.add(legend);
        output.addAll(Plot.draw(groups, tables, settings.width, settings.height, settings.horizon));
        output.add("time 0 to " + settings.horizon + " days, " + (settings.horizon / settings.width) +
                   " days per column");
        String line = "at_risk";
        for (int i = 0; i <= settings.divisions; i++)
            line += " " + (i * (settings.horizon / settings.divisions));
        output.add(line);
        for (int g = 0; g < groups.size(); g++) {
            line = settings.groups.get(g);
            for (int i = 0; i <= settings.divisions; i++)
                line += " " + Estimators.risk(groups.get(g), i * (settings.horizon / settings.divisions));
            output.add(line);
        }
        write("km_plot.txt", output);
    }
    public static void main(String[] args) throws IOException {
        Dataset.Data data = Dataset.read();
        subjects = data.subjects();
        settings = data.settings();
        for (String group : settings.groups) {
            List<Dataset.Subject> rows = new ArrayList<>();
            for (Dataset.Subject s : subjects)
                if (s.group().equals(group))
                    rows.add(s);
            groups.add(rows);
            collections.add(summarize(group, rows));
        }
        collections.add(summarize("all", subjects));
        Files.createDirectories(Path.of("output"));
        kmReport();
        testsReport();
        coxReport();
        plotReport();
    }
}
