import Foundation

protocol Smoother {
    var fitted: [Double]? { get }
    var leverage: [Double]? { get }
    var edf: Double? { get }
    func estimate(_ position: Int) -> Double?
    func weights(_ position: Int) -> [Double]?
}

func residualSquare(_ observed: [Double], _ fitted: [Double]) -> Double {
    orderedSum(observed.indices.map { (observed[$0] - fitted[$0]) * (observed[$0] - fitted[$0]) })
}

struct LinearFit: Smoother {
    let x: [Double]
    let xbar: Double
    let sxx: Double
    let slope: Double
    let intercept: Double
    let values: [Double]
    let leverage: [Double]?
    var fitted: [Double]? { values }
    var edf: Double? { 2 }

    init(_ points: [Sample]) {
        let x = points.map { $0.x }
        let y = points.map { $0.y }
        let n = Double(points.count)
        let xbar = orderedSum(x) / n
        let ybar = orderedSum(y) / n
        let sxx = orderedSum(x.map { ($0 - xbar) * ($0 - xbar) })
        let sxy = orderedSum(x.indices.map { (x[$0] - xbar) * (y[$0] - ybar) })
        let slope = sxy / sxx
        let intercept = ybar - slope * xbar
        self.x = x
        self.xbar = xbar
        self.sxx = sxx
        self.slope = slope
        self.intercept = intercept
        values = x.map { intercept + slope * $0 }
        leverage = x.map { 1 / n + ($0 - xbar) * ($0 - xbar) / sxx }
    }

    func estimate(_ position: Int) -> Double? { intercept + slope * (Double(position) / 100) }

    func weights(_ position: Int) -> [Double]? {
        x.map { 1 / Double(x.count) + (Double(position) / 100 - xbar) * ($0 - xbar) / sxx }
    }
}

struct RunningFit: Smoother {
    let positions: [Int]
    let windows: [Range<Int>]
    let values: [Double]
    let leverage: [Double]?
    let edf: Double?
    let useMedian: Bool
    var fitted: [Double]? { values }

    init(_ points: [Sample], _ width: Int, _ useMedian: Bool) {
        var windows: [Range<Int>] = []
        var values: [Double] = []
        var diagonal: [Double] = []
        for i in points.indices {
            let radius = min(min((width - 1) / 2, i), points.count - 1 - i)
            let window = (i - radius)..<(i + radius + 1)
            let ordinates = points[window].map { $0.ordinate }
            let value = useMedian ? Double(ordinates.sorted()[radius]) / 100
                : Double(ordinates.reduce(0, +)) / Double(100 * ordinates.count)
            windows.append(window)
            values.append(value)
            diagonal.append(1 / Double(ordinates.count))
        }
        positions = points.map { $0.position }
        self.windows = windows
        self.values = values
        self.useMedian = useMedian
        leverage = useMedian ? nil : diagonal
        edf = useMedian ? nil : orderedSum(diagonal)
    }

    func nearest(_ position: Int) -> Int {
        var best = 0
        for i in positions.indices.dropFirst() {
            if abs(positions[i] - position) < abs(positions[best] - position) { best = i }
        }
        return best
    }

    func estimate(_ position: Int) -> Double? { values[nearest(position)] }

    func weights(_ position: Int) -> [Double]? {
        if useMedian { return nil }
        let window = windows[nearest(position)]
        return positions.indices.map { window.contains($0) ? 1 / Double(window.count) : 0 }
    }
}

struct IsotonicBlock {
    let start: Int
    let end: Int
    let total: Int
    let count: Int
    var value: Double { Double(total) / Double(100 * count) }
}

struct IsotonicFit: Smoother {
    let positions: [Int]
    let mode: String
    let direction: String
    let values: [Double]
    let blocks: [IsotonicBlock]
    let increasingRSS: Double?
    let decreasingRSS: Double?
    var fitted: [Double]? { values }
    var leverage: [Double]? { nil }
    var edf: Double? { Double(blocks.count) }

    static func fitDirection(_ points: [Sample], _ direction: String) -> ([Double], [IsotonicBlock]) {
        var blocks: [IsotonicBlock] = []
        for (i, point) in points.enumerated() {
            blocks.append(IsotonicBlock(start: i, end: i, total: point.ordinate, count: 1))
            while blocks.count >= 2 {
                let left = blocks[blocks.count - 2]
                let right = blocks.last!
                let a = left.total * right.count
                let b = right.total * left.count
                let violates = direction == "increasing" ? a > b : a < b
                if !violates { break }
                blocks.removeLast(2)
                blocks.append(IsotonicBlock(
                    start: left.start, end: right.end, total: left.total + right.total, count: left.count + right.count
                ))
            }
        }
        var values = [Double](repeating: 0, count: points.count)
        for block in blocks {
            for i in block.start...block.end { values[i] = block.value }
        }
        return (values, blocks)
    }

    init(_ points: [Sample], _ mode: String) {
        let direction: String
        let fit: ([Double], [IsotonicBlock])
        if mode == "auto" {
            let increasing = Self.fitDirection(points, "increasing")
            let decreasing = Self.fitDirection(points, "decreasing")
            let observed = points.map { $0.y }
            let upRSS = residualSquare(observed, increasing.0)
            let downRSS = residualSquare(observed, decreasing.0)
            direction = upRSS <= downRSS ? "increasing" : "decreasing"
            fit = direction == "increasing" ? increasing : decreasing
            increasingRSS = upRSS
            decreasingRSS = downRSS
        } else {
            direction = mode
            fit = Self.fitDirection(points, mode)
            increasingRSS = nil
            decreasingRSS = nil
        }
        positions = points.map { $0.position }
        self.mode = mode
        self.direction = direction
        values = fit.0
        blocks = fit.1
    }

    func estimate(_ position: Int) -> Double? {
        let index = positions.lastIndex { $0 <= position } ?? 0
        return values[index]
    }

    func weights(_ position: Int) -> [Double]? { nil }
}

func methodsInOrder(_ settings: Settings) -> [String] {
    ["linear", "running_mean", "running_median"] + settings.kernels.map { "nw_" + $0 }
        + settings.kernels.map { "ll_" + $0 } + settings.degrees.map { "loess" + $0 } + ["spline", "isotonic"]
}

func parametersFor(_ method: String, _ settings: Settings) -> [String] {
    if method.hasPrefix("running_") { return settings.windows }
    if method.hasPrefix("nw_") || method.hasPrefix("ll_") { return settings.bandwidths }
    if method.hasPrefix("loess") { return settings.spans }
    return method == "spline" ? settings.lambdas : []
}

func fitModel(
    _ method: String, _ parameter: String, _ points: [Sample], _ settings: Settings, _ direction: String,
    robust: Bool = true, diagnostics: Bool = true
) -> any Smoother {
    if method == "linear" { return LinearFit(points) }
    if method.hasPrefix("running_") { return RunningFit(points, Int(parameter)!, method == "running_median") }
    if method == "isotonic" { return IsotonicFit(points, direction) }
    let positions = points.map { $0.position }
    let values = points.map { $0.y }
    if method.hasPrefix("nw_") || method.hasPrefix("ll_") {
        return KernelFit(positions, values, hundredths(parameter), String(method.dropFirst(3)), method.hasPrefix("ll_"), diagnostics)
    }
    if method.hasPrefix("loess") {
        return LoessFit(positions, values, hundredths(parameter), Int(method.dropFirst(5))!, robust ? settings.robustIterations : 0, diagnostics)
    }
    return SplineFit(positions, values, Double(parameter)!, diagnostics)
}

func validationPredictions(
    _ method: String, _ parameter: String, _ points: [Sample], _ settings: Settings, _ direction: String, _ folds: Int
) -> [Double?] {
    var predictions = [Double?](repeating: nil, count: points.count)
    for group in 0..<folds {
        let training = points.enumerated().filter { $0.offset % folds != group }.map { $0.element }
        let model = fitModel(method, parameter, training, settings, direction, robust: false, diagnostics: false)
        for i in stride(from: group, to: points.count, by: folds) { predictions[i] = model.estimate(points[i].position) }
    }
    return predictions
}

struct Candidate {
    let parameter: String
    let score: Double?
    let edf: Double?
}

struct ModelEntry {
    let name: String
    let parameter: String
    let model: any Smoother
    let loo: Double
    let kfold: Double?
    let candidates: [Candidate]
    let selected: Int?
    var gcv: Double? { name == "spline" ? candidates[selected!].score : nil }
}

func selectModels(_ points: [Sample], _ settings: Settings, _ methods: [String], _ mode: String) -> [ModelEntry] {
    let observed = points.map { $0.y }
    return methods.map { method in
        let candidates = parametersFor(method, settings).map { parameter -> Candidate in
            let candidate = fitModel(method, parameter, points, settings, mode, robust: false)
            let score: Double?
            if method == "spline" {
                score = generalizedScore(observed, candidate.fitted!, candidate.edf!)
            } else {
                score = crossValidationScore(observed, validationPredictions(method, parameter, points, settings, mode, points.count))
            }
            return Candidate(parameter: parameter, score: score, edf: candidate.edf)
        }
        let selected = candidates.isEmpty ? nil : chooseCandidate(candidates.map { $0.score })
        var parameter = selected.map { candidates[$0].parameter } ?? (method == "linear" ? "-" : mode)
        let model = fitModel(method, parameter, points, settings, mode)
        let direction = (model as? IsotonicFit)?.direction ?? mode
        if method == "isotonic" { parameter = direction }
        let loo: Double
        if let selected, method != "spline" {
            loo = candidates[selected].score!
        } else {
            loo = crossValidationScore(observed, validationPredictions(method, parameter, points, settings, direction, points.count))!
        }
        let kfold = crossValidationScore(observed, validationPredictions(method, parameter, points, settings, direction, settings.folds))
        return ModelEntry(
            name: method, parameter: parameter, model: model, loo: loo, kfold: kfold, candidates: candidates, selected: selected
        )
    }
}

func firstMaximum(_ values: [Double]) -> Int {
    var best = 0
    for i in values.indices.dropFirst() { if values[i] > values[best] { best = i } }
    return best
}

func residualQuantiles(_ residuals: [Double]) -> [Double] {
    let sorted = residuals.sorted()
    return (0..<5).map { k in
        let numerator = (sorted.count - 1) * k
        let index = numerator / 4
        let remainder = numerator % 4
        return remainder == 0 ? sorted[index]
            : sorted[index] + Double(remainder) / 4 * (sorted[index + 1] - sorted[index])
    }
}

struct Runs {
    let count: Int
    let positive: Int
    let negative: Int
    let z: Double
}

func residualRuns(_ residuals: [Double]) -> Runs {
    let signs = residuals.filter { $0 != 0 }.map { $0 > 0 ? 1 : -1 }
    let positive = signs.filter { $0 == 1 }.count
    let negative = signs.count - positive
    let runs = 1 + zip(signs, signs.dropFirst()).filter { $0.0 != $0.1 }.count
    let n = signs.count
    let product = 2 * positive * negative
    let mean = 1 + Double(product) / Double(n)
    let variance = Double(product * (product - n)) / Double(n * n * (n - 1))
    return Runs(count: runs, positive: positive, negative: negative, z: (Double(runs) - mean) / sqrt(variance))
}

struct Diagnostics {
    let residuals: [Double]
    let rss: Double
    let edf: Double?
    let df: Double?
    let rse: Double?
    let r2: Double
    let nonlinear: Double?
    let acf: [Double]
    let dw: Double
    let runs: Runs
    let largest: Int
    let quantiles: [Double]
    let turning: Int

    init(_ entry: ModelEntry, _ observed: [Double], _ grid: [Double?], _ linearRSS: Double) {
        let fitted = entry.model.fitted!
        let residuals = observed.indices.map { observed[$0] - fitted[$0] }
        let n = observed.count
        let rss = orderedSum(residuals.map { $0 * $0 })
        let mean = orderedSum(observed) / Double(n)
        let tss = orderedSum(observed.map { ($0 - mean) * ($0 - mean) })
        let edf = entry.model.edf
        let df = edf.map { Double(n) - $0 }
        let rse = df.map { sqrt(rss / $0) }
        let nonlinear: Double? = entry.name != "linear" && (edf.map { $0 > 2 } ?? false)
            ? ((linearRSS - rss) / (edf! - 2)) / (rss / df!) : nil
        let residualMean = orderedSum(residuals) / Double(n)
        let centered = residuals.map { $0 - residualMean }
        let denominator = orderedSum(centered.map { $0 * $0 })
        let acf = (1...5).map { lag in
            orderedSum((0..<(n - lag)).map { centered[$0] * centered[$0 + lag] }) / denominator
        }
        let dw = orderedSum(zip(residuals, residuals.dropFirst()).map { pair in
            (pair.1 - pair.0) * (pair.1 - pair.0)
        }) / rss
        let defined = grid.compactMap { $0 }
        let differences = zip(defined, defined.dropFirst()).map { $0.1 - $0.0 }.filter { $0 != 0 }
        let turning = zip(differences, differences.dropFirst()).filter { ($0.0 > 0) != ($0.1 > 0) }.count
        self.residuals = residuals
        self.rss = rss
        self.edf = edf
        self.df = df
        self.rse = rse
        r2 = 1 - rss / tss
        self.nonlinear = nonlinear
        self.acf = acf
        self.dw = dw
        runs = residualRuns(residuals)
        largest = firstMaximum(residuals.map { abs($0) })
        quantiles = residualQuantiles(residuals)
        self.turning = turning
    }
}

struct BandRow {
    let fit: Double?
    let se: Double?
    let lower: Double?
    let upper: Double?
    var values: [Double?] { [fit, se, lower, upper] }
}

struct BandSummary {
    let meanSE: Double
    let covered: Int
}

final class Minstd {
    var state: Int
    init(_ seed: Int) { state = seed }

    func index(_ count: Int) -> Int {
        state = 48271 * state % 2147483647
        return state % count
    }
}

func variabilityBands(_ model: any Smoother, _ rse: Double, _ grid: [Int], _ z: Double) -> [BandRow] {
    grid.map { position in
        guard let value = model.estimate(position) else { return BandRow(fit: nil, se: nil, lower: nil, upper: nil) }
        let se = rse * sqrt(orderedSum(model.weights(position)!.map { $0 * $0 }))
        return BandRow(fit: value, se: se, lower: value - z * se, upper: value + z * se)
    }
}

func bootstrapIntervals(
    _ model: SplineFit, _ residuals: [Double], _ grid: [Int], _ count: Int, _ trim: Int, _ generator: Minstd
) -> [BandRow] {
    let mean = orderedSum(residuals) / Double(residuals.count)
    let centered = residuals.map { $0 - mean }
    var estimates = [[Double]](repeating: [], count: grid.count)
    for _ in 0..<count {
        let response = model.fit.fitted.map { $0 + centered[generator.index(centered.count)] }
        let fit = model.system.fitValues(response)
        for i in grid.indices { estimates[i].append(model.system.evaluate(fit, grid[i])) }
    }
    return grid.indices.map { i in
        let values = estimates[i]
        let average = orderedSum(values) / Double(count)
        let se = sqrt(orderedSum(values.map { ($0 - average) * ($0 - average) }) / Double(count - 1))
        let sorted = values.sorted()
        return BandRow(fit: model.estimate(grid[i]), se: se, lower: sorted[trim], upper: sorted[count - trim - 1])
    }
}

struct SeriesAnalysis {
    let data: SeriesData
    let grid: [Int]
    let entries: [ModelEntry]
    let gridValues: [[Double?]]
    let stats: [Diagnostics]
    let ranking: [Int]
    let outlierMethod: Int
    let standardized: [Double?]
    let cooks: [Double?]
    let outliers: [Int]
    let influential: [Int]
    let bands: [String: [BandRow]]
    let bandSummaries: [String: BandSummary]

    init(_ data: SeriesData, _ settings: Settings, _ methods: [String], _ mode: String, _ generator: Minstd) {
        let points = data.points
        let positions = points.map { $0.position }
        let observed = points.map { $0.y }
        let grid = (0..<settings.gridPoints).map {
            positions[0] + $0 * (positions.last! - positions[0]) / (settings.gridPoints - 1)
        }
        let entries = selectModels(points, settings, methods, mode)
        let linearRSS = residualSquare(observed, entries[0].model.fitted!)
        let gridValues = entries.map { entry in grid.map { entry.model.estimate($0) } }
        let stats = entries.indices.map { Diagnostics(entries[$0], observed, gridValues[$0], linearRSS) }
        let ranking = entries.indices.sorted { a, b in entries[a].loo == entries[b].loo ? a < b : entries[a].loo < entries[b].loo }
        let outlierMethod = ranking.first { entries[$0].model.leverage != nil }!
        let model = entries[outlierMethod].model
        let residuals = stats[outlierMethod].residuals
        var standardized = [Double?](repeating: nil, count: points.count)
        var cooks = standardized
        for (i, leverage) in model.leverage!.enumerated() where leverage < 1 {
            let value = residuals[i] / (stats[outlierMethod].rse! * sqrt(1 - leverage))
            standardized[i] = value
            cooks[i] = value * value * leverage / ((1 - leverage) * model.edf!)
        }
        let outliers = points.indices.filter {
            standardized[$0].map { abs($0) > Double(settings.outlierThreshold) / 100 } ?? false
        }.sorted { a, b in abs(standardized[a]!) == abs(standardized[b]!) ? a < b : abs(standardized[a]!) > abs(standardized[b]!) }
        let influential = points.indices.filter { cooks[$0] != nil }.sorted { a, b in
            cooks[a]! == cooks[b]! ? a < b : cooks[a]! > cooks[b]!
        }.prefix(3)
        var bands: [String: [BandRow]] = [:]
        var summaries: [String: BandSummary] = [:]
        for name in settings.bandMethods {
            let i = methods.firstIndex(of: name)!
            let model = entries[i].model
            let rse = stats[i].rse!
            let rows = variabilityBands(model, rse, grid, settings.bandZ)
            bands[name] = rows
            let errors = rows.compactMap { $0.se }
            let covered = points.indices.filter { j in
                let se = rse * sqrt(orderedSum(model.weights(positions[j])!.map { $0 * $0 }))
                return abs(stats[i].residuals[j]) <= settings.bandZ * sqrt(rse * rse + se * se)
            }.count
            summaries[name] = BandSummary(meanSE: orderedSum(errors) / Double(errors.count), covered: covered)
        }
        let splineIndex = methods.firstIndex(of: "spline")!
        bands["spline_bootstrap"] = bootstrapIntervals(
            entries[splineIndex].model as! SplineFit, stats[splineIndex].residuals,
            grid, settings.bootstrapCount, settings.trim, generator
        )
        self.data = data
        self.grid = grid
        self.entries = entries
        self.gridValues = gridValues
        self.stats = stats
        self.ranking = ranking
        self.outlierMethod = outlierMethod
        self.standardized = standardized
        self.cooks = cooks
        self.outliers = outliers
        self.influential = Array(influential)
        self.bands = bands
        bandSummaries = summaries
    }
}

func real(_ value: Double?, places: Int = 4) -> String {
    guard let value else { return "NA" }
    let text = String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), places, value)
    let zero = "0." + String(repeating: "0", count: places)
    return text == "-" + zero ? zero : text
}

func positionText(_ value: Int) -> String {
    let magnitude = abs(value)
    return (value < 0 ? "-" : "") + String(magnitude / 100) + "." + String(format: "%02d", magnitude % 100)
}

func realList(_ values: [Double]) -> String { values.map { real($0) }.joined(separator: " ") }

func joinBlocks(_ blocks: [[String]]) -> [String] {
    var lines: [String] = []
    for (i, block) in blocks.enumerated() {
        if i > 0 { lines.append("") }
        lines += block
    }
    return lines
}

func methodDiagnosticLines(_ entry: ModelEntry, _ stats: Diagnostics, _ points: [Sample]) -> [String] {
    var first = "method \(entry.name) parameter \(entry.parameter) loo \(real(entry.loo))"
    if entry.name == "spline" { first += " gcv \(real(entry.gcv))" }
    let runs = stats.runs
    let largest = stats.largest
    var lines = [
        first,
        "  rss \(real(stats.rss)) edf \(real(stats.edf)) df \(real(stats.df)) rse \(real(stats.rse)) "
            + "r2 \(real(stats.r2)) f_nonlinear \(real(stats.nonlinear))",
        "  acf \(realList(stats.acf)) dw \(real(stats.dw))",
        "  runs \(runs.count) positive \(runs.positive) negative \(runs.negative) z \(real(runs.z))",
        "  max_residual \(real(stats.residuals[largest])) at \(positionText(points[largest].position)) turning \(stats.turning)",
        "  quantiles \(realList(stats.quantiles))"
    ]
    if let loess = entry.model as? LoessFit {
        for record in loess.records {
            lines.append("  robust \(record.iteration) scale \(real(record.scale)) zero_weight \(record.zeroWeights) max_change \(real(record.change))")
        }
        let zeros = points.indices.filter { loess.rho[$0] == 0 }.map { positionText(points[$0].position) }
        lines.append("  zero_weight_points " + (zeros.isEmpty ? "none" : zeros.joined(separator: " ")))
    }
    return lines
}

func comparisonDiagnosticLines(_ analysis: SeriesAnalysis) -> [String] {
    let entries = analysis.entries
    let best = analysis.ranking[0]
    var lines = ["ranking"]
    for (rank, i) in analysis.ranking.enumerated() {
        lines.append("  \(rank + 1) \(entries[i].name) \(real(entries[i].loo)) kfold \(real(entries[i].kfold))")
    }
    lines.append("agreement with " + entries[best].name)
    for i in entries.indices where i != best {
        var pairs: [(index: Int, value: Double)] = []
        for k in analysis.grid.indices {
            if let own = analysis.gridValues[i][k], let target = analysis.gridValues[best][k] {
                pairs.append((k, abs(own - target)))
            }
        }
        let maximum = pairs[firstMaximum(pairs.map { $0.value })]
        let rms = sqrt(orderedSum(pairs.map { $0.value * $0.value }) / Double(pairs.count))
        lines.append(
            "  \(entries[i].name) points \(pairs.count) rms \(real(rms)) max \(real(maximum.value)) "
                + "at \(positionText(analysis.grid[maximum.index]))"
        )
    }
    let spline = entries.firstIndex { $0.name == "spline" }!
    let fitted = analysis.gridValues[spline].map { $0! }
    let slopes = (1..<(analysis.grid.count - 1)).map { k in
        (fitted[k + 1] - fitted[k - 1]) / (Double(analysis.grid[k + 1] - analysis.grid[k - 1]) / 100)
    }
    let maximum = firstMaximum(slopes)
    let minimum = firstMaximum(slopes.map { -$0 })
    lines.append(
        "slope spline max \(real(slopes[maximum])) at \(positionText(analysis.grid[maximum + 1])) "
            + "min \(real(slopes[minimum])) at \(positionText(analysis.grid[minimum + 1]))"
    )
    return lines
}

func outlierDiagnosticLines(_ analysis: SeriesAnalysis, _ settings: Settings) -> [String] {
    let i = analysis.outlierMethod
    let entry = analysis.entries[i]
    let points = analysis.data.points
    var lines = ["outliers method \(entry.name) threshold \(positionText(settings.outlierThreshold))"]
    for j in analysis.outliers {
        lines.append(
            "  x \(positionText(points[j].position)) y \(positionText(points[j].ordinate)) "
                + "fit \(real(entry.model.fitted![j])) residual \(real(analysis.stats[i].residuals[j])) "
                + "standardized \(real(analysis.standardized[j]))"
        )
    }
    if analysis.outliers.isEmpty { lines.append("  none") }
    lines.append("influence method " + entry.name)
    for j in analysis.influential {
        lines.append("  x \(positionText(points[j].position)) lev \(real(entry.model.leverage![j])) cook \(real(analysis.cooks[j]))")
    }
    lines.append("bands")
    for method in settings.bandMethods {
        let summary = analysis.bandSummaries[method]!
        lines.append("  \(method) mean_se \(real(summary.meanSE)) coverage \(summary.covered) of \(points.count)")
    }
    return lines
}

func diagnosticsBlock(_ analysis: SeriesAnalysis, _ settings: Settings) -> [String] {
    let points = analysis.data.points
    let low = points.map { $0.ordinate }.min()!
    let high = points.map { $0.ordinate }.max()!
    var lines = [
        "series \(analysis.data.name) n \(points.count) x \(positionText(points[0].position)) "
            + "\(positionText(points.last!.position)) y \(positionText(low)) \(positionText(high))"
    ]
    for i in analysis.entries.indices { lines += methodDiagnosticLines(analysis.entries[i], analysis.stats[i], points) }
    lines += comparisonDiagnosticLines(analysis)
    lines += outlierDiagnosticLines(analysis, settings)
    return lines
}

func isotonicBlock(_ analysis: SeriesAnalysis) -> [String] {
    let i = analysis.entries.firstIndex { $0.name == "isotonic" }!
    let entry = analysis.entries[i]
    let model = entry.model as! IsotonicFit
    var first = "series \(analysis.data.name) direction \(model.direction) mode \(model.mode)"
    if model.mode == "auto" { first += " rss_increasing \(real(model.increasingRSS)) rss_decreasing \(real(model.decreasingRSS))" }
    var lines = [first, "blocks \(model.blocks.count) rss \(real(analysis.stats[i].rss)) loo \(real(entry.loo))"]
    for (j, block) in model.blocks.enumerated() {
        lines.append(
            "block \(j + 1) x \(positionText(model.positions[block.start])) \(positionText(model.positions[block.end])) "
                + "count \(block.count) value \(real(block.value))"
        )
    }
    return lines
}

func framed(_ cells: [[Character]]) -> [String] {
    let border = "+" + String(repeating: "-", count: cells[0].count) + "+"
    return [border] + cells.map { "|" + String($0) + "|" } + [border]
}

func histogramLines(_ standardized: [Double?]) -> [String] {
    var counts = [Int](repeating: 0, count: 14)
    for value in standardized.compactMap({ $0 }) {
        let index = value < -3 ? 0 : value >= 3 ? 13 : 1 + Int(floor((value + 3) / 0.5))
        counts[index] += 1
    }
    return counts.enumerated().map { i, count in
        let lower = i == 0 ? "-inf" : real(-3 + 0.5 * Double(i - 1), places: 2)
        let upper = i == 13 ? "inf" : real(-3 + 0.5 * Double(i), places: 2)
        return "\(lower) \(upper) \(count) |" + String(repeating: "#", count: count)
    }
}

func plotBlock(_ analysis: SeriesAnalysis, _ settings: Settings) -> [String] {
    let points = analysis.data.points
    let name = analysis.data.name
    let width = settings.width
    let height = settings.height
    let xa = points[0].position
    let xb = points.last!.position
    let ya = points.map { $0.ordinate }.min()!
    let yb = points.map { $0.ordinate }.max()!
    let columns = points.map { min(width - 1, width * ($0.position - xa) / (xb - xa)) }
    var cells = [[Character]](repeating: [Character](repeating: " ", count: width), count: height)
    for i in points.indices {
        let row = min(height - 1, height * (yb - points[i].ordinate) / (yb - ya))
        cells[row][columns[i]] = "."
    }
    for (i, method) in settings.plotMethods.enumerated() {
        let model = analysis.entries.first { $0.name == method }!.model
        let digit = Character(String(i + 1))
        for column in 0..<width {
            let position = xa + (2 * column + 1) * (xb - xa) / (2 * width)
            guard let value = model.estimate(position) else { continue }
            let pi = Double(height) * (Double(yb) / 100 - value) / (Double(yb) / 100 - Double(ya) / 100)
            let row = max(0, min(height - 1, Int(floor(pi))))
            let previous = cells[row][column]
            cells[row][column] = previous == " " || previous == "." || previous == digit ? digit : "*"
        }
    }
    let characters = cells.flatMap { $0 }
    let legend = settings.plotMethods.enumerated().map { "\($0.offset + 1) \($0.element)" }.joined(separator: " ")
    var lines = [
        "plot \(name) size \(width)x\(height) x \(positionText(xa)) \(positionText(xb)) y \(positionText(ya)) \(positionText(yb))",
        "legend . data " + legend
    ] + framed(cells)
    lines.append(
        "cells data \(characters.filter { $0 == "." }.count) curve \(characters.filter { $0.isNumber }.count) "
            + "overlap \(characters.filter { $0 == "*" }.count)"
    )
    let best = analysis.ranking[0]
    let residuals = analysis.stats[best].residuals
    let limit = residuals.map { abs($0) }.max()!
    cells = [[Character]](repeating: [Character](repeating: " ", count: width), count: height)
    cells[height / 2] = [Character](repeating: "-", count: width)
    for i in points.indices {
        let row = max(0, min(height - 1, Int(floor(Double(height) * ((limit - residuals[i]) / (2 * limit))))))
        cells[row][columns[i]] = "o"
    }
    lines += ["", "residuals \(name) method \(analysis.entries[best].name) limit \(real(limit))"] + framed(cells)
    lines += ["", "histogram \(name) method \(analysis.entries[analysis.outlierMethod].name)"] + histogramLines(analysis.standardized)
    return lines
}

func writeLines(_ name: String, _ lines: [String]) throws {
    try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    try (lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: true, encoding: .ascii)
}

let (series, tests, settings) = try readDataset()
let methods = methodsInOrder(settings)
let generator = Minstd(settings.seed)
let analyses = series.enumerated().map {
    SeriesAnalysis($0.element, settings, methods, settings.isotonic[$0.offset], generator)
}
var selections = ["series,method,parameter,score,edf,selected"]
var fits = ["series,x," + methods.joined(separator: ",")]
var predictions = fits
var bands = ["series,method,x,fit,se,lower,upper"]
for analysis in analyses {
    let name = analysis.data.name
    for entry in analysis.entries {
        for (i, candidate) in entry.candidates.enumerated() {
            selections.append([
                name, entry.name, candidate.parameter, real(candidate.score), real(candidate.edf),
                entry.selected == i ? "1" : "0"
            ].joined(separator: ","))
        }
    }
    for (k, position) in analysis.grid.enumerated() {
        let values = methods.indices.map { real(analysis.gridValues[$0][k]) }
        fits.append(([name, positionText(position)] + values).joined(separator: ","))
    }
    for method in settings.bandMethods + ["spline_bootstrap"] {
        for (position, row) in zip(analysis.grid, analysis.bands[method]!) {
            bands.append(([name, method, positionText(position)] + row.values.map { real($0) }).joined(separator: ","))
        }
    }
}
for test in tests {
    let analysis = analyses.first { $0.data.name == test.series }!
    let values = analysis.entries.map { real($0.model.estimate(test.position)) }
    predictions.append(([test.series, positionText(test.position)] + values).joined(separator: ","))
}
let plots = settings.plotSeries.map { name in plotBlock(analyses.first { $0.data.name == name }!, settings) }
for (name, lines) in [
    ("selection.csv", selections), ("fits.csv", fits), ("predictions.csv", predictions), ("bands.csv", bands),
    ("diagnostics.txt", joinBlocks(analyses.map { diagnosticsBlock($0, settings) })),
    ("isotonic.txt", joinBlocks(analyses.map(isotonicBlock))), ("plots.txt", joinBlocks(plots))
] {
    try writeLines(name, lines)
}
