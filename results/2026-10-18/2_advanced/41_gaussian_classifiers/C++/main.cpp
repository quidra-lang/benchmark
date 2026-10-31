#include "gaussian.hpp"
#include <filesystem>
static const std::array<std::string, 4> model_names = {"NB", "LDA", "QDA", "ENSEMBLE"};
static std::string num(std::int64_t value) {
    return std::to_string(value);
}
static void extend(Lines &out, const Lines &lines) {
    out.insert(out.end(), lines.begin(), lines.end());
}
static void paragraph(Lines &out, const Lines &lines) {
    if (!out.empty())
        out.push_back("");
    extend(out, lines);
}
static Model fit(const Dataset &data, const Rows &rows, const Features &features, int kind, double smoothing,
                 double gamma, bool empirical) {
    return train(rows, features, data.classes.size(), kind, empirical, smoothing, gamma);
}
static Model fit(const Dataset &data, const Rows &rows, const Features &features, int kind) {
    return fit(data, rows, features, kind, data.params.smoothing, data.params.gamma, data.params.empirical);
}
static std::vector<int> predictions(const Dataset &data, const Model &model, const Rows &rows) {
    std::vector<int> out;
    for (const Row &row : rows)
        out.push_back(predict(model, row.values, data.costs).predicted);
    return out;
}
static int correct_count(const Rows &rows, const std::vector<int> &predicted) {
    int count = 0;
    for (std::size_t i = 0; i < rows.size(); ++i)
        count += rows[i].label == predicted[i];
    return count;
}
struct CrossValidation {
    std::vector<int> prediction, fold_correct;
    int correct = 0;
};
static CrossValidation cross_validate(const Dataset &data, const Features &features, int kind,
                                      double smoothing, double gamma) {
    CrossValidation out;
    out.prediction.resize(data.train.size());
    out.fold_correct.resize(data.params.folds);
    for (int fold = 0; fold < data.params.folds; ++fold) {
        Rows training;
        for (const Row &row : data.train)
            if (row.id % data.params.folds != fold)
                training.push_back(row);
        const Model model = fit(data, training, features, kind, smoothing, gamma, data.params.empirical);
        for (std::size_t i = 0; i < data.train.size(); ++i)
            if (data.train[i].id % data.params.folds == fold) {
                out.prediction[i] = predict(model, data.train[i].values, data.costs).predicted;
                if (out.prediction[i] == data.train[i].label) {
                    ++out.fold_correct[fold];
                    ++out.correct;
                }
            }
    }
    return out;
}
static CrossValidation cross_validate(const Dataset &data, const Features &features, int kind) {
    return cross_validate(data, features, kind, data.params.smoothing, data.params.gamma);
}
static Lines confusion_lines(const Measures &measures, const Lines &classes) {
    Lines out;
    for (int a = 0; a < measures.classes; ++a) {
        std::string line = "confusion " + classes[a];
        for (int b = 0; b < measures.classes; ++b)
            line += " " + num(measures.confusion[a][b]);
        out.push_back(line);
    }
    return out;
}
static std::string mcnemar_line(const std::string &a, const std::string &b, const McNemar &test) {
    return a + " " + b + " b01 " + num(test.b01) + " b10 " + num(test.b10) + " chi2 " + real(test.chi2) +
           " significant " + (test.chi2 > 3.841 ? "yes" : "no");
}
static std::vector<int> eigen_order(const Eigen &eigen, int size) {
    std::vector<int> order(size);
    std::iota(order.begin(), order.end(), 0);
    std::sort(order.begin(), order.end(), [&](int a, int b) {
        return eigen.values[a] != eigen.values[b] ? eigen.values[a] > eigen.values[b] : a < b;
    });
    return order;
}
static Lines model_report(const Dataset &data, const Features &all, const std::array<Model, 3> &models) {
    const int size = all.size(), classes = data.classes.size();
    const Statistics &stats = models[0].stats;
    Lines out, part;
    part = {"features " + names(all, data.features), "classes "};
    part[1].clear();
    part[1] = "classes";
    for (const std::string &name : data.classes)
        part[1] += " " + name;
    part.push_back("prior_mode " + std::string(data.params.empirical ? "empirical" : "uniform"));
    for (int k = 0; k < classes; ++k)
        part.push_back("class " + data.classes[k] + " letter " + char(data.classes[k][0] - 'a' + 'A') +
                       " count " + num(stats.counts[k]) + " prior " + real(stats.priors[k]) + " mean " +
                       numbers(stats.means[k], size));
    paragraph(out, part);
    part = {"model NB", "smoothing epsilon " + real(data.params.smoothing) + " max_variance " +
                            real(models[0].max_variance) + " added " + real(models[0].added)};
    for (int k = 0; k < classes; ++k) {
        Vector diagonal{};
        for (int j = 0; j < size; ++j)
            diagonal[j] = models[0].covariance[k][j][j];
        part.push_back("class " + data.classes[k] + " variance " + numbers(diagonal, size) + " log_det " +
                       real(models[0].log_det[k]));
    }
    paragraph(out, part);
    part = {"model LDA", "log_det " + real(models[1].log_det[0])};
    for (int a = 0; a < size; ++a)
        part.push_back("  " + numbers(models[1].covariance[0][a], size));
    for (int k = 0; k < classes; ++k) {
        const Vector coefficient =
            backward(models[1].lower[0], forward(models[1].lower[0], stats.means[k], size), size);
        double product = 0;
        for (int j = 0; j < size; ++j)
            product += stats.means[k][j] * coefficient[j];
        part.push_back("class " + data.classes[k] + " intercept " +
                       real(std::log(stats.priors[k]) - product / 2) + " coef " + numbers(coefficient, size));
    }
    paragraph(out, part);
    part = {"model QDA gamma " + real(data.params.gamma)};
    for (int k = 0; k < classes; ++k) {
        const Eigen eigen = jacobi(models[2].covariance[k], size);
        const auto order = eigen_order(eigen, size);
        Vector values{};
        for (int j = 0; j < size; ++j)
            values[j] = eigen.values[order[j]];
        part.push_back("class " + data.classes[k] + " log_det " + real(models[2].log_det[k]) +
                       " eigenvalues " + numbers(values, size) + " condition " +
                       real(values[0] / values[size - 1]));
        for (int a = 0; a < size; ++a)
            part.push_back("  " + numbers(models[2].covariance[k][a], size));
    }
    paragraph(out, part);
    part = {"separation"};
    for (int a = 0; a < classes; ++a)
        for (int b = a + 1; b < classes; ++b) {
            Vector delta{};
            Matrix average{};
            for (int j = 0; j < size; ++j)
                delta[j] = stats.means[a][j] - stats.means[b][j];
            for (int i = 0; i < size; ++i)
                for (int j = 0; j < size; ++j)
                    average[i][j] = (models[2].covariance[a][i][j] + models[2].covariance[b][i][j]) / 2;
            const Matrix lower = cholesky(average, size);
            const double distance =
                quadratic(lower, delta, size) / 8 +
                (log_determinant(lower, size) - (models[2].log_det[a] + models[2].log_det[b]) / 2) / 2;
            part.push_back(data.classes[a] + " " + data.classes[b] + " mahalanobis " +
                           real(std::sqrt(quadratic(models[1].lower[0], delta, size))) + " bhattacharyya " +
                           real(distance));
        }
    paragraph(out, part);
    part = {"outliers threshold " + real(data.params.outlier)};
    std::vector<std::pair<int, double>> outliers;
    for (std::size_t i = 0; i < data.train.size(); ++i) {
        const double q = predict(models[2], data.train[i].values, data.costs).distance[data.train[i].label];
        if (q > data.params.outlier)
            outliers.push_back({i, q});
    }
    std::sort(outliers.begin(), outliers.end(), [](const auto &a, const auto &b) {
        return a.second != b.second ? a.second > b.second : a.first < b.first;
    });
    for (const auto &outlier : outliers) {
        const Row &row = data.train[outlier.first];
        part.push_back(num(row.id) + " " + data.classes[row.label] + " q " + real(outlier.second));
    }
    part.push_back("count " + num(outliers.size()));
    paragraph(out, part);
    return out;
}
static Lines evaluation_report(const Dataset &data, const Features &all, const std::array<Model, 3> &models,
                               const std::array<std::vector<Prediction>, 3> &test,
                               const std::array<std::vector<int>, 4> &labels,
                               const std::array<CrossValidation, 3> &cv) {
    const int classes = data.classes.size(), size = all.size(), n = data.train.size(), m = data.test.size();
    Lines out = {"test rows " + num(m)};
    for (int kind = 0; kind < 3; ++kind) {
        const Measures measures = evaluate(data.test, labels[kind], classes);
        Lines part = {"model " + model_names[kind]};
        extend(part, confusion_lines(measures, data.classes));
        part.push_back("accuracy " + fraction(measures.accuracy));
        part.push_back("balanced_accuracy " + fraction(measures.balanced));
        part.push_back("kappa " + fraction(measures.kappa));
        for (int k = 0; k < classes; ++k)
            part.push_back("class " + data.classes[k] + " support " + num(measures.support[k]) + " recall " +
                           fraction(measures.recall[k]) + " precision " +
                           (measures.predicted[k] ? fraction(measures.precision[k]) : "-") + " f1 " +
                           fraction(measures.f1[k]));
        double log_loss = 0;
        for (std::size_t i = 0; i < data.test.size(); ++i)
            log_loss += test[kind][i].log_posterior[data.test[i].label];
        part.push_back("macro_f1 " + real(measures.macro_f1));
        part.push_back("log_loss " + real(-log_loss / m));
        part.push_back("errors " + num(m - measures.correct));
        for (int i = 0; i < m; ++i)
            if (labels[kind][i] != data.test[i].label)
                part.push_back("error " + num(data.test[i].id) + " actual " +
                               data.classes[data.test[i].label] + " predicted " +
                               data.classes[labels[kind][i]] + " confidence " +
                               real(test[kind][i].confidence));
        double ece = 0;
        for (std::size_t bin = 0; bin <= data.params.calibration.size(); ++bin) {
            int count = 0, correct = 0;
            double confidence = 0;
            for (int i = 0; i < m; ++i)
                if (std::size_t(std::upper_bound(data.params.calibration.begin(),
                                                 data.params.calibration.end(), test[kind][i].confidence) -
                                data.params.calibration.begin()) == bin) {
                    ++count;
                    correct += labels[kind][i] == data.test[i].label;
                    confidence += test[kind][i].confidence;
                }
            const double low = bin == 0 ? 0 : data.params.calibration[bin - 1],
                         high = bin == data.params.calibration.size() ? 1 : data.params.calibration[bin];
            part.push_back("bin " + real(low) + " " + real(high) + " count " + num(count) + " confidence " +
                           (count ? real(confidence / count) : "-") + " accuracy " +
                           (count ? fraction(Fraction(correct, count)) : "-"));
            ece += std::abs(correct - confidence);
        }
        part.push_back("ece " + real(ece / m));
        for (double threshold : data.params.reject) {
            int count = 0, correct = 0;
            for (int i = 0; i < m; ++i)
                if (test[kind][i].confidence >= threshold) {
                    ++count;
                    correct += labels[kind][i] == data.test[i].label;
                }
            part.push_back("reject " + real(threshold) + " accepted " + num(count) + " coverage " +
                           fraction(Fraction(count, m)) + " accuracy " +
                           (count ? fraction(Fraction(correct, count)) : "-"));
        }
        paragraph(out, part);
    }
    const Measures ensemble = evaluate(data.test, labels[3], classes);
    paragraph(out,
              {"ensemble soft_vote", "accuracy " + fraction(ensemble.accuracy) + " balanced_accuracy " +
                                         fraction(ensemble.balanced) + " kappa " + fraction(ensemble.kappa)});
    Lines part = {"mcnemar test"};
    for (int a = 0; a < 4; ++a)
        for (int b = a + 1; b < 4; ++b)
            part.push_back(
                mcnemar_line(model_names[a], model_names[b], mcnemar(data.test, labels[a], labels[b])));
    paragraph(out, part);
    part = {"costs"};
    for (int kind = 0; kind < 3; ++kind) {
        double argmax = 0, decision = 0;
        int changed = 0, correct = 0;
        for (int i = 0; i < m; ++i) {
            argmax += data.costs[data.test[i].label][labels[kind][i]];
            decision += data.costs[data.test[i].label][test[kind][i].decision];
            changed += test[kind][i].decision != labels[kind][i];
            correct += test[kind][i].decision == data.test[i].label;
        }
        part.push_back(model_names[kind] + " argmax_total " + real(argmax) + " decision_total " +
                       real(decision) + " changed " + num(changed) + " decision_accuracy " +
                       fraction(Fraction(correct, m)));
    }
    paragraph(out, part);
    part = {"novelty threshold " + real(data.params.outlier)};
    struct Novel {
        int row, nearest;
        double q;
    };
    std::vector<Novel> novel;
    for (int i = 0; i < m; ++i) {
        int nearest = 0;
        for (int k = 1; k < classes; ++k)
            if (test[2][i].distance[k] < test[2][i].distance[nearest])
                nearest = k;
        if (test[2][i].distance[nearest] > data.params.outlier)
            novel.push_back({i, nearest, test[2][i].distance[nearest]});
    }
    std::sort(novel.begin(), novel.end(),
              [](const Novel &a, const Novel &b) { return a.q != b.q ? a.q > b.q : a.row < b.row; });
    for (const Novel &row : novel)
        part.push_back(num(data.test[row.row].id) + " nearest " + data.classes[row.nearest] + " q " +
                       real(row.q));
    part.push_back("count " + num(novel.size()));
    paragraph(out, part);
    Generator generator{data.params.seed};
    std::array<std::vector<int>, 3> bootstrap;
    std::array<std::array<int, 3>, 3> comparisons{};
    for (int sample = 0; sample < data.params.bootstrap; ++sample) {
        std::array<int, 3> counts{};
        for (int i = 0; i < m; ++i) {
            const int row = generator.draw() % m;
            for (int kind = 0; kind < 3; ++kind)
                counts[kind] += labels[kind][row] == data.test[row].label;
        }
        for (int kind = 0; kind < 3; ++kind)
            bootstrap[kind].push_back(counts[kind]);
        int pair = 0;
        for (int a = 0; a < 3; ++a)
            for (int b = a + 1; b < 3; ++b) {
                ++comparisons[pair][counts[a] > counts[b] ? 0 : counts[a] == counts[b] ? 1 : 2];
                ++pair;
            }
    }
    part = {"bootstrap resamples " + num(data.params.bootstrap) + " seed " + num(data.params.seed)};
    for (int kind = 0; kind < 3; ++kind) {
        const int sum = std::accumulate(bootstrap[kind].begin(), bootstrap[kind].end(), 0);
        std::sort(bootstrap[kind].begin(), bootstrap[kind].end());
        const int offset = data.params.bootstrap / 40;
        part.push_back(model_names[kind] + " mean " + real(double(sum) / data.params.bootstrap / m) +
                       " interval " + fraction(Fraction(bootstrap[kind][offset], m)) + " " +
                       fraction(Fraction(bootstrap[kind][data.params.bootstrap - 1 - offset], m)));
    }
    int pair = 0;
    for (int a = 0; a < 3; ++a)
        for (int b = a + 1; b < 3; ++b) {
            part.push_back(model_names[a] + " " + model_names[b] + " wins " + num(comparisons[pair][0]) +
                           " ties " + num(comparisons[pair][1]) + " losses " + num(comparisons[pair][2]));
            ++pair;
        }
    paragraph(out, part);
    part = {"prior_sensitivity alternative " + std::string(data.params.empirical ? "uniform" : "empirical")};
    for (int kind = 0; kind < 3; ++kind) {
        const Model model = fit(data, data.train, all, kind, data.params.smoothing, data.params.gamma,
                                !data.params.empirical);
        const auto prediction = predictions(data, model, data.test);
        const Measures measures = evaluate(data.test, prediction, classes);
        int changed = 0;
        for (int i = 0; i < m; ++i)
            changed += prediction[i] != labels[kind][i];
        part.push_back(model_names[kind] + " accuracy " + fraction(measures.accuracy) +
                       " balanced_accuracy " + fraction(measures.balanced) + " changed " + num(changed));
    }
    paragraph(out, part);
    part = {"learning_curve"};
    for (int limit : data.params.curve) {
        Rows rows;
        std::array<int, 5> seen{};
        for (const Row &row : data.train)
            if (seen[row.label]++ < limit)
                rows.push_back(row);
        std::string line = "size " + num(limit) + " rows " + num(rows.size());
        for (int kind = 0; kind < 3; ++kind) {
            const Model model = fit(data, rows, all, kind);
            line += " " + model_names[kind] + " " +
                    fraction(Fraction(correct_count(data.test, predictions(data, model, data.test)), m));
        }
        part.push_back(line);
    }
    paragraph(out, part);
    part = {"cross_validation folds " + num(data.params.folds)};
    std::vector<int> fold_sizes(data.params.folds);
    for (const Row &row : data.train)
        ++fold_sizes[row.id % data.params.folds];
    part.push_back("fold_sizes " + integers(fold_sizes));
    int best_subset = -1, best_model = 0, best_correct = -1;
    for (std::size_t subset = 0; subset < data.params.subsets.size(); ++subset) {
        const Subset &selected = data.params.subsets[subset];
        part.push_back("subset " + selected.name + " features " + names(selected.features, data.features));
        for (int kind = 0; kind < 3; ++kind) {
            const CrossValidation result = cross_validate(data, selected.features, kind);
            part.push_back("  " + model_names[kind] + " fold_correct " + integers(result.fold_correct) +
                           " correct " + num(result.correct) + " accuracy " +
                           fraction(Fraction(result.correct, n)));
            if (best_subset < 0 || result.correct > best_correct ||
                (result.correct == best_correct &&
                 selected.features.size() < data.params.subsets[best_subset].features.size())) {
                best_subset = subset;
                best_model = kind;
                best_correct = result.correct;
            }
        }
    }
    const Subset &selected = data.params.subsets[best_subset];
    part.push_back("best subset " + selected.name + " model " + model_names[best_model] + " correct " +
                   num(best_correct) + " accuracy " + fraction(Fraction(best_correct, n)));
    const Model selected_model = fit(data, data.train, selected.features, best_model);
    const int refit_correct = correct_count(data.test, predictions(data, selected_model, data.test));
    part.push_back("refit_test correct " + num(refit_correct) + " accuracy " +
                   fraction(Fraction(refit_correct, m)));
    paragraph(out, part);
    part = {"mcnemar cross_validation"};
    for (int a = 0; a < 3; ++a)
        for (int b = a + 1; b < 3; ++b)
            part.push_back(mcnemar_line(model_names[a], model_names[b],
                                        mcnemar(data.train, cv[a].prediction, cv[b].prediction)));
    paragraph(out, part);
    for (int kind = 0; kind < 3; ++kind) {
        const Measures measures = evaluate(data.train, cv[kind].prediction, classes);
        part = {"cv_confusion model " + model_names[kind]};
        extend(part, confusion_lines(measures, data.classes));
        part.push_back("balanced_accuracy " + fraction(measures.balanced) + " kappa " +
                       fraction(measures.kappa));
        paragraph(out, part);
    }
    part = {"leave_one_out"};
    for (int kind = 0; kind < 3; ++kind) {
        int correct = 0;
        for (int i = 0; i < n; ++i) {
            Rows rows;
            for (int j = 0; j < n; ++j)
                if (j != i)
                    rows.push_back(data.train[j]);
            const Model model = fit(data, rows, all, kind);
            correct += predict(model, data.train[i].values, data.costs).predicted == data.train[i].label;
        }
        part.push_back(model_names[kind] + " correct " + num(correct) + " accuracy " +
                       fraction(Fraction(correct, n)));
    }
    paragraph(out, part);
    for (int kind = 0; kind < 3; ++kind) {
        part = {"forward_selection model " + model_names[kind]};
        Features features;
        int best_step = 0, best = -1;
        for (int step = 1; step <= size; ++step) {
            int chosen = -1, correct = -1;
            for (int feature = 0; feature < size; ++feature)
                if (std::find(features.begin(), features.end(), feature) == features.end()) {
                    Features trial = features;
                    trial.push_back(feature);
                    const int value = cross_validate(data, trial, kind).correct;
                    if (value > correct) {
                        chosen = feature;
                        correct = value;
                    }
                }
            features.push_back(chosen);
            part.push_back("step " + num(step) + " add " + data.features[chosen] + " correct " +
                           num(correct) + " accuracy " + fraction(Fraction(correct, n)));
            if (correct > best) {
                best = correct;
                best_step = step;
            }
        }
        part.push_back("best_step " + num(best_step) + " features " +
                       names(Features(features.begin(), features.begin() + best_step), data.features));
        paragraph(out, part);
    }
    for (int tuning = 0; tuning < 2; ++tuning) {
        const int kind = tuning == 0 ? 0 : 2;
        const auto &grid = tuning == 0 ? data.params.smoothing_grid : data.params.gamma_grid;
        part = {tuning == 0 ? "nb_smoothing_path" : "qda_gamma_path"};
        int best = -1;
        double chosen = 0;
        for (double value : grid) {
            const int correct = cross_validate(data, all, kind, tuning == 0 ? value : data.params.smoothing,
                                               tuning == 1 ? value : data.params.gamma)
                                    .correct;
            part.push_back("value " + real(value) + " correct " + num(correct) + " accuracy " +
                           fraction(Fraction(correct, n)));
            if (correct >= best) {
                best = correct;
                chosen = value;
            }
        }
        const Model model = fit(data, data.train, all, kind, tuning == 0 ? chosen : data.params.smoothing,
                                tuning == 1 ? chosen : data.params.gamma, data.params.empirical);
        const int correct = correct_count(data.test, predictions(data, model, data.test));
        part.push_back("best " + real(chosen) + " test correct " + num(correct) + " accuracy " +
                       fraction(Fraction(correct, m)));
        paragraph(out, part);
    }
    return out;
}
static Lines boundaries(const Dataset &data) {
    Lines out;
    const int width = data.params.map_width, height = data.params.map_height, classes = data.classes.size();
    for (const auto &pair : data.params.pairs) {
        const Features features = {pair.first, pair.second};
        double xmin = data.train[0].values[pair.first], xmax = xmin, ymin = data.train[0].values[pair.second],
               ymax = ymin;
        for (const Row &row : data.train) {
            xmin = std::min(xmin, row.values[pair.first]);
            xmax = std::max(xmax, row.values[pair.first]);
            ymin = std::min(ymin, row.values[pair.second]);
            ymax = std::max(ymax, row.values[pair.second]);
        }
        const double dx = (xmax - xmin) / (width - 1), dy = (ymax - ymin) / (height - 1);
        Lines part = {"pair " + data.features[pair.first] + " " + data.features[pair.second],
                      "x " + data.features[pair.first] + " " + real(xmin) + " " + real(xmax) + " y " +
                          data.features[pair.second] + " " + real(ymin) + " " + real(ymax) + " grid " +
                          num(width) + "x" + num(height)};
        std::array<Lines, 3> maps;
        std::array<std::vector<Prediction>, 3> grid;
        for (int kind = 0; kind < 3; ++kind) {
            const Model model = fit(data, data.train, features, kind);
            const int correct = correct_count(data.train, predictions(data, model, data.train)),
                      cv = cross_validate(data, features, kind).correct;
            part.push_back("model " + model_names[kind] + " train_accuracy " +
                           fraction(Fraction(correct, data.train.size())) + " cv_accuracy " +
                           fraction(Fraction(cv, data.train.size())));
            maps[kind] = Lines(height, std::string(width, ' '));
            std::array<int, 5> cells{};
            for (int r = 0; r < height; ++r)
                for (int col = 0; col < width; ++col) {
                    Vector values{};
                    values[pair.first] = xmin + col * dx;
                    values[pair.second] = ymax - r * dy;
                    const Prediction prediction = predict(model, values, data.costs);
                    grid[kind].push_back(prediction);
                    maps[kind][r][col] = char(data.classes[prediction.predicted][0] - 'a' + 'A');
                    ++cells[prediction.predicted];
                }
            extend(part, frame(maps[kind]));
            std::string line = "cells";
            for (int k = 0; k < classes; ++k)
                line += " " + std::string(1, char(data.classes[k][0] - 'a' + 'A')) + " " + num(cells[k]);
            part.push_back(line);
        }
        Lines agreement(height, std::string(width, '.')), uncertainty(height, std::string(width, ' ')),
            points(height, std::string(width, ' '));
        int disagreement = 0;
        const std::string levels = " .:-=+*#%@";
        for (int r = 0; r < height; ++r)
            for (int col = 0; col < width; ++col) {
                const int index = r * width + col, a = grid[0][index].predicted, b = grid[1][index].predicted,
                          c = grid[2][index].predicted,
                          distinct = a == b && b == c             ? 1
                                     : a == b || a == c || b == c ? 2
                                                                  : 3;
                if (distinct > 1) {
                    agreement[r][col] = char('0' + distinct);
                    ++disagreement;
                }
                const double u = (1 - grid[2][index].confidence) / (1 - 1.0 / classes);
                const int level = std::min(9, int(std::floor(10 * u)));
                uncertainty[r][col] = levels[level];
            }
        for (const Row &row : data.train) {
            const int col = cell(row.values[pair.first], xmin, xmax, width),
                      r = height - 1 - cell(row.values[pair.second], ymin, ymax, height);
            const char letter = data.classes[row.label][0];
            points[r][col] = points[r][col] == ' ' || points[r][col] == letter ? letter : '*';
        }
        part.push_back("agreement");
        extend(part, frame(agreement));
        part.push_back("disagreement_cells " + num(disagreement));
        part.push_back("uncertainty QDA");
        extend(part, frame(uncertainty));
        part.push_back("points");
        extend(part, frame(points));
        paragraph(out, part);
    }
    return out;
}
static Lines projection(const Dataset &data, const Features &all, const Model &lda) {
    const Statistics &stats = lda.stats;
    const int size = all.size(), classes = data.classes.size();
    Matrix within{}, between{};
    Vector f_values{};
    for (int a = 0; a < size; ++a)
        for (int b = 0; b < size; ++b) {
            for (int k = 0; k < classes; ++k)
                within[a][b] += stats.scatter[k][a][b];
            for (int k = 0; k < classes; ++k)
                between[a][b] += stats.counts[k] * (stats.means[k][a] - stats.center[a]) *
                                 (stats.means[k][b] - stats.center[b]);
        }
    for (int j = 0; j < size; ++j)
        f_values[j] = (between[j][j] / (classes - 1)) / (within[j][j] / (stats.count - classes));
    std::vector<int> feature_order = all;
    std::sort(feature_order.begin(), feature_order.end(),
              [&](int a, int b) { return f_values[a] != f_values[b] ? f_values[a] > f_values[b] : a < b; });
    Lines out = {"univariate"};
    for (int rank = 0; rank < size; ++rank) {
        const int j = feature_order[rank];
        out.push_back("rank " + num(rank + 1) + " " + data.features[j] + " f " + real(f_values[j]) +
                      " between " + real(between[j][j]) + " within " + real(within[j][j]));
    }
    const Matrix lower = cholesky(within, size);
    Matrix y{}, z{}, symmetric{};
    for (int j = 0; j < size; ++j) {
        Vector column{};
        for (int a = 0; a < size; ++a)
            column[a] = between[a][j];
        const Vector result = forward(lower, column, size);
        for (int a = 0; a < size; ++a)
            y[a][j] = result[a];
    }
    for (int i = 0; i < size; ++i) {
        const Vector result = forward(lower, y[i], size);
        for (int a = 0; a < size; ++a)
            z[a][i] = result[a];
    }
    for (int a = 0; a < size; ++a)
        for (int b = 0; b < size; ++b)
            symmetric[a][b] = (z[a][b] + z[b][a]) / 2;
    const Eigen eigen = jacobi(symmetric, size);
    const auto order = eigen_order(eigen, size);
    double total = 0;
    for (int j = 0; j < size; ++j)
        total += eigen.values[j];
    Vector values{}, ratios{};
    for (int j = 0; j < size; ++j) {
        values[j] = eigen.values[order[j]];
        ratios[j] = values[j] / total;
    }
    std::array<Vector, 2> directions{}, standardized{};
    for (int t = 0; t < 2; ++t) {
        Vector column{};
        for (int j = 0; j < size; ++j)
            column[j] = eigen.vectors[j][order[t]];
        Vector direction = backward(lower, column, size);
        double squares = 0;
        for (int j = 0; j < size; ++j)
            squares += direction[j] * direction[j];
        const double norm = std::sqrt(squares);
        int largest = 0;
        for (int j = 0; j < size; ++j) {
            direction[j] /= norm;
            if (std::abs(direction[j]) > std::abs(direction[largest]))
                largest = j;
        }
        if (direction[largest] < 0)
            for (int j = 0; j < size; ++j)
                direction[j] = -direction[j];
        directions[t] = direction;
        for (int j = 0; j < size; ++j)
            standardized[t][j] = direction[j] * std::sqrt(lda.covariance[0][j][j]);
    }
    auto project = [&](const Vector &point) {
        std::array<double, 2> result{};
        for (int t = 0; t < 2; ++t)
            for (int j = 0; j < size; ++j)
                result[t] += directions[t][j] * (point[j] - stats.center[j]);
        return result;
    };
    std::array<std::array<double, 2>, 5> centers{}, spread{};
    for (int k = 0; k < classes; ++k) {
        centers[k] = project(stats.means[k]);
        for (int t = 0; t < 2; ++t) {
            double sum = 0;
            for (const Row &row : data.train)
                if (row.label == k) {
                    const auto point = project(row.values);
                    sum += (point[t] - centers[k][t]) * (point[t] - centers[k][t]);
                }
            spread[k][t] = std::sqrt(sum / stats.counts[k]);
        }
    }
    Lines part = {"fisher features " + names(all, data.features), "center " + numbers(stats.center, size),
                  "sweeps " + num(eigen.sweeps), "eigenvalues " + numbers(values, size),
                  "ratios " + numbers(ratios, size)};
    for (int t = 0; t < 2; ++t) {
        part.push_back("direction " + num(t + 1) + " " + numbers(directions[t], size));
        part.push_back("standardized " + num(t + 1) + " " + numbers(standardized[t], size));
    }
    for (int k = 0; k < classes; ++k)
        part.push_back("centroid " + data.classes[k] + " " + real(centers[k][0]) + " " + real(centers[k][1]) +
                       " spread " + real(spread[k][0]) + " " + real(spread[k][1]));
    for (int dims = 1; dims <= 2; ++dims) {
        auto correct = [&](const Rows &rows) {
            int count = 0;
            for (const Row &row : rows) {
                const auto point = project(row.values);
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
                count += selected == row.label;
            }
            return count;
        };
        part.push_back("nearest_centroid dims " + num(dims) + " train " +
                       fraction(Fraction(correct(data.train), data.train.size())) + " test " +
                       fraction(Fraction(correct(data.test), data.test.size())));
    }
    paragraph(out, part);
    std::vector<std::array<double, 2>> points;
    for (const Row &row : data.train)
        points.push_back(project(row.values));
    double lo1 = points[0][0], hi1 = lo1, lo2 = points[0][1], hi2 = lo2;
    for (const auto &point : points) {
        lo1 = std::min(lo1, point[0]);
        hi1 = std::max(hi1, point[0]);
        lo2 = std::min(lo2, point[1]);
        hi2 = std::max(hi2, point[1]);
    }
    const int width = data.params.plot_width, height = data.params.plot_height;
    Lines cells(height, std::string(width, ' '));
    for (std::size_t i = 0; i < points.size(); ++i) {
        const int col = cell(points[i][0], lo1, hi1, width),
                  row = height - 1 - cell(points[i][1], lo2, hi2, height);
        const char letter = data.classes[data.train[i].label][0];
        cells[row][col] = cells[row][col] == ' ' || cells[row][col] == letter ? letter : '*';
    }
    for (int k = 0; k < classes; ++k)
        cells[height - 1 - cell(centers[k][1], lo2, hi2, height)][cell(centers[k][0], lo1, hi1, width)] =
            char(data.classes[k][0] - 'a' + 'A');
    part = {"plot x " + real(lo1) + " " + real(hi1) + " y " + real(lo2) + " " + real(hi2) + " size " +
            num(width) + "x" + num(height)};
    extend(part, frame(cells));
    paragraph(out, part);
    return out;
}
int main() {
    std::filesystem::create_directories("output");
    const Dataset data = read_dataset();
    Features all(data.features.size());
    std::iota(all.begin(), all.end(), 0);
    std::array<Model, 3> models;
    std::array<std::vector<Prediction>, 3> test;
    std::array<std::vector<int>, 4> labels;
    std::array<CrossValidation, 3> cv;
    for (int kind = 0; kind < 3; ++kind) {
        models[kind] = fit(data, data.train, all, kind);
        for (const Row &row : data.test) {
            const Prediction prediction = predict(models[kind], row.values, data.costs);
            test[kind].push_back(prediction);
            labels[kind].push_back(prediction.predicted);
        }
        cv[kind] = cross_validate(data, all, kind);
    }
    for (std::size_t i = 0; i < data.test.size(); ++i) {
        int selected = 0;
        std::array<double, 5> posterior{};
        for (std::size_t k = 0; k < data.classes.size(); ++k) {
            double sum = 0;
            for (int kind = 0; kind < 3; ++kind)
                sum += test[kind][i].posterior[k];
            posterior[k] = sum / 3;
            if (posterior[k] > posterior[selected])
                selected = k;
        }
        labels[3].push_back(selected);
    }
    write_lines("models.txt", model_report(data, all, models));
    Lines csv = {"id,model,actual,predicted,decision"};
    for (const std::string &name : data.classes)
        csv[0] += "," + name;
    for (std::size_t i = 0; i < data.test.size(); ++i)
        for (int kind = 0; kind < 3; ++kind) {
            const Prediction &prediction = test[kind][i];
            std::string line = num(data.test[i].id) + "," + model_names[kind] + "," +
                               data.classes[data.test[i].label] + "," + data.classes[prediction.predicted] +
                               "," + data.classes[prediction.decision];
            for (std::size_t k = 0; k < data.classes.size(); ++k)
                line += "," + real(prediction.posterior[k]);
            csv.push_back(line);
        }
    write_lines("predictions.csv", csv);
    write_lines("evaluation.txt", evaluation_report(data, all, models, test, labels, cv));
    write_lines("boundaries.txt", boundaries(data));
    write_lines("projection.txt", projection(data, all, models[1]));
}
