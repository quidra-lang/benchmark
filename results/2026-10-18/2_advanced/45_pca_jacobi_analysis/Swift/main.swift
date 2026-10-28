import Foundation

let criteria = ["kaiser", "broken_stick", "parallel", "cumulative"]
let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")

func realText(_ value: Double, digits: Int = 4) -> String {
    let text = String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), digits, value)
    return Double(text) == 0 && text.hasPrefix("-") ? String(text.dropFirst()) : text
}

func reals<S: Sequence>(_ values: S) -> [String] where S.Element == Double { values.map { realText($0) } }
func componentNames(_ prefix: String, _ count: Int) -> [String] { (1...count).map { prefix + String($0) } }
func joinSections(_ sections: [[String]]) -> [String] { sections.enumerated().flatMap { $0.offset == 0 ? $0.element : [""] + $0.element } }
func hasMissing(_ row: [Double?]) -> Bool { row.contains { $0 == nil } }
func topIndices(_ values: [Double], _ count: Int) -> [Int] { Array(values.indices.sorted { values[$0] == values[$1] ? $0 < $1 : values[$0] > values[$1] }.prefix(count)) }

func largestIndex(_ values: [Double]) -> Int {
    var index = 0
    for i in values.indices.dropFirst() where values[i] > values[index] { index = i }
    return index
}

func smallestIndex(_ values: [Double]) -> Int {
    var index = 0
    for i in values.indices.dropFirst() where values[i] < values[index] { index = i }
    return index
}

func congruence(_ first: [Double], _ second: [Double]) -> Double { dot(first, second) / sqrt(dot(first, first) * dot(second, second)) }
func explainedRatios(_ values: [Double]) -> [Double] { let total = sequentialSum(values); return values.map { $0 / total } }

func cumulativeRatios(_ ratios: [Double]) -> [Double] {
    var running = 0.0
    return ratios.map { running = running + $0; return running }
}

func firstCrossing(_ ratios: [Double], _ thresholds: [Double]) -> Int { ratios.indices.first { ratios[$0] <= thresholds[$0] } ?? ratios.count }
func flagText(_ t2: Double, _ spe: Double, _ settings: Settings) -> String {
    let text = (t2 > settings.t2Limit ? "T" : "") + (spe > settings.speLimit ? "Q" : "")
    return text.isEmpty ? "-" : text
}

func drawAxes(_ grid: inout Grid, _ center: Cell) {
    grid[center.row] = Array(repeating: "-", count: grid[0].count)
    for r in grid.indices { grid[r][center.column] = "|" }
    grid[center.row][center.column] = "+"
}

func drawPoints(_ grid: inout Grid, _ cells: [Cell]) {
    var counts = Array(repeating: Array(repeating: 0, count: grid[0].count), count: grid.count)
    for cell in cells { counts[cell.row][cell.column] += 1 }
    for r in grid.indices {
        for c in grid[r].indices where counts[r][c] > 0 { grid[r][c] = counts[r][c] == 1 ? "." : counts[r][c] <= 3 ? "o" : "@" }
    }
}

func markCells<S: Sequence>(_ grid: inout Grid, _ cells: S, _ character: Character) where S.Element == Cell {
    for cell in cells { grid[cell.row][cell.column] = character }
}

func insideCircle(_ row: Int, _ column: Int, _ center: Cell, _ radius: Int) -> Bool {
    let horizontal = column - center.column, vertical = 2 * (row - center.row)
    return horizontal * horizontal + vertical * vertical <= radius * radius
}

struct Minstd {
    var state: Int64
    mutating func uniform() -> Double { state = 48271 * state % 2147483647; return Double(state) / 2147483647 }
}

struct VariableSummary {
    let observed: Int
    let missing: Int
    let mean: Double
    let sd: Double
    let minimum: Double
    let maximum: Double

    init(_ values: [Double], _ total: Int) {
        let mean = sequentialSum(values) / Double(values.count)
        observed = values.count
        missing = total - values.count
        self.mean = mean
        sd = sqrt(sequentialSum(values.map { ($0 - mean) * ($0 - mean) }) / Double(values.count - 1))
        minimum = values.min()!
        maximum = values.max()!
    }
}

struct AnalysisData {
    let ids: [String]
    let values: Matrix

    init(_ table: Table, _ strategy: String, _ means: [Double]) {
        let indices = table.rows.indices.filter { strategy != "listwise" || !hasMissing(table.rows[$0]) }
        ids = indices.map { table.ids[$0] }
        values = indices.map { i in means.indices.map { table.rows[i][$0] ?? means[$0] } }
    }
}

struct Decomposition {
    let data: AnalysisData
    let means: [Double]
    let covariance: Matrix
    let deviations: [Double]
    let correlation: Matrix
    let matrix: Matrix
    let scales: [Double]
    let eigen: EigenSystem

    init(_ data: AnalysisData, _ scaling: String) {
        let means = columnMeans(data.values)
        let covariance = covarianceMatrix(data.values, means)
        let deviations = standardDeviations(covariance)
        let correlation = correlationMatrix(covariance, deviations)
        let matrix = scaling == "covariance" ? covariance : correlation
        self.data = data
        self.means = means
        self.covariance = covariance
        self.deviations = deviations
        self.correlation = correlation
        self.matrix = matrix
        scales = scaling == "covariance" ? Array(repeating: 1, count: means.count) : deviations
        eigen = jacobi(matrix)
    }
}

struct Adequacy {
    let determinant: Double
    let msa: [Double]
    let kmo: Double
    let bartlett: Double
    let freedom: Int

    init(_ correlation: Matrix, _ rows: Int) {
        let size = correlation.count
        let result = gaussJordan(correlation), inverse = result.inverse
        let partial = (0..<size).map { j in (0..<size).map { k in j == k ? 0 : -inverse[j][k] / sqrt(inverse[j][j] * inverse[k][k]) } }
        let rr = (0..<size).map { j in sequentialSum((0..<size).filter { $0 != j }.map { correlation[j][$0] * correlation[j][$0] }) }
        let pp = (0..<size).map { j in sequentialSum((0..<size).filter { $0 != j }.map { partial[j][$0] * partial[j][$0] }) }
        determinant = result.determinant
        msa = (0..<size).map { rr[$0] / (rr[$0] + pp[$0]) }
        let totalRR = sequentialSum(rr), totalPP = sequentialSum(pp)
        kmo = totalRR / (totalRR + totalPP)
        bartlett = -(Double(rows - 1) - Double(2 * size + 5) / 6) * log(result.determinant)
        freedom = size * (size - 1) / 2
    }
}

func parallelAnalysis(_ rows: Int, _ size: Int, _ iterations: Int, _ seed: Int64) -> [Double] {
    var generator = Minstd(state: seed)
    var totals = Array(repeating: 0.0, count: size)
    for _ in 0..<iterations {
        let values = (0..<rows).map { _ in (0..<size).map { _ in generator.uniform() } }
        let covariance = covarianceMatrix(values, columnMeans(values))
        let correlation = correlationMatrix(covariance, standardDeviations(covariance))
        let ratios = explainedRatios(jacobi(correlation).values)
        for k in 0..<size { totals[k] = totals[k] + ratios[k] }
    }
    return totals.map { $0 / Double(iterations) }
}

struct VarianceTable {
    let total: Double
    let average: Double
    let ratios: [Double]
    let cumulative: [Double]
    let brokenStick: [Double]
    let parallel: [Double]
    let errors: [Double]
    let separated: [Bool]
    let retention: [String: Int]

    init(_ values: [Double], _ rows: Int, _ parallel: [Double], _ target: Double) {
        let size = values.count
        let total = sequentialSum(values), average = total / Double(size)
        let ratios = explainedRatios(values), cumulative = cumulativeRatios(ratios)
        let broken = (1...size).map { k in sequentialSum((k...size).map { 1 / Double($0) }) / Double(size) }
        let errors = values.map { $0 * sqrt(2 / Double(rows)) }
        self.total = total
        self.average = average
        self.ratios = ratios
        self.cumulative = cumulative
        brokenStick = broken
        self.parallel = parallel
        self.errors = errors
        separated = values.indices.map { k in [k - 1, k + 1].filter { $0 >= 0 && $0 < size }.allSatisfy { abs(values[k] - values[$0]) > errors[k] } }
        retention = ["kaiser": values.filter { $0 > average }.count, "broken_stick": firstCrossing(ratios, broken),
                     "parallel": firstCrossing(ratios, parallel), "cumulative": (cumulative.firstIndex { $0 >= target } ?? (size - 1)) + 1]
    }
}

func varimaxCriterion(_ matrix: Matrix) -> Double {
    let count = Double(matrix.count)
    var total = 0.0
    for k in matrix[0].indices {
        let q4 = sequentialSum(matrix.map { ($0[k] * $0[k]) * ($0[k] * $0[k]) })
        let q2 = sequentialSum(matrix.map { $0[k] * $0[k] })
        total = total + (q4 / count - (q2 / count) * (q2 / count))
    }
    return total
}

func rotatePair(_ matrix: inout Matrix, _ a: Int, _ b: Int) {
    let count = Double(matrix.count)
    let phi = matrix.map { $0[a] * $0[a] - $0[b] * $0[b] }, psi = matrix.map { 2 * $0[a] * $0[b] }
    let sa = sequentialSum(phi), sb = sequentialSum(psi)
    let sc = sequentialSum(zip(phi, psi).map { $0 * $0 - $1 * $1 })
    let sd = sequentialSum(zip(phi, psi).map { 2 * $0 * $1 })
    let numerator = sd - 2 * sa * sb / count, denominator = sc - (sa * sa - sb * sb) / count
    let omega = sqrt(numerator * numerator + denominator * denominator)
    if omega == 0 { return }
    let cos4 = denominator / omega, sin4 = numerator / omega
    let cos2 = sqrt((1 + cos4) / 2), sin2 = cos2 == 0 ? 1 : sin4 / (2 * cos2)
    let cos1 = sqrt((1 + cos2) / 2), sin1 = sin2 / (2 * cos1)
    for j in matrix.indices {
        let first = matrix[j][a], second = matrix[j][b]
        matrix[j][a] = cos1 * first + sin1 * second
        matrix[j][b] = -sin1 * first + cos1 * second
    }
}

struct Varimax {
    let criteria: [Double]
    let columns: Matrix
    let squares: [Double]
    let closest: [Int]
    let congruences: [Double]

    init(_ loadings: Matrix, _ components: Int, _ cycles: Int) {
        let etas = loadings.map { row in sqrt(sequentialSum((0..<components).map { row[$0] * row[$0] })) }
        var g = loadings.indices.map { j in (0..<components).map { loadings[j][$0] / etas[j] } }
        var criteria = [varimaxCriterion(g)]
        for _ in 0..<cycles {
            for a in 0..<(components - 1) {
                for b in (a + 1)..<components { rotatePair(&g, a, b) }
            }
            criteria.append(varimaxCriterion(g))
        }
        let rawColumns = (0..<components).map { k in orient(loadings.indices.map { g[$0][k] * etas[$0] }) }
        let rawSquares = rawColumns.map { dot($0, $0) }
        let order = rawColumns.indices.sorted { rawSquares[$0] == rawSquares[$1] ? $0 < $1 : rawSquares[$0] > rawSquares[$1] }
        let columns = order.map { rawColumns[$0] }
        let agreements = columns.map { rotated in (0..<components).map { abs(congruence(rotated, column(loadings, $0))) } }
        let closest = agreements.map(largestIndex)
        self.criteria = criteria
        self.columns = columns
        squares = order.map { rawSquares[$0] }
        self.closest = closest
        congruences = agreements.indices.map { agreements[$0][closest[$0]] }
    }
}

struct Observation {
    let id: String
    let z: [Double]
    let scores: [Double]
    let t2: Double
    let residual: [Double]
    let spe: Double
    let flag: String

    init(_ id: String, _ values: [Double?], _ fit: Decomposition, _ count: Int, _ settings: Settings) {
        let z = standardize(values, fit.means, fit.scales)
        let scores = componentScores(z, fit.eigen.vectors)
        let t2 = hotellingT2(scores, fit.eigen.values, count)
        let residual = residuals(z, scores, fit.eigen.vectors, count)
        let spe = dot(residual, residual)
        self.id = id
        self.z = z
        self.scores = scores
        self.t2 = t2
        self.residual = residual
        self.spe = spe
        flag = flagText(t2, spe, settings)
    }
}

struct Sensitivity {
    let strategy: String
    let scaling: String
    let rows: Int
    let sweeps: Int
    let eigenvalues: [Double]
    let cumulative: Double
    let agreement: [Double]

    init(_ strategy: String, _ scaling: String, _ fit: Decomposition, _ reference: Matrix, _ count: Int) {
        self.strategy = strategy
        self.scaling = scaling
        rows = fit.data.ids.count
        sweeps = fit.eigen.sweeps
        eigenvalues = Array(fit.eigen.values.prefix(count))
        cumulative = cumulativeRatios(explainedRatios(fit.eigen.values))[count - 1]
        agreement = (0..<count).map { abs(dot(fit.eigen.vectors[$0], reference[$0])) }
    }
}

struct PCAReport {
    let settings: Settings
    let data: Table
    let supplementary: Table
    let summaries: [VariableSummary]
    let incomplete: [String]
    let fit: Decomposition
    let strongest: [(Int, Int)]
    let adequacy: Adequacy
    let power: [PowerComponent]
    let variance: VarianceTable
    let components: Int
    let loadings: Matrix
    let communalities: [Double]
    let circle: Matrix
    let varimax: Varimax
    let observations: [Observation]
    let projections: [Observation]
    let sensitivity: [Sensitivity]
    var names: [String] { data.names }
    var size: Int { names.count }
    var ids: [String] { fit.data.ids }
    var rows: Int { ids.count }
    var eigenvalues: [Double] { fit.eigen.values }
    var vectors: Matrix { fit.eigen.vectors }

    init(_ data: Table, _ supplementary: Table, _ settings: Settings) {
        let size = data.names.count
        let summaries = (0..<size).map { j in VariableSummary(data.rows.compactMap { $0[j] }, data.rows.count) }
        let means = summaries.map { $0.mean }
        let mainData = AnalysisData(data, settings.missing, means)
        let fit = Decomposition(mainData, settings.scaling)
        let rows = mainData.ids.count
        let pairs = (0..<size).flatMap { j in ((j + 1)..<size).map { (j, $0) } }
        let strengths = pairs.map { abs(fit.correlation[$0.0][$0.1]) }
        let parallel = parallelAnalysis(rows, size, settings.parallelIterations, settings.seed)
        let variance = VarianceTable(fit.eigen.values, rows, parallel, settings.cumulativeTarget)
        let count = Int(settings.components) ?? max(variance.retention[settings.components]!, 1)
        let loadings = (0..<size).map { j in (0..<size).map { fit.eigen.vectors[$0][j] * sqrt(fit.eigen.values[$0]) } }
        self.data = data
        self.supplementary = supplementary
        self.settings = settings
        self.summaries = summaries
        incomplete = data.rows.indices.filter { hasMissing(data.rows[$0]) }.map { data.ids[$0] }
        self.fit = fit
        strongest = topIndices(strengths, settings.topRows).map { pairs[$0] }
        adequacy = Adequacy(fit.correlation, rows)
        power = powerIteration(fit.matrix, fit.eigen.vectors)
        self.variance = variance
        components = count
        self.loadings = loadings
        communalities = (0..<size).map { j in sequentialSum((0..<count).map { loadings[j][$0] * loadings[j][$0] }) / fit.matrix[j][j] }
        circle = (0..<size).map { j in (0..<2).map { loadings[j][$0] / sqrt(fit.matrix[j][j]) } }
        varimax = Varimax(loadings, count, settings.varimaxCycles)
        observations = mainData.values.indices.map { Observation(mainData.ids[$0], mainData.values[$0].map { Optional($0) }, fit, count, settings) }
        projections = supplementary.rows.indices.map { Observation(supplementary.ids[$0], supplementary.rows[$0], fit, count, settings) }
        sensitivity = ["listwise", "mean"].flatMap { strategy in ["covariance", "correlation"].map { scaling in
            Sensitivity(strategy, scaling, Decomposition(AnalysisData(data, strategy, means), scaling), fit.eigen.vectors, count)
        } }
    }

    func quality(_ observation: Observation) -> Double {
        let retained = Array(observation.scores.prefix(components))
        return dot(retained, retained) / dot(observation.z, observation.z)
    }

    func t2Contributions(_ observation: Observation) -> [Double] {
        (0..<size).map { j in observation.z[j] * sequentialSum((0..<components).map { observation.scores[$0] / eigenvalues[$0] * vectors[$0][j] }) }
    }

    func nearestRow(_ projection: Observation) -> (index: Int, distance: Double) {
        let distances = observations.map { point in
            let differences = (0..<components).map { projection.scores[$0] - point.scores[$0] }
            return dot(differences, differences)
        }
        let nearest = smallestIndex(distances)
        return (nearest, sqrt(distances[nearest]))
    }

    func eigenFile() -> [String] {
        let incompleteText = incomplete.isEmpty ? "0 -" : ([String(incomplete.count)] + incomplete).joined(separator: " ")
        let summary = ["pca rows \(data.ids.count) used \(rows) variables \(size) missing \(settings.missing) scaling \(settings.scaling)", "incomplete \(incompleteText)"]
        var variables = ["variable observed missing mean sd min max msa"]
        for j in 0..<size {
            let summary = summaries[j]
            variables.append(([names[j], String(summary.observed), String(summary.missing)] + reals([summary.mean, summary.sd, summary.minimum, summary.maximum, adequacy.msa[j]])).joined(separator: " "))
        }
        variables.append("adequacy kmo \(realText(adequacy.kmo)) determinant \(realText(adequacy.determinant, digits: 6)) bartlett \(realText(adequacy.bartlett)) df \(adequacy.freedom)")
        var matrixLines = ["matrix \(settings.scaling)"]
        for j in 0..<size { matrixLines.append(([names[j]] + reals(fit.matrix[j])).joined(separator: " ")) }
        matrixLines.append((["strongest"] + strongest.map { "\(names[$0.0]):\(names[$0.1]):\(realText(fit.correlation[$0.0][$0.1]))" }).joined(separator: " "))
        var eigenLines = ["jacobi sweeps \(fit.eigen.sweeps)", "eigenvalues total \(realText(variance.total)) average \(realText(variance.average))", "k eigenvalue ratio cumulative broken_stick parallel se separated"]
        for k in 0..<size {
            let values = reals([eigenvalues[k], variance.ratios[k], variance.cumulative[k], variance.brokenStick[k], variance.parallel[k], variance.errors[k]])
            eigenLines.append(([String(k + 1)] + values + [variance.separated[k] ? "yes" : "no"]).joined(separator: " "))
        }
        let retention = criteria.map { "\($0) \(variance.retention[$0]!)" }.joined(separator: " ")
        eigenLines += ["retention \(retention) target \(realText(settings.cumulativeTarget))", "components \(components) rule \(settings.components)"]
        var eigenvectorLines = ["eigenvectors", (["variable"] + componentNames("pc", size)).joined(separator: " ")]
        for j in 0..<size { eigenvectorLines.append(([names[j]] + reals(vectors.map { $0[j] })).joined(separator: " ")) }
        var powerLines = ["power_iteration iterations 1000", "k jacobi power agree_at match"]
        var matches = 0
        for k in 0..<size {
            let component = power[k]
            let match = abs(component.value - eigenvalues[k]) <= 1e-8 * eigenvalues[0] && maxDifference(component.vector, vectors[k]) <= 0.000001
            if match { matches += 1 }
            let agreement = component.agreement.map(String.init) ?? "-"
            powerLines.append("\(k + 1) \(realText(eigenvalues[k])) \(realText(component.value)) \(agreement) \(match ? "yes" : "no")")
        }
        powerLines.append("cross_check \(matches)/\(size)")
        var scoreLines = ["scores", "component sd min min_id max max_id contributors"]
        let denominator = Double(rows - 1)
        for k in 0..<components {
            let scores = observations.map { $0.scores[k] }
            let sd = sqrt(sequentialSum(scores.map { $0 * $0 }) / denominator)
            let low = smallestIndex(scores), high = largestIndex(scores)
            let contributions = scores.map { $0 * $0 / (denominator * eigenvalues[k]) }
            let parts = ["pc\(k + 1)", realText(sd), realText(scores[low]), ids[low], realText(scores[high]), ids[high]]
            let top = topIndices(contributions, settings.topRows).map { "\(ids[$0]):\(realText(contributions[$0]))" }
            scoreLines.append((parts + top).joined(separator: " "))
        }
        var varimaxLines = ["varimax components \(components) cycles \(settings.varimaxCycles)"]
        for (cycle, value) in varimax.criteria.enumerated() { varimaxLines.append("cycle \(cycle) criterion \(realText(value, digits: 6))") }
        for k in 0..<components {
            let squares = varimax.squares[k]
            varimaxLines.append("rc\(k + 1) ss \(realText(squares)) ratio \(realText(squares / variance.total)) closest pc\(varimax.closest[k] + 1) congruence \(realText(varimax.congruences[k]))")
        }
        var sensitivityLines = ["sensitivity", "missing scaling rows sweeps eigenvalues cumulative congruence"]
        for result in sensitivity {
            let fields = [result.strategy, result.scaling, String(result.rows), String(result.sweeps)] + reals(result.eigenvalues) + [realText(result.cumulative)] + reals(result.agreement)
            sensitivityLines.append(fields.joined(separator: " "))
        }
        return joinSections([summary, variables, matrixLines, eigenLines, eigenvectorLines, powerLines, scoreLines, varimaxLines, sensitivityLines])
    }

    func loadingsFile() -> [String] {
        var lines = [(["variable"] + componentNames("pc", components) + ["communality"] + componentNames("rc", components)).joined(separator: ",")]
        for j in 0..<size {
            let values = Array(loadings[j].prefix(components)) + [communalities[j]] + varimax.columns.map { $0[j] }
            lines.append(([names[j]] + reals(values)).joined(separator: ","))
        }
        return lines
    }

    func scoresFile() -> [String] {
        var lines = [(["id", "set"] + componentNames("pc", components)).joined(separator: ",")]
        for observation in observations { lines.append(([observation.id, "data"] + reals(observation.scores.prefix(components))).joined(separator: ",")) }
        for projection in projections { lines.append(([projection.id, "supplementary"] + reals(projection.scores.prefix(components))).joined(separator: ",")) }
        return lines
    }

    func topSection(_ label: String, _ values: [Double], _ contributions: Matrix) -> [String] {
        var lines = ["top \(label)", "rank id \(label) variable contribution"]
        for (rank, i) in topIndices(values, settings.topRows).enumerated() {
            let variable = largestIndex(contributions[i])
            lines.append("\(rank + 1) \(ids[i]) \(realText(values[i])) \(names[variable]) \(realText(contributions[i][variable]))")
        }
        return lines
    }

    func outliersFile() -> [String] {
        var diagnostic = ["diagnostics components \(components) t2_limit \(realText(settings.t2Limit)) spe_limit \(realText(settings.speLimit))", "id t2 spe quality flag"]
        for observation in observations {
            diagnostic.append(([observation.id] + reals([observation.t2, observation.spe, quality(observation)]) + [observation.flag]).joined(separator: " "))
        }
        let flags = observations.map { $0.flag }
        diagnostic.append("flagged t2 \(flags.filter { $0.contains("T") }.count) spe \(flags.filter { $0.contains("Q") }.count) both \(flags.filter { $0 == "TQ" }.count) any \(flags.filter { $0 != "-" }.count)")
        let topT2 = topSection("t2", observations.map { $0.t2 }, observations.map { t2Contributions($0) })
        let topSPE = topSection("spe", observations.map { $0.spe }, observations.map { $0.residual.map { $0 * $0 } })
        var reconstruction = ["reconstruction", "k mean_spe max_spe max_id"]
        for count in 1..<size {
            let errors = observations.map { point in
                let residual = residuals(point.z, point.scores, vectors, count)
                return dot(residual, residual)
            }
            let worst = largestIndex(errors)
            reconstruction.append("\(count) \(realText(sequentialSum(errors) / Double(rows))) \(realText(errors[worst])) \(ids[worst])")
        }
        let header = ["id"] + componentNames("pc", components) + ["t2", "spe", "flag", "nearest", "distance"]
        var supplementaryLines = ["supplementary", header.joined(separator: " ")]
        for projection in projections {
            let nearest = nearestRow(projection)
            let values = reals(Array(projection.scores.prefix(components)) + [projection.t2, projection.spe])
            supplementaryLines.append(([projection.id] + values + [projection.flag, ids[nearest.index], realText(nearest.distance)]).joined(separator: " "))
        }
        return joinSections([diagnostic, topT2, topSPE, reconstruction, supplementaryLines])
    }

    func screeSection() -> [String] {
        let width = settings.screeWidth, first = eigenvalues[0]
        let kaiser = roundedPosition(variance.average / first, Double(width))
        var lines = ["scree width \(width) kaiser_column \(kaiser)"]
        for (k, value) in eigenvalues.enumerated() {
            let length = roundedPosition(value / first, Double(width))
            let broken = roundedPosition(variance.brokenStick[k] * variance.total / first, Double(width))
            lines.append("\(screeLine(length, kaiser, broken, width)) pc\(k + 1) \(realText(value))")
        }
        return lines
    }

    func biplotSection() -> [String] {
        let width = settings.biplotWidth, height = settings.biplotHeight
        let points = observations + projections
        let xLimit = points.map { abs($0.scores[0]) }.max()!, yLimit = points.map { abs($0.scores[1]) }.max()!
        let xLoading = loadings.map { abs($0[0]) }.max()!, yLoading = loadings.map { abs($0[1]) }.max()!
        let scale = 0.9 * min(xLimit / xLoading, yLimit / yLoading)
        let origin = biplotCell(0, 0, xLimit, yLimit, width, height)
        let tips = loadings.map { biplotCell(scale * $0[0], scale * $0[1], xLimit, yLimit, width, height) }
        let cells = points.map { biplotCell($0.scores[0], $0.scores[1], xLimit, yLimit, width, height) }
        let dataCells = Array(cells.prefix(rows))
        var grid = newGrid(height, width)
        drawAxes(&grid, origin)
        for tip in tips { markCells(&grid, shaftCells(origin, tip), shaftCharacter(origin, tip)) }
        drawPoints(&grid, dataCells)
        let flagged = observations.indices.filter { observations[$0].flag != "-" }.map { dataCells[$0] }
        markCells(&grid, flagged, "X")
        markCells(&grid, cells.dropFirst(rows), "*")
        for (j, tip) in tips.enumerated() { markCells(&grid, [tip], letters[j]) }
        var lines = ["biplot pc1 pc2 width \(width) height \(height)",
                     "x \(realText(-xLimit)) \(realText(xLimit)) y \(realText(-yLimit)) \(realText(yLimit)) arrow_scale \(realText(scale))"] + framed(grid)
        for j in 0..<size { lines.append("\(letters[j]) \(names[j]) \(realText(loadings[j][0])) \(realText(loadings[j][1]))") }
        return lines
    }

    func circleSection() -> [String] {
        let radius = settings.circleRadius
        let center: Cell = (radius / 2 + 1, radius + 1)
        var grid = newGrid(radius + 3, 2 * radius + 3)
        drawAxes(&grid, center)
        for r in grid.indices {
            for c in grid[r].indices where insideCircle(r, c, center, radius) {
                let neighbors = [(r - 1, c), (r + 1, c), (r, c - 1), (r, c + 1)]
                if !neighbors.allSatisfy({ insideCircle($0.0, $0.1, center, radius) }) { grid[r][c] = "." }
            }
        }
        for j in 0..<size { markCells(&grid, [circleCell(circle[j][0], circle[j][1], radius)], letters[j]) }
        var lines = ["circle radius \(radius)"] + framed(grid)
        for j in 0..<size {
            let first = circle[j][0], second = circle[j][1]
            lines.append(([String(letters[j]), names[j]] + reals([first, second, first * first + second * second])).joined(separator: " "))
        }
        return lines
    }

    func diagnosticSection() -> [String] {
        let width = settings.diagnosticWidth, height = settings.diagnosticHeight
        let t2Max = 2 * settings.t2Limit, speMax = 2 * settings.speLimit
        var grid = newGrid(height, width)
        let limit = diagnosticCell(settings.t2Limit, settings.speLimit, t2Max, speMax, width, height)
        drawAxes(&grid, limit)
        drawPoints(&grid, observations.map { diagnosticCell($0.t2, $0.spe, t2Max, speMax, width, height) })
        markCells(&grid, projections.map { diagnosticCell($0.t2, $0.spe, t2Max, speMax, width, height) }, "*")
        return ["diagnostic width \(width) height \(height) t2_max \(realText(t2Max)) spe_max \(realText(speMax))"] + framed(grid)
    }

    func plotsFile() -> [String] { joinSections([screeSection(), biplotSection(), circleSection(), diagnosticSection()]) }
}

let data = try readTable("input/data.csv")
let supplementary = try readTable("input/supplementary.csv")
let settings = try readSettings("input/params.txt")
let report = PCAReport(data, supplementary, settings)
for (name, lines) in [("eigen.txt", report.eigenFile()), ("loadings.csv", report.loadingsFile()),
                      ("scores.csv", report.scoresFile()), ("outliers.txt", report.outliersFile()), ("plots.txt", report.plotsFile())] {
    try (lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: false, encoding: .ascii)
}
