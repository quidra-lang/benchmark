import java.util.*;

public final class Main {
    static DataIO.Data data;
    static DataIO.Settings settings;
    static int days, groups, population, caseTotal, deathTotal;
    static int[] populations, ageInflows;
    static double[] fatalities, initial, sirInitial, ageInitial, multipliers;
    static double fatality, sigma, gamma0, beta, rho, gamma, r0, betaGrid, rhoGrid, betaGolden, sseGrid,
        sseGolden, sseNelder, deltaBeta, deltaRho, seBeta;
    static List<double[]> fitted, ageFitted;
    static double[] incidence, reported, residuals, modelDeaths, average7, rt, generation;
    static double[][] contacts;
    static List<String> fit = new ArrayList<>(), reproduction = new ArrayList<>(),
                        trajectories = new ArrayList<>(), scenarios = new ArrayList<>();
    record Key(double beta, double gamma) {}
    record Eigen(double value, double[] vector) {}
    static Map<Key, double[]> cache = new HashMap<>();
    static String f(double value, int digits) {
        return Report.f(value, digits);
    }
    static String f(double value) {
        return f(value, 4);
    }
    static double sum(double[] values) {
        double total = 0;
        for (double value : values)
            total += value;
        return total;
    }
    static int sum(int[] values) {
        int total = 0;
        for (int value : values)
            total += value;
        return total;
    }
    static int peak(double[] values) {
        int selected = 0;
        for (int i = 1; i < values.length; i++)
            if (values[i] > values[selected])
                selected = i;
        return selected;
    }
    static double[] constants(int size, double value) {
        double[] result = new double[size];
        Arrays.fill(result, value);
        return result;
    }
    static double[] column(List<double[]> states, int column) {
        double[] values = new double[states.size()];
        for (int i = 0; i < values.length; i++)
            values[i] = states.get(i)[column];
        return values;
    }
    static double[] scale(double[] values, double factor) {
        double[] result = new double[values.length];
        for (int i = 0; i < result.length; i++)
            result[i] = factor * values[i];
        return result;
    }
    static String values(double[] values, int digits) {
        List<String> result = new ArrayList<>();
        for (double value : values)
            result.add(f(value, digits));
        return String.join(" ", result);
    }
    static double rmse(double error, int count) {
        return Math.sqrt(error / count);
    }
    static double rmse(double error) {
        return rmse(error, days);
    }
    static double squared(double[] values, double coefficient, int[] observations, int first, int last) {
        double sum = 0;
        for (int i = first; i < last; i++) {
            double e = coefficient * values[i] - observations[i];
            sum += e * e;
        }
        return sum;
    }
    static double[] sequence(List<DataIO.Intervention> interventions, int count) {
        double[] result = new double[count];
        int k = 0;
        for (int d = 1; d <= count; d++) {
            while (k + 1 < interventions.size() && interventions.get(k + 1).day() <= d)
                k++;
            result[d - 1] = interventions.get(k).multiplier();
        }
        return result;
    }
    static List<double[]> states(double b, double g, double[] mu, double[] state, double sigmaValue) {
        return Integrator.simulate(Models.seird(population, sigmaValue, fatality, b, g), state, mu,
                                   new int[] {5});
    }
    static List<double[]> states(double b, double g) {
        return states(b, g, multipliers, initial, sigma);
    }
    static List<double[]> ageStates(double[][] w, double[] mu, double[] state) {
        return Integrator.simulate(Models.age(populations, fatalities, sigma, beta, gamma, w), state, mu,
                                   ageInflows);
    }
    static double[] incidence(double b, double g) {
        Key key = new Key(b, g);
        if (!cache.containsKey(key))
            cache.put(key, column(states(b, g), 5));
        return cache.get(key);
    }
    static double error(double b, double g, double p) {
        return squared(incidence(b, g), p, data.cases(), 0, days);
    }
    static double[] ageIncidence(List<double[]> states) {
        double[] result = new double[states.size()];
        for (int d = 0; d < result.length; d++)
            for (int g = 0; g < groups; g++)
                result[d] += states.get(d)[6 * g + 5];
        return result;
    }
    static double[] sirIncidence(double b) {
        return column(
            Integrator.simulate(Models.sir(population, b, gamma), sirInitial, multipliers, new int[] {3}), 3);
    }
    static void prepare() throws Exception {
        data = DataIO.read();
        settings = data.settings();
        days = data.cases().length;
        groups = data.groups().size();
        populations = new int[groups];
        fatalities = new double[groups];
        ageInflows = new int[groups];
        for (int g = 0; g < groups; g++) {
            DataIO.Group group = data.groups().get(g);
            populations[g] = group.population();
            fatalities[g] = group.fatality();
            population += populations[g];
            fatality += populations[g] * fatalities[g];
            ageInflows[g] = 6 * g + 5;
        }
        fatality /= population;
        caseTotal = sum(data.cases());
        deathTotal = sum(data.deaths());
        sigma = settings.real("sigma", 0);
        gamma0 = settings.real("gamma", 0);
        double e = settings.real("initial", 0), i = settings.real("initial", 1);
        initial = new double[] {population - e - i, e, i, 0, 0, 0};
        sirInitial = new double[] {population - e - i, e + i, 0, 0};
        ageInitial = new double[groups * 6];
        for (int g = 0; g < groups; g++) {
            double eg = e * populations[g] / population, ig = i * populations[g] / population;
            ageInitial[6 * g] = populations[g] - eg - ig;
            ageInitial[6 * g + 1] = eg;
            ageInitial[6 * g + 2] = ig;
        }
        multipliers = sequence(data.interventions(), days);
    }
    static void goldenLines(int round, String name, Fitting.Golden search) {
        for (int i = 0; i < search.records().size(); i++) {
            Fitting.GoldenRecord r = search.records().get(i);
            fit.add("golden " + round + " " + name + " " + i + " a " + f(r.a(), 6) + " b " + f(r.b(), 6) +
                    " c " + f(r.c(), 6) + " d " + f(r.d(), 6) + " rmse " + f(rmse(r.fc())) + " " +
                    f(rmse(r.fd())));
        }
        fit.add("golden_result " + round + " " + name + " " + f(search.point(), 6) + " sse " +
                f(search.value(), 1));
    }
    static void fitModel() {
        double bmin = settings.real("beta_grid", 0), bmax = settings.real("beta_grid", 1),
               pmin = settings.real("rho_grid", 0), pmax = settings.real("rho_grid", 1);
        int nb = settings.integer("beta_grid", 2), np = settings.integer("rho_grid", 2);
        deltaBeta = (bmax - bmin) / (nb - 1);
        deltaRho = (pmax - pmin) / (np - 1);
        double[] betas = new double[nb], rhos = new double[np];
        for (int i = 0; i < nb; i++)
            betas[i] = bmin + (bmax - bmin) * i / (nb - 1);
        for (int j = 0; j < np; j++)
            rhos[j] = pmin + (pmax - pmin) * j / (np - 1);
        fit.add("data days " + days + " cases " + caseTotal + " deaths " + deathTotal + " population " +
                population + " fatality " + f(fatality, 6));
        fit.add("grid gamma " + f(gamma0) + " rho " + values(rhos, 4));
        sseGrid = Double.MAX_VALUE;
        for (int i = 0; i < nb; i++) {
            double[] errors = new double[np];
            for (int j = 0; j < np; j++) {
                errors[j] = error(betas[i], gamma0, rhos[j]);
                if (errors[j] < sseGrid) {
                    sseGrid = errors[j];
                    betaGrid = betas[i];
                    rhoGrid = rhos[j];
                }
            }
            List<String> scores = new ArrayList<>();
            for (double value : errors)
                scores.add(f(rmse(value), 2));
            fit.add("grid beta " + f(betas[i]) + " rmse " + String.join(" ", scores));
        }
        fit.add("grid_best beta " + f(betaGrid) + " rho " + f(rhoGrid) + " sse " + f(sseGrid, 1) + " rmse " +
                f(rmse(sseGrid)));
        double b = betaGrid, p = rhoGrid;
        int ng = settings.integer("golden", 0);
        for (int round = 1; round <= settings.integer("golden", 1); round++) {
            final double fixedP = p;
            Fitting.Golden bs =
                Fitting.golden(x -> error(x, gamma0, fixedP), b - deltaBeta, b + deltaBeta, ng);
            goldenLines(round, "beta", bs);
            b = bs.point();
            final double fixedB = b;
            Fitting.Golden ps = Fitting.golden(x -> error(fixedB, gamma0, x), p - deltaRho, p + deltaRho, ng);
            goldenLines(round, "rho", ps);
            p = ps.point();
            sseGolden = ps.value();
        }
        betaGolden = b;
        rho = p;
        Fitting.Simplex simplex = Fitting.nelder(
            (x, y)
                -> error(x, y, rho),
            b, gamma0, settings.real("simplex", 0), settings.real("simplex", 1),
            settings.real("nelder_mead", 0), settings.real("nelder_mead", 1), settings.real("nelder_mead", 2),
            settings.real("nelder_mead", 3), settings.integer("nelder_mead", 4));
        for (Fitting.Vertex v : simplex.initial())
            fit.add("simplex " + v.serial() + " beta " + f(v.beta(), 6) + " gamma " + f(v.gamma(), 6) +
                    " rmse " + f(rmse(v.value())));
        for (int i = 0; i < simplex.operations().size(); i++) {
            Fitting.Operation op = simplex.operations().get(i);
            Fitting.Vertex v = op.best();
            fit.add("nelder_mead " + (i + 1) + " " + op.name() + " beta " + f(v.beta(), 6) + " gamma " +
                    f(v.gamma(), 6) + " rmse " + f(rmse(v.value())));
        }
        for (int i = 0; i < 3; i++) {
            Fitting.Vertex v = simplex.vertices().get(i);
            fit.add("final_simplex " + (i + 1) + " beta " + f(v.beta(), 6) + " gamma " + f(v.gamma(), 6) +
                    " rmse " + f(rmse(v.value())));
        }
        Fitting.Vertex best = simplex.vertices().get(0);
        beta = best.beta();
        gamma = best.gamma();
        sseNelder = best.value();
        r0 = beta / gamma;
        double mean = (double)caseTotal / days, sst = 0;
        for (int c : data.cases()) {
            double e = c - mean;
            sst += e * e;
        }
        fit.add("fitted beta " + f(beta, 6) + " gamma " + f(gamma, 6) + " rho " + f(rho, 6) + " sigma " +
                f(sigma, 6) + " r0 " + f(r0));
        fit.add("sse grid " + f(sseGrid, 1) + " golden " + f(sseGolden, 1) + " nelder_mead " +
                f(sseNelder, 1) + " rmse " + f(rmse(sseNelder)) + " r2 " + f(1 - sseNelder / sst));
        String[] names = {"grid", "golden", "nelder_mead"};
        double[] bs = {betaGrid, betaGolden, beta}, gs = {gamma0, gamma0, gamma}, ps = {rhoGrid, rho, rho},
                 ss = {sseGrid, sseGolden, sseNelder};
        for (int k = 0; k < 3; k++)
            fit.add("stage " + names[k] + " beta " + f(bs[k], 6) + " gamma " + f(gs[k], 6) + " rho " +
                    f(ps[k], 6) + " r0 " + f(bs[k] / gs[k]) + " rmse " + f(rmse(ss[k])));
    }
    static void fittedCourse() {
        fitted = states(beta, gamma);
        incidence = column(fitted, 5);
        reported = scale(incidence, rho);
        residuals = new double[days];
        modelDeaths = new double[days];
        average7 = new double[days];
        rt = new double[days];
        trajectories.add(
            "day,S,E,I,R,D,incidence,reported,observed,average7,cumulative_observed,cumulative_reported");
        int observed = 0;
        double cumulative = 0;
        for (int d = 0; d < days; d++) {
            double[] y = fitted.get(d);
            residuals[d] = data.cases()[d] - reported[d];
            modelDeaths[d] = y[4] - (d == 0 ? 0 : fitted.get(d - 1)[4]);
            int count = 0;
            for (int j = Math.max(0, d - 6); j <= d; j++)
                count += data.cases()[j];
            average7[d] = (double)count / Math.min(d + 1, 7);
            rt[d] = r0 * multipliers[d] * (d == 0 ? initial[0] : fitted.get(d - 1)[0]) / population;
            observed += data.cases()[d];
            cumulative += reported[d];
            String row = Integer.toString(d + 1);
            for (int c = 0; c < 6; c++)
                row += "," + f(y[c], 1);
            row += "," + f(reported[d], 1) + "," + data.cases()[d] + "," + f(average7[d], 2) + "," +
                   observed + "," + f(cumulative, 1);
            trajectories.add(row);
        }
    }

    static void diagnostics() {
        double residualSum = 0, absolute = 0, u = 0, difference = 0;
        int positive = 0, runs = 1, maximum = 0;
        for (int d = 0; d < days; d++) {
            double e = residuals[d];
            residualSum += e;
            absolute += Math.abs(e);
            u += e * e;
            if (e > 0)
                positive++;
            if (Math.abs(e) > Math.abs(residuals[maximum]))
                maximum = d;
            if (d > 0) {
                if ((e > 0) != (residuals[d - 1] > 0))
                    runs++;
                double delta = e - residuals[d - 1];
                difference += delta * delta;
            }
        }
        fit.add("residuals sum " + f(residualSum, 1) + " mae " + f(absolute / days, 1) + " max " +
                f(residuals[maximum], 1) + " day " + (maximum + 1) + " positive " + positive + " runs " +
                runs + " durbin_watson " + f(difference / u));
        double[] autocorrelation = new double[7];
        for (int k = 1; k <= 7; k++) {
            double sum = 0;
            for (int d = 0; d < days - k; d++)
                sum += residuals[d] * residuals[d + k];
            autocorrelation[k - 1] = sum / u;
        }
        fit.add("autocorrelation " + values(autocorrelation, 4));
        int outliers = 0;
        for (int d = 0; d < days; d++) {
            double z = residuals[d] / Math.sqrt(reported[d]);
            if (Math.abs(z) > settings.real("outlier", 0)) {
                outliers++;
                fit.add("outlier " + (d + 1) + " observed " + data.cases()[d] + " fitted " +
                        f(reported[d], 1) + " z " + f(z));
            }
        }
        fit.add("outliers " + outliers);
        int[] counts = new int[7];
        double[] totals = new double[7], factors = new double[7];
        for (int d = 0; d < days; d++) {
            counts[d % 7] += data.cases()[d];
            totals[d % 7] += reported[d];
        }
        for (int k = 0; k < 7; k++) {
            factors[k] = counts[k] / totals[k];
            fit.add("weekday " + (k + 1) + " observed " + counts[k] + " fitted " + f(totals[k], 1) +
                    " factor " + f(factors[k]));
        }
        double adjusted = 0;
        for (int d = 0; d < days; d++) {
            double e = reported[d] * factors[d % 7] - data.cases()[d];
            adjusted += e * e;
        }
        fit.add("weekday_adjusted rmse " + f(rmse(adjusted)));
        double infections = sum(incidence);
        fit.add("burden infections " + f(infections, 1) + " ascertainment " + f(caseTotal / infections) +
                " deaths_per_infection " + f(deathTotal / infections, 6));
        double product = 0, squares = 0;
        for (int d = 0; d < days; d++) {
            product += modelDeaths[d] * data.deaths()[d];
            squares += modelDeaths[d] * modelDeaths[d];
        }
        double kappa = product / squares;
        fit.add("deaths observed " + deathTotal + " model " + f(fitted.getLast()[4], 1) + " rmse " +
                f(rmse(squared(modelDeaths, 1, data.deaths(), 0, days))) + " scale " + f(kappa) +
                " implied_fatality " + f(fatality * kappa, 6) + " cfr " + f((double)deathTotal / caseTotal));
        double largest = -Double.MAX_VALUE;
        int lag = 0;
        for (int k = 0; k <= settings.integer("death_lag", 0); k++) {
            int a = 0, b = 0, y = 0, dead = 0, cases = 0;
            for (int d = 0; d < days - k; d++) {
                a += data.cases()[d] * data.deaths()[d + k];
                b += data.cases()[d] * data.cases()[d];
                y += data.deaths()[d + k] * data.deaths()[d + k];
                dead += data.deaths()[d + k];
                cases += data.cases()[d];
            }
            double correlation = a / Math.sqrt((double)b * y);
            if (correlation > largest) {
                largest = correlation;
                lag = k;
            }
            fit.add("death_lag " + k + " correlation " + f(correlation) + " cfr " + f((double)dead / cases));
        }
        fit.add("death_best_lag " + lag);
        int previous = 0;
        for (int first = 0; first < days; first += 7) {
            int end = Math.min(days, first + 7), cases = 0, deaths = 0;
            double predicted = 0, dead = 0;
            for (int d = first; d < end; d++) {
                cases += data.cases()[d];
                deaths += data.deaths()[d];
                predicted += reported[d];
                dead += modelDeaths[d];
            }
            fit.add("weekly " + (first / 7 + 1) + " days " + (first + 1) + " " + end + " observed " + cases +
                    " fitted " + f(predicted, 1) + " deaths_observed " + deaths + " deaths_model " +
                    f(dead, 1) + " growth " + (first == 0 ? "-" : f((double)cases / previous)));
            previous = cases;
        }
    }
    static void profilesAndBacktest() {
        String[] names = {"beta", "gamma", "rho"};
        double[] fittedValues = {beta, gamma, rho};
        for (int parameter = 0; parameter < 3; parameter++) {
            double v = fittedValues[parameter], h = v / 100;
            double[] errors = new double[11];
            for (int k = -5; k <= 5; k++) {
                double[] point = fittedValues.clone();
                point[parameter] = v * (1 + k / 100.0);
                errors[k + 5] = error(point[0], point[1], point[2]);
                fit.add("profile " + names[parameter] + " " + k + " value " + f(point[parameter], 6) +
                        " rmse " + f(rmse(errors[k + 5])));
            }
            double curvature = (errors[6] - 2 * errors[5] + errors[4]) / (h * h),
                   variance = sseNelder / (days - 3), standard = Math.sqrt(2 * variance / curvature);
            if (parameter == 0)
                seBeta = standard;
            fit.add("profile_se " + names[parameter] + " " + f(standard, 6));
        }
        int nt = days - settings.integer("holdout", 0), ng = settings.integer("golden", 0);
        double[] prefix = Arrays.copyOf(multipliers, nt);
        Fitting.Golden bs = Fitting.golden(
            x
            -> squared(column(states(x, gamma, prefix, initial, sigma), 5), rho, data.cases(), 0, nt),
            beta - deltaBeta, beta + deltaBeta, ng);
        double bb = bs.point();
        double[] trained = column(states(bb, gamma, prefix, initial, sigma), 5);
        Fitting.Golden ps =
            Fitting.golden(x -> squared(trained, x, data.cases(), 0, nt), rho - deltaRho, rho + deltaRho, ng);
        double pb = ps.point();
        double[] forecast = scale(incidence(bb, gamma), pb);
        fit.add("backtest train_days " + nt + " beta " + f(bb, 6) + " rho " + f(pb, 6) + " train_rmse " +
                f(rmse(ps.value(), nt)) + " test_rmse " +
                f(rmse(squared(forecast, 1, data.cases(), nt, days), days - nt)) + " full_fit_test_rmse " +
                f(rmse(squared(reported, 1, data.cases(), nt, days), days - nt)));
        for (int d = nt; d < days; d++)
            fit.add("backtest_day " + (d + 1) + " observed " + data.cases()[d] + " forecast " +
                    f(forecast[d], 1) + " error " + f(data.cases()[d] - forecast[d], 1));
        List<DataIO.Intervention> estimated = new ArrayList<>(data.interventions());
        double after = sseNelder;
        for (int k = 1; k < estimated.size(); k++) {
            final int index = k;
            DataIO.Intervention given = data.interventions().get(k);
            Fitting.Golden effect = Fitting.golden(
                x
                -> {
                    List<DataIO.Intervention> changed = new ArrayList<>(estimated);
                    changed.set(index, new DataIO.Intervention(given.day(), x));
                    return squared(column(states(beta, gamma, sequence(changed, days), initial, sigma), 5),
                                   rho, data.cases(), 0, days);
                },
                given.multiplier() - settings.real("effect_width", 0),
                given.multiplier() + settings.real("effect_width", 0), ng);
            estimated.set(k, new DataIO.Intervention(given.day(), effect.point()));
            after = effect.value();
            fit.add("effect " + (k + 1) + " day " + given.day() + " given " + f(given.multiplier()) +
                    " estimated " + f(effect.point(), 6) + " sse " + f(after, 1));
        }
        fit.add("effect_sse before " + f(sseNelder, 1) + " after " + f(after, 1) + " rmse " + f(rmse(after)));
        String[] sensitivities = {"beta", "gamma", "sigma", "rho"};
        for (int k = 0; k < 4; k++)
            for (double factor : new double[] {0.9, 1.1}) {
                double[] point = {beta, gamma, sigma, rho};
                point[k] = point[k] * factor;
                List<double[]> states = states(point[0], point[1], multipliers, initial, point[2]);
                double[] series = column(states, 5);
                int peak = peak(series);
                fit.add("sensitivity " + sensitivities[k] + " " + f(factor, 2) + " r0 " +
                        f(point[0] / point[1]) + " rmse " +
                        f(rmse(squared(series, point[3], data.cases(), 0, days))) + " peak_day " +
                        (peak + 1) + " peak " + f(point[3] * series[peak], 1) + " attack " +
                        f((population - states.getLast()[0]) / population));
            }
    }
    static double finalSize(double reproductionNumber) {
        if (reproductionNumber <= 1)
            return 0;
        double lo = 1 - 1 / reproductionNumber, hi = 1;
        for (int i = 0; i < 20; i++) {
            double mid = (lo + hi) / 2, g = 1 - mid - Math.exp(-reproductionNumber * mid);
            if (g > 0)
                lo = mid;
            else
                hi = mid;
        }
        return (lo + hi) / 2;
    }
    static Eigen power(double[][] matrix) {
        double[] vector = constants(matrix.length, 1.0 / matrix.length);
        double value = 0;
        for (int k = 0; k < 200; k++) {
            double[] next = new double[vector.length];
            for (int g = 0; g < next.length; g++)
                for (int h = 0; h < next.length; h++)
                    next[g] += matrix[g][h] * vector[h];
            value = sum(next);
            for (int g = 0; g < next.length; g++)
                next[g] /= value;
            vector = next;
        }
        return new Eigen(value, vector);
    }
    static void homogeneous() {
        double[] terminal = states(beta, gamma, constants(730, 1), initial, sigma).getLast();
        reproduction.add("r0 " + f(r0) + " herd_immunity " + f(1 - 1 / r0));
        reproduction.add("final_size equation " + f(finalSize(r0)) + " simulated " +
                         f((population - terminal[0]) / population));
        int length = settings.integer("generation", 0);
        double[] inflow = column(Integrator.simulate(Models.generation(sigma, gamma), new double[] {1, 0, 0},
                                                     constants(length, 1), new int[] {2}),
                                 2);
        double coverage = sum(inflow), mean = 0;
        generation = new double[length];
        for (int i = 0; i < length; i++) {
            generation[i] = inflow[i] / coverage;
            mean += (i + 0.5) * generation[i];
        }
        reproduction.add("generation mean " + f(mean) + " theory " + f(1 / sigma + 1 / gamma) + " coverage " +
                         f(coverage));
        for (int i = 0; i < length; i++)
            reproduction.add("generation_weight " + (i + 1) + " " + f(generation[i], 6));
        int modelPeak = peak(incidence), infectiousPeak = peak(column(fitted, 2)), observedPeak = 0,
            averagePeak = peak(average7);
        for (int i = 1; i < days; i++)
            if (data.cases()[i] > data.cases()[observedPeak])
                observedPeak = i;
        reproduction.add("peak model day " + (modelPeak + 1) + " incidence " + f(incidence[modelPeak], 1) +
                         " reported " + f(reported[modelPeak], 1) + " infectious_day " +
                         (infectiousPeak + 1) + " infectious " + f(fitted.get(infectiousPeak)[2], 1));
        reproduction.add("peak observed day " + (observedPeak + 1) + " cases " + data.cases()[observedPeak] +
                         " average7_day " + (averagePeak + 1) + " average7 " + f(average7[averagePeak], 2));
        for (int k = 0; k < data.interventions().size(); k++) {
            int first = data.interventions().get(k).day() - 1,
                end = k + 1 < data.interventions().size() ? data.interventions().get(k + 1).day() - 1 : days,
                count = 0;
            double predicted = 0, errors = 0, bias = 0;
            for (int d = first; d < end; d++) {
                count += data.cases()[d];
                predicted += reported[d];
                errors += residuals[d] * residuals[d];
                bias += residuals[d];
            }
            reproduction.add("period " + (k + 1) + " days " + (first + 1) + " " + end + " multiplier " +
                             f(data.interventions().get(k).multiplier()) + " rt_start " + f(rt[first]) +
                             " rt_end " + f(rt[end - 1]) + " observed " + count + " fitted " +
                             f(predicted, 1) + " rmse " + f(rmse(errors, end - first)) + " bias " +
                             f(bias / (end - first), 1));
        }
        for (int target : settings.integers("milestones")) {
            int observed = 0;
            double predicted = 0;
            String observedDay = "never", fittedDay = "never";
            for (int d = 0; d < days; d++) {
                observed += data.cases()[d];
                predicted += reported[d];
                if (observedDay.equals("never") && observed >= target)
                    observedDay = Integer.toString(d + 1);
                if (fittedDay.equals("never") && predicted >= target)
                    fittedDay = Integer.toString(d + 1);
            }
            reproduction.add("milestone " + target + " observed " + observedDay + " fitted " + fittedDay);
        }
        double fittedTotal = sum(reported);
        double[] noInterventions =
            scale(column(states(beta, gamma, constants(days, data.interventions().get(0).multiplier()),
                                initial, sigma),
                         5),
                  rho);
        int peak = peak(noInterventions);
        reproduction.add("counterfactual none reported " + f(sum(noInterventions), 1) + " peak_day " +
                         (peak + 1) + " peak " + f(noInterventions[peak], 1) + " averted " +
                         f(sum(noInterventions) - fittedTotal, 1));
        for (int k = 1; k < data.interventions().size(); k++) {
            List<DataIO.Intervention> removed = new ArrayList<>(data.interventions());
            removed.remove(k);
            double total =
                sum(scale(column(states(beta, gamma, sequence(removed, days), initial, sigma), 5), rho));
            reproduction.add("counterfactual without " + (k + 1) + " reported " + f(total, 1) + " averted " +
                             f(total - fittedTotal, 1));
        }
        for (int k = 1; k < data.interventions().size(); k++)
            for (int shift : new int[] {-7, 7}) {
                List<DataIO.Intervention> changed = new ArrayList<>(data.interventions());
                DataIO.Intervention given = changed.get(k);
                changed.set(k, new DataIO.Intervention(given.day() + shift, given.multiplier()));
                double total =
                    sum(scale(column(states(beta, gamma, sequence(changed, days), initial, sigma), 5), rho));
                reproduction.add("timing " + (k + 1) + " shift " + shift + " reported " + f(total, 1) +
                                 " change " + f(total - fittedTotal, 1));
            }
        for (int d = 1; d < days; d++)
            if ((rt[d] < 1) != (rt[d - 1] < 1))
                reproduction.add("rt_cross day " + (d + 1) + " " + (rt[d] < 1 ? "down" : "up"));
        double[] pressure = new double[days];
        for (int d = 0; d < days; d++)
            for (int s = 1; s <= Math.min(length, d); s++)
                pressure[d] += generation[s - 1] * data.cases()[d - s];
        for (int d = 0; d < days; d++) {
            String empirical = "-";
            if (d + 1 >= length + 7) {
                int count = 0;
                double sum = 0;
                for (int j = d - 6; j <= d; j++) {
                    count += data.cases()[j];
                    sum += pressure[j];
                }
                empirical = f(count / sum);
            }
            reproduction.add("rt " + (d + 1) + " model " + f(rt[d]) + " empirical " + empirical);
        }
    }

    static double[][] ngm(double[][] w, double[] susceptible, double multiplier) {
        double[][] result = new double[groups][groups];
        for (int g = 0; g < groups; g++)
            for (int h = 0; h < groups; h++)
                result[g][h] = multiplier * r0 * w[g][h] * susceptible[6 * g] / populations[h];
        return result;
    }
    static void ages() {
        double average = 0;
        for (int g = 0; g < groups; g++) {
            double row = 0;
            for (int h = 0; h < groups; h++)
                row += data.contacts()[g][h];
            average += populations[g] * row;
        }
        average /= population;
        contacts = new double[groups][groups];
        double[][] matrix = new double[groups][groups];
        for (int g = 0; g < groups; g++)
            for (int h = 0; h < groups; h++) {
                contacts[g][h] = data.contacts()[g][h] / average;
                matrix[g][h] = r0 * contacts[g][h] * populations[g] / populations[h];
            }
        Eigen eigen = power(matrix);
        for (int g = 0; g < groups; g++)
            reproduction.add("ngm " + data.groups().get(g).name() + " " + values(matrix[g], 4));
        reproduction.add("r0_age " + f(eigen.value()) + " ratio " + f(eigen.value() / r0) + " kbar " +
                         f(average) + " eigenvector " + values(eigen.vector(), 4));
        double[] z = constants(groups, 1);
        for (int k = 0; k < 100; k++) {
            double[] next = new double[groups];
            for (int g = 0; g < groups; g++) {
                double sum = 0;
                for (int h = 0; h < groups; h++)
                    sum += r0 * contacts[g][h] * z[h];
                next[g] = 1 - Math.exp(-sum);
            }
            z = next;
        }
        double[] terminal = ageStates(contacts, constants(730, 1), ageInitial).getLast();
        double equation = 0, simulated = 0;
        for (int g = 0; g < groups; g++) {
            double actual = (populations[g] - terminal[6 * g]) / populations[g];
            equation += populations[g] * z[g];
            simulated += populations[g] * actual;
            reproduction.add("final_size_age " + data.groups().get(g).name() + " equation " + f(z[g]) +
                             " simulated " + f(actual));
        }
        reproduction.add("final_size_age total equation " + f(equation / population) + " simulated " +
                         f(simulated / population));
        ageFitted = ageStates(contacts, multipliers, ageInitial);
        for (int d = 0; d < days; d += 7) {
            double[] previous = d == 0 ? ageInitial : ageFitted.get(d - 1);
            reproduction.add("age_rt " + (d + 1) + " " +
                             f(power(ngm(contacts, previous, multipliers[d])).value()) + " homogeneous " +
                             f(rt[d]));
        }
        for (int first = 0; first < days; first += 7) {
            int end = Math.min(days, first + 7);
            double[] incidence = new double[groups];
            for (int d = first; d < end; d++)
                for (int g = 0; g < groups; g++)
                    incidence[g] += ageFitted.get(d)[6 * g + 5];
            reproduction.add("age_weekly " + (first / 7 + 1) + " days " + (first + 1) + " " + end + " " +
                             values(incidence, 1));
        }
        double[] infections = new double[groups];
        for (int g = 0; g < groups; g++)
            for (int d = 0; d < days; d++)
                infections[g] += ageFitted.get(d)[6 * g + 5];
        double total = sum(infections);
        terminal = ageFitted.getLast();
        for (int g = 0; g < groups; g++) {
            double[] series = column(ageFitted, 6 * g + 5);
            int peak = peak(series);
            reproduction.add("age " + data.groups().get(g).name() + " attack " +
                             f((populations[g] - terminal[6 * g]) / populations[g]) + " infections " +
                             f(infections[g], 1) + " share " + f(infections[g] / total) + " deaths " +
                             f(terminal[6 * g + 4], 1) + " peak_day " + (peak + 1) + " peak " +
                             f(series[peak], 1));
        }
        for (DataIO.ContactChange change : settings.changes) {
            int target = -1;
            for (int g = 0; g < groups; g++)
                if (data.groups().get(g).name().equals(change.group()))
                    target = g;
            double[][] changed = new double[groups][groups], ngm = new double[groups][groups];
            for (int g = 0; g < groups; g++)
                for (int h = 0; h < groups; h++) {
                    changed[g][h] = contacts[g][h] * (g == target ? change.factor() : 1) *
                                    (h == target ? change.factor() : 1);
                    ngm[g][h] = r0 * changed[g][h] * populations[g] / populations[h];
                }
            List<double[]> states = ageStates(changed, multipliers, ageInitial);
            double[] last = states.getLast();
            double deaths = 0, attack = 0;
            for (int g = 0; g < groups; g++) {
                deaths += last[6 * g + 4];
                attack += populations[g] - last[6 * g];
            }
            reproduction.add("contact_change " + change.name() + " group " + change.group() + " factor " +
                             f(change.factor()) + " r0_age " + f(power(ngm).value()) + " infections " +
                             f(sum(ageIncidence(states)), 1) + " deaths " + f(deaths, 1) + " attack " +
                             f(attack / population));
        }
    }
    static void modelComparisons() {
        String[] names = {"sir", "seir", "age"};
        double[][] series = {sirIncidence(beta), incidence, ageIncidence(ageFitted)};
        for (int k = 0; k < 3; k++) {
            double numerator = 0, denominator = 0;
            for (int d = 0; d < days; d++) {
                numerator += data.cases()[d] * series[k][d];
                denominator += series[k][d] * series[k][d];
            }
            double optimal = numerator / denominator;
            fit.add("model " + names[k] + " rmse " + f(rmse(squared(series[k], rho, data.cases(), 0, days))) +
                    " peak_day " + (peak(series[k]) + 1) + " rho_opt " + f(optimal, 6) + " rmse_opt " +
                    f(rmse(squared(series[k], optimal, data.cases(), 0, days))));
        }
        Fitting.Golden search = Fitting.golden(x
                                               -> squared(sirIncidence(x), rho, data.cases(), 0, days),
                                               settings.real("beta_grid", 0), settings.real("beta_grid", 1),
                                               settings.integer("golden", 0));
        fit.add("model sir_fit beta " + f(search.point(), 6) + " rmse " + f(rmse(search.value())) +
                " peak_day " + (peak(sirIncidence(search.point())) + 1));
    }
    static void projections() {
        scenarios.add("scenario,day,incidence,reported");
        int horizon = settings.integer("horizon", 0);
        double reference = 0;
        boolean first = true;
        for (DataIO.Scenario scenario : settings.scenarios) {
            double m = scenario.multiplier();
            List<double[]> states = states(beta, gamma, constants(horizon, m), fitted.getLast(), sigma);
            double[] projected = scale(column(states, 5), rho);
            int peak = peak(projected), above = 0;
            String below = "never";
            for (int j = 0; j < horizon; j++) {
                scenarios.add(scenario.name() + "," + (days + j + 1) + "," + f(states.get(j)[5], 1) + "," +
                              f(projected[j], 1));
                if (projected[j] >= settings.real("threshold", 0))
                    above++;
                else if (below.equals("never"))
                    below = Integer.toString(days + j + 1);
            }
            double total = sum(projected);
            if (first) {
                reference = total;
                first = false;
            }
            reproduction.add("scenario " + scenario.name() + " multiplier " + f(m) + " rt " +
                             f(r0 * m * fitted.getLast()[0] / population) + " reported " + f(total, 1) +
                             " peak_day " + (days + peak + 1) + " peak " + f(projected[peak], 1) +
                             " attack " + f((population - states.getLast()[0]) / population) +
                             " final_size " + f(finalSize(r0 * m)) + " averted " + f(reference - total, 1) +
                             " below " + below + " days_above " + above);
            double low = beta - 2 * seBeta, high = beta + 2 * seBeta;
            double[] combined = new double[days + horizon];
            System.arraycopy(multipliers, 0, combined, 0, days);
            Arrays.fill(combined, days, combined.length, m);
            double[] totals = new double[2];
            double[] betas = {low, high};
            for (int k = 0; k < 2; k++) {
                List<double[]> band = states(betas[k], gamma, combined, initial, sigma);
                for (int d = days; d < days + horizon; d++)
                    totals[k] += rho * band.get(d)[5];
            }
            reproduction.add("scenario_band " + scenario.name() + " beta_low " + f(low, 6) +
                             " reported_low " + f(totals[0], 1) + " beta_high " + f(high, 6) +
                             " reported_high " + f(totals[1], 1));
            double[] last = ageStates(contacts, constants(horizon, m), ageFitted.getLast()).getLast(),
                     attack = new double[groups];
            double deaths = 0;
            for (int g = 0; g < groups; g++) {
                attack[g] = (populations[g] - last[6 * g]) / populations[g];
                deaths += last[6 * g + 4];
            }
            reproduction.add("scenario_age " + scenario.name() + " attack " + values(attack, 4) + " deaths " +
                             f(deaths, 1));
        }
    }
    public static void main(String[] args) throws Exception {
        prepare();
        fitModel();
        fittedCourse();
        diagnostics();
        profilesAndBacktest();
        homogeneous();
        ages();
        modelComparisons();
        projections();
        DataIO.write("fit.txt", fit);
        DataIO.write("trajectories.csv", trajectories);
        DataIO.write("scenarios.csv", scenarios);
        DataIO.write("reproduction.txt", reproduction);
        DataIO.write("curve_plot.txt", Report.plot(data.cases(), reported));
    }
}
