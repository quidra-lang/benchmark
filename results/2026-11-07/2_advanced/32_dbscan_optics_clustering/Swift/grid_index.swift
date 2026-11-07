struct Cell: Hashable {
    let x: Int
    let y: Int
}

func distance(_ a: Point, _ b: Point) -> Int {
    let dx = a.x - b.x
    let dy = a.y - b.y
    return dx * dx + dy * dy
}

struct Grid {
    let radius: Int
    let cells: [Cell: [Int]]
    let neighborhoods: [[Int]]
    let candidates: Int
    let busiest: (Int, Int, Int)
    let pairs: Int
    let brutePairs: Int
    let consistent: Bool
    let occupancy: [Int: Int]

    init(_ points: [Point], _ radius: Int) {
        var cells: [Cell: [Int]] = [:]
        for (i, point) in points.enumerated() {
            cells[Cell(x: point.x / radius, y: point.y / radius), default: []].append(i)
        }
        var neighborhoods: [[Int]] = []
        var candidates = 0
        var bruteTotal = 0
        var consistent = true
        for point in points {
            let gx = point.x / radius
            let gy = point.y / radius
            var neighbors: [Int] = []
            for row in (gy - 1)...(gy + 1) {
                for column in (gx - 1)...(gx + 1) {
                    for j in cells[Cell(x: column, y: row)] ?? [] {
                        candidates += 1
                        if distance(point, points[j]) <= radius * radius { neighbors.append(j) }
                    }
                }
            }
            let brute = points.filter { distance(point, $0) <= radius * radius }.count
            consistent = consistent && brute == neighbors.count
            bruteTotal += brute
            neighborhoods.append(neighbors)
        }
        let key = cells.keys.min { a, b in
            let first = cells[a]!.count
            let second = cells[b]!.count
            if first != second { return first > second }
            return a.y == b.y ? a.x < b.x : a.y < b.y
        }!
        var occupancy: [Int: Int] = [:]
        for members in cells.values { occupancy[members.count, default: 0] += 1 }
        self.radius = radius
        self.cells = cells
        self.neighborhoods = neighborhoods
        self.candidates = candidates
        busiest = (key.x, key.y, cells[key]!.count)
        pairs = (neighborhoods.reduce(0) { $0 + $1.count } - points.count) / 2
        brutePairs = (bruteTotal - points.count) / 2
        self.consistent = consistent
        self.occupancy = occupancy
    }
}
