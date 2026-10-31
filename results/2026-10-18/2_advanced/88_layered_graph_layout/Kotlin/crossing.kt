data class Segment(val p: Int, val q: Int, val edge: Int)
object Crossing {
    fun positions(order: List<List<Int>>, n: Int): IntArray {
        val positions = IntArray(n)
        for (row in order) for ((i, v) in row.withIndex()) positions[v] = i
        return positions
    }
    fun count(segments: List<Segment>, positions: IntArray, width: Int): Int {
        val pairs = segments.map {
            Pair(positions[it.p], positions[it.q])
        }.sortedWith(compareBy<Pair<Int, Int>> {
            it.first
        }.thenBy {
            it.second
        })
        var c = 1
        while (c < width) c *= 2
        val tree = IntArray(c * 2 - 1)
        var count = 0
        for ((_, q) in pairs) {
            var k = q + c - 1
            tree[k]++
            while (k > 0) {
                if (k % 2 == 1) count += tree[k + 1]; k = (k - 1) / 2; tree[k]++
            }
        }
        return count
    }
    fun crosses(a: Segment, b: Segment, positions: IntArray): Boolean = positions[a.p] < positions[b.p] && positions[a.q] > positions[b.q] || positions[a.p] > positions[b.p] && positions[a.q] < positions[b.q]
    fun brute(segments: List<Segment>, positions: IntArray): Int {
        var count = 0
        for (i in segments.indices) for (j in i + 1 until segments.size) if (crosses(segments[i], segments[j], positions)) count++
        return count
    }
    fun total(gaps: List<List<Segment>>, order: List<List<Int>>, n: Int): Int {
        val positions = positions(order, n)
        return gaps.mapIndexed {
            i, segments -> count(segments, positions, order[i + 1].size)
        }.sum()
    }
    fun adjacent(v: Int, w: Int, upper: List<List<Int>>, lower: List<List<Int>>, positions: IntArray): Int =
    upper[v].sumOf {
        a -> upper[w].count {
            positions[a] > positions[it]
        }
    } + lower[v].sumOf {
        a -> lower[w].count {
            positions[a] > positions[it]
        }
    }
}
