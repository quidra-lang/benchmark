func stateChar(_ state: Int) -> String { state == filled ? "#" : state == empty ? "." : "?" }
func charState(_ character: Character) -> Int { character == "#" ? filled : character == "." ? empty : unknown }
func stateString(_ cells: [Int]) -> String { cells.map(stateChar).joined() }
func gridDisplay(_ names: [String], _ grids: [[[Int]]]) -> [String] { ["grid " + names.joined(separator: " ")] + grids[0].indices.map { row in grids.map { stateString($0[row]) }.joined(separator: " | ") } }
func padLeft(_ text: String, _ width: Int) -> String { String(repeating: " ", count: max(0, width - text.count)) + text }
func answerSheet(_ rows: [[Int]], _ columns: [[Int]], _ grid: [[Int]]) -> [String] {
    let tokens = columns.map { clueText($0).split(separator: " ").map(String.init) }
    let width = tokens.flatMap { $0 }.map(\.count).max()! + 1, depth = tokens.map(\.count).max()!, margin = rows.map { clueText($0).count }.max()!
    var lines: [String] = []
    for row in 0..<depth {
        var text = String(repeating: " ", count: margin)
        for column in tokens { let skipped = depth - column.count; text += row >= skipped ? padLeft(column[row - skipped], width) : String(repeating: " ", count: width) }
        while text.hasSuffix(" ") { text.removeLast() }
        lines.append(text)
    }
    for row in grid.indices { lines.append(padLeft(clueText(rows[row]), margin) + grid[row].map { String(repeating: " ", count: width - 1) + stateChar($0) }.joined()) }
    return lines
}
