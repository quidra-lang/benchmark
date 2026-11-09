data class Promotion(val round: Int, val vertex: Int, val diff: Int)
data class Layering(val heights: IntArray, val labels: IntArray, val before: Int, val rounds: Int, val promotions: List<Promotion>)
fun lexCompare(a: List<Int>, b: List<Int>): Int {
    for (i in 0 until minOf(a.size, b.size)) if (a[i] != b[i]) return a[i].compareTo(b[i])
    return a.size.compareTo(b.size)
}
object AcyclicLayering {
    fun sequence(n: Int, edges: List<Edge>): List<Int> {
        val remaining = (0 until n).toMutableSet()
        val head = mutableListOf<Int>()
        val tail = mutableListOf<Int>()
        while (remaining.isNotEmpty()) {
            val degrees = remaining.sorted().map {
                v -> Triple(v, edges.count {
                    it.a == v && it.b in remaining
                }, edges.count {
                    it.b == v && it.a in remaining
                })
            }
            val sink = degrees.firstOrNull {
                it.second == 0
            }
            val source = degrees.firstOrNull {
                it.third == 0
            }
            val chosen: Int
            if (sink != null) {
                chosen = sink.first; tail.add(0, chosen)
            }
            else if (source != null) {
                chosen = source.first; head.add(chosen)
            }
            else {
                chosen = degrees.minWithOrNull(compareByDescending<Triple<Int, Int, Int>> {
                    it.second - it.third
                }.thenBy {
                    it.first
                })!!.first; head.add(chosen)
            }
            remaining.remove(chosen)
        }
        return head + tail
    }
    fun assign(n: Int, edges: List<Edge>, coffman: Boolean, width: Int, promotion: Boolean): Layering {
        val upper = List(n) {
            mutableListOf<Int>()
        }
        val lower = List(n) {
            mutableListOf<Int>()
        }
        for ((a, b) in edges) {
            upper[b].add(a); lower[a].add(b)
        }
        for (i in 0 until n) {
            upper[i].sort(); lower[i].sort()
        }
        val labels = IntArray(n)
        var heights = IntArray(n) {
            -1
        }
        if (coffman) {
            for (k in 1..n) {
                val v = (0 until n).filter {
                    labels[it] == 0 && upper[it].all {
                        p -> labels[p] > 0
                    }
                }.minWithOrNull(Comparator {
                    a, b ->
                    val order = lexCompare(upper[a].map {
                        labels[it]
                    }.sortedDescending(), upper[b].map {
                        labels[it]
                    }.sortedDescending())
                    if (order == 0) a.compareTo(b) else order
                })!!
                labels[v] = k
            }
            var current = 0
            var count = 0
            repeat(n) {
                val v = (0 until n).filter {
                    heights[it] < 0 && lower[it].all {
                        p -> heights[p] >= 0
                    }
                }.maxByOrNull {
                    labels[it]
                }!!
                if (count == width || lower[v].any {
                    heights[it] == current
                }) {
                    current++; count = 0
                }
                heights[v] = current; count++
            }
        } else {
            fun height(v: Int): Int {
                if (heights[v] >= 0) return heights[v]
                heights[v] = lower[v].maxOfOrNull {
                    height(it) + 1
                } ?: 0
                return heights[v]
            }
            for (v in 0 until n) height(v)
        }
        val before = edges.sumOf {
            heights[it.a] - heights[it.b] - 1
        }
        var rounds = 0
        val promotions = mutableListOf<Promotion>()
        if (promotion) {
            fun promote(v: Int): Int {
                var diff = 0
                for (u in upper[v]) if (heights[u] == heights[v] + 1) diff += promote(u)
                heights[v]++
                return diff + lower[v].size - upper[v].size
            }
            while (true) {
                rounds++
                var changed = false
                for (v in 0 until n) if (upper[v].isNotEmpty()) {
                    val saved = heights.copyOf()
                    val diff = promote(v)
                    if (diff < 0) {
                        promotions.add(Promotion(rounds, v, diff)); changed = true
                    } else heights = saved
                }
                if (!changed) break
            }
        }
        return Layering(heights, labels, before, rounds, promotions)
    }
}
