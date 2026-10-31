let infinity = Int.max

struct Ordering {
    let core: [Int]
    let reach: [Int]
    let predecessor: [Int?]
    let points: [Int]
}

func opticsOrder(_ points: [Point], _ neighborhoods: [[Int]], _ minPts: Int) -> Ordering {
    let core = neighborhoods.enumerated().map { i, neighbors -> Int in
        if neighbors.count < minPts { return infinity }
        return neighbors.map { distance(points[i], points[$0]) }.sorted()[minPts - 1]
    }
    var reach = [Int](repeating: infinity, count: points.count)
    var predecessor = [Int?](repeating: nil, count: points.count)
    var processed = [Bool](repeating: false, count: points.count)
    var ordering: [Int] = []
    for start in points.indices {
        if processed[start] { continue }
        var seeds: Set<Int> = [start]
        while !seeds.isEmpty {
            let i = seeds.min { a, b in reach[a] == reach[b] ? points[a].id < points[b].id : reach[a] < reach[b] }!
            seeds.remove(i)
            processed[i] = true
            ordering.append(i)
            if core[i] == infinity { continue }
            for j in neighborhoods[i] {
                if processed[j] { continue }
                let candidate = max(core[i], distance(points[i], points[j]))
                if candidate < reach[j] {
                    reach[j] = candidate
                    predecessor[j] = i
                    seeds.insert(j)
                }
            }
        }
    }
    return Ordering(core: core, reach: reach, predecessor: predecessor, points: ordering)
}
