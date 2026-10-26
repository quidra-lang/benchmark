object DayRules {
    val months = listOf("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")
    val weekdays = listOf("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat")
    val commonDays = intArrayOf(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
    const val DAY = 86400L
    const val NEG_INFINITY = -(1L shl 62)
    const val POS_INFINITY = 1L shl 62

    fun leap(year: Int): Boolean = year % 4 == 0 && year % 100 != 0 || year % 400 == 0
    fun daysInMonth(year: Int, month: Int): Int = if (month == 2 && leap(year)) 29 else commonDays[month - 1]

    private fun daysBeforeYear(year: Int): Long {
        val previous = year - 1L
        return previous * 365 + Math.floorDiv(previous, 4) - Math.floorDiv(previous, 100) + Math.floorDiv(previous, 400)
    }

    fun dayNumber(year: Int, month: Int, day: Int): Long {
        var number = daysBeforeYear(year) - daysBeforeYear(1970) + day - 1
        for (m in 1 until month) number += daysInMonth(year, m)
        return number
    }

    fun weekday(day: Long): Int = Math.floorMod(day + 4, 7).toInt()
    fun timeValue(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int): Long =
        dayNumber(year, month, day) * DAY + hour * 3600L + minute * 60L + second

    fun splitTime(time: Long): IntArray {
        val number = Math.floorDiv(time, DAY)
        var year = 1970 + Math.floorDiv(number, 366).toInt()
        while (dayNumber(year, 1, 1) > number) year--
        while (dayNumber(year + 1, 1, 1) <= number) year++
        var month = 1
        var day = (number - dayNumber(year, 1, 1) + 1).toInt()
        while (day > daysInMonth(year, month)) { day -= daysInMonth(year, month); month++ }
        val seconds = Math.floorMod(time, DAY)
        return intArrayOf(year, month, day, (seconds / 3600).toInt(), (seconds / 60 % 60).toInt(), (seconds % 60).toInt())
    }

    data class DaySpec(val kind: String, val weekdayIndex: Int, val day: Int) {
        fun value(year: Int, month: Int): Long {
            if (kind == "last") {
                val last = dayNumber(year, month, daysInMonth(year, month))
                return last - Math.floorMod(weekday(last) - weekdayIndex, 7)
            }
            val base = dayNumber(year, month, day)
            return when (kind) {
                "after" -> base + Math.floorMod(weekdayIndex - weekday(base), 7)
                "before" -> base - Math.floorMod(weekday(base) - weekdayIndex, 7)
                else -> base
            }
        }
    }
}
