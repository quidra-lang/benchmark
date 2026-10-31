func strongComponents(_ adjacency: [[Int]]) -> [[Int]] {
    let count = adjacency.count
    var order = Array(repeating: -1, count: count)
    var low = Array(repeating: 0, count: count)
    var onStack = Array(repeating: false, count: count)
    var stack: [Int] = []
    var components: [[Int]] = []
    var counter = 0
    for root in 0..<count {
        if order[root] != -1 { continue }
        order[root] = counter
        low[root] = counter
        counter += 1
        stack.append(root)
        onStack[root] = true
        var work = [(node: root, position: 0)]
        while let frame = work.last {
            let node = frame.node
            if frame.position < adjacency[node].count {
                work[work.count - 1].position += 1
                let child = adjacency[node][frame.position]
                if order[child] == -1 {
                    order[child] = counter
                    low[child] = counter
                    counter += 1
                    stack.append(child)
                    onStack[child] = true
                    work.append((child, 0))
                } else if onStack[child] { low[node] = min(low[node], order[child]) }
                continue
            }
            work.removeLast()
            if let parent = work.last?.node { low[parent] = min(low[parent], low[node]) }
            if low[node] == order[node] {
                var component: [Int] = []
                while true {
                    let member = stack.removeLast()
                    onStack[member] = false
                    component.append(member)
                    if member == node { break }
                }
                components.append(component)
            }
        }
    }
    return components
}

func reachable(_ adjacency: [[Int]], _ starts: [Int]) -> [Bool] {
    var seen = Array(repeating: false, count: adjacency.count)
    var stack: [Int] = []
    for start in starts where !seen[start] { seen[start] = true; stack.append(start) }
    while let node = stack.popLast() {
        for neighbor in adjacency[node] where !seen[neighbor] { seen[neighbor] = true; stack.append(neighbor) }
    }
    return seen
}

func bfsDistances(_ adjacency: [[Int]], _ starts: [Int]) -> [Int] {
    var distance = Array(repeating: -1, count: adjacency.count)
    var queue: [Int] = []
    for start in starts where distance[start] == -1 { distance[start] = 0; queue.append(start) }
    var position = 0
    while position < queue.count {
        let node = queue[position]
        position += 1
        for neighbor in adjacency[node] where distance[neighbor] == -1 {
            distance[neighbor] = distance[node] + 1
            queue.append(neighbor)
        }
    }
    return distance
}

func weakComponents(_ neighbors: [[Int]]) -> [Int] {
    var labels = Array(repeating: -1, count: neighbors.count)
    var count = 0
    for start in neighbors.indices {
        if labels[start] != -1 { continue }
        labels[start] = count
        var stack = [start]
        while let node = stack.popLast() {
            for neighbor in neighbors[node] where labels[neighbor] == -1 { labels[neighbor] = count; stack.append(neighbor) }
        }
        count += 1
    }
    return labels
}
