#include "hmm.hpp"
#include <filesystem>
template <typename... T> static void line(Lines &out, const T &...values) {
    std::ostringstream text;
    (text << ... << values);
    out.push_back(text.str());
}
static void extend(Lines &out, const Lines &values) {
    out.insert(out.end(), values.begin(), values.end());
}
static std::string state_string(const Path &path, const std::string &alphabet) {
    std::string out;
    for (int state : path)
        out += alphabet[state];
    return out;
}
static std::string ratio(double numerator, I denominator) {
    return denominator ? real(double(numerator) / denominator) : "-";
}
static Params parameters(const Rows &rows, const Model &model) {
    Params p{};
    auto integer = [&](int index) { return std::stoi(rows[index][1]); };
    p.iterations = integer(0);
    p.pseudocount = std::stod(rows[1][1]);
    for (std::size_t i = 1; i < rows[2].size(); ++i) {
        p.candidates.push_back(rows[2][i]);
        p.smoothing.push_back(std::stod(rows[2][i]));
    }
    p.folds = integer(3);
    p.min_length = integer(4);
    p.max_missing = integer(5);
    p.segment_state = model.states.find(rows[6][1]);
    p.merge_gap = integer(7);
    p.min_segment = integer(8);
    p.first_motif = model.symbols.find(rows[9][1]);
    p.second_motif = model.symbols.find(rows[9][2]);
    for (std::size_t i = 1; i < rows[10].size(); ++i)
        p.rich.push_back(model.symbols.find(rows[10][i]));
    p.min_rich = integer(11);
    p.min_motif = integer(12);
    p.confidence = std::stod(rows[13][1]);
    p.boundary_tolerance = integer(14);
    p.posterior_seed = std::stoll(rows[15][1]);
    p.posterior_samples = integer(16);
    p.sample_seed = std::stoll(rows[17][1]);
    p.sample_count = integer(18);
    p.sample_length = integer(19);
    return p;
}
struct Validated {
    std::vector<Sequence> unlabeled, train, test;
    Lines rejected;
    int sequence_rejected = 0, labeled_rejected = 0;
};
static Validated validate(const Input &input, const Params &p) {
    Validated out;
    auto observations = [&](const std::string &raw, Path &path) {
        for (int i = 0; i < int(raw.size()); ++i) {
            const char ch = raw[i] >= 'a' && raw[i] <= 'z' ? char(raw[i] - 'a' + 'A') : raw[i];
            const auto symbol = input.model.symbols.find(ch);
            if (ch == input.model.missing)
                path.push_back(-1);
            else if (symbol != std::string::npos)
                path.push_back(symbol);
            else
                return "invalid symbol " + std::string(1, ch) + " at position " + std::to_string(i + 1);
        }
        return std::string{};
    };
    auto final_checks = [&](const Path &path) {
        if (path.size() < std::size_t(p.min_length))
            return "too short " + std::to_string(path.size());
        const int missing = std::count(path.begin(), path.end(), -1);
        if (100 * missing > p.max_missing * int(path.size()))
            return "too many missing " + std::to_string(missing);
        return std::string{};
    };
    std::set<std::string> names;
    for (int i = 0; i < int(input.sequences.size()); ++i) {
        const Lines &fields = input.sequences[i];
        Sequence sequence;
        sequence.name = fields[0];
        std::string reason;
        if (!names.insert(sequence.name).second)
            reason = "duplicate name";
        if (reason.empty())
            reason = observations(fields[1], sequence.observation);
        if (reason.empty())
            reason = final_checks(sequence.observation);
        if (reason.empty())
            out.unlabeled.push_back(std::move(sequence));
        else {
            ++out.sequence_rejected;
            line(out.rejected, "REJECT sequences.txt line ", i + 1, " ", sequence.name, " ", reason);
        }
    }
    names.clear();
    for (int i = 0; i < int(input.labeled.size()); i += 2) {
        const Lines &fields = input.labeled[i];
        const std::string &labels = input.labeled[i + 1][0];
        Sequence sequence;
        sequence.name = fields[0];
        sequence.role = fields[1];
        std::string reason;
        if (!names.insert(sequence.name).second)
            reason = "duplicate name";
        if (reason.empty())
            reason = observations(fields[2], sequence.observation);
        if (reason.empty())
            for (int t = 0; t < int(labels.size()); ++t) {
                const auto state = input.model.states.find(labels[t]);
                if (state == std::string::npos) {
                    reason = "invalid label " + std::string(1, labels[t]) + " at position " +
                             std::to_string(t + 1);
                    break;
                }
                sequence.truth.push_back(state);
            }
        if (reason.empty() && fields[2].size() != labels.size())
            reason =
                "length mismatch " + std::to_string(fields[2].size()) + " " + std::to_string(labels.size());
        if (reason.empty())
            reason = final_checks(sequence.observation);
        if (reason.empty())
            (sequence.role == "TRAIN" ? out.train : out.test).push_back(std::move(sequence));
        else {
            ++out.labeled_rejected;
            line(out.rejected, "REJECT labeled.txt line ", i + 1, " ", sequence.name, " ", reason);
        }
    }
    return out;
}
static std::vector<Path> observations(const std::vector<Sequence> &sequences) {
    std::vector<Path> out;
    for (const Sequence &sequence : sequences)
        out.push_back(sequence.observation);
    return out;
}
static std::vector<Pair> pairs(const std::vector<Sequence> &sequences) {
    std::vector<Pair> out;
    for (const Sequence &sequence : sequences)
        out.push_back({sequence.observation, sequence.truth});
    return out;
}
static std::vector<Region> segments(const Path &path, const Params &p) {
    std::vector<Region> merged, out;
    for (const Run &run : runs(path))
        if (run.state == p.segment_state) {
            if (!merged.empty() && run.start - merged.back().end - 1 <= p.merge_gap)
                merged.back().end = run.end;
            else
                merged.push_back({run.start, run.end});
        }
    for (const Region &region : merged)
        if (region.length() >= p.min_segment)
            out.push_back(region);
    return out;
}
static std::vector<Region> true_regions(const Path &path, int state) {
    std::vector<Region> out;
    for (const Run &run : runs(path))
        if (run.state == state)
            out.push_back({run.start, run.end});
    return out;
}
struct Composition {
    I observed = 0, rich = 0, motifs = 0, first = 0, second = 0;
    bool island = false;
};
static Composition composition(const Path &observation, Region region, const Params &p) {
    Composition out;
    for (int t = region.start - 1; t < region.end; ++t) {
        const int symbol = observation[t];
        if (symbol >= 0) {
            ++out.observed;
            out.rich += std::find(p.rich.begin(), p.rich.end(), symbol) != p.rich.end();
            out.first += symbol == p.first_motif;
            out.second += symbol == p.second_motif;
        }
        if (t + 1 < region.end && symbol == p.first_motif && observation[t + 1] == p.second_motif)
            ++out.motifs;
    }
    out.island = out.first * out.second > 0 && 100 * out.rich >= p.min_rich * out.observed &&
                 100 * out.motifs * out.observed >= p.min_motif * out.first * out.second;
    return out;
}
static void add(MatchCounts &target, MatchCounts value) {
    target.predicted += value.predicted;
    target.truth += value.truth;
    target.matched_predicted += value.matched_predicted;
    target.matched_truth += value.matched_truth;
}
struct Evaluation {
    Confusion matrix{};
    I positions = 0, correct_count = 0;
    MatchCounts regions, boundaries;
    std::array<I, 10> bins{}, correct_bins{};
    std::vector<I> record_correct;
};
static Evaluation evaluate(const Model &model, const std::vector<Sequence> &records, const Params &p,
                           int decoder) {
    Evaluation out;
    for (const Sequence &sequence : records) {
        const Decoding decoded = decode(model, sequence.observation);
        const Path &prediction = decoder == 0 ? decoded.viterbi.path : decoded.posterior;
        accumulate(out.matrix, sequence.truth, prediction);
        const I correct_count = correct(sequence.truth, prediction);
        out.positions += prediction.size();
        out.correct_count += correct_count;
        out.record_correct.push_back(correct_count);
        add(out.regions,
            region_counts(segments(prediction, p), true_regions(sequence.truth, p.segment_state)));
        add(out.boundaries, boundary_counts(prediction, sequence.truth, p.boundary_tolerance));
        if (decoder == 1)
            for (int t = 0; t < int(prediction.size()); ++t) {
                const int bin = std::min(9, int(std::floor(10 * decoded.confidence[t])));
                ++out.bins[bin];
                out.correct_bins[bin] += prediction[t] == sequence.truth[t];
            }
    }
    return out;
}
static Lines evaluation_lines(const Model &model, const Evaluation &evaluation,
                              const std::vector<Sequence> &records, const Params &p, int decoder) {
    Lines out;
    line(out, "EVALUATION ", model.name, " ", decoder == 0 ? "VITERBI" : "POSTERIOR");
    extend(out, matrix_lines(model, evaluation.matrix));
    extend(out, metric_lines(model, evaluation.matrix));
    line(out, "REGIONS ", model.states[p.segment_state], " predicted ", evaluation.regions.predicted,
         " true ", evaluation.regions.truth, " precision ",
         fraction(evaluation.regions.matched_predicted, evaluation.regions.predicted), " recall ",
         fraction(evaluation.regions.matched_truth, evaluation.regions.truth));
    line(out, "BOUNDARIES predicted ", evaluation.boundaries.predicted, " true ", evaluation.boundaries.truth,
         " precision ", fraction(evaluation.boundaries.matched_predicted, evaluation.boundaries.predicted),
         " recall ", fraction(evaluation.boundaries.matched_truth, evaluation.boundaries.truth));
    if (decoder == 1)
        for (int b = 0; b < 10; ++b)
            if (evaluation.bins[b])
                line(out, "CALIBRATION 0.", b, "-", b == 9 ? "1.0" : "0." + std::to_string(b + 1),
                     " positions ", evaluation.bins[b], " correct ", evaluation.correct_bins[b], " accuracy ",
                     fraction(evaluation.correct_bins[b], evaluation.bins[b]));
    for (int i = 0; i < int(records.size()); ++i)
        line(out, "RECORD ", records[i].name, " length ", records[i].observation.size(), " correct ",
             evaluation.record_correct[i]);
    return out;
}
static StateValues stationary(const Model &model) {
    std::array<std::array<double, 5>, 4> matrix{};
    const int k = model.k();
    for (int row = 0; row < k - 1; ++row)
        for (int column = 0; column < k; ++column)
            matrix[row][column] = model.transition[column][row] - (row == column ? 1 : 0);
    for (int column = 0; column < k; ++column)
        matrix[k - 1][column] = 1;
    matrix[k - 1][k] = 1;
    for (int column = 0; column < k; ++column) {
        int pivot = column;
        for (int row = column + 1; row < k; ++row)
            if (std::abs(matrix[row][column]) > std::abs(matrix[pivot][column]))
                pivot = row;
        std::swap(matrix[pivot], matrix[column]);
        const double value = matrix[column][column];
        for (int j = column; j <= k; ++j)
            matrix[column][j] /= value;
        for (int row = 0; row < k; ++row)
            if (row != column) {
                const double factor = matrix[row][column];
                for (int j = column; j <= k; ++j)
                    matrix[row][j] -= factor * matrix[column][j];
            }
    }
    StateValues out{};
    for (int row = 0; row < k; ++row)
        out[row] = matrix[row][k];
    return out;
}
struct PathStats {
    std::array<I, 4> positions{}, runs{};
    I total = 0;
};
static PathStats path_stats(const std::vector<Path> &paths) {
    PathStats out;
    for (const Path &path : paths) {
        out.total += path.size();
        for (int state : path)
            ++out.positions[state];
        for (const Run &run : runs(path))
            ++out.runs[run.state];
    }
    return out;
}
static double max_change(const Model &a, const Model &b) {
    double out = 0;
    for (int i = 0; i < a.k(); ++i) {
        out = std::max(out, std::abs(a.initial[i] - b.initial[i]));
        for (int j = 0; j < a.k(); ++j)
            out = std::max(out, std::abs(a.transition[i][j] - b.transition[i][j]));
        for (int j = 0; j < a.m(); ++j)
            out = std::max(out, std::abs(a.emission[i][j] - b.emission[i][j]));
    }
    return out;
}
struct CV {
    Confusion matrix{};
    I correct_count = 0, positions = 0;
    std::vector<I> fold_records, fold_positions, fold_correct;
};
int main() {
    std::filesystem::create_directories("output");
    const Input input = load();
    const Params p = parameters(input.parameters, input.model);
    const Validated data = validate(input, p);
    const auto unlabeled = observations(data.unlabeled);
    auto heldout = observations(data.train);
    const auto test_observations = observations(data.test);
    heldout.insert(heldout.end(), test_observations.begin(), test_observations.end());
    const auto train_pairs = pairs(data.train);
    std::array<Model, 4> models;
    models[0] = input.model;
    models[1] = input.model;
    Lines bw_trace{"iteration,loglik,heldout,change,max_change,status"},
        vit_trace{"iteration,logprob,loglik,changed"}, trained, decodings,
        segment_file{
            "sequence,decoder,start,end,length,mean_posterior,support,rich_fraction,motif_ratio,island"},
        sample_file, evaluation_file, report;
    Values likelihood, held;
    int violations = 0, best_held = 0;
    likelihood.push_back(total_loglik(models[1], unlabeled));
    held.push_back(total_loglik(models[1], heldout));
    line(bw_trace, "0,", real(likelihood[0]), ",", real(held[0]), ",,,");
    for (int iteration = 1; iteration <= p.iterations; ++iteration) {
        const Model previous = models[1];
        models[1] = baum_welch(previous, unlabeled, p.pseudocount);
        likelihood.push_back(total_loglik(models[1], unlabeled));
        held.push_back(total_loglik(models[1], heldout));
        const bool violation = likelihood[iteration] <
                               likelihood[iteration - 1] - 0.000001 * std::abs(likelihood[iteration - 1]);
        violations += violation;
        if (held[iteration] > held[best_held])
            best_held = iteration;
        line(bw_trace, iteration, ",", real(likelihood.back()), ",", real(held.back()), ",",
             real(likelihood[iteration] - likelihood[iteration - 1]), ",",
             real(max_change(models[1], previous), 6), ",", violation ? "violation" : "ok");
    }
    models[2] = input.model;
    std::vector<Path> previous_paths;
    double initial_probability = 0;
    for (const Path &observation : unlabeled) {
        const Viterbi result = viterbi(models[2], observation);
        previous_paths.push_back(result.path);
        initial_probability += result.logprob;
    }
    line(vit_trace, "0,", real(initial_probability), ",", real(total_loglik(models[2], unlabeled)), ",");
    int vit_iterations = 0;
    bool converged = false;
    for (int iteration = 1; iteration <= p.iterations; ++iteration) {
        std::vector<Pair> current_pairs;
        for (int i = 0; i < int(unlabeled.size()); ++i)
            current_pairs.push_back({unlabeled[i], previous_paths[i]});
        models[2] = counting(input.model, current_pairs, p.pseudocount, "VITERBI_TRAINING");
        std::vector<Path> current_paths;
        I changed = 0;
        double probability = 0;
        for (int i = 0; i < int(unlabeled.size()); ++i) {
            const Viterbi result = viterbi(models[2], unlabeled[i]);
            current_paths.push_back(result.path);
            probability += result.logprob;
            changed += result.path.size() - correct(previous_paths[i], result.path);
        }
        line(vit_trace, iteration, ",", real(probability), ",", real(total_loglik(models[2], unlabeled)), ",",
             changed);
        previous_paths = std::move(current_paths);
        vit_iterations = iteration;
        converged = changed == 0;
        if (converged)
            break;
    }
    std::vector<CV> cross_validation;
    int selected_candidate = 0;
    for (int candidate = 0; candidate < int(p.smoothing.size()); ++candidate) {
        CV cv;
        cv.fold_records.resize(p.folds);
        cv.fold_positions.resize(p.folds);
        cv.fold_correct.resize(p.folds);
        for (int fold = 0; fold < p.folds; ++fold) {
            std::vector<Pair> training;
            for (int i = 0; i < int(train_pairs.size()); ++i)
                if (i % p.folds != fold)
                    training.push_back(train_pairs[i]);
            const Model model = counting(input.model, training, p.smoothing[candidate], "SUPERVISED");
            for (int i = 0; i < int(data.train.size()); ++i)
                if (i % p.folds == fold) {
                    const Sequence &sequence = data.train[i];
                    const Viterbi decoded = viterbi(model, sequence.observation);
                    const I correct_count = correct(sequence.truth, decoded.path);
                    ++cv.fold_records[fold];
                    cv.fold_positions[fold] += sequence.truth.size();
                    cv.fold_correct[fold] += correct_count;
                    cv.positions += sequence.truth.size();
                    cv.correct_count += correct_count;
                    accumulate(cv.matrix, sequence.truth, decoded.path);
                }
        }
        cross_validation.push_back(std::move(cv));
        if (cross_validation[candidate].correct_count > cross_validation[selected_candidate].correct_count)
            selected_candidate = candidate;
    }
    models[3] = counting(input.model, train_pairs, p.smoothing[selected_candidate], "SUPERVISED");
    for (int model = 1; model < 4; ++model) {
        if (model > 1)
            line(trained, "");
        extend(trained, model_lines(models[model]));
    }
    std::array<std::array<Evaluation, 2>, 4> evaluations;
    for (int model = 0; model < 4; ++model)
        for (int decoder = 0; decoder < 2; ++decoder) {
            evaluations[model][decoder] = evaluate(models[model], data.test, p, decoder);
            if (!evaluation_file.empty())
                line(evaluation_file, "");
            extend(evaluation_file,
                   evaluation_lines(models[model], evaluations[model][decoder], data.test, p, decoder));
        }
    const CV &cv = cross_validation[selected_candidate];
    line(evaluation_file, "");
    line(evaluation_file, "CROSS_VALIDATION folds ", p.folds);
    for (int candidate = 0; candidate < int(p.smoothing.size()); ++candidate)
        line(evaluation_file, "SMOOTHING ", p.candidates[candidate], " positions ",
             cross_validation[candidate].positions, " correct ", cross_validation[candidate].correct_count,
             " accuracy ",
             fraction(cross_validation[candidate].correct_count, cross_validation[candidate].positions));
    line(evaluation_file, "SELECTED ", p.candidates[selected_candidate]);
    for (int fold = 0; fold < p.folds; ++fold)
        line(evaluation_file, "FOLD ", fold + 1, " records ", cv.fold_records[fold], " positions ",
             cv.fold_positions[fold], " correct ", cv.fold_correct[fold], " accuracy ",
             fraction(cv.fold_correct[fold], cv.fold_positions[fold]));
    extend(evaluation_file, matrix_lines(input.model, cv.matrix));
    extend(evaluation_file, metric_lines(input.model, cv.matrix));
    line(evaluation_file, "");
    line(evaluation_file, "LEARNING_CURVE");
    const I test_positions = evaluations[0][0].positions;
    for (int count = 1; count <= int(train_pairs.size()); ++count) {
        const std::vector<Pair> prefix(train_pairs.begin(), train_pairs.begin() + count);
        const Model model = counting(input.model, prefix, p.smoothing[selected_candidate], "SUPERVISED");
        I correct_count = 0;
        for (const Sequence &sequence : data.test)
            correct_count += correct(sequence.truth, viterbi(model, sequence.observation).path);
        line(evaluation_file, "RECORDS ", count, " correct ", correct_count, " accuracy ",
             fraction(correct_count, test_positions));
    }
    std::array<std::vector<Decoding>, 4> cached;
    for (int model = 0; model < 4; ++model)
        for (const Path &observation : unlabeled)
            cached[model].push_back(decode(models[model], observation));
    Generator posterior_generator{p.posterior_seed};
    const Model &bw = models[1];
    for (int index = 0; index < int(data.unlabeled.size()); ++index) {
        const Sequence &sequence = data.unlabeled[index];
        const Decoding &decoded = cached[1][index];
        std::vector<Path> samples;
        I segment_count = 0;
        for (int sample = 0; sample < p.posterior_samples; ++sample) {
            samples.push_back(posterior_sample(bw, decoded.fb, posterior_generator));
            segment_count += segments(samples.back(), p).size();
        }
        const I differences = sequence.observation.size() - correct(decoded.viterbi.path, decoded.posterior);
        I uncertain = 0;
        std::string confident = state_string(decoded.posterior, bw.states), imputed;
        for (int t = 0; t < int(sequence.observation.size()); ++t) {
            if (decoded.confidence[t] < p.confidence) {
                ++uncertain;
                confident[t] = '.';
            }
            const int observed = sequence.observation[t];
            if (observed >= 0)
                imputed += bw.symbols[observed];
            else {
                std::array<double, 8> probabilities{};
                for (int symbol = 0; symbol < bw.m(); ++symbol)
                    for (int state = 0; state < bw.k(); ++state)
                        probabilities[symbol] += decoded.fb.posterior[t][state] * bw.emission[state][symbol];
                const char symbol = bw.symbols[maximum(probabilities.data(), bw.m())];
                imputed += char(symbol - 'A' + 'a');
            }
        }
        line(decodings, "SEQUENCE ", sequence.name, " length ", sequence.observation.size(), " loglik ",
             real(decoded.fb.loglik), " viterbi ", real(decoded.viterbi.logprob), " differences ",
             differences, " uncertain ", uncertain, " expected_segments ",
             ratio(segment_count, p.posterior_samples));
        line(decodings, "VITERBI ", state_string(decoded.viterbi.path, bw.states));
        line(decodings, "POSTERIOR ", state_string(decoded.posterior, bw.states));
        line(decodings, "CONFIDENT ", confident);
        line(decodings, "IMPUTED ", imputed);
        for (int decoder = 0; decoder < 2; ++decoder) {
            const Path &path = decoder == 0 ? decoded.viterbi.path : decoded.posterior;
            for (const Region &region : segments(path, p)) {
                double mean = 0;
                for (int t = region.start - 1; t < region.end; ++t)
                    mean += decoded.fb.posterior[t][p.segment_state];
                mean /= region.length();
                I support = 0;
                for (const Path &sample : samples) {
                    int inside = 0;
                    for (int t = region.start - 1; t < region.end; ++t)
                        inside += sample[t] == p.segment_state;
                    support += 2 * inside > region.length();
                }
                const Composition composition_result = composition(sequence.observation, region, p);
                line(segment_file, sequence.name, ",", decoder == 0 ? "viterbi" : "posterior", ",",
                     region.start, ",", region.end, ",", region.length(), ",", real(mean), ",", support, ",",
                     ratio(composition_result.rich, composition_result.observed), ",",
                     ratio(composition_result.motifs * composition_result.observed,
                           composition_result.first * composition_result.second),
                     ",", composition_result.island ? "yes" : "no");
            }
        }
    }
    Generator sample_generator{p.sample_seed};
    I viterbi_correct = 0, posterior_correct = 0;
    for (int sample = 1; sample <= p.sample_count; ++sample) {
        const Pair generated = synthetic(bw, p.sample_length, sample_generator);
        const Decoding decoded = decode(bw, generated.observation);
        const I vc = correct(generated.path, decoded.viterbi.path),
                pc = correct(generated.path, decoded.posterior);
        viterbi_correct += vc;
        posterior_correct += pc;
        line(sample_file, "SAMPLE ", sample, " loglik ", real(decoded.fb.loglik), " viterbi ",
             real(decoded.viterbi.logprob), " viterbi_correct ", vc, " posterior_correct ", pc);
        line(sample_file, "STATES ", state_string(generated.path, bw.states));
        line(sample_file, "SYMBOLS ", state_string(generated.observation, bw.symbols));
        line(sample_file, "VITERBI ", state_string(decoded.viterbi.path, bw.states));
        line(sample_file, "POSTERIOR ", state_string(decoded.posterior, bw.states));
    }
    const I synthetic_positions = p.sample_count * p.sample_length;
    line(sample_file, "TOTAL positions ", synthetic_positions, " viterbi_accuracy ",
         fraction(viterbi_correct, synthetic_positions), " posterior_accuracy ",
         fraction(posterior_correct, synthetic_positions));
    I unlabeled_positions = 0, unlabeled_missing = 0, labeled_positions = 0, labeled_missing = 0;
    std::array<I, 8> symbol_counts{};
    for (const Sequence &sequence : data.unlabeled) {
        unlabeled_positions += sequence.observation.size();
        for (int symbol : sequence.observation)
            if (symbol < 0)
                ++unlabeled_missing;
            else
                ++symbol_counts[symbol];
    }
    for (const Sequence &sequence : data.train) {
        labeled_positions += sequence.observation.size();
        labeled_missing += std::count(sequence.observation.begin(), sequence.observation.end(), -1);
    }
    for (const Sequence &sequence : data.test) {
        labeled_positions += sequence.observation.size();
        labeled_missing += std::count(sequence.observation.begin(), sequence.observation.end(), -1);
    }
    line(report, "INPUT");
    line(report, "SEQUENCES accepted ", data.unlabeled.size(), " rejected ", data.sequence_rejected,
         " positions ", unlabeled_positions, " missing ", unlabeled_missing);
    line(report, "LABELED train ", data.train.size(), " test ", data.test.size(), " rejected ",
         data.labeled_rejected, " positions ", labeled_positions, " missing ", labeled_missing);
    extend(report, data.rejected);
    std::string composition_line = "COMPOSITION";
    for (int symbol = 0; symbol < input.model.m(); ++symbol)
        composition_line += " " + std::string(1, input.model.symbols[symbol]) + " " +
                            ratio(symbol_counts[symbol], unlabeled_positions - unlabeled_missing);
    line(report, composition_line);
    for (int role = 0; role < 2; ++role) {
        std::vector<Path> truth;
        for (const Sequence &sequence : role == 0 ? data.train : data.test)
            truth.push_back(sequence.truth);
        const PathStats stats = path_stats(truth);
        for (int state = 0; state < input.model.k(); ++state)
            line(report, "TRUTH ", role == 0 ? "TRAIN" : "TEST", " ", input.model.states[state],
                 " occupancy ", ratio(stats.positions[state], stats.total), " mean_run ",
                 ratio(stats.positions[state], stats.runs[state]));
    }
    line(report, "");
    line(report, "TRAINING BAUM_WELCH iterations ", p.iterations, " initial_loglik ",
         real(likelihood.front()), " final_loglik ", real(likelihood.back()), " violations ", violations,
         " best_heldout_iteration ", best_held);
    line(report, "TRAINING VITERBI_TRAINING iterations ", vit_iterations, " converged ",
         converged ? "yes" : "no");
    line(report, "TRAINING SUPERVISED smoothing ", p.candidates[selected_candidate]);
    std::array<I, 4> preference{};
    for (int index = 0; index < int(unlabeled.size()); ++index) {
        int best = 0;
        for (int model = 1; model < 4; ++model)
            if (cached[model][index].fb.loglik > cached[best][index].fb.loglik)
                best = model;
        ++preference[best];
    }
    line(report, "PREFERENCE INITIAL ", preference[0], " BAUM_WELCH ", preference[1], " VITERBI_TRAINING ",
         preference[2], " SUPERVISED ", preference[3]);
    for (int first = 0; first < 4; ++first)
        for (int second = first + 1; second < 4; ++second) {
            I agreement = 0;
            for (int index = 0; index < int(unlabeled.size()); ++index)
                agreement += correct(cached[first][index].viterbi.path, cached[second][index].viterbi.path);
            line(report, "AGREEMENT ", models[first].name, " ", models[second].name, " ",
                 fraction(agreement, unlabeled_positions));
        }
    for (int decoder = 0; decoder < 2; ++decoder) {
        int best = 0;
        for (int model = 1; model < 4; ++model)
            if (evaluations[model][decoder].correct_count > evaluations[best][decoder].correct_count)
                best = model;
        line(report, "BEST ", decoder == 0 ? "VITERBI" : "POSTERIOR", " ", models[best].name, " accuracy ",
             fraction(evaluations[best][decoder].correct_count, test_positions));
    }
    for (int model = 0; model < 4; ++model) {
        const Model &current = models[model];
        double loglik = 0;
        std::vector<Path> paths;
        I segment_count = 0, segment_length = 0, islands = 0;
        for (int index = 0; index < int(unlabeled.size()); ++index) {
            const Decoding &decoded = cached[model][index];
            loglik += decoded.fb.loglik;
            paths.push_back(decoded.viterbi.path);
            for (const Region &region : segments(decoded.viterbi.path, p)) {
                ++segment_count;
                segment_length += region.length();
                islands += composition(unlabeled[index], region, p).island;
            }
        }
        const PathStats stats = path_stats(paths);
        const StateValues phi = stationary(current);
        Confusion alignment{};
        for (const Sequence &sequence : data.train)
            accumulate(alignment, sequence.truth, viterbi(current, sequence.observation).path);
        Path permutation(current.k()), best_permutation;
        std::iota(permutation.begin(), permutation.end(), 0);
        I best_agreement = -1;
        do {
            I agreement = 0;
            for (int state = 0; state < current.k(); ++state)
                agreement += alignment[permutation[state]][state];
            if (agreement > best_agreement) {
                best_agreement = agreement;
                best_permutation = permutation;
            }
        } while (std::next_permutation(permutation.begin(), permutation.end()));
        line(report, "");
        line(report, "MODEL ", current.name);
        line(report, "LOGLIK unlabeled ", real(loglik), " per_symbol ",
             ratio(loglik, unlabeled_positions - unlabeled_missing), " test ",
             real(total_loglik(current, test_observations)));
        line(report, "SEGMENTS count ", segment_count, " mean_length ", ratio(segment_length, segment_count),
             " islands ", islands);
        std::string mapping = "ALIGNMENT";
        for (int state = 0; state < current.k(); ++state)
            mapping += " " + std::string(1, current.states[state]) + "=" +
                       std::string(1, current.states[best_permutation[state]]);
        I train_positions = 0;
        for (const Sequence &sequence : data.train)
            train_positions += sequence.truth.size();
        line(report, mapping, " agreement ", fraction(best_agreement, train_positions));
        for (int state = 0; state < current.k(); ++state)
            line(report, "STATE ", current.states[state], " stationary ", real(phi[state]), " duration ",
                 real(1 / (1 - current.transition[state][state])), " occupancy ",
                 ratio(stats.positions[state], stats.total), " mean_run ",
                 ratio(stats.positions[state], stats.runs[state]));
    }
    save("trained_model.txt", trained);
    save("loglik_trace.csv", bw_trace);
    save("viterbi_trace.csv", vit_trace);
    save("decodings.txt", decodings);
    save("segments.csv", segment_file);
    save("samples.txt", sample_file);
    save("evaluation.txt", evaluation_file);
    save("report.txt", report);
}
