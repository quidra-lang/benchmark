import kotlin.math.abs
import kotlin.math.sqrt

object Agglomerative {
    data class Merge(val a: Int, val b: Int, val height: Double, val size: Int)
    data class Edge(val parent: Int, val child: Int, val weight: Double)
    private data class Coefficients(val alphaA: Double, val alphaB: Double, val beta: Double, val gamma: Double)

    private fun coefficients(method: String, a: Int, b: Int, k: Int): Coefficients {
        val merged = a + b
        val total = merged + k
        return when (method) {
            "single" -> Coefficients(0.5, 0.5, 0.0, -0.5)
            "complete" -> Coefficients(0.5, 0.5, 0.0, 0.5)
            "average" -> Coefficients(a.toDouble() / merged, b.toDouble() / merged, 0.0, 0.0)
            "weighted" -> Coefficients(0.5, 0.5, 0.0, 0.0)
            "centroid" -> Coefficients(a.toDouble() / merged, b.toDouble() / merged, -(a * b).toDouble() / (merged * merged), 0.0)
            "median" -> Coefficients(0.5, 0.5, -0.25, 0.0)
            else -> Coefficients((a + k).toDouble() / total, (b + k).toDouble() / total, -k.toDouble() / total, 0.0)
        }
    }

    fun cluster(delta: Array<DoubleArray>, method: String): List<Merge> {
        val count = delta.size
        val capacity = 2 * count - 1
        val squared = method in setOf("centroid", "median", "ward")
        val values = Array(capacity) { DoubleArray(capacity) }
        for (u in 0 until count) for (w in 0 until count) values[u][w] = if (squared) delta[u][w] * delta[u][w] else delta[u][w]
        val sizes = IntArray(capacity) { if (it < count) 1 else 0 }
        val active = (0 until count).toMutableList()
        val merges = mutableListOf<Merge>()
        repeat(count - 1) { step ->
            var a = active[0]
            var b = active[1]
            var best = values[a][b]
            for (position in active.indices) for (next in position + 1 until active.size) {
                val first = active[position]
                val second = active[next]
                if (values[first][second] < best) { a = first; b = second; best = values[a][b] }
            }
            val node = count + step
            sizes[node] = sizes[a] + sizes[b]
            merges.add(Merge(a, b, if (squared) sqrt(best) else best, sizes[node]))
            for (k in active) {
                if (k == a || k == b) continue
                val c = coefficients(method, sizes[a], sizes[b], sizes[k])
                val value = c.alphaA * values[a][k] + c.alphaB * values[b][k] + c.beta * values[a][b] + c.gamma * abs(values[a][k] - values[b][k])
                values[node][k] = value
                values[k][node] = value
            }
            active.remove(a)
            active.remove(b)
            active.add(node)
        }
        return merges
    }

    fun minimumSpanningTree(delta: Array<DoubleArray>): List<Edge> {
        val count = delta.size
        val inTree = BooleanArray(count)
        inTree[0] = true
        val key = delta[0].copyOf()
        val parent = IntArray(count)
        val edges = mutableListOf<Edge>()
        repeat(count - 1) {
            var chosen = -1
            for (u in 0 until count) if (!inTree[u] && (chosen < 0 || key[u] < key[chosen])) chosen = u
            inTree[chosen] = true
            edges.add(Edge(parent[chosen], chosen, key[chosen]))
            for (u in 0 until count) if (!inTree[u] && delta[chosen][u] < key[u]) { key[u] = delta[chosen][u]; parent[u] = chosen }
        }
        return edges
    }
}
