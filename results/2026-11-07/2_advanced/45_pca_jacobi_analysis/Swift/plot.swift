import Foundation

typealias Grid = [[Character]]
typealias Cell = (row: Int, column: Int)

func newGrid(_ rows: Int, _ columns: Int) -> Grid { Array(repeating: Array(repeating: " ", count: columns), count: rows) }

func framed(_ grid: Grid) -> [String] {
    let border = "+" + String(repeating: "-", count: grid[0].count) + "+"
    return [border] + grid.map { "|" + String($0) + "|" } + [border]
}

func gridIndex(_ fraction: Double, _ size: Int) -> Int { min(Int(floor(fraction * Double(size))), size - 1) }
func roundedPosition(_ fraction: Double, _ size: Double) -> Int { Int(floor(fraction * size + 0.5)) }

func biplotCell(_ x: Double, _ y: Double, _ xLimit: Double, _ yLimit: Double, _ width: Int, _ height: Int) -> Cell {
    (gridIndex((yLimit - y) / (2 * yLimit), height), gridIndex((x + xLimit) / (2 * xLimit), width))
}

func circleCell(_ first: Double, _ second: Double, _ radius: Int) -> Cell {
    (radius / 2 + 1 - roundedPosition(second, Double(radius) / 2), radius + 1 + roundedPosition(first, Double(radius)))
}

func diagnosticCell(_ t2: Double, _ spe: Double, _ t2Max: Double, _ speMax: Double, _ width: Int, _ height: Int) -> Cell {
    (height - 1 - gridIndex(spe / speMax, height), gridIndex(t2 / t2Max, width))
}

func shaftCells(_ origin: Cell, _ tip: Cell) -> [Cell] {
    let dr = tip.row - origin.row, dc = tip.column - origin.column
    let steps = max(abs(dr), abs(dc))
    if steps <= 1 { return [] }
    let signRow = dr == 0 ? 0 : dr > 0 ? 1 : -1, signColumn = dc == 0 ? 0 : dc > 0 ? 1 : -1
    return (1..<steps).map { s in
        (origin.row + signRow * ((2 * s * abs(dr) + steps) / (2 * steps)),
         origin.column + signColumn * ((2 * s * abs(dc) + steps) / (2 * steps)))
    }
}

func shaftCharacter(_ origin: Cell, _ tip: Cell) -> Character {
    let dr = tip.row - origin.row, dc = tip.column - origin.column
    if 2 * abs(dr) <= abs(dc) { return "-" }
    if 2 * abs(dc) <= abs(dr) { return "|" }
    return dc * dr < 0 ? "/" : "\\"
}

func screeLine(_ length: Int, _ kaiser: Int, _ broken: Int, _ width: Int) -> String {
    let characters: [Character] = (1...width).map { $0 == broken ? "o" : $0 == kaiser ? ":" : $0 <= length ? "#" : " " }
    return "|" + String(characters) + "|"
}
