import java.util.Locale

private val methods = listOf("GET", "HEAD", "POST", "PUT", "DELETE", "PATCH", "OPTIONS")
private val reasons = listOf("fields", "date", "time", "ip", "method", "path", "status", "bytes", "latency")
private val statusClasses = listOf("1xx", "2xx", "3xx", "4xx", "5xx")
private val filterKeys = listOf("METHOD", "STATUS", "IP", "PATH")
private val monthLengths = listOf(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
private val forms = mapOf(
    "SUMMARY" to emptyList(), "MALFORMED" to emptyList(),
    "STATUS" to emptyList(), "METHODS" to emptyList(),
    "TOP" to listOf("kind", "limit"), "HOURLY" to emptyList(),
    "TIMELINE" to listOf("minutes"), "BANDWIDTH" to emptyList(),
    "VISITORS" to emptyList(), "LATENCY" to listOf("path"),
    "HISTOGRAM" to listOf("width"), "APDEX" to listOf("threshold"),
    "ERRORS" to emptyList(), "SLOWEST" to listOf("limit"),
    "SESSIONS" to listOf("ip", "minutes"), "BURST" to listOf("length", "times"),
    "PEAK" to listOf("length"), "GAPS" to listOf("length"),
    "IP" to listOf("ip"), "RANGE" to listOf("date", "time", "date", "time"),
    "FILTER" to listOf("key", "value"), "UNFILTER" to listOf("subject"),
    "RESET" to emptyList(), "STATE" to emptyList()
)
private val requireRecords = setOf(
    "STATUS", "METHODS", "TOP", "HOURLY", "TIMELINE", "BANDWIDTH",
    "VISITORS", "HISTOGRAM", "APDEX", "ERRORS", "SLOWEST", "BURST", "PEAK", "GAPS"
)
private val ranges = mapOf(
    "limit" to (1..100), "minutes" to (1..1440),
    "width" to (1..100000), "threshold" to (1..100000),
    "length" to (1..86400), "times" to (1..1000)
)
private val errors = mapOf(
    "limit" to "invalid number", "minutes" to "invalid number",
    "width" to "invalid number", "threshold" to "invalid number",
    "length" to "invalid number", "times" to "invalid number",
    "kind" to "invalid kind", "path" to "invalid path", "ip" to "invalid ip",
    "date" to "invalid timestamp", "time" to "invalid timestamp",
    "key" to "invalid key", "subject" to "invalid key", "value" to "invalid value"
)
private val integerPattern = Regex("[0-9]+")
private val datePattern = Regex("[0-9]{4}-[0-9]{2}-[0-9]{2}")
private val timePattern = Regex("[0-9]{2}:[0-9]{2}:[0-9]{2}")
private val statusPattern = Regex("[0-9]{3}")
private val hexPattern = Regex("[0-9a-f]+")
private val digitPattern = Regex("[0-9]")

private class QueryError(message: String) : RuntimeException(message)

private fun requireValue(value: Boolean, message: String) {
    if (!value) throw QueryError(message)
}

private fun tokens(line: String): List<String> =
    line.trim().takeIf { it.isNotEmpty() }?.split(Regex("\\s+")) ?: emptyList()

private fun canonical(text: String, max: Int): Boolean =
    text.isNotEmpty() && text.length <= max && integerPattern.matches(text) &&
        (text.length == 1 || text[0] != '0')

private fun leap(year: Int): Boolean =
    year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)

private fun daysInYear(year: Int): Int = if (leap(year)) 366 else 365
private fun daysInMonth(year: Int, month: Int): Int =
    if (month == 2 && leap(year)) 29 else monthLengths[month - 1]

private fun validDate(s: String): Boolean {
    if (!datePattern.matches(s)) return false
    val year = s.substring(0, 4).toInt()
    val month = s.substring(5, 7).toInt()
    val day = s.substring(8, 10).toInt()
    return year in 2000..2059 && month in 1..12 &&
        day in 1..daysInMonth(year, month)
}

private fun validTime(s: String): Boolean =
    timePattern.matches(s) && s.substring(0, 2).toInt() < 24 &&
        s.substring(3, 5).toInt() < 60 && s.substring(6, 8).toInt() < 60

private fun validIp(s: String): Boolean {
    val parts = s.split('.')
    return parts.size == 4 && parts.all { canonical(it, 3) && it.toInt() <= 255 }
}

private fun validStatus(s: String): Boolean =
    statusPattern.matches(s) && s.toInt() in 100..599

private fun validFilterValue(key: String, value: String): Boolean = when (key) {
    "METHOD" -> value in methods
    "STATUS" -> value in statusClasses || validStatus(value)
    "IP" -> validIp(value)
    else -> value.startsWith("/")
}

private fun validArgument(kind: String, text: String, args: List<String>): Boolean {
    ranges[kind]?.let { return canonical(text, 6) && text.toInt() in it }
    return when (kind) {
        "kind" -> text == "PATHS" || text == "IPS"
        "path" -> text.startsWith("/")
        "ip" -> validIp(text)
        "date" -> validDate(text)
        "time" -> validTime(text)
        "key" -> text in filterKeys
        "subject" -> text == "RANGE" || text in filterKeys
        else -> validFilterValue(args[0], text)
    }
}

private fun malformedReason(fields: List<String>): String? {
    if (fields.size != 8) return "fields"
    if (!validDate(fields[0])) return "date"
    if (!validTime(fields[1])) return "time"
    if (!validIp(fields[2])) return "ip"
    if (fields[3] !in methods) return "method"
    if (!fields[4].startsWith("/")) return "path"
    if (!validStatus(fields[5])) return "status"
    if (!canonical(fields[6], 8)) return "bytes"
    if (!canonical(fields[7], 6)) return "latency"
    return null
}

private fun secondsOf(date: String, clock: String): Long {
    val year = date.substring(0, 4).toInt()
    val month = date.substring(5, 7).toInt()
    var day = date.substring(8, 10).toLong() - 1
    for (y in 2000 until year) day += daysInYear(y)
    for (m in 1 until month) day += daysInMonth(year, m)
    return day * 86400 + clock.substring(0, 2).toLong() * 3600 +
        clock.substring(3, 5).toLong() * 60 + clock.substring(6, 8).toLong()
}

private fun pad(n: Long) = n.toString().padStart(2, '0')

private fun intervalLabel(seconds: Long): String {
    var days = seconds / 86400
    val minutes = seconds % 86400 / 60
    var year = 2000
    while (days >= daysInYear(year)) days -= daysInYear(year++)
    var month = 1
    while (days >= daysInMonth(year, month)) days -= daysInMonth(year, month++)
    return year.toString() + "-" + pad(month.toLong()) + "-" + pad(days + 1) +
        " " + pad(minutes / 60) + ":" + pad(minutes % 60)
}

private fun normalizePath(value: String): String {
    val parts = mutableListOf<String>()
    for (part in value.substringBefore('?').split('/')) {
        when (part) {
            ".." -> if (parts.isNotEmpty()) parts.removeAt(parts.lastIndex)
            "", "." -> {}
            else -> parts.add(part)
        }
    }
    return "/" + parts.joinToString("/") {
        when {
            integerPattern.matches(it) -> "{id}"
            it.length >= 8 && hexPattern.matches(it) &&
                digitPattern.containsMatchIn(it) -> "{hex}"
            else -> it
        }
    }
}

private fun compareIp(a: String, b: String): Int {
    val left = a.split('.').map { it.toInt() }
    val right = b.split('.').map { it.toInt() }
    for (i in 0..3) if (left[i] != right[i]) return left[i].compareTo(right[i])
    return 0
}

private fun statusMatches(filter: String, value: Int): Boolean =
    if (filter in statusClasses) value / 100 == filter[0].digitToInt()
    else value == filter.toInt()

private fun decimal(numerator: Long, denominator: Long, places: Int): String {
    val factor = when (places) { 1 -> 10L; 2 -> 100L; else -> 1000L }
    val scaled = numerator * factor / denominator
    return (scaled / factor).toString() + "." +
        (scaled % factor).toString().padStart(places, '0')
}

private fun percent(part: Int, whole: Int): String =
    decimal(part.toLong() * 100, whole.toLong(), 2) + "%"

private fun bar(count: Int, maximum: Int): String =
    "#".repeat((count * 30 + maximum - 1) / maximum)

private fun bytesText(n: Long): String = when {
    n >= 1073741824 -> decimal(n, 1073741824, 1) + "GB"
    n >= 1048576 -> decimal(n, 1048576, 1) + "MB"
    n >= 1024 -> decimal(n, 1024, 1) + "KB"
    else -> n.toString() + "B"
}

private fun <T> frequency(values: Iterable<T>): Map<T, Int> {
    val result = mutableMapOf<T, Int>()
    for (v in values) result[v] = result.getOrDefault(v, 0) + 1
    return result
}

private fun ranked(
    counts: Map<String, Int>,
    compare: Comparator<String> = Comparator.naturalOrder()
): List<String> = counts.keys.sortedWith { a, b ->
    val n = counts.getValue(b).compareTo(counts.getValue(a))
    if (n != 0) n else compare.compare(a, b)
}

private data class Record(
    val line: Int, val date: String, val timestamp: String, val hour: Int,
    val seconds: Long, val ip: String, val method: String, val path: String,
    val status: Int, val size: Long, val latency: Int
) {
    constructor(line: Int, f: List<String>) : this(
        line, f[0], f[0] + " " + f[1], f[1].substring(0, 2).toInt(),
        secondsOf(f[0], f[1]), f[2], f[3], normalizePath(f[4]),
        f[5].toInt(), f[6].toLong(), f[7].toInt()
    )
}

private fun classCounts(records: List<Record>): IntArray {
    val result = IntArray(5)
    for (r in records) result[r.status / 100 - 1]++
    return result
}

private data class Buckets(val first: Long, val counts: IntArray)

private fun buckets(values: List<Long>): Buckets {
    val first = values.min()
    val span = values.max() - first + 1
    requireValue(span <= 60, "too many buckets")
    val counts = IntArray(span.toInt())
    for (v in values) counts[(v - first).toInt()]++
    return Buckets(first, counts)
}

private fun percentile(values: List<Int>, rank: Int): Int =
    values[(rank * values.size + 99) / 100 - 1]

private data class Window(val count: Int, val first: Record, val last: Record)

private fun windowPeak(records: List<Record>, length: Int): Window {
    var begin = 0
    var count = 0
    var first = 0
    var last = 0
    for (i in records.indices) {
        while (records[i].seconds - records[begin].seconds >= length) begin++
        if (i - begin + 1 > count) {
            count = i - begin + 1
            first = begin
            last = i
        }
    }
    return Window(count, records[first], records[last])
}

private data class Apdex(
    val count: Int, val satisfied: Int, val tolerating: Int, val frustrated: Int,
    val points: Long, val total: Long, val text: String, val rating: String
)

private fun apdex(records: List<Record>, threshold: Int): Apdex {
    val satisfied = records.count { it.status < 500 && it.latency <= threshold }
    val tolerating = records.count {
        it.status < 500 && it.latency > threshold && it.latency <= threshold * 4
    }
    val n = records.size
    val points = satisfied * 2L + tolerating
    val total = n * 2L
    val rating = when {
        100 * points >= 94 * total -> "excellent"
        100 * points >= 85 * total -> "good"
        100 * points >= 70 * total -> "fair"
        100 * points >= 50 * total -> "poor"
        else -> "unacceptable"
    }
    return Apdex(n, satisfied, tolerating, n - satisfied - tolerating,
        points, total, decimal(points, total, 3), rating)
}

private class LogAnalyzer(lines: List<String>) {
    private val records = mutableListOf<Record>()
    private val malformed = mutableListOf<Pair<Int, String>>()
    private val lineCount = lines.size
    private val filters = mutableMapOf<String, String?>(
        "METHOD" to null, "STATUS" to null, "IP" to null, "PATH" to null
    )
    private var from: Long? = null
    private var until: Long? = null
    private var fromText: String? = null
    private var untilText: String? = null
    val output = mutableListOf<String>()

    init {
        lines.forEachIndexed { index, line ->
            val values = tokens(line)
            val reason = malformedReason(values)
            if (reason != null) malformed.add(index + 1 to reason)
            else records.add(Record(index + 1, values))
        }
        records.sortWith(compareBy<Record> { it.seconds }.thenBy { it.line })
    }

    private fun emit(vararg parts: Any) {
        output.add(parts.joinToString(" "))
    }

    private fun selected(): List<Record> = records.filter { r ->
        (from == null || r.seconds >= from!! && r.seconds <= until!!) &&
            (filters["METHOD"] == null || r.method == filters["METHOD"]) &&
            (filters["STATUS"] == null || statusMatches(filters["STATUS"]!!, r.status)) &&
            (filters["IP"] == null || r.ip == filters["IP"]) &&
            (filters["PATH"] == null || r.path == filters["PATH"])
    }

    private fun barLine(label: String, count: Int, maximum: Int) {
        if (count > 0) emit(label, count, bar(count, maximum))
        else emit(label, count)
    }

    fun execute(line: String) {
        val fields = tokens(line)
        val name = fields.firstOrNull() ?: ""
        val args = fields.drop(1)
        try {
            requireValue(name in forms, "unknown query")
            val expected = forms.getValue(name)
            val optional = (name == "LATENCY" || name == "SESSIONS") &&
                args.size == expected.size - 1
            requireValue(args.size == expected.size || optional, "wrong arguments")
            args.forEachIndexed { i, value ->
                requireValue(validArgument(expected[i], value, args),
                    errors.getValue(expected[i]))
            }
            val rows = selected()
            if (name in requireRecords && rows.isEmpty()) {
                emit(name, "no records")
                return
            }
            run(name, args, rows)
        } catch (error: QueryError) {
            emit("ERROR", error.message ?: "")
        }
    }

    private fun run(name: String, args: List<String>, rows: List<Record>) {
        when (name) {
            "SUMMARY" -> {
                emit("SUMMARY", "lines", lineCount, "valid", records.size,
                    "malformed", malformed.size)
                emit("requests", rows.size, "bytes", rows.sumOf { it.size },
                    "ips", rows.map { it.ip }.toSet().size,
                    "paths", rows.map { it.path }.toSet().size)
                if (rows.isEmpty()) emit("span", "none")
                else emit("span", rows.first().timestamp, rows.last().timestamp,
                    rows.last().seconds - rows.first().seconds)
            }
            "MALFORMED" -> {
                emit("MALFORMED", malformed.size)
                for (reason in reasons) {
                    val matching = malformed.filter { it.second == reason }.map { it.first }
                    if (matching.isNotEmpty()) emit(reason, matching.size, *matching.toTypedArray())
                }
            }
            "STATUS" -> {
                emit("STATUS", rows.size)
                val category = classCounts(rows)
                for (i in 0..4) emit(statusClasses[i], category[i], percent(category[i], rows.size))
                val statuses = frequency(rows.map { it.status })
                for (s in statuses.keys.sorted())
                    emit(s, statuses.getValue(s), percent(statuses.getValue(s), rows.size))
            }
            "METHODS" -> {
                emit("METHODS", rows.size)
                val counts = frequency(rows.map { it.method })
                for (method in ranked(counts))
                    emit(method, counts.getValue(method), percent(counts.getValue(method), rows.size))
            }
            "TOP" -> {
                val kind = args[0]
                val counts = frequency(rows.map { if (kind == "PATHS") it.path else it.ip })
                val keys = ranked(counts, if (kind == "IPS") Comparator { a, b ->
                    compareIp(a, b)
                } else Comparator.naturalOrder())
                val shown = minOf(args[1].toInt(), keys.size)
                emit("TOP", kind, shown, "of", keys.size)
                var rank = 0
                for (i in 0 until shown) {
                    if (i == 0 || counts[keys[i]] != counts[keys[i - 1]]) rank = i + 1
                    emit(rank, keys[i], counts.getValue(keys[i]),
                        percent(counts.getValue(keys[i]), rows.size))
                }
            }
            "HOURLY" -> {
                val counts = IntArray(24)
                for (r in rows) counts[r.hour]++
                val maximum = counts.max()
                emit("HOURLY", rows.size, "peak", pad(counts.indexOf(maximum).toLong()), maximum)
                for (i in counts.indices) barLine(pad(i.toLong()), counts[i], maximum)
            }
            "TIMELINE" -> {
                val minutes = args[0].toInt()
                val width = minutes * 60L
                val buckets = buckets(rows.map { it.seconds / width })
                emit("TIMELINE", minutes, buckets.counts.size)
                val maximum = buckets.counts.max()
                buckets.counts.forEachIndexed { i, n ->
                    barLine(intervalLabel((buckets.first + i) * width), n, maximum)
                }
            }
            "BANDWIDTH" -> {
                val byDate = rows.groupBy { it.date }
                val size = rows.sumOf { it.size }
                emit("BANDWIDTH", byDate.size, size, bytesText(size))
                for (date in byDate.keys.sorted()) {
                    val records = byDate.getValue(date)
                    val total = records.sumOf { it.size }
                    emit(date, records.size, total, bytesText(total))
                }
            }
            "VISITORS" -> {
                val firstDates = mutableMapOf<String, String>()
                for (r in rows) {
                    if (firstDates[r.ip] == null || r.date < firstDates.getValue(r.ip))
                        firstDates[r.ip] = r.date
                }
                val byDate = rows.groupBy { it.date }
                emit("VISITORS", byDate.size, firstDates.size)
                for (date in byDate.keys.sorted()) {
                    val ips = byDate.getValue(date).map { it.ip }.toSet()
                    val fresh = ips.count { firstDates[it] == date }
                    emit(date, "unique", ips.size, "new", fresh,
                        "returning", ips.size - fresh)
                }
            }
            "LATENCY" -> {
                val label = if (args.isEmpty()) "all" else normalizePath(args[0])
                val chosen = if (args.isEmpty()) rows else rows.filter { it.path == label }
                if (chosen.isEmpty()) {
                    emit("LATENCY", "no records")
                } else {
                    val values = chosen.map { it.latency }.sorted()
                    val count = values.size
                    val trim = count / 10
                    val trimmed = values.subList(trim, count - trim)
                    emit("LATENCY", label, "count", count, "min", values.first(),
                        "p50", percentile(values, 50), "p90", percentile(values, 90),
                        "p99", percentile(values, 99), "max", values.last(),
                        "mean", decimal(values.sumOf { it.toLong() }, count.toLong(), 2),
                        "trimmed", decimal(trimmed.sumOf { it.toLong() }, trimmed.size.toLong(), 2))
                }
            }
            "HISTOGRAM" -> {
                val width = args[0].toInt()
                val buckets = buckets(rows.map { (it.latency / width).toLong() })
                emit("HISTOGRAM", width, buckets.counts.size)
                val maximum = buckets.counts.max()
                buckets.counts.forEachIndexed { i, n ->
                    val start = (buckets.first + i) * width
                    barLine(start.toString() + "-" + (start + width - 1), n, maximum)
                }
            }
            "APDEX" -> {
                val threshold = args[0].toInt()
                val overall = apdex(rows, threshold)
                emit("APDEX", threshold, overall.text, overall.rating, "satisfied",
                    overall.satisfied, "tolerating", overall.tolerating,
                    "frustrated", overall.frustrated)
                val paths = rows.groupBy { it.path }.map { (path, group) ->
                    path to apdex(group, threshold)
                }.sortedWith { a, b ->
                    val ratio = (a.second.points * b.second.total)
                        .compareTo(b.second.points * a.second.total)
                    if (ratio != 0) ratio
                    else {
                        val count = b.second.count.compareTo(a.second.count)
                        if (count != 0) count else a.first.compareTo(b.first)
                    }
                }
                for ((path, score) in paths) emit(path, score.text, score.rating, score.count)
            }
            "ERRORS" -> {
                val failed = rows.count { it.status >= 400 }
                emit("ERRORS", failed, "of", rows.size, percent(failed, rows.size))
                data class Info(val path: String, val count: Int, val client: Int, val server: Int)
                val result = rows.groupBy { it.path }.map { (path, group) ->
                    Info(path, group.size, group.count { it.status / 100 == 4 },
                        group.count { it.status / 100 == 5 })
                }.filter { it.client + it.server > 0 }.sortedWith { a, b ->
                    val ax = a.client + a.server
                    val bx = b.client + b.server
                    val ratio = (bx.toLong() * a.count).compareTo(ax.toLong() * b.count)
                    if (ratio != 0) ratio
                    else {
                        val count = bx.compareTo(ax)
                        if (count != 0) count else a.path.compareTo(b.path)
                    }
                }
                for (info in result) {
                    emit(info.path, info.count, info.client, info.server,
                        percent(info.client + info.server, info.count))
                }
            }
            "SLOWEST" -> {
                data class Endpoint(
                    val method: String, val path: String, val count: Int,
                    val sum: Long, val maximum: Int
                )
                val result = rows.groupBy { it.method to it.path }.map { (key, group) ->
                    Endpoint(key.first, key.second, group.size,
                        group.sumOf { it.latency.toLong() }, group.maxOf { it.latency })
                }.sortedWith { a, b ->
                    val avg = (b.sum * a.count).compareTo(a.sum * b.count)
                    if (avg != 0) avg
                    else {
                        val max = b.maximum.compareTo(a.maximum)
                        if (max != 0) max
                        else {
                            val path = a.path.compareTo(b.path)
                            if (path != 0) path else a.method.compareTo(b.method)
                        }
                    }
                }
                val limit = minOf(args[0].toInt(), result.size)
                emit("SLOWEST", limit, "of", result.size)
                for ((i, item) in result.take(limit).withIndex()) {
                    emit(i + 1, item.method, item.path, "count", item.count,
                        "avg", decimal(item.sum, item.count.toLong(), 2), "max", item.maximum)
                }
            }
            "SESSIONS" -> {
                val ip = args[0]
                val minutes = if (args.size == 2) args[1].toInt() else 30
                val chosen = rows.filter { it.ip == ip }
                if (chosen.isEmpty()) {
                    emit("SESSIONS", "no records")
                } else {
                    val sessions = mutableListOf(mutableListOf(chosen.first()))
                    for (i in 1 until chosen.size) {
                        if (chosen[i].seconds - chosen[i - 1].seconds <= minutes * 60L)
                            sessions.last().add(chosen[i])
                        else sessions.add(mutableListOf(chosen[i]))
                    }
                    val duration = sessions.sumOf { it.last().seconds - it.first().seconds }
                    emit("SESSIONS", ip, "timeout", minutes, "count", sessions.size,
                        "requests", chosen.size, "avg_duration",
                        decimal(duration, sessions.size.toLong(), 1),
                        "avg_requests", decimal(chosen.size.toLong(), sessions.size.toLong(), 1))
                    for ((i, session) in sessions.withIndex()) {
                        emit(i + 1, session.first().timestamp, session.last().timestamp,
                            session.last().seconds - session.first().seconds,
                            session.size, session.map { it.path }.toSet().size)
                    }
                }
            }
            "BURST" -> {
                val length = args[0].toInt()
                val threshold = args[1].toInt()
                val bursts = rows.filter { it.status >= 400 }.groupBy { it.ip }
                    .map { (ip, group) -> ip to windowPeak(group, length) }
                    .filter { it.second.count >= threshold }
                    .sortedWith { a, b ->
                        val count = b.second.count.compareTo(a.second.count)
                        if (count != 0) count else compareIp(a.first, b.first)
                    }
                emit("BURST", length, threshold, bursts.size)
                for ((ip, window) in bursts) {
                    emit(ip, window.count, window.first.timestamp, window.last.timestamp)
                }
            }
            "PEAK" -> {
                val length = args[0].toInt()
                val peak = windowPeak(rows, length)
                emit("PEAK", length, peak.count, peak.first.timestamp, peak.last.timestamp)
            }
            "GAPS" -> {
                val length = args[0].toLong()
                val gaps = mutableListOf<Pair<Record, Record>>()
                for (i in 1 until rows.size) {
                    if (rows[i].seconds - rows[i - 1].seconds >= length)
                        gaps.add(rows[i - 1] to rows[i])
                }
                emit("GAPS", length, gaps.size)
                for ((start, end) in gaps)
                    emit(start.timestamp, end.timestamp, end.seconds - start.seconds)
            }
            "IP" -> {
                val ip = args[0]
                val found = rows.filter { it.ip == ip }
                if (found.isEmpty()) {
                    emit("IP", "no records")
                } else {
                    val counts = frequency(found.map { it.path })
                    emit("IP", ip, "requests", found.size, "bytes",
                        found.sumOf { it.size }, "errors", found.count { it.status >= 400 },
                        "paths", counts.size)
                    emit("first", found.first().timestamp, "last", found.last().timestamp)
                    val methods = frequency(found.map { it.method })
                    val methodParts = mutableListOf<Any>("methods")
                    for (method in ranked(methods)) {
                        methodParts.add(method)
                        methodParts.add(methods.getValue(method))
                    }
                    emit(*methodParts.toTypedArray())
                    val categories = classCounts(found)
                    val parts = mutableListOf<Any>("classes")
                    for (i in categories.indices) {
                        parts.add(statusClasses[i])
                        parts.add(categories[i])
                    }
                    emit(*parts.toTypedArray())
                    for (path in ranked(counts).take(3))
                        emit("path", path, counts.getValue(path))
                }
            }
            "RANGE" -> {
                val start = secondsOf(args[0], args[1])
                val end = secondsOf(args[2], args[3])
                requireValue(start <= end, "invalid range")
                from = start
                until = end
                fromText = args[0] + " " + args[1]
                untilText = args[2] + " " + args[3]
                emit("RANGE", fromText!!, untilText!!, "active", selected().size)
            }
            "FILTER" -> {
                val key = args[0]
                val value = if (key == "PATH") normalizePath(args[1]) else args[1]
                filters[key] = value
                emit("FILTER", key, value, "active", selected().size)
            }
            "UNFILTER" -> {
                val key = args[0]
                if (key == "RANGE") {
                    requireValue(from != null, "not filtered")
                    from = null
                    until = null
                    fromText = null
                    untilText = null
                } else {
                    requireValue(filters[key] != null, "not filtered")
                    filters[key] = null
                }
                emit("UNFILTER", key, "active", selected().size)
            }
            "RESET" -> {
                from = null
                until = null
                fromText = null
                untilText = null
                for (key in filterKeys) filters[key] = null
                emit("RESET", "active", selected().size)
            }
            "STATE" -> {
                val parts = mutableListOf<Any>("STATE", "active", rows.size,
                    "range", if (from == null) "-" else fromText!! + " " + untilText!!)
                for (key in filterKeys) {
                    parts.add(key.lowercase(Locale.ROOT))
                    parts.add(filters[key] ?: "-")
                }
                emit(*parts.toTypedArray())
            }
        }
    }
}

fun main() {
    val input = generateSequence(::readLine).toList()
    val separator = input.indexOf("---")
    val end = input.indexOf("END")
    val analyzer = LogAnalyzer(input.subList(0, separator))
    for (i in separator + 1 until end) analyzer.execute(input[i])
    if (analyzer.output.isNotEmpty()) println(analyzer.output.joinToString("\n"))
}
