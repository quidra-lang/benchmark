data class CurveFlow(val days: Int, val amount: Double)
data class Pillar(val maturity: Int, val coupon: Int, val frequency: Int)

class ZeroCurve(val days: List<Int>, val rates: List<Double>) {
    fun zeroRate(day: Int): Double {
        if (day <= days.first()) return rates.first()
        if (day >= days.last()) return rates.last()
        val index = days.indexOfFirst { it >= day }
        if (days[index] == day) return rates[index]
        val weight = (day - days[index - 1]).toDouble() / (days[index] - days[index - 1]).toDouble()
        return rates[index - 1] + (rates[index] - rates[index - 1]) * weight
    }
    fun discount(day: Int, spread: Double = 0.0): Double {
        val rate = zeroRate(day) + spread
        var growth = 1.0
        repeat(day / 365) { growth *= 1.0 + rate }
        return 1.0 / (growth * (1.0 + rate * (day % 365).toDouble() / 365.0))
    }
    fun forward(start: Int, end: Int) = (discount(start) / discount(end) - 1.0) * 365.0 / (end - start).toDouble()
    fun shifted(deltas: List<Double>) = ZeroCurve(days, rates.indices.map { rates[it] + deltas[it] })
    fun presentValue(flows: List<CurveFlow>, spread: Double = 0.0): Double { var total = 0.0; for (flow in flows) total += flow.amount * discount(flow.days, spread); return total }
    fun zSpread(flows: List<CurveFlow>, target: Double) = bisection(-0.5, 0.5, target) { presentValue(flows, it) }
}

fun bootstrap(settlement: Int, pillars: List<Pillar>): ZeroCurve {
    val days = mutableListOf<Int>()
    val rates = mutableListOf<Double>()
    for (pillar in pillars) {
        val dates = couponSchedule(settlement, pillar.maturity, pillar.frequency)
        val flows = (1 until dates.size).map { index ->
            val fraction = yearFraction("30/360", dates[index - 1], dates[index])
            CurveFlow(dates[index] - settlement, pillar.coupon.toDouble() * fraction.numerator.toDouble() / (10000.0 * fraction.denominator.toDouble()) + if (index == dates.lastIndex) 1.0 else 0.0)
        }
        days += pillar.maturity - settlement
        rates += bisection(0.0, 1.0, 1.0) { ZeroCurve(days, rates + it).presentValue(flows) }
    }
    return ZeroCurve(days, rates)
}
