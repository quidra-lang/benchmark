import Foundation

struct Outcome {
    let id: String
    let label: Int
    let predicted: Int
    let confidence: Double
    let scores: [Double]
    let loss: Double
    let hidden: [[Double]]
    var correct: Bool { predicted == label }
}
struct Evaluation { let loss: Double; let correct: Int; let outcomes: [Outcome] }
func evaluate(_ network: Network, _ theta: [Double], _ images: [Image]) -> Evaluation {
    var outcomes: [Outcome] = [], loss = 0.0, correct = 0
    for image in images {
        let cache = network.forward(theta, image), predicted = bestTwo(cache.scores)[0]
        outcomes.append(Outcome(id: image.id, label: image.label, predicted: predicted, confidence: cache.scores[predicted], scores: cache.scores, loss: cache.loss, hidden: Array(cache.activations.dropFirst().dropLast())))
        loss += cache.loss; if predicted == image.label { correct += 1 }
    }
    return Evaluation(loss: loss / Double(images.count), correct: correct, outcomes: outcomes)
}
func averageGradient(_ network: Network, _ theta: [Double], _ images: [Image]) -> [Double] {
    var values = Array(repeating: 0.0, count: network.parameterCount)
    for image in images { let gradient = network.gradient(theta, image).parameters; for i in values.indices { values[i] += gradient[i] } }
    return values.map { $0 / Double(images.count) }
}
func mean(_ values: [Double]) -> Double { var total = 0.0; for value in values { total += value }; return total / Double(values.count) }
func weightedL2(_ values: [Double]) -> Double { var total = 0.0; for value in values { total += value * value }; return sqrt(total) }
func checkNetwork(_ network: Network, _ training: [Image], _ settings: Settings) -> [String] {
    var generator = MINSTD(state: settings.seed), order = Array(training.indices), theta = network.initial
    generator.shuffle(&order)
    let images = order.prefix(min(settings.batchSize, training.count)).map { training[$0] }, analytic = averageGradient(network, theta, images), checked = Array(stride(from: 0, to: network.parameterCount, by: settings.gradientStride)), selected = Set(checked), h = 0.00001
    var passed = true
    for index in checked { let original = theta[index]; theta[index] = original + h; let higher = evaluate(network, theta, images).loss; theta[index] = original - h; let lower = evaluate(network, theta, images).loss; theta[index] = original; let derivative = (higher - lower) / (2 * h), error = abs(analytic[index] - derivative) / max(1, abs(analytic[index]) + abs(derivative)); if error >= 0.000001 { passed = false } }
    var lines = ["network \(network.name)", "parameters \(network.parameterCount)", "batch " + images.map { $0.id }.joined(separator: " ")]
    for (index, layer) in network.layers.enumerated() { let weights = (layer.weightStart..<layer.weightEnd).filter { selected.contains($0) }.count, biases = (layer.biasStart..<layer.biasEnd).filter { selected.contains($0) }.count; lines.append("layer \(index + 1) weights \(weights) biases \(biases)") }
    lines += ["checked \(checked.count)", "result \(passed ? "PASS" : "FAIL")"]
    return lines
}
struct EpochRecord { let epoch: Int; let rate: Double; let gradientNorm: Double; let trainingLoss: Double; let trainingCorrect: Int; let validationLoss: Double; let validationCorrect: Int; let improved: Bool }
struct TrainingResult {
    let definition: RunDefinition
    let network: Network
    let theta: [Double]
    let bestEpoch: Int
    let bestValidationLoss: Double
    let bestValidationCorrect: Int
    let epochs: [EpochRecord]
    let updates: Int
    let stop: String
    let correctness: [[Bool]]
}
func trainRun(_ definition: RunDefinition, _ network: Network, _ training: [Image], _ validation: [Image], _ settings: Settings) -> TrainingResult {
    var theta = network.initial, state = OptimizerState(network.parameterCount), generator = MINSTD(state: settings.seed), order = Array(training.indices), epochs: [EpochRecord] = [], correctness: [[Bool]] = []
    var bestEpoch = 0, bestLoss = 0.0, bestTheta = theta, savedCorrect = 0, wait = 0, updates = 0, stop = "max_epochs"
    for epoch in 1...settings.maximumEpochs {
        let rate = epochRate(definition, epoch, settings)
        generator.shuffle(&order)
        var norms: [Double] = []
        for start in stride(from: 0, to: order.count, by: settings.batchSize) {
            let images = order[start..<min(start + settings.batchSize, order.count)].map { training[$0] }
            var gradient = averageGradient(network, theta, images)
            for i in gradient.indices where network.isWeight[i] { gradient[i] += definition.decay * theta[i] }
            norms.append(weightedL2(gradient)); state.update(&theta, gradient, definition.optimizer, rate); updates += 1
        }
        let trainEvaluation = evaluate(network, theta, training), validationEvaluation = evaluate(network, theta, validation), improved = bestEpoch == 0 || validationEvaluation.loss < bestLoss
        correctness.append(trainEvaluation.outcomes.map { $0.correct })
        if improved { bestEpoch = epoch; bestLoss = validationEvaluation.loss; savedCorrect = validationEvaluation.correct; bestTheta = theta; wait = 0 } else { wait += 1 }
        epochs.append(EpochRecord(epoch: epoch, rate: rate, gradientNorm: mean(norms), trainingLoss: trainEvaluation.loss, trainingCorrect: trainEvaluation.correct, validationLoss: validationEvaluation.loss, validationCorrect: validationEvaluation.correct, improved: improved))
        if wait >= settings.patience { stop = "early"; break }
    }
    return TrainingResult(definition: definition, network: network, theta: bestTheta, bestEpoch: bestEpoch, bestValidationLoss: bestLoss, bestValidationCorrect: savedCorrect, epochs: epochs, updates: updates, stop: stop, correctness: correctness)
}
struct Forgetting { let events: Int; let rows: Int; let never: Int }
struct HiddenSummary { let means: [[Double]?]; let preferred: [Int]; let zeros: [Int] }
struct PruningResult { let percentage: Int; let removed: Int; let correct: Int; let loss: Double }
struct NoiseResult { let percentage: Int; let flipped: Int; let correct: Int }
struct RunEvaluation {
    let training: TrainingResult
    let testing: Evaluation
    let matrix: [[Int]]
    let topTwo: Int
    let confidenceCorrect: Double?
    let confidenceWrong: Double?
    let forgetting: Forgetting
    let weightNorms: [Double]
    let weightChanges: [Double]
    let bins: [[Outcome]]
    let ece: Double
    let hidden: [HiddenSummary]
    let pruning: [PruningResult]
    let noise: [NoiseResult]
    var name: String { training.definition.name }
}
func evaluateRun(_ run: TrainingResult, _ training: [Image], _ testing: [Image], _ settings: Settings) -> RunEvaluation {
    let network = run.network, theta = run.theta, testEvaluation = evaluate(network, theta, testing), outcomes = testEvaluation.outcomes, correctConfidence = outcomes.filter { $0.correct }.map { $0.confidence }, wrongConfidence = outcomes.filter { !$0.correct }.map { $0.confidence }
    var events = Array(repeating: 0, count: training.count), never = 0
    for i in training.indices { for epoch in 1..<run.correctness.count { if run.correctness[epoch - 1][i] && !run.correctness[epoch][i] { events[i] += 1 } }; if !run.correctness.contains(where: { $0[i] }) { never += 1 } }
    var norms: [Double] = [], changes: [Double] = []
    for layer in network.layers { let indices = layer.weightStart..<layer.weightEnd; norms.append(weightedL2(indices.map { theta[$0] })); changes.append(weightedL2(indices.map { theta[$0] - network.initial[$0] })) }
    var bins = Array(repeating: [Outcome](), count: settings.calibrationBins), ece = 0.0
    for outcome in outcomes { let index = min(settings.calibrationBins - 1, Int(floor(outcome.confidence * Double(settings.calibrationBins)))); bins[index].append(outcome) }
    for bin in bins where !bin.isEmpty { let correct = bin.filter { $0.correct }.count, confidence = mean(bin.map { $0.confidence }); ece += Double(bin.count) / Double(testing.count) * abs(Double(correct) / Double(bin.count) - confidence) }
    var hidden: [HiddenSummary] = []
    for (index, layer) in network.layers.dropLast().enumerated() {
        var means: [[Double]?] = []
        for number in 0..<network.classes { let subset = outcomes.filter { $0.label == number }; means.append(subset.isEmpty ? nil : (0..<layer.outputs).map { j in mean(subset.map { $0.hidden[index][j] }) }) }
        let candidates = means.indices.filter { means[$0] != nil }
        var preferred: [Int] = []
        for j in 0..<layer.outputs { var best = candidates[0]; for number in candidates.dropFirst() { if means[number]![j] > means[best]![j] { best = number } }; preferred.append(best) }
        hidden.append(HiddenSummary(means: means, preferred: preferred, zeros: (0..<layer.outputs).map { j in outcomes.filter { $0.hidden[index][j] == 0 }.count }))
    }
    let weightOrder = theta.indices.filter { network.isWeight[$0] }.sorted { abs(theta[$0]) == abs(theta[$1]) ? $0 < $1 : abs(theta[$0]) < abs(theta[$1]) }
    var pruning: [PruningResult] = [], noise: [NoiseResult] = []
    for percentage in settings.pruning { let count = percentage * network.weightCount / 100; var pruned = theta; for i in weightOrder.prefix(count) { pruned[i] = 0 }; let result = evaluate(network, pruned, testing); pruning.append(PruningResult(percentage: percentage, removed: count, correct: result.correct, loss: result.loss)) }
    for percentage in settings.noise {
        var generator = MINSTD(state: settings.seed), altered = testing, flipped = 0
        for i in altered.indices { for j in altered[i].vector.indices { if generator.draw() % 100 < percentage { altered[i].vector[j] = 1 - altered[i].vector[j]; flipped += 1 } } }
        noise.append(NoiseResult(percentage: percentage, flipped: flipped, correct: evaluate(network, theta, altered).correct))
    }
    return RunEvaluation(training: run, testing: testEvaluation, matrix: confusion(outcomes, network.classes), topTwo: outcomes.filter { bestTwo($0.scores).contains($0.label) }.count, confidenceCorrect: correctConfidence.isEmpty ? nil : mean(correctConfidence), confidenceWrong: wrongConfidence.isEmpty ? nil : mean(wrongConfidence), forgetting: Forgetting(events: events.reduce(0, +), rows: events.filter { $0 > 0 }.count, never: never), weightNorms: norms, weightChanges: changes, bins: bins, ece: ece, hidden: hidden, pruning: pruning, noise: noise)
}
func trainingLogLines(_ runs: [RunEvaluation], _ trainingCount: Int, _ validationCount: Int) -> [String] {
    var lines = ["run,epoch,lr,grad_norm,train_loss,train_acc,val_loss,val_acc,improved"]
    for run in runs { for epoch in run.training.epochs { lines.append([run.name, String(epoch.epoch), real(epoch.rate, 6), real(epoch.gradientNorm, 4), real(epoch.trainingLoss, 6), ratio(epoch.trainingCorrect, trainingCount), real(epoch.validationLoss, 6), ratio(epoch.validationCorrect, validationCount), epoch.improved ? "1" : "0"].joined(separator: ",")) } }
    return lines
}
func finalWeightLines(_ runs: [RunEvaluation]) -> [String] {
    var lines: [String] = []
    for run in runs {
        if !lines.isEmpty { lines.append("") }
        let training = run.training, network = training.network, theta = training.theta
        lines.append("RUN \(run.name) NETWORK \(network.name) EPOCH \(training.bestEpoch)")
        for (index, layer) in network.layers.enumerated() { lines.append("LAYER \(index + 1) \(layer.outputs) \(layer.inputs)"); for j in 0..<layer.outputs { let start = layer.weightStart + j * layer.inputs; lines.append("W " + theta[start..<(start + layer.inputs)].map { real($0, 4) }.joined(separator: " ")) }; lines.append("B " + theta[layer.biasStart..<layer.biasEnd].map { real($0, 4) }.joined(separator: " ")) }
    }
    return lines
}
func predictionLines(_ runs: [RunEvaluation]) -> [String] { var lines = ["run,id,label,predicted,confidence"]; for run in runs { for outcome in run.testing.outcomes { lines.append([run.name, outcome.id, String(outcome.label), String(outcome.predicted), real(outcome.confidence, 4)].joined(separator: ",")) } }; return lines }
func dataSummaryLines(_ training: [Image], _ validation: [Image], _ testing: [Image], _ network: Network) -> [String] {
    let pixels = network.width * network.height
    var lines = ["data", "train \(training.count) validation \(validation.count) test \(testing.count) pixels \(pixels)"]
    for number in 0..<network.classes { let group = training.filter { $0.label == number }, ink = group.reduce(0) { $0 + $1.pixels.filter { $0 == 49 }.count }; lines.append("class \(number) train \(group.count) validation \(validation.filter { $0.label == number }.count) test \(testing.filter { $0.label == number }.count) ink \(ratio(ink, group.count))") }
    lines.append("mean_images " + (0..<network.classes).map(String.init).joined(separator: " "))
    lines += levelMaps((0..<network.classes).map { binaryFrequency(training, $0, pixels) }, network.width, network.height)
    return lines
}
func curveLines(_ run: TrainingResult) -> [String] {
    let maximum = run.epochs.map { max($0.trainingLoss, $0.validationLoss) }.max()!
    var lines = ["curve"]
    for epoch in run.epochs { var cells = Array(repeating: " ", count: 40); let trainColumn = Int(floor(39 * epoch.trainingLoss / maximum + 0.5)), validationColumn = Int(floor(39 * epoch.validationLoss / maximum + 0.5)); cells[trainColumn] = "t"; cells[validationColumn] = trainColumn == validationColumn ? "*" : "v"; lines.append((epoch.epoch < 10 ? " " : "") + String(epoch.epoch) + " |" + cells.joined() + "|" + (epoch.epoch == run.bestEpoch ? " best" : "")) }
    return lines
}
func runEvaluationLines(_ run: RunEvaluation, _ validationCount: Int, _ testingCount: Int, _ settings: Settings) -> [String] {
    let training = run.training, network = training.network, correct = run.testing.correct
    var lines = ["run \(run.name) network \(network.name) optimizer \(training.definition.optimizer.name)", "epochs \(training.epochs.count) best_epoch \(training.bestEpoch) stop \(training.stop) updates \(training.updates)", "best_val_loss \(real(training.bestValidationLoss, 6)) best_val_acc \(ratio(training.bestValidationCorrect, validationCount)) correct \(training.bestValidationCorrect)/\(validationCount)", "test_loss \(real(run.testing.loss, 6)) test_acc \(ratio(correct, testingCount)) correct \(correct)/\(testingCount)", "top2_acc \(ratio(run.topTwo, testingCount)) correct \(run.topTwo)/\(testingCount)", "confidence correct \(run.confidenceCorrect.map { real($0, 4) } ?? "-") wrong \(run.confidenceWrong.map { real($0, 4) } ?? "-")", "forgetting events \(run.forgetting.events) rows \(run.forgetting.rows) never_learned \(run.forgetting.never)", "weight_norms " + run.weightNorms.map { real($0, 4) }.joined(separator: " "), "weight_changes " + run.weightChanges.map { real($0, 4) }.joined(separator: " ")]
    lines += curveLines(training); lines.append("confusion")
    for number in 0..<network.classes { lines.append("\(number): " + run.matrix[number].map(String.init).joined(separator: " ")) }
    for number in 0..<network.classes { let measures = classMeasures(run.matrix, number); lines.append("class \(number) support \(measures.support) predicted \(measures.predicted) precision \(measures.precision) recall \(measures.recall) f1 \(measures.f1)") }
    lines.append("calibration")
    for (index, bin) in run.bins.enumerated() { let correct = bin.filter { $0.correct }.count, confidence = bin.isEmpty ? "-" : real(mean(bin.map { $0.confidence }), 4); lines.append("bin \(index + 1) \(real(Double(index) / Double(settings.calibrationBins), 2)) \(real(Double(index + 1) / Double(settings.calibrationBins), 2)) count \(bin.count) accuracy \(ratio(correct, bin.count)) confidence \(confidence)") }
    lines.append("ece \(real(run.ece, 4))")
    for (index, layer) in network.layers.dropLast().enumerated() { let summary = run.hidden[index]; lines.append("hidden \(index + 1) \(layer.activation.rawValue) units \(layer.outputs)"); for number in 0..<network.classes { lines.append("class \(number) mean " + (summary.means[number].map { $0.map { real($0, 4) }.joined(separator: " ") } ?? "-")) }; lines.append("preferred " + summary.preferred.map(String.init).joined(separator: " ")); if layer.activation == .relu { lines.append("zero_counts " + summary.zeros.map(String.init).joined(separator: " ")) } }
    lines.append("pruning")
    for result in run.pruning { lines.append("prune \(result.percentage) removed \(result.removed) correct \(result.correct) test_acc \(ratio(result.correct, testingCount)) test_loss \(real(result.loss, 6))") }
    lines.append("noise")
    for result in run.noise { lines.append("noise \(result.percentage) correct \(result.correct) test_acc \(ratio(result.correct, testingCount))") }
    let wrong = run.testing.outcomes.filter { !$0.correct }
    lines.append("misclassified \(wrong.count)" + (wrong.isEmpty ? "" : " " + wrong.map { $0.id }.joined(separator: " ")))
    return lines
}
struct Ensembles { let majority: [Int]; let soft: [Int]; let softCount: Int }
func ensembles(_ runs: [RunEvaluation], _ rank: [Int], _ testing: [Image]) -> Ensembles {
    let classes = runs[0].training.network.classes, softRuns = runs.indices.filter { runs[$0].training.network.layers.last!.activation == .softmax }
    var majority: [Int] = [], soft: [Int] = []
    for i in testing.indices {
        var votes = Array(repeating: 0, count: classes)
        for run in runs { votes[run.testing.outcomes[i].predicted] += 1 }
        let maximum = votes.max()!, winner = rank.first { votes[runs[$0].testing.outcomes[i].predicted] == maximum }!
        majority.append(runs[winner].testing.outcomes[i].predicted)
        if !softRuns.isEmpty { var means = Array(repeating: 0.0, count: classes); for number in 0..<classes { for index in softRuns { means[number] += runs[index].testing.outcomes[i].scores[number] }; means[number] /= Double(softRuns.count) }; soft.append(bestTwo(means)[0]) }
    }
    return Ensembles(majority: majority, soft: soft, softCount: softRuns.count)
}
func saliencyLines(_ top: RunEvaluation, _ testing: [Image]) -> [String] {
    let network = top.training.network, size = network.width * network.height
    var maps: [[Int]] = []
    for number in 0..<network.classes {
        let chosen = testing.filter { $0.label == number }
        if chosen.isEmpty { maps.append(Array(repeating: 0, count: size)); continue }
        var values = Array(repeating: 0.0, count: size)
        for image in chosen { let gradient = network.gradient(top.training.theta, image).input; for i in values.indices { values[i] += abs(gradient[i]) } }
        values = values.map { $0 / Double(chosen.count) }
        let maximum = values.max()!
        maps.append(maximum > 0 ? values.map { min(9, Int(floor(10 * $0 / maximum))) } : Array(repeating: 0, count: size))
    }
    return ["saliency \(top.name)", "classes " + (0..<network.classes).map(String.init).joined(separator: " ")] + levelMaps(maps, network.width, network.height)
}
func hardestExampleLines(_ top: RunEvaluation, _ training: [Image]) -> [String] {
    let outcomes = evaluate(top.training.network, top.training.theta, training).outcomes, order = training.indices.sorted { outcomes[$0].loss == outcomes[$1].loss ? $0 < $1 : outcomes[$0].loss > outcomes[$1].loss }.prefix(5)
    var lines = ["hardest_training_examples \(top.name)"]
    for i in order { lines.append("\(training[i].id) label \(training[i].label) predicted \(outcomes[i].predicted) loss \(real(outcomes[i].loss, 6))") }
    return lines
}
func misclassifiedExampleLines(_ top: RunEvaluation, _ runs: [RunEvaluation], _ testing: [Image], _ allTraining: [Image], _ majority: [Int]) -> [String] {
    var lines = ["misclassified_examples \(top.name)"]
    for i in testing.indices where !top.testing.outcomes[i].correct {
        let image = testing[i], outcome = top.testing.outcomes[i]
        var nearest = 0, distance = image.pixels.count + 1
        for (index, candidate) in allTraining.enumerated() { let differences = image.pixels.indices.filter { image.pixels[$0] != candidate.pixels[$0] }.count; if differences < distance { distance = differences; nearest = index } }
        let predictions = runs.map { String($0.testing.outcomes[i].predicted) }.joined(separator: " ")
        lines += ["\(image.id) label \(image.label) predicted \(outcome.predicted) confidence \(real(outcome.confidence, 4)) true_score \(real(outcome.scores[image.label], 4)) runs \(predictions) ensemble \(majority[i])", "nearest \(allTraining[nearest].id) label \(allTraining[nearest].label) distance \(distance)"]
        lines += asciiImage(image, top.training.network.width, top.training.network.height)
    }
    return lines
}
func comparisonLines(_ runs: [RunEvaluation], _ training: [Image], _ allTraining: [Image], _ testing: [Image], _ settings: Settings) -> [String] {
    let rank = runs.indices.sorted { first, second in if runs[first].testing.correct != runs[second].testing.correct { return runs[first].testing.correct > runs[second].testing.correct }; if runs[first].training.bestValidationLoss != runs[second].training.bestValidationLoss { return runs[first].training.bestValidationLoss < runs[second].training.bestValidationLoss }; return first < second }, top = runs[rank[0]], size = testing.count, ensemble = ensembles(runs, rank, testing), classes = top.training.network.classes
    var lines = ["comparison"]
    for (index, number) in rank.enumerated() { let run = runs[number], trained = run.training; lines.append("rank \(index + 1) \(run.name) correct \(run.testing.correct) test_acc \(ratio(run.testing.correct, size)) best_val_loss \(real(trained.bestValidationLoss, 6)) test_loss \(real(run.testing.loss, 6)) best_epoch \(trained.bestEpoch) epochs \(trained.epochs.count) updates \(trained.updates)") }
    lines.append("agreement")
    for first in runs { let agreements = runs.map { second in testing.indices.filter { first.testing.outcomes[$0].predicted == second.testing.outcomes[$0].predicted }.count }; lines.append(first.name + " " + agreements.map(String.init).joined(separator: " ")) }
    lines.append("mcnemar \(top.name)")
    for number in rank.dropFirst() { let run = runs[number]; var b = 0, c = 0; for i in testing.indices { if top.testing.outcomes[i].correct && !run.testing.outcomes[i].correct { b += 1 }; if !top.testing.outcomes[i].correct && run.testing.outcomes[i].correct { c += 1 } }; let difference = max(abs(b - c) - 1, 0), numerator = difference * difference, denominator = b + c, chi = denominator == 0 ? "0.0000" : ratio(numerator, denominator); lines.append("vs \(run.name) b \(b) c \(c) chi2 \(chi) significant \(numerator * 1000 > 3841 * denominator ? "yes" : "no")") }
    var majorityCorrect = 0, fixed = 0, broken = 0
    for i in testing.indices { let correct = ensemble.majority[i] == testing[i].label; if correct { majorityCorrect += 1 }; if correct && !top.testing.outcomes[i].correct { fixed += 1 }; if !correct && top.testing.outcomes[i].correct { broken += 1 } }
    lines.append("ensemble correct \(majorityCorrect)/\(size) test_acc \(ratio(majorityCorrect, size)) fixed \(fixed) broken \(broken)")
    if ensemble.softCount > 0 { let correct = testing.indices.filter { ensemble.soft[$0] == testing[$0].label }.count; lines.append("soft_ensemble runs \(ensemble.softCount) correct \(correct)/\(size) test_acc \(ratio(correct, size))") } else { lines.append("soft_ensemble none") }
    for result in runs[0].noise { lines.append("noise \(result.percentage) flipped \(result.flipped)") }
    var total = Array(repeating: Array(repeating: 0, count: classes), count: classes), pairs: [(Int, Int)] = []
    for y in 0..<classes { for p in 0..<classes { for run in runs { total[y][p] += run.matrix[y][p] }; if y != p && total[y][p] > 0 { pairs.append((y, p)) } } }
    pairs.sort { first, second in if total[first.0][first.1] != total[second.0][second.1] { return total[first.0][first.1] > total[second.0][second.1] }; if first.0 != second.0 { return first.0 < second.0 }; return first.1 < second.1 }
    lines.append("confused_pairs")
    for (y, p) in pairs.prefix(5) { lines.append("\(y) as \(p) count \(total[y][p])") }
    lines.append(""); lines += saliencyLines(top, testing)
    lines.append(""); lines += hardestExampleLines(top, training)
    lines.append(""); lines += misclassifiedExampleLines(top, runs, testing, allTraining, ensemble.majority)
    return lines
}
func writeLines(_ name: String, _ lines: [String]) throws { try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true); try (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: false, encoding: .ascii) }
let inputs = try readInputs(), settings = inputs.settings, validationCount = inputs.images.count / 5, split = inputs.images.count - validationCount, training = Array(inputs.images[..<split]), validation = Array(inputs.images[split...])
var checks: [String] = [], runs: [RunEvaluation] = []
for network in inputs.networks { if !checks.isEmpty { checks.append("") }; checks += checkNetwork(network, training, settings) }
for definition in settings.runs { let network = inputs.networks.first { $0.name == definition.networkName }!; runs.append(evaluateRun(trainRun(definition, network, training, validation, settings), training, inputs.testing, settings)) }
var report = dataSummaryLines(training, validation, inputs.testing, inputs.networks[0])
report.append("")
for run in runs { report += runEvaluationLines(run, validation.count, inputs.testing.count, settings); report.append("") }
report += comparisonLines(runs, training, inputs.images, inputs.testing, settings)
try writeLines("gradient_check.txt", checks)
try writeLines("training_log.csv", trainingLogLines(runs, training.count, validation.count))
try writeLines("final_weights.txt", finalWeightLines(runs))
try writeLines("predictions.csv", predictionLines(runs))
try writeLines("evaluation.txt", report)
