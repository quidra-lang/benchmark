data class Decision(val node: Node, val rows: Int, val leafError: Int, val subtreeError: Int, val pruned: Boolean)
data class PruningResult(val tree: PrunedTree, val decisions: List<Decision>)
data class SequenceTree(val alpha: Fraction, val tree: PrunedTree)

object Pruning {
    fun reducedError(root: Node, rows: List<Row>): PruningResult {
        val reached = mutableMapOf<Int, IntArray>()
        val tree = PrunedTree(root)
        for (row in rows)
            for (node in tree.route(row).path) {
                val tally = reached.getOrPut(node.number) { IntArray(2) }
                tally[0]++
                if (node.prediction != row.label) tally[1]++
            }
        val decisions = mutableListOf<Decision>()
        val cut = mutableSetOf<Int>()
        fun decide(node: Node): Int {
            val tally = reached[node.number] ?: IntArray(2)
            val leafError = tally[1]
            if (node.split == null) return leafError
            val subtreeError = decide(node.left) + decide(node.right)
            val pruned = leafError <= subtreeError
            decisions += Decision(node, tally[0], leafError, subtreeError, pruned)
            if (pruned) cut += node.number
            return if (pruned) leafError else subtreeError
        }
        decide(root)
        return PruningResult(PrunedTree(root, cut), decisions)
    }
    fun costComplexity(root: Node): List<SequenceTree> {
        var tree = PrunedTree(root)
        val sequence = mutableListOf(SequenceTree(Fraction(0, 1), tree))
        while (!tree.isLeaf(root)) {
            var alpha: Fraction? = null
            val weakest = mutableSetOf<Int>()
            for (node in tree.internalNodes()) {
                val leaves = tree.leaves(node)
                val value = Fraction((node.errors - leaves.sumOf { it.errors }).toLong(), (leaves.size - 1).toLong())
                if (alpha == null || value < alpha) { alpha = value; weakest.clear(); weakest += node.number }
                else if (value.compareTo(alpha) == 0) weakest += node.number
            }
            tree = PrunedTree(root, tree.cut + weakest)
            sequence += SequenceTree(requireNotNull(alpha), tree)
        }
        return sequence
    }
}
