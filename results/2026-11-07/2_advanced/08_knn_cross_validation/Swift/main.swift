import Foundation

struct CrossValidation {
    let model: Model
    let predictions: [Prediction]
    let hits: [Bool]
    let correct: Int
    let error: Double
    init(_ model: Model, _ rows: [Row], _ predictions: [Prediction]) {
        self.model = model
        self.predictions = predictions
        hits = zip(predictions, rows).map { $0.0.label == $0.1.label }
        correct = hits.filter { $0 }.count
        error = rmse(zip(predictions, rows).map { $0.0.estimate - $0.1.target! })
    }
}
func crossValidate(_ models: [Model], _ rows: [Row], _ folds: Int, _ features: [Int]) -> [CrossValidation] {
    var predictions = Array(repeating: Array<Prediction?>(repeating: nil, count: rows.count), count: models.count)
    var spaces: [(String, String)] = []
    for model in models where !spaces.contains(where: { $0.0 == model.scaling && $0.1 == model.metric }) { spaces.append((model.scaling, model.metric)) }
    for fold in stratifiedFolds(rows, folds) {
        let training = foldTraining(rows, fold)
        let queries = fold.map { rows[$0] }
        for (scaling, metric) in spaces {
            let orders = neighborOrders(training, queries, scaling, metric, features)
            for (number, model) in models.enumerated() where model.scaling == scaling && model.metric == metric {
                for (position, index) in fold.enumerated() { predictions[number][index] = predictionFromOrder(orders[position], model.k, model.weighting) }
            }
        }
    }
    return models.enumerated().map { CrossValidation($0.element, rows, predictions[$0.offset].map { $0! }) }
}
func bestClassifier(_ results: [CrossValidation]) -> CrossValidation {
    var best = results[0]
    for result in results.dropFirst() where result.correct > best.correct { best = result }
    return best
}
func bestRegressor(_ results: [CrossValidation]) -> CrossValidation {
    var best = results[0]
    for result in results.dropFirst() where fourDecimal(result.error) < fourDecimal(best.error) { best = result }
    return best
}
func correctCount(_ predictions: [Prediction], _ rows: [Row]) -> Int { zip(predictions, rows).filter { $0.0.label == $0.1.label }.count }
func labelCounts(_ rows: [Row], _ labels: [String]) -> String { labels.map { label in "\(label) \(rows.filter { $0.label == label }.count)" }.joined(separator: " ") }
func evaluationLines(_ pairs: [(String, String)], _ labels: [String]) -> [String] {
    var matrix = Array(repeating: Array(repeating: 0, count: labels.count), count: labels.count)
    for (truth, prediction) in pairs { matrix[labels.firstIndex(of: truth)!][labels.firstIndex(of: prediction)!] += 1 }
    var lines = ["true\\predicted " + labels.joined(separator: " ")]
    for (index, label) in labels.enumerated() { lines.append(label + " " + matrix[index].map(String.init).joined(separator: " ")) }
    var totals = Array(repeating: 0.0, count: 3)
    var valued = Array(repeating: 0, count: 3)
    for (index, label) in labels.enumerated() {
        let hits = matrix[index][index]
        let predicted = matrix.reduce(0) { $0 + $1[index] }
        let actual = matrix[index].reduce(0, +)
        let metrics = [(hits, predicted), (hits, actual), (2 * hits, predicted + actual)]
        for (position, metric) in metrics.enumerated() where metric.1 > 0 { totals[position] += Double(metric.0) / Double(metric.1); valued[position] += 1 }
        lines.append("class \(label) precision \(fraction(hits, predicted)) recall \(fraction(hits, actual)) f1 \(fraction(2 * hits, predicted + actual)) support \(actual)")
    }
    let averages = totals.indices.map { valued[$0] == 0 ? "-" : fixed(totals[$0] / Double(valued[$0])) }
    lines.append("macro precision \(averages[0]) recall \(averages[1]) f1 \(averages[2])")
    return lines
}
func reliabilityLines(_ pairs: [(Prediction, String)], _ bounds: [Double]) -> [String] {
    let lower = [0.0] + bounds
    var counts = Array(repeating: 0, count: lower.count)
    var hits = counts
    var shares = Array(repeating: 0.0, count: lower.count)
    for (prediction, truth) in pairs {
        let bin = bounds.filter { $0 <= prediction.share }.count
        counts[bin] += 1
        if prediction.label == truth { hits[bin] += 1 }
        shares[bin] += prediction.share
    }
    return lower.indices.map { index in "bin \(fixed(lower[index], 2)) rows \(counts[index])" + (counts[index] == 0 ? "" : " correct \(ratio(hits[index], counts[index])) share \(fixed(shares[index] / Double(counts[index])))") }
}
struct ClassifierSpace {
    let model: Model
    let gaps: [String: [String: Double]]
    init(_ model: Model, _ train: [Row], _ test: [Row]) {
        self.model = model
        let features = Array(train[0].values.indices)
        let scaling = computeScaling(train, model.scaling)
        let references = train.map { scaling.transform($0.values, features) }
        gaps = Dictionary(uniqueKeysWithValues: (train + test).map { query in
            let vector = scaling.transform(query.values, features)
            let distances = Dictionary(uniqueKeysWithValues: train.enumerated().map { ($0.element.id, distance(vector, references[$0.offset], model.metric)) })
            return (query.id, distances)
        })
    }
    func order(_ query: Row, _ rows: [Row]) -> [Neighbor] { sortNeighbors(rows.map { Neighbor(distance: gaps[query.id]![$0.id]!, row: $0) }) }
    func voting(_ query: Row, _ rows: [Row], _ k: Int) -> Vote { vote(Array(order(query, rows).prefix(k)), model.weighting) }
    func nearestLabel(_ query: Row, _ rows: [Row]) -> String { order(query, rows)[0].row.label! }
}
func wilsonEditing(_ space: ClassifierSpace, _ rows: [Row], _ editK: Int) -> ([Row], [[(Row, Vote)]]) {
    var current = rows
    var passes: [[(Row, Vote)]] = []
    while true {
        let removed = current.compactMap { row -> (Row, Vote)? in
            let result = space.voting(row, current.filter { $0.id != row.id }, editK)
            return result.label != row.label ? (row, result) : nil
        }
        passes.append(removed)
        if removed.isEmpty { return (current, passes) }
        let ids = Set(removed.map { $0.0.id })
        current.removeAll { ids.contains($0.id) }
    }
}
func hartCondensing(_ space: ClassifierSpace, _ rows: [Row]) -> ([Row], Int) {
    var store = [rows[0]]
    var stored = Set([rows[0].id])
    var scans = 0
    while true {
        scans += 1
        var added = false
        for row in rows where !stored.contains(row.id) && space.nearestLabel(row, store) != row.label { store.append(row); stored.insert(row.id); added = true }
        if !added { return (store.sorted { $0.id < $1.id }, scans) }
    }
}

final class Experiment {
    let featureNames: [String]
    let features: [Int]
    let train: [Row]
    let test: [Row]
    let settings: Settings
    let labels: [String]
    let labelled: [Row]
    let targeted: [Row]
    let grid: [Model]
    let folds: [[Int]]
    let results: [CrossValidation]
    let classifier: CrossValidation
    let regressor: CrossValidation
    let testPredictions: [Prediction]
    let testEstimates: [Double]
    let labelledPredictions: [(Row, Prediction)]
    init(_ data: Dataset) {
        featureNames = data.features
        let features = Array(data.features.indices)
        self.features = features
        train = data.train
        test = data.test
        settings = data.settings
        labels = Set(data.train.map { $0.label! }).sorted()
        labelled = data.test.filter { $0.label != nil }
        targeted = data.test.filter { $0.target != nil }
        let grid = data.settings.ks.flatMap { k in data.settings.metrics.flatMap { metric in data.settings.weightings.flatMap { weighting in data.settings.scalings.map { Model(k: k, metric: metric, weighting: weighting, scaling: $0) } } } }
        self.grid = grid
        folds = stratifiedFolds(data.train, data.settings.folds)
        let results = crossValidate(grid, data.train, data.settings.folds, features)
        self.results = results
        let classifier = bestClassifier(results), regressor = bestRegressor(results)
        self.classifier = classifier
        self.regressor = regressor
        let predictions = predictRows(classifier.model, data.train, data.test, features)
        testPredictions = predictions
        testEstimates = predictRows(regressor.model, data.train, data.test, features).map(\.estimate)
        labelledPredictions = zip(data.test, predictions).filter { $0.0.label != nil }
    }
    func names(_ features: [Int]) -> String { features.map { featureNames[$0] }.joined(separator: " ") }
    func trainRatio(_ count: Int) -> String { ratio(count, train.count) }
    func classifierSummary(_ result: CrossValidation) -> String { "\(result.model.notation()) correct \(trainRatio(result.correct)) rmse \(fixed(result.error))" }
    func regressorSummary(_ result: CrossValidation) -> String { "\(result.model.notation()) rmse \(fixed(result.error)) correct \(trainRatio(result.correct))" }
    func gridTable() -> [String] { ["k,metric,weighting,scaling,correct,accuracy,rmse"] + results.map { "\($0.model.k),\($0.model.metric),\($0.model.weighting),\($0.model.scaling),\($0.correct),\(fixed(Double($0.correct) / Double(train.count))),\(fixed($0.error))" } }
    func predictionTable() -> [String] { ["id,label,vote_share,estimate"] + test.indices.map { "\(test[$0].id),\(testPredictions[$0].label),\(fixed(testPredictions[$0].share)),\(fixed(testEstimates[$0]))" } }
    func dataPart() -> [String] { ["data train \(train.count) test \(test.count) labelled \(labelled.count) targets \(targeted.count) features \(features.count) classes \(labels.count)", "classes \(labelCounts(train, labels))"] }
    func scalingPart(_ method: String) -> [String] {
        let scaling = computeScaling(train, method)
        return ["scaling \(method)"] + featureNames.indices.map { "\(featureNames[$0]) center \(fixed(scaling.centers[$0], 6)) scale \(fixed(scaling.scales[$0], 6))" }
    }
    func foldsPart() -> [String] { ["folds \(settings.folds)"] + folds.enumerated().map { index, fold in "fold \(index + 1) size \(fold.count) \(labelCounts(fold.map { train[$0] }, labels))" } }
    func selectionPart() -> [String] { ["grid \(grid.count)", "best_classifier \(classifierSummary(classifier))", "best_regressor \(regressorSummary(regressor))"] }
    func topPart(_ accuracy: Bool) -> [String] {
        let ordered = results.indices.sorted { a, b in
            if accuracy && results[a].correct != results[b].correct { return results[a].correct > results[b].correct }
            if !accuracy && fourDecimal(results[a].error) != fourDecimal(results[b].error) { return fourDecimal(results[a].error) < fourDecimal(results[b].error) }
            return a < b
        }
        return ["top \(settings.top) by \(accuracy ? "accuracy" : "rmse")"] + ordered.prefix(settings.top).enumerated().map { rank, index in "\(rank + 1) \(accuracy ? classifierSummary(results[index]) : regressorSummary(results[index]))" }
    }
    func bestPerItemParts() -> [[String]] {
        let values = [("k", settings.ks.map(String.init)), ("metric", settings.metrics), ("weighting", settings.weightings), ("scaling", settings.scalings)]
        return values.map { item, entries in
            ["best per \(item)"] + entries.map { value in
                let selected = results.filter { result in
                    let entry: String
                    switch item { case "k": entry = String(result.model.k); case "metric": entry = result.model.metric; case "weighting": entry = result.model.weighting; default: entry = result.model.scaling }
                    return entry == value
                }
                let first = bestClassifier(selected), second = bestRegressor(selected)
                return "\(item)=\(value) classifier \(first.model.notation()) accuracy \(fixed(Double(first.correct) / Double(train.count))) regressor \(second.model.notation()) rmse \(fixed(second.error))"
            }
        }
    }
    func classifierFoldsPart() -> [String] { ["classifier folds"] + folds.enumerated().map { number, fold in "fold \(number + 1) correct \(ratio(fold.filter { classifier.hits[$0] }.count, fold.count))" } }
    func regressorFoldsPart() -> [String] { ["regressor folds"] + folds.enumerated().map { number, fold in "fold \(number + 1) size \(fold.count) rmse \(fixed(rmse(fold.map { regressor.predictions[$0].estimate - train[$0].target! })))" } }
    func mcnemarPart() -> [String] {
        var lines = ["mcnemar"]
        for metric in settings.metrics {
            let comparison = bestClassifier(results.filter { $0.model.metric == metric })
            let b = train.indices.filter { classifier.hits[$0] && !comparison.hits[$0] }.count
            let c = train.indices.filter { comparison.hits[$0] && !classifier.hits[$0] }.count
            let difference = max(0, abs(b - c) - 1)
            let numerator = difference * difference
            let statistic = b + c == 0 ? "0/1 0.0000" : fraction(numerator, b + c)
            lines.append("\(comparison.model.notation()) b \(b) c \(c) statistic \(statistic) significant \(1000 * numerator > 3841 * (b + c) ? "yes" : "no")")
        }
        return lines
    }
    func leaveOneOutParts() -> [[String]] {
        let model = classifier.model
        var byK = Dictionary(uniqueKeysWithValues: settings.ks.map { ($0, [Prediction]()) })
        var estimates: [Double] = []
        for (index, row) in train.enumerated() {
            let others = train.enumerated().filter { $0.offset != index }.map(\.element)
            let order = neighborOrders(others, [row], model.scaling, model.metric, features)[0]
            for k in settings.ks { byK[k]!.append(predictionFromOrder(order, k, model.weighting)) }
            estimates.append(predictRows(regressor.model, others, [row], features)[0].estimate)
        }
        let predictions = byK[model.k]!
        let errors = zip(train, predictions).filter { $0.0.label != $0.1.label }.sorted { $0.0.id < $1.0.id }
        let counts = labels.map { label in "\(label) \(errors.filter { $0.0.label == label }.count)" }.joined(separator: " ")
        var first = ["leave_one_out classifier \(model.notation())", "errors \(trainRatio(errors.count))", "class_errors \(counts)"]
        for (row, prediction) in errors { first.append("\(row.id) true \(row.label!) predicted \(prediction.label) share \(fixed(prediction.share))") }
        let residuals = train.indices.map { estimates[$0] - train[$0].target! }
        var second = ["leave_one_out regressor \(regressor.model.notation())", "rmse \(fixed(rmse(residuals))) mae \(fixed(mae(residuals)))", "largest \(settings.top) residuals"]
        let ranking = train.indices.sorted { a, b in fourDecimal(abs(residuals[a])) == fourDecimal(abs(residuals[b])) ? train[a].id < train[b].id : fourDecimal(abs(residuals[a])) > fourDecimal(abs(residuals[b])) }
        for index in ranking.prefix(settings.top) { second.append("\(train[index].id) target \(fixed(train[index].target!)) estimate \(fixed(estimates[index])) residual \(fixed(residuals[index]))") }
        var third = ["leave_one_out by k metric=\(model.metric) weighting=\(model.weighting) scaling=\(model.scaling)"]
        for k in settings.ks { let predictions = byK[k]!; let residuals = zip(predictions, train).map { $0.0.estimate - $0.1.target! }; third.append("k=\(k) correct \(trainRatio(correctCount(predictions, train))) rmse \(fixed(rmse(residuals)))") }
        return [first, second, third]
    }
    func nestedPart() -> [String] {
        var lines = ["nested_cross_validation folds \(settings.folds)"]
        var estimates = Array(repeating: 0.0, count: train.count)
        var correct = 0
        for (number, fold) in folds.enumerated() {
            let training = foldTraining(train, fold)
            let queries = fold.map { train[$0] }
            let results = crossValidate(grid, training, settings.folds, features)
            let first = bestClassifier(results), second = bestRegressor(results)
            let predictions = predictRows(first.model, training, queries, features)
            let hits = correctCount(predictions, queries)
            correct += hits
            let predicted = predictRows(second.model, training, queries, features)
            for (position, index) in fold.enumerated() { estimates[index] = predicted[position].estimate }
            let residuals = zip(predicted, queries).map { $0.0.estimate - $0.1.target! }
            lines.append("fold \(number + 1) classifier \(first.model.notation()) inner \(fixed(Double(first.correct) / Double(training.count))) outer \(ratio(hits, fold.count))")
            lines.append("fold \(number + 1) regressor \(second.model.notation()) inner \(fixed(second.error)) outer \(fixed(rmse(residuals)))")
        }
        lines.append("nested accuracy \(trainRatio(correct)) rmse \(fixed(rmse(train.indices.map { estimates[$0] - train[$0].target! })))")
        return lines
    }
    func featureSelectionPart() -> [String] {
        let model = classifier.model
        var current = features
        var selected = current
        var selectedCorrect = classifier.correct
        var lines = ["feature_selection \(model.notation())", "start features \(names(current)) correct \(trainRatio(classifier.correct))"]
        var step = 0
        while current.count >= 3 {
            step += 1
            let candidates = current.map { feature in (feature, crossValidate([model], train, settings.folds, current.filter { $0 != feature })[0].correct) }
            var chosen = candidates[0]
            for candidate in candidates.dropFirst() where candidate.1 > chosen.1 { chosen = candidate }
            current.removeAll { $0 == chosen.0 }
            let listing = candidates.map { "\(featureNames[$0.0]) \($0.1)" }.joined(separator: " ")
            lines.append("step \(step) remove \(featureNames[chosen.0]) correct \(trainRatio(chosen.1)) candidates \(listing)")
            if chosen.1 >= selectedCorrect { selected = current; selectedCorrect = chosen.1 }
        }
        let predictions = predictRows(model, train, labelled, selected)
        lines.append("selected features \(names(selected)) correct \(trainRatio(selectedCorrect))")
        lines.append("selected test \(ratio(correctCount(predictions, labelled), labelled.count))")
        return lines
    }
    func testClassificationPart() -> [String] {
        let pairs = labelledPredictions.map { ($0.0.label!, $0.1.label) }
        return ["test classification \(classifier.model.notation())", "labelled \(labelled.count) correct \(ratio(pairs.filter { $0.0 == $0.1 }.count, labelled.count))"] + evaluationLines(pairs, labels)
    }
    func uncertainPart() -> [String] {
        let margins = testPredictions.map { $0.share - $0.runnerShare }
        let ranking = test.indices.sorted { fourDecimal(margins[$0]) == fourDecimal(margins[$1]) ? $0 < $1 : fourDecimal(margins[$0]) < fourDecimal(margins[$1]) }
        return ["uncertain \(settings.top) test rows"] + ranking.prefix(settings.top).map { index in
            let row = test[index], prediction = testPredictions[index]
            return "\(row.id) predicted \(prediction.label) share \(fixed(prediction.share)) runner_up \(prediction.runner ?? "-") share \(fixed(prediction.runnerShare)) margin \(fixed(margins[index])) true \(row.label ?? "-")"
        }
    }
    func testRegressionPart() -> [String] {
        let pairs = zip(test, testEstimates).filter { $0.0.target != nil }
        let errors = pairs.map { $0.1 - $0.0.target! }
        var lines = ["test regression \(regressor.model.notation())", "targets \(pairs.count) rmse \(fixed(rmse(errors))) mae \(fixed(mae(errors))) r2 \(fixed(rSquared(errors, pairs.map { $0.0.target! })))"]
        for label in labels {
            let selected = pairs.filter { $0.0.label == label }.map { $0.1 - $0.0.target! }
            lines.append("class \(label) targets \(selected.count) rmse \(selected.isEmpty ? "-" : fixed(rmse(selected)))")
        }
        return lines
    }
    func misclassifiedPart() -> [String] {
        var lines = ["misclassified test rows"]
        var count = 0
        for (row, prediction) in labelledPredictions where row.label != prediction.label {
            count += 1
            lines.append("\(row.id) true \(row.label!) predicted \(prediction.label) share \(fixed(prediction.share))")
            for neighbor in prediction.nearest { lines.append("  \(neighbor.row.id) \(neighbor.row.label!) \(fixed(neighbor.distance))") }
        }
        lines.append("count \(count)")
        return lines
    }
    func metricsReport() -> [String] {
        var parts = [dataPart()]
        parts += settings.scalings.map(scalingPart)
        parts += [foldsPart(), selectionPart(), topPart(true), topPart(false)]
        parts += bestPerItemParts()
        let labelsCV = zip(train, classifier.predictions).map { ($0.0.label!, $0.1.label) }
        let sharesCV = zip(train, classifier.predictions).map { ($0.1, $0.0.label!) }
        parts += [classifierFoldsPart(), regressorFoldsPart(), ["cross_validation classes"] + evaluationLines(labelsCV, labels), ["cross_validation reliability"] + reliabilityLines(sharesCV, settings.bins), mcnemarPart()]
        parts += leaveOneOutParts()
        parts += [nestedPart(), featureSelectionPart(), testClassificationPart(), ["test reliability"] + reliabilityLines(labelledPredictions.map { ($0.1, $0.0.label!) }, settings.bins), uncertainPart(), testRegressionPart(), misclassifiedPart()]
        return joinParts(parts)
    }
    func learningCurveTable() -> [String] {
        var lines = ["n,train_size,correct,accuracy,rmse"]
        for limit in settings.curve {
            var taken = Dictionary(uniqueKeysWithValues: labels.map { ($0, 0) })
            let rows = train.filter { row in let label = row.label!; let count = taken[label]!; if count < limit { taken[label] = count + 1; return true }; return false }
            let predictions = predictRows(classifier.model, rows, labelled, features)
            let correct = correctCount(predictions, labelled)
            let estimates = predictRows(regressor.model, rows, targeted, features)
            let errors = zip(estimates, targeted).map { $0.0.estimate - $0.1.target! }
            lines.append("\(limit),\(rows.count),\(correct),\(fixed(Double(correct) / Double(labelled.count))),\(fixed(rmse(errors)))")
        }
        return lines
    }
    func prototypesReport() -> [String] {
        let space = ClassifierSpace(classifier.model, train, test)
        let ordered = train.sorted { $0.id < $1.id }
        let (edited, passes) = wilsonEditing(space, ordered, settings.editK)
        let (condensed, originalScans) = hartCondensing(space, ordered)
        let (editedCondensed, editedScans) = hartCondensing(space, edited)
        var editing = ["editing k=\(settings.editK)"]
        for (number, removed) in passes.enumerated() {
            editing.append("pass \(number + 1) removed \(removed.count)")
            for (row, vote) in removed { editing.append("  \(row.id) true \(row.label!) predicted \(vote.label) share \(fixed(vote.share))") }
        }
        editing.append("edited size \(edited.count) removed \(train.count - edited.count)")
        let sets = [("original", ordered), ("edited", edited), ("condensed", condensed), ("edited_condensed", editedCondensed)].map { name, rows in
            let knn = labelled.filter { space.voting($0, rows, classifier.model.k).label == $0.label }.count
            let nearest = labelled.filter { space.nearestLabel($0, rows) == $0.label }.count
            return "set \(name) size \(rows.count) \(labelCounts(rows, labels)) knn \(ratio(knn, labelled.count)) 1nn \(ratio(nearest, labelled.count))"
        }
        var borders = ["borders"]
        var total = 0
        for label in labels {
            let members = ordered.filter { $0.label == label }
            var count = 0
            var same = 0.0, other = 0.0
            for row in members {
                let order = space.order(row, ordered.filter { $0.id != row.id })
                if order[0].row.label != label { count += 1 }
                same += order.first { $0.row.label == label }!.distance
                other += order.first { $0.row.label != label }!.distance
            }
            total += count
            borders.append("class \(label) size \(members.count) border \(count) same \(fixed(same / Double(members.count))) other \(fixed(other / Double(members.count)))")
        }
        borders.append("border total \(trainRatio(total))")
        var occurrences = Dictionary(uniqueKeysWithValues: train.map { ($0.id, 0) })
        for prediction in testPredictions { for neighbor in prediction.nearest { occurrences[neighbor.row.id]! += 1 } }
        var hubs = ["hubs k=\(classifier.model.k) queries \(test.count)"]
        let ranked = train.sorted { occurrences[$0.id]! == occurrences[$1.id]! ? $0.id < $1.id : occurrences[$0.id]! > occurrences[$1.id]! }
        for row in ranked.prefix(settings.top) { hubs.append("\(row.id) \(row.label!) \(occurrences[row.id]!)") }
        hubs.append("anti_hubs \(occurrences.values.filter { $0 == 0 }.count)")
        func ids(_ rows: [Row]) -> [String] { stride(from: 0, to: rows.count, by: 10).map { start in rows[start..<min(start + 10, rows.count)].map(\.id).joined(separator: " ") } }
        return joinParts([["space \(classifier.model.notation())"], editing, ["condensing original scans \(originalScans) size \(condensed.count)", "condensing edited scans \(editedScans) size \(editedCondensed.count)"], sets, ["prototypes condensed"] + ids(condensed), ["prototypes edited_condensed"] + ids(editedCondensed), borders, hubs])
    }
    func write() throws {
        for (name, lines) in [("cv_grid.csv", gridTable()), ("predictions.csv", predictionTable()), ("metrics.txt", metricsReport()), ("learning_curve.csv", learningCurveTable()), ("prototypes.txt", prototypesReport())] { try writeLines(name, lines) }
    }
}

let experiment = try Experiment(readDataset())
try experiment.write()
