#include "classifier.hpp"
static std::vector<Example> selected_data(const std::vector<Example> &data, const Ids &indices) {
    std::vector<Example> out;
    for (int i : indices)
        out.push_back(data[i]);
    return out;
}
static Matrix selected_matrix(const Matrix &matrix, const Ids &indices) {
    Matrix out(indices.size(), Field(indices.size()));
    for (int i = 0; i < int(indices.size()); ++i)
        for (int j = 0; j < int(indices.size()); ++j)
            out[i][j] = matrix[indices[i]][indices[j]];
    return out;
}
static Field decisions(const Model &model, const std::vector<Example> &data) {
    Field out;
    for (const Example &example : data)
        out.push_back(model.decision(example.point));
    return out;
}
struct Support {
    int total = 0, bound = 0, free = 0;
    std::array<int, 2> by_bound{}, by_free{};
};
static Support support(const Model &model) {
    Support out;
    for (int i = 0; i < int(model.alpha.size()); ++i)
        if (model.alpha[i] > 0) {
            ++out.total;
            const int label = model.data[i].label == 1 ? 0 : 1;
            if (model.alpha[i] == model.c) {
                ++out.bound;
                ++out.by_bound[label];
            } else {
                ++out.free;
                ++out.by_free[label];
            }
        }
    return out;
}
static std::string support_text(const Model &model) {
    const Support s = support(model);
    return "support_vectors " + std::to_string(s.total) + " bound " + std::to_string(s.bound) +
           " free " + std::to_string(s.free);
}
static std::string run_info(const Model &model) {
    return "passes " + std::to_string(model.passes.size()) + " steps " +
           std::to_string(model.steps) + " converged " + (model.converged ? "yes" : "no");
}
static std::pair<double, double> objectives(const Field &alpha, const std::vector<Example> &data,
                                            const Matrix &matrix) {
    double q = 0, total = 0;
    for (int i = 0; i < int(alpha.size()); ++i) {
        double sum = 0;
        for (int j = 0; j < int(alpha.size()); ++j)
            if (alpha[j] > 0)
                sum += alpha[j] * data[j].label * matrix[i][j];
        q += alpha[i] * data[i].label * sum;
        total += alpha[i];
    }
    return {q, total - q / 2};
}
struct FoldResult {
    int train, test, correct, sv, passes, steps;
    bool converged;
};
struct CV {
    int kernel, candidate, correct = 0, sv = 0, passes = 0, steps = 0;
    Field decisions;
    std::vector<FoldResult> folds;
};
static CV cross_validate(const Input &input, int kernel, int candidate, const Matrix &matrix) {
    CV out;
    out.kernel = kernel;
    out.candidate = candidate;
    out.decisions.resize(input.train.size());
    for (const Fold &fold : folds(int(input.train.size()), input.params.folds)) {
        const Model model = train(selected_data(input.train, fold.train),
                                  input.params.kernels[kernel], selected_matrix(matrix, fold.train),
                                  input.params.c_grid[candidate], input.params);
        int correct = 0;
        for (int i : fold.test) {
            out.decisions[i] = model.decision(input.train[i].point);
            correct += sign(out.decisions[i]) == input.train[i].label;
        }
        const int sv = support(model).total;
        out.correct += correct;
        out.sv += sv;
        out.passes += int(model.passes.size());
        out.steps += model.steps;
        out.folds.push_back({int(fold.train.size()), int(fold.test.size()), correct, sv,
                             int(model.passes.size()), model.steps, model.converged});
    }
    return out;
}
struct Metrics {
    Field train, test;
    Support sv;
    Point weights{};
    double alignment = 0, equality = 0, q = 0, dual = 0, primal = 0, violation = 0, radius = 0,
           positive_mean = 0, negative_mean = 0;
    int violations = 0, estimated_errors = 0, train_correct = 0, inside = 0;
    Evaluation evaluation;
};
static Metrics metrics(const Input &input, const Model &model) {
    Metrics out;
    out.train = model.training_decisions();
    out.test = decisions(model, input.test);
    out.sv = support(model);
    const auto [q, dual] = objectives(model.alpha, model.data, model.matrix);
    out.q = q;
    out.dual = dual;
    double sy = 0, sg = 0, xi = 0, maximum_diagonal = model.matrix[0][0],
           minimum = model.matrix[0][0];
    for (int i = 0; i < int(model.data.size()); ++i) {
        for (int j = 0; j < int(model.data.size()); ++j) {
            sy += model.data[i].label * model.data[j].label * model.matrix[i][j];
            sg += model.matrix[i][j] * model.matrix[i][j];
            minimum = std::min(minimum, model.matrix[i][j]);
        }
        maximum_diagonal = std::max(maximum_diagonal, model.matrix[i][i]);
        out.equality += model.alpha[i] * model.data[i].label;
        for (int coordinate = 0; coordinate < 2; ++coordinate)
            out.weights[coordinate] +=
                model.alpha[i] * model.data[i].label * model.data[i].point[coordinate];
        const double residual = model.data[i].label * out.train[i] - 1,
                     violation = model.alpha[i] == 0         ? std::max(0.0, -residual)
                                 : model.alpha[i] == model.c ? std::max(0.0, residual)
                                                             : std::abs(residual);
        out.violations += violation > input.params.tolerance;
        out.violation = std::max(out.violation, violation);
        xi += std::max(0.0, 1 - model.data[i].label * out.train[i]);
        out.train_correct += sign(out.train[i]) == model.data[i].label;
    }
    out.alignment = sy / (double(model.data.size()) * std::sqrt(sg));
    out.radius = maximum_diagonal - minimum;
    out.primal = q / 2 + model.c * xi;
    for (int i = 0; i < int(model.data.size()); ++i)
        out.estimated_errors += 2 * model.alpha[i] * out.radius +
                                    std::max(0.0, 1 - model.data[i].label * out.train[i]) >=
                                1;
    int positive = 0, negative = 0;
    for (int i = 0; i < int(input.test.size()); ++i) {
        const double value = out.test[i];
        out.inside += std::abs(value) < 1;
        if (input.test[i].label == 1) {
            out.positive_mean += value;
            ++positive;
        } else {
            out.negative_mean += value;
            ++negative;
        }
    }
    out.positive_mean /= positive;
    out.negative_mean /= negative;
    out.evaluation = evaluate(input.test, out.test);
    return out;
}
static void model_report(Lines &out, const Input &input, const Model &model, const Metrics &m) {
    const int n = int(input.train.size()), count = int(input.test.size());
    const Evaluation &e = m.evaluation;
    line(out, "model ", model.kernel.name);
    line(out, "kernel ", kernel_description(model.kernel));
    line(out, "C ", real(model.c, 4));
    line(out, "alignment ", real(m.alignment, 6));
    line(out, "passes ", model.passes.size(), " full ", model.full, " nonbound ", model.nonbound,
         " converged ", model.converged ? "yes" : "no");
    line(out, "examined ", model.examined, " steps ", model.steps);
    line(out, "choice heuristic ", model.choices[0], " nonbound_loop ", model.choices[1],
         " full_loop ", model.choices[2]);
    line(out, "clipping none ", model.clipping[0], " lower ", model.clipping[1], " upper ",
         model.clipping[2]);
    out.push_back(support_text(model));
    line(out, "b ", real(model.b, 6));
    line(out, "equality ", real(m.equality, 6));
    if (model.kernel.kind == "linear")
        line(out, "w ", real(m.weights[0], 6), " ", real(m.weights[1], 6));
    line(out, "sv_by_class positive bound ", m.sv.by_bound[0], " free ", m.sv.by_free[0],
         " negative bound ", m.sv.by_bound[1], " free ", m.sv.by_free[1]);
    line(out, "norm ", real(std::sqrt(m.q), 6), " margin ", real(2 / std::sqrt(m.q), 6));
    line(out, "dual_objective ", real(m.dual, 6));
    line(out, "primal_objective ", real(m.primal, 6));
    line(out, "duality_gap ", real(m.primal - m.dual, 6));
    line(out, "kkt_violations ", m.violations, " max ", real(m.violation, 6));
    line(out, "xi_alpha radius ", real(m.radius, 6), " errors ", m.estimated_errors, "/", n,
         " accuracy ", ratio(n - m.estimated_errors, n));
    line(out, "train correct ", m.train_correct, "/", n, " accuracy ", ratio(m.train_correct, n));
    line(out, "test correct ", e.correct(), "/", count, " accuracy ", ratio(e.correct(), count),
         " tp ", e.tp, " fp ", e.fp, " tn ", e.tn, " fn ", e.fn);
    line(out, "test precision ", ratio(e.tp, e.tp + e.fp), " recall ", ratio(e.tp, e.tp + e.fn),
         " f1 ", ratio(2 * e.tp, 2 * e.tp + e.fp + e.fn), " auc ",
         real(auc(input.test, m.test), 4));
    line(out, "test inside_margin ", m.inside);
    line(out, "test mean_decision positive ", real(m.positive_mean, 4), " negative ",
         real(m.negative_mean, 4));
    for (int i = 0; i < n; ++i)
        if (model.alpha[i] > 0)
            line(out, "sv ", model.data[i].id, " y ", model.data[i].label, " alpha ",
                 real(model.alpha[i], 6), " f ", real(m.train[i], 4), " ",
                 model.alpha[i] == model.c ? "bound" : "free");
}
static double probability(double value, double a, double b) {
    return 1 / (1 + std::exp(a * value + b));
}
static double nll(const Field &values, const Field &targets, double a, double b) {
    double out = 0;
    for (int i = 0; i < int(values.size()); ++i) {
        const double p = probability(values[i], a, b);
        out += targets[i] * std::log(p) + (1 - targets[i]) * std::log(1 - p);
    }
    return -out;
}
struct Calibration {
    double a = 0, b = 0;
    Field probabilities;
    Lines lines;
};
static Calibration calibrate(const Input &input, const Model &model, const Field &cv,
                             const Field &test) {
    Calibration out;
    int positive = 0;
    for (const Example &example : input.train)
        positive += example.label == 1;
    const int negative = int(input.train.size()) - positive;
    Field targets;
    for (const Example &example : input.train)
        targets.push_back(example.label == 1 ? double(positive + 1) / (positive + 2)
                                             : 1.0 / (negative + 2));
    out.b = std::log(double(negative + 1) / (positive + 1));
    line(out.lines, "calibration ", model.kernel.name, " C ", real(model.c, 4), " positives ",
         positive, " negatives ", negative);
    line(out.lines, "start A ", real(out.a, 6), " B ", real(out.b, 6), " nll ",
         real(nll(cv, targets, out.a, out.b), 6));
    for (int iteration = 1; iteration <= input.params.newton_iterations; ++iteration) {
        double g1 = 0, g2 = 0, h11 = 0, h21 = 0, h22 = 0;
        for (int i = 0; i < int(cv.size()); ++i) {
            const double p = probability(cv[i], out.a, out.b);
            g1 += cv[i] * (targets[i] - p);
            g2 += targets[i] - p;
            h11 += cv[i] * cv[i] * p * (1 - p);
            h21 += cv[i] * p * (1 - p);
            h22 += p * (1 - p);
        }
        const double determinant = h11 * h22 - h21 * h21,
                     a = out.a - (h22 * g1 - h21 * g2) / determinant,
                     b = out.b - (h11 * g2 - h21 * g1) / determinant;
        out.a = a;
        out.b = b;
        line(out.lines, "iteration ", iteration, " A ", real(a, 6), " B ", real(b, 6), " nll ",
             real(nll(cv, targets, a, b), 6));
    }
    std::array<int, 5> count{}, positives{};
    std::array<double, 5> sums{};
    double loss = 0, brier = 0;
    for (int i = 0; i < int(test.size()); ++i) {
        const double p = probability(test[i], out.a, out.b);
        out.probabilities.push_back(p);
        loss += input.test[i].label == 1 ? std::log(p) : std::log(1 - p);
        const double error = p - (input.test[i].label == 1 ? 1 : 0);
        brier += error * error;
        const int bin = std::min(4, int(std::floor(p * 5)));
        ++count[bin];
        sums[bin] += p;
        positives[bin] += input.test[i].label == 1;
    }
    line(out.lines, "test log_loss ", real(-loss / double(test.size()), 6), " brier ",
         real(brier / double(test.size()), 6));
    const std::array<std::string, 5> ranges{"0.0-0.2", "0.2-0.4", "0.4-0.6", "0.6-0.8", "0.8-1.0"};
    for (int bin = 0; bin < 5; ++bin)
        line(out.lines, "bin ", ranges[bin], " count ", count[bin], " mean_probability ",
             count[bin] ? real(sums[bin] / count[bin], 4) : "-", " positive_rate ",
             ratio(positives[bin], count[bin]));
    Ids closest(test.size());
    std::iota(closest.begin(), closest.end(), 0);
    std::sort(closest.begin(), closest.end(), [&](int a, int b) {
        const double x = std::abs(test[a]), y = std::abs(test[b]);
        return x != y ? x < y : a < b;
    });
    for (int index : Ids(closest.begin(), closest.begin() + 5))
        line(out.lines, "closest ", input.test[index].id, " label ", input.test[index].label,
             " decision ", real(test[index], 4), " probability ",
             real(out.probabilities[index], 4));
    return out;
}
using Weights = std::array<double, 3>;
static double psi(Weights weights, Point point) {
    return weights[0] * point[0] + weights[1] * point[1] + weights[2];
}
struct Pegasos {
    Weights weights{}, average{};
    Field test;
    Lines lines;
};
static Pegasos pegasos(const Input &input, const Model &linear, const Metrics &linear_metrics) {
    Pegasos out;
    const Params &p = input.params;
    std::int64_t state = p.seed;
    Weights sums{};
    int updates = 0;
    const int n = int(input.train.size()), m = int(input.test.size());
    line(out.lines, "pegasos lambda ", real(p.lambda, 4), " iterations ", p.pegasos_iterations,
         " seed ", p.seed);
    for (int t = 1; t <= p.pegasos_iterations; ++t) {
        state = 48271 * state % 2147483647;
        const Example &example = input.train[std::size_t(state % n)];
        const double eta = 1 / (p.lambda * t), sigma = 1 - eta * p.lambda;
        const bool update = example.label * psi(out.weights, example.point) < 1;
        if (update) {
            out.weights[0] = sigma * out.weights[0] + eta * example.label * example.point[0];
            out.weights[1] = sigma * out.weights[1] + eta * example.label * example.point[1];
            out.weights[2] = sigma * out.weights[2] + eta * example.label;
            ++updates;
        } else
            for (double &weight : out.weights)
                weight = sigma * weight;
        for (int i = 0; i < 3; ++i)
            sums[i] += out.weights[i];
        if (t % (p.pegasos_iterations / 10) == 0) {
            double xi = 0;
            int correct = 0;
            for (const Example &example : input.train) {
                const double value = psi(out.weights, example.point);
                xi += std::max(0.0, 1 - example.label * value);
                correct += sign(value) == example.label;
            }
            const Weights &w = out.weights;
            const double objective =
                p.lambda / 2 * (w[0] * w[0] + w[1] * w[1] + w[2] * w[2]) + xi / n;
            line(out.lines, "checkpoint ", t, " objective ", real(objective, 6), " train ", correct,
                 "/", n);
        }
    }
    for (int i = 0; i < 3; ++i)
        out.average[i] = sums[i] / p.pegasos_iterations;
    int train_correct = 0, test_correct = 0, average_correct = 0, agreement = 0;
    for (const Example &example : input.train)
        train_correct += sign(psi(out.weights, example.point)) == example.label;
    for (int i = 0; i < m; ++i) {
        const double value = psi(out.weights, input.test[i].point);
        out.test.push_back(value);
        test_correct += sign(value) == input.test[i].label;
        average_correct += sign(psi(out.average, input.test[i].point)) == input.test[i].label;
        agreement += sign(value) == sign(linear_metrics.test[i]);
    }
    const Weights &w = out.weights;
    const Point &v = linear_metrics.weights;
    const double cosine = (w[0] * v[0] + w[1] * v[1]) / (std::sqrt(w[0] * w[0] + w[1] * w[1]) *
                                                         std::sqrt(v[0] * v[0] + v[1] * v[1]));
    line(out.lines, "updates ", updates);
    line(out.lines, "w ", real(w[0], 6), " ", real(w[1], 6), " bias ", real(w[2], 6));
    line(out.lines, "train correct ", train_correct, "/", n, " accuracy ", ratio(train_correct, n));
    line(out.lines, "test correct ", test_correct, "/", m, " accuracy ", ratio(test_correct, m));
    line(out.lines, "average w ", real(out.average[0], 6), " ", real(out.average[1], 6), " bias ",
         real(out.average[2], 6), " test correct ", average_correct, "/", m);
    line(out.lines, "compare ", linear.kernel.name, " cosine ", real(cosine, 6), " test_agreement ",
         agreement, "/", m);
    return out;
}
static std::string multi_summary(const std::string &prefix, const std::vector<Example> &data,
                                 const std::vector<MultiPrediction> &predictions) {
    int rest = 0, one = 0, agreement = 0, ties = 0;
    for (int i = 0; i < int(data.size()); ++i) {
        rest += predictions[i].ovr == data[i].label;
        one += predictions[i].ovo == data[i].label;
        agreement += predictions[i].ovr == predictions[i].ovo;
        ties += predictions[i].tie;
    }
    const int n = int(data.size());
    return prefix + " ovr " + std::to_string(rest) + "/" + std::to_string(n) + " " +
           ratio(rest, n) + " ovo " + std::to_string(one) + "/" + std::to_string(n) + " " +
           ratio(one, n) + " agreement " + std::to_string(agreement) + "/" + std::to_string(n) +
           " vote_ties " + std::to_string(ties);
}
static Lines multi_report(const Input &input, const Multi &models) {
    Lines out;
    const int n = int(input.multi_train.size()), m = int(input.multi_test.size());
    line(out, "multiclass kernel ", input.params.multi_name, " C ", real(input.params.multi_c, 4),
         " classes 3 train ", n, " test ", m);
    out.push_back("ovr");
    for (int k = 1; k <= 3; ++k) {
        const Model &model = models.rest[k - 1];
        int positive = 0, correct = 0;
        for (const Example &example : model.data)
            positive += example.label == 1;
        for (const Example &example : input.multi_test)
            correct += sign(model.decision(example.point)) == (example.label == k ? 1 : -1);
        line(out, "model ", k, "-rest examples ", n, " positives ", positive, " ",
             support_text(model), " b ", real(model.b, 6), " ", run_info(model), " test ", correct,
             "/", m);
    }
    out.push_back("ovo");
    const std::array<std::array<int, 2>, 3> pairs{{{1, 2}, {1, 3}, {2, 3}}};
    for (int k = 0; k < 3; ++k) {
        const Model &model = models.pairs[k];
        int positive = 0, correct = 0, count = 0;
        for (const Example &example : model.data)
            positive += example.label == 1;
        for (const Example &example : input.multi_test)
            if (example.label == pairs[k][0] || example.label == pairs[k][1]) {
                ++count;
                correct +=
                    sign(model.decision(example.point)) == (example.label == pairs[k][0] ? 1 : -1);
            }
        line(out, "model ", pairs[k][0], "-", pairs[k][1], " examples ", model.data.size(),
             " positives ", positive, " ", support_text(model), " b ", real(model.b, 6), " ",
             run_info(model), " test ", correct, "/", count);
    }
    std::vector<MultiPrediction> train_predictions, test_predictions;
    for (const Example &example : input.multi_train)
        train_predictions.push_back(classify(models, example.point));
    for (const Example &example : input.multi_test)
        test_predictions.push_back(classify(models, example.point));
    out.push_back("predictions");
    for (int i = 0; i < m; ++i) {
        const MultiPrediction &p = test_predictions[i];
        line(out, input.multi_test[i].id, " class ", input.multi_test[i].label, " ovr ",
             real(p.rest[0], 4), " ", real(p.rest[1], 4), " ", real(p.rest[2], 4), " pred ", p.ovr,
             " ovo ", real(p.pairs[0], 4), " ", real(p.pairs[1], 4), " ", real(p.pairs[2], 4),
             " votes ", p.votes[0], " ", p.votes[1], " ", p.votes[2], " pred ", p.ovo);
    }
    out.push_back(multi_summary("train", input.multi_train, train_predictions));
    out.push_back(multi_summary("test", input.multi_test, test_predictions));
    for (bool rest : {true, false}) {
        const Confusion confusion = confusion_matrix(input.multi_test, test_predictions, rest);
        line(out, "confusion ", rest ? "ovr" : "ovo");
        for (const auto &row : confusion)
            line(out, row[0], " ", row[1], " ", row[2]);
        for (int k = 0; k < 3; ++k) {
            int column = 0, row = 0;
            for (int j = 0; j < 3; ++j) {
                column += confusion[j][k];
                row += confusion[k][j];
            }
            line(out, "class ", k + 1, " precision ", ratio(confusion[k][k], column), " recall ",
                 ratio(confusion[k][k], row));
        }
    }
    return out;
}
static void frame(Lines &out, const std::vector<std::string> &rows, int width) {
    out.push_back("+" + std::string(width, '-') + "+");
    for (const std::string &row : rows)
        out.push_back("|" + row + "|");
    out.push_back("+" + std::string(width, '-') + "+");
}
static Lines plots(const Input &input, const std::vector<Model> &models, int selected,
                   const Calibration &calibration, const Multi &multi) {
    const Params &p = input.params;
    const Model &model = models[selected];
    const double dx = (p.x_max - p.x_min) / p.width, dy = (p.y_max - p.y_min) / p.height;
    std::vector<std::string> binary(p.height, std::string(p.width, ' ')), probabilities = binary,
                                                                          multiclass = binary;
    std::vector<Ids> signs(models.size(), Ids(p.width * p.height));
    for (int row = 0; row < p.height; ++row)
        for (int column = 0; column < p.width; ++column) {
            const Point point{p.x_min + (column + 0.5) * dx, p.y_max - (row + 0.5) * dy};
            const double value = model.decision(point);
            binary[row][column] = value >= 1 ? '+' : value > 0 ? '.' : value > -1 ? '-' : ' ';
            probabilities[row][column] = char(
                '0' + std::min(9, int(std::floor(probability(value, calibration.a, calibration.b) *
                                                 10))));
            const MultiPrediction prediction = classify(multi, point);
            multiclass[row][column] = prediction.ovr != prediction.ovo ? '?'
                                      : prediction.ovr == 1            ? ' '
                                      : prediction.ovr == 2            ? '.'
                                                                       : ':';
            for (int k = 0; k < int(models.size()); ++k)
                signs[k][row * p.width + column] = sign(models[k].decision(point));
        }
    auto location = [&](Point point) {
        const double column = std::floor((point[0] - p.x_min) / dx),
                     row = std::floor((p.y_max - point[1]) / dy);
        if (column < 0 || column >= p.width || row < 0 || row >= p.height)
            return -1;
        return int(row) * p.width + int(column);
    };
    Ids assigned(p.width * p.height, -1), multi_assigned(p.width * p.height, -1);
    int outside = 0, multi_outside = 0;
    for (int i = 0; i < int(input.train.size()); ++i) {
        const int cell = location(input.train[i].point);
        if (cell < 0) {
            ++outside;
            continue;
        }
        if (assigned[cell] < 0 || (model.alpha[i] > 0 && model.alpha[assigned[cell]] == 0))
            assigned[cell] = i;
    }
    for (int i = 0; i < int(input.multi_train.size()); ++i) {
        const int cell = location(input.multi_train[i].point);
        if (cell < 0) {
            ++multi_outside;
            continue;
        }
        if (multi_assigned[cell] < 0)
            multi_assigned[cell] = i;
    }
    int points = 0, multi_points = 0;
    std::array<int, 4> count{}, multi_count{};
    std::array<int, 10> levels{};
    for (int cell = 0; cell < p.width * p.height; ++cell) {
        const int row = cell / p.width, column = cell % p.width;
        if (assigned[cell] >= 0) {
            ++points;
            const int i = assigned[cell];
            binary[row][column] = input.train[i].label == 1 ? (model.alpha[i] > 0 ? 'X' : 'x')
                                                            : (model.alpha[i] > 0 ? 'O' : 'o');
        }
        if (multi_assigned[cell] >= 0) {
            ++multi_points;
            multiclass[row][column] = char('0' + input.multi_train[multi_assigned[cell]].label);
        }
        const char b = binary[row][column], m = multiclass[row][column];
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
        ++levels[probabilities[row][column] - '0'];
    }
    Lines out;
    line(out, "binary ", model.kernel.name, " C ", real(model.c, 4));
    line(out, "x ", real(p.x_min, 4), " ", real(p.x_max, 4), " y ", real(p.y_min, 4), " ",
         real(p.y_max, 4), " grid ", p.width, "x", p.height);
    frame(out, binary, p.width);
    line(out, "cells outer_positive ", count[0], " inner_positive ", count[1], " inner_negative ",
         count[2], " outer_negative ", count[3], " points ", points, " outside ", outside);
    out.push_back("");
    line(out, "probability ", model.kernel.name, " A ", real(calibration.a, 6), " B ",
         real(calibration.b, 6));
    frame(out, probabilities, p.width);
    std::string level_line = "levels";
    for (int count : levels)
        level_line += " " + std::to_string(count);
    out.push_back(level_line);
    out.push_back("");
    out.push_back("grid_agreement");
    for (int a = 0; a < int(models.size()); ++a)
        for (int b = a + 1; b < int(models.size()); ++b) {
            int agreement = 0, positive_a = 0, positive_b = 0;
            for (int cell = 0; cell < p.width * p.height; ++cell) {
                agreement += signs[a][cell] == signs[b][cell];
                positive_a += signs[a][cell] == 1;
                positive_b += signs[b][cell] == 1;
            }
            line(out, models[a].kernel.name, " ", models[b].kernel.name, " ", agreement, "/",
                 p.width * p.height, " positive ", positive_a, " ", positive_b);
        }
    out.push_back("");
    line(out, "multiclass ", p.multi_name, " C ", real(p.multi_c, 4));
    frame(out, multiclass, p.width);
    line(out, "cells class1 ", multi_count[0], " class2 ", multi_count[1], " class3 ",
         multi_count[2], " disagree ", multi_count[3], " points ", multi_points, " outside ",
         multi_outside);
    return out;
}
int main() {
    const Input input = load();
    const Params &p = input.params;
    const int n = int(input.train.size()), m = int(input.test.size());
    std::vector<Matrix> matrices;
    std::vector<CV> cv;
    Ids best(p.kernels.size());
    for (int k = 0; k < int(p.kernels.size()); ++k) {
        matrices.push_back(kernel_matrix(p.kernels[k], input.train));
        best[k] = int(cv.size());
        for (int c = 0; c < int(p.c_grid.size()); ++c) {
            cv.push_back(cross_validate(input, k, c, matrices[k]));
            if (cv.back().correct > cv[best[k]].correct)
                best[k] = int(cv.size()) - 1;
        }
    }
    int selected = 0;
    for (int k = 1; k < int(best.size()); ++k)
        if (cv[best[k]].correct > cv[best[selected]].correct ||
            (cv[best[k]].correct == cv[best[selected]].correct &&
             p.c_grid[cv[best[k]].candidate] < p.c_grid[cv[best[selected]].candidate]))
            selected = k;
    const double selected_c = p.c_grid[cv[best[selected]].candidate];
    std::vector<Model> models;
    std::vector<Metrics> evaluations;
    int linear = 0, multi_kernel = 0;
    bool found_linear = false;
    for (int k = 0; k < int(p.kernels.size()); ++k) {
        models.push_back(
            train(input.train, p.kernels[k], matrices[k], p.c_grid[cv[best[k]].candidate], p));
        evaluations.push_back(metrics(input, models.back()));
        if (!found_linear && p.kernels[k].kind == "linear") {
            linear = k;
            found_linear = true;
        }
        if (p.kernels[k].name == p.multi_name)
            multi_kernel = k;
    }
    Ids ranking(cv.size());
    std::iota(ranking.begin(), ranking.end(), 0);
    std::sort(ranking.begin(), ranking.end(), [&](int a, int b) {
        const CV &x = cv[a], &y = cv[b];
        return x.correct != y.correct ? x.correct > y.correct
               : p.c_grid[x.candidate] != p.c_grid[y.candidate]
                   ? p.c_grid[x.candidate] < p.c_grid[y.candidate]
                   : x.kernel < y.kernel;
    });
    Lines model_report_lines;
    line(model_report_lines, "cross_validation folds ", p.folds, " examples ", n);
    for (int k = 0; k < int(best.size()); ++k) {
        const CV &value = cv[best[k]];
        line(model_report_lines, "best ", p.kernels[k].name, " C ",
             real(p.c_grid[value.candidate], 4), " correct ", value.correct, "/", n, " accuracy ",
             ratio(value.correct, n));
    }
    line(model_report_lines, "selected ", p.kernels[selected].name, " C ", real(selected_c, 4));
    model_report_lines.push_back("ranking");
    for (int i = 0; i < int(ranking.size()); ++i) {
        const CV &value = cv[ranking[i]];
        line(model_report_lines, i + 1, " ", p.kernels[value.kernel].name, " C ",
             real(p.c_grid[value.candidate], 4), " correct ", value.correct, "/", n);
    }
    line(model_report_lines, "cv_detail ", p.kernels[selected].name, " C ", real(selected_c, 4));
    for (int i = 0; i < p.folds; ++i) {
        const FoldResult &f = cv[best[selected]].folds[i];
        line(model_report_lines, "fold ", i + 1, " train ", f.train, " test ", f.test, " correct ",
             f.correct, " support_vectors ", f.sv, " passes ", f.passes, " steps ", f.steps,
             " converged ", f.converged ? "yes" : "no");
    }
    for (int k = 0; k < int(models.size()); ++k) {
        model_report_lines.push_back("");
        model_report(model_report_lines, input, models[k], evaluations[k]);
    }
    const Model &model = models[selected];
    model_report_lines.push_back("");
    line(model_report_lines, "training_log ", model.kernel.name);
    for (int i = 0; i < int(model.passes.size());) {
        const Pass &pass = model.passes[i];
        if (pass.full) {
            line(model_report_lines, "pass ", i + 1, " full examined ", pass.examined, " changed ",
                 pass.changed, " dual_objective ",
                 real(objectives(pass.alpha, model.data, model.matrix).second, 6));
            ++i;
        } else {
            const int first = i;
            int examined = 0, changed = 0;
            while (i < int(model.passes.size()) && !model.passes[i].full) {
                examined += model.passes[i].examined;
                changed += model.passes[i].changed;
                ++i;
            }
            line(model_report_lines, "passes ", first + 1, "-", i, " nonbound examined ", examined,
                 " changed ", changed);
        }
    }
    model_report_lines.push_back("");
    line(model_report_lines, "c_path ", model.kernel.name);
    for (double c : p.c_grid) {
        const Model current =
            c == selected_c ? model : train(input.train, model.kernel, model.matrix, c, p);
        const Field train_values = current.training_decisions(),
                    test_values = decisions(current, input.test);
        line(model_report_lines, "C ", real(c, 4), " ", support_text(current), " dual_objective ",
             real(objectives(current.alpha, current.data, current.matrix).second, 6), " train ",
             evaluate(input.train, train_values).correct(), "/", n, " test ",
             evaluate(input.test, test_values).correct(), "/", m, " ", run_info(current));
    }
    model_report_lines.push_back("");
    line(model_report_lines, "learning_curve ", model.kernel.name, " C ", real(selected_c, 4));
    for (int q : p.learning) {
        const int size = n * q / 100;
        Ids indices(size);
        std::iota(indices.begin(), indices.end(), 0);
        const Model current = train(selected_data(input.train, indices), model.kernel,
                                    selected_matrix(model.matrix, indices), selected_c, p);
        line(model_report_lines, "size ", size, " support_vectors ", support(current).total,
             " train ", evaluate(current.data, current.training_decisions()).correct(), "/", size,
             " test ", evaluate(input.test, decisions(current, input.test)).correct(), "/", m, " ",
             run_info(current));
    }
    const Calibration calibration =
        calibrate(input, model, cv[best[selected]].decisions, evaluations[selected].test);
    model_report_lines.push_back("");
    model_report_lines.insert(model_report_lines.end(), calibration.lines.begin(),
                              calibration.lines.end());
    const Pegasos peg = pegasos(input, models[linear], evaluations[linear]);
    model_report_lines.push_back("");
    model_report_lines.insert(model_report_lines.end(), peg.lines.begin(), peg.lines.end());
    model_report_lines.push_back("");
    model_report_lines.push_back("mcnemar");
    std::vector<Field> comparison_values;
    std::vector<std::string> names;
    for (int k = 0; k < int(models.size()); ++k) {
        comparison_values.push_back(evaluations[k].test);
        names.push_back(models[k].kernel.name);
    }
    comparison_values.push_back(peg.test);
    names.push_back("pegasos");
    for (int a = 0; a < int(names.size()); ++a)
        for (int b = a + 1; b < int(names.size()); ++b) {
            int first = 0, second = 0;
            for (int i = 0; i < m; ++i) {
                const bool x = sign(comparison_values[a][i]) == input.test[i].label,
                           y = sign(comparison_values[b][i]) == input.test[i].label;
                first += x && !y;
                second += y && !x;
            }
            const int numerator = (std::abs(first - second) - 1) * (std::abs(first - second) - 1),
                      denominator = first + second;
            line(model_report_lines, names[a], " ", names[b], " only_first ", first,
                 " only_second ", second, " chi2 ",
                 denominator ? real(double(numerator) / denominator, 4) : "-");
        }
    Lines grid;
    std::string header = "kernel,C";
    for (int i = 1; i <= p.folds; ++i)
        header += ",fold" + std::to_string(i);
    header += ",correct,accuracy,support_vectors,passes,steps";
    grid.push_back(header);
    for (const CV &value : cv) {
        std::string row = p.kernels[value.kernel].name + "," + real(p.c_grid[value.candidate], 4);
        for (const FoldResult &fold : value.folds)
            row += "," + std::to_string(fold.correct);
        row += "," + std::to_string(value.correct) + "," + ratio(value.correct, n) + "," +
               std::to_string(value.sv) + "," + std::to_string(value.passes) + "," +
               std::to_string(value.steps);
        grid.push_back(row);
    }
    Lines predictions;
    header = "id,label";
    for (const Kernel &kernel : p.kernels)
        header += "," + kernel.name;
    header += ",pegasos,predicted,probability";
    predictions.push_back(header);
    for (int i = 0; i < m; ++i) {
        std::string row = input.test[i].id + "," + std::to_string(input.test[i].label);
        for (const Metrics &value : evaluations)
            row += "," + real(value.test[i], 4);
        row += "," + real(peg.test[i], 4) + "," +
               std::to_string(sign(evaluations[selected].test[i])) + "," +
               real(calibration.probabilities[i], 4);
        predictions.push_back(row);
    }
    const Multi multi = train_multi(input, p.kernels[multi_kernel]);
    save("model.txt", model_report_lines);
    save("cv_grid.csv", grid);
    save("predictions.csv", predictions);
    save("multiclass.txt", multi_report(input, multi));
    save("decision_plot.txt", plots(input, models, selected, calibration, multi));
}
