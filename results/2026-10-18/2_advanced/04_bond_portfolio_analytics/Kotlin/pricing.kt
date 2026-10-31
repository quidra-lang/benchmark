fun bisection(low: Double, high: Double, target: Double, function: (Double) -> Double): Double {
    var lo = low
    var hi = high
    repeat(80) {
        val middle = (lo + hi) / 2.0
        if (function(middle) > target) lo = middle else hi = middle
    }
    return (lo + hi) / 2.0
}

data class RiskMeasures(val macaulay: Double, val modified: Double, val convexity: Double, val dv01: Double)

class YieldPricer(val flows: List<Long>, val fraction: Double, val frequency: Int, val outstanding: Long) {
    fun presentValues(rate: Double): List<Double> {
        val first = 1.0 + fraction * rate / frequency.toDouble()
        val growth = 1.0 + rate / frequency.toDouble()
        var factor = 1.0
        return flows.map { flow -> val value = flow.toDouble() / (first * factor); factor *= growth; value }
    }
    fun dirty(rate: Double): Double { var total = 0.0; for (value in presentValues(rate)) total += value; return total * 100.0 / outstanding.toDouble() }
    fun solve(target: Double) = bisection(0.0, 1.0, target, ::dirty)
    fun inRange(target: Double) = dirty(0.0) > target && target > dirty(1.0)
    fun risk(rate: Double): RiskMeasures {
        val growth = 1.0 + rate / frequency.toDouble()
        var total = 0.0
        var weighted = 0.0
        var curvature = 0.0
        for ((index, value) in presentValues(rate).withIndex()) {
            val years = (index.toDouble() + fraction) / frequency.toDouble()
            total += value
            weighted += years * value
            curvature += years * (years + 1.0 / frequency.toDouble()) * value
        }
        val macaulay = weighted / total
        return RiskMeasures(macaulay, macaulay / growth, curvature / (total * growth * growth), (dirty(rate - 0.0001) - dirty(rate + 0.0001)) / 2.0)
    }
}
