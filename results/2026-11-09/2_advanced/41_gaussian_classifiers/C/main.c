#include "gaussian.h"
#include <sys/stat.h>
static const char *model_names[] = {"NB", "LDA", "QDA", "ENSEMBLE"};
static void paragraph(Lines *out, Lines *part) {
    if (out->count)
        line_push(out, text(""));
    lines_extend(out, part);
    lines_free(part);
}
static void extend_owned(Lines *out, Lines part) {
    lines_extend(out, &part);
    lines_free(&part);
}
static Model fit(const Dataset *data, const Rows *rows, Features features, int kind) {
    return train(rows, features, data->classes.count, kind, data->params.empirical, data->params.smoothing,
                 data->params.gamma);
}
static void predictions(const Dataset *data, const Model *model, const Rows *rows, int *out) {
    for (int i = 0; i < rows->count; ++i)
        out[i] = predict(model, &rows->data[i].values, data->costs).predicted;
}
static int correct_count(const Rows *rows, const int *predicted) {
    int out = 0;
    for (int i = 0; i < rows->count; ++i)
        out += rows->data[i].label == predicted[i];
    return out;
}
static int model_correct(const Dataset *data, const Model *model, const Rows *rows) {
    int prediction[400];
    predictions(data, model, rows, prediction);
    return correct_count(rows, prediction);
}
typedef struct {
    int prediction[400], fold_correct[10], correct;
} CrossValidation;
static CrossValidation cross_validate_values(const Dataset *data, Features features, int kind,
                                             double smoothing, double gamma) {
    CrossValidation out = {0};
    for (int fold = 0; fold < data->params.folds; ++fold) {
        Rows training = {0};
        for (int i = 0; i < data->train.count; ++i)
            if (data->train.data[i].id % data->params.folds != fold)
                row_push(&training, data->train.data[i]);
        Model model =
            train(&training, features, data->classes.count, kind, data->params.empirical, smoothing, gamma);
        free(training.data);
        for (int i = 0; i < data->train.count; ++i)
            if (data->train.data[i].id % data->params.folds == fold) {
                out.prediction[i] = predict(&model, &data->train.data[i].values, data->costs).predicted;
                if (out.prediction[i] == data->train.data[i].label) {
                    ++out.fold_correct[fold];
                    ++out.correct;
                }
            }
    }
    return out;
}
static CrossValidation cross_validate(const Dataset *data, Features features, int kind) {
    return cross_validate_values(data, features, kind, data->params.smoothing, data->params.gamma);
}
static void confusion_lines(Lines *out, const Measures *measures, const Lines *classes) {
    for (int a = 0; a < measures->classes; ++a) {
        char *line = format("confusion %s", classes->data[a]);
        for (int b = 0; b < measures->classes; ++b) {
            char *next = format("%s %d", line, measures->confusion[a][b]);
            free(line);
            line = next;
        }
        line_push(out, line);
    }
}
static char *mcnemar_line(const char *a, const char *b, McNemar test) {
    return format("%s %s b01 %d b10 %d chi2 %s significant %s", a, b, test.b01, test.b10, real(test.chi2),
                  test.chi2 > 3.841 ? "yes" : "no");
}
static void eigen_order(const Eigen *eigen, int size, int *order) {
    for (int i = 0; i < size; ++i)
        order[i] = i;
    for (int i = 1; i < size; ++i) {
        int selected = order[i], j = i;
        while (j > 0 &&
               (eigen->values.v[selected] > eigen->values.v[order[j - 1]] ||
                (eigen->values.v[selected] == eigen->values.v[order[j - 1]] && selected < order[j - 1]))) {
            order[j] = order[j - 1];
            --j;
        }
        order[j] = selected;
    }
}
typedef struct {
    Dataset *data;
    Features all;
    Model models[3];
    Prediction test[3][200];
    int labels[4][200];
    CrossValidation cv[3];
} App;
static Lines model_report(const App *app) {
    const Dataset *data = app->data;
    int size = app->all.count, classes = data->classes.count;
    const Statistics *stats = &app->models[0].stats;
    Lines out = {0}, part = {0};
    line_push(&part, format("features %s", names(app->all, &data->features)));
    char *class_line = text("classes");
    for (int k = 0; k < classes; ++k) {
        char *next = format("%s %s", class_line, data->classes.data[k]);
        free(class_line);
        class_line = next;
    }
    line_push(&part, class_line);
    line_push(&part, format("prior_mode %s", data->params.empirical ? "empirical" : "uniform"));
    for (int k = 0; k < classes; ++k)
        line_push(&part, format("class %s letter %c count %d prior %s mean %s", data->classes.data[k],
                                data->classes.data[k][0] - 'a' + 'A', stats->counts[k],
                                real(stats->priors[k]), numbers(stats->means[k], size)));
    paragraph(&out, &part);
    line_push(&part, text("model NB"));
    line_push(&part, format("smoothing epsilon %s max_variance %s added %s", real(data->params.smoothing),
                            real(app->models[0].max_variance), real(app->models[0].added)));
    for (int k = 0; k < classes; ++k) {
        Vector diagonal = {0};
        for (int j = 0; j < size; ++j)
            diagonal.v[j] = app->models[0].covariance[k].v[j][j];
        line_push(&part, format("class %s variance %s log_det %s", data->classes.data[k],
                                numbers(diagonal, size), real(app->models[0].log_det[k])));
    }
    paragraph(&out, &part);
    line_push(&part, text("model LDA"));
    line_push(&part, format("log_det %s", real(app->models[1].log_det[0])));
    for (int a = 0; a < size; ++a) {
        Vector row = {0};
        for (int j = 0; j < size; ++j)
            row.v[j] = app->models[1].covariance[0].v[a][j];
        line_push(&part, format("  %s", numbers(row, size)));
    }
    for (int k = 0; k < classes; ++k) {
        Vector temporary = forward(&app->models[1].lower[0], &stats->means[k], size),
               coefficient = backward(&app->models[1].lower[0], &temporary, size);
        double product = 0;
        for (int j = 0; j < size; ++j)
            product += stats->means[k].v[j] * coefficient.v[j];
        line_push(&part, format("class %s intercept %s coef %s", data->classes.data[k],
                                real(log(stats->priors[k]) - product / 2), numbers(coefficient, size)));
    }
    paragraph(&out, &part);
    line_push(&part, format("model QDA gamma %s", real(data->params.gamma)));
    for (int k = 0; k < classes; ++k) {
        Eigen eigen = jacobi(&app->models[2].covariance[k], size);
        int order[6];
        eigen_order(&eigen, size, order);
        Vector values = {0};
        for (int j = 0; j < size; ++j)
            values.v[j] = eigen.values.v[order[j]];
        line_push(&part, format("class %s log_det %s eigenvalues %s condition %s", data->classes.data[k],
                                real(app->models[2].log_det[k]), numbers(values, size),
                                real(values.v[0] / values.v[size - 1])));
        for (int a = 0; a < size; ++a) {
            Vector row = {0};
            for (int j = 0; j < size; ++j)
                row.v[j] = app->models[2].covariance[k].v[a][j];
            line_push(&part, format("  %s", numbers(row, size)));
        }
    }
    paragraph(&out, &part);
    line_push(&part, text("separation"));
    for (int a = 0; a < classes; ++a)
        for (int b = a + 1; b < classes; ++b) {
            Vector delta = {0};
            Matrix average = {0};
            for (int j = 0; j < size; ++j)
                delta.v[j] = stats->means[a].v[j] - stats->means[b].v[j];
            for (int i = 0; i < size; ++i)
                for (int j = 0; j < size; ++j)
                    average.v[i][j] =
                        (app->models[2].covariance[a].v[i][j] + app->models[2].covariance[b].v[i][j]) / 2;
            Matrix lower = cholesky(&average, size);
            double distance = quadratic(&lower, &delta, size) / 8 +
                              (log_determinant(&lower, size) -
                               (app->models[2].log_det[a] + app->models[2].log_det[b]) / 2) /
                                  2;
            line_push(&part,
                      format("%s %s mahalanobis %s bhattacharyya %s", data->classes.data[a],
                             data->classes.data[b],
                             real(sqrt(quadratic(&app->models[1].lower[0], &delta, size))), real(distance)));
        }
    paragraph(&out, &part);
    line_push(&part, format("outliers threshold %s", real(data->params.outlier)));
    typedef struct {
        int row;
        double q;
    } Outlier;
    Outlier outliers[400];
    int count = 0;
    for (int i = 0; i < data->train.count; ++i) {
        Prediction prediction = predict(&app->models[2], &data->train.data[i].values, data->costs);
        double q = prediction.distance[data->train.data[i].label];
        if (q > data->params.outlier) {
            int j = count;
            while (j > 0 && q > outliers[j - 1].q) {
                outliers[j] = outliers[j - 1];
                --j;
            }
            outliers[j] = (Outlier){i, q};
            ++count;
        }
    }
    for (int i = 0; i < count; ++i) {
        const Row *row = &data->train.data[outliers[i].row];
        line_push(&part, format("%d %s q %s", row->id, data->classes.data[row->label], real(outliers[i].q)));
    }
    line_push(&part, format("count %d", count));
    paragraph(&out, &part);
    return out;
}
static int int_compare(const void *a, const void *b) {
    int x = *(const int *)a, y = *(const int *)b;
    return (x > y) - (x < y);
}
static bool feature_contains(Features features, int value) {
    for (int j = 0; j < features.count; ++j)
        if (features.v[j] == value)
            return true;
    return false;
}
static Lines evaluation_report(const App *app) {
    const Dataset *data = app->data;
    int classes = data->classes.count, size = app->all.count, n = data->train.count, m = data->test.count;
    Lines out = {0}, part = {0};
    line_push(&out, format("test rows %d", m));
    for (int kind = 0; kind < 3; ++kind) {
        Measures measures = evaluate(&data->test, app->labels[kind], classes);
        line_push(&part, format("model %s", model_names[kind]));
        confusion_lines(&part, &measures, &data->classes);
        line_push(&part, format("accuracy %s", fraction(measures.accuracy)));
        line_push(&part, format("balanced_accuracy %s", fraction(measures.balanced)));
        line_push(&part, format("kappa %s", fraction(measures.kappa)));
        for (int k = 0; k < classes; ++k)
            line_push(&part, format("class %s support %d recall %s precision %s f1 %s", data->classes.data[k],
                                    measures.support[k], fraction(measures.recall[k]),
                                    measures.predicted[k] ? fraction(measures.precision[k]) : "-",
                                    fraction(measures.f1[k])));
        double log_loss = 0;
        for (int i = 0; i < m; ++i)
            log_loss += app->test[kind][i].log_posterior[data->test.data[i].label];
        line_push(&part, format("macro_f1 %s", real(measures.macro_f1)));
        line_push(&part, format("log_loss %s", real(-log_loss / m)));
        line_push(&part, format("errors %d", m - measures.correct));
        for (int i = 0; i < m; ++i)
            if (app->labels[kind][i] != data->test.data[i].label)
                line_push(&part, format("error %d actual %s predicted %s confidence %s",
                                        data->test.data[i].id, data->classes.data[data->test.data[i].label],
                                        data->classes.data[app->labels[kind][i]],
                                        real(app->test[kind][i].confidence)));
        double ece = 0;
        for (int bin = 0; bin <= data->params.calibration.count; ++bin) {
            int count = 0, correct = 0;
            double confidence = 0;
            for (int i = 0; i < m; ++i) {
                int selected = 0;
                while (selected < data->params.calibration.count &&
                       app->test[kind][i].confidence >= data->params.calibration.data[selected])
                    ++selected;
                if (selected == bin) {
                    ++count;
                    correct += app->labels[kind][i] == data->test.data[i].label;
                    confidence += app->test[kind][i].confidence;
                }
            }
            double low = bin == 0 ? 0 : data->params.calibration.data[bin - 1],
                   high = bin == data->params.calibration.count ? 1 : data->params.calibration.data[bin];
            line_push(&part, format("bin %s %s count %d confidence %s accuracy %s", real(low), real(high),
                                    count, count ? real(confidence / count) : "-",
                                    count ? fraction(make_fraction(correct, count)) : "-"));
            ece += fabs(correct - confidence);
        }
        line_push(&part, format("ece %s", real(ece / m)));
        for (int threshold_index = 0; threshold_index < data->params.reject.count; ++threshold_index) {
            double threshold = data->params.reject.data[threshold_index];
            int count = 0, correct = 0;
            for (int i = 0; i < m; ++i)
                if (app->test[kind][i].confidence >= threshold) {
                    ++count;
                    correct += app->labels[kind][i] == data->test.data[i].label;
                }
            line_push(&part, format("reject %s accepted %d coverage %s accuracy %s", real(threshold), count,
                                    fraction(make_fraction(count, m)),
                                    count ? fraction(make_fraction(correct, count)) : "-"));
        }
        paragraph(&out, &part);
    }
    Measures ensemble = evaluate(&data->test, app->labels[3], classes);
    line_push(&part, text("ensemble soft_vote"));
    line_push(&part, format("accuracy %s balanced_accuracy %s kappa %s", fraction(ensemble.accuracy),
                            fraction(ensemble.balanced), fraction(ensemble.kappa)));
    paragraph(&out, &part);
    line_push(&part, text("mcnemar test"));
    for (int a = 0; a < 4; ++a)
        for (int b = a + 1; b < 4; ++b)
            line_push(&part, mcnemar_line(model_names[a], model_names[b],
                                          mcnemar(&data->test, app->labels[a], app->labels[b])));
    paragraph(&out, &part);
    line_push(&part, text("costs"));
    for (int kind = 0; kind < 3; ++kind) {
        double argmax = 0, decision = 0;
        int changed = 0, correct = 0;
        for (int i = 0; i < m; ++i) {
            argmax += data->costs[data->test.data[i].label][app->labels[kind][i]];
            decision += data->costs[data->test.data[i].label][app->test[kind][i].decision];
            changed += app->test[kind][i].decision != app->labels[kind][i];
            correct += app->test[kind][i].decision == data->test.data[i].label;
        }
        line_push(&part, format("%s argmax_total %s decision_total %s changed %d decision_accuracy %s",
                                model_names[kind], real(argmax), real(decision), changed,
                                fraction(make_fraction(correct, m))));
    }
    paragraph(&out, &part);
    line_push(&part, format("novelty threshold %s", real(data->params.outlier)));
    typedef struct {
        int row, nearest;
        double q;
    } Novel;
    Novel novel[200];
    int novel_count = 0;
    for (int i = 0; i < m; ++i) {
        int nearest = 0;
        for (int k = 1; k < classes; ++k)
            if (app->test[2][i].distance[k] < app->test[2][i].distance[nearest])
                nearest = k;
        double q = app->test[2][i].distance[nearest];
        if (q > data->params.outlier) {
            int j = novel_count;
            while (j > 0 && q > novel[j - 1].q) {
                novel[j] = novel[j - 1];
                --j;
            }
            novel[j] = (Novel){i, nearest, q};
            ++novel_count;
        }
    }
    for (int i = 0; i < novel_count; ++i)
        line_push(&part, format("%d nearest %s q %s", data->test.data[novel[i].row].id,
                                data->classes.data[novel[i].nearest], real(novel[i].q)));
    line_push(&part, format("count %d", novel_count));
    paragraph(&out, &part);
    Generator generator = {data->params.seed};
    int bootstrap[3][2000] = {{0}}, comparisons[3][3] = {{0}};
    for (int sample = 0; sample < data->params.bootstrap; ++sample) {
        int counts[3] = {0};
        for (int i = 0; i < m; ++i) {
            int row = (int)(draw(&generator) % m);
            for (int kind = 0; kind < 3; ++kind)
                counts[kind] += app->labels[kind][row] == data->test.data[row].label;
        }
        for (int kind = 0; kind < 3; ++kind)
            bootstrap[kind][sample] = counts[kind];
        int pair = 0;
        for (int a = 0; a < 3; ++a)
            for (int b = a + 1; b < 3; ++b) {
                ++comparisons[pair][counts[a] > counts[b] ? 0 : counts[a] == counts[b] ? 1 : 2];
                ++pair;
            }
    }
    line_push(&part, format("bootstrap resamples %d seed %lld", data->params.bootstrap,
                            (long long)data->params.seed));
    for (int kind = 0; kind < 3; ++kind) {
        int sum = 0;
        for (int i = 0; i < data->params.bootstrap; ++i)
            sum += bootstrap[kind][i];
        qsort(bootstrap[kind], (size_t)data->params.bootstrap, sizeof(int), int_compare);
        int offset = data->params.bootstrap / 40;
        line_push(&part,
                  format("%s mean %s interval %s %s", model_names[kind],
                         real((double)sum / data->params.bootstrap / m),
                         fraction(make_fraction(bootstrap[kind][offset], m)),
                         fraction(make_fraction(bootstrap[kind][data->params.bootstrap - 1 - offset], m))));
    }
    int pair = 0;
    for (int a = 0; a < 3; ++a)
        for (int b = a + 1; b < 3; ++b) {
            line_push(&part, format("%s %s wins %d ties %d losses %d", model_names[a], model_names[b],
                                    comparisons[pair][0], comparisons[pair][1], comparisons[pair][2]));
            ++pair;
        }
    paragraph(&out, &part);
    line_push(&part,
              format("prior_sensitivity alternative %s", data->params.empirical ? "uniform" : "empirical"));
    for (int kind = 0; kind < 3; ++kind) {
        Model model = train(&data->train, app->all, classes, kind, !data->params.empirical,
                            data->params.smoothing, data->params.gamma);
        int prediction[200];
        predictions(data, &model, &data->test, prediction);
        Measures measures = evaluate(&data->test, prediction, classes);
        int changed = 0;
        for (int i = 0; i < m; ++i)
            changed += prediction[i] != app->labels[kind][i];
        line_push(&part, format("%s accuracy %s balanced_accuracy %s changed %d", model_names[kind],
                                fraction(measures.accuracy), fraction(measures.balanced), changed));
    }
    paragraph(&out, &part);
    line_push(&part, text("learning_curve"));
    for (int limit_index = 0; limit_index < data->params.curve.count; ++limit_index) {
        int limit = data->params.curve.data[limit_index], seen[5] = {0};
        Rows rows = {0};
        for (int i = 0; i < n; ++i) {
            const Row *row = &data->train.data[i];
            if (seen[row->label]++ < limit)
                row_push(&rows, *row);
        }
        char *line = format("size %d rows %d", limit, rows.count);
        for (int kind = 0; kind < 3; ++kind) {
            Model model = fit(data, &rows, app->all, kind);
            char *next = format("%s %s %s", line, model_names[kind],
                                fraction(make_fraction(model_correct(data, &model, &data->test), m)));
            free(line);
            line = next;
        }
        free(rows.data);
        line_push(&part, line);
    }
    paragraph(&out, &part);
    line_push(&part, format("cross_validation folds %d", data->params.folds));
    int fold_sizes[10] = {0};
    for (int i = 0; i < n; ++i)
        ++fold_sizes[data->train.data[i].id % data->params.folds];
    IntList sizes = {.data = fold_sizes, .count = data->params.folds};
    line_push(&part, format("fold_sizes %s", integers(&sizes)));
    int best_subset = -1, best_model = 0, best_correct = -1;
    for (int subset = 0; subset < data->params.subset_count; ++subset) {
        const Subset *selected = &data->params.subsets[subset];
        line_push(&part, format("subset %s features %s", selected->name,
                                names(selected->features, &data->features)));
        for (int kind = 0; kind < 3; ++kind) {
            CrossValidation result = cross_validate(data, selected->features, kind);
            IntList folds = {.data = result.fold_correct, .count = data->params.folds};
            line_push(&part,
                      format("  %s fold_correct %s correct %d accuracy %s", model_names[kind],
                             integers(&folds), result.correct, fraction(make_fraction(result.correct, n))));
            if (best_subset < 0 || result.correct > best_correct ||
                (result.correct == best_correct &&
                 selected->features.count < data->params.subsets[best_subset].features.count)) {
                best_subset = subset;
                best_model = kind;
                best_correct = result.correct;
            }
        }
    }
    const Subset *selected = &data->params.subsets[best_subset];
    line_push(&part, format("best subset %s model %s correct %d accuracy %s", selected->name,
                            model_names[best_model], best_correct, fraction(make_fraction(best_correct, n))));
    Model selected_model = fit(data, &data->train, selected->features, best_model);
    int refit_correct = model_correct(data, &selected_model, &data->test);
    line_push(&part, format("refit_test correct %d accuracy %s", refit_correct,
                            fraction(make_fraction(refit_correct, m))));
    paragraph(&out, &part);
    line_push(&part, text("mcnemar cross_validation"));
    for (int a = 0; a < 3; ++a)
        for (int b = a + 1; b < 3; ++b)
            line_push(&part,
                      mcnemar_line(model_names[a], model_names[b],
                                   mcnemar(&data->train, app->cv[a].prediction, app->cv[b].prediction)));
    paragraph(&out, &part);
    for (int kind = 0; kind < 3; ++kind) {
        Measures measures = evaluate(&data->train, app->cv[kind].prediction, classes);
        line_push(&part, format("cv_confusion model %s", model_names[kind]));
        confusion_lines(&part, &measures, &data->classes);
        line_push(&part, format("balanced_accuracy %s kappa %s", fraction(measures.balanced),
                                fraction(measures.kappa)));
        paragraph(&out, &part);
    }
    line_push(&part, text("leave_one_out"));
    for (int kind = 0; kind < 3; ++kind) {
        int correct = 0;
        for (int i = 0; i < n; ++i) {
            Rows rows = {0};
            for (int j = 0; j < n; ++j)
                if (j != i)
                    row_push(&rows, data->train.data[j]);
            Model model = fit(data, &rows, app->all, kind);
            free(rows.data);
            correct += predict(&model, &data->train.data[i].values, data->costs).predicted ==
                       data->train.data[i].label;
        }
        line_push(&part, format("%s correct %d accuracy %s", model_names[kind], correct,
                                fraction(make_fraction(correct, n))));
    }
    paragraph(&out, &part);
    for (int kind = 0; kind < 3; ++kind) {
        line_push(&part, format("forward_selection model %s", model_names[kind]));
        Features features = {0};
        int best_step = 0, best = -1;
        for (int step = 1; step <= size; ++step) {
            int chosen = -1, correct = -1;
            for (int feature = 0; feature < size; ++feature)
                if (!feature_contains(features, feature)) {
                    Features trial = features;
                    trial.v[trial.count++] = feature;
                    int value = cross_validate(data, trial, kind).correct;
                    if (value > correct) {
                        chosen = feature;
                        correct = value;
                    }
                }
            features.v[features.count++] = chosen;
            line_push(&part,
                      format("step %d add %s correct %d accuracy %s", step, data->features.data[chosen],
                             correct, fraction(make_fraction(correct, n))));
            if (correct > best) {
                best = correct;
                best_step = step;
            }
        }
        features.count = best_step;
        line_push(&part, format("best_step %d features %s", best_step, names(features, &data->features)));
        paragraph(&out, &part);
    }
    for (int tuning = 0; tuning < 2; ++tuning) {
        int kind = tuning == 0 ? 0 : 2;
        const DoubleList *grid = tuning == 0 ? &data->params.smoothing_grid : &data->params.gamma_grid;
        line_push(&part, text(tuning == 0 ? "nb_smoothing_path" : "qda_gamma_path"));
        int best = -1;
        double chosen = 0;
        for (int i = 0; i < grid->count; ++i) {
            double value = grid->data[i];
            int correct =
                cross_validate_values(data, app->all, kind, tuning == 0 ? value : data->params.smoothing,
                                      tuning == 1 ? value : data->params.gamma)
                    .correct;
            line_push(&part, format("value %s correct %d accuracy %s", real(value), correct,
                                    fraction(make_fraction(correct, n))));
            if (correct >= best) {
                best = correct;
                chosen = value;
            }
        }
        Model model =
            train(&data->train, app->all, classes, kind, data->params.empirical,
                  tuning == 0 ? chosen : data->params.smoothing, tuning == 1 ? chosen : data->params.gamma);
        int correct = model_correct(data, &model, &data->test);
        line_push(&part, format("best %s test correct %d accuracy %s", real(chosen), correct,
                                fraction(make_fraction(correct, m))));
        paragraph(&out, &part);
    }
    return out;
}
static Lines empty_map(int width, int height, char value) {
    Lines out = {0};
    for (int r = 0; r < height; ++r) {
        char *row = resize(NULL, (size_t)width + 1);
        memset(row, value, (size_t)width);
        row[width] = 0;
        line_push(&out, row);
    }
    return out;
}
static Lines boundaries(const Dataset *data) {
    Lines out = {0};
    int width = data->params.map_width, height = data->params.map_height, classes = data->classes.count;
    for (int pair_index = 0; pair_index < data->params.pair_count; ++pair_index) {
        Pair pair = data->params.pairs[pair_index];
        Features features = {{pair.x, pair.y}, 2};
        double xmin = data->train.data[0].values.v[pair.x], xmax = xmin,
               ymin = data->train.data[0].values.v[pair.y], ymax = ymin;
        for (int i = 0; i < data->train.count; ++i) {
            const Row *row = &data->train.data[i];
            if (row->values.v[pair.x] < xmin)
                xmin = row->values.v[pair.x];
            if (row->values.v[pair.x] > xmax)
                xmax = row->values.v[pair.x];
            if (row->values.v[pair.y] < ymin)
                ymin = row->values.v[pair.y];
            if (row->values.v[pair.y] > ymax)
                ymax = row->values.v[pair.y];
        }
        double dx = (xmax - xmin) / (width - 1), dy = (ymax - ymin) / (height - 1);
        Lines part = {0};
        line_push(&part, format("pair %s %s", data->features.data[pair.x], data->features.data[pair.y]));
        line_push(&part,
                  format("x %s %s %s y %s %s %s grid %dx%d", data->features.data[pair.x], real(xmin),
                         real(xmax), data->features.data[pair.y], real(ymin), real(ymax), width, height));
        Prediction *grid[3];
        for (int kind = 0; kind < 3; ++kind) {
            Model model = fit(data, &data->train, features, kind);
            int correct = model_correct(data, &model, &data->train),
                cv = cross_validate(data, features, kind).correct;
            line_push(&part, format("model %s train_accuracy %s cv_accuracy %s", model_names[kind],
                                    fraction(make_fraction(correct, data->train.count)),
                                    fraction(make_fraction(cv, data->train.count))));
            Lines map = empty_map(width, height, ' ');
            int cells[5] = {0};
            grid[kind] = resize(NULL, (size_t)width * height * sizeof(Prediction));
            for (int r = 0; r < height; ++r)
                for (int col = 0; col < width; ++col) {
                    Vector values = {0};
                    values.v[pair.x] = xmin + col * dx;
                    values.v[pair.y] = ymax - r * dy;
                    Prediction prediction = predict(&model, &values, data->costs);
                    grid[kind][r * width + col] = prediction;
                    map.data[r][col] = (char)(data->classes.data[prediction.predicted][0] - 'a' + 'A');
                    ++cells[prediction.predicted];
                }
            extend_owned(&part, frame(&map));
            lines_free(&map);
            char *line = text("cells");
            for (int k = 0; k < classes; ++k) {
                char *next = format("%s %c %d", line, data->classes.data[k][0] - 'a' + 'A', cells[k]);
                free(line);
                line = next;
            }
            line_push(&part, line);
        }
        Lines agreement = empty_map(width, height, '.'), uncertainty = empty_map(width, height, ' '),
              points = empty_map(width, height, ' ');
        int disagreement = 0;
        const char *levels = " .:-=+*#%@";
        for (int r = 0; r < height; ++r)
            for (int col = 0; col < width; ++col) {
                int index = r * width + col, a = grid[0][index].predicted, b = grid[1][index].predicted,
                    c = grid[2][index].predicted,
                    distinct = a == b && b == c             ? 1
                               : a == b || a == c || b == c ? 2
                                                            : 3;
                if (distinct > 1) {
                    agreement.data[r][col] = (char)('0' + distinct);
                    ++disagreement;
                }
                double u = (1 - grid[2][index].confidence) / (1 - 1.0 / classes);
                int level = (int)floor(10 * u);
                if (level > 9)
                    level = 9;
                uncertainty.data[r][col] = levels[level];
            }
        for (int i = 0; i < data->train.count; ++i) {
            const Row *row = &data->train.data[i];
            int col = cell(row->values.v[pair.x], xmin, xmax, width),
                r = height - 1 - cell(row->values.v[pair.y], ymin, ymax, height);
            char letter = data->classes.data[row->label][0];
            points.data[r][col] = points.data[r][col] == ' ' || points.data[r][col] == letter ? letter : '*';
        }
        line_push(&part, text("agreement"));
        extend_owned(&part, frame(&agreement));
        line_push(&part, format("disagreement_cells %d", disagreement));
        line_push(&part, text("uncertainty QDA"));
        extend_owned(&part, frame(&uncertainty));
        line_push(&part, text("points"));
        extend_owned(&part, frame(&points));
        for (int kind = 0; kind < 3; ++kind)
            free(grid[kind]);
        lines_free(&agreement);
        lines_free(&uncertainty);
        lines_free(&points);
        paragraph(&out, &part);
    }
    return out;
}
static void project(Vector point, const Statistics *stats, const Vector *directions, int size, double *out) {
    out[0] = out[1] = 0;
    for (int t = 0; t < 2; ++t)
        for (int j = 0; j < size; ++j)
            out[t] += directions[t].v[j] * (point.v[j] - stats->center.v[j]);
}
static int nearest_correct(const Rows *rows, const Statistics *stats, const Vector *directions,
                           const double centers[5][2], int classes, int size, int dims) {
    int count = 0;
    for (int i = 0; i < rows->count; ++i) {
        double point[2];
        project(rows->data[i].values, stats, directions, size, point);
        int selected = 0;
        double smallest = 0;
        for (int k = 0; k < classes; ++k) {
            double distance = 0;
            for (int t = 0; t < dims; ++t)
                distance += (point[t] - centers[k][t]) * (point[t] - centers[k][t]);
            if (k == 0 || distance < smallest) {
                smallest = distance;
                selected = k;
            }
        }
        count += selected == rows->data[i].label;
    }
    return count;
}
static Lines projection(const App *app) {
    const Dataset *data = app->data;
    const Model *lda = &app->models[1];
    const Statistics *stats = &lda->stats;
    int size = app->all.count, classes = data->classes.count;
    Matrix within = {0}, between = {0};
    Vector f_values = {0};
    for (int a = 0; a < size; ++a)
        for (int b = 0; b < size; ++b) {
            for (int k = 0; k < classes; ++k)
                within.v[a][b] += stats->scatter[k].v[a][b];
            for (int k = 0; k < classes; ++k)
                between.v[a][b] += stats->counts[k] * (stats->means[k].v[a] - stats->center.v[a]) *
                                   (stats->means[k].v[b] - stats->center.v[b]);
        }
    for (int j = 0; j < size; ++j)
        f_values.v[j] = (between.v[j][j] / (classes - 1)) / (within.v[j][j] / (stats->count - classes));
    int feature_order[6];
    for (int i = 0; i < size; ++i) {
        int j = i;
        while (j > 0 && f_values.v[i] > f_values.v[feature_order[j - 1]]) {
            feature_order[j] = feature_order[j - 1];
            --j;
        }
        feature_order[j] = i;
    }
    Lines out = {0}, part = {0};
    line_push(&out, text("univariate"));
    for (int rank = 0; rank < size; ++rank) {
        int j = feature_order[rank];
        line_push(&out, format("rank %d %s f %s between %s within %s", rank + 1, data->features.data[j],
                               real(f_values.v[j]), real(between.v[j][j]), real(within.v[j][j])));
    }
    Matrix lower = cholesky(&within, size), y = {0}, z = {0}, symmetric = {0};
    for (int j = 0; j < size; ++j) {
        Vector column = {0};
        for (int a = 0; a < size; ++a)
            column.v[a] = between.v[a][j];
        Vector result = forward(&lower, &column, size);
        for (int a = 0; a < size; ++a)
            y.v[a][j] = result.v[a];
    }
    for (int i = 0; i < size; ++i) {
        Vector row = {0};
        for (int j = 0; j < size; ++j)
            row.v[j] = y.v[i][j];
        Vector result = forward(&lower, &row, size);
        for (int a = 0; a < size; ++a)
            z.v[a][i] = result.v[a];
    }
    for (int a = 0; a < size; ++a)
        for (int b = 0; b < size; ++b)
            symmetric.v[a][b] = (z.v[a][b] + z.v[b][a]) / 2;
    Eigen eigen = jacobi(&symmetric, size);
    int order[6];
    eigen_order(&eigen, size, order);
    double total = 0;
    for (int j = 0; j < size; ++j)
        total += eigen.values.v[j];
    Vector values = {0}, ratios = {0};
    for (int j = 0; j < size; ++j) {
        values.v[j] = eigen.values.v[order[j]];
        ratios.v[j] = values.v[j] / total;
    }
    Vector directions[2] = {{0}}, standardized[2] = {{0}};
    for (int t = 0; t < 2; ++t) {
        Vector column = {0};
        for (int j = 0; j < size; ++j)
            column.v[j] = eigen.vectors.v[j][order[t]];
        Vector direction = backward(&lower, &column, size);
        double squares = 0;
        for (int j = 0; j < size; ++j)
            squares += direction.v[j] * direction.v[j];
        double norm = sqrt(squares);
        int largest = 0;
        for (int j = 0; j < size; ++j) {
            direction.v[j] /= norm;
            if (fabs(direction.v[j]) > fabs(direction.v[largest]))
                largest = j;
        }
        if (direction.v[largest] < 0)
            for (int j = 0; j < size; ++j)
                direction.v[j] = -direction.v[j];
        directions[t] = direction;
        for (int j = 0; j < size; ++j)
            standardized[t].v[j] = direction.v[j] * sqrt(lda->covariance[0].v[j][j]);
    }
    double centers[5][2] = {{0}}, spread[5][2] = {{0}};
    for (int k = 0; k < classes; ++k) {
        project(stats->means[k], stats, directions, size, centers[k]);
        for (int t = 0; t < 2; ++t) {
            double sum = 0;
            for (int i = 0; i < data->train.count; ++i)
                if (data->train.data[i].label == k) {
                    double point[2];
                    project(data->train.data[i].values, stats, directions, size, point);
                    sum += (point[t] - centers[k][t]) * (point[t] - centers[k][t]);
                }
            spread[k][t] = sqrt(sum / stats->counts[k]);
        }
    }
    line_push(&part, format("fisher features %s", names(app->all, &data->features)));
    line_push(&part, format("center %s", numbers(stats->center, size)));
    line_push(&part, format("sweeps %d", eigen.sweeps));
    line_push(&part, format("eigenvalues %s", numbers(values, size)));
    line_push(&part, format("ratios %s", numbers(ratios, size)));
    for (int t = 0; t < 2; ++t) {
        line_push(&part, format("direction %d %s", t + 1, numbers(directions[t], size)));
        line_push(&part, format("standardized %d %s", t + 1, numbers(standardized[t], size)));
    }
    for (int k = 0; k < classes; ++k)
        line_push(&part, format("centroid %s %s %s spread %s %s", data->classes.data[k], real(centers[k][0]),
                                real(centers[k][1]), real(spread[k][0]), real(spread[k][1])));
    for (int dims = 1; dims <= 2; ++dims)
        line_push(&part, format("nearest_centroid dims %d train %s test %s", dims,
                                fraction(make_fraction(nearest_correct(&data->train, stats, directions,
                                                                       centers, classes, size, dims),
                                                       data->train.count)),
                                fraction(make_fraction(nearest_correct(&data->test, stats, directions,
                                                                       centers, classes, size, dims),
                                                       data->test.count))));
    paragraph(&out, &part);
    double points[400][2];
    for (int i = 0; i < data->train.count; ++i)
        project(data->train.data[i].values, stats, directions, size, points[i]);
    double lo1 = points[0][0], hi1 = lo1, lo2 = points[0][1], hi2 = lo2;
    for (int i = 0; i < data->train.count; ++i) {
        if (points[i][0] < lo1)
            lo1 = points[i][0];
        if (points[i][0] > hi1)
            hi1 = points[i][0];
        if (points[i][1] < lo2)
            lo2 = points[i][1];
        if (points[i][1] > hi2)
            hi2 = points[i][1];
    }
    int width = data->params.plot_width, height = data->params.plot_height;
    Lines cells = empty_map(width, height, ' ');
    for (int i = 0; i < data->train.count; ++i) {
        int col = cell(points[i][0], lo1, hi1, width),
            row = height - 1 - cell(points[i][1], lo2, hi2, height);
        char letter = data->classes.data[data->train.data[i].label][0];
        cells.data[row][col] = cells.data[row][col] == ' ' || cells.data[row][col] == letter ? letter : '*';
    }
    for (int k = 0; k < classes; ++k)
        cells.data[height - 1 - cell(centers[k][1], lo2, hi2, height)][cell(centers[k][0], lo1, hi1, width)] =
            (char)(data->classes.data[k][0] - 'a' + 'A');
    line_push(&part, format("plot x %s %s y %s %s size %dx%d", real(lo1), real(hi1), real(lo2), real(hi2),
                            width, height));
    extend_owned(&part, frame(&cells));
    lines_free(&cells);
    paragraph(&out, &part);
    return out;
}
static void write_owned(const char *name, Lines lines) {
    write_lines(name, &lines);
    lines_free(&lines);
}
int main(void) {
    mkdir("output", 0777);
    App *app = calloc(1, sizeof(App));
    app->data = read_dataset();
    Dataset *data = app->data;
    for (int j = 0; j < data->features.count; ++j)
        app->all.v[app->all.count++] = j;
    for (int kind = 0; kind < 3; ++kind) {
        app->models[kind] = fit(data, &data->train, app->all, kind);
        for (int i = 0; i < data->test.count; ++i) {
            app->test[kind][i] = predict(&app->models[kind], &data->test.data[i].values, data->costs);
            app->labels[kind][i] = app->test[kind][i].predicted;
        }
        app->cv[kind] = cross_validate(data, app->all, kind);
    }
    for (int i = 0; i < data->test.count; ++i) {
        int selected = 0;
        double posterior[5] = {0};
        for (int k = 0; k < data->classes.count; ++k) {
            double sum = 0;
            for (int kind = 0; kind < 3; ++kind)
                sum += app->test[kind][i].posterior[k];
            posterior[k] = sum / 3;
            if (posterior[k] > posterior[selected])
                selected = k;
        }
        app->labels[3][i] = selected;
    }
    write_owned("models.txt", model_report(app));
    Lines csv = {0};
    char *header = text("id,model,actual,predicted,decision");
    for (int k = 0; k < data->classes.count; ++k) {
        char *next = format("%s,%s", header, data->classes.data[k]);
        free(header);
        header = next;
    }
    line_push(&csv, header);
    for (int i = 0; i < data->test.count; ++i)
        for (int kind = 0; kind < 3; ++kind) {
            const Prediction *prediction = &app->test[kind][i];
            char *line =
                format("%d,%s,%s,%s,%s", data->test.data[i].id, model_names[kind],
                       data->classes.data[data->test.data[i].label],
                       data->classes.data[prediction->predicted], data->classes.data[prediction->decision]);
            for (int k = 0; k < data->classes.count; ++k) {
                char *next = format("%s,%s", line, real(prediction->posterior[k]));
                free(line);
                line = next;
            }
            line_push(&csv, line);
        }
    write_owned("predictions.csv", csv);
    write_owned("evaluation.txt", evaluation_report(app));
    write_owned("boundaries.txt", boundaries(data));
    write_owned("projection.txt", projection(app));
    free(data->train.data);
    free(data->test.data);
    lines_free(&data->features);
    lines_free(&data->classes);
    free(data->params.smoothing_grid.data);
    free(data->params.gamma_grid.data);
    free(data->params.calibration.data);
    free(data->params.reject.data);
    free(data->params.curve.data);
    for (int i = 0; i < data->params.subset_count; ++i)
        free(data->params.subsets[i].name);
    free(data->params.subsets);
    free(data->params.pairs);
    free(data);
    free(app);
    return 0;
}
