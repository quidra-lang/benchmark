import java.util.Locale
import java.util.TreeMap
import java.util.TreeSet
import kotlin.math.abs

private val fieldNames = listOf("minute", "hour", "day-of-month", "month", "day-of-week")
private val minimum = intArrayOf(0, 0, 1, 1, 0)
private val maximum = intArrayOf(59, 23, 31, 12, 7)
private val months = listOf("January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December")
private val weekdays = listOf("Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday")
private val monthDays = intArrayOf(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
private class CommandError(message: String) : RuntimeException(message)
private fun fail(reason: String): Nothing = throw CommandError(reason)
private fun fmt(pattern: String, vararg values: Any): String = String.format(Locale.ROOT, pattern, *values)
private fun digits(text: String, minimum: Int, maximum: Int) = text.length in minimum..maximum && text.all { it in '0'..'9' }
private fun leap(year: Int) = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
private fun monthLength(year: Int, month: Int) = if (month == 2 && leap(year)) 29 else monthDays[month - 1]

private data class Date(val year: Int, val month: Int, val day: Int) {
    val number: Int get() {
        var result = day - 1
        for (y in 2000 until year) result += if (leap(y)) 366 else 365
        for (m in 1 until month) result += monthLength(year, m)
        return result
    }
    val weekday: Int get() = (number + 6) % 7
    override fun toString() = fmt("%04d-%02d-%02d %s", year, month, day, weekdays[weekday].take(3))
    companion object {
        fun fromNumber(value: Int): Date {
            var number = value
            var year = 2000
            var month = 1
            while (number >= if (leap(year)) 366 else 365) { number -= if (leap(year)) 366 else 365; year++ }
            while (number >= monthLength(year, month)) { number -= monthLength(year, month); month++ }
            return Date(year, month, number + 1)
        }
    }
}
private fun pattern(text: String, pattern: String) = text.length == pattern.length && text.indices.all { i ->
    if (pattern[i] == '#') text[i] in '0'..'9' else text[i] == pattern[i]
}
private fun readDate(text: String, reason: String = "invalid date"): Date {
    if (!pattern(text, "####-##-##")) fail(reason)
    val date = Date(text.substring(0, 4).toInt(), text.substring(5, 7).toInt(), text.substring(8).toInt())
    if (date.year !in 2001..2098 || date.month !in 1..12 || date.day < 1 || date.day > monthLength(date.year, date.month)) fail(reason)
    return date
}
private fun readDatetime(words: List<String>, at: Int): Int {
    val date = readDate(words[at], "invalid datetime")
    val time = words[at + 1]
    if (!pattern(time, "##:##")) fail("invalid datetime")
    val hour = time.substring(0, 2).toInt()
    val minute = time.substring(3).toInt()
    if (hour > 23 || minute > 59) fail("invalid datetime")
    return date.number * 1440 + hour * 60 + minute
}
private fun readMonth(text: String): Date {
    if (!pattern(text, "####-##")) fail("invalid month")
    val date = Date(text.substring(0, 4).toInt(), text.substring(5).toInt(), 1)
    if (date.year !in 2001..2098 || date.month !in 1..12) fail("invalid month")
    return date
}
private fun datetimeText(time: Int): String {
    val date = Date.fromNumber(time / 1440)
    return fmt("%04d-%02d-%02d %02d:%02d %s", date.year, date.month, date.day, time % 1440 / 60, time % 60, weekdays[date.weekday].take(3))
}
private fun span(minutes: Int) = fmt("%dd%02dh%02dm", minutes / 1440, minutes % 1440 / 60, minutes % 60)
private fun positive(text: String, width: Int, maximum: Int, reason: String): Int {
    if (!digits(text, 1, width) || text[0] == '0' || text.toInt() > maximum) fail(reason)
    return text.toInt()
}
private data class Window(val low: Int, val high: Int)
private fun readWindow(words: List<String>, at: Int): Window {
    val low = readDatetime(words, at)
    val high = readDatetime(words, at + 2)
    if (low > high) fail("invalid window")
    if (high - low > 44640) fail("window too long")
    return Window(low, high)
}

private enum class SpecialKind { LAST, LAST_WORKDAY, BEFORE_LAST, NEAREST, NTH_WEEKDAY, LAST_WEEKDAY }
private data class Special(val kind: SpecialKind, val value: Int = 0, val occurrence: Int = 0) {
    override fun toString() = when (kind) {
        SpecialKind.LAST -> "L"
        SpecialKind.LAST_WORKDAY -> "LW"
        SpecialKind.BEFORE_LAST -> "L-$value"
        SpecialKind.NEAREST -> "${value}W"
        SpecialKind.NTH_WEEKDAY -> "$value#$occurrence"
        SpecialKind.LAST_WEEKDAY -> "${value}L"
    }
    fun phrase() = when (kind) {
        SpecialKind.LAST -> "the last day"
        SpecialKind.LAST_WORKDAY -> "the last weekday"
        SpecialKind.BEFORE_LAST -> "$value ${if (value == 1) "day" else "days"} before the last day"
        SpecialKind.NEAREST -> "the weekday nearest day $value"
        SpecialKind.NTH_WEEKDAY -> "the ${listOf("1st", "2nd", "3rd", "4th", "5th")[occurrence - 1]} ${weekdays[value]}"
        SpecialKind.LAST_WEEKDAY -> "the last ${weekdays[value]}"
    }
}
private fun readValue(text: String, index: Int): Int {
    val names = when (index) {
        3 -> listOf("JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC")
        4 -> listOf("SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT")
        else -> emptyList()
    }
    val named = names.indexOf(text)
    if (named >= 0) return named + if (index == 3) 1 else 0
    if (!digits(text, 1, 2)) fail("invalid value")
    val value = text.toInt()
    if (value !in minimum[index]..maximum[index]) fail("out of range")
    return value
}
private fun specialNumber(text: String, maximum: Int, width: Int = 2): Int {
    if (!digits(text, 1, width)) fail("invalid value")
    val value = text.toInt()
    if (value !in 1..maximum) fail("out of range")
    return value
}
private fun wordList(parts: List<String>, either: Boolean = false): String {
    if (parts.size < 2) return parts.joinToString("")
    return parts.dropLast(1).joinToString(", ") + (if (either) " or " else " and ") + parts.last()
}
private data class Field(val index: Int, val values: List<Int>, val specials: List<Special>, val restricted: Boolean) {
    fun contains(value: Int) = values.binarySearch(value) >= 0
    fun stepped(): Int {
        if (values.size < 2 || values[0] != 0 || values[1] < 2) return 0
        val step = values[1]
        if (values.size != maximum[index] / step + 1 || values.indices.any { values[it] != it * step }) return 0
        return step
    }
    private fun valueName(value: Int) = when (index) { 3 -> months[value - 1]; 4 -> weekdays[value]; else -> value.toString() }
    fun valueList(either: Boolean = false): String {
        val parts = mutableListOf<String>()
        var first = 0
        while (first < values.size) {
            var last = first
            while (last + 1 < values.size && values[last + 1] == values[last] + 1) last++
            if (last - first >= 2) parts += "${valueName(values[first])} through ${valueName(values[last])}"
            else for (i in first..last) parts += valueName(values[i])
            first = last + 1
        }
        return wordList(parts, either)
    }
    fun dayPhrase(either: Boolean = false): String {
        val parts = mutableListOf<String>()
        if (values.isNotEmpty()) parts += if (index == 4) valueList(either) else "${if (values.size == 1) "day" else "days"} ${valueList()}"
        parts += specials.map { it.phrase() }
        return wordList(parts, either) + if (index == 2 || specials.isNotEmpty()) " of the month" else ""
    }
    companion object {
        fun parse(text: String, index: Int): Field {
            val values = sortedSetOf<Int>()
            val specials = mutableListOf<Special>()
            try {
                for (item in text.split(',')) {
                    if (item.isEmpty()) fail("empty item")
                    val special = when {
                        index == 2 && (item.startsWith('L') || item.endsWith('W')) -> when {
                            item == "L" -> Special(SpecialKind.LAST)
                            item == "LW" -> Special(SpecialKind.LAST_WORKDAY)
                            item.startsWith("L-") -> Special(SpecialKind.BEFORE_LAST, specialNumber(item.drop(2), 30))
                            item.endsWith('W') -> Special(SpecialKind.NEAREST, specialNumber(item.dropLast(1), 31))
                            else -> fail("invalid value")
                        }
                        index == 4 && '#' in item -> {
                            val at = item.indexOf('#')
                            val weekday = readValue(item.substring(0, at), index)
                            val occurrence = specialNumber(item.substring(at + 1), 5, 1)
                            Special(SpecialKind.NTH_WEEKDAY, weekday % 7, occurrence)
                        }
                        index == 4 && item.length >= 2 && item.endsWith('L') -> Special(SpecialKind.LAST_WEEKDAY, readValue(item.dropLast(1), index) % 7)
                        else -> null
                    }
                    if (special != null) { if (special !in specials) specials += special; continue }
                    val slash = item.indexOf('/')
                    val base = if (slash < 0) item else item.substring(0, slash)
                    val first: Int
                    val last: Int
                    if (base == "*") { first = minimum[index]; last = maximum[index] }
                    else {
                        val dash = base.indexOf('-')
                        if (dash >= 0) {
                            first = readValue(base.substring(0, dash), index)
                            last = readValue(base.substring(dash + 1), index)
                            if (first > last) fail("invalid range")
                        } else { first = readValue(base, index); last = if (slash < 0) first else maximum[index] }
                    }
                    val step = if (slash < 0) 1 else {
                        val part = item.substring(slash + 1)
                        if (!digits(part, 1, 2) || part.toInt() == 0) fail("invalid step")
                        part.toInt()
                    }
                    for (value in first..last step step) values += if (index == 4) value % 7 else value
                }
            } catch (error: CommandError) { fail("${fieldNames[index]} ${error.message}") }
            return Field(index, values.toList(), specials.toList(), !text.startsWith('*'))
        }
    }
}
private data class DayMatch(val dom: Boolean, val dow: Boolean, val condition: Boolean)
private data class Cron(val fields: List<Field>, val daily: List<Int>, val text: String, val expanded: String) {
    val orRule get() = fields[2].restricted && fields[4].restricted
    fun matchDay(date: Date): DayMatch {
        val last = monthLength(date.year, date.month)
        val weekday = date.weekday
        fun nearest(day: Int): Int = when ((date.number - date.day + day + 6) % 7) {
            6 -> if (day == 1) 3 else day - 1
            0 -> if (day == last) day - 2 else day + 1
            else -> day
        }
        val dom = fields[2].contains(date.day) || fields[2].specials.any {
            when (it.kind) {
                SpecialKind.LAST -> date.day == last
                SpecialKind.LAST_WORKDAY -> date.day == nearest(last)
                SpecialKind.BEFORE_LAST -> date.day == last - it.value
                SpecialKind.NEAREST -> it.value <= last && date.day == nearest(it.value)
                else -> false
            }
        }
        val dow = fields[4].contains(weekday) || fields[4].specials.any {
            weekday == it.value && if (it.kind == SpecialKind.NTH_WEEKDAY) (date.day - 1) / 7 + 1 == it.occurrence else date.day + 7 > last
        }
        return DayMatch(dom, dow, if (orRule) dom || dow else dom && dow)
    }
    fun scheduled(date: Date) = fields[3].contains(date.month) && matchDay(date).condition
    fun fires(low: Int, high: Int, holidays: Set<Int>, reverse: Boolean = false, limit: Int = 0): List<Int> {
        val times = mutableListOf<Int>()
        val first = low / 1440
        val last = high / 1440
        val days = if (reverse) last downTo first else first..last
        val indices = if (reverse) daily.indices.reversed() else daily.indices
        for (day in days) {
            if (day in holidays || !scheduled(Date.fromNumber(day))) continue
            for (i in indices) {
                val time = day * 1440 + daily[i]
                if (time !in low..high) continue
                times += time
                if (limit > 0 && times.size == limit) return times
            }
        }
        return times
    }
    fun description(): String {
        val (minute, hour, dom, month, dow) = fields
        var text = if (daily.size <= 4) "At " + wordList(daily.map { fmt("%02d:%02d", it / 60, it % 60) }) else {
            val ms = minute.stepped()
            val hs = hour.stepped()
            var time = when {
                minute.values.size == 60 -> "Every minute"
                ms > 0 -> "Every $ms minutes"
                minute.values.size == 1 -> "At minute ${minute.values[0]}"
                else -> "At minutes ${minute.valueList()}"
            }
            when {
                hour.values.size == 24 -> if (time.startsWith("At minute")) time += " of every hour"
                hs > 0 -> time += ", every $hs hours"
                hour.values.last() - hour.values.first() + 1 == hour.values.size -> time += fmt(", between %02d:00 and %02d:59", hour.values.first(), hour.values.last())
                else -> time += ", during hours ${hour.valueList()}"
            }
            time
        }
        val dFull = dom.values.size == 31
        val wFull = dow.values.size == 7
        if (orRule) { if (!dFull && !wFull) text += ", on ${dom.dayPhrase()} or on ${dow.dayPhrase()}" }
        else if (!dFull && !wFull) text += ", on ${dom.dayPhrase()} if it is ${dow.dayPhrase(true)}"
        else if (!dFull) text += ", on ${dom.dayPhrase()}"
        else if (!wFull) text += ", on ${dow.dayPhrase()}"
        if (month.values.size != 12) text += ", in ${month.valueList()}"
        return text
    }
    companion object {
        fun parse(input: List<String>): Cron {
            val text = input.joinToString(" ")
            val words = if (input.size == 1 && input[0].startsWith('@')) {
                when (input[0]) {
                    "@yearly", "@annually" -> "0 0 1 1 *"
                    "@monthly" -> "0 0 1 * *"
                    "@weekly" -> "0 0 * * 0"
                    "@daily", "@midnight" -> "0 0 * * *"
                    "@hourly" -> "0 * * * *"
                    else -> fail("unknown macro")
                }.split(' ')
            } else input
            if (words.size != 5) fail("field count")
            val fields = words.mapIndexed { index, word -> Field.parse(word, index) }
            val daily = fields[1].values.flatMap { hour -> fields[0].values.map { minute -> hour * 60 + minute } }
            return Cron(fields, daily, text, words.joinToString(" "))
        }
    }
}

private enum class Policy { ALLOW, FORBID, REPLACE }
private class Job(val cron: Cron, var enabled: Boolean = true, var duration: Int = 1, var policy: Policy = Policy.ALLOW)
private class Scheduler {
    private val jobs = TreeMap<String, Job>()
    private val holidays = TreeSet<Int>()
    private fun job(id: String) = jobs[id] ?: fail("unknown job")
    private fun newId(id: String) {
        if (id.length !in 1..16 || id[0] !in 'a'..'z' || id.any { it !in 'a'..'z' && it !in '0'..'9' && it != '_' }) fail("invalid id")
        if (id in jobs) fail("duplicate job")
    }
    private fun enabled() = jobs.filterValues { it.enabled }.toList()
    private fun timeline(window: Window, conflicts: Boolean): List<String> {
        val enabled = enabled()
        val masks = LongArray(window.high - window.low + 1)
        for ((i, entry) in enabled.withIndex()) for (time in entry.second.cron.fires(window.low, window.high, holidays)) {
            val at = time - window.low
            masks[at] = masks[at] or (1L shl i)
        }
        val total = masks.sumOf { if (conflicts) if (it.countOneBits() >= 2) 1 else 0 else it.countOneBits() }
        val peak = masks.maxOfOrNull { if (it.countOneBits() >= 2) it.countOneBits() else 0 } ?: 0
        val rows = mutableListOf(if (conflicts) "CONFLICTS $total peak $peak" else "TIMELINE $total")
        for ((i, mask) in masks.withIndex()) {
            if (rows.size == 101) break
            if (conflicts) {
                if (mask.countOneBits() < 2) continue
                val ids = enabled.filterIndexed { index, _ -> (mask and (1L shl index)) != 0L }.map { it.first }
                rows += "${datetimeText(window.low + i)} ${ids.size} ${ids.joinToString(" ")}"
            } else for ((index, entry) in enabled.withIndex()) {
                if (rows.size == 101) break
                if ((mask and (1L shl index)) != 0L) rows += "${datetimeText(window.low + i)} ${entry.first}"
            }
        }
        if (total > 100) rows += "... ${total - 100} more"
        return rows
    }
    private fun simulate(window: Window): List<String> {
        val enabled = enabled()
        val events = IntArray(window.high - window.low + 1441)
        val rows = mutableListOf<String>()
        for ((id, job) in enabled) {
            var started = 0; var skipped = 0; var replaced = 0; var busy = 0; var lastEnd = -1
            for (time in job.cron.fires(window.low, window.high, holidays)) {
                if (lastEnd > time && job.policy == Policy.FORBID) { skipped++; continue }
                if (lastEnd > time && job.policy == Policy.REPLACE) {
                    events[lastEnd - window.low]++; events[time - window.low]--
                    busy -= lastEnd - time; replaced++
                }
                lastEnd = time + job.duration
                events[time - window.low]++; events[lastEnd - window.low]--
                started++; busy += job.duration
            }
            rows += "$id ${job.policy} started $started skipped $skipped replaced $replaced busy $busy"
        }
        var running = 0; var peak = 0; var at = 0
        for ((i, change) in events.withIndex()) { running += change; if (running > peak) { peak = running; at = window.low + i } }
        rows.add(0, "SIMULATE ${enabled.size} peak $peak" + if (peak == 0) "" else " at ${datetimeText(at)}")
        return rows
    }
    fun execute(words: List<String>): List<String> {
        val command = words[0]
        val expected = when (command) {
            "JOB" -> -3; "VALIDATE" -> -2; "LIST", "HOLIDAYS" -> 1
            "REMOVE", "ENABLE", "DISABLE", "DESCRIBE", "WEEK", "EXCLUDE", "INCLUDE" -> 2
            "RENAME", "EXPAND", "CALENDAR" -> 3; "RUNTIME", "MATCH", "GAP" -> 4
            "NEXT", "PREV", "TIMELINE", "CONFLICTS", "SIMULATE" -> 5; "COUNT" -> 6; "OVERLAP" -> 7
            else -> fail("unknown command")
        }
        if (if (expected < 0) words.size < -expected else words.size != expected) fail("wrong arguments")
        return when (command) {
            "JOB" -> { newId(words[1]); val cron = Cron.parse(words.drop(2)); jobs[words[1]] = Job(cron); listOf("JOB ${words[1]} added") }
            "VALIDATE" -> { val cron = Cron.parse(words.drop(1)); listOf("VALID ${cron.expanded} ${if (cron.orRule) "OR" else "AND"} ${cron.daily.size}") }
            "REMOVE" -> { job(words[1]); jobs.remove(words[1]); listOf("REMOVE ${words[1]}") }
            "RENAME" -> { val job = job(words[1]); newId(words[2]); jobs.remove(words[1]); jobs[words[2]] = job; listOf("RENAME ${words[1]} ${words[2]}") }
            "ENABLE", "DISABLE" -> {
                val job = job(words[1]); val desired = command == "ENABLE"
                if (job.enabled == desired) fail(if (desired) "already enabled" else "already disabled")
                job.enabled = desired; listOf("$command ${words[1]}")
            }
            "RUNTIME" -> {
                val job = job(words[1]); val duration = positive(words[2], 4, 1440, "invalid duration")
                val policy = Policy.entries.find { it.name == words[3] } ?: fail("invalid policy")
                job.duration = duration; job.policy = policy; listOf("RUNTIME ${words[1]} $duration $policy")
            }
            "LIST" -> listOf("LIST ${jobs.size}") + jobs.map { (id, job) -> "$id ${if (job.enabled) "on" else "off"} ${job.duration} ${job.policy} ${job.cron.text}" }
            "EXPAND" -> {
                val job = job(words[1]); val index = fieldNames.indexOf(words[2])
                if (index < 0) fail("invalid field")
                val field = job.cron.fields[index]
                val parts = listOf("EXPAND ${words[1]} ${words[2]} ${field.values.size}") + field.values.map { it.toString() } + field.specials.map { it.toString() }
                listOf(parts.joinToString(" "))
            }
            "DESCRIBE" -> { val job = job(words[1]); listOf("DESCRIBE ${words[1]} ${job.cron.description()}") }
            "MATCH" -> {
                val job = job(words[1]); val time = readDatetime(words, 2); val date = Date.fromNumber(time / 1440); val match = job.cron.matchDay(date)
                val reasons = mutableListOf<String>()
                if (!job.cron.fields[0].contains(time % 60)) reasons += "minute"
                if (!job.cron.fields[1].contains(time % 1440 / 60)) reasons += "hour"
                if (!match.condition && !match.dom) reasons += "day-of-month"
                if (!job.cron.fields[3].contains(date.month)) reasons += "month"
                if (!match.condition && !match.dow) reasons += "day-of-week"
                if (time / 1440 in holidays) reasons += "excluded"
                listOf("MATCH ${words[1]} ${datetimeText(time)} " + if (reasons.isEmpty()) "yes" else "no ${reasons.joinToString(" ")}")
            }
            "NEXT", "PREV" -> {
                val job = job(words[1]); val base = readDatetime(words, 2); val limit = positive(words[4], 2, 50, "invalid count"); val reverse = command == "PREV"
                val times = job.cron.fires(if (reverse) base - 527040 else base + 1, if (reverse) base - 1 else base + 527040, holidays, reverse, limit)
                val rows = mutableListOf("$command ${words[1]} ${times.size}")
                rows += times.map { "${datetimeText(it)} ${if (reverse) '-' else '+'}${span(abs(it - base))}" }
                if (times.size < limit) rows += "NONE"
                rows
            }
            "COUNT" -> {
                val job = job(words[1]); val window = readWindow(words, 2); val times = job.cron.fires(window.low, window.high, holidays)
                listOf("COUNT ${words[1]} runs ${times.size} days ${times.map { it / 1440 }.distinct().size}")
            }
            "GAP" -> {
                val job = job(words[1]); val base = readDatetime(words, 2); val times = job.cron.fires(base, base + 44640, holidays)
                if (times.size < 2) return listOf("GAP ${words[1]} runs ${times.size} none")
                val histogram = TreeMap<Int, Int>(); var longest = 0; var first = 0
                for (i in 0 until times.lastIndex) {
                    val gap = times[i + 1] - times[i]; histogram[gap] = (histogram[gap] ?: 0) + 1
                    if (gap > longest) { longest = gap; first = i }
                }
                listOf("GAP ${words[1]} runs ${times.size} shortest ${span(histogram.firstKey())} longest ${span(longest)} from ${datetimeText(times[first])} to ${datetimeText(times[first + 1])}") + histogram.map { (gap, count) -> "${span(gap)} $count" }
            }
            "OVERLAP" -> {
                val a = job(words[1]); val b = job(words[2]); val window = readWindow(words, 3)
                val other = b.cron.fires(window.low, window.high, holidays).toSet()
                val times = a.cron.fires(window.low, window.high, holidays).filter { it in other }
                listOf("OVERLAP ${words[1]} ${words[2]} ${times.size}" + if (times.isEmpty()) "" else " first ${datetimeText(times.first())} last ${datetimeText(times.last())}")
            }
            "TIMELINE", "CONFLICTS", "SIMULATE" -> {
                val window = readWindow(words, 1)
                if (command == "SIMULATE") simulate(window) else timeline(window, command == "CONFLICTS")
            }
            "WEEK" -> {
                val first = readDate(words[1]).number; val counts = Array(7) { IntArray(24) }
                for ((_, job) in enabled()) for (time in job.cron.fires(first * 1440, (first + 7) * 1440 - 1, holidays)) counts[time / 1440 - first][time % 1440 / 60]++
                listOf("WEEK ${words[1]} ${counts.sumOf { it.sum() }}") + counts.mapIndexed { day, hours ->
                    val heat = hours.map { if (it == 0) '.' else if (it >= 10) '+' else '0' + it }.joinToString("")
                    "${Date.fromNumber(first + day)} $heat ${hours.sum()}"
                }
            }
            "CALENDAR" -> {
                val job = job(words[1]); val first = readMonth(words[2]); val cells = MutableList(first.weekday) { "..." }; var days = 0
                for (day in 1..monthLength(first.year, first.month)) {
                    val date = first.copy(day = day)
                    val mark = if (!job.cron.scheduled(date)) '-' else if (date.number in holidays) 'x' else '*'
                    if (mark == '*') days++
                    cells += fmt("%02d%c", day, mark)
                }
                while (cells.size % 7 != 0) cells += "..."
                listOf("CALENDAR ${words[1]} ${words[2]} days $days runs ${days * job.cron.daily.size}", "Sun Mon Tue Wed Thu Fri Sat") + cells.chunked(7).map { it.joinToString(" ") }
            }
            "EXCLUDE", "INCLUDE" -> {
                val date = readDate(words[1])
                if (command == "EXCLUDE") { if (!holidays.add(date.number)) fail("already excluded") }
                else if (!holidays.remove(date.number)) fail("not excluded")
                listOf("$command $date holidays ${holidays.size}")
            }
            "HOLIDAYS" -> listOf("HOLIDAYS ${holidays.size}") + holidays.map { Date.fromNumber(it).toString() }
            else -> error("unreachable command")
        }
    }
}

fun main() {
    val input = System.`in`.bufferedReader()
    val first = input.readLine() ?: return
    val scheduler = Scheduler()
    val output = System.out.bufferedWriter()
    repeat(first.toInt()) {
        val words = input.readLine().split(' ').filter { it.isNotEmpty() }
        try { for (row in scheduler.execute(words)) { output.write(row); output.write("\n") } }
        catch (error: CommandError) { output.write("ERROR ${error.message}\n") }
    }
    output.flush()
}
