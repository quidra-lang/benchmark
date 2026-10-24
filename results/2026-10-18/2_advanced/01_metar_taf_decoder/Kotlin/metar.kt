val mainSlots = listOf("modifier", "wind", "variation", "visibility", "rvr", "weather", "cloud", "temperature", "pressure", "no trend")

val trendSlots = listOf("wind", "visibility", "weather", "cloud")

fun repeatable(kind: String) = kind in listOf("rvr", "weather", "cloud")

typealias WordGroup = Pair<Int, String>

class Trend(val kind: String, val times: List<String>, val groups: List<WordGroup>) {
    val section = Section(allowsNsw = true)
}

fun splitMetar(groups: List<WordGroup>): Triple<List<WordGroup>, List<List<WordGroup>>, List<WordGroup>> {
    val r = groups.indexOfFirst {
        it.second == "RMK"
    }.let {
        if (it < 0) groups.size else it
    }
    val before = groups.take(r)
    val remarks = groups.drop(r + 1)
    val t = before.indexOfFirst {
        it.second in listOf("BECMG", "TEMPO")
    }.let {
        if (it < 0) before.size else it
    }
    val trends = mutableListOf<MutableList<WordGroup>>()
    for (g in before.drop(t)) {
        if (g.second in listOf("BECMG", "TEMPO")) trends.add(mutableListOf())
        trends.last().add(g)
    }
    return Triple(before.take(t), trends, remarks)
}

fun readTrend(groups: List<WordGroup>, errors: MutableList<WordGroup>): Trend? {
    fun time(i: Int, prefixes: List<String>) = i < groups.size && captures("(FM|TL|AT)([0-9]{4})", groups[i].second) != null && groups[i].second.take(2) in prefixes
    val count = if (time(1, listOf("FM"))) {
        if (time(2, listOf("TL"))) 2 else 1
    } else if (time(1, listOf("TL", "AT"))) 1 else 0
    val times = mutableListOf<String>()
    for ((position, text) in groups.drop(1).take(count)) {
        if (text.substring(2, 4).toInt() > 23 || text.substring(4).toInt() > 59) {
            errors.add(position to "invalid period \"$text\"")
            return null
        }
        times.add(text)
    }
    return Trend(groups[0].second, times, groups.drop(1 + count))
}

fun readRemarks(groups: List<WordGroup>): Pair<List<Long>, List<Pair<Long, Long>>> {
    val pressures = mutableListOf<Long>()
    val temperatures = mutableListOf<Pair<Long, Long>>()
    for ((_, text) in groups) {
        captures("SLP([0-9]{3})", text)?.let {
            val p = it[0].toLong()
            pressures.add((if (p >= 500) 9000 else 10000) + p)
        }
        captures("T([01])([0-9]{3})([01])([0-9]{3})", text)?.let { m -> temperatures.add(m[1].toLong() * (if (m[0] == "1") -1 else 1) to m[3].toLong() * (if (m[2] == "1") -1 else 1))
        }
    }
    return pressures to temperatures
}
