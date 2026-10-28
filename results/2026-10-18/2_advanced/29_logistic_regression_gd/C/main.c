#include "regression.h"
#include <stdarg.h>
static void emit(FILE *out, const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    vfprintf(out, pattern, args);
    va_end(args);
    fputc('\n', out);
}
static char *r4(double value) {
    return real(value, 4);
}
static char *r6(double value) {
    return real(value, 6);
}
static Targets sequence(int size) {
    Targets ids = {.count = size};
    for (int i = 0; i < size; ++i)
        ids.values[i] = i;
    return ids;
}
static Matrix subset_matrix(const Matrix *data, Targets ids) {
    Matrix result = {.rows = ids.count, .columns = data->columns};
    for (int i = 0; i < ids.count; ++i)
        memcpy(result.values[i], data->values[ids.values[i]], (size_t)data->columns * sizeof(double));
    return result;
}
static Targets subset_targets(Targets targets, Targets ids) {
    Targets result = {.count = ids.count};
    for (int i = 0; i < ids.count; ++i)
        result.values[i] = targets.values[ids.values[i]];
    return result;
}
static Targets score_order(Scores scores, bool descending) {
    Targets result = {.count = scores.count};
    for (int i = 0; i < scores.count; ++i) {
        int at = i;
        while (at && (descending ? scores.values[i] > scores.values[result.values[at - 1]]
                                 : scores.values[i] < scores.values[result.values[at - 1]])) {
            result.values[at] = result.values[at - 1];
            --at;
        }
        result.values[at] = i;
    }
    return result;
}
static Square inverse(Square matrix) {
    Square lower = cholesky(matrix), result = {.size = matrix.size};
    for (int k = 0; k < matrix.size; ++k) {
        Vector basis = {.count = matrix.size};
        basis.values[k] = 1;
        Vector column = solve(lower, basis);
        for (int j = 0; j < matrix.size; ++j)
            result.values[j][k] = column.values[j];
    }
    return result;
}
static int correct(Scores scores, const Targets *targets, double threshold) {
    Confusion c = confusion(scores, targets, threshold);
    return (int)(c.tp + c.tn);
}
typedef struct {
    double folds[5], loss;
    Scores probabilities;
    int errors;
} CrossValidation;
typedef struct {
    Square covariance;
    Scores probabilities, leverage, residual, cook;
    double edf, deviance, aic, bic;
} Influence;
static Influence influence(Vector weights, const Matrix *data, const Targets *targets, double lambda) {
    Influence fit = {0};
    fit.covariance = inverse(hessian(weights, data, lambda));
    fit.probabilities = probabilities(weights, data);
    fit.leverage.count = fit.residual.count = fit.cook.count = data->rows;
    for (int i = 0; i < data->rows; ++i) {
        double pi = fit.probabilities.values[i], v = pi * (1 - pi), q = 0;
        for (int j = 0; j < weights.count; ++j)
            for (int k = 0; k < weights.count; ++k)
                q += data->values[i][j] * fit.covariance.values[j][k] * data->values[i][k];
        double h = v * q / (double)data->rows, e = (targets->values[i] - pi) / sqrt(v), t = e / sqrt(1 - h),
               cook = e * e * h / ((double)weights.count * ((1 - h) * (1 - h)));
        fit.leverage.values[i] = h;
        fit.residual.values[i] = t;
        fit.cook.values[i] = cook;
        fit.edf += h;
    }
    fit.deviance = 2 * (double)data->rows * average_loss(weights, data, targets);
    fit.aic = fit.deviance + 2 * fit.edf;
    fit.bic = fit.deviance + log((double)data->rows) * fit.edf;
    return fit;
}
typedef struct {
    const char *name;
    Trace checkpoints;
    Vector weights;
    Scores train_probabilities, test_probabilities;
} Model;
typedef struct {
    int counts[10], hits[10], groups;
    double sums[10], ece, mce, hl;
} Calibration;
static Calibration calibration(Scores scores, const Targets *targets) {
    Calibration table = {0};
    for (int i = 0; i < scores.count; ++i) {
        int bin = (int)floor(scores.values[i] * 10);
        if (bin > 9)
            bin = 9;
        ++table.counts[bin];
        table.hits[bin] += targets->values[i];
        table.sums[bin] += scores.values[i];
    }
    for (int bin = 0; bin < 10; ++bin)
        if (table.counts[bin]) {
            ++table.groups;
            double sum = table.sums[bin], count = table.counts[bin], observed = table.hits[bin];
            table.ece += fabs(sum - observed);
            table.mce = fmax(table.mce, fabs(sum / count - observed / count));
            table.hl += (observed - sum) * (observed - sum) / (sum * (1 - sum / count));
        }
    table.ece /= (double)scores.count;
    return table;
}
static char *bin_range(int bin) {
    char *text = malloc(16);
    if (bin == 9)
        strcpy(text, "0.9-1.0");
    else
        snprintf(text, 16, "0.%d-0.%d", bin, bin + 1);
    return text;
}
static Table train, test;
static Params p;
static Features features;
static Statistics stats;
static Matrix train_expanded, test_expanded, x, z;
static Targets y, yt, class_train, class_test;
static int n, m, q, classes, selected, one_se, soft_correct;
static double lambda, se;
static CrossValidation validations[8];
static Model models[3];
static SoftTrace soft_checkpoints;
static SoftWeights soft_weights;
static SoftPoint soft_points[150];
static Influence fit;
static CrossValidation cross_validate(double coefficient, int count) {
    CrossValidation result = {0};
    result.probabilities.count = n;
    double losses[300];
    for (int fold = 0; fold < 5; ++fold) {
        Targets training = {0}, validation = {0};
        for (int i = 0; i < n; ++i) {
            Targets *ids = i % 5 == fold ? &validation : &training;
            ids->values[ids->count++] = i;
        }
        Matrix raw = subset_matrix(&train_expanded, training);
        Statistics fold_stats = statistics(&raw, count);
        Matrix tx = standardize(&raw, &fold_stats, count), vr = subset_matrix(&train_expanded, validation),
               vx = standardize(&vr, &fold_stats, count);
        Targets targets = subset_targets(y, training);
        Trace trace = newton(&tx, &targets, coefficient);
        Vector weights = trace.points[trace.count - 1].weights;
        double total = 0;
        for (int j = 0; j < validation.count; ++j) {
            int id = validation.values[j];
            double u = score(weights, vx.values[j]);
            losses[id] = logistic_loss(u, y.values[id]);
            result.probabilities.values[id] = sigmoid(u);
            total += losses[id];
            if ((result.probabilities.values[id] >= p.threshold) != y.values[id])
                ++result.errors;
        }
        result.folds[fold] = total / (double)validation.count;
    }
    double total = 0;
    for (int i = 0; i < n; ++i)
        total += losses[i];
    result.loss = total / (double)n;
    return result;
}
static Vector trained_newton(const Matrix *data, const Targets *targets, double coefficient) {
    Trace trace = newton(data, targets, coefficient);
    return trace.points[trace.count - 1].weights;
}
static Vector original(Vector weights) {
    Vector result = {.count = weights.count};
    double total = 0;
    for (int j = 1; j < weights.count; ++j) {
        result.values[j] = weights.values[j] / stats.deviation[j - 1];
        total += result.values[j] * stats.mean[j - 1];
    }
    result.values[0] = weights.values[0] - total;
    return result;
}
static void write_terms(FILE *out, Vector weights) {
    Vector units = original(weights);
    for (int j = 0; j < weights.count; ++j)
        emit(out, "term %s standardized %s original %s", j ? features.values[j - 1].name : "intercept",
             r4(weights.values[j]), r4(units.values[j]));
}
static void write_weights(void) {
    FILE *out = fopen("output/weights.txt", "w");
    emit(out, "features %d degree %d expanded %d", train.features, p.degree, q);
    emit(out, "standardization");
    Square correlation = {.size = q};
    for (int j = 0; j < q; ++j)
        for (int k = 0; k < q; ++k) {
            double total = 0;
            for (int i = 0; i < n; ++i)
                total += x.values[i][j + 1] * x.values[i][k + 1];
            correlation.values[j][k] = total / (double)(n - 1);
        }
    Square vif = inverse(correlation);
    for (int j = 0; j < q; ++j)
        emit(out, "%s mean %s sd %s vif %s", features.values[j].name, r6(stats.mean[j]),
             r6(stats.deviation[j]), r4(vif.values[j][j]));
    emit(out, "correlation");
    for (int j = 0; j < q; ++j) {
        for (int k = 0; k < q; ++k)
            fprintf(out, "%s%s", k ? " " : "", r4(correlation.values[j][k]));
        fputc('\n', out);
    }
    for (int i = 0; i < 3; ++i) {
        Model *model = models + i;
        fputc('\n', out);
        emit(out, "model %s lambda %s", model->name, r4(lambda));
        write_terms(out, model->weights);
        Vector slopes = {.count = q};
        for (int j = 0; j < q; ++j)
            slopes.values[j] = model->weights.values[j + 1];
        emit(out, "norm %s", r4(length(slopes)));
        if (i < 2) {
            Vector delta = {.count = q + 1};
            for (int j = 0; j <= q; ++j)
                delta.values[j] = model->weights.values[j] - models[2].weights.values[j];
            emit(out, "distance_to_newton %s", r6(length(delta)));
        }
    }
    fputc('\n', out);
    emit(out, "coefficients newton lambda %s", r4(lambda));
    Vector weights = models[2].weights;
    for (int j = 0; j <= q; ++j) {
        double error = sqrt(fit.covariance.values[j][j] / (double)n);
        emit(out, "%s weight %s se %s z %s lower %s upper %s odds_ratio %s",
             j ? features.values[j - 1].name : "intercept", r4(weights.values[j]), r4(error),
             r4(weights.values[j] / error), r4(weights.values[j] - 1.96 * error),
             r4(weights.values[j] + 1.96 * error), r4(exp(weights.values[j])));
    }
    fputc('\n', out);
    emit(out, "model softmax lambda %s", r4(p.softmax_lambda));
    for (int k = 0; k < classes; ++k) {
        emit(out, "class %d", k);
        write_terms(out, soft_weights.classes[k]);
    }
    fclose(out);
}
static void write_traces_predictions(void) {
    FILE *trace = fopen("output/loss_trace.csv", "w");
    emit(trace, "optimizer,iteration,loss,gradient_norm,test_loss");
    for (int i = 0; i < 3; ++i) {
        Model *model = models + i;
        for (int j = 0; j < model->checkpoints.count; ++j) {
            Checkpoint point = model->checkpoints.points[j];
            emit(trace, "%s,%d,%s,%s,%s", model->name, point.iteration,
                 r6(objective(point.weights, &x, &y, lambda)),
                 r6(length(gradient(point.weights, &x, &y, lambda))),
                 r6(average_loss(point.weights, &z, &yt)));
        }
    }
    for (int i = 0; i < soft_checkpoints.count; ++i) {
        SoftCheckpoint point = soft_checkpoints.points[i];
        SoftWeights g = soft_gradient(point.weights, &x, &class_train, p.softmax_lambda);
        double total = 0;
        for (int k = 0; k < classes; ++k)
            for (int j = 0; j <= q; ++j)
                total += g.classes[k].values[j] * g.classes[k].values[j];
        emit(trace, "softmax,%d,%s,%s,%s", point.iteration,
             r6(soft_objective(point.weights, &x, &class_train, p.softmax_lambda)), r6(sqrt(total)),
             r6(soft_loss(point.weights, &z, &class_test)));
    }
    fclose(trace);
    FILE *out = fopen("output/predictions.csv", "w");
    emit(out, "id,model,probability,predicted,actual");
    for (int i = 0; i < 3; ++i)
        for (int j = 0; j < m; ++j)
            emit(out, "%s,%s,%s,%d,%d", test.rows[j].id, models[i].name,
                 r6(models[i].test_probabilities.values[j]),
                 models[i].test_probabilities.values[j] >= p.threshold, yt.values[j]);
    for (int j = 0; j < m; ++j) {
        SoftPoint point = soft_points[j];
        emit(out, "%s,softmax,%s,%d,%d", test.rows[j].id, r6(point.probabilities[point.predicted]),
             point.predicted, class_test.values[j]);
    }
    fclose(out);
}
static void write_binary(FILE *out, FILE *roc_file, const Model *model) {
    Scores scores = model->test_probabilities;
    Confusion c = confusion(scores, &yt, p.threshold);
    Integer pos = c.tp + c.fn, neg = c.fp + c.tn;
    emit(out, "model %s lambda %s", model->name, r4(lambda));
    int train_correct = correct(model->train_probabilities, &y, p.threshold);
    emit(out, "train correct %d/%d accuracy %s", train_correct, n, ratio(train_correct, n));
    emit(out, "test tp %" PRId64 " fp %" PRId64 " tn %" PRId64 " fn %" PRId64, c.tp, c.fp, c.tn, c.fn);
    emit(out, "test accuracy %s precision %s recall %s specificity %s f1 %s", ratio(c.tp + c.tn, m),
         ratio(c.tp, c.tp + c.fp), ratio(c.tp, pos), ratio(c.tn, neg),
         ratio(2 * c.tp, 2 * c.tp + c.fp + c.fn));
    double brier = 0;
    for (int i = 0; i < m; ++i) {
        double delta = scores.values[i] - yt.values[i];
        brier += delta * delta;
    }
    emit(out, "log_loss %s brier %s", r6(average_loss(model->weights, &z, &yt)), r6(brier / (double)m));
    Roc points = roc(scores, &yt);
    double ap = 0;
    Integer prior = 0;
    int youden = 0, f1 = 0, cost = 0;
    for (int i = 0; i < points.count; ++i) {
        RocPoint r = points.points[i];
        ap += (double)((r.tp - prior) * r.tp) / (double)(r.tp + r.fp);
        prior = r.tp;
        RocPoint a = points.points[youden], b = points.points[f1], d = points.points[cost];
        if (r.tp * neg - r.fp * pos > a.tp * neg - a.fp * pos)
            youden = i;
        if (r.tp * (pos + b.tp + b.fp) > b.tp * (pos + r.tp + r.fp))
            f1 = i;
        if (p.fp_cost * r.fp + p.fn_cost * (pos - r.tp) < p.fp_cost * d.fp + p.fn_cost * (pos - d.tp))
            cost = i;
    }
    ap /= (double)pos;
    emit(out, "auc %s average_precision %s", fraction_text(auc(scores, &yt)), r4(ap));
    RocPoint a = points.points[youden], b = points.points[f1], d = points.points[cost];
    emit(out, "youden threshold %s tpr %s fpr %s j %s", r6(a.threshold), ratio(a.tp, pos), ratio(a.fp, neg),
         ratio(a.tp * neg - a.fp * pos, pos * neg));
    emit(out, "best_f1 threshold %s precision %s recall %s f1 %s", r6(b.threshold), ratio(b.tp, b.tp + b.fp),
         ratio(b.tp, pos), ratio(2 * b.tp, pos + b.tp + b.fp));
    emit(out, "min_cost threshold %s cost %" PRId64 " fp %" PRId64 " fn %" PRId64, r6(d.threshold),
         p.fp_cost * d.fp + p.fn_cost * (pos - d.tp), d.fp, pos - d.tp);
    Calibration table = calibration(scores, &yt);
    emit(out, "calibration");
    for (int bin = 0; bin < 10; ++bin)
        emit(out, "bin %s count %d mean_probability %s positive_rate %s", bin_range(bin), table.counts[bin],
             table.counts[bin] ? r4(table.sums[bin] / (double)table.counts[bin]) : "-",
             ratio(table.hits[bin], table.counts[bin]));
    emit(out, "ece %s mce %s hosmer_lemeshow %s groups %d", r4(table.ece), r4(table.mce), r4(table.hl),
         table.groups);
    emit(out, "gains");
    Targets order = score_order(scores, true);
    for (int decile = 1; decile <= 10; ++decile) {
        int size = decile * m / 10, hits = 0;
        for (int i = 0; i < size; ++i)
            hits += yt.values[order.values[i]];
        emit(out, "decile %d rows %d positives %d gain %s lift %s", decile, size, hits, ratio(hits, pos),
             ratio((Integer)hits * m, (Integer)size * pos));
    }
    emit(roc_file, "%s,inf,0.0000,0.0000,-", model->name);
    for (int i = 0; i < points.count; ++i) {
        RocPoint r = points.points[i];
        emit(roc_file, "%s,%s,%s,%s,%s", model->name, r6(r.threshold), ratio(r.tp, pos), ratio(r.fp, neg),
             ratio(r.tp, r.tp + r.fp));
    }
}
static double slope(Vector units, int feature, const double *values) {
    double total = 0;
    for (int j = 0; j < q; ++j) {
        int count = 0;
        bool removed = false;
        double product = 1;
        Feature term = features.values[j];
        for (int k = 0; k < term.degree; ++k) {
            int index = term.indices[k];
            if (index == feature) {
                ++count;
                if (!removed) {
                    removed = true;
                    continue;
                }
            }
            product *= values[index];
        }
        if (count)
            total += units.values[j + 1] * ((double)count * product);
    }
    return total;
}
static int fraction_compare(const void *first, const void *second) {
    Fraction a = *(const Fraction *)first, b = *(const Fraction *)second;
    Integer left = a.numerator * b.denominator, right = b.numerator * a.denominator;
    return (left > right) - (left < right);
}
static void diagnostics(FILE *out) {
    Model *model = models + 2;
    Scores scores = model->test_probabilities;
    int positives = 0;
    for (int i = 0; i < n; ++i)
        positives += y.values[i];
    double pi_bar = (double)positives / (double)n,
           null_loss = -(pi_bar * log(pi_bar) + (1 - pi_bar) * log(1 - pi_bar)),
           loss = average_loss(model->weights, &x, &y);
    emit(out, "diagnostics newton lambda %s", r4(lambda));
    emit(out, "fit null_loss %s train_loss %s mcfadden_r2 %s deviance %s edf %s aic %s bic %s", r6(null_loss),
         r6(loss), r4(1 - loss / null_loss), r4(fit.deviance), r4(fit.edf), r4(fit.aic), r4(fit.bic));
    Targets order = score_order(fit.probabilities, false);
    double expected[10], hl = 0;
    int counts[10], observed[10];
    for (int group = 0; group < 10; ++group) {
        int first = group * n / 10, end = (group + 1) * n / 10;
        double sum = 0;
        int hits = 0;
        for (int i = first; i < end; ++i) {
            sum += fit.probabilities.values[order.values[i]];
            hits += y.values[order.values[i]];
        }
        int count = end - first;
        hl += (hits - sum) * (hits - sum) / (sum * (1 - sum / (double)count));
        expected[group] = sum;
        counts[group] = count;
        observed[group] = hits;
    }
    emit(out, "hosmer_lemeshow_train groups 10 statistic %s", r4(hl));
    for (int group = 0; group < 10; ++group)
        emit(out, "group %d rows %d observed %d expected %s", group + 1, counts[group], observed[group],
             r4(expected[group]));
    emit(out, "newton_iterations");
    for (int iteration = 1; iteration <= 10; ++iteration) {
        Vector weights = model->checkpoints.points[iteration - 1].weights,
               g = gradient(weights, &x, &y, lambda),
               delta = solve(cholesky(hessian(weights, &x, lambda)), g);
        double product = 0;
        for (int j = 0; j <= q; ++j)
            product += g.values[j] * delta.values[j];
        emit(out, "iteration %d objective %s gradient_norm %s step_norm %s predicted_decrease %s", iteration,
             r6(objective(weights, &x, &y, lambda)), r6(length(g)), r6(length(delta)), r6(product / 2));
    }
    Vector units = original(model->weights);
    double base_mean[6];
    for (int k = 0; k < train.features; ++k)
        base_mean[k] = stats.mean[k];
    Vector center_vector = standardize_point(expand(base_mean, &features), &stats, q);
    double center = sigmoid(score(model->weights, center_vector.values));
    for (int k = 0; k < train.features; ++k) {
        double total = 0;
        for (int i = 0; i < n; ++i)
            total += fit.probabilities.values[i] * (1 - fit.probabilities.values[i]) *
                     slope(units, k, train.rows[i].values);
        emit(out, "marginal %s average %s at_mean %s", train.names[k], r4(total / (double)n),
             r4(center * (1 - center) * slope(units, k, base_mean)));
    }
    for (int k = 1; k <= 9; ++k) {
        Confusion c = confusion(scores, &yt, (double)k / 10);
        emit(out,
             "cut 0.%d positive %" PRId64 " tp %" PRId64 " fp %" PRId64 " precision %s recall %s accuracy %s",
             k, c.tp + c.fp, c.tp, c.fp, ratio(c.tp, c.tp + c.fp), ratio(c.tp, c.tp + c.fn),
             ratio(c.tp + c.tn, m));
    }
    Scores distances = {.count = m};
    for (int i = 0; i < m; ++i)
        distances.values[i] = fabs(scores.values[i] - p.threshold);
    order = score_order(distances, true);
    int written = 0;
    for (int i = 0; i < m; ++i) {
        int id = order.values[i];
        if ((scores.values[id] >= p.threshold) == yt.values[id])
            continue;
        emit(out, "error %s actual %d probability %s", test.rows[id].id, yt.values[id],
             r6(scores.values[id]));
        if (++written == 5)
            break;
    }
    Minstd random = {p.bootstrap_seed};
    Fraction fractions[1000];
    double values[1000], mean = 0;
    for (int replicate = 0; replicate < p.bootstrap; ++replicate) {
        Scores sample = {.count = m};
        Targets targets = {.count = m};
        for (int i = 0; i < m; ++i) {
            int id = (int)(draw(&random) % m);
            sample.values[i] = scores.values[id];
            targets.values[i] = yt.values[id];
        }
        fractions[replicate] = auc(sample, &targets);
        values[replicate] = (double)fractions[replicate].numerator / (double)fractions[replicate].denominator;
        mean += values[replicate];
    }
    mean /= (double)p.bootstrap;
    double squares = 0;
    for (int i = 0; i < p.bootstrap; ++i)
        squares += (values[i] - mean) * (values[i] - mean);
    qsort(fractions, (size_t)p.bootstrap, sizeof *fractions, fraction_compare);
    emit(out, "bootstrap resamples %d seed %" PRId64 " auc_mean %s auc_sd %s lower %s upper %s", p.bootstrap,
         p.bootstrap_seed, r4(mean), r4(sqrt(squares / (double)(p.bootstrap - 1))),
         fraction_text(fractions[p.bootstrap / 40]),
         fraction_text(fractions[p.bootstrap - p.bootstrap / 40 - 1]));
    int large = 0;
    for (int i = 0; i < n; ++i)
        if (fabs(fit.residual.values[i]) > 2)
            ++large;
    emit(out, "influence effective_parameters %s large_residuals %d", r4(fit.edf), large);
    order = score_order(fit.cook, true);
    for (int i = 0; i < n && i < 5; ++i) {
        int id = order.values[i];
        emit(out, "cook %s actual %d probability %s leverage %s residual %s distance %s", train.rows[id].id,
             y.values[id], r4(fit.probabilities.values[id]), r4(fit.leverage.values[id]),
             r4(fit.residual.values[id]), r4(fit.cook.values[id]));
    }
}
static void importance_profiles(FILE *out) {
    Model *model = models + 2;
    double baseline_loss = average_loss(model->weights, &z, &yt);
    Fraction baseline_auc = auc(model->test_probabilities, &yt);
    emit(out, "importance repeats %d seed %" PRId64, p.permutations, p.permutation_seed);
    emit(out, "baseline log_loss %s auc %s softmax_accuracy %s", r6(baseline_loss),
         fraction_text(baseline_auc), ratio(soft_correct, m));
    Minstd random = {p.permutation_seed};
    for (int k = 0; k < train.features; ++k) {
        double total_loss = 0;
        Integer total_auc = 0, total_correct = 0;
        for (int repeat = 0; repeat < p.permutations; ++repeat) {
            Targets order = sequence(m);
            shuffle(&random, &order);
            Table rows = test;
            for (int i = 0; i < m; ++i)
                rows.rows[i].values[k] = test.rows[order.values[i]].values[k];
            Matrix raw = expanded(&rows, &features), data = standardize(&raw, &stats, q);
            total_loss += average_loss(model->weights, &data, &yt);
            total_auc += auc(probabilities(model->weights, &data), &yt).numerator;
            for (int i = 0; i < m; ++i)
                if (soft_point(soft_weights, data.values[i], class_test.values[i]).predicted ==
                    class_test.values[i])
                    ++total_correct;
        }
        emit(out, "feature %s log_loss_increase %s auc %s softmax_accuracy %s", train.names[k],
             r6(total_loss / (double)p.permutations - baseline_loss),
             fraction_text((Fraction){total_auc, (Integer)p.permutations * baseline_auc.denominator}),
             ratio(total_correct, (Integer)p.permutations * m));
    }
    fputc('\n', out);
    emit(out, "profiles");
    for (int k = 0; k < train.features; ++k) {
        double lo = train.rows[0].values[k], hi = lo;
        for (int i = 0; i < n; ++i) {
            lo = fmin(lo, train.rows[i].values[k]);
            hi = fmax(hi, train.rows[i].values[k]);
        }
        for (int point = 0; point < 5; ++point) {
            double values[6];
            for (int j = 0; j < train.features; ++j)
                values[j] = stats.mean[j];
            values[k] = lo + (hi - lo) * point / 4;
            Vector vector = standardize_point(expand(values, &features), &stats, q);
            SoftPoint soft = soft_point(soft_weights, vector.values, 0);
            fprintf(out, "profile %s value %s newton %s softmax", train.names[k], r4(values[k]),
                    r4(sigmoid(score(model->weights, vector.values))));
            for (int j = 0; j < classes; ++j)
                fprintf(out, " %s", r4(soft.probabilities[j]));
            fputc('\n', out);
        }
    }
}
static void multiclass(FILE *out) {
    emit(out, "softmax classes %d lambda %s iterations %d", classes, r4(p.softmax_lambda),
         p.softmax_iterations);
    emit(out, "confusion");
    Integer table[4][4] = {{0}}, rows[4] = {0}, columns[4] = {0}, diagonal = 0;
    for (int i = 0; i < m; ++i)
        ++table[class_test.values[i]][soft_points[i].predicted];
    for (int k = 0; k < classes; ++k) {
        for (int j = 0; j < classes; ++j) {
            fprintf(out, "%s%" PRId64, j ? " " : "", table[k][j]);
            rows[k] += table[k][j];
            columns[j] += table[k][j];
        }
        fputc('\n', out);
        diagonal += table[k][k];
    }
    for (int k = 0; k < classes; ++k) {
        Scores scores = {.count = m};
        Targets targets = {.count = m};
        for (int i = 0; i < m; ++i) {
            scores.values[i] = soft_points[i].probabilities[k];
            targets.values[i] = class_test.values[i] == k;
        }
        emit(out, "class %d precision %s recall %s f1 %s auc %s", k, ratio(table[k][k], columns[k]),
             ratio(table[k][k], rows[k]), ratio(2 * table[k][k], columns[k] + rows[k]),
             fraction_text(auc(scores, &targets)));
    }
    Integer expected = 0;
    for (int k = 0; k < classes; ++k)
        expected += rows[k] * columns[k];
    emit(out, "accuracy %s kappa %s", ratio(diagonal, m),
         ratio((Integer)m * diagonal - expected, (Integer)m * m - expected));
    double brier = 0;
    for (int i = 0; i < m; ++i) {
        double total = 0;
        for (int k = 0; k < classes; ++k) {
            double delta = soft_points[i].probabilities[k] - (class_test.values[i] == k);
            total += delta * delta;
        }
        brier += total;
    }
    emit(out, "log_loss %s brier %s", r6(soft_loss(soft_weights, &z, &class_test)), r6(brier / (double)m));
    Scores scores = {.count = m}, confidence = {.count = m};
    Targets hits = {.count = m};
    double binary_loss = 0;
    int agreement = 0;
    for (int i = 0; i < m; ++i) {
        double probability = soft_points[i].probabilities[p.positive];
        scores.values[i] = probability;
        binary_loss += -log(yt.values[i] ? probability : 1 - probability);
        if ((probability >= p.threshold) == (models[2].test_probabilities.values[i] >= p.threshold))
            ++agreement;
        confidence.values[i] = soft_points[i].probabilities[soft_points[i].predicted];
        hits.values[i] = soft_points[i].predicted == class_test.values[i];
    }
    emit(out, "binary_view positive_class %d auc %s log_loss %s accuracy %s agreement_with_newton %d/%d",
         p.positive, fraction_text(auc(scores, &yt)), r6(binary_loss / (double)m),
         ratio(correct(scores, &yt, p.threshold), m), agreement, m);
    emit(out, "confidence");
    Calibration bins = calibration(confidence, &hits);
    for (int bin = 0; bin < 10; ++bin)
        emit(out, "bin %s count %d mean_confidence %s accuracy %s", bin_range(bin), bins.counts[bin],
             bins.counts[bin] ? r4(bins.sums[bin] / (double)bins.counts[bin]) : "-",
             ratio(bins.hits[bin], bins.counts[bin]));
    emit(out, "ece %s", r4(bins.ece));
    fputc('\n', out);
    emit(out, "one_vs_rest lambda %s newton_iterations 10", r4(p.softmax_lambda));
    Scores ovr[4];
    for (int k = 0; k < classes; ++k) {
        Targets train_targets = labels(&train, k), test_targets = labels(&test, k);
        Vector weights = trained_newton(&x, &train_targets, p.softmax_lambda);
        ovr[k] = probabilities(weights, &z);
        emit(out, "class %d objective %s auc %s", k,
             r6(objective(weights, &x, &train_targets, p.softmax_lambda)),
             fraction_text(auc(ovr[k], &test_targets)));
    }
    int correct_count = 0, same = 0;
    for (int i = 0; i < m; ++i) {
        int predicted = 0;
        for (int k = 1; k < classes; ++k)
            if (ovr[k].values[i] > ovr[predicted].values[i])
                predicted = k;
        if (predicted == class_test.values[i])
            ++correct_count;
        if (predicted == soft_points[i].predicted)
            ++same;
    }
    emit(out, "accuracy %s agreement_with_softmax %d/%d", ratio(correct_count, m), same, m);
}
static void maps(FILE *out) {
    emit(out, "map %s %s width %d height %d", train.names[0], train.names[1], p.width, p.height);
    emit(out, "softmax_classes");
    double lo[6], hi[6];
    for (int k = 0; k < train.features; ++k)
        lo[k] = hi[k] = train.rows[0].values[k];
    for (int i = 0; i < n; ++i)
        for (int k = 0; k < train.features; ++k) {
            lo[k] = fmin(lo[k], train.rows[i].values[k]);
            hi[k] = fmax(hi[k], train.rows[i].values[k]);
        }
    int cells[4] = {0};
    char probability_map[80][81];
    for (int r = 0; r < p.height; ++r) {
        char class_line[81];
        for (int c = 0; c < p.width; ++c) {
            double values[6];
            for (int k = 0; k < train.features; ++k)
                values[k] = stats.mean[k];
            values[0] = lo[0] + (c + 0.5) * (hi[0] - lo[0]) / p.width;
            values[1] = hi[1] - (r + 0.5) * (hi[1] - lo[1]) / p.height;
            Vector vector = standardize_point(expand(values, &features), &stats, q);
            int predicted = soft_point(soft_weights, vector.values, 0).predicted;
            class_line[c] = (char)('0' + predicted);
            ++cells[predicted];
            int bin = (int)floor(sigmoid(score(models[2].weights, vector.values)) * 10);
            if (bin > 9)
                bin = 9;
            probability_map[r][c] = (char)('0' + bin);
        }
        class_line[p.width] = probability_map[r][p.width] = 0;
        emit(out, "%s", class_line);
    }
    fputs("cells", out);
    for (int k = 0; k < classes; ++k)
        fprintf(out, " %d", cells[k]);
    fputc('\n', out);
    emit(out, "newton_probability");
    for (int r = 0; r < p.height; ++r)
        emit(out, "%s", probability_map[r]);
}
static void write_evaluation(void) {
    FILE *out = fopen("output/evaluation.txt", "w"), *roc_file = fopen("output/roc.csv", "w");
    emit(roc_file, "model,threshold,tpr,fpr,precision");
    emit(out, "data train %d test %d base_features %d degree %d features %d", n, m, train.features, p.degree,
         q);
    int positive_train = 0, positive_test = 0;
    for (int i = 0; i < n; ++i)
        positive_train += y.values[i];
    for (int i = 0; i < m; ++i)
        positive_test += yt.values[i];
    emit(out, "binary positive_class %d train %d/%d test %d/%d", p.positive, positive_train, n, positive_test,
         m);
    fprintf(out, "classes %d train", classes);
    for (int k = 0; k < classes; ++k) {
        int count = 0;
        for (int i = 0; i < n; ++i)
            if (class_train.values[i] == k)
                ++count;
        fprintf(out, " %d", count);
    }
    fputs(" test", out);
    for (int k = 0; k < classes; ++k) {
        int count = 0;
        for (int i = 0; i < m; ++i)
            if (class_test.values[i] == k)
                ++count;
        fprintf(out, " %d", count);
    }
    fputs("\n\n", out);
    emit(out, "cross_validation folds 5 newton_iterations 10");
    for (int i = 0; i < p.lambda_count; ++i) {
        CrossValidation cv = validations[i];
        fprintf(out, "lambda %s fold_loss", r4(p.lambdas[i]));
        for (int f = 0; f < 5; ++f)
            fprintf(out, " %s", r6(cv.folds[f]));
        emit(out, " cv_loss %s errors %d/%d", r6(cv.loss), cv.errors, n);
    }
    emit(out, "selected lambda %s cv_loss %s se %s lambda_1se %s", r4(lambda), r6(validations[selected].loss),
         r6(se), r4(p.lambdas[one_se]));
    Confusion validation = confusion(validations[selected].probabilities, &y, p.threshold);
    emit(out, "out_of_fold tp %" PRId64 " fp %" PRId64 " tn %" PRId64 " fn %" PRId64 " accuracy %s auc %s",
         validation.tp, validation.fp, validation.tn, validation.fn, ratio(validation.tp + validation.tn, n),
         fraction_text(auc(validations[selected].probabilities, &y)));
    fputc('\n', out);
    emit(out, "lambda_path");
    for (int i = 0; i < p.lambda_count; ++i) {
        double coefficient = p.lambdas[i];
        Vector weights = trained_newton(&x, &y, coefficient), slopes = {.count = q};
        for (int j = 0; j < q; ++j)
            slopes.values[j] = weights.values[j + 1];
        emit(out,
             "lambda %s objective %s train_loss %s test_loss %s train_accuracy %s test_accuracy %s norm %s",
             r4(coefficient), r6(objective(weights, &x, &y, coefficient)), r6(average_loss(weights, &x, &y)),
             r6(average_loss(weights, &z, &yt)),
             ratio(correct(probabilities(weights, &x), &y, p.threshold), n),
             ratio(correct(probabilities(weights, &z), &yt, p.threshold), m), r4(length(slopes)));
    }
    fputc('\n', out);
    emit(out, "degrees lambda %s", r4(lambda));
    for (int degree = 1; degree <= p.degree; ++degree) {
        int count = 0;
        for (int j = 0; j < q; ++j)
            if (features.values[j].degree <= degree)
                ++count;
        Matrix tx = standardize(&train_expanded, &stats, count),
               vx = standardize(&test_expanded, &stats, count);
        Vector weights = trained_newton(&tx, &y, lambda);
        Influence measures = influence(weights, &tx, &y, lambda);
        Scores scores = probabilities(weights, &vx);
        CrossValidation cv = cross_validate(lambda, count);
        emit(out,
             "degree %d features %d cv_loss %s train_loss %s test_loss %s test_accuracy %s auc %s edf %s aic "
             "%s bic %s",
             degree, count, r6(cv.loss), r6(average_loss(weights, &tx, &y)),
             r6(average_loss(weights, &vx, &yt)), ratio(correct(scores, &yt, p.threshold), m),
             fraction_text(auc(scores, &yt)), r4(measures.edf), r4(measures.aic), r4(measures.bic));
    }
    fputc('\n', out);
    emit(out, "learning_curve lambda %s", r4(lambda));
    for (int k = 1; k <= 4; ++k) {
        int size = k * n / 4;
        Matrix raw = train_expanded;
        raw.rows = size;
        Statistics local = statistics(&raw, q);
        Matrix tx = standardize(&raw, &local, q), vx = standardize(&test_expanded, &local, q);
        Targets targets = y;
        targets.count = size;
        Vector weights = trained_newton(&tx, &targets, lambda);
        Scores scores = probabilities(weights, &vx);
        emit(out, "size %d train_loss %s test_loss %s test_accuracy %s auc %s", size,
             r6(average_loss(weights, &tx, &targets)), r6(average_loss(weights, &vx, &yt)),
             ratio(correct(scores, &yt, p.threshold), m), fraction_text(auc(scores, &yt)));
    }
    for (int i = 0; i < 3; ++i) {
        fputc('\n', out);
        write_binary(out, roc_file, models + i);
    }
    fputc('\n', out);
    int pairs[3][2] = {{0, 1}, {0, 2}, {1, 2}};
    for (int k = 0; k < 3; ++k) {
        Integer same = 0, first = 0, second = 0;
        int a = pairs[k][0], b = pairs[k][1];
        for (int i = 0; i < m; ++i) {
            bool pa = models[a].test_probabilities.values[i] >= p.threshold,
                 pb = models[b].test_probabilities.values[i] >= p.threshold;
            if (pa == pb)
                ++same;
            if (pa == yt.values[i] && pb != yt.values[i])
                ++first;
            if (pb == yt.values[i] && pa != yt.values[i])
                ++second;
        }
        Integer delta = first > second ? first - second : second - first;
        --delta;
        emit(out,
             "agreement %s %s same %" PRId64 "/%d only_first %" PRId64 " only_second %" PRId64 " mcnemar %s",
             models[a].name, models[b].name, same, m, first, second, ratio(delta * delta, first + second));
    }
    fputc('\n', out);
    diagnostics(out);
    fputc('\n', out);
    importance_profiles(out);
    fputc('\n', out);
    multiclass(out);
    fputc('\n', out);
    maps(out);
    fclose(out);
    fclose(roc_file);
}
int main(void) {
    train = read_table("train.csv");
    test = read_table("test.csv");
    p = read_params();
    features = build_features(&train, p.degree);
    n = train.count;
    m = test.count;
    q = features.count;
    train_expanded = expanded(&train, &features);
    test_expanded = expanded(&test, &features);
    stats = statistics(&train_expanded, q);
    x = standardize(&train_expanded, &stats, q);
    z = standardize(&test_expanded, &stats, q);
    y = labels(&train, p.positive);
    yt = labels(&test, p.positive);
    class_train = labels(&train, -1);
    class_test = labels(&test, -1);
    for (int i = 0; i < n; ++i)
        if (class_train.values[i] + 1 > classes)
            classes = class_train.values[i] + 1;
    for (int i = 0; i < p.lambda_count; ++i)
        validations[i] = cross_validate(p.lambdas[i], q);
    for (int i = 1; i < p.lambda_count; ++i)
        if (validations[i].loss <= validations[selected].loss)
            selected = i;
    lambda = p.lambdas[selected];
    double mean = 0, squares = 0;
    for (int f = 0; f < 5; ++f)
        mean += validations[selected].folds[f];
    mean /= 5;
    for (int f = 0; f < 5; ++f)
        squares += (validations[selected].folds[f] - mean) * (validations[selected].folds[f] - mean);
    se = sqrt(squares / 4) / sqrt(5.0);
    for (int i = 0; i < p.lambda_count; ++i)
        if (validations[i].loss <= validations[selected].loss + se)
            one_se = i;
    models[0].name = "gd";
    models[0].checkpoints = gradient_descent(&x, &y, lambda, p.gd_rate, p.gd_iterations);
    models[1].name = "sgd";
    models[1].checkpoints = stochastic(&x, &y, lambda, &p);
    models[2].name = "newton";
    models[2].checkpoints = newton(&x, &y, lambda);
    for (int i = 0; i < 3; ++i) {
        models[i].weights = models[i].checkpoints.points[models[i].checkpoints.count - 1].weights;
        models[i].train_probabilities = probabilities(models[i].weights, &x);
        models[i].test_probabilities = probabilities(models[i].weights, &z);
    }
    fit = influence(models[2].weights, &x, &y, lambda);
    soft_checkpoints = train_softmax(&x, &class_train, classes, &p);
    soft_weights = soft_checkpoints.points[soft_checkpoints.count - 1].weights;
    for (int i = 0; i < m; ++i) {
        soft_points[i] = soft_point(soft_weights, z.values[i], class_test.values[i]);
        if (soft_points[i].predicted == class_test.values[i])
            ++soft_correct;
    }
    write_weights();
    write_traces_predictions();
    write_evaluation();
    return 0;
}
