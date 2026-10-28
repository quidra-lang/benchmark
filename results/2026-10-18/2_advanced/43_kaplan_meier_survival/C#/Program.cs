using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Program {
    public static List<Dataset.Subject> subjects;
    public static Dataset.Settings settings;
    public static List<List<Dataset.Subject>> groups = new();
    public static List<CollectionSummary> collections = new();
    public static string Real(double value) {
        if (double.IsNaN(value))
            return "NA";
        string s = value.ToString("F4", CultureInfo.InvariantCulture);
        return s.Equals("-0.0000") ? "0.0000" : s;
    }
    public static string One(double value) {
        return value.ToString("F1", CultureInfo.InvariantCulture);
    }
    public static string Day(int value) {
        return value < 0 ? "NA" : Convert.ToString(value);
    }
    public static string Pad(string s, int width) {
        return " ".Repeat(Math.Max(0, width - s.Length)) + s;
    }
    public static string Reals(double[] values) {
        List<string> result = new();
        foreach (double value in values)
            result.Add(Real(value));
        return string.Join(" ", result);
    }
    public static void Section(List<string> output, List<string> section) {
        if (output.Count != 0)
            output.Add("");
        output.AddRange(section);
    }
    public static void Write(string name, List<string> lines) {
        File.WriteAllText(Path.Combine("output", name), string.Join("\n", lines) + "\n", Encoding.ASCII);
    }
    public static int Events(List<Dataset.Subject> rows) {
        int result = 0;
        foreach (Dataset.Subject s in rows)
            result += s.eventFlag;
        return result;
    }
    public static List<Dataset.Subject> Subset(List<Dataset.Subject> rows, string variable, string value) {
        List<Dataset.Subject> result = new();
        foreach (Dataset.Subject s in rows)
            if (Level(s, variable).Equals(value))
                result.Add(s);
        return result;
    }
    public static string Level(Dataset.Subject s, string variable) {
        return variable.Equals("sex") ? s.sex : Convert.ToString(s.stage);
    }
    public static List<string> Levels(string variable) {
        SortedSet<string> result = new(StringComparer.Ordinal);
        foreach (Dataset.Subject s in subjects)
            result.Add(Level(s, variable));
        return new(result);
    }
    public sealed class CollectionSummary {
        public string name;
        public List<Dataset.Subject> subjects;
        public List<Estimators.Row> rows;
        public List<Estimators.Life> life;
        public int events, personDays, maximum, followup = -1;
        public double rate, rateLo, rateHi, lifeMedian = double.NaN, rmst, se;
    }
    public static CollectionSummary Summarize(string name, List<Dataset.Subject> rows) {
        CollectionSummary c = new CollectionSummary();
        c.name = name;
        c.subjects = rows;
        c.rows = Estimators.Km(rows, false);
        c.life = Estimators.Life(rows, settings.lifeWidth, settings.lifeCount);
        c.events = Events(rows);
        foreach (Dataset.Subject s in rows) {
            c.personDays += s.time;
            c.maximum = Math.Max(c.maximum, s.time);
        }
        c.rate = (double)(1000 * c.events) / c.personDays;
        double eta = Numerics.Z / Math.Sqrt(c.events);
        c.rateLo = Math.Exp(Math.Log(c.rate) - eta);
        c.rateHi = Math.Exp(Math.Log(c.rate) + eta);
        foreach (Estimators.Row r in Estimators.Km(rows, true))
            if (r.survival <= 0.5) {
                c.followup = r.time;
                break;
            }
        double previous = 1;
        foreach (Estimators.Life r in c.life) {
            if (r.survival <= 0.5) {
                c.lifeMedian = r.start + settings.lifeWidth * (previous - 0.5) / (previous - r.survival);
                break;
            }
            previous = r.survival;
        }
        List<Estimators.Row> kept = new();
        foreach (Estimators.Row r in c.rows)
            if (r.time <= settings.tau)
                kept.Add(r);
        double[] tails = new double[kept.Count + 1];
        for (int i = kept.Count; i >= 0; i--) {
            int start = i == 0 ? 0 : kept[i - 1].time, end = i == kept.Count ? settings.tau : kept[i].time;
            double survival = i == 0 ? 1 : kept[i - 1].survival;
            tails[i] = survival * (end - start) + (i == kept.Count ? 0 : tails[i + 1]);
        }
        c.rmst = tails[0];
        double variance = 0;
        for (int i = 1; i < tails.Length; i++) {
            Estimators.Row r = kept[i - 1];
            variance += tails[i] * tails[i] * ((double)r.events / (r.risk * (r.risk - r.events)));
        }
        c.se = Math.Sqrt(variance);
        return c;
    }
    public static int Percentile(CollectionSummary c, double q, int field) {
        foreach (Estimators.Row r in c.rows) {
            double value = field == 0 ? r.survival : r.survival == 0 ? 0 : field == 1 ? r.lower : r.upper;
            if (value <= q)
                return r.time;
        }
        return -1;
    }
    public static void KmReport() {
        List<string> output = new(),
                     life =
                         new(["group,interval,at_risk,events,withdrawn,exposed,q,survival,std_err,hazard"]);
        foreach (CollectionSummary c in collections) {
            List<string> block = new([
                "group " + c.name + " subjects " + c.subjects.Count + " events " + c.events + " censored " +
                    (c.subjects.Count - c.events) + " max_time " + c.maximum,
                "person_days " + c.personDays + " rate " + Real(c.rate) + " lower " + Real(c.rateLo) +
                    " upper " + Real(c.rateHi),
                "followup_median " + Day(c.followup), "life_table_median " + Real(c.lifeMedian)
            ]);
            foreach (int p in new int[] { 25, 50, 75 }) {
                double q = 1 - p / 100.0;
                block.Add("percentile " + p + " time " + Day(Percentile(c, q, 0)) + " lower " +
                          Day(Percentile(c, q, 1)) + " upper " + Day(Percentile(c, q, 2)));
            }
            block.Add("rmst tau " + settings.tau + " estimate " + Real(c.rmst) + " se " + Real(c.se) +
                      " lower " + Real(c.rmst - Numerics.Z * c.se) + " upper " +
                      Real(c.rmst + Numerics.Z * c.se));
            foreach (int time in settings.report) {
                Estimators.Row r = Estimators.At(c.rows, time);
                int events = 0;
                foreach (Dataset.Subject s in c.subjects)
                    if (s.time <= time)
                        events += s.eventFlag;
                block.Add("at " + time + " at_risk " + Estimators.Risk(c.subjects, time) + " events " +
                          events + " survival " + Real(r.survival) + " std_err " + Real(r.se) + " lower " +
                          Real(r.lower) + " upper " + Real(r.upper) + " cum_hazard " + Real(r.hazard) +
                          " hazard_se " + Real(r.hazardSe));
            }
            string header = "";
            for (string name: [
                     "time", "at_risk", "events", "censored", "survival", "std_err", "lower", "upper",
                     "cum_haz", "haz_se"
                 ])
                header += Pad(name, 9);
            block.Add(header);
            foreach (Estimators.Row r in c.rows) {
                List<string> fields = [
                    Convert.ToString(r.time), Convert.ToString(r.risk), Convert.ToString(r.events),
                    Convert.ToString(r.censored), Real(r.survival), Real(r.se), Real(r.lower), Real(r.upper),
                    Real(r.hazard), Real(r.hazardSe)
                ];
                string line = "";
                foreach (string value in fields)
                    line += Pad(value, 9);
                block.Add(line);
            }
            Section(output, block);
            foreach (Estimators.Life r in c.life)
                life.Add(c.name + "," + r.start + "-" + r.end + "," + r.risk + "," + r.events + "," +
                         r.withdrawn + "," + One(r.exposed2 / 2.0) + "," + Real(r.q) + "," +
                         Real(r.survival) + "," + Real(r.se) + "," + Real(r.hazard));
        }
        Write("km_tables.txt", output);
        Write("life_table.csv", life);
    }
    public static List<string> Baseline() {
        List<string> output = new(["baseline"]);
        foreach (CollectionSummary c in collections) {
            int n = c.subjects.Count, sum = 0, male = 0;
            int[] stage = new int[4];
            List<int> ages = new();
            foreach (Dataset.Subject s in c.subjects) {
                sum += s.age;
                male += s.sex.Equals("M") ? 1 : 0;
                stage[s.stage - 1]++;
                ages.Add(s.age);
            }
            double mean = (double)sum / n, variance = 0;
            foreach (Dataset.Subject s in c.subjects)
                variance += (s.age - mean) * (s.age - mean);
            ages.Sort();
            double median = (ages[(n - 1) / 2] + ages[n / 2]) / 2.0;
            output.Add("  group " + c.name + " subjects " + n + " age_mean " + Real(mean) + " age_sd " +
                       Real(Math.Sqrt(variance / (n - 1))) + " age_median " + One(median) + " male " + male +
                       " stage " + stage[0] + " " + stage[1] + " " + stage[2] + " " + stage[3]);
        }
        List<Dataset.Subject> sorted = new(subjects);
        sorted.Sort(Comparer<Dataset.Subject>.Create((a, b) => a.age != b.age ? a.age.CompareTo(b.age)
                                                                              : a.id.CompareTo(b.id)));
        Dictionary<int, double> ranks = new();
        int position = 0, ties = 0;
        while (position < sorted.Count) {
            int end = position + 1;
            while (end < sorted.Count && sorted[end].age == sorted[position].age)
                end++;
            int t = end - position;
            ties += t * t * t - t;
            double rank = (position + 1 + end) / 2.0;
            for (int i = position; i < end; i++)
                ranks[sorted[i].id] = rank;
            position = end;
        }
        double[] rankSum = new double[groups.Count];
        foreach (Dataset.Subject s in subjects)
            rankSum[settings.groups.IndexOf(s.group)] += ranks[s.id];
        double rankTotal = 0;
        for (int g = 0; g < groups.Count; g++)
            rankTotal += rankSum[g] * rankSum[g] / groups[g].Count;
        int subjectCount = subjects.Count;
        double w0 = 12 * rankTotal / (subjectCount * (subjectCount + 1)) - 3 * (subjectCount + 1),
               w = w0 / (1 - (double)ties / (subjectCount * subjectCount * subjectCount - subjectCount));
        output.Add("  age kruskal_wallis chisq " + Real(w) + " df " + (groups.Count - 1) + " p " +
                   Real(Numerics.Pvalue(w, groups.Count - 1)));
        foreach (string variable in new string[] { "sex", "stage" }) {
            List<string> levels = Levels(variable);
            double chi2 = 0;
            for (int g = 0; g < groups.Count; g++)
                foreach (string value in levels) {
                    int observed = Subset(groups[g], variable, value).Count,
                        column = Subset(subjects, variable, value).Count;
                    double expected = (double)(groups[g].Count * column) / subjectCount;
                    chi2 += (observed - expected) * (observed - expected) / expected;
                }
            int df = (groups.Count - 1) * (levels.Count - 1);
            output.Add("  " + variable + " chisq " + Real(chi2) + " df " + df + " p " +
                       Real(Numerics.Pvalue(chi2, df)));
        }
        return output;
    }
    public static string TestLine(string prefix, GroupTests.Result r) {
        return prefix + " chisq " + Real(r.chi2) + " df " + r.degrees + " p " + Real(r.pvalue);
    }
    public static void GroupLines(List<string> output, GroupTests.Result r) {
        for (int g = 0; g < r.groups.Count; g++)
            output.Add("  group " + r.groups[g] + " events " + r.events[g] + " observed " +
                       Real(r.observed[g]) + " expected " + Real(r.expected[g]) + " o_minus_e " +
                       Real(r.observed[g] - r.expected[g]) + " variance " + Real(r.covariance[g][g]));
    }
    public sealed class Pair {
        public GroupTests.Result test;
        public double hr, phi, lower, upper, adjusted;
        public int a, b;
    }
    public static Pair ComparePair(List<Dataset.Subject> rows, int a, int b) {
        Pair result = new Pair();
        result.a = a;
        result.b = b;
        result.test = GroupTests.Weighted(rows, [settings.groups[a], settings.groups[b]], 0, subjects.Count);
        double[] o = result.test.observed, x = result.test.expected;
        result.hr = (o[1] / x[1]) / (o[0] / x[0]);
        result.phi = 1 / x[0] + 1 / x[1];
        double log = Math.Log(result.hr), se = Math.Sqrt(result.phi);
        result.lower = Math.Exp(log - Numerics.Z * se);
        result.upper = Math.Exp(log + Numerics.Z * se);
        return result;
    }
    public static List<Dataset.Subject> PairRows(List<Dataset.Subject> rows, int a, int b) {
        List<Dataset.Subject> result = new();
        foreach (Dataset.Subject s in rows)
            if (s.group.Equals(settings.groups[a]) || s.group.Equals(settings.groups[b]))
                result.Add(s);
        return result;
    }
    public static string Difference(double delta, double se) {
        double z = delta / se;
        return "difference " + Real(delta) + " se " + Real(se) + " lower " + Real(delta - Numerics.Z * se) +
               " upper " + Real(delta + Numerics.Z * se) + " z " + Real(z) + " p " +
               Real(Numerics.Pvalue(z * z, 1));
    }
    public static void TestsReport() {
        List<string> output = Baseline(), part = new();
        GroupTests.Result logrank = null;
        for (int weight = 0; weight < 3; weight++) {
            GroupTests.Result r = GroupTests.Weighted(subjects, settings.groups, weight, subjects.Count);
            part.Add(TestLine("test " + GroupTests.WEIGHTS[weight], r));
            GroupLines(part, r);
            if (weight == 0)
                logrank = r;
        }
        double u = 0, variance = 0;
        for (int g = 0; g < groups.Count; g++) {
            u += (g + 1) * (logrank.observed[g] - logrank.expected[g]);
            double inner = 0;
            for (int h = 0; h < groups.Count; h++)
                inner += (g + 1) * (h + 1) * logrank.covariance[g][h];
            variance += inner;
        }
        double trend = u * u / variance;
        part.Add("test logrank_trend chisq " + Real(trend) + " df 1 p " + Real(Numerics.Pvalue(trend, 1)));
        Section(output, part);
        part = new();
        List<string> strata = Levels(settings.strata);
        for (int weight = 0; weight < 3; weight++) {
            List<GroupTests.Result> results = new();
            List<List<Dataset.Subject>> rows = new();
            foreach (string level in strata) {
                List<Dataset.Subject> stratum = Subset(subjects, settings.strata, level);
                rows.Add(stratum);
                results.Add(GroupTests.Weighted(stratum, settings.groups, weight, subjects.Count));
            }
            GroupTests.Result combined = GroupTests.Combined(results, settings.groups);
            part.Add(
                TestLine("stratified " + GroupTests.WEIGHTS[weight] + " by " + settings.strata, combined));
            for (int i = 0; i < strata.Count; i++) {
                GroupTests.Result r = results[i];
                part.Add("  stratum " + strata[i] + " subjects " + rows[i].Count + " events " +
                         Events(rows[i]) + " chisq " + Real(r.chi2) + " p " + Real(r.pvalue));
            }
            GroupLines(part, combined);
        }
        Section(output, part);
        List<Dataset.Subject> landmark = new();
        foreach (Dataset.Subject s in subjects)
            if (s.time > settings.landmark)
                landmark.Add(s);
        GroupTests.Result lm = GroupTests.Weighted(landmark, settings.groups, 0, subjects.Count);
        part = new([TestLine("landmark " + settings.landmark + " subjects " + landmark.Count, lm)]);
        GroupLines(part, lm);
        Section(output, part);
        List<Pair> pairs = new();
        for (int a = 0; a < groups.Count; a++)
            for (int b = a + 1; b < groups.Count; b++)
                pairs.Add(ComparePair(PairRows(subjects, a, b), a, b));
        List<int> order = new();
        for (int i = 0; i < pairs.Count; i++)
            order.Add(i);
        order.Sort((a, b) => pairs[a].test.pvalue != pairs[b].test.pvalue
                                 ? pairs[a].test.pvalue.CompareTo(pairs[b].test.pvalue)
                                 : a.CompareTo(b));
        double previous = 0;
        for (int r = 0; r < order.Count; r++) {
            Pair p = pairs[order[r]];
            p.adjusted = Math.Max(previous, Math.Min(1, (pairs.Count - r) * p.test.pvalue));
            previous = p.adjusted;
        }
        part = new(["pairwise logrank adjust holm"]);
        foreach (Pair p in pairs)
            part.Add("  " + settings.groups[p.a] + " " + settings.groups[p.b] + " chisq " +
                     Real(p.test.chi2) + " p " + Real(p.test.pvalue) + " p_holm " + Real(p.adjusted) +
                     " hr " + Real(p.hr) + " lower " + Real(p.lower) + " upper " + Real(p.upper));
        Section(output, part);
        part = new(["subgroups reference " + settings.groups[0]]);
        foreach (string variable in settings.subgroups)
            for (int b = 1; b < groups.Count; b++) {
                List<string> levels = Levels(variable);
                List<Pair> estimates = new();
                foreach (string level in levels) {
                    List<Dataset.Subject> rows = PairRows(Subset(subjects, variable, level), 0, b);
                    Pair p = ComparePair(rows, 0, b);
                    estimates.Add(p);
                    part.Add("  " + variable + " " + level + " " + settings.groups[b] + " subjects " +
                             rows.Count + " events " + Events(rows) + " hr " + Real(p.hr) + " lower " +
                             Real(p.lower) + " upper " + Real(p.upper) + " p " + Real(p.test.pvalue));
                }
                double numerator = 0, denominator = 0;
                foreach (Pair p in estimates) {
                    numerator += (1 / p.phi) * Math.Log(p.hr);
                    denominator += 1 / p.phi;
                }
                double mean = numerator / denominator, q = 0;
                foreach (Pair p in estimates) {
                    double delta = Math.Log(p.hr) - mean;
                    q += (1 / p.phi) * delta * delta;
                }
                int df = levels.Count - 1;
                part.Add("  " + variable + " " + settings.groups[b] + " heterogeneity chisq " + Real(q) +
                         " df " + df + " p " + Real(Numerics.Pvalue(q, df)));
            }
        Section(output, part);
        CollectionSummary control = collections[0];
        part = new(["rmst_difference tau " + settings.tau + " reference " + control.name]);
        for (int g = 1; g < groups.Count; g++) {
            CollectionSummary c = collections[g];
            part.Add("  " + c.name + " " +
                     Difference(c.rmst - control.rmst, Math.Sqrt(c.se * c.se + control.se * control.se)));
        }
        Section(output, part);
        part = new(["rate_ratio reference " + control.name]);
        for (int g = 1; g < groups.Count; g++) {
            CollectionSummary c = collections[g];
            double ratio = c.rate / control.rate, se = Math.Sqrt(1.0 / c.events + 1.0 / control.events),
                   log = Math.Log(ratio), z = log / se;
            part.Add("  " + c.name + " ratio " + Real(ratio) + " lower " +
                     Real(Math.Exp(log - Numerics.Z * se)) + " upper " +
                     Real(Math.Exp(log + Numerics.Z * se)) + " z " + Real(z) + " p " +
                     Real(Numerics.Pvalue(z * z, 1)));
        }
        Section(output, part);
        part = new(["survival_difference reference " + control.name]);
        foreach (int time in settings.report)
            for (int g = 1; g < groups.Count; g++) {
                Estimators.Row a = Estimators.At(control.rows, time),
                               b = Estimators.At(collections[g].rows, time);
                part.Add("  at " + time + " " + settings.groups[g] + " " +
                         Difference(b.survival - a.survival, Math.Sqrt(b.se * b.se + a.se * a.se)));
            }
        Section(output, part);
        Write("tests.txt", output);
    }
    public static double Covariate(Dataset.Subject s, string name) {
        return name.Equals("age")     ? s.age
               : name.Equals("male")  ? (s.sex.Equals("M") ? 1 : 0)
               : name.Equals("stage") ? s.stage
               : s.group.Equals(name) ? 1
                                      : 0;
    }
    public static string Coefficient(double beta, double se) {
        double z = beta / se;
        return "coef " + Real(beta) + " se " + Real(se) + " z " + Real(z) + " p " +
               Real(Numerics.Pvalue(z * z, 1)) + " hr " + Real(Math.Exp(beta)) + " lower " +
               Real(Math.Exp(beta - Numerics.Z * se)) + " upper " + Real(Math.Exp(beta + Numerics.Z * se));
    }
    public static double Hazard(SortedDictionary<int, double> hazards, int time) {
        double value = 0;
        foreach (var e in hazards) {
            if (e.Key > time)
                break;
            value = e.Value;
        }
        return value;
    }
    public record Residual(int index, double martingale, double deviance) {
    }
    public static void CoxReport() {
        int n = subjects.Count, p = settings.covariates.Count;
        double[][] x = Enumerable.Range(0, n)
                           .Select(
                               _ => new double[p])
                           .ToArray();
        for (int j = 0; j < n; j++)
            for (int c = 0; c < p; c++)
                x[j][c] = Covariate(subjects[j], settings.covariates[c]);
        Cox.Fit fit = Cox.Fit(subjects, x);
        Cox.Evaluation end = fit.finalEvaluation, start = fit.initial;
        double[][] covariance = Numerics.Inverse(end.information);
        List<string> output = new(["cox covariates " + string.Join(" ", settings.covariates) + " subjects " +
                                   n + " events " + Events(subjects) + " event_times " + end.times.Count]);
        foreach (Cox.Iteration i in fit.iterations)
            output.Add("iter " + i.number + " loglik " + Real(i.likelihood) + " beta " + Reals(i.beta));
        output.Add("final loglik " + Real(end.likelihood) + " null_loglik " + Real(start.likelihood));
        for (int c = 0; c < p; c++)
            output.Add("term " + settings.covariates[c] + " " +
                       Coefficient(fit.beta[c], Math.Sqrt(covariance[c][c])));
        for (int a = 0; a < p; a++)
            if (settings.groups.Contains(settings.covariates[a]))
                for (int b = a + 1; b < p; b++)
                    if (settings.groups.Contains(settings.covariates[b]))
                        output.Add("contrast " + settings.covariates[b] + " vs " + settings.covariates[a] +
                                   " " +
                                   Coefficient(fit.beta[b] - fit.beta[a],
                                               Math.Sqrt(covariance[b][b] + covariance[a][a] -
                                                         2 * covariance[a][b])));
        double likelihoodRatio = 2 * (end.likelihood - start.likelihood), wald = 0, score = 0;
        for (int c = 0; c < p; c++) {
            double inner = 0;
            for (int d = 0; d < p; d++)
                inner += end.information[c][d] * fit.beta[d];
            wald += fit.beta[c] * inner;
        }
        double[] solved = Numerics.Solve(start.information, start.score);
        for (int c = 0; c < p; c++)
            score += start.score[c] * solved[c];
        foreach (string name in new string[] { "likelihood_ratio", "wald", "score" }) {
            double chi2 = name.Equals("likelihood_ratio") ? likelihoodRatio
                          : name.Equals("wald")           ? wald
                                                          : score;
            output.Add(name + " chisq " + Real(chi2) + " df " + p + " p " + Real(Numerics.Pvalue(chi2, p)));
        }
        for (int c = 0; c < p; c++) {
            double ll = start.likelihood;
            if (p > 1) {
                double[][] reduced = Enumerable.Range(0, n)
                                         .Select(
                                             _ => new double[p - 1])
                                         .ToArray();
                for (int j = 0; j < n; j++) {
                    int target = 0;
                    for (int d = 0; d < p; d++)
                        if (d != c)
                            reduced[j][target++] = x[j][d];
                }
                ll = Cox.Fit(subjects, reduced).finalEvaluation.likelihood;
            }
            double chi2 = 2 * (end.likelihood - ll);
            output.Add("drop " + settings.covariates[c] + " loglik " + Real(ll) + " chisq " + Real(chi2) +
                       " df 1 p " + Real(Numerics.Pvalue(chi2, 1)));
        }
        int comparable = 0, concordant = 0, tied = 0;
        for (int i = 0; i < n; i++)
            if (subjects[i].eventFlag == 1)
                for (int j = 0; j < n; j++)
                    if (i != j && (subjects[i].time < subjects[j].time ||
                                   (subjects[i].time == subjects[j].time && subjects[j].eventFlag == 0))) {
                        comparable++;
                        bool equal = true;
                        for (int c = 0; c < p; c++)
                            if (x[i][c] != x[j][c])
                                equal = false;
                        if (equal)
                            tied++;
                        else if (end.theta[i] > end.theta[j])
                            concordant++;
                    }
        output.Add("concordance " + Real((double)(2 * concordant + tied) / (2 * comparable)) +
                   " comparable " + comparable + " concordant " + concordant + " tied " + tied);
        List<int> eventOrder = new();
        for (int i = 0; i < n; i++)
            if (subjects[i].eventFlag == 1)
                eventOrder.Add(i);
        eventOrder.Sort((a, b) => subjects[a].time != subjects[b].time
                                      ? subjects[a].time.CompareTo(subjects[b].time)
                                      : subjects[a].id.CompareTo(subjects[b].id));
        int timeSum = 0;
        foreach (int i in eventOrder)
            timeSum += subjects[i].time;
        double timeMean = (double)timeSum / eventOrder.Count;
        for (int c = 0; c < p; c++) {
            double[] residual = new double[eventOrder.Count];
            double sum = 0;
            for (int j = 0; j < eventOrder.Count; j++) {
                int i = eventOrder[j];
                Cox.Risk r = end.times[subjects[i].time];
                residual[j] = x[i][c] - r.s1[c] / r.s0;
                sum += residual[j];
            }
            double mean = sum / eventOrder.Count, sxy = 0, sxx = 0, syy = 0;
            for (int j = 0; j < eventOrder.Count; j++) {
                double dx = residual[j] - mean, dy = subjects[eventOrder[j]].time - timeMean;
                sxy += dx * dy;
                sxx += dx * dx;
                syy += dy * dy;
            }
            double rho = sxy / Math.Sqrt(sxx * syy),
                   z = 0.5 * Math.Log((1 + rho) / (1 - rho)) * Math.Sqrt(eventOrder.Count - 3);
            output.Add("ph_check " + settings.covariates[c] + " rho " + Real(rho) + " z " + Real(z) + " p " +
                       Real(Numerics.Pvalue(z * z, 1)));
        }
        SortedDictionary<int, double> cumulative = new();
        double lambda = 0;
        foreach (var e in end.times) {
            lambda += e.Value.events / e.Value.s0;
            cumulative[e.Key] = lambda;
        }
        List<Residual> residuals = new();
        for (int i = 0; i < n; i++) {
            Dataset.Subject s = subjects[i];
            double m = s.eventFlag - Hazard(cumulative, s.time) * Math.Exp(end.theta[i]);
            double deviance = Math.Sqrt(s.eventFlag == 1 ? -2 * (m + Math.Log(1 - m)) : -2 * m);
            if (!(m > 0))
                deviance = -deviance;
            residuals.Add(new Residual(i, m, deviance));
        }
        residuals.Sort((a, b) => Math.Abs(a.deviance) != Math.Abs(b.deviance)
                                     ? Math.Abs(b.deviance).CompareTo(Math.Abs(a.deviance))
                                     : subjects[a.index].id.CompareTo(subjects[b.index].id));
        output.Add("residuals top " + settings.residuals);
        for (int j = 0; j < settings.residuals; j++) {
            Residual r = residuals[j];
            Dataset.Subject s = subjects[r.index];
            output.Add("  id " + s.id + " group " + s.group + " time " + s.time + " event " + s.eventFlag +
                       " martingale " + Real(r.martingale) + " deviance " + Real(r.deviance));
        }
        double[] means = new double[p];
        string meanLine = "adjusted_survival mean";
        int standard = 0;
        for (int c = 0; c < p; c++)
            if (new string[] { "age", "male", "stage" }.Contains(settings.covariates[c])) {
                int sum = 0;
                for (int i = 0; i < n; i++)
                    sum += (int)x[i][c];
                means[c] = (double)sum / n;
                meanLine += " " + settings.covariates[c] + " " + Real(means[c]);
                standard++;
            }
        output.Add(meanLine + (standard == 0 ? " none" : ""));
        double[] risks = new double[groups.Count];
        for (int g = 0; g < groups.Count; g++) {
            double theta = 0;
            for (int c = 0; c < p; c++) {
                string name = settings.covariates[c];
                double value =
                    settings.groups.Contains(name) ? (name.Equals(settings.groups[g]) ? 1 : 0) : means[c];
                theta += fit.beta[c] * value;
            }
            risks[g] = Math.Exp(theta);
        }
        foreach (int time in settings.report) {
            string line = "  at " + time;
            for (int g = 0; g < groups.Count; g++)
                line += " " + settings.groups[g] + " " + Real(Math.Exp(-Hazard(cumulative, time) * risks[g]));
            output.Add(line);
        }
        string medianLine = "  median";
        for (int g = 0; g < groups.Count; g++) {
            int median = -1;
            foreach (var e in cumulative)
                if (Math.Exp(-e.Value * risks[g]) <= 0.5) {
                    median = e.Key;
                    break;
                }
            medianLine += " " + settings.groups[g] + " " + Day(median);
        }
        output.Add(medianLine);
        Write("cox.txt", output);
    }
    public static void PlotReport() {
        List<List<Estimators.Row>> tables = new();
        for (int g = 0; g < groups.Count; g++)
            tables.Add(collections[g].rows);
        List<string> output = new(
            ["km_plot width " + settings.width + " height " + settings.height + " time " + settings.horizon]);
        string legend = "legend";
        for (int g = 0; g < groups.Count; g++)
            legend += " " + (char)('A' + g) + " " + settings.groups[g];
        output.Add(legend);
        output.AddRange(Plot.Draw(groups, tables, settings.width, settings.height, settings.horizon));
        output.Add("time 0 to " + settings.horizon + " days, " + (settings.horizon / settings.width) +
                   " days per column");
        string line = "at_risk";
        for (int i = 0; i <= settings.divisions; i++)
            line += " " + (i * (settings.horizon / settings.divisions));
        output.Add(line);
        for (int g = 0; g < groups.Count; g++) {
            line = settings.groups[g];
            for (int i = 0; i <= settings.divisions; i++)
                line += " " + Estimators.Risk(groups[g], i * (settings.horizon / settings.divisions));
            output.Add(line);
        }
        Write("km_plot.txt", output);
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Dataset.Data data = Dataset.Read();
        subjects = data.subjects;
        settings = data.settings;
        foreach (string group in settings.groups) {
            List<Dataset.Subject> rows = new();
            foreach (Dataset.Subject s in subjects)
                if (s.group.Equals(group))
                    rows.Add(s);
            groups.Add(rows);
            collections.Add(Summarize(group, rows));
        }
        collections.Add(Summarize("all", subjects));
        Directory.CreateDirectory(Path.Combine("output"));
        KmReport();
        TestsReport();
        CoxReport();
        PlotReport();
    }
}
