import Foundation

struct ChessError: Error {
    let reason: String
}

func fail(_ s: String) throws -> Never {
    throw ChessError(reason: s)
}

func square(_ s: String) -> Int? {
    let a = Array(s.utf8)
    guard a.count == 2, (97...104).contains(a[0]), (49...56).contains(a[1]) else {
        return nil
    }
    return Int(a[1] - 49) * 8 + Int(a[0] - 97)
}

func name(_ s: Int) -> String {
    String(UnicodeScalar(97 + s % 8)!) + String(s / 8 + 1)
}

func color(_ p: String) -> Bool {
    p == p.uppercased()
}

func number(_ s: String, _ lo: Int, _ hi: Int) -> Int? {
    guard !s.isEmpty, s.utf8.allSatisfy({
        (48...57).contains($0)
    }), s == "0" || s.first != "0", let n = Int(s), (lo...hi).contains(n) else {
        return nil
    }
    return n
}

struct Move: Equatable {
    let s: Int
    let t: Int
    var promotion = ""
}

struct Position {
    var board = Array(repeating: ".", count: 64)
    var white = true
    var rights = ""
    var ep: Int? = nil
    var half = 0
    var full = 1
    func attacks(_ s: Int, _ t: Int) -> Bool {
        if s == t || board[s] == "." {
            return false
        }
        let dx = t % 8 - s % 8
        let dy = t / 8 - s / 8
        let p = board[s].uppercased()
        if p == "P" {
            return abs(dx) == 1 && dy == (color(board[s]) ? 1 : -1)
        }
        if p == "N" {
            return abs(dx) * abs(dy) == 2
        }
        if p == "K" {
            return max(abs(dx), abs(dy)) == 1
        }
        let straight = dx == 0 || dy == 0
        let diagonal = abs(dx) == abs(dy)
        if !(p == "Q" && (straight || diagonal) || p == "R" && straight || p == "B" && diagonal) {
            return false
        }
        let sx = dx.signum()
        let sy = dy.signum()
        var x = s % 8 + sx
        var y = s / 8 + sy
        while x != t % 8 || y != t / 8 {
            if board[y * 8 + x] != "." {
                return false
            }
            x += sx
            y += sy
        }
        return true
    }
    func attacked(_ t: Int, _ byWhite: Bool) -> Bool {
        (0..<64).contains {
            board[$0] != "." && color(board[$0]) == byWhite && attacks($0, t)
        }
    }
    func check(_ side: Bool) -> Bool {
        guard let king = board.firstIndex(of: side ? "K" : "k") else {
            return true
        }
        return attacked(king, !side)
    }
    func castle(_ m: Move) -> Bool {
        board[m.s].uppercased() == "K" && abs(m.s - m.t) == 2
    }
    func enPassant(_ m: Move) -> Bool {
        board[m.s].uppercased() == "P" && m.s % 8 != m.t % 8 && board[m.t] == "."
    }
    func capture(_ m: Move) -> Bool {
        board[m.t] != "." || enPassant(m)
    }
    func after(_ m: Move) -> Position {
        var q = self
        let p = board[m.s]
        let pawn = p.uppercased() == "P"
        if enPassant(m) {
            q.board[m.t + (white ? -8 : 8)] = "."
        }
        if castle(m) {
            let r = m.s / 8 * 8
            let from = r + (m.t > m.s ? 7 : 0)
            let to = r + (m.t > m.s ? 5 : 3)
            q.board[to] = q.board[from]
            q.board[from] = "."
        }
        q.board[m.t] = m.promotion.isEmpty ? p : (white ? m.promotion : m.promotion.lowercased())
        q.board[m.s] = "."
        q.half = pawn || capture(m) ? 0 : half + 1
        if p.uppercased() == "K" {
            q.rights.removeAll {
                (white ? "KQ" : "kq").contains($0)
            }
        }
        for (s, r) in [(0, Character("Q")), (7, Character("K")), (56, Character("q")), (63, Character("k"))] where m.s == s || m.t == s {
            q.rights.removeAll {
                $0 == r
            }
        }
        q.ep = pawn && abs(m.t - m.s) == 16 ? (m.s + m.t) / 2 : nil
        q.full += white ? 0 : 1
        q.white.toggle()
        return q
    }
    func pseudo() -> [Move] {
        var result: [Move] = []
        for s in 0..<64 where board[s] != "." && color(board[s]) == white {
            let pawn = board[s].uppercased() == "P"
            let step = white ? 8 : -8
            for t in 0..<64 {
                if board[t] != "." && color(board[t]) == white {
                    continue
                }
                var valid = attacks(s, t)
                if pawn {
                    valid = (t == s + step && board[t] == ".") || (t == s + step * 2 && s / 8 == (white ? 1 : 6) && board[s + step] == "." && board[t] == ".") || (attacks(s, t) && (board[t] != "." || ep == t))
                }
                if valid {
                    if pawn && t / 8 == (white ? 7 : 0) {
                        for p in ["Q", "R", "B", "N"] {
                            result.append(Move(s: s, t: t, promotion: p))
                        }
                    }
                    else {
                        result.append(Move(s: s, t: t))
                    }
                }
            }
        }
        return result
    }
    func castleReason(_ kingSide: Bool) -> String? {
        let right = white ? (kingSide ? "K" : "Q") : (kingSide ? "k" : "q")
        let base = white ? 0 : 56
        if !rights.contains(right) {
            return "no castling right"
        }
        if (kingSide ? [5, 6] : [1, 2, 3]).contains(where: {
            board[base + $0] != "."
        }) {
            return "path blocked"
        }
        if check(white) {
            return "in check"
        }
        if attacked(base + (kingSide ? 5 : 3), !white) {
            return "through check"
        }
        if after(Move(s: base + 4, t: base + (kingSide ? 6 : 2))).check(white) {
            return "into check"
        }
        return nil
    }
    func legal() -> [Move] {
        var moves = pseudo().filter {
            !after($0).check(white)
        }
        let base = white ? 0 : 56
        for ks in [true, false] where castleReason(ks) == nil {
            moves.append(Move(s: base + 4, t: base + (ks ? 6 : 2)))
        }
        return moves
    }
    func disambiguation(_ m: Move, _ moves: [Move]) -> String {
        let others = moves.filter {
            $0.s != m.s && $0.t == m.t && board[$0.s] == board[m.s] && !castle($0)
        }
        if others.isEmpty {
            return ""
        }
        if others.allSatisfy({
            $0.s % 8 != m.s % 8
        }) {
            return String(name(m.s).prefix(1))
        }
        if others.allSatisfy({
            $0.s / 8 != m.s / 8
        }) {
            return String(m.s / 8 + 1)
        }
        return name(m.s)
    }
    func mark(_ m: Move) -> String {
        let q = after(m)
        return q.check(q.white) ? (q.legal().isEmpty ? "#" : "+") : ""
    }
    func san(_ m: Move, _ moves: [Move]) -> String {
        var s = ""
        if castle(m) {
            s = m.t > m.s ? "O-O" : "O-O-O"
        }
        else if board[m.s].uppercased() == "P" {
            s = (capture(m) ? String(name(m.s).prefix(1)) + "x" : "") + name(m.t)
            if !m.promotion.isEmpty {
                s += "=" + m.promotion
            }
        } else {
            s = board[m.s].uppercased() + disambiguation(m, moves) + (capture(m) ? "x" : "") + name(m.t)
        }
        return s + mark(m)
    }
    func readMove(_ w: String, _ uci: Bool) throws -> Move {
        var u = w
        var promo = ""
        var suffix = ""
        var kind = "P"
        var file = ""
        var rank = ""
        var cap = false
        var ks: Bool? = nil
        var from: Int? = nil
        var target = 0
        if uci {
            let a = Array(w)
            guard a.count == 4 || a.count == 5, let s = square(String(a[0..<2])), let t = square(String(a[2..<4])), a.count == 4 || "qrbn".contains(a[4]) else {
                try fail("syntax")
            }
            from = s
            target = t
            if a.count == 5 {
                promo = String(a[4]).uppercased()
            }
        } else {
            if u.last == "+" || u.last == "#" {
                suffix = String(u.removeLast())
            }
            if u == "O-O" || u == "O-O-O" {
                ks = u == "O-O"
            }
            else {
                if u.count >= 2 && u.dropLast().last == "=" {
                    promo = String(u.removeLast())
                    u.removeLast()
                    if !["Q", "R", "B", "N"].contains(promo) {
                        try fail("syntax")
                    }
                }
                guard u.count >= 2, let t = square(String(u.suffix(2))) else {
                    try fail("syntax")
                }
                target = t
                u.removeLast(2)
                if u.last == "x" {
                    cap = true
                    u.removeLast()
                }
                if let c = u.first, "KQRBN".contains(c) {
                    kind = String(u.removeFirst())
                    if let c = u.first, "abcdefgh".contains(c) {
                        file = String(u.removeFirst())
                    }
                    if let c = u.first, "12345678".contains(c) {
                        rank = String(u.removeFirst())
                    }
                    if !u.isEmpty || !promo.isEmpty {
                        try fail("syntax")
                    }
                } else if cap {
                    if u.count != 1 || !"abcdefgh".contains(u) {
                        try fail("syntax")
                    }
                    file = u
                } else if !u.isEmpty {
                    try fail("syntax")
                }
            }
        }
        let moves = legal()
        if moves.isEmpty {
            try fail("game over")
        }
        if let ks = ks {
            if let r = castleReason(ks) {
                try fail(r)
            }
            let base = white ? 0 : 56
            let m = Move(s: base + 4, t: base + (ks ? 6 : 2))
            if mark(m) != suffix {
                try fail("check mark")
            }
            return m
        }
        if let s = from, board[s] == "." || color(board[s]) != white {
            try fail("no piece")
        }
        func matches(_ m: Move) -> Bool {
            if m.t != target {
                return false
            }
            if let s = from {
                return m.s == s
            }
            return !castle(m) && board[m.s].uppercased() == kind && (file.isEmpty || name(m.s).hasPrefix(file)) && (rank.isEmpty || name(m.s).hasSuffix(rank)) && (kind != "P" || (m.s % 8 != m.t % 8) == cap)
        }
        let matching = moves.filter(matches)
        if matching.isEmpty {
            try fail(pseudo().contains(where: matches) ? "leaves king in check" : "no such move")
        }
        if Set(matching.map {
            $0.s
        }).count > 1 {
            try fail("ambiguous")
        }
        let m = matching[0]
        if !uci && capture(m) != cap {
            try fail("capture mark")
        }
        if !m.promotion.isEmpty && promo.isEmpty {
            try fail("missing promotion")
        }
        if m.promotion.isEmpty && !promo.isEmpty {
            try fail("invalid promotion")
        }
        if !uci && kind != "P" && file + rank != disambiguation(m, moves) {
            try fail("disambiguation")
        }
        let chosen = matching.first {
            $0.promotion == promo
        }!
        if !uci && mark(chosen) != suffix {
            try fail("check mark")
        }
        return chosen
    }
    func fen() -> String {
        var ranks: [String] = []
        for r in stride(from: 7, through: 0, by: -1) {
            var row = ""
            var empty = 0
            for f in 0..<8 {
                let p = board[r * 8 + f]
                if p == "." {
                    empty += 1
                } else {
                    if empty > 0 {
                        row += String(empty)
                        empty = 0
                    }
                    row += p
                }
            }
            if empty > 0 {
                row += String(empty)
            }
            ranks.append(row)
        }
        return ranks.joined(separator: "/") + " \(white ? "w" : "b") \(rights.isEmpty ? "-" : rights) \(ep.map(name) ?? "-") \(half) \(full)"
    }
    func key() -> String {
        let e = legal().contains {
            enPassant($0)
        } ? ep.map(name) ?? "-" : "-"
        return board.joined() + (white ? "w" : "b") + rights + e
    }
}

func load(_ fields: [String]) throws -> Position {
    if fields.count != 6 {
        try fail("fields")
    }
    let ranks = fields[0].components(separatedBy: "/")
    if ranks.count != 8 {
        try fail("placement")
    }
    var p = Position()
    for (i, rank) in ranks.enumerated() {
        var row: [String] = []
        var digit = false
        for c in rank {
            if "12345678".contains(c) {
                if digit {
                    try fail("placement")
                }
                row += Array(repeating: ".", count: Int(String(c))!)
                digit = true
            } else {
                if !"KQRBNPkqrbnp".contains(c) {
                    try fail("placement")
                }
                row.append(String(c))
                digit = false
            }
        }
        if row.count != 8 {
            try fail("placement")
        }
        for f in 0..<8 {
            p.board[(7 - i) * 8 + f] = row[f]
        }
    }
    if p.board.filter({
        $0 == "K"
    }).count != 1 || p.board.filter({
        $0 == "k"
    }).count != 1 {
        try fail("kings")
    }
    if (Array(0..<8) + Array(56..<64)).contains(where: {
        p.board[$0].uppercased() == "P"
    }) {
        try fail("pawns")
    }
    if fields[1] != "w" && fields[1] != "b" {
        try fail("side")
    }
    p.white = fields[1] == "w"
    let rights = fields[2] == "-" ? "" : fields[2]
    if fields[2] != "-" && (rights.isEmpty || String("KQkq".filter {
        rights.contains($0)
    }) != rights) {
        try fail("castling")
    }
    for (r, k, s, piece) in [("K",4,7,"R"),("Q",4,0,"R"),("k",60,63,"r"),("q",60,56,"r")] where rights.contains(r) {
        if p.board[k] != (k == 4 ? "K" : "k") || p.board[s] != piece {
            try fail("castling")
        }
    }
    p.rights = rights
    if fields[3] != "-" {
        guard let e = square(fields[3]) else {
            try fail("en passant")
        }
        if e / 8 != (p.white ? 5 : 2) || p.board[e] != "." || p.board[e + (p.white ? 8 : -8)] != "." || p.board[e + (p.white ? -8 : 8)] != (p.white ? "p" : "P") {
            try fail("en passant")
        }
        p.ep = e
    }
    guard let h = number(fields[4],0,999), let f = number(fields[5],1,999), p.ep == nil || h == 0 else {
        try fail("clocks")
    }
    p.half = h
    p.full = f
    if p.check(!p.white) {
        try fail("check")
    }
    return p
}

func perft(_ p: Position, _ d: Int) -> [Int] {
    if d == 0 {
        return [1,0,0,0,0,0,0]
    }
    var counts = Array(repeating: 0, count: 7)
    for m in p.legal() {
        let q = p.after(m)
        if d == 1 {
            counts[0] += 1
            counts[1] += p.capture(m) ? 1 : 0
            counts[2] += p.enPassant(m) ? 1 : 0
            counts[3] += p.castle(m) ? 1 : 0
            counts[4] += m.promotion.isEmpty ? 0 : 1
            if q.check(q.white) {
                counts[5] += 1
                if q.legal().isEmpty {
                    counts[6] += 1
                }
            }
        } else {
            let c = perft(q,d-1)
            for i in 0..<7 {
                counts[i] += c[i]
            }
        }
    }
    return counts
}

struct Record {
    let before: Position
    let san: String
    let uci: String
    let captured: String
}
let initial = try! load("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".components(separatedBy: " "))
var position = initial
var start = initial
var loaded = false
var history: [Record] = []

func state() -> (String, Int, [String], String) {
    let moves = position.legal()
    let check = position.check(position.white)
    let s = moves.isEmpty ? (check ? "checkmate" : "stalemate") : (check ? "check" : "normal")
    let key = position.key()
    let rep = (history.map {
        $0.before
    } + [position]).filter {
        $0.key() == key
    }.count
    var marks: [String] = []
    if position.half >= 100 {
        marks.append("fifty")
    }
    if rep >= 3 {
        marks.append("threefold")
    }
    let pieces = (0..<64).filter {
        position.board[$0] != "." && position.board[$0].uppercased() != "K"
    }
    if !pieces.contains(where: {
        "PRQ".contains(position.board[$0].uppercased())
    }) && (pieces.count <= 1 || pieces.allSatisfy {
        position.board[$0].uppercased() == "B"
    } && Set(pieces.map {
        ($0 / 8 + $0 % 8) % 2
    }).count <= 1) {
        marks.append("insufficient")
    }
    let result = s == "checkmate" ? (position.white ? "0-1" : "1-0") : (s == "stalemate" || !marks.isEmpty ? "1/2-1/2" : "*")
    return (s,rep,marks,result)
}
let n = Int(readLine()!)!
for _ in 0..<n {
    let words = readLine()!.components(separatedBy: " ")
    let command = words[0]
    let a = Array(words.dropFirst())
    if !["NEW","LOAD","FEN","BOARD","MOVE","UCI","LEGAL","STATUS","UNDO","PERFT","DIVIDE","ATTACKS","PINS","HISTORY","PGN"].contains(command) {
        print("ERROR unknown command")
        continue
    }
    var valid = true
    if ["NEW","FEN","BOARD","STATUS","PINS","HISTORY","PGN"].contains(command) {
        valid = a.isEmpty
    }
    if command == "MOVE" || command == "UCI" {
        valid = !a.isEmpty
    }
    if command == "LEGAL" {
        valid = a.count <= 1 && (a.isEmpty || square(a[0]) != nil)
    }
    if command == "ATTACKS" {
        valid = a.count == 1 && square(a[0]) != nil
    }
    if ["UNDO","PERFT","DIVIDE"].contains(command) {
        valid = a.count == 1 && number(a[0],1,command == "UNDO" ? 9999 : 3) != nil
    }
    if !valid {
        print("ERROR bad arguments")
        continue
    }
    switch command {
        case "NEW": position = initial
        start = initial
        loaded = false
        history = []
        print("OK")
        case "LOAD": do {
            let p = try load(a)
            position = p
            start = p
            loaded = true
            history = []
            print("OK")
        } catch let e as ChessError {
            print("ERROR bad fen (\(e.reason))")
        } catch {
        }
        case "FEN": print(position.fen())
        case "BOARD":
        for r in stride(from: 7, through: 0, by: -1) {
            print("\(r+1) " + position.board[(r*8)..<(r*8+8)].joined(separator: " "))
        }
        print("  a b c d e f g h")
        case "MOVE", "UCI":
        var sans: [String] = []
        var error: String? = nil
        for (i,w) in a.enumerated() {
            do {
                let m = try position.readMove(w,command == "UCI")
                let san = position.san(m,position.legal())
                history.append(Record(before: position, san: san, uci: name(m.s)+name(m.t)+m.promotion.lowercased(), captured: position.enPassant(m) ? "p" : (position.board[m.t] == "." ? "-" : position.board[m.t].lowercased())))
                position = position.after(m)
                sans.append(san)
            } catch let e as ChessError {
                error = "ILLEGAL move \(i+1): \(w) (\(e.reason))"
                break
            } catch {
            }
        }
        if command == "UCI" && !sans.isEmpty {
            print("san " + sans.joined(separator: " "))
        }
        if let e = error {
            print(e)
        } else if command == "MOVE" {
            print("OK")
        }
        case "LEGAL":
        let moves = position.legal()
        let names = moves.filter {
            a.isEmpty || $0.s == square(a[0])
        }.map {
            position.san($0,moves)
        }.sorted()
        print((["legal",String(names.count)] + names).joined(separator: " "))
        case "STATUS": let (s,r,m,_) = state()
        print((["status",position.white ? "white" : "black",s,"rep",String(r)] + m).joined(separator: " "))
        case "UNDO": let k = Int(a[0])!
        if k > history.count {
            print("ERROR cannot undo")
        } else {
            position = history[history.count-k].before
            history.removeLast(k)
            print("OK")
        }
        case "PERFT":
        let d = Int(a[0])!
        let c = perft(position,d)
        let keys = ["nodes","captures","ep","castles","promotions","checks","mates"]
        print("perft \(d) " + zip(keys,c).map {
            "\($0.0) \($0.1)"
        }.joined(separator: " "))
        case "DIVIDE":
        let moves = position.legal()
        let entries = moves.map {
            (position.san($0,moves),perft(position.after($0),Int(a[0])!-1)[0])
        }.sorted {
            $0.0 < $1.0
        }
        for (s,c) in entries {
            print("\(s) \(c)")
        }
        print("total \(entries.reduce(0) { $0 + $1.1 })")
        case "ATTACKS":
        let t = square(a[0])!
        let w = (0..<64).filter {
            position.board[$0] != "." && color(position.board[$0]) && position.attacks($0,t)
        }.map(name), b = (0..<64).filter {
            position.board[$0] != "." && !color(position.board[$0]) && position.attacks($0,t)
        }.map(name)
        print((["attacks",a[0],"white",String(w.count)] + w + ["black",String(b.count)] + b).joined(separator: " "))
        case "PINS":
        let k = position.board.firstIndex(of: position.white ? "K" : "k")!
        var pins: [(Int,Int)] = []
        for (dx,dy) in [(1,0),(-1,0),(0,1),(0,-1),(1,1),(1,-1),(-1,1),(-1,-1)] {
            var x = k % 8 + dx
            var y = k / 8 + dy
            var first: Int? = nil
            while (0..<8).contains(x) && (0..<8).contains(y) {
                let s = y*8+x
                let p = position.board[s]
                if p != "." {
                    if first == nil {
                        if color(p) != position.white {
                            break
                        }
                        first = s
                    }
                    else {
                        if color(p) != position.white && (p.uppercased() == "Q" || p.uppercased() == (dx == 0 || dy == 0 ? "R" : "B")) {
                            pins.append((first!,s))
                        }
                        break
                    }
                }
                x += dx
                y += dy
            }
        }
        print((["pins",String(pins.count)] + pins.sorted {
            $0.0 < $1.0
        }.map {
            name($0.0)+"-"+name($0.1)
        }).joined(separator: " "))
        case "HISTORY": print("history \(history.count)")
        for (i,r) in history.enumerated() {
            print("\(i+1) \(r.uci) \(r.san) \(r.captured)")
        }
        case "PGN":
        let result = state().3
        print("[Result \"\(result)\"]")
        if loaded {
            print("[SetUp \"1\"]")
            print("[FEN \"\(start.fen())\"]")
        }
        var tokens: [String] = []
        for (i,r) in history.enumerated() {
            if r.before.white {
                tokens.append("\(r.before.full).")
            } else if i == 0 {
                tokens.append("\(r.before.full)...")
            }
            tokens.append(r.san)
        }
        tokens.append(result)
        print(tokens.joined(separator: " "))
        default: break
    }
}
