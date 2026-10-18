import Foundation

let P=0, G=2, W=4, L=6, R=8, GS=10, SERVE=11, LEG=12, DONE=13, WINNER=14
let TC=15, TS=16, TV=17, TURN=18, LINEUP=21, SUBS=33, TIMEOUTS=35
let POINTS=37, SERVED=39, SERVEWON=41, RUN=43, CURRENT=45, SERVICE=47
let HOLDS=49, BREAKS=51, BPO=53, BPW=55, DARTS=57, SCORED=59, BUSTS=61
let HIGH=63, TONS=65, MAXIMUMS=67, ATTEMPTS=69, HITS=71, FRAME=73, STANDING=74
let ROLLCOUNT=75, ROLLS=76, FRAMEROLLS=97, FIRSTROLL=98, SECONDROLL=99
struct Finished {
    let a: Int
    let b: Int
    var type = 0
    var loser = 0
}
struct Dart {
    let name: String
    let value: Int
    let doubleOut: Bool
}
struct BowlingFrame {
    let marks: String
    let cumulative: Int?
    let open: Bool
}
struct Problem: Error {
    let message: String
}

final class Scoreboard {
    var matches: [String:Match] = [:]
    var darts: [Dart] = []
    var doubles: [Dart] = []
    var dartIndex: [String:Int] = [:]
    var cache: [Int:[String]] = [:]
    init() {
        for prefix in ["S","T","D"] {
            for n in stride(from: 20,through: 1,by: -1) {
                let multiplier = prefix == "S" ? 1 : (prefix == "T" ? 3 : 2)
                let dart = Dart(name: prefix+String(n),value: n*multiplier,doubleOut: prefix == "D")
                darts.append(dart)
                if dart.doubleOut { doubles.append(dart) }
            }
        }
        darts.append(Dart(name: "25",value: 25,doubleOut: false))
        let bull = Dart(name: "BULL",value: 50,doubleOut: true)
        darts.append(bull)
        doubles.append(bull)
        darts.append(Dart(name: "MISS",value: 0,doubleOut: false))
        for (i,dart) in darts.enumerated() { dartIndex[dart.name] = i }
    }
    func checkout(_ score: Int, _ maximum: Int) -> [String] {
        let key = score*4+maximum
        if let answer = cache[key] { return answer }
        func search() -> [String] {
            for a in doubles where a.value == score { return [a.name] }
            if maximum >= 2 {
                for a in darts.prefix(62) {
                    for b in doubles where a.value+b.value == score { return [a.name,b.name] }
                }
            }
            if maximum >= 3 {
                for a in darts.prefix(62) {
                    for b in darts.prefix(62) {
                        for c in doubles where a.value+b.value+c.value == score { return [a.name,b.name,c.name] }
                    }
                }
            }
            return []
        }
        let answer = search()
        cache[key] = answer
        return answer
    }
    func execute(_ line: String) throws -> [String] {
        let t = line.split(separator: " ").map(String.init)
        let command = t[0]
        if command == "MATCH" {
            guard matches[t[1]] == nil else { throw Problem(message: "duplicate match") }
            let match = try Match(self,t)
            matches[t[1]] = match
            return []
        }
        if command == "CHECKOUT" {
            let answer = checkout(Int(t[1])!,3)
            return ["checkout "+t[1]+": "+(answer.isEmpty ? "none" : answer.joined(separator: " "))]
        }
        if command == "STANDINGS" {
            var totals: [String:[Int]] = [:]
            for match in matches.values where match.over() && match.sport != "BOWLING" {
                let winner = match.s[WINNER]
                totals[match.names[winner],default: [0,0]][0] += 1
                totals[match.names[1-winner],default: [0,0]][1] += 1
            }
            let names = totals.keys.sorted {
                if totals[$0]![0] != totals[$1]![0] { return totals[$0]![0] > totals[$1]![0] }
                if totals[$0]![1] != totals[$1]![1] { return totals[$0]![1] < totals[$1]![1] }
                return $0 < $1
            }
            let records = names.map { "\($0) \(totals[$0]![0])-\(totals[$0]![1])" }
            return ["standings: "+(records.isEmpty ? "none" : records.joined(separator: ", "))]
        }
        guard let match = matches[t[1]] else { throw Problem(message: "unknown match") }
        switch command {
        case "UNDO": try match.undo()
        case "SCORE": return [match.score()]
        case "STATS": return match.stats()
        case "RESULT": return [try match.result()]
        default:
            let correct: Bool
            switch command {
            case "POINT": correct = match.rally()
            case "ROLL": correct = match.sport == "BOWLING"
            case "THROW": correct = match.sport == "DARTS"
            default: correct = match.sport == "VOLLEYBALL"
            }
            guard correct else { throw Problem(message: "wrong event") }
            if command == "POINT" {
                for c in t[2] { try match.event(command,String(c),t) }
            } else if command == "ROLL" || command == "THROW" {
                for value in t.dropFirst(2) { try match.event(command,value,t) }
            } else { try match.event(command,"",t) }
        }
        return []
    }
}

final class Match {
    unowned let app: Scoreboard
    let id: String
    let sport: String
    let names: [String]
    var options: [String:String] = [:]
    var initial = Array(repeating: Array(repeating: 0,count: 6),count: 2)
    var s = Array(repeating: 0,count: 100)
    var finished: [Finished] = []
    var history: [[Int]] = []
    init(_ owner: Scoreboard, _ t: [String]) throws {
        app = owner
        id = t[1]
        sport = t[2]
        names = [t[3],sport == "BOWLING" ? "" : t[4]]
        var allowed: [String:Set<String>] = [:]
        if sport != "BOWLING" {
            allowed["FIRST"] = ["A","B"]
            options["FIRST"] = "A"
        }
        if sport == "TENNIS" {
            allowed["SETS"] = ["3","5"]
            allowed["DEUCE"] = ["AD","NOAD"]
            allowed["FINAL"] = ["TB7","TB10","ADV","SUPER"]
            options["SETS"] = "3"
            options["DEUCE"] = "AD"
            options["FINAL"] = "TB7"
        }
        if sport == "TABLETENNIS" {
            allowed["GAMES"] = ["5","7"]
            options["GAMES"] = "5"
        }
        if sport == "DARTS" {
            allowed["START"] = ["301","501","701"]
            allowed["SETS"] = ["1","2","3","4","5"]
            allowed["LEGS"] = ["1","2","3","4","5"]
            options["START"] = "501"
            options["SETS"] = "1"
            options["LEGS"] = "1"
        }
        let firstOption = sport == "BOWLING" ? 4 : (sport == "VOLLEYBALL" ? 7 : 5)
        var seen: Set<String> = []
        for token in t.dropFirst(firstOption) {
            let p = token.components(separatedBy: "=")
            guard p.count == 2, let values = allowed[p[0]], values.contains(p[1]), seen.insert(p[0]).inserted else {
                throw Problem(message: "invalid option")
            }
            options[p[0]] = p[1]
        }
        s[GS] = first()
        s[SERVE] = first()
        s[LEG] = 1
        s[STANDING] = 10
        if sport == "DARTS" {
            s[R] = option("START")
            s[R+1] = option("START")
            s[TS] = option("START")
        }
        if sport == "VOLLEYBALL" {
            for side in 0..<2 {
                let lineup = t[5+side].split(separator: ",").map { Int($0)! }
                for i in 0..<6 {
                    initial[side][i] = lineup[i]
                    s[LINEUP+side*6+i] = lineup[i]
                }
            }
        }
    }
    func first() -> Int { options["FIRST",default: "A"] == "A" ? 0 : 1 }
    func option(_ key: String) -> Int { Int(options[key]!)! }
    func over() -> Bool { s[DONE] != 0 }
    func tennis() -> Bool { sport == "TENNIS" }
    func rally() -> Bool { sport != "DARTS" && sport != "BOWLING" }
    func finalSet() -> Bool { tennis() && s[W] == option("SETS")/2 && s[W+1] == option("SETS")/2 }
    func superTie() -> Bool { finalSet() && options["FINAL"] == "SUPER" }
    func tieBreak() -> Bool { superTie() || (tennis() && s[G] == 6 && s[G+1] == 6 && !(finalSet() && options["FINAL"] == "ADV")) }
    func server() -> Int {
        if tennis() { return s[GS] ^ (tieBreak() ? (s[P]+s[P+1]+1)/2%2 : 0) }
        if sport == "TABLETENNIS" {
            let played = s[P]+s[P+1]
            return first() ^ (finished.count%2) ^ (played < 20 ? played/2%2 : played%2)
        }
        return s[SERVE]
    }
    func normalWin(_ x: Int, _ extra: Int) -> Bool {
        s[P+x]+extra >= 4 && (options["DEUCE"] == "NOAD" || s[P+x]+extra-s[P+1-x] >= 2)
    }
    func endSet(_ x: Int, _ score: Finished) {
        finished.append(score)
        s[W+x] += 1
        let target: Int
        switch sport {
        case "TENNIS": target = option("SETS")/2+1
        case "TABLETENNIS": target = option("GAMES")/2+1
        case "VOLLEYBALL": target = 3
        default: target = 2
        }
        if s[W+x] == target {
            s[DONE] = 1
            s[WINNER] = x
        } else {
            s[P] = 0
            s[P+1] = 0
            s[G] = 0
            s[G+1] = 0
            if sport == "VOLLEYBALL" {
                for side in 0..<2 {
                    s[SUBS+side] = 0
                    s[TIMEOUTS+side] = 0
                    s.replaceSubrange((LINEUP+side*6)..<(LINEUP+side*6+6),with: initial[side])
                }
                s[SERVE] = first() ^ (finished.count%2)
            }
        }
    }
    func point(_ x: Int) {
        let serve = server()
        s[POINTS+x] += 1
        s[SERVED+serve] += 1
        if serve == x { s[SERVEWON+x] += 1 }
        s[CURRENT+1-x] = 0
        s[CURRENT+x] += 1
        s[RUN+x] = max(s[RUN+x],s[CURRENT+x])
        if tennis() {
            let tie = tieBreak()
            let superGame = superTie()
            if !tie && normalWin(1-serve,1) {
                s[BPO+1-serve] += 1
                if x != serve { s[BPW+x] += 1 }
            }
            s[P+x] += 1
            if tie {
                let target = superGame || (finalSet() && options["FINAL"] == "TB10") ? 10 : 7
                if s[P+x] >= target && s[P+x]-s[P+1-x] >= 2 {
                    let score: Finished
                    if superGame { score = Finished(a: s[P],b: s[P+1],type: 2) }
                    else {
                        s[G+x] += 1
                        score = Finished(a: s[G],b: s[G+1],type: 1,loser: s[P+1-x])
                    }
                    s[GS] ^= 1
                    endSet(x,score)
                }
            } else if normalWin(x,0) {
                s[SERVICE+s[GS]] += 1
                if x == s[GS] { s[HOLDS+x] += 1 }
                else { s[BREAKS+x] += 1 }
                s[G+x] += 1
                s[P] = 0
                s[P+1] = 0
                s[GS] ^= 1
                if s[G+x] >= 6 && s[G+x]-s[G+1-x] >= 2 { endSet(x,Finished(a: s[G],b: s[G+1])) }
            }
            return
        }
        s[P+x] += 1
        if sport == "BADMINTON" { s[SERVE] = x }
        if sport == "VOLLEYBALL" && s[SERVE] != x {
            let start = LINEUP+x*6
            let old = s[start]
            for i in 0..<5 { s[start+i] = s[start+i+1] }
            s[start+5] = old
            s[SERVE] = x
        }
        let target = sport == "TABLETENNIS" ? 11 : (sport == "BADMINTON" ? 21 : (finished.count == 4 ? 15 : 25))
        if (s[P+x] >= target && s[P+x]-s[P+1-x] >= 2) || (sport == "BADMINTON" && s[P+x] == 30) {
            endSet(x,Finished(a: s[P],b: s[P+1]))
        }
    }
    func completeTurn(_ x: Int) {
        s[HIGH+x] = max(s[HIGH+x],s[TV])
        if s[TV] >= 100 { s[TONS+x] += 1 }
        if s[TV] == 180 { s[MAXIMUMS+x] += 1 }
    }
    func nextTurn() {
        s[SERVE] ^= 1
        s[TC] = 0
        s[TV] = 0
        s[TS] = s[R+s[SERVE]]
    }
    func dart(_ code: Int) {
        let d = app.darts[code]
        let x = s[SERVE]
        let before = s[R+x]
        if s[TC] == 0 { s[TS] = before }
        if before == 50 || (before <= 40 && before%2 == 0) { s[ATTEMPTS+x] += 1 }
        s[DARTS+x] += 1
        s[TURN+s[TC]] = code
        s[TC] += 1
        s[TV] += d.value
        let remaining = before-d.value
        if remaining < 0 || remaining == 1 || (remaining == 0 && !d.doubleOut) {
            s[SCORED+x] -= s[TV]-d.value
            s[BUSTS+x] += 1
            s[R+x] = s[TS]
            nextTurn()
        } else {
            s[R+x] = remaining
            s[SCORED+x] += d.value
            if remaining == 0 {
                s[HITS+x] += 1
                completeTurn(x)
                s[L+x] += 1
                if s[L+x] == option("LEGS") {
                    finished.append(Finished(a: s[L],b: s[L+1]))
                    s[W+x] += 1
                    if s[W+x] == option("SETS") {
                        s[DONE] = 1
                        s[WINNER] = x
                        return
                    }
                    s[L] = 0
                    s[L+1] = 0
                }
                s[LEG] += 1
                s[R] = option("START")
                s[R+1] = option("START")
                s[SERVE] = first() ^ ((s[LEG]-1)%2)
                s[TC] = 0
                s[TV] = 0
                s[TS] = option("START")
            } else if s[TC] == 3 {
                completeTurn(x)
                nextTurn()
            }
        }
    }
    func roll(_ pins: Int) {
        s[ROLLS+s[ROLLCOUNT]] = pins
        s[ROLLCOUNT] += 1
        let r = s[FRAMEROLLS]
        let frame = s[FRAME]
        if r == 0 { s[FIRSTROLL] = pins }
        if r == 1 { s[SECONDROLL] = pins }
        s[STANDING] -= pins
        let end = frame < 9 ? r == 1 || (r == 0 && pins == 10) :
            r == 2 || (r == 1 && s[FIRSTROLL] != 10 && s[FIRSTROLL]+pins < 10)
        if end {
            if frame == 9 { s[DONE] = 1 }
            else {
                s[FRAME] += 1
                s[FRAMEROLLS] = 0
                s[STANDING] = 10
            }
        } else {
            s[FRAMEROLLS] += 1
            if frame == 9 && s[STANDING] == 0 { s[STANDING] = 10 }
        }
    }
    func bowlingFrames() -> [BowlingFrame] {
        var result: [BowlingFrame] = []
        var cursor = 0
        var cumulative = 0
        for frame in 0..<10 {
            if cursor >= s[ROLLCOUNT] { break }
            let first = s[ROLLS+cursor]
            let count = frame < 9 ? (first == 10 ? 1 : min(2,s[ROLLCOUNT]-cursor)) : min(3,s[ROLLCOUNT]-cursor)
            var marks = ""
            var standing = 10
            var sum = 0
            var fresh = true
            for i in 0..<count {
                let pins = s[ROLLS+cursor+i]
                marks += pins == 10 && fresh ? "X" : (pins == standing ? "/" : (pins == 0 ? "-" : String(pins)))
                sum += pins
                standing -= pins
                fresh = frame == 9 && standing == 0
                if fresh { standing = 10 }
            }
            let score: Int?
            if frame == 9 { score = over() ? sum : nil }
            else if first == 10 && cursor+2 < s[ROLLCOUNT] { score = 10+s[ROLLS+cursor+1]+s[ROLLS+cursor+2] }
            else if first != 10 && count == 2 {
                score = sum < 10 ? sum : (cursor+2 < s[ROLLCOUNT] ? 10+s[ROLLS+cursor+2] : nil)
            } else { score = nil }
            var total: Int? = nil
            if let score {
                cumulative += score
                total = cumulative
            }
            let open = count >= 2 && first != 10 && first+s[ROLLS+cursor+1] < 10
            result.append(BowlingFrame(marks: marks,cumulative: total,open: open))
            cursor += count
        }
        return result
    }
    func event(_ command: String, _ value: String, _ tokens: [String]) throws {
        guard !over() else { throw Problem(message: "match over") }
        var code = 0
        var side = 0
        var position = -1
        if command == "ROLL" {
            code = Int(value)!
            guard code <= s[STANDING] else { throw Problem(message: "too many pins") }
        }
        if command == "THROW" {
            guard let index = app.dartIndex[value] else { throw Problem(message: "invalid dart") }
            code = index
        }
        if command == "SUB" || command == "TIMEOUT" {
            side = tokens[2] == "A" ? 0 : 1
            if command == "SUB" {
                let from = Int(tokens[3])!
                let to = Int(tokens[4])!
                guard let found = s[(LINEUP+side*6)..<(LINEUP+side*6+6)].firstIndex(of: from) else {
                    throw Problem(message: "player not on court")
                }
                position = found-LINEUP-side*6
                guard !(0..<6).contains(where: { s[LINEUP+side*6+$0] == to }) else { throw Problem(message: "player already on court") }
                guard s[SUBS+side] < 6 else { throw Problem(message: "no substitutions left") }
            } else if s[TIMEOUTS+side] == 2 { throw Problem(message: "no timeouts left") }
        }
        let before = s
        let count = finished.count
        switch command {
        case "POINT": point(value == "A" ? 0 : 1)
        case "ROLL": roll(code)
        case "THROW": dart(code)
        case "SUB":
            s[LINEUP+side*6+position] = Int(tokens[4])!
            s[SUBS+side] += 1
        case "TIMEOUT": s[TIMEOUTS+side] += 1
        default: preconditionFailure("Unreachable event")
        }
        var undo = [count]
        for i in s.indices where s[i] != before[i] {
            undo.append(i)
            undo.append(before[i])
        }
        history.append(undo)
    }
    func undo() throws {
        guard let undo = history.popLast() else { throw Problem(message: "nothing to undo") }
        for i in stride(from: 1,to: undo.count,by: 2) { s[undo[i]] = undo[i+1] }
        if finished.count > undo[0] { finished.removeLast(finished.count-undo[0]) }
    }
    func situation(_ x: Int) -> String {
        let old = s
        let count = finished.count
        let games = s[G]+s[G+1]
        let serve = server()
        let normal = tennis() && !tieBreak()
        point(x)
        let result: String
        if over() { result = "match point" }
        else if finished.count > count { result = tennis() || sport == "VOLLEYBALL" ? "set point" : "game point" }
        else if normal && s[G]+s[G+1] > games { result = x == serve ? "game point" : "break point" }
        else { result = "" }
        s = old
        if finished.count > count { finished.removeLast(finished.count-count) }
        return result
    }
    func finishedScore(_ f: Finished, _ first: Int) -> String {
        let pair = first == 0 ? "\(f.a)-\(f.b)" : "\(f.b)-\(f.a)"
        return f.type == 2 ? "["+pair+"]" : pair+(f.type == 1 ? "(\(f.loser))" : "")
    }
    func pair(_ offset: Int) -> String { "\(s[offset])-\(s[offset+1])" }
    func score() -> String {
        if sport == "BOWLING" {
            let frames = bowlingFrames().map { $0.marks+($0.cumulative.map { "(\($0))" } ?? "") }
            return id+": "+names[0]+(frames.isEmpty ? "" : " "+frames.joined(separator: " "))
        }
        let serve = over() ? -1 : server()
        var items: [String] = []
        if sport == "DARTS" {
            items += ["sets",pair(W),"legs",pair(L),"score",pair(R)]
            if !over() {
                if s[TC] > 0 {
                    items.append("turn")
                    for i in 0..<s[TC] { items.append(app.darts[s[TURN+i]].name) }
                }
                let check = app.checkout(s[R+s[SERVE]],3-s[TC])
                if !check.isEmpty {
                    items.append("checkout")
                    items += check
                }
            }
        } else {
            items += finished.map { finishedScore($0,0) }
            if !over() {
                if tennis() {
                    if superTie() { items.append("["+pair(P)+"]") }
                    else {
                        items.append(pair(G))
                        if tieBreak() { items.append(pair(P)) }
                        else if options["DEUCE"] == "AD" && s[P] >= 3 && s[P+1] >= 3 {
                            items.append(s[P] == s[P+1] ? "40-40" : (s[P] > s[P+1] ? "AD-40" : "40-AD"))
                        } else {
                            let points = ["0","15","30","40"]
                            items.append(points[s[P]]+"-"+points[s[P+1]])
                        }
                    }
                } else {
                    items.append(pair(P))
                    if sport == "VOLLEYBALL" { items += ["server",String(s[LINEUP+s[SERVE]*6])] }
                }
                for x in 0..<2 {
                    let situation = situation(x)
                    if !situation.isEmpty { items.append("("+situation+" "+names[x]+")") }
                }
            }
        }
        return id+": "+names[0]+(serve == 0 ? "*" : "")+" vs "+names[1]+(serve == 1 ? "*" : "")+" "+items.joined(separator: " ")
    }
    func stats() -> [String] {
        if sport == "BOWLING" {
            let frames = bowlingFrames()
            let strikes = frames.reduce(0) { $0+$1.marks.filter { $0 == "X" }.count }
            let spares = frames.reduce(0) { $0+$1.marks.filter { $0 == "/" }.count }
            let open = frames.filter { $0.open }.count
            let old = s
            while !over() { roll(s[STANDING]) }
            let maximum = bowlingFrames().last!.cumulative!
            s = old
            return ["\(id) \(names[0]): strikes \(strikes) spares \(spares) open \(open) max \(maximum)"]
        }
        return (0..<2).map { x in
            var line = id+" "+names[x]+": "
            if sport == "DARTS" {
                let average = s[DARTS+x] == 0 ? 0 : s[SCORED+x]*300/s[DARTS+x]
                let formatted = String(format: "%ld.%02ld",locale: Locale(identifier: "en_US_POSIX"),average/100,average%100)
                line += "darts \(s[DARTS+x]) average "+formatted+
                    " busts \(s[BUSTS+x]) high \(s[HIGH+x]) tons \(s[TONS+x]) 180s \(s[MAXIMUMS+x]) doubles \(s[HITS+x])/\(s[ATTEMPTS+x])"
            } else {
                line += "points \(s[POINTS+x]) serve \(s[SERVEWON+x])/\(s[SERVED+x]) run \(s[RUN+x])"
                if tennis() { line += " holds \(s[HOLDS+x])/\(s[SERVICE+x]) breaks \(s[BREAKS+x]) break points \(s[BPW+x])/\(s[BPO+x])" }
                if sport == "VOLLEYBALL" {
                    line += " subs \(s[SUBS+x]) timeouts \(s[TIMEOUTS+x]) lineup "+(0..<6).map { String(s[LINEUP+x*6+$0]) }.joined(separator: ",")
                }
            }
            return line
        }
    }
    func result() throws -> String {
        guard over() else { throw Problem(message: "match not finished") }
        if sport == "BOWLING" { return id+": "+names[0]+" \(bowlingFrames().last!.cumulative!)" }
        let winner = s[WINNER]
        return id+": "+names[winner]+" def. "+names[1-winner]+" "+finished.map { finishedScore($0,winner) }.joined(separator: " ")
    }
}

let app = Scoreboard()
let count = Int(readLine()!)!
for _ in 0..<count {
    do {
        for line in try app.execute(readLine()!) { print(line) }
    } catch let problem as Problem {
        print("ERROR "+problem.message)
    } catch {
        preconditionFailure("Unexpected error")
    }
}
