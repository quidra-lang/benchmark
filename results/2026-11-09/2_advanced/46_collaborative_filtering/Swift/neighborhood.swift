import Foundation

struct IDPair: Hashable {
    let first: Int
    let second: Int
    init(_ first: Int, _ second: Int) { self.first = min(first, second); self.second = max(first, second) }
}

struct Similarity {
    let value: Double
    let common: Int
}

typealias Neighbor = (id: Int, similarity: Double)

func largestNeighbors(_ candidates: [Neighbor], _ count: Int) -> [Neighbor] {
    Array(candidates.sorted { $0.similarity == $1.similarity ? $0.id < $1.id : $0.similarity > $1.similarity }.prefix(count))
}

struct Neighborhood {
    var user: [IDPair: Similarity] = [:]
    var item: [IDPair: Similarity] = [:]
    var counts: [IDPair: Int] = [:]
    var differences: [IDPair: Int] = [:]
    let shrinkage: Int

    init(_ data: Ratings, _ shrinkage: Int) {
        self.shrinkage = shrinkage
        for (position, u) in data.users.enumerated() {
            let left = data.byUser[u]!
            for v in data.users.dropFirst(position + 1) {
                let right = data.byUser[v]!
                let common = data.userItems[u]!.filter { right[$0] != nil }, n = common.count
                if n < 2 { continue }
                var sx = 0, sy = 0, sxx = 0, syy = 0, sxy = 0
                for i in common {
                    let x = left[i]!, y = right[i]!
                    sx += x; sy += y; sxx += x * x; syy += y * y; sxy += x * y
                }
                let numerator = n * sxy - sx * sy, dx = n * sxx - sx * sx, dy = n * syy - sy * sy
                if dx == 0 || dy == 0 { continue }
                let a = (numerator * n) * (numerator * n), b = dx * dy * (n + shrinkage) * (n + shrinkage)
                let sign = numerator > 0 ? 1.0 : numerator < 0 ? -1.0 : 0.0
                user[IDPair(u, v)] = Similarity(value: sign * sqrt(Double(a) / Double(b)), common: n)
            }
        }
        for (position, i) in data.items.enumerated() {
            let left = data.byItem[i]!
            for j in data.items.dropFirst(position + 1) {
                let right = data.byItem[j]!
                let common = data.itemUsers[i]!.filter { right[$0] != nil }, n = common.count
                if n == 0 { continue }
                counts[IDPair(i, j)] = n
                differences[IDPair(i, j)] = common.reduce(0) { $0 + left[$1]! - right[$1]! }
                if n < 2 { continue }
                var numerator = 0.0, leftNorm = 0.0, rightNorm = 0.0
                for u in common {
                    let x = Double(left[u]!) - data.userMeans[u]!, y = Double(right[u]!) - data.userMeans[u]!
                    numerator = numerator + x * y
                    leftNorm = leftNorm + x * x
                    rightNorm = rightNorm + y * y
                }
                if leftNorm == 0 || rightNorm == 0 { continue }
                let similarity = numerator / sqrt(leftNorm * rightNorm) * Double(n) / Double(n + shrinkage)
                item[IDPair(i, j)] = Similarity(value: similarity, common: n)
            }
        }
    }

    func userSimilarity(_ first: Int, _ second: Int) -> Similarity? { user[IDPair(first, second)] }
    func itemSimilarity(_ first: Int, _ second: Int) -> Similarity? { item[IDPair(first, second)] }
    func commonCount(_ first: Int, _ second: Int) -> Int { counts[IDPair(first, second)] ?? 0 }
    func difference(_ target: Int, _ source: Int) -> Int { let value = differences[IDPair(target, source)] ?? 0; return target < source ? value : -value }
    func deviation(_ target: Int, _ source: Int) -> Double { Double(difference(target, source)) / Double(commonCount(target, source) + shrinkage) }
}
