val categories = listOf("VFR", "MVFR", "IFR", "LIFR")

fun covers(f: Forecast, t: Int) = f.issue <= t && f.start <= t - t % 60 && t - t % 60 < f.end

fun chosenForecast(fs: List<Forecast>, t: Int): Forecast? {
    var chosen: Forecast? = null
    for (f in fs) if (covers(f, t) && (chosen == null || f.issue >= chosen.issue)) chosen = f
    return chosen
}

class Contingency {
    val table = Array(4) {
        LongArray(4)
    }
    var temporaryHits = 0L
    fun add(expected: String, observed: String, hit: Boolean) {
        table[categories.indexOf(expected)][categories.indexOf(observed)]++
        if (hit) temporaryHits++
    }
    fun row(i: Int) = table[i].sum()
    fun column(i: Int) = table.sumOf {
        it[i]
    }
    val total get() = table.sumOf {
        it.sum()
    }
    val hits get() = (0..3).sumOf {
        table[it][it]
    }
    val skill: Pair<Long, Long> get() {
        val e = (0..3).sumOf {
            row(it) * column(it)
        }
        return total * hits - e to total * total - e
    }
    fun detection(i: Int) = table[i][i] to column(i)
    fun falseAlarm(i: Int) = row(i) - table[i][i] to row(i)
}
