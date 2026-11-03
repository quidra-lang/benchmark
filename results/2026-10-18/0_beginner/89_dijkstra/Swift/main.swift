let edges = [
    (0, 1, 7), (0, 2, 3), (0, 3, 9), (1, 2, 2), (2, 4, 6), (1, 3, 3), (3, 4, 4), (3, 5, 5),
    (4, 5, 3), (4, 6, 8), (5, 6, 4),
]
var weight = [[Int]](repeating: [Int](repeating: 0, count: 7), count: 7)
for (a, b, w) in edges {
    weight[a][b] = w
    weight[b][a] = w
}
var distance = [Int](repeating: Int.max, count: 7), previous = [Int](repeating: -1, count: 7)
distance[0] = 0
var done = [Bool](repeating: false, count: 7)
for _ in 0..<7 {
    let u = (0..<7).filter { !done[$0] }.min { distance[$0] < distance[$1] }!
    done[u] = true
    for v in 0..<7 where weight[u][v] > 0 {
        if distance[u] + weight[u][v] < distance[v] {
            distance[v] = distance[u] + weight[u][v]
            previous[v] = u
        }
    }
}
let names = Array("ABCDEFG")
for v in 0..<7 {
    var path = [String](), u = v
    while u >= 0 {
        path.append(String(names[u]))
        u = previous[u]
    }
    print("\(names[v]): distance=\(distance[v]) path=\(path.reversed().joined(separator: "-"))")
}
