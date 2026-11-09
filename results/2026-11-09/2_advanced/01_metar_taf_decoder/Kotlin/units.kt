import kotlin.math.abs

fun floorDiv(n: Long, d: Long): Long = Math.floorDiv(n, d)

fun knots(v: Long, unit: String) = if (unit == "MPS") (v * 1944 + 500) / 1000 else v

fun inhg(q: Long) = (q * 2953 + 500) / 1000

fun hpa(a: Long) = (a * 33864 + 50000) / 100000

val sineTable = listOf(0L, 174L, 342L, 500L, 643L, 766L, 866L, 940L, 985L, 1000L)

fun sine(x: Int): Long {
    val y = Math.floorMod(x, 360)
    return when {
        y <= 90 -> sineTable[y / 10]
        y <= 180 -> sineTable[(180 - y) / 10]
        y <= 270 -> -sineTable[(y - 180) / 10]
        else -> -sineTable[(360 - y) / 10]
    }
}

fun cosine(x: Int) = sine(x + 90)

fun daysInMonth(y: Int, m: Int) = if (m == 2) {
    if (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)) 29 else 28
} else if (m in listOf(1, 3, 5, 7, 8, 10, 12)) 31 else 30

fun dayMinutes(d: Int, h: Int, m: Int) = ((d - 1) * 24 + h) * 60 + m

fun pad(n: Number, width: Int) = n.toString().padStart(width, '0')

class Calendar(val year: Int, val month: Int) {
    val days = daysInMonth(year, month)
    val nextYear = if (month == 12) year + 1 else year
    val nextMonth = if (month == 12) 1 else month + 1
    fun forecastTime(d: Int, h: Int, m: Int, issueDay: Int): Int? {
        val next = d < issueDay
        if (d < 1 || d > daysInMonth(if (next) nextYear else year, if (next) nextMonth else month)) return null
        return (if (next) days * 1440 else 0) + dayMinutes(d, h, m)
    }
    fun stamp(time: Int): String {
        val next = time >= days * 1440
        val t = time - if (next) days * 1440 else 0
        return "${pad(if (next) nextYear else year, 4)}-${pad(if (next) nextMonth else month, 2)}-${pad(t / 1440 + 1, 2)}T${pad(t % 1440 / 60, 2)}:${pad(t % 60, 2)}Z"
    }
}

fun miles(g: Group): Pair<Long, Long> = if (g.visibilityKind == "MILES") {
    if (g.denominator == 0L) g.whole to 1L else g.whole * g.denominator + g.numerator to g.denominator
} else 1000 * g.meters to 1609344L

fun meterValue(g: Group): Long {
    val (n, d) = miles(g)
    return if (g.visibilityKind == "MILES") 1609344 * n / (1000 * d) else g.meters
}

fun lessFraction(a: Pair<Long, Long>, b: Pair<Long, Long>) = a.first * b.second < b.first * a.second

fun fraction(n: Long, d: Long): String {
    if (d == 0L) return "undefined"
    var a = abs(n)
    var b = abs(d)
    while (b != 0L) {
        val r = a % b
        a = b
        b = r
    }
    val sign = if (d < 0) -1 else 1
    return "${n / a * sign}/${d / a * sign}"
}
