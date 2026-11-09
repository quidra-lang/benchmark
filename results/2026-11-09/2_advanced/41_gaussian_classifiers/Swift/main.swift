import Foundation

let modelKinds = ModelKind.allCases

struct CrossValidation {
    let predictions: [Int]
    let foldCorrect: [Int]
    var correct: Int { foldCorrect.reduce(0, +) }
}

struct ValidationKey: Hashable {
    let kind: ModelKind
    let features: [Int]
    let epsilon: Double
    let gamma: Double
}

func confusionLines(_ classes: [String], _ matrix: [[Int]]) -> [String] {
    zip(classes, matrix).map { "confusion \($0.0) " + $0.1.map(String.init).joined(separator: " ") }
}

func comparisonLines(_ title: String, _ names: [String], _ predictions: [[Int]], _ actual: [Int]) -> [String] {
    var lines = [title]
    for first in names.indices {
        for second in (first + 1)..<names.count {
            let result = mcnemar(actual, predictions[first], predictions[second])
            lines.append("\(names[first]) \(names[second]) b01 \(result.b01) b10 \(result.b10) chi2 \(real(result.chiSquared)) "
                + "significant \(result.significant ? "yes" : "no")")
        }
    }
    return lines
}

func pointGrid(_ points: [[Double]], _ actual: [Int], _ letters: [String],
               _ limits: [Double], _ width: Int, _ height: Int) -> [[String]] {
    var grid = Array(repeating: Array(repeating: " ", count: width), count: height)
    for (point, expected) in zip(points, actual) {
        let column = cell(point[0], limits[0], limits[1], width)
        let row = height - 1 - cell(point[1], limits[2], limits[3], height)
        let letter = letters[expected]
        let previous = grid[row][column]
        grid[row][column] = previous == " " || previous == letter ? letter : "*"
    }
    return grid
}

func nearestCentroidCorrect(_ points: [[Double]], _ actual: [Int], _ centroids: [[Double]], _ dimensions: Int) -> Int {
    var correct = 0
    for (point, expected) in zip(points, actual) {
        let distances = centroids.map { centroid -> Double in
            let first = point[0] - centroid[0]
            var distance = first * first
            if dimensions == 2 {
                let second = point[1] - centroid[1]
                distance = distance + second * second
            }
            return distance
        }
        if argmin(distances) == expected { correct += 1 }
    }
    return correct
}

final class Analysis {
    let data: Dataset
    var cache: [ValidationKey: CrossValidation] = [:]
    var mainModels: [GaussianModel] = []
    var results: [[Prediction]] = []
    var predictions: [[Int]] = []
    var parameters: Parameters { data.parameters }
    var train: [Row] { data.train }
    var test: [Row] { data.test }
    var features: [String] { data.features }
    var classes: [String] { data.classes }
    var n: Int { train.count }
    var m: Int { test.count }
    var d: Int { features.count }
    var classCount: Int { classes.count }
    var allFeatures: [Int] { Array(features.indices) }
    var trainActual: [Int] { train.map { $0.classIndex } }
    var testActual: [Int] { test.map { $0.classIndex } }
    var upperLetters: [String] { classes.map { String($0.prefix(1)).uppercased() } }
    var lowerLetters: [String] { classes.map { String($0.prefix(1)) } }

    init(_ data: Dataset) {
        self.data = data
        mainModels = modelKinds.map { fit($0) }
        results = mainModels.map { model in test.map { model.infer($0.values, costs: data.costs) } }
        predictions = results.map { $0.map { $0.predicted } }
    }

    func fit(_ kind: ModelKind, features: [Int]? = nil, rows: [Row]? = nil,
             prior: String? = nil, epsilon: Double? = nil, gamma: Double? = nil) -> GaussianModel {
        GaussianModel(rows ?? train, features: features ?? allFeatures, classes: classCount, kind: kind,
                       prior: prior ?? parameters.prior, epsilon: epsilon ?? parameters.epsilon, gamma: gamma ?? parameters.gamma)
    }

    func crossValidate(_ kind: ModelKind, _ features: [Int], epsilon: Double? = nil, gamma: Double? = nil) -> CrossValidation {
        let epsilon = epsilon ?? parameters.epsilon
        let gamma = gamma ?? parameters.gamma
        let key = ValidationKey(kind: kind, features: features, epsilon: epsilon, gamma: gamma)
        if let cached = cache[key] { return cached }
        var predictions = Array(repeating: 0, count: n)
        var foldCorrect: [Int] = []
        for fold in 0..<parameters.folds {
            let retained = train.filter { $0.id % parameters.folds != fold }
            let model = fit(kind, features: features, rows: retained, epsilon: epsilon, gamma: gamma)
            var correct = 0
            for (index, row) in train.enumerated() where row.id % parameters.folds == fold {
                predictions[index] = model.predict(row.values)
                if predictions[index] == row.classIndex { correct += 1 }
            }
            foldCorrect.append(correct)
        }
        let result = CrossValidation(predictions: predictions, foldCorrect: foldCorrect)
        cache[key] = result
        return result
    }

    func modelSections() -> [[String]] {
        let nb = mainModels[0]
        let lda = mainModels[1]
        let qda = mainModels[2]
        let statistics = nb.statistics
        var sections: [[String]] = []
        var lines = ["features " + features.joined(separator: " "), "classes " + classes.joined(separator: " "),
                     "prior_mode " + parameters.prior]
        for group in classes.indices {
            lines.append("class \(classes[group]) letter \(upperLetters[group]) count \(statistics.counts[group]) "
                + "prior \(real(nb.priors[group])) mean \(reals(statistics.means[group]))")
        }
        sections.append(lines)
        lines = ["model NB", "smoothing epsilon \(real(nb.epsilon)) max_variance \(real(nb.maximumVariance)) added \(real(nb.addedVariance))"]
        for group in classes.indices {
            let diagonal = features.indices.map { nb.covariances[group][$0][$0] }
            lines.append("class \(classes[group]) variance \(reals(diagonal)) log_det \(real(nb.logDeterminants[group]))")
        }
        sections.append(lines)
        let lower = lda.factors[0]
        lines = ["model LDA", "log_det \(real(lda.logDeterminants[0]))"]
        lines += lda.covariances[0].map { "  " + reals($0) }
        for group in classes.indices {
            let coefficients = backward(lower, forward(lower, lda.means[group]))
            let intercept = log(lda.priors[group]) - dot(lda.means[group], coefficients) / 2
            lines.append("class \(classes[group]) intercept \(real(intercept)) coef \(reals(coefficients))")
        }
        sections.append(lines)
        lines = ["model QDA gamma \(real(qda.gamma))"]
        for group in classes.indices {
            let eigenvalues = jacobi(qda.covariances[group]).values.sorted(by: >)
            let condition = eigenvalues[0] / eigenvalues.last!
            lines.append("class \(classes[group]) log_det \(real(qda.logDeterminants[group])) eigenvalues \(reals(eigenvalues)) condition \(real(condition))")
            lines += qda.covariances[group].map { "  " + reals($0) }
        }
        sections.append(lines)
        lines = ["separation"]
        for first in classes.indices {
            for second in (first + 1)..<classCount {
                let difference = features.indices.map { statistics.means[first][$0] - statistics.means[second][$0] }
                let mahalanobis = sqrt(quadraticForm(lower, difference))
                let average = features.indices.map { a in features.indices.map { b in
                    (qda.covariances[first][a][b] + qda.covariances[second][a][b]) / 2
                } }
                let averageLower = cholesky(average)
                let bhattacharyya = quadraticForm(averageLower, difference) / 8
                    + (logDeterminant(averageLower) - (qda.logDeterminants[first] + qda.logDeterminants[second]) / 2) / 2
                lines.append("\(classes[first]) \(classes[second]) mahalanobis \(real(mahalanobis)) bhattacharyya \(real(bhattacharyya))")
            }
        }
        sections.append(lines)
        let outliers = train.enumerated().map { (index: $0.offset, distance: qda.distances($0.element.values)[$0.element.classIndex]) }
            .filter { $0.distance > parameters.outlierThreshold }
            .sorted { $0.distance == $1.distance ? $0.index < $1.index : $0.distance > $1.distance }
        lines = ["outliers threshold \(real(parameters.outlierThreshold))"]
        lines += outliers.map { "\(train[$0.index].id) \(train[$0.index].label) q \(real($0.distance))" }
        lines.append("count \(outliers.count)")
        sections.append(lines)
        return sections
    }

    func predictionLines() -> [String] {
        var lines = ["id,model,actual,predicted,decision," + classes.joined(separator: ",")]
        for (index, row) in test.enumerated() {
            for model in modelKinds.indices {
                let result = results[model][index]
                let fields = [String(row.id), modelKinds[model].rawValue, row.label, classes[result.predicted], classes[result.decision]]
                    + result.posterior.map(real)
                lines.append(fields.joined(separator: ","))
            }
        }
        return lines
    }

    func modelEvaluation(_ model: Int) -> [String] {
        let results = self.results[model]
        let metrics = measures(testActual, predictions[model], classCount)
        var lines = ["model " + modelKinds[model].rawValue]
        lines += confusionLines(classes, metrics.matrix)
        lines += ["accuracy \(fractionText(metrics.accuracy))", "balanced_accuracy \(fractionText(metrics.balancedAccuracy))",
                  "kappa \(fractionText(metrics.kappa))"]
        for group in classes.indices {
            lines.append("class \(classes[group]) support \(metrics.support[group]) recall \(fractionText(metrics.recall[group])) "
                + "precision \(fractionText(metrics.precision[group])) f1 \(fractionText(metrics.f1[group]))")
        }
        let logLoss = -orderedSum(test.indices.map { results[$0].logPosterior[test[$0].classIndex] }) / Double(m)
        lines += ["macro_f1 \(real(metrics.macroF1))", "log_loss \(real(logLoss))"]
        let errors = test.indices.filter { results[$0].predicted != test[$0].classIndex }
        lines.append("errors \(errors.count)")
        lines += errors.map { "error \(test[$0].id) actual \(test[$0].label) predicted \(classes[results[$0].predicted]) confidence \(real(results[$0].confidence))" }
        let edges = [0.0] + parameters.calibrationEdges + [1.0]
        var calibrationError = 0.0
        for bin in 0..<(edges.count - 1) {
            let low = edges[bin]
            let high = edges[bin + 1]
            let last = bin == edges.count - 2
            let indices = test.indices.filter {
                results[$0].confidence >= low && (results[$0].confidence < high || (last && results[$0].confidence == high))
            }
            let confidenceSum = orderedSum(indices.map { results[$0].confidence })
            let correct = indices.filter { results[$0].predicted == test[$0].classIndex }.count
            let confidence = indices.isEmpty ? "-" : real(confidenceSum / Double(indices.count))
            lines.append("bin \(real(low)) \(real(high)) count \(indices.count) confidence \(confidence) accuracy \(ratioText(correct, indices.count))")
            calibrationError += abs(Double(correct) - confidenceSum)
        }
        lines.append("ece \(real(calibrationError / Double(m)))")
        for threshold in parameters.rejectThresholds {
            let accepted = test.indices.filter { results[$0].confidence >= threshold }
            let correct = accepted.filter { results[$0].predicted == test[$0].classIndex }.count
            lines.append("reject \(real(threshold)) accepted \(accepted.count) coverage \(ratioText(accepted.count, m)) accuracy \(ratioText(correct, accepted.count))")
        }
        return lines
    }

    func ensemblePredictions() -> [Int] {
        test.indices.map { index in
            argmax(classes.indices.map { group in orderedSum(modelKinds.indices.map { results[$0][index].posterior[group] }) / 3 })
        }
    }

    func costLines() -> [String] {
        var lines = ["costs"]
        for model in modelKinds.indices {
            let results = self.results[model]
            let argmaxTotal = orderedSum(test.indices.map { data.costs[test[$0].classIndex][results[$0].predicted] })
            let decisionTotal = orderedSum(test.indices.map { data.costs[test[$0].classIndex][results[$0].decision] })
            let changed = results.filter { $0.predicted != $0.decision }.count
            let correct = test.indices.filter { results[$0].decision == test[$0].classIndex }.count
            lines.append("\(modelKinds[model].rawValue) argmax_total \(real(argmaxTotal)) decision_total \(real(decisionTotal)) "
                + "changed \(changed) decision_accuracy \(ratioText(correct, m))")
        }
        return lines
    }

    func noveltyLines() -> [String] {
        let novel = test.indices.map { index -> (index: Int, nearest: Int, distance: Double) in
            let distances = mainModels[2].distances(test[index].values)
            let nearest = argmin(distances)
            return (index, nearest, distances[nearest])
        }.filter { $0.distance > parameters.outlierThreshold }
            .sorted { $0.distance == $1.distance ? $0.index < $1.index : $0.distance > $1.distance }
        return ["novelty threshold \(real(parameters.outlierThreshold))"]
            + novel.map { "\(test[$0.index].id) nearest \(classes[$0.nearest]) q \(real($0.distance))" } + ["count \(novel.count)"]
    }

    func bootstrapLines() -> [String] {
        let count = parameters.bootstrapCount
        var generator = RandomGenerator(state: parameters.seed)
        var resamples = Array(repeating: [Int](), count: 3)
        for _ in 0..<count {
            var correct = [0, 0, 0]
            for _ in 0..<m {
                let index = generator.draw() % m
                for model in 0..<3 where predictions[model][index] == test[index].classIndex { correct[model] += 1 }
            }
            for model in 0..<3 { resamples[model].append(correct[model]) }
        }
        var lines = ["bootstrap resamples \(count) seed \(parameters.seed)"]
        let offset = count / 40
        for model in 0..<3 {
            let ordered = resamples[model].sorted()
            let mean = Double(resamples[model].reduce(0, +)) / Double(count) / Double(m)
            lines.append("\(modelKinds[model].rawValue) mean \(real(mean)) interval \(ratioText(ordered[offset], m)) "
                + "\(ratioText(ordered[count - offset - 1], m))")
        }
        for first in 0..<3 {
            for second in (first + 1)..<3 {
                let wins = (0..<count).filter { resamples[first][$0] > resamples[second][$0] }.count
                let ties = (0..<count).filter { resamples[first][$0] == resamples[second][$0] }.count
                lines.append("\(modelKinds[first].rawValue) \(modelKinds[second].rawValue) wins \(wins) ties \(ties) losses \(count - wins - ties)")
            }
        }
        return lines
    }

    func priorLines() -> [String] {
        let alternative = parameters.prior == "empirical" ? "uniform" : "empirical"
        var lines = ["prior_sensitivity alternative " + alternative]
        for index in modelKinds.indices {
            let model = fit(modelKinds[index], prior: alternative)
            let predictions = test.map { model.predict($0.values) }
            let metrics = measures(testActual, predictions, classCount)
            let changed = test.indices.filter { predictions[$0] != self.predictions[index][$0] }.count
            lines.append("\(modelKinds[index].rawValue) accuracy \(fractionText(metrics.accuracy)) "
                + "balanced_accuracy \(fractionText(metrics.balancedAccuracy)) changed \(changed)")
        }
        return lines
    }

    func learningCurveLines() -> [String] {
        var lines = ["learning_curve"]
        for size in parameters.curve {
            var taken = Array(repeating: 0, count: classCount)
            let rows = train.filter { row in
                if taken[row.classIndex] >= size { return false }
                taken[row.classIndex] += 1
                return true
            }
            var fields = ["size \(size) rows \(rows.count)"]
            for kind in modelKinds {
                let model = fit(kind, rows: rows)
                let correct = test.filter { model.predict($0.values) == $0.classIndex }.count
                fields.append(kind.rawValue + " " + ratioText(correct, m))
            }
            lines.append(fields.joined(separator: " "))
        }
        return lines
    }

    func subsetLines() -> [String] {
        let folds = train.map { $0.id % parameters.folds }
        let foldSizes = (0..<parameters.folds).map { fold in folds.filter { $0 == fold }.count }
        var lines = ["cross_validation folds \(parameters.folds)", "fold_sizes " + foldSizes.map(String.init).joined(separator: " ")]
        var best: (subset: Int, model: Int, correct: Int)?
        for (subsetIndex, subset) in parameters.subsets.enumerated() {
            lines.append("subset \(subset.name) features " + subset.features.map { features[$0] }.joined(separator: " "))
            for (modelIndex, kind) in modelKinds.enumerated() {
                let result = crossValidate(kind, subset.features)
                lines.append("  \(kind.rawValue) fold_correct " + result.foldCorrect.map(String.init).joined(separator: " ")
                    + " correct \(result.correct) accuracy \(ratioText(result.correct, n))")
                if let previous = best {
                    let previousCount = parameters.subsets[previous.subset].features.count
                    if result.correct < previous.correct
                        || (result.correct == previous.correct && subset.features.count >= previousCount) { continue }
                }
                best = (subsetIndex, modelIndex, result.correct)
            }
        }
        let selected = best!
        let subset = parameters.subsets[selected.subset]
        let kind = modelKinds[selected.model]
        lines.append("best subset \(subset.name) model \(kind.rawValue) correct \(selected.correct) accuracy \(ratioText(selected.correct, n))")
        let model = fit(kind, features: subset.features)
        let correct = test.filter { model.predict($0.values) == $0.classIndex }.count
        lines.append("refit_test correct \(correct) accuracy \(ratioText(correct, m))")
        return lines
    }

    func leaveOneOutLines() -> [String] {
        var lines = ["leave_one_out"]
        for kind in modelKinds {
            var correct = 0
            for (index, row) in train.enumerated() {
                let rows = train.enumerated().filter { $0.offset != index }.map { $0.element }
                let model = fit(kind, rows: rows)
                if model.predict(row.values) == row.classIndex { correct += 1 }
            }
            lines.append("\(kind.rawValue) correct \(correct) accuracy \(ratioText(correct, n))")
        }
        return lines
    }

    func forwardSelectionSections() -> [[String]] {
        var sections: [[String]] = []
        for kind in modelKinds {
            var lines = ["forward_selection model " + kind.rawValue]
            var selected: [Int] = []
            var bestStep = 0
            var bestCorrect = -1
            for step in 1...d {
                var added = -1
                var stepCorrect = -1
                for feature in allFeatures where !selected.contains(feature) {
                    let result = crossValidate(kind, selected + [feature])
                    if result.correct > stepCorrect {
                        added = feature
                        stepCorrect = result.correct
                    }
                }
                selected.append(added)
                lines.append("step \(step) add \(features[added]) correct \(stepCorrect) accuracy \(ratioText(stepCorrect, n))")
                if stepCorrect > bestCorrect {
                    bestStep = step
                    bestCorrect = stepCorrect
                }
            }
            lines.append("best_step \(bestStep) features " + selected.prefix(bestStep).map { features[$0] }.joined(separator: " "))
            sections.append(lines)
        }
        return sections
    }

    func tuningLines(_ kind: ModelKind, _ values: [Double], _ title: String) -> [String] {
        var lines = [title]
        var bestValue = values[0]
        var bestCorrect = -1
        for value in values {
            let result = kind == .nb ? crossValidate(kind, allFeatures, epsilon: value) : crossValidate(kind, allFeatures, gamma: value)
            lines.append("value \(real(value)) correct \(result.correct) accuracy \(ratioText(result.correct, n))")
            if result.correct >= bestCorrect {
                bestValue = value
                bestCorrect = result.correct
            }
        }
        let model = kind == .nb ? fit(kind, epsilon: bestValue) : fit(kind, gamma: bestValue)
        let correct = test.filter { model.predict($0.values) == $0.classIndex }.count
        lines.append("best \(real(bestValue)) test correct \(correct) accuracy \(ratioText(correct, m))")
        return lines
    }

    func evaluationSections() -> [[String]] {
        var sections = [["test rows \(m)"]]
        sections += modelKinds.indices.map { modelEvaluation($0) }
        let ensemble = ensemblePredictions()
        let metrics = measures(testActual, ensemble, classCount)
        sections.append(["ensemble soft_vote", "accuracy \(fractionText(metrics.accuracy)) balanced_accuracy \(fractionText(metrics.balancedAccuracy)) "
            + "kappa \(fractionText(metrics.kappa))"])
        sections.append(comparisonLines("mcnemar test", modelKinds.map { $0.rawValue } + ["ENSEMBLE"], predictions + [ensemble], testActual))
        sections += [costLines(), noveltyLines(), bootstrapLines(), priorLines(), learningCurveLines(), subsetLines()]
        let crossValidation = modelKinds.map { crossValidate($0, allFeatures) }
        sections.append(comparisonLines("mcnemar cross_validation", modelKinds.map { $0.rawValue }, crossValidation.map { $0.predictions }, trainActual))
        for (kind, validation) in zip(modelKinds, crossValidation) {
            let metrics = measures(trainActual, validation.predictions, classCount)
            sections.append(["cv_confusion model " + kind.rawValue] + confusionLines(classes, metrics.matrix)
                + ["balanced_accuracy \(fractionText(metrics.balancedAccuracy)) kappa \(fractionText(metrics.kappa))"])
        }
        sections.append(leaveOneOutLines())
        sections += forwardSelectionSections()
        sections.append(tuningLines(.nb, parameters.smoothingGrid, "nb_smoothing_path"))
        sections.append(tuningLines(.qda, parameters.gammaGrid, "qda_gamma_path"))
        return sections
    }

    func boundarySections() -> [[String]] {
        var sections: [[String]] = []
        let width = parameters.mapWidth
        let height = parameters.mapHeight
        let levelCharacters = Array(" .:-=+*#%@").map(String.init)
        for pair in parameters.pairs {
            let fx = pair[0]
            let fy = pair[1]
            let xmin = train.map { $0.values[fx] }.min()!
            let xmax = train.map { $0.values[fx] }.max()!
            let ymin = train.map { $0.values[fy] }.min()!
            let ymax = train.map { $0.values[fy] }.max()!
            let dx = (xmax - xmin) / Double(width - 1)
            let dy = (ymax - ymin) / Double(height - 1)
            let gridPoints = (0..<height).map { row in (0..<width).map { column in
                [xmin + Double(column) * dx, ymax - Double(row) * dy]
            } }
            var lines = ["pair \(features[fx]) \(features[fy])", "x \(features[fx]) \(real(xmin)) \(real(xmax)) "
                + "y \(features[fy]) \(real(ymin)) \(real(ymax)) grid \(width)x\(height)"]
            var allGrids: [[[Prediction]]] = []
            for kind in modelKinds {
                let model = fit(kind, features: pair)
                let correct = train.filter { model.predict($0.values) == $0.classIndex }.count
                let validation = crossValidate(kind, pair)
                lines.append("model \(kind.rawValue) train_accuracy \(ratioText(correct, n)) cv_accuracy \(ratioText(validation.correct, n))")
                let grid = gridPoints.map { row in row.map { model.inferVector($0) } }
                allGrids.append(grid)
                lines += frame(grid.map { row in row.map { upperLetters[$0.predicted] } })
                var counts = Array(repeating: 0, count: classCount)
                for row in grid {
                    for prediction in row { counts[prediction.predicted] += 1 }
                }
                lines.append("cells " + classes.indices.map { "\(upperLetters[$0]) \(counts[$0])" }.joined(separator: " "))
            }
            var agreement: [[String]] = []
            var uncertainty: [[String]] = []
            var disagreements = 0
            for row in 0..<height {
                var agreementRow: [String] = []
                var uncertaintyRow: [String] = []
                for column in 0..<width {
                    let distinct = Set(allGrids.map { $0[row][column].predicted }).count
                    agreementRow.append(distinct == 1 ? "." : String(distinct))
                    if distinct != 1 { disagreements += 1 }
                    let confidence = allGrids[2][row][column].confidence
                    let uncertainty = (1 - confidence) / (1 - 1 / Double(classCount))
                    let level = min(9, Int(floor(10 * uncertainty)))
                    uncertaintyRow.append(levelCharacters[level])
                }
                agreement.append(agreementRow)
                uncertainty.append(uncertaintyRow)
            }
            lines.append("agreement")
            lines += frame(agreement)
            lines += ["disagreement_cells \(disagreements)", "uncertainty QDA"]
            lines += frame(uncertainty)
            let points = train.map { [$0.values[fx], $0.values[fy]] }
            lines.append("points")
            lines += frame(pointGrid(points, trainActual, lowerLetters, [xmin, xmax, ymin, ymax], width, height))
            sections.append(lines)
        }
        return sections
    }

    func projectionSections() -> [[String]] {
        let statistics = mainModels[0].statistics
        let center = statistics.center
        var within = zeros(d)
        var between = zeros(d)
        for a in allFeatures {
            for b in allFeatures {
                within[a][b] = orderedSum(statistics.scatter.map { $0[a][b] })
                between[a][b] = orderedSum(classes.indices.map { group in
                    Double(statistics.counts[group]) * (statistics.means[group][a] - center[a]) * (statistics.means[group][b] - center[b])
                })
            }
        }
        let fValues = allFeatures.map { (between[$0][$0] / Double(classCount - 1)) / (within[$0][$0] / Double(n - classCount)) }
        let order = allFeatures.sorted { fValues[$0] == fValues[$1] ? $0 < $1 : fValues[$0] > fValues[$1] }
        var univariate = ["univariate"]
        for (rank, feature) in order.enumerated() {
            univariate.append("rank \(rank + 1) \(features[feature]) f \(real(fValues[feature])) "
                + "between \(real(between[feature][feature])) within \(real(within[feature][feature]))")
        }
        let lower = cholesky(within)
        var transformed = zeros(d)
        for column in allFeatures {
            let vector = forward(lower, allFeatures.map { between[$0][column] })
            for row in allFeatures { transformed[row][column] = vector[row] }
        }
        var whitened = zeros(d)
        for index in allFeatures {
            let vector = forward(lower, transformed[index])
            for row in allFeatures { whitened[row][index] = vector[row] }
        }
        let symmetric = allFeatures.map { a in allFeatures.map { b in (whitened[a][b] + whitened[b][a]) / 2 } }
        let decomposition = jacobi(symmetric)
        let eigenvalues = decomposition.values
        let eigenOrder = allFeatures.sorted { eigenvalues[$0] == eigenvalues[$1] ? $0 < $1 : eigenvalues[$0] > eigenvalues[$1] }
        let eigenSum = orderedSum(eigenvalues)
        var directions: [[Double]] = []
        for index in eigenOrder.prefix(2) {
            let eigenvector = allFeatures.map { decomposition.vectors[$0][index] }
            var direction = backward(lower, eigenvector)
            let norm = sqrt(dot(direction, direction))
            direction = direction.map { $0 / norm }
            let pivot = argmax(direction.map(abs))
            if direction[pivot] < 0 { direction = direction.map { -$0 } }
            directions.append(direction)
        }
        func project(_ vector: [Double]) -> [Double] {
            directions.map { direction in orderedSum(allFeatures.map { direction[$0] * (vector[$0] - center[$0]) }) }
        }
        let trainPoints = train.map { project($0.values) }
        let testPoints = test.map { project($0.values) }
        let centroids = statistics.means.map(project)
        var fisher = ["fisher features " + features.joined(separator: " "), "center " + reals(center), "sweeps \(decomposition.sweeps)",
                      "eigenvalues " + reals(eigenOrder.map { eigenvalues[$0] }), "ratios " + reals(eigenOrder.map { eigenvalues[$0] / eigenSum })]
        let pooled = mainModels[1].covariances[0]
        for (index, direction) in directions.enumerated() {
            let standardized = allFeatures.map { direction[$0] * sqrt(pooled[$0][$0]) }
            fisher += ["direction \(index + 1) \(reals(direction))", "standardized \(index + 1) \(reals(standardized))"]
        }
        for group in classes.indices {
            let spread = (0..<2).map { dimension -> Double in
                let squares = train.indices.filter { train[$0].classIndex == group }.map { index in
                    (trainPoints[index][dimension] - centroids[group][dimension]) * (trainPoints[index][dimension] - centroids[group][dimension])
                }
                return sqrt(orderedSum(squares) / Double(statistics.counts[group]))
            }
            fisher.append("centroid \(classes[group]) \(reals(centroids[group])) spread \(reals(spread))")
        }
        for dimensions in 1...2 {
            let trainCorrect = nearestCentroidCorrect(trainPoints, trainActual, centroids, dimensions)
            let testCorrect = nearestCentroidCorrect(testPoints, testActual, centroids, dimensions)
            fisher.append("nearest_centroid dims \(dimensions) train \(ratioText(trainCorrect, n)) test \(ratioText(testCorrect, m))")
        }
        let xmin = trainPoints.map { $0[0] }.min()!
        let xmax = trainPoints.map { $0[0] }.max()!
        let ymin = trainPoints.map { $0[1] }.min()!
        let ymax = trainPoints.map { $0[1] }.max()!
        let width = parameters.plotWidth
        let height = parameters.plotHeight
        var grid = pointGrid(trainPoints, trainActual, lowerLetters, [xmin, xmax, ymin, ymax], width, height)
        for group in classes.indices {
            let column = cell(centroids[group][0], xmin, xmax, width)
            let row = height - 1 - cell(centroids[group][1], ymin, ymax, height)
            grid[row][column] = upperLetters[group]
        }
        let scatter = ["plot x \(real(xmin)) \(real(xmax)) y \(real(ymin)) \(real(ymax)) size \(width)x\(height)"] + frame(grid)
        return [univariate, fisher, scatter]
    }
}

let analysis = Analysis(try readInputs())
try writeLines("models.txt", joinSections(analysis.modelSections()))
try writeLines("predictions.csv", analysis.predictionLines())
try writeLines("evaluation.txt", joinSections(analysis.evaluationSections()))
try writeLines("boundaries.txt", joinSections(analysis.boundarySections()))
try writeLines("projection.txt", joinSections(analysis.projectionSections()))
