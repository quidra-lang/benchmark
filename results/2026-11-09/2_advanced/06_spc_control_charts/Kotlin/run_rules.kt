data class Point(val number: Int, val value: Double)
data class Signal(val chart: String, val rule: String, val start: Int, val end: Int, val value: Double, val direction: String) {
    fun subgroup(size: Int) = if (chart == "I" || chart == "MR") (end - 1) / size + 1 else end
}
data class Zones(val upper1: Double, val upper2: Double, val lower1: Double, val lower2: Double)
fun zones(limits: Limits): Zones {
    val above = (limits.ucl - limits.cl) / 3.0
    val below = (limits.cl - limits.lcl) / 3.0
    return Zones(limits.cl + above, limits.cl + 2.0 * above, limits.cl - below, limits.cl - 2.0 * below)
}
fun zoneName(value: Double, limits: Limits): String {
    val zone = zones(limits)
    return when { value > limits.ucl -> "OUT+"; value < limits.lcl -> "OUT-"; value > zone.upper2 -> "A+"; value > zone.upper1 -> "B+"; value > limits.cl -> "C+"; value < zone.lower2 -> "A-"; value < zone.lower1 -> "B-"; value < limits.cl -> "C-"; else -> "C0" }
}

fun runRules(chart: String, points: List<Point>, limits: Limits, rules: List<Int>): List<Signal> {
    val lengths = listOf(0, 1, 3, 5, 8, 6, 14, 15, 8)
    val zone = zones(limits)
    val signals = mutableListOf<Signal>()
    for (index in points.indices) for (rule in rules) {
        val length = lengths[rule]
        if (index + 1 < length) continue
        val window = points.subList(index + 1 - length, index + 1).map { it.value }
        val value = window.last()
        val direction = when (rule) {
            1 -> if (limits.outside(value)) if (value > limits.cl) "UP" else "DOWN" else null
            2 -> when { value > zone.upper2 && window.count { it > zone.upper2 } >= 2 -> "UP"; value < zone.lower2 && window.count { it < zone.lower2 } >= 2 -> "DOWN"; else -> null }
            3 -> when { value > zone.upper1 && window.count { it > zone.upper1 } >= 4 -> "UP"; value < zone.lower1 && window.count { it < zone.lower1 } >= 4 -> "DOWN"; else -> null }
            4 -> when { window.all { it > limits.cl } -> "UP"; window.all { it < limits.cl } -> "DOWN"; else -> null }
            5 -> when { window.zipWithNext().all { (a, b) -> b > a } -> "UP"; window.zipWithNext().all { (a, b) -> b < a } -> "DOWN"; else -> null }
            6 -> { val differences = window.zipWithNext { a, b -> b - a }; if (differences.all { it != 0.0 } && differences.zipWithNext().all { (a, b) -> (a > 0.0) != (b > 0.0) }) "NONE" else null }
            7 -> if (window.all { it > zone.lower1 && it < zone.upper1 }) "NONE" else null
            else -> if (window.all { it > zone.upper1 || it < zone.lower1 } && window.any { it > zone.upper1 } && window.any { it < zone.lower1 }) "NONE" else null
        }
        if (direction != null) signals += Signal(chart, rule.toString(), points[index + 1 - length].number, points[index].number, value, direction)
    }
    return signals
}
