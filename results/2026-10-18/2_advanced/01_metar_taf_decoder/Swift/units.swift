import Foundation

func floorDiv(_ n: Int, _ d: Int) -> Int {
    n >= 0 ? n / d : -((-n + d - 1) / d)
}

func knots(_ v: Int, _ unit: String) -> Int {
    unit == "MPS" ? (v * 1944 + 500) / 1000 : v
}

func inhg(_ q: Int) -> Int {
    (q * 2953 + 500) / 1000
}

func hpa(_ a: Int) -> Int {
    (a * 33864 + 50000) / 100000
}

let sineTable = [0, 174, 342, 500, 643, 766, 866, 940, 985, 1000]

func sine(_ x: Int) -> Int {
    let y = (x % 360 + 360) % 360
    if y <= 90 {
        return sineTable[y / 10]
    }
    if y <= 180 {
        return sineTable[(180 - y) / 10]
    }
    if y <= 270 {
        return -sineTable[(y - 180) / 10]
    }
    return -sineTable[(360 - y) / 10]
}

func cosine(_ x: Int) -> Int {
    sine(x + 90)
}

func daysInMonth(_ y: Int, _ m: Int) -> Int {
    if m == 2 {
        return y % 4 == 0 && (y % 100 != 0 || y % 400 == 0) ? 29 : 28
    }
    return [1, 3, 5, 7, 8, 10, 12].contains(m) ? 31 : 30
}

func dayMinutes(_ d: Int, _ h: Int, _ m: Int) -> Int {
    ((d - 1) * 24 + h) * 60 + m
}

func pad(_ n: Int, _ width: Int) -> String {
    let s = String(n)
    return String(repeating: "0", count: max(0, width - s.count)) + s
}

struct Calendar {
    let year: Int, month: Int
    var days: Int {
        daysInMonth(year, month)
    }
    var nextYear: Int {
        month == 12 ? year + 1 : year
    }
    var nextMonth: Int {
        month == 12 ? 1 : month + 1
    }
    func forecastTime(_ d: Int, _ h: Int, _ m: Int, _ issueDay: Int) -> Int? {
        let next = d < issueDay
        if d < 1 || d > daysInMonth(next ? nextYear : year, next ? nextMonth : month) {
            return nil
        }
        return (next ? days * 1440 : 0) + dayMinutes(d, h, m)
    }
    func stamp(_ time: Int) -> String {
        let next = time >= days * 1440, t = time - (time >= days * 1440 ? days * 1440 : 0)
        return "\(pad(next ? nextYear : year, 4))-\(pad(next ? nextMonth : month, 2))-\(pad(t / 1440 + 1, 2))T\(pad(t % 1440 / 60, 2)):\(pad(t % 60, 2))Z"
    }
}

func miles(_ g: Group) -> (Int, Int) {
    if g.visibilityKind == "MILES" {
        return g.denominator == 0 ? (g.whole, 1) : (g.whole * g.denominator + g.numerator, g.denominator)
    }
    return (1000 * g.meters, 1609344)
}

func meterValue(_ g: Group) -> Int {
    let (n, d) = miles(g)
    return g.visibilityKind == "MILES" ? 1609344 * n / (1000 * d) : g.meters
}

func lessFraction(_ a: (Int, Int), _ b: (Int, Int)) -> Bool {
    a.0 * b.1 < b.0 * a.1
}

func fraction(_ n: Int, _ d: Int) -> String {
    if d == 0 {
        return "undefined"
    }
    var a = abs(n), b = abs(d)
    while b != 0 {
        let r = a % b
        a = b
        b = r
    }
    let sign = d < 0 ? -1 : 1
    return "\(n / a * sign)/\(d / a * sign)"
}
