import java.io.File
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

data class Runway(val name: String, val heading: Int)

class Station(val code: String, val elevation: Long, val runways: List<Runway>, val name: String) {
    val title get() = "$code ($name)"
}

class Report(val number: Int, val words: MutableList<String>) {
    val errors = mutableListOf<WordGroup>()
}

data class Header(val kind: String, val station: Station, val time: Int, val start: Int, val end: Int, val modifier: String, val body: List<WordGroup>)

data class RunwayWind(val runway: Runway, val mean: Pair<Long, Long>, val gust: Pair<Long, Long>?, val usable: Boolean)

class Observation(val number: Int, h: Header) {
    val time = h.time
    val kind = h.kind
    val station = h.station
    val main = Section(h.station.runways.map {
        it.name
    })
    val trends = mutableListOf<Trend>()
    var pressures: List<Long> = emptyList()
    var temperatures: List<Pair<Long, Long>> = emptyList()
    var ceilingValue: Long? = null
    var pressureAltitude: Long? = null
    var densityAltitude: Long? = null
    var category = ""
    var winds: List<RunwayWind>? = null
    val reasons = mutableListOf<String>()
}

fun readLines(path: String) = File(path).readLines()

fun joinGroups(words: List<String>, start: Int): List<WordGroup> {
    val result = mutableListOf<WordGroup>()
    var i = start
    while (i < words.size) {
        if (digits(words[i], 1, 1) && i + 1 < words.size && captures("([0-9])/([0-9]{1,2})SM", words[i + 1]) != null) {
            result.add(i + 1 to "${words[i]} ${words[i + 1]}")
            i += 2
        } else {
            result.add(i + 1 to words[i])
            i++
        }
    }
    return result
}

fun parseHeader(r: Report, stations: Map<String, Station>, c: Calendar): Header? {
    val w = r.words
    val kind = w[0]
    fun reject(p: Int, message: String) {
        r.errors.add(p to "rejected report, $message")
    }
    if (kind !in listOf("METAR", "SPECI", "TAF")) {
        reject(1, "invalid type \"$kind\"")
        return null
    }
    var i = 1
    var modifier = ""
    if (kind == "TAF" && i < w.size && w[i] in listOf("AMD", "COR")) modifier = w[i++]
    var station: Station? = null
    var time = 0
    var start = 0
    var end = 0
    for (item in listOf("station", "time") + if (kind == "TAF") listOf("validity") else emptyList()) {
        if (i == w.size) {
            reject(i + 1, "missing $item")
            return null
        }
        val text = w[i]
        var valid = false
        when (item) {
            "station" -> {
                station = stations[text]
                valid = station != null
            }
            "time" -> captures("([0-9]{2})([0-9]{2})([0-9]{2})Z", text)?.let { m ->
                val n = m.map(String::toInt)
                valid = n[0] in 1..c.days && n[1] <= 23 && n[2] <= 59
                if (valid) time = dayMinutes(n[0], n[1], n[2])
            }
            "validity" -> {
                val p = parsePeriod(text, time / 1440 + 1, c)
                valid = p != null && p.second <= p.first + 1800
                if (valid) {
                    start = p!!.first
                    end = p.second
                }
            }
        }
        if (!valid) {
            reject(i + 1, "invalid $item \"$text\"")
            return null
        }
        i++
    }
    return Header(kind, station!!, time, start, end, modifier, joinGroups(w, i))
}

fun matchGroups(groups: List<WordGroup>, slots: List<String>, section: Section, errors: MutableList<WordGroup>) {
    var current = 0
    for ((position, text) in groups) { var index = -1
        var value: Group? = null
        for (j in current until slots.size) {
            value = parseGroup(slots[j], text)
            if (value != null) {
                index = j
                break
            }
        }
        if (index < 0) {
            val earlier = slots.take(current).any {
                parseGroup(it, text) != null
            }
            errors.add(position to "${if (earlier) "out of order group" else "unknown group"} \"$text\"")
            continue
        }
        val g = value!!
        if (!validGroup(g, section)) {
            errors.add(position to "invalid group \"$text\"")
            continue
        }
        section.record(g)
        if (g.kind == "visibility" && g.visibilityKind == "CAVOK") {
            section.state.weather = emptyList()
            section.state.cloud = emptyList()
            current = slots.indexOf("cloud") + 1
        } else current = index + if (repeatable(slots[index])) 0 else 1
    }
}

fun forecastState(groups: List<WordGroup>, nsw: Boolean, errors: MutableList<WordGroup>): State {
    val section = Section(allowsNsw = nsw)
    matchGroups(groups, tafSlots, section, errors)
    return section.state
}

fun decodeObservation(r: Report, h: Header): Observation {
    val o = Observation(r.number, h)
    val (main, trends, remarks) = splitMetar(h.body)
    matchGroups(main, mainSlots, o.main, r.errors)
    for (groups in trends) {
        val t = readTrend(groups, r.errors) ?: continue
        matchGroups(t.groups, trendSlots, t.section, r.errors)
        o.trends.add(t)
    }
    val (pressures, temperatures) = readRemarks(remarks)
    o.pressures = pressures
    o.temperatures = temperatures
    return o
}

fun decodeForecast(r: Report, h: Header, c: Calendar): Forecast {
    val f = Forecast(r.number, h.station, h.time, h.modifier, h.start, h.end)
    val (base, changes) = splitChanges(f, h.body, c, r.errors)
    f.base = forecastState(base, false, r.errors)
    f.changes = changes
    for (change in changes) change.state = forecastState(change.groups, true, r.errors)
    return f
}

fun ceiling(s: State) = s.cloud?.firstOrNull {
    it.amount in listOf("BKN", "OVC", "VV")
}?.height

fun flightCategory(s: State): String {
    val c = ceiling(s)
    val (n, d) = s.visibility?.let(::miles) ?: (1L to 0L)
    return when {
        c != null && c < 500 || n < d -> "LIFR"
        c != null && c < 1000 || n < 3 * d -> "IFR"
        c != null && c <= 3000 || n <= 5 * d -> "MVFR"
        else -> "VFR"
    }
}

fun pressureInhg(g: Group) = if (g.unit == "A") g.pressureValue else inhg(g.pressureValue)

fun components(d: Int, h: Int, w: Long) = floorDiv(w * cosine(d - h), 1000) to floorDiv(w * sine(d - h), 1000)

fun windChanges(a: Group?, b: Group?, alpha: Int): List<String> {
    if (a == null || b == null) return emptyList()
    val result = mutableListOf<String>()
    if (a.directed && b.directed && max(a.speed, b.speed) >= 10) {
        val d = abs(a.direction.toInt() - b.direction.toInt()) % 360
        if (min(d, 360 - d) >= alpha) result.add("wind shift")
    }
    if (abs(a.speed - b.speed) >= 10) result.add("wind speed")
    return result
}

fun thunder(s: State) = s.weather.orEmpty().any {
    it.descriptor == "TS"
}

fun freezing(s: State) = s.weather.orEmpty().any {
    it.descriptor == "FZ" && it.weatherPhenomena.any { p -> p in listOf("DZ", "RA")
    }
}

fun derive(o: Observation, previous: Observation?, crossLimit: Long, tailLimit: Long) {
    val s = o.main.state
    val p = o.main.pressure
    val t = o.main.temperature
    o.ceilingValue = ceiling(s)
    o.category = flightCategory(s)
    if (p != null) {
        val a = o.station.elevation + (2992 - pressureInhg(p)) * 10
        o.pressureAltitude = a
        if (t != null) o.densityAltitude = a + floorDiv(120 * (1000 * t.air - 15000 + 2 * a), 1000)
    }
    val w = s.wind
    if (w != null && w.directed) o.winds = o.station.runways.map { r ->
        val mean = components(w.direction.toInt(), r.heading, w.speed)
        val gust = w.gust?.let {
            components(w.direction.toInt(), r.heading, it)
        }
        val deciding = gust ?: mean
        RunwayWind(r, mean, gust, abs(deciding.second) <= crossLimit && -deciding.first <= tailLimit)
    }
    if (o.kind != "SPECI") return
    if (previous == null) {
        o.reasons.add("no previous report")
        return
    }
    if (previous.category != o.category) o.reasons.add("category ${previous.category} to ${o.category}")
    val before = previous.main.state
    o.reasons.addAll(windChanges(before.wind, s.wind, 45))
    if (thunder(before) != thunder(s)) o.reasons.add("thunderstorm ${if (thunder(s)) "began" else "ended"}")
    if (freezing(before) != freezing(s)) o.reasons.add("freezing precipitation ${if (freezing(s)) "began" else "ended"}")
    if (o.reasons.isEmpty()) o.reasons.add("no criteria met")
}

fun windPhrase(g: Group): String {
    var t = if (g.calm) "calm" else if (g.direction == "VRB") "variable at ${g.speed} KT" else "${g.direction} degrees at ${g.speed} KT"
    if (g.gust != null) t += " gusting ${g.gust} KT"
    return t
}

fun mileNumber(g: Group) = if (g.denominator == 0L) "${g.whole}" else "${if (g.whole == 0L) "" else "${g.whole} "}${g.numerator}/${g.denominator}"

fun qualifier(q: String) = when (q) {
    "M" -> "less than "
    "P" -> "more than "
    else -> ""
}

fun visibilityPhrase(g: Group) = when (g.visibilityKind) {
    "CAVOK" -> "10 km or more (CAVOK)"
    "METERS" -> if (g.qualifier == "P") "10 km or more" else "${g.meters} m"
    else -> "${qualifier(g.qualifier)}${mileNumber(g)} SM"
}

fun weatherPhrase(g: Group): String {
    if (g.text == "NSW") return "no significant weather"
    return listOfNotNull(intensities[g.intensity], descriptors[g.descriptor], g.weatherPhenomena.takeIf {
        it.isNotEmpty()
    }?.joinToString(" and ") {
        phenomena.getValue(it)
    }).joinToString(" ")
}

fun cloudPhrase(g: Group): String {
    clearSkies[g.amount]?.let {
        return it
    }
    if (g.amount == "VV") return "vertical visibility ${g.height} ft"
    return "${amounts[g.amount]} at ${g.height} ft" + when (g.cloudType) {
        "CB" -> " cumulonimbus"
        "TCU" -> " towering cumulus"
        else -> ""
    }
}

fun summary(s: State): String {
    val p = listOfNotNull(s.wind?.let {
        "wind ${windPhrase(it)}"
    }, s.visibility?.let {
        "visibility ${visibilityPhrase(it)}"
    }, s.weather?.takeIf {
        it.isNotEmpty()
    }?.let {
        "weather ${it.joinToString(", ", transform = ::weatherPhrase)}"
    }, s.cloud?.takeIf {
        it.isNotEmpty()
    }?.let {
        "cloud ${it.joinToString(", ", transform = ::cloudPhrase)}"
    })
    return if (p.isEmpty()) "no conditions" else p.joinToString("; ")
}

fun windCode(g: Group) = if (g.calm) "00000KT" else "${g.direction}${pad(g.speed, 2)}${g.gust?.let { "G${pad(it, 2)}" } ?: ""}KT"

fun visibilityCode(g: Group) = when (g.visibilityKind) {
    "CAVOK" -> "CAVOK"
    "METERS" -> if (g.qualifier == "P") "9999" else pad(g.meters, 4)
    else -> "${g.qualifier}${mileNumber(g)}SM"
}

fun tokens(s: State): String {
    val parts = mutableListOf<String>()
    s.wind?.let { parts.add(windCode(it)) }
    s.visibility?.let { parts.add(visibilityCode(it)) }
    parts.addAll(s.weather.orEmpty().filter { it.text != "NSW" }.map { it.text })
    parts.addAll(s.cloud.orEmpty().map { it.text })
    parts.add(flightCategory(s))
    return parts.joinToString(" ")
}

fun tenths(v: Long) = "${if (v < 0) "-" else ""}${abs(v) / 10}.${abs(v) % 10}"

fun inhgText(v: Long) = "${v / 100}.${pad(v % 100, 2)}"

fun componentPhrase(c: Pair<Long, Long>) = "${if (c.first < 0) "tailwind ${-c.first}" else "headwind ${c.first}"} KT, crosswind ${abs(c.second)} KT" + when {
    c.second > 0 -> " from right"
    c.second < 0 -> " from left"
    else -> ""
}

fun rvrPhrase(g: Group): String {
    val readings = g.readings.map { "${qualifier(it.qualifier)}${it.value}" }
    val value = if (readings.size == 1) readings.first() else "between ${readings.first()} and ${readings.last()}"
    val trend = if (g.trend.isEmpty()) "" else ", ${mapOf("U" to "rising", "D" to "falling", "N" to "no change")[g.trend]}"
    return "runway ${g.runway} $value${if (g.feet) " ft" else " m"}$trend"
}

fun altitude(v: Long?) = if (v == null) "not available" else "$v ft"

fun observationLines(o: Observation, c: Calendar): List<String> {
    val m = o.main
    val s = m.state
    val w = s.wind
    val v = s.visibility
    val t = m.temperature
    val p = m.pressure
    val lines = mutableListOf("REPORT ${o.number}: ${o.kind} ${o.station.title}", "  time: ${c.stamp(o.time)}")
    m.modifier?.let {
        lines.add("  modifier: ${if (it.text == "AUTO") "automated" else "corrected"}")
    }
    var wind = w?.let(::windPhrase) ?: "not reported"
    m.variation?.let {
        wind += ", varying between ${pad(it.firstDirection, 3)} and ${pad(it.secondDirection, 3)} degrees"
    }
    lines.addAll(listOf("  wind: $wind", "  visibility: ${v?.let(::visibilityPhrase) ?: "not reported"}"))
    for (g in m.rvrs) lines.add("  runway visual range: ${rvrPhrase(g)}")
    for (g in s.weather.orEmpty()) lines.add("  weather: ${weatherPhrase(g)}")
    val clouds = if (v?.visibilityKind == "CAVOK") listOf("no significant cloud") else s.cloud?.map(::cloudPhrase) ?: listOf("not reported")
    for (text in clouds) lines.add("  cloud: $text")
    lines.add("  temperature: ${t?.let { "${it.air} C, dew point ${it.dewPoint} C, spread ${it.air - it.dewPoint} C" } ?: "not reported"}")
    lines.add("  altimeter: ${p?.let { if (it.unit == "A") "${inhgText(it.pressureValue)} inHg (${hpa(it.pressureValue)} hPa)" else "${it.pressureValue} hPa (${inhgText(pressureInhg(it))} inHg)" } ?: "not reported"}")
    if (m.noTrend != null) lines.add("  trend: no significant change")
    for (trend in o.trends) {
        var text = if (trend.kind == "BECMG") "becoming" else "temporarily"
        for (time in trend.times) text += " ${mapOf("FM" to "from", "TL" to "until", "AT" to "at")[time.take(2)]} ${time.substring(2, 4)}:${time.substring(4)}Z"
        lines.add("  trend: $text: ${summary(trend.section.state)}")
    }
    for (pressure in o.pressures) lines.add("  sea level pressure: ${tenths(pressure)} hPa")
    for ((air, dew) in o.temperatures) lines.add("  precise temperature: ${tenths(air)} C, dew point ${tenths(dew)} C")
    lines.addAll(listOf("  ceiling: ${o.ceilingValue?.let { "$it ft" } ?: "none"}", "  flight category: ${o.category}", "  pressure altitude: ${altitude(o.pressureAltitude)}", "  density altitude: ${altitude(o.densityAltitude)}"))
    val winds = o.winds
    if (winds == null) lines.add("  runway wind: not computed") else {
        var preferred: RunwayWind? = null
        val usable = mutableListOf<String>()
        for (r in winds) {
            lines.add("  runway ${r.runway.name}: ${componentPhrase(r.mean)}${r.gust?.let { "; gusts ${componentPhrase(it)}" } ?: ""}")
            if (r.usable) {
                usable.add(r.runway.name)
                if (preferred == null || r.mean.first > preferred.mean.first) preferred = r
            }
        }
        lines.add("  usable runways: ${if (usable.isEmpty()) "none" else usable.joinToString(" ")}")
        lines.add("  preferred runway: ${preferred?.runway?.name ?: "none"}")
    }
    if (o.kind == "SPECI") lines.add("  speci check: ${o.reasons.joinToString(", ")}")
    return lines
}

fun forecastLines(f: Forecast, c: Calendar): List<String> {
    val lines = mutableListOf("REPORT ${f.number}: TAF ${f.station.title}", "  issued: ${c.stamp(f.issue)}")
    if (f.modifier.isNotEmpty()) lines.add("  modifier: ${if (f.modifier == "AMD") "amended" else "corrected"}")
    lines.addAll(listOf("  valid: ${c.stamp(f.start)} to ${c.stamp(f.end)}", "  base: ${summary(f.base)}"))
    for (g in f.changes) lines.add("  ${g.kind} ${c.stamp(g.start)}${if (g.kind == "FM") "" else " to ${c.stamp(g.end)}"}: ${summary(g.state)}")
    return lines
}

fun categoryCounts(cs: List<String>) = categories.joinToString(", ") { name -> "$name ${cs.count { it == name }}"
}

fun timelineLines(f: Forecast, c: Calendar): List<String> {
    val lines = mutableListOf("TAF ${f.station.code} issued ${c.stamp(f.issue)} valid ${c.stamp(f.start)} to ${c.stamp(f.end)}")
    val cs = mutableListOf<String>()
    for (h in f.start until f.end step 60) {
        val state = prevailing(f, h)
        var line = "${c.stamp(h)} ${tokens(state)}"
        for ((kind, temporary) in temporary(f, h)) line += " | $kind ${tokens(temporary)}"
        lines.add(line)
        cs.add(flightCategory(state))
    }
    lines.add("summary: ${categoryCounts(cs)}")
    return lines
}

fun extremeLines(os: List<Observation>, c: Calendar): List<String> {
    var cold: Observation? = null
    var warm: Observation? = null
    var wind: Observation? = null
    var cloud: Observation? = null
    var vis: Observation? = null
    for (o in os) {
        val t = o.main.temperature
        val w = o.main.state.wind
        val v = o.main.state.visibility
        if (t != null) {
            if (cold == null || t.air < cold.main.temperature!!.air) cold = o
            if (warm == null || t.air > warm.main.temperature!!.air) warm = o
        }
        if (w != null && (wind == null || w.strength > wind.main.state.wind!!.strength)) wind = o
        if (o.ceilingValue != null && (cloud == null || o.ceilingValue!! < cloud.ceilingValue!!)) cloud = o
        if (v != null && (vis == null || lessFraction(miles(v), miles(vis.main.state.visibility!!)))) vis = o
    }
    fun line(label: String, o: Observation?, describe: (Observation) -> String) = "$label: ${o?.let { "${describe(it)} at ${c.stamp(it.time)}" } ?: "not available"}"
    return listOf(line("lowest temperature", cold) {
        "${it.main.temperature!!.air} C"
    }, line("highest temperature", warm) {
        "${it.main.temperature!!.air} C"
    }, line("strongest wind", wind) {
        windPhrase(it.main.state.wind!!)
    }, line("lowest ceiling", cloud) {
        "${it.ceilingValue} ft"
    }, line("lowest visibility", vis) {
        visibilityPhrase(it.main.state.visibility!!)
    })
}

fun tableRow(label: String, cells: List<Any>) = label.padEnd(8) + cells.joinToString("") {
    it.toString().padStart(6)
}

fun verificationLines(station: Station, observations: List<Observation>, forecasts: List<Forecast>, c: Calendar): List<String> {
    val os = observations.filter {
        it.station === station
    }
    val fs = forecasts.filter {
        it.station === station
    }
    val cont = Contingency()
    val amendments = mutableListOf<String>()
    var noForecast = 0
    val pairs = LongArray(5)
    val hits = LongArray(5)
    val lines = mutableListOf("station ${station.title}", "reports: METAR ${os.count { it.kind == "METAR" }}, SPECI ${os.count { it.kind == "SPECI" }}", "observed categories: ${categoryCounts(os.map { it.category })}")
    lines.addAll(extremeLines(os, c))
    for (o in os) {
        val f = chosenForecast(fs, o.time)
        if (f == null) {
            noForecast++
            continue
        }
        val h = o.time - o.time % 60
        val p = prevailing(f, h)
        val expected = flightCategory(p)
        val alternatives = listOf(expected) + temporary(f, h).map {
            flightCategory(it.second)
        }
        val hit = o.category in alternatives
        cont.add(expected, o.category, hit)
        val reasons = mutableListOf<String>()
        if (!hit) reasons.add("category ${o.category}, forecast $expected")
        if (windChanges(p.wind, o.main.state.wind, 60).isNotEmpty()) reasons.add("wind ${windCode(o.main.state.wind!!)}, forecast ${windCode(p.wind!!)}")
        if (reasons.isNotEmpty()) amendments.add("amendment ${c.stamp(o.time)}: ${reasons.joinToString("; ")}")
    }
    for (f in fs) for (o in os) if (covers(f, o.time)) {
        val h = o.time - o.time % 60
        val b = (h - f.start) / 360
        pairs[b]++
        if (flightCategory(prevailing(f, h)) == o.category) hits[b]++
    }
    lines.addAll(listOf("verified: ${cont.total}", "no forecast: $noForecast", tableRow("forecast", categories + "total")))
    for (i in 0..3) lines.add(tableRow(categories[i], cont.table[i].toList() + cont.row(i)))
    lines.add(tableRow("total", (0..3).map(cont::column) + cont.total))
    lines.addAll(listOf("hit rate: ${fraction(cont.hits, cont.total)}", "hit rate with temporary groups: ${fraction(cont.temporaryHits, cont.total)}", "heidke skill score: ${fraction(cont.skill.first, cont.skill.second)}"))
    for (i in 0..3) {
        val pod = cont.detection(i)
        val far = cont.falseAlarm(i)
        lines.add("${categories[i]}: pod ${fraction(pod.first, pod.second)}, far ${fraction(far.first, far.second)}")
    }
    for (b in 0..4) lines.add("hours ${b * 6}-${b * 6 + 5}: ${fraction(hits[b], pairs[b])}")
    return lines + amendments
}

fun blocks(values: List<List<String>>): List<String> {
    val lines = mutableListOf<String>()
    for (value in values) {
        if (lines.isNotEmpty()) lines.add("")
        lines.addAll(value)
    }
    return lines
}

fun writeLines(path: String, lines: List<String>) {
    File(path).writeText(if (lines.isEmpty()) "" else lines.joinToString("\n", postfix = "\n"))
}

fun main() {
    val stations = linkedMapOf<String, Station>()
    for (line in readLines("input/stations.txt")) {
        val p = line.split(' ')
        stations[p[0]] = Station(p[0], p[1].toLong(), p[2].split(',').map {
            val a = it.split('/')
            Runway(a[0], a[1].toInt())
        }, p.drop(3).joinToString(" "))
    }
    val settings = readLines("input/params.txt").associate {
        val p = it.split(' ')
        p[0] to p.drop(1)
    }
    val c = Calendar(settings.getValue("YEAR")[0].toInt(), settings.getValue("MONTH")[0].toInt())
    val cross = settings.getValue("CROSSWIND_LIMIT")[0].toLong()
    val tail = settings.getValue("TAILWIND_LIMIT")[0].toLong()
    val reports = mutableListOf<Report>()
    for (line in readLines("input/reports.txt")) {
        val words = line.trimStart().split(' ')
        if (line.startsWith(' ')) reports.last().words.addAll(words) else reports.add(Report(reports.size + 1, words.toMutableList()))
    }
    val observations = mutableListOf<Observation>()
    val forecasts = mutableListOf<Forecast>()
    val decoded = mutableListOf<List<String>>()
    val latest = mutableMapOf<String, Observation>()
    for (r in reports) {
        val h = parseHeader(r, stations, c) ?: continue
        if (h.kind == "TAF") {
            val f = decodeForecast(r, h, c)
            forecasts.add(f)
            decoded.add(forecastLines(f, c))
        } else {
            val o = decodeObservation(r, h)
            derive(o, latest[h.station.code], cross, tail)
            latest[h.station.code] = o
            observations.add(o)
            decoded.add(observationLines(o, c))
        }
    }
    File("output").mkdirs()
    writeLines("output/decoded.txt", blocks(decoded))
    writeLines("output/categories.csv", listOf("station,time,ceiling,visibility,category") + observations.map { o ->
        val v = o.main.state.visibility;  "${o.station.code},${c.stamp(o.time)},${o.ceilingValue ?: "NONE"},${v?.let { "${it.qualifier}${meterValue(it)}" } ?: "NONE"},${o.category}"
    })
    writeLines("output/taf_timeline.txt", blocks(forecasts.map {
        timelineLines(it, c)
    }))
    writeLines("output/verification.txt", blocks(settings.getValue("VERIFY").map {
        verificationLines(stations.getValue(it), observations, forecasts, c)
    }))
    writeLines("output/errors.txt", reports.flatMap { r -> r.errors.sortedBy {
            it.first
        }.map {
            "report ${r.number} word ${it.first}: ${it.second}"
        }
    })
}
