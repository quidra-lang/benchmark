import Foundation

let modelNames = ["multinomial", "bernoulli", "complement", "rocchio", "vote"]
let modelPairs = [(0, 1), (0, 2), (0, 3), (1, 2), (1, 3), (2, 3)]
let foldCount = 5
func readLines(_ name: String) throws -> [String] { try String(contentsOfFile: "input/" + name, encoding: .utf8).split(whereSeparator: \.isNewline).map(String.init) }
func writeLines(_ name: String, _ lines: [String]) throws { try (lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: true, encoding: .utf8) }
func joinParts(_ parts: [[String]]) -> [String] {
    var lines: [String] = []
    for part in parts { if !lines.isEmpty { lines.append("") }; lines += part }
    return lines
}
func hundredths(_ text: String) -> Int { let parts = text.split(separator: "."); return Int(parts[0])! * 100 + Int(parts[1])! }
func hundredthsText(_ value: Int) -> String { String(value / 100) + "." + String(format: "%02d", value % 100) }
func classCountsText(_ names: [String], _ counts: [Int]) -> String { zip(names, counts).map { "\($0.0) \($0.1)" }.joined(separator: " ") }
func rankedRatios(_ entries: [(Int, Int, Int)]) -> [(Int, Int, Int)] {
    entries.sorted { a, b in let left = a.0 * b.1, right = b.0 * a.1; return left == right ? a.2 < b.2 : left > right }
}
func majorityVote(_ labels: [Int], _ classCount: Int) -> Prediction {
    var votes = Array(repeating: 0, count: classCount)
    for label in labels { votes[label] += 1 }
    var winner = labels[0]
    for label in labels { if votes[label] > votes[winner] { winner = label } }
    return Prediction(label: winner, score: Double(votes[winner]) / Double(labels.count), ranking: [], scores: [], probabilities: [], normalizer: 0, margin: 0)
}
struct Settings {
    let alphas: [Int]
    let minDF: Int
    let features: Int
    let bigrams: Bool
    let top: Int
    let curve: [Int]
    let sizes: [Int]
    let thresholds: [Int]
    let lengths: [Int]
    let iterations: Int
    let weight: Int
    let resamples: Int
    let seed: Int
    init(_ lines: [String]) {
        var values: [String: [String]] = [:]
        for line in lines { let fields = line.split(separator: " ").map(String.init); values[fields[0]] = Array(fields.dropFirst()) }
        alphas = values["ALPHAS"]!.map(hundredths); minDF = Int(values["MIN_DF"]![0])!; features = Int(values["FEATURES"]![0])!
        bigrams = values["BIGRAMS"]![0] == "yes"; top = Int(values["TOP"]![0])!
        curve = values["CURVE"]!.map { Int($0)! }; sizes = values["SIZES"]!.map { Int($0)! }
        thresholds = values["THRESHOLDS"]!.map(hundredths); lengths = values["LENGTHS"]!.map { Int($0)! }
        iterations = Int(values["EM_ITERATIONS"]![0])!; weight = hundredths(values["EM_WEIGHT"]![0])
        resamples = Int(values["BOOTSTRAP"]![0])!; seed = Int(values["BOOTSTRAP"]![1])!
    }
}
struct Document { let name: String; let label: Int?; let tokens: Tokens }
struct FoldSummary { let train: Int; let validate: Int; let candidates: Int; let vocabulary: Int }
struct CrossValidationRun {
    let predictions: [Int]
    let evaluation: Evaluation
    let foldCorrect: [Int]
    init(_ predictions: [Int], _ truths: [Int], _ classes: Int) {
        var correct = Array(repeating: 0, count: foldCount)
        for index in truths.indices { if truths[index] == predictions[index] { correct[index % foldCount] += 1 } }
        self.predictions = predictions; evaluation = Evaluation(classes, truths, predictions); foldCorrect = correct
    }
}
struct Training {
    let bigrams: Bool
    let vocabulary: Vocabulary
    let counts: TrainingCounts
    let rocchio: Rocchio
    var models: [NaiveBayes] = []
    init(_ documents: [Document], _ bigrams: Bool, _ classes: Int, _ minDF: Int, _ size: Int) {
        let sequences = documents.map { $0.tokens.terms(bigrams) }, labels = documents.map { $0.label! }
        let vocabulary = Vocabulary(sequences, labels, classes, minDF, size)
        let encoded = sequences.map { vocabulary.encode($0) }
        self.bigrams = bigrams; self.vocabulary = vocabulary
        counts = TrainingCounts(encoded, labels, classes, vocabulary.size)
        rocchio = Rocchio(encoded, labels, classes, vocabulary.frequencies)
    }
    mutating func train(_ alphas: [Int]) { models = (0..<3).map { NaiveBayes.train($0, counts, alphas[$0]) } }
    func encode(_ document: Document) -> [Int] { vocabulary.encode(document.tokens.terms(bigrams)) }
    func classify(_ model: Int, _ sequence: [Int]) -> Prediction { model == 3 ? rocchio.predict(sequence) : models[model].predict(sequence) }
}
struct Experiment {
    let settings: Settings
    let classes: [String]
    let training: [Document]
    let tests: [Document]
    let unlabelled: [Document]
    let labelled: [Int]
    let truths: [Int]
    let folds: [FoldSummary]
    let cvRuns: [[CrossValidationRun]]
    let selectedPositions: [Int]
    let selected: [Int]
    let finalTraining: Training
    let testSequences: [[Int]]
    let predictions: [[Prediction]]
    let correct: [[Bool]]
    init() throws {
        let settings = Settings(try readLines("params.txt")), stopwords = Set(try readLines("stopwords.txt"))
        let rows = try readLines("train.txt").map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
        let classes = Set(rows.map { $0[0] }).sorted()
        let positions = Dictionary(uniqueKeysWithValues: classes.enumerated().map { ($0.element, $0.offset) })
        let training = rows.enumerated().map { index, row in Document(name: String(index + 1), label: positions[row[0]]!, tokens: Tokens(row[1], stopwords)) }
        let tests = try readLines("test.txt").map { line -> Document in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            return Document(name: fields[0], label: positions[fields[1]], tokens: Tokens(fields[2], stopwords))
        }
        let unlabelled = try readLines("unlabelled.txt").enumerated().map { Document(name: String($0.offset + 1), label: nil, tokens: Tokens($0.element, stopwords)) }
        let labelled = tests.indices.filter { tests[$0].label != nil }, truths = labelled.map { tests[$0].label! }
        let trainingTruths = training.map { $0.label! }
        var nbPredictions = Array(repeating: Array(repeating: Array(repeating: 0, count: training.count), count: settings.alphas.count), count: 3)
        var rocchioPredictions = Array(repeating: 0, count: training.count)
        var folds: [FoldSummary] = []
        for fold in 0..<foldCount {
            let members = training.indices.filter { $0 % foldCount != fold }.map { training[$0] }
            let heldOut = training.indices.filter { $0 % foldCount == fold }
            let fitted = Training(members, settings.bigrams, classes.count, settings.minDF, settings.features)
            folds.append(FoldSummary(train: members.count, validate: heldOut.count, candidates: fitted.vocabulary.candidateCount, vocabulary: fitted.vocabulary.size))
            let sequences = heldOut.map { fitted.encode(training[$0]) }
            for kind in 0..<3 {
                for (a, alpha) in settings.alphas.enumerated() {
                    let model = NaiveBayes.train(kind, fitted.counts, alpha)
                    for (index, sequence) in zip(heldOut, sequences) { nbPredictions[kind][a][index] = model.predict(sequence).label }
                }
            }
            for (index, sequence) in zip(heldOut, sequences) { rocchioPredictions[index] = fitted.rocchio.predict(sequence).label }
        }
        var cvRuns = nbPredictions.map { $0.map { CrossValidationRun($0, trainingTruths, classes.count) } }
        cvRuns.append([CrossValidationRun(rocchioPredictions, trainingTruths, classes.count)])
        var selectedPositions = Array(repeating: 0, count: 3)
        for kind in 0..<3 {
            for a in 1..<settings.alphas.count {
                if rounded(cvRuns[kind][a].evaluation.macroF1) > rounded(cvRuns[kind][selectedPositions[kind]].evaluation.macroF1) { selectedPositions[kind] = a }
            }
        }
        let selected = selectedPositions.map { settings.alphas[$0] }
        var finalTraining = Training(training, settings.bigrams, classes.count, settings.minDF, settings.features)
        finalTraining.train(selected)
        let testSequences = tests.map { finalTraining.encode($0) }
        var predictions = (0..<4).map { model in testSequences.map { finalTraining.classify(model, $0) } }
        let votes = tests.indices.map { index in majorityVote((0..<4).map { predictions[$0][index].label }, classes.count) }
        predictions.append(votes)
        let correct = (0..<5).map { model in labelled.map { predictions[model][$0].label == tests[$0].label! } }
        self.settings = settings; self.classes = classes; self.training = training; self.tests = tests; self.unlabelled = unlabelled
        self.labelled = labelled; self.truths = truths; self.folds = folds; self.cvRuns = cvRuns
        self.selectedPositions = selectedPositions; self.selected = selected; self.finalTraining = finalTraining
        self.testSequences = testSequences; self.predictions = predictions; self.correct = correct
    }
    func alphaText(_ model: Int) -> String { model < 3 ? hundredthsText(selected[model]) : "-" }
    func selectedRun(_ model: Int) -> CrossValidationRun { cvRuns[model][model < 3 ? selectedPositions[model] : 0] }
    func trained(_ documents: [Document], _ bigrams: Bool, _ size: Int) -> Training {
        var fitted = Training(documents, bigrams, classes.count, settings.minDF, size)
        fitted.train(selected)
        return fitted
    }
    func testEvaluations(_ fitted: Training) -> [Evaluation] {
        let sequences = labelled.map { fitted.encode(tests[$0]) }
        return (0..<4).map { model in Evaluation(classes.count, truths, sequences.map { fitted.classify(model, $0).label }) }
    }
    func vocabularyLines() -> [String] {
        let vocabulary = finalTraining.vocabulary
        var lines = ["documents \(training.count) terms \(vocabulary.termCount) candidates \(vocabulary.candidateCount) vocabulary \(vocabulary.size)"]
        for (index, entry) in vocabulary.ranking.enumerated() { lines.append("\(index + 1) \(entry.term) \(entry.frequency) \(realText(entry.score)) \(classes[entry.bestClass])") }
        return lines
    }
    func cvLines() -> [String] {
        var lines = ["model,alpha,correct,accuracy,macro_f1,selected"]
        for kind in 0..<3 {
            for (position, alpha) in settings.alphas.enumerated() {
                let chosen = alpha == selected[kind] ? "yes" : "no"
                lines.append("\(modelNames[kind]),\(hundredthsText(alpha)),\(cvRuns[kind][position].evaluation.fields),\(chosen)")
            }
        }
        lines.append("rocchio,-,\(cvRuns[3][0].evaluation.fields),yes")
        return lines
    }
    func predictionLines() -> [String] {
        var lines = ["id,model,label,score"]
        for index in tests.indices {
            for model in 0..<5 { let prediction = predictions[model][index]; lines.append("\(tests[index].name),\(modelNames[model]),\(classes[prediction.label]),\(realText(prediction.score))") }
        }
        return lines
    }
    func curveLines() -> [String] {
        var lines = ["size,vocabulary,model,correct,accuracy,macro_f1"]
        for size in settings.curve {
            let fitted = trained(Array(training.prefix(size)), settings.bigrams, settings.features)
            for (model, evaluation) in testEvaluations(fitted).enumerated() { lines.append("\(size),\(fitted.vocabulary.size),\(modelNames[model]),\(evaluation.fields)") }
        }
        return lines
    }
    func featureLines() -> [String] {
        var lines = ["terms,features,vocabulary,model,correct,accuracy,macro_f1"]
        for (kind, bigrams) in [("unigrams", false), ("bigrams", true)] {
            for size in settings.sizes {
                let fitted = trained(training, bigrams, size)
                for (model, evaluation) in testEvaluations(fitted).enumerated() { lines.append("\(kind),\(size),\(fitted.vocabulary.size),\(modelNames[model]),\(evaluation.fields)") }
            }
        }
        return lines
    }
    func dataPart() -> [String] {
        let vocabulary = finalTraining.vocabulary
        var lines = ["documents train \(training.count) test \(tests.count) labelled \(labelled.count) unlabelled \(unlabelled.count) classes \(classes.count)"]
        var trainCounts = Array(repeating: 0, count: classes.count), testCounts = Array(repeating: 0, count: classes.count)
        for document in training { trainCounts[document.label!] += 1 }
        for truth in truths { testCounts[truth] += 1 }
        for label in classes.indices { lines.append("class \(classes[label]) train \(trainCounts[label]) test \(testCounts[label])") }
        var raw = 0, stopwords = 0, short = 0, kept = 0, bigrams = 0
        var terms = Set<String>()
        for document in training {
            let tokens = document.tokens
            raw += tokens.rawCount; stopwords += tokens.stopwordCount; short += tokens.shortCount; kept += tokens.words.count
            if settings.bigrams { bigrams += tokens.bigrams.count }
            terms.formUnion(tokens.terms(settings.bigrams))
        }
        let distinctBigrams = terms.filter { $0.contains("_") }.count
        lines.append("train_tokens raw \(raw) stopwords \(stopwords) short \(short) unigrams \(kept) bigrams \(bigrams)")
        lines.append("train_terms unigrams \(terms.count - distinctBigrams) bigrams \(distinctBigrams) candidates \(vocabulary.candidateCount) vocabulary \(vocabulary.size)")
        let total = tests.reduce(0) { $0 + $1.tokens.terms(settings.bigrams).count }
        let inVocabulary = testSequences.reduce(0) { $0 + $1.count }
        lines.append("test_terms total \(total) in_vocabulary \(inVocabulary)")
        var occurrences: [String: Int] = [:]
        for document in tests { for word in document.tokens.words { if vocabulary.index[word] == nil { occurrences[word, default: 0] += 1 } } }
        let ranked = occurrences.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        lines.append((["test_oov"] + ranked.prefix(settings.top).map { "\($0.key) \($0.value)" }).joined(separator: " "))
        return lines
    }
    func foldsPart() -> [String] {
        var lines = ["folds \(foldCount)"]
        for (index, summary) in folds.enumerated() { lines.append("fold \(index + 1) train \(summary.train) validate \(summary.validate) candidates \(summary.candidates) vocabulary \(summary.vocabulary)") }
        return lines
    }
    func selectionPart() -> [String] {
        var lines = ["selection"]
        for model in 0..<4 {
            let run = selectedRun(model), evaluation = run.evaluation
            let foldText = run.foldCorrect.map(String.init).joined(separator: " ")
            lines.append("\(modelNames[model]) alpha \(alphaText(model)) correct \(proportionText(evaluation.correct, evaluation.total)) macro_f1 \(realText(evaluation.macroF1)) folds \(foldText)")
        }
        return lines
    }
    func crossValidationPart(_ model: Int) -> [String] { ["cross_validation \(modelNames[model]) alpha \(alphaText(model))"] + selectedRun(model).evaluation.lines(classes) }
    func testPart(_ model: Int) -> [String] {
        let predicted = labelled.map { predictions[model][$0].label }
        let evaluation = Evaluation(classes.count, truths, predicted)
        var lines = ["test \(modelNames[model]) alpha \(alphaText(model))", "labelled \(labelled.count) correct \(proportionText(evaluation.correct, evaluation.total))"]
        if model < 4 {
            let topTwo = labelled.filter { predictions[model][$0].ranking.prefix(2).contains(tests[$0].label!) }.count
            lines.append("top2 \(proportionText(topTwo, labelled.count))")
        }
        lines += evaluation.lines(classes)
        return lines
    }
    func probabilityPart(_ model: Int) -> [String] {
        let thresholds = settings.thresholds, limits = settings.thresholds.map { Double($0) / 100.0 }
        var rows = Array(repeating: 0, count: limits.count + 1), hits = Array(repeating: 0, count: limits.count + 1)
        var sums = Array(repeating: 0.0, count: limits.count + 1)
        var accepted = Array(repeating: 0, count: limits.count), acceptedHits = Array(repeating: 0, count: limits.count)
        var loss = 0.0, brier = 0.0
        for (position, index) in labelled.enumerated() {
            let prediction = predictions[model][index], truth = truths[position]
            let gap = prediction.scores[truth] - prediction.scores[prediction.label]
            loss += log(prediction.normalizer) - gap
            var squares = 0.0
            for label in classes.indices { let difference = prediction.probabilities[label] - (label == truth ? 1.0 : 0.0); squares += difference * difference }
            brier += squares
            let bucket = limits.filter { prediction.score >= $0 }.count
            rows[bucket] += 1; sums[bucket] += prediction.score
            if correct[model][position] { hits[bucket] += 1 }
            for t in limits.indices {
                if prediction.score >= limits[t] { accepted[t] += 1; if correct[model][position] { acceptedHits[t] += 1 } }
            }
        }
        let count = labelled.count
        var lines = ["probability \(modelNames[model]) alpha \(alphaText(model))", "log_loss \(realText(loss / Double(count))) brier \(realText(brier / Double(count)))"]
        for (bucket, bound) in ([0] + thresholds).enumerated() {
            var line = "bin \(hundredthsText(bound)) rows \(rows[bucket])"
            if rows[bucket] > 0 { line += " correct \(proportionText(hits[bucket], rows[bucket])) mean \(realText(sums[bucket] / Double(rows[bucket])))" }
            lines.append(line)
        }
        for t in thresholds.indices {
            let precise = accepted[t] > 0 ? proportionText(acceptedHits[t], accepted[t]) : "-"
            lines.append("threshold \(hundredthsText(thresholds[t])) covered \(proportionText(accepted[t], count)) correct \(precise)")
        }
        return lines
    }
    func lengthsPart() -> [String] {
        var rows = Array(repeating: 0, count: settings.lengths.count + 1)
        var hits = Array(repeating: rows, count: 5)
        for (position, index) in labelled.enumerated() {
            let bucket = settings.lengths.filter { testSequences[index].count >= $0 }.count
            rows[bucket] += 1
            for model in 0..<5 { if correct[model][position] { hits[model][bucket] += 1 } }
        }
        var lines = ["lengths"]
        for (bucket, bound) in ([0] + settings.lengths).enumerated() {
            var line = "length \(bound) rows \(rows[bucket])"
            if rows[bucket] > 0 { for model in 0..<5 { line += " \(modelNames[model]) \(proportionText(hits[model][bucket], rows[bucket]))" } }
            lines.append(line)
        }
        return lines
    }
    func comparisonPart() -> [String] {
        var lines = ["comparison"]
        for (first, second) in modelPairs {
            let agree = tests.indices.filter { predictions[first][$0].label == predictions[second][$0].label }.count
            let b = labelled.indices.filter { correct[first][$0] && !correct[second][$0] }.count
            let c = labelled.indices.filter { correct[second][$0] && !correct[first][$0] }.count
            let difference = max(0, abs(b - c) - 1)
            let statistic = b + c == 0 ? fractionText(0, 1) : fractionText(difference * difference, b + c)
            lines.append("\(modelNames[first]) \(modelNames[second]) agree \(proportionText(agree, tests.count)) b \(b) c \(c) statistic \(statistic)")
        }
        var errors = Array(repeating: 0, count: 5)
        for position in labelled.indices { errors[(0..<4).filter { !correct[$0][position] }.count] += 1 }
        lines.append("errors " + errors.enumerated().map { "\($0.offset) \($0.element)" }.joined(separator: " "))
        return lines
    }
    func bootstrapPart() -> [String] {
        let count = labelled.count
        var state = settings.seed, totals = Array(repeating: [Int](), count: 5)
        for _ in 0..<settings.resamples {
            var chosen: [Int] = []
            for _ in 0..<count { state = 48271 * state % 2147483647; chosen.append(state % count) }
            for model in 0..<5 { totals[model].append(chosen.filter { correct[model][$0] }.count) }
        }
        let rank = settings.resamples / 40
        var lines = ["bootstrap resamples \(settings.resamples) seed \(settings.seed)"]
        for model in 0..<5 {
            let ordered = totals[model].sorted()
            let mean = Double(ordered.reduce(0, +)) / Double(settings.resamples * count)
            lines.append("\(modelNames[model]) mean \(realText(mean)) low \(proportionText(ordered[rank], count)) high \(proportionText(ordered[ordered.count - 1 - rank], count))")
        }
        for (first, second) in modelPairs {
            var wins = 0, ties = 0, losses = 0
            for (one, other) in zip(totals[first], totals[second]) { if one > other { wins += 1 } else if one == other { ties += 1 } else { losses += 1 } }
            lines.append("pair \(modelNames[first]) \(modelNames[second]) wins \(wins) ties \(ties) losses \(losses)")
        }
        return lines
    }
    func hardPart() -> [String] {
        var hard: [(Document, [Int])] = [], counts = Array(repeating: 0, count: classes.count)
        for (index, document) in training.enumerated() {
            let predicted = (0..<4).map { selectedRun($0).predictions[index] }
            if predicted.allSatisfy({ $0 != document.label! }) { counts[document.label!] += 1; hard.append((document, predicted)) }
        }
        var lines = ["hard_documents \(hard.count) \(classCountsText(classes, counts))"]
        for (document, predicted) in hard.prefix(settings.top) { lines.append("\(document.name) true \(classes[document.label!]) predicted " + predicted.map { classes[$0] }.joined(separator: " ")) }
        return lines
    }
    func uncertainPart() -> [String] {
        let order = tests.indices.sorted { a, b in
            let first = rounded(predictions[0][a].margin), second = rounded(predictions[0][b].margin)
            return first == second ? a < b : first < second
        }
        let shown = order.prefix(settings.top)
        var lines = ["uncertain multinomial \(shown.count)"]
        for index in shown {
            let document = tests[index], prediction = predictions[0][index]
            let truth = document.label.map { classes[$0] } ?? "?"
            lines.append("\(document.name) predicted \(classes[prediction.label]) runner_up \(classes[prediction.ranking[1]]) margin \(realText(prediction.margin)) posterior \(realText(prediction.score)) true \(truth)")
        }
        return lines
    }
    func misclassifiedPart() -> [String] {
        let indices = labelled.filter { predictions[0][$0].label != tests[$0].label! }
        var lines = ["misclassified multinomial \(indices.count)"]
        let counts = finalTraining.counts, weights = finalTraining.models[0].weights, alpha = selected[0]
        for index in indices {
            let document = tests[index], prediction = predictions[0][index]
            let truth = document.label!, predicted = prediction.label, sequence = testSequences[index]
            lines.append("\(document.name) true \(classes[truth]) predicted \(classes[predicted]) posterior \(realText(prediction.score))")
            let entries = firstOccurrences(sequence).map { term in (100 * counts.occurrences[predicted][term] + alpha, 100 * counts.occurrences[truth][term] + alpha, term) }
            for (_, _, term) in rankedRatios(entries).prefix(3) {
                let frequency = sequence.filter { $0 == term }.count
                lines.append("  \(finalTraining.vocabulary.terms[term]) count \(frequency) evidence \(realText(weights[predicted][term] - weights[truth][term]))")
            }
        }
        return lines
    }
    func maximization(_ posteriors: [Prediction], _ sequences: [[Int]]) -> NaiveBayes {
        let counts = finalTraining.counts, weight = Double(settings.weight) / 100.0
        var occurrences = counts.occurrences.map { $0.map(Double.init) }, documents = counts.documents.map(Double.init)
        for (posterior, sequence) in zip(posteriors, sequences) {
            var frequencies = Array(repeating: 0, count: counts.vocabularySize)
            for term in sequence { frequencies[term] += 1 }
            let terms = firstOccurrences(sequence)
            for label in classes.indices {
                let share = weight * posterior.probabilities[label]
                documents[label] += share
                for term in terms { occurrences[label][term] += share * Double(frequencies[term]) }
            }
        }
        let alpha = Double(selected[0])
        var weights: [[Double]] = []
        for row in occurrences {
            var total = 0.0
            for value in row { total += value }
            weights.append(row.map { log((100.0 * $0 + alpha) / (100.0 * total + alpha * Double(counts.vocabularySize))) })
        }
        let scale = Double(training.count) + Double(settings.weight * unlabelled.count) / 100.0
        return NaiveBayes(kind: 0, priors: documents.map { log($0 / scale) }, base: Array(repeating: 0, count: classes.count), weights: weights)
    }
    func semiSupervisedPart() -> [String] {
        let sequences = unlabelled.map { finalTraining.encode($0) }
        var model = finalTraining.models[0], previous: [Int]? = nil
        var lines = ["semi_supervised multinomial alpha \(alphaText(0)) weight \(hundredthsText(settings.weight)) unlabelled \(unlabelled.count)"]
        for iteration in 0...settings.iterations {
            let posteriors = sequences.map { model.predict($0) }, assignments = posteriors.map(\.label)
            let predicted = labelled.map { model.predict(testSequences[$0]).label }
            let evaluation = Evaluation(classes.count, truths, predicted)
            let changed = previous.map { old in String(zip(old, assignments).filter { $0.0 != $0.1 }.count) } ?? "-"
            var assigned = Array(repeating: 0, count: classes.count)
            for label in assignments { assigned[label] += 1 }
            lines.append("iteration \(iteration) correct \(proportionText(evaluation.correct, evaluation.total)) macro_f1 \(realText(evaluation.macroF1)) changed \(changed) assigned \(classCountsText(classes, assigned))")
            if iteration < settings.iterations { model = maximization(posteriors, sequences) }
            previous = assignments
        }
        return lines
    }
    func metricsParts() -> [[String]] {
        var parts = [dataPart(), foldsPart(), selectionPart()]
        parts += (0..<4).map(crossValidationPart); parts += (0..<5).map(testPart); parts += (0..<3).map(probabilityPart)
        parts += [lengthsPart(), comparisonPart(), bootstrapPart(), hardPart(), uncertainPart(), misclassifiedPart(), semiSupervisedPart()]
        return parts
    }
    func topFeatureParts() -> [[String]] {
        let counts = finalTraining.counts, size = counts.vocabularySize
        var parts: [[String]] = []
        for kind in 0..<2 {
            let alpha = selected[kind], table = kind == 0 ? counts.occurrences : counts.containing
            let totals = kind == 0 ? counts.totals : counts.documents, overall = kind == 0 ? counts.total : counts.documentTotal
            let outcomes = kind == 0 ? size : 2
            let termTotals = (0..<size).map { term in table.reduce(0) { $0 + $1[term] } }
            parts.append(["model \(modelNames[kind]) alpha \(hundredthsText(alpha)) vocabulary \(size) top \(settings.top)"])
            for label in classes.indices {
                let total = totals[label], other = overall - total
                var lines = ["class \(classes[label]) total \(total) other \(other)"]
                let entries = (0..<size).map { term in (100 * table[label][term] + alpha, 100 * (termTotals[term] - table[label][term]) + alpha, term) }
                for (rank, entry) in rankedRatios(entries).prefix(settings.top).enumerated() {
                    let term = entry.2, count = table[label][entry.2], otherCount = termTotals[entry.2] - table[label][entry.2]
                    let odds = smoothedLog(count, total, alpha, outcomes) - smoothedLog(otherCount, other, alpha, outcomes)
                    lines.append("\(rank + 1) \(finalTraining.vocabulary.terms[term]) \(count) \(otherCount) \(realText(odds))")
                }
                parts.append(lines)
            }
        }
        return parts
    }
}
func main() throws {
    let experiment = try Experiment()
    try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    try writeLines("vocabulary.txt", experiment.vocabularyLines()); try writeLines("cv_results.csv", experiment.cvLines())
    try writeLines("predictions.csv", experiment.predictionLines()); try writeLines("learning_curve.csv", experiment.curveLines())
    try writeLines("feature_study.csv", experiment.featureLines()); try writeLines("metrics.txt", joinParts(experiment.metricsParts()))
    try writeLines("top_features.txt", joinParts(experiment.topFeatureParts()))
}
try main()
