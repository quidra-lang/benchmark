import Foundation

func logGamma(_ x: Double) -> Double {
    let coefficients = [76.18009172947146, -86.50532032941677, 24.01409824083091,
                        -1.231739572450155, 0.001208650973866179, -0.000005395239384953]
    let t = x + 5.5
    let adjustment = t - (x + 0.5) * log(t)
    var series = 1.000000000190015
    for (j, coefficient) in coefficients.enumerated() { series = series + coefficient / (x + Double(j + 1)) }
    return -adjustment + log(2.5066282746310005 * series / x)
}

func replaceSmall(_ value: Double) -> Double { abs(value) < 1e-300 ? 1e-300 : value }

func betaFraction(_ a: Double, _ b: Double, _ x: Double) -> Double {
    var c = 1.0
    var d = 1 / replaceSmall(1 - (a + b) * x / (a + 1))
    var h = d
    for index in 1...1000 {
        let m = Double(index)
        var q = m * (b - m) * x / ((a - 1 + 2 * m) * (a + 2 * m))
        d = 1 / replaceSmall(1 + q * d)
        c = replaceSmall(1 + q / c)
        h = h * (d * c)
        q = -(a + m) * (a + b + m) * x / ((a + 2 * m) * (a + 1 + 2 * m))
        d = 1 / replaceSmall(1 + q * d)
        c = replaceSmall(1 + q / c)
        let delta = d * c
        h = h * delta
        if abs(delta - 1) < 1e-15 { break }
    }
    return h
}

func incompleteBeta(_ x: Double, _ a: Double, _ b: Double) -> Double {
    if x <= 0 { return 0 }
    if x >= 1 { return 1 }
    let factor = exp(logGamma(a + b) - logGamma(a) - logGamma(b) + a * log(x) + b * log(1 - x))
    if x < (a + 1) / (a + b + 2) { return factor * betaFraction(a, b, x) / a }
    return 1 - factor * betaFraction(b, a, 1 - x) / b
}

func upperGamma(_ a: Double, _ x: Double) -> Double {
    if x <= 0 { return 1 }
    let factor = exp(-x + a * log(x) - logGamma(a))
    if x < a + 1 {
        var term = 1 / a
        var series = term
        var e = a
        for _ in 0..<1000 {
            e = e + 1
            term = term * (x / e)
            series = series + term
            if abs(term) < abs(series) * 1e-15 { break }
        }
        return 1 - series * factor
    }
    var beta = x + 1 - a
    var c = 1 / 1e-300
    var d = 1 / beta
    var h = d
    for index in 1...1000 {
        let i = Double(index)
        let q = -i * (i - a)
        beta = beta + 2
        d = 1 / replaceSmall(q * d + beta)
        c = replaceSmall(beta + q / c)
        let delta = d * c
        h = h * delta
        if abs(delta - 1) < 1e-15 { break }
    }
    return factor * h
}

func tPValue(_ t: Double, _ degrees: Int) -> Double {
    let df = Double(degrees)
    return incompleteBeta(df / (df + t * t), df / 2, 0.5)
}

func fPValue(_ statistic: Double, _ numerator: Int, _ denominator: Int) -> Double {
    let d1 = Double(numerator), d2 = Double(denominator)
    return incompleteBeta(d2 / (d2 + d1 * statistic), d2 / 2, d1 / 2)
}

func chiPValue(_ statistic: Double, _ degrees: Int) -> Double { upperGamma(Double(degrees) / 2, statistic / 2) }

func tQuantile(_ confidence: Double, _ degrees: Int) -> Double {
    var lo = 0.0, hi = 1000.0
    for _ in 0..<100 {
        let mid = (lo + hi) / 2
        if tPValue(mid, degrees) > 1 - confidence { lo = mid } else { hi = mid }
    }
    return (lo + hi) / 2
}

func significance(_ value: Double?) -> String {
    guard let value else { return "" }
    if value < 0.001 { return "***" }
    if value < 0.01 { return "**" }
    if value < 0.05 { return "*" }
    return value < 0.1 ? "." : ""
}

func four(_ value: Double?) -> String {
    guard let value else { return "NA" }
    let text = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), value)
    return text == "-0.0000" ? "0.0000" : text
}

func probability(_ value: Double?) -> String {
    guard let value else { return "NA" }
    return value < 0.0001 ? "<0.0001" : four(value)
}
