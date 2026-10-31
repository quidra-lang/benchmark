func lineLabel(_ isRow: Bool, _ index: Int) -> String { (isRow ? "R" : "C") + String(index + 1) }
func lineCells(_ grid: [[Int]], _ isRow: Bool, _ index: Int) -> [Int] { isRow ? grid[index] : grid.map { $0[index] } }
func determinedCount(_ grid: [[Int]]) -> Int { grid.reduce(0) { $0 + $1.filter { $0 != unknown }.count } }
struct Step {
    let isRow: Bool
    let index: Int
    let gain: Int
    let contradiction: Bool
    var label: String { lineLabel(isRow, index) }
    var text: String { label + (contradiction ? "!" : "+\(gain)") }
}
struct Propagation {
    var steps: [Step] = []
    var conflict: Step? = nil
    var record: String { steps.map(\.text).joined(separator: " ") }
}
func propagate(_ grid: inout [[Int]], _ rowClues: [[Int]], _ columnClues: [[Int]], _ precise: Bool, _ rowMarks: [Bool], _ columnMarks: [Bool]) -> Propagation {
    var rows = rowMarks, columns = columnMarks, result = Propagation()
    while true {
        let isRow: Bool, index: Int
        if let row = rows.firstIndex(of: true) { isRow = true; index = row; rows[row] = false }
        else if let column = columns.firstIndex(of: true) { isRow = false; index = column; columns[column] = false }
        else { return result }
        let cells = lineCells(grid, isRow, index), clue = isRow ? rowClues[index] : columnClues[index]
        guard let solved = solveLine(cells, clue, precise) else { let step = Step(isRow: isRow, index: index, gain: 0, contradiction: true); result.conflict = step; result.steps.append(step); return result }
        var gain = 0
        for position in cells.indices where cells[position] == unknown && solved[position] != unknown {
            gain += 1
            if isRow { grid[index][position] = solved[position]; columns[position] = true }
            else { grid[position][index] = solved[position]; rows[position] = true }
        }
        result.steps.append(Step(isRow: isRow, index: index, gain: gain, contradiction: false))
    }
}
