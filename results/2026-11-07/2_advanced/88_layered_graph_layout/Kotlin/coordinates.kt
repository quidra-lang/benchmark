data class VertexPair(val a: Int, val b: Int) {
    companion object {
        fun unordered(a: Int, b: Int): VertexPair = VertexPair(minOf(a, b), maxOf(a, b))
    }
}
data class Coordinates(val x: IntArray, val aligned: List<IntArray>, val blocks: List<Int>, val widths: List<Int>,
val smallest: Int, val conflicts: Int, val left: IntArray, val right: IntArray) {
    companion object {
        fun floorHalf(value: Int): Int = Math.floorDiv(value, 2)
        fun assign(n: Int, order: List<List<Int>>, layer: List<Int>, upper: List<List<Int>>, lower: List<List<Int>>,
        width: List<Int>, vertical: Boolean, nodeSep: Int, dummySep: Int): Coordinates {
            val vertices = layer.size
            val positions = Crossing.positions(order, vertices)
            val left = IntArray(vertices) {
                if (vertical) (width[it] - 1) / 2 else 0
            }
            val right = IntArray(vertices) {
                if (vertical) width[it] - 1 - left[it] else 0
            }
            fun separation(a: Int, b: Int): Int = right[a] + left[b] + 1 + if (a < n && b < n) nodeSep else dummySep
            val marked = mutableSetOf<VertexPair>()
            for (i in 0 until order.size - 1) {
                val a = order[i]
                val b = order[i + 1]
                var k0 = 0
                var t = 0
                for (l1 in b.indices) {
                    val v = b[l1]
                    val inner = v >= n && upper[v][0] >= n
                    if (inner || l1 + 1 == b.size) {
                        val k1 = if (inner) positions[upper[v][0]] else a.size - 1
                        for (l in t..l1) for (u in upper[b[l]]) if (positions[u] < k0 || positions[u] > k1) marked.add(VertexPair.unordered(u, b[l]))
                        t = l1 + 1; k0 = k1
                    }
                }
            }
            val layouts = mutableListOf<IntArray>()
            val blocks = mutableListOf<Int>()
            val widths = mutableListOf<Int>()
            val lows = mutableListOf<Int>()
            val highs = mutableListOf<Int>()
            for (variant in 0..3) {
                val down = variant >= 2
                val rightScan = variant % 2 == 1
                fun q(v: Int): Int = if (rightScan) order[layer[v]].size - 1 - positions[v] else positions[v]
                val root = IntArray(vertices) {
                    it
                }
                val align = root.copyOf()
                val layers = if (down) order.indices.reversed().toList() else order.indices.toList()
                for (i in layers.drop(1)) {
                    val scan = if (rightScan) order[i].reversed() else order[i]
                    var rho = -1
                    for (v in scan) {
                        val reference = (if (down) lower[v] else upper[v]).sortedBy {
                            q(it)
                        }
                        if (reference.isEmpty()) continue
                        for (m in listOf((reference.size - 1) / 2, reference.size / 2)) {
                            val u = reference[m]
                            if (align[v] == v && VertexPair.unordered(u, v) !in marked && rho < q(u)) {
                                align[u] = v; root[v] = root[u]; align[v] = root[v]; rho = q(u)
                            }
                        }
                    }
                }
                val roots = root.toSet()
                blocks.add(roots.size)
                val edges = mutableMapOf<VertexPair, Int>()
                for (row in order) {
                    val scan = if (rightScan) row.reversed() else row
                    for (i in 1 until scan.size) {
                        val a = scan[i - 1]
                        val b = scan[i]
                        val delta = if (rightScan) separation(b, a) else separation(a, b)
                        val pair = VertexPair(root[a], root[b])
                        edges[pair] = maxOf(edges[pair] ?: 0, delta)
                    }
                }
                val incoming = List(vertices) {
                    mutableListOf<Pair<Int, Int>>()
                }
                val outgoing = List(vertices) {
                    mutableListOf<Pair<Int, Int>>()
                }
                val degree = IntArray(vertices)
                for ((pair, delta) in edges) {
                    incoming[pair.b].add(Pair(pair.a, delta)); outgoing[pair.a].add(Pair(pair.b, delta)); degree[pair.b]++
                }
                val ready = roots.filter {
                    degree[it] == 0
                }.toMutableSet()
                val topology = mutableListOf<Int>()
                while (ready.isNotEmpty()) {
                    val v = ready.minOrNull()!!
                    ready.remove(v); topology.add(v)
                    for ((u, _) in outgoing[v]) {
                        degree[u]--; if (degree[u] == 0) ready.add(u)
                    }
                }
                val y1 = IntArray(vertices)
                for (v in topology) y1[v] = incoming[v].maxOfOrNull {
                    y1[it.first] + it.second
                } ?: 0
                val y2 = y1.copyOf()
                for (v in topology.reversed()) {
                    val minimum = outgoing[v].minOfOrNull {
                        y2[it.first] - it.second
                    }
                    if (minimum != null) y2[v] = maxOf(y1[v], minimum)
                }
                val x = IntArray(vertices) {
                    if (rightScan) -y2[root[it]] else y2[root[it]]
                }
                val lo = (0 until vertices).minOf {
                    x[it] - left[it]
                }
                val hi = (0 until vertices).maxOf {
                    x[it] + right[it]
                }
                lows.add(lo); highs.add(hi); widths.add(hi - lo + 1); layouts.add(x)
            }
            val smallest = (0..3).minWithOrNull(compareBy<Int> {
                widths[it]
            }.thenBy {
                it
            })!!
            for (i in 0..3) {
                val delta = if (i % 2 == 0) lows[smallest] - lows[i] else highs[smallest] - highs[i]
                for (v in 0 until vertices) layouts[i][v] += delta
            }
            val x = IntArray(vertices) {
                v -> val sorted = layouts.map {
                    it[v]
                }.sorted(); floorHalf(sorted[1] + sorted[2])
            }
            val minimum = (0 until vertices).minOf {
                x[it] - left[it]
            }
            for (v in 0 until vertices) x[v] -= minimum
            return Coordinates(x, layouts, blocks, widths, smallest, marked.size, left, right)
        }
    }
}
