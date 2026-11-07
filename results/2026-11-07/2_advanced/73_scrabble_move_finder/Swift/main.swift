import Foundation

enum Strategy: String { case score, tiles, equity }
let vowels: Set<UInt8> = Set("AEIOU".utf8)
struct TileTable { let values: [Int]; let counts: [Int]; let weights: [Int] }
struct Inputs { let table: TileTable; let trie: Trie; let jobs: [[String]]; let dictionaryLines: [String] }
struct Evaluated {
    let move: Move; let score: Int; let newTiles: [PlacedTile]; let wordList: String; let leave: [UInt8]; let value: Int
    var key: PlacementKey { PlacementKey(tiles: newTiles.sorted()) }
}
func validName(_ value: String) -> Bool { let bytes = Array(value.utf8); return !bytes.isEmpty && bytes.count <= 20 && bytes.allSatisfy { ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 95 } }
func validNumber(_ value: String, _ minimum: Int, _ maximum: Int) -> Bool { let bytes = Array(value.utf8); if bytes.isEmpty || (bytes.count > 1 && bytes[0] == 48) || !bytes.allSatisfy({ $0 >= 48 && $0 <= 57 }) { return false }; guard let number = Int(value) else { return false }; return number >= minimum && number <= maximum }
func validRack(_ value: [UInt8]) -> Bool { !value.isEmpty && value.count <= rackSize && value.allSatisfy { ($0 >= 65 && $0 <= 90) || $0 == 63 } }
func validWord(_ value: [UInt8]) -> Bool { value.count >= 2 && value.count <= boardSize && value.allSatisfy { let letter = upper($0); return letter >= 65 && letter <= 90 } }
func collection(_ value: [UInt8]) -> String { value.isEmpty ? "-" : text(value.sorted()) }
func tileKind(_ letter: UInt8) -> UInt8 { lowercase(letter) ? 63 : letter }
func tileIndex(_ letter: UInt8) -> Int { letter == 63 || lowercase(letter) ? 26 : Int(letter - 65) }
func countsOf(_ rack: [UInt8]) -> [Int] { var counts = Array(repeating: 0, count: 27); for letter in rack { counts[tileIndex(letter)] += 1 }; return counts }
func tileBytes(_ counts: [Int]) -> [UInt8] { ([26] + Array(0..<26)).flatMap { Array(repeating: tileOrder[$0], count: counts[$0]) } }
func removeTiles(_ rack: [UInt8], _ removed: [UInt8]) -> [UInt8] { var counts = countsOf(rack); for letter in removed { counts[tileIndex(letter)] -= 1 }; return tileBytes(counts) }
func notation(_ evaluated: Evaluated) -> String { position(evaluated.move) + " " + text(evaluated.move.word) }
func standardPrecedes(_ first: Evaluated, _ second: Evaluated) -> Bool {
    if first.score != second.score { return first.score > second.score }
    let a = first.move, b = second.move
    if a.row != b.row { return a.row < b.row }; if a.column != b.column { return a.column < b.column }
    if a.direction != b.direction { return a.direction.rawValue < b.direction.rawValue }
    return a.word.lexicographicallyPrecedes(b.word)
}
func strategyPrecedes(_ first: Evaluated, _ second: Evaluated, _ strategy: Strategy) -> Bool {
    if strategy == .tiles && first.newTiles.count != second.newTiles.count { return first.newTiles.count > second.newTiles.count }
    if strategy == .equity && first.score + first.value != second.score + second.value { return first.score + first.value > second.score + second.value }
    return standardPrecedes(first, second)
}
func inputLines(_ name: String) throws -> [String] { try String(contentsOfFile: "input/" + name, encoding: .ascii).split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(String.init) }
func fields(_ line: String) -> [String] { line.split(separator: " ").map(String.init) }
func readInputs() throws -> Inputs {
    var values = Array(repeating: 0, count: 27), counts = values, weights = values
    for line in try inputLines("tiles.txt") where !line.isEmpty && line.first != "#" {
        let parts = fields(line), index = tileIndex(parts[0].utf8.first!)
        values[index] = Int(parts[1])!; counts[index] = Int(parts[2])!; weights[index] = Int(parts[3])!
    }
    let trie = Trie()
    var candidates = 0, skipped = 0, duplicates = 0, lengths: [Int: Int] = [:]
    for line in try inputLines("dictionary.txt") where !line.isEmpty && line.first != "#" {
        candidates += 1
        let bytes = Array(line.utf8)
        if bytes.count < 2 || bytes.count > 15 || !bytes.allSatisfy({ $0 >= 65 && $0 <= 90 }) { skipped += 1 }
        else if trie.add(bytes) { lengths[bytes.count, default: 0] += 1 } else { duplicates += 1 }
    }
    var jobs: [[String]] = [], current: [String] = [], active = false
    for line in try inputLines("jobs.txt") {
        if !active { if !line.isEmpty && line.first != "#" { current = [line]; active = true } }
        else if line == "END" { jobs.append(current); current = []; active = false } else { current.append(line) }
    }
    let dictionaryLines = ["DICTIONARY lines=\(candidates) words=\(trie.words) skipped=\(skipped) duplicates=\(duplicates) nodes=\(trie.nodes.count)", "lengths" + lengths.keys.sorted().map { " \($0)=\(lengths[$0]!)" }.joined()]
    return Inputs(table: TileTable(values: values, counts: counts, weights: weights), trie: trie, jobs: jobs, dictionaryLines: dictionaryLines)
}
final class Scrabble {
    let table: TileTable
    let trie: Trie
    var topTotals: [String: Int] = [:], validationTotals: [String: Int] = [:], gameTotals: [String: Int] = [:]
    init(_ table: TileTable, _ trie: Trie) { self.table = table; self.trie = trie }
    func usedTiles(_ board: Board) -> [Int] { var counts = Array(repeating: 0, count: 27); for tile in boardTiles(board) { counts[tileIndex(tile.letter)] += 1 }; return counts }
    func tileError(_ board: Board, _ rack: [UInt8]) -> String? {
        let used = zip(usedTiles(board), countsOf(rack)).map { $0.0 + $0.1 }
        for index in tileOrder.indices where used[index] > table.counts[index] { return "too many " + String(UnicodeScalar(tileOrder[index])) }
        return nil
    }
    func unseen(_ board: Board, _ rack: [UInt8]) -> [UInt8] { let used = zip(usedTiles(board), countsOf(rack)).map { $0.0 + $0.1 }; return tileBytes(table.counts.indices.map { table.counts[$0] - used[$0] }) }
    func boardError(_ board: Board, _ rack: [UInt8]) -> String? {
        if board.count != boardSize { return "board rows \(board.count)" }
        for (index, row) in board.enumerated() { if row.count != boardSize || !row.allSatisfy({ $0 == 46 || (upper($0) >= 65 && upper($0) <= 90) }) { return "bad board row \(index + 1)" } }
        if let error = tileError(board, rack) { return error }
        if !boardTiles(board).isEmpty && board[center.row][center.column] == 46 { return "center empty" }
        if !connected(board) { return "disconnected" }
        for word in boardWords(board) where !trie.contains(word.word.map(upper)) { return "unknown word \(text(word.word)) at \(position(word))" }
        return nil
    }
    func jobError(_ job: [String], _ seen: Set<String>) -> String? {
        let header = fields(job[0]), kind = header[0], name = header[1]
        if !validName(name) { return "bad name" }; if seen.contains(name) { return "duplicate name" }
        if kind == "TOPN" {
            if !validNumber(header[2], 1, 99) { return "bad count" }; if Strategy(rawValue: header[3]) == nil { return "bad order" }
            let rack = Array(fields(job[1])[1].utf8)
            if !validRack(rack) { return "bad rack" }
            return boardError(job.dropFirst(3).map { Array($0.utf8) }, rack)
        }
        if kind == "VALIDATE" { return boardError(job.dropFirst(2).prefix { !$0.hasPrefix("MOVE") }.map { Array($0.utf8) }, []) }
        if !validNumber(header[2], 1, 2147483646) { return "bad seed" }
        if job.count - 1 < 2 || job.count - 1 > 4 { return "bad player count \(job.count - 1)" }
        var names: Set<String> = []
        for (index, line) in job.dropFirst().enumerated() {
            let parts = fields(line)
            if !validName(parts[1]) || Strategy(rawValue: parts[2]) == nil || (kind == "GAME" && !validNumber(parts[3], 0, 99)) { return "bad player \(index + 1)" }
            if !names.insert(parts[1]).inserted { return "duplicate player \(index + 1)" }
        }
        return nil
    }
    func leaveValue(_ rack: [UInt8]) -> Int {
        let counts = countsOf(rack), duplicates = (0..<26).map { max(0, counts[$0] - 1) }.reduce(0, +)
        let vowelCount = rack.filter { vowels.contains($0) }.count, consonants = rack.filter { $0 != 63 && !vowels.contains($0) }.count
        return rack.map { table.weights[tileIndex($0)] }.reduce(0, +) - 4 * duplicates - 3 * max(0, abs(vowelCount - consonants) - 1)
    }
    func bestLeave(_ rack: [UInt8]) -> [UInt8] {
        let counts = countsOf(rack)
        var chosen = Array(repeating: 0, count: 27), best: [UInt8] = [], bestValue = Int.min
        func choose(_ index: Int, _ count: Int) {
            if index == 27 {
                if count >= rack.count { return }
                let candidate = tileBytes(chosen), value = leaveValue(candidate)
                if value > bestValue || (value == bestValue && (candidate.count > best.count || (candidate.count == best.count && candidate.lexicographicallyPrecedes(best)))) { best = candidate; bestValue = value }
                return
            }
            for amount in 0...counts[index] { chosen[index] = amount; choose(index + 1, count + amount) }
        }
        choose(0, 0)
        return best
    }
    func evaluate(_ board: Board, _ rack: [UInt8], _ move: Move) -> Evaluated {
        let scored = scoreMove(board, move, table.values), leave = removeTiles(rack, scored.tiles.map { tileKind($0.letter) })
        let words = scored.words.map { "\(text($0.move.word)):\($0.score)" }.joined(separator: ",")
        return Evaluated(move: move, score: scored.score, newTiles: scored.tiles, wordList: words, leave: leave, value: leaveValue(leave))
    }
    func legalMoves(_ board: Board, _ rack: [UInt8]) -> [Evaluated] { generate(board, rack, trie).map { evaluate(board, rack, $0) }.sorted(by: standardPrecedes) }
    func positionSummary(_ board: Board) -> String {
        let words = boardWords(board), tiles = boardTiles(board)
        var longest: [UInt8] = [], counts: [UInt8: Int] = [:]
        for word in words where word.word.count > longest.count { longest = word.word }
        for tile in tiles { counts[premiums[tile.row][tile.column], default: 0] += 1 }
        return "position tiles=\(tiles.count) words=\(words.count) longest=\(longest.isEmpty ? "-" : text(longest)) blanks=\(tiles.filter { lowercase($0.letter) }.count) premiums=TW:\(counts[35, default: 0]),DW:\(counts[42, default: 0]),TL:\(counts[94, default: 0]),DL:\(counts[43, default: 0])"
    }
    func topn(_ job: [String]) -> [String] {
        let header = fields(job[0]), name = header[1], count = Int(header[2])!, strategy = Strategy(rawValue: header[3])!, rack = Array(fields(job[1])[1].utf8), board = job.dropFirst(3).map { Array($0.utf8) }
        let moves = legalMoves(board, rack), shown = Array(moves.sorted { strategyPrecedes($0, $1, strategy) }.prefix(count)), unseen = self.unseen(board, rack), anchorSquares = anchors(board)
        let checks = [crossChecks(board, trie), crossChecks(transpose(board), trie)], statistics = checks.map { "\($0.count),\($0.values.filter { $0.isEmpty }.count),\($0.values.map { $0.count }.reduce(0, +))" }
        let across = moves.filter { $0.move.direction == .across }.count, bingos = moves.filter { $0.newTiles.count == rackSize }.count, blanks = moves.filter { $0.newTiles.contains { lowercase($0.letter) } }.count
        let vowelCount = rack.filter { vowels.contains($0) }.count, consonants = rack.filter { $0 != 63 && !vowels.contains($0) }.count
        var lines = ["TOPN \(name) n=\(count) order=\(strategy.rawValue) rack=\(collection(rack))", "board tiles=\(boardTiles(board).count) anchors=\(anchorSquares.count)", "unseen count=\(unseen.count) tiles=\(collection(unseen))", "rack vowels=\(vowelCount) consonants=\(consonants) blanks=\(rack.filter { $0 == 63 }.count) value=\(points(rack, table.values))", "checks across=\(statistics[0]) down=\(statistics[1])", "moves total=\(moves.count) across=\(across) down=\(moves.count - across) bingos=\(bingos) blanks=\(blanks)"]
        lines.append("best_by_tiles" + (1...rackSize).map { number in " \(number)=" + (moves.filter { $0.newTiles.count == number }.map { $0.score }.max().map(String.init) ?? "-") }.joined())
        let keep = bestLeave(rack), anagrams = trie.anagrams(rack).sorted { $0.count == $1.count ? $0.lexicographicallyPrecedes($1) : $0.count > $1.count }
        lines += ["exchange keep=\(collection(keep)) value=\(leaveValue(keep))", "anagrams total=\(anagrams.count) top=\(anagrams.isEmpty ? "-" : anagrams.prefix(10).map(text).joined(separator: ","))"]
        for word in boardWords(board) where word.word.count >= 3 {
            let upperWord = word.word.map(upper), front = letters.filter { trie.contains([$0] + upperWord) }, back = letters.filter { trie.contains(upperWord + [$0]) }
            if !front.isEmpty || !back.isEmpty { lines.append("hook \(position(word)) \(text(word.word)) front=\(front.isEmpty ? "-" : text(front)) back=\(back.isEmpty ? "-" : text(back))") }
        }
        var nets: [Int]?
        if unseen.count >= 1 && unseen.count <= rackSize && !shown.isEmpty {
            let values = shown.map { move in move.score - (legalMoves(applying(board, move.newTiles), unseen).first?.score ?? 0) }
            nets = values
            let best = values.indices.first { values[$0] == values.max()! }!
            lines.append("endgame opponent=\(collection(unseen)) best=\(best + 1) net=\(values[best])")
        }
        for (index, move) in shown.enumerated() {
            let net = nets.map { " net=\($0[index])" } ?? ""
            lines.append("\(index + 1) \(notation(move)) score=\(move.score) tiles=\(move.newTiles.count) leave=\(collection(move.leave)) value=\(move.value)\(net) words=\(move.wordList)")
        }
        topTotals["moves", default: 0] += moves.count; topTotals["bingos", default: 0] += bingos
        return lines
    }
}
struct ValidationPlayer { let name: String; var moves = 0; var valid = 0; var score = 0; var loss = 0 }
struct GameStatistics { var plays = 0; var bingos = 0; var exchanges = 0; var passes = 0; var top = 0; var loss = 0 }
struct GamePlayer { let name: String; let strategy: Strategy; let threshold: Int; var rack: [UInt8]; var score = 0; var statistics = GameStatistics() }
struct Highlight { let turn: Int; let player: String; let move: Evaluated }
extension Scrabble {
    func recordError(_ board: Board, _ player: String, _ rack: [UInt8], _ action: [String]) -> (error: String?, move: Move?) {
        if !validName(player) { return ("bad player", nil) }
        if !validRack(rack) { return ("bad rack", nil) }
        if let error = tileError(board, rack) { return (error, nil) }
        if action.count == 1 && action[0] == "PASS" { return (nil, nil) }
        if action[0] == "EXCHANGE" {
            let returned = Array(action[1].utf8)
            if !validRack(returned) { return ("bad exchange", nil) }
            let available = countsOf(rack), requested = countsOf(returned)
            for letter in returned where requested[tileIndex(letter)] > available[tileIndex(letter)] { return ("rack lacks " + String(UnicodeScalar(letter)), nil) }
            return (nil, nil)
        }
        guard let parsed = parsePosition(action[0]) else { return ("bad position", nil) }
        let word = Array(action[1].utf8)
        if !validWord(word) { return ("bad word", nil) }
        let move = Move(row: parsed.row, column: parsed.column, direction: parsed.direction, word: word), cells = squares(move)
        if cells.contains(where: { !inside($0.row, $0.column) }) { return ("off board", nil) }
        for cell in cells where board[cell.row][cell.column] != 46 && board[cell.row][cell.column] != cell.letter { return ("mismatch at " + squareName(cell.row, cell.column), nil) }
        let dr = move.direction.dr, dc = move.direction.dc, before = Square(row: move.row - dr, column: move.column - dc), after = Square(row: move.row + dr * word.count, column: move.column + dc * word.count)
        if [before, after].contains(where: { inside($0.row, $0.column) && board[$0.row][$0.column] != 46 }) { return ("not whole word", nil) }
        let newTiles = placement(board, move)
        if newTiles.isEmpty { return ("no new tiles", nil) }
        var available = countsOf(rack)
        for tile in newTiles {
            let kind = tileKind(tile.letter), index = tileIndex(kind)
            if available[index] == 0 { return ("rack lacks " + String(UnicodeScalar(kind)), nil) }
            available[index] -= 1
        }
        if boardTiles(board).isEmpty { if !newTiles.contains(where: { $0.square == center }) { return ("center not covered", nil) } }
        else if !newTiles.contains(where: { tile in neighbors(tile.square).contains { board[$0.row][$0.column] != 46 } }) { return ("not connected", nil) }
        for formed in [move] + crossWords(board, move) where !trie.contains(formed.word.map(upper)) { return ("unknown word \(text(formed.word)) at \(position(formed))", nil) }
        return (nil, move)
    }
    func validate(_ job: [String]) -> [String] {
        let name = fields(job[0])[1], records = Array(job.dropFirst(2 + boardSize))
        var board = job.dropFirst(2).prefix(boardSize).map { Array($0.utf8) }, lines = ["VALIDATE " + name], players: [ValidationPlayer] = [], totals: [String: Int] = [:]
        for (index, line) in records.enumerated() {
            let parts = fields(line), player = parts[1], rack = Array(parts[2].utf8), action = Array(parts.dropFirst(3)), prefix = "move \(index + 1) \(player) " + action.joined(separator: " "), result = recordError(board, player, rack, action)
            var playerIndex: Int?
            if result.error != "bad player" {
                if let previous = players.firstIndex(where: { $0.name == player }) { playerIndex = previous } else { playerIndex = players.count; players.append(ValidationPlayer(name: player)) }
                players[playerIndex!].moves += 1
            }
            if let error = result.error { lines.append(prefix + " invalid " + error); totals["invalid", default: 0] += 1; continue }
            let legal = legalMoves(board, rack), best = legal.first?.score ?? 0, evaluated = result.move.map { evaluate(board, rack, $0) }, score = evaluated?.score ?? 0, pi = playerIndex!
            players[pi].valid += 1; players[pi].score += score; players[pi].loss += best - score
            totals["valid", default: 0] += 1; totals["score", default: 0] += score; totals["best", default: 0] += best; totals["loss", default: 0] += best - score
            if let evaluated {
                let rank = legal.firstIndex { $0.key == evaluated.key }! + 1
                lines.append("\(prefix) score=\(score) total=\(players[pi].score) tiles=\(evaluated.newTiles.count) rank=\(rank)/\(legal.count) best=\(best) words=\(evaluated.wordList)")
                board = applying(board, evaluated.newTiles)
            } else { lines.append("\(prefix) score=0 total=\(players[pi].score) moves=\(legal.count) best=\(best)") }
        }
        for player in players { lines.append("player \(player.name) moves=\(player.moves) valid=\(player.valid) score=\(player.score) loss=\(player.loss)") }
        lines.append("total valid=\(totals["valid", default: 0]) invalid=\(totals["invalid", default: 0]) score=\(totals["score", default: 0]) best=\(totals["best", default: 0]) loss=\(totals["loss", default: 0])")
        lines.append(positionSummary(board)); lines += display(board)
        validationTotals["moves", default: 0] += records.count
        for key in ["valid", "invalid", "loss"] { validationTotals[key, default: 0] += totals[key, default: 0] }
        return lines
    }
    func ordinaryGame(_ job: [String]) -> [String] {
        let header = fields(job[0]), name = header[1], seed = Int64(header[2])!, random = Minstd(seed)
        var bag = makeBag(table.counts, random), board = Array(repeating: Array(repeating: UInt8(46), count: boardSize), count: boardSize), players: [GamePlayer] = [], lines = ["GAME \(name) seed=\(seed) players=\(job.count - 1)"]
        for (index, line) in job.dropFirst().enumerated() {
            let parts = fields(line), player = GamePlayer(name: parts[1], strategy: Strategy(rawValue: parts[2])!, threshold: Int(parts[3])!, rack: draw(&bag, rackSize))
            players.append(player); lines.append("player \(index + 1) \(player.name) strategy=\(player.strategy.rawValue) threshold=\(player.threshold)")
        }
        var turn = 0, consecutive = 0, outgoing: Int?, highlight: Highlight?
        while true {
            let index = turn % players.count
            var player = players[index]
            turn += 1
            let rack = player.rack, legal = legalMoves(board, rack), candidate = legal.min { strategyPrecedes($0, $1, player.strategy) }, prefix = "turn \(turn) \(player.name) rack=\(collection(rack)) moves=\(legal.count)"
            var wentOut = false
            if let candidate, !(candidate.score < player.threshold && bag.count >= rackSize) {
                let best = legal[0].score
                board = applying(board, candidate.newTiles); player.score += candidate.score
                let drawn = draw(&bag, rackSize - candidate.leave.count)
                player.rack = candidate.leave + drawn; player.statistics.plays += 1; player.statistics.bingos += candidate.newTiles.count == rackSize ? 1 : 0
                player.statistics.top = max(player.statistics.top, candidate.score); player.statistics.loss += best - candidate.score; consecutive = 0
                if highlight == nil || candidate.score > highlight!.move.score { highlight = Highlight(turn: turn, player: player.name, move: candidate) }
                lines.append("\(prefix) best=\(best) play \(notation(candidate)) score=\(candidate.score) total=\(player.score) draw=\(collection(drawn)) bag=\(bag.count)")
                wentOut = player.rack.isEmpty && bag.isEmpty
            } else if bag.count >= rackSize {
                let keep = bestLeave(rack), returned = removeTiles(rack, keep), drawn = exchange(&bag, returned, random)
                player.rack = keep + drawn; player.statistics.exchanges += 1; consecutive += 1
                lines.append("\(prefix) exchange keep=\(collection(keep)) draw=\(collection(drawn)) bag=\(bag.count)")
            } else { player.statistics.passes += 1; consecutive += 1; lines.append("\(prefix) pass bag=\(bag.count)") }
            players[index] = player
            if wentOut { outgoing = index; break }; if consecutive == 6 { break }
        }
        if let outgoing { lines.append("end reason=out player=\(players[outgoing].name) turns=\(turn)") } else { lines.append("end reason=scoreless turns=\(turn)") }
        var adjustments = players.map { -points($0.rack, table.values) }
        if let outgoing { adjustments[outgoing] = players.indices.filter { $0 != outgoing }.map { points(players[$0].rack, table.values) }.reduce(0, +) }
        let scores = players.indices.map { players[$0].score + adjustments[$0] }
        for index in players.indices {
            let player = players[index], adjustment = adjustments[index], adjusted = adjustment > 0 ? "+\(adjustment)" : String(adjustment)
            lines.append("final \(player.name) score=\(player.score) rack=\(collection(player.rack)) adjust=\(adjusted) total=\(scores[index])")
        }
        let standings = players.indices.sorted { scores[$0] == scores[$1] ? $0 < $1 : scores[$0] > scores[$1] }
        for (rank, index) in standings.enumerated() {
            let player = players[index], stats = player.statistics
            lines.append("standing \(rank + 1) \(player.name) total=\(scores[index]) plays=\(stats.plays) bingos=\(stats.bingos) exchanges=\(stats.exchanges) passes=\(stats.passes) top=\(stats.top) loss=\(stats.loss)")
        }
        lines.append("winner " + players.indices.filter { scores[$0] == scores.max()! }.map { players[$0].name }.joined(separator: ","))
        if let highlight { lines.append("highlight turn=\(highlight.turn) player=\(highlight.player) play \(notation(highlight.move)) score=\(highlight.move.score)") }
        lines.append(positionSummary(board)); lines += display(board)
        gameTotals["turns", default: 0] += turn
        for player in players { let stats = player.statistics; gameTotals["plays", default: 0] += stats.plays; gameTotals["bingos", default: 0] += stats.bingos; gameTotals["exchanges", default: 0] += stats.exchanges; gameTotals["passes", default: 0] += stats.passes }
        return lines
    }
    func duplicateGame(_ job: [String]) -> [String] {
        let header = fields(job[0]), name = header[1], seed = Int64(header[2])!, random = Minstd(seed), players = job.dropFirst().map { line -> (name: String, strategy: Strategy) in let parts = fields(line); return (parts[1], Strategy(rawValue: parts[2])!) }
        var bag = makeBag(table.counts, random), board = Array(repeating: Array(repeating: UInt8(46), count: boardSize), count: boardSize), rack = draw(&bag, rackSize), totals = Array(repeating: 0, count: players.count), lines = ["DUPLICATE \(name) seed=\(seed) players=\(players.count)"]
        for (index, player) in players.enumerated() { lines.append("player \(index + 1) \(player.name) strategy=\(player.strategy.rawValue)") }
        var round = 0, masterTotal = 0, reason = "stuck"
        while true {
            let legal = legalMoves(board, rack)
            guard let master = legal.first else { break }
            round += 1
            let choices = players.map { player in legal.min { strategyPrecedes($0, $1, player.strategy) }! }
            for index in players.indices { totals[index] += choices[index].score }
            masterTotal += master.score
            lines.append("round \(round) rack=\(collection(rack)) moves=\(legal.count) master \(notation(master)) score=\(master.score) picks=\(choices.map { String($0.score) }.joined(separator: ","))")
            board = applying(board, master.newTiles); rack = master.leave + draw(&bag, rackSize - master.leave.count)
            if rack.isEmpty { reason = "out"; break }
        }
        lines += ["end reason=\(reason) rounds=\(round)" + (reason == "stuck" ? " rack=" + collection(rack) : ""), "master total=\(masterTotal)"]
        for index in players.indices { let percent = masterTotal >= 1 ? 100 * totals[index] / masterTotal : 0; lines.append("final \(players[index].name) total=\(totals[index]) percent=\(percent)") }
        lines.append("winner " + players.indices.filter { totals[$0] == totals.max()! }.map { players[$0].name }.joined(separator: ","))
        lines.append(positionSummary(board)); lines += display(board); gameTotals["rounds", default: 0] += round
        return lines
    }
    func process(_ jobs: [[String]], _ dictionaryLines: [String]) -> [[[String]]] {
        var moveBlocks = [dictionaryLines], validationBlocks: [[String]] = [], gameBlocks: [[String]] = [], seen: Set<String> = []
        for job in jobs {
            let header = fields(job[0]), kind = header[0], name = header[1]
            if kind == "TOPN" { topTotals["jobs", default: 0] += 1 } else if kind == "VALIDATE" { validationTotals["jobs", default: 0] += 1 } else { gameTotals[kind == "GAME" ? "games" : "duplicates", default: 0] += 1 }
            let error = jobError(job, seen)
            seen.insert(name)
            if let error {
                let block = [kind + " " + name, "error " + error]
                if kind == "TOPN" { moveBlocks.append(block); topTotals["errors", default: 0] += 1 } else if kind == "VALIDATE" { validationBlocks.append(block); validationTotals["errors", default: 0] += 1 } else { gameBlocks.append(block); gameTotals["errors", default: 0] += 1 }
            } else if kind == "TOPN" { moveBlocks.append(topn(job)) } else if kind == "VALIDATE" { validationBlocks.append(validate(job)) } else if kind == "GAME" { gameBlocks.append(ordinaryGame(job)) } else { gameBlocks.append(duplicateGame(job)) }
        }
        moveBlocks.append(["SUMMARY " + ["jobs", "errors", "moves", "bingos"].map { "\($0)=\(topTotals[$0, default: 0])" }.joined(separator: " ")])
        validationBlocks.append(["SUMMARY " + ["jobs", "errors", "moves", "valid", "invalid", "loss"].map { "\($0)=\(validationTotals[$0, default: 0])" }.joined(separator: " ")])
        gameBlocks.append(["SUMMARY " + ["games", "duplicates", "errors", "turns", "rounds", "plays", "exchanges", "passes", "bingos"].map { "\($0)=\(gameTotals[$0, default: 0])" }.joined(separator: " ")])
        return [moveBlocks, validationBlocks, gameBlocks]
    }
}
let input = try readInputs(), program = Scrabble(input.table, input.trie), reports = program.process(input.jobs, input.dictionaryLines)
try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
for (name, blocks) in zip(["moves.txt", "validation.txt", "game.txt"], reports) {
    let contents = blocks.map { $0.joined(separator: "\n") }.joined(separator: "\n\n") + "\n"
    try contents.write(toFile: "output/" + name, atomically: false, encoding: .ascii)
}
