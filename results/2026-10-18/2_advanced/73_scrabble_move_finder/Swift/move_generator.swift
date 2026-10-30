import Foundation

let letters: [UInt8] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ".utf8)
func anchors(_ board: Board) -> Set<Square> {
    if boardTiles(board).isEmpty { return [center] }
    var result: Set<Square> = []
    for row in 0..<boardSize { for column in 0..<boardSize where board[row][column] == 46 {
        let square = Square(row: row, column: column)
        if neighbors(square).contains(where: { board[$0.row][$0.column] != 46 }) { result.insert(square) }
    } }
    return result
}
func crossChecks(_ board: Board, _ trie: Trie) -> [Square: Set<UInt8>] {
    var result: [Square: Set<UInt8>] = [:]
    for row in 0..<boardSize { for column in 0..<boardSize where board[row][column] == 46 {
        var first = row, last = row
        while first > 0 && board[first - 1][column] != 46 { first -= 1 }
        while last + 1 < boardSize && board[last + 1][column] != 46 { last += 1 }
        if first == last { continue }
        let prefix = (first..<row).map { upper(board[$0][column]) }, suffix = ((row + 1)..<(last + 1)).map { upper(board[$0][column]) }
        result[Square(row: row, column: column)] = Set(letters.filter { trie.contains(prefix + [$0] + suffix) })
    } }
    return result
}
func acrossMoves(_ board: Board, _ rack: [UInt8], _ trie: Trie, _ anchorSquares: Set<Square>, _ checks: [Square: Set<UInt8>]) -> [Move] {
    var result: [Move] = [], counts = Array(repeating: 0, count: 27)
    for letter in rack { counts[letter == 63 ? 26 : Int(letter - 65)] += 1 }
    for square in anchorSquares.sorted(by: { $0.row == $1.row ? $0.column < $1.column : $0.row < $1.row }) {
        let row = square.row, anchor = square.column
        func extend(_ node: Int, _ column: Int, _ word: [UInt8], _ start: Int) {
            let empty = column == boardSize || board[row][column] == 46
            if empty && column > anchor && trie.nodes[node].terminal { result.append(Move(row: row, column: start, direction: .across, word: word)) }
            if column == boardSize { return }
            if !empty {
                let letter = board[row][column], child = trie.nodes[node].children[Int(upper(letter) - 65)]
                if child != -1 { extend(child, column + 1, word + [letter], start) }
                return
            }
            let allowed = checks[Square(row: row, column: column)]
            for index in 0..<26 where trie.nodes[node].children[index] != -1 {
                let letter = UInt8(65 + index), child = trie.nodes[node].children[index]
                if let allowed, !allowed.contains(letter) { continue }
                for (tile, written) in [(index, letter), (26, letter + 32)] where counts[tile] > 0 { counts[tile] -= 1; extend(child, column + 1, word + [written], start); counts[tile] += 1 }
            }
        }
        func leftPart(_ node: Int, _ prefix: [UInt8], _ remaining: Int) {
            extend(node, anchor, prefix, anchor - prefix.count)
            if remaining == 0 { return }
            for index in 0..<26 where trie.nodes[node].children[index] != -1 {
                let letter = UInt8(65 + index)
                for (tile, written) in [(index, letter), (26, letter + 32)] where counts[tile] > 0 { counts[tile] -= 1; leftPart(trie.nodes[node].children[index], prefix + [written], remaining - 1); counts[tile] += 1 }
            }
        }
        if anchor > 0 && board[row][anchor - 1] != 46 {
            var first = anchor - 1
            while first > 0 && board[row][first - 1] != 46 { first -= 1 }
            let prefix = Array(board[row][first..<anchor])
            if let node = trie.prefix(prefix.map(upper)) { extend(node, anchor, prefix, first) }
        } else {
            var first = anchor - 1
            while first >= 0 && board[row][first] == 46 && !anchorSquares.contains(Square(row: row, column: first)) { first -= 1 }
            leftPart(0, [], anchor - first - 1)
        }
    }
    return result
}
struct PlacementKey: Hashable { let tiles: [PlacedTile] }
func generate(_ board: Board, _ rack: [UInt8], _ trie: Trie) -> [Move] {
    let anchorSquares = anchors(board), across = acrossMoves(board, rack, trie, anchorSquares, crossChecks(board, trie)), transposed = transpose(board)
    let downAnchors = Set(anchorSquares.map { Square(row: $0.column, column: $0.row) }), down = acrossMoves(transposed, rack, trie, downAnchors, crossChecks(transposed, trie)).map { Move(row: $0.column, column: $0.row, direction: .down, word: $0.word) }
    var seen: Set<PlacementKey> = [], result: [Move] = []
    for move in across + down {
        let newTiles = placement(board, move)
        if newTiles.count == 1 && move.direction == .down && runAt(applying(board, newTiles), newTiles[0].square, .across).word.count >= 2 { continue }
        if seen.insert(PlacementKey(tiles: newTiles.sorted())).inserted { result.append(move) }
    }
    return result
}
