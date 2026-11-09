import java.util.Locale

data class DateResult(val seconds: Long?, val error: String?)
object Dates {
    private val WEEKDAYS = listOf("mon", "tue", "wed", "thu", "fri", "sat", "sun")
    private val MONTHS = listOf("jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec")
    private val MONTH_DAYS = intArrayOf(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
    private val ZONES = mapOf("ut" to 0, "gmt" to 0, "z" to 0, "est" to -300, "edt" to -240, "cst" to -360, "cdt" to -300, "mst" to -420, "mdt" to -360, "pst" to -480, "pdt" to -420)
    private fun leap(year: Int) = year % 4 == 0 && year % 100 != 0 || year % 400 == 0
    private fun monthDays(year: Int, month: Int) = if (month == 2 && leap(year)) 29 else MONTH_DAYS[month - 1]
    private fun yearDays(year: Int) = if (leap(year)) 366 else 365
    private fun epochDays(year: Int, month: Int, day: Int): Int {
        var days = day - 1
        for (current in 1970 until year) days += yearDays(current)
        for (current in 1 until month) days += monthDays(year, current)
        return days
    }
    fun digits(text: String, vararg lengths: Int) = text.length in lengths && text.all { it in '0'..'9' }
    private fun numericZone(text: String) = text.length == 5 && text[0] in "+-" && digits(text.substring(1), 4)
    private fun failure(text: String) = DateResult(null, text)
    fun parse(value: String): DateResult {
        val text = Headers.removeComments(value) ?: return failure("bad Date syntax")
        var tokens = Headers.words(text.replace(",", " , "))
        var weekday = -1
        if (tokens.size >= 3 && tokens[0].lowercase() in WEEKDAYS && tokens[1] == ",") {
            weekday = WEEKDAYS.indexOf(tokens[0].lowercase())
            tokens = tokens.drop(2)
        }
        if (tokens.size != 5) return failure("bad Date syntax")
        val dayText = tokens[0]
        val monthText = tokens[1].lowercase()
        val yearText = tokens[2]
        val time = tokens[3].split(':')
        val zone = tokens[4]
        val validTime = time.size in 2..3 && time.all { digits(it, 2) }
        if (!digits(dayText, 1, 2) || monthText !in MONTHS || !digits(yearText, 2, 4) || !validTime || !(numericZone(zone) || zone.lowercase() in ZONES)) return failure("bad Date syntax")
        val day = dayText.toInt()
        val month = MONTHS.indexOf(monthText) + 1
        var year = yearText.toInt()
        if (yearText.length == 2) year += if (year < 50) 2000 else 1900
        val hour = time[0].toInt()
        val minute = time[1].toInt()
        val second = if (time.size == 3) time[2].toInt() else 0
        val offset = if (numericZone(zone)) {
            val hours = zone.substring(1, 3).toInt()
            val minutes = zone.substring(3).toInt()
            if (hours > 23 || minutes > 59) return failure("Date out of range")
            (hours * 60 + minutes) * (if (zone[0] == '-') -1 else 1)
        } else ZONES.getValue(zone.lowercase())
        if (year !in 1970..2099 || day < 1 || day > monthDays(year, month) || hour > 23 || minute > 59 || second > 59) return failure("Date out of range")
        val days = epochDays(year, month, day)
        val seconds = days * 86400L + hour * 3600 + minute * 60 + second - offset * 60
        if (seconds < 0) return failure("Date out of range")
        if (weekday >= 0 && (days + 3) % 7 != weekday) return failure("Date weekday mismatch")
        return DateResult(seconds, null)
    }
    fun format(seconds: Long): String {
        var days = (seconds / 86400).toInt()
        val rest = (seconds % 86400).toInt()
        var year = 1970
        var month = 1
        while (days >= yearDays(year)) { days -= yearDays(year); year++ }
        while (days >= monthDays(year, month)) { days -= monthDays(year, month); month++ }
        return String.format(Locale.ROOT, "%04d-%02d-%02d %02d:%02d:%02d", year, month, days + 1, rest / 3600, rest % 3600 / 60, rest % 60)
    }
}
