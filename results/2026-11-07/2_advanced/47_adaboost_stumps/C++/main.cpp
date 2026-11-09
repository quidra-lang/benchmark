#include "boosting.hpp"
#include <filesystem>
static Vector scores(const Model &model, const Rows &rows, int count = -1) {
    if (count < 0)
        count = model.rounds.size();
    count = std::min(count, int(model.rounds.size()));
    Vector out(rows.size());
    for (std::size_t i = 0; i < rows.size(); ++i)
        for (int t = 0; t < count; ++t)
            out[i] += model.rounds[t].stump.output(rows[i].values);
    return out;
}
static double magnitude(const Round &round, const std::string &variant) {
    if (variant == "samme")
        return round.alpha;
    double out = 0;
    for (double value : round.stump.values)
        out = std::max(out, std::abs(value));
    return out;
}
static double scale(const Model &model, int count = -1) {
    if (count < 0)
        count = model.rounds.size();
    double out = 0;
    for (int t = 0; t < count; ++t)
        out += magnitude(model.rounds[t], model.variant);
    return out;
}
static int error_count(const Rows &rows, const Vector &values) {
    int out = 0;
    for (std::size_t i = 0; i < rows.size(); ++i)
        out += prediction(values[i]) != rows[i].label;
    return out;
}
static double loss(const Rows &rows, const Vector &values, const std::string &variant) {
    double out = 0;
    for (std::size_t i = 0; i < rows.size(); ++i)
        out += variant == "logit" ? std::log(1 + std::exp(-2 * rows[i].label * values[i]))
                                  : std::exp(-rows[i].label * values[i]);
    return out / rows.size();
}
static void metrics(std::ostream &out, const std::string &kind, const std::string &variant, int rounds,
                    const Rows &rows, const Vector &values) {
    int tp = 0, fp = 0, tn = 0, fn = 0;
    for (std::size_t i = 0; i < rows.size(); ++i) {
        const bool yes = prediction(values[i]) == 1;
        if (rows[i].label == 1) {
            tp += yes;
            fn += !yes;
        } else {
            fp += yes;
            tn += !yes;
        }
    }
    const auto area = auc(rows, values);
    out << kind << ' ' << variant << " rounds " << rounds << " correct " << tp + tn << '/' << rows.size()
        << " accuracy " << ratio(tp + tn, rows.size()) << " tp " << tp << " fp " << fp << " tn " << tn
        << " fn " << fn << " precision " << ratio(tp, tp + fp) << " recall " << ratio(tp, tp + fn) << " f1 "
        << ratio(2 * tp, 2 * tp + fp + fn) << " auc " << ratio(area.first, area.second) << " loss "
        << real(loss(rows, values, variant)) << '\n';
}
static Ints ordered(const Vector &values, bool decreasing) {
    Ints out(values.size());
    std::iota(out.begin(), out.end(), 0);
    std::stable_sort(out.begin(), out.end(), [&](int a, int b) {
        return decreasing ? values[a] > values[b] : values[a] < values[b];
    });
    return out;
}
struct Importance {
    Vector value;
    Ints count, order;
};
static Importance importance(const Model &model, int features) {
    Importance out;
    out.value.resize(features);
    out.count.resize(features);
    for (const Round &round : model.rounds) {
        out.value[round.stump.feature] += magnitude(round, model.variant);
        ++out.count[round.stump.feature];
    }
    out.order = ordered(out.value, true);
    return out;
}
static void importance_lines(std::ostream &out, const Importance &values, const Lines &names) {
    double total = 0;
    for (double value : values.value)
        total += value;
    for (std::size_t rank = 0; rank < values.order.size(); ++rank) {
        const int j = values.order[rank];
        out << rank + 1 << ' ' << names[j] << " score " << real(values.value[j]) << " share "
            << real(values.value[j] / total) << " rounds " << values.count[j] << '\n';
    }
}
struct Curve {
    Ints train, test;
    Vector train_loss, test_loss, minimum;
};
static Curve curve(const Model &model, const Rows &train, const Rows &test) {
    Curve out;
    for (std::size_t t = 1; t <= model.rounds.size(); ++t) {
        const Vector a = scores(model, train, t), b = scores(model, test, t);
        out.train.push_back(error_count(train, a));
        out.test.push_back(error_count(test, b));
        out.train_loss.push_back(loss(train, a, model.variant));
        out.test_loss.push_back(loss(test, b, model.variant));
        double minimum = train[0].label * a[0];
        for (std::size_t i = 1; i < train.size(); ++i)
            minimum = std::min(minimum, train[i].label * a[i]);
        out.minimum.push_back(minimum / scale(model, t));
    }
    return out;
}
static int first_minimum(const Ints &values) {
    return std::min_element(values.begin(), values.end()) - values.begin();
}
static std::int64_t draw(std::int64_t &state) {
    state = (48271 * state) % 2147483647;
    return state;
}
static void save(const std::string &name, const std::ostringstream &stream) {
    std::istringstream input(stream.str());
    Lines lines;
    std::string line;
    while (std::getline(input, line))
        lines.push_back(line);
    write_lines(name, lines);
}
static Rows relabel(Rows rows, int positive) {
    for (Row &row : rows)
        row.label = row.label == positive ? 1 : -1;
    return rows;
}
static std::vector<Vector> class_scores(const Model &model, const Rows &rows, int classes, int count = -1) {
    if (count < 0)
        count = model.rounds.size();
    std::vector<Vector> out(rows.size(), Vector(classes));
    for (std::size_t i = 0; i < rows.size(); ++i)
        for (int t = 0; t < count; ++t)
            out[i][int(model.rounds[t].stump.output(rows[i].values)) - 1] += model.rounds[t].alpha;
    return out;
}
static Ints class_predictions(const std::vector<Vector> &scores) {
    Ints out;
    for (const Vector &values : scores)
        out.push_back(std::max_element(values.begin(), values.end()) - values.begin() + 1);
    return out;
}
static int multiclass_errors(const Rows &rows, const Ints &predictions) {
    int out = 0;
    for (std::size_t i = 0; i < rows.size(); ++i)
        out += rows[i].label != predictions[i];
    return out;
}
static void confusion_lines(std::ostream &out, const Rows &rows, const Ints &predictions, int classes) {
    const auto table = confusion(rows, predictions, classes);
    out << "confusion\n";
    for (const Ints &row : table) {
        for (int j = 0; j < classes; ++j)
            out << (j ? " " : "") << row[j];
        out << '\n';
    }
    for (int k = 0; k < classes; ++k) {
        int row = 0, column = 0;
        for (int h = 0; h < classes; ++h) {
            row += table[k][h];
            column += table[h][k];
        }
        out << "class " << k + 1 << " precision " << ratio(table[k][k], column) << " recall "
            << ratio(table[k][k], row) << '\n';
    }
}
static Rows restricted(Rows rows, const Ints &features) {
    for (Row &row : rows) {
        Vector values;
        for (int j : features)
            values.push_back(row.values[j]);
        row.values = std::move(values);
    }
    return rows;
}
int main() {
    std::filesystem::create_directories("output");
    const Input input = read_input();
    const Params &p = input.params;
    const Rows &train = input.train, &test = input.test;
    const int n = train.size(), m = test.size(), d = input.names.size(), variants = p.variants.size();
    std::ostringstream ensemble, error_curve, prediction_file, roc, margins, shapes, multi, summary,
        experiments;
    error_curve << "variant,round,train_error,test_error,train_loss,test_loss,min_margin\n";
    prediction_file << "id,variant,score,label";
    for (const std::string &name : input.names)
        prediction_file << ',' << name;
    prediction_file << '\n';
    roc << "variant,threshold,tp,fp\n";
    std::vector<Model> folds;
    std::vector<Ints> fold_errors;
    Ints cv(p.rounds);
    for (int fold = 0; fold < p.folds; ++fold) {
        int validation = 0;
        for (int i = 0; i < n; ++i)
            validation += i % p.folds == fold;
        Vector weights(n);
        for (int i = 0; i < n; ++i)
            if (i % p.folds != fold)
                weights[i] = 1.0 / (n - validation);
        folds.push_back(discrete(train, p, p.rounds, 1, weights));
        Ints errors(p.rounds);
        for (int t = 1; t <= p.rounds; ++t) {
            const Vector values = scores(folds.back(), train, t);
            for (int i = 0; i < n; ++i)
                if (i % p.folds == fold)
                    errors[t - 1] += prediction(values[i]) != train[i].label;
            cv[t - 1] += errors[t - 1];
        }
        fold_errors.push_back(std::move(errors));
    }
    const int selected = first_minimum(cv) + 1;
    Vector oof(n);
    for (int fold = 0; fold < p.folds; ++fold) {
        const Vector values = scores(folds[fold], train, selected);
        for (int i = 0; i < n; ++i)
            if (i % p.folds == fold)
                oof[i] = values[i];
    }
    std::vector<Model> full, final;
    std::vector<Curve> curves;
    std::vector<Vector> train_scores, test_scores;
    std::vector<Importance> importances;
    std::int64_t permutation_state = p.permutation_seed;
    for (int v = 0; v < variants; ++v) {
        const std::string &variant = p.variants[v];
        full.push_back(variant_train(train, p, variant));
        Model model = full.back();
        if (variant == "discrete" && int(model.rounds.size()) > selected)
            model.rounds.resize(selected);
        final.push_back(std::move(model));
        curves.push_back(curve(full.back(), train, test));
        train_scores.push_back(scores(final.back(), train));
        test_scores.push_back(scores(final.back(), test));
        importances.push_back(importance(final.back(), d));
        if (v) {
            ensemble << '\n';
            margins << '\n';
            shapes << '\n';
        }
        const Model &trained = full.back(), &fit = final.back();
        ensemble << "variant " << variant << " rounds " << trained.rounds.size() << " stop " << trained.stop;
        if (variant == "real")
            ensemble << " bins " << p.bins << " smoothing " << real(p.smoothing) << " convergence "
                     << real(p.convergence, 6);
        if (variant == "logit")
            ensemble << " clip " << real(p.clip);
        ensemble << '\n';
        if (variant == "real")
            for (int j = 0; j < d; ++j) {
                ensemble << "cuts " << input.names[j];
                for (double value : trained.cuts[j])
                    ensemble << ' ' << real(value);
                ensemble << '\n';
            }
        for (std::size_t t = 0; t < trained.rounds.size(); ++t) {
            const Round &round = trained.rounds[t];
            ensemble << "round " << t + 1 << " feature " << input.names[round.stump.feature];
            if (variant == "real") {
                ensemble << " z " << real(round.z) << " bound " << real(round.bound) << " values";
                for (double value : round.stump.values)
                    ensemble << ' ' << real(value);
            } else {
                ensemble << " threshold " << real(round.stump.thresholds[0]);
                if (variant == "discrete")
                    ensemble << " polarity " << round.polarity << " error " << real(round.error) << " alpha "
                             << real(round.alpha) << " z " << real(round.z) << " bound " << real(round.bound);
                else {
                    ensemble << " left " << real(round.stump.values[0]) << " right "
                             << real(round.stump.values[1]) << " error " << real(round.error);
                    if (variant == "logit")
                        ensemble << " loss " << real(round.loss);
                }
            }
            ensemble << '\n';
            if (variant == "discrete") {
                const int maximum =
                    std::max_element(round.weights.begin(), round.weights.end()) - round.weights.begin();
                double squares = 0;
                for (double weight : round.weights)
                    squares += weight * weight;
                ensemble << "weights " << t + 1 << " max " << real(round.weights[maximum], 6) << " id "
                         << train[maximum].id << " ess " << real(1 / squares) << '\n';
            }
            const Curve &curve_ = curves.back();
            error_curve << variant << ',' << t + 1 << ',' << ratio(curve_.train[t], n) << ','
                        << ratio(curve_.test[t], m) << ',' << real(curve_.train_loss[t]) << ','
                        << real(curve_.test_loss[t]) << ',' << real(curve_.minimum[t]) << '\n';
        }
        if (variant == "discrete") {
            ensemble << "cv folds " << p.folds << " selected " << selected << " errors " << cv[selected - 1]
                     << '/' << n << '\n';
            for (int fold = 0; fold < p.folds; ++fold) {
                int validation = 0;
                for (int i = 0; i < n; ++i)
                    validation += i % p.folds == fold;
                ensemble << "fold " << fold + 1 << " train " << n - validation << " validation " << validation
                         << " rounds " << folds[fold].rounds.size() << " stop " << folds[fold].stop
                         << " selected " << fold_errors[fold][selected - 1] << '/' << validation << " final "
                         << fold_errors[fold].back() << '/' << validation << '\n';
            }
            ensemble << "cv_errors";
            for (int value : cv)
                ensemble << ' ' << value;
            ensemble << '\n';
        }
        const double total = scale(fit);
        Vector train_margin(n), test_margin(m);
        for (int i = 0; i < n; ++i)
            train_margin[i] = train[i].label * train_scores[v][i] / total;
        for (int i = 0; i < m; ++i)
            test_margin[i] = test[i].label * test_scores[v][i] / total;
        margins << "variant " << variant << " rounds " << fit.rounds.size() << " scale " << real(total)
                << '\n';
        for (int set = 0; set < 2; ++set) {
            const Vector &values = set ? test_margin : train_margin;
            const std::string kind = set ? "test" : "train";
            double sum = 0;
            for (double value : values)
                sum += value;
            margins << kind << " min " << real(*std::min_element(values.begin(), values.end())) << " mean "
                    << real(sum / values.size()) << '\n';
            for (double theta : p.margins) {
                const int count = margin_count(values, theta);
                margins << kind << " le " << real(theta) << ' ' << count << '/' << values.size() << ' '
                        << ratio(count, values.size()) << '\n';
            }
            if (!set) {
                std::array<int, 20> histogram{};
                for (double value : values)
                    ++histogram[std::min(19, int(std::floor((value + 1) * 10)))];
                margins << "histogram";
                for (int count : histogram)
                    margins << ' ' << count;
                margins << '\n';
                const Ints order = ordered(values, false);
                for (int rank = 0; rank < 5; ++rank) {
                    const int i = order[rank];
                    margins << "hardest " << train[i].id << " label " << train[i].label << " margin "
                            << real(values[i]) << '\n';
                }
            } else
                for (double theta : p.margins) {
                    int count = 0, correct = 0;
                    for (int i = 0; i < m; ++i)
                        if (std::abs(values[i]) > theta) {
                            ++count;
                            correct += prediction(test_scores[v][i]) == test[i].label;
                        }
                    margins << "test confident " << real(theta) << ' ' << count << '/' << m << " correct "
                            << correct << '/' << count << ' ' << ratio(correct, count) << '\n';
                }
        }
        margins << "importance\n";
        importance_lines(margins, importances[v], input.names);
        const int base = m - error_count(test, test_scores[v]);
        margins << "permutation repeats " << p.permutations << " base " << base << '/' << m << '\n';
        Vector drops(d);
        Ints minimum(d, m), maximum(d);
        for (int j = 0; j < d; ++j)
            for (int repeat = 0; repeat < p.permutations; ++repeat) {
                Ints permutation(m);
                std::iota(permutation.begin(), permutation.end(), 0);
                for (int i = m - 1; i >= 1; --i) {
                    const int other = draw(permutation_state) % (i + 1);
                    std::swap(permutation[i], permutation[other]);
                }
                int correct = 0;
                for (int i = 0; i < m; ++i) {
                    Vector values = test[i].values;
                    values[j] = test[permutation[i]].values[j];
                    double value = 0;
                    for (const Round &round : fit.rounds)
                        value += round.stump.output(values);
                    correct += prediction(value) == test[i].label;
                }
                drops[j] += base - correct;
                minimum[j] = std::min(minimum[j], correct);
                maximum[j] = std::max(maximum[j], correct);
            }
        const Ints permutation_order = ordered(drops, true);
        for (int rank = 0; rank < d; ++rank) {
            const int j = permutation_order[rank];
            margins << rank + 1 << ' ' << input.names[j] << " drop " << real(drops[j] / (p.permutations * m))
                    << " min " << minimum[j] << '/' << m << " max " << maximum[j] << '/' << m << '\n';
        }
        shapes << "variant " << variant << " rounds " << fit.rounds.size() << '\n';
        for (int j = 0; j < d; ++j) {
            std::vector<const Stump *> collected;
            std::set<double> thresholds;
            for (const Round &round : fit.rounds)
                if (round.stump.feature == j) {
                    collected.push_back(&round.stump);
                    thresholds.insert(round.stump.thresholds.begin(), round.stump.thresholds.end());
                }
            Vector ends(thresholds.begin(), thresholds.end()), values(ends.size() + 1);
            for (std::size_t interval = 0; interval < values.size(); ++interval)
                for (const Stump *stump : collected) {
                    int bin = 0;
                    if (interval)
                        for (double threshold : stump->thresholds)
                            bin += threshold <= ends[interval - 1];
                    values[interval] += stump->values[bin];
                }
            shapes << "feature " << input.names[j] << " rounds " << collected.size() << " cuts "
                   << ends.size() << " range "
                   << real(*std::max_element(values.begin(), values.end()) -
                           *std::min_element(values.begin(), values.end()))
                   << '\n';
            for (std::size_t interval = 0; interval < values.size(); ++interval)
                shapes << "interval " << (interval ? real(ends[interval - 1]) : "-inf") << ' '
                       << (interval < ends.size() ? real(ends[interval]) : "inf") << " value "
                       << real(values[interval]) << '\n';
        }
        std::set<double, std::greater<double>> thresholds(test_scores[v].begin(), test_scores[v].end());
        for (double threshold : thresholds) {
            int tp = 0, fp = 0;
            for (int i = 0; i < m; ++i)
                if (test_scores[v][i] >= threshold) {
                    tp += test[i].label == 1;
                    fp += test[i].label == -1;
                }
            roc << variant << ',' << real(threshold) << ',' << tp << ',' << fp << '\n';
        }
    }
    for (int i = 0; i < m; ++i)
        for (int v = 0; v < variants; ++v) {
            prediction_file << test[i].id << ',' << p.variants[v] << ',' << real(test_scores[v][i]) << ','
                            << prediction(test_scores[v][i]);
            Vector contributions(d);
            for (const Round &round : final[v].rounds)
                contributions[round.stump.feature] += round.stump.output(test[i].values);
            for (double value : contributions)
                prediction_file << ',' << real(value);
            prediction_file << '\n';
        }
    const Model multi_model = samme(input.multi_train, p);
    const auto same_train_scores = class_scores(multi_model, input.multi_train, p.classes),
               same_test_scores = class_scores(multi_model, input.multi_test, p.classes);
    const Ints same_train = class_predictions(same_train_scores),
               same_test = class_predictions(same_test_scores);
    multi << "samme classes " << p.classes << " train " << input.multi_train.size() << " test "
          << input.multi_test.size() << " rounds " << multi_model.rounds.size() << " stop "
          << multi_model.stop << '\n';
    for (std::size_t t = 0; t < multi_model.rounds.size(); ++t) {
        const Round &round = multi_model.rounds[t];
        multi << "round " << t + 1 << " feature " << input.multi_names[round.stump.feature] << " threshold "
              << real(round.stump.thresholds[0]) << " left " << int(round.stump.values[0]) << " right "
              << int(round.stump.values[1]) << " error " << real(round.error) << " alpha "
              << real(round.alpha) << '\n';
        const int a = multiclass_errors(
                      input.multi_train,
                      class_predictions(class_scores(multi_model, input.multi_train, p.classes, t + 1))),
                  b = multiclass_errors(
                      input.multi_test,
                      class_predictions(class_scores(multi_model, input.multi_test, p.classes, t + 1)));
        error_curve << "samme," << t + 1 << ',' << ratio(a, input.multi_train.size()) << ','
                    << ratio(b, input.multi_test.size()) << ",-,-,-\n";
    }
    const int multi_train_error = multiclass_errors(input.multi_train, same_train),
              multi_test_error = multiclass_errors(input.multi_test, same_test);
    multi << "train errors " << multi_train_error << '/' << input.multi_train.size() << " rate "
          << ratio(multi_train_error, input.multi_train.size()) << "\ntest errors " << multi_test_error << '/'
          << input.multi_test.size() << " rate " << ratio(multi_test_error, input.multi_test.size()) << '\n';
    confusion_lines(multi, input.multi_test, same_test, p.classes);
    multi << "importance\n";
    importance_lines(multi, importance(multi_model, input.multi_names.size()), input.multi_names);
    multi << "\novr classes " << p.classes << " rounds " << p.samme_rounds << '\n';
    std::vector<Vector> ovr_train(input.multi_train.size(), Vector(p.classes)),
        ovr_test(input.multi_test.size(), Vector(p.classes));
    for (int k = 1; k <= p.classes; ++k) {
        const Rows a = relabel(input.multi_train, k), b = relabel(input.multi_test, k);
        const Model model = discrete(a, p, p.samme_rounds);
        const Vector av = scores(model, a), bv = scores(model, b);
        int positives = 0;
        for (const Row &row : a)
            positives += row.label == 1;
        multi << "class " << k << " rounds " << model.rounds.size() << " stop " << model.stop << " positives "
              << positives << " train_errors " << error_count(a, av) << '/' << a.size() << " test_errors "
              << error_count(b, bv) << '/' << b.size() << '\n';
        for (std::size_t i = 0; i < a.size(); ++i)
            ovr_train[i][k - 1] = av[i];
        for (std::size_t i = 0; i < b.size(); ++i)
            ovr_test[i][k - 1] = bv[i];
    }
    const Ints ovr_train_prediction = class_predictions(ovr_train),
               ovr_test_prediction = class_predictions(ovr_test);
    const int ovr_train_error = multiclass_errors(input.multi_train, ovr_train_prediction),
              ovr_test_error = multiclass_errors(input.multi_test, ovr_test_prediction);
    multi << "train errors " << ovr_train_error << '/' << input.multi_train.size() << " rate "
          << ratio(ovr_train_error, input.multi_train.size()) << "\ntest errors " << ovr_test_error << '/'
          << input.multi_test.size() << " rate " << ratio(ovr_test_error, input.multi_test.size()) << '\n';
    confusion_lines(multi, input.multi_test, ovr_test_prediction, p.classes);
    int same = 0;
    for (std::size_t i = 0; i < input.multi_test.size(); ++i)
        same += same_test[i] == ovr_test_prediction[i];
    multi << "agreement " << same << '/' << input.multi_test.size() << "\npredictions\n";
    for (std::size_t i = 0; i < input.multi_test.size(); ++i) {
        multi << input.multi_test[i].id << " class " << input.multi_test[i].label << " samme " << same_test[i]
              << " ovr " << ovr_test_prediction[i] << " scores";
        for (double value : same_test_scores[i])
            multi << ' ' << real(value);
        multi << '\n';
    }
    int train_positive = 0, test_positive = 0;
    for (const Row &row : train)
        train_positive += row.label == 1;
    for (const Row &row : test)
        test_positive += row.label == 1;
    summary << "data train " << n << " test " << m << " features " << d << " positives " << train_positive
            << ' ' << test_positive << '\n';
    for (int j = 0; j < d; ++j) {
        summary << "feature " << input.names[j];
        for (const Rows *rows : {&train, &test}) {
            Vector values;
            double sum = 0;
            std::set<double> distinct;
            for (const Row &row : *rows) {
                values.push_back(row.values[j]);
                sum += row.values[j];
                distinct.insert(row.values[j]);
            }
            summary << ' ' << (rows == &train ? "train" : "test") << ' '
                    << real(*std::min_element(values.begin(), values.end())) << ' '
                    << real(*std::max_element(values.begin(), values.end())) << ' '
                    << real(sum / values.size()) << ' ' << distinct.size();
        }
        summary << '\n';
    }
    summary << "cv selected " << selected << " errors " << cv[selected - 1] << '/' << n << " rate "
            << ratio(cv[selected - 1], n) << '\n';
    metrics(summary, "oof", "discrete", selected, train, oof);
    Vector committee_train(n), committee_test(m);
    int committee_rounds = 0;
    for (int v = 0; v < variants; ++v) {
        metrics(summary, "train", p.variants[v], final[v].rounds.size(), train, train_scores[v]);
        metrics(summary, "test", p.variants[v], final[v].rounds.size(), test, test_scores[v]);
        const double total = scale(final[v]);
        for (int i = 0; i < n; ++i)
            committee_train[i] += train_scores[v][i] / total;
        for (int i = 0; i < m; ++i)
            committee_test[i] += test_scores[v][i] / total;
        committee_rounds += final[v].rounds.size();
    }
    metrics(summary, "train", "committee", committee_rounds, train, committee_train);
    metrics(summary, "test", "committee", committee_rounds, test, committee_test);
    for (int v = 0; v < variants; ++v) {
        const Curve &values = curves[v];
        const int a = first_minimum(values.train), b = first_minimum(values.test);
        summary << "curve " << p.variants[v] << " rounds " << full[v].rounds.size() << " train_min "
                << values.train[a] << '/' << n << " at " << a + 1 << " test_min " << values.test[b] << '/'
                << m << " at " << b + 1 << '\n';
    }
    Ints wrong;
    for (int i = 0; i < m; ++i) {
        bool all = true;
        for (int v = 0; v < variants; ++v)
            all = all && prediction(test_scores[v][i]) != test[i].label;
        if (all)
            wrong.push_back(i);
    }
    summary << "all_wrong " << wrong.size();
    for (int i : wrong)
        summary << ' ' << test[i].id;
    summary << "\nagreement\n";
    for (int a = 0; a < variants - 1; ++a)
        for (int b = a + 1; b < variants; ++b) {
            int agreement = 0, n1 = 0, n2 = 0;
            for (int i = 0; i < m; ++i) {
                const int x = prediction(test_scores[a][i]), y = prediction(test_scores[b][i]);
                agreement += x == y;
                n1 += x == test[i].label && y != test[i].label;
                n2 += y == test[i].label && x != test[i].label;
            }
            const int numerator = (std::abs(n1 - n2) - 1) * (std::abs(n1 - n2) - 1);
            summary << p.variants[a] << ' ' << p.variants[b] << " agree " << agreement << '/' << m
                    << " only_first " << n1 << " only_second " << n2 << " chi2 " << ratio(numerator, n1 + n2)
                    << '\n';
        }
    summary << "bootstrap samples " << p.bootstrap << " seed " << p.bootstrap_seed << '\n';
    std::int64_t bootstrap_state = p.bootstrap_seed;
    std::vector<Ints> bootstrap(variants, Ints(p.bootstrap));
    for (int sample = 0; sample < p.bootstrap; ++sample)
        for (int draw_ = 0; draw_ < m; ++draw_) {
            const int i = draw(bootstrap_state) % m;
            for (int v = 0; v < variants; ++v)
                bootstrap[v][sample] += prediction(test_scores[v][i]) == test[i].label;
        }
    for (int v = 0; v < variants; ++v) {
        Ints values = bootstrap[v];
        std::sort(values.begin(), values.end());
        int sum = 0;
        for (int count : values)
            sum += count;
        const int g = p.bootstrap / 40;
        summary << p.variants[v] << " mean " << ratio(sum, p.bootstrap * m) << " low " << ratio(values[g], m)
                << " high " << ratio(values[p.bootstrap - g - 1], m) << '\n';
    }
    for (int a = 0; a < variants - 1; ++a)
        for (int b = a + 1; b < variants; ++b) {
            int first = 0, tie = 0, second = 0;
            for (int sample = 0; sample < p.bootstrap; ++sample) {
                first += bootstrap[a][sample] > bootstrap[b][sample];
                tie += bootstrap[a][sample] == bootstrap[b][sample];
                second += bootstrap[a][sample] < bootstrap[b][sample];
            }
            summary << p.variants[a] << ' ' << p.variants[b] << " first " << first << " tie " << tie
                    << " second " << second << '\n';
        }
    for (int v = 0; v < variants; ++v) {
        std::array<int, 5> counts{}, positives{};
        std::array<double, 5> sums{};
        double brier = 0;
        for (int i = 0; i < m; ++i) {
            const double probability = 1 / (1 + std::exp(-2 * test_scores[v][i])),
                         delta = probability - (test[i].label == 1 ? 1 : 0);
            brier += delta * delta;
            const int bin = std::min(4, int(std::floor(probability * 5)));
            ++counts[bin];
            sums[bin] += probability;
            positives[bin] += test[i].label == 1;
        }
        summary << "calibration " << p.variants[v] << " brier " << real(brier / m) << '\n';
        const Lines ranges = {"0.0-0.2", "0.2-0.4", "0.4-0.6", "0.6-0.8", "0.8-1.0"};
        for (int bin = 0; bin < 5; ++bin)
            summary << "bin " << ranges[bin] << " count " << counts[bin] << " mean "
                    << (counts[bin] ? real(sums[bin] / counts[bin]) : "-") << " positives " << positives[bin]
                    << '\n';
    }
    for (int percent : p.sizes) {
        const int size = n * percent / 100;
        const Rows rows(train.begin(), train.begin() + size);
        experiments << "size " << percent << " rows " << size << '\n';
        for (const std::string &variant : p.variants) {
            const Model model = variant_train(rows, p, variant);
            experiments << variant << " rounds " << model.rounds.size() << " stop " << model.stop
                        << " train_errors " << error_count(rows, scores(model, rows)) << '/' << size
                        << " test_errors " << error_count(test, scores(model, test)) << '/' << m << '\n';
        }
    }
    for (double shrinkage : p.shrinkage) {
        const Model model = discrete(train, p, p.rounds, shrinkage);
        const Curve values = curve(model, train, test);
        const int minimum = first_minimum(values.test);
        experiments << "shrinkage " << real(shrinkage) << " rounds " << model.rounds.size() << " stop "
                    << model.stop << " train_errors " << error_count(train, scores(model, train)) << '/' << n
                    << " test_errors " << error_count(test, scores(model, test)) << '/' << m << " test_min "
                    << values.test[minimum] << '/' << m << " at " << minimum + 1 << '\n';
    }
    const int discrete_index =
        std::find(p.variants.begin(), p.variants.end(), "discrete") - p.variants.begin();
    const Ints &feature_order = importances[discrete_index].order;
    for (int count = 1; count <= d; ++count) {
        Ints features(feature_order.begin(), feature_order.begin() + count);
        std::sort(features.begin(), features.end());
        const Rows a = restricted(train, features), b = restricted(test, features);
        const Model model = discrete(a, p, selected);
        experiments << "top " << count << " features";
        for (int j : features)
            experiments << ' ' << input.names[j];
        experiments << " rounds " << model.rounds.size() << " train_errors "
                    << error_count(a, scores(model, a)) << '/' << n << " test_errors "
                    << error_count(b, scores(model, b)) << '/' << m << '\n';
    }
    for (int percent : p.noise) {
        const int flipped = n * percent / 100;
        std::int64_t state = p.noise_seed;
        Ints permutation(n);
        std::iota(permutation.begin(), permutation.end(), 0);
        for (int i = 0; i < flipped; ++i) {
            const int other = draw(state) % (n - i) + i;
            std::swap(permutation[i], permutation[other]);
        }
        Rows rows = train;
        std::vector<bool> changed(n);
        for (int i = 0; i < flipped; ++i) {
            rows[permutation[i]].label = -rows[permutation[i]].label;
            changed[permutation[i]] = true;
        }
        experiments << "noise " << percent << " flipped " << flipped << '\n';
        for (const std::string &variant : p.variants) {
            const Model model = variant_train(rows, p, variant);
            const Curve values = curve(model, rows, test);
            const int minimum = first_minimum(values.test);
            double weight = 0;
            for (int i = 0; i < n; ++i)
                if (changed[i])
                    weight += model.rounds.back().weights[i];
            experiments << variant << " rounds " << model.rounds.size() << " stop " << model.stop
                        << " train_errors " << error_count(rows, scores(model, rows)) << '/' << n
                        << " test_errors " << error_count(test, scores(model, test)) << '/' << m
                        << " test_min " << values.test[minimum] << '/' << m << " at " << minimum + 1
                        << " flipped_weight " << real(weight) << '\n';
        }
    }
    save("ensemble.txt", ensemble);
    save("error_curve.csv", error_curve);
    save("predictions.csv", prediction_file);
    save("roc.csv", roc);
    save("margins.txt", margins);
    save("shapes.txt", shapes);
    save("samme.txt", multi);
    save("summary.txt", summary);
    save("experiments.txt", experiments);
}
