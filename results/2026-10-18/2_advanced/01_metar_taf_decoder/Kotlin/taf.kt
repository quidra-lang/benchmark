val tafSlots = listOf("wind", "visibility", "weather", "cloud")

val temporaryKinds = listOf("TEMPO", "PROB30", "PROB40", "PROB30 TEMPO", "PROB40 TEMPO")

class Change(val kind: String, val start: Int, val end: Int, val groups: List<WordGroup>) {
    var state = State()
}

class Forecast(val number: Int, val station: Station, val issue: Int, val modifier: String, val start: Int, val end: Int) {
    var base = State()
    var changes: List<Change> = emptyList()
}

fun fmIndicator(t: String) = captures("FM([0-9]{6})", t) != null

fun changeIndicator(t: String) = t in listOf("BECMG", "TEMPO", "PROB30", "PROB40") || fmIndicator(t)

fun parsePeriod(t: String, issueDay: Int, c: Calendar): Pair<Int, Int>? {
    val m = captures("([0-9]{2})([0-9]{2})/([0-9]{2})([0-9]{2})", t) ?: return null
    val n = m.map(String::toInt)
    if (n[1] > 23 || n[3] !in 1..24) return null
    val s = c.forecastTime(n[0], n[1], 0, issueDay) ?: return null
    val e = c.forecastTime(n[2], n[3], 0, issueDay) ?: return null
    return if (s < e) s to e else null
}

fun splitChanges(f: Forecast, groups: List<WordGroup>, c: Calendar, errors: MutableList<WordGroup>): Pair<List<WordGroup>, List<Change>> {
    var i = 0
    while (i < groups.size && !changeIndicator(groups[i].second)) i++
    val base = groups.take(i)
    val changes = mutableListOf<Change>()
    while (i < groups.size) { val indicator = groups[i++]
        var kind = indicator.second
        var start: Int? = null
        var end = 0
        if (kind in listOf("PROB30", "PROB40") && i < groups.size && groups[i].second == "TEMPO") {
            kind += " TEMPO"
            i++
        }
        if (fmIndicator(kind)) {
            val d = kind.substring(2, 4).toInt()
            val h = kind.substring(4, 6).toInt()
            val m = kind.substring(6).toInt()
            start = if (h <= 23 && m <= 59) c.forecastTime(d, h, m, f.issue / 1440 + 1) else null
            if (start == null || start < f.start || start >= f.end) {
                errors.add(indicator.first to "invalid period \"$kind\"")
                start = null
            } else {
                kind = "FM"
                end = start
            }
        } else if (i == groups.size || captures("([0-9]{4})/([0-9]{4})", groups[i].second) == null) {
            errors.add(indicator.first to "missing period \"$kind\"")
        } else {
            val p = groups[i++]
            val period = parsePeriod(p.second, f.issue / 1440 + 1, c)
            if (period == null || period.first < f.start || period.second > f.end) errors.add(p.first to "invalid period \"${p.second}\"")
            else {
                start = period.first
                end = period.second
            }
        }
        val first = i
        while (i < groups.size && !changeIndicator(groups[i].second)) i++
        if (start != null) changes.add(Change(kind, start, end, groups.subList(first, i)))
    }
    return base to changes
}

fun overlay(s: State, c: State) = State(c.wind ?: s.wind, c.visibility ?: s.visibility, c.weather ?: s.weather, c.cloud ?: s.cloud)

fun prevailing(f: Forecast, h: Int): State {
    var state = f.base
    for (c in f.changes) {
        if (c.kind == "FM" && c.start <= h) state = c.state else if (c.kind == "BECMG" && c.end <= h) state = overlay(state, c.state)
    }
    return state
}

fun temporary(f: Forecast, h: Int): List<Pair<String, State>> {
    val p = prevailing(f, h)
    return f.changes.filter {
        it.kind in temporaryKinds && it.start <= h && h < it.end
    }.map {
        it.kind to overlay(p, it.state)
    }
}
