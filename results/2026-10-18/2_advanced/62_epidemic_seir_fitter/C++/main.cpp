#include "epidemic.hpp"
static Field multipliers(const std::vector<Intervention> &interventions, int count) {
    Field out(count);
    int index = 0;
    for (int day = 1; day <= count; ++day) {
        while (index + 1 < int(interventions.size()) && interventions[index + 1].day <= day)
            ++index;
        out[day - 1] = interventions[index].multiplier;
    }
    return out;
}
struct Laboratory {
    const Input &input;
    I population = 0;
    double fatality = 0, kbar = 0;
    Field multiplier;
    Matrix contacts;
    explicit Laboratory(const Input &value) : input(value) {
        for (const Group &group : input.groups) {
            population += group.population;
            fatality += double(group.population) * group.fatality;
        }
        fatality /= double(population);
        for (int g = 0; g < int(input.groups.size()); ++g) {
            double row = 0;
            for (double value : input.contacts[g])
                row += value;
            kbar += double(input.groups[g].population) * row;
        }
        kbar /= double(population);
        contacts = input.contacts;
        for (Field &row : contacts)
            for (double &value : row)
                value /= kbar;
        multiplier = multipliers(input.interventions, int(input.cases.size()));
    }
    Model model(Kind kind, double beta, double gamma, double sigma) const {
        Model out;
        out.kind = kind;
        out.beta = beta;
        out.gamma = gamma;
        out.sigma = sigma;
        out.population = double(population);
        out.fatality = fatality;
        out.e0 = input.params.e0;
        out.i0 = input.params.i0;
        if (kind == Kind::age) {
            out.groups = input.groups;
            out.contacts = contacts;
        }
        return out;
    }
};
static Field series(const Model &model, const States &states) {
    Field out;
    for (const Field &state : states) {
        double value = 0;
        if (model.kind == Kind::age) {
            for (int g = 0; g < int(model.groups.size()); ++g)
                value += state[6 * g + 5];
        } else
            value = state[model.kind == Kind::generation ? 2 : model.kind == Kind::sir ? 3 : 5];
        out.push_back(value);
    }
    return out;
}
static States trajectory(const Model &model, const Field &multiplier) {
    return simulate(model, model.initial(), multiplier);
}
static double errors(const Field &values, double coefficient, const std::vector<I> &observations,
                     int start = 0) {
    double out = 0;
    for (int i = 0; i < int(values.size()); ++i) {
        const double difference = coefficient * values[i] - double(observations[start + i]);
        out += difference * difference;
    }
    return out;
}
static double rmse(double value, int count) { return std::sqrt(value / count); }
static double total(const Field &values) {
    double out = 0;
    for (double value : values)
        out += value;
    return out;
}
static int peak(const Field &values) {
    return int(std::max_element(values.begin(), values.end()) - values.begin());
}
static Field reported(const Field &values, double rho) {
    Field out;
    for (double value : values)
        out.push_back(rho * value);
    return out;
}
static void golden_report(Lines &lines, const Golden &search, int round, const std::string &name,
                          int days) {
    for (int i = 0; i < int(search.records.size()); ++i) {
        const GoldenRecord &record = search.records[i];
        line(lines, "golden ", round, " ", name, " ", i, " a ", real(record.a, 6), " b ",
             real(record.b, 6), " c ", real(record.c, 6), " d ", real(record.d, 6), " rmse ",
             real(rmse(record.fc, days), 4), " ", real(rmse(record.fd, days), 4));
    }
    line(lines, "golden_result ", round, " ", name, " ", real(search.point, 6), " sse ",
         real(search.value, 1));
}
static double final_size(double r) {
    if (r <= 1)
        return 0;
    double lo = 1 - 1 / r, hi = 1;
    for (int iteration = 0; iteration < 20; ++iteration) {
        const double mid = (lo + hi) / 2, g = 1 - mid - std::exp(-r * mid);
        if (g > 0)
            lo = mid;
        else
            hi = mid;
    }
    return (lo + hi) / 2;
}
struct Eigen {
    double value = 0;
    Field vector;
};
static Eigen largest(const Matrix &matrix) {
    const int n = int(matrix.size());
    Eigen out{0, Field(n, 1.0 / n)};
    for (int iteration = 0; iteration < 200; ++iteration) {
        Field next(n);
        for (int g = 0; g < n; ++g)
            for (int h = 0; h < n; ++h)
                next[g] += matrix[g][h] * out.vector[h];
        out.value = total(next);
        for (int g = 0; g < n; ++g)
            out.vector[g] = next[g] / out.value;
    }
    return out;
}
static Matrix next_generation(const Laboratory &lab, const Matrix &contacts, double r0) {
    Matrix out = contacts;
    for (int g = 0; g < int(out.size()); ++g)
        for (int h = 0; h < int(out.size()); ++h)
            out[g][h] = r0 * contacts[g][h] * double(lab.input.groups[g].population) /
                        double(lab.input.groups[h].population);
    return out;
}
static double age_deaths(const Field &state, int groups) {
    double out = 0;
    for (int g = 0; g < groups; ++g)
        out += state[6 * g + 4];
    return out;
}
int main() {
    const Input input = load();
    const Params &p = input.params;
    const Laboratory lab(input);
    const int days = int(input.cases.size()), groups = int(input.groups.size());
    const I cases_total = std::accumulate(input.cases.begin(), input.cases.end(), I(0)),
            deaths_total = std::accumulate(input.deaths.begin(), input.deaths.end(), I(0));
    auto seird = [&](double beta, double gamma, double sigma) {
        return lab.model(Kind::seird, beta, gamma, sigma);
    };
    auto incidence = [&](double beta, double gamma, double sigma, const Field &sequence) {
        const Model model = seird(beta, gamma, sigma);
        return series(model, trajectory(model, sequence));
    };
    auto objective = [&](double beta, double gamma, double rho) {
        return errors(incidence(beta, gamma, p.sigma, lab.multiplier), rho, input.cases);
    };
    Lines fit;
    line(fit, "data days ", days, " cases ", cases_total, " deaths ", deaths_total, " population ",
         lab.population, " fatality ", real(lab.fatality, 6));
    Field beta_grid(p.beta_count), rho_grid(p.rho_count);
    for (int i = 0; i < p.beta_count; ++i)
        beta_grid[i] = p.beta_min + (p.beta_max - p.beta_min) * i / (p.beta_count - 1);
    for (int j = 0; j < p.rho_count; ++j)
        rho_grid[j] = p.rho_min + (p.rho_max - p.rho_min) * j / (p.rho_count - 1);
    const double beta_spacing = (p.beta_max - p.beta_min) / (p.beta_count - 1),
                 rho_spacing = (p.rho_max - p.rho_min) / (p.rho_count - 1);
    std::string heading = "grid gamma " + real(p.gamma, 4) + " rho";
    for (double rho : rho_grid)
        heading += " " + real(rho, 4);
    fit.push_back(heading);
    double grid_beta = 0, grid_rho = 0, grid_sse = std::numeric_limits<double>::infinity();
    for (double beta : beta_grid) {
        const Field values = incidence(beta, p.gamma, p.sigma, lab.multiplier);
        std::string row = "grid beta " + real(beta, 4) + " rmse";
        for (double rho : rho_grid) {
            const double value = errors(values, rho, input.cases);
            row += " " + real(rmse(value, days), 2);
            if (value < grid_sse) {
                grid_sse = value;
                grid_beta = beta;
                grid_rho = rho;
            }
        }
        fit.push_back(row);
    }
    line(fit, "grid_best beta ", real(grid_beta, 4), " rho ", real(grid_rho, 4), " sse ",
         real(grid_sse, 1), " rmse ", real(rmse(grid_sse, days), 4));
    double beta_golden = grid_beta, rho_hat = grid_rho, golden_sse = grid_sse;
    for (int round = 1; round <= p.rounds; ++round) {
        const Golden beta =
            golden([&](double value) { return objective(value, p.gamma, rho_hat); },
                   beta_golden - beta_spacing, beta_golden + beta_spacing, p.golden);
        golden_report(fit, beta, round, "beta", days);
        beta_golden = beta.point;
        const Field values = incidence(beta_golden, p.gamma, p.sigma, lab.multiplier);
        const Golden rho = golden([&](double value) { return errors(values, value, input.cases); },
                                  rho_hat - rho_spacing, rho_hat + rho_spacing, p.golden);
        golden_report(fit, rho, round, "rho", days);
        rho_hat = rho.point;
        golden_sse = rho.value;
    }
    const Simplex simplex =
        nelder_mead([&](Point point) { return objective(point[0], point[1], rho_hat); },
                    {beta_golden, p.gamma}, p);
    for (const Vertex &vertex : simplex.initial)
        line(fit, "simplex ", vertex.number, " beta ", real(vertex.point[0], 6), " gamma ",
             real(vertex.point[1], 6), " rmse ", real(rmse(vertex.value, days), 4));
    for (int i = 0; i < int(simplex.records.size()); ++i) {
        const SimplexRecord &record = simplex.records[i];
        line(fit, "nelder_mead ", i + 1, " ", record.operation, " beta ",
             real(record.best.point[0], 6), " gamma ", real(record.best.point[1], 6), " rmse ",
             real(rmse(record.best.value, days), 4));
    }
    for (int i = 0; i < 3; ++i) {
        const Vertex &vertex = simplex.final[i];
        line(fit, "final_simplex ", i + 1, " beta ", real(vertex.point[0], 6), " gamma ",
             real(vertex.point[1], 6), " rmse ", real(rmse(vertex.value, days), 4));
    }
    const double beta_hat = simplex.final[0].point[0], gamma_hat = simplex.final[0].point[1],
                 nm_sse = simplex.final[0].value, r0 = beta_hat / gamma_hat;
    const Model model = seird(beta_hat, gamma_hat, p.sigma);
    const States fitted = trajectory(model, lab.multiplier);
    const Field infections = series(model, fitted), predicted = reported(infections, rho_hat);
    Field residuals(days), deaths(days), average(days), rt(days), infectious(days),
        cumulative_fitted(days);
    std::vector<I> cumulative_observed(days);
    double sst = 0, residual_sum = 0, absolute = 0, u = 0, dw = 0;
    int max_residual = 0, positive = 0, runs = 1;
    I cumulative = 0;
    double cumulative_reported = 0;
    const double mean = double(cases_total) / days;
    for (int d = 0; d < days; ++d) {
        residuals[d] = double(input.cases[d]) - predicted[d];
        residual_sum += residuals[d];
        absolute += std::abs(residuals[d]);
        u += residuals[d] * residuals[d];
        if (std::abs(residuals[d]) > std::abs(residuals[max_residual]))
            max_residual = d;
        positive += residuals[d] > 0;
        if (d > 0) {
            const double difference = residuals[d] - residuals[d - 1];
            dw += difference * difference;
            runs += (residuals[d] > 0) != (residuals[d - 1] > 0);
        }
        const double centered = double(input.cases[d]) - mean;
        sst += centered * centered;
        deaths[d] = fitted[d][4] - (d ? fitted[d - 1][4] : 0);
        rt[d] = r0 * lab.multiplier[d] * (d ? fitted[d - 1][0] : model.initial()[0]) /
                double(lab.population);
        infectious[d] = fitted[d][2];
        I week = 0;
        for (int i = std::max(0, d - 6); i <= d; ++i)
            week += input.cases[i];
        average[d] = double(week) / std::min(d + 1, 7);
        cumulative += input.cases[d];
        cumulative_observed[d] = cumulative;
        cumulative_reported += predicted[d];
        cumulative_fitted[d] = cumulative_reported;
    }
    line(fit, "fitted beta ", real(beta_hat, 6), " gamma ", real(gamma_hat, 6), " rho ",
         real(rho_hat, 6), " sigma ", real(p.sigma, 6), " r0 ", real(r0, 4));
    line(fit, "sse grid ", real(grid_sse, 1), " golden ", real(golden_sse, 1), " nelder_mead ",
         real(nm_sse, 1), " rmse ", real(rmse(nm_sse, days), 4), " r2 ", real(1 - nm_sse / sst, 4));
    auto stage = [&](const std::string &name, double beta, double gamma, double rho, double sse) {
        line(fit, "stage ", name, " beta ", real(beta, 6), " gamma ", real(gamma, 6), " rho ",
             real(rho, 6), " r0 ", real(beta / gamma, 4), " rmse ", real(rmse(sse, days), 4));
    };
    stage("grid", grid_beta, p.gamma, grid_rho, grid_sse);
    stage("golden", beta_golden, p.gamma, rho_hat, golden_sse);
    stage("nelder_mead", beta_hat, gamma_hat, rho_hat, nm_sse);
    line(fit, "residuals sum ", real(residual_sum, 1), " mae ", real(absolute / days, 1), " max ",
         real(residuals[max_residual], 1), " day ", max_residual + 1, " positive ", positive,
         " runs ", runs, " durbin_watson ", real(dw / u, 4));
    std::string autocorrelation = "autocorrelation";
    for (int lag = 1; lag <= 7; ++lag) {
        double sum = 0;
        for (int d = 0; d < days - lag; ++d)
            sum += residuals[d] * residuals[d + lag];
        autocorrelation += " " + real(sum / u, 4);
    }
    fit.push_back(autocorrelation);
    int outliers = 0;
    for (int d = 0; d < days; ++d) {
        const double z = residuals[d] / std::sqrt(predicted[d]);
        if (std::abs(z) > p.outlier) {
            ++outliers;
            line(fit, "outlier ", d + 1, " observed ", input.cases[d], " fitted ",
                 real(predicted[d], 1), " z ", real(z, 4));
        }
    }
    line(fit, "outliers ", outliers);
    std::array<I, 7> weekday_observed{};
    std::array<double, 7> weekday_fitted{}, weekday_factor{};
    for (int d = 0; d < days; ++d) {
        weekday_observed[d % 7] += input.cases[d];
        weekday_fitted[d % 7] += predicted[d];
    }
    for (int k = 0; k < 7; ++k) {
        weekday_factor[k] = double(weekday_observed[k]) / weekday_fitted[k];
        line(fit, "weekday ", k + 1, " observed ", weekday_observed[k], " fitted ",
             real(weekday_fitted[k], 1), " factor ", real(weekday_factor[k], 4));
    }
    double corrected = 0;
    for (int d = 0; d < days; ++d) {
        const double difference = predicted[d] * weekday_factor[d % 7] - double(input.cases[d]);
        corrected += difference * difference;
    }
    line(fit, "weekday_adjusted rmse ", real(rmse(corrected, days), 4));
    const double burden = total(infections);
    line(fit, "burden infections ", real(burden, 1), " ascertainment ",
         real(double(cases_total) / burden, 4), " deaths_per_infection ",
         real(double(deaths_total) / burden, 6));
    double death_cross = 0, death_square = 0;
    for (int d = 0; d < days; ++d) {
        death_cross += deaths[d] * double(input.deaths[d]);
        death_square += deaths[d] * deaths[d];
    }
    const double kappa = death_cross / death_square;
    line(fit, "deaths observed ", deaths_total, " model ", real(fitted.back()[4], 1), " rmse ",
         real(rmse(errors(deaths, 1, input.deaths), days), 4), " scale ", real(kappa, 4),
         " implied_fatality ", real(lab.fatality * kappa, 6), " cfr ",
         real(double(deaths_total) / double(cases_total), 4));
    Field death_correlations;
    for (int lag = 0; lag <= p.death_lag; ++lag) {
        I a = 0, b = 0, y = 0, cases = 0, deaths = 0;
        for (int d = 0; d < days - lag; ++d) {
            a += input.cases[d] * input.deaths[d + lag];
            b += input.cases[d] * input.cases[d];
            y += input.deaths[d + lag] * input.deaths[d + lag];
            cases += input.cases[d];
            deaths += input.deaths[d + lag];
        }
        const double correlation = double(a) / std::sqrt(double(b) * double(y));
        death_correlations.push_back(correlation);
        line(fit, "death_lag ", lag, " correlation ", real(correlation, 4), " cfr ",
             real(double(deaths) / double(cases), 4));
    }
    line(fit, "death_best_lag ", peak(death_correlations));
    I previous_week = 0;
    for (int first = 0, week = 1; first < days; first += 7, ++week) {
        const int last = std::min(days, first + 7);
        I cases = 0, deaths_observed = 0;
        double fitted_sum = 0, death_sum = 0;
        for (int d = first; d < last; ++d) {
            cases += input.cases[d];
            deaths_observed += input.deaths[d];
            fitted_sum += predicted[d];
            death_sum += deaths[d];
        }
        line(fit, "weekly ", week, " days ", first + 1, " ", last, " observed ", cases, " fitted ",
             real(fitted_sum, 1), " deaths_observed ", deaths_observed, " deaths_model ",
             real(death_sum, 1), " growth ",
             week == 1 ? "-" : real(double(cases) / double(previous_week), 4));
        previous_week = cases;
    }
    const std::array<std::string, 3> parameter_names{"beta", "gamma", "rho"};
    const std::array<double, 3> fitted_values{beta_hat, gamma_hat, rho_hat};
    std::array<double, 3> standard_errors{};
    for (int parameter = 0; parameter < 3; ++parameter) {
        std::array<double, 11> values{};
        for (int k = -5; k <= 5; ++k) {
            const double value = fitted_values[parameter] * (1 + double(k) / 100);
            auto point = fitted_values;
            point[parameter] = value;
            values[k + 5] = objective(point[0], point[1], point[2]);
            line(fit, "profile ", parameter_names[parameter], " ", k, " value ", real(value, 6),
                 " rmse ", real(rmse(values[k + 5], days), 4));
        }
        const double h = fitted_values[parameter] / 100,
                     curvature = (values[6] - 2 * values[5] + values[4]) / (h * h),
                     variance = nm_sse / (days - 3);
        standard_errors[parameter] = std::sqrt(2 * variance / curvature);
        line(fit, "profile_se ", parameter_names[parameter], " ",
             real(standard_errors[parameter], 6));
    }
    const int training_days = days - p.holdout;
    const Field training_multiplier(lab.multiplier.begin(), lab.multiplier.begin() + training_days);
    const Golden back_beta = golden(
        [&](double beta) {
            return errors(incidence(beta, gamma_hat, p.sigma, training_multiplier), rho_hat,
                          input.cases);
        },
        beta_hat - beta_spacing, beta_hat + beta_spacing, p.golden);
    const Field back_training = incidence(back_beta.point, gamma_hat, p.sigma, training_multiplier);
    const Golden back_rho =
        golden([&](double rho) { return errors(back_training, rho, input.cases); },
               rho_hat - rho_spacing, rho_hat + rho_spacing, p.golden);
    const Field back_incidence = incidence(back_beta.point, gamma_hat, p.sigma, lab.multiplier);
    const Field forecast =
                    reported(Field(back_incidence.begin() + training_days, back_incidence.end()),
                             back_rho.point),
                full_test(predicted.begin() + training_days, predicted.end());
    line(fit, "backtest train_days ", training_days, " beta ", real(back_beta.point, 6), " rho ",
         real(back_rho.point, 6), " train_rmse ", real(rmse(back_rho.value, training_days), 4),
         " test_rmse ", real(rmse(errors(forecast, 1, input.cases, training_days), p.holdout), 4),
         " full_fit_test_rmse ",
         real(rmse(errors(full_test, 1, input.cases, training_days), p.holdout), 4));
    for (int i = 0; i < p.holdout; ++i)
        line(fit, "backtest_day ", training_days + i + 1, " observed ",
             input.cases[training_days + i], " forecast ", real(forecast[i], 1), " error ",
             real(double(input.cases[training_days + i]) - forecast[i], 1));
    std::vector<Intervention> estimated = input.interventions;
    double effect_sse = nm_sse;
    for (int k = 1; k < int(estimated.size()); ++k) {
        const Golden effect = golden(
            [&](double value) {
                auto trial = estimated;
                trial[k].multiplier = value;
                return errors(incidence(beta_hat, gamma_hat, p.sigma, multipliers(trial, days)),
                              rho_hat, input.cases);
            },
            input.interventions[k].multiplier - p.effect_width,
            input.interventions[k].multiplier + p.effect_width, p.golden);
        estimated[k].multiplier = effect.point;
        effect_sse = effect.value;
        line(fit, "effect ", k + 1, " day ", input.interventions[k].day, " given ",
             real(input.interventions[k].multiplier, 4), " estimated ", real(effect.point, 6),
             " sse ", real(effect.value, 1));
    }
    line(fit, "effect_sse before ", real(nm_sse, 1), " after ", real(effect_sse, 1), " rmse ",
         real(rmse(effect_sse, days), 4));
    const std::array<std::string, 4> sensitivity_names{"beta", "gamma", "sigma", "rho"};
    for (int parameter = 0; parameter < 4; ++parameter)
        for (double factor : {0.9, 1.1}) {
            std::array<double, 4> values{beta_hat, gamma_hat, p.sigma, rho_hat};
            values[parameter] = values[parameter] * factor;
            const Model changed = seird(values[0], values[1], values[2]);
            const States states = trajectory(changed, lab.multiplier);
            const Field values_incidence = series(changed, states);
            const int day = peak(values_incidence);
            line(fit, "sensitivity ", sensitivity_names[parameter], " ", real(factor, 2), " r0 ",
                 real(values[0] / values[1], 4), " rmse ",
                 real(rmse(errors(values_incidence, values[3], input.cases), days), 4),
                 " peak_day ", day + 1, " peak ", real(values[3] * values_incidence[day], 1),
                 " attack ",
                 real((double(lab.population) - states.back()[0]) / double(lab.population), 4));
        }
    const Model sir = lab.model(Kind::sir, beta_hat, gamma_hat, p.sigma),
                age = lab.model(Kind::age, beta_hat, gamma_hat, p.sigma);
    const States age_states = trajectory(age, lab.multiplier);
    const Field sir_incidence = series(sir, trajectory(sir, lab.multiplier)),
                age_incidence = series(age, age_states);
    auto compare_model = [&](const std::string &name, const Field &values) {
        double cross = 0, square = 0;
        for (int d = 0; d < days; ++d) {
            cross += double(input.cases[d]) * values[d];
            square += values[d] * values[d];
        }
        const double rho = cross / square;
        line(fit, "model ", name, " rmse ",
             real(rmse(errors(values, rho_hat, input.cases), days), 4), " peak_day ",
             peak(values) + 1, " rho_opt ", real(rho, 6), " rmse_opt ",
             real(rmse(errors(values, rho, input.cases), days), 4));
    };
    compare_model("sir", sir_incidence);
    compare_model("seir", infections);
    compare_model("age", age_incidence);
    const Golden sir_search = golden(
        [&](double beta) {
            const Model candidate = lab.model(Kind::sir, beta, gamma_hat, p.sigma);
            return errors(series(candidate, trajectory(candidate, lab.multiplier)), rho_hat,
                          input.cases);
        },
        p.beta_min, p.beta_max, p.golden);
    const Model fitted_sir = lab.model(Kind::sir, sir_search.point, gamma_hat, p.sigma);
    const Field fitted_sir_incidence = series(fitted_sir, trajectory(fitted_sir, lab.multiplier));
    line(fit, "model sir_fit beta ", real(sir_search.point, 6), " rmse ",
         real(rmse(sir_search.value, days), 4), " peak_day ", peak(fitted_sir_incidence) + 1);
    Lines trajectories{
        "day,S,E,I,R,D,incidence,reported,observed,average7,cumulative_observed,cumulative_reported"};
    for (int d = 0; d < days; ++d)
        line(trajectories, d + 1, ",", real(fitted[d][0], 1), ",", real(fitted[d][1], 1), ",",
             real(fitted[d][2], 1), ",", real(fitted[d][3], 1), ",", real(fitted[d][4], 1), ",",
             real(infections[d], 1), ",", real(predicted[d], 1), ",", input.cases[d], ",",
             real(average[d], 2), ",", cumulative_observed[d], ",", real(cumulative_fitted[d], 1));
    Lines reproduction;
    line(reproduction, "r0 ", real(r0, 4), " herd_immunity ", real(1 - 1 / r0, 4));
    const States long_states = trajectory(model, Field(730, 1));
    line(reproduction, "final_size equation ", real(final_size(r0), 4), " simulated ",
         real((double(lab.population) - long_states.back()[0]) / double(lab.population), 4));
    const Model generation = lab.model(Kind::generation, 0, gamma_hat, p.sigma);
    const Field generation_incidence =
        series(generation, trajectory(generation, Field(p.generation, 1)));
    const double coverage = total(generation_incidence);
    Field generation_weights;
    double generation_mean = 0;
    for (int s = 0; s < p.generation; ++s) {
        generation_weights.push_back(generation_incidence[s] / coverage);
        generation_mean += (s + 1 - 0.5) * generation_weights.back();
    }
    line(reproduction, "generation mean ", real(generation_mean, 4), " theory ",
         real(1 / p.sigma + 1 / gamma_hat, 4), " coverage ", real(coverage, 4));
    for (int s = 0; s < p.generation; ++s)
        line(reproduction, "generation_weight ", s + 1, " ", real(generation_weights[s], 6));
    const int model_peak = peak(infections), infectious_peak = peak(infectious),
              observed_peak = int(std::max_element(input.cases.begin(), input.cases.end()) -
                                  input.cases.begin()),
              average_peak = peak(average);
    line(reproduction, "peak model day ", model_peak + 1, " incidence ",
         real(infections[model_peak], 1), " reported ", real(predicted[model_peak], 1),
         " infectious_day ", infectious_peak + 1, " infectious ",
         real(infectious[infectious_peak], 1));
    line(reproduction, "peak observed day ", observed_peak + 1, " cases ",
         input.cases[observed_peak], " average7_day ", average_peak + 1, " average7 ",
         real(average[average_peak], 2));
    for (int k = 0; k < int(input.interventions.size()); ++k) {
        const int first = input.interventions[k].day - 1,
                  last = k + 1 < int(input.interventions.size())
                             ? input.interventions[k + 1].day - 1
                             : days;
        I observed = 0;
        double predicted_sum = 0, square = 0, bias = 0;
        for (int d = first; d < last; ++d) {
            observed += input.cases[d];
            predicted_sum += predicted[d];
            square += residuals[d] * residuals[d];
            bias += residuals[d];
        }
        line(reproduction, "period ", k + 1, " days ", first + 1, " ", last, " multiplier ",
             real(input.interventions[k].multiplier, 4), " rt_start ", real(rt[first], 4),
             " rt_end ", real(rt[last - 1], 4), " observed ", observed, " fitted ",
             real(predicted_sum, 1), " rmse ", real(rmse(square, last - first), 4), " bias ",
             real(bias / (last - first), 1));
    }
    for (I target : p.milestones) {
        int observed = -1, predicted_day = -1;
        for (int d = 0; d < days; ++d) {
            if (observed < 0 && cumulative_observed[d] >= target)
                observed = d + 1;
            if (predicted_day < 0 && cumulative_fitted[d] >= double(target))
                predicted_day = d + 1;
        }
        line(reproduction, "milestone ", target, " observed ",
             observed < 0 ? "never" : std::to_string(observed), " fitted ",
             predicted_day < 0 ? "never" : std::to_string(predicted_day));
    }
    const double predicted_total = total(predicted);
    const Field none = reported(
        incidence(beta_hat, gamma_hat, p.sigma, Field(days, input.interventions[0].multiplier)),
        rho_hat);
    const int none_peak = peak(none);
    line(reproduction, "counterfactual none reported ", real(total(none), 1), " peak_day ",
         none_peak + 1, " peak ", real(none[none_peak], 1), " averted ",
         real(total(none) - predicted_total, 1));
    for (int k = 1; k < int(input.interventions.size()); ++k) {
        auto without = input.interventions;
        without.erase(without.begin() + k);
        const double sum = total(
            reported(incidence(beta_hat, gamma_hat, p.sigma, multipliers(without, days)), rho_hat));
        line(reproduction, "counterfactual without ", k + 1, " reported ", real(sum, 1),
             " averted ", real(sum - predicted_total, 1));
    }
    for (int k = 1; k < int(input.interventions.size()); ++k)
        for (int shift : {-7, 7}) {
            auto moved = input.interventions;
            moved[k].day += shift;
            const double sum = total(reported(
                incidence(beta_hat, gamma_hat, p.sigma, multipliers(moved, days)), rho_hat));
            line(reproduction, "timing ", k + 1, " shift ", shift, " reported ", real(sum, 1),
                 " change ", real(sum - predicted_total, 1));
        }
    for (int d = 1; d < days; ++d)
        if ((rt[d] < 1) != (rt[d - 1] < 1))
            line(reproduction, "rt_cross day ", d + 1, " ", rt[d] < 1 ? "down" : "up");
    Field pressure(days);
    for (int d = 0; d < days; ++d)
        for (int s = 1; s <= std::min(p.generation, d); ++s)
            pressure[d] += generation_weights[s - 1] * double(input.cases[d - s]);
    for (int d = 0; d < days; ++d) {
        std::string empirical = "-";
        if (d + 1 >= p.generation + 7) {
            I numerator = 0;
            double denominator = 0;
            for (int j = d - 6; j <= d; ++j) {
                numerator += input.cases[j];
                denominator += pressure[j];
            }
            empirical = real(double(numerator) / denominator, 4);
        }
        line(reproduction, "rt ", d + 1, " model ", real(rt[d], 4), " empirical ", empirical);
    }
    const Matrix ngm = next_generation(lab, lab.contacts, r0);
    const Eigen eigen = largest(ngm);
    for (int g = 0; g < groups; ++g) {
        std::string row = "ngm " + input.groups[g].name;
        for (double value : ngm[g])
            row += " " + real(value, 4);
        reproduction.push_back(row);
    }
    std::string eigen_line = "r0_age " + real(eigen.value, 4) + " ratio " +
                             real(eigen.value / r0, 4) + " kbar " + real(lab.kbar, 4) +
                             " eigenvector";
    for (double value : eigen.vector)
        eigen_line += " " + real(value, 4);
    reproduction.push_back(eigen_line);
    Field z(groups, 1);
    for (int iteration = 0; iteration < 100; ++iteration) {
        Field next(groups);
        for (int g = 0; g < groups; ++g) {
            double sum = 0;
            for (int h = 0; h < groups; ++h)
                sum += r0 * lab.contacts[g][h] * z[h];
            next[g] = 1 - std::exp(-sum);
        }
        z = std::move(next);
    }
    const States long_age = trajectory(age, Field(730, 1));
    double final_equation = 0, final_simulated = 0;
    for (int g = 0; g < groups; ++g) {
        const double population = double(input.groups[g].population),
                     simulated = (population - long_age.back()[6 * g]) / population;
        final_equation += population * z[g];
        final_simulated += population * simulated;
        line(reproduction, "final_size_age ", input.groups[g].name, " equation ", real(z[g], 4),
             " simulated ", real(simulated, 4));
    }
    line(reproduction, "final_size_age total equation ",
         real(final_equation / double(lab.population), 4), " simulated ",
         real(final_simulated / double(lab.population), 4));
    const Field age_initial = age.initial();
    for (int d = 0; d < days; d += 7) {
        Matrix matrix(groups, Field(groups));
        for (int g = 0; g < groups; ++g)
            for (int h = 0; h < groups; ++h)
                matrix[g][h] = lab.multiplier[d] * r0 * lab.contacts[g][h] *
                               (d ? age_states[d - 1][6 * g] : age_initial[6 * g]) /
                               double(input.groups[h].population);
        line(reproduction, "age_rt ", d + 1, " ", real(largest(matrix).value, 4), " homogeneous ",
             real(rt[d], 4));
    }
    for (int first = 0, week = 1; first < days; first += 7, ++week) {
        const int last = std::min(days, first + 7);
        std::string row = "age_weekly " + std::to_string(week) + " days " +
                          std::to_string(first + 1) + " " + std::to_string(last);
        for (int g = 0; g < groups; ++g) {
            double sum = 0;
            for (int d = first; d < last; ++d)
                sum += age_states[d][6 * g + 5];
            row += " " + real(sum, 1);
        }
        reproduction.push_back(row);
    }
    Field age_infections(groups);
    for (int g = 0; g < groups; ++g)
        for (int d = 0; d < days; ++d)
            age_infections[g] += age_states[d][6 * g + 5];
    const double age_total = total(age_infections);
    for (int g = 0; g < groups; ++g) {
        Field values;
        for (const Field &state : age_states)
            values.push_back(state[6 * g + 5]);
        const int day = peak(values);
        const double population = double(input.groups[g].population);
        line(reproduction, "age ", input.groups[g].name, " attack ",
             real((population - age_states.back()[6 * g]) / population, 4), " infections ",
             real(age_infections[g], 1), " share ", real(age_infections[g] / age_total, 4),
             " deaths ", real(age_states.back()[6 * g + 4], 1), " peak_day ", day + 1, " peak ",
             real(values[day], 1));
    }
    for (const ContactChange &change : p.changes) {
        int target = 0;
        while (input.groups[target].name != change.group)
            ++target;
        Matrix changed_contacts = lab.contacts;
        for (int g = 0; g < groups; ++g)
            for (int h = 0; h < groups; ++h)
                changed_contacts[g][h] = changed_contacts[g][h] *
                                         (g == target ? change.factor : 1) *
                                         (h == target ? change.factor : 1);
        Model changed = age;
        changed.contacts = changed_contacts;
        const States states = trajectory(changed, lab.multiplier);
        const double infections = total(series(changed, states));
        double susceptible_loss = 0;
        for (int g = 0; g < groups; ++g)
            susceptible_loss += double(input.groups[g].population) - states.back()[6 * g];
        line(reproduction, "contact_change ", change.name, " group ", change.group, " factor ",
             real(change.factor, 4), " r0_age ",
             real(largest(next_generation(lab, changed_contacts, r0)).value, 4), " infections ",
             real(infections, 1), " deaths ", real(age_deaths(states.back(), groups), 1),
             " attack ", real(susceptible_loss / double(lab.population), 4));
    }
    Lines scenarios{"scenario,day,incidence,reported"};
    double first_scenario = 0;
    for (int index = 0; index < int(p.scenarios.size()); ++index) {
        const Scenario &scenario = p.scenarios[index];
        const Field future_multiplier(p.horizon, scenario.multiplier);
        const States future = simulate(model, fitted.back(), future_multiplier);
        const Field future_incidence = series(model, future),
                    future_reported = reported(future_incidence, rho_hat);
        const double sum = total(future_reported);
        if (index == 0)
            first_scenario = sum;
        const int day = peak(future_reported);
        int below = -1, above = 0;
        for (int j = 0; j < p.horizon; ++j) {
            if (below < 0 && future_reported[j] < p.threshold)
                below = days + j + 1;
            above += future_reported[j] >= p.threshold;
            line(scenarios, scenario.name, ",", days + j + 1, ",", real(future_incidence[j], 1),
                 ",", real(future_reported[j], 1));
        }
        line(reproduction, "scenario ", scenario.name, " multiplier ", real(scenario.multiplier, 4),
             " rt ", real(r0 * scenario.multiplier * fitted.back()[0] / double(lab.population), 4),
             " reported ", real(sum, 1), " peak_day ", days + day + 1, " peak ",
             real(future_reported[day], 1), " attack ",
             real((double(lab.population) - future.back()[0]) / double(lab.population), 4),
             " final_size ", real(final_size(r0 * scenario.multiplier), 4), " averted ",
             real(first_scenario - sum, 1), " below ", below < 0 ? "never" : std::to_string(below),
             " days_above ", above);
        const double beta_low = beta_hat - 2 * standard_errors[0],
                     beta_high = beta_hat + 2 * standard_errors[0];
        Field combined = lab.multiplier;
        combined.insert(combined.end(), future_multiplier.begin(), future_multiplier.end());
        std::array<double, 2> band{};
        for (int k = 0; k < 2; ++k) {
            const Field values =
                incidence(k == 0 ? beta_low : beta_high, gamma_hat, p.sigma, combined);
            for (int d = days; d < days + p.horizon; ++d)
                band[k] += rho_hat * values[d];
        }
        line(reproduction, "scenario_band ", scenario.name, " beta_low ", real(beta_low, 6),
             " reported_low ", real(band[0], 1), " beta_high ", real(beta_high, 6),
             " reported_high ", real(band[1], 1));
        const States age_future = simulate(age, age_states.back(), future_multiplier);
        std::string row = "scenario_age " + scenario.name + " attack";
        for (int g = 0; g < groups; ++g)
            row += " " + real((double(input.groups[g].population) - age_future.back()[6 * g]) /
                                  double(input.groups[g].population),
                              4);
        row += " deaths " + real(age_deaths(age_future.back(), groups), 1);
        reproduction.push_back(row);
    }
    save("fit.txt", fit);
    save("trajectories.csv", trajectories);
    save("scenarios.csv", scenarios);
    save("reproduction.txt", reproduction);
    save("curve_plot.txt", curve_plot(input.cases, predicted));
}
