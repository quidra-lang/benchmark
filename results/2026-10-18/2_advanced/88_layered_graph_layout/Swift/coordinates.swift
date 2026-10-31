struct VertexPair: Hashable {
    let a: Int, b: Int
    init(_ a: Int, _ b: Int) {
        self.a = a;
        self.b = b
    }
    static func unordered(_ a: Int, _ b: Int) -> Self {
        Self(min(a, b), max(a, b))
    }
}
struct Coordinates {
    let x: [Int], aligned: [[Int]], blocks: [Int], widths: [Int], smallest: Int, conflicts: Int, left: [Int], right: [Int]
    static func floorHalf(_ value: Int) -> Int {
        value / 2 - (value % 2 < 0 ? 1 : 0)
    }
    static func assign(_ n: Int, _ order: [[Int]], _ layer: [Int], _ upper: [[Int]], _ lower: [[Int]], _ width: [Int], _ vertical: Bool, _ nodeSep: Int, _ dummySep: Int) -> Self {
        let vertices = layer.count, positions = Crossing.positions(order, vertices)
        let left = width.map {
            vertical ? ($0 - 1) / 2 : 0
        }, right = width.indices.map {
            vertical ? width[$0] - 1 - left[$0] : 0
        }
        func separation(_ a: Int, _ b: Int) -> Int {
            right[a] + left[b] + 1 + (a < n && b < n ? nodeSep : dummySep)
        }
        var marked: Set<VertexPair> = []
        for i in 0..<max(0, order.count - 1) {
            let a = order[i], b = order[i + 1]
            var k0 = 0, t = 0
            for l1 in b.indices {
                let v = b[l1], inner = v >= n && upper[v][0] >= n
                if inner || l1 + 1 == b.count {
                    let k1 = inner ? positions[upper[v][0]] : a.count - 1
                    for l in t...l1 {
                        let w = b[l]
                        for u in upper[w] where positions[u] < k0 || positions[u] > k1 {
                            marked.insert(.unordered(u, w))
                        }
                    }
                    t = l1 + 1;
                    k0 = k1
                }
            }
        }
        var layouts: [[Int]] = [], blocks: [Int] = [], widths: [Int] = [], lows: [Int] = [], highs: [Int] = []
        for variant in 0..<4 {
            let down = variant >= 2, rightScan = variant % 2 == 1
            func q(_ v: Int) -> Int {
                rightScan ? order[layer[v]].count - 1 - positions[v] : positions[v]
            }
            var root = Array(0..<vertices), align = root
            let layers = down ? Array(order.indices.reversed()) : Array(order.indices)
            for i in layers.dropFirst() {
                let scan = rightScan ? Array(order[i].reversed()) : order[i]
                var rho = -1
                for v in scan {
                    let reference = (down ? lower[v] : upper[v]).sorted {
                        q($0) < q($1)
                    }
                    if reference.isEmpty {
                        continue
                    }
                    for m in [(reference.count - 1) / 2, reference.count / 2] {
                        let u = reference[m]
                        if align[v] == v && !marked.contains(.unordered(u, v)) && rho < q(u) {
                            align[u] = v;
                            root[v] = root[u];
                            align[v] = root[v];
                            rho = q(u)
                        }
                    }
                }
            }
            let roots = Set(root)
            blocks.append(roots.count)
            var edges: [VertexPair: Int] = [:]
            for row in order {
                let scan = rightScan ? Array(row.reversed()) : row
                for i in 1..<scan.count {
                    let a = scan[i - 1], b = scan[i], delta = rightScan ? separation(b, a) : separation(a, b), pair = VertexPair(root[a], root[b])
                    edges[pair] = max(edges[pair] ?? 0, delta)
                }
            }
            var incoming = Array(repeating: [(Int, Int)](), count: vertices), outgoing = incoming, degree = Array(repeating: 0, count: vertices)
            for (pair, delta) in edges {
                incoming[pair.b].append((pair.a, delta));
                outgoing[pair.a].append((pair.b, delta));
                degree[pair.b] += 1
            }
            var ready = Set(roots.filter {
                degree[$0] == 0
            }), topology: [Int] = []
            while let v = ready.min() {
                ready.remove(v);
                topology.append(v)
                for (u, _) in outgoing[v] {
                    degree[u] -= 1;
                    if degree[u] == 0 {
                        ready.insert(u)
                    }
                }
            }
            var y1 = Array(repeating: 0, count: vertices)
            for v in topology {
                y1[v] = incoming[v].map {
                    y1[$0.0] + $0.1
                }.max() ?? 0
            }
            var y2 = y1
            for v in topology.reversed() {
                if let minimum = outgoing[v].map({
                    y2[$0.0] - $0.1
                }).min() {
                    y2[v] = max(y1[v], minimum)
                }
            }
            let x = root.map {
                rightScan ? -y2[$0] : y2[$0]
            }, lo = (0..<vertices).map {
                x[$0] - left[$0]
            }.min()!, hi = (0..<vertices).map {
                x[$0] + right[$0]
            }.max()!
            lows.append(lo);
            highs.append(hi);
            widths.append(hi - lo + 1);
            layouts.append(x)
        }
        let smallest = (0..<4).min {
            widths[$0] == widths[$1] ? $0 < $1 : widths[$0] < widths[$1]
        }!
        for i in 0..<4 {
            let delta = i % 2 == 0 ? lows[smallest] - lows[i] : highs[smallest] - highs[i]
            layouts[i] = layouts[i].map {
                $0 + delta
            }
        }
        var x = (0..<vertices).map {
            v in let sorted = layouts.map {
                $0[v]
            }.sorted();
            return floorHalf(sorted[1] + sorted[2])
        }
        let minimum = (0..<vertices).map {
            x[$0] - left[$0]
        }.min()!
        x = x.map {
            $0 - minimum
        }
        return Self(x: x, aligned: layouts, blocks: blocks, widths: widths, smallest: smallest, conflicts: marked.count, left: left, right: right)
    }
}
