#include "epidemic.h"
static void multiplier_sequence(const Intervention *interventions, int intervention_count,
                                int count, double *out) {
    int index = 0;
    for (int day = 1; day <= count; ++day) {
        while (index + 1 < intervention_count && interventions[index + 1].day <= day)
            ++index;
        out[day - 1] = interventions[index].multiplier;
    }
}
typedef struct {
    const Input *input;
    I population;
    double fatality, kbar, contacts[6][6], multipliers[200];
} Laboratory;
static Laboratory *laboratory(const Input *input) {
    Laboratory *out = allocate(1, sizeof(Laboratory));
    out->input = input;
    for (int g = 0; g < input->group_count; ++g) {
        out->population += input->groups[g].population;
        out->fatality += (double)input->groups[g].population * input->groups[g].fatality;
    }
    out->fatality /= (double)out->population;
    for (int g = 0; g < input->group_count; ++g) {
        double row = 0;
        for (int h = 0; h < input->group_count; ++h)
            row += input->contacts[g][h];
        out->kbar += (double)input->groups[g].population * row;
    }
    out->kbar /= (double)out->population;
    for (int g = 0; g < input->group_count; ++g)
        for (int h = 0; h < input->group_count; ++h)
            out->contacts[g][h] = input->contacts[g][h] / out->kbar;
    multiplier_sequence(input->interventions, input->intervention_count, input->days,
                        out->multipliers);
    return out;
}
static Model make_model(const Laboratory *lab, int kind, double beta, double gamma, double sigma) {
    Model out = {0};
    out.kind = kind;
    out.beta = beta;
    out.gamma = gamma;
    out.sigma = sigma;
    out.population = (double)lab->population;
    out.fatality = lab->fatality;
    out.e0 = lab->input->params.e0;
    out.i0 = lab->input->params.i0;
    out.groups = lab->input->groups;
    out.group_count = lab->input->group_count;
    out.contacts = lab->contacts;
    return out;
}
static double *series(const Model *model, Trajectory trajectory) {
    double *out = allocate((size_t)trajectory.count, sizeof(double));
    for (int d = 0; d < trajectory.count; ++d) {
        if (model->kind == K_AGE)
            for (int g = 0; g < model->group_count; ++g)
                out[d] += trajectory.states[d].values[6 * g + 5];
        else
            out[d] = trajectory.states[d].values[model->kind == K_GENERATION ? 2
                                                 : model->kind == K_SIR      ? 3
                                                                             : 5];
    }
    return out;
}
static Trajectory trajectory(const Model *model, const double *multipliers, int count) {
    return simulate(model, initial_state(model), multipliers, count);
}
static double *incidence(const Laboratory *lab, double beta, double gamma, double sigma,
                         const double *multipliers, int count) {
    Model model = make_model(lab, K_SEIRD, beta, gamma, sigma);
    return series(&model, trajectory(&model, multipliers, count));
}
static double errors(const double *values, int count, double coefficient, const I *observations) {
    double out = 0;
    for (int i = 0; i < count; ++i) {
        double difference = coefficient * values[i] - (double)observations[i];
        out += difference * difference;
    }
    return out;
}
static double rmse(double value, int count) { return sqrt(value / count); }
static double total(const double *values, int count) {
    double out = 0;
    for (int i = 0; i < count; ++i)
        out += values[i];
    return out;
}
static int peak(const double *values, int count) {
    int out = 0;
    for (int i = 1; i < count; ++i)
        if (values[i] > values[out])
            out = i;
    return out;
}
static double *reported(const double *values, int count, double rho) {
    double *out = allocate((size_t)count, sizeof(double));
    for (int i = 0; i < count; ++i)
        out[i] = rho * values[i];
    return out;
}
static double objective(const Laboratory *lab, double beta, double gamma, double rho) {
    return errors(
        incidence(lab, beta, gamma, lab->input->params.sigma, lab->multipliers, lab->input->days),
        lab->input->days, rho, lab->input->cases);
}
typedef struct {
    const Laboratory *lab;
    double beta, gamma, rho, sigma;
    const double *multipliers, *cached;
    int count, parameter, kind, effect_index;
    bool effect;
    Intervention interventions[10];
} SearchContext;
static double search_value(double value, void *context) {
    SearchContext *search = context;
    if (search->effect) {
        Intervention lines[10];
        memcpy(lines, search->interventions, sizeof(lines));
        lines[search->effect_index].multiplier = value;
        double multipliers[200];
        multiplier_sequence(lines, search->lab->input->intervention_count, search->count,
                            multipliers);
        return errors(incidence(search->lab, search->beta, search->gamma, search->sigma,
                                multipliers, search->count),
                      search->count, search->rho, search->lab->input->cases);
    }
    double beta = search->beta, gamma = search->gamma, rho = search->rho;
    if (search->parameter == 0)
        beta = value;
    else if (search->parameter == 1)
        gamma = value;
    else
        rho = value;
    if (search->cached)
        return errors(search->cached, search->count, rho, search->lab->input->cases);
    Model model = make_model(search->lab, search->kind, beta, gamma, search->sigma);
    return errors(series(&model, trajectory(&model, search->multipliers, search->count)),
                  search->count, rho, search->lab->input->cases);
}
static double simplex_value(Point point, void *context) {
    SearchContext *search = context;
    return objective(search->lab, point.value[0], point.value[1], search->rho);
}
static void golden_report(Lines *lines, Golden search, int round, const char *name, int days) {
    for (int i = 0; i < search.count; ++i) {
        GoldenRecord record = search.records[i];
        line(lines, "golden %d %s %d a %s b %s c %s d %s rmse %s %s", round, name, i,
             real(record.a, 6), real(record.b, 6), real(record.c, 6), real(record.d, 6),
             real(rmse(record.fc, days), 4), real(rmse(record.fd, days), 4));
    }
    line(lines, "golden_result %d %s %s sse %s", round, name, real(search.point, 6),
         real(search.value, 1));
}
static double final_size(double r) {
    if (r <= 1)
        return 0;
    double lo = 1 - 1 / r, hi = 1;
    for (int iteration = 0; iteration < 20; ++iteration) {
        double mid = (lo + hi) / 2, g = 1 - mid - exp(-r * mid);
        if (g > 0)
            lo = mid;
        else
            hi = mid;
    }
    return (lo + hi) / 2;
}
typedef struct {
    double value, vector[6];
} Eigen;
static Eigen largest(const double matrix[6][6], int count) {
    Eigen out = {0};
    for (int g = 0; g < count; ++g)
        out.vector[g] = 1.0 / count;
    for (int iteration = 0; iteration < 200; ++iteration) {
        double next[6] = {0};
        for (int g = 0; g < count; ++g)
            for (int h = 0; h < count; ++h)
                next[g] += matrix[g][h] * out.vector[h];
        out.value = total(next, count);
        for (int g = 0; g < count; ++g)
            out.vector[g] = next[g] / out.value;
    }
    return out;
}
static void next_generation(const Laboratory *lab, const double contacts[6][6], double r0,
                            double out[6][6]) {
    for (int g = 0; g < lab->input->group_count; ++g)
        for (int h = 0; h < lab->input->group_count; ++h)
            out[g][h] = r0 * contacts[g][h] * (double)lab->input->groups[g].population /
                        (double)lab->input->groups[h].population;
}
static double age_deaths(State state, int groups) {
    double out = 0;
    for (int g = 0; g < groups; ++g)
        out += state.values[6 * g + 4];
    return out;
}
static void stage(Lines *fit, const char *name, double beta, double gamma, double rho, double sse,
                  int days) {
    line(fit, "stage %s beta %s gamma %s rho %s r0 %s rmse %s", name, real(beta, 6), real(gamma, 6),
         real(rho, 6), real(beta / gamma, 4), real(rmse(sse, days), 4));
}
static void compare_model(Lines *fit, const char *name, const double *values, const Input *input,
                          double rho) {
    double cross = 0, square = 0;
    for (int d = 0; d < input->days; ++d) {
        cross += (double)input->cases[d] * values[d];
        square += values[d] * values[d];
    }
    double optimal = cross / square;
    line(fit, "model %s rmse %s peak_day %d rho_opt %s rmse_opt %s", name,
         real(rmse(errors(values, input->days, rho, input->cases), input->days), 4),
         peak(values, input->days) + 1, real(optimal, 6),
         real(rmse(errors(values, input->days, optimal, input->cases), input->days), 4));
}
int main(void) {
    const Input *input = load();
    const Params *p = &input->params;
    const Laboratory *lab = laboratory(input);
    int days = input->days, groups = input->group_count;
    I cases_total = 0, deaths_total = 0;
    for (int d = 0; d < days; ++d) {
        cases_total += input->cases[d];
        deaths_total += input->deaths[d];
    }
    Lines fit = {0};
    line(&fit, "data days %d cases %lld deaths %lld population %lld fatality %s", days, cases_total,
         deaths_total, lab->population, real(lab->fatality, 6));
    double beta_grid[15], rho_grid[15];
    for (int i = 0; i < p->beta_count; ++i)
        beta_grid[i] = p->beta_min + (p->beta_max - p->beta_min) * i / (p->beta_count - 1);
    for (int j = 0; j < p->rho_count; ++j)
        rho_grid[j] = p->rho_min + (p->rho_max - p->rho_min) * j / (p->rho_count - 1);
    double beta_spacing = (p->beta_max - p->beta_min) / (p->beta_count - 1),
           rho_spacing = (p->rho_max - p->rho_min) / (p->rho_count - 1);
    char *heading = format("grid gamma %s rho", real(p->gamma, 4));
    for (int j = 0; j < p->rho_count; ++j)
        heading = joined(heading, format(" %s", real(rho_grid[j], 4)));
    line(&fit, "%s", heading);
    double grid_beta = 0, grid_rho = 0, grid_sse = DBL_MAX;
    for (int i = 0; i < p->beta_count; ++i) {
        double beta = beta_grid[i],
               *values = incidence(lab, beta, p->gamma, p->sigma, lab->multipliers, days);
        char *row = format("grid beta %s rmse", real(beta, 4));
        for (int j = 0; j < p->rho_count; ++j) {
            double rho = rho_grid[j], value = errors(values, days, rho, input->cases);
            row = joined(row, format(" %s", real(rmse(value, days), 2)));
            if (value < grid_sse) {
                grid_sse = value;
                grid_beta = beta;
                grid_rho = rho;
            }
        }
        line(&fit, "%s", row);
    }
    line(&fit, "grid_best beta %s rho %s sse %s rmse %s", real(grid_beta, 4), real(grid_rho, 4),
         real(grid_sse, 1), real(rmse(grid_sse, days), 4));
    double beta_golden = grid_beta, rho_hat = grid_rho, golden_sse = grid_sse;
    SearchContext search = {.lab = lab,
                            .gamma = p->gamma,
                            .sigma = p->sigma,
                            .multipliers = lab->multipliers,
                            .count = days,
                            .kind = K_SEIRD};
    for (int round = 1; round <= p->rounds; ++round) {
        search.rho = rho_hat;
        search.parameter = 0;
        search.cached = NULL;
        Golden beta = golden(search_value, &search, beta_golden - beta_spacing,
                             beta_golden + beta_spacing, p->golden);
        golden_report(&fit, beta, round, "beta", days);
        beta_golden = beta.point;
        search.beta = beta_golden;
        search.parameter = 2;
        search.cached = incidence(lab, beta_golden, p->gamma, p->sigma, lab->multipliers, days);
        Golden rho =
            golden(search_value, &search, rho_hat - rho_spacing, rho_hat + rho_spacing, p->golden);
        golden_report(&fit, rho, round, "rho", days);
        rho_hat = rho.point;
        golden_sse = rho.value;
    }
    search.rho = rho_hat;
    Point start = {{beta_golden, p->gamma}};
    Simplex simplex = nelder_mead(simplex_value, &search, start, p);
    for (int i = 0; i < 3; ++i) {
        Vertex v = simplex.initial[i];
        line(&fit, "simplex %d beta %s gamma %s rmse %s", v.number, real(v.point.value[0], 6),
             real(v.point.value[1], 6), real(rmse(v.value, days), 4));
    }
    for (int i = 0; i < simplex.count; ++i) {
        SimplexRecord record = simplex.records[i];
        line(&fit, "nelder_mead %d %s beta %s gamma %s rmse %s", i + 1, record.operation,
             real(record.best.point.value[0], 6), real(record.best.point.value[1], 6),
             real(rmse(record.best.value, days), 4));
    }
    for (int i = 0; i < 3; ++i) {
        Vertex v = simplex.final[i];
        line(&fit, "final_simplex %d beta %s gamma %s rmse %s", i + 1, real(v.point.value[0], 6),
             real(v.point.value[1], 6), real(rmse(v.value, days), 4));
    }
    double beta_hat = simplex.final[0].point.value[0], gamma_hat = simplex.final[0].point.value[1],
           nm_sse = simplex.final[0].value, r0 = beta_hat / gamma_hat;
    Model model = make_model(lab, K_SEIRD, beta_hat, gamma_hat, p->sigma);
    Trajectory fitted = trajectory(&model, lab->multipliers, days);
    double *infections = series(&model, fitted), *predicted = reported(infections, days, rho_hat),
           residuals[200], deaths[200], average[200], rt[200], infectious[200],
           cumulative_fitted[200];
    I cumulative_observed[200], cumulative = 0;
    double cumulative_reported = 0, sst = 0, residual_sum = 0, absolute = 0, u = 0, dw = 0,
           mean = (double)cases_total / days;
    int max_residual = 0, positive = 0, runs = 1;
    for (int d = 0; d < days; ++d) {
        residuals[d] = (double)input->cases[d] - predicted[d];
        residual_sum += residuals[d];
        absolute += fabs(residuals[d]);
        u += residuals[d] * residuals[d];
        if (fabs(residuals[d]) > fabs(residuals[max_residual]))
            max_residual = d;
        positive += residuals[d] > 0;
        if (d > 0) {
            double difference = residuals[d] - residuals[d - 1];
            dw += difference * difference;
            runs += (residuals[d] > 0) != (residuals[d - 1] > 0);
        }
        double centered = (double)input->cases[d] - mean;
        sst += centered * centered;
        deaths[d] = fitted.states[d].values[4] - (d ? fitted.states[d - 1].values[4] : 0);
        rt[d] = r0 * lab->multipliers[d] *
                (d ? fitted.states[d - 1].values[0] : initial_state(&model).values[0]) /
                (double)lab->population;
        infectious[d] = fitted.states[d].values[2];
        I week = 0;
        int first = d - 6 > 0 ? d - 6 : 0;
        for (int i = first; i <= d; ++i)
            week += input->cases[i];
        average[d] = (double)week / (d + 1 < 7 ? d + 1 : 7);
        cumulative += input->cases[d];
        cumulative_observed[d] = cumulative;
        cumulative_reported += predicted[d];
        cumulative_fitted[d] = cumulative_reported;
    }
    line(&fit, "fitted beta %s gamma %s rho %s sigma %s r0 %s", real(beta_hat, 6),
         real(gamma_hat, 6), real(rho_hat, 6), real(p->sigma, 6), real(r0, 4));
    line(&fit, "sse grid %s golden %s nelder_mead %s rmse %s r2 %s", real(grid_sse, 1),
         real(golden_sse, 1), real(nm_sse, 1), real(rmse(nm_sse, days), 4),
         real(1 - nm_sse / sst, 4));
    stage(&fit, "grid", grid_beta, p->gamma, grid_rho, grid_sse, days);
    stage(&fit, "golden", beta_golden, p->gamma, rho_hat, golden_sse, days);
    stage(&fit, "nelder_mead", beta_hat, gamma_hat, rho_hat, nm_sse, days);
    line(&fit, "residuals sum %s mae %s max %s day %d positive %d runs %d durbin_watson %s",
         real(residual_sum, 1), real(absolute / days, 1), real(residuals[max_residual], 1),
         max_residual + 1, positive, runs, real(dw / u, 4));
    char *autocorrelation = "autocorrelation";
    for (int lag = 1; lag <= 7; ++lag) {
        double sum = 0;
        for (int d = 0; d < days - lag; ++d)
            sum += residuals[d] * residuals[d + lag];
        autocorrelation = joined(autocorrelation, format(" %s", real(sum / u, 4)));
    }
    line(&fit, "%s", autocorrelation);
    int outliers = 0;
    for (int d = 0; d < days; ++d) {
        double z = residuals[d] / sqrt(predicted[d]);
        if (fabs(z) > p->outlier) {
            ++outliers;
            line(&fit, "outlier %d observed %lld fitted %s z %s", d + 1, input->cases[d],
                 real(predicted[d], 1), real(z, 4));
        }
    }
    line(&fit, "outliers %d", outliers);
    I weekday_observed[7] = {0};
    double weekday_fitted[7] = {0}, weekday_factor[7];
    for (int d = 0; d < days; ++d) {
        weekday_observed[d % 7] += input->cases[d];
        weekday_fitted[d % 7] += predicted[d];
    }
    for (int k = 0; k < 7; ++k) {
        weekday_factor[k] = (double)weekday_observed[k] / weekday_fitted[k];
        line(&fit, "weekday %d observed %lld fitted %s factor %s", k + 1, weekday_observed[k],
             real(weekday_fitted[k], 1), real(weekday_factor[k], 4));
    }
    double corrected = 0;
    for (int d = 0; d < days; ++d) {
        double difference = predicted[d] * weekday_factor[d % 7] - (double)input->cases[d];
        corrected += difference * difference;
    }
    line(&fit, "weekday_adjusted rmse %s", real(rmse(corrected, days), 4));
    double burden = total(infections, days);
    line(&fit, "burden infections %s ascertainment %s deaths_per_infection %s", real(burden, 1),
         real((double)cases_total / burden, 4), real((double)deaths_total / burden, 6));
    double death_cross = 0, death_square = 0;
    for (int d = 0; d < days; ++d) {
        death_cross += deaths[d] * (double)input->deaths[d];
        death_square += deaths[d] * deaths[d];
    }
    double kappa = death_cross / death_square;
    line(&fit, "deaths observed %lld model %s rmse %s scale %s implied_fatality %s cfr %s",
         deaths_total, real(fitted.states[days - 1].values[4], 1),
         real(rmse(errors(deaths, days, 1, input->deaths), days), 4), real(kappa, 4),
         real(lab->fatality * kappa, 6), real((double)deaths_total / (double)cases_total, 4));
    double death_correlations[200];
    for (int lag = 0; lag <= p->death_lag; ++lag) {
        I a = 0, b = 0, y = 0, cases = 0, death_count = 0;
        for (int d = 0; d < days - lag; ++d) {
            a += input->cases[d] * input->deaths[d + lag];
            b += input->cases[d] * input->cases[d];
            y += input->deaths[d + lag] * input->deaths[d + lag];
            cases += input->cases[d];
            death_count += input->deaths[d + lag];
        }
        double correlation = (double)a / sqrt((double)b * (double)y);
        death_correlations[lag] = correlation;
        line(&fit, "death_lag %d correlation %s cfr %s", lag, real(correlation, 4),
             real((double)death_count / (double)cases, 4));
    }
    line(&fit, "death_best_lag %d", peak(death_correlations, p->death_lag + 1));
    I previous_week = 0;
    for (int first = 0, week = 1; first < days; first += 7, ++week) {
        int last = first + 7 < days ? first + 7 : days;
        I cases = 0, deaths_observed = 0;
        double fitted_sum = 0, death_sum = 0;
        for (int d = first; d < last; ++d) {
            cases += input->cases[d];
            deaths_observed += input->deaths[d];
            fitted_sum += predicted[d];
            death_sum += deaths[d];
        }
        line(
            &fit,
            "weekly %d days %d %d observed %lld fitted %s deaths_observed %lld deaths_model %s growth %s",
            week, first + 1, last, cases, real(fitted_sum, 1), deaths_observed, real(death_sum, 1),
            week == 1 ? "-" : real((double)cases / (double)previous_week, 4));
        previous_week = cases;
    }
    const char *parameter_names[3] = {"beta", "gamma", "rho"};
    double fitted_values[3] = {beta_hat, gamma_hat, rho_hat}, standard_errors[3];
    for (int parameter = 0; parameter < 3; ++parameter) {
        double values[11];
        for (int k = -5; k <= 5; ++k) {
            double value = fitted_values[parameter] * (1 + (double)k / 100), point[3];
            memcpy(point, fitted_values, sizeof(point));
            point[parameter] = value;
            values[k + 5] = objective(lab, point[0], point[1], point[2]);
            line(&fit, "profile %s %d value %s rmse %s", parameter_names[parameter], k,
                 real(value, 6), real(rmse(values[k + 5], days), 4));
        }
        double h = fitted_values[parameter] / 100,
               curvature = (values[6] - 2 * values[5] + values[4]) / (h * h),
               variance = nm_sse / (days - 3);
        standard_errors[parameter] = sqrt(2 * variance / curvature);
        line(&fit, "profile_se %s %s", parameter_names[parameter],
             real(standard_errors[parameter], 6));
    }
    int training_days = days - p->holdout;
    SearchContext back = {.lab = lab,
                          .beta = beta_hat,
                          .gamma = gamma_hat,
                          .rho = rho_hat,
                          .sigma = p->sigma,
                          .multipliers = lab->multipliers,
                          .count = training_days,
                          .kind = K_SEIRD,
                          .parameter = 0};
    Golden back_beta =
        golden(search_value, &back, beta_hat - beta_spacing, beta_hat + beta_spacing, p->golden);
    back.cached =
        incidence(lab, back_beta.point, gamma_hat, p->sigma, lab->multipliers, training_days);
    back.parameter = 2;
    Golden back_rho =
        golden(search_value, &back, rho_hat - rho_spacing, rho_hat + rho_spacing, p->golden);
    double *back_incidence =
               incidence(lab, back_beta.point, gamma_hat, p->sigma, lab->multipliers, days),
           *forecast = reported(back_incidence + training_days, p->holdout, back_rho.point);
    line(&fit,
         "backtest train_days %d beta %s rho %s train_rmse %s test_rmse %s full_fit_test_rmse %s",
         training_days, real(back_beta.point, 6), real(back_rho.point, 6),
         real(rmse(back_rho.value, training_days), 4),
         real(rmse(errors(forecast, p->holdout, 1, input->cases + training_days), p->holdout), 4),
         real(rmse(errors(predicted + training_days, p->holdout, 1, input->cases + training_days),
                   p->holdout),
              4));
    for (int i = 0; i < p->holdout; ++i)
        line(&fit, "backtest_day %d observed %lld forecast %s error %s", training_days + i + 1,
             input->cases[training_days + i], real(forecast[i], 1),
             real((double)input->cases[training_days + i] - forecast[i], 1));
    SearchContext effect = {.lab = lab,
                            .beta = beta_hat,
                            .gamma = gamma_hat,
                            .rho = rho_hat,
                            .sigma = p->sigma,
                            .count = days,
                            .effect = true};
    memcpy(effect.interventions, input->interventions, sizeof(effect.interventions));
    double effect_sse = nm_sse;
    for (int k = 1; k < input->intervention_count; ++k) {
        effect.effect_index = k;
        Golden result =
            golden(search_value, &effect, input->interventions[k].multiplier - p->effect_width,
                   input->interventions[k].multiplier + p->effect_width, p->golden);
        effect.interventions[k].multiplier = result.point;
        effect_sse = result.value;
        line(&fit, "effect %d day %d given %s estimated %s sse %s", k + 1,
             input->interventions[k].day, real(input->interventions[k].multiplier, 4),
             real(result.point, 6), real(result.value, 1));
    }
    line(&fit, "effect_sse before %s after %s rmse %s", real(nm_sse, 1), real(effect_sse, 1),
         real(rmse(effect_sse, days), 4));
    const char *sensitivity_names[4] = {"beta", "gamma", "sigma", "rho"};
    for (int parameter = 0; parameter < 4; ++parameter)
        for (int k = 0; k < 2; ++k) {
            double factor = k ? 1.1 : 0.9, values[4] = {beta_hat, gamma_hat, p->sigma, rho_hat};
            values[parameter] *= factor;
            Model changed = make_model(lab, K_SEIRD, values[0], values[1], values[2]);
            Trajectory states = trajectory(&changed, lab->multipliers, days);
            double *values_incidence = series(&changed, states);
            int day = peak(values_incidence, days);
            line(&fit, "sensitivity %s %s r0 %s rmse %s peak_day %d peak %s attack %s",
                 sensitivity_names[parameter], real(factor, 2), real(values[0] / values[1], 4),
                 real(rmse(errors(values_incidence, days, values[3], input->cases), days), 4),
                 day + 1, real(values[3] * values_incidence[day], 1),
                 real(((double)lab->population - states.states[days - 1].values[0]) /
                          (double)lab->population,
                      4));
        }
    Model sir = make_model(lab, K_SIR, beta_hat, gamma_hat, p->sigma),
          age = make_model(lab, K_AGE, beta_hat, gamma_hat, p->sigma);
    Trajectory age_states = trajectory(&age, lab->multipliers, days);
    double *sir_incidence = series(&sir, trajectory(&sir, lab->multipliers, days)),
           *age_incidence = series(&age, age_states);
    compare_model(&fit, "sir", sir_incidence, input, rho_hat);
    compare_model(&fit, "seir", infections, input, rho_hat);
    compare_model(&fit, "age", age_incidence, input, rho_hat);
    SearchContext sir_context = {.lab = lab,
                                 .gamma = gamma_hat,
                                 .rho = rho_hat,
                                 .sigma = p->sigma,
                                 .multipliers = lab->multipliers,
                                 .count = days,
                                 .kind = K_SIR,
                                 .parameter = 0};
    Golden sir_search = golden(search_value, &sir_context, p->beta_min, p->beta_max, p->golden);
    Model fitted_sir = make_model(lab, K_SIR, sir_search.point, gamma_hat, p->sigma);
    double *fitted_sir_incidence =
        series(&fitted_sir, trajectory(&fitted_sir, lab->multipliers, days));
    line(&fit, "model sir_fit beta %s rmse %s peak_day %d", real(sir_search.point, 6),
         real(rmse(sir_search.value, days), 4), peak(fitted_sir_incidence, days) + 1);
    Lines trajectories = {0};
    line(
        &trajectories,
        "day,S,E,I,R,D,incidence,reported,observed,average7,cumulative_observed,cumulative_reported");
    for (int d = 0; d < days; ++d)
        line(&trajectories, "%d,%s,%s,%s,%s,%s,%s,%s,%lld,%s,%lld,%s", d + 1,
             real(fitted.states[d].values[0], 1), real(fitted.states[d].values[1], 1),
             real(fitted.states[d].values[2], 1), real(fitted.states[d].values[3], 1),
             real(fitted.states[d].values[4], 1), real(infections[d], 1), real(predicted[d], 1),
             input->cases[d], real(average[d], 2), cumulative_observed[d],
             real(cumulative_fitted[d], 1));
    Lines reproduction = {0};
    line(&reproduction, "r0 %s herd_immunity %s", real(r0, 4), real(1 - 1 / r0, 4));
    double ones[730];
    for (int d = 0; d < 730; ++d)
        ones[d] = 1;
    Trajectory long_states = trajectory(&model, ones, 730);
    line(&reproduction, "final_size equation %s simulated %s", real(final_size(r0), 4),
         real(((double)lab->population - long_states.states[729].values[0]) /
                  (double)lab->population,
              4));
    Model generation = make_model(lab, K_GENERATION, 0, gamma_hat, p->sigma);
    double *generation_incidence =
               series(&generation, trajectory(&generation, ones, p->generation)),
           coverage = total(generation_incidence, p->generation), generation_weights[60],
           generation_mean = 0;
    for (int s = 0; s < p->generation; ++s) {
        generation_weights[s] = generation_incidence[s] / coverage;
        generation_mean += (s + 1 - 0.5) * generation_weights[s];
    }
    line(&reproduction, "generation mean %s theory %s coverage %s", real(generation_mean, 4),
         real(1 / p->sigma + 1 / gamma_hat, 4), real(coverage, 4));
    for (int s = 0; s < p->generation; ++s)
        line(&reproduction, "generation_weight %d %s", s + 1, real(generation_weights[s], 6));
    int model_peak = peak(infections, days), infectious_peak = peak(infectious, days),
        observed_peak = 0, average_peak = peak(average, days);
    for (int d = 1; d < days; ++d)
        if (input->cases[d] > input->cases[observed_peak])
            observed_peak = d;
    line(&reproduction,
         "peak model day %d incidence %s reported %s infectious_day %d infectious %s",
         model_peak + 1, real(infections[model_peak], 1), real(predicted[model_peak], 1),
         infectious_peak + 1, real(infectious[infectious_peak], 1));
    line(&reproduction, "peak observed day %d cases %lld average7_day %d average7 %s",
         observed_peak + 1, input->cases[observed_peak], average_peak + 1,
         real(average[average_peak], 2));
    for (int k = 0; k < input->intervention_count; ++k) {
        int first = input->interventions[k].day - 1,
            last = k + 1 < input->intervention_count ? input->interventions[k + 1].day - 1 : days;
        I observed = 0;
        double predicted_sum = 0, square = 0, bias = 0;
        for (int d = first; d < last; ++d) {
            observed += input->cases[d];
            predicted_sum += predicted[d];
            square += residuals[d] * residuals[d];
            bias += residuals[d];
        }
        line(
            &reproduction,
            "period %d days %d %d multiplier %s rt_start %s rt_end %s observed %lld fitted %s rmse %s bias %s",
            k + 1, first + 1, last, real(input->interventions[k].multiplier, 4), real(rt[first], 4),
            real(rt[last - 1], 4), observed, real(predicted_sum, 1),
            real(rmse(square, last - first), 4), real(bias / (last - first), 1));
    }
    for (int k = 0; k < p->milestone_count; ++k) {
        I target = p->milestones[k];
        int observed = -1, predicted_day = -1;
        for (int d = 0; d < days; ++d) {
            if (observed < 0 && cumulative_observed[d] >= target)
                observed = d + 1;
            if (predicted_day < 0 && cumulative_fitted[d] >= (double)target)
                predicted_day = d + 1;
        }
        line(&reproduction, "milestone %lld observed %s fitted %s", target,
             observed < 0 ? "never" : format("%d", observed),
             predicted_day < 0 ? "never" : format("%d", predicted_day));
    }
    double predicted_total = total(predicted, days), constant[200];
    for (int d = 0; d < days; ++d)
        constant[d] = input->interventions[0].multiplier;
    double *none =
        reported(incidence(lab, beta_hat, gamma_hat, p->sigma, constant, days), days, rho_hat);
    int none_peak = peak(none, days);
    line(&reproduction, "counterfactual none reported %s peak_day %d peak %s averted %s",
         real(total(none, days), 1), none_peak + 1, real(none[none_peak], 1),
         real(total(none, days) - predicted_total, 1));
    for (int k = 1; k < input->intervention_count; ++k) {
        Intervention without[10];
        int count = 0;
        for (int j = 0; j < input->intervention_count; ++j)
            if (j != k)
                without[count++] = input->interventions[j];
        double multipliers[200];
        multiplier_sequence(without, count, days, multipliers);
        double sum =
            total(reported(incidence(lab, beta_hat, gamma_hat, p->sigma, multipliers, days), days,
                           rho_hat),
                  days);
        line(&reproduction, "counterfactual without %d reported %s averted %s", k + 1, real(sum, 1),
             real(sum - predicted_total, 1));
    }
    for (int k = 1; k < input->intervention_count; ++k)
        for (int shift = -7; shift <= 7; shift += 14) {
            Intervention moved[10];
            memcpy(moved, input->interventions, sizeof(moved));
            moved[k].day += shift;
            double multipliers[200];
            multiplier_sequence(moved, input->intervention_count, days, multipliers);
            double sum =
                total(reported(incidence(lab, beta_hat, gamma_hat, p->sigma, multipliers, days),
                               days, rho_hat),
                      days);
            line(&reproduction, "timing %d shift %d reported %s change %s", k + 1, shift,
                 real(sum, 1), real(sum - predicted_total, 1));
        }
    for (int d = 1; d < days; ++d)
        if ((rt[d] < 1) != (rt[d - 1] < 1))
            line(&reproduction, "rt_cross day %d %s", d + 1, rt[d] < 1 ? "down" : "up");
    double pressure[200] = {0};
    for (int d = 0; d < days; ++d)
        for (int s = 1; s <= (p->generation < d ? p->generation : d); ++s)
            pressure[d] += generation_weights[s - 1] * (double)input->cases[d - s];
    for (int d = 0; d < days; ++d) {
        char *empirical = "-";
        if (d + 1 >= p->generation + 7) {
            I numerator = 0;
            double denominator = 0;
            for (int j = d - 6; j <= d; ++j) {
                numerator += input->cases[j];
                denominator += pressure[j];
            }
            empirical = real((double)numerator / denominator, 4);
        }
        line(&reproduction, "rt %d model %s empirical %s", d + 1, real(rt[d], 4), empirical);
    }
    double ngm[6][6] = {0};
    next_generation(lab, lab->contacts, r0, ngm);
    Eigen eigen = largest(ngm, groups);
    for (int g = 0; g < groups; ++g) {
        char *row = format("ngm %s", input->groups[g].name);
        for (int h = 0; h < groups; ++h)
            row = joined(row, format(" %s", real(ngm[g][h], 4)));
        line(&reproduction, "%s", row);
    }
    char *eigen_line = format("r0_age %s ratio %s kbar %s eigenvector", real(eigen.value, 4),
                              real(eigen.value / r0, 4), real(lab->kbar, 4));
    for (int g = 0; g < groups; ++g)
        eigen_line = joined(eigen_line, format(" %s", real(eigen.vector[g], 4)));
    line(&reproduction, "%s", eigen_line);
    double z[6];
    for (int g = 0; g < groups; ++g)
        z[g] = 1;
    for (int iteration = 0; iteration < 100; ++iteration) {
        double next[6] = {0};
        for (int g = 0; g < groups; ++g) {
            double sum = 0;
            for (int h = 0; h < groups; ++h)
                sum += r0 * lab->contacts[g][h] * z[h];
            next[g] = 1 - exp(-sum);
        }
        memcpy(z, next, sizeof(z));
    }
    Trajectory long_age = trajectory(&age, ones, 730);
    double final_equation = 0, final_simulated = 0;
    for (int g = 0; g < groups; ++g) {
        double population = (double)input->groups[g].population,
               simulated = (population - long_age.states[729].values[6 * g]) / population;
        final_equation += population * z[g];
        final_simulated += population * simulated;
        line(&reproduction, "final_size_age %s equation %s simulated %s", input->groups[g].name,
             real(z[g], 4), real(simulated, 4));
    }
    line(&reproduction, "final_size_age total equation %s simulated %s",
         real(final_equation / (double)lab->population, 4),
         real(final_simulated / (double)lab->population, 4));
    State age_initial = initial_state(&age);
    for (int d = 0; d < days; d += 7) {
        double matrix[6][6] = {0};
        for (int g = 0; g < groups; ++g)
            for (int h = 0; h < groups; ++h)
                matrix[g][h] =
                    lab->multipliers[d] * r0 * lab->contacts[g][h] *
                    (d ? age_states.states[d - 1].values[6 * g] : age_initial.values[6 * g]) /
                    (double)input->groups[h].population;
        line(&reproduction, "age_rt %d %s homogeneous %s", d + 1,
             real(largest(matrix, groups).value, 4), real(rt[d], 4));
    }
    for (int first = 0, week = 1; first < days; first += 7, ++week) {
        int last = first + 7 < days ? first + 7 : days;
        char *row = format("age_weekly %d days %d %d", week, first + 1, last);
        for (int g = 0; g < groups; ++g) {
            double sum = 0;
            for (int d = first; d < last; ++d)
                sum += age_states.states[d].values[6 * g + 5];
            row = joined(row, format(" %s", real(sum, 1)));
        }
        line(&reproduction, "%s", row);
    }
    double age_infections[6] = {0};
    for (int g = 0; g < groups; ++g)
        for (int d = 0; d < days; ++d)
            age_infections[g] += age_states.states[d].values[6 * g + 5];
    double age_total = total(age_infections, groups);
    for (int g = 0; g < groups; ++g) {
        double values[200];
        for (int d = 0; d < days; ++d)
            values[d] = age_states.states[d].values[6 * g + 5];
        int day = peak(values, days);
        double population = (double)input->groups[g].population;
        line(&reproduction, "age %s attack %s infections %s share %s deaths %s peak_day %d peak %s",
             input->groups[g].name,
             real((population - age_states.states[days - 1].values[6 * g]) / population, 4),
             real(age_infections[g], 1), real(age_infections[g] / age_total, 4),
             real(age_states.states[days - 1].values[6 * g + 4], 1), day + 1, real(values[day], 1));
    }
    for (int i = 0; i < p->change_count; ++i) {
        ContactChange change = p->changes[i];
        int target = 0;
        while (strcmp(input->groups[target].name, change.group) != 0)
            ++target;
        double changed_contacts[6][6];
        memcpy(changed_contacts, lab->contacts, sizeof(changed_contacts));
        for (int g = 0; g < groups; ++g)
            for (int h = 0; h < groups; ++h)
                changed_contacts[g][h] = changed_contacts[g][h] *
                                         (g == target ? change.factor : 1) *
                                         (h == target ? change.factor : 1);
        Model changed = age;
        changed.contacts = changed_contacts;
        Trajectory states = trajectory(&changed, lab->multipliers, days);
        double changed_infections = total(series(&changed, states), days), susceptible_loss = 0;
        for (int g = 0; g < groups; ++g)
            susceptible_loss +=
                (double)input->groups[g].population - states.states[days - 1].values[6 * g];
        double changed_ngm[6][6] = {0};
        next_generation(lab, changed_contacts, r0, changed_ngm);
        line(&reproduction,
             "contact_change %s group %s factor %s r0_age %s infections %s deaths %s attack %s",
             change.name, change.group, real(change.factor, 4),
             real(largest(changed_ngm, groups).value, 4), real(changed_infections, 1),
             real(age_deaths(states.states[days - 1], groups), 1),
             real(susceptible_loss / (double)lab->population, 4));
    }
    Lines scenarios = {0};
    line(&scenarios, "scenario,day,incidence,reported");
    double first_scenario = 0;
    for (int index = 0; index < p->scenario_count; ++index) {
        Scenario scenario = p->scenarios[index];
        double future_multiplier[365];
        for (int d = 0; d < p->horizon; ++d)
            future_multiplier[d] = scenario.multiplier;
        Trajectory future =
            simulate(&model, fitted.states[days - 1], future_multiplier, p->horizon);
        double *future_incidence = series(&model, future),
               *future_reported = reported(future_incidence, p->horizon, rho_hat),
               sum = total(future_reported, p->horizon);
        if (index == 0)
            first_scenario = sum;
        int day = peak(future_reported, p->horizon), below = -1, above = 0;
        for (int j = 0; j < p->horizon; ++j) {
            if (below < 0 && future_reported[j] < p->threshold)
                below = days + j + 1;
            above += future_reported[j] >= p->threshold;
            line(&scenarios, "%s,%d,%s,%s", scenario.name, days + j + 1,
                 real(future_incidence[j], 1), real(future_reported[j], 1));
        }
        line(
            &reproduction,
            "scenario %s multiplier %s rt %s reported %s peak_day %d peak %s attack %s final_size %s averted %s below %s days_above %d",
            scenario.name, real(scenario.multiplier, 4),
            real(r0 * scenario.multiplier * fitted.states[days - 1].values[0] /
                     (double)lab->population,
                 4),
            real(sum, 1), days + day + 1, real(future_reported[day], 1),
            real(((double)lab->population - future.states[p->horizon - 1].values[0]) /
                     (double)lab->population,
                 4),
            real(final_size(r0 * scenario.multiplier), 4), real(first_scenario - sum, 1),
            below < 0 ? "never" : format("%d", below), above);
        double beta_low = beta_hat - 2 * standard_errors[0],
               beta_high = beta_hat + 2 * standard_errors[0], combined[565], band[2] = {0};
        memcpy(combined, lab->multipliers, (size_t)days * sizeof(double));
        memcpy(combined + days, future_multiplier, (size_t)p->horizon * sizeof(double));
        for (int k = 0; k < 2; ++k) {
            double *values = incidence(lab, k ? beta_high : beta_low, gamma_hat, p->sigma, combined,
                                       days + p->horizon);
            for (int d = days; d < days + p->horizon; ++d)
                band[k] += rho_hat * values[d];
        }
        line(&reproduction,
             "scenario_band %s beta_low %s reported_low %s beta_high %s reported_high %s",
             scenario.name, real(beta_low, 6), real(band[0], 1), real(beta_high, 6),
             real(band[1], 1));
        Trajectory age_future =
            simulate(&age, age_states.states[days - 1], future_multiplier, p->horizon);
        char *row = format("scenario_age %s attack", scenario.name);
        for (int g = 0; g < groups; ++g)
            row = joined(row, format(" %s", real(((double)input->groups[g].population -
                                                  age_future.states[p->horizon - 1].values[6 * g]) /
                                                     (double)input->groups[g].population,
                                                 4)));
        row = joined(row, format(" deaths %s",
                                 real(age_deaths(age_future.states[p->horizon - 1], groups), 1)));
        line(&reproduction, "%s", row);
    }
    save("fit.txt", fit);
    save("trajectories.csv", trajectories);
    save("scenarios.csv", scenarios);
    save("reproduction.txt", reproduction);
    save("curve_plot.txt", curve_plot(input->cases, predicted, days));
    return 0;
}
