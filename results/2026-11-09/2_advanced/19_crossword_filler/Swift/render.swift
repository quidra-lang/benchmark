func decimal(_ numerator: Int, _ denominator: Int, _ places: Int) -> String {
    var scale = 1
    for _ in 0..<places { scale *= 10 }
    let rounded = (2 * numerator * scale + denominator) / (2 * denominator)
    let remainder = String(rounded % scale)
    return "\(rounded / scale)." + String(repeating: "0", count: places - remainder.count) + remainder
}
func gridLines(_ grid: Grid, _ letters: [UInt8]) -> [String] {
    (0..<grid.height).map { String(decoding: letters[($0 * grid.width)..<(($0 + 1) * grid.width)], as: UTF8.self) }
}
func numberLines(_ layout: Layout) -> [String] {
    let grid = layout.grid
    return (0..<grid.height).map { row in
        (0..<grid.width).map { column in
            let cell = grid.cell(row, column)
            if grid.cells[cell] == 35 { return "##" }
            if let number = layout.numbers[cell] { return number < 10 ? " \(number)" : String(number) }
            return " ."
        }.joined(separator: " ")
    }
}
func listLine(_ slot: Slot, _ clue: String, _ entry: String, _ score: String, _ theme: Bool) -> String {
    "\(slot.number). \(clue) (\(slot.length)) \(entry) \(score)" + (theme ? " theme" : "")
}
