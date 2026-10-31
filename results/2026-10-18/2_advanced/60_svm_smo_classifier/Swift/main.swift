import Foundation

func supportCounts(_ model: Model) -> (total: Int, bound: Int, free: Int) {
    let total = model.alpha.filter { $0 > 0 }.count, bound = model.alpha.filter { $0 > 0 && $0 == model.coefficient }.count
    return (total, bound, total - bound)
}
func supportText(_ model: Model) -> String { let counts = supportCounts(model); return "support_vectors \(counts.total) bound \(counts.bound) free \(counts.free)" }
func runInfo(_ model: Model) -> String { "passes \(model.passes) steps \(model.steps) converged \(model.converged ? "yes" : "no")" }
func objectives(_ model: Model, _ override: [Double]? = nil) -> (quadratic: Double, dual: Double) {
    let alpha = override ?? model.alpha
    var scores: [Double] = [], quadratic = 0.0, total = 0.0
    for row in model.matrix { var score = 0.0; for i in alpha.indices where alpha[i] > 0 { score += alpha[i] * Double(model.labels[i]) * row[i] }; scores.append(score) }
    for i in alpha.indices { quadratic += alpha[i] * Double(model.labels[i]) * scores[i]; total += alpha[i] }
    return (quadratic, total - quadratic / 2)
}
struct FoldResult { let training: Int; let testing: Int; let correct: Int; let support: Int; let model: Model }
struct CVResult {
    let kernel: Kernel
    let kernelIndex: Int
    let coefficient: Double
    let values: [Double]
    let folds: [FoldResult]
    let correct: Int
    let support: Int
    let passes: Int
    let steps: Int
}
struct CVSummary { let matrices: [[[Double]]]; let combinations: [CVResult]; let best: [CVResult]; let selected: CVResult; let ranking: [CVResult] }
func ranksBefore(_ first: CVResult, _ second: CVResult) -> Bool { if first.correct != second.correct { return first.correct > second.correct }; if first.coefficient != second.coefficient { return first.coefficient < second.coefficient }; return first.kernelIndex < second.kernelIndex }
func crossValidate(_ examples: [Example], _ settings: Settings) -> CVSummary {
    let points = examples.map { $0.point }, labels = examples.map { $0.label }, partitions = folds(examples.count, settings.foldCount)
    var matrices: [[[Double]]] = [], combinations: [CVResult] = [], best: [CVResult] = []
    for (kernelIndex, kernel) in settings.kernels.enumerated() {
        let matrix = kernel.matrix(points)
        matrices.append(matrix)
        var candidates: [CVResult] = []
        for coefficient in settings.coefficients {
            var values = Array(repeating: 0.0, count: examples.count), foldResults: [FoldResult] = [], totalCorrect = 0, totalSupport = 0, totalPasses = 0, totalSteps = 0
            for partition in partitions {
                let model = train(partition.training.map { points[$0] }, partition.training.map { labels[$0] }, kernel, submatrix(matrix, partition.training), coefficient, settings)
                var correct = 0
                for i in partition.testing { values[i] = model.decision(points[i]); if sign(values[i]) == labels[i] { correct += 1 } }
                let support = supportCounts(model).total
                foldResults.append(FoldResult(training: partition.training.count, testing: partition.testing.count, correct: correct, support: support, model: model))
                totalCorrect += correct; totalSupport += support; totalPasses += model.passes; totalSteps += model.steps
            }
            let result = CVResult(kernel: kernel, kernelIndex: kernelIndex, coefficient: coefficient, values: values, folds: foldResults, correct: totalCorrect, support: totalSupport, passes: totalPasses, steps: totalSteps)
            candidates.append(result); combinations.append(result)
        }
        best.append(candidates.sorted(by: ranksBefore)[0])
    }
    return CVSummary(matrices: matrices, combinations: combinations, best: best, selected: best.sorted(by: ranksBefore)[0], ranking: combinations.sorted(by: ranksBefore))
}
func crossValidationLines(_ size: Int, _ foldCount: Int, _ summary: CVSummary) -> [String] {
    var lines = ["cross_validation folds \(foldCount) examples \(size)"]
    for result in summary.best { lines.append("best \(result.kernel.name) C \(fixed(result.coefficient)) correct \(result.correct)/\(size) accuracy \(ratio(result.correct, size))") }
    let selected = summary.selected
    lines += ["selected \(selected.kernel.name) C \(fixed(selected.coefficient))", "ranking"]
    for (index, result) in summary.ranking.enumerated() { lines.append("\(index + 1) \(result.kernel.name) C \(fixed(result.coefficient)) correct \(result.correct)/\(size)") }
    lines.append("cv_detail \(selected.kernel.name) C \(fixed(selected.coefficient))")
    for (index, result) in selected.folds.enumerated() { lines.append("fold \(index + 1) train \(result.training) test \(result.testing) correct \(result.correct) support_vectors \(result.support) \(runInfo(result.model))") }
    return lines
}
struct FinalEvaluation { let model: Model; let trainingValues: [Double]; let testingValues: [Double]; let weights: Point; let lines: [String] }
func evaluateFinal(_ model: Model, _ training: [Example], _ testing: [Example], _ tolerance: Double) -> FinalEvaluation {
    let n = training.count, m = testing.count, trainingValues = model.trainingDecisions(), testingValues = testing.map { model.decision($0.point) }, testLabels = testing.map { $0.label }, objective = objectives(model)
    var labelAlignment = 0.0, matrixSquares = 0.0, equality = 0.0, w1 = 0.0, w2 = 0.0, positiveBound = 0, positiveFree = 0, negativeBound = 0, negativeFree = 0
    for i in model.matrix.indices { for j in model.matrix[i].indices { let value = model.matrix[i][j]; labelAlignment += Double(model.labels[i] * model.labels[j]) * value; matrixSquares += value * value } }
    for i in training.indices {
        let example = training[i], alpha = model.alpha[i]
        equality += alpha * Double(example.label)
        if model.kernel.isLinear { w1 += alpha * Double(example.label) * example.point.x; w2 += alpha * Double(example.label) * example.point.y }
        if alpha > 0 { if example.label == 1 { if alpha == model.coefficient { positiveBound += 1 } else { positiveFree += 1 } } else { if alpha == model.coefficient { negativeBound += 1 } else { negativeFree += 1 } } }
    }
    let alignment = labelAlignment / (Double(n) * sqrt(matrixSquares)), norm = sqrt(objective.quadratic), radius = model.matrix.indices.map { model.matrix[$0][$0] }.max()! - model.matrix.flatMap { $0 }.min()!
    var hingeTotal = 0.0, violations = 0, estimatedErrors = 0, maximumViolation = 0.0
    for i in training.indices {
        let alpha = model.alpha[i], label = Double(model.labels[i]), value = trainingValues[i], hinge = max(0, 1 - label * value), residual = label * value - 1, violation = alpha == 0 ? max(0, -residual) : alpha == model.coefficient ? max(0, residual) : abs(residual)
        hingeTotal += hinge; if violation > tolerance { violations += 1 }; maximumViolation = max(maximumViolation, violation)
        if 2 * alpha * radius + hinge >= 1 { estimatedErrors += 1 }
    }
    let primal = objective.quadratic / 2 + model.coefficient * hingeTotal, trainingCorrect = correctCount(model.labels, trainingValues), counts = binaryCounts(testLabels, testingValues)
    var inside = 0, positiveTotal = 0.0, negativeTotal = 0.0
    for i in testing.indices { let value = testingValues[i]; if abs(value) < 1 { inside += 1 }; if testing[i].label == 1 { positiveTotal += value } else { negativeTotal += value } }
    var lines = ["model \(model.kernel.name)", "kernel \(model.kernel.description)", "C \(fixed(model.coefficient))", "alignment \(fixed(alignment, 6))", "passes \(model.passes) full \(model.fullPasses) nonbound \(model.nonboundPasses) converged \(model.converged ? "yes" : "no")", "examined \(model.examined) steps \(model.steps)", "choice heuristic \(model.choices[0]) nonbound_loop \(model.choices[1]) full_loop \(model.choices[2])", "clipping none \(model.clipping[0]) lower \(model.clipping[1]) upper \(model.clipping[2])", supportText(model), "b \(fixed(model.b, 6))", "equality \(fixed(equality, 6))"]
    if model.kernel.isLinear { lines.append("w \(fixed(w1, 6)) \(fixed(w2, 6))") }
    lines += ["sv_by_class positive bound \(positiveBound) free \(positiveFree) negative bound \(negativeBound) free \(negativeFree)", "norm \(fixed(norm, 6)) margin \(fixed(2 / norm, 6))", "dual_objective \(fixed(objective.dual, 6))", "primal_objective \(fixed(primal, 6))", "duality_gap \(fixed(primal - objective.dual, 6))", "kkt_violations \(violations) max \(fixed(maximumViolation, 6))", "xi_alpha radius \(fixed(radius, 6)) errors \(estimatedErrors)/\(n) accuracy \(ratio(n - estimatedErrors, n))", "train correct \(trainingCorrect)/\(n) accuracy \(ratio(trainingCorrect, n))", "test correct \(counts.correct)/\(m) accuracy \(ratio(counts.correct, m)) tp \(counts.tp) fp \(counts.fp) tn \(counts.tn) fn \(counts.fn)", "test precision \(ratio(counts.tp, counts.tp + counts.fp)) recall \(ratio(counts.tp, counts.tp + counts.fn)) f1 \(ratio(2 * counts.tp, 2 * counts.tp + counts.fp + counts.fn)) auc \(fixed(auc(testLabels, testingValues)))", "test inside_margin \(inside)", "test mean_decision positive \(fixed(positiveTotal / Double(counts.tp + counts.fn))) negative \(fixed(negativeTotal / Double(counts.fp + counts.tn)))"]
    for i in training.indices where model.alpha[i] > 0 { lines.append("sv \(training[i].id) y \(training[i].label) alpha \(fixed(model.alpha[i], 6)) f \(fixed(trainingValues[i])) \(model.alpha[i] == model.coefficient ? "bound" : "free")") }
    return FinalEvaluation(model: model, trainingValues: trainingValues, testingValues: testingValues, weights: Point(x: w1, y: w2), lines: lines)
}
func trainingLog(_ model: Model) -> [String] {
    var lines = ["training_log \(model.kernel.name)"], index = 0
    while index < model.records.count {
        let record = model.records[index]
        if record.full { lines.append("pass \(index + 1) full examined \(record.examined) changed \(record.changed) dual_objective \(fixed(objectives(model, record.alpha).dual, 6))"); index += 1 }
        else { let first = index + 1; var examined = 0, changed = 0; while index < model.records.count && !model.records[index].full { examined += model.records[index].examined; changed += model.records[index].changed; index += 1 }; lines.append("passes \(first)-\(index) nonbound examined \(examined) changed \(changed)") }
    }
    return lines
}
func coefficientPath(_ training: [Example], _ testing: [Example], _ selected: CVResult, _ matrix: [[Double]], _ settings: Settings) -> [String] {
    let points = training.map { $0.point }, labels = training.map { $0.label }, testingLabels = testing.map { $0.label }
    var lines = ["c_path \(selected.kernel.name)"]
    for coefficient in settings.coefficients { let model = train(points, labels, selected.kernel, matrix, coefficient, settings), trainCorrect = correctCount(labels, model.trainingDecisions()), testCorrect = correctCount(testingLabels, testing.map { model.decision($0.point) }); lines.append("C \(fixed(coefficient)) \(supportText(model)) dual_objective \(fixed(objectives(model).dual, 6)) train \(trainCorrect)/\(training.count) test \(testCorrect)/\(testing.count) \(runInfo(model))") }
    return lines
}
func learningCurve(_ training: [Example], _ testing: [Example], _ selected: CVResult, _ matrix: [[Double]], _ settings: Settings) -> [String] {
    var lines = ["learning_curve \(selected.kernel.name) C \(fixed(selected.coefficient))"]
    let testingLabels = testing.map { $0.label }
    for percentage in settings.learningPercentages {
        let size = training.count * percentage / 100, examples = Array(training.prefix(size)), labels = examples.map { $0.label }, model = train(examples.map { $0.point }, labels, selected.kernel, submatrix(matrix, Array(0..<size)), selected.coefficient, settings)
        let trainCorrect = correctCount(labels, model.trainingDecisions()), testCorrect = correctCount(testingLabels, testing.map { model.decision($0.point) })
        lines.append("size \(size) support_vectors \(supportCounts(model).total) train \(trainCorrect)/\(size) test \(testCorrect)/\(testing.count) \(runInfo(model))")
    }
    return lines
}
func probability(_ value: Double, _ coefficient: Double, _ intercept: Double) -> Double { 1 / (1 + exp(coefficient * value + intercept)) }
func negativeLogLikelihood(_ values: [Double], _ targets: [Double], _ coefficient: Double, _ intercept: Double) -> Double { var total = 0.0; for i in values.indices { let p = probability(values[i], coefficient, intercept); total += targets[i] * log(p) + (1 - targets[i]) * log(1 - p) }; return -total }
struct Calibration { let coefficient: Double; let intercept: Double; let probabilities: [Double]; let lines: [String] }
struct ProbabilityBin { var count = 0; var total = 0.0; var positive = 0 }
func calibrate(_ training: [Example], _ testing: [Example], _ selected: CVResult, _ testingValues: [Double], _ iterations: Int) -> Calibration {
    let positives = training.filter { $0.label == 1 }.count, negatives = training.count - positives, targets = training.map { $0.label == 1 ? Double(positives + 1) / Double(positives + 2) : 1 / Double(negatives + 2) }, values = selected.values
    var coefficient = 0.0, intercept = log(Double(negatives + 1) / Double(positives + 1))
    var lines = ["calibration \(selected.kernel.name) C \(fixed(selected.coefficient)) positives \(positives) negatives \(negatives)", "start A \(fixed(coefficient, 6)) B \(fixed(intercept, 6)) nll \(fixed(negativeLogLikelihood(values, targets, coefficient, intercept), 6))"]
    for iteration in 1...iterations {
        var g1 = 0.0, g2 = 0.0, h11 = 0.0, h21 = 0.0, h22 = 0.0
        for i in values.indices { let value = values[i], target = targets[i], p = probability(value, coefficient, intercept); g1 += value * (target - p); g2 += target - p; h11 += value * value * p * (1 - p); h21 += value * p * (1 - p); h22 += p * (1 - p) }
        let determinant = h11 * h22 - h21 * h21
        coefficient -= (h22 * g1 - h21 * g2) / determinant; intercept -= (h11 * g2 - h21 * g1) / determinant
        lines.append("iteration \(iteration) A \(fixed(coefficient, 6)) B \(fixed(intercept, 6)) nll \(fixed(negativeLogLikelihood(values, targets, coefficient, intercept), 6))")
    }
    let probabilities = testingValues.map { probability($0, coefficient, intercept) }
    var logTotal = 0.0, brierTotal = 0.0, bins = Array(repeating: ProbabilityBin(), count: 5)
    for i in testing.indices { let p = probabilities[i], positive = testing[i].label == 1, difference = p - (positive ? 1 : 0), index = min(4, Int(floor(p * 5))); logTotal += positive ? log(p) : log(1 - p); brierTotal += difference * difference; bins[index].count += 1; bins[index].total += p; bins[index].positive += positive ? 1 : 0 }
    lines.append("test log_loss \(fixed(-logTotal / Double(testing.count), 6)) brier \(fixed(brierTotal / Double(testing.count), 6))")
    let ranges = ["0.0-0.2", "0.2-0.4", "0.4-0.6", "0.6-0.8", "0.8-1.0"]
    for i in bins.indices { let bin = bins[i], mean = bin.count > 0 ? fixed(bin.total / Double(bin.count)) : "-"; lines.append("bin \(ranges[i]) count \(bin.count) mean_probability \(mean) positive_rate \(ratio(bin.positive, bin.count))") }
    let closest = testing.indices.sorted { abs(testingValues[$0]) == abs(testingValues[$1]) ? $0 < $1 : abs(testingValues[$0]) < abs(testingValues[$1]) }.prefix(5)
    for i in closest { lines.append("closest \(testing[i].id) label \(testing[i].label) decision \(fixed(testingValues[i])) probability \(fixed(probabilities[i]))") }
    return Calibration(coefficient: coefficient, intercept: intercept, probabilities: probabilities, lines: lines)
}
struct LinearWeights { let x: Double; let y: Double; let bias: Double; func decision(_ point: Point) -> Double { x * point.x + y * point.y + bias } }
struct PegasosResult { let values: [Double]; let lines: [String] }
func pegasos(_ training: [Example], _ testing: [Example], _ parameters: PegasosParameters, _ comparison: FinalEvaluation) -> PegasosResult {
    let regularization = parameters.regularization, iterations = parameters.iterations, n = training.count, m = testing.count, trainLabels = training.map { $0.label }, testLabels = testing.map { $0.label }
    var state = parameters.seed, w1 = 0.0, w2 = 0.0, bias = 0.0, sum1 = 0.0, sum2 = 0.0, sumBias = 0.0, updates = 0
    var lines = ["pegasos lambda \(fixed(regularization)) iterations \(iterations) seed \(parameters.seed)"]
    for iteration in 1...iterations {
        state = 48271 * state % 2147483647
        let example = training[state % n], label = Double(example.label), eta = 1 / (regularization * Double(iteration)), sigma = 1 - eta * regularization
        if label * (w1 * example.point.x + w2 * example.point.y + bias) < 1 { w1 = sigma * w1 + eta * label * example.point.x; w2 = sigma * w2 + eta * label * example.point.y; bias = sigma * bias + eta * label; updates += 1 } else { w1 = sigma * w1; w2 = sigma * w2; bias = sigma * bias }
        sum1 += w1; sum2 += w2; sumBias += bias
        if iteration % (iterations / 10) == 0 {
            let weights = LinearWeights(x: w1, y: w2, bias: bias), values = training.map { weights.decision($0.point) }
            var hingeTotal = 0.0
            for i in training.indices { hingeTotal += max(0, 1 - Double(trainLabels[i]) * values[i]) }
            let objective = regularization / 2 * (w1 * w1 + w2 * w2 + bias * bias) + hingeTotal / Double(n)
            lines.append("checkpoint \(iteration) objective \(fixed(objective, 6)) train \(correctCount(trainLabels, values))/\(n)")
        }
    }
    let weights = LinearWeights(x: w1, y: w2, bias: bias), average = LinearWeights(x: sum1 / Double(iterations), y: sum2 / Double(iterations), bias: sumBias / Double(iterations)), trainingValues = training.map { weights.decision($0.point) }, testingValues = testing.map { weights.decision($0.point) }, averageValues = testing.map { average.decision($0.point) }
    let trainingCorrect = correctCount(trainLabels, trainingValues), testingCorrect = correctCount(testLabels, testingValues), averageCorrect = correctCount(testLabels, averageValues), v1 = comparison.weights.x, v2 = comparison.weights.y, cosine = (w1 * v1 + w2 * v2) / (sqrt(w1 * w1 + w2 * w2) * sqrt(v1 * v1 + v2 * v2)), agreement = testing.indices.filter { sign(testingValues[$0]) == sign(comparison.testingValues[$0]) }.count
    lines += ["updates \(updates)", "w \(fixed(w1, 6)) \(fixed(w2, 6)) bias \(fixed(bias, 6))", "train correct \(trainingCorrect)/\(n) accuracy \(ratio(trainingCorrect, n))", "test correct \(testingCorrect)/\(m) accuracy \(ratio(testingCorrect, m))", "average w \(fixed(average.x, 6)) \(fixed(average.y, 6)) bias \(fixed(average.bias, 6)) test correct \(averageCorrect)/\(m)", "compare \(comparison.model.kernel.name) cosine \(fixed(cosine, 6)) test_agreement \(agreement)/\(m)"]
    return PegasosResult(values: testingValues, lines: lines)
}
func mcnemarLines(_ testing: [Example], _ results: [FinalEvaluation], _ pegasosValues: [Double]) -> [String] {
    let names = results.map { $0.model.kernel.name } + ["pegasos"], values = results.map { $0.testingValues } + [pegasosValues], correct = values.map { decisions in testing.indices.map { sign(decisions[$0]) == testing[$0].label } }
    var lines = ["mcnemar"]
    for first in names.indices { for second in (first + 1)..<names.count { var onlyFirst = 0, onlySecond = 0; for i in testing.indices { if correct[first][i] && !correct[second][i] { onlyFirst += 1 } else if correct[second][i] && !correct[first][i] { onlySecond += 1 } }; let denominator = onlyFirst + onlySecond, difference = abs(onlyFirst - onlySecond) - 1, chi = denominator == 0 ? "-" : fixed(Double(difference * difference) / Double(denominator)); lines.append("\(names[first]) \(names[second]) only_first \(onlyFirst) only_second \(onlySecond) chi2 \(chi)") } }
    return lines
}
func multiclassSummary(_ role: String, _ examples: [MulticlassExample], _ classifications: [Classification]) -> String {
    var rest = 0, pair = 0, agreement = 0, ties = 0
    for i in examples.indices { let result = classifications[i]; if result.rest == examples[i].classNumber { rest += 1 }; if result.pair == examples[i].classNumber { pair += 1 }; if result.rest == result.pair { agreement += 1 }; if result.tied { ties += 1 } }
    let size = examples.count
    return "\(role) ovr \(rest)/\(size) \(ratio(rest, size)) ovo \(pair)/\(size) \(ratio(pair, size)) agreement \(agreement)/\(size) vote_ties \(ties)"
}
func multiclassLines(_ training: [MulticlassExample], _ testing: [MulticlassExample], _ models: MulticlassModels) -> [String] {
    let trainingResults = training.map { models.classify($0.point) }, testingResults = testing.map { models.classify($0.point) }, n = training.count, m = testing.count
    var lines = ["multiclass kernel \(models.kernel.name) C \(fixed(models.coefficient)) classes 3 train \(n) test \(m)", "ovr"]
    for (index, model) in models.restModels.enumerated() { let correct = testing.indices.filter { sign(testingResults[$0].restValues[index]) == (testing[$0].classNumber == index + 1 ? 1 : -1) }.count, positives = model.labels.filter { $0 == 1 }.count; lines.append("model \(index + 1)-rest examples \(n) positives \(positives) \(supportText(model)) b \(fixed(model.b, 6)) \(runInfo(model)) test \(correct)/\(m)") }
    lines.append("ovo")
    for (index, pair) in classPairs.enumerated() { let model = models.pairModels[index]; var correct = 0, count = 0; for i in testing.indices where testing[i].classNumber == pair.0 || testing[i].classNumber == pair.1 { count += 1; if sign(testingResults[i].pairValues[index]) == (testing[i].classNumber == pair.0 ? 1 : -1) { correct += 1 } }; lines.append("model \(pair.0)-\(pair.1) examples \(model.points.count) positives \(model.labels.filter { $0 == 1 }.count) \(supportText(model)) b \(fixed(model.b, 6)) \(runInfo(model)) test \(correct)/\(count)") }
    lines.append("predictions")
    for i in testing.indices { let example = testing[i], result = testingResults[i], rest = result.restValues.map { fixed($0) }.joined(separator: " "), pair = result.pairValues.map { fixed($0) }.joined(separator: " "), votes = result.votes.map(String.init).joined(separator: " "); lines.append("\(example.id) class \(example.classNumber) ovr \(rest) pred \(result.rest) ovo \(pair) votes \(votes) pred \(result.pair)") }
    lines += [multiclassSummary("train", training, trainingResults), multiclassSummary("test", testing, testingResults), "confusion ovr"]
    lines += confusionLines(confusionMatrix(testing.map { $0.classNumber }, testingResults.map { $0.rest }))
    lines.append("confusion ovo"); lines += confusionLines(confusionMatrix(testing.map { $0.classNumber }, testingResults.map { $0.pair }))
    return lines
}
func framedPlot(_ cells: [String], _ width: Int, _ height: Int) -> [String] { let border = "+" + String(repeating: "-", count: width) + "+"; return [border] + (0..<height).map { "|" + cells[($0 * width)..<(($0 + 1) * width)].joined() + "|" } + [border] }
func plotCell(_ point: Point, _ settings: Settings, _ dx: Double, _ dy: Double) -> Int? { let column = Int(floor((point.x - settings.xmin) / dx)), row = Int(floor((settings.ymax - point.y) / dy)); return column >= 0 && column < settings.width && row >= 0 && row < settings.height ? row * settings.width + column : nil }
func decisionPlots(_ training: [Example], _ multiTraining: [MulticlassExample], _ results: [FinalEvaluation], _ selected: CVResult, _ calibration: Calibration, _ multi: MulticlassModels, _ settings: Settings) -> [String] {
    let width = settings.width, height = settings.height, dx = (settings.xmax - settings.xmin) / Double(width), dy = (settings.ymax - settings.ymin) / Double(height), count = width * height, model = results[selected.kernelIndex].model
    var binary: [String] = [], probabilityCells: [String] = [], multiclass: [String] = [], gridSigns = Array(repeating: [Int](), count: results.count), levels = Array(repeating: 0, count: 10)
    for row in 0..<height { for column in 0..<width {
        let point = Point(x: settings.xmin + (Double(column) + 0.5) * dx, y: settings.ymax - (Double(row) + 0.5) * dy), values = results.map { $0.model.decision(point) }, value = values[selected.kernelIndex], level = min(9, Int(floor(probability(value, calibration.coefficient, calibration.intercept) * 10))), result = multi.classify(point)
        binary.append(value >= 1 ? "+" : value > 0 ? "." : value > -1 ? "-" : " "); probabilityCells.append(String(level)); levels[level] += 1
        for i in results.indices { gridSigns[i].append(sign(values[i])) }
        multiclass.append(result.rest != result.pair ? "?" : [" ", ".", ":"][result.rest - 1])
    } }
    var binaryAssignments = Array<Int?>(repeating: nil, count: count), multiAssignments = Array<Int?>(repeating: nil, count: count), binaryOutside = 0, multiOutside = 0, binaryPoints = 0, multiPoints = 0
    for i in training.indices { guard let cell = plotCell(training[i].point, settings, dx, dy) else { binaryOutside += 1; continue }; if let previous = binaryAssignments[cell] { if model.alpha[i] > 0 && model.alpha[previous] <= 0 { binaryAssignments[cell] = i } } else { binaryAssignments[cell] = i } }
    for cell in 0..<count { if let i = binaryAssignments[cell] { binaryPoints += 1; binary[cell] = training[i].label == 1 ? (model.alpha[i] > 0 ? "X" : "x") : (model.alpha[i] > 0 ? "O" : "o") } }
    for i in multiTraining.indices { if let cell = plotCell(multiTraining[i].point, settings, dx, dy) { if multiAssignments[cell] == nil { multiAssignments[cell] = i } } else { multiOutside += 1 } }
    for cell in 0..<count { if let i = multiAssignments[cell] { multiPoints += 1; multiclass[cell] = String(multiTraining[i].classNumber) } }
    var lines = ["binary \(model.kernel.name) C \(fixed(model.coefficient))", "x \(fixed(settings.xmin)) \(fixed(settings.xmax)) y \(fixed(settings.ymin)) \(fixed(settings.ymax)) grid \(width)x\(height)"]
    lines += framedPlot(binary, width, height)
    lines += ["cells outer_positive \(binary.filter { $0 == "+" }.count) inner_positive \(binary.filter { $0 == "." }.count) inner_negative \(binary.filter { $0 == "-" }.count) outer_negative \(binary.filter { $0 == " " }.count) points \(binaryPoints) outside \(binaryOutside)", "", "probability \(model.kernel.name) A \(fixed(calibration.coefficient, 6)) B \(fixed(calibration.intercept, 6))"]
    lines += framedPlot(probabilityCells, width, height)
    lines += ["levels " + levels.map(String.init).joined(separator: " "), "", "grid_agreement"]
    let positiveCounts = gridSigns.map { $0.filter { $0 == 1 }.count }
    for first in results.indices { for second in (first + 1)..<results.count { let agreement = (0..<count).filter { gridSigns[first][$0] == gridSigns[second][$0] }.count; lines.append("\(results[first].model.kernel.name) \(results[second].model.kernel.name) \(agreement)/\(count) positive \(positiveCounts[first]) \(positiveCounts[second])") } }
    lines += ["", "multiclass \(multi.kernel.name) C \(fixed(multi.coefficient))"]
    lines += framedPlot(multiclass, width, height)
    lines.append("cells class1 \(multiclass.filter { $0 == " " }.count) class2 \(multiclass.filter { $0 == "." }.count) class3 \(multiclass.filter { $0 == ":" }.count) disagree \(multiclass.filter { $0 == "?" }.count) points \(multiPoints) outside \(multiOutside)")
    return lines
}
func cvGridLines(_ summary: CVSummary, _ foldCount: Int, _ size: Int) -> [String] {
    let header = ["kernel", "C"] + (1...foldCount).map { "fold\($0)" } + ["correct", "accuracy", "support_vectors", "passes", "steps"]
    var lines = [header.joined(separator: ",")]
    for result in summary.combinations { let row = [result.kernel.name, fixed(result.coefficient)] + result.folds.map { String($0.correct) } + [String(result.correct), ratio(result.correct, size), String(result.support), String(result.passes), String(result.steps)]; lines.append(row.joined(separator: ",")) }
    return lines
}
func predictionLines(_ testing: [Example], _ results: [FinalEvaluation], _ selected: CVResult, _ pegasosValues: [Double], _ probabilities: [Double]) -> [String] {
    let header = ["id", "label"] + results.map { $0.model.kernel.name } + ["pegasos", "predicted", "probability"]
    var lines = [header.joined(separator: ",")]
    for i in testing.indices { let row = [testing[i].id, String(testing[i].label)] + results.map { fixed($0.testingValues[i]) } + [fixed(pegasosValues[i]), String(sign(results[selected.kernelIndex].testingValues[i])), fixed(probabilities[i])]; lines.append(row.joined(separator: ",")) }
    return lines
}
let input = try readInputs(), settings = input.settings, summary = crossValidate(input.training, settings), points = input.training.map { $0.point }, labels = input.training.map { $0.label }
var results: [FinalEvaluation] = []
for (index, result) in summary.best.enumerated() { results.append(evaluateFinal(train(points, labels, result.kernel, summary.matrices[index], result.coefficient, settings), input.training, input.testing, settings.tolerance)) }
let selected = summary.selected, selectedResult = results[selected.kernelIndex], selectedMatrix = summary.matrices[selected.kernelIndex], calibration = calibrate(input.training, input.testing, selected, selectedResult.testingValues, settings.newtonIterations)
let pegasosResult = pegasos(input.training, input.testing, settings.pegasos, results.first { $0.model.kernel.isLinear }!), multiKernel = settings.kernels.first { $0.name == settings.multiclassName }!, multi = MulticlassModels(input.multiTraining, multiKernel, settings.multiclassCoefficient, settings)
var sections = [crossValidationLines(input.training.count, settings.foldCount, summary)] + results.map { $0.lines }
sections += [trainingLog(selectedResult.model), coefficientPath(input.training, input.testing, selected, selectedMatrix, settings), learningCurve(input.training, input.testing, selected, selectedMatrix, settings), calibration.lines, pegasosResult.lines, mcnemarLines(input.testing, results, pegasosResult.values)]
var modelLines: [String] = []
for section in sections { if !modelLines.isEmpty { modelLines.append("") }; modelLines += section }
try writeLines("model.txt", modelLines)
try writeLines("cv_grid.csv", cvGridLines(summary, settings.foldCount, input.training.count))
try writeLines("predictions.csv", predictionLines(input.testing, results, selected, pegasosResult.values, calibration.probabilities))
try writeLines("multiclass.txt", multiclassLines(input.multiTraining, input.multiTesting, multi))
try writeLines("decision_plot.txt", decisionPlots(input.training, input.multiTraining, results, selected, calibration, multi, settings))
