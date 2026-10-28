#include "hmm.h"
static char *r(double value) {
    return real(value, 4);
}
static char *ratio(double numerator, I denominator) {
    return denominator ? r(numerator / (double)denominator) : "-";
}
static char *state_string(Path path, const char *alphabet) {
    char *out = allocate(path.count + 1, 1);
    for (int i = 0; i < path.count; ++i)
        out[i] = alphabet[path.data[i]];
    return out;
}
static int index_of(const char *text, char value) {
    const char *found = strchr(text, value);
    return found ? (int)(found - text) : -1;
}
static Params parameters(Rows rows, Model model) {
    Params p = {0};
    p.iterations = atoi(rows.data[0].data[1]);
    p.pseudocount = strtod(rows.data[1].data[1], NULL);
    p.candidate_count = rows.data[2].count - 1;
    p.candidates = allocate(p.candidate_count, sizeof(char *));
    p.smoothing = allocate(p.candidate_count, sizeof(double));
    for (int i = 0; i < p.candidate_count; ++i) {
        p.candidates[i] = rows.data[2].data[i + 1];
        p.smoothing[i] = strtod(p.candidates[i], NULL);
    }
    p.folds = atoi(rows.data[3].data[1]);
    p.min_length = atoi(rows.data[4].data[1]);
    p.max_missing = atoi(rows.data[5].data[1]);
    p.segment_state = index_of(model.states, rows.data[6].data[1][0]);
    p.merge_gap = atoi(rows.data[7].data[1]);
    p.min_segment = atoi(rows.data[8].data[1]);
    p.first_motif = index_of(model.symbols, rows.data[9].data[1][0]);
    p.second_motif = index_of(model.symbols, rows.data[9].data[2][0]);
    p.rich = path_new(rows.data[10].count - 1);
    for (int i = 0; i < p.rich.count; ++i)
        p.rich.data[i] = index_of(model.symbols, rows.data[10].data[i + 1][0]);
    p.min_rich = atoi(rows.data[11].data[1]);
    p.min_motif = atoi(rows.data[12].data[1]);
    p.confidence = strtod(rows.data[13].data[1], NULL);
    p.boundary_tolerance = atoi(rows.data[14].data[1]);
    p.posterior_seed = strtoll(rows.data[15].data[1], NULL, 10);
    p.posterior_samples = atoi(rows.data[16].data[1]);
    p.sample_seed = strtoll(rows.data[17].data[1], NULL, 10);
    p.sample_count = atoi(rows.data[18].data[1]);
    p.sample_length = atoi(rows.data[19].data[1]);
    return p;
}
typedef struct {
    Sequence unlabeled[30], train[30], test[30];
    int unlabeled_count, train_count, test_count, sequence_rejected, labeled_rejected;
    Lines rejected;
} Validated;
static char *parse_observation(const char *raw, Model model, Path *path) {
    *path = path_new((int)strlen(raw));
    for (int i = 0; i < path->count; ++i) {
        char ch = raw[i] >= 'a' && raw[i] <= 'z' ? (char)(raw[i] - 'a' + 'A') : raw[i];
        int symbol = index_of(model.symbols, ch);
        if (ch == model.missing)
            path->data[i] = -1;
        else if (symbol >= 0)
            path->data[i] = symbol;
        else
            return format("invalid symbol %c at position %d", ch, i + 1);
    }
    return NULL;
}
static int missing_count(Path path) {
    int out = 0;
    for (int i = 0; i < path.count; ++i)
        out += path.data[i] < 0;
    return out;
}
static char *final_checks(Path path, const Params *p) {
    if (path.count < p->min_length)
        return format("too short %d", path.count);
    int missing = missing_count(path);
    if (100 * missing > p->max_missing * path.count)
        return format("too many missing %d", missing);
    return NULL;
}
static Validated validate(const Input *input, const Params *p) {
    Validated out = {0};
    for (int i = 0; i < input->sequences.count; ++i) {
        Tokens fields = input->sequences.data[i];
        Sequence sequence = {.name = fields.data[0]};
        char *reason = NULL;
        for (int j = 0; j < i; ++j)
            if (!strcmp(sequence.name, input->sequences.data[j].data[0])) {
                reason = "duplicate name";
                break;
            }
        if (!reason)
            reason = parse_observation(fields.data[1], input->model, &sequence.observation);
        if (!reason)
            reason = final_checks(sequence.observation, p);
        if (!reason)
            out.unlabeled[out.unlabeled_count++] = sequence;
        else {
            ++out.sequence_rejected;
            line(&out.rejected, "REJECT sequences.txt line %d %s %s", i + 1, sequence.name, reason);
        }
    }
    for (int i = 0; i < input->labeled.count; i += 2) {
        Tokens fields = input->labeled.data[i];
        const char *labels = input->labeled.data[i + 1].data[0];
        Sequence sequence = {.name = fields.data[0], .role = fields.data[1]};
        char *reason = NULL;
        for (int j = 0; j < i; j += 2)
            if (!strcmp(sequence.name, input->labeled.data[j].data[0])) {
                reason = "duplicate name";
                break;
            }
        if (!reason)
            reason = parse_observation(fields.data[2], input->model, &sequence.observation);
        if (!reason) {
            sequence.truth = path_new((int)strlen(labels));
            for (int t = 0; t < sequence.truth.count; ++t) {
                int state = index_of(input->model.states, labels[t]);
                if (state < 0) {
                    reason = format("invalid label %c at position %d", labels[t], t + 1);
                    break;
                }
                sequence.truth.data[t] = state;
            }
        }
        if (!reason && strlen(fields.data[2]) != strlen(labels))
            reason = format("length mismatch %zu %zu", strlen(fields.data[2]), strlen(labels));
        if (!reason)
            reason = final_checks(sequence.observation, p);
        if (!reason) {
            if (!strcmp(sequence.role, "TRAIN"))
                out.train[out.train_count++] = sequence;
            else
                out.test[out.test_count++] = sequence;
        } else {
            ++out.labeled_rejected;
            line(&out.rejected, "REJECT labeled.txt line %d %s %s", i + 1, sequence.name, reason);
        }
    }
    return out;
}
static Regions segments(Path path, const Params *p) {
    Regions merged = {.data = allocate(path.count, sizeof(Region))},
            out = {.data = allocate(path.count, sizeof(Region))};
    Runs values = runs(path);
    for (int i = 0; i < values.count; ++i) {
        Run run = values.data[i];
        if (run.state != p->segment_state)
            continue;
        if (merged.count && run.start - merged.data[merged.count - 1].end - 1 <= p->merge_gap)
            merged.data[merged.count - 1].end = run.end;
        else
            merged.data[merged.count++] = (Region){run.start, run.end};
    }
    for (int i = 0; i < merged.count; ++i)
        if (merged.data[i].end - merged.data[i].start + 1 >= p->min_segment)
            out.data[out.count++] = merged.data[i];
    return out;
}
static Regions true_regions(Path path, int state) {
    Regions out = {.data = allocate(path.count, sizeof(Region))};
    Runs values = runs(path);
    for (int i = 0; i < values.count; ++i)
        if (values.data[i].state == state)
            out.data[out.count++] = (Region){values.data[i].start, values.data[i].end};
    return out;
}
typedef struct {
    I observed, rich, motifs, first, second;
    bool island;
} Composition;
static Composition composition(Path observation, Region region, const Params *p) {
    Composition out = {0};
    for (int t = region.start - 1; t < region.end; ++t) {
        int symbol = observation.data[t];
        if (symbol >= 0) {
            ++out.observed;
            for (int i = 0; i < p->rich.count; ++i)
                if (p->rich.data[i] == symbol) {
                    ++out.rich;
                    break;
                }
            out.first += symbol == p->first_motif;
            out.second += symbol == p->second_motif;
        }
        if (t + 1 < region.end && symbol == p->first_motif && observation.data[t + 1] == p->second_motif)
            ++out.motifs;
    }
    out.island = out.first * out.second > 0 && 100 * out.rich >= p->min_rich * out.observed &&
                 100 * out.motifs * out.observed >= p->min_motif * out.first * out.second;
    return out;
}
static void add(MatchCounts *target, MatchCounts value) {
    target->predicted += value.predicted;
    target->truth += value.truth;
    target->matched_predicted += value.matched_predicted;
    target->matched_truth += value.matched_truth;
}
typedef struct {
    Confusion matrix;
    I positions, correct_count;
    MatchCounts regions, boundaries;
    I bins[10], correct_bins[10], record_correct[30];
} Evaluation;
static Evaluation evaluate(Model model, const Sequence *records, int count, const Params *p, int decoder) {
    Evaluation out = {0};
    for (int i = 0; i < count; ++i) {
        void *mark = allocation_mark();
        Sequence sequence = records[i];
        Decoding decoded = decode(model, sequence.observation);
        Path prediction = decoder == 0 ? decoded.viterbi.path : decoded.posterior;
        accumulate(&out.matrix, sequence.truth, prediction);
        I correct_count = correct(sequence.truth, prediction);
        out.positions += prediction.count;
        out.correct_count += correct_count;
        out.record_correct[i] = correct_count;
        add(&out.regions,
            region_counts(segments(prediction, p), true_regions(sequence.truth, p->segment_state)));
        add(&out.boundaries, boundary_counts(prediction, sequence.truth, p->boundary_tolerance));
        if (decoder == 1)
            for (int t = 0; t < prediction.count; ++t) {
                int bin = (int)floor(10 * decoded.confidence[t]);
                if (bin > 9)
                    bin = 9;
                ++out.bins[bin];
                out.correct_bins[bin] += prediction.data[t] == sequence.truth.data[t];
            }
        release_to(mark);
    }
    return out;
}
static Lines evaluation_lines(Model model, Evaluation evaluation, const Sequence *records, int count,
                              const Params *p, int decoder) {
    Lines out = {0};
    line(&out, "EVALUATION %s %s", model.name, decoder == 0 ? "VITERBI" : "POSTERIOR");
    extend(&out, matrix_lines(model, evaluation.matrix));
    extend(&out, metric_lines(model, evaluation.matrix));
    line(&out, "REGIONS %c predicted %" PRId64 " true %" PRId64 " precision %s recall %s",
         model.states[p->segment_state], evaluation.regions.predicted, evaluation.regions.truth,
         fraction(evaluation.regions.matched_predicted, evaluation.regions.predicted),
         fraction(evaluation.regions.matched_truth, evaluation.regions.truth));
    line(&out, "BOUNDARIES predicted %" PRId64 " true %" PRId64 " precision %s recall %s",
         evaluation.boundaries.predicted, evaluation.boundaries.truth,
         fraction(evaluation.boundaries.matched_predicted, evaluation.boundaries.predicted),
         fraction(evaluation.boundaries.matched_truth, evaluation.boundaries.truth));
    if (decoder == 1)
        for (int b = 0; b < 10; ++b)
            if (evaluation.bins[b])
                line(&out, "CALIBRATION 0.%d-%s positions %" PRId64 " correct %" PRId64 " accuracy %s", b,
                     b == 9 ? "1.0" : format("0.%d", b + 1), evaluation.bins[b], evaluation.correct_bins[b],
                     fraction(evaluation.correct_bins[b], evaluation.bins[b]));
    for (int i = 0; i < count; ++i)
        line(&out, "RECORD %s length %d correct %" PRId64, records[i].name, records[i].observation.count,
             evaluation.record_correct[i]);
    return out;
}
static void stationary(Model model, double *out) {
    double matrix[4][5] = {0};
    int k = model.k;
    for (int row = 0; row < k - 1; ++row)
        for (int column = 0; column < k; ++column)
            matrix[row][column] = model.transition[column][row] - (row == column ? 1 : 0);
    for (int column = 0; column < k; ++column)
        matrix[k - 1][column] = 1;
    matrix[k - 1][k] = 1;
    for (int column = 0; column < k; ++column) {
        int pivot = column;
        for (int row = column + 1; row < k; ++row)
            if (fabs(matrix[row][column]) > fabs(matrix[pivot][column]))
                pivot = row;
        for (int j = 0; j <= k; ++j) {
            double swap = matrix[pivot][j];
            matrix[pivot][j] = matrix[column][j];
            matrix[column][j] = swap;
        }
        double value = matrix[column][column];
        for (int j = column; j <= k; ++j)
            matrix[column][j] /= value;
        for (int row = 0; row < k; ++row)
            if (row != column) {
                double factor = matrix[row][column];
                for (int j = column; j <= k; ++j)
                    matrix[row][j] -= factor * matrix[column][j];
            }
    }
    for (int row = 0; row < k; ++row)
        out[row] = matrix[row][k];
}
typedef struct {
    I positions[4], runs[4], total;
} PathStats;
static PathStats path_stats(const Path *paths, int count) {
    PathStats out = {0};
    for (int i = 0; i < count; ++i) {
        Path path = paths[i];
        out.total += path.count;
        for (int j = 0; j < path.count; ++j)
            ++out.positions[path.data[j]];
        void *mark = allocation_mark();
        Runs values = runs(path);
        for (int j = 0; j < values.count; ++j)
            ++out.runs[values.data[j].state];
        release_to(mark);
    }
    return out;
}
static double max_change(Model a, Model b) {
    double out = 0;
    for (int i = 0; i < a.k; ++i) {
        double value = fabs(a.initial[i] - b.initial[i]);
        if (value > out)
            out = value;
        for (int j = 0; j < a.k; ++j) {
            value = fabs(a.transition[i][j] - b.transition[i][j]);
            if (value > out)
                out = value;
        }
        for (int j = 0; j < a.m; ++j) {
            value = fabs(a.emission[i][j] - b.emission[i][j]);
            if (value > out)
                out = value;
        }
    }
    return out;
}
static bool next_permutation(int *values, int count) {
    int i = count - 2;
    while (i >= 0 && values[i] >= values[i + 1])
        --i;
    if (i < 0)
        return false;
    int j = count - 1;
    while (values[j] <= values[i])
        --j;
    int swap = values[i];
    values[i] = values[j];
    values[j] = swap;
    for (int a = i + 1, b = count - 1; a < b; ++a, --b) {
        swap = values[a];
        values[a] = values[b];
        values[b] = swap;
    }
    return true;
}
typedef struct {
    Confusion matrix;
    I correct_count, positions;
    I *fold_records;
    I *fold_positions;
    I *fold_correct;
} CV;
int main(void) {
    mkdir("output", 0777);
    Input input = {0};
    load(&input);
    Params p = parameters(input.parameters, input.model);
    Validated data = validate(&input, &p);
    Path unlabeled[30], heldout[60], test_observations[30];
    Pair train_pairs[30];
    int heldout_count = 0;
    for (int i = 0; i < data.unlabeled_count; ++i)
        unlabeled[i] = data.unlabeled[i].observation;
    for (int i = 0; i < data.train_count; ++i) {
        heldout[heldout_count++] = data.train[i].observation;
        train_pairs[i] = (Pair){data.train[i].observation, data.train[i].truth};
    }
    for (int i = 0; i < data.test_count; ++i) {
        test_observations[i] = data.test[i].observation;
        heldout[heldout_count++] = test_observations[i];
    }
    Model models[4];
    models[0] = input.model;
    models[1] = input.model;
    Lines bw_trace = {0}, vit_trace = {0}, trained = {0}, decodings = {0}, segment_file = {0},
          sample_file = {0}, evaluation_file = {0}, report = {0};
    line(&bw_trace, "iteration,loglik,heldout,change,max_change,status");
    line(&vit_trace, "iteration,logprob,loglik,changed");
    line(&segment_file,
         "sequence,decoder,start,end,length,mean_posterior,support,rich_fraction,motif_ratio,island");
    double likelihood[21], held[21];
    int violations = 0, best_held = 0;
    likelihood[0] = total_loglik(models[1], unlabeled, data.unlabeled_count);
    held[0] = total_loglik(models[1], heldout, heldout_count);
    line(&bw_trace, "0,%s,%s,,,", r(likelihood[0]), r(held[0]));
    for (int iteration = 1; iteration <= p.iterations; ++iteration) {
        Model previous = models[1];
        models[1] = baum_welch(previous, unlabeled, data.unlabeled_count, p.pseudocount);
        likelihood[iteration] = total_loglik(models[1], unlabeled, data.unlabeled_count);
        held[iteration] = total_loglik(models[1], heldout, heldout_count);
        bool violation =
            likelihood[iteration] < likelihood[iteration - 1] - 0.000001 * fabs(likelihood[iteration - 1]);
        violations += violation;
        if (held[iteration] > held[best_held])
            best_held = iteration;
        line(&bw_trace, "%d,%s,%s,%s,%s,%s", iteration, r(likelihood[iteration]), r(held[iteration]),
             r(likelihood[iteration] - likelihood[iteration - 1]), real(max_change(models[1], previous), 6),
             violation ? "violation" : "ok");
    }
    models[2] = input.model;
    Path previous_paths[30];
    double initial_probability = 0;
    for (int i = 0; i < data.unlabeled_count; ++i) {
        Viterbi result = viterbi(models[2], unlabeled[i]);
        previous_paths[i] = result.path;
        initial_probability += result.logprob;
    }
    line(&vit_trace, "0,%s,%s,", r(initial_probability),
         r(total_loglik(models[2], unlabeled, data.unlabeled_count)));
    int vit_iterations = 0;
    bool converged = false;
    for (int iteration = 1; iteration <= p.iterations; ++iteration) {
        Pair current_pairs[30];
        for (int i = 0; i < data.unlabeled_count; ++i)
            current_pairs[i] = (Pair){unlabeled[i], previous_paths[i]};
        models[2] =
            counting(input.model, current_pairs, data.unlabeled_count, p.pseudocount, "VITERBI_TRAINING");
        I changed = 0;
        double probability = 0;
        for (int i = 0; i < data.unlabeled_count; ++i) {
            Viterbi result = viterbi(models[2], unlabeled[i]);
            probability += result.logprob;
            changed += result.path.count - correct(previous_paths[i], result.path);
            previous_paths[i] = result.path;
        }
        line(&vit_trace, "%d,%s,%s,%" PRId64, iteration, r(probability),
             r(total_loglik(models[2], unlabeled, data.unlabeled_count)), changed);
        vit_iterations = iteration;
        converged = changed == 0;
        if (converged)
            break;
    }
    CV *cross_validation = allocate(p.candidate_count, sizeof(CV));
    int selected_candidate = 0;
    for (int candidate = 0; candidate < p.candidate_count; ++candidate) {
        CV *cv = &cross_validation[candidate];
        cv->fold_records = allocate(p.folds, sizeof(I));
        cv->fold_positions = allocate(p.folds, sizeof(I));
        cv->fold_correct = allocate(p.folds, sizeof(I));
        for (int fold = 0; fold < p.folds; ++fold) {
            Pair training[30];
            int training_count = 0;
            for (int i = 0; i < data.train_count; ++i)
                if (i % p.folds != fold)
                    training[training_count++] = train_pairs[i];
            Model model =
                counting(input.model, training, training_count, p.smoothing[candidate], "SUPERVISED");
            for (int i = 0; i < data.train_count; ++i)
                if (i % p.folds == fold) {
                    void *mark = allocation_mark();
                    Sequence sequence = data.train[i];
                    Viterbi decoded = viterbi(model, sequence.observation);
                    I correct_count = correct(sequence.truth, decoded.path);
                    ++cv->fold_records[fold];
                    cv->fold_positions[fold] += sequence.truth.count;
                    cv->fold_correct[fold] += correct_count;
                    cv->positions += sequence.truth.count;
                    cv->correct_count += correct_count;
                    accumulate(&cv->matrix, sequence.truth, decoded.path);
                    release_to(mark);
                }
        }
        if (cv->correct_count > cross_validation[selected_candidate].correct_count)
            selected_candidate = candidate;
    }
    models[3] =
        counting(input.model, train_pairs, data.train_count, p.smoothing[selected_candidate], "SUPERVISED");
    for (int model = 1; model < 4; ++model) {
        if (model > 1)
            line(&trained, "");
        extend(&trained, model_lines(models[model]));
    }
    Evaluation evaluations[4][2];
    for (int model = 0; model < 4; ++model)
        for (int decoder = 0; decoder < 2; ++decoder) {
            evaluations[model][decoder] = evaluate(models[model], data.test, data.test_count, &p, decoder);
            if (evaluation_file.count)
                line(&evaluation_file, "");
            extend(&evaluation_file, evaluation_lines(models[model], evaluations[model][decoder], data.test,
                                                      data.test_count, &p, decoder));
        }
    CV *cv = &cross_validation[selected_candidate];
    line(&evaluation_file, "");
    line(&evaluation_file, "CROSS_VALIDATION folds %d", p.folds);
    for (int candidate = 0; candidate < p.candidate_count; ++candidate)
        line(&evaluation_file, "SMOOTHING %s positions %" PRId64 " correct %" PRId64 " accuracy %s",
             p.candidates[candidate], cross_validation[candidate].positions,
             cross_validation[candidate].correct_count,
             fraction(cross_validation[candidate].correct_count, cross_validation[candidate].positions));
    line(&evaluation_file, "SELECTED %s", p.candidates[selected_candidate]);
    for (int fold = 0; fold < p.folds; ++fold)
        line(&evaluation_file,
             "FOLD %d records %" PRId64 " positions %" PRId64 " correct %" PRId64 " accuracy %s", fold + 1,
             cv->fold_records[fold], cv->fold_positions[fold], cv->fold_correct[fold],
             fraction(cv->fold_correct[fold], cv->fold_positions[fold]));
    extend(&evaluation_file, matrix_lines(input.model, cv->matrix));
    extend(&evaluation_file, metric_lines(input.model, cv->matrix));
    line(&evaluation_file, "");
    line(&evaluation_file, "LEARNING_CURVE");
    I test_positions = evaluations[0][0].positions;
    for (int count = 1; count <= data.train_count; ++count) {
        Model model =
            counting(input.model, train_pairs, count, p.smoothing[selected_candidate], "SUPERVISED");
        I correct_count = 0;
        for (int i = 0; i < data.test_count; ++i) {
            void *mark = allocation_mark();
            correct_count += correct(data.test[i].truth, viterbi(model, data.test[i].observation).path);
            release_to(mark);
        }
        line(&evaluation_file, "RECORDS %d correct %" PRId64 " accuracy %s", count, correct_count,
             fraction(correct_count, test_positions));
    }
    Decoding(*cached)[30] = allocate(4, sizeof(*cached));
    for (int model = 0; model < 4; ++model)
        for (int i = 0; i < data.unlabeled_count; ++i)
            cached[model][i] = decode(models[model], unlabeled[i]);
    Generator posterior_generator = {p.posterior_seed};
    Model bw = models[1];
    for (int index = 0; index < data.unlabeled_count; ++index) {
        Sequence sequence = data.unlabeled[index];
        Decoding decoded = cached[1][index];
        Path samples[100];
        I segment_count = 0;
        for (int sample = 0; sample < p.posterior_samples; ++sample) {
            samples[sample] = posterior_sample(bw, decoded.fb, &posterior_generator);
            segment_count += segments(samples[sample], &p).count;
        }
        I differences = sequence.observation.count - correct(decoded.viterbi.path, decoded.posterior),
          uncertain = 0;
        char *confident = state_string(decoded.posterior, bw.states);
        char *imputed = allocate(sequence.observation.count + 1, 1);
        for (int t = 0; t < sequence.observation.count; ++t) {
            if (decoded.confidence[t] < p.confidence) {
                ++uncertain;
                confident[t] = '.';
            }
            int observed = sequence.observation.data[t];
            if (observed >= 0)
                imputed[t] = bw.symbols[observed];
            else {
                double probabilities[8] = {0};
                for (int symbol = 0; symbol < bw.m; ++symbol)
                    for (int state = 0; state < bw.k; ++state)
                        probabilities[symbol] += decoded.fb.posterior[t][state] * bw.emission[state][symbol];
                char symbol = bw.symbols[maximum(probabilities, bw.m)];
                imputed[t] = (char)(symbol - 'A' + 'a');
            }
        }
        line(&decodings,
             "SEQUENCE %s length %d loglik %s viterbi %s differences %" PRId64 " uncertain %" PRId64
             " expected_segments %s",
             sequence.name, sequence.observation.count, r(decoded.fb.loglik), r(decoded.viterbi.logprob),
             differences, uncertain, ratio((double)segment_count, p.posterior_samples));
        line(&decodings, "VITERBI %s", state_string(decoded.viterbi.path, bw.states));
        line(&decodings, "POSTERIOR %s", state_string(decoded.posterior, bw.states));
        line(&decodings, "CONFIDENT %s", confident);
        line(&decodings, "IMPUTED %s", imputed);
        for (int decoder = 0; decoder < 2; ++decoder) {
            Path path = decoder == 0 ? decoded.viterbi.path : decoded.posterior;
            Regions regions = segments(path, &p);
            for (int i = 0; i < regions.count; ++i) {
                Region region = regions.data[i];
                int length = region.end - region.start + 1;
                double mean = 0;
                for (int t = region.start - 1; t < region.end; ++t)
                    mean += decoded.fb.posterior[t][p.segment_state];
                mean /= length;
                I support = 0;
                for (int sample = 0; sample < p.posterior_samples; ++sample) {
                    int inside = 0;
                    for (int t = region.start - 1; t < region.end; ++t)
                        inside += samples[sample].data[t] == p.segment_state;
                    support += 2 * inside > length;
                }
                Composition result = composition(sequence.observation, region, &p);
                line(&segment_file, "%s,%s,%d,%d,%d,%s,%" PRId64 ",%s,%s,%s", sequence.name,
                     decoder == 0 ? "viterbi" : "posterior", region.start, region.end, length, r(mean),
                     support, ratio((double)result.rich, result.observed),
                     ratio((double)(result.motifs * result.observed), result.first * result.second),
                     result.island ? "yes" : "no");
            }
        }
    }
    Generator sample_generator = {p.sample_seed};
    I viterbi_correct = 0, posterior_correct = 0;
    for (int sample = 1; sample <= p.sample_count; ++sample) {
        Pair generated = synthetic(bw, p.sample_length, &sample_generator);
        Decoding decoded = decode(bw, generated.observation);
        I vc = correct(generated.path, decoded.viterbi.path), pc = correct(generated.path, decoded.posterior);
        viterbi_correct += vc;
        posterior_correct += pc;
        line(&sample_file,
             "SAMPLE %d loglik %s viterbi %s viterbi_correct %" PRId64 " posterior_correct %" PRId64, sample,
             r(decoded.fb.loglik), r(decoded.viterbi.logprob), vc, pc);
        line(&sample_file, "STATES %s", state_string(generated.path, bw.states));
        line(&sample_file, "SYMBOLS %s", state_string(generated.observation, bw.symbols));
        line(&sample_file, "VITERBI %s", state_string(decoded.viterbi.path, bw.states));
        line(&sample_file, "POSTERIOR %s", state_string(decoded.posterior, bw.states));
    }
    I synthetic_positions = p.sample_count * p.sample_length;
    line(&sample_file, "TOTAL positions %" PRId64 " viterbi_accuracy %s posterior_accuracy %s",
         synthetic_positions, fraction(viterbi_correct, synthetic_positions),
         fraction(posterior_correct, synthetic_positions));
    I unlabeled_positions = 0, unlabeled_missing = 0, labeled_positions = 0, labeled_missing = 0,
      symbol_counts[8] = {0};
    for (int i = 0; i < data.unlabeled_count; ++i) {
        Sequence sequence = data.unlabeled[i];
        unlabeled_positions += sequence.observation.count;
        for (int t = 0; t < sequence.observation.count; ++t) {
            int symbol = sequence.observation.data[t];
            if (symbol < 0)
                ++unlabeled_missing;
            else
                ++symbol_counts[symbol];
        }
    }
    for (int i = 0; i < data.train_count; ++i) {
        labeled_positions += data.train[i].observation.count;
        labeled_missing += missing_count(data.train[i].observation);
    }
    for (int i = 0; i < data.test_count; ++i) {
        labeled_positions += data.test[i].observation.count;
        labeled_missing += missing_count(data.test[i].observation);
    }
    line(&report, "INPUT");
    line(&report, "SEQUENCES accepted %d rejected %d positions %" PRId64 " missing %" PRId64,
         data.unlabeled_count, data.sequence_rejected, unlabeled_positions, unlabeled_missing);
    line(&report, "LABELED train %d test %d rejected %d positions %" PRId64 " missing %" PRId64,
         data.train_count, data.test_count, data.labeled_rejected, labeled_positions, labeled_missing);
    extend(&report, data.rejected);
    char *composition_line = "COMPOSITION";
    for (int symbol = 0; symbol < input.model.m; ++symbol)
        composition_line =
            format("%s %c %s", composition_line, input.model.symbols[symbol],
                   ratio((double)symbol_counts[symbol], unlabeled_positions - unlabeled_missing));
    line(&report, "%s", composition_line);
    for (int role = 0; role < 2; ++role) {
        Path truth[30];
        Sequence *records = role == 0 ? data.train : data.test;
        int count = role == 0 ? data.train_count : data.test_count;
        for (int i = 0; i < count; ++i)
            truth[i] = records[i].truth;
        PathStats stats = path_stats(truth, count);
        for (int state = 0; state < input.model.k; ++state)
            line(&report, "TRUTH %s %c occupancy %s mean_run %s", role == 0 ? "TRAIN" : "TEST",
                 input.model.states[state], ratio((double)stats.positions[state], stats.total),
                 ratio((double)stats.positions[state], stats.runs[state]));
    }
    line(&report, "");
    line(
        &report,
        "TRAINING BAUM_WELCH iterations %d initial_loglik %s final_loglik %s violations %d best_heldout_iteration %d",
        p.iterations, r(likelihood[0]), r(likelihood[p.iterations]), violations, best_held);
    line(&report, "TRAINING VITERBI_TRAINING iterations %d converged %s", vit_iterations,
         converged ? "yes" : "no");
    line(&report, "TRAINING SUPERVISED smoothing %s", p.candidates[selected_candidate]);
    I preference[4] = {0};
    for (int index = 0; index < data.unlabeled_count; ++index) {
        int best = 0;
        for (int model = 1; model < 4; ++model)
            if (cached[model][index].fb.loglik > cached[best][index].fb.loglik)
                best = model;
        ++preference[best];
    }
    line(&report,
         "PREFERENCE INITIAL %" PRId64 " BAUM_WELCH %" PRId64 " VITERBI_TRAINING %" PRId64
         " SUPERVISED %" PRId64,
         preference[0], preference[1], preference[2], preference[3]);
    for (int first = 0; first < 4; ++first)
        for (int second = first + 1; second < 4; ++second) {
            I agreement = 0;
            for (int index = 0; index < data.unlabeled_count; ++index)
                agreement += correct(cached[first][index].viterbi.path, cached[second][index].viterbi.path);
            line(&report, "AGREEMENT %s %s %s", models[first].name, models[second].name,
                 fraction(agreement, unlabeled_positions));
        }
    for (int decoder = 0; decoder < 2; ++decoder) {
        int best = 0;
        for (int model = 1; model < 4; ++model)
            if (evaluations[model][decoder].correct_count > evaluations[best][decoder].correct_count)
                best = model;
        line(&report, "BEST %s %s accuracy %s", decoder == 0 ? "VITERBI" : "POSTERIOR", models[best].name,
             fraction(evaluations[best][decoder].correct_count, test_positions));
    }
    for (int model = 0; model < 4; ++model) {
        Model current = models[model];
        double loglik = 0;
        Path paths[30];
        I segment_count = 0, segment_length = 0, islands = 0;
        for (int index = 0; index < data.unlabeled_count; ++index) {
            Decoding decoded = cached[model][index];
            loglik += decoded.fb.loglik;
            paths[index] = decoded.viterbi.path;
            void *mark = allocation_mark();
            Regions regions = segments(decoded.viterbi.path, &p);
            for (int i = 0; i < regions.count; ++i) {
                Region region = regions.data[i];
                ++segment_count;
                segment_length += region.end - region.start + 1;
                islands += composition(unlabeled[index], region, &p).island;
            }
            release_to(mark);
        }
        PathStats stats = path_stats(paths, data.unlabeled_count);
        double phi[4];
        stationary(current, phi);
        Confusion alignment = {0};
        for (int i = 0; i < data.train_count; ++i) {
            void *mark = allocation_mark();
            Sequence sequence = data.train[i];
            accumulate(&alignment, sequence.truth, viterbi(current, sequence.observation).path);
            release_to(mark);
        }
        int permutation[4] = {0, 1, 2, 3}, best_permutation[4] = {0};
        I best_agreement = -1;
        do {
            I agreement = 0;
            for (int state = 0; state < current.k; ++state)
                agreement += alignment.data[permutation[state]][state];
            if (agreement > best_agreement) {
                best_agreement = agreement;
                memcpy(best_permutation, permutation, current.k * sizeof(int));
            }
        } while (next_permutation(permutation, current.k));
        line(&report, "");
        line(&report, "MODEL %s", current.name);
        line(&report, "LOGLIK unlabeled %s per_symbol %s test %s", r(loglik),
             ratio(loglik, unlabeled_positions - unlabeled_missing),
             r(total_loglik(current, test_observations, data.test_count)));
        line(&report, "SEGMENTS count %" PRId64 " mean_length %s islands %" PRId64, segment_count,
             ratio((double)segment_length, segment_count), islands);
        char *mapping = "ALIGNMENT";
        for (int state = 0; state < current.k; ++state)
            mapping =
                format("%s %c=%c", mapping, current.states[state], current.states[best_permutation[state]]);
        I train_positions = 0;
        for (int i = 0; i < data.train_count; ++i)
            train_positions += data.train[i].truth.count;
        line(&report, "%s agreement %s", mapping, fraction(best_agreement, train_positions));
        for (int state = 0; state < current.k; ++state)
            line(&report, "STATE %c stationary %s duration %s occupancy %s mean_run %s",
                 current.states[state], r(phi[state]), r(1 / (1 - current.transition[state][state])),
                 ratio((double)stats.positions[state], stats.total),
                 ratio((double)stats.positions[state], stats.runs[state]));
    }
    save("trained_model.txt", trained);
    save("loglik_trace.csv", bw_trace);
    save("viterbi_trace.csv", vit_trace);
    save("decodings.txt", decodings);
    save("segments.csv", segment_file);
    save("samples.txt", sample_file);
    save("evaluation.txt", evaluation_file);
    save("report.txt", report);
    release_all();
    return 0;
}
