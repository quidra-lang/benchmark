import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

object Dendrogram {
    fun children(merges: List<Agglomerative.Merge>, count: Int): Array<IntArray> {
        val minimum = IntArray(2 * count - 1) { if (it < count) it else 0 }
        return Array(merges.size) { step ->
            val merge = merges[step]
            val pair = if (minimum[merge.a] < minimum[merge.b]) intArrayOf(merge.a, merge.b) else intArrayOf(merge.b, merge.a)
            minimum[count + step] = min(minimum[merge.a], minimum[merge.b])
            pair
        }
    }

    fun leafOrder(children: Array<IntArray>, count: Int): IntArray {
        val order = mutableListOf<Int>()
        val pending = ArrayDeque<Int>()
        pending.addLast(count + children.size - 1)
        while (pending.isNotEmpty()) {
            val node = pending.removeLast()
            if (node < count) order.add(node)
            else { pending.addLast(children[node - count][1]); pending.addLast(children[node - count][0]) }
        }
        return order.toIntArray()
    }

    fun column(height: Double, maximum: Double, width: Int): Int {
        val position = floor(height / maximum * width)
        return if (position > width) width + 1 else position.toInt()
    }
    private fun mark(grid: Array<IntArray>, row: Int, column: Int, priority: Int) { grid[row][column] = max(grid[row][column], priority) }

    fun rows(merges: List<Agglomerative.Merge>, children: Array<IntArray>, order: IntArray, idents: List<String>, labels: List<String>, maximum: Double, cutColumns: IntArray, width: Int): List<String> {
        val count = order.size
        val grid = Array(count) { IntArray(width + 1) }
        val anchor = IntArray(2 * count - 1)
        for (row in 0 until count) anchor[order[row]] = row
        for (x in cutColumns) if (x <= width) for (row in 0 until count) mark(grid, row, x, 1)
        val columns = merges.map { column(it.height, maximum, width) }.toIntArray()
        for (step in children.indices) {
            val upper = children[step][0]
            val lower = children[step][1]
            val x = columns[step]
            mark(grid, anchor[upper], x, 4)
            mark(grid, anchor[lower], x, 4)
            for (row in anchor[upper] + 1 until anchor[lower]) mark(grid, row, x, 3)
            for (child in children[step]) {
                val start = if (child < count) 0 else columns[child - count] + 1
                for (position in start until x) mark(grid, anchor[child], position, 2)
            }
            anchor[count + step] = (anchor[upper] + anchor[lower]) / 2
        }
        val idWidth = idents.maxOf(String::length)
        val labelWidth = labels.maxOf(String::length)
        val rows = mutableListOf<String>()
        for (row in 0 until count) {
            val leaf = order[row]
            val text = buildString {
                append(idents[leaf].padEnd(idWidth)).append(' ').append(labels[leaf].padEnd(labelWidth)).append(' ')
                for (mark in grid[row]) append(" :-|+"[mark])
            }
            rows.add(text.trimEnd())
        }
        rows.add(" ".repeat(idWidth + labelWidth + 2) + (0..width).joinToString("") { if (it % 10 == 0) "+" else "-" })
        return rows
    }
}
