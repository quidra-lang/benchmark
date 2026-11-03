#include "regression.h"
#include <stdarg.h>
#include <sys/stat.h>
static void write_lines(const char *name, const Lines *lines) {
    char *path = format("output/%s", name);
    FILE *file = fopen(path, "wb");
    free(path);
    if (!file)
        return;
    for (int i = 0; i < lines->count; ++i) {
        fputs(lines->data[i], file);
        fputc('\n', file);
    }
    fclose(file);
}
static void write_owned(const char *name, Lines lines) {
    write_lines(name, &lines);
    lines_free(&lines);
}
static char *number(int value) {
    return format("%d", value);
}
static char *join(const Lines *values, const char *separator) {
    char *out = text("");
    for (int i = 0; i < values->count; ++i) {
        char *next = format("%s%s%s", out, i ? separator : "", values->data[i]);
        free(out);
        out = next;
    }
    return out;
}
static Lines fields(int count, ...) {
    Lines out = {0};
    va_list args;
    va_start(args, count);
    for (int i = 0; i < count; ++i)
        line_push(&out, text(va_arg(args, const char *)));
    va_end(args);
    return out;
}
typedef struct {
    Lines fields;
    char *mark;
} TableRow;
typedef struct {
    Lines header;
    TableRow *rows;
    int count, capacity;
} Table;
static void table_add(Table *table, const char *mark, Lines row) {
    if (table->count == table->capacity) {
        table->capacity = table->capacity ? 2 * table->capacity : 16;
        table->rows = resize(table->rows, (size_t)table->capacity * sizeof(TableRow));
    }
    table->rows[table->count++] = (TableRow){row, text(mark)};
}
static char *render_row(const TableRow *row, const int *widths) {
    char *out = text("");
    for (int j = 0; j < row->fields.count; ++j) {
        char *next = j ? format("%s  %*s", out, widths[j], row->fields.data[j])
                       : format("%-*s", widths[j], row->fields.data[j]);
        free(out);
        out = next;
    }
    if (*row->mark) {
        char *next = format("%s %s", out, row->mark);
        free(out);
        out = next;
    }
    size_t length = strlen(out);
    while (length && out[length - 1] == ' ')
        out[--length] = 0;
    return out;
}
static void append_table(Lines *out, Table *table) {
    int widths[13] = {0};
    for (int j = 0; j < table->header.count; ++j)
        widths[j] = (int)strlen(table->header.data[j]);
    for (int i = 0; i < table->count; ++i)
        for (int j = 0; j < table->rows[i].fields.count; ++j) {
            int length = (int)strlen(table->rows[i].fields.data[j]);
            if (length > widths[j])
                widths[j] = length;
        }
    TableRow header = {table->header, ""};
    line_push(out, render_row(&header, widths));
    for (int i = 0; i < table->count; ++i) {
        line_push(out, render_row(&table->rows[i], widths));
        lines_free(&table->rows[i].fields);
        free(table->rows[i].mark);
    }
    lines_free(&table->header);
    free(table->rows);
    *table = (Table){0};
}
static void blank(Lines *out) {
    line_push(out, text(""));
}
typedef struct {
    int n, df;
    double sigma, tss, r2, adjusted, f, f_p, loglik, aic, bic, press, predicted, critical, quantiles[5];
} Statistics;
static int double_compare(const void *a, const void *b) {
    double x = *(const double *)a, y = *(const double *)b;
    return (x > y) - (x < y);
}
static Statistics statistics(const Vector *y, const Vector *weights, const Fit *model, const Params *p) {
    Statistics out = {.n = y->count, .df = y->count - model->rank, .f_p = 1};
    out.sigma = sqrt(model->rss / out.df);
    double weight_sum = 0, response_sum = 0, log_weights = 0;
    for (int i = 0; i < y->count; ++i) {
        weight_sum += weights->data[i];
        response_sum += weights->data[i] * y->data[i];
        log_weights += log(weights->data[i]);
    }
    double mean = response_sum / weight_sum;
    for (int i = 0; i < y->count; ++i)
        out.tss += weights->data[i] * (y->data[i] - mean) * (y->data[i] - mean);
    out.r2 = 1 - model->rss / out.tss;
    out.adjusted = 1 - (1 - out.r2) * (out.n - 1) / out.df;
    if (model->rank > 1) {
        out.f = ((out.tss - model->rss) / (model->rank - 1)) / (model->rss / out.df);
        out.f_p = p_f(out.f, model->rank - 1, out.df);
    }
    out.loglik =
        0.5 * (log_weights - out.n * (log(2 * 3.141592653589793) + 1 - log((double)out.n) + log(model->rss)));
    out.aic = -2 * out.loglik + 2 * (model->rank + 1);
    out.bic = -2 * out.loglik + log((double)out.n) * (model->rank + 1);
    for (int i = 0; i < y->count; ++i) {
        double value = model->weighted_residuals.data[i] / (1 - model->leverage.data[i]);
        out.press += value * value;
    }
    out.predicted = 1 - out.press / out.tss;
    Vector residuals = vector_new(y->count);
    memcpy(residuals.data, model->weighted_residuals.data, (size_t)y->count * sizeof(double));
    qsort(residuals.data, (size_t)residuals.count, sizeof(double), double_compare);
    for (int q = 0; q < 5; ++q) {
        double g = (out.n - 1) * ((double)q / 4);
        int k = (int)floor(g);
        out.quantiles[q] = k + 1 < out.n
                               ? residuals.data[k] + (g - k) * (residuals.data[k + 1] - residuals.data[k])
                               : residuals.data[k];
    }
    free(residuals.data);
    out.critical = t_quantile(p->confidence, out.df);
    return out;
}
static Matrix columns(const Matrix *matrix, const IntList *indices) {
    Matrix out = matrix_new(matrix->rows, indices->count);
    for (int i = 0; i < matrix->rows; ++i)
        for (int j = 0; j < indices->count; ++j)
            AT(out, i, j) = AT(*matrix, i, indices->data[j]);
    return out;
}
typedef struct {
    Fit model;
    Statistics stats;
} SubsetFit;
static SubsetFit fit_subset(const Design *design, const IntList *terms, const Params *p) {
    IntList indices = selected_columns(design, terms);
    Matrix x = columns(&design->x, &indices);
    SubsetFit out = {0};
    out.model = fit(&x, &design->y, &design->weights, p->rank_tol);
    out.stats = statistics(&design->y, &design->weights, &out.model, p);
    free(indices.data);
    free(x.data);
    return out;
}
typedef struct {
    int term, degrees;
    double ss, rss, f, p;
} Marginal;
typedef struct {
    Marginal data[20];
    int count;
} Marginals;
static Marginals marginal(const Design *design, const IntList *terms, const Fit *model,
                          const Statistics *stats, const Params *p) {
    Marginals out = {0};
    for (int i = 0; i < terms->count; ++i) {
        int term = terms->data[i];
        bool removable = true;
        for (int j = 0; j < terms->count; ++j)
            if (contained(&design->formula.terms[term], &design->formula.terms[terms->data[j]]))
                removable = false;
        if (!removable)
            continue;
        IntList remaining = {0};
        for (int j = 0; j < terms->count; ++j)
            if (terms->data[j] != term)
                int_push(&remaining, terms->data[j]);
        SubsetFit smaller = fit_subset(design, &remaining, p);
        Marginal test = {.term = term, .degrees = model->rank - smaller.model.rank, .rss = smaller.model.rss};
        test.ss = test.rss - model->rss;
        if (test.degrees > 0) {
            test.f = (test.ss / test.degrees) / (model->rss / stats->df);
            test.p = p_f(test.f, test.degrees, stats->df);
        }
        out.data[out.count++] = test;
        fit_free(&smaller.model);
        free(remaining.data);
    }
    return out;
}
static Lines data_summary(const Dataframe *data) {
    Lines out = {0};
    line_push(&out, format("Data: %d rows, %d columns", data->count, data->names.count));
    blank(&out);
    line_push(&out, text("Numeric columns:"));
    IntList numeric = {0};
    Table table = {.header = fields(7, "column", "n", "missing", "Mean", "SD", "Min", "Max")};
    for (int j = 0; j < data->names.count; ++j)
        if (!data->categorical[j]) {
            int_push(&numeric, j);
            int count = 0;
            double sum = 0, minimum = 0, maximum = 0;
            for (int i = 0; i < data->count; ++i)
                if (!data->rows[i].cells[j].missing) {
                    double value = data->rows[i].cells[j].number;
                    if (!count || value < minimum)
                        minimum = value;
                    if (!count || value > maximum)
                        maximum = value;
                    sum += value;
                    ++count;
                }
            double mean = sum / count, squares = 0;
            for (int i = 0; i < data->count; ++i)
                if (!data->rows[i].cells[j].missing) {
                    double value = data->rows[i].cells[j].number;
                    squares += (value - mean) * (value - mean);
                }
            table_add(&table, "",
                      fields(7, data->names.data[j], number(count), number(data->count - count), real(mean),
                             real(sqrt(squares / (count - 1))), real(minimum), real(maximum)));
        }
    append_table(&out, &table);
    blank(&out);
    line_push(&out, text("Categorical columns:"));
    for (int j = 0; j < data->names.count; ++j)
        if (data->categorical[j]) {
            Lines labels = {0};
            for (int i = 0; i < data->count; ++i)
                if (!data->rows[i].cells[j].missing) {
                    const char *label = data->rows[i].cells[j].label;
                    bool found = false;
                    for (int k = 0; k < labels.count; ++k)
                        if (!strcmp(labels.data[k], label))
                            found = true;
                    if (!found)
                        line_push(&labels, text(label));
                }
            for (int i = 1; i < labels.count; ++i) {
                char *value = labels.data[i];
                int k = i;
                while (k > 0 && strcmp(value, labels.data[k - 1]) < 0) {
                    labels.data[k] = labels.data[k - 1];
                    --k;
                }
                labels.data[k] = value;
            }
            int present = 0;
            Lines pairs = {0};
            for (int k = 0; k < labels.count; ++k) {
                int count = 0;
                for (int i = 0; i < data->count; ++i)
                    if (!data->rows[i].cells[j].missing &&
                        !strcmp(data->rows[i].cells[j].label, labels.data[k]))
                        ++count;
                present += count;
                line_push(&pairs, format("%s %d", labels.data[k], count));
            }
            line_push(&out, format("%s: %d values, %d missing, %d levels: %s", data->names.data[j], present,
                                   data->count - present, labels.count, join(&pairs, ", ")));
            lines_free(&labels);
            lines_free(&pairs);
        }
    blank(&out);
    line_push(&out, text("Correlations (pairwise complete observations):"));
    table = (Table){0};
    line_push(&table.header, text("column"));
    for (int i = 0; i < numeric.count; ++i)
        line_push(&table.header, text(data->names.data[numeric.data[i]]));
    for (int ai = 0; ai < numeric.count; ++ai) {
        int a = numeric.data[ai];
        Lines row = {0};
        line_push(&row, text(data->names.data[a]));
        for (int bi = 0; bi < numeric.count; ++bi) {
            int b = numeric.data[bi], count = 0;
            double sum_x = 0, sum_y = 0;
            for (int i = 0; i < data->count; ++i)
                if (!data->rows[i].cells[a].missing && !data->rows[i].cells[b].missing) {
                    sum_x += data->rows[i].cells[a].number;
                    sum_y += data->rows[i].cells[b].number;
                    ++count;
                }
            double mean_x = sum_x / count, mean_y = sum_y / count, xy = 0, xx = 0, yy = 0;
            for (int i = 0; i < data->count; ++i)
                if (!data->rows[i].cells[a].missing && !data->rows[i].cells[b].missing) {
                    double x = data->rows[i].cells[a].number - mean_x,
                           y = data->rows[i].cells[b].number - mean_y;
                    xy += x * y;
                    xx += x * x;
                    yy += y * y;
                }
            line_push(&row, real(xy / sqrt(xx * yy)));
        }
        table_add(&table, "", row);
    }
    append_table(&out, &table);
    free(numeric.data);
    blank(&out);
    return out;
}
typedef struct {
    Design *design;
    Fit fit_;
    Statistics stats;
    Diagnostics diag;
    IntList terms;
    Marginals drops;
    int predicted, with_actual, covered;
    double error_squares;
} Model;
static Lines model_summary(Model *model, const Input *input, int index) {
    const Design *design = model->design;
    const Fit *fit_ = &model->fit_;
    const Statistics *stats = &model->stats;
    const Diagnostics *diag = &model->diag;
    int n = design->y.count, rank = fit_->rank;
    Lines terms = {0}, aliases = {0}, out = {0};
    for (int t = 0; t < design->formula.count; ++t)
        line_push(&terms, text(design->formula.terms[t].name));
    for (int j = 0; j < design->count; ++j)
        if (fit_->alias[j])
            line_push(&aliases, text(design->columns[j].name));
    line_push(&out, format("Model %d: %s", index, design->formula.raw));
    line_push(&out, format("Terms: %s", join(&terms, ", ")));
    line_push(&out,
              format("Weights: %s",
                     design->formula.weight < 0 ? "none" : input->data.names.data[design->formula.weight]));
    line_push(&out, format("Observations: %d used, %d dropped", n, input->data.count - n));
    line_push(&out, format("Columns: %d, rank %d, aliased: %s", design->count, rank,
                           aliases.count ? join(&aliases, ", ") : "none"));
    lines_free(&terms);
    lines_free(&aliases);
    blank(&out);
    line_push(&out, format("Residuals: Min %s, 1Q %s, Median %s, 3Q %s, Max %s", real(stats->quantiles[0]),
                           real(stats->quantiles[1]), real(stats->quantiles[2]), real(stats->quantiles[3]),
                           real(stats->quantiles[4])));
    blank(&out);
    line_push(&out, text("Coefficients:"));
    double standard_errors[20] = {0}, robust[20] = {0};
    for (int k = 0; k < rank; ++k) {
        int j = fit_->accepted.data[k];
        standard_errors[j] = stats->sigma * sqrt(fit_->variance.data[k]);
        double sum = 0;
        for (int i = 0; i < n; ++i) {
            double h = fit_->leverage.data[i], eps = fit_->weighted_residuals.data[i],
                   omega = eps * eps / ((1 - h) * (1 - h));
            sum += omega * AT(fit_->g, i, k) * AT(fit_->g, i, k);
        }
        robust[j] = sqrt(sum);
    }
    Table table = {.header = fields(5, "term", "Estimate", "Std. Error", "t value", "Pr(>|t|)")};
    for (int j = 0; j < design->count; ++j) {
        if (fit_->alias[j])
            table_add(&table, "", fields(5, design->columns[j].name, "NA", "NA", "NA", "NA"));
        else {
            double t = fit_->coefficients.data[j] / standard_errors[j], p = p_t(t, stats->df);
            table_add(&table, significance(p),
                      fields(5, design->columns[j].name, real(fit_->coefficients.data[j]),
                             real(standard_errors[j]), real(t), p_format(p)));
        }
    }
    append_table(&out, &table);
    line_push(&out, text("---"));
    line_push(&out, text("Signif. codes: 0 '***' 0.001 '**' 0.01 '*' 0.05 '.' 0.1 ' ' 1"));
    blank(&out);
    line_push(&out,
              format("Residual standard error: %s on %d degrees of freedom", real(stats->sigma), stats->df));
    line_push(&out, format("Multiple R-squared: %s, Adjusted R-squared: %s", real(stats->r2),
                           real(stats->adjusted)));
    line_push(&out, format("F-statistic: %s on %d and %d DF, p-value: %s", real(stats->f), rank - 1,
                           stats->df, p_format(stats->f_p)));
    line_push(&out, format("Log-likelihood: %s, AIC: %s, BIC: %s", real(stats->loglik), real(stats->aic),
                           real(stats->bic)));
    line_push(&out, format("PRESS: %s, Predicted R-squared: %s", real(stats->press), real(stats->predicted)));
    blank(&out);
    line_push(&out, format("Confidence intervals (level %s, t %s):", real(input->params.confidence),
                           real(stats->critical)));
    table = (Table){.header = fields(3, "term", "Lower", "Upper")};
    for (int j = 0; j < design->count; ++j)
        table_add(
            &table, "",
            fields(3, design->columns[j].name,
                   fit_->alias[j] ? "NA"
                                  : real(fit_->coefficients.data[j] - stats->critical * standard_errors[j]),
                   fit_->alias[j] ? "NA"
                                  : real(fit_->coefficients.data[j] + stats->critical * standard_errors[j])));
    append_table(&out, &table);
    blank(&out);
    line_push(&out, text("Robust standard errors (HC3):"));
    table = (Table){.header = fields(4, "term", "Std. Error", "t value", "Pr(>|t|)")};
    for (int j = 0; j < design->count; ++j) {
        if (fit_->alias[j])
            table_add(&table, "", fields(4, design->columns[j].name, "NA", "NA", "NA"));
        else {
            double t = fit_->coefficients.data[j] / robust[j], p = p_t(t, stats->df);
            table_add(&table, significance(p),
                      fields(4, design->columns[j].name, real(robust[j]), real(t), p_format(p)));
        }
    }
    append_table(&out, &table);
    blank(&out);
    line_push(&out, text("Analysis of variance (sequential):"));
    table = (Table){.header = fields(6, "term", "Df", "Sum Sq", "Mean Sq", "F value", "Pr(>F)")};
    for (int term = 0; term < design->formula.count; ++term) {
        int degrees = 0;
        double sum = 0;
        for (int k = 0; k < rank; ++k)
            if (design->columns[fit_->accepted.data[k]].term == term) {
                ++degrees;
                sum += fit_->effects.data[k] * fit_->effects.data[k];
            }
        if (!degrees)
            continue;
        double mean = sum / degrees, f = mean / (fit_->rss / stats->df), p = p_f(f, degrees, stats->df);
        table_add(&table, significance(p),
                  fields(6, design->formula.terms[term].name, number(degrees), real(sum), real(mean), real(f),
                         p_format(p)));
    }
    table_add(&table, "",
              fields(4, "Residuals", number(stats->df), real(fit_->rss), real(fit_->rss / stats->df)));
    append_table(&out, &table);
    blank(&out);
    line_push(&out, text("Marginal F tests (drop one term):"));
    table = (Table){.header = fields(6, "term", "Df", "Sum Sq", "RSS", "F value", "Pr(>F)")};
    for (int i = 0; i < model->drops.count; ++i) {
        Marginal drop = model->drops.data[i];
        table_add(&table, drop.degrees ? significance(drop.p) : "",
                  fields(6, design->formula.terms[drop.term].name, number(drop.degrees), real(drop.ss),
                         real(drop.rss), drop.degrees ? real(drop.f) : "NA",
                         drop.degrees ? p_format(drop.p) : "NA"));
    }
    append_table(&out, &table);
    blank(&out);
    line_push(&out, text("Variance inflation factors:"));
    table = (Table){.header = fields(2, "column", "VIF")};
    for (int k = 1; k < rank; ++k) {
        int target = fit_->accepted.data[k];
        IntList other = {0};
        for (int j = 0; j < rank; ++j)
            if (fit_->accepted.data[j] != target)
                int_push(&other, fit_->accepted.data[j]);
        Vector response = vector_new(n);
        double weighted_sum = 0, weight_sum = 0;
        for (int i = 0; i < n; ++i) {
            response.data[i] = AT(design->x, i, target);
            weighted_sum += design->weights.data[i] * response.data[i];
            weight_sum += design->weights.data[i];
        }
        Matrix x = columns(&design->x, &other);
        Fit auxiliary = fit(&x, &response, &design->weights, input->params.rank_tol);
        double mean = weighted_sum / weight_sum, tss = 0;
        for (int i = 0; i < n; ++i)
            tss += design->weights.data[i] * (response.data[i] - mean) * (response.data[i] - mean);
        double r2 = 1 - auxiliary.rss / tss, vif = 1 / (1 - r2);
        table_add(&table, vif > input->params.vif ? "high" : "",
                  fields(2, design->columns[target].name, real(vif)));
        free(other.data);
        free(response.data);
        free(x.data);
        fit_free(&auxiliary);
    }
    append_table(&out, &table);
    blank(&out);
    line_push(&out, text("Diagnostics:"));
    line_push(&out, format("Durbin-Watson: %s (%s)", real(diag->durbin),
                           diag->durbin < input->params.durbin       ? "positive autocorrelation"
                           : diag->durbin > 4 - input->params.durbin ? "negative autocorrelation"
                                                                     : "no autocorrelation"));
    line_push(&out, format("Breusch-Pagan: %s on %d DF, p-value: %s (%s)", real(diag->bp), diag->bp_df,
                           p_format(diag->bp_p),
                           diag->bp_p < input->params.breusch ? "heteroscedastic" : "homoscedastic"));
    line_push(&out, format("Jarque-Bera: %s on 2 DF, p-value: %s, skewness %s, kurtosis %s (%s)",
                           real(diag->jb), p_format(diag->jb_p), real(diag->skewness), real(diag->kurtosis),
                           diag->jb_p < input->params.normality ? "non-normal" : "normal"));
    Matrix augmented = matrix_new(n, rank + 2);
    for (int i = 0; i < n; ++i) {
        for (int k = 0; k < rank; ++k)
            AT(augmented, i, k) = AT(design->x, i, fit_->accepted.data[k]);
        AT(augmented, i, rank) = fit_->fitted.data[i] * fit_->fitted.data[i];
        AT(augmented, i, rank + 1) = fit_->fitted.data[i] * fit_->fitted.data[i] * fit_->fitted.data[i];
    }
    Fit reset = fit(&augmented, &design->y, &design->weights, input->params.rank_tol);
    int q = reset.rank - rank, df = n - reset.rank;
    double reset_f = ((fit_->rss - reset.rss) / q) / (reset.rss / df);
    line_push(&out, format("RESET (powers 2 and 3): F %s on %d and %d DF, p-value: %s", real(reset_f), q, df,
                           p_format(p_f(reset_f, q, df))));
    free(augmented.data);
    fit_free(&reset);
    int outlier = 0;
    for (int i = 1; i < n; ++i)
        if (fabs(diag->studentized.data[i]) > fabs(diag->studentized.data[outlier]))
            outlier = i;
    double unadjusted = p_t(diag->studentized.data[outlier], stats->df - 1), adjusted = n * unadjusted;
    if (adjusted > 1)
        adjusted = 1;
    line_push(&out,
              format("Outlier test: row %d, studentized %s, unadjusted p-value: %s, Bonferroni p-value: %s",
                     design->used.data[outlier] + 1, real(diag->studentized.data[outlier]),
                     p_format(unadjusted), p_format(adjusted)));
    line_push(&out, format("Flagged rows: leverage %d, outlier %d, cooks %d, dffits %d, any %d",
                           diag->flag_counts[0], diag->flag_counts[1], diag->flag_counts[2],
                           diag->flag_counts[3], diag->any));
    line_push(&out, text("Largest Cook's distances:"));
    int order[400];
    for (int i = 0; i < n; ++i) {
        int j = i;
        while (j > 0 && diag->cooks.data[i] > diag->cooks.data[order[j - 1]]) {
            order[j] = order[j - 1];
            --j;
        }
        order[j] = i;
    }
    for (int j = 0; j < 3 && j < n; ++j) {
        int i = order[j];
        line_push(&out,
                  format("row %d: cooks_d %s, leverage %s, studentized %s, flags %s",
                         design->used.data[i] + 1, real(diag->cooks.data[i]), real(fit_->leverage.data[i]),
                         real(diag->studentized.data[i]), diag->flags.data[i]));
    }
    line_push(&out, text("Largest absolute DFBETAS:"));
    table = (Table){.header = fields(3, "column", "row", "DFBETAS")};
    for (int k = 0; k < rank; ++k) {
        int largest = 0;
        for (int i = 1; i < n; ++i)
            if (fabs(AT(diag->dfbetas, i, k)) > fabs(AT(diag->dfbetas, largest, k)))
                largest = i;
        table_add(&table, "",
                  fields(3, design->columns[fit_->accepted.data[k]].name,
                         number(design->used.data[largest] + 1), real(AT(diag->dfbetas, largest, k))));
    }
    append_table(&out, &table);
    return out;
}
static Lines prediction_lines(Model *model, const Dataframe *prediction, int index) {
    Lines out = {0};
    const Fit *fit_ = &model->fit_;
    const Statistics *stats = &model->stats;
    for (int i = 0; i < prediction->count; ++i) {
        const Record *record = &prediction->rows[i];
        if (!predictable(model->design, record)) {
            line_push(&out, format("%d,%d,NA,NA,NA,NA,NA,NA,NA,NA,NA", index, i + 1));
            continue;
        }
        ++model->predicted;
        Vector values = record_values(model->design->columns, model->design->count, record);
        double value = 0;
        for (int k = 0; k < fit_->rank; ++k)
            value += values.data[fit_->accepted.data[k]] * fit_->coefficients.data[fit_->accepted.data[k]];
        double squares = 0;
        for (int k = 0; k < fit_->rank; ++k) {
            double sum = 0;
            for (int m = 0; m < fit_->rank; ++m)
                sum += values.data[fit_->accepted.data[m]] * AT(fit_->inverse, m, k);
            squares += sum * sum;
        }
        free(values.data);
        double se = stats->sigma * sqrt(squares), confidence = stats->critical * se,
               interval = stats->critical * sqrt(stats->sigma * stats->sigma + se * se);
        char *line =
            format("%d,%d,%s,%s,%s,%s,%s,%s", index, i + 1, real(value), real(se), real(value - confidence),
                   real(value + confidence), real(value - interval), real(value + interval));
        if (record->cells[model->design->formula.response].missing) {
            line_push(&out, format("%s,NA,NA,NA", line));
        } else {
            ++model->with_actual;
            double actual = record->cells[model->design->formula.response].number, error = actual - value;
            bool covered = value - interval <= actual && actual <= value + interval;
            model->covered += covered;
            model->error_squares += error * error;
            line_push(&out, format("%s,%s,%s,%s", line, real(actual), real(error), covered ? "yes" : "no"));
        }
        free(line);
    }
    return out;
}
static IntList copy_terms(const IntList *terms) {
    IntList out = {0};
    for (int i = 0; i < terms->count; ++i)
        int_push(&out, terms->data[i]);
    return out;
}
static Lines selection(const Model *model, const Input *input) {
    const Design *design = model->design;
    const Params *p = &input->params;
    IntList terms = copy_terms(&model->terms);
    Lines out = {0};
    line_push(&out,
              format("Backward elimination (model 1, alpha %s, rows %d)", real(p->alpha), design->y.count));
    int step = 1;
    while (true) {
        SubsetFit current = fit_subset(design, &terms, p);
        line_push(&out, format("Step %d: %s (RSS %s, df %d, AIC %s)", step,
                               formula_text(&design->formula, &terms, &input->data), real(current.model.rss),
                               current.stats.df, real(current.stats.aic)));
        if (!terms.count) {
            line_push(&out, text("  stop: no removable terms"));
            fit_free(&current.model);
            break;
        }
        Marginals drops = marginal(design, &terms, &current.model, &current.stats, p);
        int selected = -1;
        double largest = -1;
        for (int i = 0; i < drops.count; ++i) {
            Marginal drop = drops.data[i];
            line_push(&out, format("  - %s: F %s on %d and %d DF, p-value %s",
                                   design->formula.terms[drop.term].name, real(drop.f), drop.degrees,
                                   current.stats.df, p_format(drop.p)));
            if (drop.p > largest) {
                largest = drop.p;
                selected = drop.term;
            }
        }
        fit_free(&current.model);
        if (largest > p->alpha) {
            line_push(&out, format("  remove %s", design->formula.terms[selected].name));
            int count = 0;
            for (int i = 0; i < terms.count; ++i)
                if (terms.data[i] != selected)
                    terms.data[count++] = terms.data[i];
            terms.count = count;
            ++step;
        } else {
            line_push(&out, format("  stop: largest p-value %s is not above %s", p_format(largest),
                                   real(p->alpha)));
            break;
        }
    }
    line_push(&out, format("Final model: %s", formula_text(&design->formula, &terms, &input->data)));
    blank(&out);
    line_push(&out, format("Forward selection by AIC (model 1, rows %d)", design->y.count));
    terms.count = 0;
    step = 1;
    while (true) {
        SubsetFit current = fit_subset(design, &terms, p);
        line_push(&out,
                  format("Step %d: %s (AIC %s)", step, formula_text(&design->formula, &terms, &input->data),
                         real(current.stats.aic)));
        IntList candidates = {0};
        for (int term = 0; term < design->formula.count; ++term)
            if (!int_contains(&terms, term)) {
                bool eligible = true;
                for (int other = 0; other < design->formula.count; ++other)
                    if (contained(&design->formula.terms[other], &design->formula.terms[term]) &&
                        !int_contains(&terms, other))
                        eligible = false;
                if (eligible)
                    int_push(&candidates, term);
            }
        if (!candidates.count) {
            line_push(&out, text("  stop: no candidate terms remain"));
            fit_free(&current.model);
            free(candidates.data);
            break;
        }
        int selected = -1;
        double smallest = 0;
        for (int i = 0; i < candidates.count; ++i) {
            int candidate = candidates.data[i];
            IntList trial = copy_terms(&terms);
            int_push(&trial, candidate);
            int_sort(&trial);
            SubsetFit fitted = fit_subset(design, &trial, p);
            double aic = fitted.stats.aic;
            line_push(&out, format("  + %s: AIC %s", design->formula.terms[candidate].name, real(aic)));
            if (selected < 0 || aic < smallest) {
                selected = candidate;
                smallest = aic;
            }
            fit_free(&fitted.model);
            free(trial.data);
        }
        free(candidates.data);
        double aic = current.stats.aic;
        fit_free(&current.model);
        if (smallest < aic) {
            line_push(&out, format("  add %s", design->formula.terms[selected].name));
            int_push(&terms, selected);
            int_sort(&terms);
            ++step;
        } else {
            line_push(&out, text("  stop: no candidate lowers the AIC"));
            break;
        }
    }
    line_push(&out, format("Final model: %s", formula_text(&design->formula, &terms, &input->data)));
    free(terms.data);
    typedef struct {
        int mask, rank;
        IntList terms;
        double bic, aic;
    } Candidate;
    Candidate *candidates = calloc((size_t)(1 << design->formula.count), sizeof(Candidate));
    int candidate_count = 0;
    for (int mask = 0; mask < (1 << design->formula.count); ++mask) {
        IntList included = {0};
        for (int term = 0; term < design->formula.count; ++term)
            if (mask & (1 << term))
                int_push(&included, term);
        bool hierarchical = true;
        for (int i = 0; i < included.count; ++i)
            for (int other = 0; other < design->formula.count; ++other)
                if (contained(&design->formula.terms[other], &design->formula.terms[included.data[i]]) &&
                    !(mask & (1 << other)))
                    hierarchical = false;
        if (!hierarchical) {
            free(included.data);
            continue;
        }
        SubsetFit fitted = fit_subset(design, &included, p);
        Candidate candidate = {mask, fitted.model.rank, included, fitted.stats.bic, fitted.stats.aic};
        fit_free(&fitted.model);
        int position = candidate_count;
        while (position > 0 &&
               (candidate.bic < candidates[position - 1].bic ||
                (candidate.bic == candidates[position - 1].bic && mask < candidates[position - 1].mask))) {
            candidates[position] = candidates[position - 1];
            --position;
        }
        candidates[position] = candidate;
        ++candidate_count;
    }
    blank(&out);
    line_push(&out,
              format("Best subsets by BIC (model 1, rows %d, subsets %d)", design->y.count, candidate_count));
    for (int i = 0; i < p->best_subsets && i < candidate_count; ++i) {
        const Candidate *candidate = &candidates[i];
        line_push(&out,
                  format("%d. BIC %s, AIC %s, rank %d: %s", i + 1, real(candidate->bic), real(candidate->aic),
                         candidate->rank, formula_text(&design->formula, &candidate->terms, &input->data)));
    }
    for (int i = 0; i < candidate_count; ++i)
        free(candidates[i].terms.data);
    free(candidates);
    return out;
}
typedef struct {
    int *counts, *rows;
} Plot;
static Plot count_plot(const Vector *horizontal, const Vector *vertical, double low, double high,
                       const Params *p) {
    Plot out = {calloc((size_t)p->plot_height * (size_t)p->plot_width, sizeof(int)),
                calloc((size_t)p->plot_height, sizeof(int))};
    for (int i = 0; i < horizontal->count; ++i) {
        int column = (int)floor((horizontal->data[i] - low) / (high - low) * p->plot_width);
        if (column > p->plot_width - 1)
            column = p->plot_width - 1;
        int row = (int)floor((p->plot_limit - vertical->data[i]) / (2 * p->plot_limit) * p->plot_height);
        if (row < 0)
            row = 0;
        if (row >= p->plot_height)
            row = p->plot_height - 1;
        ++out.counts[row * p->plot_width + column];
        ++out.rows[row];
    }
    return out;
}
static void append_frame(Lines *out, const Plot *plot, const Params *p) {
    char *border = resize(NULL, (size_t)p->plot_width + 3);
    border[0] = '+';
    memset(border + 1, '-', (size_t)p->plot_width);
    border[p->plot_width + 1] = '+';
    border[p->plot_width + 2] = 0;
    line_push(out, text(border));
    for (int row = 0; row < p->plot_height; ++row) {
        char *line = resize(NULL, (size_t)p->plot_width + 3);
        line[0] = '|';
        for (int column = 0; column < p->plot_width; ++column) {
            int count = plot->counts[row * p->plot_width + column];
            line[column + 1] = count >= 10                 ? '*'
                               : count > 0                 ? (char)('0' + count)
                               : row == p->plot_height / 2 ? '-'
                                                           : '.';
        }
        line[p->plot_width + 1] = '|';
        line[p->plot_width + 2] = 0;
        line_push(out, line);
    }
    line_push(out, border);
}
static Lines residual_plots(const Model *models, int count, const Params *p) {
    Lines out = {0};
    for (int index = 0; index < count; ++index) {
        if (index)
            blank(&out);
        const Model *model = &models[index];
        double low = model->fit_.fitted.data[0], high = low, max_h = 0;
        for (int i = 0; i < model->design->y.count; ++i) {
            double value = model->fit_.fitted.data[i];
            if (value < low)
                low = value;
            if (value > high)
                high = value;
            if (model->fit_.leverage.data[i] > max_h)
                max_h = model->fit_.leverage.data[i];
        }
        line_push(&out, format("Model %d: studentized residuals vs fitted values", index + 1));
        line_push(&out, format("fitted %s to %s, studentized %s to %s", real(low), real(high),
                               real(-p->plot_limit), real(p->plot_limit)));
        Plot plot = count_plot(&model->fit_.fitted, &model->diag.studentized, low, high, p);
        append_frame(&out, &plot, p);
        int above = 0, below = 0, outside = 0;
        for (int i = 0; i < model->diag.studentized.count; ++i) {
            double value = model->diag.studentized.data[i];
            above += value > 2;
            below += value < -2;
            outside += fabs(value) > p->plot_limit;
        }
        line_push(&out, format("points: %d, above +2: %d, below -2: %d, outside range: %d",
                               model->design->y.count, above, below, outside));
        line_push(&out, text("Histogram of studentized residuals:"));
        int maximum = 0;
        for (int row = 0; row < p->plot_height; ++row)
            if (plot.rows[row] > maximum)
                maximum = plot.rows[row];
        for (int row = 0; row < p->plot_height; ++row) {
            int length = (plot.rows[row] * 40 + maximum - 1) / maximum;
            char *line =
                format("%s to %s: %d", real(p->plot_limit - 2 * p->plot_limit * (row + 1) / p->plot_height),
                       real(p->plot_limit - 2 * p->plot_limit * row / p->plot_height), plot.rows[row]);
            if (length) {
                char *bar = resize(NULL, (size_t)length + 1);
                memset(bar, '#', (size_t)length);
                bar[length] = 0;
                line_push(&out, format("%s %s", line, bar));
                free(line);
                free(bar);
            } else
                line_push(&out, line);
        }
        free(plot.counts);
        free(plot.rows);
        line_push(&out, format("Model %d: studentized residuals vs leverage", index + 1));
        line_push(&out, format("leverage 0.0000 to %s, studentized %s to %s", real(max_h),
                               real(-p->plot_limit), real(p->plot_limit)));
        plot = count_plot(&model->fit_.leverage, &model->diag.studentized, 0, max_h, p);
        append_frame(&out, &plot, p);
        free(plot.counts);
        free(plot.rows);
    }
    return out;
}
static void design_free(Design *design) {
    for (int j = 0; j < design->count; ++j) {
        free(design->columns[j].name);
        for (int k = 0; k < design->columns[j].count; ++k)
            free(design->columns[j].components[k].name);
    }
    for (int j = 0; j < 12; ++j)
        lines_free(&design->levels[j]);
    for (int t = 0; t < design->formula.count; ++t) {
        for (int f = 0; f < design->formula.terms[t].count; ++f)
            free(design->formula.terms[t].factors[f].name);
        free(design->formula.terms[t].name);
    }
    free(design->formula.terms);
    free(design->formula.raw);
    free(design->used.data);
    free(design->x.data);
    free(design->y.data);
    free(design->weights.data);
    free(design);
}
int main(void) {
    mkdir("output", 0777);
    Input *input = read_input();
    int count = input->formulas.count;
    Model *models = calloc((size_t)count, sizeof(Model));
    for (int i = 0; i < count; ++i) {
        Model *model = &models[i];
        model->design = build_design(parse_formula(input->formulas.data[i], &input->data), &input->data);
        model->fit_ =
            fit(&model->design->x, &model->design->y, &model->design->weights, input->params.rank_tol);
        model->stats = statistics(&model->design->y, &model->design->weights, &model->fit_, &input->params);
        model->diag = diagnostics(&model->design->x, &model->design->weights, &model->fit_, &input->params);
        for (int t = 0; t < model->design->formula.count; ++t)
            int_push(&model->terms, t);
        model->drops = marginal(model->design, &model->terms, &model->fit_, &model->stats, &input->params);
    }
    Lines summary = data_summary(&input->data), diagnostic_lines = {0}, prediction = {0};
    line_push(&diagnostic_lines, text("model,row,fitted,residual,leverage,studentized,cooks_d,dffits,flags"));
    line_push(&prediction,
              text("model,row,fit,se_fit,conf_lower,conf_upper,pred_lower,pred_upper,actual,error,covered"));
    for (int i = 0; i < count; ++i) {
        Model *model = &models[i];
        if (i)
            blank(&summary);
        Lines part = model_summary(model, input, i + 1);
        lines_extend(&summary, &part);
        lines_free(&part);
        part = prediction_lines(model, &input->prediction, i + 1);
        lines_extend(&prediction, &part);
        lines_free(&part);
        for (int row = 0; row < model->design->y.count; ++row)
            line_push(&diagnostic_lines,
                      format("%d,%d,%s,%s,%s,%s,%s,%s,%s", i + 1, model->design->used.data[row] + 1,
                             real(model->fit_.fitted.data[row]), real(model->fit_.residuals.data[row]),
                             real(model->fit_.leverage.data[row]), real(model->diag.studentized.data[row]),
                             real(model->diag.cooks.data[row]), real(model->diag.dffits.data[row]),
                             model->diag.flags.data[row]));
    }
    blank(&summary);
    line_push(&summary, text("Model comparison:"));
    Table table = {.header = fields(9, "model", "n", "rank", "sigma", "R-squared", "Adj. R-squared",
                                    "Pred. R-squared", "AIC", "BIC")};
    for (int i = 0; i < count; ++i) {
        const Model *model = &models[i];
        table_add(&table, "",
                  fields(9, number(i + 1), number(model->design->y.count), number(model->fit_.rank),
                         real(model->stats.sigma), real(model->stats.r2), real(model->stats.adjusted),
                         real(model->stats.predicted), real(model->stats.aic), real(model->stats.bic)));
    }
    append_table(&summary, &table);
    blank(&summary);
    line_push(&summary, text("Prediction check:"));
    for (int i = 0; i < count; ++i) {
        const Model *model = &models[i];
        line_push(
            &summary,
            format("model %d: %d predicted, %d with actual values, RMSE %s, inside prediction interval %d",
                   i + 1, model->predicted, model->with_actual,
                   model->with_actual ? real(sqrt(model->error_squares / model->with_actual)) : "NA",
                   model->covered));
    }
    write_owned("summary.txt", summary);
    write_owned("diagnostics.csv", diagnostic_lines);
    write_owned("selection.txt", selection(&models[0], input));
    write_owned("predictions.csv", prediction);
    write_owned("residual_plot.txt", residual_plots(models, count, &input->params));
    for (int i = 0; i < count; ++i) {
        diagnostics_free(&models[i].diag);
        fit_free(&models[i].fit_);
        free(models[i].terms.data);
        design_free(models[i].design);
    }
    free(models);
    for (int i = 0; i < input->data.count; ++i)
        for (int j = 0; j < input->data.names.count; ++j)
            free(input->data.rows[i].cells[j].label);
    for (int i = 0; i < input->prediction.count; ++i)
        for (int j = 0; j < input->data.names.count; ++j)
            free(input->prediction.rows[i].cells[j].label);
    free(input->data.rows);
    free(input->prediction.rows);
    lines_free(&input->data.names);
    lines_free(&input->formulas);
    free(input);
    return 0;
}
