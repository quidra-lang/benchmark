import kotlin.math.sqrt

data class Edge(val source: Int, val target: Int)
data class HitsResult(val authority: DoubleArray, val hub: DoubleArray)
object Hits {
    fun compute(count: Int, nodes: List<Int>, links: List<Edge>, iterations: Int): HitsResult {
        val sources = List(count) { mutableListOf<Int>() }
        val targets = List(count) { mutableListOf<Int>() }
        for (edge in links.sortedWith(compareBy<Edge> { it.source }.thenBy { it.target })) {
            sources[edge.target].add(edge.source)
            targets[edge.source].add(edge.target)
        }
        val authority = DoubleArray(count)
        val hub = DoubleArray(count)
        for (node in nodes) { authority[node] = 1.0; hub[node] = 1.0 }
        for (step in 0 until iterations) {
            val incoming = DoubleArray(count)
            val outgoing = DoubleArray(count)
            for (node in nodes) for (source in sources[node]) incoming[node] += hub[source]
            for (node in nodes) for (target in targets[node]) outgoing[node] += incoming[target]
            val authorityNorm = norm(incoming, nodes)
            val hubNorm = norm(outgoing, nodes)
            for (node in nodes) { authority[node] = incoming[node] / authorityNorm; hub[node] = outgoing[node] / hubNorm }
        }
        return HitsResult(authority, hub)
    }
    fun norm(values: DoubleArray, nodes: List<Int>): Double {
        var squares = 0.0
        for (node in nodes) squares += values[node] * values[node]
        return sqrt(squares)
    }
}
