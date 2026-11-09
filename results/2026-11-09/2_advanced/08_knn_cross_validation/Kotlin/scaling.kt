import kotlin.math.sqrt

data class Scaling(val centers: List<Double>, val scales: List<Double>) {
    fun transform(values: List<Double>, features: List<Int>) = features.map { if (scales[it] > 0.0) (values[it] - centers[it]) / scales[it] else 0.0 }
}
fun computeScaling(rows: List<Row>, method: String): Scaling {
    val centers = mutableListOf<Double>()
    val scales = mutableListOf<Double>()
    for (feature in rows[0].values.indices) {
        val column = rows.map { it.values[feature] }
        if (method == "minmax") { centers += column.min(); scales += column.max() - column.min() }
        else {
            var total = 0.0
            for (value in column) total += value
            val center = total / rows.size.toDouble()
            var squares = 0.0
            for (value in column) squares += (value - center) * (value - center)
            centers += center
            scales += if (rows.size == 1) 0.0 else sqrt(squares / (rows.size - 1).toDouble())
        }
    }
    return Scaling(centers, scales)
}
