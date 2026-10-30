#include "trainer.hpp"
struct Evaluated {
    double loss = 0;
    int correct = 0;
    Ids predictions;
    std::vector<Forward> records;
};
static Evaluated evaluate(const Network &network, const Field &weights,
                          const std::vector<Image> &images, bool retain = false) {
    Evaluated out;
    for (const Image &image : images) {
        Forward result = forward(network, weights, image);
        const int chosen = prediction(result.scores);
        out.loss += result.loss;
        out.correct += chosen == image.label;
        out.predictions.push_back(chosen);
        if (retain)
            out.records.push_back(std::move(result));
    }
    out.loss /= double(images.size());
    return out;
}
static std::pair<Field, double> mean_gradient(const Network &network, const Field &weights,
                                              const std::vector<Image> &images, const Ids &order,
                                              int first, int last) {
    Field gradient(weights.size());
    double loss = 0;
    for (int i = first; i < last; ++i) {
        const Forward record = forward(network, weights, images[order[i]]);
        const Backward value = backward(network, weights, record);
        for (int p = 0; p < int(gradient.size()); ++p)
            gradient[p] += value.parameters[p];
        loss += record.loss;
    }
    for (double &value : gradient)
        value /= last - first;
    return {gradient, loss / (last - first)};
}
static double batch_loss(const Network &network, const Field &weights,
                         const std::vector<Image> &images, const Ids &batch) {
    double loss = 0;
    for (int i : batch)
        loss += forward(network, weights, images[i]).loss;
    return loss / double(batch.size());
}
static Lines gradient_check(const Input &input, const std::vector<Image> &training) {
    Lines out;
    for (const Network &network : input.networks) {
        if (!out.empty())
            out.push_back("");
        Random random{input.params.seed};
        Ids order(training.size());
        std::iota(order.begin(), order.end(), 0);
        random.shuffle(order);
        const Ids batch(order.begin(),
                        order.begin() + std::min(input.params.batch, int(order.size())));
        const Field analytic =
            mean_gradient(network, network.initial, training, batch, 0, int(batch.size())).first;
        Field weights = network.initial;
        std::vector<std::array<int, 2>> counts(network.layers.size());
        bool passed = true;
        int checked = 0;
        for (int p = 0; p < int(weights.size()); p += input.params.stride) {
            const double original = weights[p], h = 0.00001;
            weights[p] = original + h;
            const double plus = batch_loss(network, weights, training, batch);
            weights[p] = original - h;
            const double minus = batch_loss(network, weights, training, batch);
            weights[p] = original;
            const double numeric = (plus - minus) / (2 * h),
                         error = std::abs(analytic[p] - numeric) /
                                 std::max(1.0, std::abs(analytic[p]) + std::abs(numeric));
            passed &= error < 0.000001;
            ++checked;
            for (int l = 0; l < int(network.layers.size()); ++l) {
                const Layer &layer = network.layers[l];
                if (p >= layer.weights && p < layer.biases)
                    ++counts[l][0];
                else if (p >= layer.biases && p < layer.biases + layer.units)
                    ++counts[l][1];
            }
        }
        line(out, "network ", network.name);
        line(out, "parameters ", weights.size());
        std::string ids = "batch";
        for (int i : batch)
            ids += " " + training[i].id;
        out.push_back(ids);
        for (int l = 0; l < int(counts.size()); ++l)
            line(out, "layer ", l + 1, " weights ", counts[l][0], " biases ", counts[l][1]);
        line(out, "checked ", checked);
        line(out, "result ", passed ? "PASS" : "FAIL");
    }
    return out;
}
struct Epoch {
    int number;
    double eta, magnitude, train_loss, val_loss;
    int train_correct, val_correct;
    bool improved;
    std::vector<bool> correct;
};
struct Result {
    Run definition;
    Field weights;
    std::vector<Epoch> epochs;
    int best_epoch = 0, best_correct = 0, updates = 0;
    double best_loss = 0;
    std::string stop;
    Evaluated test;
    Counts confusion;
};
static Result train_run(const Input &input, const std::vector<Image> &training,
                        const std::vector<Image> &validation, Run definition) {
    const Network &network = input.networks[definition.network];
    Result out;
    out.definition = definition;
    Field weights = network.initial;
    Optimizer optimizer{int(weights.size())};
    Random random{input.params.seed};
    Ids order(training.size());
    std::iota(order.begin(), order.end(), 0);
    int wait = 0;
    for (int epoch = 1; epoch <= input.params.epochs; ++epoch) {
        const double eta = learning_rate(definition, input.params, epoch);
        random.shuffle(order);
        double magnitude = 0;
        int batches = 0;
        for (int first = 0; first < int(order.size()); first += input.params.batch) {
            const int last = std::min(int(order.size()), first + input.params.batch);
            Field gradient = mean_gradient(network, weights, training, order, first, last).first;
            for (int p = 0; p < int(weights.size()); ++p)
                if (network.is_weight[p])
                    gradient[p] = gradient[p] + definition.decay * weights[p];
            double squared = 0;
            for (double value : gradient)
                squared += value * value;
            magnitude += std::sqrt(squared);
            ++batches;
            optimizer.update(weights, gradient, definition, eta);
            ++out.updates;
        }
        const Evaluated train = evaluate(network, weights, training),
                        valid = evaluate(network, weights, validation);
        const bool improved = epoch == 1 || valid.loss < out.best_loss;
        Epoch record{epoch,         eta,        magnitude / batches,
                     train.loss,    valid.loss, train.correct,
                     valid.correct, improved,   {}};
        for (int i = 0; i < int(training.size()); ++i)
            record.correct.push_back(train.predictions[i] == training[i].label);
        out.epochs.push_back(record);
        if (improved) {
            out.best_loss = valid.loss;
            out.best_epoch = epoch;
            out.best_correct = valid.correct;
            out.weights = weights;
            wait = 0;
        } else
            ++wait;
        if (wait >= input.params.patience) {
            out.stop = "early";
            break;
        }
        if (epoch == input.params.epochs)
            out.stop = "max_epochs";
    }
    out.test = evaluate(network, out.weights, input.test, true);
    out.confusion = confusion(input.test, out.test.predictions, input.classes);
    return out;
}
struct Noise {
    int rate, flipped = 0;
    std::vector<Image> images;
};
static std::vector<Noise> noisy(const Input &input) {
    std::vector<Noise> out;
    for (int rate : input.params.noise) {
        Noise result{rate, 0, input.test};
        Random random{input.params.seed};
        for (Image &image : result.images)
            for (int i = 0; i < int(image.input.size()); ++i)
                if (random.draw() % 100 < rate) {
                    image.input[i] = 1 - image.input[i];
                    image.pixels[i] = image.pixels[i] == '1' ? '0' : '1';
                    ++result.flipped;
                }
        out.push_back(std::move(result));
    }
    return out;
}
static std::string class_heading(const std::string &prefix, int count) {
    std::string out = prefix;
    for (int k = 0; k < count; ++k)
        out += " " + std::to_string(k);
    return out;
}
static Lines data_summary(const Input &input, const std::vector<Image> &training,
                          const std::vector<Image> &validation) {
    Lines out{"data"};
    const int pixels = input.width * input.height;
    line(out, "train ", training.size(), " validation ", validation.size(), " test ",
         input.test.size(), " pixels ", pixels);
    Ids train_counts(input.classes), val_counts(input.classes), test_counts(input.classes),
        ink(input.classes);
    std::vector<Ids> sums(input.classes, Ids(pixels)), levels = sums;
    for (const Image &image : training) {
        ++train_counts[image.label];
        for (int i = 0; i < pixels; ++i) {
            const int value = image.pixels[i] == '1';
            ink[image.label] += value;
            sums[image.label][i] += value;
        }
    }
    for (const Image &image : validation)
        ++val_counts[image.label];
    for (const Image &image : input.test)
        ++test_counts[image.label];
    for (int k = 0; k < input.classes; ++k) {
        line(out, "class ", k, " train ", train_counts[k], " validation ", val_counts[k], " test ",
             test_counts[k], " ink ", ratio(ink[k], train_counts[k]));
        for (int i = 0; i < pixels; ++i)
            levels[k][i] = train_counts[k] ? std::min(9, 10 * sums[k][i] / train_counts[k]) : 0;
    }
    out.push_back(class_heading("mean_images", input.classes));
    const Lines maps = level_maps(levels, input.width, input.height);
    out.insert(out.end(), maps.begin(), maps.end());
    return out;
}
static Lines run_report(const Input &input, const std::vector<Image> &training,
                        const std::vector<Image> &validation, const Result &result,
                        const std::vector<Noise> &noise) {
    Lines out;
    const Run &run = result.definition;
    const Network &network = input.networks[run.network];
    const int count = int(input.test.size());
    line(out, "run ", run.name, " network ", network.name, " optimizer ", run.optimizer);
    line(out, "epochs ", result.epochs.size(), " best_epoch ", result.best_epoch, " stop ",
         result.stop, " updates ", result.updates);
    line(out, "best_val_loss ", real(result.best_loss, 6), " best_val_acc ",
         ratio(result.best_correct, int(validation.size())), " correct ", result.best_correct, "/",
         validation.size());
    line(out, "test_loss ", real(result.test.loss, 6), " test_acc ",
         ratio(result.test.correct, count), " correct ", result.test.correct, "/", count);
    int top2 = 0, correct_count = 0, wrong_count = 0;
    double correct_confidence = 0, wrong_confidence = 0;
    for (int i = 0; i < count; ++i) {
        const int chosen = result.test.predictions[i];
        const Forward &record = result.test.records[i];
        const bool correct = chosen == input.test[i].label;
        top2 += correct || second_class(record.scores, chosen) == input.test[i].label;
        if (correct) {
            ++correct_count;
            correct_confidence += record.scores[chosen];
        } else {
            ++wrong_count;
            wrong_confidence += record.scores[chosen];
        }
    }
    line(out, "top2_acc ", ratio(top2, count), " correct ", top2, "/", count);
    line(out, "confidence correct ",
         correct_count ? real(correct_confidence / correct_count, 4) : "-", " wrong ",
         wrong_count ? real(wrong_confidence / wrong_count, 4) : "-");
    int forgetting = 0, forgotten = 0, never = 0;
    for (int i = 0; i < int(training.size()); ++i) {
        int events = 0;
        bool learned = false;
        for (int epoch = 0; epoch < int(result.epochs.size()); ++epoch) {
            const bool correct = result.epochs[epoch].correct[i];
            learned |= correct;
            if (epoch > 0 && result.epochs[epoch - 1].correct[i] && !correct)
                ++events;
        }
        forgetting += events;
        forgotten += events > 0;
        never += !learned;
    }
    line(out, "forgetting events ", forgetting, " rows ", forgotten, " never_learned ", never);
    std::string norms = "weight_norms", changes = "weight_changes";
    for (const Layer &layer : network.layers) {
        double norm = 0, change = 0;
        for (int p = layer.weights; p < layer.biases; ++p) {
            norm += result.weights[p] * result.weights[p];
            const double difference = result.weights[p] - network.initial[p];
            change += difference * difference;
        }
        norms += " " + real(std::sqrt(norm), 4);
        changes += " " + real(std::sqrt(change), 4);
    }
    out.push_back(norms);
    out.push_back(changes);
    out.push_back("curve");
    double maximum = 0;
    for (const Epoch &epoch : result.epochs)
        maximum = std::max(maximum, std::max(epoch.train_loss, epoch.val_loss));
    for (const Epoch &epoch : result.epochs) {
        std::string cells(40, ' ');
        const int train = int(std::floor(39 * epoch.train_loss / maximum + 0.5)),
                  valid = int(std::floor(39 * epoch.val_loss / maximum + 0.5));
        cells[train] = 't';
        cells[valid] = valid == train ? '*' : 'v';
        std::ostringstream text;
        text << std::setw(2) << epoch.number << " |" << cells << '|';
        if (epoch.number == result.best_epoch)
            text << " best";
        out.push_back(text.str());
    }
    out.push_back("confusion");
    for (int k = 0; k < input.classes; ++k) {
        std::string row = std::to_string(k) + ":";
        for (int value : result.confusion[k])
            row += " " + std::to_string(value);
        out.push_back(row);
    }
    for (int k = 0; k < input.classes; ++k) {
        const ClassStats stats = class_stats(result.confusion, k);
        line(out, "class ", k, " support ", stats.support, " predicted ", stats.predicted,
             " precision ", ratio(stats.true_positive, stats.predicted), " recall ",
             ratio(stats.true_positive, stats.support), " f1 ",
             ratio(2 * stats.true_positive, stats.support + stats.predicted));
    }
    out.push_back("calibration");
    Ids bin_counts(input.params.bins), bin_correct(input.params.bins);
    Field bin_sums(input.params.bins);
    for (int i = 0; i < count; ++i) {
        const int chosen = result.test.predictions[i];
        const double confidence = result.test.records[i].scores[chosen];
        const int bin =
            std::min(input.params.bins - 1, int(std::floor(confidence * input.params.bins)));
        ++bin_counts[bin];
        bin_correct[bin] += chosen == input.test[i].label;
        bin_sums[bin] += confidence;
    }
    double ece = 0;
    for (int bin = 0; bin < input.params.bins; ++bin) {
        const int n = bin_counts[bin];
        line(out, "bin ", bin + 1, " ", real(double(bin) / input.params.bins, 2), " ",
             real(double(bin + 1) / input.params.bins, 2), " count ", n, " accuracy ",
             ratio(bin_correct[bin], n), " confidence ", n ? real(bin_sums[bin] / n, 4) : "-");
        if (n)
            ece += (double(n) / count) * std::abs(double(bin_correct[bin]) / n - bin_sums[bin] / n);
    }
    line(out, "ece ", real(ece, 4));
    Ids class_counts(input.classes);
    for (const Image &image : input.test)
        ++class_counts[image.label];
    for (int l = 0; l + 1 < int(network.layers.size()); ++l) {
        const Layer &layer = network.layers[l];
        line(out, "hidden ", l + 1, " ", layer.function, " units ", layer.units);
        std::vector<Field> means(input.classes, Field(layer.units));
        Ids zeros(layer.units);
        for (int i = 0; i < count; ++i)
            for (int j = 0; j < layer.units; ++j) {
                const double value = result.test.records[i].activations[l + 1][j];
                means[input.test[i].label][j] += value;
                zeros[j] += value == 0;
            }
        for (int k = 0; k < input.classes; ++k) {
            std::string row = "class " + std::to_string(k) + " mean";
            if (class_counts[k] == 0)
                row += " -";
            else
                for (double &value : means[k]) {
                    value /= class_counts[k];
                    row += " " + real(value, 4);
                }
            out.push_back(row);
        }
        std::string preferred = "preferred";
        for (int j = 0; j < layer.units; ++j) {
            int best = -1;
            for (int k = 0; k < input.classes; ++k)
                if (class_counts[k] && (best < 0 || means[k][j] > means[best][j]))
                    best = k;
            preferred += " " + std::to_string(best);
        }
        out.push_back(preferred);
        if (layer.function == "RELU") {
            std::string row = "zero_counts";
            for (int n : zeros)
                row += " " + std::to_string(n);
            out.push_back(row);
        }
    }
    out.push_back("pruning");
    Ids weights;
    for (int p = 0; p < int(network.is_weight.size()); ++p)
        if (network.is_weight[p])
            weights.push_back(p);
    std::sort(weights.begin(), weights.end(), [&](int a, int b) {
        const double x = std::abs(result.weights[a]), y = std::abs(result.weights[b]);
        return x != y ? x < y : a < b;
    });
    for (int q : input.params.prune) {
        const int removed = q * network.weight_count / 100;
        Field pruned = result.weights;
        for (int i = 0; i < removed; ++i)
            pruned[weights[i]] = 0;
        const Evaluated value = evaluate(network, pruned, input.test);
        line(out, "prune ", q, " removed ", removed, " correct ", value.correct, " test_acc ",
             ratio(value.correct, count), " test_loss ", real(value.loss, 6));
    }
    out.push_back("noise");
    for (const Noise &item : noise) {
        const int correct = evaluate(network, result.weights, item.images).correct;
        line(out, "noise ", item.rate, " correct ", correct, " test_acc ", ratio(correct, count));
    }
    std::string missed = "misclassified " + std::to_string(count - result.test.correct);
    for (int i = 0; i < count; ++i)
        if (result.test.predictions[i] != input.test[i].label)
            missed += " " + input.test[i].id;
    out.push_back(missed);
    return out;
}
static Lines final_weights(const Input &input, const std::vector<Result> &results) {
    Lines out;
    for (const Result &result : results) {
        if (!out.empty())
            out.push_back("");
        const Network &network = input.networks[result.definition.network];
        line(out, "RUN ", result.definition.name, " NETWORK ", network.name, " EPOCH ",
             result.best_epoch);
        for (int l = 0; l < int(network.layers.size()); ++l) {
            const Layer &layer = network.layers[l];
            line(out, "LAYER ", l + 1, " ", layer.units, " ", layer.inputs);
            for (int j = 0; j < layer.units; ++j) {
                std::string row = "W";
                for (int i = 0; i < layer.inputs; ++i)
                    row += " " + real(result.weights[layer.weights + j * layer.inputs + i], 4);
                out.push_back(row);
            }
            std::string row = "B";
            for (int j = 0; j < layer.units; ++j)
                row += " " + real(result.weights[layer.biases + j], 4);
            out.push_back(row);
        }
    }
    return out;
}
static Lines comparison(const Input &input, const std::vector<Image> &training,
                        const std::vector<Result> &results, const std::vector<Noise> &noise) {
    Lines out{"comparison"};
    Ids ranking(results.size());
    std::iota(ranking.begin(), ranking.end(), 0);
    std::sort(ranking.begin(), ranking.end(), [&](int a, int b) {
        const Result &x = results[a], &y = results[b];
        return x.test.correct != y.test.correct ? x.test.correct > y.test.correct
               : x.best_loss != y.best_loss     ? x.best_loss < y.best_loss
                                                : a < b;
    });
    const int count = int(input.test.size()), top_index = ranking[0];
    const Result &top = results[top_index];
    const Network &network = input.networks[top.definition.network];
    for (int rank = 0; rank < int(ranking.size()); ++rank) {
        const Result &result = results[ranking[rank]];
        line(out, "rank ", rank + 1, " ", result.definition.name, " correct ", result.test.correct,
             " test_acc ", ratio(result.test.correct, count), " best_val_loss ",
             real(result.best_loss, 6), " test_loss ", real(result.test.loss, 6), " best_epoch ",
             result.best_epoch, " epochs ", result.epochs.size(), " updates ", result.updates);
    }
    out.push_back("agreement");
    for (const Result &a : results) {
        std::string row = a.definition.name;
        for (const Result &b : results) {
            int agreement = 0;
            for (int i = 0; i < count; ++i)
                agreement += a.test.predictions[i] == b.test.predictions[i];
            row += " " + std::to_string(agreement);
        }
        out.push_back(row);
    }
    line(out, "mcnemar ", top.definition.name);
    for (int index : ranking)
        if (index != top_index) {
            const Result &other = results[index];
            int b = 0, c = 0;
            for (int i = 0; i < count; ++i) {
                const bool x = top.test.predictions[i] == input.test[i].label,
                           y = other.test.predictions[i] == input.test[i].label;
                b += x && !y;
                c += y && !x;
            }
            const std::int64_t difference = std::max(std::abs(b - c) - 1, 0),
                               numerator = difference * difference, denominator = b + c;
            line(out, "vs ", other.definition.name, " b ", b, " c ", c, " chi2 ",
                 denominator ? ratio(numerator, denominator) : "0.0000", " significant ",
                 numerator * 1000 > 3841 * denominator ? "yes" : "no");
        }
    Ids ensemble;
    int correct = 0, fixed = 0, broken = 0;
    for (int i = 0; i < count; ++i) {
        Ids votes(input.classes);
        for (const Result &result : results)
            ++votes[result.test.predictions[i]];
        const int maximum = *std::max_element(votes.begin(), votes.end());
        int chosen = 0;
        for (int index : ranking)
            if (votes[results[index].test.predictions[i]] == maximum) {
                chosen = results[index].test.predictions[i];
                break;
            }
        ensemble.push_back(chosen);
        const bool good = chosen == input.test[i].label,
                   top_good = top.test.predictions[i] == input.test[i].label;
        correct += good;
        fixed += good && !top_good;
        broken += top_good && !good;
    }
    line(out, "ensemble correct ", correct, "/", count, " test_acc ", ratio(correct, count),
         " fixed ", fixed, " broken ", broken);
    Ids soft;
    for (int run = 0; run < int(results.size()); ++run)
        if (input.networks[results[run].definition.network].layers.back().function == "SOFTMAX")
            soft.push_back(run);
    if (soft.empty())
        out.push_back("soft_ensemble none");
    else {
        int correct = 0;
        for (int i = 0; i < count; ++i) {
            Field scores(input.classes);
            for (int index : soft)
                for (int k = 0; k < input.classes; ++k)
                    scores[k] += results[index].test.records[i].scores[k];
            for (double &score : scores)
                score /= double(soft.size());
            correct += prediction(scores) == input.test[i].label;
        }
        line(out, "soft_ensemble runs ", soft.size(), " correct ", correct, "/", count,
             " test_acc ", ratio(correct, count));
    }
    for (const Noise &item : noise)
        line(out, "noise ", item.rate, " flipped ", item.flipped);
    struct Pair {
        int actual, predicted, count;
    };
    std::vector<Pair> pairs;
    Counts summed(input.classes, Ids(input.classes));
    for (const Result &result : results)
        for (int a = 0; a < input.classes; ++a)
            for (int b = 0; b < input.classes; ++b)
                summed[a][b] += result.confusion[a][b];
    for (int a = 0; a < input.classes; ++a)
        for (int b = 0; b < input.classes; ++b)
            if (a != b && summed[a][b] > 0)
                pairs.push_back({a, b, summed[a][b]});
    std::sort(pairs.begin(), pairs.end(), [](const Pair &a, const Pair &b) {
        return a.count != b.count
                   ? a.count > b.count
                   : std::tie(a.actual, a.predicted) < std::tie(b.actual, b.predicted);
    });
    out.push_back("confused_pairs");
    for (int i = 0; i < std::min(5, int(pairs.size())); ++i)
        line(out, pairs[i].actual, " as ", pairs[i].predicted, " count ", pairs[i].count);
    out.push_back("");
    line(out, "saliency ", top.definition.name);
    out.push_back(class_heading("classes", input.classes));
    const int pixels = input.width * input.height;
    std::vector<Field> saliency(input.classes, Field(pixels));
    Ids class_counts(input.classes);
    for (int i = 0; i < count; ++i) {
        const int label = input.test[i].label;
        ++class_counts[label];
        const Field gradient = backward(network, top.weights, top.test.records[i]).input;
        for (int p = 0; p < pixels; ++p)
            saliency[label][p] += std::abs(gradient[p]);
    }
    std::vector<Ids> levels(input.classes, Ids(pixels));
    for (int k = 0; k < input.classes; ++k) {
        if (class_counts[k])
            for (double &value : saliency[k])
                value /= class_counts[k];
        const double maximum = *std::max_element(saliency[k].begin(), saliency[k].end());
        if (class_counts[k] && maximum > 0)
            for (int p = 0; p < pixels; ++p)
                levels[k][p] = std::min(9, int(std::floor(10 * saliency[k][p] / maximum)));
    }
    const Lines maps = level_maps(levels, input.width, input.height);
    out.insert(out.end(), maps.begin(), maps.end());
    out.push_back("");
    line(out, "hardest_training_examples ", top.definition.name);
    const Evaluated train = evaluate(network, top.weights, training, true);
    Ids hardest(training.size());
    std::iota(hardest.begin(), hardest.end(), 0);
    std::sort(hardest.begin(), hardest.end(), [&](int a, int b) {
        const double x = train.records[a].loss, y = train.records[b].loss;
        return x != y ? x > y : a < b;
    });
    for (int i = 0; i < std::min(5, int(hardest.size())); ++i) {
        const int index = hardest[i];
        line(out, training[index].id, " label ", training[index].label, " predicted ",
             train.predictions[index], " loss ", real(train.records[index].loss, 6));
    }
    out.push_back("");
    line(out, "misclassified_examples ", top.definition.name);
    for (int i = 0; i < count; ++i)
        if (top.test.predictions[i] != input.test[i].label) {
            const Image &image = input.test[i];
            const int chosen = top.test.predictions[i];
            std::string runs;
            for (const Result &result : results)
                runs += " " + std::to_string(result.test.predictions[i]);
            line(out, image.id, " label ", image.label, " predicted ", chosen, " confidence ",
                 real(top.test.records[i].scores[chosen], 4), " true_score ",
                 real(top.test.records[i].scores[image.label], 4), " runs", runs, " ensemble ",
                 ensemble[i]);
            int nearest = 0, distance = pixels + 1;
            for (int j = 0; j < int(input.train.size()); ++j) {
                int d = 0;
                for (int p = 0; p < pixels; ++p)
                    d += image.pixels[p] != input.train[j].pixels[p];
                if (d < distance) {
                    distance = d;
                    nearest = j;
                }
            }
            line(out, "nearest ", input.train[nearest].id, " label ", input.train[nearest].label,
                 " distance ", distance);
            const Lines shown = image_lines(image, input.width, input.height);
            out.insert(out.end(), shown.begin(), shown.end());
        }
    return out;
}
int main() {
    const Input input = load();
    const int validation_count = int(input.train.size()) / 5,
              training_count = int(input.train.size()) - validation_count;
    const std::vector<Image> training(input.train.begin(), input.train.begin() + training_count),
        validation(input.train.begin() + training_count, input.train.end());
    const Lines check = gradient_check(input, training);
    const std::vector<Noise> noise = noisy(input);
    std::vector<Result> results;
    for (const Run &run : input.params.runs)
        results.push_back(train_run(input, training, validation, run));
    Lines log{"run,epoch,lr,grad_norm,train_loss,train_acc,val_loss,val_acc,improved"},
        predictions{"run,id,label,predicted,confidence"};
    for (const Result &result : results) {
        for (const Epoch &epoch : result.epochs)
            line(log, result.definition.name, ",", epoch.number, ",", real(epoch.eta, 6), ",",
                 real(epoch.magnitude, 4), ",", real(epoch.train_loss, 6), ",",
                 ratio(epoch.train_correct, training_count), ",", real(epoch.val_loss, 6), ",",
                 ratio(epoch.val_correct, validation_count), ",", epoch.improved ? 1 : 0);
        for (int i = 0; i < int(input.test.size()); ++i) {
            const int chosen = result.test.predictions[i];
            line(predictions, result.definition.name, ",", input.test[i].id, ",",
                 input.test[i].label, ",", chosen, ",",
                 real(result.test.records[i].scores[chosen], 4));
        }
    }
    Lines evaluation = data_summary(input, training, validation);
    evaluation.push_back("");
    for (const Result &result : results) {
        const Lines report = run_report(input, training, validation, result, noise);
        evaluation.insert(evaluation.end(), report.begin(), report.end());
        evaluation.push_back("");
    }
    const Lines compared = comparison(input, training, results, noise);
    evaluation.insert(evaluation.end(), compared.begin(), compared.end());
    save("gradient_check.txt", check);
    save("training_log.csv", log);
    save("final_weights.txt", final_weights(input, results));
    save("predictions.csv", predictions);
    save("evaluation.txt", evaluation);
}
