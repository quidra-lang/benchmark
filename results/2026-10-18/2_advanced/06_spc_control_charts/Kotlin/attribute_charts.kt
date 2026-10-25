import kotlin.math.sqrt

data class AttributeCenter(val chart: String, val value: Double, val fraction: Double)
data class LotPoint(val lot: Lot, val value: Double, val lcl: Double, val ucl: Double, val z: Double, val status: String)

fun attributeCenter(chart: String, lots: List<Lot>): AttributeCenter {
    val defectives = lots.sumOf { it.defectives }
    val defects = lots.sumOf { it.defects }
    val inspected = lots.sumOf { it.inspected }
    val fraction = defectives.toDouble() / inspected.toDouble()
    val center = when (chart) { "p" -> fraction; "np" -> defectives.toDouble() / lots.size.toDouble(); "c" -> defects.toDouble() / lots.size.toDouble(); else -> defects.toDouble() / inspected.toDouble() }
    return AttributeCenter(chart, center, fraction)
}

fun attributePoint(lot: Lot, center: AttributeCenter): LotPoint {
    val cl = center.value
    val value: Double
    val sigma: Double
    when (center.chart) {
        "p" -> { value = lot.defectives.toDouble() / lot.inspected.toDouble(); sigma = sqrt(cl * (1.0 - cl) / lot.inspected.toDouble()) }
        "np" -> { value = lot.defectives.toDouble(); sigma = sqrt(cl * (1.0 - center.fraction)) }
        "c" -> { value = lot.defects.toDouble(); sigma = sqrt(cl) }
        else -> { value = lot.defects.toDouble() / lot.inspected.toDouble(); sigma = sqrt(cl / lot.inspected.toDouble()) }
    }
    val lcl = maxOf(0.0, cl - 3.0 * sigma)
    val ucl = cl + 3.0 * sigma
    val status = when { value > ucl -> "high"; value < lcl -> "low"; else -> "ok" }
    return LotPoint(lot, value, lcl, ucl, (value - cl) / sigma, status)
}
