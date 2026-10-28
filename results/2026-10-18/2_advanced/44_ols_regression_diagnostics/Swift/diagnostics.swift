import Foundation

struct RowDiagnostic {
    let standardized: Double
    let studentized: Double
    let cooks: Double
    let dffits: Double
    let flags: String
    let dfbetas: [Double]
}

struct Diagnostics {
    let rows: [RowDiagnostic]
    let durbinWatson: Double
    let breuschPagan: (statistic: Double, degrees: Int, p: Double)
    let jarqueBera: (statistic: Double, p: Double, skewness: Double, kurtosis: Double)

    init(_ fit: Fit, _ params: Parameters) {
        let n = Double(fit.n), r = Double(fit.rank), df = n - r
        let sigma = sqrt(fit.rss / df)
        let leverageLimit = params.leverage * r / n
        let cookLimit = params.cook / n
        let dffitsLimit = params.dffits * sqrt(r / n)
        rows = (0..<fit.n).map { i in
            let h = fit.leverage[i], residual = fit.weightedResidual[i]
            let z = residual / (sigma * sqrt(1 - h))
            let studentized = z * sqrt((df - 1) / (df - z * z))
            let cooks = z * z * h / (r * (1 - h))
            let dffits = studentized * sqrt(h / (1 - h))
            var flags = ""
            if h > leverageLimit { flags += "H" }
            if abs(studentized) > params.studentized { flags += "O" }
            if cooks > cookLimit { flags += "C" }
            if abs(dffits) > dffitsLimit { flags += "F" }
            let deletedSigma = sigma * sqrt((df - z * z) / (df - 1))
            let dfbetas = (0..<fit.rank).map { k in
                fit.g[i][k] * residual / (1 - h) / (deletedSigma * sqrt(fit.variance[k]))
            }
            return RowDiagnostic(standardized: z, studentized: studentized, cooks: cooks,
                                 dffits: dffits, flags: flags.isEmpty ? "-" : flags, dfbetas: dfbetas)
        }
        let differences = (1..<fit.n).map { i in
            let difference = fit.weightedResidual[i] - fit.weightedResidual[i - 1]
            return difference * difference
        }
        durbinWatson = orderedSum(differences) / fit.rss
        let squared = fit.weightedResidual.map { $0 * $0 }
        let matrix = fit.matrix.map { row in fit.accepted.map { row[$0] } }
        let auxiliary = Fit(matrix, squared, Array(repeating: 1, count: fit.n), params.rankTolerance)
        let mean = orderedSum(squared) / n
        let tss = orderedSum(squared.map { ($0 - mean) * ($0 - mean) })
        let bp = n * (1 - auxiliary.rss / tss)
        let degrees = auxiliary.rank - 1
        breuschPagan = (bp, degrees, chiPValue(bp, degrees))
        let residualMean = orderedSum(fit.weightedResidual) / n
        let centered = fit.weightedResidual.map { $0 - residualMean }
        let m2 = orderedSum(centered.map { $0 * $0 }) / n
        let m3 = orderedSum(centered.map { $0 * $0 * $0 }) / n
        let m4 = orderedSum(centered.map { $0 * $0 * $0 * $0 }) / n
        let skewness = m3 / (m2 * sqrt(m2)), kurtosis = m4 / (m2 * m2)
        let jb = n / 6 * (skewness * skewness + (kurtosis - 3) * (kurtosis - 3) / 4)
        jarqueBera = (jb, chiPValue(jb, 2), skewness, kurtosis)
    }
}
