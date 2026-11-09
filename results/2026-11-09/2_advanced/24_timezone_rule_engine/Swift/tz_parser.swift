import Foundation

let minYear = 1800, maxYear = 2099
enum FieldError: Error { case invalid(String) }
struct Until {
    let yearText: String
    let monthText: String
    let dayText: String
    let time: Int
    let timeType: Character
    let value: Int
}
func lineContent(_ raw: String) -> String {
    var content = String(raw.prefix { $0 != "#" })
    while content.last == " " { content.removeLast() }
    return content
}
func splitFields(_ content: String) -> [String] { content.split(separator: " ").map(String.init) }
func isNumber(_ text: String, _ low: Int, _ high: Int) -> Bool { (low...high).contains(text.utf8.count) && text.utf8.allSatisfy { (48...57).contains($0) } }
func hmsValue(_ text: String, _ maxParts: Int = 3) -> Int? {
    if text.isEmpty { return nil }
    let parts = text.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
    if parts.count > maxParts || !isNumber(parts[0], 1, 2) { return nil }
    var value = Int(parts[0])! * 3600
    for (part, unit) in zip(parts.dropFirst(), [60, 1]) {
        if !isNumber(part, 2, 2) || Int(part)! > 59 { return nil }
        value += Int(part)! * unit
    }
    return value
}
func parseYear(_ text: String) throws -> Int {
    if isNumber(text, 4, 4), let value = Int(text), (minYear...maxYear).contains(value) { return value }
    throw FieldError.invalid("bad year")
}
func parseTo(_ text: String, _ from: Int) throws -> Int {
    if text == "only" { return from }; if text == "max" { return maxYear }
    if isNumber(text, 4, 4), let value = Int(text), (from...maxYear).contains(value) { return value }
    throw FieldError.invalid("bad year")
}
func parseMonth(_ text: String) throws -> Int { guard let position = monthNames.firstIndex(of: text) else { throw FieldError.invalid("bad month") }; return position + 1 }
func parseWeekday(_ text: String) throws -> Int { guard let position = weekdayNames.firstIndex(of: text) else { throw FieldError.invalid("bad day spec") }; return position }
func parseDay(_ text: String, _ month: Int) throws -> Int {
    if isNumber(text, 1, 2), !text.hasPrefix("0"), let value = Int(text), value <= commonMonthDays[month - 1] { return value }
    throw FieldError.invalid("bad day spec")
}
func parseDaySpec(_ text: String, _ month: Int) throws -> DaySpec {
    if text.hasPrefix("last") { return .last(try parseWeekday(String(text.dropFirst(4)))) }
    for (operation, after) in [(">=", true), ("<=", false)] {
        if let range = text.range(of: operation) {
            let weekday = try parseWeekday(String(text[..<range.lowerBound])), day = try parseDay(String(text[range.upperBound...]), month)
            return after ? .after(weekday, day) : .before(weekday, day)
        }
    }
    return .day(try parseDay(text, month))
}
func parseTime(_ text: String) throws -> (Int, Character) {
    var clock = text, kind: Character = "w"
    if let last = clock.last, "wsu".contains(last) { kind = last; clock.removeLast() }
    guard let value = hmsValue(clock), value <= secondsPerDay else { throw FieldError.invalid("bad time") }
    return (value, kind)
}
func parseSave(_ text: String) throws -> Int { guard let value = hmsValue(text, 2), value <= 7200 else { throw FieldError.invalid("bad save") }; return value }
func parseLetter(_ text: String) throws -> String {
    if text == "-" { return "" }
    if !text.isEmpty && text.utf8.count <= 5 && text.utf8.allSatisfy({ (65...90).contains($0) }) { return text }
    throw FieldError.invalid("bad letter")
}
func parseStdoff(_ text: String) throws -> Int {
    let negative = text.hasPrefix("-"), clock = text.hasPrefix("-") ? String(text.dropFirst()) : text
    guard let value = hmsValue(clock), value < 57600 else { throw FieldError.invalid("bad offset") }
    return negative ? -value : value
}
func checkFormat(_ text: String, _ usesRuleSet: Bool) throws {
    let placeholders = text.components(separatedBy: "%s").count - 1, slashes = text.filter { $0 == "/" }.count
    let characters = text.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || [43, 45, 47, 37].contains($0) }
    let valid = characters && text.filter { $0 == "%" }.count == placeholders && placeholders <= 1 && slashes <= 1
        && !(placeholders > 0 && slashes > 0) && (usesRuleSet || placeholders == 0)
        && !(slashes == 1 && (text.hasPrefix("/") || text.hasSuffix("/")))
    if !valid { throw FieldError.invalid("bad format") }
}
func parseUntil(_ fields: [String]) throws -> Until {
    let year = try parseYear(fields[0]), monthText = fields.count > 1 ? fields[1] : "Jan"
    let month = try parseMonth(monthText), dayText = fields.count > 2 ? fields[2] : "1"
    let day = try parseDaySpec(dayText, month)
    let (time, kind) = try (fields.count > 3 ? parseTime(fields[3]) : (0, Character("w")))
    return Until(yearText: fields[0], monthText: monthText, dayText: dayText, time: time, timeType: kind, value: day.value(year, month) * secondsPerDay + time)
}
