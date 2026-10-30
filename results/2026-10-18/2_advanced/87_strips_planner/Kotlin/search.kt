import java.util.PriorityQueue
data class SearchResult(var status: String, var plan: List<Int> = emptyList(), var expanded: Int = 0, var generated: Int = 0)
data class SearchNode(val state: State, val g: Long, val depth: Int, val parent: Int?, val action: Int?)
data class SearchKey(val f: Long, val h: Long, val serial: Int)
object Search {
    fun applicable(action: Action, state: State): Boolean = state.containsAll(action.pre) && action.neg.none {
        it in state
    }
    fun apply(action: Action, state: State): State = (state - action.del) + action.add
    fun run(g: Grounding, start: State, algorithm: String, heuristic: String, budget: Int, weight: Int): SearchResult {
        if (algorithm == "ehc") return ehc(g, start, heuristic, budget)
        val result = SearchResult("exhausted")
        val initialH = Heuristics.value(g, start, heuristic)
        if (initialH >= Heuristics.INFINITY) {
            result.status = "dead end"; return result
        }
        val nodes = mutableListOf(SearchNode(start, 0, 0, null, null))
        val frontier = PriorityQueue(compareBy<SearchKey> {
            it.f
        }.thenBy {
            it.h
        }.thenBy {
            it.serial
        })
        val table = mutableMapOf(start to 0L)
        fun key(cost: Long, depth: Int, h: Long, serial: Int): SearchKey {
            val f = when (algorithm) {
                "bfs" -> depth.toLong(); "ucs" -> cost; "gbfs" -> h; "astar" -> cost + h; else -> cost + weight * h
            }
            return SearchKey(f, h, serial)
        }
        frontier.add(key(0, 0, initialH, 0))
        while (frontier.isNotEmpty()) {
            val index = frontier.remove().serial
            val node = nodes[index]
            val state = node.state
            if (algorithm in listOf("ucs", "astar", "wastar") && node.g > table.getValue(state)) continue
            if (state.containsAll(g.goals)) {
                result.status = "solved"
                var current = index
                val plan = mutableListOf<Int>()
                while (nodes[current].parent != null) {
                    plan.add(nodes[current].action!!); current = nodes[current].parent!!
                }
                result.plan = plan.reversed()
                return result
            }
            if (result.expanded == budget) {
                result.status = "budget"; return result
            }
            result.expanded++
            for ((a, action) in g.actions.withIndex()) if (applicable(action, state)) {
                result.generated++
                val next = apply(action, state)
                val cost = node.g + action.cost
                val old = table[next]
                if (old != null && (algorithm in listOf("bfs", "gbfs") || old <= cost)) continue
                table[next] = cost
                val h = Heuristics.value(g, next, heuristic)
                if (h >= Heuristics.INFINITY) continue
                val serial = nodes.size
                nodes.add(SearchNode(next, cost, node.depth + 1, index, a))
                frontier.add(key(cost, node.depth + 1, h, serial))
            }
        }
        return result
    }
    fun ehc(g: Grounding, start: State, heuristic: String, budget: Int): SearchResult {
        val result = SearchResult("stuck")
        var current = start
        var hc = Heuristics.value(g, start, heuristic)
        if (hc >= Heuristics.INFINITY) {
            result.status = "dead end"; return result
        }
        while (true) {
            if (current.containsAll(g.goals)) {
                result.status = "solved"; return result
            }
            val queue = ArrayDeque<Pair<State, List<Int>>>()
            queue.addLast(Pair(current, emptyList()))
            val visited = mutableSetOf(current)
            var improvement: Triple<State, Long, List<Int>>? = null
            while (queue.isNotEmpty() && improvement == null) {
                val (state, path) = queue.removeFirst()
                if (result.expanded == budget) {
                    result.status = "budget"; return result
                }
                result.expanded++
                for (action in Heuristics.relaxed(g, state).helpful) {
                    result.generated++
                    val next = apply(g.actions[action], state)
                    if (!visited.add(next)) continue
                    val h = Heuristics.value(g, next, heuristic)
                    if (h >= Heuristics.INFINITY) continue
                    val nextPath = path + action
                    if (h < hc) {
                        improvement = Triple(next, h, nextPath); break
                    }
                    queue.addLast(Pair(next, nextPath))
                }
            }
            val found = improvement ?: return result
            current = found.first; hc = found.second; result.plan = result.plan + found.third
        }
    }
}
