data class CivilDate(val year: Int, val month: Int, val day: Int)

fun isLeap(year: Int) = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
fun yearLength(year: Int) = if (isLeap(year)) 366 else 365
fun monthLength(year: Int, month: Int) = if (month == 2 && isLeap(year)) 29 else listOf(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)[month - 1]
fun splitDate(text: String) = CivilDate(text.substring(0, 4).toInt(), text.substring(5, 7).toInt(), text.substring(8, 10).toInt())
fun validDate(text: String): Boolean {
    val date = splitDate(text)
    return date.year in 2001..2099 && date.month in 1..12 && date.day in 1..monthLength(date.year, date.month)
}
fun dayNumber(year: Int, month: Int, day: Int): Int {
    var result = day - 1
    for (earlier in 2000 until year) result += yearLength(earlier)
    for (earlier in 1 until month) result += monthLength(year, earlier)
    return result
}
fun parseDate(text: String): Int { val date = splitDate(text); return dayNumber(date.year, date.month, date.day) }
fun civilDate(number: Int): CivilDate {
    var remaining = number
    var year = 2000
    while (remaining >= yearLength(year)) { remaining -= yearLength(year); year++ }
    var month = 1
    while (remaining >= monthLength(year, month)) { remaining -= monthLength(year, month); month++ }
    return CivilDate(year, month, remaining + 1)
}
fun dateText(number: Int): String {
    val date = civilDate(number)
    return "${date.year.toString().padStart(4, '0')}-${date.month.toString().padStart(2, '0')}-${date.day.toString().padStart(2, '0')}"
}
class BusinessCalendar(val holidays: Set<Int>) {
    fun business(day: Int) = (day + 5) % 7 < 5 && day !in holidays
    fun following(day: Int): Int { var result = day; while (!business(result)) result++; return result }
    fun preceding(day: Int): Int { var result = day; while (!business(result)) result--; return result }
    fun adjust(day: Int, rule: String): Int = when (rule) {
        "FOLLOWING" -> following(day)
        "PRECEDING" -> preceding(day)
        "MODIFIED_FOLLOWING" -> following(day).let { if (civilDate(it).month != civilDate(day).month) preceding(day) else it }
        else -> day
    }
    fun move(day: Int, count: Int, direction: Int = 1): Int {
        var remaining = count
        var result = day
        while (remaining > 0) { result += direction; if (business(result)) remaining-- }
        return result
    }
}
