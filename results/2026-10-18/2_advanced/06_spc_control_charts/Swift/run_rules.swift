struct Point {
    let number: Int
    let value: Double
}
struct Signal {
    let chart: String
    let rule: String
    let start: Int
    let end: Int
    let value: Double
    let direction: String
    func subgroup(_ size: Int) -> Int { chart == "I" || chart == "MR" ? (end - 1) / size + 1 : end }
}
struct Zones {
    let upper1: Double
    let upper2: Double
    let lower1: Double
    let lower2: Double
    init(_ limits: Limits) {
        let above = (limits.ucl - limits.cl) / 3
        let below = (limits.cl - limits.lcl) / 3
        upper1 = limits.cl + above
        upper2 = limits.cl + 2 * above
        lower1 = limits.cl - below
        lower2 = limits.cl - 2 * below
    }
}
func zoneName(_ value: Double, _ limits: Limits) -> String {
    let zone = Zones(limits)
    if value > limits.ucl { return "OUT+" }
    if value < limits.lcl { return "OUT-" }
    if value > zone.upper2 { return "A+" }
    if value > zone.upper1 { return "B+" }
    if value > limits.cl { return "C+" }
    if value < zone.lower2 { return "A-" }
    if value < zone.lower1 { return "B-" }
    return value < limits.cl ? "C-" : "C0"
}
func runRules(_ chart: String, _ points: [Point], _ limits: Limits, _ rules: [Int]) -> [Signal] {
    let lengths = [0, 1, 3, 5, 8, 6, 14, 15, 8]
    let zone = Zones(limits)
    var signals: [Signal] = []
    for index in points.indices {
        for rule in rules {
            let length = lengths[rule]
            if index + 1 < length { continue }
            let window = points[(index + 1 - length)...index].map(\.value)
            let value = window.last!
            var direction: String?
            switch rule {
            case 1: if limits.outside(value) { direction = value > limits.cl ? "UP" : "DOWN" }
            case 2:
                if value > zone.upper2 && window.filter({ $0 > zone.upper2 }).count >= 2 { direction = "UP" }
                else if value < zone.lower2 && window.filter({ $0 < zone.lower2 }).count >= 2 { direction = "DOWN" }
            case 3:
                if value > zone.upper1 && window.filter({ $0 > zone.upper1 }).count >= 4 { direction = "UP" }
                else if value < zone.lower1 && window.filter({ $0 < zone.lower1 }).count >= 4 { direction = "DOWN" }
            case 4:
                if window.allSatisfy({ $0 > limits.cl }) { direction = "UP" }
                else if window.allSatisfy({ $0 < limits.cl }) { direction = "DOWN" }
            case 5:
                if zip(window, window.dropFirst()).allSatisfy({ pair in pair.1 > pair.0 }) { direction = "UP" }
                else if zip(window, window.dropFirst()).allSatisfy({ pair in pair.1 < pair.0 }) { direction = "DOWN" }
            case 6:
                let differences = zip(window, window.dropFirst()).map { pair in pair.1 - pair.0 }
                if differences.allSatisfy({ $0 != 0 }) && zip(differences, differences.dropFirst()).allSatisfy({ pair in (pair.0 > 0) != (pair.1 > 0) }) { direction = "NONE" }
            case 7: if window.allSatisfy({ $0 > zone.lower1 && $0 < zone.upper1 }) { direction = "NONE" }
            default:
                if window.allSatisfy({ $0 > zone.upper1 || $0 < zone.lower1 }) && window.contains(where: { $0 > zone.upper1 }) && window.contains(where: { $0 < zone.lower1 }) { direction = "NONE" }
            }
            if let direction { signals.append(Signal(chart: chart, rule: String(rule), start: points[index + 1 - length].number, end: points[index].number, value: value, direction: direction)) }
        }
    }
    return signals
}
