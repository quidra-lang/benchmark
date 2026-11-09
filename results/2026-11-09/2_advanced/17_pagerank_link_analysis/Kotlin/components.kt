object Components {
    private class Frame(val node: Int, var position: Int = 0)
    fun strong(adjacency: List<List<Int>>): List<List<Int>> {
        val count = adjacency.size
        var counter = 0
        val order = IntArray(count) { -1 }
        val low = IntArray(count)
        val onStack = BooleanArray(count)
        val stack = ArrayDeque<Int>()
        val groups = mutableListOf<List<Int>>()
        for (root in 0 until count) {
            if (order[root] >= 0) continue
            order[root] = counter
            low[root] = counter++
            stack.addLast(root)
            onStack[root] = true
            val work = ArrayDeque<Frame>()
            work.addLast(Frame(root))
            while (work.isNotEmpty()) {
                val frame = work.last()
                val node = frame.node
                if (frame.position < adjacency[node].size) {
                    val child = adjacency[node][frame.position++]
                    if (order[child] < 0) {
                        order[child] = counter
                        low[child] = counter++
                        stack.addLast(child)
                        onStack[child] = true
                        work.addLast(Frame(child))
                    } else if (onStack[child]) low[node] = minOf(low[node], order[child])
                    continue
                }
                work.removeLast()
                if (work.isNotEmpty()) low[work.last().node] = minOf(low[work.last().node], low[node])
                if (low[node] == order[node]) {
                    val group = mutableListOf<Int>()
                    var member: Int
                    do {
                        member = stack.removeLast()
                        onStack[member] = false
                        group.add(member)
                    } while (member != node)
                    groups.add(group)
                }
            }
        }
        return groups
    }
    fun reachable(adjacency: List<List<Int>>, starts: List<Int>): BooleanArray {
        val seen = BooleanArray(adjacency.size)
        val stack = ArrayDeque<Int>()
        for (start in starts) if (!seen[start]) { seen[start] = true; stack.addLast(start) }
        while (stack.isNotEmpty()) for (neighbor in adjacency[stack.removeLast()]) if (!seen[neighbor]) { seen[neighbor] = true; stack.addLast(neighbor) }
        return seen
    }
    fun distances(adjacency: List<List<Int>>, starts: List<Int>): IntArray {
        val distance = IntArray(adjacency.size) { -1 }
        val queue = ArrayDeque<Int>()
        for (start in starts) if (distance[start] < 0) { distance[start] = 0; queue.addLast(start) }
        while (queue.isNotEmpty()) {
            val node = queue.removeFirst()
            for (neighbor in adjacency[node]) if (distance[neighbor] < 0) { distance[neighbor] = distance[node] + 1; queue.addLast(neighbor) }
        }
        return distance
    }
    fun weak(neighbors: List<List<Int>>): IntArray {
        val labels = IntArray(neighbors.size) { -1 }
        var count = 0
        for (start in labels.indices) {
            if (labels[start] >= 0) continue
            labels[start] = count
            val stack = ArrayDeque<Int>()
            stack.addLast(start)
            while (stack.isNotEmpty()) for (neighbor in neighbors[stack.removeLast()]) if (labels[neighbor] < 0) { labels[neighbor] = count; stack.addLast(neighbor) }
            count++
        }
        return labels
    }
}
