import kotlin.math.sqrt

class Customer(val id: String, val orders: List<Order>, day: Int) {
    val recency: Int
    val frequency = orders.size
    val spend: Int
    val monetary: Double
    val basket: Double
    val categories: Int
    val tenure: Int
    val categorySpend = sortedMapOf<String, Int>()
    init {
        var latest = Int.MIN_VALUE
        var earliest = Int.MAX_VALUE
        var total = 0
        for (order in orders) {
            latest = maxOf(latest, order.day)
            earliest = minOf(earliest, order.day)
            total += order.net
            for (row in order.rows) categorySpend[row.category] = categorySpend.getOrDefault(row.category, 0) + row.amount
        }
        recency = day - latest
        spend = total
        monetary = spend / 100.0
        basket = monetary / frequency
        categories = categorySpend.values.count { it > 0 }
        tenure = day - earliest
    }
    fun values() = doubleArrayOf(recency.toDouble(), frequency.toDouble(), monetary, basket, categories.toDouble(), tenure.toDouble())
    fun transformed(): DoubleArray {
        val result = values()
        for (f in result.indices) if (Features.SQRT[f]) result[f] = sqrt(result[f])
        return result
    }
}
data class Standardization(val means: DoubleArray, val sds: DoubleArray)
object Features {
    val NAMES = listOf("recency", "frequency", "monetary", "basket", "categories", "tenure")
    val SQRT = booleanArrayOf(false, true, true, true, false, false)
    fun eligible(orders: List<Order>, day: Int): List<Customer> {
        val groups = Transactions.byCustomer(orders.filter { it.valid() })
        return groups.keys.sorted().map { Customer(it, groups.getValue(it), day) }
    }
    fun sum(values: DoubleArray): Double {
        var total = 0.0
        for (value in values) total += value
        return total
    }
    fun mean(values: DoubleArray) = sum(values) / values.size
    fun sampleSd(values: DoubleArray): Double {
        val average = mean(values)
        var total = 0.0
        for (value in values) {
            val difference = value - average
            total += difference * difference
        }
        return sqrt(total / (values.size - 1))
    }
    fun standardization(rows: List<DoubleArray>): Standardization {
        val means = DoubleArray(6)
        val sds = DoubleArray(6)
        for (f in 0 until 6) {
            val column = DoubleArray(rows.size) { rows[it][f] }
            means[f] = mean(column)
            sds[f] = sampleSd(column)
        }
        return Standardization(means, sds)
    }
    fun standardize(values: DoubleArray, means: DoubleArray, sds: DoubleArray) =
        DoubleArray(values.size) { if (sds[it] == 0.0) 0.0 else (values[it] - means[it]) / sds[it] }
    fun correlation(points: List<DoubleArray>, first: Int, second: Int): Double {
        var total = 0.0
        for (point in points) total += point[first] * point[second]
        return total / (points.size - 1)
    }
}
