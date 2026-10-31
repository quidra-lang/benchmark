import Foundation

let boardSize = 15
typealias Board = [[UInt8]]
enum Direction: Int {
    case across, down
    var dr: Int { rawValue }
    var dc: Int { 1 - rawValue }
    var perpendicular: Direction { self == .across ? .down : .across }
}
struct Square: Hashable { let row: Int; let column: Int }
let center = Square(row: 7, column: 7)
struct PlacedTile: Hashable, Comparable {
    let row: Int; let column: Int; let letter: UInt8
    var square: Square { Square(row: row, column: column) }
    static func < (_ first: PlacedTile, _ second: PlacedTile) -> Bool { if first.row != second.row { return first.row < second.row }; if first.column != second.column { return first.column < second.column }; return first.letter < second.letter }
}
struct Move { let row: Int; let column: Int; let direction: Direction; let word: [UInt8] }
let premiums: [[UInt8]] = [
    "# . . + . . . # . . . + . . #", ". * . . . ^ . . . ^ . . . * .", ". . * . . . + . + . . . * . .",
    "+ . . * . . . + . . . * . . +", ". . . . * . . . . . * . . . .", ". ^ . . . ^ . . . ^ . . . ^ .",
    ". . + . . . + . + . . . + . .", "# . . + . . . * . . . + . . #", ". . + . . . + . + . . . + . .",
    ". ^ . . . ^ . . . ^ . . . ^ .", ". . . . * . . . . . * . . . .", "+ . . * . . . + . . . * . . +",
    ". . * . . . + . + . . . * . .", ". * . . . ^ . . . ^ . . . * .", "# . . + . . . # . . . + . . #"
].map { Array($0.utf8.filter { $0 != 32 }) }
func text(_ bytes: [UInt8]) -> String { String(decoding: bytes, as: UTF8.self) }
func upper(_ letter: UInt8) -> UInt8 { letter >= 97 && letter <= 122 ? letter - 32 : letter }
func lowercase(_ letter: UInt8) -> Bool { letter >= 97 && letter <= 122 }
func inside(_ row: Int, _ column: Int) -> Bool { row >= 0 && row < boardSize && column >= 0 && column < boardSize }
func squareName(_ row: Int, _ column: Int) -> String { String(UnicodeScalar(UInt8(65 + column))) + String(row + 1) }
func position(_ move: Move) -> String { let column = String(UnicodeScalar(UInt8(65 + move.column))); return move.direction == .across ? String(move.row + 1) + column : column + String(move.row + 1) }
func parsePosition(_ value: String) -> (row: Int, column: Int, direction: Direction)? {
    let bytes = Array(value.utf8)
    if bytes.count < 2 || bytes.count > 3 { return nil }
    func rowNumber(_ digits: [UInt8]) -> Int? { if digits[0] == 48 || !digits.allSatisfy({ $0 >= 48 && $0 <= 57 }) { return nil }; let number = Int(text(digits))!; return number >= 1 && number <= 15 ? number - 1 : nil }
    if let last = bytes.last, last >= 65 && last <= 79, let row = rowNumber(Array(bytes.dropLast())) { return (row, Int(last - 65), .across) }
    if bytes[0] >= 65 && bytes[0] <= 79, let row = rowNumber(Array(bytes.dropFirst())) { return (row, Int(bytes[0] - 65), .down) }
    return nil
}
func transpose(_ board: Board) -> Board { (0..<boardSize).map { column in (0..<boardSize).map { board[$0][column] } } }
func transposeTiles(_ tiles: [PlacedTile]) -> [PlacedTile] { tiles.map { PlacedTile(row: $0.column, column: $0.row, letter: $0.letter) } }
func boardTiles(_ board: Board) -> [PlacedTile] { board.indices.flatMap { row in board[row].indices.filter { board[row][$0] != 46 }.map { PlacedTile(row: row, column: $0, letter: board[row][$0]) } } }
func neighbors(_ square: Square) -> [Square] { [Square(row: square.row - 1, column: square.column), Square(row: square.row + 1, column: square.column), Square(row: square.row, column: square.column - 1), Square(row: square.row, column: square.column + 1)].filter { inside($0.row, $0.column) } }
func runAt(_ board: Board, _ square: Square, _ direction: Direction) -> Move {
    var row = square.row, column = square.column
    while inside(row - direction.dr, column - direction.dc) && board[row - direction.dr][column - direction.dc] != 46 { row -= direction.dr; column -= direction.dc }
    let firstRow = row, firstColumn = column
    var letters: [UInt8] = []
    while inside(row, column) && board[row][column] != 46 { letters.append(board[row][column]); row += direction.dr; column += direction.dc }
    return Move(row: firstRow, column: firstColumn, direction: direction, word: letters)
}
func boardWords(_ board: Board) -> [Move] {
    var result: [Move] = []
    for direction in [Direction.across, .down] { for line in 0..<boardSize {
        var offset = 0
        while offset < boardSize {
            let square = direction == .across ? Square(row: line, column: offset) : Square(row: offset, column: line)
            if board[square.row][square.column] == 46 { offset += 1; continue }
            let word = runAt(board, square, direction)
            if word.word.count >= 2 { result.append(word) }
            offset += word.word.count
        }
    } }
    return result
}
func connected(_ board: Board) -> Bool {
    let occupied = Set(boardTiles(board).map { $0.square })
    guard let first = occupied.first else { return true }
    var pending = [first], seen: Set<Square> = [first]
    while let square = pending.popLast() { for neighbor in neighbors(square) where occupied.contains(neighbor) && !seen.contains(neighbor) { seen.insert(neighbor); pending.append(neighbor) } }
    return seen == occupied
}
func display(_ board: Board) -> [String] {
    let columns = (0..<boardSize).map { String(UnicodeScalar(UInt8(65 + $0))) }.joined(separator: " ")
    return ["   " + columns] + board.indices.map { row in
        let letters = board[row].indices.map { column in String(UnicodeScalar(board[row][column] == 46 ? premiums[row][column] : board[row][column])) }.joined(separator: " ")
        return (row < 9 ? " " : "") + String(row + 1) + " " + letters
    }
}
