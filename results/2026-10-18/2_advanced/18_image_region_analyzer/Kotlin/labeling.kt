data class LabelResult(val labels: Array<IntArray>, val count: Int, val provisional: Int)
object Labeling {
    private fun previous(connectivity: Int) = if (connectivity == 4) listOf(Pixel(-1, 0), Pixel(0, -1))
        else listOf(Pixel(-1, 0), Pixel(-1, -1), Pixel(0, -1), Pixel(1, -1))
    private fun find(parents: MutableList<Int>, original: Int): Int {
        var label = original
        while (parents[label] != label) { parents[label] = parents[parents[label]]; label = parents[label] }
        return label
    }
    private fun union(parents: MutableList<Int>, first: Int, second: Int) {
        val a = find(parents, first)
        val b = find(parents, second)
        if (a != b) parents[maxOf(a, b)] = minOf(a, b)
    }
    fun label(mask: Array<BooleanArray>, connectivity: Int): LabelResult {
        val height = mask.size
        val width = mask[0].size
        val provisional = Array(height) { IntArray(width) }
        val parents = mutableListOf(0)
        for (y in 0 until height) for (x in 0 until width) {
            if (!mask[y][x]) continue
            val neighbors = mutableListOf<Int>()
            for (offset in previous(connectivity)) {
                val nx = x + offset.x
                val ny = y + offset.y
                if (nx in 0 until width && ny >= 0 && mask[ny][nx]) neighbors.add(provisional[ny][nx])
            }
            if (neighbors.isEmpty()) { provisional[y][x] = parents.size; parents.add(parents.size) }
            else { provisional[y][x] = neighbors[0]; for (other in neighbors.drop(1)) union(parents, neighbors[0], other) }
        }
        val numbers = IntArray(parents.size)
        val labels = Array(height) { IntArray(width) }
        var count = 0
        for (y in 0 until height) for (x in 0 until width) {
            if (provisional[y][x] == 0) continue
            val root = find(parents, provisional[y][x])
            if (numbers[root] == 0) numbers[root] = ++count
            labels[y][x] = numbers[root]
        }
        return LabelResult(labels, count, parents.size - 1)
    }
    fun bitQuad(mask: Array<BooleanArray>, connectivity: Int): Int {
        var singles = 0
        var triples = 0
        var diagonals = 0
        for (y in -1 until mask.size) for (x in -1 until mask[0].size) {
            val a = Morphology.occupied(mask, x, y)
            val b = Morphology.occupied(mask, x + 1, y)
            val c = Morphology.occupied(mask, x, y + 1)
            val d = Morphology.occupied(mask, x + 1, y + 1)
            val count = listOf(a, b, c, d).count { it }
            if (count == 1) singles++ else if (count == 3) triples++ else if (count == 2 && (a && d || b && c)) diagonals++
        }
        return (singles - triples + (if (connectivity == 8) -2 else 2) * diagonals) / 4
    }
}
