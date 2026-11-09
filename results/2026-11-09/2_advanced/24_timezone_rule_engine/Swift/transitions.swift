import Foundation

struct Rule {
    let number: Int
    let fields: [String]
    let name: String
    let fromYear: Int
    let toYear: Int
    let month: Int
    let day: DaySpec
    let at: Int
    let atType: Character
    let save: Int
    let letter: String
}
struct RuleInstance { let rule: Int; let nominal: Int }
struct LineRun { var lastPreStart: Int?; var applied: [(Int, Int)] = []; var end = positiveInfinity }
func instanceSequence(_ rules: [Rule], _ indices: [Int]) -> [RuleInstance] {
    var instances: [RuleInstance] = []
    for index in indices {
        let rule = rules[index]
        for year in rule.fromYear...rule.toYear { instances.append(RuleInstance(rule: index, nominal: rule.day.value(year, rule.month) * secondsPerDay + rule.at)) }
    }
    instances.sort { ($0.nominal, rules[$0.rule].number) < ($1.nominal, rules[$1.rule].number) }
    return instances
}
func adjustment(_ kind: Character, _ stdoff: Int, _ save: Int) -> Int { kind == "u" ? 0 : (kind == "s" ? stdoff : stdoff + save) }
func runInstances(_ instances: [RuleInstance], _ rules: [Rule], _ stdoff: Int, _ start: Int, _ until: Until?) -> LineRun {
    var run = LineRun(lastPreStart: nil), save = 0
    for instance in instances {
        let rule = rules[instance.rule], time = instance.nominal - adjustment(rules[instance.rule].atType, stdoff, save)
        if let until = until, time >= until.value - adjustment(until.timeType, stdoff, save) { break }
        if time <= start { run.lastPreStart = instance.rule } else { run.applied.append((time, instance.rule)) }
        save = rule.save
    }
    if let until = until { run.end = until.value - adjustment(until.timeType, stdoff, save) }
    return run
}
func abbreviation(_ format: String, _ save: Int, _ letter: String) -> String {
    if let slash = format.firstIndex(of: "/") { return save == 0 ? String(format[..<slash]) : String(format[format.index(after: slash)...]) }
    return format.replacingOccurrences(of: "%s", with: letter)
}
