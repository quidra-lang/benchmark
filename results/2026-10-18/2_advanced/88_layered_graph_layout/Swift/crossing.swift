struct Segment {
    let p: Int, q: Int, edge: Int
}
enum Crossing {
    static func positions(_ order: [[Int]], _ n: Int) -> [Int] {
        var positions = Array(repeating: 0, count: n)
        for row in order {
            for (i, v) in row.enumerated() {
                positions[v] = i
            }
        }
        return positions
    }
    static func count(_ segments: [Segment], _ positions: [Int], _ width: Int) -> Int {
        let pairs = segments.map {
            (positions[$0.p], positions[$0.q])
        }.sorted {
            $0 < $1
        }
        var c = 1
        while c < width {
            c *= 2
        }
        var tree = Array(repeating: 0, count: c * 2 - 1), count = 0
        for (_, q) in pairs {
            var k = q + c - 1
            tree[k] += 1
            while k > 0 {
                if k % 2 == 1 {
                    count += tree[k + 1]
                };
                k = (k - 1) / 2;
                tree[k] += 1
            }
        }
        return count
    }
    static func crosses(_ a: Segment, _ b: Segment, _ positions: [Int]) -> Bool {
        positions[a.p] < positions[b.p] && positions[a.q] > positions[b.q] || positions[a.p] > positions[b.p] && positions[a.q] < positions[b.q]
    }
    static func brute(_ segments: [Segment], _ positions: [Int]) -> Int {
        var count = 0
        for i in segments.indices {
            for j in (i + 1)..<segments.count where crosses(segments[i], segments[j], positions) {
                count += 1
            }
        }
        return count
    }
    static func total(_ gaps: [[Segment]], _ order: [[Int]], _ n: Int) -> Int {
        let positions = self.positions(order, n);
        return gaps.enumerated().reduce(0) {
            $0 + count($1.element, positions, order[$1.offset + 1].count)
        }
    }
    static func adjacent(_ v: Int, _ w: Int, _ upper: [[Int]], _ lower: [[Int]], _ positions: [Int]) -> Int {
        upper[v].reduce(0) {
            total, a in total + upper[w].filter {
                positions[a] > positions[$0]
            }.count
        } + lower[v].reduce(0) {
            total, a in total + lower[w].filter {
                positions[a] > positions[$0]
            }.count
        }
    }
}
