fun couponSchedule(issue: Int, maturity: Int, frequency: Int, endOfMonth: Boolean = false, longStub: Boolean = false): List<Int> {
    val date = civilDate(maturity)
    val eom = endOfMonth && date.day == monthLength(date.year, date.month)
    val dates = mutableListOf<Int>()
    var boundary = maturity
    while (boundary > issue) {
        dates += boundary
        val index = date.year * 12 + date.month - 1 - 12 / frequency * dates.size
        val year = index / 12
        val month = index % 12 + 1
        boundary = dayNumber(year, month, if (eom) monthLength(year, month) else minOf(date.day, monthLength(year, month)))
    }
    if (longStub && boundary != issue && dates.size >= 2) dates.removeAt(dates.lastIndex)
    dates += issue
    return dates.reversed()
}
