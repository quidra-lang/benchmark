let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
let weekdayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
let commonMonthDays = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
let secondsPerDay = 86400
let negativeInfinity = -(1 << 62), positiveInfinity = 1 << 62
func floorDiv(_ value: Int, _ divisor: Int) -> Int { value / divisor - (value % divisor < 0 ? 1 : 0) }
func floorMod(_ value: Int, _ divisor: Int) -> Int { let remainder = value % divisor; return remainder < 0 ? remainder + divisor : remainder }
func isLeapYear(_ year: Int) -> Bool { year % 4 == 0 && year % 100 != 0 || year % 400 == 0 }
func daysInMonth(_ year: Int, _ month: Int) -> Int { month == 2 && isLeapYear(year) ? 29 : commonMonthDays[month - 1] }
func daysBeforeYear(_ year: Int) -> Int { let previous = year - 1; return previous * 365 + floorDiv(previous, 4) - floorDiv(previous, 100) + floorDiv(previous, 400) }
func dayNumber(_ year: Int, _ month: Int, _ day: Int) -> Int {
    var result = daysBeforeYear(year) - daysBeforeYear(1970) + day - 1
    for earlier in 1..<month { result += daysInMonth(year, earlier) }
    return result
}
func weekdayOf(_ number: Int) -> Int { floorMod(number + 4, 7) }
func dateOfDay(_ number: Int) -> (Int, Int, Int) {
    var year = 1970 + floorDiv(number, 366)
    while dayNumber(year, 1, 1) > number { year -= 1 }
    while dayNumber(year + 1, 1, 1) <= number { year += 1 }
    var month = 1, day = number - dayNumber(year, 1, 1) + 1
    while day > daysInMonth(year, month) { day -= daysInMonth(year, month); month += 1 }
    return (year, month, day)
}
func timeValue(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int) -> Int { dayNumber(year, month, day) * secondsPerDay + hour * 3600 + minute * 60 + second }
func splitTime(_ time: Int) -> (Int, Int, Int, Int, Int, Int) {
    let (year, month, day) = dateOfDay(floorDiv(time, secondsPerDay)), seconds = floorMod(time, secondsPerDay)
    return (year, month, day, seconds / 3600, seconds / 60 % 60, seconds % 60)
}
enum DaySpec {
    case day(Int), last(Int), after(Int, Int), before(Int, Int)
    func value(_ year: Int, _ month: Int) -> Int {
        switch self {
        case .day(let day): return dayNumber(year, month, day)
        case .last(let weekday): let last = dayNumber(year, month, daysInMonth(year, month)); return last - floorMod(weekdayOf(last) - weekday, 7)
        case .after(let weekday, let day): let base = dayNumber(year, month, day); return base + floorMod(weekday - weekdayOf(base), 7)
        case .before(let weekday, let day): let base = dayNumber(year, month, day); return base - floorMod(weekdayOf(base) - weekday, 7)
        }
    }
}
