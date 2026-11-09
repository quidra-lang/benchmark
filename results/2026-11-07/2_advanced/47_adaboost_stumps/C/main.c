#include "boosting.h"
static Vector scores(const Model *model, const Rows *rows, int count) {
    if (count < 0 || count > model->n)
        count = model->n;
    Vector out = {.n = rows->n};
    for (int i = 0; i < rows->n; ++i)
        for (int t = 0; t < count; ++t)
            out.v[i] += stump_output(&model->rounds[t].stump, rows->rows[i].values);
    return out;
}
static double magnitude(const Round *round, const char *variant) {
    if (strcmp(variant, "samme") == 0)
        return round->alpha;
    double out = 0;
    for (int b = 0; b <= round->stump.nthresholds; ++b)
        out = fmax(out, fabs(round->stump.values[b]));
    return out;
}
static double scale(const Model *model, int count) {
    if (count < 0)
        count = model->n;
    double out = 0;
    for (int t = 0; t < count; ++t)
        out += magnitude(&model->rounds[t], model->variant);
    return out;
}
static int error_count(const Rows *rows, Vector values) {
    int out = 0;
    for (int i = 0; i < rows->n; ++i)
        out += prediction(values.v[i]) != rows->rows[i].label;
    return out;
}
static double loss(const Rows *rows, Vector values, const char *variant) {
    double out = 0;
    for (int i = 0; i < rows->n; ++i)
        out += strcmp(variant, "logit") == 0 ? log(1 + exp(-2 * rows->rows[i].label * values.v[i]))
                                             : exp(-rows->rows[i].label * values.v[i]);
    return out / rows->n;
}
static void metrics(Text *out, const char *kind, const char *variant, int rounds, const Rows *rows,
                    Vector values) {
    int tp = 0, fp = 0, tn = 0, fn = 0;
    for (int i = 0; i < rows->n; ++i) {
        const bool yes = prediction(values.v[i]) == 1;
        if (rows->rows[i].label == 1) {
            tp += yes;
            fn += !yes;
        } else {
            fp += yes;
            tn += !yes;
        }
    }
    const Fraction area = auc(rows, values.v);
    line(
        out,
        "%s %s rounds %d correct %d/%d accuracy %s tp %d fp %d tn %d fn %d precision %s recall %s f1 %s auc %s loss %s",
        kind, variant, rounds, tp + tn, rows->n, ratio(tp + tn, rows->n), tp, fp, tn, fn, ratio(tp, tp + fp),
        ratio(tp, tp + fn), ratio(2 * tp, 2 * tp + fp + fn), ratio(area.numerator, area.denominator),
        real(loss(rows, values, variant), 4));
}
static Ints ordered(Vector values, bool decreasing) {
    Ints out = {.n = values.n};
    for (int i = 0; i < values.n; ++i) {
        int position = i;
        while (position > 0 && (decreasing ? values.v[i] > values.v[out.v[position - 1]]
                                           : values.v[i] < values.v[out.v[position - 1]])) {
            out.v[position] = out.v[position - 1];
            --position;
        }
        out.v[position] = i;
    }
    return out;
}
typedef struct {
    Vector value;
    Ints count, order;
} Importance;
static Importance importance(const Model *model, int d) {
    Importance out = {0};
    out.value.n = out.count.n = d;
    for (int t = 0; t < model->n; ++t) {
        const Round *round = &model->rounds[t];
        out.value.v[round->stump.feature] += magnitude(round, model->variant);
        ++out.count.v[round->stump.feature];
    }
    out.order = ordered(out.value, true);
    return out;
}
static void importance_lines(Text *out, Importance values, const char names[10][17]) {
    double total = 0;
    for (int j = 0; j < values.value.n; ++j)
        total += values.value.v[j];
    for (int rank = 0; rank < values.order.n; ++rank) {
        const int j = values.order.v[rank];
        line(out, "%d %s score %s share %s rounds %d", rank + 1, names[j], real(values.value.v[j], 4),
             real(values.value.v[j] / total, 4), values.count.v[j]);
    }
}
typedef struct {
    Ints train, test;
    Vector train_loss, test_loss, minimum;
} Curve;
static Curve curve(const Model *model, const Rows *train, const Rows *test) {
    Curve out = {0};
    out.train.n = out.test.n = out.train_loss.n = out.test_loss.n = out.minimum.n = model->n;
    for (int t = 1; t <= model->n; ++t) {
        const Vector a = scores(model, train, t), b = scores(model, test, t);
        out.train.v[t - 1] = error_count(train, a);
        out.test.v[t - 1] = error_count(test, b);
        out.train_loss.v[t - 1] = loss(train, a, model->variant);
        out.test_loss.v[t - 1] = loss(test, b, model->variant);
        double minimum = train->rows[0].label * a.v[0];
        for (int i = 1; i < train->n; ++i)
            minimum = fmin(minimum, train->rows[i].label * a.v[i]);
        out.minimum.v[t - 1] = minimum / scale(model, t);
    }
    return out;
}
static int first_minimum(Ints values) {
    int out = 0;
    for (int i = 1; i < values.n; ++i)
        if (values.v[i] < values.v[out])
            out = i;
    return out;
}
static int64_t draw(int64_t *state) {
    *state = (48271 * *state) % 2147483647;
    return *state;
}
static Rows relabel(Rows rows, int positive) {
    for (int i = 0; i < rows.n; ++i)
        rows.rows[i].label = rows.rows[i].label == positive ? 1 : -1;
    return rows;
}
typedef struct {
    int n, classes;
    double values[400][6];
} ClassScores;
static ClassScores class_scores(const Model *model, const Rows *rows, int classes, int count) {
    if (count < 0)
        count = model->n;
    ClassScores out = {.n = rows->n, .classes = classes};
    for (int i = 0; i < rows->n; ++i)
        for (int t = 0; t < count; ++t)
            out.values[i][(int)stump_output(&model->rounds[t].stump, rows->rows[i].values) - 1] +=
                model->rounds[t].alpha;
    return out;
}
static Ints class_predictions(const ClassScores *values) {
    Ints out = {.n = values->n};
    for (int i = 0; i < values->n; ++i) {
        int largest = 0;
        for (int k = 1; k < values->classes; ++k)
            if (values->values[i][k] > values->values[i][largest])
                largest = k;
        out.v[i] = largest + 1;
    }
    return out;
}
static int multiclass_errors(const Rows *rows, Ints values) {
    int out = 0;
    for (int i = 0; i < rows->n; ++i)
        out += rows->rows[i].label != values.v[i];
    return out;
}
static void confusion_lines(Text *out, const Rows *rows, Ints predictions, int classes) {
    int table[6][6];
    confusion(rows, predictions.v, classes, table);
    line(out, "confusion");
    for (int i = 0; i < classes; ++i) {
        for (int j = 0; j < classes; ++j)
            add(out, "%s%d", j ? " " : "", table[i][j]);
        line(out, "");
    }
    for (int k = 0; k < classes; ++k) {
        int row = 0, column = 0;
        for (int h = 0; h < classes; ++h) {
            row += table[k][h];
            column += table[h][k];
        }
        line(out, "class %d precision %s recall %s", k + 1, ratio(table[k][k], column),
             ratio(table[k][k], row));
    }
}
static Rows restricted(Rows rows, Ints features) {
    rows.d = features.n;
    for (int i = 0; i < rows.n; ++i) {
        double values[10];
        for (int j = 0; j < features.n; ++j)
            values[j] = rows.rows[i].values[features.v[j]];
        memcpy(rows.rows[i].values, values, (size_t)features.n * sizeof(double));
    }
    return rows;
}
static void insert_value(Vector *values, double value) {
    int position = 0;
    while (position < values->n && values->v[position] < value)
        ++position;
    if (position < values->n && values->v[position] == value)
        return;
    memmove(values->v + position + 1, values->v + position, (size_t)(values->n - position) * sizeof(double));
    values->v[position] = value;
    ++values->n;
}
int main(void) {
    mkdir("output", 0777);
    Input *input = read_input();
    const Params *p = &input->params;
    const Rows *train = &input->train, *test = &input->test;
    const int n = train->n, m = test->n, d = train->d, nv = p->nvariants;
    Text ensemble = {0}, error_curve = {0}, prediction_file = {0}, roc = {0}, margins = {0}, shapes = {0},
         multi = {0}, summary = {0}, experiments = {0};
    line(&error_curve, "variant,round,train_error,test_error,train_loss,test_loss,min_margin");
    add(&prediction_file, "id,variant,score,label");
    for (int j = 0; j < d; ++j)
        add(&prediction_file, ",%s", input->names[j]);
    line(&prediction_file, "");
    line(&roc, "variant,threshold,tp,fp");
    Model *folds[10];
    Ints fold_errors[10];
    Ints cv = {.n = p->rounds};
    for (int fold = 0; fold < p->folds; ++fold) {
        int validation = 0;
        for (int i = 0; i < n; ++i)
            validation += i % p->folds == fold;
        double weights[400] = {0};
        for (int i = 0; i < n; ++i)
            if (i % p->folds != fold)
                weights[i] = 1.0 / (n - validation);
        folds[fold] = discrete(train, p, p->rounds, 1, weights);
        fold_errors[fold] = (Ints){.n = p->rounds};
        for (int t = 1; t <= p->rounds; ++t) {
            const Vector values = scores(folds[fold], train, t);
            for (int i = 0; i < n; ++i)
                if (i % p->folds == fold)
                    fold_errors[fold].v[t - 1] += prediction(values.v[i]) != train->rows[i].label;
            cv.v[t - 1] += fold_errors[fold].v[t - 1];
        }
    }
    const int selected = first_minimum(cv) + 1;
    Vector oof = {.n = n};
    for (int fold = 0; fold < p->folds; ++fold) {
        const Vector values = scores(folds[fold], train, selected);
        for (int i = 0; i < n; ++i)
            if (i % p->folds == fold)
                oof.v[i] = values.v[i];
    }
    Model *full[4], *final[4];
    Curve curves[4];
    Vector train_scores[4], test_scores[4];
    Importance importances[4];
    int64_t permutation_state = p->permutation_seed;
    for (int v = 0; v < nv; ++v) {
        const char *variant = p->variants[v];
        full[v] = variant_train(train, p, variant);
        final[v] = malloc(sizeof *final[v]);
        *final[v] = *full[v];
        if (strcmp(variant, "discrete") == 0 && final[v]->n > selected)
            final[v]->n = selected;
        curves[v] = curve(full[v], train, test);
        train_scores[v] = scores(final[v], train, -1);
        test_scores[v] = scores(final[v], test, -1);
        importances[v] = importance(final[v], d);
        if (v) {
            line(&ensemble, "");
            line(&margins, "");
            line(&shapes, "");
        }
        const Model *trained = full[v], *fit = final[v];
        add(&ensemble, "variant %s rounds %d stop %s", variant, trained->n, trained->stop);
        if (strcmp(variant, "real") == 0)
            add(&ensemble, " bins %d smoothing %s convergence %s", p->bins, real(p->smoothing, 4),
                real(p->convergence, 6));
        if (strcmp(variant, "logit") == 0)
            add(&ensemble, " clip %s", real(p->clip, 4));
        line(&ensemble, "");
        if (strcmp(variant, "real") == 0)
            for (int j = 0; j < d; ++j) {
                add(&ensemble, "cuts %s", input->names[j]);
                for (int b = 0; b < p->bins - 1; ++b)
                    add(&ensemble, " %s", real(trained->cuts[j][b], 4));
                line(&ensemble, "");
            }
        for (int t = 0; t < trained->n; ++t) {
            const Round *round = &trained->rounds[t];
            add(&ensemble, "round %d feature %s", t + 1, input->names[round->stump.feature]);
            if (strcmp(variant, "real") == 0) {
                add(&ensemble, " z %s bound %s values", real(round->z, 4), real(round->bound, 4));
                for (int b = 0; b <= round->stump.nthresholds; ++b)
                    add(&ensemble, " %s", real(round->stump.values[b], 4));
            } else {
                add(&ensemble, " threshold %s", real(round->stump.thresholds[0], 4));
                if (strcmp(variant, "discrete") == 0)
                    add(&ensemble, " polarity %d error %s alpha %s z %s bound %s", round->polarity,
                        real(round->error, 4), real(round->alpha, 4), real(round->z, 4),
                        real(round->bound, 4));
                else {
                    add(&ensemble, " left %s right %s error %s", real(round->stump.values[0], 4),
                        real(round->stump.values[1], 4), real(round->error, 4));
                    if (strcmp(variant, "logit") == 0)
                        add(&ensemble, " loss %s", real(round->loss, 4));
                }
            }
            line(&ensemble, "");
            if (strcmp(variant, "discrete") == 0) {
                int maximum = 0;
                double squares = 0;
                for (int i = 0; i < n; ++i) {
                    if (round->weights[i] > round->weights[maximum])
                        maximum = i;
                    squares += round->weights[i] * round->weights[i];
                }
                line(&ensemble, "weights %d max %s id %s ess %s", t + 1, real(round->weights[maximum], 6),
                     train->rows[maximum].id, real(1 / squares, 4));
            }
            line(&error_curve, "%s,%d,%s,%s,%s,%s,%s", variant, t + 1, ratio(curves[v].train.v[t], n),
                 ratio(curves[v].test.v[t], m), real(curves[v].train_loss.v[t], 4),
                 real(curves[v].test_loss.v[t], 4), real(curves[v].minimum.v[t], 4));
        }
        if (strcmp(variant, "discrete") == 0) {
            line(&ensemble, "cv folds %d selected %d errors %d/%d", p->folds, selected, cv.v[selected - 1],
                 n);
            for (int fold = 0; fold < p->folds; ++fold) {
                int validation = 0;
                for (int i = 0; i < n; ++i)
                    validation += i % p->folds == fold;
                line(&ensemble, "fold %d train %d validation %d rounds %d stop %s selected %d/%d final %d/%d",
                     fold + 1, n - validation, validation, folds[fold]->n, folds[fold]->stop,
                     fold_errors[fold].v[selected - 1], validation, fold_errors[fold].v[p->rounds - 1],
                     validation);
            }
            add(&ensemble, "cv_errors");
            for (int t = 0; t < p->rounds; ++t)
                add(&ensemble, " %d", cv.v[t]);
            line(&ensemble, "");
        }
        const double total = scale(fit, -1);
        Vector train_margin = {.n = n}, test_margin = {.n = m};
        for (int i = 0; i < n; ++i)
            train_margin.v[i] = train->rows[i].label * train_scores[v].v[i] / total;
        for (int i = 0; i < m; ++i)
            test_margin.v[i] = test->rows[i].label * test_scores[v].v[i] / total;
        line(&margins, "variant %s rounds %d scale %s", variant, fit->n, real(total, 4));
        for (int set = 0; set < 2; ++set) {
            const Vector values = set ? test_margin : train_margin;
            const char *kind = set ? "test" : "train";
            double sum = 0, minimum = values.v[0];
            for (int i = 0; i < values.n; ++i) {
                sum += values.v[i];
                minimum = fmin(minimum, values.v[i]);
            }
            line(&margins, "%s min %s mean %s", kind, real(minimum, 4), real(sum / values.n, 4));
            for (int k = 0; k < p->margins.n; ++k) {
                const double theta = p->margins.v[k];
                const int count = margin_count(values.v, values.n, theta);
                line(&margins, "%s le %s %d/%d %s", kind, real(theta, 4), count, values.n,
                     ratio(count, values.n));
            }
            if (!set) {
                int histogram[20] = {0};
                for (int i = 0; i < values.n; ++i) {
                    int bin = (int)floor((values.v[i] + 1) * 10);
                    if (bin > 19)
                        bin = 19;
                    ++histogram[bin];
                }
                add(&margins, "histogram");
                for (int bin = 0; bin < 20; ++bin)
                    add(&margins, " %d", histogram[bin]);
                line(&margins, "");
                const Ints order = ordered(values, false);
                for (int rank = 0; rank < 5; ++rank) {
                    const int i = order.v[rank];
                    line(&margins, "hardest %s label %d margin %s", train->rows[i].id, train->rows[i].label,
                         real(values.v[i], 4));
                }
            } else
                for (int k = 0; k < p->margins.n; ++k) {
                    const double theta = p->margins.v[k];
                    int count = 0, correct = 0;
                    for (int i = 0; i < m; ++i)
                        if (fabs(values.v[i]) > theta) {
                            ++count;
                            correct += prediction(test_scores[v].v[i]) == test->rows[i].label;
                        }
                    line(&margins, "test confident %s %d/%d correct %d/%d %s", real(theta, 4), count, m,
                         correct, count, ratio(correct, count));
                }
        }
        line(&margins, "importance");
        importance_lines(&margins, importances[v], input->names);
        const int base = m - error_count(test, test_scores[v]);
        line(&margins, "permutation repeats %d base %d/%d", p->permutations, base, m);
        Vector drops = {.n = d};
        int minimum[10], maximum[10] = {0};
        for (int j = 0; j < d; ++j) {
            minimum[j] = m;
            for (int repeat = 0; repeat < p->permutations; ++repeat) {
                int permutation[400];
                for (int i = 0; i < m; ++i)
                    permutation[i] = i;
                for (int i = m - 1; i >= 1; --i) {
                    const int other = (int)(draw(&permutation_state) % (i + 1)), temporary = permutation[i];
                    permutation[i] = permutation[other];
                    permutation[other] = temporary;
                }
                int correct = 0;
                for (int i = 0; i < m; ++i) {
                    double values[10];
                    memcpy(values, test->rows[i].values, sizeof values);
                    values[j] = test->rows[permutation[i]].values[j];
                    double value = 0;
                    for (int t = 0; t < fit->n; ++t)
                        value += stump_output(&fit->rounds[t].stump, values);
                    correct += prediction(value) == test->rows[i].label;
                }
                drops.v[j] += base - correct;
                if (correct < minimum[j])
                    minimum[j] = correct;
                if (correct > maximum[j])
                    maximum[j] = correct;
            }
        }
        const Ints permutation_order = ordered(drops, true);
        for (int rank = 0; rank < d; ++rank) {
            const int j = permutation_order.v[rank];
            line(&margins, "%d %s drop %s min %d/%d max %d/%d", rank + 1, input->names[j],
                 real(drops.v[j] / (p->permutations * m), 4), minimum[j], m, maximum[j], m);
        }
        line(&shapes, "variant %s rounds %d", variant, fit->n);
        for (int j = 0; j < d; ++j) {
            const Stump *collected[50];
            int ncollected = 0;
            Vector ends = {0};
            for (int t = 0; t < fit->n; ++t)
                if (fit->rounds[t].stump.feature == j) {
                    const Stump *stump = &fit->rounds[t].stump;
                    collected[ncollected++] = stump;
                    for (int b = 0; b < stump->nthresholds; ++b)
                        insert_value(&ends, stump->thresholds[b]);
                }
            Vector values = {.n = ends.n + 1};
            for (int interval = 0; interval < values.n; ++interval)
                for (int t = 0; t < ncollected; ++t) {
                    const Stump *stump = collected[t];
                    int bin = 0;
                    if (interval)
                        for (int b = 0; b < stump->nthresholds; ++b)
                            bin += stump->thresholds[b] <= ends.v[interval - 1];
                    values.v[interval] += stump->values[bin];
                }
            double low = values.v[0], high = low;
            for (int i = 1; i < values.n; ++i) {
                low = fmin(low, values.v[i]);
                high = fmax(high, values.v[i]);
            }
            line(&shapes, "feature %s rounds %d cuts %d range %s", input->names[j], ncollected, ends.n,
                 real(high - low, 4));
            for (int interval = 0; interval < values.n; ++interval)
                line(&shapes, "interval %s %s value %s", interval ? real(ends.v[interval - 1], 4) : "-inf",
                     interval < ends.n ? real(ends.v[interval], 4) : "inf", real(values.v[interval], 4));
        }
        Vector thresholds = {0};
        for (int i = 0; i < m; ++i)
            insert_value(&thresholds, test_scores[v].v[i]);
        for (int k = thresholds.n - 1; k >= 0; --k) {
            const double threshold = thresholds.v[k];
            int tp = 0, fp = 0;
            for (int i = 0; i < m; ++i)
                if (test_scores[v].v[i] >= threshold) {
                    tp += test->rows[i].label == 1;
                    fp += test->rows[i].label == -1;
                }
            line(&roc, "%s,%s,%d,%d", variant, real(threshold, 4), tp, fp);
        }
    }
    for (int i = 0; i < m; ++i)
        for (int v = 0; v < nv; ++v) {
            add(&prediction_file, "%s,%s,%s,%d", test->rows[i].id, p->variants[v],
                real(test_scores[v].v[i], 4), prediction(test_scores[v].v[i]));
            double contributions[10] = {0};
            for (int t = 0; t < final[v]->n; ++t) {
                const Round *round = &final[v]->rounds[t];
                contributions[round->stump.feature] += stump_output(&round->stump, test->rows[i].values);
            }
            for (int j = 0; j < d; ++j)
                add(&prediction_file, ",%s", real(contributions[j], 4));
            line(&prediction_file, "");
        }
    Model *multi_model = samme(&input->multi_train, p);
    const ClassScores same_train_scores = class_scores(multi_model, &input->multi_train, p->classes, -1),
                      same_test_scores = class_scores(multi_model, &input->multi_test, p->classes, -1);
    const Ints same_train = class_predictions(&same_train_scores),
               same_test = class_predictions(&same_test_scores);
    line(&multi, "samme classes %d train %d test %d rounds %d stop %s", p->classes, input->multi_train.n,
         input->multi_test.n, multi_model->n, multi_model->stop);
    for (int t = 0; t < multi_model->n; ++t) {
        const Round *round = &multi_model->rounds[t];
        line(&multi, "round %d feature %s threshold %s left %d right %d error %s alpha %s", t + 1,
             input->multi_names[round->stump.feature], real(round->stump.thresholds[0], 4),
             (int)round->stump.values[0], (int)round->stump.values[1], real(round->error, 4),
             real(round->alpha, 4));
        const ClassScores a = class_scores(multi_model, &input->multi_train, p->classes, t + 1),
                          b = class_scores(multi_model, &input->multi_test, p->classes, t + 1);
        const int ae = multiclass_errors(&input->multi_train, class_predictions(&a)),
                  be = multiclass_errors(&input->multi_test, class_predictions(&b));
        line(&error_curve, "samme,%d,%s,%s,-,-,-", t + 1, ratio(ae, input->multi_train.n),
             ratio(be, input->multi_test.n));
    }
    const int multi_train_error = multiclass_errors(&input->multi_train, same_train),
              multi_test_error = multiclass_errors(&input->multi_test, same_test);
    line(&multi, "train errors %d/%d rate %s", multi_train_error, input->multi_train.n,
         ratio(multi_train_error, input->multi_train.n));
    line(&multi, "test errors %d/%d rate %s", multi_test_error, input->multi_test.n,
         ratio(multi_test_error, input->multi_test.n));
    confusion_lines(&multi, &input->multi_test, same_test, p->classes);
    line(&multi, "importance");
    importance_lines(&multi, importance(multi_model, input->multi_train.d), input->multi_names);
    line(&multi, "");
    line(&multi, "ovr classes %d rounds %d", p->classes, p->samme_rounds);
    ClassScores ovr_train = {.n = input->multi_train.n, .classes = p->classes},
                ovr_test = {.n = input->multi_test.n, .classes = p->classes};
    for (int k = 1; k <= p->classes; ++k) {
        const Rows a = relabel(input->multi_train, k), b = relabel(input->multi_test, k);
        Model *model = discrete(&a, p, p->samme_rounds, 1, NULL);
        const Vector av = scores(model, &a, -1), bv = scores(model, &b, -1);
        int positives = 0;
        for (int i = 0; i < a.n; ++i)
            positives += a.rows[i].label == 1;
        line(&multi, "class %d rounds %d stop %s positives %d train_errors %d/%d test_errors %d/%d", k,
             model->n, model->stop, positives, error_count(&a, av), a.n, error_count(&b, bv), b.n);
        for (int i = 0; i < a.n; ++i)
            ovr_train.values[i][k - 1] = av.v[i];
        for (int i = 0; i < b.n; ++i)
            ovr_test.values[i][k - 1] = bv.v[i];
        free(model);
    }
    const Ints ovr_train_prediction = class_predictions(&ovr_train),
               ovr_test_prediction = class_predictions(&ovr_test);
    const int ovr_train_error = multiclass_errors(&input->multi_train, ovr_train_prediction),
              ovr_test_error = multiclass_errors(&input->multi_test, ovr_test_prediction);
    line(&multi, "train errors %d/%d rate %s", ovr_train_error, input->multi_train.n,
         ratio(ovr_train_error, input->multi_train.n));
    line(&multi, "test errors %d/%d rate %s", ovr_test_error, input->multi_test.n,
         ratio(ovr_test_error, input->multi_test.n));
    confusion_lines(&multi, &input->multi_test, ovr_test_prediction, p->classes);
    int same = 0;
    for (int i = 0; i < input->multi_test.n; ++i)
        same += same_test.v[i] == ovr_test_prediction.v[i];
    line(&multi, "agreement %d/%d", same, input->multi_test.n);
    line(&multi, "");
    line(&multi, "predictions");
    for (int i = 0; i < input->multi_test.n; ++i) {
        add(&multi, "%s class %d samme %d ovr %d scores", input->multi_test.rows[i].id,
            input->multi_test.rows[i].label, same_test.v[i], ovr_test_prediction.v[i]);
        for (int k = 0; k < p->classes; ++k)
            add(&multi, " %s", real(same_test_scores.values[i][k], 4));
        line(&multi, "");
    }
    int train_positive = 0, test_positive = 0;
    for (int i = 0; i < n; ++i)
        train_positive += train->rows[i].label == 1;
    for (int i = 0; i < m; ++i)
        test_positive += test->rows[i].label == 1;
    line(&summary, "data train %d test %d features %d positives %d %d", n, m, d, train_positive,
         test_positive);
    for (int j = 0; j < d; ++j) {
        add(&summary, "feature %s", input->names[j]);
        for (int set = 0; set < 2; ++set) {
            const Rows *rows = set ? test : train;
            Vector distinct = {0};
            double sum = 0, minimum = rows->rows[0].values[j], maximum = minimum;
            for (int i = 0; i < rows->n; ++i) {
                const double value = rows->rows[i].values[j];
                sum += value;
                minimum = fmin(minimum, value);
                maximum = fmax(maximum, value);
                insert_value(&distinct, value);
            }
            add(&summary, " %s %s %s %s %d", set ? "test" : "train", real(minimum, 4), real(maximum, 4),
                real(sum / rows->n, 4), distinct.n);
        }
        line(&summary, "");
    }
    line(&summary, "cv selected %d errors %d/%d rate %s", selected, cv.v[selected - 1], n,
         ratio(cv.v[selected - 1], n));
    metrics(&summary, "oof", "discrete", selected, train, oof);
    Vector committee_train = {.n = n}, committee_test = {.n = m};
    int committee_rounds = 0;
    for (int v = 0; v < nv; ++v) {
        metrics(&summary, "train", p->variants[v], final[v]->n, train, train_scores[v]);
        metrics(&summary, "test", p->variants[v], final[v]->n, test, test_scores[v]);
        const double total = scale(final[v], -1);
        for (int i = 0; i < n; ++i)
            committee_train.v[i] += train_scores[v].v[i] / total;
        for (int i = 0; i < m; ++i)
            committee_test.v[i] += test_scores[v].v[i] / total;
        committee_rounds += final[v]->n;
    }
    metrics(&summary, "train", "committee", committee_rounds, train, committee_train);
    metrics(&summary, "test", "committee", committee_rounds, test, committee_test);
    for (int v = 0; v < nv; ++v) {
        const int a = first_minimum(curves[v].train), b = first_minimum(curves[v].test);
        line(&summary, "curve %s rounds %d train_min %d/%d at %d test_min %d/%d at %d", p->variants[v],
             full[v]->n, curves[v].train.v[a], n, a + 1, curves[v].test.v[b], m, b + 1);
    }
    Ints wrong = {0};
    for (int i = 0; i < m; ++i) {
        bool all = true;
        for (int v = 0; v < nv; ++v)
            all = all && prediction(test_scores[v].v[i]) != test->rows[i].label;
        if (all)
            wrong.v[wrong.n++] = i;
    }
    add(&summary, "all_wrong %d", wrong.n);
    for (int k = 0; k < wrong.n; ++k)
        add(&summary, " %s", test->rows[wrong.v[k]].id);
    line(&summary, "");
    line(&summary, "agreement");
    for (int a = 0; a < nv - 1; ++a)
        for (int b = a + 1; b < nv; ++b) {
            int agreement = 0, n1 = 0, n2 = 0;
            for (int i = 0; i < m; ++i) {
                const int x = prediction(test_scores[a].v[i]), y = prediction(test_scores[b].v[i]);
                agreement += x == y;
                n1 += x == test->rows[i].label && y != test->rows[i].label;
                n2 += y == test->rows[i].label && x != test->rows[i].label;
            }
            const int numerator = (abs(n1 - n2) - 1) * (abs(n1 - n2) - 1);
            line(&summary, "%s %s agree %d/%d only_first %d only_second %d chi2 %s", p->variants[a],
                 p->variants[b], agreement, m, n1, n2, ratio(numerator, n1 + n2));
        }
    line(&summary, "bootstrap samples %d seed %lld", p->bootstrap, (long long)p->bootstrap_seed);
    int64_t bootstrap_state = p->bootstrap_seed;
    int bootstrap[4][1000] = {0};
    for (int sample = 0; sample < p->bootstrap; ++sample)
        for (int draw_index = 0; draw_index < m; ++draw_index) {
            const int i = (int)(draw(&bootstrap_state) % m);
            for (int v = 0; v < nv; ++v)
                bootstrap[v][sample] += prediction(test_scores[v].v[i]) == test->rows[i].label;
        }
    for (int v = 0; v < nv; ++v) {
        int values[1000], sum = 0;
        for (int i = 0; i < p->bootstrap; ++i) {
            const int value = bootstrap[v][i];
            sum += value;
            int position = i;
            while (position > 0 && value < values[position - 1]) {
                values[position] = values[position - 1];
                --position;
            }
            values[position] = value;
        }
        const int g = p->bootstrap / 40;
        line(&summary, "%s mean %s low %s high %s", p->variants[v], ratio(sum, p->bootstrap * m),
             ratio(values[g], m), ratio(values[p->bootstrap - g - 1], m));
    }
    for (int a = 0; a < nv - 1; ++a)
        for (int b = a + 1; b < nv; ++b) {
            int first = 0, tie = 0, second = 0;
            for (int sample = 0; sample < p->bootstrap; ++sample) {
                first += bootstrap[a][sample] > bootstrap[b][sample];
                tie += bootstrap[a][sample] == bootstrap[b][sample];
                second += bootstrap[a][sample] < bootstrap[b][sample];
            }
            line(&summary, "%s %s first %d tie %d second %d", p->variants[a], p->variants[b], first, tie,
                 second);
        }
    for (int v = 0; v < nv; ++v) {
        int counts[5] = {0}, positives[5] = {0};
        double sums[5] = {0}, brier = 0;
        for (int i = 0; i < m; ++i) {
            const double probability = 1 / (1 + exp(-2 * test_scores[v].v[i])),
                         delta = probability - (test->rows[i].label == 1 ? 1 : 0);
            brier += delta * delta;
            int bin = (int)floor(probability * 5);
            if (bin > 4)
                bin = 4;
            ++counts[bin];
            sums[bin] += probability;
            positives[bin] += test->rows[i].label == 1;
        }
        line(&summary, "calibration %s brier %s", p->variants[v], real(brier / m, 4));
        const char *ranges[] = {"0.0-0.2", "0.2-0.4", "0.4-0.6", "0.6-0.8", "0.8-1.0"};
        for (int bin = 0; bin < 5; ++bin)
            line(&summary, "bin %s count %d mean %s positives %d", ranges[bin], counts[bin],
                 counts[bin] ? real(sums[bin] / counts[bin], 4) : "-", positives[bin]);
    }
    for (int k = 0; k < p->sizes.n; ++k) {
        const int percent = p->sizes.v[k], size = n * percent / 100;
        Rows rows = *train;
        rows.n = size;
        line(&experiments, "size %d rows %d", percent, size);
        for (int v = 0; v < nv; ++v) {
            const char *variant = p->variants[v];
            Model *model = variant_train(&rows, p, variant);
            line(&experiments, "%s rounds %d stop %s train_errors %d/%d test_errors %d/%d", variant, model->n,
                 model->stop, error_count(&rows, scores(model, &rows, -1)), size,
                 error_count(test, scores(model, test, -1)), m);
            free(model);
        }
    }
    for (int k = 0; k < p->shrinkage.n; ++k) {
        const double shrinkage = p->shrinkage.v[k];
        Model *model = discrete(train, p, p->rounds, shrinkage, NULL);
        const Curve values = curve(model, train, test);
        const int minimum = first_minimum(values.test);
        line(&experiments,
             "shrinkage %s rounds %d stop %s train_errors %d/%d test_errors %d/%d test_min %d/%d at %d",
             real(shrinkage, 4), model->n, model->stop, error_count(train, scores(model, train, -1)), n,
             error_count(test, scores(model, test, -1)), m, values.test.v[minimum], m, minimum + 1);
        free(model);
    }
    int discrete_index = 0;
    while (strcmp(p->variants[discrete_index], "discrete") != 0)
        ++discrete_index;
    const Ints feature_order = importances[discrete_index].order;
    for (int count = 1; count <= d; ++count) {
        Ints features = {.n = count};
        for (int i = 0; i < count; ++i) {
            const int value = feature_order.v[i];
            int position = i;
            while (position > 0 && value < features.v[position - 1]) {
                features.v[position] = features.v[position - 1];
                --position;
            }
            features.v[position] = value;
        }
        const Rows a = restricted(*train, features), b = restricted(*test, features);
        Model *model = discrete(&a, p, selected, 1, NULL);
        add(&experiments, "top %d features", count);
        for (int j = 0; j < count; ++j)
            add(&experiments, " %s", input->names[features.v[j]]);
        line(&experiments, " rounds %d train_errors %d/%d test_errors %d/%d", model->n,
             error_count(&a, scores(model, &a, -1)), n, error_count(&b, scores(model, &b, -1)), m);
        free(model);
    }
    for (int k = 0; k < p->noise.n; ++k) {
        const int percent = p->noise.v[k], flipped = n * percent / 100;
        int64_t state = p->noise_seed;
        int permutation[400];
        for (int i = 0; i < n; ++i)
            permutation[i] = i;
        for (int i = 0; i < flipped; ++i) {
            const int other = (int)(draw(&state) % (n - i)) + i, temporary = permutation[i];
            permutation[i] = permutation[other];
            permutation[other] = temporary;
        }
        Rows rows = *train;
        bool changed[400] = {0};
        for (int i = 0; i < flipped; ++i) {
            rows.rows[permutation[i]].label = -rows.rows[permutation[i]].label;
            changed[permutation[i]] = true;
        }
        line(&experiments, "noise %d flipped %d", percent, flipped);
        for (int v = 0; v < nv; ++v) {
            const char *variant = p->variants[v];
            Model *model = variant_train(&rows, p, variant);
            const Curve values = curve(model, &rows, test);
            const int minimum = first_minimum(values.test);
            double weight = 0;
            for (int i = 0; i < n; ++i)
                if (changed[i])
                    weight += model->rounds[model->n - 1].weights[i];
            line(
                &experiments,
                "%s rounds %d stop %s train_errors %d/%d test_errors %d/%d test_min %d/%d at %d flipped_weight %s",
                variant, model->n, model->stop, error_count(&rows, scores(model, &rows, -1)), n,
                error_count(test, scores(model, test, -1)), m, values.test.v[minimum], m, minimum + 1,
                real(weight, 4));
            free(model);
        }
    }
    write_report("ensemble.txt", ensemble);
    write_report("error_curve.csv", error_curve);
    write_report("predictions.csv", prediction_file);
    write_report("roc.csv", roc);
    write_report("margins.txt", margins);
    write_report("shapes.txt", shapes);
    write_report("samme.txt", multi);
    write_report("summary.txt", summary);
    write_report("experiments.txt", experiments);
    for (int fold = 0; fold < p->folds; ++fold)
        free(folds[fold]);
    for (int v = 0; v < nv; ++v) {
        free(full[v]);
        free(final[v]);
    }
    free(multi_model);
    free(ensemble.data);
    free(error_curve.data);
    free(prediction_file.data);
    free(roc.data);
    free(margins.data);
    free(shapes.data);
    free(multi.data);
    free(summary.data);
    free(experiments.data);
    free(input);
    return 0;
}
