func find(_ parent: inout [Int], _ v: Int) -> Int {
    if parent[v] != v {
        let previous = parent[v]
        let root = find(&parent, previous)
        parent[v] = root
    }
    return parent[v]
}

let edges = [
    (0, 1, 7), (2, 0, 4), (1, 2, 9), (1, 3, 14), (3, 2, 6), (2, 4, 3), (4, 3, 5), (5, 3, 11),
    (4, 6, 16), (6, 5, 8), (7, 5, 12), (6, 7, 2), (7, 4, 10),
]
var parent = Array(0..<8), accepted = 0, skipped = 0, total = 0
let names = Array("ABCDEFGH")
for (u, v, weight) in edges.sorted(by: { $0.2 < $1.2 }) {
    let a = find(&parent, u), b = find(&parent, v)
    if a == b {
        skipped += 1
        continue
    }
    parent[a] = b
    accepted += 1
    total += weight
    print("\(names[min(u, v)])-\(names[max(u, v)]) \(weight)")
    if accepted == 7 { break }
}
print("total weight: \(total)")
print("skipped: \(skipped)")
