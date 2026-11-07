struct Layering {
    let heights: [Int], labels: [Int], before: Int, rounds: Int, promotions: [(Int, Int, Int)]
}
enum AcyclicLayering {
    static func sequence(_ n: Int, _ edges: [(Int, Int)]) -> [Int] {
        var remaining = Set(0..<n), head: [Int] = [], tail: [Int] = []
        while !remaining.isEmpty {
            let degrees = remaining.sorted().map {
                v in (v, edges.filter {
                    $0.0 == v && remaining.contains($0.1)
                }.count, edges.filter {
                    $0.1 == v && remaining.contains($0.0)
                }.count)
            }
            let chosen: Int
            if let sink = degrees.first(where: {
                $0.1 == 0
            }) {
                chosen = sink.0;
                tail.insert(chosen, at: 0)
            }
            else if let source = degrees.first(where: {
                $0.2 == 0
            }) {
                chosen = source.0;
                head.append(chosen)
            }
            else {
                chosen = degrees.min {
                    let x = $0.1 - $0.2, y = $1.1 - $1.2;
                    return x == y ? $0.0 < $1.0 : x > y
                }!.0;
                head.append(chosen)
            }
            remaining.remove(chosen)
        }
        return head + tail
    }
    static func assign(_ n: Int, _ edges: [(Int, Int)], _ coffman: Bool, _ width: Int, _ promotion: Bool) -> Layering {
        var upper = Array(repeating: [Int](), count: n), lower = upper
        for (a, b) in edges {
            upper[b].append(a);
            lower[a].append(b)
        }
        for i in 0..<n {
            upper[i].sort();
            lower[i].sort()
        }
        var labels = Array(repeating: 0, count: n), heights = Array(repeating: -1, count: n)
        if coffman {
            for k in 1...n {
                let v = (0..<n).filter {
                    labels[$0] == 0 && upper[$0].allSatisfy {
                        labels[$0] > 0
                    }
                }.min {
                    let a = upper[$0].map {
                        labels[$0]
                    }.sorted(by: >), b = upper[$1].map {
                        labels[$0]
                    }.sorted(by: >)
                    return a == b ? $0 < $1 : a.lexicographicallyPrecedes(b)
                }!
                labels[v] = k
            }
            var current = 0, count = 0
            for _ in 0..<n {
                let v = (0..<n).filter {
                    heights[$0] < 0 && lower[$0].allSatisfy {
                        heights[$0] >= 0
                    }
                }.max {
                    labels[$0] < labels[$1]
                }!
                if count == width || lower[v].contains(where: {
                    heights[$0] == current
                }) {
                    current += 1;
                    count = 0
                }
                heights[v] = current;
                count += 1
            }
        } else {
            func height(_ v: Int) -> Int {
                if heights[v] >= 0 {
                    return heights[v]
                }
                var h = 0
                for u in lower[v] {
                    h = max(h, height(u) + 1)
                }
                heights[v] = h
                return h
            }
            for v in 0..<n {
                _ = height(v)
            }
        }
        let before = edges.reduce(0) {
            $0 + heights[$1.0] - heights[$1.1] - 1
        }
        var rounds = 0, promotions: [(Int, Int, Int)] = []
        if promotion {
            func promote(_ v: Int) -> Int {
                var diff = 0
                for u in upper[v] where heights[u] == heights[v] + 1 {
                    diff += promote(u)
                }
                heights[v] += 1
                return diff + lower[v].count - upper[v].count
            }
            while true {
                rounds += 1
                var changed = false
                for v in 0..<n where !upper[v].isEmpty {
                    let saved = heights, diff = promote(v)
                    if diff < 0 {
                        promotions.append((rounds, v, diff));
                        changed = true
                    } else {
                        heights = saved
                    }
                }
                if !changed {
                    break
                }
            }
        }
        return Layering(heights: heights, labels: labels, before: before, rounds: rounds, promotions: promotions)
    }
}
