#include "regression.hpp"
template <class... T> static void line(std::ostream &out, const T &...values) {
    bool first = true;
    auto put = [&](const auto &value) {
        if (!first)
            out << ' ';
        first = false;
        out << value;
    };
    (put(values), ...);
    out << '\n';
}
static std::vector<int> sequence(int size) {
    std::vector<int> result(size);
    std::iota(result.begin(), result.end(), 0);
    return result;
}
template <class T> static std::vector<T> subset(const std::vector<T> &data, const std::vector<int> &ids) {
    std::vector<T> result;
    for (int id : ids)
        result.push_back(data[id]);
    return result;
}
static std::vector<int> score_order(const Vector &values, bool descending) {
    std::vector<int> ids = sequence(int(values.size()));
    std::stable_sort(ids.begin(), ids.end(), [&](int a, int b) {
        return descending ? values[a] > values[b] : values[a] < values[b];
    });
    return ids;
}
static Matrix inverse(const Matrix &matrix) {
    const int size = int(matrix.size());
    const Matrix lower = cholesky(matrix);
    Matrix result(size, Vector(size));
    for (int k = 0; k < size; ++k) {
        Vector basis(size);
        basis[k] = 1;
        const Vector column = solve(lower, basis);
        for (int j = 0; j < size; ++j)
            result[j][k] = column[j];
    }
    return result;
}
static int correct(const Vector &probabilities_, const std::vector<int> &targets, double threshold) {
    const Confusion c = confusion(probabilities_, targets, threshold);
    return int(c.tp + c.tn);
}
struct CrossValidation {
    Vector folds, probabilities;
    double loss = 0;
    int errors = 0;
};
struct Influence {
    Matrix covariance;
    Vector probabilities, leverage, residual, cook;
    double edf = 0, deviance = 0, aic = 0, bic = 0;
};
static Influence influence(const Vector &weights, const Matrix &data, const std::vector<int> &targets,
                           double lambda) {
    Influence fit;
    fit.covariance = inverse(hessian(weights, data, lambda));
    fit.probabilities = probabilities(weights, data);
    for (std::size_t i = 0; i < data.size(); ++i) {
        const double pi = fit.probabilities[i], v = pi * (1 - pi);
        double q = 0;
        for (std::size_t j = 0; j < weights.size(); ++j)
            for (std::size_t k = 0; k < weights.size(); ++k)
                q += data[i][j] * fit.covariance[j][k] * data[i][k];
        const double h = v * q / double(data.size()), e = (targets[i] - pi) / std::sqrt(v),
                     t = e / std::sqrt(1 - h),
                     cook = e * e * h / (double(weights.size()) * ((1 - h) * (1 - h)));
        fit.leverage.push_back(h);
        fit.residual.push_back(t);
        fit.cook.push_back(cook);
        fit.edf += h;
    }
    fit.deviance = 2 * double(data.size()) * average_loss(weights, data, targets);
    fit.aic = fit.deviance + 2 * fit.edf;
    fit.bic = fit.deviance + std::log(double(data.size())) * fit.edf;
    return fit;
}
struct Model {
    std::string name;
    std::vector<Checkpoint> checkpoints;
    Vector weights, train_probabilities, test_probabilities;
};
struct Calibration {
    int counts[10] = {}, hits[10] = {};
    double sums[10] = {}, ece = 0, mce = 0, hl = 0;
    int groups = 0;
};
static Calibration calibration(const Vector &probabilities_, const std::vector<int> &targets) {
    Calibration table;
    for (std::size_t i = 0; i < targets.size(); ++i) {
        const int bin = std::min(9, int(std::floor(probabilities_[i] * 10)));
        ++table.counts[bin];
        table.hits[bin] += targets[i];
        table.sums[bin] += probabilities_[i];
    }
    for (int bin = 0; bin < 10; ++bin)
        if (table.counts[bin]) {
            ++table.groups;
            const double sum = table.sums[bin], count = table.counts[bin], observed = table.hits[bin];
            table.ece += std::abs(sum - observed);
            table.mce = std::max(table.mce, std::abs(sum / count - observed / count));
            table.hl += (observed - sum) * (observed - sum) / (sum * (1 - sum / count));
        }
    table.ece /= double(targets.size());
    return table;
}
static std::string bin_range(int bin) {
    return "0." + std::to_string(bin) + "-" + (bin == 9 ? "1.0" : "0." + std::to_string(bin + 1));
}
class Study {
    Table train = read_table("train.csv"), test = read_table("test.csv");
    Params p = read_params();
    std::vector<Feature> terms = features(train.names, p.degree);
    int n = int(train.rows.size()), m = int(test.rows.size()), q = int(terms.size()), classes = 0;
    Matrix train_expanded = expanded(train.rows, terms), test_expanded = expanded(test.rows, terms);
    Statistics stats = statistics(train_expanded, q);
    Matrix x = standardize(train_expanded, stats, q), z = standardize(test_expanded, stats, q);
    std::vector<int> y = labels(train.rows, p.positive), yt = labels(test.rows, p.positive),
                     class_train = labels(train.rows, -1), class_test = labels(test.rows, -1);
    std::vector<CrossValidation> validations;
    int selected = 0, one_se = 0;
    double se = 0, lambda = 0;
    std::vector<Model> models;
    std::vector<SoftCheckpoint> soft_checkpoints;
    Matrix soft_weights, soft_probabilities;
    std::vector<int> soft_predictions;
    int soft_correct = 0;
    Influence fit;
    CrossValidation cross_validate(double coefficient, int count) const {
        CrossValidation result;
        result.probabilities.resize(n);
        Vector losses(n);
        for (int fold = 0; fold < 5; ++fold) {
            std::vector<int> training, validation;
            for (int i = 0; i < n; ++i)
                (i % 5 == fold ? validation : training).push_back(i);
            const Matrix raw = subset(train_expanded, training);
            const Statistics fold_stats = statistics(raw, count);
            const Matrix tx = standardize(raw, fold_stats, count),
                         vx = standardize(subset(train_expanded, validation), fold_stats, count);
            const std::vector<int> targets = subset(y, training);
            const Vector weights = newton(tx, targets, coefficient).back().weights;
            double total = 0;
            for (std::size_t j = 0; j < validation.size(); ++j) {
                const int id = validation[j];
                const double u = score(weights, vx[j]);
                losses[id] = logistic_loss(u, y[id]);
                result.probabilities[id] = sigmoid(u);
                total += losses[id];
                if (int(result.probabilities[id] >= p.threshold) != y[id])
                    ++result.errors;
            }
            result.folds.push_back(total / double(validation.size()));
        }
        double total = 0;
        for (double loss : losses)
            total += loss;
        result.loss = total / double(n);
        return result;
    }
    Vector original(const Vector &weights) const {
        Vector values(weights.size());
        double total = 0;
        for (std::size_t j = 1; j < weights.size(); ++j) {
            values[j] = weights[j] / stats.deviation[j - 1];
            total += values[j] * stats.mean[j - 1];
        }
        values[0] = weights[0] - total;
        return values;
    }
    void write_terms(std::ostream &out, const Vector &weights) const {
        const Vector units = original(weights);
        for (std::size_t j = 0; j < weights.size(); ++j)
            line(out, "term", j ? terms[j - 1].name : "intercept", "standardized", real(weights[j]),
                 "original", real(units[j]));
    }
    void write_weights() const {
        std::ofstream out("output/weights.txt");
        line(out, "features", train.names.size(), "degree", p.degree, "expanded", q);
        line(out, "standardization");
        Matrix correlation(q, Vector(q));
        for (int j = 0; j < q; ++j)
            for (int k = 0; k < q; ++k) {
                double total = 0;
                for (const Vector &row : x)
                    total += row[j + 1] * row[k + 1];
                correlation[j][k] = total / double(n - 1);
            }
        const Matrix vif = inverse(correlation);
        for (int j = 0; j < q; ++j)
            line(out, terms[j].name, "mean", real(stats.mean[j], 6), "sd", real(stats.deviation[j], 6), "vif",
                 real(vif[j][j]));
        line(out, "correlation");
        for (const Vector &row : correlation) {
            for (int k = 0; k < q; ++k) {
                if (k)
                    out << ' ';
                out << real(row[k]);
            }
            out << '\n';
        }
        for (const Model &model : models) {
            out << '\n';
            line(out, "model", model.name, "lambda", real(lambda));
            write_terms(out, model.weights);
            line(out, "norm", real(length(Vector(model.weights.begin() + 1, model.weights.end()))));
            if (model.name != "newton") {
                Vector delta;
                for (int j = 0; j <= q; ++j)
                    delta.push_back(model.weights[j] - models[2].weights[j]);
                line(out, "distance_to_newton", real(length(delta), 6));
            }
        }
        out << '\n';
        line(out, "coefficients newton lambda", real(lambda));
        const Vector &weights = models[2].weights;
        for (int j = 0; j <= q; ++j) {
            const double standard_error = std::sqrt(fit.covariance[j][j] / double(n));
            line(out, j ? terms[j - 1].name : "intercept", "weight", real(weights[j]), "se",
                 real(standard_error), "z", real(weights[j] / standard_error), "lower",
                 real(weights[j] - 1.96 * standard_error), "upper", real(weights[j] + 1.96 * standard_error),
                 "odds_ratio", real(std::exp(weights[j])));
        }
        out << '\n';
        line(out, "model softmax lambda", real(p.softmax_lambda));
        for (int k = 0; k < classes; ++k) {
            line(out, "class", k);
            write_terms(out, soft_weights[k]);
        }
    }
    void write_traces_predictions() const {
        std::ofstream trace("output/loss_trace.csv");
        trace << "optimizer,iteration,loss,gradient_norm,test_loss\n";
        for (const Model &model : models)
            for (const Checkpoint &checkpoint : model.checkpoints)
                trace << model.name << ',' << checkpoint.iteration << ','
                      << real(objective(checkpoint.weights, x, y, lambda), 6) << ','
                      << real(length(gradient(checkpoint.weights, x, y, lambda)), 6) << ','
                      << real(average_loss(checkpoint.weights, z, yt), 6) << '\n';
        for (const SoftCheckpoint &checkpoint : soft_checkpoints) {
            const Matrix g = soft_gradient(checkpoint.weights, x, class_train, p.softmax_lambda);
            Vector flattened;
            for (const Vector &row : g)
                flattened.insert(flattened.end(), row.begin(), row.end());
            trace << "softmax," << checkpoint.iteration << ','
                  << real(soft_objective(checkpoint.weights, x, class_train, p.softmax_lambda), 6) << ','
                  << real(length(flattened), 6) << ','
                  << real(soft_loss(checkpoint.weights, z, class_test), 6) << '\n';
        }
        std::ofstream predictions("output/predictions.csv");
        predictions << "id,model,probability,predicted,actual\n";
        for (const Model &model : models)
            for (int i = 0; i < m; ++i)
                predictions << test.rows[i].id << ',' << model.name << ','
                            << real(model.test_probabilities[i], 6) << ','
                            << int(model.test_probabilities[i] >= p.threshold) << ',' << yt[i] << '\n';
        for (int i = 0; i < m; ++i)
            predictions << test.rows[i].id << ",softmax,"
                        << real(soft_probabilities[i][soft_predictions[i]], 6) << ',' << soft_predictions[i]
                        << ',' << class_test[i] << '\n';
    }
    void write_binary(std::ostream &out, std::ostream &roc_file, const Model &model) const {
        const Vector &probabilities_ = model.test_probabilities;
        const Confusion c = confusion(probabilities_, yt, p.threshold);
        const Integer pos = c.tp + c.fn, neg = c.fp + c.tn;
        line(out, "model", model.name, "lambda", real(lambda));
        const int train_correct = correct(model.train_probabilities, y, p.threshold);
        line(out, "train correct", std::to_string(train_correct) + "/" + std::to_string(n), "accuracy",
             ratio(train_correct, n));
        line(out, "test tp", c.tp, "fp", c.fp, "tn", c.tn, "fn", c.fn);
        line(out, "test accuracy", ratio(c.tp + c.tn, m), "precision", ratio(c.tp, c.tp + c.fp), "recall",
             ratio(c.tp, pos), "specificity", ratio(c.tn, neg), "f1",
             ratio(2 * c.tp, 2 * c.tp + c.fp + c.fn));
        double brier = 0;
        for (int i = 0; i < m; ++i) {
            const double delta = probabilities_[i] - yt[i];
            brier += delta * delta;
        }
        line(out, "log_loss", real(average_loss(model.weights, z, yt), 6), "brier",
             real(brier / double(m), 6));
        const std::vector<RocPoint> points = roc(probabilities_, yt);
        double ap = 0;
        Integer prior = 0;
        int youden = 0, f1 = 0, cost = 0;
        for (std::size_t i = 0; i < points.size(); ++i) {
            const RocPoint &r = points[i];
            ap += double((r.tp - prior) * r.tp) / double(r.tp + r.fp);
            prior = r.tp;
            const RocPoint &a = points[youden];
            if (r.tp * neg - r.fp * pos > a.tp * neg - a.fp * pos)
                youden = int(i);
            const RocPoint &b = points[f1];
            if (r.tp * (pos + b.tp + b.fp) > b.tp * (pos + r.tp + r.fp))
                f1 = int(i);
            const RocPoint &d = points[cost];
            if (p.fp_cost * r.fp + p.fn_cost * (pos - r.tp) < p.fp_cost * d.fp + p.fn_cost * (pos - d.tp))
                cost = int(i);
        }
        ap /= double(pos);
        line(out, "auc", auc(probabilities_, yt).text(), "average_precision", real(ap));
        const RocPoint &a = points[youden];
        line(out, "youden threshold", real(a.threshold, 6), "tpr", ratio(a.tp, pos), "fpr", ratio(a.fp, neg),
             "j", ratio(a.tp * neg - a.fp * pos, pos * neg));
        const RocPoint &b = points[f1];
        line(out, "best_f1 threshold", real(b.threshold, 6), "precision", ratio(b.tp, b.tp + b.fp), "recall",
             ratio(b.tp, pos), "f1", ratio(2 * b.tp, pos + b.tp + b.fp));
        const RocPoint &d = points[cost];
        line(out, "min_cost threshold", real(d.threshold, 6), "cost",
             p.fp_cost * d.fp + p.fn_cost * (pos - d.tp), "fp", d.fp, "fn", pos - d.tp);
        const Calibration table = calibration(probabilities_, yt);
        line(out, "calibration");
        for (int bin = 0; bin < 10; ++bin)
            line(out, "bin", bin_range(bin), "count", table.counts[bin], "mean_probability",
                 table.counts[bin] ? real(table.sums[bin] / double(table.counts[bin])) : "-", "positive_rate",
                 ratio(table.hits[bin], table.counts[bin]));
        line(out, "ece", real(table.ece), "mce", real(table.mce), "hosmer_lemeshow", real(table.hl), "groups",
             table.groups);
        line(out, "gains");
        const std::vector<int> order = score_order(probabilities_, true);
        for (int decile = 1; decile <= 10; ++decile) {
            const int size = decile * m / 10;
            int hits = 0;
            for (int i = 0; i < size; ++i)
                hits += yt[order[i]];
            line(out, "decile", decile, "rows", size, "positives", hits, "gain", ratio(hits, pos), "lift",
                 ratio(Integer(hits) * m, Integer(size) * pos));
        }
        roc_file << model.name << ",inf,0.0000,0.0000,-\n";
        for (const RocPoint &r : points)
            roc_file << model.name << ',' << real(r.threshold, 6) << ',' << ratio(r.tp, pos) << ','
                     << ratio(r.fp, neg) << ',' << ratio(r.tp, r.tp + r.fp) << '\n';
    }
    double slope(const Vector &units, int feature, const Vector &values) const {
        double total = 0;
        for (int j = 0; j < q; ++j) {
            int count = 0;
            bool removed = false;
            double product = 1;
            for (int index : terms[j].indices) {
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
                total += units[j + 1] * (double(count) * product);
        }
        return total;
    }
    void diagnostics(std::ostream &out) const {
        const Model &model = models[2];
        const Vector &probability = model.test_probabilities;
        const double pi_bar = double(std::accumulate(y.begin(), y.end(), 0)) / double(n),
                     null_loss = -(pi_bar * std::log(pi_bar) + (1 - pi_bar) * std::log(1 - pi_bar)),
                     loss = average_loss(model.weights, x, y);
        line(out, "diagnostics newton lambda", real(lambda));
        line(out, "fit null_loss", real(null_loss, 6), "train_loss", real(loss, 6), "mcfadden_r2",
             real(1 - loss / null_loss), "deviance", real(fit.deviance), "edf", real(fit.edf), "aic",
             real(fit.aic), "bic", real(fit.bic));
        const std::vector<int> order = score_order(fit.probabilities, false);
        Vector expectations;
        std::vector<int> counts, observed;
        double hl = 0;
        for (int group = 1; group <= 10; ++group) {
            const int first = (group - 1) * n / 10, end = group * n / 10;
            double expected = 0;
            int hits = 0;
            for (int i = first; i < end; ++i) {
                expected += fit.probabilities[order[i]];
                hits += y[order[i]];
            }
            const int count = end - first;
            hl += (hits - expected) * (hits - expected) / (expected * (1 - expected / double(count)));
            expectations.push_back(expected);
            counts.push_back(count);
            observed.push_back(hits);
        }
        line(out, "hosmer_lemeshow_train groups 10 statistic", real(hl));
        for (int group = 0; group < 10; ++group)
            line(out, "group", group + 1, "rows", counts[group], "observed", observed[group], "expected",
                 real(expectations[group]));
        line(out, "newton_iterations");
        for (int iteration = 1; iteration <= 10; ++iteration) {
            const Vector &weights = model.checkpoints[iteration - 1].weights;
            const Vector g = gradient(weights, x, y, lambda),
                         delta = solve(cholesky(hessian(weights, x, lambda)), g);
            double product = 0;
            for (int j = 0; j <= q; ++j)
                product += g[j] * delta[j];
            line(out, "iteration", iteration, "objective", real(objective(weights, x, y, lambda), 6),
                 "gradient_norm", real(length(g), 6), "step_norm", real(length(delta), 6),
                 "predicted_decrease", real(product / 2, 6));
        }
        const Vector units = original(model.weights),
                     base_mean(stats.mean.begin(), stats.mean.begin() + int(train.names.size()));
        const double center =
            sigmoid(score(model.weights, standardize_point(expand(base_mean, terms), stats, q)));
        for (int feature = 0; feature < int(train.names.size()); ++feature) {
            double total = 0;
            for (int i = 0; i < n; ++i)
                total += fit.probabilities[i] * (1 - fit.probabilities[i]) *
                         slope(units, feature, train.rows[i].values);
            line(out, "marginal", train.names[feature], "average", real(total / double(n)), "at_mean",
                 real(center * (1 - center) * slope(units, feature, base_mean)));
        }
        for (int k = 1; k <= 9; ++k) {
            const Confusion c = confusion(probability, yt, double(k) / 10);
            line(out, "cut", "0." + std::to_string(k), "positive", c.tp + c.fp, "tp", c.tp, "fp", c.fp,
                 "precision", ratio(c.tp, c.tp + c.fp), "recall", ratio(c.tp, c.tp + c.fn), "accuracy",
                 ratio(c.tp + c.tn, m));
        }
        Vector distances;
        for (double value : probability)
            distances.push_back(std::abs(value - p.threshold));
        int written = 0;
        for (int id : score_order(distances, true))
            if (int(probability[id] >= p.threshold) != yt[id]) {
                line(out, "error", test.rows[id].id, "actual", yt[id], "probability",
                     real(probability[id], 6));
                if (++written == 5)
                    break;
            }
        Minstd random(p.bootstrap_seed);
        std::vector<Fraction> fractions;
        Vector values;
        for (int replicate = 0; replicate < p.bootstrap; ++replicate) {
            Vector sample;
            std::vector<int> targets;
            for (int i = 0; i < m; ++i) {
                const int id = int(random.draw() % m);
                sample.push_back(probability[id]);
                targets.push_back(yt[id]);
            }
            const Fraction a = auc(sample, targets);
            fractions.push_back(a);
            values.push_back(a.value());
        }
        double mean = 0;
        for (double value : values)
            mean += value;
        mean /= double(values.size());
        double squares = 0;
        for (double value : values)
            squares += (value - mean) * (value - mean);
        std::stable_sort(fractions.begin(), fractions.end(), [](Fraction a, Fraction b) {
            return a.numerator * b.denominator < b.numerator * a.denominator;
        });
        line(out, "bootstrap resamples", p.bootstrap, "seed", p.bootstrap_seed, "auc_mean", real(mean),
             "auc_sd", real(std::sqrt(squares / double(p.bootstrap - 1))), "lower",
             fractions[p.bootstrap / 40].text(), "upper",
             fractions[p.bootstrap - p.bootstrap / 40 - 1].text());
        int large = 0;
        for (double residual : fit.residual)
            if (std::abs(residual) > 2)
                ++large;
        line(out, "influence effective_parameters", real(fit.edf), "large_residuals", large);
        written = 0;
        for (int id : score_order(fit.cook, true)) {
            line(out, "cook", train.rows[id].id, "actual", y[id], "probability", real(fit.probabilities[id]),
                 "leverage", real(fit.leverage[id]), "residual", real(fit.residual[id]), "distance",
                 real(fit.cook[id]));
            if (++written == 5)
                break;
        }
    }
    void importance_profiles(std::ostream &out) const {
        const Model &model = models[2];
        const double baseline_loss = average_loss(model.weights, z, yt);
        const Fraction baseline_auc = auc(model.test_probabilities, yt);
        line(out, "importance repeats", p.permutations, "seed", p.permutation_seed);
        line(out, "baseline log_loss", real(baseline_loss, 6), "auc", baseline_auc.text(), "softmax_accuracy",
             ratio(soft_correct, m));
        Minstd random(p.permutation_seed);
        for (int feature = 0; feature < int(train.names.size()); ++feature) {
            double total_loss = 0;
            Integer total_auc = 0, total_correct = 0;
            for (int repeat = 0; repeat < p.permutations; ++repeat) {
                std::vector<int> order = sequence(m);
                random.shuffle(order);
                std::vector<Row> rows = test.rows;
                for (int i = 0; i < m; ++i)
                    rows[i].values[feature] = test.rows[order[i]].values[feature];
                const Matrix data = standardize(expanded(rows, terms), stats, q);
                total_loss += average_loss(model.weights, data, yt);
                total_auc += auc(probabilities(model.weights, data), yt).numerator;
                for (int i = 0; i < m; ++i)
                    if (soft_point(soft_weights, data[i], class_test[i]).predicted == class_test[i])
                        ++total_correct;
            }
            line(out, "feature", train.names[feature], "log_loss_increase",
                 real(total_loss / double(p.permutations) - baseline_loss, 6), "auc",
                 Fraction{total_auc, Integer(p.permutations) * baseline_auc.denominator}.text(),
                 "softmax_accuracy", ratio(total_correct, Integer(p.permutations) * m));
        }
        out << '\n';
        line(out, "profiles");
        const Vector mean(stats.mean.begin(), stats.mean.begin() + int(train.names.size()));
        for (int feature = 0; feature < int(train.names.size()); ++feature) {
            double lo = train.rows[0].values[feature], hi = lo;
            for (const Row &row : train.rows) {
                lo = std::min(lo, row.values[feature]);
                hi = std::max(hi, row.values[feature]);
            }
            for (int point = 0; point < 5; ++point) {
                Vector values = mean;
                values[feature] = lo + (hi - lo) * point / 4;
                const Vector vector = standardize_point(expand(values, terms), stats, q);
                const SoftPoint soft = soft_point(soft_weights, vector, 0);
                out << "profile " << train.names[feature] << " value " << real(values[feature]) << " newton "
                    << real(sigmoid(score(model.weights, vector))) << " softmax";
                for (double probability : soft.probabilities)
                    out << ' ' << real(probability);
                out << '\n';
            }
        }
    }
    void multiclass(std::ostream &out) const {
        line(out, "softmax classes", classes, "lambda", real(p.softmax_lambda), "iterations",
             p.softmax_iterations);
        line(out, "confusion");
        std::vector<std::vector<Integer>> table(classes, std::vector<Integer>(classes));
        for (int i = 0; i < m; ++i)
            ++table[class_test[i]][soft_predictions[i]];
        std::vector<Integer> rows(classes), columns(classes);
        Integer diagonal = 0;
        for (int k = 0; k < classes; ++k) {
            for (int j = 0; j < classes; ++j) {
                if (j)
                    out << ' ';
                out << table[k][j];
                rows[k] += table[k][j];
                columns[j] += table[k][j];
            }
            out << '\n';
            diagonal += table[k][k];
        }
        for (int k = 0; k < classes; ++k) {
            Vector scores;
            std::vector<int> targets;
            for (int i = 0; i < m; ++i) {
                scores.push_back(soft_probabilities[i][k]);
                targets.push_back(int(class_test[i] == k));
            }
            line(out, "class", k, "precision", ratio(table[k][k], columns[k]), "recall",
                 ratio(table[k][k], rows[k]), "f1", ratio(2 * table[k][k], columns[k] + rows[k]), "auc",
                 auc(scores, targets).text());
        }
        Integer chance = 0;
        for (int k = 0; k < classes; ++k)
            chance += rows[k] * columns[k];
        line(out, "accuracy", ratio(diagonal, m), "kappa",
             ratio(Integer(m) * diagonal - chance, Integer(m) * m - chance));
        double brier = 0;
        for (int i = 0; i < m; ++i) {
            double total = 0;
            for (int k = 0; k < classes; ++k) {
                const double delta = soft_probabilities[i][k] - int(class_test[i] == k);
                total += delta * delta;
            }
            brier += total;
        }
        line(out, "log_loss", real(soft_loss(soft_weights, z, class_test), 6), "brier",
             real(brier / double(m), 6));
        Vector scores, confidence;
        std::vector<int> hits;
        double binary_loss = 0;
        Integer agreement = 0;
        for (int i = 0; i < m; ++i) {
            const double probability = soft_probabilities[i][p.positive];
            scores.push_back(probability);
            binary_loss += -std::log(yt[i] ? probability : 1 - probability);
            if ((probability >= p.threshold) == (models[2].test_probabilities[i] >= p.threshold))
                ++agreement;
            confidence.push_back(soft_probabilities[i][soft_predictions[i]]);
            hits.push_back(int(soft_predictions[i] == class_test[i]));
        }
        line(out, "binary_view positive_class", p.positive, "auc", auc(scores, yt).text(), "log_loss",
             real(binary_loss / double(m), 6), "accuracy", ratio(correct(scores, yt, p.threshold), m),
             "agreement_with_newton", std::to_string(agreement) + "/" + std::to_string(m));
        line(out, "confidence");
        const Calibration bins = calibration(confidence, hits);
        for (int bin = 0; bin < 10; ++bin)
            line(out, "bin", bin_range(bin), "count", bins.counts[bin], "mean_confidence",
                 bins.counts[bin] ? real(bins.sums[bin] / double(bins.counts[bin])) : "-", "accuracy",
                 ratio(bins.hits[bin], bins.counts[bin]));
        line(out, "ece", real(bins.ece));
        out << '\n';
        line(out, "one_vs_rest lambda", real(p.softmax_lambda), "newton_iterations 10");
        Matrix ovr_probabilities;
        for (int k = 0; k < classes; ++k) {
            const std::vector<int> train_targets = labels(train.rows, k), test_targets = labels(test.rows, k);
            const Vector weights = newton(x, train_targets, p.softmax_lambda).back().weights;
            const Vector values = probabilities(weights, z);
            ovr_probabilities.push_back(values);
            line(out, "class", k, "objective",
                 real(objective(weights, x, train_targets, p.softmax_lambda), 6), "auc",
                 auc(values, test_targets).text());
        }
        Integer hits_count = 0, same = 0;
        for (int i = 0; i < m; ++i) {
            int predicted = 0;
            for (int k = 1; k < classes; ++k)
                if (ovr_probabilities[k][i] > ovr_probabilities[predicted][i])
                    predicted = k;
            if (predicted == class_test[i])
                ++hits_count;
            if (predicted == soft_predictions[i])
                ++same;
        }
        line(out, "accuracy", ratio(hits_count, m), "agreement_with_softmax",
             std::to_string(same) + "/" + std::to_string(m));
    }
    void maps(std::ostream &out) const {
        line(out, "map", train.names[0], train.names[1], "width", p.width, "height", p.height);
        line(out, "softmax_classes");
        Vector lo = train.rows[0].values, hi = lo;
        for (const Row &row : train.rows)
            for (std::size_t j = 0; j < lo.size(); ++j) {
                lo[j] = std::min(lo[j], row.values[j]);
                hi[j] = std::max(hi[j], row.values[j]);
            }
        std::vector<Integer> cells(classes);
        std::vector<std::string> probability_map;
        const Vector mean(stats.mean.begin(), stats.mean.begin() + int(train.names.size()));
        for (int r = 0; r < p.height; ++r) {
            std::string classes_line, probability_line;
            for (int c = 0; c < p.width; ++c) {
                Vector values = mean;
                values[0] = lo[0] + (c + 0.5) * (hi[0] - lo[0]) / p.width;
                values[1] = hi[1] - (r + 0.5) * (hi[1] - lo[1]) / p.height;
                const Vector vector = standardize_point(expand(values, terms), stats, q);
                const int predicted = soft_point(soft_weights, vector, 0).predicted;
                classes_line += char('0' + predicted);
                ++cells[predicted];
                probability_line +=
                    char('0' + std::min(9, int(std::floor(sigmoid(score(models[2].weights, vector)) * 10))));
            }
            line(out, classes_line);
            probability_map.push_back(probability_line);
        }
        out << "cells";
        for (Integer count : cells)
            out << ' ' << count;
        out << '\n';
        line(out, "newton_probability");
        for (const std::string &row : probability_map)
            line(out, row);
    }
    void write_evaluation() const {
        std::ofstream out("output/evaluation.txt"), roc_file("output/roc.csv");
        roc_file << "model,threshold,tpr,fpr,precision\n";
        line(out, "data train", n, "test", m, "base_features", train.names.size(), "degree", p.degree,
             "features", q);
        line(out, "binary positive_class", p.positive, "train",
             std::to_string(std::accumulate(y.begin(), y.end(), 0)) + "/" + std::to_string(n), "test",
             std::to_string(std::accumulate(yt.begin(), yt.end(), 0)) + "/" + std::to_string(m));
        out << "classes " << classes << " train";
        for (int k = 0; k < classes; ++k)
            out << ' ' << std::count(class_train.begin(), class_train.end(), k);
        out << " test";
        for (int k = 0; k < classes; ++k)
            out << ' ' << std::count(class_test.begin(), class_test.end(), k);
        out << "\n\n";
        line(out, "cross_validation folds 5 newton_iterations 10");
        for (std::size_t i = 0; i < p.lambdas.size(); ++i) {
            const CrossValidation &cv = validations[i];
            out << "lambda " << real(p.lambdas[i]) << " fold_loss";
            for (double loss : cv.folds)
                out << ' ' << real(loss, 6);
            out << " cv_loss " << real(cv.loss, 6) << " errors " << cv.errors << '/' << n << '\n';
        }
        line(out, "selected lambda", real(lambda), "cv_loss", real(validations[selected].loss, 6), "se",
             real(se, 6), "lambda_1se", real(p.lambdas[one_se]));
        const Confusion validation = confusion(validations[selected].probabilities, y, p.threshold);
        line(out, "out_of_fold tp", validation.tp, "fp", validation.fp, "tn", validation.tn, "fn",
             validation.fn, "accuracy", ratio(validation.tp + validation.tn, n), "auc",
             auc(validations[selected].probabilities, y).text());
        out << '\n';
        line(out, "lambda_path");
        for (double coefficient : p.lambdas) {
            const Vector weights = newton(x, y, coefficient).back().weights;
            line(out, "lambda", real(coefficient), "objective",
                 real(objective(weights, x, y, coefficient), 6), "train_loss",
                 real(average_loss(weights, x, y), 6), "test_loss", real(average_loss(weights, z, yt), 6),
                 "train_accuracy", ratio(correct(probabilities(weights, x), y, p.threshold), n),
                 "test_accuracy", ratio(correct(probabilities(weights, z), yt, p.threshold), m), "norm",
                 real(length(Vector(weights.begin() + 1, weights.end()))));
        }
        out << '\n';
        line(out, "degrees lambda", real(lambda));
        for (int degree = 1; degree <= p.degree; ++degree) {
            int count = 0;
            for (const Feature &term : terms)
                if (term.indices.size() <= std::size_t(degree))
                    ++count;
            const Matrix tx = standardize(train_expanded, stats, count),
                         vx = standardize(test_expanded, stats, count);
            const Vector weights = newton(tx, y, lambda).back().weights;
            const Influence measures = influence(weights, tx, y, lambda);
            const Vector probabilities_ = probabilities(weights, vx);
            line(out, "degree", degree, "features", count, "cv_loss",
                 real(cross_validate(lambda, count).loss, 6), "train_loss",
                 real(average_loss(weights, tx, y), 6), "test_loss", real(average_loss(weights, vx, yt), 6),
                 "test_accuracy", ratio(correct(probabilities_, yt, p.threshold), m), "auc",
                 auc(probabilities_, yt).text(), "edf", real(measures.edf), "aic", real(measures.aic), "bic",
                 real(measures.bic));
        }
        out << '\n';
        line(out, "learning_curve lambda", real(lambda));
        for (int k = 1; k <= 4; ++k) {
            const int size = k * n / 4;
            const Matrix raw(train_expanded.begin(), train_expanded.begin() + size);
            const Statistics local = statistics(raw, q);
            const Matrix tx = standardize(raw, local, q), vx = standardize(test_expanded, local, q);
            const std::vector<int> targets(y.begin(), y.begin() + size);
            const Vector weights = newton(tx, targets, lambda).back().weights,
                         probabilities_ = probabilities(weights, vx);
            line(out, "size", size, "train_loss", real(average_loss(weights, tx, targets), 6), "test_loss",
                 real(average_loss(weights, vx, yt), 6), "test_accuracy",
                 ratio(correct(probabilities_, yt, p.threshold), m), "auc", auc(probabilities_, yt).text());
        }
        for (const Model &model : models) {
            out << '\n';
            write_binary(out, roc_file, model);
        }
        out << '\n';
        for (const auto pair : std::vector<std::pair<int, int>>{{0, 1}, {0, 2}, {1, 2}}) {
            Integer same = 0, first = 0, second = 0;
            for (int i = 0; i < m; ++i) {
                const int a = int(models[pair.first].test_probabilities[i] >= p.threshold),
                          b = int(models[pair.second].test_probabilities[i] >= p.threshold);
                if (a == b)
                    ++same;
                if (a == yt[i] && b != yt[i])
                    ++first;
                if (b == yt[i] && a != yt[i])
                    ++second;
            }
            const Integer delta = std::abs(first - second) - 1;
            line(out, "agreement", models[pair.first].name, models[pair.second].name, "same",
                 std::to_string(same) + "/" + std::to_string(m), "only_first", first, "only_second", second,
                 "mcnemar", ratio(delta * delta, first + second));
        }
        out << '\n';
        diagnostics(out);
        out << '\n';
        importance_profiles(out);
        out << '\n';
        multiclass(out);
        out << '\n';
        maps(out);
    }

  public:
    void run() {
        for (int label : class_train)
            classes = std::max(classes, label + 1);
        for (double coefficient : p.lambdas)
            validations.push_back(cross_validate(coefficient, q));
        for (std::size_t i = 1; i < validations.size(); ++i)
            if (validations[i].loss <= validations[selected].loss)
                selected = int(i);
        lambda = p.lambdas[selected];
        double mean = 0;
        for (double value : validations[selected].folds)
            mean += value;
        mean /= 5;
        double squares = 0;
        for (double value : validations[selected].folds)
            squares += (value - mean) * (value - mean);
        se = std::sqrt(squares / 4) / std::sqrt(5.0);
        for (std::size_t i = 0; i < validations.size(); ++i)
            if (validations[i].loss <= validations[selected].loss + se)
                one_se = int(i);
        models.push_back({"gd", gradient_descent(x, y, lambda, p.gd_rate, p.gd_iterations)});
        models.push_back({"sgd", stochastic(x, y, lambda, p)});
        models.push_back({"newton", newton(x, y, lambda)});
        for (Model &model : models) {
            model.weights = model.checkpoints.back().weights;
            model.train_probabilities = probabilities(model.weights, x);
            model.test_probabilities = probabilities(model.weights, z);
        }
        fit = influence(models[2].weights, x, y, lambda);
        soft_checkpoints = train_softmax(x, class_train, classes, p);
        soft_weights = soft_checkpoints.back().weights;
        for (int i = 0; i < m; ++i) {
            const SoftPoint point = soft_point(soft_weights, z[i], class_test[i]);
            soft_probabilities.push_back(point.probabilities);
            soft_predictions.push_back(point.predicted);
            if (point.predicted == class_test[i])
                ++soft_correct;
        }
        write_weights();
        write_traces_predictions();
        write_evaluation();
    }
};
int main() {
    Study study;
    study.run();
}
