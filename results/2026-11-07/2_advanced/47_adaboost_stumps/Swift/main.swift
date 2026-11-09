import Foundation

struct Minstd {
    var state: Int64
    mutating func draw() -> Int64 { state = 48271 * state % 2147483647; return state }
}

func trainVariant(_ variant: String, _ rows: [Row], _ params: Parameters) -> Model {
    switch variant {
    case "discrete": return trainDiscrete(rows, params.rounds)
    case "real": return trainReal(rows, params.rounds, params.bins, params.smoothing, params.convergence)
    case "gentle": return trainGentle(rows, params.rounds)
    default: return trainLogit(rows, params.rounds, params.clip)
    }
}

func rowScore(_ rounds: [BoostRound], _ values: [Double]) -> Double { orderedSum(rounds.map { $0.stump.output(values) }) }
func scoreRows(_ rounds: [BoostRound], _ rows: [Row]) -> [Double] { rows.map { rowScore(rounds, $0.values) } }
func magnitude(_ round: BoostRound) -> Double { round.stump.values.map { abs($0) }.max()! }
func totalMagnitude(_ rounds: [BoostRound]) -> Double { orderedSum(rounds.map(magnitude)) }

func addRoundScores(_ round: BoostRound, _ rows: [Row], _ scores: inout [Double]) {
    for i in rows.indices { scores[i] = scores[i] + round.stump.output(rows[i].values) }
}

func contributions(_ rounds: [BoostRound], _ values: [Double], _ features: Int) -> [Double] {
    var result = Array(repeating: 0.0, count: features)
    for round in rounds { result[round.stump.feature] = result[round.stump.feature] + round.stump.output(values) }
    return result
}

func countErrors(_ rows: [Row], _ scores: [Double]) -> Int { rows.indices.filter { prediction(scores[$0]) != rows[$0].label }.count }

func loss(_ rows: [Row], _ scores: [Double], _ variant: String) -> Double {
    let terms = rows.indices.map { i in variant == "logit" ? log(1 + exp(-2 * Double(rows[i].label) * scores[i])) : exp(-Double(rows[i].label) * scores[i]) }
    return orderedSum(terms) / Double(rows.count)
}

func metricsLine(_ kind: String, _ variant: String, _ rounds: Int, _ rows: [Row], _ scores: [Double]) -> String {
    var tp = 0, fp = 0, tn = 0, fn = 0
    for i in rows.indices {
        if prediction(scores[i]) == 1 { if rows[i].label == 1 { tp += 1 } else { fp += 1 } }
        else if rows[i].label == -1 { tn += 1 } else { fn += 1 }
    }
    let area = auc(rows, scores)
    return "\(kind) \(variant) rounds \(rounds) correct \(tp + tn)/\(rows.count) accuracy \(ratio(tp + tn, rows.count)) tp \(tp) fp \(fp) tn \(tn) fn \(fn) precision \(ratio(tp, tp + fp)) recall \(ratio(tp, tp + fn)) f1 \(ratio(2 * tp, 2 * tp + fp + fn)) auc \(ratio(area.numerator, area.denominator)) loss \(number(loss(rows, scores, variant)))"
}

struct CurvePoint {
    let round: Int
    let trainErrors: Int
    let testErrors: Int
    let trainLoss: Double
    let testLoss: Double
    let margin: Double
}

func trainingCurve(_ rounds: [BoostRound], _ training: [Row], _ testing: [Row], _ variant: String) -> [CurvePoint] {
    var trainScores = Array(repeating: 0.0, count: training.count), testScores = Array(repeating: 0.0, count: testing.count)
    var scale = 0.0, curve: [CurvePoint] = []
    for (index, round) in rounds.enumerated() {
        addRoundScores(round, training, &trainScores)
        addRoundScores(round, testing, &testScores)
        scale = scale + magnitude(round)
        let minimum = training.indices.map { Double(training[$0].label) * trainScores[$0] }.min()!
        curve.append(CurvePoint(round: index + 1, trainErrors: countErrors(training, trainScores), testErrors: countErrors(testing, testScores),
                                trainLoss: loss(training, trainScores, variant), testLoss: loss(testing, testScores, variant), margin: minimum / scale))
    }
    return curve
}

struct FoldResult {
    let indices: [Int]
    let trainingCount: Int
    let model: Model
    let errors: [Int]
}

struct CrossValidation {
    let folds: [FoldResult]
    let errors: [Int]
    let selected: Int
    let scores: [Double]

    init(_ rows: [Row], _ params: Parameters) {
        let space = SearchSpace(rows)
        var folds: [FoldResult] = [], errors = Array(repeating: 0, count: params.rounds)
        for fold in 0..<params.folds {
            let indices = rows.indices.filter { $0 % params.folds == fold }, count = rows.count - indices.count
            let weights = rows.indices.map { $0 % params.folds == fold ? 0 : 1 / Double(count) }
            let model = trainDiscrete(rows, params.rounds, weights: weights, space: space)
            let validation = indices.map { rows[$0] }
            var scores = Array(repeating: 0.0, count: validation.count), foldErrors: [Int] = []
            for index in 0..<params.rounds {
                if index < model.rounds.count { addRoundScores(model.rounds[index], validation, &scores) }
                let count = countErrors(validation, scores)
                foldErrors.append(count)
                errors[index] += count
            }
            folds.append(FoldResult(indices: indices, trainingCount: count, model: model, errors: foldErrors))
        }
        var best = 0
        for index in errors.indices.dropFirst() where errors[index] < errors[best] { best = index }
        let selected = best + 1
        var scores = Array(repeating: 0.0, count: rows.count)
        for fold in folds {
            let rounds = Array(fold.model.rounds.prefix(selected))
            for index in fold.indices { scores[index] = rowScore(rounds, rows[index].values) }
        }
        self.folds = folds
        self.errors = errors
        self.selected = selected
        self.scores = scores
    }
}

struct Importance {
    let scores: [Double]
    let counts: [Int]
    let total: Double
    let order: [Int]

    init(_ rounds: [BoostRound], _ count: Int, samme: Bool = false) {
        var scores = Array(repeating: 0.0, count: count), counts = Array(repeating: 0, count: count)
        for round in rounds {
            let feature = round.stump.feature
            scores[feature] = scores[feature] + (samme ? round.alpha! : magnitude(round))
            counts[feature] += 1
        }
        self.scores = scores
        self.counts = counts
        total = orderedSum(scores)
        order = scores.indices.sorted { scores[$0] == scores[$1] ? $0 < $1 : scores[$0] > scores[$1] }
    }

    func lines(_ features: [String]) -> [String] {
        ["importance"] + order.enumerated().map { rank, feature in
            "\(rank + 1) \(features[feature]) score \(number(scores[feature])) share \(ratio(scores[feature], total)) rounds \(counts[feature])"
        }
    }
}

struct VariantResult {
    let full: Model
    let rounds: [BoostRound]
    let scale: Double
    let train: [Double]
    let test: [Double]
    let curve: [CurvePoint]
    let importance: Importance

    init(_ variant: String, _ inputs: Inputs, _ selected: Int) {
        let model = trainVariant(variant, inputs.train, inputs.params)
        let rounds = variant == "discrete" ? Array(model.rounds.prefix(selected)) : model.rounds
        full = model
        self.rounds = rounds
        scale = totalMagnitude(rounds)
        train = scoreRows(rounds, inputs.train)
        test = scoreRows(rounds, inputs.test)
        curve = trainingCurve(model.rounds, inputs.train, inputs.test, variant)
        importance = Importance(rounds, inputs.features.count)
    }
}

typealias Analysis = [String: VariantResult]

func ensembleLines(_ inputs: Inputs, _ analysis: Analysis, _ cv: CrossValidation) -> [String] {
    let params = inputs.params
    var lines: [String] = []
    for variant in params.variants {
        if !lines.isEmpty { lines.append("") }
        let model = analysis[variant]!.full
        var header = "variant \(variant) rounds \(model.rounds.count) stop \(model.stop)"
        if variant == "real" { header += " bins \(params.bins) smoothing \(number(params.smoothing)) convergence \(number(params.convergence, decimals: 6))" }
        else if variant == "logit" { header += " clip \(number(params.clip))" }
        lines.append(header)
        if variant == "real" {
            for (feature, cuts) in zip(inputs.features, model.cuts!) { lines.append("cuts \(feature) " + cuts.map { number($0) }.joined(separator: " ")) }
        }
        for (index, record) in model.rounds.enumerated() {
            let stump = record.stump
            var line = "round \(index + 1) feature \(inputs.features[stump.feature])"
            if variant == "real" {
                line += " z \(number(record.z!)) bound \(number(record.bound!)) values " + stump.values.map { number($0) }.joined(separator: " ")
            } else {
                line += " threshold \(number(stump.thresholds[0]))"
                if variant == "discrete" {
                    line += " polarity \(record.polarity!) error \(number(record.error!)) alpha \(number(record.alpha!)) z \(number(record.z!)) bound \(number(record.bound!))"
                } else {
                    line += " left \(number(stump.values[0])) right \(number(stump.values[1])) error \(number(record.error!))"
                    if variant == "logit" { line += " loss \(number(record.loss!))" }
                }
            }
            lines.append(line)
            if variant == "discrete" {
                let maximum = firstMaximum(record.weights), ess = 1 / orderedSum(record.weights.map { $0 * $0 })
                lines.append("weights \(index + 1) max \(number(record.weights[maximum], decimals: 6)) id \(inputs.train[maximum].id) ess \(number(ess))")
            }
        }
        if variant == "discrete" {
            let selected = cv.selected
            lines.append("cv folds \(params.folds) selected \(selected) errors \(cv.errors[selected - 1])/\(inputs.train.count)")
            for (index, fold) in cv.folds.enumerated() {
                let validation = fold.indices.count
                lines.append("fold \(index + 1) train \(fold.trainingCount) validation \(validation) rounds \(fold.model.rounds.count) stop \(fold.model.stop) selected \(fold.errors[selected - 1])/\(validation) final \(fold.errors.last!)/\(validation)")
            }
            lines.append("cv_errors " + cv.errors.map(String.init).joined(separator: " "))
        }
    }
    return lines
}

typealias SAMMECurve = [(round: Int, trainErrors: Int, testErrors: Int)]

func errorCurveLines(_ inputs: Inputs, _ analysis: Analysis, _ samme: SAMMECurve) -> [String] {
    var lines = ["variant,round,train_error,test_error,train_loss,test_loss,min_margin"]
    for variant in inputs.params.variants {
        for point in analysis[variant]!.curve {
            lines.append("\(variant),\(point.round),\(ratio(point.trainErrors, inputs.train.count)),\(ratio(point.testErrors, inputs.test.count)),\(number(point.trainLoss)),\(number(point.testLoss)),\(number(point.margin))")
        }
    }
    for point in samme { lines.append("samme,\(point.round),\(ratio(point.trainErrors, inputs.multiTrain.count)),\(ratio(point.testErrors, inputs.multiTest.count)),-,-,-") }
    return lines
}

func predictionLines(_ inputs: Inputs, _ analysis: Analysis) -> [String] {
    var lines = ["id,variant,score,label," + inputs.features.joined(separator: ",")]
    for (index, row) in inputs.test.enumerated() {
        for variant in inputs.params.variants {
            let result = analysis[variant]!, score = result.test[index]
            let parts = contributions(result.rounds, row.values, inputs.features.count)
            lines.append("\(row.id),\(variant),\(number(score)),\(prediction(score))," + parts.map { number($0) }.joined(separator: ","))
        }
    }
    return lines
}

func rocLines(_ inputs: Inputs, _ analysis: Analysis) -> [String] {
    var lines = ["variant,threshold,tp,fp"]
    for variant in inputs.params.variants {
        let scores = analysis[variant]!.test
        for threshold in Set(scores).sorted(by: >) {
            let selected = inputs.test.indices.filter { scores[$0] >= threshold }
            let tp = selected.filter { inputs.test[$0].label == 1 }.count
            lines.append("\(variant),\(number(threshold)),\(tp),\(selected.count - tp)")
        }
    }
    return lines
}

struct PermutationImportance {
    let feature: Int
    let drop: Int
    let minimum: Int
    let maximum: Int
}

func permutationImportance(_ rounds: [BoostRound], _ rows: [Row], _ features: Int, _ repeats: Int, _ generator: inout Minstd) -> (base: Int, entries: [PermutationImportance]) {
    let base = rows.count - countErrors(rows, scoreRows(rounds, rows))
    var entries: [PermutationImportance] = []
    for feature in 0..<features {
        var counts: [Int] = []
        for _ in 0..<repeats {
            var permutation = Array(rows.indices)
            for i in (1..<rows.count).reversed() { permutation.swapAt(i, Int(generator.draw() % Int64(i + 1))) }
            var correct = 0
            for (i, row) in rows.enumerated() {
                var values = row.values
                values[feature] = rows[permutation[i]].values[feature]
                if prediction(rowScore(rounds, values)) == row.label { correct += 1 }
            }
            counts.append(correct)
        }
        entries.append(PermutationImportance(feature: feature, drop: counts.reduce(0) { $0 + base - $1 }, minimum: counts.min()!, maximum: counts.max()!))
    }
    entries.sort { $0.drop == $1.drop ? $0.feature < $1.feature : $0.drop > $1.drop }
    return (base, entries)
}

func marginLines(_ inputs: Inputs, _ analysis: Analysis) -> [String] {
    var lines: [String] = []
    let repeats = inputs.params.permutationRepeats
    var generator = Minstd(state: inputs.params.permutationSeed)
    for variant in inputs.params.variants {
        if !lines.isEmpty { lines.append("") }
        let result = analysis[variant]!
        let trainMargins = inputs.train.indices.map { Double(inputs.train[$0].label) * result.train[$0] / result.scale }
        let testMargins = inputs.test.indices.map { Double(inputs.test[$0].label) * result.test[$0] / result.scale }
        lines += ["variant \(variant) rounds \(result.rounds.count) scale \(number(result.scale))",
                  "train min \(number(trainMargins.min()!)) mean \(number(orderedSum(trainMargins) / Double(inputs.train.count)))"]
        for threshold in inputs.params.margins {
            let count = countAtMost(trainMargins, threshold)
            lines.append("train le \(number(threshold)) \(count)/\(inputs.train.count) \(ratio(count, inputs.train.count))")
        }
        var histogram = Array(repeating: 0, count: 20)
        for margin in trainMargins { histogram[min(19, Int(floor((margin + 1) * 10)))] += 1 }
        lines.append("histogram " + histogram.map(String.init).joined(separator: " "))
        let hardest = trainMargins.indices.sorted { trainMargins[$0] == trainMargins[$1] ? $0 < $1 : trainMargins[$0] < trainMargins[$1] }
        for index in hardest.prefix(5) { lines.append("hardest \(inputs.train[index].id) label \(inputs.train[index].label) margin \(number(trainMargins[index]))") }
        lines.append("test min \(number(testMargins.min()!)) mean \(number(orderedSum(testMargins) / Double(inputs.test.count)))")
        for threshold in inputs.params.margins {
            let count = countAtMost(testMargins, threshold)
            lines.append("test le \(number(threshold)) \(count)/\(inputs.test.count) \(ratio(count, inputs.test.count))")
        }
        for threshold in inputs.params.margins {
            let confident = testMargins.indices.filter { abs(testMargins[$0]) > threshold }
            let correct = confident.filter { prediction(result.test[$0]) == inputs.test[$0].label }.count
            lines.append("test confident \(number(threshold)) \(confident.count)/\(inputs.test.count) correct \(correct)/\(confident.count) \(ratio(correct, confident.count))")
        }
        lines += result.importance.lines(inputs.features)
        let permutation = permutationImportance(result.rounds, inputs.test, inputs.features.count, repeats, &generator)
        lines.append("permutation repeats \(repeats) base \(permutation.base)/\(inputs.test.count)")
        for (rank, entry) in permutation.entries.enumerated() {
            lines.append("\(rank + 1) \(inputs.features[entry.feature]) drop \(ratio(entry.drop, repeats * inputs.test.count)) min \(entry.minimum)/\(inputs.test.count) max \(entry.maximum)/\(inputs.test.count)")
        }
    }
    return lines
}

func shapeLines(_ inputs: Inputs, _ analysis: Analysis) -> [String] {
    var lines: [String] = []
    for variant in inputs.params.variants {
        if !lines.isEmpty { lines.append("") }
        let rounds = analysis[variant]!.rounds
        lines.append("variant \(variant) rounds \(rounds.count)")
        for (feature, name) in inputs.features.enumerated() {
            let collected = rounds.filter { $0.stump.feature == feature }, cuts = Set(rounds.filter { $0.stump.feature == feature }.flatMap { $0.stump.thresholds }).sorted()
            var values = [orderedSum(collected.map { $0.stump.values[0] })]
            for cut in cuts { values.append(orderedSum(collected.map { $0.stump.values[$0.stump.thresholds.filter { $0 <= cut }.count] })) }
            lines.append("feature \(name) rounds \(collected.count) cuts \(cuts.count) range \(number(values.max()! - values.min()!))")
            for (index, value) in values.enumerated() {
                let lower = index == 0 ? "-inf" : number(cuts[index - 1]), upper = index == cuts.count ? "inf" : number(cuts[index])
                lines.append("interval \(lower) \(upper) value \(number(value))")
            }
        }
    }
    return lines
}

func calibrationLines(_ variant: String, _ rows: [Row], _ scores: [Double]) -> [String] {
    var counts = Array(repeating: 0, count: 5), positives = counts
    var totals = Array(repeating: 0.0, count: 5), brier = 0.0
    for (index, row) in rows.enumerated() {
        let probability = 1 / (1 + exp(-2 * scores[index])), target = row.label == 1 ? 1 : 0
        let difference = probability - Double(target), bin = min(4, Int(floor(probability * 5)))
        brier = brier + difference * difference
        counts[bin] += 1
        totals[bin] = totals[bin] + probability
        positives[bin] += target
    }
    let ranges = ["0.0-0.2", "0.2-0.4", "0.4-0.6", "0.6-0.8", "0.8-1.0"]
    return ["calibration \(variant) brier \(number(brier / Double(rows.count)))"] + (0..<5).map {
        "bin \(ranges[$0]) count \(counts[$0]) mean \(ratio(totals[$0], counts[$0])) positives \(positives[$0])"
    }
}

func comparisonLines(_ inputs: Inputs, _ analysis: Analysis) -> [String] {
    let variants = inputs.params.variants
    let predictions = Dictionary(uniqueKeysWithValues: variants.map { ($0, analysis[$0]!.test.map(prediction)) })
    let wrong = inputs.test.indices.filter { i in variants.allSatisfy { predictions[$0]![i] != inputs.test[i].label } }.map { inputs.test[$0].id }
    var lines = [(["all_wrong", String(wrong.count)] + wrong).joined(separator: " "), "agreement"]
    for a in 0..<(variants.count - 1) {
        for b in (a + 1)..<variants.count {
            var agree = 0, onlyFirst = 0, onlySecond = 0
            for (i, row) in inputs.test.enumerated() {
                let left = predictions[variants[a]]![i], right = predictions[variants[b]]![i]
                if left == right { agree += 1 }
                if left == row.label && right != row.label { onlyFirst += 1 }
                if right == row.label && left != row.label { onlySecond += 1 }
            }
            let difference = abs(onlyFirst - onlySecond) - 1
            lines.append("\(variants[a]) \(variants[b]) agree \(agree)/\(inputs.test.count) only_first \(onlyFirst) only_second \(onlySecond) chi2 \(ratio(difference * difference, onlyFirst + onlySecond))")
        }
    }
    return lines
}

func bootstrapLines(_ inputs: Inputs, _ analysis: Analysis) -> [String] {
    let variants = inputs.params.variants, samples = inputs.params.bootstrapSamples, seed = inputs.params.bootstrapSeed
    var generator = Minstd(state: seed)
    let correct = Dictionary(uniqueKeysWithValues: variants.map { variant in
        (variant, inputs.test.indices.map { prediction(analysis[variant]!.test[$0]) == inputs.test[$0].label })
    })
    var counts: [String: [Int]] = Dictionary(uniqueKeysWithValues: variants.map { ($0, []) })
    for _ in 0..<samples {
        let selected = inputs.test.map { _ in Int(generator.draw() % Int64(inputs.test.count)) }
        for variant in variants { counts[variant]!.append(selected.filter { correct[variant]![$0] }.count) }
    }
    var lines = ["bootstrap samples \(samples) seed \(seed)"]
    let trim = samples / 40
    for variant in variants {
        let ordered = counts[variant]!.sorted()
        lines.append("\(variant) mean \(ratio(counts[variant]!.reduce(0, +), samples * inputs.test.count)) low \(ratio(ordered[trim], inputs.test.count)) high \(ratio(ordered[samples - trim - 1], inputs.test.count))")
    }
    for a in 0..<(variants.count - 1) {
        for b in (a + 1)..<variants.count {
            var wins = 0, ties = 0, losses = 0
            for (left, right) in zip(counts[variants[a]]!, counts[variants[b]]!) {
                if left > right { wins += 1 } else if left == right { ties += 1 } else { losses += 1 }
            }
            lines.append("\(variants[a]) \(variants[b]) first \(wins) tie \(ties) second \(losses)")
        }
    }
    return lines
}

func featureSummary(_ rows: [Row], _ feature: Int) -> String {
    let values = rows.map { $0.values[feature] }
    return "\(number(values.min()!)) \(number(values.max()!)) \(number(orderedSum(values) / Double(values.count))) \(Set(values).count)"
}

func summaryLines(_ inputs: Inputs, _ analysis: Analysis, _ cv: CrossValidation) -> [String] {
    let training = inputs.train, testing = inputs.test, params = inputs.params
    var lines = ["data train \(training.count) test \(testing.count) features \(inputs.features.count) positives \(training.filter { $0.label == 1 }.count) \(testing.filter { $0.label == 1 }.count)"]
    for (feature, name) in inputs.features.enumerated() { lines.append("feature \(name) train \(featureSummary(training, feature)) test \(featureSummary(testing, feature))") }
    let selected = cv.selected, errors = cv.errors[selected - 1]
    lines += ["cv selected \(selected) errors \(errors)/\(training.count) rate \(ratio(errors, training.count))", metricsLine("oof", "discrete", selected, training, cv.scores)]
    var committeeTrain = Array(repeating: 0.0, count: training.count), committeeTest = Array(repeating: 0.0, count: testing.count), committeeRounds = 0
    for variant in params.variants {
        let result = analysis[variant]!, rounds = result.rounds.count
        lines += [metricsLine("train", variant, rounds, training, result.train), metricsLine("test", variant, rounds, testing, result.test)]
        committeeRounds += rounds
        for i in result.train.indices { committeeTrain[i] = committeeTrain[i] + result.train[i] / result.scale }
        for i in result.test.indices { committeeTest[i] = committeeTest[i] + result.test[i] / result.scale }
    }
    lines += [metricsLine("train", "committee", committeeRounds, training, committeeTrain), metricsLine("test", "committee", committeeRounds, testing, committeeTest)]
    for variant in params.variants {
        let curve = analysis[variant]!.curve
        var trainMinimum = curve[0], testMinimum = curve[0]
        for point in curve.dropFirst() {
            if point.trainErrors < trainMinimum.trainErrors { trainMinimum = point }
            if point.testErrors < testMinimum.testErrors { testMinimum = point }
        }
        lines.append("curve \(variant) rounds \(curve.count) train_min \(trainMinimum.trainErrors)/\(training.count) at \(trainMinimum.round) test_min \(testMinimum.testErrors)/\(testing.count) at \(testMinimum.round)")
    }
    lines += comparisonLines(inputs, analysis)
    lines += bootstrapLines(inputs, analysis)
    for variant in params.variants { lines += calibrationLines(variant, testing, analysis[variant]!.test) }
    return lines
}

func classPrediction(_ scores: [Double]) -> Int { firstMaximum(scores) + 1 }
func classErrors(_ rows: [Row], _ predictions: [Int]) -> Int { rows.indices.filter { rows[$0].label != predictions[$0] }.count }

func sammeProgression(_ rounds: [BoostRound], _ training: [Row], _ testing: [Row], _ classes: Int) -> (train: [[Double]], test: [[Double]], curve: SAMMECurve) {
    var train = Array(repeating: Array(repeating: 0.0, count: classes), count: training.count)
    var test = Array(repeating: Array(repeating: 0.0, count: classes), count: testing.count)
    var curve: SAMMECurve = []
    for (index, record) in rounds.enumerated() {
        for i in training.indices {
            let c = Int(record.stump.output(training[i].values)) - 1
            train[i][c] = train[i][c] + record.alpha!
        }
        for i in testing.indices {
            let c = Int(record.stump.output(testing[i].values)) - 1
            test[i][c] = test[i][c] + record.alpha!
        }
        curve.append((index + 1, classErrors(training, train.map(classPrediction)), classErrors(testing, test.map(classPrediction))))
    }
    return (train, test, curve)
}

func confusionLines(_ rows: [Row], _ predictions: [Int], _ classes: Int) -> [String] {
    let matrix = confusion(rows, predictions, classes)
    var lines = ["confusion"] + matrix.map { $0.map(String.init).joined(separator: " ") }
    for index in 0..<classes {
        let truePositive = matrix[index][index], predicted = matrix.reduce(0) { $0 + $1[index] }, actual = matrix[index].reduce(0, +)
        lines.append("class \(index + 1) precision \(ratio(truePositive, predicted)) recall \(ratio(truePositive, actual))")
    }
    return lines
}

func multiclassReport(_ inputs: Inputs) -> (lines: [String], curve: SAMMECurve) {
    let training = inputs.multiTrain, testing = inputs.multiTest, params = inputs.params
    let model = trainSAMME(training, params.sammeRounds, params.classes)
    let progression = sammeProgression(model.rounds, training, testing, params.classes)
    let trainPredictions = progression.train.map(classPrediction), testPredictions = progression.test.map(classPrediction)
    var lines = ["samme classes \(params.classes) train \(training.count) test \(testing.count) rounds \(model.rounds.count) stop \(model.stop)"]
    for (index, record) in model.rounds.enumerated() {
        let stump = record.stump
        lines.append("round \(index + 1) feature \(inputs.multiFeatures[stump.feature]) threshold \(number(stump.thresholds[0])) left \(Int(stump.values[0])) right \(Int(stump.values[1])) error \(number(record.error!)) alpha \(number(record.alpha!))")
    }
    for (kind, rows, predictions) in [("train", training, trainPredictions), ("test", testing, testPredictions)] {
        let count = classErrors(rows, predictions)
        lines.append("\(kind) errors \(count)/\(rows.count) rate \(ratio(count, rows.count))")
    }
    lines += confusionLines(testing, testPredictions, params.classes)
    lines += Importance(model.rounds, inputs.multiFeatures.count, samme: true).lines(inputs.multiFeatures)
    lines += ["", "ovr classes \(params.classes) rounds \(params.sammeRounds)"]
    var ovrTrainScores: [[Double]] = [], ovrTestScores: [[Double]] = []
    for c in 1...params.classes {
        let binaryTraining = training.map { $0.relabeled($0.label == c ? 1 : -1) }, binaryTesting = testing.map { $0.relabeled($0.label == c ? 1 : -1) }
        let model = trainDiscrete(binaryTraining, params.sammeRounds)
        let trainScores = scoreRows(model.rounds, binaryTraining), testScores = scoreRows(model.rounds, binaryTesting)
        ovrTrainScores.append(trainScores)
        ovrTestScores.append(testScores)
        let positives = training.filter { $0.label == c }.count
        lines.append("class \(c) rounds \(model.rounds.count) stop \(model.stop) positives \(positives) train_errors \(countErrors(binaryTraining, trainScores))/\(training.count) test_errors \(countErrors(binaryTesting, testScores))/\(testing.count)")
    }
    let ovrTrainPredictions = training.indices.map { i in classPrediction(ovrTrainScores.map { $0[i] }) }
    let ovrTestPredictions = testing.indices.map { i in classPrediction(ovrTestScores.map { $0[i] }) }
    for (kind, rows, predictions) in [("train", training, ovrTrainPredictions), ("test", testing, ovrTestPredictions)] {
        let count = classErrors(rows, predictions)
        lines.append("\(kind) errors \(count)/\(rows.count) rate \(ratio(count, rows.count))")
    }
    lines += confusionLines(testing, ovrTestPredictions, params.classes)
    let agreement = testing.indices.filter { testPredictions[$0] == ovrTestPredictions[$0] }.count
    lines += ["agreement \(agreement)/\(testing.count)", "", "predictions"]
    for (index, row) in testing.enumerated() {
        lines.append("\(row.id) class \(row.label) samme \(testPredictions[index]) ovr \(ovrTestPredictions[index]) scores " + progression.test[index].map { number($0) }.joined(separator: " "))
    }
    return (lines, progression.curve)
}

func modelErrors(_ model: Model, _ training: [Row], _ testing: [Row]) -> (train: Int, test: Int) {
    (countErrors(training, scoreRows(model.rounds, training)), countErrors(testing, scoreRows(model.rounds, testing)))
}

func testMinimum(_ rounds: [BoostRound], _ testing: [Row]) -> (errors: Int, at: Int) {
    var scores = Array(repeating: 0.0, count: testing.count), counts: [Int] = []
    for round in rounds { addRoundScores(round, testing, &scores); counts.append(countErrors(testing, scores)) }
    var index = 0
    for i in counts.indices.dropFirst() where counts[i] < counts[index] { index = i }
    return (counts[index], index + 1)
}

func experimentLines(_ inputs: Inputs, _ analysis: Analysis, _ selected: Int) -> [String] {
    let training = inputs.train, testing = inputs.test, params = inputs.params
    var lines: [String] = []
    for percentage in params.sizes {
        let size = training.count * percentage / 100, subset = Array(training.prefix(training.count * percentage / 100))
        lines.append("size \(percentage) rows \(size)")
        for variant in params.variants {
            let model = trainVariant(variant, subset, params), errors = modelErrors(model, subset, testing)
            lines.append("\(variant) rounds \(model.rounds.count) stop \(model.stop) train_errors \(errors.train)/\(size) test_errors \(errors.test)/\(testing.count)")
        }
    }
    for shrinkage in params.shrinkage {
        let model = trainDiscrete(training, params.rounds, shrinkage: shrinkage), errors = modelErrors(model, training, testing)
        let minimum = testMinimum(model.rounds, testing)
        lines.append("shrinkage \(number(shrinkage)) rounds \(model.rounds.count) stop \(model.stop) train_errors \(errors.train)/\(training.count) test_errors \(errors.test)/\(testing.count) test_min \(minimum.errors)/\(testing.count) at \(minimum.at)")
    }
    let ranked = analysis["discrete"]!.importance.order
    for count in 1...inputs.features.count {
        let features = ranked.prefix(count).sorted()
        let reducedTraining = training.map { $0.restricted(features) }, reducedTesting = testing.map { $0.restricted(features) }
        let model = trainDiscrete(reducedTraining, selected), errors = modelErrors(model, reducedTraining, reducedTesting)
        let names = features.map { inputs.features[$0] }.joined(separator: " ")
        lines.append("top \(count) features \(names) rounds \(model.rounds.count) train_errors \(errors.train)/\(training.count) test_errors \(errors.test)/\(testing.count)")
    }
    for percentage in params.noise {
        let flippedCount = training.count * percentage / 100
        var generator = Minstd(state: params.noiseSeed), permutation = Array(training.indices)
        for index in 0..<flippedCount { permutation.swapAt(index, Int(generator.draw() % Int64(training.count - index)) + index) }
        let flipped = Set(permutation.prefix(flippedCount))
        let noisy = training.indices.map { flipped.contains($0) ? training[$0].relabeled(-training[$0].label) : training[$0] }
        lines.append("noise \(percentage) flipped \(flippedCount)")
        for variant in params.variants {
            let model = trainVariant(variant, noisy, params), errors = modelErrors(model, noisy, testing), minimum = testMinimum(model.rounds, testing)
            let weights = model.rounds.last!.weights
            let flippedWeight = orderedSum(weights.indices.filter { flipped.contains($0) }.map { weights[$0] })
            lines.append("\(variant) rounds \(model.rounds.count) stop \(model.stop) train_errors \(errors.train)/\(training.count) test_errors \(errors.test)/\(testing.count) test_min \(minimum.errors)/\(testing.count) at \(minimum.at) flipped_weight \(number(flippedWeight))")
        }
    }
    return lines
}

let inputs = try readInputs()
let cv = CrossValidation(inputs.train, inputs.params)
let analysis = Dictionary(uniqueKeysWithValues: inputs.params.variants.map { ($0, VariantResult($0, inputs, cv.selected)) })
let multiclass = multiclassReport(inputs)
try writeLines("ensemble.txt", ensembleLines(inputs, analysis, cv))
try writeLines("error_curve.csv", errorCurveLines(inputs, analysis, multiclass.curve))
try writeLines("predictions.csv", predictionLines(inputs, analysis))
try writeLines("roc.csv", rocLines(inputs, analysis))
try writeLines("margins.txt", marginLines(inputs, analysis))
try writeLines("shapes.txt", shapeLines(inputs, analysis))
try writeLines("samme.txt", multiclass.lines)
try writeLines("summary.txt", summaryLines(inputs, analysis, cv))
try writeLines("experiments.txt", experimentLines(inputs, analysis, cv.selected))
