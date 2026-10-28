#include "forecasting.h"
#include <stdarg.h>
static const char *names[] = {"naive",  "snaive",  "drift",      "ses",         "holt", "damped",
                              "hw_add", "hw_mult", "decomp_add", "decomp_mult", "ar",   "combo"};
static const char *difference_names[] = {"none", "first", "seasonal", "both"};
static void emit(FILE *out, const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    vfprintf(out, pattern, args);
    va_end(args);
    fputc('\n', out);
}
static Vector slice(Vector values, int first, int end) {
    Vector result = {.count = end - first};
    memcpy(result.values, values.values + first, (size_t)result.count * sizeof(double));
    return result;
}
static void vector_values(FILE *out, Vector values) {
    for (int i = 0; i < values.count; ++i)
        fprintf(out, " %s", real(values.values[i]));
}
typedef struct {
    int method, season, difference_kind, order;
    Vector values, residuals, seasonal, differenced, coefficients, aic, variances;
    SmoothParameters parameters;
    Smoothed smoothing;
    Correlation correlation;
    Levinson levinson;
    double intercept, slope, sigma2;
} Fitted;
static Vector forecast_method(const Fitted *model, int origin, int steps) {
    Vector result = {.count = steps};
    int method = model->method, season = model->season;
    Vector values = model->values;
    if (method == 0) {
        for (int k = 0; k < steps; ++k)
            result.values[k] = values.values[origin - 1];
        return result;
    }
    if (method == 1) {
        for (int k = 1; k <= steps; ++k)
            result.values[k - 1] = values.values[origin - season + (k - 1) % season];
        return result;
    }
    if (method == 2) {
        for (int k = 1; k <= steps; ++k)
            result.values[k - 1] =
                values.values[origin - 1] +
                k * ((values.values[origin - 1] - values.values[0]) / (double)(origin - 1));
        return result;
    }
    if (method >= 3 && method <= 7)
        return smooth_forecast(method, model->smoothing.states[origin], model->parameters, origin, steps,
                               season);
    if (method == 8 || method == 9) {
        for (int k = 1; k <= steps; ++k) {
            int t = origin + k - 1;
            double value = model->intercept + model->slope * (t + 1),
                   component = model->seasonal.values[t % season];
            result.values[k - 1] = method == 8 ? value + component : value * component;
        }
        return result;
    }
    return ar_forecast(values, model->differenced, model->difference_kind, season, origin, steps,
                       model->correlation.mean, model->coefficients);
}
static void consider(Fitted *model, Vector values, int season, SmoothParameters parameters, double *best) {
    Smoothed result = smooth(model->method, values, season, parameters);
    double sse = 0;
    for (int t = 0; t < result.residuals.count; ++t)
        sse += result.residuals.values[t] * result.residuals.values[t];
    if (sse < *best) {
        *best = sse;
        model->parameters = parameters;
        model->smoothing = result;
    }
}
static Fitted fit_method(int method, Vector values, const Params *p) {
    Fitted model = {.method = method, .values = values, .season = p->season, .parameters = {.phi = 1}};
    int size = values.count;
    if (method <= 2) {
        if (method == 2)
            model.slope = (values.values[size - 1] - values.values[0]) / (double)(size - 1);
        int start = method == 1 ? p->season : 1;
        for (int t = start; t < size; ++t)
            model.residuals.values[model.residuals.count++] =
                method == 1   ? values.values[t] - values.values[t - p->season]
                : method == 2 ? values.values[t] - values.values[t - 1] - model.slope
                              : values.values[t] - values.values[t - 1];
    } else if (method <= 7) {
        double best = INFINITY;
        for (int a = 0; a < p->alpha.count; ++a) {
            double alpha = p->alpha.values[a];
            if (method == 3) {
                consider(&model, values, p->season, (SmoothParameters){.alpha = alpha, .phi = 1}, &best);
                continue;
            }
            for (int b = 0; b < p->beta.count; ++b) {
                double beta = p->beta.values[b];
                if (method == 4)
                    consider(&model, values, p->season,
                             (SmoothParameters){.alpha = alpha, .beta = beta, .phi = 1}, &best);
                else if (method == 5)
                    for (int f = 0; f < p->phi.count; ++f)
                        consider(&model, values, p->season,
                                 (SmoothParameters){.alpha = alpha, .beta = beta, .phi = p->phi.values[f]},
                                 &best);
                else
                    for (int g = 0; g < p->gamma.count; ++g)
                        consider(&model, values, p->season,
                                 (SmoothParameters){
                                     .alpha = alpha, .beta = beta, .gamma = p->gamma.values[g], .phi = 1},
                                 &best);
            }
        }
        model.residuals = model.smoothing.residuals;
    } else if (method <= 9) {
        Decomposition decomposition = decompose(values, p->season);
        model.seasonal = method == 8 ? decomposition.additive : decomposition.multiplicative;
        Vector adjusted = {.count = size};
        for (int t = 0; t < size; ++t)
            adjusted.values[t] = method == 8 ? values.values[t] - model.seasonal.values[t % p->season]
                                             : values.values[t] / model.seasonal.values[t % p->season];
        regression(adjusted, &model.intercept, &model.slope);
        for (int t = 0; t < size; ++t) {
            double base = model.intercept + model.slope * (t + 1),
                   component = model.seasonal.values[t % p->season];
            model.residuals.values[model.residuals.count++] =
                values.values[t] - (method == 8 ? base + component : base * component);
        }
    } else {
        double smallest = INFINITY;
        for (int kind = 0; kind < 4; ++kind) {
            Vector differenced = difference(values, kind, p->season);
            Correlation correlation = autocorrelation(differenced, p->max_lag);
            model.variances.values[model.variances.count++] = correlation.variance;
            if (correlation.variance < smallest) {
                smallest = correlation.variance;
                model.difference_kind = kind;
                model.differenced = differenced;
                model.correlation = correlation;
            }
        }
        model.levinson = durbin_levinson(model.correlation.acf, p->max_lag);
        double best = INFINITY;
        for (int order = 0; order <= p->max_ar; ++order) {
            double value = (double)model.differenced.count *
                               log(model.correlation.variance * model.levinson.variance.values[order]) +
                           2 * order;
            model.aic.values[model.aic.count++] = value;
            if (value < best) {
                best = value;
                model.order = order;
            }
        }
        model.sigma2 = model.correlation.variance * model.levinson.variance.values[model.order];
        for (int j = 1; j <= model.order; ++j)
            model.coefficients.values[model.coefficients.count++] =
                model.levinson.coefficients[model.order][j];
        model.residuals = ar_residuals(model.differenced, model.correlation.mean, model.coefficients);
    }
    return model;
}
static void model_lines(FILE *out, const Fitted *model, const char *prefix) {
    int method = model->method;
    const char *name = names[method];
    char *tail = format("rmse %s residuals %d", real(rmse(model->residuals)), model->residuals.count);
    if (method <= 1)
        emit(out, "%s%s %s", prefix, name, tail);
    else if (method == 2)
        emit(out, "%s%s slope %s %s", prefix, name, real(model->slope), tail);
    else if (method <= 7) {
        fprintf(out, "%s%s alpha %s", prefix, name, real(model->parameters.alpha));
        if (method != 3)
            fprintf(out, " beta %s", real(model->parameters.beta));
        if (method == 5)
            fprintf(out, " phi %s", real(model->parameters.phi));
        if (method == 6 || method == 7)
            fprintf(out, " gamma %s", real(model->parameters.gamma));
        State state = model->smoothing.states[model->values.count];
        fprintf(out, " %s level %s", tail, real(state.level));
        if (method != 3)
            fprintf(out, " slope %s", real(state.slope));
        fputc('\n', out);
        if (method == 6 || method == 7) {
            fprintf(out, "%s%s seasonal", prefix, name);
            for (int i = 0; i < model->season; ++i)
                fprintf(out, " %s", real(state.seasonal[(model->values.count + i) % model->season]));
            fputc('\n', out);
        }
    } else if (method <= 9) {
        emit(out, "%s%s intercept %s slope %s %s", prefix, name, real(model->intercept), real(model->slope),
             tail);
        fprintf(out, "%s%s seasonal", prefix, name);
        vector_values(out, model->seasonal);
        fputc('\n', out);
    } else {
        emit(out, "%sar variance none %s first %s seasonal %s both %s", prefix,
             real(model->variances.values[0]), real(model->variances.values[1]),
             real(model->variances.values[2]), real(model->variances.values[3]));
        emit(out, "%sar difference %s n %d mean %s order %d sigma2 %s %s", prefix,
             difference_names[model->difference_kind], model->differenced.count,
             real(model->correlation.mean), model->order, real(model->sigma2), tail);
        fprintf(out, "%sar aic", prefix);
        vector_values(out, model->aic);
        fputc('\n', out);
        fprintf(out, "%sar coefficients", prefix);
        if (!model->coefficients.count)
            fputs(" none", out);
        else
            vector_values(out, model->coefficients);
        fputc('\n', out);
    }
    free(tail);
}
typedef Vector (*Forecaster)(void *, int, int);
typedef struct {
    int counts[24];
    Vector sigma, mae;
    double rmse;
} CrossValidation;
static CrossValidation cross_validate(Vector values, const Params *p, Forecaster forecast, void *context) {
    CrossValidation result = {.sigma = {.count = p->horizon}, .mae = {.count = p->horizon}};
    double squares[24] = {0}, absolute[24] = {0};
    for (int origin = p->cv_start; origin < values.count; ++origin) {
        int steps = p->horizon < values.count - origin ? p->horizon : values.count - origin;
        Vector estimates = forecast(context, origin, steps);
        for (int k = 0; k < steps; ++k) {
            double error = values.values[origin + k] - estimates.values[k];
            ++result.counts[k];
            squares[k] += error * error;
            absolute[k] += fabs(error);
        }
    }
    for (int k = 0; k < p->horizon; ++k) {
        result.sigma.values[k] = sqrt(squares[k] / result.counts[k]);
        result.mae.values[k] = absolute[k] / result.counts[k];
    }
    double sum = 0;
    int count = 0;
    for (int k = 0; k < p->holdout; ++k) {
        sum += squares[k];
        count += result.counts[k];
    }
    result.rmse = sqrt(sum / count);
    return result;
}
static Vector method_forecast(void *context, int origin, int steps) {
    return forecast_method(context, origin, steps);
}
typedef struct {
    Fitted *models;
    Indices members;
    int best;
} ModelGroup;
static Vector group_forecast(void *context, int origin, int steps) {
    ModelGroup *group = context;
    if (group->best != 11)
        return forecast_method(group->models + group->best, origin, steps);
    Vector result = {.count = steps};
    for (int i = 0; i < group->members.count; ++i) {
        Vector estimates = forecast_method(group->models + group->members.values[i], origin, steps);
        for (int k = 0; k < steps; ++k)
            result.values[k] += estimates.values[k];
    }
    for (int k = 0; k < steps; ++k)
        result.values[k] /= (double)group->members.count;
    return result;
}
typedef struct {
    FILE *decomposition, *models, *forecasts, *accuracy, *cv, *correlogram, *chart, *plan;
} Outputs;
static Outputs open_outputs(void) {
    Outputs out = {fopen("output/decomposition.csv", "w"),
                   fopen("output/models.txt", "w"),
                   fopen("output/forecasts.csv", "w"),
                   fopen("output/accuracy.csv", "w"),
                   fopen("output/cv.csv", "w"),
                   fopen("output/correlogram.txt", "w"),
                   fopen("output/chart.txt", "w"),
                   fopen("output/plan.txt", "w")};
    emit(out.decomposition,
         "series,period,value,cleaned,trend,seasonal_add,residual_add,seasonal_mult,residual_mult,flag");
    emit(out.forecasts, "series,stage,method,period,actual,forecast,lo80,hi80,lo95,hi95");
    emit(out.accuracy,
         "series,method,me,mae,rmse,mape,smape,mase,fva,cv_rmse,cover80,cover95,winkler80,winkler95,rank");
    emit(out.cv, "series,method,step,origins,mae,rmse");
    return out;
}
typedef struct {
    double forecast, lo80, hi80, lo95, hi95;
} Interval;
static Interval interval(double forecast, double sigma, const Params *p, double multiplier) {
    return (Interval){forecast * multiplier, (forecast - p->z80 * sigma) * multiplier,
                      (forecast + p->z80 * sigma) * multiplier, (forecast - p->z95 * sigma) * multiplier,
                      (forecast + p->z95 * sigma) * multiplier};
}
static void forecast_row(FILE *out, const char *name, const char *stage, const char *model,
                         const char *period, const char *actual, Interval v) {
    emit(out, "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s", name, stage, model, period, actual, real(v.forecast),
         real(v.lo80), real(v.hi80), real(v.lo95), real(v.hi95));
}
static char *correlation_bar(double correlation, double band) {
    char *bar = malloc(42);
    memset(bar, ' ', 41);
    bar[41] = 0;
    int extent = (int)floor(fabs(correlation) * 20 + 0.5), boundary = (int)floor(band * 20 + 0.5);
    bar[20 - boundary] = bar[20 + boundary] = ':';
    bar[20] = '|';
    if (correlation > 0)
        memset(bar + 21, '#', (size_t)extent);
    else if (correlation < 0)
        memset(bar + 20 - extent, '#', (size_t)extent);
    return bar;
}
static void diagnostics(FILE *out, const char *name, const Fitted *fitted, const Params *p) {
    const Fitted *ar = fitted + 10;
    double band = 2 / sqrt((double)ar->differenced.count);
    emit(out, "series %s difference %s n %d band %s", name, difference_names[ar->difference_kind],
         ar->differenced.count, real(band));
    for (int partial = 0; partial < 2; ++partial)
        for (int lag = 1; lag <= p->max_lag; ++lag) {
            double value = partial ? ar->levinson.partial.values[lag] : ar->correlation.acf.values[lag];
            emit(out, "%s %2d %7s [%s]%s", partial ? "pacf" : "acf", lag, real(value),
                 correlation_bar(value, band), fabs(value) > band ? " *" : "");
        }
    for (int method = 0; method < 11; ++method) {
        Vector residuals = fitted[method].residuals;
        double average = mean(residuals), count = residuals.count, s2 = 0, s3 = 0, s4 = 0, squares = 0,
               differences = 0;
        for (int i = 0; i < residuals.count; ++i) {
            double delta = residuals.values[i] - average;
            s2 += delta * delta;
            s3 += delta * delta * delta;
            s4 += delta * delta * delta * delta;
            squares += residuals.values[i] * residuals.values[i];
            if (i) {
                double difference_ = residuals.values[i] - residuals.values[i - 1];
                differences += difference_ * difference_;
            }
        }
        double m2 = s2 / count, m3 = s3 / count, m4 = s4 / count, skew = m3 / (m2 * sqrt(m2)),
               kurtosis = m4 / (m2 * m2) - 3, jb = count / 6 * (skew * skew + kurtosis * kurtosis / 4);
        emit(out, "residuals %s n %d mean %s sd %s dw %s skewness %s kurtosis %s jb %s", names[method],
             residuals.count, real(average), real(sqrt(s2 / (count - 1))), real(differences / squares),
             real(skew), real(kurtosis), real(jb));
        fprintf(out, "ljung_box %s", names[method]);
        for (int i = 0; i < p->ljung_box.count; ++i) {
            int lag = p->ljung_box.values[i];
            double q, probability;
            ljung_box(residuals, lag, &q, &probability);
            fprintf(out, " lag %d q %s p %s", lag, real(q), real(probability));
        }
        fputc('\n', out);
    }
}
static int chart_column(double value, double low, double high) {
    return (int)floor((value - low) / (high - low) * 60 + 0.5);
}
static void charts(FILE *out, const Series *series, int best, Vector actual, const Interval *holdout,
                   const Interval *future, const Decomposition *decomposition, const Params *p) {
    Interval rows[48];
    for (int k = 0; k < p->holdout; ++k)
        rows[k] = holdout[k];
    for (int k = 0; k < p->horizon; ++k)
        rows[p->holdout + k] = future[k];
    int count = p->holdout + p->horizon;
    double low = rows[0].lo95, high = rows[0].hi95;
    for (int i = 0; i < count; ++i) {
        low = fmin(low, rows[i].lo95);
        high = fmax(high, rows[i].hi95);
    }
    for (int i = 0; i < actual.count; ++i) {
        low = fmin(low, actual.values[i]);
        high = fmax(high, actual.values[i]);
    }
    emit(out, "chart %s method %s", series->name, names[best]);
    emit(out, "scale low %s high %s", real(low), real(high));
    int first = series->raw.count - p->holdout;
    for (int i = 0; i < count; ++i) {
        Interval row = rows[i];
        char chart[62];
        memset(chart, ' ', 61);
        chart[61] = 0;
        int left = chart_column(row.lo95, low, high), right = chart_column(row.hi95, low, high);
        memset(chart + left, '-', (size_t)(right - left + 1));
        left = chart_column(row.lo80, low, high);
        right = chart_column(row.hi80, low, high);
        memset(chart + left, '=', (size_t)(right - left + 1));
        chart[chart_column(row.forecast, low, high)] = 'o';
        if (i < actual.count)
            chart[chart_column(actual.values[i], low, high)] = '*';
        emit(out, "%s |%s|", series->periods[first + i], chart);
    }
    double peak = 0;
    for (int j = 0; j < p->season; ++j)
        peak = fmax(peak, fabs(decomposition->multiplicative.values[j] - 1));
    emit(out, "profile peak %s", real(peak));
    for (int j = 0; j < p->season; ++j) {
        double value = decomposition->multiplicative.values[j];
        int extent = (int)floor(fabs(value - 1) / peak * 30 + 0.5);
        char chart[62];
        memset(chart, ' ', 61);
        chart[61] = 0;
        chart[30] = '|';
        if (value > 1)
            memset(chart + 31, '#', (size_t)extent);
        else if (value < 1)
            memset(chart + 30 - extent, '#', (size_t)extent);
        emit(out, "season %2d %s [%s]", j + 1, real(value), chart);
    }
}
static void inventory_plan(FILE *out, const Series *series, int best, Vector corrected, Vector actual,
                           const Interval *future, Inventory policy, const Params *p, Forecaster forecast,
                           void *context) {
    int size = corrected.count, protection = policy.lead_time + policy.review;
    double squares = 0;
    for (int origin = p->cv_start; origin <= size - protection; ++origin) {
        Vector estimates = forecast(context, origin, protection);
        double error = 0;
        for (int k = 0; k < protection; ++k)
            error += corrected.values[origin + k] - estimates.values[k];
        squares += error * error;
    }
    double safety = policy.service * sqrt(squares / (double)(size - protection - p->cv_start + 1));
    emit(out, "series %s method %s", series->name, names[best]);
    emit(out, "policy on_hand %" PRId64 " lead_time %d review %d service %s safety_stock %s", policy.on_hand,
         policy.lead_time, policy.review, real(policy.service), real(safety));
    int last = 1;
    for (int k = 1; k - 1 + protection <= p->horizon; k += policy.review)
        last = k;
    int end = last - 1 + protection;
    Integer receipts[50] = {0}, outstanding = 0, ordered = 0;
    double stock = (double)policy.on_hand, lowest = INFINITY, sum = 0;
    int orders = 0, short_periods = 0;
    for (int k = 1; k <= end; ++k) {
        Integer receipt = receipts[k];
        stock += (double)receipt;
        outstanding -= receipt;
        if ((k - 1) % policy.review == 0 && k - 1 + protection <= p->horizon) {
            double position = stock + (double)outstanding, demand = 0;
            for (int j = k - 1; j < k - 1 + protection; ++j)
                demand += future[j].forecast;
            double target = demand + safety;
            Integer quantity = (Integer)ceil(target - position);
            if (quantity < 0)
                quantity = 0;
            emit(out, "review %s position %s target %s order %" PRId64, series->periods[size + k - 1],
                 real(position), real(target), quantity);
            if (quantity) {
                ++orders;
                ordered += quantity;
                outstanding += quantity;
                receipts[k + policy.lead_time] += quantity;
            }
        }
        stock -= future[k - 1].forecast;
        const char *status = stock < 0 ? "short" : stock < safety ? "low" : "ok";
        if (stock < 0)
            ++short_periods;
        lowest = fmin(lowest, stock);
        sum += stock;
        emit(out, "period %s demand %s receipt %" PRId64 " on_hand %s status %s",
             series->periods[size + k - 1], real(future[k - 1].forecast), receipt, real(stock), status);
    }
    emit(out, "summary orders %d ordered %" PRId64 " short_periods %d lowest %s average %s", orders, ordered,
         short_periods, real(lowest), real(sum / end));
    typedef struct {
        int year, actual_months, forecast_months;
        double actual, forecast;
    } Year;
    Year years[16] = {0};
    int year_count = 0;
    for (int t = 0; t < size + p->horizon; ++t) {
        int year = atoi(series->periods[t]);
        if (!year_count || years[year_count - 1].year != year)
            years[year_count++].year = year;
        Year *item = &years[year_count - 1];
        if (t < size) {
            ++item->actual_months;
            item->actual += actual.values[t];
        } else {
            ++item->forecast_months;
            item->forecast += future[t - size].forecast;
        }
    }
    bool previous_full = false;
    double previous_total = 0;
    for (int i = 0; i < year_count; ++i) {
        Year year = years[i];
        double value = year.actual + year.forecast;
        bool full = year.actual_months + year.forecast_months == 12;
        emit(out, "year %04d actual_months %d actual %s forecast_months %d forecast %s total %s growth %s",
             year.year, year.actual_months, real(year.actual), year.forecast_months, real(year.forecast),
             real(value),
             full && previous_full ? real(100 * (value - previous_total) / previous_total) : "NA");
        previous_full = full;
        previous_total = value;
    }
}
static const char *event_kind(const Input *input, const char *series, const char *period) {
    for (int i = 0; i < input->event_count; ++i)
        if (!strcmp(input->events[i].series, series) && !strcmp(input->events[i].period, period))
            return input->events[i].kind;
    return "";
}
static void analyze_series(Series series, const Input *input, Inventory inventory, Outputs out) {
    const Params *p = &input->params;
    int size = series.raw.count, training_size = size - p->holdout;
    for (int k = 0; k < p->horizon; ++k)
        next_month(series.periods[size + k - 1], series.periods[size + k]);
    Vector interpolated = series.raw;
    for (int t = 0; t < size; ++t)
        if (series.missing[t]) {
            int a = t - 1, b = t + 1;
            while (series.missing[a])
                --a;
            while (series.missing[b])
                ++b;
            interpolated.values[t] = series.raw.values[a] + (series.raw.values[b] - series.raw.values[a]) *
                                                                (double)(t - a) / (double)(b - a);
        }
    Decomposition decomposition = decompose(interpolated, p->season);
    int half = p->season / 2;
    Vector residuals = slice(decomposition.residual_add, half, size - half);
    double residual_mean = mean(residuals), residual_sd = sqrt(sample_variance(residuals));
    Vector corrected = interpolated;
    bool outliers[144] = {0};
    const char *events[144];
    char kinds[144][13];
    Vector lifts[144] = {0};
    int kind_count = 0, outlier_count = 0, event_count = 0;
    for (int t = 0; t < size; ++t) {
        events[t] = event_kind(input, series.name, series.periods[t]);
        if (events[t][0]) {
            ++event_count;
            int kind = 0;
            while (kind < kind_count && strcmp(kinds[kind], events[t]))
                ++kind;
            if (kind == kind_count)
                strcpy(kinds[kind_count++], events[t]);
            lifts[kind].values[lifts[kind].count++] =
                interpolated.values[t] /
                (decomposition.trend.values[t] + decomposition.additive.values[t % p->season]);
        }
        if (t >= half && t < size - half && !series.missing[t] && !events[t][0] &&
            fabs(decomposition.residual_add.values[t] - residual_mean) > p->outlier * residual_sd) {
            outliers[t] = true;
            ++outlier_count;
        }
        if (outliers[t] || events[t][0])
            corrected.values[t] =
                decomposition.trend.values[t] + decomposition.additive.values[t % p->season];
        const char *flag = events[t][0]        ? events[t]
                           : series.missing[t] ? "missing"
                           : outliers[t]       ? "outlier"
                                               : "ok";
        emit(out.decomposition, "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s", series.name, series.periods[t],
             real(interpolated.values[t]), real(corrected.values[t]),
             isnan(decomposition.trend.values[t]) ? "NA" : real(decomposition.trend.values[t]),
             real(decomposition.additive.values[t % p->season]),
             isnan(decomposition.residual_add.values[t]) ? "NA" : real(decomposition.residual_add.values[t]),
             real(decomposition.multiplicative.values[t % p->season]),
             isnan(decomposition.residual_mult.values[t]) ? "NA"
                                                          : real(decomposition.residual_mult.values[t]),
             flag);
    }
    Vector trend_residual = {0}, season_residual = {0};
    for (int t = half; t < size - half; ++t) {
        trend_residual.values[trend_residual.count++] =
            decomposition.trend.values[t] + decomposition.residual_add.values[t];
        season_residual.values[season_residual.count++] =
            decomposition.additive.values[t % p->season] + decomposition.residual_add.values[t];
    }
    double residual_variance = sample_variance(residuals),
           strength_trend = fmax(0, 1 - residual_variance / sample_variance(trend_residual)),
           strength_season = fmax(0, 1 - residual_variance / sample_variance(season_residual));
    Vector training = slice(corrected, 0, training_size), actual = slice(interpolated, training_size, size);
    Fitted *fitted = calloc(11, sizeof *fitted);
    CrossValidation validations[12];
    for (int method = 0; method < 11; ++method) {
        fitted[method] = fit_method(method, training, p);
        validations[method] = cross_validate(training, p, method_forecast, fitted + method);
    }
    Indices members = {.count = 11};
    for (int i = 0; i < 11; ++i) {
        int at = i;
        while (at && validations[i].rmse < validations[members.values[at - 1]].rmse) {
            members.values[at] = members.values[at - 1];
            --at;
        }
        members.values[at] = i;
    }
    members.count = p->combo;
    for (int i = 0; i < members.count; ++i)
        for (int j = i + 1; j < members.count; ++j)
            if (members.values[j] < members.values[i]) {
                int value = members.values[i];
                members.values[i] = members.values[j];
                members.values[j] = value;
            }
    ModelGroup combination = {fitted, members, 11};
    validations[11] = cross_validate(training, p, group_forecast, &combination);
    Vector forecasts[12];
    Accuracy measures[12];
    Interval intervals[12][24];
    double delta = scale_delta(training, p->season);
    for (int model = 0; model < 12; ++model) {
        forecasts[model] = model == 11 ? group_forecast(&combination, training_size, p->holdout)
                                       : forecast_method(fitted + model, training_size, p->holdout);
        measures[model] = evaluate(actual, forecasts[model], validations[model].sigma, p->z80, p->z95, delta);
        measures[model].cv_rmse = validations[model].rmse;
        for (int k = 0; k < p->holdout; ++k)
            intervals[model][k] =
                interval(forecasts[model].values[k], validations[model].sigma.values[k], p, 1);
    }
    int best = rank_accuracy(measures, 12).values[0];
    for (int i = 0; i < 12; ++i)
        measures[i].fva = 100 * (measures[0].mae - measures[i].mae) / measures[0].mae;
    Fitted *final_fitted = calloc(11, sizeof *final_fitted);
    if (best == 11)
        for (int i = 0; i < members.count; ++i) {
            int method = members.values[i];
            final_fitted[method] = fit_method(method, corrected, p);
        }
    else
        final_fitted[best] = fit_method(best, corrected, p);
    ModelGroup final = {final_fitted, members, best};
    CrossValidation final_cv = cross_validate(corrected, p, group_forecast, &final);
    Vector estimates = group_forecast(&final, size, p->horizon);
    Interval future[24];
    for (int k = 0; k < p->horizon; ++k) {
        double multiplier = 1;
        const char *event = event_kind(input, series.name, series.periods[size + k]);
        if (event[0]) {
            int kind = 0;
            while (strcmp(kinds[kind], event))
                ++kind;
            multiplier = mean(lifts[kind]);
        }
        future[k] = interval(estimates.values[k], final_cv.sigma.values[k], p, multiplier);
    }
    int missing_count = 0;
    for (int t = 0; t < size; ++t)
        if (series.missing[t])
            ++missing_count;
    emit(out.models, "series %s", series.name);
    emit(out.models, "data observations %d train %d holdout %d missing %d outliers %d events %d", size,
         training_size, p->holdout, missing_count, outlier_count, event_count);
    for (int kind = 0; kind < kind_count; ++kind)
        emit(out.models, "event %s occurrences %d lift %s", kinds[kind], lifts[kind].count,
             real(mean(lifts[kind])));
    for (int t = 0; t < size; ++t)
        if (outliers[t])
            emit(out.models, "outlier %s value %s expected %s score %s", series.periods[t],
                 real(interpolated.values[t]), real(corrected.values[t]),
                 real((decomposition.residual_add.values[t] - residual_mean) / residual_sd));
    emit(out.models, "strength trend %s seasonal %s", real(strength_trend), real(strength_season));
    for (int method = 0; method < 11; ++method)
        model_lines(out.models, fitted + method, "");
    fputs("combo members", out.models);
    for (int i = 0; i < members.count; ++i)
        fprintf(out.models, " %s", names[members.values[i]]);
    fputc('\n', out.models);
    emit(out.models, "best %s rmse %s", names[best], real(measures[best].rmse));
    if (best == 11) {
        for (int i = 0; i < members.count; ++i)
            model_lines(out.models, final_fitted + members.values[i], "final ");
    } else
        model_lines(out.models, final_fitted + best, "final ");
    for (int model = 0; model < 12; ++model) {
        for (int k = 0; k < p->holdout; ++k)
            forecast_row(
                out.forecasts, series.name, "holdout", names[model], series.periods[training_size + k],
                format("%" PRId64, (Integer)series.raw.values[training_size + k]), intervals[model][k]);
        Accuracy a = measures[model];
        emit(out.accuracy, "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%d,%d,%s,%s,%d", series.name, names[model],
             real(a.me), real(a.mae), real(a.rmse), real(a.mape), real(a.smape), real(a.mase), real(a.fva),
             real(a.cv_rmse), a.cover80, a.cover95, real(a.winkler80), real(a.winkler95), a.rank);
        for (int k = 0; k < p->horizon; ++k)
            emit(out.cv, "%s,%s,%d,%d,%s,%s", series.name, names[model], k + 1, validations[model].counts[k],
                 real(validations[model].mae.values[k]), real(validations[model].sigma.values[k]));
    }
    for (int k = 0; k < p->horizon; ++k)
        forecast_row(out.forecasts, series.name, "future", names[best], series.periods[size + k], "NA",
                     future[k]);
    diagnostics(out.correlogram, series.name, fitted, p);
    charts(out.chart, &series, best, actual, intervals[best], future, &decomposition, p);
    inventory_plan(out.plan, &series, best, corrected, interpolated, future, inventory, p, group_forecast,
                   &final);
    free(fitted);
    free(final_fitted);
}
int main(void) {
    Input input = read_input();
    Outputs output = open_outputs();
    for (int i = 0; i < input.series_count; ++i)
        analyze_series(input.series[i], &input, input.inventory[i], output);
    fclose(output.decomposition);
    fclose(output.models);
    fclose(output.forecasts);
    fclose(output.accuracy);
    fclose(output.cv);
    fclose(output.correlogram);
    fclose(output.chart);
    fclose(output.plan);
    return 0;
}
