data class Fraction(val numerator: Long, val denominator: Long) {
    fun value() = numerator.toDouble() / denominator.toDouble()
}

fun yearFraction(convention: String, start: Int, end: Int): Fraction {
    val first = civilDate(start)
    val last = civilDate(end)
    if (convention == "30/360" || convention == "30E/360") {
        var d1 = first.day
        var d2 = last.day
        if (convention == "30E/360") { if (d1 == 31) d1 = 30; if (d2 == 31) d2 = 30 }
        else {
            val february = first.month == 2 && d1 == monthLength(first.year, first.month)
            if (february && last.month == 2 && d2 == monthLength(last.year, last.month)) d2 = 30
            if (february) d1 = 30
            if (d2 == 31 && d1 >= 30) d2 = 30
            if (d1 == 31) d1 = 30
        }
        return Fraction((360 * (last.year - first.year) + 30 * (last.month - first.month) + d2 - d1).toLong(), 360)
    }
    if (convention == "ACT/360") return Fraction((end - start).toLong(), 360)
    if (convention == "ACT/365F") return Fraction((end - start).toLong(), 365)
    var cursor = start
    var year = first.year
    var numerator = 0L
    while (cursor < end) {
        val boundary = minOf(dayNumber(year + 1, 1, 1), end)
        numerator += (boundary - cursor).toLong() * if (isLeap(year)) 365 else 366
        cursor = boundary
        year++
    }
    return Fraction(numerator, 133590)
}
