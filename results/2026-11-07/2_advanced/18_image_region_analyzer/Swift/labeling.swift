struct Labeling {
    let labels: [[Int]]
    let count: Int
    let provisional: Int
}

private func find(_ parents: inout [Int], _ original: Int) -> Int {
    var label = original
    while parents[label] != label {
        let parent = parents[label]
        parents[label] = parents[parent]
        label = parents[label]
    }
    return label
}
private func union(_ parents: inout [Int], _ first: Int, _ second: Int) {
    let a = find(&parents, first)
    let b = find(&parents, second)
    if a != b { parents[max(a, b)] = min(a, b) }
}
func labelComponents(_ mask: Mask, _ connectivity: Int) -> Labeling {
    let height = mask.count
    let width = mask[0].count
    let previous = connectivity == 4 ? [Point(-1, 0), Point(0, -1)] : [Point(-1, 0), Point(-1, -1), Point(0, -1), Point(1, -1)]
    var provisional = Array(repeating: Array(repeating: 0, count: width), count: height)
    var parents = [0]
    for y in 0..<height { for x in 0..<width {
        if !mask[y][x] { continue }
        var neighbors: [Int] = []
        for offset in previous {
            let nx = x + offset.x
            let ny = y + offset.y
            if occupied(mask, nx, ny) { neighbors.append(provisional[ny][nx]) }
        }
        if neighbors.isEmpty { provisional[y][x] = parents.count; parents.append(parents.count) }
        else {
            provisional[y][x] = neighbors[0]
            for other in neighbors.dropFirst() { union(&parents, neighbors[0], other) }
        }
    } }
    var numbers = Array(repeating: 0, count: parents.count)
    var labels = Array(repeating: Array(repeating: 0, count: width), count: height)
    var count = 0
    for y in 0..<height { for x in 0..<width {
        if provisional[y][x] == 0 { continue }
        let root = find(&parents, provisional[y][x])
        if numbers[root] == 0 { count += 1; numbers[root] = count }
        labels[y][x] = numbers[root]
    } }
    return Labeling(labels: labels, count: count, provisional: parents.count - 1)
}
func bitQuadEuler(_ mask: Mask, _ connectivity: Int) -> Int {
    var singles = 0
    var triples = 0
    var diagonals = 0
    for y in -1..<mask.count { for x in -1..<mask[0].count {
        let tl = occupied(mask, x, y)
        let tr = occupied(mask, x + 1, y)
        let bl = occupied(mask, x, y + 1)
        let br = occupied(mask, x + 1, y + 1)
        let count = [tl, tr, bl, br].filter { $0 }.count
        if count == 1 { singles += 1 }
        else if count == 3 { triples += 1 }
        else if count == 2 && ((tl && br) || (tr && bl)) { diagonals += 1 }
    } }
    return (singles - triples + (connectivity == 8 ? -2 * diagonals : 2 * diagonals)) / 4
}
