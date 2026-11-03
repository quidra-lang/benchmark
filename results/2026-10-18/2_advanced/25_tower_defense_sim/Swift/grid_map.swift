import Foundation

struct Cell: Hashable { var x: Int; var y: Int }
struct Point { var x: Int; var y: Int }
func cellCenter(_ cell: Cell) -> Point { Point(x: 100 * cell.x, y: 100 * cell.y) }
struct GridMap {
    let width: Int
    let height: Int
    let rows: [[UInt8]]
    let exit: Cell
    let spawns: [Cell]
    init(_ path: String) throws {
        let lines = try String(contentsOfFile: path, encoding: .utf8).split(whereSeparator: \.isNewline).map(String.init)
        let dimensions = lines[0].split(separator: " ").map { Int($0)! }
        let width = dimensions[0], height = dimensions[1], rows = lines[1...dimensions[1]].map { Array($0.utf8) }
        var exit = Cell(x: 0, y: 0), found: [Int: Cell] = [:]
        for y in 0..<height { for x in 0..<width {
            if (49...57).contains(rows[y][x]) { found[Int(rows[y][x] - 48)] = Cell(x: x, y: y) }
            else if rows[y][x] == 69 { exit = Cell(x: x, y: y) }
        } }
        self.width = width; self.height = height; self.rows = rows; self.exit = exit
        spawns = found.keys.sorted().map { found[$0]! }
    }
    func inside(_ cell: Cell) -> Bool { cell.x >= 0 && cell.y >= 0 && cell.x < width && cell.y < height }
    func terrain(_ cell: Cell) -> UInt8 { rows[cell.y][cell.x] }
    func isRock(_ cell: Cell) -> Bool { terrain(cell) == 35 }
    func isWater(_ cell: Cell) -> Bool { terrain(cell) == 126 }
    func buildable(_ cell: Cell) -> Bool { terrain(cell) == 46 }
}
