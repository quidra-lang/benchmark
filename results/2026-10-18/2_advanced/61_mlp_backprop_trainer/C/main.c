#include "trainer.h"
typedef struct {
    double loss;
    int correct, predictions[200];
    Forward *records;
} Evaluated;
static Evaluated evaluate(const Network *network, const double *weights, const Image *images,
                          int count, bool retain) {
    Evaluated out = {0};
    if (retain)
        out.records = allocate((size_t)count, sizeof(Forward));
    Forward record;
    for (int i = 0; i < count; ++i) {
        forward(network, weights, &images[i], &record);
        int chosen = prediction(record.scores, network->classes);
        out.loss += record.loss;
        out.correct += chosen == images[i].label;
        out.predictions[i] = chosen;
        if (retain)
            out.records[i] = record;
    }
    out.loss /= count;
    return out;
}
static void mean_gradient(const Network *network, const double *weights, const Image *images,
                          const int *order, int first, int last, double *gradient) {
    memset(gradient, 0, (size_t)network->param_count * sizeof(double));
    Forward record;
    Backward value;
    for (int i = first; i < last; ++i) {
        forward(network, weights, &images[order[i]], &record);
        backward(network, weights, &record, &value);
        for (int p = 0; p < network->param_count; ++p)
            gradient[p] += value.parameters[p];
    }
    for (int p = 0; p < network->param_count; ++p)
        gradient[p] /= last - first;
}
static double batch_loss(const Network *network, const double *weights, const Image *images,
                         const int *batch, int count) {
    double loss = 0;
    Forward record;
    for (int i = 0; i < count; ++i) {
        forward(network, weights, &images[batch[i]], &record);
        loss += record.loss;
    }
    return loss / count;
}
static Lines gradient_check(const Input *input, int training_count) {
    Lines out = {0};
    for (int index = 0; index < input->network_count; ++index) {
        if (index)
            line(&out, "");
        const Network *network = &input->networks[index];
        Random random = {input->params.seed};
        int order[200];
        for (int i = 0; i < training_count; ++i)
            order[i] = i;
        shuffle(&random, order, training_count);
        int count = input->params.batch < training_count ? input->params.batch : training_count;
        double analytic[1066], weights[1066];
        mean_gradient(network, network->initial, input->train, order, 0, count, analytic);
        memcpy(weights, network->initial, (size_t)network->param_count * sizeof(double));
        int counts[3][2] = {0}, checked = 0;
        bool passed = true;
        for (int p = 0; p < network->param_count; p += input->params.stride) {
            double original = weights[p], h = 0.00001;
            weights[p] = original + h;
            double plus = batch_loss(network, weights, input->train, order, count);
            weights[p] = original - h;
            double minus = batch_loss(network, weights, input->train, order, count);
            weights[p] = original;
            double numeric = (plus - minus) / (2 * h),
                   error = fabs(analytic[p] - numeric) / fmax(1, fabs(analytic[p]) + fabs(numeric));
            passed = passed && error < 0.000001;
            ++checked;
            for (int l = 0; l < network->layer_count; ++l) {
                const Layer *layer = &network->layers[l];
                if (p >= layer->weights && p < layer->biases)
                    ++counts[l][0];
                else if (p >= layer->biases && p < layer->biases + layer->units)
                    ++counts[l][1];
            }
        }
        line(&out, "network %s", network->name);
        line(&out, "parameters %d", network->param_count);
        char *ids = "batch";
        for (int i = 0; i < count; ++i)
            ids = joined(ids, format(" %s", input->train[order[i]].id));
        line(&out, "%s", ids);
        for (int l = 0; l < network->layer_count; ++l)
            line(&out, "layer %d weights %d biases %d", l + 1, counts[l][0], counts[l][1]);
        line(&out, "checked %d", checked);
        line(&out, "result %s", passed ? "PASS" : "FAIL");
    }
    return out;
}
typedef struct {
    int number;
    double eta, magnitude, train_loss, val_loss;
    int train_correct, val_correct;
    bool improved, correct[200];
} Epoch;
typedef struct {
    Run definition;
    double weights[1066];
    Epoch epochs[99];
    int epoch_count, best_epoch, best_correct, updates;
    double best_loss;
    const char *stop;
    Evaluated test;
    int confusion[10][10];
} Result;
static Result *train_run(const Input *input, int training_count, int validation_count,
                         Run definition) {
    const Network *network = &input->networks[definition.network];
    Result *out = allocate(1, sizeof(Result));
    out->definition = definition;
    double weights[1066], gradient[1066];
    memcpy(weights, network->initial, (size_t)network->param_count * sizeof(double));
    Optimizer optimizer;
    optimizer_init(&optimizer);
    Random random = {input->params.seed};
    int order[200];
    for (int i = 0; i < training_count; ++i)
        order[i] = i;
    int wait = 0;
    for (int epoch = 1; epoch <= input->params.epochs; ++epoch) {
        double eta = learning_rate(&definition, &input->params, epoch), magnitude = 0;
        int batches = 0;
        shuffle(&random, order, training_count);
        for (int first = 0; first < training_count; first += input->params.batch) {
            int last = first + input->params.batch < training_count ? first + input->params.batch
                                                                    : training_count;
            mean_gradient(network, weights, input->train, order, first, last, gradient);
            for (int p = 0; p < network->param_count; ++p)
                if (network->is_weight[p])
                    gradient[p] = gradient[p] + definition.decay * weights[p];
            double squared = 0;
            for (int p = 0; p < network->param_count; ++p)
                squared += gradient[p] * gradient[p];
            magnitude += sqrt(squared);
            ++batches;
            update(&optimizer, weights, gradient, network->param_count, &definition, eta);
            ++out->updates;
        }
        Evaluated training = evaluate(network, weights, input->train, training_count, false),
                  validation = evaluate(network, weights, input->train + training_count,
                                        validation_count, false);
        bool improved = epoch == 1 || validation.loss < out->best_loss;
        Epoch *record = &out->epochs[out->epoch_count++];
        record->number = epoch;
        record->eta = eta;
        record->magnitude = magnitude / batches;
        record->train_loss = training.loss;
        record->val_loss = validation.loss;
        record->train_correct = training.correct;
        record->val_correct = validation.correct;
        record->improved = improved;
        for (int i = 0; i < training_count; ++i)
            record->correct[i] = training.predictions[i] == input->train[i].label;
        if (improved) {
            out->best_loss = validation.loss;
            out->best_epoch = epoch;
            out->best_correct = validation.correct;
            memcpy(out->weights, weights, (size_t)network->param_count * sizeof(double));
            wait = 0;
        } else
            ++wait;
        if (wait >= input->params.patience) {
            out->stop = "early";
            break;
        }
        if (epoch == input->params.epochs)
            out->stop = "max_epochs";
    }
    out->test = evaluate(network, out->weights, input->test, input->test_count, true);
    confusion(input->test, out->test.predictions, input->test_count, input->classes,
              out->confusion);
    return out;
}
typedef struct {
    int rate, flipped;
    Image images[200];
} Noise;
static Noise *noisy(const Input *input) {
    Noise *out = allocate((size_t)input->params.noise_count, sizeof(Noise));
    int pixels = input->width * input->height;
    for (int n = 0; n < input->params.noise_count; ++n) {
        Noise *item = &out[n];
        item->rate = input->params.noise[n];
        memcpy(item->images, input->test, (size_t)input->test_count * sizeof(Image));
        Random random = {input->params.seed};
        for (int i = 0; i < input->test_count; ++i)
            for (int p = 0; p < pixels; ++p)
                if (random_draw(&random) % 100 < item->rate) {
                    item->images[i].input[p] = 1 - item->images[i].input[p];
                    item->images[i].pixels[p] = item->images[i].pixels[p] == '1' ? '0' : '1';
                    ++item->flipped;
                }
    }
    return out;
}
static char *class_heading(const char *prefix, int count) {
    char *out = (char *)prefix;
    for (int k = 0; k < count; ++k)
        out = joined(out, format(" %d", k));
    return out;
}
static Lines data_summary(const Input *input, int training_count, int validation_count) {
    Lines out = {0};
    line(&out, "data");
    int pixels = input->width * input->height;
    line(&out, "train %d validation %d test %d pixels %d", training_count, validation_count,
         input->test_count, pixels);
    int training[10] = {0}, validation[10] = {0}, testing[10] = {0}, ink[10] = {0},
        sums[10][64] = {0}, levels[10][64] = {0};
    for (int i = 0; i < training_count; ++i) {
        const Image *image = &input->train[i];
        ++training[image->label];
        for (int p = 0; p < pixels; ++p) {
            int value = image->pixels[p] == '1';
            ink[image->label] += value;
            sums[image->label][p] += value;
        }
    }
    for (int i = training_count; i < input->train_count; ++i)
        ++validation[input->train[i].label];
    for (int i = 0; i < input->test_count; ++i)
        ++testing[input->test[i].label];
    for (int k = 0; k < input->classes; ++k) {
        line(&out, "class %d train %d validation %d test %d ink %s", k, training[k], validation[k],
             testing[k], ratio(ink[k], training[k]));
        for (int p = 0; p < pixels; ++p) {
            int value = training[k] ? 10 * sums[k][p] / training[k] : 0;
            levels[k][p] = value > 9 ? 9 : value;
        }
    }
    line(&out, "%s", class_heading("mean_images", input->classes));
    level_maps(&out, levels, input->classes, input->width, input->height);
    return out;
}
static const double *prune_weights;
static int compare_weight(const void *a, const void *b) {
    int x = *(const int *)a, y = *(const int *)b;
    double first = fabs(prune_weights[x]), second = fabs(prune_weights[y]);
    return first != second ? (first < second ? -1 : 1) : x - y;
}
static Lines run_report(const Input *input, int training_count, int validation_count,
                        const Result *result, const Noise *noise) {
    Lines out = {0};
    const Run *run = &result->definition;
    const Network *network = &input->networks[run->network];
    int count = input->test_count;
    line(&out, "run %s network %s optimizer %s", run->name, network->name, run->optimizer);
    line(&out, "epochs %d best_epoch %d stop %s updates %d", result->epoch_count,
         result->best_epoch, result->stop, result->updates);
    line(&out, "best_val_loss %s best_val_acc %s correct %d/%d", real(result->best_loss, 6),
         ratio(result->best_correct, validation_count), result->best_correct, validation_count);
    line(&out, "test_loss %s test_acc %s correct %d/%d", real(result->test.loss, 6),
         ratio(result->test.correct, count), result->test.correct, count);
    int top2 = 0, correct_count = 0, wrong_count = 0;
    double correct_confidence = 0, wrong_confidence = 0;
    for (int i = 0; i < count; ++i) {
        int chosen = result->test.predictions[i];
        const Forward *record = &result->test.records[i];
        bool correct = chosen == input->test[i].label;
        top2 +=
            correct || second_class(record->scores, input->classes, chosen) == input->test[i].label;
        if (correct) {
            ++correct_count;
            correct_confidence += record->scores[chosen];
        } else {
            ++wrong_count;
            wrong_confidence += record->scores[chosen];
        }
    }
    line(&out, "top2_acc %s correct %d/%d", ratio(top2, count), top2, count);
    line(&out, "confidence correct %s wrong %s",
         correct_count ? real(correct_confidence / correct_count, 4) : "-",
         wrong_count ? real(wrong_confidence / wrong_count, 4) : "-");
    int forgetting = 0, forgotten = 0, never = 0;
    for (int i = 0; i < training_count; ++i) {
        int events = 0;
        bool learned = false;
        for (int epoch = 0; epoch < result->epoch_count; ++epoch) {
            bool correct = result->epochs[epoch].correct[i];
            learned = learned || correct;
            if (epoch > 0 && result->epochs[epoch - 1].correct[i] && !correct)
                ++events;
        }
        forgetting += events;
        forgotten += events > 0;
        never += !learned;
    }
    line(&out, "forgetting events %d rows %d never_learned %d", forgetting, forgotten, never);
    char *norms = "weight_norms", *changes = "weight_changes";
    for (int l = 0; l < network->layer_count; ++l) {
        Layer layer = network->layers[l];
        double norm = 0, change = 0;
        for (int p = layer.weights; p < layer.biases; ++p) {
            norm += result->weights[p] * result->weights[p];
            double difference = result->weights[p] - network->initial[p];
            change += difference * difference;
        }
        norms = joined(norms, format(" %s", real(sqrt(norm), 4)));
        changes = joined(changes, format(" %s", real(sqrt(change), 4)));
    }
    line(&out, "%s", norms);
    line(&out, "%s", changes);
    line(&out, "curve");
    double maximum = 0;
    for (int i = 0; i < result->epoch_count; ++i) {
        Epoch epoch = result->epochs[i];
        if (epoch.train_loss > maximum)
            maximum = epoch.train_loss;
        if (epoch.val_loss > maximum)
            maximum = epoch.val_loss;
    }
    for (int i = 0; i < result->epoch_count; ++i) {
        Epoch epoch = result->epochs[i];
        char cells[41];
        memset(cells, ' ', 40);
        cells[40] = '\0';
        int training = (int)floor(39 * epoch.train_loss / maximum + 0.5),
            validation = (int)floor(39 * epoch.val_loss / maximum + 0.5);
        cells[training] = 't';
        cells[validation] = training == validation ? '*' : 'v';
        line(&out, "%2d |%s|%s", epoch.number, cells,
             epoch.number == result->best_epoch ? " best" : "");
    }
    line(&out, "confusion");
    for (int k = 0; k < input->classes; ++k) {
        char *row = format("%d:", k);
        for (int j = 0; j < input->classes; ++j)
            row = joined(row, format(" %d", result->confusion[k][j]));
        line(&out, "%s", row);
    }
    for (int k = 0; k < input->classes; ++k) {
        ClassStats stats = class_stats(result->confusion, k, input->classes);
        line(&out, "class %d support %d predicted %d precision %s recall %s f1 %s", k,
             stats.support, stats.predicted, ratio(stats.true_positive, stats.predicted),
             ratio(stats.true_positive, stats.support),
             ratio(2 * stats.true_positive, stats.support + stats.predicted));
    }
    line(&out, "calibration");
    int bin_counts[10] = {0}, bin_correct[10] = {0};
    double bin_sums[10] = {0};
    for (int i = 0; i < count; ++i) {
        int chosen = result->test.predictions[i];
        double confidence = result->test.records[i].scores[chosen];
        int bin = (int)floor(confidence * input->params.bins);
        if (bin >= input->params.bins)
            bin = input->params.bins - 1;
        ++bin_counts[bin];
        bin_correct[bin] += chosen == input->test[i].label;
        bin_sums[bin] += confidence;
    }
    double ece = 0;
    for (int bin = 0; bin < input->params.bins; ++bin) {
        int n = bin_counts[bin];
        line(&out, "bin %d %s %s count %d accuracy %s confidence %s", bin + 1,
             real((double)bin / input->params.bins, 2),
             real((double)(bin + 1) / input->params.bins, 2), n, ratio(bin_correct[bin], n),
             n ? real(bin_sums[bin] / n, 4) : "-");
        if (n)
            ece += ((double)n / count) * fabs((double)bin_correct[bin] / n - bin_sums[bin] / n);
    }
    line(&out, "ece %s", real(ece, 4));
    int class_counts[10] = {0};
    for (int i = 0; i < count; ++i)
        ++class_counts[input->test[i].label];
    for (int l = 0; l < network->layer_count - 1; ++l) {
        const Layer *layer = &network->layers[l];
        line(&out, "hidden %d %s units %d", l + 1, layer->function, layer->units);
        double means[10][12] = {0};
        int zeros[12] = {0};
        for (int i = 0; i < count; ++i)
            for (int j = 0; j < layer->units; ++j) {
                double value = result->test.records[i].activations[l + 1][j];
                means[input->test[i].label][j] += value;
                zeros[j] += value == 0;
            }
        for (int k = 0; k < input->classes; ++k) {
            char *row = format("class %d mean", k);
            if (!class_counts[k])
                row = joined(row, " -");
            else
                for (int j = 0; j < layer->units; ++j) {
                    means[k][j] /= class_counts[k];
                    row = joined(row, format(" %s", real(means[k][j], 4)));
                }
            line(&out, "%s", row);
        }
        char *preferred = "preferred";
        for (int j = 0; j < layer->units; ++j) {
            int best = -1;
            for (int k = 0; k < input->classes; ++k)
                if (class_counts[k] && (best < 0 || means[k][j] > means[best][j]))
                    best = k;
            preferred = joined(preferred, format(" %d", best));
        }
        line(&out, "%s", preferred);
        if (strcmp(layer->function, "RELU") == 0) {
            char *row = "zero_counts";
            for (int j = 0; j < layer->units; ++j)
                row = joined(row, format(" %d", zeros[j]));
            line(&out, "%s", row);
        }
    }
    line(&out, "pruning");
    int weights[1032], weight_count = 0;
    for (int p = 0; p < network->param_count; ++p)
        if (network->is_weight[p])
            weights[weight_count++] = p;
    prune_weights = result->weights;
    qsort(weights, (size_t)weight_count, sizeof(int), compare_weight);
    double pruned[1066];
    for (int q = 0; q < input->params.prune_count; ++q) {
        int fraction = input->params.prune[q], removed = fraction * network->weight_count / 100;
        memcpy(pruned, result->weights, (size_t)network->param_count * sizeof(double));
        for (int i = 0; i < removed; ++i)
            pruned[weights[i]] = 0;
        Evaluated value = evaluate(network, pruned, input->test, count, false);
        line(&out, "prune %d removed %d correct %d test_acc %s test_loss %s", fraction, removed,
             value.correct, ratio(value.correct, count), real(value.loss, 6));
    }
    line(&out, "noise");
    for (int i = 0; i < input->params.noise_count; ++i) {
        int correct = evaluate(network, result->weights, noise[i].images, count, false).correct;
        line(&out, "noise %d correct %d test_acc %s", noise[i].rate, correct,
             ratio(correct, count));
    }
    char *missed = format("misclassified %d", count - result->test.correct);
    for (int i = 0; i < count; ++i)
        if (result->test.predictions[i] != input->test[i].label)
            missed = joined(missed, format(" %s", input->test[i].id));
    line(&out, "%s", missed);
    return out;
}
static Lines final_weights(const Input *input, Result *const *results) {
    Lines out = {0};
    for (int index = 0; index < input->params.run_count; ++index) {
        const Result *result = results[index];
        if (index)
            line(&out, "");
        const Network *network = &input->networks[result->definition.network];
        line(&out, "RUN %s NETWORK %s EPOCH %d", result->definition.name, network->name,
             result->best_epoch);
        for (int l = 0; l < network->layer_count; ++l) {
            const Layer *layer = &network->layers[l];
            line(&out, "LAYER %d %d %d", l + 1, layer->units, layer->inputs);
            for (int j = 0; j < layer->units; ++j) {
                char *row = "W";
                for (int i = 0; i < layer->inputs; ++i)
                    row = joined(
                        row,
                        format(" %s",
                               real(result->weights[layer->weights + j * layer->inputs + i], 4)));
                line(&out, "%s", row);
            }
            char *row = "B";
            for (int j = 0; j < layer->units; ++j)
                row = joined(row, format(" %s", real(result->weights[layer->biases + j], 4)));
            line(&out, "%s", row);
        }
    }
    return out;
}
static Result *const *sort_results;
static int compare_run(const void *a, const void *b) {
    int i = *(const int *)a, j = *(const int *)b;
    const Result *x = sort_results[i], *y = sort_results[j];
    if (x->test.correct != y->test.correct)
        return x->test.correct > y->test.correct ? -1 : 1;
    if (x->best_loss != y->best_loss)
        return x->best_loss < y->best_loss ? -1 : 1;
    return i - j;
}
typedef struct {
    int actual, predicted, count;
} Pair;
static int compare_pair(const void *a, const void *b) {
    const Pair *x = a, *y = b;
    if (x->count != y->count)
        return x->count > y->count ? -1 : 1;
    return x->actual != y->actual ? x->actual - y->actual : x->predicted - y->predicted;
}
static const Evaluated *hardest_values;
static int compare_hardest(const void *a, const void *b) {
    int x = *(const int *)a, y = *(const int *)b;
    double first = hardest_values->records[x].loss, second = hardest_values->records[y].loss;
    return first != second ? (first > second ? -1 : 1) : x - y;
}
static Lines comparison(const Input *input, int training_count, Result *const *results,
                        const Noise *noise) {
    Lines out = {0};
    line(&out, "comparison");
    int ranking[6], run_count = input->params.run_count;
    for (int i = 0; i < run_count; ++i)
        ranking[i] = i;
    sort_results = results;
    qsort(ranking, (size_t)run_count, sizeof(int), compare_run);
    int count = input->test_count, top_index = ranking[0];
    const Result *top = results[top_index];
    const Network *network = &input->networks[top->definition.network];
    for (int rank = 0; rank < run_count; ++rank) {
        const Result *result = results[ranking[rank]];
        line(
            &out,
            "rank %d %s correct %d test_acc %s best_val_loss %s test_loss %s best_epoch %d epochs %d updates %d",
            rank + 1, result->definition.name, result->test.correct,
            ratio(result->test.correct, count), real(result->best_loss, 6),
            real(result->test.loss, 6), result->best_epoch, result->epoch_count, result->updates);
    }
    line(&out, "agreement");
    for (int a = 0; a < run_count; ++a) {
        char *row = results[a]->definition.name;
        for (int b = 0; b < run_count; ++b) {
            int agreement = 0;
            for (int i = 0; i < count; ++i)
                agreement += results[a]->test.predictions[i] == results[b]->test.predictions[i];
            row = joined(row, format(" %d", agreement));
        }
        line(&out, "%s", row);
    }
    line(&out, "mcnemar %s", top->definition.name);
    for (int rank = 0; rank < run_count; ++rank) {
        int index = ranking[rank];
        if (index == top_index)
            continue;
        const Result *other = results[index];
        int b = 0, c = 0;
        for (int i = 0; i < count; ++i) {
            bool x = top->test.predictions[i] == input->test[i].label,
                 y = other->test.predictions[i] == input->test[i].label;
            b += x && !y;
            c += y && !x;
        }
        int difference = abs(b - c) - 1;
        if (difference < 0)
            difference = 0;
        int64_t numerator = (int64_t)difference * difference, denominator = b + c;
        line(&out, "vs %s b %d c %d chi2 %s significant %s", other->definition.name, b, c,
             denominator ? ratio(numerator, denominator) : "0.0000",
             numerator * 1000 > 3841 * denominator ? "yes" : "no");
    }
    int ensemble[200], correct = 0, fixed = 0, broken = 0;
    for (int i = 0; i < count; ++i) {
        int votes[10] = {0}, maximum = 0, chosen = 0;
        for (int run = 0; run < run_count; ++run)
            ++votes[results[run]->test.predictions[i]];
        for (int k = 0; k < input->classes; ++k)
            if (votes[k] > maximum)
                maximum = votes[k];
        for (int rank = 0; rank < run_count; ++rank)
            if (votes[results[ranking[rank]]->test.predictions[i]] == maximum) {
                chosen = results[ranking[rank]]->test.predictions[i];
                break;
            }
        ensemble[i] = chosen;
        bool good = chosen == input->test[i].label,
             top_good = top->test.predictions[i] == input->test[i].label;
        correct += good;
        fixed += good && !top_good;
        broken += top_good && !good;
    }
    line(&out, "ensemble correct %d/%d test_acc %s fixed %d broken %d", correct, count,
         ratio(correct, count), fixed, broken);
    int soft[6], soft_count = 0;
    for (int run = 0; run < run_count; ++run) {
        const Network *net = &input->networks[results[run]->definition.network];
        if (strcmp(net->layers[net->layer_count - 1].function, "SOFTMAX") == 0)
            soft[soft_count++] = run;
    }
    if (!soft_count)
        line(&out, "soft_ensemble none");
    else {
        int correct = 0;
        for (int i = 0; i < count; ++i) {
            double scores[10] = {0};
            for (int run = 0; run < soft_count; ++run)
                for (int k = 0; k < input->classes; ++k)
                    scores[k] += results[soft[run]]->test.records[i].scores[k];
            for (int k = 0; k < input->classes; ++k)
                scores[k] /= soft_count;
            correct += prediction(scores, input->classes) == input->test[i].label;
        }
        line(&out, "soft_ensemble runs %d correct %d/%d test_acc %s", soft_count, correct, count,
             ratio(correct, count));
    }
    for (int i = 0; i < input->params.noise_count; ++i)
        line(&out, "noise %d flipped %d", noise[i].rate, noise[i].flipped);
    Pair pairs[90];
    int pair_count = 0, summed[10][10] = {0};
    for (int run = 0; run < run_count; ++run)
        for (int a = 0; a < input->classes; ++a)
            for (int b = 0; b < input->classes; ++b)
                summed[a][b] += results[run]->confusion[a][b];
    for (int a = 0; a < input->classes; ++a)
        for (int b = 0; b < input->classes; ++b)
            if (a != b && summed[a][b] > 0)
                pairs[pair_count++] = (Pair){a, b, summed[a][b]};
    qsort(pairs, (size_t)pair_count, sizeof(Pair), compare_pair);
    line(&out, "confused_pairs");
    for (int i = 0; i < pair_count && i < 5; ++i)
        line(&out, "%d as %d count %d", pairs[i].actual, pairs[i].predicted, pairs[i].count);
    line(&out, "");
    line(&out, "saliency %s", top->definition.name);
    line(&out, "%s", class_heading("classes", input->classes));
    int pixels = input->width * input->height, class_counts[10] = {0}, levels[10][64] = {0};
    double saliency[10][64] = {0};
    Backward gradient;
    for (int i = 0; i < count; ++i) {
        int label = input->test[i].label;
        ++class_counts[label];
        backward(network, top->weights, &top->test.records[i], &gradient);
        for (int p = 0; p < pixels; ++p)
            saliency[label][p] += fabs(gradient.input[p]);
    }
    for (int k = 0; k < input->classes; ++k) {
        if (class_counts[k])
            for (int p = 0; p < pixels; ++p)
                saliency[k][p] /= class_counts[k];
        double maximum = saliency[k][0];
        for (int p = 1; p < pixels; ++p)
            if (saliency[k][p] > maximum)
                maximum = saliency[k][p];
        if (class_counts[k] && maximum > 0)
            for (int p = 0; p < pixels; ++p) {
                int value = (int)floor(10 * saliency[k][p] / maximum);
                levels[k][p] = value > 9 ? 9 : value;
            }
    }
    level_maps(&out, levels, input->classes, input->width, input->height);
    line(&out, "");
    line(&out, "hardest_training_examples %s", top->definition.name);
    Evaluated training = evaluate(network, top->weights, input->train, training_count, true);
    int hardest[200];
    for (int i = 0; i < training_count; ++i)
        hardest[i] = i;
    hardest_values = &training;
    qsort(hardest, (size_t)training_count, sizeof(int), compare_hardest);
    for (int i = 0; i < training_count && i < 5; ++i) {
        int index = hardest[i];
        line(&out, "%s label %d predicted %d loss %s", input->train[index].id,
             input->train[index].label, training.predictions[index],
             real(training.records[index].loss, 6));
    }
    line(&out, "");
    line(&out, "misclassified_examples %s", top->definition.name);
    for (int i = 0; i < count; ++i)
        if (top->test.predictions[i] != input->test[i].label) {
            const Image *image = &input->test[i];
            int chosen = top->test.predictions[i];
            char *runs = "";
            for (int run = 0; run < run_count; ++run)
                runs = joined(runs, format(" %d", results[run]->test.predictions[i]));
            line(&out, "%s label %d predicted %d confidence %s true_score %s runs%s ensemble %d",
                 image->id, image->label, chosen, real(top->test.records[i].scores[chosen], 4),
                 real(top->test.records[i].scores[image->label], 4), runs, ensemble[i]);
            int nearest = 0, distance = pixels + 1;
            for (int j = 0; j < input->train_count; ++j) {
                int d = 0;
                for (int p = 0; p < pixels; ++p)
                    d += image->pixels[p] != input->train[j].pixels[p];
                if (d < distance) {
                    distance = d;
                    nearest = j;
                }
            }
            line(&out, "nearest %s label %d distance %d", input->train[nearest].id,
                 input->train[nearest].label, distance);
            image_lines(&out, image, input->width, input->height);
        }
    return out;
}
int main(void) {
    const Input *input = load();
    int validation_count = input->train_count / 5,
        training_count = input->train_count - validation_count;
    Lines check = gradient_check(input, training_count);
    Noise *noise = noisy(input);
    Result *results[6];
    for (int i = 0; i < input->params.run_count; ++i)
        results[i] = train_run(input, training_count, validation_count, input->params.runs[i]);
    Lines log = {0}, predictions = {0};
    line(&log, "run,epoch,lr,grad_norm,train_loss,train_acc,val_loss,val_acc,improved");
    line(&predictions, "run,id,label,predicted,confidence");
    for (int i = 0; i < input->params.run_count; ++i) {
        const Result *result = results[i];
        for (int j = 0; j < result->epoch_count; ++j) {
            Epoch epoch = result->epochs[j];
            line(&log, "%s,%d,%s,%s,%s,%s,%s,%s,%d", result->definition.name, epoch.number,
                 real(epoch.eta, 6), real(epoch.magnitude, 4), real(epoch.train_loss, 6),
                 ratio(epoch.train_correct, training_count), real(epoch.val_loss, 6),
                 ratio(epoch.val_correct, validation_count), epoch.improved ? 1 : 0);
        }
        for (int j = 0; j < input->test_count; ++j) {
            int chosen = result->test.predictions[j];
            line(&predictions, "%s,%s,%d,%d,%s", result->definition.name, input->test[j].id,
                 input->test[j].label, chosen, real(result->test.records[j].scores[chosen], 4));
        }
    }
    Lines evaluation = data_summary(input, training_count, validation_count);
    line(&evaluation, "");
    for (int i = 0; i < input->params.run_count; ++i) {
        Lines report = run_report(input, training_count, validation_count, results[i], noise);
        for (int j = 0; j < report.count; ++j)
            line(&evaluation, "%s", report.data[j]);
        line(&evaluation, "");
    }
    Lines compared = comparison(input, training_count, results, noise);
    for (int i = 0; i < compared.count; ++i)
        line(&evaluation, "%s", compared.data[i]);
    save("gradient_check.txt", check);
    save("training_log.csv", log);
    save("final_weights.txt", final_weights(input, results));
    save("predictions.csv", predictions);
    save("evaluation.txt", evaluation);
    return 0;
}
