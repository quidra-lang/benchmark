import Foundation

struct CommandError: Error { let message: String }
func fail(_ message: String) throws -> Never {
    throw CommandError(message: message)
}
typealias Field = [Int]
typealias Values = [Int]
typealias Matrix = [Values]
typealias Relation = [[Bool]]
struct Ballot { let votes: Int
    let ranking: Field
}
struct Aggregate {
    let groups: [Ballot]
    let first: Values
    let last: Values
    let borda: Values
    let positions: Matrix
    let pairwise: Matrix
    let total: Int
    let blank: Int
}
struct TallyResult { let standings: Field
    let tie: Bool
    let rows: [String]
    var exhausted: [String] = []
}
struct Choice { let candidate: Int
    let tie: Bool
}
enum MethodKind: String {
    case plurality = "PLURALITY", runoff = "RUNOFF", irv = "IRV", coombs = "COOMBS", bucklin = "BUCKLIN"
    case borda = "BORDA", baldwin = "BALDWIN", nanson = "NANSON", black = "BLACK", veto = "VETO"
    case condorcet = "CONDORCET", copeland = "COPELAND", minimax = "MINIMAX", schulze = "SCHULZE"
    case rankedPairs = "RANKEDPAIRS", kemeny = "KEMENY", approval = "APPROVAL", stv = "STV"
}
enum MinimaxKind: String { case winning = "WINNING", margin = "MARGIN", opposition = "OPPOSITION" }
struct Method {
    let kind: MethodKind
    let parameter: Int
    let score: MinimaxKind
    init(_ kind: MethodKind, parameter: Int = 0, score: MinimaxKind = .winning) {
        self.kind = kind
        self.parameter = parameter
        self.score = score
    }
    var text: String {
        if kind == .minimax {
            return "\(kind.rawValue) \(score.rawValue)"
        }
        if kind == .approval || kind == .stv {
            return "\(kind.rawValue) \(parameter)"
        }
        return kind.rawValue
    }
}
func parseMethod(_ words: [String]) -> Method {
    let kind = MethodKind(rawValue: words[0])!
    if kind == .approval || kind == .stv {
        return Method(kind, parameter: Int(words[1])!)
    }
    if kind == .minimax {
        return Method(kind, score: MinimaxKind(rawValue: words[1])!)
    }
    return Method(kind)
}
let summaryMethods: [Method] = [
    MethodKind.plurality,
    .runoff,
    .irv,
    .coombs,
    .bucklin,
    .borda,
    .baldwin,
    .nanson,
    .black,
    .veto,
    .copeland,
    .minimax,
    .schulze,
    .rankedPairs,
    .kemeny
].map { Method($0) }
func sum(_ values: Values) -> Int {
    values.reduce(0, +)
}
func sumField(_ field: Field, _ values: Values) -> Int {
    field.reduce(0) { $0 + values[$1] }
}
func fieldMask(_ field: Field) -> Int {
    field.reduce(0) { $0 | (1 << $1) }
}
func money(_ value: Int) -> String {
    "\(value / 100).\(value % 100 < 10 ? "0" : "")\(value % 100)"
}
func tieText(_ tie: Bool) -> String {
    tie ? " (tie)" : ""
}

final class Election {
    let names: [String]
    let number: Int
    var withdrawn: Set<Int> = []
    var priority: Field = []
    var tieRank: Values
    var entries: [[Ballot]] = []
    var cache: [Int: Aggregate] = [:]

    init(_ names: [String], _ number: Int) {
        self.names = names
        self.number = number
        tieRank = Array(repeating: 0, count: names.count)
        setPriority(names.indices.sorted { names[$0] < names[$1] })
    }
    func zeros() -> Values {
        Array(repeating: 0, count: names.count)
    }
    func matrix() -> Matrix {
        Array(repeating: zeros(), count: names.count)
    }
    func relation() -> Relation {
        Array(repeating: Array(repeating: false, count: names.count), count: names.count)
    }
    func active() -> Field {
        names.indices.filter { !withdrawn.contains($0) }
    }
    func candidate(_ name: String) throws -> Int {
        guard let index = names.firstIndex(of: name) else {
            try fail("unknown candidate \(name)")
        }
        return index
    }
    func checkedNames(_ requested: [String]) throws -> Field {
        var found: Field = []
        for name in requested {
            let index = try candidate(name)
            if found.contains(index) {
                try fail("duplicate candidate \(name)")
            }
            found.append(index)
        }
        return found
    }
    func setPriority(_ order: Field) {
        priority = order
        for (index, candidate) in order.enumerated() {
            tieRank[candidate] = index
        }
    }
    func list(_ field: Field,
              _ separator: String = ", ") -> String
    {
        field.map { names[$0] }.joined(separator: separator)
    }
    func values(_ field: Field, _ values: Values, cents: Bool = false) -> String {
        field.map { "\(names[$0]) \(cents ? money(values[$0]) : String(values[$0]))" }.joined(separator: ", ")
    }
    func ordered(_ field: Field, _ values: Values, ascending: Bool = false) -> Field {
        field
            .sorted { a, b in
                values[a] == values[b] ? tieRank[a] < tieRank[b] : ascending ? values[a] < values[b] : values[a] >
                    values[b]
            }
    }
    func preferred(_ field: Field) -> Field {
        field.sorted { tieRank[$0] < tieRank[$1] }
    }
    func aggregate(_ field: Field) -> Aggregate {
        let mask = fieldMask(field)
        if let cached = cache[mask] {
            return cached
        }
        var combined: [Field: Int] = [:]
        for group in entries.joined() {
            let ranking = group.ranking.filter { mask & (1 << $0) != 0 }
            combined[ranking, default: 0] += group.votes
        }
        let groups = combined.map { Ballot(votes: $0.value, ranking: $0.key) }
        var first = zeros(), last = zeros(), borda = zeros(), pairwise = matrix()
        var positions = Array(repeating: Array(repeating: 0, count: field.count), count: names.count)
        var total = 0, blank = 0
        for group in groups {
            let ranking = group.ranking, votes = group.votes
            total += votes
            if ranking.isEmpty {
                blank += votes
            } else {
                first[ranking[0]] += votes
            }
            var ranks = Array(repeating: field.count, count: names.count)
            for (place, candidate) in ranking.enumerated() {
                ranks[candidate] = place
                positions[candidate][place] += votes
                borda[candidate] += votes * (field.count - place - 1)
            }
            for candidate in field {
                if ranking.count < field.count ? ranks[candidate] == field.count : candidate == ranking
                    .last!
                {
                    last[candidate] += votes
                }
                for other in field where ranks[candidate] < ranks[other] {
                    pairwise[candidate][other] += votes
                }
            }
        }
        let result = Aggregate(
            groups: groups,
            first: first,
            last: last,
            borda: borda,
            positions: positions,
            pairwise: pairwise,
            total: total,
            blank: blank
        )
        cache[mask] = result
        return result
    }
}
func eliminate(_ election: Election, _ field: Field, _ values: Values, _ history: [Values]) -> Choice {
    let minimum = field.map { values[$0] }.min()!
    var choices = field.filter { values[$0] == minimum }
    let tie = choices.count > 1
    for round in history.reversed() {
        if choices.count == 1 {
            break
        }
        let oldMinimum = choices.map { round[$0] }.min()!
        choices = choices.filter { round[$0] == oldMinimum }
    }
    return Choice(candidate: election.preferred(choices).last!, tie: tie)
}
func finish(_ election: Election, _ standings: Field, _ tie: Bool, _ rows: [String]) -> TallyResult {
    TallyResult(standings: standings, tie: tie, rows: rows + ["winner: \(election.names[standings[0]])\(tieText(tie))"])
}
func scored(_ election: Election, _ field: Field, _ values: Values, _ label: String,
            ascending: Bool = false) -> TallyResult
{
    let standings = election.ordered(field, values, ascending: ascending)
    return finish(
        election,
        standings,
        values[standings[0]] == values[standings[1]],
        ["\(label): \(election.values(field, values))"]
    )
}
func pairLines(_ election: Election, _ field: Field, _ matrix: Matrix) -> [String] {
    var rows: [String] = []
    for i in field.indices {
        for j in (i + 1)..<field.count {
            let first = field[i], second = field[j], a = matrix[first][second], b = matrix[second][first]
            let result = a > b ? election.names[first] : b > a ? election.names[second] : "tie"
            rows.append("\(election.names[first]) vs \(election.names[second]): \(a)-\(b) (\(result))")
        }
    }
    return rows
}
func runoff(_ election: Election, _ field: Field) -> TallyResult {
    let first = election.aggregate(field).first
    var order = election.ordered(field, first), rows = ["round 1: \(election.values(field, first))"]
    if 2 * first[order[0]] > sumField(field, first) {
        return finish(election, order, false, rows)
    }
    let finalists = order.prefix(2).sorted(), second = election.aggregate(finalists).first
    let advance = order.count >= 3 && first[order[1]] == first[order[2]]
    rows.append("finalists: \(election.list(finalists))\(tieText(advance))")
    rows.append("round 2: \(election.values(finalists, second))")
    let tie = second[order[0]] == second[order[1]]
    if second[order[1]] > second[order[0]] {
        order.swapAt(0, 1)
    }
    return finish(election, order, tie, rows)
}
func eliminationRounds(_ election: Election, _ field: Field, coombs: Bool) -> TallyResult {
    var remaining = field, removed: Field = [], history: [Values] = [], rows: [String] = [], exhausted: [String] = []
    var round = 1
    while true {
        let aggregate = election.aggregate(remaining), values = aggregate.first
        let ordered = election.ordered(remaining, values), active = sumField(remaining, values)
        var row = "round \(round): \(election.values(remaining, values))"
        exhausted.append("round \(round): active \(active), exhausted \(aggregate.total - active)")
        if remaining.count == 1 || 2 * values[ordered[0]] > active {
            var result = finish(election, ordered + Array(removed.reversed()), false, rows + [row])
            result.exhausted = exhausted
            return result
        }
        let chosen: Choice
        if coombs {
            let last = aggregate.last, maximum = remaining.map { last[$0] }.max()!
            let tied = remaining.filter { last[$0] == maximum }
            chosen = Choice(candidate: election.ordered(tied, values).last!, tie: tied.count > 1)
            row += "; last \(election.values(remaining, last))"
        } else {
            chosen = eliminate(election, remaining, values, history)
        }
        rows.append("\(row); eliminated \(election.names[chosen.candidate])\(tieText(chosen.tie))")
        history.append(values)
        removed.append(chosen.candidate)
        remaining.removeAll { $0 == chosen.candidate }
        round += 1
    }
}
func bucklin(_ election: Election, _ field: Field) -> TallyResult {
    let aggregate = election.aggregate(field), majority = (aggregate.total - aggregate.blank) / 2 + 1
    var history: [Values] = [], rows = ["majority: \(majority)"]
    for depth in 1...field.count {
        let values = aggregate.positions.map { sum(Array($0.prefix(depth))) }
        history.append(values)
        rows.append("round \(depth): \(election.values(field, values))")
        if field.contains(where: { values[$0] >= majority }) {
            break
        }
    }
    let standings = field.sorted { a, b in
        for round in history.reversed() where round[a] != round[b] {
            return round[a] > round[b]
        }
        return election.tieRank[a] < election.tieRank[b]
    }
    let final = history.last!
    return finish(election, standings, final[standings[0]] == final[standings[1]], rows)
}
func bordaRounds(_ election: Election, _ field: Field, nanson: Bool) -> TallyResult {
    var remaining = field, tail: Field = [], history: [Values] = [], rows: [String] = []
    while remaining.count >= 2 {
        let values = election.aggregate(remaining).borda
        var row = "round \(rows.count + 1): \(election.values(remaining, values))"
        let removed: Field
        if nanson {
            let total = sumField(remaining, values)
            let below = remaining.filter { values[$0] * remaining.count < total }
            if below.isEmpty {
                rows.append(row)
                break
            }
            row += "; eliminated \(election.list(below))"
            removed = election.ordered(below, values)
        } else {
            let chosen = eliminate(election, remaining, values, history)
            removed = [chosen.candidate]
            row += "; eliminated \(election.names[chosen.candidate])\(tieText(chosen.tie))"
        }
        tail = removed + tail
        remaining.removeAll { removed.contains($0) }
        history.append(values)
        rows.append(row)
    }
    return finish(election, election.preferred(remaining) + tail, remaining.count > 1, rows)
}
func condorcetWinner(_ field: Field, _ pairwise: Matrix, loser: Bool = false) -> Int? {
    field.first { candidate in
        field
            .allSatisfy { other in
                candidate == other ||
                    (loser ? pairwise[candidate][other] < pairwise[other][candidate] : pairwise[candidate][other] >
                        pairwise[other][candidate])
            }
    }
}
func closure(_ field: Field, _ edges: Relation) -> Relation {
    var reach = edges
    for middle in field {
        for first in field {
            for second in field where reach[first][middle] && reach[middle][second] {
                reach[first][second] = true
            }
        }
    }
    return reach
}
func condorcet(_ election: Election, _ field: Field, _ pairwise: Matrix) -> TallyResult {
    let winner = condorcetWinner(field, pairwise), loser = condorcetWinner(field, pairwise, loser: true)
    var weak = election.relation(), strong = election.relation()
    for first in field {
        for second in field {
            weak[first][second] = first == second || pairwise[first][second] >= pairwise[second][first]
            strong[first][second] = first != second && pairwise[first][second] > pairwise[second][first]
        }
    }
    weak = closure(field, weak)
    strong = closure(field, strong)
    let smith = field.filter { candidate in field.allSatisfy { weak[candidate][$0] } }
    let schwartz = field.filter { candidate in field.allSatisfy { !strong[$0][candidate] || strong[candidate][$0] } }
    return TallyResult(
        standings: [],
        tie: false,
        rows: [
            "winner: \(winner.map { election.names[$0] } ?? "NONE")",
            "loser: \(loser.map { election.names[$0] } ?? "NONE")",
            "smith: \(election.list(smith))",
            "schwartz: \(election.list(schwartz))"
        ]
    )
}
func topological(_ election: Election, _ field: Field, _ beats: Relation) -> (Field, Bool) {
    var remaining = field, standings: Field = [], tie = false
    while !remaining.isEmpty {
        let eligible = remaining
            .filter { candidate in remaining.allSatisfy { candidate == $0 || !beats[$0][candidate] } }
        if standings.isEmpty {
            tie = eligible.count > 1
        }
        let candidate = election.preferred(eligible)[0]
        standings.append(candidate)
        remaining.removeAll { $0 == candidate }
    }
    return (standings, tie)
}
func schulze(_ election: Election, _ field: Field, _ pairwise: Matrix) -> TallyResult {
    var strengths = election.matrix()
    for first in field {
        for second in field
            where first != second && pairwise[first][second] >
            pairwise[second][first]
        {
            strengths[first][second] = pairwise[first][second]
        }
    }
    for middle in field {
        for first in field where first != middle {
            for second in field where second != middle && second != first {
                strengths[first][second] = max(
                    strengths[first][second],
                    min(strengths[first][middle], strengths[middle][second])
                )
            }
        }
    }
    var beats = election.relation()
    for first in field {
        for second in field {
            beats[first][second] = strengths[first][second] > strengths[second][first]
        }
    }
    let (standings, tie) = topological(election, field, beats)
    return finish(
        election,
        standings,
        tie,
        pairLines(election, field, strengths) + ["ranking: \(election.list(standings, " > "))"]
    )
}
func rankedPairs(_ election: Election, _ field: Field, _ pairwise: Matrix) -> TallyResult {
    var pairs: [(Int, Int)] = [], edges = election.relation(), rows: [String] = []
    for first in field {
        for second in field where pairwise[first][second] > pairwise[second][first] {
            pairs.append((
                first,
                second
            ))
        }
    }
    pairs.sort { first, second in
        let (a, b) = first, (c, d) = second
        if pairwise[a][b] != pairwise[c][d] {
            return pairwise[a][b] > pairwise[c][d]
        }
        if pairwise[b][a] != pairwise[d][c] {
            return pairwise[b][a] < pairwise[d][c]
        }
        if a != c {
            return election.tieRank[a] < election.tieRank[c]
        }
        return election.tieRank[b] < election.tieRank[d]
    }
    for (first, second) in pairs {
        let lock = !closure(field, edges)[second][first]
        if lock {
            edges[first][second] = true
        }
        rows
            .append(
                "\(lock ? "lock" : "skip") \(election.names[first])>\(election.names[second]) \(pairwise[first][second])-\(pairwise[second][first])"
            )
    }
    let (standings, tie) = topological(election, field, edges)
    return finish(election, standings, tie, rows)
}
func kemeny(_ election: Election, _ field: Field, _ pairwise: Matrix) -> TallyResult {
    struct Optimum { var score = 0
        var count = 0
        var first: Field = []
    }
    let mask = fieldMask(field)
    var optimum = Array(repeating: Optimum(), count: 1 << election.names.count)
    optimum[0].count = 1
    for subset in 1...mask where (subset & mask) == subset {
        var current = Optimum(score: -1, count: 0, first: [])
        for candidate in field where subset & (1 << candidate) != 0 {
            let rest = subset ^ (1 << candidate)
            var score = optimum[rest].score
            for other in field where rest & (1 << other) != 0 {
                score += pairwise[candidate][other]
            }
            if score > current.score {
                current.score = score
                current.count = 0
                current.first = []
            }
            if score == current.score {
                current.count += optimum[rest].count
                current.first.append(candidate)
            }
        }
        optimum[subset] = current
    }
    var remaining = mask, standings: Field = []
    while remaining != 0 {
        let candidate = election.preferred(optimum[remaining].first)[0]
        standings.append(candidate)
        remaining ^= 1 << candidate
    }
    let best = optimum[mask]
    return finish(
        election,
        standings,
        best.first.count > 1,
        ["score: \(best.score)", "optimal: \(best.count)", "ranking: \(election.list(standings, " > "))"]
    )
}
func stv(_ election: Election, _ field: Field, _ seats: Int) throws -> TallyResult {
    if seats >= field.count {
        try fail("too many seats")
    }
    let aggregate = election.aggregate(field), groups = aggregate.groups.filter { !$0.ranking.isEmpty }
    let quota = 100 * (aggregate.total - aggregate.blank) / (seats + 1) + 1
    var perVote = Array(repeating: 100, count: groups.count), continuing = field, elected: Field = []
    var history: [Values] = [], rows = ["quota: \(money(quota))"], round = 1
    while true {
        var values = election.zeros(), current = Array(repeating: -1, count: groups.count), exhausted = 0
        for (index, group) in groups.enumerated() {
            let value = group.votes * perVote[index]
            if let candidate = group.ranking.first(where: { continuing.contains($0) }) {
                current[index] = candidate
                values[candidate] += value
            } else {
                exhausted += value
            }
        }
        var row = "round \(round): \(election.values(continuing, values, cents: true)); exhausted \(money(exhausted))"
        let ordered = election.ordered(continuing, values)
        if continuing.count == seats - elected.count {
            elected += ordered
            rows.append("\(row); elected \(election.list(ordered))")
            break
        }
        let removed: Int
        if values[ordered[0]] >= quota {
            removed = ordered[0]
            elected.append(removed)
            let total = values[removed], surplus = total - quota
            for index in current.indices
                where current[index] == removed
            {
                perVote[index] = perVote[index] * surplus / total
            }
            row += "; elected \(election.names[removed]) (surplus \(money(surplus)))"
        } else {
            let chosen = eliminate(election, continuing, values, history)
            removed = chosen.candidate
            row += "; excluded \(election.names[removed])\(tieText(chosen.tie))"
        }
        rows.append(row)
        if elected.count == seats {
            break
        }
        history.append(values)
        continuing.removeAll { $0 == removed }
        round += 1
    }
    return TallyResult(standings: [], tie: false, rows: rows + ["elected: \(election.list(elected))"])
}
func tally(_ election: Election, _ method: Method, _ field: Field) throws -> TallyResult {
    let aggregate = election.aggregate(field), pairwise = aggregate.pairwise
    switch method.kind {
    case .plurality:
        return scored(election, field, aggregate.first, "votes")
    case .runoff:
        return runoff(election, field)
    case .irv:
        return eliminationRounds(election, field, coombs: false)
    case .coombs:
        return eliminationRounds(election, field, coombs: true)
    case .bucklin:
        return bucklin(election, field)
    case .borda:
        return scored(election, field, aggregate.borda, "scores")
    case .baldwin:
        return bordaRounds(election, field, nanson: false)
    case .nanson:
        return bordaRounds(election, field, nanson: true)
    case .black:
        let winner = condorcetWinner(field, pairwise)
        var standings = election.ordered(field, aggregate.borda)
        let tie = winner == nil && aggregate.borda[standings[0]] == aggregate.borda[standings[1]]
        if let winner {
            standings.removeAll { $0 == winner }
            standings.insert(winner, at: 0)
        }
        return finish(
            election,
            standings,
            tie,
            [
                "condorcet: \(winner.map { election.names[$0] } ?? "NONE")",
                "scores: \(election.values(field, aggregate.borda))"
            ]
        )
    case .veto:
        return scored(election, field, aggregate.last, "vetoes", ascending: true)
    case .condorcet:
        return condorcet(election, field, pairwise)
    case .copeland:
        var scores = election.zeros(), parts: [String] = []
        for candidate in field {
            var wins = 0, draws = 0, losses = 0
            for other in field where other != candidate {
                if pairwise[candidate][other] > pairwise[other][candidate] {
                    wins += 1
                } else if pairwise[candidate][other] == pairwise[other][candidate] {
                    draws += 1
                } else {
                    losses += 1
                }
            }
            let score = 2 * wins + draws
            scores[candidate] = score
            parts
                .append(
                    "\(election.names[candidate]) \(score / 2).\(score % 2 == 0 ? "0" : "5") (\(wins)-\(draws)-\(losses))"
                )
        }
        let standings = election.ordered(field, scores)
        return finish(
            election,
            standings,
            scores[standings[0]] == scores[standings[1]],
            ["scores: \(parts.joined(separator: ", "))"]
        )
    case .minimax:
        var scores = election.zeros()
        for candidate in field {
            for other in field where candidate != other {
                let opposition = pairwise[other][candidate], support = pairwise[candidate][other]
                if method.score == .opposition {
                    scores[candidate] = max(scores[candidate], opposition)
                } else if opposition > support {
                    scores[candidate] = max(
                        scores[candidate],
                        method.score == .margin ? opposition - support : opposition
                    )
                }
            }
        }
        return scored(election, field, scores, "scores", ascending: true)
    case .schulze:
        return schulze(election, field, pairwise)
    case .rankedPairs:
        return rankedPairs(election, field, pairwise)
    case .kemeny:
        return kemeny(election, field, pairwise)
    case .approval:
        let approvals = aggregate.positions.map { sum(Array($0.prefix(method.parameter))) }
        return scored(election, field, approvals, "approvals")
    case .stv:
        return try stv(election, field, method.parameter)
    }
}
func reports(_ election: Election, _ command: String, _ args: [String], _ field: Field) throws -> [String] {
    let aggregate = election.aggregate(field)
    switch command {
    case "STATUS":
        let withdrawn = election.names.indices.filter { election.withdrawn.contains($0) }
        return [
            "election \(election.number)",
            "active: \(election.list(field))",
            "withdrawn: \(withdrawn.isEmpty ? "none" : election.list(withdrawn))",
            "tiebreak: \(election.list(election.priority))",
            "ballots: \(aggregate.total) in \(election.entries.count) entries"
        ]
    case "BALLOTS":
        let groups = aggregate.groups.map { group in (
            votes: group.votes,
            notation: group.ranking.isEmpty ? "-" : election.list(group.ranking, ">")
        ) }.sorted { a, b in a.votes == b.votes ? a.notation < b.notation : a.votes > b.votes }
        return ["total \(aggregate.total), blank \(aggregate.blank), distinct \(groups.count)"] + groups
            .map { "\($0.votes) \($0.notation)" }
    case "PROFILE":
        return field.map { candidate in
            let positions = aggregate.positions[candidate]
            return "\(election.names[candidate]): \(positions.map(String.init).joined(separator: " ")) unranked \(aggregate.total - sum(positions))"
        }
    case "PAIRWISE":
        return pairLines(election, field, aggregate.pairwise)
    case "EXHAUSTED":
        return eliminationRounds(election, field, coombs: false).exhausted
    case "RANKING", "SPOILERS":
        let method = parseMethod(args)
        if method.kind == .condorcet || method.kind == .stv {
            try fail("not rankable")
        }
        if command == "SPOILERS" && field.count < 3 {
            try fail("too few candidates")
        }
        let standings = try tally(election, method, field).standings
        if command == "RANKING" {
            return [election.list(standings, " > ")]
        }
        let winner = standings[0]
        var rows = ["winner: \(election.names[winner])"]
        for excluded in field where excluded != winner {
            let other = try tally(election, method, field.filter { $0 != excluded }).standings[0]
            rows
                .append(
                    "without \(election.names[excluded]): \(election.names[other])\(other != winner ? " (changed)" : "")"
                )
        }
        return rows
    case "SUMMARY":
        var wins = election.zeros(), rows: [String] = []
        for method in summaryMethods {
            let winner = try tally(election, method, field).standings[0]
            wins[winner] += 1
            rows.append("\(method.text): \(election.names[winner])")
        }
        return rows + ["wins: \(election.values(field, wins))"]
    case "COMPARE":
        var candidates: Field = []
        for name in args {
            let candidate = try election.candidate(name)
            if election.withdrawn.contains(candidate) {
                try fail("withdrawn candidate \(name)")
            }
            candidates.append(candidate)
        }
        let first = candidates[0], second = candidates[1]
        if first == second {
            try fail("same candidate")
        }
        let a = aggregate.pairwise[first][second], b = aggregate.pairwise[second][first]
        var ahead: [[String]] = [[], []]
        for method in summaryMethods {
            let standings = try tally(election, method, field).standings
            let side = standings.firstIndex(of: first)! < standings.firstIndex(of: second)! ? 0 : 1
            ahead[side].append(method.text)
        }
        let rows = ["\(args[0]) \(a), \(args[1]) \(b), neither \(aggregate.total - a - b)"]
        return rows + args.indices
            .map { "\(args[$0]) ahead: \(ahead[$0].isEmpty ? "none" : ahead[$0].joined(separator: ", "))" }
    default:
        return try tally(election, parseMethod([command] + args), field).rows
    }
}
final class VoteCounter {
    private var election: Election?
    private var number = 0

    func execute(_ line: String) throws -> [String] {
        let words = line.split(separator: " ").map(String.init), command = words[0], args = Array(words.dropFirst())
        if command == "CANDIDATES" {
            if args.count < 2 {
                try fail("too few candidates")
            }
            var seen: Set<String> = []
            for name in args {
                if !seen.insert(name).inserted {
                    try fail("duplicate candidate \(name)")
                }
            }
            number += 1
            election = Election(args, number)
            return ["election \(number): \(args.count) candidates"]
        }
        guard let election else {
            try fail("no election")
        }
        let field = election.active()
        switch command {
        case "BALLOT":
            let ranking: Field
            if args[1] == "-" {
                ranking = []
            } else {
                ranking = try election.checkedNames(args[1].split(separator: ">").map(String.init))
            }
            election.entries.append([Ballot(votes: Int(args[0])!, ranking: ranking)])
            election.cache.removeAll()
            return []
        case "RANDOM":
            var state = Int64(args[1])!
            func draw() -> Int64 {
                state = 48271 * state % 2147483647
                return state
            }
            var groups: [Ballot] = []
            for _ in 0..<Int(args[0])! {
                var ranking = field
                for index in stride(from: ranking.count - 1, through: 1, by: -1) {
                    ranking.swapAt(index, Int(draw() % Int64(index + 1)))
                }
                let length = Int(draw() % Int64(ranking.count)) + 1
                groups.append(Ballot(votes: 1, ranking: Array(ranking.prefix(length))))
            }
            election.entries.append(groups)
            election.cache.removeAll()
            return []
        case "UNDO":
            if election.entries.isEmpty {
                try fail("nothing to undo")
            }
            election.entries.removeLast()
            election.cache.removeAll()
            return []
        case "WITHDRAW", "RESTORE":
            let candidate = try election.candidate(args[0])
            if command == "WITHDRAW" {
                if election.withdrawn.contains(candidate) {
                    try fail("already withdrawn \(args[0])")
                }
                if field.count <= 2 {
                    try fail("too few candidates")
                }
                election.withdrawn.insert(candidate)
            } else {
                if !election.withdrawn.contains(candidate) {
                    try fail("not withdrawn \(args[0])")
                }
                election.withdrawn.remove(candidate)
            }
            return []
        case "TIEBREAK":
            let order = try election.checkedNames(args)
            if order.count != election.names.count {
                try fail("incomplete tiebreak")
            }
            election.setPriority(order)
            return []
        default:
            if command != "STATUS" && election.entries.isEmpty {
                try fail("no ballots")
            }
            let rows = try reports(election, command, args, field)
            return ["[\(line)]"] + rows
        }
    }
}

let count = Int(readLine()!)!
let counter = VoteCounter()
var output: [String] = []
for _ in 0..<count {
    do { output += try counter.execute(readLine()!) }
    catch let error as CommandError { output.append("ERROR \(error.message)") }
    catch { fatalError("Unexpected error: \(error)") }
}
print(output.joined(separator: "\n"))
