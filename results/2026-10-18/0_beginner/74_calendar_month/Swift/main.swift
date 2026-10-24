import Foundation

let names = ["January","February","March","April","May","June",
    "July","August","September","October","November","December"]
let offsets = [0,3,2,5,0,3,5,1,4,6,2,4]
for (index,pair) in [(2024,2),(2026,8),(2026,11)].enumerated() {
    if index > 0 { print() }
    let (year,month) = pair, y = month < 3 ? year - 1 : year
    let weekday = (y + y / 4 - y / 100 + y / 400 + offsets[month - 1] + 1) % 7
    var lengths = [31,28,31,30,31,30,31,31,30,31,30,31]
    if year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) { lengths[1] = 29 }
    print("\(names[month - 1]) \(year)")
    print("Su Mo Tu We Th Fr Sa")
    var week = [String](repeating: "  ", count: weekday)
    for day in 1...lengths[month - 1] {
        week.append(String(format: "%2d", locale: Locale(identifier: "en_US_POSIX"), day))
        if week.count == 7 {
            print(week.joined(separator: " "))
            week.removeAll()
        }
    }
    if !week.isEmpty { print(week.joined(separator: " ")) }
}
