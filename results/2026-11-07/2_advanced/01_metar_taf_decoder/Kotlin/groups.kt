val descriptors = mapOf("MI" to "shallow", "BC" to "patches", "PR" to "partial", "DR" to "low drifting", "BL" to "blowing", "SH" to "showers", "TS" to "thunderstorm", "FZ" to "freezing")

val phenomena = mapOf("DZ" to "drizzle", "RA" to "rain", "SN" to "snow", "SG" to "snow grains", "IC" to "ice crystals", "PL" to "ice pellets", "GR" to "hail", "GS" to "small hail", "UP" to "unknown precipitation", "BR" to "mist", "FG" to "fog", "FU" to "smoke", "VA" to "volcanic ash", "DU" to "dust", "SA" to "sand", "HZ" to "haze", "PY" to "spray", "PO" to "dust whirls", "SQ" to "squalls", "FC" to "funnel cloud", "SS" to "sandstorm", "DS" to "duststorm")

val precipitation = setOf("DZ", "RA", "SN", "SG", "IC", "PL", "GR", "GS", "UP")

val amounts = mapOf("FEW" to "few", "SCT" to "scattered", "BKN" to "broken", "OVC" to "overcast")

val clearSkies = mapOf("SKC" to "sky clear", "CLR" to "clear below 12000 ft", "NSC" to "no significant cloud")

val intensities = mapOf("-" to "light", "+" to "heavy", "VC" to "nearby")

data class Reading(val qualifier: String, val value: Long)

data class Group(
    val text: String,
    val kind: String,
    val direction: String = "",
    val speed: Long = 0,
    val gust: Long? = null,
    val unit: String = "",
    val firstDirection: Long = 0,
    val secondDirection: Long = 0,
    val visibilityKind: String = "",
    val qualifier: String = "",
    val meters: Long = 0,
    val whole: Long = 0,
    val numerator: Long = 0,
    val denominator: Long = 0,
    val joined: Boolean = false,
    val runway: String = "",
    val readings: List<Reading> = emptyList(),
    val feet: Boolean = false,
    val trend: String = "",
    val intensity: String = "",
    val codes: List<String> = emptyList(),
    val amount: String = "",
    val height: Long = 0,
    val cloudType: String = "",
    val air: Long = 0,
    val dewPoint: Long = 0,
    val pressureValue: Long = 0,
) {
    val calm get() = kind == "wind" && direction == "000"
    val directed get() = kind == "wind" && direction != "VRB" && !calm
    val strength get() = gust ?: speed
    val descriptor get() = codes.firstOrNull()?.takeIf { it in descriptors } ?: ""
    val weatherPhenomena get() = codes.filter { it in phenomena }
}

data class State(var wind: Group? = null, var visibility: Group? = null, var weather: List<Group>? = null, var cloud: List<Group>? = null)

class Section(val runways: List<String> = emptyList(), val allowsNsw: Boolean = false) {
    val state = State()
    var modifier: Group? = null
    var variation: Group? = null
    var temperature: Group? = null
    var pressure: Group? = null
    var noTrend: Group? = null
    val rvrs = mutableListOf<Group>()
    fun record(g: Group) {
        when (g.kind) {
            "wind" -> state.wind = g.copy(
                unit = "KT", speed = knots(g.speed, g.unit),
                gust = g.gust?.let { knots(it, g.unit) }
            )
            "visibility" -> state.visibility = g
            "weather" -> state.weather = (state.weather ?: emptyList()) + g
            "cloud" -> state.cloud = (state.cloud ?: emptyList()) + g
            "modifier" -> modifier = g
            "variation" -> variation = g
            "temperature" -> temperature = g
            "pressure" -> pressure = g
            "no trend" -> noTrend = g
            "rvr" -> rvrs.add(g)
        }
    }
}

fun captures(pattern: String, text: String): List<String>? = Regex(pattern).matchEntire(text)?.groupValues?.drop(1)

fun digits(text: String, a: Int, b: Int) = text.length in a..b && text.all { it in '0'..'9'
}

fun parseGroup(kind: String, t: String): Group? {
    when (kind) {
        "modifier" -> if (t in listOf("AUTO", "COR")) return Group(t, kind)
        "no trend" -> if (t == "NOSIG") return Group(t, kind)
        "wind" -> captures("(VRB|[0-9]{3})([0-9]{2,3})(?:G([0-9]{2,3}))?(KT|MPS)", t)?.let { m ->
            return Group(t, kind, direction = m[0], speed = m[1].toLong(), gust = m[2].toLongOrNull(), unit = m[3])
        }
        "variation" -> captures("([0-9]{3})V([0-9]{3})", t)?.let { m ->
            return Group(t, kind, firstDirection = m[0].toLong(), secondDirection = m[1].toLong())
        }
        "visibility" -> {
            if (t == "CAVOK") return Group(t, kind, visibilityKind = "CAVOK", qualifier = "P", meters = 10000)
            if (digits(t, 4, 4)) return Group(t, kind, visibilityKind = "METERS", qualifier = if (t == "9999") "P" else "", meters = if (t == "9999") 10000 else t.toLong())
            captures("([0-9]) ([0-9])/([0-9]{1,2})SM", t)?.let { m ->
                return Group(t, kind, visibilityKind = "MILES", joined = true, whole = m[0].toLong(), numerator = m[1].toLong(), denominator = m[2].toLong())
            }
            captures("([MP]?)(?:([0-9]{1,2})|([0-9])/([0-9]{1,2}))SM", t)?.let { m ->
                return Group(t, kind, visibilityKind = "MILES", qualifier = m[0], whole = m[1].toLongOrNull() ?: 0, numerator = m[2].toLongOrNull() ?: 0, denominator = m[3].toLongOrNull() ?: 0)
            }
        }
        "rvr" -> captures("R([0-9]{2}[LCR]?)/([MP]?)([0-9]{4})(?:V([MP]?)([0-9]{4}))?(FT)?([UDN]?)", t)?.let { m ->
            val readings = listOf(Reading(m[1], m[2].toLong())) + if (m[4].isEmpty()) emptyList() else listOf(Reading(m[3], m[4].toLong()))
            return Group(t, kind, runway = m[0], readings = readings, feet = m[5] == "FT", trend = m[6])
        }
        "weather" -> {
            if (t == "NSW") return Group(t, kind)
            captures("(-|\\+|VC)?([A-Z]+)", t)?.let { m ->
                val codes = m[1].chunked(2)
                if (m[1].length % 2 == 0 && codes.all { it in descriptors || it in phenomena }) return Group(t, kind, intensity = m[0], codes = codes)
            }
        }
        "cloud" -> {
            if (t in clearSkies) return Group(t, kind, amount = t)
            captures("(FEW|SCT|BKN|OVC|VV)([0-9]{3})(CB|TCU)?", t)?.let { m ->
                if (m[0] != "VV" || m[2].isEmpty()) return Group(t, kind, amount = m[0], height = m[1].toLong() * 100, cloudType = m[2])
            }
        }
        "temperature" -> captures("(M?[0-9]{2})/(M?[0-9]{2})", t)?.let { m ->
            fun celsius(v: String) = if (v.startsWith("M")) -v.substring(1).toLong() else v.toLong()
            return Group(t, kind, air = celsius(m[0]), dewPoint = celsius(m[1]))
        }
        "pressure" -> captures("([AQ])([0-9]{4})", t)?.let { m ->
            return Group(t, kind, unit = m[0], pressureValue = m[1].toLong())
        }
    }
    return null
}

fun validGroup(g: Group, section: Section): Boolean {
    val state = section.state
    return when (g.kind) {
        "wind" -> {
            if (g.direction == "VRB") {
                if (g.speed < 1) return false
            } else {
                val d = g.direction.toInt()
                if (d > 360 || d % 10 != 0 || (d == 0) != (g.speed == 0L)) return false
            }
            g.gust == null || (!g.calm && g.gust > g.speed)
        }
        "variation" -> listOf(g.firstDirection, g.secondDirection).all { it in 10L..360L && it % 10 == 0L } && g.firstDirection != g.secondDirection && state.wind?.directed == true
        "visibility" -> if (g.visibilityKind != "MILES") true else if (g.denominator == 0L) '/' !in g.text && g.whole >= 1 else
            (!g.joined || g.whole >= 1) && g.denominator in listOf(2L, 4L, 8L, 16L) && g.numerator >= 1 && g.numerator < g.denominator
        "rvr" -> g.runway in section.runways && (g.readings.size == 1 || g.readings.first().value < g.readings.last().value)
        "weather" -> {
            val accepted = state.weather ?: emptyList()
            val p = g.weatherPhenomena
            if (accepted.size >= 3 || accepted.any { it.text == "NSW" }) return false
            if (g.text == "NSW") return section.allowsNsw && accepted.isEmpty()
            if (g.codes.drop(1).any { it in descriptors } || p.toSet().size != p.size) return false
            if (p.isEmpty() && g.descriptor !in listOf("TS", "SH")) return false
            if (g.intensity in listOf("-", "+") && p.none { it in precipitation }) return false
            p.size < 2 || p.all { it in precipitation }
        }
        "cloud" -> {
            val last = state.cloud?.lastOrNull()
            last == null || g.amount in amounts && last.amount in amounts && g.height > last.height
        }
        "temperature" -> g.dewPoint <= g.air
        "pressure" -> if (g.unit == "A") g.pressureValue in 2500L..3150L else g.pressureValue in 850L..1070L
        else -> true
    }
}
