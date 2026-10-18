func dfs(_ v: Int, _ graph: [[Bool]], _ seen: inout [Bool], _ order: inout [Int]) {
    seen[v] = true
    order.append(v)
    for w in graph.indices where graph[v][w] && !seen[w] { dfs(w,graph,&seen,&order) }
}
var graph = [[Bool]](repeating: [Bool](repeating: false, count: 9), count: 9)
let edges = [(5,0),(3,8),(7,2),(1,6),(0,2),(5,3),(7,5),(6,4),(8,7)]
for (a,b) in edges {
    graph[a][b] = true
    graph[b][a] = true
}
var seen = [Bool](repeating: false, count: 9), depth = [Int]()
dfs(0,graph,&seen,&depth)
seen = [Bool](repeating: false, count: 9)
var queue = [0], head = 0, breadth = [Int]()
seen[0] = true
while head < queue.count {
    let v = queue[head]
    head += 1
    breadth.append(v)
    for w in 0..<9 where graph[v][w] && !seen[w] {
        seen[w] = true
        queue.append(w)
    }
}
var components = [[Int]]()
seen = [Bool](repeating: false, count: 9)
for v in 0..<9 where !seen[v] {
    var component = [Int]()
    dfs(v,graph,&seen,&component)
    components.append(component.sorted())
}
print("DFS: \(depth.map(String.init).joined(separator: " "))")
print("BFS: \(breadth.map(String.init).joined(separator: " "))")
print("components: \(components.count)")
for (i,component) in components.enumerated() {
    print("component \(i + 1): \(component.map(String.init).joined(separator: " "))")
}
