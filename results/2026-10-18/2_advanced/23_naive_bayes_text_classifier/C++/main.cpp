#include "classifier.hpp"
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <memory>
#include <stdexcept>

static const Lines models{"multinomial", "bernoulli", "complement", "rocchio", "vote"};
static Lines readLines(const std::string& name) { std::ifstream file("input/" + name, std::ios::binary); if (!file) throw std::runtime_error("cannot read " + name); Lines lines; std::string line; while (std::getline(file, line)) lines.push_back(line); if (file.bad()) throw std::runtime_error("cannot read " + name); return lines; }
static Lines split(const std::string& line, char separator) { Lines result; std::size_t start = 0; for (std::size_t i = 0; i < line.size(); ++i) if (line[i] == separator) { result.push_back(line.substr(start, i - start)); start = i + 1; } result.push_back(line.substr(start)); return result; }
static int hundredths(const std::string& value) { Lines pieces = split(value, '.'); return 100 * std::stoi(pieces[0]) + std::stoi(pieces[1]); }
static std::string hundredthsText(int value) { std::ostringstream stream; stream << value / 100 << '.' << std::setfill('0') << std::setw(2) << value % 100; return stream.str(); }
static void paragraph(Lines& target, const Lines& source) { if (!target.empty()) target.push_back(""); target.insert(target.end(), source.begin(), source.end()); }
static void extend(Lines& target, const Lines& source) { target.insert(target.end(), source.begin(), source.end()); }
static void writeLines(const std::string& name, const Lines& lines) { std::ofstream file("output/" + name, std::ios::binary); if (!file) throw std::runtime_error("cannot write " + name); for (const std::string& line : lines) file << line << '\n'; file.close(); if (!file) throw std::runtime_error("cannot write " + name); }
static Lines evaluationFields(const Evaluation& evaluation) { return {text(evaluation.correct), realText(evaluation.micro), realText(evaluation.macro)}; }
struct Settings {
    Indices alphas, curve, sizes, thresholds, lengths;
    int minimum, features, top, iterations, weight, resamples;
    Integer seed;
    bool bigrams;
};
static Settings readSettings() {
    std::map<std::string, Lines> values;
    for (const std::string& line : readLines("params.txt")) { Lines fields = split(line, ' '); values[fields[0]] = Lines(fields.begin() + 1, fields.end()); }
    Settings s;
    for (const std::string& value : values.at("ALPHAS")) s.alphas.push_back(hundredths(value));
    for (const std::string& value : values.at("CURVE")) s.curve.push_back(std::stoi(value));
    for (const std::string& value : values.at("SIZES")) s.sizes.push_back(std::stoi(value));
    for (const std::string& value : values.at("THRESHOLDS")) s.thresholds.push_back(hundredths(value));
    for (const std::string& value : values.at("LENGTHS")) s.lengths.push_back(std::stoi(value));
    s.minimum = std::stoi(values.at("MIN_DF")[0]); s.features = std::stoi(values.at("FEATURES")[0]); s.bigrams = values.at("BIGRAMS")[0] == "yes"; s.top = std::stoi(values.at("TOP")[0]); s.iterations = std::stoi(values.at("EM_ITERATIONS")[0]); s.weight = hundredths(values.at("EM_WEIGHT")[0]); s.resamples = std::stoi(values.at("BOOTSTRAP")[0]); s.seed = std::stoll(values.at("BOOTSTRAP")[1]); return s;
}
struct Document { std::string id; int label; Tokenization tokens; };
using Documents = std::vector<const Document*>;
struct Training {
    bool bigrams;
    Vocabulary vocabulary;
    TrainingCounts counts;
    Rocchio rocchio;
    std::array<NaiveBayes, 3> nb;
    Training(const Documents& documents, bool bigrams, int classes, int minimum, int limit) : bigrams(bigrams) {
        TextSequences sequences; Indices labels;
        for (const Document* document : documents) { sequences.push_back(document->tokens.terms(bigrams)); labels.push_back(document->label); }
        vocabulary = Vocabulary(sequences, labels, classes, minimum, limit); Sequences encoded; for (const Lines& sequence : sequences) encoded.push_back(vocabulary.encode(sequence));
        counts = TrainingCounts(encoded, labels, classes, vocabulary.size()); rocchio = Rocchio(encoded, labels, classes, vocabulary.frequencies);
    }
    void train(const std::array<int, 3>& alphas) { for (int model = 0; model < 3; ++model) nb[model] = trainNaiveBayes(model, counts, alphas[model]); }
    Indices encode(const Document& document) const { return vocabulary.encode(document.tokens.terms(bigrams)); }
    Prediction classify(int model, const Indices& sequence) const { return model == 3 ? rocchio.predict(sequence) : nb[model].predict(sequence); }
};
struct Fold { int train, validate, candidates, size; };
struct CrossRun { Indices predictions; Evaluation evaluation; std::array<int, 5> folds{}; };
struct RatioEntry { Integer numerator, denominator; int term; };
static std::vector<RatioEntry> ratioRanking(std::vector<RatioEntry> entries) { std::sort(entries.begin(), entries.end(), [](const RatioEntry& first, const RatioEntry& second) { Integer left = first.numerator * second.denominator, right = second.numerator * first.denominator; return left != right ? left > right : first.term < second.term; }); return entries; }
class Experiment {
    Settings settings;
    Lines classes;
    int classCount;
    std::vector<Document> training, tests, unlabelled;
    Indices labelled, truths, trainingTruths;
    std::array<std::vector<CrossRun>, 4> cross;
    std::vector<Fold> folds;
    std::array<int, 3> selected{};
    std::array<int, 4> selectedRun{};
    std::unique_ptr<Training> final;
    Sequences testSequences;
    std::array<std::vector<Prediction>, 5> predictions;
    std::array<Indices, 5> correct;
    Documents allTraining() const { Documents result; for (const Document& document : training) result.push_back(&document); return result; }
    const CrossRun& chosen(int model) const { return cross[model][selectedRun[model]]; }
    std::string alphaText(int model) const { return model < 3 ? hundredthsText(selected[model]) : "-"; }
    std::string classCounts(const Indices& counts) const { Lines fields; for (int label = 0; label < classCount; ++label) { fields.push_back(classes[label]); fields.push_back(text(counts[label])); } return join(fields, " "); }
    void crossValidate() {
        int count = static_cast<int>(training.size()); std::array<std::vector<Indices>, 4> predicted;
        for (int model = 0; model < 4; ++model) predicted[model].assign(model < 3 ? settings.alphas.size() : 1, Indices(count));
        for (int fold = 0; fold < 5; ++fold) {
            Documents members; Indices held;
            for (int index = 0; index < count; ++index) { if (index % 5 == fold) held.push_back(index); else members.push_back(&training[index]); }
            Training fit(members, settings.bigrams, classCount, settings.minimum, settings.features); folds.push_back({static_cast<int>(members.size()), static_cast<int>(held.size()), fit.vocabulary.candidateCount, fit.vocabulary.size()});
            Sequences sequences; for (int index : held) sequences.push_back(fit.encode(training[index]));
            for (int model = 0; model < 3; ++model) for (std::size_t alpha = 0; alpha < settings.alphas.size(); ++alpha) { NaiveBayes nb = trainNaiveBayes(model, fit.counts, settings.alphas[alpha]); for (std::size_t k = 0; k < held.size(); ++k) predicted[model][alpha][held[k]] = nb.predict(sequences[k]).label; }
            for (std::size_t k = 0; k < held.size(); ++k) predicted[3][0][held[k]] = fit.rocchio.predict(sequences[k]).label;
        }
        for (int model = 0; model < 4; ++model) for (const Indices& labels : predicted[model]) { CrossRun run; run.predictions = labels; run.evaluation = Evaluation(classCount, trainingTruths, labels); for (int index = 0; index < count; ++index) run.folds[index % 5] += labels[index] == trainingTruths[index]; cross[model].push_back(std::move(run)); }
        for (int model = 0; model < 3; ++model) { int best = 0; for (int alpha = 1; alpha < static_cast<int>(settings.alphas.size()); ++alpha) if (decimalValue(cross[model][alpha].evaluation.macro) > decimalValue(cross[model][best].evaluation.macro)) best = alpha; selectedRun[model] = best; selected[model] = settings.alphas[best]; }
    }
    void trainFinal() {
        final = std::make_unique<Training>(allTraining(), settings.bigrams, classCount, settings.minimum, settings.features); final->train(selected);
        for (const Document& document : tests) testSequences.push_back(final->encode(document));
        for (int model = 0; model < 4; ++model) for (const Indices& sequence : testSequences) predictions[model].push_back(final->classify(model, sequence));
        for (std::size_t index = 0; index < tests.size(); ++index) { Indices votes(classCount), labels; for (int model = 0; model < 4; ++model) { int label = predictions[model][index].label; ++votes[label]; labels.push_back(label); } int winner = labels[0]; for (int label : labels) if (votes[label] > votes[winner]) winner = label; Prediction vote; vote.label = winner; vote.score = votes[winner] / 4.0; predictions[4].push_back(vote); }
        for (int model = 0; model < 5; ++model) for (int index : labelled) correct[model].push_back(predictions[model][index].label == tests[index].label);
    }
    std::vector<Evaluation> evaluate(const Training& fit) const { Sequences sequences; for (int index : labelled) sequences.push_back(fit.encode(tests[index])); std::vector<Evaluation> result; for (int model = 0; model < 4; ++model) { Indices labels; for (const Indices& sequence : sequences) labels.push_back(fit.classify(model, sequence).label); result.emplace_back(classCount, truths, labels); } return result; }
    Lines vocabularyLines() const { const Vocabulary& vocabulary = final->vocabulary; Lines lines{text("documents ", training.size(), " terms ", vocabulary.termCount, " candidates ", vocabulary.candidateCount, " vocabulary ", vocabulary.size())}; for (std::size_t i = 0; i < vocabulary.ranking.size(); ++i) { const RankedTerm& term = vocabulary.ranking[i]; add(lines, i + 1, ' ', term.term, ' ', term.frequency, ' ', realText(term.score), ' ', classes[term.bestClass]); } return lines; }
    Lines crossLines() const { Lines lines{"model,alpha,correct,accuracy,macro_f1,selected"}; for (int model = 0; model < 4; ++model) for (std::size_t alpha = 0; alpha < cross[model].size(); ++alpha) { Lines fields{models[model], model < 3 ? hundredthsText(settings.alphas[alpha]) : "-"}; extend(fields, evaluationFields(cross[model][alpha].evaluation)); fields.push_back(static_cast<int>(alpha) == selectedRun[model] ? "yes" : "no"); lines.push_back(join(fields, ",")); } return lines; }
    Lines predictionLines() const { Lines lines{"id,model,label,score"}; for (std::size_t index = 0; index < tests.size(); ++index) for (int model = 0; model < 5; ++model) { const Prediction& prediction = predictions[model][index]; add(lines, tests[index].id, ',', models[model], ',', classes[prediction.label], ',', realText(prediction.score)); } return lines; }
    Lines curveLines() const { Lines lines{"size,vocabulary,model,correct,accuracy,macro_f1"}; Documents all = allTraining(); for (int size : settings.curve) { Documents prefix(all.begin(), all.begin() + size); Training fit(prefix, settings.bigrams, classCount, settings.minimum, settings.features); fit.train(selected); std::vector<Evaluation> values = evaluate(fit); for (int model = 0; model < 4; ++model) { Lines fields{text(size), text(fit.vocabulary.size()), models[model]}; extend(fields, evaluationFields(values[model])); lines.push_back(join(fields, ",")); } } return lines; }
    Lines featureLines() const { Lines lines{"terms,features,vocabulary,model,correct,accuracy,macro_f1"}; for (bool bigrams : {false, true}) for (int size : settings.sizes) { Training fit(allTraining(), bigrams, classCount, settings.minimum, size); fit.train(selected); std::vector<Evaluation> values = evaluate(fit); for (int model = 0; model < 4; ++model) { Lines fields{bigrams ? "bigrams" : "unigrams", text(size), text(fit.vocabulary.size()), models[model]}; extend(fields, evaluationFields(values[model])); lines.push_back(join(fields, ",")); } } return lines; }
    Lines dataPart() const {
        const Vocabulary& vocabulary = final->vocabulary; Lines lines{text("documents train ", training.size(), " test ", tests.size(), " labelled ", labelled.size(), " unlabelled ", unlabelled.size(), " classes ", classCount)}; Indices trainCounts(classCount), testCounts(classCount);
        for (const Document& document : training) ++trainCounts[document.label]; for (int truth : truths) ++testCounts[truth];
        for (int label = 0; label < classCount; ++label) add(lines, "class ", classes[label], " train ", trainCounts[label], " test ", testCounts[label]);
        int raw = 0, stopped = 0, shortWords = 0, kept = 0, bigrams = 0; std::set<std::string> terms;
        for (const Document& document : training) { const Tokenization& tokens = document.tokens; raw += tokens.raw; stopped += tokens.stopped; shortWords += tokens.shortWords; kept += static_cast<int>(tokens.words.size()); if (settings.bigrams) bigrams += static_cast<int>(tokens.bigrams.size()); const Lines& sequence = tokens.terms(settings.bigrams); terms.insert(sequence.begin(), sequence.end()); }
        int distinctBigrams = 0; for (const std::string& term : terms) distinctBigrams += term.find('_') != std::string::npos;
        add(lines, "train_tokens raw ", raw, " stopwords ", stopped, " short ", shortWords, " unigrams ", kept, " bigrams ", bigrams); add(lines, "train_terms unigrams ", terms.size() - distinctBigrams, " bigrams ", distinctBigrams, " candidates ", vocabulary.candidateCount, " vocabulary ", vocabulary.size());
        std::size_t total = 0, encoded = 0; std::map<std::string, int> oov;
        for (std::size_t index = 0; index < tests.size(); ++index) { total += tests[index].tokens.terms(settings.bigrams).size(); encoded += testSequences[index].size(); for (const std::string& word : tests[index].tokens.words) if (!vocabulary.index.count(word)) ++oov[word]; }
        add(lines, "test_terms total ", total, " in_vocabulary ", encoded); std::vector<std::pair<std::string, int>> ranked(oov.begin(), oov.end());
        std::sort(ranked.begin(), ranked.end(), [](const std::pair<std::string, int>& first, const std::pair<std::string, int>& second) { return first.second != second.second ? first.second > second.second : first.first < second.first; });
        std::string line = "test_oov"; for (int i = 0; i < settings.top && i < static_cast<int>(ranked.size()); ++i) line += text(' ', ranked[i].first, ' ', ranked[i].second); lines.push_back(line); return lines;
    }
    Lines foldsPart() const { Lines lines{"folds 5"}; for (std::size_t i = 0; i < folds.size(); ++i) add(lines, "fold ", i + 1, " train ", folds[i].train, " validate ", folds[i].validate, " candidates ", folds[i].candidates, " vocabulary ", folds[i].size); return lines; }
    Lines selectionPart() const { Lines lines{"selection"}; for (int model = 0; model < 4; ++model) { const CrossRun& run = chosen(model); Lines counts; for (int value : run.folds) counts.push_back(text(value)); add(lines, models[model], " alpha ", alphaText(model), " correct ", proportionText(run.evaluation.correct, run.evaluation.total), " macro_f1 ", realText(run.evaluation.macro), " folds ", join(counts, " ")); } return lines; }
    Lines crossPart(int model) const { Lines lines{text("cross_validation ", models[model], " alpha ", alphaText(model))}; extend(lines, chosen(model).evaluation.lines(classes)); return lines; }
    Lines testPart(int model) const { Indices labels; int topTwo = 0; for (std::size_t k = 0; k < labelled.size(); ++k) { const Prediction& prediction = predictions[model][labelled[k]]; labels.push_back(prediction.label); if (model < 4 && (prediction.ranking[0] == truths[k] || prediction.ranking[1] == truths[k])) ++topTwo; } Evaluation evaluation(classCount, truths, labels); Lines lines{text("test ", models[model], " alpha ", alphaText(model)), text("labelled ", labelled.size(), " correct ", proportionText(evaluation.correct, labelled.size()))}; if (model < 4) add(lines, "top2 ", proportionText(topTwo, labelled.size())); extend(lines, evaluation.lines(classes)); return lines; }
    Lines probabilityPart(int model) const {
        std::size_t bins = settings.thresholds.size() + 1; Indices rows(bins), hits(bins), accepted(bins - 1), acceptedHits(bins - 1); Values sums(bins); double loss = 0, brier = 0;
        for (std::size_t position = 0; position < labelled.size(); ++position) {
            const Prediction& prediction = predictions[model][labelled[position]]; int truth = truths[position]; bool right = correct[model][position];
            loss += std::log(prediction.normalizer) - (prediction.scores[truth] - prediction.scores[prediction.label]);
            double squares = 0; for (int label = 0; label < classCount; ++label) { double difference = prediction.probabilities[label] - (label == truth ? 1.0 : 0.0); squares += difference * difference; } brier += squares;
            int bucket = 0; for (int threshold : settings.thresholds) bucket += prediction.score >= threshold / 100.0;
            ++rows[bucket]; hits[bucket] += right; sums[bucket] += prediction.score;
            for (std::size_t k = 0; k < settings.thresholds.size(); ++k) if (prediction.score >= settings.thresholds[k] / 100.0) { ++accepted[k]; acceptedHits[k] += right; }
        }
        Lines lines{text("probability ", models[model], " alpha ", alphaText(model)), text("log_loss ", realText(loss / labelled.size()), " brier ", realText(brier / labelled.size()))};
        for (std::size_t bin = 0; bin < bins; ++bin) { std::string line = text("bin ", hundredthsText(bin ? settings.thresholds[bin - 1] : 0), " rows ", rows[bin]); if (rows[bin]) line += text(" correct ", proportionText(hits[bin], rows[bin]), " mean ", realText(sums[bin] / rows[bin])); lines.push_back(line); }
        for (std::size_t k = 0; k < settings.thresholds.size(); ++k) add(lines, "threshold ", hundredthsText(settings.thresholds[k]), " covered ", proportionText(accepted[k], labelled.size()), " correct ", accepted[k] ? proportionText(acceptedHits[k], accepted[k]) : "-");
        return lines;
    }
    Lines lengthsPart() const {
        Indices rows(settings.lengths.size() + 1); std::array<Indices, 5> hits; for (Indices& values : hits) values.assign(rows.size(), 0);
        for (std::size_t position = 0; position < labelled.size(); ++position) { int bucket = 0; for (int boundary : settings.lengths) bucket += testSequences[labelled[position]].size() >= static_cast<std::size_t>(boundary); ++rows[bucket]; for (int model = 0; model < 5; ++model) hits[model][bucket] += correct[model][position]; }
        Lines lines{"lengths"};
        for (std::size_t bucket = 0; bucket < rows.size(); ++bucket) { std::string line = text("length ", bucket ? settings.lengths[bucket - 1] : 0, " rows ", rows[bucket]); if (rows[bucket]) for (int model = 0; model < 5; ++model) line += text(' ', models[model], ' ', proportionText(hits[model][bucket], rows[bucket])); lines.push_back(line); }
        return lines;
    }
    Lines comparisonPart() const {
        Lines lines{"comparison"};
        for (int first = 0; first < 4; ++first) for (int second = first + 1; second < 4; ++second) {
            int agreement = 0, b = 0, c = 0;
            for (std::size_t index = 0; index < tests.size(); ++index) agreement += predictions[first][index].label == predictions[second][index].label;
            for (std::size_t k = 0; k < labelled.size(); ++k) { b += correct[first][k] && !correct[second][k]; c += correct[second][k] && !correct[first][k]; }
            Integer difference = std::max(0, std::abs(b - c) - 1); std::string statistic = b + c ? fractionText(difference * difference, b + c) : fractionText(0, 1);
            add(lines, models[first], ' ', models[second], " agree ", proportionText(agreement, tests.size()), " b ", b, " c ", c, " statistic ", statistic);
        }
        std::array<int, 5> errors{}; for (std::size_t k = 0; k < labelled.size(); ++k) { int wrong = 0; for (int model = 0; model < 4; ++model) wrong += !correct[model][k]; ++errors[wrong]; }
        std::string line = "errors"; for (int wrong = 0; wrong < 5; ++wrong) line += text(' ', wrong, ' ', errors[wrong]); lines.push_back(line); return lines;
    }
    Lines bootstrapPart() const {
        Integer state = settings.seed; int count = static_cast<int>(labelled.size()); std::array<Indices, 5> totals;
        for (int sample = 0; sample < settings.resamples; ++sample) { Indices chosen; for (int k = 0; k < count; ++k) { state = 48271 * state % 2147483647; chosen.push_back(static_cast<int>(state % count)); } for (int model = 0; model < 5; ++model) { int hits = 0; for (int position : chosen) hits += correct[model][position]; totals[model].push_back(hits); } }
        int tail = settings.resamples / 40; Lines lines{text("bootstrap resamples ", settings.resamples, " seed ", settings.seed)};
        for (int model = 0; model < 5; ++model) { Indices ordered = totals[model]; std::sort(ordered.begin(), ordered.end()); Integer sum = std::accumulate(ordered.begin(), ordered.end(), Integer(0)); add(lines, models[model], " mean ", realText(static_cast<double>(sum) / (settings.resamples * count)), " low ", proportionText(ordered[tail], count), " high ", proportionText(ordered[ordered.size() - 1 - tail], count)); }
        for (int first = 0; first < 4; ++first) for (int second = first + 1; second < 4; ++second) { int wins = 0, ties = 0, losses = 0; for (int k = 0; k < settings.resamples; ++k) { wins += totals[first][k] > totals[second][k]; ties += totals[first][k] == totals[second][k]; losses += totals[first][k] < totals[second][k]; } add(lines, "pair ", models[first], ' ', models[second], " wins ", wins, " ties ", ties, " losses ", losses); }
        return lines;
    }
    Lines hardPart() const {
        Indices hard, counts(classCount);
        for (int index = 0; index < static_cast<int>(training.size()); ++index) { bool wrong = true; for (int model = 0; model < 4; ++model) wrong = wrong && chosen(model).predictions[index] != training[index].label; if (wrong) { hard.push_back(index); ++counts[training[index].label]; } }
        Lines lines{text("hard_documents ", hard.size(), ' ', classCounts(counts))};
        for (int k = 0; k < settings.top && k < static_cast<int>(hard.size()); ++k) { int index = hard[k]; std::string line = text(training[index].id, " true ", classes[training[index].label], " predicted"); for (int model = 0; model < 4; ++model) line += ' ' + classes[chosen(model).predictions[index]]; lines.push_back(line); }
        return lines;
    }
    Lines uncertainPart() const {
        Indices order(tests.size()); std::iota(order.begin(), order.end(), 0);
        std::stable_sort(order.begin(), order.end(), [&](int a, int b) { return decimalValue(predictions[0][a].margin) < decimalValue(predictions[0][b].margin); });
        int shown = std::min(settings.top, static_cast<int>(tests.size())); Lines lines{text("uncertain multinomial ", shown)};
        for (int k = 0; k < shown; ++k) { int index = order[k]; const Prediction& prediction = predictions[0][index]; add(lines, tests[index].id, " predicted ", classes[prediction.label], " runner_up ", classes[prediction.runnerUp], " margin ", realText(prediction.margin), " posterior ", realText(prediction.score), " true ", tests[index].label < 0 ? "?" : classes[tests[index].label]); }
        return lines;
    }
    Lines misclassifiedPart() const {
        Indices wrong; for (int index : labelled) if (predictions[0][index].label != tests[index].label) wrong.push_back(index);
        Lines lines{text("misclassified multinomial ", wrong.size())}; int alpha = selected[0];
        for (int index : wrong) {
            const Prediction& prediction = predictions[0][index]; int truth = tests[index].label; add(lines, tests[index].id, " true ", classes[truth], " predicted ", classes[prediction.label], " posterior ", realText(prediction.score));
            std::vector<RatioEntry> entries; for (int term : firstOccurrences(testSequences[index])) entries.push_back({100 * final->counts.occurrences[prediction.label][term] + alpha, 100 * final->counts.occurrences[truth][term] + alpha, term}); entries = ratioRanking(std::move(entries));
            for (std::size_t k = 0; k < entries.size() && k < 3; ++k) { int term = entries[k].term; int count = static_cast<int>(std::count(testSequences[index].begin(), testSequences[index].end(), term)); double evidence = final->nb[0].weights[prediction.label][term] - final->nb[0].weights[truth][term]; add(lines, "  ", final->vocabulary.terms[term], " count ", count, " evidence ", realText(evidence)); }
        }
        return lines;
    }
    NaiveBayes maximization(const std::vector<Prediction>& posteriors, const Sequences& sequences) const {
        ValueTable occurrences(classCount, Values(final->vocabulary.size())); Values documents(classCount);
        for (int label = 0; label < classCount; ++label) { documents[label] = final->counts.documents[label]; for (int term = 0; term < final->vocabulary.size(); ++term) occurrences[label][term] = final->counts.occurrences[label][term]; }
        double weight = settings.weight / 100.0;
        for (std::size_t index = 0; index < sequences.size(); ++index) { std::map<int, int> frequencies; for (int term : sequences[index]) ++frequencies[term]; Indices first = firstOccurrences(sequences[index]); for (int label = 0; label < classCount; ++label) { double share = weight * posteriors[index].probabilities[label]; documents[label] += share; for (int term : first) occurrences[label][term] += share * frequencies[term]; } }
        NaiveBayes model; model.kind = 0; model.base.assign(classCount, 0); model.weights.assign(classCount, Values(final->vocabulary.size())); double scale = training.size() + (settings.weight * unlabelled.size()) / 100.0;
        for (int label = 0; label < classCount; ++label) { double total = 0; for (double value : occurrences[label]) total += value; for (int term = 0; term < final->vocabulary.size(); ++term) model.weights[label][term] = smoothedLog(occurrences[label][term], total, selected[0], final->vocabulary.size()); model.priors.push_back(std::log(documents[label] / scale)); }
        return model;
    }
    Lines semiSupervisedPart() const {
        Sequences sequences; for (const Document& document : unlabelled) sequences.push_back(final->encode(document)); NaiveBayes model = final->nb[0]; Indices previous;
        Lines lines{text("semi_supervised multinomial alpha ", alphaText(0), " weight ", hundredthsText(settings.weight), " unlabelled ", unlabelled.size())};
        for (int iteration = 0; iteration <= settings.iterations; ++iteration) { std::vector<Prediction> posteriors; Indices assignments, assigned(classCount), predicted; for (const Indices& sequence : sequences) { posteriors.push_back(model.predict(sequence)); assignments.push_back(posteriors.back().label); ++assigned[assignments.back()]; } for (int index : labelled) predicted.push_back(model.predict(testSequences[index]).label); Evaluation evaluation(classCount, truths, predicted); std::string changed = "-"; if (iteration) { int count = 0; for (std::size_t i = 0; i < assignments.size(); ++i) count += previous[i] != assignments[i]; changed = text(count); } add(lines, "iteration ", iteration, " correct ", proportionText(evaluation.correct, evaluation.total), " macro_f1 ", realText(evaluation.macro), " changed ", changed, " assigned ", classCounts(assigned)); if (iteration < settings.iterations) model = maximization(posteriors, sequences); previous = std::move(assignments); }
        return lines;
    }
    Lines metricsLines() const { Lines lines; paragraph(lines, dataPart()); paragraph(lines, foldsPart()); paragraph(lines, selectionPart()); for (int model = 0; model < 4; ++model) paragraph(lines, crossPart(model)); for (int model = 0; model < 5; ++model) paragraph(lines, testPart(model)); for (int model = 0; model < 3; ++model) paragraph(lines, probabilityPart(model)); paragraph(lines, lengthsPart()); paragraph(lines, comparisonPart()); paragraph(lines, bootstrapPart()); paragraph(lines, hardPart()); paragraph(lines, uncertainPart()); paragraph(lines, misclassifiedPart()); paragraph(lines, semiSupervisedPart()); return lines; }
    Lines topFeatureLines() const {
        const TrainingCounts& counts = final->counts; int size = final->vocabulary.size(); Lines lines;
        for (int model = 0; model < 2; ++model) {
            int alpha = selected[model], outcomes = model ? 2 : size; const IntegerTable& table = model ? counts.containing : counts.occurrences; const std::vector<Integer>& totals = model ? counts.documents : counts.totals; Integer overall = model ? counts.documentTotal : counts.total; std::vector<Integer> termTotals(size);
            for (const std::vector<Integer>& row : table) for (int term = 0; term < size; ++term) termTotals[term] += row[term];
            paragraph(lines, {text("model ", models[model], " alpha ", alphaText(model), " vocabulary ", size, " top ", settings.top)});
            for (int label = 0; label < classCount; ++label) { Integer total = totals[label], other = overall - total; Lines part{text("class ", classes[label], " total ", total, " other ", other)}; std::vector<RatioEntry> entries; for (int term = 0; term < size; ++term) entries.push_back({100 * table[label][term] + alpha, 100 * (termTotals[term] - table[label][term]) + alpha, term}); entries = ratioRanking(std::move(entries)); for (int rank = 0; rank < settings.top && rank < size; ++rank) { int term = entries[rank].term; Integer count = table[label][term], otherCount = termTotals[term] - count; double odds = smoothedLog(count, total, alpha, outcomes) - smoothedLog(otherCount, other, alpha, outcomes); add(part, rank + 1, ' ', final->vocabulary.terms[term], ' ', count, ' ', otherCount, ' ', realText(odds)); } paragraph(lines, part); }
        }
        return lines;
    }
public:
    Experiment() : settings(readSettings()), classCount(0) {
        Lines stopped = readLines("stopwords.txt"); std::set<std::string> stopwords(stopped.begin(), stopped.end()); std::vector<Lines> rows;
        std::set<std::string> names; for (const std::string& line : readLines("train.txt")) { Lines fields = split(line, '\t'); names.insert(fields[0]); rows.push_back(fields); }
        classes.assign(names.begin(), names.end()); classCount = static_cast<int>(classes.size()); std::map<std::string, int> indices; for (int label = 0; label < classCount; ++label) indices[classes[label]] = label;
        for (const Lines& fields : rows) { int label = indices.at(fields[0]); training.push_back({text(training.size() + 1), label, Tokenization(fields[1], stopwords)}); trainingTruths.push_back(label); }
        for (const std::string& line : readLines("test.txt")) { Lines fields = split(line, '\t'); int label = fields[1] == "?" ? -1 : indices.at(fields[1]); if (label >= 0) { labelled.push_back(static_cast<int>(tests.size())); truths.push_back(label); } tests.push_back({fields[0], label, Tokenization(fields[2], stopwords)}); }
        for (const std::string& line : readLines("unlabelled.txt")) unlabelled.push_back({text(unlabelled.size() + 1), -1, Tokenization(line, stopwords)});
        crossValidate(); trainFinal();
    }
    void write() const { std::filesystem::create_directories("output"); writeLines("vocabulary.txt", vocabularyLines()); writeLines("cv_results.csv", crossLines()); writeLines("predictions.csv", predictionLines()); writeLines("learning_curve.csv", curveLines()); writeLines("feature_study.csv", featureLines()); writeLines("metrics.txt", metricsLines()); writeLines("top_features.txt", topFeatureLines()); }
};
int main() { Experiment experiment; experiment.write(); }
