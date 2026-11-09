import kotlin.math.abs
import kotlin.math.sqrt

data class Neighbor(val distance: Double, val row: Row)
data class Vote(val label: String, val share: Double, val runner: String?, val runnerShare: Double)
class VoteTally(val label: String) { var count = 0; var distances = 0.0; var weights = 0.0 }
fun distance(first: List<Double>, second: List<Double>, metric: String): Double {
    var total = 0.0
    var dot = 0.0
    var firstSquares = 0.0
    var secondSquares = 0.0
    for (index in first.indices) {
        val a = first[index]
        val b = second[index]
        val difference = a - b
        when (metric) {
            "squared_euclidean" -> total += difference * difference
            "manhattan" -> total += abs(difference)
            "chebyshev" -> total = maxOf(total, abs(difference))
            else -> { dot += a * b; firstSquares += a * a; secondSquares += b * b }
        }
    }
    if (metric != "cosine") return total
    val a = sqrt(firstSquares)
    val b = sqrt(secondSquares)
    return if (a == 0.0 || b == 0.0) 1.0 else 1.0 - dot / (a * b)
}
fun sortNeighbors(neighbors: List<Neighbor>) = neighbors.sortedWith(compareBy({ it.distance }, { it.row.id }))
fun neighborOrder(query: List<Double>, references: List<Pair<List<Double>, Row>>, metric: String) = sortNeighbors(references.map { (vector, row) -> Neighbor(distance(query, vector, metric), row) })
fun vote(nearest: List<Neighbor>, weighting: String): Vote {
    val tallies = mutableMapOf<String, VoteTally>()
    var totalWeight = 0.0
    for (neighbor in nearest) {
        val weight = 1.0 / (neighbor.distance + 0.000000001)
        val label = neighbor.row.label!!
        val tally = tallies.getOrPut(label) { VoteTally(label) }
        tally.count++
        tally.distances += neighbor.distance
        tally.weights += weight
        totalWeight += weight
    }
    val ranked = tallies.values.sortedWith { first, second ->
        val primary = if (weighting == "uniform") second.count.compareTo(first.count) else second.weights.compareTo(first.weights)
        when { primary != 0 -> primary; first.distances != second.distances -> first.distances.compareTo(second.distances); else -> first.label.compareTo(second.label) }
    }
    fun share(tally: VoteTally) = if (weighting == "uniform") tally.count.toDouble() / nearest.size.toDouble() else tally.weights / totalWeight
    return Vote(ranked[0].label, share(ranked[0]), ranked.getOrNull(1)?.label, ranked.getOrNull(1)?.let(::share) ?: 0.0)
}
fun estimate(nearest: List<Neighbor>, weighting: String): Double {
    var total = 0.0
    var weights = 0.0
    for (neighbor in nearest) {
        if (weighting == "uniform") total += neighbor.row.target!!
        else { val weight = 1.0 / (neighbor.distance + 0.000000001); total += weight * neighbor.row.target!!; weights += weight }
    }
    return total / (if (weighting == "uniform") nearest.size.toDouble() else weights)
}
