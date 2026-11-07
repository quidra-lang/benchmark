import kotlin.math.abs
import kotlin.math.sqrt

data class Model(val k: Int, val metric: String, val weighting: String, val scaling: String) { fun notation() = "k=$k metric=$metric weighting=$weighting scaling=$scaling" }
data class Prediction(val nearest: List<Neighbor>, val vote: Vote, val estimate: Double) {
    val label get() = vote.label
    val share get() = vote.share
    val runner get() = vote.runner
    val runnerShare get() = vote.runnerShare
}
fun stratifiedFolds(rows: List<Row>, count: Int): List<List<Int>> {
    val folds = List(count) { mutableListOf<Int>() }
    val ordered = rows.indices.sortedWith(compareBy({ rows[it].label!! }, { rows[it].id }))
    for ((position, index) in ordered.withIndex()) folds[position % count] += index
    return folds.map { it.sorted() }
}
fun foldTraining(rows: List<Row>, fold: List<Int>): List<Row> { val excluded = fold.toSet(); return rows.filterIndexed { index, _ -> index !in excluded } }
fun neighborOrders(training: List<Row>, queries: List<Row>, method: String, metric: String, features: List<Int>): List<List<Neighbor>> {
    val scaling = computeScaling(training, method)
    val references = training.map { scaling.transform(it.values, features) to it }
    return queries.map { neighborOrder(scaling.transform(it.values, features), references, metric) }
}
fun predictionFromOrder(order: List<Neighbor>, k: Int, weighting: String): Prediction { val nearest = order.take(k); return Prediction(nearest, vote(nearest, weighting), estimate(nearest, weighting)) }
fun predictRows(model: Model, training: List<Row>, queries: List<Row>, features: List<Int>) = neighborOrders(training, queries, model.scaling, model.metric, features).map { predictionFromOrder(it, model.k, model.weighting) }
fun rmse(errors: List<Double>): Double { var total = 0.0; for (error in errors) total += error * error; return sqrt(total / errors.size.toDouble()) }
fun mae(errors: List<Double>): Double { var total = 0.0; for (error in errors) total += abs(error); return total / errors.size.toDouble() }
fun rSquared(errors: List<Double>, targets: List<Double>): Double {
    var total = 0.0
    for (target in targets) total += target
    val mean = total / targets.size.toDouble()
    var residual = 0.0
    var spread = 0.0
    for (error in errors) residual += error * error
    for (target in targets) spread += (target - mean) * (target - mean)
    return 1.0 - residual / spread
}
