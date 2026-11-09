using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Program {
    public static DataIO.Data data;
    public static DataIO.Settings settings;
    public static int days, groups, population, caseTotal, deathTotal;
    public static int[] populations, ageInflows;
    public static double[] fatalities, initial, sirInitial, ageInitial, multipliers;
    public static double fatality, sigma, gamma0, beta, rho, gamma, r0, betaGrid, rhoGrid, betaGolden,
        sseGrid, sseGolden, sseNelder, deltaBeta, deltaRho, seBeta;
    public static List<double[]> fitted, ageFitted;
    public static double[] incidence, reported, residuals, modelDeaths, average7, rt, generation;
    public static double[][] contacts;
    public static List<string> fit = new(), reproduction = new(), trajectories = new(), scenarios = new();
    public record Key(double beta, double gamma) {
    }
    public record Eigen(double value, double[] vector) {
    }
    public static Dictionary<Key, double[]> cache = new();
    public static string F(double value, int digits) {
        return Report.F(value, digits);
    }
    public static string F(double value) {
        return F(value, 4);
    }
    public static double Sum(double[] values) {
        double total = 0;
        foreach (double value in values)
            total += value;
        return total;
    }
    public static int Sum(int[] values) {
        int total = 0;
        foreach (int value in values)
            total += value;
        return total;
    }
    public static int Peak(double[] values) {
        int selected = 0;
        for (int i = 1; i < values.Length; i++)
            if (values[i] > values[selected])
                selected = i;
        return selected;
    }
    public static double[] Constants(int size, double value) {
        double[] result = new double[size];
        Array.Fill(result, value);
        return result;
    }
    public static double[] Column(List<double[]> states, int column) {
        double[] values = new double[states.Count];
        for (int i = 0; i < values.Length; i++)
            values[i] = states[i][column];
        return values;
    }
    public static double[] Scale(double[] values, double factor) {
        double[] result = new double[values.Length];
        for (int i = 0; i < result.Length; i++)
            result[i] = factor * values[i];
        return result;
    }
    public static string Values(double[] values, int digits) {
        List<string> result = new();
        foreach (double value in values)
            result.Add(F(value, digits));
        return string.Join(" ", result);
    }
    public static double Rmse(double error, int count) {
        return Math.Sqrt(error / count);
    }
    public static double Rmse(double error) {
        return Rmse(error, days);
    }
    public static double Squared(double[] values, double coefficient, int[] observations, int first,
                                 int last) {
        double sum = 0;
        for (int i = first; i < last; i++) {
            double e = coefficient * values[i] - observations[i];
            sum += e * e;
        }
        return sum;
    }
    public static double[] Sequence(List<DataIO.Intervention> interventions, int count) {
        double[] result = new double[count];
        int k = 0;
        for (int d = 1; d <= count; d++) {
            while (k + 1 < interventions.Count && interventions[k + 1].day <= d)
                k++;
            result[d - 1] = interventions[k].multiplier;
        }
        return result;
    }
    public static List<double[]> States(double b, double g, double[] mu, double[] state, double sigmaValue) {
        return Integrator.Simulate(Models.Seird(population, sigmaValue, fatality, b, g), state, mu,
                                   new int[] { 5 });
    }
    public static List<double[]> States(double b, double g) {
        return States(b, g, multipliers, initial, sigma);
    }
    public static List<double[]> AgeStates(double[][] w, double[] mu, double[] state) {
        return Integrator.Simulate(Models.Age(populations, fatalities, sigma, beta, gamma, w), state, mu,
                                   ageInflows);
    }
    public static double[] Incidence(double b, double g) {
        Key key = new Key(b, g);
        if (!cache.ContainsKey(key))
            cache[key] = Column(States(b, g), 5);
        return cache[key];
    }
    public static double Error(double b, double g, double p) {
        return Squared(Incidence(b, g), p, data.cases, 0, days);
    }
    public static double[] AgeIncidence(List<double[]> states) {
        double[] result = new double[states.Count];
        for (int d = 0; d < result.Length; d++)
            for (int g = 0; g < groups; g++)
                result[d] += states[d][6 * g + 5];
        return result;
    }
    public static double[] SirIncidence(double b) {
        return Column(
            Integrator.Simulate(Models.Sir(population, b, gamma), sirInitial, multipliers, new int[] { 3 }),
            3);
    }
    public static void Prepare() {
        data = DataIO.Read();
        settings = data.settings;
        days = data.cases.Length;
        groups = data.groups.Count;
        populations = new int[groups];
        fatalities = new double[groups];
        ageInflows = new int[groups];
        for (int g = 0; g < groups; g++) {
            DataIO.Group group = data.groups[g];
            populations[g] = group.population;
            fatalities[g] = group.fatality;
            population += populations[g];
            fatality += populations[g] * fatalities[g];
            ageInflows[g] = 6 * g + 5;
        }
        fatality /= population;
        caseTotal = Sum(data.cases);
        deathTotal = Sum(data.deaths);
        sigma = settings.Real("sigma", 0);
        gamma0 = settings.Real("gamma", 0);
        double e = settings.Real("initial", 0), i = settings.Real("initial", 1);
        initial = new double[] { population - e - i, e, i, 0, 0, 0 };
        sirInitial = new double[] { population - e - i, e + i, 0, 0 };
        ageInitial = new double[groups * 6];
        for (int g = 0; g < groups; g++) {
            double eg = e * populations[g] / population, ig = i * populations[g] / population;
            ageInitial[6 * g] = populations[g] - eg - ig;
            ageInitial[6 * g + 1] = eg;
            ageInitial[6 * g + 2] = ig;
        }
        multipliers = Sequence(data.interventions, days);
    }
    public static void GoldenLines(int round, string name, Fitting.Golden search) {
        for (int i = 0; i < search.records.Count; i++) {
            Fitting.GoldenRecord r = search.records[i];
            fit.Add("golden " + round + " " + name + " " + i + " a " + F(r.a, 6) + " b " + F(r.b, 6) + " c " +
                    F(r.c, 6) + " d " + F(r.d, 6) + " rmse " + F(Rmse(r.fc)) + " " + F(Rmse(r.fd)));
        }
        fit.Add("golden_result " + round + " " + name + " " + F(search.point, 6) + " sse " +
                F(search.value, 1));
    }
    public static void FitModel() {
        double bmin = settings.Real("beta_grid", 0), bmax = settings.Real("beta_grid", 1),
               pmin = settings.Real("rho_grid", 0), pmax = settings.Real("rho_grid", 1);
        int nb = settings.Integer("beta_grid", 2), np = settings.Integer("rho_grid", 2);
        deltaBeta = (bmax - bmin) / (nb - 1);
        deltaRho = (pmax - pmin) / (np - 1);
        double[] betas = new double[nb], rhos = new double[np];
        for (int i = 0; i < nb; i++)
            betas[i] = bmin + (bmax - bmin) * i / (nb - 1);
        for (int j = 0; j < np; j++)
            rhos[j] = pmin + (pmax - pmin) * j / (np - 1);
        fit.Add("data days " + days + " cases " + caseTotal + " deaths " + deathTotal + " population " +
                population + " fatality " + F(fatality, 6));
        fit.Add("grid gamma " + F(gamma0) + " rho " + Values(rhos, 4));
        sseGrid = double.MaxValue;
        for (int i = 0; i < nb; i++) {
            double[] errors = new double[np];
            for (int j = 0; j < np; j++) {
                errors[j] = Error(betas[i], gamma0, rhos[j]);
                if (errors[j] < sseGrid) {
                    sseGrid = errors[j];
                    betaGrid = betas[i];
                    rhoGrid = rhos[j];
                }
            }
            List<string> scores = new();
            foreach (double value in errors)
                scores.Add(F(Rmse(value), 2));
            fit.Add("grid beta " + F(betas[i]) + " rmse " + string.Join(" ", scores));
        }
        fit.Add("grid_best beta " + F(betaGrid) + " rho " + F(rhoGrid) + " sse " + F(sseGrid, 1) + " rmse " +
                F(Rmse(sseGrid)));
        double b = betaGrid, p = rhoGrid;
        int ng = settings.Integer("golden", 0);
        for (int round = 1; round <= settings.Integer("golden", 1); round++) {
            public readonly double fixedP = p;
            Fitting.Golden bs =
                Fitting.SearchGolden(x => Error(x, gamma0, fixedP), b - deltaBeta, b + deltaBeta, ng);
            GoldenLines(round, "beta", bs);
            b = bs.point;
            public readonly double fixedB = b;
            Fitting.Golden ps =
                Fitting.SearchGolden(x => Error(fixedB, gamma0, x), p - deltaRho, p + deltaRho, ng);
            GoldenLines(round, "rho", ps);
            p = ps.point;
            sseGolden = ps.value;
        }
        betaGolden = b;
        rho = p;
        Fitting.Simplex simplex = Fitting.Nelder(
            (x, y) => Error(x, y, rho), b, gamma0, settings.Real("simplex", 0), settings.Real("simplex", 1),
            settings.Real("nelder_mead", 0), settings.Real("nelder_mead", 1), settings.Real("nelder_mead", 2),
            settings.Real("nelder_mead", 3), settings.Integer("nelder_mead", 4));
        foreach (Fitting.Vertex v in simplex.initial)
            fit.Add("simplex " + v.serial + " beta " + F(v.beta, 6) + " gamma " + F(v.gamma, 6) + " rmse " +
                    F(Rmse(v.value)));
        for (int i = 0; i < simplex.operations.Count; i++) {
            Fitting.Operation op = simplex.operations[i];
            Fitting.Vertex v = op.best;
            fit.Add("nelder_mead " + (i + 1) + " " + op.name + " beta " + F(v.beta, 6) + " gamma " +
                    F(v.gamma, 6) + " rmse " + F(Rmse(v.value)));
        }
        for (int i = 0; i < 3; i++) {
            Fitting.Vertex v = simplex.vertices[i];
            fit.Add("final_simplex " + (i + 1) + " beta " + F(v.beta, 6) + " gamma " + F(v.gamma, 6) +
                    " rmse " + F(Rmse(v.value)));
        }
        Fitting.Vertex best = simplex.vertices[0];
        beta = best.beta;
        gamma = best.gamma;
        sseNelder = best.value;
        r0 = beta / gamma;
        double mean = (double)caseTotal / days, sst = 0;
        foreach (int c in data.cases) {
            double e = c - mean;
            sst += e * e;
        }
        fit.Add("fitted beta " + F(beta, 6) + " gamma " + F(gamma, 6) + " rho " + F(rho, 6) + " sigma " +
                F(sigma, 6) + " r0 " + F(r0));
        fit.Add("sse grid " + F(sseGrid, 1) + " golden " + F(sseGolden, 1) + " nelder_mead " +
                F(sseNelder, 1) + " rmse " + F(Rmse(sseNelder)) + " r2 " + F(1 - sseNelder / sst));
        string[] names = { "grid", "golden", "nelder_mead" };
        double[] stageBetas = { betaGrid, betaGolden, beta }, stageGammas = { gamma0, gamma0, gamma },
                 stageRhos = { rhoGrid, rho, rho }, stageErrors = { sseGrid, sseGolden, sseNelder };
        for (int k = 0; k < 3; k++)
            fit.Add("stage " + names[k] + " beta " + F(stageBetas[k], 6) + " gamma " + F(stageGammas[k], 6) +
                    " rho " + F(stageRhos[k], 6) + " r0 " + F(stageBetas[k] / stageGammas[k]) + " rmse " +
                    F(Rmse(stageErrors[k])));
    }
    public static void FittedCourse() {
        fitted = States(beta, gamma);
        incidence = Column(fitted, 5);
        reported = Scale(incidence, rho);
        residuals = new double[days];
        modelDeaths = new double[days];
        average7 = new double[days];
        rt = new double[days];
        trajectories.Add(
            "day,S,E,I,R,D,incidence,reported,observed,average7,cumulative_observed,cumulative_reported");
        int observed = 0;
        double cumulative = 0;
        for (int d = 0; d < days; d++) {
            double[] y = fitted[d];
            residuals[d] = data.cases[d] - reported[d];
            modelDeaths[d] = y[4] - (d == 0 ? 0 : fitted[d - 1][4]);
            int count = 0;
            for (int j = Math.Max(0, d - 6); j <= d; j++)
                count += data.cases[j];
            average7[d] = (double)count / Math.Min(d + 1, 7);
            rt[d] = r0 * multipliers[d] * (d == 0 ? initial[0] : fitted[d - 1][0]) / population;
            observed += data.cases[d];
            cumulative += reported[d];
            string row = Convert.ToString(d + 1);
            for (int c = 0; c < 6; c++)
                row += "," + F(y[c], 1);
            row += "," + F(reported[d], 1) + "," + data.cases[d] + "," + F(average7[d], 2) + "," + observed +
                   "," + F(cumulative, 1);
            trajectories.Add(row);
        }
    }

    public static void Diagnostics() {
        double residualSum = 0, absolute = 0, u = 0, difference = 0;
        int positive = 0, runs = 1, maximum = 0;
        for (int d = 0; d < days; d++) {
            double e = residuals[d];
            residualSum += e;
            absolute += Math.Abs(e);
            u += e * e;
            if (e > 0)
                positive++;
            if (Math.Abs(e) > Math.Abs(residuals[maximum]))
                maximum = d;
            if (d > 0) {
                if ((e > 0) != (residuals[d - 1] > 0))
                    runs++;
                double delta = e - residuals[d - 1];
                difference += delta * delta;
            }
        }
        fit.Add("residuals sum " + F(residualSum, 1) + " mae " + F(absolute / days, 1) + " max " +
                F(residuals[maximum], 1) + " day " + (maximum + 1) + " positive " + positive + " runs " +
                runs + " durbin_watson " + F(difference / u));
        double[] autocorrelation = new double[7];
        for (int k = 1; k <= 7; k++) {
            double sum = 0;
            for (int d = 0; d < days - k; d++)
                sum += residuals[d] * residuals[d + k];
            autocorrelation[k - 1] = sum / u;
        }
        fit.Add("autocorrelation " + Values(autocorrelation, 4));
        int outliers = 0;
        for (int d = 0; d < days; d++) {
            double z = residuals[d] / Math.Sqrt(reported[d]);
            if (Math.Abs(z) > settings.Real("outlier", 0)) {
                outliers++;
                fit.Add("outlier " + (d + 1) + " observed " + data.cases[d] + " fitted " + F(reported[d], 1) +
                        " z " + F(z));
            }
        }
        fit.Add("outliers " + outliers);
        int[] counts = new int[7];
        double[] totals = new double[7], factors = new double[7];
        for (int d = 0; d < days; d++) {
            counts[d % 7] += data.cases[d];
            totals[d % 7] += reported[d];
        }
        for (int k = 0; k < 7; k++) {
            factors[k] = counts[k] / totals[k];
            fit.Add("weekday " + (k + 1) + " observed " + counts[k] + " fitted " + F(totals[k], 1) +
                    " factor " + F(factors[k]));
        }
        double adjusted = 0;
        for (int d = 0; d < days; d++) {
            double e = reported[d] * factors[d % 7] - data.cases[d];
            adjusted += e * e;
        }
        fit.Add("weekday_adjusted rmse " + F(Rmse(adjusted)));
        double infections = Sum(incidence);
        fit.Add("burden infections " + F(infections, 1) + " ascertainment " + F(caseTotal / infections) +
                " deaths_per_infection " + F(deathTotal / infections, 6));
        double product = 0, squares = 0;
        for (int d = 0; d < days; d++) {
            product += modelDeaths[d] * data.deaths[d];
            squares += modelDeaths[d] * modelDeaths[d];
        }
        double kappa = product / squares;
        fit.Add("deaths observed " + deathTotal + " model " + F(fitted[^1][4], 1) + " rmse " +
                F(Rmse(Squared(modelDeaths, 1, data.deaths, 0, days))) + " scale " + F(kappa) +
                " implied_fatality " + F(fatality * kappa, 6) + " cfr " + F((double)deathTotal / caseTotal));
        double largest = -double.MaxValue;
        int lag = 0;
        for (int k = 0; k <= settings.Integer("death_lag", 0); k++) {
            int a = 0, b = 0, y = 0, dead = 0, cases = 0;
            for (int d = 0; d < days - k; d++) {
                a += data.cases[d] * data.deaths[d + k];
                b += data.cases[d] * data.cases[d];
                y += data.deaths[d + k] * data.deaths[d + k];
                dead += data.deaths[d + k];
                cases += data.cases[d];
            }
            double correlation = a / Math.Sqrt((double)b * y);
            if (correlation > largest) {
                largest = correlation;
                lag = k;
            }
            fit.Add("death_lag " + k + " correlation " + F(correlation) + " cfr " + F((double)dead / cases));
        }
        fit.Add("death_best_lag " + lag);
        int previous = 0;
        for (int first = 0; first < days; first += 7) {
            int end = Math.Min(days, first + 7), cases = 0, deaths = 0;
            double predicted = 0, dead = 0;
            for (int d = first; d < end; d++) {
                cases += data.cases[d];
                deaths += data.deaths[d];
                predicted += reported[d];
                dead += modelDeaths[d];
            }
            fit.Add("weekly " + (first / 7 + 1) + " days " + (first + 1) + " " + end + " observed " + cases +
                    " fitted " + F(predicted, 1) + " deaths_observed " + deaths + " deaths_model " +
                    F(dead, 1) + " growth " + (first == 0 ? "-" : F((double)cases / previous)));
            previous = cases;
        }
    }
    public static void ProfilesAndBacktest() {
        string[] names = { "beta", "gamma", "rho" };
        double[] fittedValues = { beta, gamma, rho };
        for (int parameter = 0; parameter < 3; parameter++) {
            double v = fittedValues[parameter], h = v / 100;
            double[] errors = new double[11];
            for (int k = -5; k <= 5; k++) {
                double[] point = fittedValues.ToArray();
                point[parameter] = v * (1 + k / 100.0);
                errors[k + 5] = Error(point[0], point[1], point[2]);
                fit.Add("profile " + names[parameter] + " " + k + " value " + F(point[parameter], 6) +
                        " rmse " + F(Rmse(errors[k + 5])));
            }
            double curvature = (errors[6] - 2 * errors[5] + errors[4]) / (h * h),
                   variance = sseNelder / (days - 3), standard = Math.Sqrt(2 * variance / curvature);
            if (parameter == 0)
                seBeta = standard;
            fit.Add("profile_se " + names[parameter] + " " + F(standard, 6));
        }
        int nt = days - settings.Integer("holdout", 0), ng = settings.Integer("golden", 0);
        double[] prefix = multipliers[..nt];
        Fitting.Golden bs = Fitting.SearchGolden(
            x => Squared(Column(States(x, gamma, prefix, initial, sigma), 5), rho, data.cases, 0, nt),
            beta - deltaBeta, beta + deltaBeta, ng);
        double bb = bs.point;
        double[] trained = Column(States(bb, gamma, prefix, initial, sigma), 5);
        Fitting.Golden ps = Fitting.SearchGolden(x => Squared(trained, x, data.cases, 0, nt), rho - deltaRho,
                                                 rho + deltaRho, ng);
        double pb = ps.point;
        double[] forecast = Scale(Incidence(bb, gamma), pb);
        fit.Add("backtest train_days " + nt + " beta " + F(bb, 6) + " rho " + F(pb, 6) + " train_rmse " +
                F(Rmse(ps.value, nt)) + " test_rmse " +
                F(Rmse(Squared(forecast, 1, data.cases, nt, days), days - nt)) + " full_fit_test_rmse " +
                F(Rmse(Squared(reported, 1, data.cases, nt, days), days - nt)));
        for (int d = nt; d < days; d++)
            fit.Add("backtest_day " + (d + 1) + " observed " + data.cases[d] + " forecast " +
                    F(forecast[d], 1) + " error " + F(data.cases[d] - forecast[d], 1));
        List<DataIO.Intervention> estimated = new(data.interventions);
        double after = sseNelder;
        for (int k = 1; k < estimated.Count; k++) {
            int index = k;
            DataIO.Intervention given = data.interventions[k];
            Fitting.Golden effect = Fitting.SearchGolden(
                x => {
                    List<DataIO.Intervention> changed = new(estimated);
                    changed[index] = new DataIO.Intervention(given.day, x);
                    return Squared(Column(States(beta, gamma, Sequence(changed, days), initial, sigma), 5),
                                   rho, data.cases, 0, days);
                },
                given.multiplier - settings.Real("effect_width", 0),
                given.multiplier + settings.Real("effect_width", 0), ng);
            estimated[k] = new DataIO.Intervention(given.day, effect.point);
            after = effect.value;
            fit.Add("effect " + (k + 1) + " day " + given.day + " given " + F(given.multiplier) +
                    " estimated " + F(effect.point, 6) + " sse " + F(after, 1));
        }
        fit.Add("effect_sse before " + F(sseNelder, 1) + " after " + F(after, 1) + " rmse " + F(Rmse(after)));
        string[] sensitivities = { "beta", "gamma", "sigma", "rho" };
        for (int k = 0; k < 4; k++)
            foreach (double factor in new double[] { 0.9, 1.1 }) {
                double[] point = { beta, gamma, sigma, rho };
                point[k] = point[k] * factor;
                List<double[]> states = States(point[0], point[1], multipliers, initial, point[2]);
                double[] series = Column(states, 5);
                int peak = Peak(series);
                fit.Add("sensitivity " + sensitivities[k] + " " + F(factor, 2) + " r0 " +
                        F(point[0] / point[1]) + " rmse " +
                        F(Rmse(Squared(series, point[3], data.cases, 0, days))) + " peak_day " + (peak + 1) +
                        " peak " + F(point[3] * series[peak], 1) + " attack " +
                        F((population - states[^1][0]) / population));
            }
    }
    public static double FinalSize(double reproductionNumber) {
        if (reproductionNumber <= 1)
            return 0;
        double lo = 1 - 1 / reproductionNumber, hi = 1;
        for (int i = 0; i < 20; i++) {
            double mid = (lo + hi) / 2, g = 1 - mid - Math.Exp(-reproductionNumber * mid);
            if (g > 0)
                lo = mid;
            else
                hi = mid;
        }
        return (lo + hi) / 2;
    }
    public static Eigen Power(double[][] matrix) {
        double[] vector = Constants(matrix.Length, 1.0 / matrix.Length);
        double value = 0;
        for (int k = 0; k < 200; k++) {
            double[] next = new double[vector.Length];
            for (int g = 0; g < next.Length; g++)
                for (int h = 0; h < next.Length; h++)
                    next[g] += matrix[g][h] * vector[h];
            value = Sum(next);
            for (int g = 0; g < next.Length; g++)
                next[g] /= value;
            vector = next;
        }
        return new Eigen(value, vector);
    }
    public static void Homogeneous() {
        double[] terminal = States(beta, gamma, Constants(730, 1), initial, sigma)[^1];
        reproduction.Add("r0 " + F(r0) + " herd_immunity " + F(1 - 1 / r0));
        reproduction.Add("final_size equation " + F(FinalSize(r0)) + " simulated " +
                         F((population - terminal[0]) / population));
        int length = settings.Integer("generation", 0);
        double[] inflow =
            Column(Integrator.Simulate(Models.Generation(sigma, gamma), new double[] { 1, 0, 0 },
                                       Constants(length, 1), new int[] { 2 }),
                   2);
        double coverage = Sum(inflow), mean = 0;
        generation = new double[length];
        for (int i = 0; i < length; i++) {
            generation[i] = inflow[i] / coverage;
            mean += (i + 0.5) * generation[i];
        }
        reproduction.Add("generation mean " + F(mean) + " theory " + F(1 / sigma + 1 / gamma) + " coverage " +
                         F(coverage));
        for (int i = 0; i < length; i++)
            reproduction.Add("generation_weight " + (i + 1) + " " + F(generation[i], 6));
        int modelPeak = Peak(incidence), infectiousPeak = Peak(Column(fitted, 2)), observedPeak = 0,
            averagePeak = Peak(average7);
        for (int i = 1; i < days; i++)
            if (data.cases[i] > data.cases[observedPeak])
                observedPeak = i;
        reproduction.Add("peak model day " + (modelPeak + 1) + " incidence " + F(incidence[modelPeak], 1) +
                         " reported " + F(reported[modelPeak], 1) + " infectious_day " +
                         (infectiousPeak + 1) + " infectious " + F(fitted[infectiousPeak][2], 1));
        reproduction.Add("peak observed day " + (observedPeak + 1) + " cases " + data.cases[observedPeak] +
                         " average7_day " + (averagePeak + 1) + " average7 " + F(average7[averagePeak], 2));
        for (int k = 0; k < data.interventions.Count; k++) {
            int first = data.interventions[k].day - 1,
                end = k + 1 < data.interventions.Count ? data.interventions[k + 1].day - 1 : days, count = 0;
            double predicted = 0, errors = 0, bias = 0;
            for (int d = first; d < end; d++) {
                count += data.cases[d];
                predicted += reported[d];
                errors += residuals[d] * residuals[d];
                bias += residuals[d];
            }
            reproduction.Add("period " + (k + 1) + " days " + (first + 1) + " " + end + " multiplier " +
                             F(data.interventions[k].multiplier) + " rt_start " + F(rt[first]) + " rt_end " +
                             F(rt[end - 1]) + " observed " + count + " fitted " + F(predicted, 1) + " rmse " +
                             F(Rmse(errors, end - first)) + " bias " + F(bias / (end - first), 1));
        }
        foreach (int target in settings.Integers("milestones")) {
            int observed = 0;
            double predicted = 0;
            string observedDay = "never", fittedDay = "never";
            for (int d = 0; d < days; d++) {
                observed += data.cases[d];
                predicted += reported[d];
                if (observedDay.Equals("never") && observed >= target)
                    observedDay = Convert.ToString(d + 1);
                if (fittedDay.Equals("never") && predicted >= target)
                    fittedDay = Convert.ToString(d + 1);
            }
            reproduction.Add("milestone " + target + " observed " + observedDay + " fitted " + fittedDay);
        }
        double fittedTotal = Sum(reported);
        double[] noInterventions = Scale(
            Column(States(beta, gamma, Constants(days, data.interventions[0].multiplier), initial, sigma), 5),
            rho);
        int peak = Peak(noInterventions);
        reproduction.Add("counterfactual none reported " + F(Sum(noInterventions), 1) + " peak_day " +
                         (peak + 1) + " peak " + F(noInterventions[peak], 1) + " averted " +
                         F(Sum(noInterventions) - fittedTotal, 1));
        for (int k = 1; k < data.interventions.Count; k++) {
            List<DataIO.Intervention> removed = new(data.interventions);
            removed.RemoveAt(k);
            double total =
                Sum(Scale(Column(States(beta, gamma, Sequence(removed, days), initial, sigma), 5), rho));
            reproduction.Add("counterfactual without " + (k + 1) + " reported " + F(total, 1) + " averted " +
                             F(total - fittedTotal, 1));
        }
        for (int k = 1; k < data.interventions.Count; k++)
            foreach (int shift in new int[] { -7, 7 }) {
                List<DataIO.Intervention> changed = new(data.interventions);
                DataIO.Intervention given = changed[k];
                changed[k] = new DataIO.Intervention(given.day + shift, given.multiplier);
                double total =
                    Sum(Scale(Column(States(beta, gamma, Sequence(changed, days), initial, sigma), 5), rho));
                reproduction.Add("timing " + (k + 1) + " shift " + shift + " reported " + F(total, 1) +
                                 " change " + F(total - fittedTotal, 1));
            }
        for (int d = 1; d < days; d++)
            if ((rt[d] < 1) != (rt[d - 1] < 1))
                reproduction.Add("rt_cross day " + (d + 1) + " " + (rt[d] < 1 ? "down" : "up"));
        double[] pressure = new double[days];
        for (int d = 0; d < days; d++)
            for (int s = 1; s <= Math.Min(length, d); s++)
                pressure[d] += generation[s - 1] * data.cases[d - s];
        for (int d = 0; d < days; d++) {
            string empirical = "-";
            if (d + 1 >= length + 7) {
                int count = 0;
                double sum = 0;
                for (int j = d - 6; j <= d; j++) {
                    count += data.cases[j];
                    sum += pressure[j];
                }
                empirical = F(count / sum);
            }
            reproduction.Add("rt " + (d + 1) + " model " + F(rt[d]) + " empirical " + empirical);
        }
    }

    public static double[][] Ngm(double[][] w, double[] susceptible, double multiplier) {
        double[][] result = Enumerable.Range(0, groups)
                                .Select(
                                    _ => new double[groups])
                                .ToArray();
        for (int g = 0; g < groups; g++)
            for (int h = 0; h < groups; h++)
                result[g][h] = multiplier * r0 * w[g][h] * susceptible[6 * g] / populations[h];
        return result;
    }
    public static void Ages() {
        double average = 0;
        for (int g = 0; g < groups; g++) {
            double row = 0;
            for (int h = 0; h < groups; h++)
                row += data.contacts[g][h];
            average += populations[g] * row;
        }
        average /= population;
        contacts = Enumerable.Range(0, groups)
                       .Select(
                           _ => new double[groups])
                       .ToArray();
        double[][] matrix = Enumerable.Range(0, groups)
                                .Select(
                                    _ => new double[groups])
                                .ToArray();
        for (int g = 0; g < groups; g++)
            for (int h = 0; h < groups; h++) {
                contacts[g][h] = data.contacts[g][h] / average;
                matrix[g][h] = r0 * contacts[g][h] * populations[g] / populations[h];
            }
        Eigen eigen = Power(matrix);
        for (int g = 0; g < groups; g++)
            reproduction.Add("ngm " + data.groups[g].name + " " + Values(matrix[g], 4));
        reproduction.Add("r0_age " + F(eigen.value) + " ratio " + F(eigen.value / r0) + " kbar " +
                         F(average) + " eigenvector " + Values(eigen.vector, 4));
        double[] z = Constants(groups, 1);
        for (int k = 0; k < 100; k++) {
            double[] next = new double[groups];
            for (int g = 0; g < groups; g++) {
                double sum = 0;
                for (int h = 0; h < groups; h++)
                    sum += r0 * contacts[g][h] * z[h];
                next[g] = 1 - Math.Exp(-sum);
            }
            z = next;
        }
        double[] terminal = AgeStates(contacts, Constants(730, 1), ageInitial)[^1];
        double equation = 0, simulated = 0;
        for (int g = 0; g < groups; g++) {
            double actual = (populations[g] - terminal[6 * g]) / populations[g];
            equation += populations[g] * z[g];
            simulated += populations[g] * actual;
            reproduction.Add("final_size_age " + data.groups[g].name + " equation " + F(z[g]) +
                             " simulated " + F(actual));
        }
        reproduction.Add("final_size_age total equation " + F(equation / population) + " simulated " +
                         F(simulated / population));
        ageFitted = AgeStates(contacts, multipliers, ageInitial);
        for (int d = 0; d < days; d += 7) {
            double[] previous = d == 0 ? ageInitial : ageFitted[d - 1];
            reproduction.Add("age_rt " + (d + 1) + " " +
                             F(Power(Ngm(contacts, previous, multipliers[d])).value) + " homogeneous " +
                             F(rt[d]));
        }
        for (int first = 0; first < days; first += 7) {
            int end = Math.Min(days, first + 7);
            double[] incidence = new double[groups];
            for (int d = first; d < end; d++)
                for (int g = 0; g < groups; g++)
                    incidence[g] += ageFitted[d][6 * g + 5];
            reproduction.Add("age_weekly " + (first / 7 + 1) + " days " + (first + 1) + " " + end + " " +
                             Values(incidence, 1));
        }
        double[] infections = new double[groups];
        for (int g = 0; g < groups; g++)
            for (int d = 0; d < days; d++)
                infections[g] += ageFitted[d][6 * g + 5];
        double total = Sum(infections);
        terminal = ageFitted[^1];
        for (int g = 0; g < groups; g++) {
            double[] series = Column(ageFitted, 6 * g + 5);
            int peak = Peak(series);
            reproduction.Add("age " + data.groups[g].name + " attack " +
                             F((populations[g] - terminal[6 * g]) / populations[g]) + " infections " +
                             F(infections[g], 1) + " share " + F(infections[g] / total) + " deaths " +
                             F(terminal[6 * g + 4], 1) + " peak_day " + (peak + 1) + " peak " +
                             F(series[peak], 1));
        }
        foreach (DataIO.ContactChange change in settings.changes) {
            int target = -1;
            for (int g = 0; g < groups; g++)
                if (data.groups[g].name.Equals(change.group))
                    target = g;
            double[][] changed = Enumerable.Range(0, groups)
                                     .Select(
                                         _ => new double[groups])
                                     .ToArray(),
                       ngm = Enumerable.Range(0, groups)
                                 .Select(
                                     _ => new double[groups])
                                 .ToArray();
            for (int g = 0; g < groups; g++)
                for (int h = 0; h < groups; h++) {
                    changed[g][h] = contacts[g][h] * (g == target ? change.factor : 1) *
                                    (h == target ? change.factor : 1);
                    ngm[g][h] = r0 * changed[g][h] * populations[g] / populations[h];
                }
            List<double[]> states = AgeStates(changed, multipliers, ageInitial);
            double[] last = states[^1];
            double deaths = 0, attack = 0;
            for (int g = 0; g < groups; g++) {
                deaths += last[6 * g + 4];
                attack += populations[g] - last[6 * g];
            }
            reproduction.Add("contact_change " + change.name + " group " + change.group + " factor " +
                             F(change.factor) + " r0_age " + F(Power(ngm).value) + " infections " +
                             F(Sum(AgeIncidence(states)), 1) + " deaths " + F(deaths, 1) + " attack " +
                             F(attack / population));
        }
    }
    public static void ModelComparisons() {
        string[] names = { "sir", "seir", "age" };
        double[][] series = { SirIncidence(beta), incidence, AgeIncidence(ageFitted) };
        for (int k = 0; k < 3; k++) {
            double numerator = 0, denominator = 0;
            for (int d = 0; d < days; d++) {
                numerator += data.cases[d] * series[k][d];
                denominator += series[k][d] * series[k][d];
            }
            double optimal = numerator / denominator;
            fit.Add("model " + names[k] + " rmse " + F(Rmse(Squared(series[k], rho, data.cases, 0, days))) +
                    " peak_day " + (Peak(series[k]) + 1) + " rho_opt " + F(optimal, 6) + " rmse_opt " +
                    F(Rmse(Squared(series[k], optimal, data.cases, 0, days))));
        }
        Fitting.Golden search = Fitting.SearchGolden(
            x => Squared(SirIncidence(x), rho, data.cases, 0, days), settings.Real("beta_grid", 0),
            settings.Real("beta_grid", 1), settings.Integer("golden", 0));
        fit.Add("model sir_fit beta " + F(search.point, 6) + " rmse " + F(Rmse(search.value)) + " peak_day " +
                (Peak(SirIncidence(search.point)) + 1));
    }
    public static void Projections() {
        scenarios.Add("scenario,day,incidence,reported");
        int horizon = settings.Integer("horizon", 0);
        double reference = 0;
        bool first = true;
        foreach (DataIO.Scenario scenario in settings.scenarios) {
            double m = scenario.multiplier;
            List<double[]> states = States(beta, gamma, Constants(horizon, m), fitted[^1], sigma);
            double[] projected = Scale(Column(states, 5), rho);
            int peak = Peak(projected), above = 0;
            string below = "never";
            for (int j = 0; j < horizon; j++) {
                scenarios.Add(scenario.name + "," + (days + j + 1) + "," + F(states[j][5], 1) + "," +
                              F(projected[j], 1));
                if (projected[j] >= settings.Real("threshold", 0))
                    above++;
                else if (below.Equals("never"))
                    below = Convert.ToString(days + j + 1);
            }
            double total = Sum(projected);
            if (first) {
                reference = total;
                first = false;
            }
            reproduction.Add("scenario " + scenario.name + " multiplier " + F(m) + " rt " +
                             F(r0 * m * fitted[^1][0] / population) + " reported " + F(total, 1) +
                             " peak_day " + (days + peak + 1) + " peak " + F(projected[peak], 1) +
                             " attack " + F((population - states[^1][0]) / population) + " final_size " +
                             F(FinalSize(r0 * m)) + " averted " + F(reference - total, 1) + " below " +
                             below + " days_above " + above);
            double low = beta - 2 * seBeta, high = beta + 2 * seBeta;
            double[] combined = new double[days + horizon];
            Array.Copy(multipliers, 0, combined, 0, days);
            Array.Fill(combined, m, days, combined.Length - days);
            double[] totals = new double[2];
            double[] betas = { low, high };
            for (int k = 0; k < 2; k++) {
                List<double[]> band = States(betas[k], gamma, combined, initial, sigma);
                for (int d = days; d < days + horizon; d++)
                    totals[k] += rho * band[d][5];
            }
            reproduction.Add("scenario_band " + scenario.name + " beta_low " + F(low, 6) + " reported_low " +
                             F(totals[0], 1) + " beta_high " + F(high, 6) + " reported_high " +
                             F(totals[1], 1));
            double[] last = AgeStates(contacts, Constants(horizon, m), ageFitted[^1])[^1],
                     attack = new double[groups];
            double deaths = 0;
            for (int g = 0; g < groups; g++) {
                attack[g] = (populations[g] - last[6 * g]) / populations[g];
                deaths += last[6 * g + 4];
            }
            reproduction.Add("scenario_age " + scenario.name + " attack " + Values(attack, 4) + " deaths " +
                             F(deaths, 1));
        }
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Prepare();
        FitModel();
        FittedCourse();
        Diagnostics();
        ProfilesAndBacktest();
        Homogeneous();
        Ages();
        ModelComparisons();
        Projections();
        DataIO.Write("fit.txt", fit);
        DataIO.Write("trajectories.csv", trajectories);
        DataIO.Write("scenarios.csv", scenarios);
        DataIO.Write("reproduction.txt", reproduction);
        DataIO.Write("curve_plot.txt", Report.Plot(data.cases, reported));
    }
}
