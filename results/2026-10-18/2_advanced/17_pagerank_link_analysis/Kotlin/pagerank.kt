import kotlin.math.abs

data class WeightedEdge(val source: Int, val weight: Int)
data class PageRankResult(val values: DoubleArray, val changes: DoubleArray, val convergedAt: Int?)
object PageRank {
    fun compute(incoming: List<List<WeightedEdge>>, teleport: List<Int>, damping: Double, iterations: Int, tolerance: Double): PageRankResult {
        val count = incoming.size
        val outgoing = IntArray(count)
        for (edges in incoming) for (edge in edges) outgoing[edge.source] += edge.weight
        val inTeleport = BooleanArray(count)
        for (node in teleport) inTeleport[node] = true
        var values = DoubleArray(count) { if (inTeleport[it]) 1.0 / teleport.size else 0.0 }
        val changes = DoubleArray(iterations)
        var convergedAt: Int? = null
        for (step in 0 until iterations) {
            var dangling = 0.0
            for (node in 0 until count) if (outgoing[node] == 0) dangling += values[node]
            val base = ((1 - damping) + damping * dangling) / teleport.size
            val updated = DoubleArray(count)
            for (node in 0 until count) {
                var inflow = 0.0
                for (edge in incoming[node]) inflow += values[edge.source] * edge.weight / outgoing[edge.source]
                updated[node] = if (inTeleport[node]) damping * inflow + base else damping * inflow
            }
            var change = 0.0
            for (node in 0 until count) change += abs(updated[node] - values[node])
            changes[step] = change
            if (convergedAt == null && change < tolerance) convergedAt = step + 1
            values = updated
        }
        return PageRankResult(values, changes, convergedAt)
    }
}
