data class Pattern(val items: List<String>, val weight: Int)
class FPNode(val item: String, val parent: Int) { var count = 0; val children = mutableMapOf<String, Int>() }
class FPTree(base: List<Pattern>, minimum: Int) {
    val header: List<String>
    val nodes = mutableListOf(FPNode("", -1))
    val links = mutableMapOf<String, MutableList<Int>>()
    val nodeCount get() = nodes.size - 1
    init {
        val supports = mutableMapOf<String, Int>()
        for (pattern in base) for (item in pattern.items) supports[item] = (supports[item] ?: 0) + pattern.weight
        header = supports.keys.filter { supports.getValue(it) >= minimum }.sortedWith(compareBy({ -supports.getValue(it) }, { it }))
        val order = header.withIndex().associate { it.value to it.index }
        for (item in header) links[item] = mutableListOf()
        for (pattern in base) {
            var cursor = 0
            for (item in pattern.items.filter { it in order }.sortedBy { order.getValue(it) }) {
                var child = nodes[cursor].children[item]
                if (child == null) { child = nodes.size; nodes += FPNode(item, cursor); nodes[cursor].children[item] = child; links.getValue(item) += child }
                nodes[child].count += pattern.weight
                cursor = child
            }
        }
    }
    fun support(item: String) = links.getValue(item).sumOf { nodes[it].count }
    fun conditionalBase(item: String) = links.getValue(item).map { index ->
        val path = mutableListOf<String>()
        var parent = nodes[index].parent
        while (parent > 0) { path += nodes[parent].item; parent = nodes[parent].parent }
        Pattern(path.reversed(), nodes[index].count)
    }
}
data class GrowthResult(val header: Int, val nodes: Int, var conditionalTrees: Int = 0, var conditionalNodes: Int = 0, val itemsets: MutableMap<List<String>, Int> = mutableMapOf())
fun fpGrowth(base: List<Pattern>, minimum: Int, maxSize: Int): GrowthResult {
    val tree = FPTree(base, minimum)
    val result = GrowthResult(tree.header.size, tree.nodeCount)
    val stack = mutableListOf(tree to emptyList<String>())
    while (stack.isNotEmpty()) {
        val (current, suffix) = stack.removeAt(stack.lastIndex)
        for (item in current.header.asReversed()) {
            val items = (suffix + item).sorted()
            result.itemsets[items] = current.support(item)
            if (items.size < maxSize) {
                val conditional = FPTree(current.conditionalBase(item), minimum)
                if (conditional.nodeCount > 0) { stack += conditional to items; result.conditionalTrees++; result.conditionalNodes += conditional.nodeCount }
            }
        }
    }
    return result
}
