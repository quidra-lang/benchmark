struct Crossing {
    let point: Point, ar: Int, ae: Int, br: Int, be: Int, t: Fraction, u: Fraction
}
struct Node {
    let point: Point, crossing: Int?, enter: Bool
}
final class Graph {
    var nodes: [[[Node]]] = [[], []]
    var locations: [[(Int, Int)]] = []
    var ordered: [(Point, Bool)] = []
    var order: [Int] = []
    let na: Int, nb: Int
    init(_ a: Rings, _ b: Rings) {
        na = a.filter {
            RingOps.interior($0[0], b)
        }.count
        nb = b.filter {
            RingOps.interior($0[0], a)
        }.count
        var crossings: [Crossing] = []
        for (ar, r) in a.enumerated() {
            for ae in r.indices {
                for (br, q) in b.enumerated() {
                    for be in q.indices {
                        if let (point, t, u) = Intersections.crossing(r[ae], r[(ae + 1) % r.count], q[be], q[(be + 1) % q.count]) {
                            crossings.append(Crossing(point: point, ar: ar, ae: ae, br: br, be: be, t: t, u: u))
                        }
                    }
                }
            }
        }
        locations = Array(repeating: [(0, 0), (0, 0)], count: crossings.count)
        for (side, pair) in [(a, b), (b, a)].enumerated() {
            let (p, q) = pair
            for (ri, ring) in p.enumerated() {
                var list: [Node] = [], inside = RingOps.interior(ring[0], q)
                for edge in ring.indices {
                    list.append(Node(point: ring[edge], crossing: nil, enter: false))
                    let on = crossings.indices.filter {
                        side == 0 ? crossings[$0].ar == ri && crossings[$0].ae == edge : crossings[$0].br == ri && crossings[$0].be == edge
                    }.sorted {
                        side == 0 ? crossings[$0].t < crossings[$1].t : crossings[$0].u < crossings[$1].u
                    }
                    for id in on {
                        locations[id][side] = (ri, list.count)
                        list.append(Node(point: crossings[id].point, crossing: id, enter: !inside))
                        if side == 0 {
                            order.append(id);
                            ordered.append((crossings[id].point, !inside))
                        }
                        inside.toggle()
                    }
                }
                nodes[side].append(list)
            }
        }
    }
    func result(_ kind: String) -> Region {
        let inverted = kind == "UNION" ? [true, true] : kind == "DIFFERENCE" ? [true, false] : [false, false]
        var visited = Array(repeating: false, count: locations.count), rings: Rings = []
        for start in order where !visited[start] {
            var side = 0, id = start, points: Ring = []
            while true {
                let (ri, index) = locations[id][side], list = nodes[side][ri], node = list[index]
                visited[id] = true
                points.append(node.point)
                let forward = node.enter != inverted[side]
                var next = index
                repeat {
                    next = forward ? (next + 1) % list.count : (next + list.count - 1) % list.count
                    if list[next].crossing == nil {
                        points.append(list[next].point)
                    }
                } while list[next].crossing == nil
                let found = list[next].crossing!
                if found == start {
                    break
                }
                id = found
                side = 1 - side
            }
            rings.append(points)
        }
        for side in 0..<2 {
            let other = nodes[1 - side].map {
                $0.map(\.point)
            }
            for list in nodes[side] where !list.contains(where: {
                $0.crossing != nil
            }) {
                if RingOps.interior(list[0].point, other) != inverted[side] {
                    rings.append(list.map(\.point))
                }
            }
        }
        return RingOps.assemble(rings)
    }
}
