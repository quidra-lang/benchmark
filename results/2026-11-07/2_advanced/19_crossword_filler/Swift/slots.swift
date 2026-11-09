private func startsRun(_ grid: Grid, _ row: Int, _ column: Int, _ dr: Int, _ dc: Int) -> Bool {
    grid.isOpen(row, column) && !grid.isOpen(row - dr, column - dc)
}
private func runLength(_ grid: Grid, _ row: Int, _ column: Int, _ dr: Int, _ dc: Int) -> Int {
    var length = 0
    while grid.isOpen(row + length * dr, column + length * dc) { length += 1 }
    return length
}
func findShortRun(_ grid: Grid) -> (cell: Int, direction: String)? {
    for row in 0..<grid.height { for column in 0..<grid.width {
        for (dr, dc, direction) in [(0, 1, "across"), (1, 0, "down")] {
            if startsRun(grid, row, column, dr, dc) && runLength(grid, row, column, dr, dc) == 2 { return (grid.cell(row, column), direction) }
        }
    } }
    return nil
}
struct Slot {
    let index: Int
    let number: Int
    let across: Bool
    let cells: [Int]
    let label: String
    var crossings: [Int] = []
    var length: Int { cells.count }
}
struct Layout {
    let grid: Grid
    let numbers: [Int: Int]
    let slots: [Slot]
    let acrossSlot: [Int?]
    let downSlot: [Int?]
    init(_ grid: Grid) {
        self.grid = grid
        var numbers: [Int: Int] = [:]
        var slots: [Slot] = []
        var acrossSlot = Array<Int?>(repeating: nil, count: grid.cells.count)
        var downSlot = acrossSlot
        for row in 0..<grid.height { for column in 0..<grid.width {
            for (dr, dc, across) in [(0, 1, true), (1, 0, false)] {
                if !startsRun(grid, row, column, dr, dc) { continue }
                let length = runLength(grid, row, column, dr, dc)
                if length < 3 { continue }
                let start = grid.cell(row, column)
                if numbers[start] == nil { numbers[start] = numbers.count + 1 }
                let number = numbers[start]!
                let cells = (0..<length).map { grid.cell(row + $0 * dr, column + $0 * dc) }
                let index = slots.count
                for cell in cells { if across { acrossSlot[cell] = index } else { downSlot[cell] = index } }
                slots.append(Slot(index: index, number: number, across: across, cells: cells, label: "\(number)\(across ? "A" : "D")"))
            }
        } }
        for index in slots.indices {
            let owners = slots[index].across ? downSlot : acrossSlot
            slots[index].crossings = slots[index].cells.compactMap { owners[$0] }.sorted()
        }
        self.numbers = numbers
        self.slots = slots
        self.acrossSlot = acrossSlot
        self.downSlot = downSlot
    }
    func ownerCount(_ cell: Int) -> Int { (acrossSlot[cell] == nil ? 0 : 1) + (downSlot[cell] == nil ? 0 : 1) }
    var orphanCell: Int? { grid.whiteCells.first { ownerCount($0) == 0 } }
}
