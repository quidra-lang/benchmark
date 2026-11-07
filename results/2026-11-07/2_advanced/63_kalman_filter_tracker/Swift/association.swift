import Foundation

struct Pair: Hashable { let row: Int; let column: Int }
func pairBefore(_ first: Pair, _ second: Pair) -> Bool { first.row == second.row ? first.column < second.column : first.row < second.row }
func minimumMatching(_ costs: Matrix) -> [Pair] {
    if costs.isEmpty || costs[0].isEmpty { return [] }
    let transposed = costs.count > costs[0].count, matrix = transposed ? transpose(costs) : costs, rows = matrix.count, columns = matrix[0].count
    var u = Array(repeating: 0.0, count: rows + 1), v = Array(repeating: 0.0, count: columns + 1), matched = Array(repeating: 0, count: columns + 1), previous = Array(repeating: 0, count: columns + 1)
    for row in 1...rows {
        matched[0] = row
        var column = 0, distances = Array(repeating: Double.infinity, count: columns + 1), used = Array(repeating: false, count: columns + 1)
        repeat {
            used[column] = true
            let currentRow = matched[column]
            var delta = Double.infinity, following = 0
            for candidate in 1...columns where !used[candidate] { let reduced = matrix[currentRow - 1][candidate - 1] - u[currentRow] - v[candidate]; if reduced < distances[candidate] { distances[candidate] = reduced; previous[candidate] = column }; if distances[candidate] < delta { delta = distances[candidate]; following = candidate } }
            for candidate in 0...columns { if used[candidate] { u[matched[candidate]] += delta; v[candidate] -= delta } else { distances[candidate] -= delta } }
            column = following
        } while matched[column] != 0
        while column != 0 { let following = previous[column]; matched[column] = matched[following]; column = following }
    }
    return (1...columns).filter { matched[$0] != 0 }.map { transposed ? Pair(row: $0 - 1, column: matched[$0] - 1) : Pair(row: matched[$0] - 1, column: $0 - 1) }.sorted(by: pairBefore)
}
func optimalAssignment(_ rows: Int, _ columns: Int, _ usable: [Pair: Double]) -> [Pair] { if rows == 0 || columns == 0 || usable.isEmpty { return [] }; let largest = usable.values.max()!, penalty = Double(min(rows, columns) + 1) * (max(1, largest) + 1), costs = (0..<rows).map { row in (0..<columns).map { usable[Pair(row: row, column: $0)] ?? penalty } }; return minimumMatching(costs).filter { usable[$0] != nil } }
