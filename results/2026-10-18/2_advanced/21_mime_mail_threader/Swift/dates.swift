import Foundation

private let weekdays = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
private let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
private let namedZones = ["ut": 0, "gmt": 0, "z": 0, "est": -300, "edt": -240, "cst": -360, "cdt": -300, "mst": -420, "mdt": -360, "pst": -480, "pdt": -420]
enum DateProblem: String, Error { case syntax = "bad Date syntax", range = "Date out of range", weekday = "Date weekday mismatch" }
private func leap(_ year: Int) -> Bool { year % 4 == 0 && year % 100 != 0 || year % 400 == 0 }
private func monthDays(_ year: Int, _ month: Int) -> Int { month == 2 && leap(year) ? 29 : [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1] }
private func yearDays(_ year: Int) -> Int { leap(year) ? 366 : 365 }
private func digits(_ text: String, _ lengths: [Int]) -> Bool { lengths.contains(text.utf8.count) && text.utf8.allSatisfy { 48...57 ~= $0 } }
func parseDate(_ value: String) throws -> Int {
    guard let text = removeComments(value) else { throw DateProblem.syntax }
    var tokens = splitWords(text.replacingOccurrences(of: ",", with: " , "))
    var weekday: Int?
    if tokens.count >= 3 && tokens[1] == ",", let day = weekdays.firstIndex(of: tokens[0].lowercased()) { weekday = day; tokens.removeFirst(2) }
    if tokens.count != 5 { throw DateProblem.syntax }
    let dayText = tokens[0], monthText = tokens[1], yearText = tokens[2], zone = tokens[4]
    let pieces = tokens[3].split(separator: ":", omittingEmptySubsequences: false).map(String.init)
    let numeric = (zone.first == "+" || zone.first == "-") && digits(String(zone.dropFirst()), [4])
    guard digits(dayText, [1, 2]), let monthIndex = months.firstIndex(of: monthText.lowercased()), digits(yearText, [2, 4]), [2, 3].contains(pieces.count), pieces.allSatisfy({ digits($0, [2]) }), numeric || namedZones[zone.lowercased()] != nil else { throw DateProblem.syntax }
    let month = monthIndex + 1
    let day = Int(dayText)!
    var year = Int(yearText)!
    if yearText.count == 2 { year += year < 50 ? 2000 : 1900 }
    let hour = Int(pieces[0])!, minute = Int(pieces[1])!, second = pieces.count == 3 ? Int(pieces[2])! : 0
    let offset: Int
    if numeric {
        let hours = Int(zone.dropFirst().prefix(2))!, minutes = Int(zone.suffix(2))!
        if hours > 23 || minutes > 59 { throw DateProblem.range }
        offset = (hours * 60 + minutes) * (zone.first == "-" ? -1 : 1)
    } else { offset = namedZones[zone.lowercased()]! }
    if !(1970...2099).contains(year) || day < 1 || day > monthDays(year, month) || hour > 23 || minute > 59 || second > 59 { throw DateProblem.range }
    var days = day - 1
    for current in 1970..<year { days += yearDays(current) }
    for current in 1..<month { days += monthDays(year, current) }
    let seconds = days * 86400 + hour * 3600 + minute * 60 + second - offset * 60
    if seconds < 0 { throw DateProblem.range }
    if let weekday, (days + 3) % 7 != weekday { throw DateProblem.weekday }
    return seconds
}
func formatUTC(_ seconds: Int) -> String {
    var days = seconds / 86400
    let rest = seconds % 86400
    var year = 1970
    var month = 1
    while days >= yearDays(year) { days -= yearDays(year); year += 1 }
    while days >= monthDays(year, month) { days -= monthDays(year, month); month += 1 }
    func pad(_ value: Int, _ width: Int) -> String { let text = String(value); return String(repeating: "0", count: max(0, width - text.count)) + text }
    return "\(pad(year, 4))-\(pad(month, 2))-\(pad(days + 1, 2)) \(pad(rest / 3600, 2)):\(pad(rest % 3600 / 60, 2)):\(pad(rest % 60, 2))"
}
