import Foundation

func date(_ y: Int, _ m: Int, _ d: Int) -> String {
    let parts = [y,m,d], widths = [4,2,2]
    return parts.enumerated().map { i,value in String(repeating: "0",count: widths[i] - String(value).count) + String(value) }.joined(separator: "-")
}
for (initialYear,initialMonth,initialDay,days) in [(1999,12,25,10),(2000,2,27,3),(2021,2,20,14),(2023,11,15,120),(2026,10,17,1500)] {
    var year = initialYear, month = initialMonth, day = initialDay
    let original = date(year,month,day)
    for _ in 0..<days {
        var lengths = [31,28,31,30,31,30,31,31,30,31,30,31]
        if year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) { lengths[1] = 29 }
        day += 1; if day > lengths[month - 1] { day = 1; month += 1; if month > 12 { month = 1; year += 1 } }
    }
    print("\(original) + \(days) days = \(date(year,month,day))")
}
