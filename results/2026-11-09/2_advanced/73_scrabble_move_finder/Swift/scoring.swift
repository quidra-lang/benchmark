import Foundation

let rackSize = 7
let bingoBonus = 50
func squares(_ move: Move) -> [PlacedTile] { move.word.enumerated().map { PlacedTile(row: move.row + move.direction.dr * $0.offset, column: move.column + move.direction.dc * $0.offset, letter: $0.element) } }
func placement(_ board: Board, _ move: Move) -> [PlacedTile] { squares(move).filter { board[$0.row][$0.column] == 46 } }
func applying(_ board: Board, _ tiles: [PlacedTile]) -> Board { var result = board; for tile in tiles { result[tile.row][tile.column] = tile.letter }; return result }
func crossWords(_ board: Board, _ move: Move) -> [Move] { let newTiles = placement(board, move), after = applying(board, newTiles); return newTiles.map { runAt(after, $0.square, move.direction.perpendicular) }.filter { $0.word.count >= 2 } }
func wordScore(_ board: Board, _ word: Move, _ values: [Int]) -> Int {
    var score = 0, multiplier = 1
    for tile in squares(word) {
        var value = lowercase(tile.letter) ? 0 : values[Int(tile.letter - 65)]
        if board[tile.row][tile.column] == 46 {
            let premium = premiums[tile.row][tile.column]
            value *= premium == 43 ? 2 : premium == 94 ? 3 : 1
            multiplier *= premium == 42 ? 2 : premium == 35 ? 3 : 1
        }
        score += value
    }
    return score * multiplier
}
struct ScoredWord { let move: Move; let score: Int }
struct MoveScore { let score: Int; let tiles: [PlacedTile]; let words: [ScoredWord] }
func scoreMove(_ board: Board, _ move: Move, _ values: [Int]) -> MoveScore {
    let words = ([move] + crossWords(board, move)).map { ScoredWord(move: $0, score: wordScore(board, $0, values)) }, tiles = placement(board, move)
    return MoveScore(score: words.map { $0.score }.reduce(0, +) + (tiles.count == rackSize ? bingoBonus : 0), tiles: tiles, words: words)
}
