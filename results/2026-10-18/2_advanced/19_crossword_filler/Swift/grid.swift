struct Grid {
    let width: Int
    let height: Int
    let cells: [UInt8]
    init(_ rows: [String]) { width = rows[0].utf8.count; height = rows.count; cells = rows.flatMap { Array($0.utf8) } }
    func cell(_ row: Int, _ column: Int) -> Int { row * width + column }
    func location(_ cell: Int) -> String { "\(cell / width + 1),\(cell % width + 1)" }
    func isOpen(_ row: Int, _ column: Int) -> Bool {
        row >= 0 && row < height && column >= 0 && column < width && cells[cell(row, column)] != 35
    }
    var whiteCells: [Int] { cells.indices.filter { cells[$0] != 35 } }
    func asymmetricCell(_ symmetry: String) -> Int? {
        for row in 0..<height { for column in 0..<width {
            let otherRow = symmetry == "rot180" ? height - 1 - row : row
            if isOpen(row, column) != isOpen(otherRow, width - 1 - column) { return cell(row, column) }
        } }
        return nil
    }
    var componentCount: Int {
        var seen = Array(repeating: false, count: cells.count)
        var count = 0
        for start in whiteCells {
            if seen[start] { continue }
            count += 1
            seen[start] = true
            var stack = [start]
            while let cell = stack.popLast() {
                let row = cell / width
                let column = cell % width
                for (dr, dc) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                    let r = row + dr
                    let c = column + dc
                    if isOpen(r, c) {
                        let neighbor = self.cell(r, c)
                        if !seen[neighbor] { seen[neighbor] = true; stack.append(neighbor) }
                    }
                }
            }
        }
        return count
    }
}
