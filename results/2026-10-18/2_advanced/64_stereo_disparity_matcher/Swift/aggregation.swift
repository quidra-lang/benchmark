import Foundation

let directions = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (-1, 1), (1, -1)]
func pathCosts(_ base: [[Int]], _ left: [Int], _ width: Int, _ height: Int, _ direction: (Int, Int), _ p1: Int, _ p2: Int, _ gamma: Int) -> [[Int]] {
    let rx = direction.0, ry = direction.1, rows = ry >= 0 ? Array(0..<height) : Array((0..<height).reversed()), columns = rx >= 0 ? Array(0..<width) : Array((0..<width).reversed()), disparities = base[0].count
    var result = Array(repeating: [Int](), count: base.count)
    for y in rows { for x in columns { let p = y * width + x, qx = x - rx, qy = y - ry; if qx < 0 || qx >= width || qy < 0 || qy >= height { result[p] = base[p]; continue }; let q = qy * width + qx, previous = result[q], minimum = previous.min()!, penalty = max(p1, p2 * gamma / (gamma + abs(left[p] - left[q]))); var values: [Int] = []; for d in 0..<disparities { var best = min(previous[d], minimum + penalty); if d > 0 { best = min(best, previous[d - 1] + p1) }; if d + 1 < disparities { best = min(best, previous[d + 1] + p1) }; values.append(base[p][d] + best - minimum) }; result[p] = values } }
    return result
}
func cumulativeCosts(_ base: [[Int]], _ left: [Int], _ width: Int, _ height: Int, _ paths: Int, _ p1: Int, _ p2: Int, _ gamma: Int) -> [[[Int]]] { var sum = Array(repeating: Array(repeating: 0, count: base[0].count), count: base.count), results: [[[Int]]] = []; for direction in directions.prefix(paths) { let costs = pathCosts(base, left, width, height, direction, p1, p2, gamma); for p in costs.indices { for d in costs[p].indices { sum[p][d] += costs[p][d] } }; results.append(sum) }; return results }
