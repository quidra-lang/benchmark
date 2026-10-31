import Foundation

final class GridCell {
    let column: Int
    let row: Int
    let box: Box
    var points: [Point] = []
    init(_ column: Int, _ row: Int, _ size: Int) {
        self.column = column; self.row = row
        box = Box(x1: column * size, y1: row * size, x2: column * size + size - 1, y2: row * size + size - 1)
    }
}

final class Grid {
    let world: Int
    let cellSize: Int
    let side: Int
    let cells: [GridCell]
    init(_ world: Int, _ cellSize: Int, _ points: [Point]) {
        let side = world / cellSize
        self.world = world; self.cellSize = cellSize; self.side = side
        cells = (0..<side).flatMap { row in (0..<side).map { GridCell($0, row, cellSize) } }
        for point in points { insert(point) }
    }
    func position(_ point: Point) -> (column: Int, row: Int) { (point.x / cellSize, point.y / cellSize) }
    func cell(_ point: Point) -> GridCell { let cell = position(point); return cells[cell.row * side + cell.column] }
    func insert(_ point: Point) { let cell = cell(point); cell.points.append(point); cell.points.sort { $0.id < $1.id } }
    func delete(_ point: Point) { cell(point).points.removeAll { $0.id == point.id } }
}
