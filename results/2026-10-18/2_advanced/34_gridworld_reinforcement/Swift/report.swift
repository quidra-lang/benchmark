import Foundation

func fixedText(_ value: Int) -> String {
    let magnitude = abs(value)
    return (value < 0 ? "-" : "") + String(magnitude / 10000) + "." + String(format: "%04d", magnitude % 10000)
}

func averageText(_ total: Int, _ count: Int) -> String { fixedText(floorDivide(10000 * total, count)) }
func cellText(_ world: World, _ cell: Int) -> String { "\(cell / world.cols),\(cell % world.cols)" }
func cellsText(_ world: World, _ cells: [Int]) -> String { cells.map { cellText(world, $0) }.joined(separator: " ") }

func gridLines(_ world: World, _ fields: [String], _ separator: String) -> [String] {
    (0..<world.rows).map { row in
        (row * world.cols..<((row + 1) * world.cols)).map { cell in
            world.stateIndex[cell].map { fields[$0] } ?? String(world.kinds[cell])
        }.joined(separator: separator)
    }
}

func valueGrid(_ world: World, _ values: [Int]) -> [String] { gridLines(world, values.map(fixedText), " ") }

func policyGrid(_ world: World, _ policy: [Int]) -> [String] {
    let symbols = Array("^>v<")
    return gridLines(world, policy.map { String(symbols[$0]) }, "")
}

func symbolGrid(_ world: World, _ symbols: [String]) -> [String] { gridLines(world, symbols, "") }

func qTableRows(_ world: World, _ name: String, _ values: [[Int]], _ visits: [[Int]]?) -> [String] {
    var rows: [String] = []
    for (state, cell) in world.states.enumerated() {
        for action in 0..<4 {
            let count = visits.map { String($0[state][action]) } ?? "-"
            rows.append("\(name),\(cell / world.cols),\(cell % world.cols),\(actionLetters[action]),\(fixedText(values[state][action])),\(count)")
        }
    }
    return rows
}

func joinParts(_ parts: [[String]]) -> [String] {
    var lines: [String] = []
    for part in parts {
        if !lines.isEmpty { lines.append("") }
        lines += part
    }
    return lines
}

func writeLines(_ name: String, _ lines: [String]) throws {
    try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    try (lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: true, encoding: .ascii)
}
