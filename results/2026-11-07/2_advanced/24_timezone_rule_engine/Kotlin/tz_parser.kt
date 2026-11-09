object TzParser {
    class FieldError(message: String) : RuntimeException(message)
    data class Time(val value: Long, val type: Char)
    data class Until(val yearText: String, val monthText: String, val dayText: String, val time: Long, val type: Char, val value: Long)

    fun content(raw: String): String = raw.substringBefore('#').trimEnd(' ')
    fun continuation(content: String): Boolean = content.startsWith(' ')
    fun fields(content: String): List<String> = content.trimStart(' ').split(Regex(" +"))
    private fun number(text: String, low: Int, high: Int): Boolean = text.length in low..high && text.all { it in '0'..'9' }

    private fun hms(text: String, maxParts: Int): Long? {
        val parts = text.split(':')
        if (parts.size > maxParts || !number(parts[0], 1, 2)) return null
        var value = parts[0].toLong() * 3600
        for (i in 1 until parts.size) {
            if (!number(parts[i], 2, 2) || parts[i].toInt() > 59) return null
            value += parts[i].toLong() * if (i == 1) 60 else 1
        }
        return value
    }

    fun year(text: String): Int {
        if (!number(text, 4, 4)) throw FieldError("bad year")
        val value = text.toInt()
        if (value !in 1800..2099) throw FieldError("bad year")
        return value
    }

    fun toYear(text: String, from: Int): Int {
        if (text == "only") return from
        if (text == "max") return 2099
        if (!number(text, 4, 4)) throw FieldError("bad year")
        val value = text.toInt()
        if (value !in from..2099) throw FieldError("bad year")
        return value
    }

    fun month(text: String): Int {
        val index = DayRules.months.indexOf(text)
        if (index < 0) throw FieldError("bad month")
        return index + 1
    }

    private fun weekday(text: String): Int {
        val index = DayRules.weekdays.indexOf(text)
        if (index < 0) throw FieldError("bad day spec")
        return index
    }

    private fun dayOfMonth(text: String, month: Int): Int {
        if (!number(text, 1, 2) || text[0] == '0' || text.toInt() > DayRules.commonDays[month - 1]) throw FieldError("bad day spec")
        return text.toInt()
    }

    fun day(text: String, month: Int): DayRules.DaySpec {
        if (text.startsWith("last")) return DayRules.DaySpec("last", weekday(text.substring(4)), 0)
        for (operator in listOf(">=", "<=")) {
            val index = text.indexOf(operator)
            if (index >= 0) return DayRules.DaySpec(if (operator == ">=") "after" else "before", weekday(text.substring(0, index)), dayOfMonth(text.substring(index + 2), month))
        }
        return DayRules.DaySpec("day", 0, dayOfMonth(text, month))
    }

    fun time(raw: String): Time {
        var text = raw
        var type = 'w'
        if (text.isNotEmpty() && text.last() in "wsu") { type = text.last(); text = text.dropLast(1) }
        val value = hms(text, 3)
        if (value == null || value > 86400) throw FieldError("bad time")
        return Time(value, type)
    }

    fun save(text: String): Long {
        val value = hms(text, 2)
        if (value == null || value > 7200) throw FieldError("bad save")
        return value
    }

    fun letter(text: String): String {
        if (text == "-") return ""
        if (!Regex("[A-Z]{1,5}").matches(text)) throw FieldError("bad letter")
        return text
    }

    fun offset(raw: String): Long {
        val sign = if (raw.startsWith('-')) -1 else 1
        val value = hms(if (sign < 0) raw.substring(1) else raw, 3)
        if (value == null || value >= 57600) throw FieldError("bad offset")
        return sign * value
    }

    fun checkFormat(text: String, ruleSet: Boolean) {
        val placeholders = (text.length - text.replace("%s", "").length) / 2
        val percentages = text.count { it == '%' }
        val slashes = text.count { it == '/' }
        var valid = Regex("[A-Za-z0-9+/%-]+").matches(text) && percentages == placeholders && placeholders <= 1 && slashes <= 1 &&
            !(placeholders > 0 && slashes > 0) && (ruleSet || placeholders == 0)
        if (slashes == 1 && (text.startsWith('/') || text.endsWith('/'))) valid = false
        if (!valid) throw FieldError("bad format")
    }

    fun until(fields: List<String>): Until {
        val year = year(fields[0])
        val monthText = fields.getOrElse(1) { "Jan" }
        val month = month(monthText)
        val dayText = fields.getOrElse(2) { "1" }
        val day = day(dayText, month)
        val time = if (fields.size > 3) time(fields[3]) else Time(0, 'w')
        return Until(fields[0], monthText, dayText, time.value, time.type, day.value(year, month) * DayRules.DAY + time.value)
    }
}
