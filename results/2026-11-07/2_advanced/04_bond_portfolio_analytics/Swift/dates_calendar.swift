struct CivilDate { let year: Int; let month: Int; let day: Int }

func isLeap(_ year: Int) -> Bool { year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) }
func yearLength(_ year: Int) -> Int { isLeap(year) ? 366 : 365 }
func monthLength(_ year: Int, _ month: Int) -> Int { month == 2 && isLeap(year) ? 29 : [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1] }
func splitDate(_ text: String) -> CivilDate {
    let parts = text.split(separator: "-").map { Int($0)! }
    return CivilDate(year: parts[0], month: parts[1], day: parts[2])
}
func validDate(_ text: String) -> Bool {
    let date = splitDate(text)
    return (2001...2099).contains(date.year) && (1...12).contains(date.month) && (1...monthLength(date.year, date.month)).contains(date.day)
}
func dayNumber(_ year: Int, _ month: Int, _ day: Int) -> Int {
    var number = day - 1
    if year > 2000 { for earlier in 2000..<year { number += yearLength(earlier) } }
    if month > 1 { for earlier in 1..<month { number += monthLength(year, earlier) } }
    return number
}
func parseDate(_ text: String) -> Int { let date = splitDate(text); return dayNumber(date.year, date.month, date.day) }
func civilDate(_ number: Int) -> CivilDate {
    var remaining = number
    var year = 2000
    while remaining >= yearLength(year) { remaining -= yearLength(year); year += 1 }
    var month = 1
    while remaining >= monthLength(year, month) { remaining -= monthLength(year, month); month += 1 }
    return CivilDate(year: year, month: month, day: remaining + 1)
}
func dateText(_ number: Int) -> String {
    let date = civilDate(number)
    func padded(_ value: Int, _ width: Int) -> String { let text = String(value); return String(repeating: "0", count: max(0, width - text.count)) + text }
    return "\(padded(date.year, 4))-\(padded(date.month, 2))-\(padded(date.day, 2))"
}
struct BusinessCalendar {
    let holidays: Set<Int>
    func business(_ day: Int) -> Bool { (day + 5) % 7 < 5 && !holidays.contains(day) }
    func following(_ day: Int) -> Int { var result = day; while !business(result) { result += 1 }; return result }
    func preceding(_ day: Int) -> Int { var result = day; while !business(result) { result -= 1 }; return result }
    func adjust(_ day: Int, rule: String) -> Int {
        switch rule {
        case "FOLLOWING": return following(day)
        case "PRECEDING": return preceding(day)
        case "MODIFIED_FOLLOWING": let next = following(day); return civilDate(next).month != civilDate(day).month ? preceding(day) : next
        default: return day
        }
    }
    func move(_ day: Int, count: Int, direction: Int = 1) -> Int {
        var remaining = count
        var result = day
        while remaining > 0 { result += direction; if business(result) { remaining -= 1 } }
        return result
    }
}
