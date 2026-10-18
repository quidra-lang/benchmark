import Foundation

func date(_ y: Int, _ m: Int, _ d: Int) -> String {
    String(format: "%04d-%02d-%02d", locale: Locale(identifier: "en_US_POSIX"), y, m, d)
}
let lengths = [31,28,31,30,31,30,31,31,30,31,30,31]
for (initialYear,initialMonth,initialDay,days) in [(1999,12,25,10),(2000,2,27,3),(2021,2,20,14),(2023,11,15,120),(2026,10,17,1500)] {
    var year = initialYear, month = initialMonth, day = initialDay
    let original = date(year,month,day)
    for _ in 0..<days {
        let monthLength = lengths[month - 1] + (month == 2 && year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 1 : 0)
        day += 1
        if day > monthLength {
            day = 1
            month += 1
            if month > 12 {
                month = 1
                year += 1
            }
        }
    }
    print("\(original) + \(days) days = \(date(year,month,day))")
}
