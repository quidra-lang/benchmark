struct Fraction {
    let numerator: Int
    let denominator: Int
    var value: Double { Double(numerator) / Double(denominator) }
}

func yearFraction(_ convention: String, start: Int, end: Int) -> Fraction {
    let first = civilDate(start)
    let last = civilDate(end)
    if convention == "30/360" || convention == "30E/360" {
        var d1 = first.day
        var d2 = last.day
        if convention == "30E/360" { if d1 == 31 { d1 = 30 }; if d2 == 31 { d2 = 30 } }
        else {
            let february = first.month == 2 && d1 == monthLength(first.year, first.month)
            if february && last.month == 2 && d2 == monthLength(last.year, last.month) { d2 = 30 }
            if february { d1 = 30 }
            if d2 == 31 && d1 >= 30 { d2 = 30 }
            if d1 == 31 { d1 = 30 }
        }
        return Fraction(numerator: 360 * (last.year - first.year) + 30 * (last.month - first.month) + d2 - d1, denominator: 360)
    }
    if convention == "ACT/360" { return Fraction(numerator: end - start, denominator: 360) }
    if convention == "ACT/365F" { return Fraction(numerator: end - start, denominator: 365) }
    var cursor = start
    var year = first.year
    var numerator = 0
    while cursor < end {
        let boundary = min(dayNumber(year + 1, 1, 1), end)
        numerator += (boundary - cursor) * (isLeap(year) ? 365 : 366)
        cursor = boundary
        year += 1
    }
    return Fraction(numerator: numerator, denominator: 133590)
}
