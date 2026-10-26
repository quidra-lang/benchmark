data class Split(val attribute: Attribute, val point: Int) {
    fun goesLeft(value: Int): Boolean = if (attribute.integer) 2 * value <= point else value == point
    fun condition(left: Boolean): String = attribute.name + if (attribute.integer)
        (if (left) " <= " else " > ") + halfText(point)
        else (if (left) " = " else " != ") + attribute.values[point]
    companion object {
        fun halfText(value: Int): String = "${value / 2}.${5 * (value % 2)}"
    }
}
data class Surrogate(val split: Split, val left: Boolean, val score: Int) {
    fun goesLeft(value: Int): Boolean = split.goesLeft(value) == left
}
data class Candidate(val split: Split, val leftCounts: IntArray, val rightCounts: IntArray) {
    val leftSize: Int get() = leftCounts.sum()
    val rightSize: Int get() = rightCounts.sum()
    fun quality(): Fraction = Impurity.quality(leftCounts, rightCounts)
}
class Node(val number: Int, val depth: Int, val counts: IntArray) {
    val size = counts.sum()
    val prediction = Impurity.majority(counts)
    val errors = Impurity.errors(counts)
    var split: Split? = null
    var surrogates = emptyList<Surrogate>()
    var defaultLeft = false
    lateinit var left: Node
    lateinit var right: Node
}

class TreeBuilder(private val attributes: List<Attribute>, private val classes: Int, private val settings: Settings) {
    fun candidates(attribute: Attribute, rows: List<Row>, labels: List<Int>, classCount: Int): List<Candidate> {
        val groups = sortedMapOf<Int, IntArray>()
        val total = IntArray(classCount)
        for (i in rows.indices) {
            groups.getOrPut(rows[i].value(attribute)) { IntArray(classCount) }[labels[i]]++
            total[labels[i]]++
        }
        val found = mutableListOf<Candidate>()
        if (groups.size < 2) return found
        val values = groups.keys.toList()
        if (attribute.integer) {
            val left = IntArray(classCount)
            for (i in 0 until values.lastIndex) {
                for (k in 0 until classCount) left[k] += groups.getValue(values[i])[k]
                val right = IntArray(classCount) { total[it] - left[it] }
                found += Candidate(Split(attribute, values[i] + values[i + 1]), left.copyOf(), right)
            }
        } else for (value in values) {
            val left = groups.getValue(value)
            found += Candidate(Split(attribute, value), left, IntArray(classCount) { total[it] - left[it] })
        }
        return found
    }
    fun bestSplit(rows: List<Row>, considered: List<Attribute>): Candidate? {
        var best: Candidate? = null
        val labels = rows.map { it.label }
        for (attribute in considered)
            for (candidate in candidates(attribute, rows, labels, classes))
                if (candidate.leftSize >= settings.minLeaf && candidate.rightSize >= settings.minLeaf
                    && (best == null || candidate.quality() > best.quality())) best = candidate
        return best
    }
    private fun findSurrogates(rows: List<Row>, primary: Split): List<Surrogate> {
        val directions = rows.map { if (primary.goesLeft(it.value(primary.attribute))) 0 else 1 }
        val leftSize = directions.count { it == 0 }
        val baseline = maxOf(leftSize, rows.size - leftSize)
        val found = mutableListOf<Surrogate>()
        for (attribute in attributes) {
            if (attribute.index == primary.attribute.index) continue
            var best: Surrogate? = null
            for (candidate in candidates(attribute, rows, directions, 2)) {
                val agreement = candidate.leftCounts[0] + candidate.rightCounts[1]
                val surrogate = Surrogate(candidate.split, agreement >= rows.size - agreement, maxOf(agreement, rows.size - agreement))
                if (best == null || surrogate.score > best.score) best = surrogate
            }
            if (best != null && best.score > baseline) found += best
        }
        return found.sortedWith(compareByDescending<Surrogate> { it.score }.thenBy { it.split.attribute.index }).take(settings.maxSurrogates)
    }
    fun grow(rows: List<Row>): Node = growNode(rows, 1, 0)
    private fun growNode(rows: List<Row>, number: Int, depth: Int): Node {
        val node = Node(number, depth, Impurity.counts(rows, classes))
        if (node.errors == 0 || depth == settings.maxDepth || node.size < settings.minSplit) return node
        val best = bestSplit(rows, attributes) ?: return node
        if (!Impurity.improves(best.quality(), node.counts)) return node
        val split = best.split
        val (left, right) = rows.partition { split.goesLeft(it.value(split.attribute)) }
        node.split = split
        node.surrogates = findSurrogates(rows, split)
        node.defaultLeft = left.size >= right.size
        node.left = growNode(left, 2 * number, depth + 1)
        node.right = growNode(right, 2 * number + 1, depth + 1)
        return node
    }
}
