fun dfs(v: Int, graph: Array<BooleanArray>, seen: BooleanArray, order: MutableList<Int>) {
    seen[v] = true
    order.add(v)
    for (w in graph.indices) {
        if (graph[v][w] && !seen[w]) dfs(w, graph, seen, order)
    }
}

fun main() {
    val graph = Array(9) { BooleanArray(9) }
    val edges = listOf(5 to 0, 3 to 8, 7 to 2, 1 to 6, 0 to 2, 5 to 3, 7 to 5, 6 to 4, 8 to 7)
    for ((a, b) in edges) {
        graph[a][b] = true
        graph[b][a] = true
    }
    val depth = mutableListOf<Int>()
    dfs(0, graph, BooleanArray(9), depth)
    val seen = BooleanArray(9)
    val queue = ArrayDeque<Int>()
    val breadth = mutableListOf<Int>()
    seen[0] = true
    queue.addLast(0)
    while (queue.isNotEmpty()) {
        val v = queue.removeFirst()
        breadth.add(v)
        for (w in 0 until 9) {
            if (graph[v][w] && !seen[w]) {
                seen[w] = true
                queue.addLast(w)
            }
        }
    }
    val components = mutableListOf<List<Int>>()
    seen.fill(false)
    for (v in 0 until 9) {
        if (!seen[v]) {
            val component = mutableListOf<Int>()
            dfs(v, graph, seen, component)
            components.add(component.sorted())
        }
    }
    println("DFS: ${depth.joinToString(" ")}")
    println("BFS: ${breadth.joinToString(" ")}")
    println("components: ${components.size}")
    for ((i, component) in components.withIndex()) println("component ${i + 1}: ${component.joinToString(" ")}")
}
