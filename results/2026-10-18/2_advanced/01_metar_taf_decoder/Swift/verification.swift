import Foundation

let categories = ["VFR", "MVFR", "IFR", "LIFR"]

func covers(_ f: Forecast, _ t: Int) -> Bool {
    f.issue <= t && f.start <= t - t % 60 && t - t % 60 < f.end
}

func chosenForecast(_ fs: [Forecast], _ t: Int) -> Forecast? {
    var chosen: Forecast? = nil
    for f in fs {
        if covers(f, t) && (chosen == nil || f.issue >= chosen!.issue) {
            chosen = f
        }
    }
    return chosen
}

final class Contingency {
    var table = Array(repeating: Array(repeating: 0, count: 4), count: 4)
    var temporaryHits = 0
    func add(_ expected: String, _ observed: String, _ hit: Bool) {
        table[categories.firstIndex(of: expected)!][categories.firstIndex(of: observed)!] += 1
        if hit {
            temporaryHits += 1
        }
    }
    func row(_ i: Int) -> Int {
        table[i].reduce(0, +)
    }
    func column(_ i: Int) -> Int {
        table.reduce(0) {
            $0 + $1[i]
        }
    }
    var total: Int {
        table.reduce(0) {
            $0 + $1.reduce(0, +)
        }
    }
    var hits: Int {
        (0..<4).reduce(0) {
            $0 + table[$1][$1]
        }
    }
    var skill: (Int, Int) {
        let e = (0..<4).reduce(0) {
            $0 + row($1) * column($1)
        }
        return (total * hits - e, total * total - e)
    }
    func detection(_ i: Int) -> (Int, Int) {
        (table[i][i], column(i))
    }
    func falseAlarm(_ i: Int) -> (Int, Int) {
        (row(i) - table[i][i], row(i))
    }
}
