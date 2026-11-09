#include "classifier.h"
typedef struct {
    int total, bound, free, by_bound[2], by_free[2];
} Support;
static Support support(const Model *model) {
    Support out = {0};
    for (int i = 0; i < model->count; ++i)
        if (model->alpha[i] > 0) {
            ++out.total;
            int label = model->data[i].label == 1 ? 0 : 1;
            if (model->alpha[i] == model->c) {
                ++out.bound;
                ++out.by_bound[label];
            } else {
                ++out.free;
                ++out.by_free[label];
            }
        }
    return out;
}
static char *support_text(const Model *model) {
    Support s = support(model);
    return format("support_vectors %d bound %d free %d", s.total, s.bound, s.free);
}
static char *run_info(const Model *model) {
    return format("passes %d steps %d converged %s", model->pass_count, model->steps,
                  model->converged ? "yes" : "no");
}
static void decisions(const Model *model, const Example *data, int count, double *out) {
    for (int i = 0; i < count; ++i)
        out[i] = decision(model, data[i].point);
}
static void objectives(const double *alpha, const Example *data, const double *matrix, int count,
                       double *q, double *dual) {
    *q = 0;
    double total = 0;
    for (int i = 0; i < count; ++i) {
        double sum = 0;
        for (int j = 0; j < count; ++j)
            if (alpha[j] > 0)
                sum += alpha[j] * data[j].label * matrix[i * count + j];
        *q += alpha[i] * data[i].label * sum;
        total += alpha[i];
    }
    *dual = total - *q / 2;
}
typedef struct {
    int train, test, correct, sv, passes, steps;
    bool converged;
} FoldResult;
typedef struct {
    int kernel, candidate, correct, sv, passes, steps;
    double decisions[200];
    FoldResult folds[200];
} CV;
static CV cross_validate(const Input *input, int kernel, int candidate, const double *matrix) {
    CV out = {0};
    out.kernel = kernel;
    out.candidate = candidate;
    int n = input->train_count;
    Fold *partitions = folds(n, input->params.folds);
    Example data[200];
    double selected[40000];
    for (int f = 0; f < input->params.folds; ++f) {
        Fold fold = partitions[f];
        for (int i = 0; i < fold.train_count; ++i) {
            data[i] = input->train[fold.train[i]];
            for (int j = 0; j < fold.train_count; ++j)
                selected[i * fold.train_count + j] = matrix[fold.train[i] * n + fold.train[j]];
        }
        Model model = train(data, fold.train_count, input->params.kernels[kernel], selected,
                            input->params.c_grid[candidate], &input->params);
        int correct = 0;
        for (int j = 0; j < fold.test_count; ++j) {
            int i = fold.test[j];
            out.decisions[i] = decision(&model, input->train[i].point);
            correct += sign(out.decisions[i]) == input->train[i].label;
        }
        int sv = support(&model).total;
        out.correct += correct;
        out.sv += sv;
        out.passes += model.pass_count;
        out.steps += model.steps;
        out.folds[f] = (FoldResult){fold.train_count, fold.test_count, correct,        sv,
                                    model.pass_count, model.steps,     model.converged};
        free_model(&model);
    }
    return out;
}
typedef struct {
    double train[200], test[100], weights[2], alignment, equality, q, dual, primal, violation,
        radius, positive_mean, negative_mean;
    Support sv;
    int violations, estimated_errors, train_correct, inside;
    Evaluation evaluation;
} Metrics;
static Metrics metrics(const Input *input, const Model *model) {
    Metrics out = {0};
    training_decisions(model, out.train);
    decisions(model, input->test, input->test_count, out.test);
    out.sv = support(model);
    objectives(model->alpha, model->data, model->matrix, model->count, &out.q, &out.dual);
    double sy = 0, sg = 0, xi = 0, maximum_diagonal = model->matrix[0], minimum = model->matrix[0];
    int n = model->count;
    for (int i = 0; i < n; ++i) {
        for (int j = 0; j < n; ++j) {
            double value = model->matrix[i * n + j];
            sy += model->data[i].label * model->data[j].label * value;
            sg += value * value;
            if (value < minimum)
                minimum = value;
        }
        if (model->matrix[i * n + i] > maximum_diagonal)
            maximum_diagonal = model->matrix[i * n + i];
        out.equality += model->alpha[i] * model->data[i].label;
        for (int coordinate = 0; coordinate < 2; ++coordinate)
            out.weights[coordinate] +=
                model->alpha[i] * model->data[i].label * model->data[i].point[coordinate];
        double residual = model->data[i].label * out.train[i] - 1,
               violation = model->alpha[i] == 0          ? fmax(0, -residual)
                           : model->alpha[i] == model->c ? fmax(0, residual)
                                                         : fabs(residual);
        out.violations += violation > input->params.tolerance;
        if (violation > out.violation)
            out.violation = violation;
        xi += fmax(0, 1 - model->data[i].label * out.train[i]);
        out.train_correct += sign(out.train[i]) == model->data[i].label;
    }
    out.alignment = sy / (n * sqrt(sg));
    out.radius = maximum_diagonal - minimum;
    out.primal = out.q / 2 + model->c * xi;
    for (int i = 0; i < n; ++i)
        out.estimated_errors +=
            2 * model->alpha[i] * out.radius + fmax(0, 1 - model->data[i].label * out.train[i]) >=
            1;
    int positive = 0, negative = 0;
    for (int i = 0; i < input->test_count; ++i) {
        double value = out.test[i];
        out.inside += fabs(value) < 1;
        if (input->test[i].label == 1) {
            out.positive_mean += value;
            ++positive;
        } else {
            out.negative_mean += value;
            ++negative;
        }
    }
    out.positive_mean /= positive;
    out.negative_mean /= negative;
    out.evaluation = evaluate(input->test, out.test, input->test_count);
    return out;
}
static void model_report(Lines *out, const Input *input, const Model *model, const Metrics *m) {
    int n = input->train_count, count = input->test_count;
    Evaluation e = m->evaluation;
    line(out, "model %s", model->kernel.name);
    line(out, "kernel %s", kernel_description(model->kernel));
    line(out, "C %s", real(model->c, 4));
    line(out, "alignment %s", real(m->alignment, 6));
    line(out, "passes %d full %d nonbound %d converged %s", model->pass_count, model->full,
         model->nonbound, model->converged ? "yes" : "no");
    line(out, "examined %d steps %d", model->examined, model->steps);
    line(out, "choice heuristic %d nonbound_loop %d full_loop %d", model->choices[0],
         model->choices[1], model->choices[2]);
    line(out, "clipping none %d lower %d upper %d", model->clipping[0], model->clipping[1],
         model->clipping[2]);
    line(out, "%s", support_text(model));
    line(out, "b %s", real(model->b, 6));
    line(out, "equality %s", real(m->equality, 6));
    if (strcmp(model->kernel.kind, "linear") == 0)
        line(out, "w %s %s", real(m->weights[0], 6), real(m->weights[1], 6));
    line(out, "sv_by_class positive bound %d free %d negative bound %d free %d", m->sv.by_bound[0],
         m->sv.by_free[0], m->sv.by_bound[1], m->sv.by_free[1]);
    line(out, "norm %s margin %s", real(sqrt(m->q), 6), real(2 / sqrt(m->q), 6));
    line(out, "dual_objective %s", real(m->dual, 6));
    line(out, "primal_objective %s", real(m->primal, 6));
    line(out, "duality_gap %s", real(m->primal - m->dual, 6));
    line(out, "kkt_violations %d max %s", m->violations, real(m->violation, 6));
    line(out, "xi_alpha radius %s errors %d/%d accuracy %s", real(m->radius, 6),
         m->estimated_errors, n, ratio(n - m->estimated_errors, n));
    line(out, "train correct %d/%d accuracy %s", m->train_correct, n, ratio(m->train_correct, n));
    line(out, "test correct %d/%d accuracy %s tp %d fp %d tn %d fn %d", e.tp + e.tn, count,
         ratio(e.tp + e.tn, count), e.tp, e.fp, e.tn, e.fn);
    line(out, "test precision %s recall %s f1 %s auc %s", ratio(e.tp, e.tp + e.fp),
         ratio(e.tp, e.tp + e.fn), ratio(2 * e.tp, 2 * e.tp + e.fp + e.fn),
         real(auc(input->test, m->test, count), 4));
    line(out, "test inside_margin %d", m->inside);
    line(out, "test mean_decision positive %s negative %s", real(m->positive_mean, 4),
         real(m->negative_mean, 4));
    for (int i = 0; i < n; ++i)
        if (model->alpha[i] > 0)
            line(out, "sv %s y %d alpha %s f %s %s", model->data[i].id, model->data[i].label,
                 real(model->alpha[i], 6), real(m->train[i], 4),
                 model->alpha[i] == model->c ? "bound" : "free");
}
static double probability(double value, double a, double b) { return 1 / (1 + exp(a * value + b)); }
static double nll(const double *values, const double *targets, int count, double a, double b) {
    double out = 0;
    for (int i = 0; i < count; ++i) {
        double p = probability(values[i], a, b);
        out += targets[i] * log(p) + (1 - targets[i]) * log(1 - p);
    }
    return -out;
}
typedef struct {
    double a, b, probabilities[100];
    Lines lines;
} Calibration;
static const double *closest_values;
static int compare_closest(const void *a, const void *b) {
    int x = *(const int *)a, y = *(const int *)b;
    double first = fabs(closest_values[x]), second = fabs(closest_values[y]);
    return first != second ? (first < second ? -1 : 1) : x - y;
}
static Calibration calibrate(const Input *input, const Model *model, const double *cv,
                             const double *test) {
    Calibration out = {0};
    int positive = 0, n = input->train_count, m = input->test_count;
    for (int i = 0; i < n; ++i)
        positive += input->train[i].label == 1;
    int negative = n - positive;
    double targets[200];
    for (int i = 0; i < n; ++i)
        targets[i] = input->train[i].label == 1 ? (double)(positive + 1) / (positive + 2)
                                                : 1.0 / (negative + 2);
    out.b = log((double)(negative + 1) / (positive + 1));
    line(&out.lines, "calibration %s C %s positives %d negatives %d", model->kernel.name,
         real(model->c, 4), positive, negative);
    line(&out.lines, "start A %s B %s nll %s", real(out.a, 6), real(out.b, 6),
         real(nll(cv, targets, n, out.a, out.b), 6));
    for (int iteration = 1; iteration <= input->params.newton_iterations; ++iteration) {
        double g1 = 0, g2 = 0, h11 = 0, h21 = 0, h22 = 0;
        for (int i = 0; i < n; ++i) {
            double p = probability(cv[i], out.a, out.b);
            g1 += cv[i] * (targets[i] - p);
            g2 += targets[i] - p;
            h11 += cv[i] * cv[i] * p * (1 - p);
            h21 += cv[i] * p * (1 - p);
            h22 += p * (1 - p);
        }
        double determinant = h11 * h22 - h21 * h21, a = out.a - (h22 * g1 - h21 * g2) / determinant,
               b = out.b - (h11 * g2 - h21 * g1) / determinant;
        out.a = a;
        out.b = b;
        line(&out.lines, "iteration %d A %s B %s nll %s", iteration, real(a, 6), real(b, 6),
             real(nll(cv, targets, n, a, b), 6));
    }
    int count[5] = {0}, positives[5] = {0};
    double sums[5] = {0}, loss = 0, brier = 0;
    for (int i = 0; i < m; ++i) {
        double p = probability(test[i], out.a, out.b);
        out.probabilities[i] = p;
        loss += input->test[i].label == 1 ? log(p) : log(1 - p);
        double error = p - (input->test[i].label == 1 ? 1 : 0);
        brier += error * error;
        int bin = (int)floor(p * 5);
        if (bin > 4)
            bin = 4;
        ++count[bin];
        sums[bin] += p;
        positives[bin] += input->test[i].label == 1;
    }
    line(&out.lines, "test log_loss %s brier %s", real(-loss / m, 6), real(brier / m, 6));
    const char *ranges[5] = {"0.0-0.2", "0.2-0.4", "0.4-0.6", "0.6-0.8", "0.8-1.0"};
    for (int bin = 0; bin < 5; ++bin)
        line(&out.lines, "bin %s count %d mean_probability %s positive_rate %s", ranges[bin],
             count[bin], count[bin] ? real(sums[bin] / count[bin], 4) : "-",
             ratio(positives[bin], count[bin]));
    int closest[100];
    for (int i = 0; i < m; ++i)
        closest[i] = i;
    closest_values = test;
    qsort(closest, (size_t)m, sizeof(int), compare_closest);
    for (int j = 0; j < 5; ++j) {
        int i = closest[j];
        line(&out.lines, "closest %s label %d decision %s probability %s", input->test[i].id,
             input->test[i].label, real(test[i], 4), real(out.probabilities[i], 4));
    }
    return out;
}
static double psi(const double *weights, const double *point) {
    return weights[0] * point[0] + weights[1] * point[1] + weights[2];
}
typedef struct {
    double weights[3], average[3], test[100];
    Lines lines;
} Pegasos;
static Pegasos pegasos(const Input *input, const Model *linear, const Metrics *metrics) {
    Pegasos out = {0};
    const Params *p = &input->params;
    int64_t state = p->seed;
    double sums[3] = {0};
    int updates = 0, n = input->train_count, m = input->test_count;
    line(&out.lines, "pegasos lambda %s iterations %d seed %lld", real(p->lambda, 4),
         p->pegasos_iterations, (long long)p->seed);
    for (int t = 1; t <= p->pegasos_iterations; ++t) {
        state = 48271 * state % 2147483647;
        Example example = input->train[state % n];
        double eta = 1 / (p->lambda * t), sigma = 1 - eta * p->lambda;
        bool update = example.label * psi(out.weights, example.point) < 1;
        if (update) {
            out.weights[0] = sigma * out.weights[0] + eta * example.label * example.point[0];
            out.weights[1] = sigma * out.weights[1] + eta * example.label * example.point[1];
            out.weights[2] = sigma * out.weights[2] + eta * example.label;
            ++updates;
        } else
            for (int i = 0; i < 3; ++i)
                out.weights[i] = sigma * out.weights[i];
        for (int i = 0; i < 3; ++i)
            sums[i] += out.weights[i];
        if (t % (p->pegasos_iterations / 10) == 0) {
            double xi = 0;
            int correct = 0;
            for (int i = 0; i < n; ++i) {
                double value = psi(out.weights, input->train[i].point);
                xi += fmax(0, 1 - input->train[i].label * value);
                correct += sign(value) == input->train[i].label;
            }
            double *w = out.weights,
                   objective = p->lambda / 2 * (w[0] * w[0] + w[1] * w[1] + w[2] * w[2]) + xi / n;
            line(&out.lines, "checkpoint %d objective %s train %d/%d", t, real(objective, 6),
                 correct, n);
        }
    }
    for (int i = 0; i < 3; ++i)
        out.average[i] = sums[i] / p->pegasos_iterations;
    int train_correct = 0, test_correct = 0, average_correct = 0, agreement = 0;
    for (int i = 0; i < n; ++i)
        train_correct += sign(psi(out.weights, input->train[i].point)) == input->train[i].label;
    for (int i = 0; i < m; ++i) {
        double value = psi(out.weights, input->test[i].point);
        out.test[i] = value;
        test_correct += sign(value) == input->test[i].label;
        average_correct += sign(psi(out.average, input->test[i].point)) == input->test[i].label;
        agreement += sign(value) == sign(metrics->test[i]);
    }
    double *w = out.weights;
    const double *v = metrics->weights;
    double cosine = (w[0] * v[0] + w[1] * v[1]) /
                    (sqrt(w[0] * w[0] + w[1] * w[1]) * sqrt(v[0] * v[0] + v[1] * v[1]));
    line(&out.lines, "updates %d", updates);
    line(&out.lines, "w %s %s bias %s", real(w[0], 6), real(w[1], 6), real(w[2], 6));
    line(&out.lines, "train correct %d/%d accuracy %s", train_correct, n, ratio(train_correct, n));
    line(&out.lines, "test correct %d/%d accuracy %s", test_correct, m, ratio(test_correct, m));
    line(&out.lines, "average w %s %s bias %s test correct %d/%d", real(out.average[0], 6),
         real(out.average[1], 6), real(out.average[2], 6), average_correct, m);
    line(&out.lines, "compare %s cosine %s test_agreement %d/%d", linear->kernel.name,
         real(cosine, 6), agreement, m);
    return out;
}
static char *multi_summary(const char *prefix, const Example *data,
                           const MultiPrediction *predictions, int count) {
    int rest = 0, one = 0, agreement = 0, ties = 0;
    for (int i = 0; i < count; ++i) {
        rest += predictions[i].ovr == data[i].label;
        one += predictions[i].ovo == data[i].label;
        agreement += predictions[i].ovr == predictions[i].ovo;
        ties += predictions[i].tie;
    }
    return format("%s ovr %d/%d %s ovo %d/%d %s agreement %d/%d vote_ties %d", prefix, rest, count,
                  ratio(rest, count), one, count, ratio(one, count), agreement, count, ties);
}
static Lines multi_report(const Input *input, const Multi *models) {
    Lines out = {0};
    int n = input->multi_train_count, m = input->multi_test_count;
    line(&out, "multiclass kernel %s C %s classes 3 train %d test %d", input->params.multi_name,
         real(input->params.multi_c, 4), n, m);
    line(&out, "ovr");
    for (int k = 1; k <= 3; ++k) {
        const Model *model = &models->rest[k - 1];
        int positive = 0, correct = 0;
        for (int i = 0; i < model->count; ++i)
            positive += model->data[i].label == 1;
        for (int i = 0; i < m; ++i)
            correct += sign(decision(model, input->multi_test[i].point)) ==
                       (input->multi_test[i].label == k ? 1 : -1);
        line(&out, "model %d-rest examples %d positives %d %s b %s %s test %d/%d", k, n, positive,
             support_text(model), real(model->b, 6), run_info(model), correct, m);
    }
    line(&out, "ovo");
    const int pairs[3][2] = {{1, 2}, {1, 3}, {2, 3}};
    for (int k = 0; k < 3; ++k) {
        const Model *model = &models->pairs[k];
        int positive = 0, correct = 0, count = 0;
        for (int i = 0; i < model->count; ++i)
            positive += model->data[i].label == 1;
        for (int i = 0; i < m; ++i)
            if (input->multi_test[i].label == pairs[k][0] ||
                input->multi_test[i].label == pairs[k][1]) {
                ++count;
                correct += sign(decision(model, input->multi_test[i].point)) ==
                           (input->multi_test[i].label == pairs[k][0] ? 1 : -1);
            }
        line(&out, "model %d-%d examples %d positives %d %s b %s %s test %d/%d", pairs[k][0],
             pairs[k][1], model->count, positive, support_text(model), real(model->b, 6),
             run_info(model), correct, count);
    }
    MultiPrediction train_predictions[150], test_predictions[100];
    for (int i = 0; i < n; ++i)
        train_predictions[i] = classify(models, input->multi_train[i].point);
    for (int i = 0; i < m; ++i)
        test_predictions[i] = classify(models, input->multi_test[i].point);
    line(&out, "predictions");
    for (int i = 0; i < m; ++i) {
        MultiPrediction p = test_predictions[i];
        line(&out, "%s class %d ovr %s %s %s pred %d ovo %s %s %s votes %d %d %d pred %d",
             input->multi_test[i].id, input->multi_test[i].label, real(p.rest[0], 4),
             real(p.rest[1], 4), real(p.rest[2], 4), p.ovr, real(p.pairs[0], 4),
             real(p.pairs[1], 4), real(p.pairs[2], 4), p.votes[0], p.votes[1], p.votes[2], p.ovo);
    }
    line(&out, "%s", multi_summary("train", input->multi_train, train_predictions, n));
    line(&out, "%s", multi_summary("test", input->multi_test, test_predictions, m));
    for (int mode = 0; mode < 2; ++mode) {
        int confusion[3][3];
        confusion_matrix(input->multi_test, test_predictions, m, mode == 0, confusion);
        line(&out, "confusion %s", mode == 0 ? "ovr" : "ovo");
        for (int i = 0; i < 3; ++i)
            line(&out, "%d %d %d", confusion[i][0], confusion[i][1], confusion[i][2]);
        for (int k = 0; k < 3; ++k) {
            int column = 0, row = 0;
            for (int j = 0; j < 3; ++j) {
                column += confusion[j][k];
                row += confusion[k][j];
            }
            line(&out, "class %d precision %s recall %s", k + 1, ratio(confusion[k][k], column),
                 ratio(confusion[k][k], row));
        }
    }
    return out;
}
static void frame(Lines *out, const char *cells, int width, int height) {
    char border[83];
    border[0] = '+';
    memset(border + 1, '-', (size_t)width);
    border[width + 1] = '+';
    border[width + 2] = '\0';
    line(out, "%s", border);
    for (int row = 0; row < height; ++row)
        line(out, "|%.*s|", width, cells + row * width);
    line(out, "%s", border);
}
static int location(const Params *p, const double *point, double dx, double dy) {
    double column = floor((point[0] - p->x_min) / dx), row = floor((p->y_max - point[1]) / dy);
    if (column < 0 || column >= p->width || row < 0 || row >= p->height)
        return -1;
    return (int)row * p->width + (int)column;
}
static Lines plots(const Input *input, const Model *models, int selected,
                   const Calibration *calibration, const Multi *multi) {
    const Params *p = &input->params;
    const Model *model = &models[selected];
    double dx = (p->x_max - p->x_min) / p->width, dy = (p->y_max - p->y_min) / p->height;
    char binary[3200], probabilities[3200], multiclass[3200];
    int signs[4][3200], assigned[3200], multi_assigned[3200], cell_count = p->width * p->height;
    for (int row = 0; row < p->height; ++row)
        for (int column = 0; column < p->width; ++column) {
            int cell = row * p->width + column;
            double point[2] = {p->x_min + (column + 0.5) * dx, p->y_max - (row + 0.5) * dy},
                   value = decision(model, point);
            binary[cell] = value >= 1 ? '+' : value > 0 ? '.' : value > -1 ? '-' : ' ';
            int digit = (int)floor(probability(value, calibration->a, calibration->b) * 10);
            probabilities[cell] = (char)('0' + (digit > 9 ? 9 : digit));
            MultiPrediction prediction = classify(multi, point);
            multiclass[cell] = prediction.ovr != prediction.ovo ? '?'
                               : prediction.ovr == 1            ? ' '
                               : prediction.ovr == 2            ? '.'
                                                                : ':';
            for (int k = 0; k < p->kernel_count; ++k)
                signs[k][cell] = sign(decision(&models[k], point));
            assigned[cell] = multi_assigned[cell] = -1;
        }
    int outside = 0, multi_outside = 0;
    for (int i = 0; i < input->train_count; ++i) {
        int cell = location(p, input->train[i].point, dx, dy);
        if (cell < 0) {
            ++outside;
            continue;
        }
        if (assigned[cell] < 0 || (model->alpha[i] > 0 && model->alpha[assigned[cell]] == 0))
            assigned[cell] = i;
    }
    for (int i = 0; i < input->multi_train_count; ++i) {
        int cell = location(p, input->multi_train[i].point, dx, dy);
        if (cell < 0) {
            ++multi_outside;
            continue;
        }
        if (multi_assigned[cell] < 0)
            multi_assigned[cell] = i;
    }
    int points = 0, multi_points = 0, count[4] = {0}, multi_count[4] = {0}, levels[10] = {0};
    for (int cell = 0; cell < cell_count; ++cell) {
        if (assigned[cell] >= 0) {
            ++points;
            int i = assigned[cell];
            binary[cell] = input->train[i].label == 1 ? (model->alpha[i] > 0 ? 'X' : 'x')
                                                      : (model->alpha[i] > 0 ? 'O' : 'o');
        }
        if (multi_assigned[cell] >= 0) {
            ++multi_points;
            multiclass[cell] = (char)('0' + input->multi_train[multi_assigned[cell]].label);
        }
        char b = binary[cell], m = multiclass[cell];
        if (b == '+')
            ++count[0];
        else if (b == '.')
            ++count[1];
        else if (b == '-')
            ++count[2];
        else if (b == ' ')
            ++count[3];
        if (m == ' ')
            ++multi_count[0];
        else if (m == '.')
            ++multi_count[1];
        else if (m == ':')
            ++multi_count[2];
        else if (m == '?')
            ++multi_count[3];
        ++levels[probabilities[cell] - '0'];
    }
    Lines out = {0};
    line(&out, "binary %s C %s", model->kernel.name, real(model->c, 4));
    line(&out, "x %s %s y %s %s grid %dx%d", real(p->x_min, 4), real(p->x_max, 4),
         real(p->y_min, 4), real(p->y_max, 4), p->width, p->height);
    frame(&out, binary, p->width, p->height);
    line(
        &out,
        "cells outer_positive %d inner_positive %d inner_negative %d outer_negative %d points %d outside %d",
        count[0], count[1], count[2], count[3], points, outside);
    line(&out, "");
    line(&out, "probability %s A %s B %s", model->kernel.name, real(calibration->a, 6),
         real(calibration->b, 6));
    frame(&out, probabilities, p->width, p->height);
    char *level_line = "levels";
    for (int i = 0; i < 10; ++i)
        level_line = joined(level_line, format(" %d", levels[i]));
    line(&out, "%s", level_line);
    line(&out, "");
    line(&out, "grid_agreement");
    for (int a = 0; a < p->kernel_count; ++a)
        for (int b = a + 1; b < p->kernel_count; ++b) {
            int agreement = 0, positive_a = 0, positive_b = 0;
            for (int cell = 0; cell < cell_count; ++cell) {
                agreement += signs[a][cell] == signs[b][cell];
                positive_a += signs[a][cell] == 1;
                positive_b += signs[b][cell] == 1;
            }
            line(&out, "%s %s %d/%d positive %d %d", models[a].kernel.name, models[b].kernel.name,
                 agreement, cell_count, positive_a, positive_b);
        }
    line(&out, "");
    line(&out, "multiclass %s C %s", p->multi_name, real(p->multi_c, 4));
    frame(&out, multiclass, p->width, p->height);
    line(&out, "cells class1 %d class2 %d class3 %d disagree %d points %d outside %d",
         multi_count[0], multi_count[1], multi_count[2], multi_count[3], multi_points,
         multi_outside);
    return out;
}
static const CV *sort_cv;
static const Params *sort_params;
static int compare_cv(const void *a, const void *b) {
    const CV *x = &sort_cv[*(const int *)a], *y = &sort_cv[*(const int *)b];
    if (x->correct != y->correct)
        return x->correct > y->correct ? -1 : 1;
    double first = sort_params->c_grid[x->candidate], second = sort_params->c_grid[y->candidate];
    return first != second ? (first < second ? -1 : 1) : x->kernel - y->kernel;
}
int main(void) {
    const Input *input = load();
    const Params *p = &input->params;
    int n = input->train_count, m = input->test_count;
    double *matrices[4];
    CV *cv = allocate((size_t)p->kernel_count * p->c_count, sizeof(CV));
    int cv_count = 0, best[4];
    for (int k = 0; k < p->kernel_count; ++k) {
        matrices[k] = kernel_matrix(p->kernels[k], input->train, n);
        best[k] = cv_count;
        for (int c = 0; c < p->c_count; ++c) {
            cv[cv_count] = cross_validate(input, k, c, matrices[k]);
            if (cv[cv_count].correct > cv[best[k]].correct)
                best[k] = cv_count;
            ++cv_count;
        }
    }
    int selected = 0;
    for (int k = 1; k < p->kernel_count; ++k)
        if (cv[best[k]].correct > cv[best[selected]].correct ||
            (cv[best[k]].correct == cv[best[selected]].correct &&
             p->c_grid[cv[best[k]].candidate] < p->c_grid[cv[best[selected]].candidate]))
            selected = k;
    double selected_c = p->c_grid[cv[best[selected]].candidate];
    Model models[4];
    Metrics evaluations[4];
    int linear = 0, multi_kernel = 0;
    bool found_linear = false;
    for (int k = 0; k < p->kernel_count; ++k) {
        models[k] =
            train(input->train, n, p->kernels[k], matrices[k], p->c_grid[cv[best[k]].candidate], p);
        evaluations[k] = metrics(input, &models[k]);
        if (!found_linear && strcmp(p->kernels[k].kind, "linear") == 0) {
            linear = k;
            found_linear = true;
        }
        if (strcmp(p->kernels[k].name, p->multi_name) == 0)
            multi_kernel = k;
    }
    int ranking[24];
    for (int i = 0; i < cv_count; ++i)
        ranking[i] = i;
    sort_cv = cv;
    sort_params = p;
    qsort(ranking, (size_t)cv_count, sizeof(int), compare_cv);
    Lines report = {0};
    line(&report, "cross_validation folds %d examples %d", p->folds, n);
    for (int k = 0; k < p->kernel_count; ++k) {
        CV *value = &cv[best[k]];
        line(&report, "best %s C %s correct %d/%d accuracy %s", p->kernels[k].name,
             real(p->c_grid[value->candidate], 4), value->correct, n, ratio(value->correct, n));
    }
    line(&report, "selected %s C %s", p->kernels[selected].name, real(selected_c, 4));
    line(&report, "ranking");
    for (int i = 0; i < cv_count; ++i) {
        CV *value = &cv[ranking[i]];
        line(&report, "%d %s C %s correct %d/%d", i + 1, p->kernels[value->kernel].name,
             real(p->c_grid[value->candidate], 4), value->correct, n);
    }
    line(&report, "cv_detail %s C %s", p->kernels[selected].name, real(selected_c, 4));
    for (int i = 0; i < p->folds; ++i) {
        FoldResult f = cv[best[selected]].folds[i];
        line(
            &report,
            "fold %d train %d test %d correct %d support_vectors %d passes %d steps %d converged %s",
            i + 1, f.train, f.test, f.correct, f.sv, f.passes, f.steps, f.converged ? "yes" : "no");
    }
    for (int k = 0; k < p->kernel_count; ++k) {
        line(&report, "");
        model_report(&report, input, &models[k], &evaluations[k]);
    }
    const Model *model = &models[selected];
    line(&report, "");
    line(&report, "training_log %s", model->kernel.name);
    for (int i = 0; i < model->pass_count;) {
        Pass pass = model->passes[i];
        if (pass.full) {
            double q, dual;
            objectives(pass.alpha, model->data, model->matrix, model->count, &q, &dual);
            line(&report, "pass %d full examined %d changed %d dual_objective %s", i + 1,
                 pass.examined, pass.changed, real(dual, 6));
            ++i;
        } else {
            int first = i, examined = 0, changed = 0;
            while (i < model->pass_count && !model->passes[i].full) {
                examined += model->passes[i].examined;
                changed += model->passes[i].changed;
                ++i;
            }
            line(&report, "passes %d-%d nonbound examined %d changed %d", first + 1, i, examined,
                 changed);
        }
    }
    line(&report, "");
    line(&report, "c_path %s", model->kernel.name);
    for (int c = 0; c < p->c_count; ++c) {
        Model current = train(input->train, n, model->kernel, model->matrix, p->c_grid[c], p);
        double train_values[200], test_values[100], q, dual;
        training_decisions(&current, train_values);
        decisions(&current, input->test, m, test_values);
        objectives(current.alpha, current.data, current.matrix, current.count, &q, &dual);
        Evaluation train_evaluation = evaluate(input->train, train_values, n),
                   test_evaluation = evaluate(input->test, test_values, m);
        line(&report, "C %s %s dual_objective %s train %d/%d test %d/%d %s", real(current.c, 4),
             support_text(&current), real(dual, 6), train_evaluation.tp + train_evaluation.tn, n,
             test_evaluation.tp + test_evaluation.tn, m, run_info(&current));
        free_model(&current);
    }
    line(&report, "");
    line(&report, "learning_curve %s C %s", model->kernel.name, real(selected_c, 4));
    Example learning_data[200];
    double learning_matrix[40000];
    for (int q = 0; q < p->learning_count; ++q) {
        int size = n * p->learning[q] / 100;
        for (int i = 0; i < size; ++i) {
            learning_data[i] = input->train[i];
            for (int j = 0; j < size; ++j)
                learning_matrix[i * size + j] = model->matrix[i * n + j];
        }
        Model current = train(learning_data, size, model->kernel, learning_matrix, selected_c, p);
        double train_values[200], test_values[100];
        training_decisions(&current, train_values);
        decisions(&current, input->test, m, test_values);
        Evaluation train_evaluation = evaluate(current.data, train_values, size),
                   test_evaluation = evaluate(input->test, test_values, m);
        line(&report, "size %d support_vectors %d train %d/%d test %d/%d %s", size,
             support(&current).total, train_evaluation.tp + train_evaluation.tn, size,
             test_evaluation.tp + test_evaluation.tn, m, run_info(&current));
        free_model(&current);
    }
    Calibration calibration =
        calibrate(input, model, cv[best[selected]].decisions, evaluations[selected].test);
    line(&report, "");
    for (int i = 0; i < calibration.lines.count; ++i)
        line(&report, "%s", calibration.lines.data[i]);
    Pegasos peg = pegasos(input, &models[linear], &evaluations[linear]);
    line(&report, "");
    for (int i = 0; i < peg.lines.count; ++i)
        line(&report, "%s", peg.lines.data[i]);
    line(&report, "");
    line(&report, "mcnemar");
    const double *comparison_values[5];
    const char *names[5];
    for (int k = 0; k < p->kernel_count; ++k) {
        comparison_values[k] = evaluations[k].test;
        names[k] = models[k].kernel.name;
    }
    comparison_values[p->kernel_count] = peg.test;
    names[p->kernel_count] = "pegasos";
    for (int a = 0; a <= p->kernel_count; ++a)
        for (int b = a + 1; b <= p->kernel_count; ++b) {
            int first = 0, second = 0;
            for (int i = 0; i < m; ++i) {
                bool x = sign(comparison_values[a][i]) == input->test[i].label,
                     y = sign(comparison_values[b][i]) == input->test[i].label;
                first += x && !y;
                second += y && !x;
            }
            int difference = abs(first - second) - 1, numerator = difference * difference,
                denominator = first + second;
            line(&report, "%s %s only_first %d only_second %d chi2 %s", names[a], names[b], first,
                 second, denominator ? real((double)numerator / denominator, 4) : "-");
        }
    Lines grid = {0};
    char *header = "kernel,C";
    for (int i = 1; i <= p->folds; ++i)
        header = joined(header, format(",fold%d", i));
    header = joined(header, ",correct,accuracy,support_vectors,passes,steps");
    line(&grid, "%s", header);
    for (int i = 0; i < cv_count; ++i) {
        CV *value = &cv[i];
        char *row =
            format("%s,%s", p->kernels[value->kernel].name, real(p->c_grid[value->candidate], 4));
        for (int f = 0; f < p->folds; ++f)
            row = joined(row, format(",%d", value->folds[f].correct));
        row = joined(row, format(",%d,%s,%d,%d,%d", value->correct, ratio(value->correct, n),
                                 value->sv, value->passes, value->steps));
        line(&grid, "%s", row);
    }
    Lines predictions = {0};
    header = "id,label";
    for (int k = 0; k < p->kernel_count; ++k)
        header = joined(header, format(",%s", p->kernels[k].name));
    header = joined(header, ",pegasos,predicted,probability");
    line(&predictions, "%s", header);
    for (int i = 0; i < m; ++i) {
        char *row = format("%s,%d", input->test[i].id, input->test[i].label);
        for (int k = 0; k < p->kernel_count; ++k)
            row = joined(row, format(",%s", real(evaluations[k].test[i], 4)));
        row = joined(row,
                     format(",%s,%d,%s", real(peg.test[i], 4), sign(evaluations[selected].test[i]),
                            real(calibration.probabilities[i], 4)));
        line(&predictions, "%s", row);
    }
    Multi *multi = train_multi(input, p->kernels[multi_kernel]);
    save("model.txt", report);
    save("cv_grid.csv", grid);
    save("predictions.csv", predictions);
    save("multiclass.txt", multi_report(input, multi));
    save("decision_plot.txt", plots(input, models, selected, &calibration, multi));
    for (int k = 0; k < p->kernel_count; ++k)
        free_model(&models[k]);
    for (int k = 0; k < 3; ++k) {
        free_model(&multi->rest[k]);
        free_model(&multi->pairs[k]);
    }
    return 0;
}
