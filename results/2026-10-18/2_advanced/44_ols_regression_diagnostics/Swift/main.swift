import Foundation

func table(_ header: [String], _ rows: [[String]], marks: [String]? = nil) -> [String] {
    let allRows = [header] + rows
    let widths = header.indices.map { column in allRows.compactMap { column < $0.count ? $0[column].count : nil }.max()! }
    return allRows.enumerated().map { index, row in
        var line = row[0] + String(repeating: " ", count: widths[0] - row[0].count)
        for column in 1..<row.count {
            line += "  " + String(repeating: " ", count: widths[column] - row[column].count) + row[column]
        }
        if index > 0, let marks, !marks[index - 1].isEmpty { line += " " + marks[index - 1] }
        while line.last == " " { line.removeLast() }
        return line
    }
}

func dataSummary(_ data: DataFrame) -> [String] {
    let numeric = data.columns.filter { data.kinds[$0] == .numeric }
    var lines = ["Data: \(data.rows.count) rows, \(data.columns.count) columns", "", "Numeric columns:"]
    let numericRows = numeric.map { column -> [String] in
        let values = data.rows.compactMap { $0[column]!.numericValue }
        let mean = orderedSum(values) / Double(values.count)
        let variance = orderedSum(values.map { ($0 - mean) * ($0 - mean) }) / Double(values.count - 1)
        return [column, String(values.count), String(data.rows.count - values.count), four(mean),
                four(sqrt(variance)), four(values.min()!), four(values.max()!)]
    }
    lines += table(["column", "n", "missing", "Mean", "SD", "Min", "Max"], numericRows)
    lines += ["", "Categorical columns:"]
    for column in data.columns where data.kinds[column] == .categorical {
        let labels = data.rows.compactMap { $0[column]!.labelValue }
        let counts = Dictionary(grouping: labels, by: { $0 }).mapValues { $0.count }
        let levels = counts.keys.sorted().map { "\($0) \(counts[$0]!)" }.joined(separator: ", ")
        lines.append("\(column): \(labels.count) values, \(data.rows.count - labels.count) missing, \(counts.count) levels: \(levels)")
    }
    lines += ["", "Correlations (pairwise complete observations):"]
    let correlations = numeric.map { a -> [String] in
        [a] + numeric.map { b in
            let pairs = data.rows.compactMap { row -> (Double, Double)? in
                guard let x = row[a]!.numericValue, let y = row[b]!.numericValue else { return nil }
                return (x, y)
            }
            let meanX = orderedSum(pairs.map { $0.0 }) / Double(pairs.count)
            let meanY = orderedSum(pairs.map { $0.1 }) / Double(pairs.count)
            let cross = orderedSum(pairs.map { ($0.0 - meanX) * ($0.1 - meanY) })
            let squareX = orderedSum(pairs.map { ($0.0 - meanX) * ($0.0 - meanX) })
            let squareY = orderedSum(pairs.map { ($0.1 - meanY) * ($0.1 - meanY) })
            return four(cross / sqrt(squareX * squareY))
        }
    }
    lines += table(["column"] + numeric, correlations)
    lines.append("")
    return lines
}

func informationCriteria(_ fit: Fit) -> (likelihood: Double, aic: Double, bic: Double) {
    let n = Double(fit.n)
    let likelihood = 0.5 * (orderedSum(fit.weights.map(log)) - n * (log(2 * 3.141592653589793) + 1 - log(n) + log(fit.rss)))
    return (likelihood, -2 * likelihood + 2 * Double(fit.rank + 1), -2 * likelihood + log(n) * Double(fit.rank + 1))
}

struct ModelStatistics {
    let df: Int
    let sigma: Double
    let weightSum: Double
    let tss: Double
    let rSquared: Double
    let adjusted: Double
    let f: Double
    let p: Double
    let likelihood: Double
    let aic: Double
    let bic: Double
    let press: Double
    let predicted: Double
    let quantiles: [Double]
    let critical: Double

    init(_ fit: Fit, _ confidence: Double) {
        let df = fit.n - fit.rank
        let sigma = sqrt(fit.rss / Double(df))
        let weightSum = orderedSum(fit.weights)
        let mean = orderedSum((0..<fit.n).map { fit.weights[$0] * fit.response[$0] }) / weightSum
        let tss = orderedSum((0..<fit.n).map { fit.weights[$0] * (fit.response[$0] - mean) * (fit.response[$0] - mean) })
        let rSquared = 1 - fit.rss / tss
        let f = ((tss - fit.rss) / Double(fit.rank - 1)) / (fit.rss / Double(df))
        let criteria = informationCriteria(fit)
        let press = orderedSum((0..<fit.n).map { i in
            let value = fit.weightedResidual[i] / (1 - fit.leverage[i])
            return value * value
        })
        let residuals = fit.weightedResidual.sorted()
        quantiles = [0.0, 0.25, 0.5, 0.75, 1.0].map { proportion in
            let position = Double(fit.n - 1) * proportion
            let index = Int(floor(position))
            return index + 1 < residuals.count ? residuals[index] + (position - Double(index)) * (residuals[index + 1] - residuals[index]) : residuals[index]
        }
        self.df = df
        self.sigma = sigma
        self.weightSum = weightSum
        self.tss = tss
        self.rSquared = rSquared
        adjusted = 1 - (1 - rSquared) * Double(fit.n - 1) / Double(df)
        self.f = f
        p = fPValue(f, fit.rank - 1, df)
        likelihood = criteria.likelihood
        aic = criteria.aic
        bic = criteria.bic
        self.press = press
        predicted = 1 - press / tss
        critical = tQuantile(confidence, df)
    }
}

struct CoefficientInference {
    let estimate: Double?
    let standardError: Double?
    let t: Double?
    let p: Double?
    let lower: Double?
    let upper: Double?
    let robustError: Double?
    let robustT: Double?
    let robustP: Double?
}

func coefficientInference(_ fit: Fit, _ stats: ModelStatistics) -> [CoefficientInference] {
    let accepted = Dictionary(uniqueKeysWithValues: fit.accepted.enumerated().map { ($0.element, $0.offset) })
    let omega = (0..<fit.n).map { i in fit.weightedResidual[i] * fit.weightedResidual[i] / ((1 - fit.leverage[i]) * (1 - fit.leverage[i])) }
    return fit.beta.enumerated().map { column, value in
        guard let value else {
            return CoefficientInference(estimate: nil, standardError: nil, t: nil, p: nil,
                                        lower: nil, upper: nil, robustError: nil, robustT: nil, robustP: nil)
        }
        let k = accepted[column]!
        let se = stats.sigma * sqrt(fit.variance[k]), t = value / se
        let halfWidth = stats.critical * se
        let robust = sqrt(orderedSum((0..<fit.n).map { omega[$0] * fit.g[$0][k] * fit.g[$0][k] }))
        let robustT = value / robust
        return CoefficientInference(estimate: value, standardError: se, t: t, p: tPValue(t, stats.df),
                                    lower: value - halfWidth, upper: value + halfWidth, robustError: robust,
                                    robustT: robustT, robustP: tPValue(robustT, stats.df))
    }
}

struct SequentialTest {
    let name: String
    let df: Int
    let squares: Double
    let meanSquare: Double
    let f: Double
    let p: Double
}

func sequentialANOVA(_ design: Design, _ fit: Fit) -> [SequentialTest] {
    var result: [SequentialTest] = []
    for (index, term) in design.model.terms.enumerated() {
        let effects = fit.accepted.indices.filter { design.columns[fit.accepted[$0]].termIndex == index }
        if effects.isEmpty { continue }
        let squares = orderedSum(effects.map { fit.effects[$0] * fit.effects[$0] })
        let meanSquare = squares / Double(effects.count)
        let f = meanSquare / (fit.rss / Double(fit.n - fit.rank))
        result.append(SequentialTest(name: term.name, df: effects.count, squares: squares,
                                     meanSquare: meanSquare, f: f, p: fPValue(f, effects.count, fit.n - fit.rank)))
    }
    return result
}

func fitSubset(_ design: Design, _ terms: [Int], _ tolerance: Double) -> Fit {
    Fit(design.subsetMatrix(terms), design.response, design.weights, tolerance)
}

struct MarginalTest {
    let index: Int
    let name: String
    let df: Int
    let squares: Double
    let rss: Double
    let f: Double?
    let p: Double?
}

func marginalTests(_ design: Design, _ fit: Fit, _ terms: [Int], _ tolerance: Double) -> [MarginalTest] {
    design.model.removable(terms).map { index in
        let reduced = fitSubset(design, terms.filter { $0 != index }, tolerance)
        let df = fit.rank - reduced.rank
        let squares = reduced.rss - fit.rss
        let f = df > 0 ? (squares / Double(df)) / (fit.rss / Double(fit.n - fit.rank)) : nil
        return MarginalTest(index: index, name: design.model.terms[index].name, df: df, squares: squares,
                            rss: reduced.rss, f: f, p: f.map { fPValue($0, df, fit.n - fit.rank) })
    }
}

func varianceInflation(_ design: Design, _ fit: Fit, _ stats: ModelStatistics, _ params: Parameters) -> [(name: String, value: Double, high: Bool)] {
    fit.accepted.dropFirst().map { column in
        let response = fit.matrix.map { $0[column] }
        let others = fit.accepted.filter { $0 != column }
        let matrix = fit.matrix.map { row in others.map { row[$0] } }
        let auxiliary = Fit(matrix, response, fit.weights, params.rankTolerance)
        let mean = orderedSum((0..<fit.n).map { fit.weights[$0] * response[$0] }) / stats.weightSum
        let tss = orderedSum((0..<fit.n).map { fit.weights[$0] * (response[$0] - mean) * (response[$0] - mean) })
        let rSquared = 1 - auxiliary.rss / tss
        let value = 1 / (1 - rSquared)
        return (design.columns[column].name, value, value > params.vif)
    }
}

func resetTest(_ fit: Fit, _ tolerance: Double) -> (f: Double, added: Int, residualDF: Int, p: Double) {
    let matrix = (0..<fit.n).map { i in fit.accepted.map { fit.matrix[i][$0] } + [fit.fitted[i] * fit.fitted[i], fit.fitted[i] * fit.fitted[i] * fit.fitted[i]] }
    let augmented = Fit(matrix, fit.response, fit.weights, tolerance)
    let q = augmented.rank - fit.rank, df = fit.n - augmented.rank
    let f = ((fit.rss - augmented.rss) / Double(q)) / (augmented.rss / Double(df))
    return (f, q, df, fPValue(f, q, df))
}

struct DiagnosticDecisions {
    let dwLabel: String
    let bpLabel: String
    let jbLabel: String
    let outlier: Int
    let unadjusted: Double
    let bonferroni: Double
    let largestCooks: [Int]
    let largestDFBetas: [(name: String, row: Int, value: Double)]
    let counts: [String: Int]

    init(_ design: Design, _ fit: Fit, _ diagnostics: Diagnostics, _ params: Parameters) {
        let rows = diagnostics.rows
        let dw = diagnostics.durbinWatson
        dwLabel = dw < params.durbinWatson ? "positive autocorrelation" : dw > 4 - params.durbinWatson ? "negative autocorrelation" : "no autocorrelation"
        bpLabel = diagnostics.breuschPagan.p < params.breuschPagan ? "heteroscedastic" : "homoscedastic"
        jbLabel = diagnostics.jarqueBera.p < params.normality ? "non-normal" : "normal"
        var outlier = 0
        for i in 1..<fit.n where abs(rows[i].studentized) > abs(rows[outlier].studentized) { outlier = i }
        self.outlier = outlier
        let unadjusted = tPValue(rows[outlier].studentized, fit.n - fit.rank - 1)
        self.unadjusted = unadjusted
        bonferroni = min(1, Double(fit.n) * unadjusted)
        largestCooks = Array((0..<fit.n).sorted { rows[$0].cooks == rows[$1].cooks ? $0 < $1 : rows[$0].cooks > rows[$1].cooks }.prefix(3))
        largestDFBetas = fit.accepted.enumerated().map { k, column in
            var index = 0
            for i in 1..<fit.n where abs(rows[i].dfbetas[k]) > abs(rows[index].dfbetas[k]) { index = i }
            return (design.columns[column].name, design.rowNumbers[index], rows[index].dfbetas[k])
        }
        var counts: [String: Int] = [:]
        for flag in ["H", "O", "C", "F"] { counts[flag] = rows.filter { $0.flags.contains(flag) }.count }
        counts["any"] = rows.filter { $0.flags != "-" }.count
        self.counts = counts
    }
}

struct PredictionCheck {
    let predicted: Int
    let actual: Int
    let rmse: Double?
    let covered: Int
}

func predictionReport(_ number: Int, _ design: Design, _ fit: Fit, _ stats: ModelStatistics, _ data: DataFrame) -> (lines: [String], check: PredictionCheck) {
    var lines: [String] = []
    var predictedCount = 0, actualCount = 0, coveredCount = 0
    var squaredErrors = 0.0
    for (index, record) in data.rows.enumerated() {
        var fields = [String(number), String(index + 1)]
        if !design.predictable(record) { lines.append((fields + Array(repeating: "NA", count: 9)).joined(separator: ",")); continue }
        predictedCount += 1
        let values = design.values(record)
        let predicted = orderedSum(fit.accepted.map { values[$0] * fit.beta[$0]! })
        let u = (0..<fit.rank).map { k in orderedSum((0..<fit.rank).map { values[fit.accepted[$0]] * fit.inverse[$0][k] }) }
        let se = stats.sigma * sqrt(orderedSum(u.map { $0 * $0 }))
        let confidenceWidth = stats.critical * se
        let predictionWidth = stats.critical * sqrt(stats.sigma * stats.sigma + se * se)
        let lower = predicted - predictionWidth, upper = predicted + predictionWidth
        fields += [predicted, se, predicted - confidenceWidth, predicted + confidenceWidth, lower, upper].map { four($0) }
        if let actual = record[design.model.response]?.numericValue {
            actualCount += 1
            let error = actual - predicted
            squaredErrors = squaredErrors + error * error
            let covered = lower <= actual && actual <= upper
            if covered { coveredCount += 1 }
            fields += [four(actual), four(error), covered ? "yes" : "no"]
        } else { fields += ["NA", "NA", "NA"] }
        lines.append(fields.joined(separator: ","))
    }
    return (lines, PredictionCheck(predicted: predictedCount, actual: actualCount,
                                   rmse: actualCount > 0 ? sqrt(squaredErrors / Double(actualCount)) : nil, covered: coveredCount))
}

struct ModelReport {
    let number: Int
    let design: Design
    let fit: Fit
    let stats: ModelStatistics
    let coefficients: [CoefficientInference]
    let anova: [SequentialTest]
    let marginal: [MarginalTest]
    let vif: [(name: String, value: Double, high: Bool)]
    let diagnostics: Diagnostics
    let decisions: DiagnosticDecisions
    let reset: (f: Double, added: Int, residualDF: Int, p: Double)
    let predictions: [String]
    let predictionCheck: PredictionCheck

    init(_ number: Int, _ design: Design, _ params: Parameters, _ predictionData: DataFrame) {
        let fit = Fit(design.matrix, design.response, design.weights, params.rankTolerance)
        let stats = ModelStatistics(fit, params.confidence)
        let diagnostics = Diagnostics(fit, params)
        let prediction = predictionReport(number, design, fit, stats, predictionData)
        self.number = number
        self.design = design
        self.fit = fit
        self.stats = stats
        coefficients = coefficientInference(fit, stats)
        anova = sequentialANOVA(design, fit)
        marginal = marginalTests(design, fit, Array(design.model.terms.indices), params.rankTolerance)
        vif = varianceInflation(design, fit, stats, params)
        self.diagnostics = diagnostics
        decisions = DiagnosticDecisions(design, fit, diagnostics, params)
        reset = resetTest(fit, params.rankTolerance)
        predictions = prediction.lines
        predictionCheck = prediction.check
    }
}

func diagnosticSummary(_ report: ModelReport) -> [String] {
    let design = report.design, fit = report.fit, diagnostic = report.diagnostics, decisions = report.decisions
    let bp = diagnostic.breuschPagan, jb = diagnostic.jarqueBera, reset = report.reset
    let outlier = decisions.outlier, counts = decisions.counts
    var lines = ["Diagnostics:",
                 "Durbin-Watson: \(four(diagnostic.durbinWatson)) (\(decisions.dwLabel))",
                 "Breusch-Pagan: \(four(bp.statistic)) on \(bp.degrees) DF, p-value: \(probability(bp.p)) (\(decisions.bpLabel))",
                 "Jarque-Bera: \(four(jb.statistic)) on 2 DF, p-value: \(probability(jb.p)), skewness \(four(jb.skewness)), kurtosis \(four(jb.kurtosis)) (\(decisions.jbLabel))",
                 "RESET (powers 2 and 3): F \(four(reset.f)) on \(reset.added) and \(reset.residualDF) DF, p-value: \(probability(reset.p))",
                 "Outlier test: row \(design.rowNumbers[outlier]), studentized \(four(diagnostic.rows[outlier].studentized)), unadjusted p-value: \(probability(decisions.unadjusted)), Bonferroni p-value: \(probability(decisions.bonferroni))",
                 "Flagged rows: leverage \(counts["H"]!), outlier \(counts["O"]!), cooks \(counts["C"]!), dffits \(counts["F"]!), any \(counts["any"]!)",
                 "Largest Cook's distances:"]
    for i in decisions.largestCooks {
        let row = diagnostic.rows[i]
        lines.append("row \(design.rowNumbers[i]): cooks_d \(four(row.cooks)), leverage \(four(fit.leverage[i])), studentized \(four(row.studentized)), flags \(row.flags)")
    }
    lines.append("Largest absolute DFBETAS:")
    lines += table(["column", "row", "DFBETAS"], decisions.largestDFBetas.map { [$0.name, String($0.row), four($0.value)] })
    return lines
}

func modelSummary(_ report: ModelReport, _ totalRows: Int, _ confidence: Double) -> [String] {
    let design = report.design, fit = report.fit, stats = report.stats
    let names = design.columns.map { $0.name }, coefficients = report.coefficients
    let aliasNames = fit.aliases.map { names[$0] }.joined(separator: ", ")
    let aliases = aliasNames.isEmpty ? "none" : aliasNames
    let quantiles = stats.quantiles
    var lines = ["Model \(report.number): \(design.model.original)",
                 "Terms: " + design.model.terms.map { $0.name }.joined(separator: ", "),
                 "Weights: \(design.model.weight ?? "none")",
                 "Observations: \(fit.n) used, \(totalRows - fit.n) dropped",
                 "Columns: \(fit.p), rank \(fit.rank), aliased: \(aliases)", "",
                 "Residuals: Min \(four(quantiles[0])), 1Q \(four(quantiles[1])), Median \(four(quantiles[2])), 3Q \(four(quantiles[3])), Max \(four(quantiles[4]))",
                 "", "Coefficients:"]
    lines += table(["term", "Estimate", "Std. Error", "t value", "Pr(>|t|)"], coefficients.indices.map { i in
        let coefficient = coefficients[i]
        return [names[i], four(coefficient.estimate), four(coefficient.standardError), four(coefficient.t), probability(coefficient.p)]
    }, marks: coefficients.map { significance($0.p) })
    lines += ["---", "Signif. codes: 0 '***' 0.001 '**' 0.01 '*' 0.05 '.' 0.1 ' ' 1", "",
              "Residual standard error: \(four(stats.sigma)) on \(stats.df) degrees of freedom",
              "Multiple R-squared: \(four(stats.rSquared)), Adjusted R-squared: \(four(stats.adjusted))",
              "F-statistic: \(four(stats.f)) on \(fit.rank - 1) and \(stats.df) DF, p-value: \(probability(stats.p))",
              "Log-likelihood: \(four(stats.likelihood)), AIC: \(four(stats.aic)), BIC: \(four(stats.bic))",
              "PRESS: \(four(stats.press)), Predicted R-squared: \(four(stats.predicted))", "",
              "Confidence intervals (level \(four(confidence)), t \(four(stats.critical))):"]
    lines += table(["term", "Lower", "Upper"], coefficients.indices.map { [names[$0], four(coefficients[$0].lower), four(coefficients[$0].upper)] })
    lines += ["", "Robust standard errors (HC3):"]
    lines += table(["term", "Std. Error", "t value", "Pr(>|t|)"], coefficients.indices.map { i in
        [names[i], four(coefficients[i].robustError), four(coefficients[i].robustT), probability(coefficients[i].robustP)]
    }, marks: coefficients.map { significance($0.robustP) })
    lines += ["", "Analysis of variance (sequential):"]
    var anova = report.anova.map { [$0.name, String($0.df), four($0.squares), four($0.meanSquare), four($0.f), probability($0.p)] }
    anova.append(["Residuals", String(stats.df), four(fit.rss), four(fit.rss / Double(stats.df))])
    lines += table(["term", "Df", "Sum Sq", "Mean Sq", "F value", "Pr(>F)"], anova,
                   marks: report.anova.map { significance($0.p) } + [""])
    lines += ["", "Marginal F tests (drop one term):"]
    lines += table(["term", "Df", "Sum Sq", "RSS", "F value", "Pr(>F)"], report.marginal.map {
        [$0.name, String($0.df), four($0.squares), four($0.rss), four($0.f), probability($0.p)]
    }, marks: report.marginal.map { significance($0.p) })
    lines += ["", "Variance inflation factors:"]
    lines += table(["column", "VIF"], report.vif.map { [$0.name, four($0.value)] }, marks: report.vif.map { $0.high ? "high" : "" })
    lines.append("")
    lines += diagnosticSummary(report)
    return lines
}

func summaryReport(_ data: DataFrame, _ reports: [ModelReport], _ params: Parameters) -> [String] {
    var lines = dataSummary(data)
    for (index, report) in reports.enumerated() {
        if index > 0 { lines.append("") }
        lines += modelSummary(report, data.rows.count, params.confidence)
    }
    lines += ["", "Model comparison:"]
    lines += table(["model", "n", "rank", "sigma", "R-squared", "Adj. R-squared", "Pred. R-squared", "AIC", "BIC"], reports.map { report in
        let stats = report.stats
        return [String(report.number), String(report.fit.n), String(report.fit.rank), four(stats.sigma),
                four(stats.rSquared), four(stats.adjusted), four(stats.predicted), four(stats.aic), four(stats.bic)]
    })
    lines += ["", "Prediction check:"]
    for report in reports {
        let check = report.predictionCheck
        lines.append("model \(report.number): \(check.predicted) predicted, \(check.actual) with actual values, RMSE \(four(check.rmse)), inside prediction interval \(check.covered)")
    }
    return lines
}

func diagnosticsCSV(_ reports: [ModelReport]) -> [String] {
    var lines = ["model,row,fitted,residual,leverage,studentized,cooks_d,dffits,flags"]
    for report in reports {
        let fit = report.fit
        for (i, row) in report.diagnostics.rows.enumerated() {
            let values = [fit.fitted[i], fit.residual[i], fit.leverage[i], row.studentized, row.cooks, row.dffits]
            lines.append(([String(report.number), String(report.design.rowNumbers[i])] + values.map { four($0) } + [row.flags]).joined(separator: ","))
        }
    }
    return lines
}

func backwardSelection(_ report: ModelReport, _ params: Parameters) -> [String] {
    let design = report.design, model = design.model
    var terms = Array(model.terms.indices), fit = report.fit
    var lines = ["Backward elimination (model 1, alpha \(four(params.removeAlpha)), rows \(design.rows.count))"]
    var step = 1
    while true {
        let aic = informationCriteria(fit).aic, df = fit.n - fit.rank
        lines.append("Step \(step): \(model.format(terms)) (RSS \(four(fit.rss)), df \(df), AIC \(four(aic)))")
        if terms.isEmpty { lines.append("  stop: no removable terms"); break }
        let tests = marginalTests(design, fit, terms, params.rankTolerance)
        for test in tests {
            lines.append("  - \(test.name): F \(four(test.f)) on \(test.df) and \(df) DF, p-value \(probability(test.p))")
        }
        var largest = tests[0]
        for test in tests.dropFirst() where test.p! > largest.p! { largest = test }
        if largest.p! <= params.removeAlpha {
            lines.append("  stop: largest p-value \(probability(largest.p)) is not above \(four(params.removeAlpha))")
            break
        }
        lines.append("  remove \(largest.name)")
        terms.removeAll { $0 == largest.index }
        fit = fitSubset(design, terms, params.rankTolerance)
        step += 1
    }
    lines.append("Final model: \(model.format(terms))")
    return lines
}

func forwardSelection(_ report: ModelReport, _ params: Parameters) -> [String] {
    let design = report.design, model = design.model
    var terms: [Int] = []
    var lines = ["Forward selection by AIC (model 1, rows \(design.rows.count))"]
    var step = 1
    while true {
        let fit = fitSubset(design, terms, params.rankTolerance)
        let aic = informationCriteria(fit).aic
        lines.append("Step \(step): \(model.format(terms)) (AIC \(four(aic)))")
        let candidates = model.candidates(terms)
        if candidates.isEmpty { lines.append("  stop: no candidate terms remain"); break }
        var best: (index: Int, aic: Double, terms: [Int])?
        for index in candidates {
            let selected = (terms + [index]).sorted()
            let candidate = fitSubset(design, selected, params.rankTolerance)
            let candidateAIC = informationCriteria(candidate).aic
            lines.append("  + \(model.terms[index].name): AIC \(four(candidateAIC))")
            if best == nil || candidateAIC < best!.aic { best = (index, candidateAIC, selected) }
        }
        if best!.aic >= aic { lines.append("  stop: no candidate lowers the AIC"); break }
        lines.append("  add \(model.terms[best!.index].name)")
        terms = best!.terms
        step += 1
    }
    lines.append("Final model: \(model.format(terms))")
    return lines
}

func bestSubsets(_ report: ModelReport, _ params: Parameters) -> [String] {
    let design = report.design, model = design.model
    var subsets: [(bic: Double, mask: Int, aic: Double, rank: Int, terms: [Int])] = []
    for mask in 0..<(1 << model.terms.count) {
        let terms = model.terms.indices.filter { mask & (1 << $0) != 0 }
        if !model.hierarchical(terms) { continue }
        let fit = fitSubset(design, terms, params.rankTolerance)
        let criteria = informationCriteria(fit)
        subsets.append((criteria.bic, mask, criteria.aic, fit.rank, terms))
    }
    subsets.sort { $0.bic == $1.bic ? $0.mask < $1.mask : $0.bic < $1.bic }
    var lines = ["Best subsets by BIC (model 1, rows \(design.rows.count), subsets \(subsets.count))"]
    for (index, subset) in subsets.prefix(params.bestSubsets).enumerated() {
        lines.append("\(index + 1). BIC \(four(subset.bic)), AIC \(four(subset.aic)), rank \(subset.rank): \(model.format(subset.terms))")
    }
    return lines
}

func plotGrid(_ horizontal: [Double], _ vertical: [Double], _ lo: Double, _ hi: Double, _ params: Parameters) -> [[Int]] {
    let width = params.plotWidth, height = params.plotHeight, limit = params.plotLimit
    var grid = Array(repeating: Array(repeating: 0, count: width), count: height)
    for (x, y) in zip(horizontal, vertical) {
        let column = min(Int(floor((x - lo) / (hi - lo) * Double(width))), width - 1)
        let row = max(0, min(Int(floor((limit - y) / (2 * limit) * Double(height))), height - 1))
        grid[row][column] += 1
    }
    return grid
}

func plotFrame(_ grid: [[Int]]) -> [String] {
    let border = "+" + String(repeating: "-", count: grid[0].count) + "+"
    var lines = [border]
    for (index, row) in grid.enumerated() {
        let empty = index == grid.count / 2 ? "-" : "."
        lines.append("|" + row.map { $0 >= 10 ? "*" : $0 > 0 ? String($0) : empty }.joined() + "|")
    }
    return lines + [border]
}

func residualPlot(_ report: ModelReport, _ params: Parameters) -> [String] {
    let fit = report.fit, number = report.number, limit = params.plotLimit
    let studentized = report.diagnostics.rows.map { $0.studentized }
    let lo = fit.fitted.min()!, hi = fit.fitted.max()!
    let grid = plotGrid(fit.fitted, studentized, lo, hi, params)
    var lines = ["Model \(number): studentized residuals vs fitted values",
                 "fitted \(four(lo)) to \(four(hi)), studentized \(four(-limit)) to \(four(limit))"]
    lines += plotFrame(grid)
    let above = studentized.filter { $0 > 2 }.count, below = studentized.filter { $0 < -2 }.count
    let outside = studentized.filter { abs($0) > limit }.count
    lines += ["points: \(fit.n), above +2: \(above), below -2: \(below), outside range: \(outside)", "Histogram of studentized residuals:"]
    let counts = grid.map { $0.reduce(0, +) }, maximum = counts.max()!
    for (index, count) in counts.enumerated() {
        let lower = limit - 2 * limit * Double(index + 1) / Double(params.plotHeight)
        let upper = limit - 2 * limit * Double(index) / Double(params.plotHeight)
        let length = (count * 40 + maximum - 1) / maximum
        var line = "\(four(lower)) to \(four(upper)): \(count)"
        if length > 0 { line += " " + String(repeating: "#", count: length) }
        lines.append(line)
    }
    let leverageHigh = fit.leverage.max()!
    lines += ["Model \(number): studentized residuals vs leverage",
              "leverage 0.0000 to \(four(leverageHigh)), studentized \(four(-limit)) to \(four(limit))"]
    lines += plotFrame(plotGrid(fit.leverage, studentized, 0, leverageHigh, params))
    return lines
}

func writeReport(_ filename: String, _ lines: [String]) throws {
    try (lines.joined(separator: "\n") + "\n").write(toFile: "output/" + filename, atomically: false, encoding: .ascii)
}

let data = try readCSV("input/data.csv")
let models = try inputLines("input/model.txt")
let predictionData = try readCSV("input/predict.csv", kinds: data.kinds)
let params = try readParameters()
let reports = models.enumerated().map { index, line in ModelReport(index + 1, Design(Model(line), data), params, predictionData) }
try writeReport("summary.txt", summaryReport(data, reports, params))
try writeReport("diagnostics.csv", diagnosticsCSV(reports))
try writeReport("selection.txt", backwardSelection(reports[0], params) + [""] + forwardSelection(reports[0], params) + [""] + bestSubsets(reports[0], params))
try writeReport("predictions.csv", ["model,row,fit,se_fit,conf_lower,conf_upper,pred_lower,pred_upper,actual,error,covered"] + reports.flatMap { $0.predictions })
var plots: [String] = []
for (index, report) in reports.enumerated() {
    if index > 0 { plots.append("") }
    plots += residualPlot(report, params)
}
try writeReport("residual_plot.txt", plots)
