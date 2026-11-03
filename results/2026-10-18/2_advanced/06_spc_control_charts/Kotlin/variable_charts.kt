import kotlin.math.abs
import kotlin.math.sqrt

data class Subgroup(val number: Int, val values: List<Long>) {
    val total = values.sum()
    val squares = values.sumOf { it * it }
    val mean = total.toDouble() / values.size.toDouble()
    val range = values.max() - values.min()
    val sd = sqrt((values.size.toLong() * squares - total * total).toDouble() / (values.size.toLong() * (values.size - 1).toLong()).toDouble())
}
data class Limits(val lcl: Double, val cl: Double, val ucl: Double) { fun outside(value: Double) = value > ucl || value < lcl }
data class FamilyLimits(val first: Limits, val second: Limits)
fun realSum(values: Iterable<Double>): Double { var total = 0.0; for (value in values) total += value; return total }

fun familyLimits(family: String, ids: List<Int>, groups: List<Subgroup>, samples: List<Long>, size: Int, constants: ControlConstants): FamilyLimits {
    if (family == "I_MR") {
        val values = ids.map { samples[it - 1] }
        val mean = values.sum().toDouble() / values.size.toDouble()
        val ranges = values.zipWithNext { first, second -> abs(second - first) }
        val moving = ranges.sum().toDouble() / ranges.size.toDouble()
        val pair = controlConstants(2)
        return FamilyLimits(Limits(mean - 3.0 * moving / pair.d2, mean, mean + 3.0 * moving / pair.d2), Limits(pair.d3 * moving, moving, pair.d4 * moving))
    }
    val selected = ids.map { groups[it - 1] }
    val mean = selected.sumOf { it.total }.toDouble() / (ids.size * size).toDouble()
    if (family == "XBAR_R") {
        val range = selected.sumOf { it.range }.toDouble() / selected.size.toDouble()
        return FamilyLimits(Limits(mean - constants.a2 * range, mean, mean + constants.a2 * range), Limits(constants.d3 * range, range, constants.d4 * range))
    }
    val sd = realSum(selected.map { it.sd }) / selected.size.toDouble()
    return FamilyLimits(Limits(mean - constants.a3 * sd, mean, mean + constants.a3 * sd), Limits(constants.b3 * sd, sd, constants.b4 * sd))
}
