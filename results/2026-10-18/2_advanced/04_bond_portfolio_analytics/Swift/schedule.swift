func couponSchedule(issue: Int, maturity: Int, frequency: Int, endOfMonth: Bool = false, longStub: Bool = false) -> [Int] {
    let date = civilDate(maturity)
    let eom = endOfMonth && date.day == monthLength(date.year, date.month)
    var dates: [Int] = []
    var boundary = maturity
    while boundary > issue {
        dates.append(boundary)
        let index = date.year * 12 + date.month - 1 - 12 / frequency * dates.count
        let year = index / 12
        let month = index % 12 + 1
        boundary = dayNumber(year, month, eom ? monthLength(year, month) : min(date.day, monthLength(year, month)))
    }
    if longStub && boundary != issue && dates.count >= 2 { dates.removeLast() }
    dates.append(issue)
    return dates.reversed()
}
