data class Edge(val first: String, val second: String, val shared: Int)

class ConflictGraph(vertices: List<String>, students: Collection<List<String>>) {
    val vertices = vertices.sorted()
    private val shared = this.vertices.associateWith { sortedMapOf<String, Int>() }

    init {
        for (ids in students)
            for (i in ids.indices)
                for (j in i + 1 until ids.size) {
                    val first = ids[i]
                    val second = ids[j]
                    val left = shared.getValue(first)
                    val right = shared.getValue(second)
                    left[second] = left.getOrDefault(second, 0) + 1
                    right[first] = right.getOrDefault(first, 0) + 1
                }
    }

    fun neighbours(id: String): Map<String, Int> = shared[id] ?: emptyMap()
    fun degree(id: String): Int = neighbours(id).size
    fun sharedTotal(id: String): Int = neighbours(id).values.sum()

    fun edges(): List<Edge> = buildList {
        for (first in vertices)
            for ((second, count) in neighbours(first))
                if (first < second) add(Edge(first, second, count))
    }

    fun components(): List<List<String>> {
        val seen = mutableSetOf<String>()
        val components = mutableListOf<List<String>>()
        for (vertex in vertices) {
            if (!seen.add(vertex)) continue
            val component = mutableListOf(vertex)
            var index = 0
            while (index < component.size) {
                for (neighbour in neighbours(component[index]).keys)
                    if (seen.add(neighbour)) component += neighbour
                index++
            }
            components += component.sorted()
        }
        return components.sortedWith(compareByDescending<List<String>> { it.size }.thenBy { it.first() })
    }

    fun greedyClique(initial: List<String>): List<String> {
        val candidates = initial.toMutableList()
        val clique = mutableListOf<String>()
        while (candidates.isNotEmpty()) {
            val chosen = candidates.minWith(compareByDescending<String> { degree(it) }.thenBy { it })
            clique += chosen
            candidates.removeAll { it !in neighbours(chosen) }
        }
        return clique
    }

    fun kempeChain(assignment: Map<String, Int>, start: String, first: Int, second: Int): List<String> {
        val seen = mutableSetOf(start)
        val chain = mutableListOf(start)
        var index = 0
        while (index < chain.size) {
            for (neighbour in neighbours(chain[index]).keys) {
                val slot = assignment[neighbour]
                if ((slot == first || slot == second) && seen.add(neighbour)) chain += neighbour
            }
            index++
        }
        return chain.sorted()
    }

    companion object {
        fun reachable(arrows: Map<String, List<String>>, source: String, target: String): Boolean {
            val stack = mutableListOf(source)
            val seen = mutableSetOf(source)
            while (stack.isNotEmpty()) {
                val node = stack.removeAt(stack.lastIndex)
                if (node == target) return true
                for (next in arrows[node].orEmpty())
                    if (seen.add(next)) stack += next
            }
            return false
        }
    }
}
