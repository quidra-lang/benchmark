import Foundation

func firstMaximum(_ values: [Double]) -> Int { var best = 0; for i in values.indices.dropFirst() { if values[i] > values[best] { best = i } }; return best }
func entropy(_ probabilities: [Double]) -> Double { -probabilities.reduce(0) { $0 + ($1 > 0 ? $1 * log($1) : 0) } }
func parameterCount(_ count: Int, _ type: CovarianceKind) -> Int {
    switch type { case .full: return 6 * count - 1; case .tied: return 3 * count + 2; case .diagonal: return 5 * count - 1; case .spherical: return 4 * count - 1 }
}
struct ModelSummary {
    let fit: EMFit
    let typeIndex: Int
    let parameters: Int
    let assignment: [Int]
    let sizes: [Int]
    let entropy: Double
    let bic: Double
    let aic: Double
    let icl: Double
    var count: Int { fit.model.count }
    var type: CovarianceKind { fit.model.type }
    init(_ fit: EMFit, _ typeIndex: Int, _ n: Int) {
        self.fit = fit; self.typeIndex = typeIndex
        let parameterTotal = parameterCount(fit.model.count, fit.model.type)
        parameters = parameterTotal
        let labels = fit.records.map { firstMaximum($0.probabilities) }
        assignment = labels
        sizes = (0..<fit.model.count).map { k in labels.filter { $0 == k }.count }
        var total = 0.0
        for record in fit.records { total += -record.probabilities.reduce(0) { $0 + ($1 > 0 ? $1 * log($1) : 0) } }
        let bicValue = -2 * fit.logLikelihood + Double(parameterTotal) * log(Double(n))
        entropy = total; bic = bicValue; aic = -2 * fit.logLikelihood + 2 * Double(parameterTotal); icl = bicValue + 2 * total
    }
    func criterion(_ name: String) -> Double { name == "bic" ? bic : name == "aic" ? aic : icl }
}
func estimateModels(_ points: [Observation], _ initial: [Int: InitialValues], _ settings: Settings) -> [ModelSummary] {
    var models: [ModelSummary] = []
    for k in settings.counts { for (index, type) in settings.types.enumerated() { models.append(ModelSummary(runEM(points, initial[k]!, type, settings), index, points.count)) } }
    return models
}
func ranking(_ models: [ModelSummary], _ criterion: String, _ candidates: [Int]? = nil) -> [Int] {
    (candidates ?? Array(models.indices)).sorted {
        let a = models[$0], b = models[$1], av = writtenValue(a.criterion(criterion)), bv = writtenValue(b.criterion(criterion))
        return av == bv ? [a.parameters, a.count, a.typeIndex].lexicographicallyPrecedes([b.parameters, b.count, b.typeIndex]) : av < bv
    }
}
func contingency(_ left: [Int], _ right: [Int], _ rows: Int, _ columns: Int) -> [[Int]] {
    var table = Array(repeating: Array(repeating: 0, count: columns), count: rows)
    for i in left.indices { table[left[i]][right[i]] += 1 }
    return table
}
func chooseTwo(_ n: Int) -> Int { n * (n - 1) / 2 }
struct RandIndex {
    let numerator: Int
    let denominator: Int
    var text: String { "\(numerator)/\(denominator) \(decimal(Double(numerator) / Double(denominator)))" }
}
func adjustedRand(_ left: [Int], _ right: [Int], _ rows: Int, _ columns: Int) -> RandIndex {
    let table = contingency(left, right, rows, columns), shared = table.flatMap { $0 }.reduce(0) { $0 + chooseTwo($1) }
    let a = table.reduce(0) { $0 + chooseTwo($1.reduce(0, +)) }, b = (0..<columns).reduce(0) { total, col in total + chooseTwo(table.reduce(0) { $0 + $1[col] }) }
    let total = chooseTwo(left.count)
    var numerator = 2 * (total * shared - a * b), denominator = total * (a + b) - 2 * a * b
    if denominator == 0 { return RandIndex(numerator: 1, denominator: 1) }
    if denominator < 0 { numerator = -numerator; denominator = -denominator }
    var x = abs(numerator), y = denominator
    while y != 0 { let rest = x % y; x = y; y = rest }
    return RandIndex(numerator: numerator / x, denominator: denominator / x)
}
struct PartitionMetrics { let silhouette: Double?; let clusterSilhouettes: [Double?]; let ch: Double?; let db: Double? }
func partitionMetrics(_ points: [Observation], _ labels: [Int], _ count: Int) -> PartitionMetrics {
    let members = (0..<count).map { k in points.indices.filter { labels[$0] == k } }, occupied = members.indices.filter { !members[$0].isEmpty }
    if occupied.count < 2 { return PartitionMetrics(silhouette: nil, clusterSilhouettes: Array(repeating: nil, count: count), ch: nil, db: nil) }
    var centroids = Array(repeating: Vector2(x: 0, y: 0), count: count)
    for k in occupied { var x = 0.0, y = 0.0; for i in members[k] { x += points[i].position.x; y += points[i].position.y }; centroids[k] = Vector2(x: x / Double(members[k].count), y: y / Double(members[k].count)) }
    let distances = points.map { point in points.map { distance(point.position, $0.position) } }
    var silhouettes: [Double] = []
    for i in points.indices {
        let current = labels[i]
        if members[current].count == 1 { silhouettes.append(0); continue }
        let own = members[current].filter { $0 != i }.reduce(0) { $0 + distances[i][$1] } / Double(members[current].count - 1)
        let other = occupied.filter { $0 != current }.map { k in members[k].reduce(0) { $0 + distances[i][$1] } / Double(members[k].count) }.min()!
        silhouettes.append((other - own) / max(own, other))
    }
    let n = Double(points.count), g = Double(occupied.count), center = Vector2(x: points.reduce(0) { $0 + $1.position.x } / n, y: points.reduce(0) { $0 + $1.position.y } / n)
    let between = occupied.reduce(0.0) { $0 + Double(members[$1].count) * squaredDistance(centroids[$1], center) }
    let within = points.indices.reduce(0.0) { $0 + squaredDistance(points[$1].position, centroids[labels[$1]]) }
    let scattered = (0..<count).map { k in members[k].isEmpty ? 0 : members[k].reduce(0) { $0 + distance(points[$1].position, centroids[k]) } / Double(members[k].count) }
    let db = occupied.reduce(0.0) { total, k in total + occupied.filter { $0 != k }.map { (scattered[k] + scattered[$0]) / distance(centroids[k], centroids[$0]) }.max()! } / g
    let clusterSilhouettes: [Double?] = members.map { indices in indices.isEmpty ? nil : indices.reduce(0) { $0 + silhouettes[$1] } / Double(indices.count) }
    return PartitionMetrics(silhouette: silhouettes.reduce(0, +) / n, clusterSilhouettes: clusterSilhouettes, ch: (between / (g - 1)) / (within / (n - g)), db: db)
}
func parents(_ previous: ModelSummary, _ current: ModelSummary) -> (numbers: [String], shared: [Int]) {
    let table = contingency(previous.assignment, current.assignment, previous.count, current.count)
    var numbers: [String] = [], shared: [Int] = []
    for col in 0..<current.count {
        let counts = table.map { $0[col] }, best = firstMaximum(counts.map(Double.init))
        numbers.append(counts[best] == 0 ? "-" : String(best + 1)); shared.append(counts[best])
    }
    return (numbers, shared)
}
func bestMatching(_ table: [[Int]]) -> (permutation: [Int], agreement: Int) {
    let count = table.count
    var best: [Int] = [], agreement = -1
    func visit(_ permutation: [Int], _ remaining: [Int]) {
        if remaining.isEmpty {
            let total = permutation.enumerated().reduce(0) { $0 + table[$1.element][$1.offset] }
            if total > agreement { best = permutation; agreement = total }
            return
        }
        for next in remaining { visit(permutation + [next], remaining.filter { $0 != next }) }
    }
    visit([], Array(0..<count))
    return (best, agreement)
}
struct ComponentDetails {
    let index: Int
    let size: Int
    let softSize: Double
    let geometry: Ellipse
    let insideOne: Int
    let insideTwo: Int
    let silhouette: Double?
    let observed: [Int]
    let expected: [Double]
    let chiSquare: Double
}
func componentDetails(_ model: ModelSummary, _ points: [Observation], _ edges: [Double], _ metrics: PartitionMetrics) -> [ComponentDetails] {
    (0..<model.count).map { k in
        let mixture = model.fit.model, member = points.indices.filter { model.assignment[$0] == k }
        let squared = points.map { mixture.covariances[k].mahalanobis($0.position, mixture.means[k]) }
        let distances = member.map { sqrt(squared[$0]) }, boundaries = [0] + edges
        var observed: [Int] = [], expected: [Double] = [], chiSquare = 0.0
        for i in boundaries.indices {
            let left = boundaries[i], right = i + 1 < boundaries.count ? boundaries[i + 1] : Double.infinity
            let o = distances.filter { left <= $0 && $0 < right }.count, e = Double(member.count) * (exp(-left * left / 2) - (right.isInfinite ? 0 : exp(-right * right / 2)))
            observed.append(o); expected.append(e); chiSquare += (Double(o) - e) * (Double(o) - e) / e
        }
        return ComponentDetails(index: k, size: member.count, softSize: model.fit.records.reduce(0) { $0 + $1.probabilities[k] }, geometry: ellipse(mixture.covariances[k]), insideOne: member.filter { squared[$0] <= 1 }.count, insideTwo: member.filter { squared[$0] <= 4 }.count, silhouette: metrics.clusterSilhouettes[k], observed: observed, expected: expected, chiSquare: chiSquare)
    }
}
func clusterProbabilities(_ clusters: [[Int]], _ record: Posterior) -> [Double] { clusters.map { $0.reduce(0) { $0 + record.probabilities[$1] } } }
func clusterEntropy(_ clusters: [[Int]], _ records: [Posterior]) -> Double { records.reduce(0) { $0 + entropy(clusterProbabilities(clusters, $1)) } }
struct MergeStep { let first: String; let second: String; let entropy: Double; let sizes: [Int] }
func mergingSteps(_ model: ModelSummary) -> (initial: Double, steps: [MergeStep]) {
    var clusters = (0..<model.count).map { [$0] }, steps: [MergeStep] = []
    let initial = clusterEntropy(clusters, model.fit.records)
    func name(_ values: [Int]) -> String { values.map { String($0 + 1) }.joined(separator: "+") }
    while clusters.count > 1 {
        var best: (a: Int, b: Int, value: Double, proposed: [[Int]])?
        for a in clusters.indices {
            for b in (a + 1)..<clusters.count {
                var proposed = clusters
                proposed[a] = (clusters[a] + clusters[b]).sorted(); proposed.remove(at: b); proposed.sort { $0[0] < $1[0] }
                let value = clusterEntropy(proposed, model.fit.records)
                if best == nil || writtenValue(value) < writtenValue(best!.value) { best = (a, b, value, proposed) }
            }
        }
        let selected = best!, assigned = model.fit.records.map { firstMaximum(clusterProbabilities(selected.proposed, $0)) }
        steps.append(MergeStep(first: name(clusters[selected.a]), second: name(clusters[selected.b]), entropy: selected.value, sizes: selected.proposed.indices.map { k in assigned.filter { $0 == k }.count }))
        clusters = selected.proposed
    }
    return (initial, steps)
}
func refitFromKMeans(_ model: ModelSummary, _ means: KMeansResult, _ points: [Observation], _ settings: Settings) -> ModelSummary {
    var weights: [Double] = [], covariances: [Covariance] = []
    for k in 0..<model.count {
        let members = points.indices.filter { means.assignment[$0] == k }, center = means.centers[k], count = Double(members.count)
        var a = 0.0, b = 0.0, c = 0.0
        for i in members { let dx = points[i].position.x - center.x, dy = points[i].position.y - center.y; a += dx * dx; b += dx * dy; c += dy * dy }
        weights.append(count / Double(points.count)); covariances.append(Covariance(a: a / count + settings.epsilon, b: b / count, c: c / count + settings.epsilon))
    }
    let initial = InitialValues(weights: weights, means: means.centers, covariances: covariances)
    return ModelSummary(runEM(points, initial, model.type, settings), model.typeIndex, points.count)
}
struct FoldResult { let fold: Int; let train: Int; let test: Int; let trainLogLikelihood: Double; let testLogLikelihood: Double }
func crossValidation(_ model: ModelSummary, _ points: [Observation], _ initial: InitialValues, _ settings: Settings) -> [FoldResult] {
    (0..<settings.folds).map { f in
        let training = points.enumerated().filter { $0.offset % settings.folds != f }.map { $0.element }, testing = points.enumerated().filter { $0.offset % settings.folds == f }.map { $0.element }
        let fitted = runEM(training, initial, model.type, settings), measured = expectation(testing, fitted.model)
        return FoldResult(fold: f + 1, train: training.count, test: testing.count, trainLogLikelihood: fitted.logLikelihood / Double(training.count), testLogLikelihood: measured.logLikelihood / Double(testing.count))
    }
}

func modelsBlocks(_ models: [ModelSummary]) -> [[String]] {
    models.map { summary in
        let fit = summary.fit, mixture = fit.model
        var lines = ["model K=\(summary.count) type=\(summary.type.rawValue)", "parameters \(summary.parameters)", "loglik \(decimal(fit.logLikelihood))", "bic \(decimal(summary.bic))", "aic \(decimal(summary.aic))", "icl \(decimal(summary.icl))", "mean_entropy \(decimal(summary.entropy / Double(fit.records.count)))", "settled_at \(fit.settledAt)", "largest_increase iteration \(fit.largestIteration) value \(decimal(fit.largestIncrease))", "violations \(fit.violations.count)", "sizes " + integers(summary.sizes)]
        for k in 0..<summary.count {
            let geometry = ellipse(mixture.covariances[k])
            lines.append("component \(k + 1) weight \(decimal(mixture.weights[k])) mean \(vectorText(mixture.means[k])) cov \(covarianceText(mixture.covariances[k])) axes \(reals([geometry.major, geometry.minor])) angle \(decimal(geometry.angle))")
        }
        return lines
    }
}
func traceLines(_ models: [ModelSummary]) -> [String] {
    ["K,type,iteration,loglik"] + models.flatMap { model in model.fit.trace.enumerated().map { "\(model.count),\(model.type.rawValue),\($0.offset),\(decimal($0.element))" } }
}
func assignmentLines(_ model: ModelSummary, _ means: KMeansResult, _ points: [Observation]) -> [String] {
    ["id,component,max_responsibility,log_density,kmeans_cluster"] + points.indices.map { i in
        "\(points[i].id),\(model.assignment[i] + 1),\(decimal(model.fit.records[i].probabilities.max()!)),\(decimal(model.fit.records[i].logDensity)),\(means.assignment[i] + 1)"
    }
}
func rankingBlock(_ models: [ModelSummary], _ ranked: [String: [Int]]) -> [String] {
    let selected = models[ranked["bic"]![0]], baseline = writtenValue(selected.bic)
    var lines = ["ranking by bic", "rank K type parameters loglik bic delta_bic aic aic_rank icl icl_rank"]
    for (position, i) in ranked["bic"]!.enumerated() {
        let model = models[i], aicRank = ranked["aic"]!.firstIndex(of: i)! + 1, iclRank = ranked["icl"]!.firstIndex(of: i)! + 1
        lines.append("\(position + 1) \(model.count) \(model.type.rawValue) \(model.parameters) \(decimal(model.fit.logLikelihood)) \(decimal(model.bic)) \(decimal(writtenValue(model.bic) - baseline)) \(decimal(model.aic)) \(aicRank) \(decimal(model.icl)) \(iclRank)")
    }
    for (label, criterion) in [("selected", "bic"), ("best_aic", "aic"), ("best_icl", "icl")] { let best = models[ranked[criterion]![0]]; lines.append("\(label) K=\(best.count) type=\(best.type.rawValue)") }
    return lines
}
func bestPerTypeBlock(_ models: [ModelSummary], _ settings: Settings) -> [String] {
    var lines = ["best K per type"]
    for type in settings.types {
        let candidates = models.indices.filter { models[$0].type == type }, winners = ["bic", "aic", "icl"].map { models[ranking(models, $0, candidates)[0]].count }
        lines.append("\(type.rawValue) bic \(winners[0]) aic \(winners[1]) icl \(winners[2])")
    }
    return lines
}
func perCountBlocks(_ models: [ModelSummary], _ means: [Int: KMeansResult], _ points: [Observation], _ settings: Settings) -> [[String]] {
    var blocks: [[String]] = [], previous: ModelSummary?
    for count in settings.counts {
        let model = models[ranking(models, "bic", models.indices.filter { models[$0].count == count })[0]], kmeans = means[count]!
        let gmmMetrics = partitionMetrics(points, model.assignment, count), kmeansMetrics = partitionMetrics(points, kmeans.assignment, count)
        var lines = ["K=\(count) type=\(model.type.rawValue) bic \(decimal(model.bic))", "  kmeans iterations \(kmeans.iterations) inertia \(decimal(kmeans.inertia))", "  ari \(adjustedRand(model.assignment, kmeans.assignment, count, count).text)", "  silhouette gmm \(optionalDecimal(gmmMetrics.silhouette)) kmeans \(optionalDecimal(kmeansMetrics.silhouette))", "  calinski_harabasz gmm \(optionalDecimal(gmmMetrics.ch)) kmeans \(optionalDecimal(kmeansMetrics.ch))", "  davies_bouldin gmm \(optionalDecimal(gmmMetrics.db)) kmeans \(optionalDecimal(kmeansMetrics.db))"]
        if let previous { let relation = parents(previous, model); lines.append("  parents K=\(previous.count) " + relation.numbers.joined(separator: " ") + " shared " + integers(relation.shared)) }
        blocks.append(lines); previous = model
    }
    return blocks
}
func violationsBlock(_ models: [ModelSummary]) -> [String] {
    var lines = ["violations"]
    for model in models { for t in model.fit.violations { lines.append("K=\(model.count) type=\(model.type.rawValue) iteration \(t) previous \(decimal(model.fit.trace[t - 1])) current \(decimal(model.fit.trace[t]))") } }
    if lines.count == 1 { lines.append("none") }
    return lines
}
func componentsBlock(_ model: ModelSummary, _ details: [ComponentDetails]) -> [String] {
    var lines = ["selected components"]
    for detail in details {
        let k = detail.index, mixture = model.fit.model, geometry = detail.geometry
        lines += ["component \(k + 1) weight \(decimal(mixture.weights[k])) size \(detail.size) soft_size \(decimal(detail.softSize)) mean \(vectorText(mixture.means[k]))",
                  "  cov \(covarianceText(mixture.covariances[k])) corr \(decimal(geometry.correlation))",
                  "  eigen \(reals([geometry.leading, geometry.trailing])) direction \(vectorText(geometry.direction)) angle \(decimal(geometry.angle))",
                  "  axes_1sigma \(reals([geometry.major, geometry.minor])) axes_2sigma \(reals([2 * geometry.major, 2 * geometry.minor]))",
                  "  inside_1sigma \(detail.insideOne) inside_2sigma \(detail.insideTwo) area_1sigma \(decimal(geometry.area))",
                  "  silhouette \(optionalDecimal(detail.silhouette))",
                  "  gof observed \(integers(detail.observed)) expected \(reals(detail.expected)) chi2 \(decimal(detail.chiSquare))"]
    }
    return lines
}
func overlapBlock(_ model: ModelSummary) -> [String] {
    var lines = ["overlap"]
    let mixture = model.fit.model
    for a in 0..<model.count {
        for b in (a + 1)..<model.count {
            let value = bhattacharyya(mixture.means[a], mixture.covariances[a], mixture.means[b], mixture.covariances[b]), shared = model.fit.records.reduce(0) { $0 + $1.probabilities[a] * $1.probabilities[b] }
            lines.append("\(a + 1)-\(b + 1) bhattacharyya \(decimal(value)) coefficient \(decimal(exp(-value))) shared \(decimal(shared))")
        }
    }
    if lines.count == 1 { lines.append("none") }
    return lines
}
func mergingBlock(_ model: ModelSummary) -> [String] {
    let merged = mergingSteps(model)
    return ["merging", "start entropy \(decimal(merged.initial))"] + merged.steps.enumerated().map { "step \($0.offset + 1) merge \($0.element.first) \($0.element.second) entropy \(decimal($0.element.entropy)) sizes \(integers($0.element.sizes))" }
}
func kmeansBlock(_ model: ModelSummary, _ means: KMeansResult, _ points: [Observation]) -> [String] {
    let count = model.count, table = contingency(model.assignment, means.assignment, count, count), matching = bestMatching(table)
    var lines = ["kmeans K=\(count)", "iterations \(means.iterations)", "inertia \(decimal(means.inertia))", "sizes " + integers(means.sizes)]
    for (index, center) in means.centers.enumerated() { lines.append("center \(index + 1) \(vectorText(center))") }
    lines += ["contingency"] + table.map { integers($0) }
    lines += ["ari \(adjustedRand(model.assignment, means.assignment, count, count).text)", "matching " + integers(matching.permutation.map { $0 + 1 }), "agreement \(matching.agreement)/\(points.count) \(decimal(Double(matching.agreement) / Double(points.count)))"]
    var disagreements = 0
    for i in points.indices where matching.permutation[means.assignment[i]] != model.assignment[i] {
        lines.append("disagree \(points[i].id) gmm \(model.assignment[i] + 1) kmeans \(means.assignment[i] + 1) max \(decimal(model.fit.records[i].probabilities.max()!))"); disagreements += 1
    }
    lines.append("disagreements \(disagreements)")
    return lines
}
func refitBlock(_ selected: ModelSummary, _ refit: ModelSummary) -> [String] {
    ["refit_from_kmeans K=\(selected.count) type=\(selected.type.rawValue)", "loglik \(decimal(refit.fit.logLikelihood)) bic \(decimal(refit.bic)) settled_at \(refit.fit.settledAt)", "sizes " + integers(refit.sizes), "ari_vs_selected \(adjustedRand(selected.assignment, refit.assignment, selected.count, selected.count).text)"]
}
func crossValidationBlock(_ model: ModelSummary, _ folds: [FoldResult]) -> [String] {
    ["cross_validation K=\(model.count) type=\(model.type.rawValue) folds \(folds.count)"] + folds.map { "fold \($0.fold) train \($0.train) test \($0.test) train_loglik \(decimal($0.trainLogLikelihood)) test_loglik \(decimal($0.testLogLikelihood))" } + ["mean_test_loglik \(decimal(folds.reduce(0) { $0 + $1.testLogLikelihood } / Double(folds.count)))"]
}
func uncertainBlock(_ model: ModelSummary, _ points: [Observation], _ threshold: Double) -> [String] {
    let indices = points.indices.filter { model.fit.records[$0].probabilities.max()! < threshold }.sorted {
        let a = writtenValue(model.fit.records[$0].probabilities.max()!), b = writtenValue(model.fit.records[$1].probabilities.max()!)
        return a == b ? $0 < $1 : a < b
    }
    return ["uncertain threshold \(decimal(threshold))"] + indices.map { i in "\(points[i].id) component \(model.assignment[i] + 1) max \(decimal(model.fit.records[i].probabilities.max()!)) responsibilities \(reals(model.fit.records[i].probabilities))" } + ["count \(indices.count)"]
}
func outliersBlock(_ model: ModelSummary, _ points: [Observation], _ threshold: Double) -> [String] {
    let indices = points.indices.filter { model.fit.records[$0].logDensity < threshold }.sorted {
        let a = writtenValue(model.fit.records[$0].logDensity), b = writtenValue(model.fit.records[$1].logDensity)
        return a == b ? $0 < $1 : a < b
    }
    return ["outliers threshold \(decimal(threshold))"] + indices.map { i in
        let k = model.assignment[i], q = model.fit.model.covariances[k].mahalanobis(points[i].position, model.fit.model.means[k])
        return "\(points[i].id) component \(k + 1) log_density \(decimal(model.fit.records[i].logDensity)) q \(decimal(q))"
    } + ["count \(indices.count)"]
}
func selectionBlocks(_ models: [ModelSummary], _ selected: ModelSummary, _ ranked: [String: [Int]], _ means: [Int: KMeansResult], _ points: [Observation], _ initial: [Int: InitialValues], _ settings: Settings) -> [[String]] {
    let metrics = partitionMetrics(points, selected.assignment, selected.count), details = componentDetails(selected, points, settings.edges, metrics), kmeans = means[selected.count]!
    var blocks = [rankingBlock(models, ranked), bestPerTypeBlock(models, settings)]
    blocks += perCountBlocks(models, means, points, settings)
    blocks += [violationsBlock(models), componentsBlock(selected, details), overlapBlock(selected), mergingBlock(selected), kmeansBlock(selected, kmeans, points)]
    let refit = refitFromKMeans(selected, kmeans, points, settings), cv = crossValidation(selected, points, initial[selected.count]!, settings)
    blocks += [refitBlock(selected, refit), crossValidationBlock(selected, cv), uncertainBlock(selected, points, settings.uncertain), outliersBlock(selected, points, settings.lowDensity)]
    return blocks
}

func plotMaps(_ summary: ModelSummary, _ points: [Observation], _ settings: Settings) -> [String] {
    let model = summary.fit.model, width = settings.width, height = settings.height
    let dx = (settings.xmax - settings.xmin) / Double(width), dy = (settings.ymax - settings.ymin) / Double(height)
    func center(_ row: Int, _ col: Int) -> Vector2 { Vector2(x: settings.xmin + (Double(col) + 0.5) * dx, y: settings.ymax - (Double(row) + 0.5) * dy) }
    func cell(_ point: Vector2) -> (row: Int, col: Int) { (Int(floor((settings.ymax - point.y) / dy)), Int(floor((point.x - settings.xmin) / dx))) }
    func inside(_ row: Int, _ col: Int) -> Bool { row >= 0 && row < height && col >= 0 && col < width }
    let coordinates = (0..<height).map { row in (0..<width).map { center(row, $0) } }
    let posteriors = coordinates.map { $0.map { posterior($0, model) } }, densities = posteriors.map { $0.map { $0.scores.reduce(0) { $0 + exp($1) } } }
    let maximum = densities.flatMap { $0 }.max()!, mass = densities.flatMap { $0 }.reduce(0, +) * dx * dy
    var densityMap = Array(repeating: Array(repeating: " ", count: width), count: height), regionMap = densityMap, uncertaintyMap = densityMap, pointMap = densityMap
    var levelCounts = Array(repeating: 0, count: 10)
    for row in 0..<height {
        for col in 0..<width {
            let record = posteriors[row][col], level = min(9, Int(floor(10 * densities[row][col] / maximum)))
            densityMap[row][col] = levelCharacters[level]; levelCounts[level] += 1
            regionMap[row][col] = String(firstMaximum(record.scores) + 1)
            if model.count > 1 { let value = max(0, min(9, Int(floor(10 * entropy(record.probabilities) / log(Double(model.count)))))); uncertaintyMap[row][col] = levelCharacters[value] }
        }
    }
    for (k, mean) in model.means.enumerated() { let position = cell(mean); if inside(position.row, position.col) { densityMap[position.row][position.col] = String(k + 1) } }
    var bins = Array(repeating: Array(repeating: Set<Int>(), count: width), count: height), outside = 0
    for (i, point) in points.enumerated() { let position = cell(point.position); if inside(position.row, position.col) { bins[position.row][position.col].insert(summary.assignment[i]) } else { outside += 1 } }
    for row in 0..<height {
        for col in 0..<width {
            let assigned = bins[row][col]
            if !assigned.isEmpty { pointMap[row][col] = assigned.count == 1 ? String(assigned.first! + 1) : "*"; continue }
            let contour = (0..<model.count).contains { k in
                let covariance = model.covariances[k], mean = model.means[k]
                if covariance.mahalanobis(coordinates[row][col], mean) > 4 { return false }
                return [(row - 1, col), (row + 1, col), (row, col - 1), (row, col + 1)].contains { r, c in inside(r, c) && covariance.mahalanobis(coordinates[r][c], mean) > 4 }
            }
            if contour { pointMap[row][col] = "." }
        }
    }
    var lines = ["density K=\(model.count) type=\(model.type.rawValue)", "x \(decimal(settings.xmin)) \(decimal(settings.xmax)) y \(decimal(settings.ymin)) \(decimal(settings.ymax)) grid \(width)x\(height)", "max_density \(decimal(maximum, 6)) mass_in_map \(decimal(mass))"] + framed(densityMap)
    for level in 0..<10 { lines.append("level \(level) \"\(levelCharacters[level])\" from \(decimal(Double(level) * maximum / 10, 6)) cells \(levelCounts[level])") }
    lines += ["", "regions"] + framed(regionMap) + ["", "uncertainty"] + framed(uncertaintyMap) + ["", "points"] + framed(pointMap) + ["outside \(outside)"]
    return lines
}

let points = try readObservations(), initial = try readInitialValues(), settings = try readSettings()
let models = estimateModels(points, initial, settings)
let ranked = Dictionary(uniqueKeysWithValues: ["bic", "aic", "icl"].map { ($0, ranking(models, $0)) })
let selected = models[ranked["bic"]![0]]
let means = Dictionary(uniqueKeysWithValues: settings.counts.map { ($0, runKMeans(points, initial[$0]!.means, settings.kmeansIterations)) })
try writeBlocks("models.txt", modelsBlocks(models))
try writeLines("loglik_trace.csv", traceLines(models))
try writeLines("assignments.csv", assignmentLines(selected, means[selected.count]!, points))
try writeBlocks("selection.txt", selectionBlocks(models, selected, ranked, means, points, initial, settings))
try writeLines("density_map.txt", plotMaps(selected, points, settings))
