struct Cell: Equatable { let row: Int; let column: Int }
func guessCell(_ grid: [[Int]]) -> Cell {
    let rows = grid.map { $0.filter { $0 == unknown }.count }
    let columns = grid[0].indices.map { column in grid.filter { $0[column] == unknown }.count }
    var best = Cell(row: -1, column: -1), score = 0
    for row in grid.indices {
        for column in grid[row].indices where grid[row][column] == unknown { let candidate = rows[row] + columns[column]; if best.row < 0 || candidate < score { best = Cell(row: row, column: column); score = candidate } }
    }
    return best
}
struct Guess { let number: Int; let depth: Int; let cell: Cell; let value: Int; let solves: Int; let known: Int; let result: String }
final class Search {
    let rowClues: [[Int]]
    let columnClues: [[Int]]
    var guesses: [Guess] = []
    var solutions: [[[Int]]] = []
    var backtracks = 0, maxDepth = 0, lineSolves = 0
    init(_ rows: [[Int]], _ columns: [[Int]]) { rowClues = rows; columnClues = columns }
    @discardableResult func run(_ grid: [[Int]], _ depth: Int = 1) -> Bool {
        let chosen = guessCell(grid)
        for value in [filled, empty] {
            var child = grid
            child[chosen.row][chosen.column] = value
            var rows = Array(repeating: false, count: rowClues.count), columns = Array(repeating: false, count: columnClues.count)
            rows[chosen.row] = true; columns[chosen.column] = true
            let details = propagate(&child, rowClues, columnClues, true, rows, columns), known = determinedCount(child)
            let result: String
            if let conflict = details.conflict { result = "contradiction at=" + conflict.label; backtracks += 1 }
            else if known == rowClues.count * columnClues.count { solutions.append(child); result = "solution\(solutions.count)" }
            else { result = "open" }
            maxDepth = max(maxDepth, depth); lineSolves += details.steps.count
            guesses.append(Guess(number: guesses.count + 1, depth: depth, cell: chosen, value: value, solves: details.steps.count, known: known, result: result))
            if result == "open" { if run(child, depth + 1) { return true } }
            else if solutions.count == 2 { return true }
        }
        return false
    }
}
