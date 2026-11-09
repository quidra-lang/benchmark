#include "smoothing.h"
void *allocate(size_t count, size_t size) {
    void *value = calloc(count ? count : 1, size);
    if (!value)
        exit(EXIT_FAILURE);
    return value;
}
void grow(void **data, size_t *cap, size_t need, size_t size) {
    if (need <= *cap)
        return;
    size_t next = *cap ? *cap : 8;
    while (next < need)
        next *= 2;
    void *value = realloc(*data, next * size);
    if (!value)
        exit(EXIT_FAILURE);
    *data = value;
    *cap = next;
}
static char *vformat(const char *pattern, va_list args) {
    va_list copy;
    va_copy(copy, args);
    int count = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    char *out = allocate((size_t)count + 1, 1);
    vsnprintf(out, (size_t)count + 1, pattern, args);
    return out;
}
char *format(const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    char *out = vformat(pattern, args);
    va_end(args);
    return out;
}
void text_add(Text *text, const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    char *value = vformat(pattern, args);
    va_end(args);
    size_t length = strlen(value);
    grow((void **)&text->data, &text->cap, text->len + length + 1, 1);
    memcpy(text->data + text->len, value, length + 1);
    text->len += length;
    free(value);
}
void line_add(Lines *lines, const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    char *value = vformat(pattern, args);
    va_end(args);
    grow((void **)&lines->data, &lines->cap, lines->len + 1, sizeof *lines->data);
    lines->data[lines->len++] = value;
}
void extend(Lines *out, Lines lines) {
    for (size_t i = 0; i < lines.len; ++i)
        line_add(out, "%s", lines.data[i]);
}
Lines read_lines(const char *path) {
    FILE *file = fopen(path, "rb");
    if (!file)
        exit(EXIT_FAILURE);
    fseek(file, 0, SEEK_END);
    long length = ftell(file);
    rewind(file);
    char *data = allocate((size_t)length + 1, 1);
    size_t size = fread(data, 1, (size_t)length, file);
    fclose(file);
    Lines lines = {0};
    size_t first = 0;
    for (size_t i = 0; i < size; ++i)
        if (data[i] == '\n') {
            data[i] = 0;
            line_add(&lines, "%s", data + first);
            first = i + 1;
        }
    return lines;
}
Lines split(const char *text, char delimiter) {
    Lines out = {0};
    size_t first = 0, length = strlen(text);
    for (size_t i = 0; i <= length; ++i)
        if (i == length || text[i] == delimiter) {
            line_add(&out, "%.*s", (int)(i - first), text + first);
            first = i + 1;
        }
    return out;
}
Optional some(double value) {
    return (Optional){true, value};
}
static double sum(const double *values, int count) {
    double total = 0;
    for (int i = 0; i < count; ++i)
        total += values[i];
    return total;
}
static double rss(const double *observed, const double *fitted, int count) {
    double total = 0;
    for (int i = 0; i < count; ++i) {
        double error = observed[i] - fitted[i];
        total += error * error;
    }
    return total;
}
static int integer_compare(const void *pa, const void *pb) {
    int a = *(const int *)pa, b = *(const int *)pb;
    return a < b ? -1 : a > b;
}
static int real_compare(const void *pa, const void *pb) {
    double a = *(const double *)pa, b = *(const double *)pb;
    return a < b ? -1 : a > b;
}
static int pava(const Data *data, const char *direction, double *fitted, IsoBlock *blocks) {
    int count = 0;
    for (int i = 0; i < data->n; ++i) {
        blocks[count++] = (IsoBlock){i, i, data->y[i], 1};
        while (count >= 2) {
            IsoBlock a = blocks[count - 2], b = blocks[count - 1];
            bool violate = !strcmp(direction, "increasing") ? a.sum * b.count > b.sum * a.count
                                                            : a.sum * b.count < b.sum * a.count;
            if (!violate)
                break;
            blocks[count - 2] = (IsoBlock){a.first, b.last, a.sum + b.sum, a.count + b.count};
            --count;
        }
    }
    for (int b = 0; b < count; ++b)
        for (int i = blocks[b].first; i <= blocks[b].last; ++i)
            fitted[i] = (double)blocks[b].sum / (double)(100 * blocks[b].count);
    return count;
}
static int nearest(const Data *data, int position) {
    int best = 0;
    for (int i = 1; i < data->n; ++i)
        if (abs(data->x[i] - position) < abs(data->x[best] - position))
            best = i;
    return best;
}
Fit make_fit(const Data *data, const Method *method, Parameter parameter, const char *direction,
             int robust_iterations, bool full) {
    Fit fit = {0};
    fit.data = *data;
    fit.method = *method;
    fit.parameter = parameter;
    fit.defined = true;
    int n = data->n;
    if (method->kind == LINEAR) {
        fit.xbar = sum(data->real_x, n) / (double)n;
        double ybar = sum(data->real_y, n) / (double)n, sxy = 0;
        for (int i = 0; i < n; ++i) {
            fit.sxx += (data->real_x[i] - fit.xbar) * (data->real_x[i] - fit.xbar);
            sxy += (data->real_x[i] - fit.xbar) * (data->real_y[i] - ybar);
        }
        fit.slope = sxy / fit.sxx;
        fit.intercept = ybar - fit.slope * fit.xbar;
        fit.edf = some(2);
        for (int i = 0; i < n; ++i) {
            fit.fitted[i] = fit.intercept + fit.slope * data->real_x[i];
            fit.leverage[i] =
                1 / (double)n + (data->real_x[i] - fit.xbar) * (data->real_x[i] - fit.xbar) / fit.sxx;
        }
    } else if (method->kind == MEAN || method->kind == MEDIAN) {
        int k = (parameter.integer - 1) / 2;
        for (int i = 0; i < n; ++i) {
            int radius = k;
            if (i < radius)
                radius = i;
            if (n - 1 - i < radius)
                radius = n - 1 - i;
            int count = 2 * radius + 1, values[200];
            Integer total = 0;
            for (int j = i - radius; j <= i + radius; ++j) {
                total += data->y[j];
                values[j - i + radius] = data->y[j];
            }
            if (method->kind == MEAN) {
                fit.fitted[i] = (double)total / (double)(100 * count);
                fit.leverage[i] = 1 / (double)count;
            } else {
                qsort(values, count, sizeof *values, integer_compare);
                fit.fitted[i] = (double)values[radius] / 100;
            }
        }
        if (method->kind == MEAN)
            fit.edf = some(sum(fit.leverage, n));
    } else if (method->kind == NW || method->kind == LL) {
        if (full) {
            for (int i = 0; i < n; ++i) {
                KernelResult local =
                    kernel_estimate(data, method->kernel, parameter.integer, data->x[i], method->kind == LL);
                if (!local.estimate.defined) {
                    fit.defined = false;
                    break;
                }
                fit.fitted[i] = local.estimate.value;
                fit.leverage[i] = local.leverage.value;
            }
            if (fit.defined)
                fit.edf = some(sum(fit.leverage, n));
        }
    } else if (method->kind == LOESS) {
        if (full) {
            LoessFit local = loess_fit(data, parameter.integer, method->degree, robust_iterations);
            memcpy(fit.fitted, local.fitted, sizeof fit.fitted);
            memcpy(fit.leverage, local.leverage, sizeof fit.leverage);
            memcpy(fit.rho, local.rho, sizeof fit.rho);
            memcpy(fit.robust, local.iterations, sizeof fit.robust);
            fit.robust_count = local.count;
            fit.edf = some(local.edf);
        } else
            for (int i = 0; i < n; ++i)
                fit.rho[i] = 1;
    } else if (method->kind == SPLINE) {
        fit.spline = spline_create(data->x, n, parameter.value);
        fit.spline_values = spline_fit(fit.spline, data->real_y);
        memcpy(fit.fitted, fit.spline_values.fitted, sizeof fit.fitted);
        if (full) {
            spline_leverage(fit.spline, fit.leverage);
            fit.edf = some(sum(fit.leverage, n));
        }
    } else {
        fit.direction = (char *)direction;
        if (!strcmp(direction, "auto")) {
            double increasing[200], decreasing[200];
            IsoBlock inc_blocks[200], dec_blocks[200];
            int inc = pava(data, "increasing", increasing, inc_blocks),
                dec = pava(data, "decreasing", decreasing, dec_blocks);
            fit.increasing_rss = rss(data->real_y, increasing, n);
            fit.decreasing_rss = rss(data->real_y, decreasing, n);
            bool choose_increasing = fit.increasing_rss <= fit.decreasing_rss;
            fit.direction = choose_increasing ? "increasing" : "decreasing";
            memcpy(fit.fitted, choose_increasing ? increasing : decreasing, (size_t)n * sizeof(double));
            fit.block_count = choose_increasing ? inc : dec;
            memcpy(fit.blocks, choose_increasing ? inc_blocks : dec_blocks,
                   (size_t)fit.block_count * sizeof *fit.blocks);
        } else
            fit.block_count = pava(data, direction, fit.fitted, fit.blocks);
        fit.edf = some((double)fit.block_count);
        fit.parameter.text = fit.direction;
    }
    return fit;
}
Optional estimate(const Fit *fit, int position) {
    Kind kind = fit->method.kind;
    if (kind == LINEAR)
        return some(fit->intercept + fit->slope * ((double)position / 100));
    if (kind == MEAN || kind == MEDIAN)
        return some(fit->fitted[nearest(&fit->data, position)]);
    if (kind == NW || kind == LL)
        return kernel_estimate(&fit->data, fit->method.kernel, fit->parameter.integer, position, kind == LL)
            .estimate;
    if (kind == LOESS)
        return some(
            local_fit(&fit->data, position, fit->parameter.integer, fit->method.degree, fit->rho).value);
    if (kind == SPLINE)
        return some(spline_evaluate(fit->spline, &fit->spline_values, position));
    int index = 0;
    while (index + 1 < fit->data.n && fit->data.x[index + 1] <= position)
        ++index;
    return some(fit->fitted[index]);
}
void weights(const Fit *fit, int position, double *values) {
    const Data *data = &fit->data;
    int n = data->n;
    for (int i = 0; i < n; ++i)
        values[i] = 0;
    Kind kind = fit->method.kind;
    if (kind == LINEAR) {
        double x0 = (double)position / 100;
        for (int j = 0; j < n; ++j)
            values[j] = 1 / (double)n + (x0 - fit->xbar) * (data->real_x[j] - fit->xbar) / fit->sxx;
    } else if (kind == MEAN) {
        int c = nearest(data, position), radius = (fit->parameter.integer - 1) / 2;
        if (c < radius)
            radius = c;
        if (n - 1 - c < radius)
            radius = n - 1 - c;
        for (int j = c - radius; j <= c + radius; ++j)
            values[j] = 1 / (double)(2 * radius + 1);
    } else if (kind == NW || kind == LL) {
        KernelResult local =
            kernel_estimate(data, fit->method.kernel, fit->parameter.integer, position, kind == LL);
        memcpy(values, local.weights, (size_t)n * sizeof *values);
    } else if (kind == LOESS) {
        LocalFit local = local_fit(data, position, fit->parameter.integer, fit->method.degree, fit->rho);
        memcpy(values, local.weights, (size_t)n * sizeof *values);
    } else if (kind == SPLINE)
        spline_weights(fit->spline, position, values);
}
static Data subset(const Data *data, int excluded, int fold, int folds) {
    Data out = {0};
    for (int i = 0; i < data->n; ++i) {
        if (i == excluded || (folds && i % folds == fold))
            continue;
        int j = out.n++;
        out.x[j] = data->x[i];
        out.y[j] = data->y[i];
        out.real_x[j] = data->real_x[i];
        out.real_y[j] = data->real_y[i];
    }
    return out;
}
static Optional cross_validation(const Data *data, const Method *method, Parameter parameter,
                                 const char *direction, int folds) {
    Optional predictions[200] = {{0}};
    if (!folds) {
        for (int i = 0; i < data->n; ++i) {
            Data training = subset(data, i, 0, 0);
            Fit fit = make_fit(&training, method, parameter, direction, 0, false);
            predictions[i] = estimate(&fit, data->x[i]);
        }
    } else
        for (int fold = 0; fold < folds; ++fold) {
            Data training = subset(data, -1, fold, folds);
            Fit fit = make_fit(&training, method, parameter, direction, 0, false);
            for (int i = 0; i < data->n; ++i)
                if (i % folds == fold)
                    predictions[i] = estimate(&fit, data->x[i]);
        }
    return loo_score(data->real_y, predictions, data->n);
}
static int build_methods(const Params *p, Method *out) {
    int count = 0;
    out[count++] = (Method){.name = "linear", .kind = LINEAR};
    out[count++] = (Method){.name = "running_mean", .kind = MEAN};
    out[count++] = (Method){.name = "running_median", .kind = MEDIAN};
    for (size_t i = 0; i < p->rows[1].len; ++i)
        out[count++] =
            (Method){.name = format("nw_%s", p->rows[1].data[i]), .kind = NW, .kernel = p->rows[1].data[i]};
    for (size_t i = 0; i < p->rows[1].len; ++i)
        out[count++] =
            (Method){.name = format("ll_%s", p->rows[1].data[i]), .kind = LL, .kernel = p->rows[1].data[i]};
    for (size_t i = 0; i < p->rows[3].len; ++i)
        out[count++] = (Method){
            .name = format("loess%s", p->rows[3].data[i]), .kind = LOESS, .degree = atoi(p->rows[3].data[i])};
    out[count++] = (Method){.name = "spline", .kind = SPLINE};
    out[count++] = (Method){.name = "isotonic", .kind = ISOTONIC};
    for (int m = 0; m < count; ++m) {
        Kind kind = out[m].kind;
        int row = kind == MEAN || kind == MEDIAN ? 0
                  : kind == NW || kind == LL     ? 2
                  : kind == LOESS                ? 4
                  : kind == SPLINE               ? 6
                                                 : -1;
        if (row < 0)
            continue;
        for (size_t c = 0; c < p->rows[row].len; ++c) {
            char *text = p->rows[row].data[c];
            out[m].candidates[out[m].candidate_count++] =
                (Parameter){text, strtod(text, NULL),
                            row == 0               ? atoi(text)
                            : row == 2 || row == 4 ? hundredths(text)
                                                   : 0};
        }
    }
    return count;
}
static char *real_text(Optional value, int digits) {
    if (!value.defined)
        return "NA";
    char *text = format("%.*f", digits, value.value);
    if (text[0] == '-') {
        bool zero = true;
        for (size_t i = 1; text[i]; ++i)
            if (text[i] != '0' && text[i] != '.')
                zero = false;
        if (zero)
            return text + 1;
    }
    return text;
}
static char *real(double value) {
    return real_text(some(value), 4);
}
static char *position_text(int value) {
    Integer magnitude = value < 0 ? -(Integer)value : value;
    return format("%s%" PRId64 ".%02" PRId64, value < 0 ? "-" : "", magnitude / 100, magnitude % 100);
}
static int method_index(const Method *methods, int count, const char *name) {
    for (int i = 0; i < count; ++i)
        if (!strcmp(methods[i].name, name))
            return i;
    return count;
}
typedef struct {
    double residuals[200], rss, r2, dw, z;
    Optional df, rse, nonlinear;
    double acf[5], quantiles[5];
    int runs, positive, negative, turning, largest;
} Diagnostic;
static Diagnostic diagnose(const Fit *fit, double linear_rss, const Optional *grid, int grid_count) {
    Diagnostic d = {0};
    int n = fit->data.n;
    double mean = sum(fit->data.real_y, n) / (double)n, tss = 0;
    for (int i = 0; i < n; ++i) {
        double residual = fit->data.real_y[i] - fit->fitted[i];
        d.residuals[i] = residual;
        d.rss += residual * residual;
        tss += (fit->data.real_y[i] - mean) * (fit->data.real_y[i] - mean);
        if (fabs(residual) > fabs(d.residuals[d.largest]))
            d.largest = i;
    }
    d.r2 = 1 - d.rss / tss;
    if (fit->edf.defined) {
        d.df = some((double)n - fit->edf.value);
        d.rse = some(sqrt(d.rss / d.df.value));
        if (fit->method.kind != LINEAR && fit->edf.value > 2)
            d.nonlinear = some(((linear_rss - d.rss) / (fit->edf.value - 2)) / (d.rss / d.df.value));
    }
    double residual_mean = sum(d.residuals, n) / (double)n, denominator = 0;
    for (int i = 0; i < n; ++i)
        denominator += (d.residuals[i] - residual_mean) * (d.residuals[i] - residual_mean);
    for (int k = 1; k <= 5; ++k) {
        double numerator = 0;
        for (int i = 0; i + k < n; ++i)
            numerator += (d.residuals[i] - residual_mean) * (d.residuals[i + k] - residual_mean);
        d.acf[k - 1] = numerator / denominator;
    }
    double dw = 0;
    for (int i = 1; i < n; ++i)
        dw += (d.residuals[i] - d.residuals[i - 1]) * (d.residuals[i] - d.residuals[i - 1]);
    d.dw = dw / d.rss;
    int sign = 0;
    for (int i = 0; i < n; ++i) {
        double residual = d.residuals[i];
        if (residual == 0)
            continue;
        int current = residual > 0 ? 1 : -1;
        if (current > 0)
            ++d.positive;
        else
            ++d.negative;
        if (current != sign) {
            ++d.runs;
            sign = current;
        }
    }
    Integer nonzero = d.positive + d.negative, product = 2 * (Integer)d.positive * d.negative;
    double mu = 1 + (double)product / (double)nonzero,
           variance = (double)(product * (product - nonzero)) / (double)(nonzero * nonzero * (nonzero - 1));
    d.z = ((double)d.runs - mu) / sqrt(variance);
    double sorted[200];
    memcpy(sorted, d.residuals, (size_t)n * sizeof *sorted);
    qsort(sorted, n, sizeof *sorted, real_compare);
    for (int k = 0; k < 5; ++k) {
        int j = (n - 1) * k / 4, remainder = (n - 1) * k - 4 * j;
        d.quantiles[k] =
            !remainder ? sorted[j] : sorted[j] + (double)remainder / 4 * (sorted[j + 1] - sorted[j]);
    }
    Optional previous = {0};
    int previous_sign = 0;
    for (int k = 0; k < grid_count; ++k) {
        if (!grid[k].defined)
            continue;
        if (previous.defined) {
            double delta = grid[k].value - previous.value;
            if (delta != 0) {
                int current = delta > 0 ? 1 : -1;
                if (previous_sign && current != previous_sign)
                    ++d.turning;
                previous_sign = current;
            }
        }
        previous = grid[k];
    }
    return d;
}
typedef struct {
    int method, candidate;
    Optional score, edf;
    bool selected;
} SelectionRow;
typedef struct {
    Series series;
    Fit fits[13];
    Optional loo[13], kfold[13];
    SelectionRow selection[110];
    int selection_count, grid[201], grid_count;
    Optional estimates[13][201];
    Diagnostic diagnostics[13];
    int ranking[13], best, outlier;
    double standardized[200], cook[200];
} Study;
static Study *study(const Series *series, const Params *p, const Method *methods, int count,
                    int series_index) {
    Study *out = allocate(1, sizeof *out);
    out->series = *series;
    int robust = atoi(p->rows[5].data[0]), folds = atoi(p->rows[7].data[0]);
    for (int m = 0; m < count; ++m) {
        const Method *method = &methods[m];
        const char *direction = p->rows[8].data[series_index];
        Parameter parameter = {"-", 0, 0};
        Optional score = {0};
        if (method->candidate_count) {
            Optional scores[10], edfs[10];
            for (int c = 0; c < method->candidate_count; ++c) {
                Parameter candidate = method->candidates[c];
                Fit fit = make_fit(&series->data, method, candidate, direction, 0, true);
                scores[c] =
                    method->kind == SPLINE
                        ? some(gcv_score(series->data.real_y, fit.fitted, series->data.n, fit.edf.value))
                        : cross_validation(&series->data, method, candidate, direction, 0);
                edfs[c] = fit.edf;
            }
            int selected = selected_candidate(scores, method->candidate_count);
            parameter = method->candidates[selected];
            score = scores[selected];
            for (int c = 0; c < method->candidate_count; ++c)
                out->selection[out->selection_count++] =
                    (SelectionRow){m, c, scores[c], edfs[c], c == selected};
        }
        Fit *fit = &out->fits[m];
        *fit = make_fit(&series->data, method, parameter, direction, robust, true);
        out->loo[m] = method->kind == LINEAR || method->kind == SPLINE || method->kind == ISOTONIC
                          ? cross_validation(&series->data, method, parameter, fit->direction, 0)
                          : score;
        out->kfold[m] = cross_validation(&series->data, method, parameter, fit->direction, folds);
    }
    const Data *data = &series->data;
    out->grid_count = atoi(p->rows[9].data[0]);
    for (int k = 0; k < out->grid_count; ++k)
        out->grid[k] = data->x[0] + k * (data->x[data->n - 1] - data->x[0]) / (out->grid_count - 1);
    for (int m = 0; m < count; ++m)
        for (int k = 0; k < out->grid_count; ++k)
            out->estimates[m][k] = estimate(&out->fits[m], out->grid[k]);
    double linear_rss = rss(data->real_y, out->fits[0].fitted, data->n);
    for (int m = 0; m < count; ++m) {
        out->diagnostics[m] = diagnose(&out->fits[m], linear_rss, out->estimates[m], out->grid_count);
        out->ranking[m] = m;
    }
    for (int i = 1; i < count; ++i) {
        int value = out->ranking[i], j = i;
        while (j > 0 && out->loo[out->ranking[j - 1]].value > out->loo[value].value) {
            out->ranking[j] = out->ranking[j - 1];
            --j;
        }
        out->ranking[j] = value;
    }
    out->best = out->ranking[0];
    for (int i = 0; i < count; ++i) {
        int m = out->ranking[i];
        if (methods[m].kind != MEDIAN && methods[m].kind != ISOTONIC) {
            out->outlier = m;
            break;
        }
    }
    Fit *fit = &out->fits[out->outlier];
    Diagnostic *d = &out->diagnostics[out->outlier];
    for (int i = 0; i < data->n; ++i)
        if (fit->leverage[i] < 1) {
            double t = d->residuals[i] / (d->rse.value * sqrt(1 - fit->leverage[i]));
            out->standardized[i] = t;
            out->cook[i] = t * t * fit->leverage[i] / ((1 - fit->leverage[i]) * fit->edf.value);
        }
    return out;
}
static double standard_error(const Fit *fit, const Diagnostic *d, int position) {
    double values[200], total = 0;
    weights(fit, position, values);
    for (int i = 0; i < fit->data.n; ++i)
        total += values[i] * values[i];
    return d->rse.value * sqrt(total);
}
static int minimum_y(const Data *data) {
    int value = data->y[0];
    for (int i = 1; i < data->n; ++i)
        if (data->y[i] < value)
            value = data->y[i];
    return value;
}
static int maximum_y(const Data *data) {
    int value = data->y[0];
    for (int i = 1; i < data->n; ++i)
        if (data->y[i] > value)
            value = data->y[i];
    return value;
}
static Lines diagnostics_lines(const Study *s, const Params *p, const Method *methods, int method_count) {
    const Data *data = &s->series.data;
    Lines out = {0};
    line_add(&out, "series %s n %d x %s %s y %s %s", s->series.name, data->n, position_text(data->x[0]),
             position_text(data->x[data->n - 1]), position_text(minimum_y(data)),
             position_text(maximum_y(data)));
    for (int m = 0; m < method_count; ++m) {
        const Fit *fit = &s->fits[m];
        const Diagnostic *d = &s->diagnostics[m];
        Text first = {0};
        text_add(&first, "method %s parameter %s loo %s", methods[m].name, fit->parameter.text,
                 real_text(s->loo[m], 4));
        if (methods[m].kind == SPLINE)
            for (int c = 0; c < s->selection_count; ++c)
                if (s->selection[c].method == m && s->selection[c].selected)
                    text_add(&first, " gcv %s", real_text(s->selection[c].score, 4));
        line_add(&out, "%s", first.data);
        line_add(&out, "  rss %s edf %s df %s rse %s r2 %s f_nonlinear %s", real(d->rss),
                 real_text(fit->edf, 4), real_text(d->df, 4), real_text(d->rse, 4), real(d->r2),
                 real_text(d->nonlinear, 4));
        line_add(&out, "  acf %s %s %s %s %s dw %s", real(d->acf[0]), real(d->acf[1]), real(d->acf[2]),
                 real(d->acf[3]), real(d->acf[4]), real(d->dw));
        line_add(&out, "  runs %d positive %d negative %d z %s", d->runs, d->positive, d->negative,
                 real(d->z));
        line_add(&out, "  max_residual %s at %s turning %d", real(d->residuals[d->largest]),
                 position_text(data->x[d->largest]), d->turning);
        line_add(&out, "  quantiles %s %s %s %s %s", real(d->quantiles[0]), real(d->quantiles[1]),
                 real(d->quantiles[2]), real(d->quantiles[3]), real(d->quantiles[4]));
        if (methods[m].kind == LOESS) {
            for (int t = 0; t < fit->robust_count; ++t) {
                Robust r = fit->robust[t];
                line_add(&out, "  robust %d scale %s zero_weight %d max_change %s", t + 1, real(r.scale),
                         r.zero, real(r.change));
            }
            Text zero = {0};
            text_add(&zero, "  zero_weight_points");
            bool any = false;
            for (int i = 0; i < data->n; ++i)
                if (fit->rho[i] == 0) {
                    text_add(&zero, " %s", position_text(data->x[i]));
                    any = true;
                }
            if (!any)
                text_add(&zero, " none");
            line_add(&out, "%s", zero.data);
        }
    }
    line_add(&out, "ranking");
    for (int rank = 0; rank < method_count; ++rank) {
        int m = s->ranking[rank];
        line_add(&out, "  %d %s %s kfold %s", rank + 1, methods[m].name, real_text(s->loo[m], 4),
                 real_text(s->kfold[m], 4));
    }
    line_add(&out, "agreement with %s", methods[s->best].name);
    for (int m = 0; m < method_count; ++m) {
        if (m == s->best)
            continue;
        int count = 0, at = 0;
        double squared = 0, maximum = -1;
        for (int k = 0; k < s->grid_count; ++k)
            if (s->estimates[m][k].defined && s->estimates[s->best][k].defined) {
                ++count;
                double delta = fabs(s->estimates[m][k].value - s->estimates[s->best][k].value);
                squared += delta * delta;
                if (delta > maximum) {
                    maximum = delta;
                    at = k;
                }
            }
        line_add(&out, "  %s points %d rms %s max %s at %s", methods[m].name, count,
                 real(sqrt(squared / (double)count)), real(maximum), position_text(s->grid[at]));
    }
    int spline = method_index(methods, method_count, "spline"), max_at = 1, min_at = 1;
    double maximum = 0, minimum = 0;
    for (int k = 1; k + 1 < s->grid_count; ++k) {
        double slope = (s->estimates[spline][k + 1].value - s->estimates[spline][k - 1].value) /
                       ((double)(s->grid[k + 1] - s->grid[k - 1]) / 100);
        if (k == 1 || slope > maximum) {
            maximum = slope;
            max_at = k;
        }
        if (k == 1 || slope < minimum) {
            minimum = slope;
            min_at = k;
        }
    }
    line_add(&out, "slope spline max %s at %s min %s at %s", real(maximum), position_text(s->grid[max_at]),
             real(minimum), position_text(s->grid[min_at]));
    const Fit *fit = &s->fits[s->outlier];
    const Diagnostic *d = &s->diagnostics[s->outlier];
    double threshold = (double)hundredths(p->rows[12].data[0]) / 100;
    line_add(&out, "outliers method %s threshold %s", methods[s->outlier].name,
             position_text(hundredths(p->rows[12].data[0])));
    int outliers[200], outlier_count = 0, influence[200], influence_count = 0;
    for (int i = 0; i < data->n; ++i)
        if (fit->leverage[i] < 1) {
            influence[influence_count++] = i;
            if (fabs(s->standardized[i]) > threshold)
                outliers[outlier_count++] = i;
        }
    for (int k = 1; k < outlier_count; ++k) {
        int value = outliers[k], j = k;
        while (j > 0 && fabs(s->standardized[outliers[j - 1]]) < fabs(s->standardized[value])) {
            outliers[j] = outliers[j - 1];
            --j;
        }
        outliers[j] = value;
    }
    if (!outlier_count)
        line_add(&out, "  none");
    for (int k = 0; k < outlier_count; ++k) {
        int i = outliers[k];
        line_add(&out, "  x %s y %s fit %s residual %s standardized %s", position_text(data->x[i]),
                 position_text(data->y[i]), real(fit->fitted[i]), real(d->residuals[i]),
                 real(s->standardized[i]));
    }
    line_add(&out, "influence method %s", methods[s->outlier].name);
    for (int k = 1; k < influence_count; ++k) {
        int value = influence[k], j = k;
        while (j > 0 && s->cook[influence[j - 1]] < s->cook[value]) {
            influence[j] = influence[j - 1];
            --j;
        }
        influence[j] = value;
    }
    for (int k = 0; k < 3 && k < influence_count; ++k) {
        int i = influence[k];
        line_add(&out, "  x %s lev %s cook %s", position_text(data->x[i]), real(fit->leverage[i]),
                 real(s->cook[i]));
    }
    line_add(&out, "bands");
    double z = strtod(p->rows[10].data[0], NULL);
    for (size_t b = 0; b < p->rows[11].len; ++b) {
        char *name = p->rows[11].data[b];
        int m = method_index(methods, method_count, name), count = 0, coverage = 0;
        double total = 0;
        for (int k = 0; k < s->grid_count; ++k)
            if (s->estimates[m][k].defined) {
                total += standard_error(&s->fits[m], &s->diagnostics[m], s->grid[k]);
                ++count;
            }
        for (int i = 0; i < data->n; ++i) {
            double se = standard_error(&s->fits[m], &s->diagnostics[m], data->x[i]),
                   rse = s->diagnostics[m].rse.value;
            if (fabs(s->diagnostics[m].residuals[i]) <= z * sqrt(rse * rse + se * se))
                ++coverage;
        }
        line_add(&out, "  %s mean_se %s coverage %d of %d", name, real(total / (double)count), coverage,
                 data->n);
    }
    return out;
}
static Lines framed(char **rows, int width, int height) {
    Lines out = {0};
    char *middle = allocate((size_t)width + 1, 1);
    memset(middle, '-', width);
    line_add(&out, "+%s+", middle);
    for (int row = 0; row < height; ++row)
        line_add(&out, "|%s|", rows[row]);
    line_add(&out, "+%s+", middle);
    return out;
}
static char **plot_grid(int width, int height) {
    char **rows = allocate(height, sizeof *rows);
    for (int i = 0; i < height; ++i) {
        rows[i] = allocate((size_t)width + 1, 1);
        memset(rows[i], ' ', width);
    }
    return rows;
}
static int clamped_row(double value, int height) {
    return value < 0 ? 0 : value >= (double)height ? height - 1 : (int)value;
}
static Lines plot_lines(const Study *s, const Params *p, const Method *methods, int method_count) {
    const Data *data = &s->series.data;
    int width = atoi(p->rows[16].data[0]), height = atoi(p->rows[16].data[1]), xa = data->x[0],
        xb = data->x[data->n - 1], ya = minimum_y(data), yb = maximum_y(data);
    double ymin = (double)ya / 100, ymax = (double)yb / 100;
    Lines out = {0};
    line_add(&out, "plot %s size %dx%d x %s %s y %s %s", s->series.name, width, height, position_text(xa),
             position_text(xb), position_text(ya), position_text(yb));
    Text legend = {0};
    text_add(&legend, "legend . data");
    for (size_t m = 0; m < p->rows[15].len; ++m)
        text_add(&legend, " %zu %s", m + 1, p->rows[15].data[m]);
    line_add(&out, "%s", legend.data);
    char **rows = plot_grid(width, height);
    int columns[200];
    for (int i = 0; i < data->n; ++i) {
        int col = width * (data->x[i] - xa) / (xb - xa), row = height * (yb - data->y[i]) / (yb - ya);
        if (col == width)
            --col;
        if (row == height)
            --row;
        columns[i] = col;
        rows[row][col] = '.';
    }
    for (size_t m = 0; m < p->rows[15].len; ++m) {
        int method = method_index(methods, method_count, p->rows[15].data[m]);
        char digit = (char)('1' + m);
        for (int col = 0; col < width; ++col) {
            int position = xa + (2 * col + 1) * (xb - xa) / (2 * width);
            Optional value = estimate(&s->fits[method], position);
            if (!value.defined)
                continue;
            int row = clamped_row((double)height * (ymax - value.value) / (ymax - ymin), height);
            char cell = rows[row][col];
            rows[row][col] = cell == ' ' || cell == '.' || cell == digit ? digit : '*';
        }
    }
    extend(&out, framed(rows, width, height));
    int dots = 0, curves = 0, overlaps = 0;
    for (int row = 0; row < height; ++row)
        for (int col = 0; col < width; ++col) {
            char c = rows[row][col];
            if (c == '.')
                ++dots;
            else if (c == '*')
                ++overlaps;
            else if (c >= '1' && c <= '9')
                ++curves;
        }
    line_add(&out, "cells data %d curve %d overlap %d", dots, curves, overlaps);
    line_add(&out, "");
    const Diagnostic *d = &s->diagnostics[s->best];
    double limit = 0;
    for (int i = 0; i < data->n; ++i)
        if (fabs(d->residuals[i]) > limit)
            limit = fabs(d->residuals[i]);
    line_add(&out, "residuals %s method %s limit %s", s->series.name, methods[s->best].name, real(limit));
    rows = plot_grid(width, height);
    memset(rows[height / 2], '-', width);
    for (int i = 0; i < data->n; ++i) {
        double pi = (double)height * ((limit - d->residuals[i]) / (2 * limit));
        rows[clamped_row(pi, height)][columns[i]] = 'o';
    }
    extend(&out, framed(rows, width, height));
    line_add(&out, "");
    line_add(&out, "histogram %s method %s", s->series.name, methods[s->outlier].name);
    int counts[14] = {0};
    for (int i = 0; i < data->n; ++i)
        if (s->fits[s->outlier].leverage[i] < 1) {
            double t = s->standardized[i];
            int bin = t < -3 ? 0 : t >= 3 ? 13 : 1 + (int)((t + 3) / 0.5);
            ++counts[bin];
        }
    for (int bin = 0; bin < 14; ++bin) {
        char *lower = bin == 0 ? "-inf" : real_text(some(-3 + 0.5 * (bin - 1)), 2),
             *upper = bin == 13 ? "inf" : real_text(some(-3 + 0.5 * bin), 2);
        char *marks = allocate((size_t)counts[bin] + 1, 1);
        memset(marks, '#', counts[bin]);
        line_add(&out, "%s %s %d |%s", lower, upper, counts[bin], marks);
    }
    return out;
}
static void write(const char *name, Lines lines) {
    FILE *out = fopen(format("output/%s", name), "wb");
    if (!out)
        exit(EXIT_FAILURE);
    for (size_t i = 0; i < lines.len; ++i)
        fprintf(out, "%s\n", lines.data[i]);
    fclose(out);
}
int main(void) {
    Input *input = read_input();
    const Params *p = &input->params;
    Method methods[13] = {{0}};
    int method_count = build_methods(p, methods);
    Study *studies[3];
    for (int i = 0; i < input->series_count; ++i)
        studies[i] = study(&input->series[i], p, methods, method_count, i);
    Lines selection = {0}, fits = {0}, predictions = {0}, bands = {0}, diagnostics = {0}, isotonic = {0},
          plots = {0};
    line_add(&selection, "series,method,parameter,score,edf,selected");
    line_add(&bands, "series,method,x,fit,se,lower,upper");
    Text header = {0};
    text_add(&header, "series,x");
    for (int m = 0; m < method_count; ++m)
        text_add(&header, ",%s", methods[m].name);
    line_add(&fits, "%s", header.data);
    line_add(&predictions, "%s", header.data);
    Integer random = strtoll(p->rows[13].data[2], NULL, 10);
    int repetitions = atoi(p->rows[13].data[0]), trim = atoi(p->rows[13].data[1]);
    double z = strtod(p->rows[10].data[0], NULL);
    for (int series = 0; series < input->series_count; ++series) {
        const Study *s = studies[series];
        const Data *data = &s->series.data;
        for (int c = 0; c < s->selection_count; ++c) {
            SelectionRow row = s->selection[c];
            line_add(&selection, "%s,%s,%s,%s,%s,%d", s->series.name, methods[row.method].name,
                     methods[row.method].candidates[row.candidate].text, real_text(row.score, 4),
                     real_text(row.edf, 4), row.selected ? 1 : 0);
        }
        for (int k = 0; k < s->grid_count; ++k) {
            Text line = {0};
            text_add(&line, "%s,%s", s->series.name, position_text(s->grid[k]));
            for (int m = 0; m < method_count; ++m)
                text_add(&line, ",%s", real_text(s->estimates[m][k], 4));
            line_add(&fits, "%s", line.data);
        }
        for (size_t b = 0; b < p->rows[11].len; ++b) {
            char *name = p->rows[11].data[b];
            int m = method_index(methods, method_count, name);
            for (int k = 0; k < s->grid_count; ++k) {
                Optional value = s->estimates[m][k];
                if (!value.defined) {
                    line_add(&bands, "%s,%s,%s,NA,NA,NA,NA", s->series.name, name, position_text(s->grid[k]));
                    continue;
                }
                double se = standard_error(&s->fits[m], &s->diagnostics[m], s->grid[k]);
                line_add(&bands, "%s,%s,%s,%s,%s,%s,%s", s->series.name, name, position_text(s->grid[k]),
                         real(value.value), real(se), real(value.value - z * se), real(value.value + z * se));
            }
        }
        int m = method_index(methods, method_count, "spline");
        const Fit *spline = &s->fits[m];
        const Diagnostic *d = &s->diagnostics[m];
        double mean = sum(d->residuals, data->n) / (double)data->n, centered[200];
        for (int i = 0; i < data->n; ++i)
            centered[i] = d->residuals[i] - mean;
        double *bootstrap = allocate((size_t)s->grid_count * repetitions, sizeof *bootstrap);
        for (int b = 0; b < repetitions; ++b) {
            double sampled[200];
            for (int i = 0; i < data->n; ++i) {
                random = (48271 * random) % 2147483647;
                int index = (int)(random % data->n);
                sampled[i] = spline->fitted[i] + centered[index];
            }
            SplineValues fit = spline_fit(spline->spline, sampled);
            for (int k = 0; k < s->grid_count; ++k)
                bootstrap[(size_t)k * repetitions + b] = spline_evaluate(spline->spline, &fit, s->grid[k]);
        }
        for (int k = 0; k < s->grid_count; ++k) {
            double *values = bootstrap + (size_t)k * repetitions,
                   average = sum(values, repetitions) / (double)repetitions, total = 0;
            for (int b = 0; b < repetitions; ++b)
                total += (values[b] - average) * (values[b] - average);
            double se = sqrt(total / (double)(repetitions - 1));
            qsort(values, repetitions, sizeof *values, real_compare);
            line_add(&bands, "%s,spline_bootstrap,%s,%s,%s,%s,%s", s->series.name, position_text(s->grid[k]),
                     real_text(s->estimates[m][k], 4), real(se), real(values[trim]),
                     real(values[repetitions - trim - 1]));
        }
        if (series) {
            line_add(&diagnostics, "");
            line_add(&isotonic, "");
        }
        extend(&diagnostics, diagnostics_lines(s, p, methods, method_count));
        int iso = method_index(methods, method_count, "isotonic");
        const Fit *fit = &s->fits[iso];
        Text first = {0};
        text_add(&first, "series %s direction %s mode %s", s->series.name, fit->direction,
                 p->rows[8].data[series]);
        if (!strcmp(p->rows[8].data[series], "auto"))
            text_add(&first, " rss_increasing %s rss_decreasing %s", real(fit->increasing_rss),
                     real(fit->decreasing_rss));
        line_add(&isotonic, "%s", first.data);
        line_add(&isotonic, "blocks %d rss %s loo %s", fit->block_count, real(s->diagnostics[iso].rss),
                 real_text(s->loo[iso], 4));
        for (int b = 0; b < fit->block_count; ++b) {
            IsoBlock block = fit->blocks[b];
            line_add(&isotonic, "block %d x %s %s count %d value %s", b + 1,
                     position_text(data->x[block.first]), position_text(data->x[block.last]), block.count,
                     real((double)block.sum / (double)(100 * block.count)));
        }
    }
    for (int i = 0; i < input->test_count; ++i) {
        TestPoint point = input->tests[i];
        int s = 0;
        while (strcmp(studies[s]->series.name, point.series))
            ++s;
        Text line = {0};
        text_add(&line, "%s,%s", point.series, position_text(point.x));
        for (int m = 0; m < method_count; ++m)
            text_add(&line, ",%s", real_text(estimate(&studies[s]->fits[m], point.x), 4));
        line_add(&predictions, "%s", line.data);
    }
    for (size_t i = 0; i < p->rows[14].len; ++i) {
        if (i)
            line_add(&plots, "");
        int s = 0;
        while (strcmp(studies[s]->series.name, p->rows[14].data[i]))
            ++s;
        extend(&plots, plot_lines(studies[s], p, methods, method_count));
    }
    write("selection.csv", selection);
    write("fits.csv", fits);
    write("predictions.csv", predictions);
    write("bands.csv", bands);
    write("diagnostics.txt", diagnostics);
    write("isotonic.txt", isotonic);
    write("plots.txt", plots);
    return 0;
}
