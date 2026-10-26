struct CommandError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) {
        description = message
    }
}

func gcd(_ left: Int64, _ right: Int64) -> Int64 {
    var a = abs(left), b = abs(right)
    while b != 0 {
        (a, b) = (b, a % b)
    }
    return a
}

struct Fraction: Comparable, CustomStringConvertible, ExpressibleByIntegerLiteral, Sendable {
    let numerator: Int64
    let denominator: Int64
    static let zero = Fraction(0)
    static let one = Fraction(1)

    init(_ numerator: Int64, _ denominator: Int64 = 1) {
        let n = denominator < 0 ? -numerator : numerator
        let d = abs(denominator)
        let divisor = gcd(n, d)
        self.numerator = n / divisor
        self.denominator = d / divisor
    }

    init(integerLiteral value: Int64) {
        self.init(value)
    }

    static func + (a: Fraction, b: Fraction) -> Fraction {
        Fraction(a.numerator * b.denominator + b.numerator * a.denominator,
                 a.denominator * b.denominator)
    }
    static func - (a: Fraction, b: Fraction) -> Fraction {
        Fraction(a.numerator * b.denominator - b.numerator * a.denominator,
                 a.denominator * b.denominator)
    }
    static func * (a: Fraction, b: Fraction) -> Fraction {
        Fraction(a.numerator * b.numerator, a.denominator * b.denominator)
    }
    static func / (a: Fraction, b: Fraction) -> Fraction {
        Fraction(a.numerator * b.denominator, a.denominator * b.numerator)
    }
    static func < (a: Fraction, b: Fraction) -> Bool {
        a.numerator * b.denominator < b.numerator * a.denominator
    }

    var absolute: Fraction {
        Fraction(abs(numerator), denominator)
    }
    var description: String {
        "\(numerator)/\(denominator)"
    }
    var value: String {
        let digits = String(numerator % denominator * 1_000_000 / denominator)
        return "\(self)(\(numerator / denominator).\(String(repeating: "0", count: 6 - digits.count))\(digits))"
    }
}

typealias Row = [Fraction]
typealias Matrix = [Row]

func split(_ text: String, by separator: Character = " ") -> [String] {
    text.split(separator: separator).map(String.init)
}

func yes(_ value: Bool) -> String {
    value ? "yes" : "no"
}
func delta(_ i: Int, _ j: Int) -> Fraction {
    i == j ? .one : .zero
}

func probability(_ text: String) throws -> Fraction {
    let parts = split(text, by: "/")
    let numerator = Int64(parts[0])!
    let denominator = parts.count == 2 ? Int64(parts[1])! : 1
    if denominator == 0 || numerator > denominator {
        throw CommandError("BAD PROBABILITY")
    }
    return Fraction(numerator, denominator)
}

func total(_ values: Row) -> Fraction {
    var result: Fraction = 0
    for value in values {
        result = result + value
    }
    return result
}

func matrix(_ rows: Int, _ columns: Int) -> Matrix {
    Matrix(repeating: Row(repeating: .zero, count: columns), count: rows)
}

func identity(_ size: Int) -> Matrix {
    (0..<size).map { i in (0..<size).map { j in delta(i, j) } }
}

func multiply(_ left: Matrix, _ right: Matrix) -> Matrix {
    var result = matrix(left.count, right[0].count)
    for i in left.indices {
        for j in right[0].indices {
            for k in right.indices {
                result[i][j] = result[i][j] + left[i][k] * right[k][j]
            }
        }
    }
    return result
}

func solve(_ augmented: Matrix) -> Matrix {
    if augmented.isEmpty {
        return []
    }
    var rows = augmented
    let size = rows.count, width = rows[0].count
    for column in 0..<size {
        var pivotRow = column
        while rows[pivotRow][column].numerator == 0 {
            pivotRow += 1
        }
        rows.swapAt(column, pivotRow)
        let pivot = rows[column][column]
        for j in 0..<width {
            rows[column][j] = rows[column][j] / pivot
        }
        for i in 0..<size where i != column {
            let factor = rows[i][column]
            if factor.numerator == 0 {
                continue
            }
            for j in 0..<width {
                rows[i][j] = rows[i][j] - factor * rows[column][j]
            }
        }
    }
    return rows.map { Array($0[size...]) }
}

struct Chain {
    let names: [String]
    var p: Matrix
    var size: Int {
        names.count
    }
    var indices: Range<Int> {
        names.indices
    }

    init(_ names: [String]) {
        self.names = names
        p = matrix(names.count, names.count)
    }

    func state(_ name: String) throws -> Int {
        guard let index = names.firstIndex(of: name) else {
            throw CommandError("UNKNOWN STATE \(name)")
        }
        return index
    }

    func stateSet(_ requested: [String]) throws -> [Int] {
        var result = Set<Int>()
        for name in requested {
            let index = try state(name)
            if !result.insert(index).inserted {
                throw CommandError("DUPLICATE STATE \(name)")
            }
        }
        return result.sorted()
    }

    func labels(_ states: [Int], separator: String = " ") -> String {
        states.map { names[$0] }.joined(separator: separator)
    }

    func blockSum(_ state: Int, _ block: [Int]) -> Fraction {
        var result: Fraction = 0
        for target in block {
            result = result + p[state][target]
        }
        return result
    }
}

struct Component {
    let states: [Int]
    let closed: Bool
    let levels: [Int]
    let period: Int
}

struct Decomposition {
    let reach: [[Bool]]
    let classes: [Component]
    let classOf: [Int]

    init(_ chain: Chain) {
        let n = chain.size
        var reach = chain.indices.map { i in
            chain.indices.map { j in i == j || chain.p[i][j].numerator > 0 }
        }
        for k in chain.indices {
            for i in chain.indices {
                for j in chain.indices {
                    reach[i][j] = reach[i][j] || reach[i][k] && reach[k][j]
                }
            }
        }
        var classes: [Component] = []
        var classOf = [Int](repeating: -1, count: n)
        for root in chain.indices where classOf[root] == -1 {
            let states = chain.indices.filter { reach[root][$0] && reach[$0][root] }
            let inside = Set(states)
            for state in states {
                classOf[state] = classes.count
            }
            let closed = states.allSatisfy { i in
                chain.indices.allSatisfy { j in inside.contains(j) || chain.p[i][j].numerator == 0 }
            }
            var levels = [Int](repeating: -1, count: n)
            levels[root] = 0
            var queue = [root], head = 0
            while head < queue.count {
                let u = queue[head]
                head += 1
                for v in states where levels[v] < 0 && chain.p[u][v].numerator > 0 {
                    levels[v] = levels[u] + 1
                    queue.append(v)
                }
            }
            var period = 0
            for u in states {
                for v in states where chain.p[u][v].numerator > 0 {
                    period = Int(gcd(Int64(period), Int64(levels[u] + 1 - levels[v])))
                }
            }
            classes.append(Component(states: states, closed: closed, levels: levels, period: period))
        }
        self.reach = reach
        self.classes = classes
        self.classOf = classOf
    }
}

func stationary(_ chain: Chain, _ states: [Int]) -> Row {
    let size = states.count
    var rows = matrix(size, size + 1)
    for r in 0..<(size - 1) {
        for k in 0..<size {
            rows[r][k] = chain.p[states[k]][states[r]] - delta(k, r)
        }
    }
    rows[size - 1] = Row(repeating: .one, count: size + 1)
    return solve(rows).map { $0[0] }
}

func irreducible(_ chain: Chain, _ graph: Decomposition) throws -> Row {
    if graph.classes.count != 1 {
        throw CommandError("NOT IRREDUCIBLE")
    }
    return stationary(chain, graph.classes[0].states)
}

struct Hitting {
    let probabilities: Row
    let times: [Fraction?]
}

func hitting(_ chain: Chain, _ targets: [Int], _ reach: [[Bool]], withTimes: Bool = true) -> Hitting {
    var chances = Row(repeating: .zero, count: chain.size)
    var times = [Fraction?](repeating: nil, count: chain.size)
    let inside = Set(targets)
    for state in targets {
        chances[state] = .one
        times[state] = Fraction.zero
    }
    let unknown = chain.indices.filter { i in !inside.contains(i) && targets.contains { reach[i][$0] } }
    if !unknown.isEmpty {
        let size = unknown.count
        var rows = matrix(size, size + 1)
        for r in 0..<size {
            for k in 0..<size {
                rows[r][k] = delta(r, k) - chain.p[unknown[r]][unknown[k]]
            }
            rows[r][size] = chain.blockSum(unknown[r], targets)
        }
        let solution = solve(rows)
        for r in 0..<size {
            chances[unknown[r]] = solution[r][0]
        }
    }
    if withTimes {
        let certain = unknown.filter { chances[$0] == .one }
        if !certain.isEmpty {
            let size = certain.count
            var rows = matrix(size, size + 1)
            for r in 0..<size {
                for k in 0..<size {
                    rows[r][k] = delta(r, k) - chain.p[certain[r]][certain[k]]
                }
                rows[r][size] = .one
            }
            let solution = solve(rows)
            for r in 0..<size {
                times[certain[r]] = solution[r][0]
            }
        }
    }
    return Hitting(probabilities: chances, times: times)
}

struct Absorption {
    let transient: [Int]
    let absorbing: [Int]
    let fundamental: Matrix
    let means: Row
    let variances: Row
    let probabilities: Matrix

    init(_ chain: Chain) {
        let transient = chain.indices.filter { chain.p[$0][$0] != .one }
        let absorbing = chain.indices.filter { chain.p[$0][$0] == .one }
        let t = transient.count
        var rows = matrix(t, 2 * t)
        for i in 0..<t {
            for j in 0..<t {
                rows[i][j] = delta(i, j) - chain.p[transient[i]][transient[j]]
            }
            rows[i][t + i] = .one
        }
        let fundamental = solve(rows)
        let means = fundamental.map(total)
        var variances = Row(repeating: .zero, count: t)
        var probabilities = matrix(t, absorbing.count)
        for i in 0..<t {
            var secondMoment: Fraction = 0
            for j in 0..<t {
                secondMoment = secondMoment + (2 * fundamental[i][j] - delta(i, j)) * means[j]
            }
            variances[i] = secondMoment - means[i] * means[i]
            for j in absorbing.indices {
                for l in 0..<t {
                    probabilities[i][j] = probabilities[i][j] + fundamental[i][l] * chain.p[transient[l]][absorbing[j]]
                }
            }
        }
        self.transient = transient
        self.absorbing = absorbing
        self.fundamental = fundamental
        self.means = means
        self.variances = variances
        self.probabilities = probabilities
    }
}

final class Analyzer {
    var chains: [String: Chain] = [:]
    var output: [String] = []

    func emit(_ line: String) {
        output.append(line)
    }

    func display(_ chain: Chain, values: Matrix? = nil, prefix: String = "ROW") {
        let rows = values ?? chain.p
        emit("STATES \(chain.names.joined(separator: " "))")
        for i in chain.indices {
            emit("\(prefix) \(chain.names[i]) \(rows[i].map(\.description).joined(separator: " "))")
        }
    }

    func create(_ words: [String]) throws {
        let names = Array(words.dropFirst(2))
        if names.count > 10 {
            throw CommandError("TOO MANY STATES")
        }
        var seen = Set<String>()
        for name in names {
            if !seen.insert(name).inserted {
                throw CommandError("DUPLICATE STATE \(name)")
            }
        }
        chains[words[1]] = Chain(names)
        emit("CHAIN \(words[1]) states=\(names.count)")
    }

    func build(_ words: [String]) throws {
        let name = words[1], order = Int(words[2])!
        if order != 1 && order != 2 {
            throw CommandError("BAD ORDER")
        }
        let tokens = Array(words.dropFirst(3))
        if tokens.count <= order {
            throw CommandError("TOO FEW TOKENS")
        }
        let observations = order == 1 ? tokens : (0..<(tokens.count - 1)).map { "\(tokens[$0]).\(tokens[$0 + 1])" }
        var names: [String] = []
        var positions: [String: Int] = [:]
        var sequence: [Int] = []
        for observation in observations {
            if positions[observation] == nil {
                positions[observation] = names.count
                names.append(observation)
            }
            sequence.append(positions[observation]!)
        }
        if names.count > 10 {
            throw CommandError("TOO MANY STATES")
        }
        var chain = Chain(names)
        var counts = [[Int]](repeating: [Int](repeating: 0, count: chain.size), count: chain.size)
        var totals = [Int](repeating: 0, count: chain.size)
        for i in 1..<sequence.count {
            counts[sequence[i - 1]][sequence[i]] += 1
            totals[sequence[i - 1]] += 1
        }
        for i in chain.indices {
            if totals[i] == 0 {
                chain.p[i][i] = .one
            } else {
                for j in chain.indices {
                    chain.p[i][j] = Fraction(Int64(counts[i][j]), Int64(totals[i]))
                }
            }
        }
        chains[name] = chain
        emit("BUILD \(name) order=\(order) states=\(chain.size) transitions=\(sequence.count - 1)")
        for i in chain.indices {
            let detail = totals[i] == 0 ? "absorbing" : chain.indices.filter { counts[i][$0] > 0 }
                .map { "\(names[$0]):\(counts[i][$0])" }.joined(separator: " ")
            emit("FROM \(names[i]) total=\(totals[i]) \(detail)")
        }
    }

    func gambler(_ words: [String]) throws {
        let name = words[1], goal = Int(words[2])!, start = Int(words[3])!
        if goal == 0 || goal > 9 {
            throw CommandError("BAD SIZE")
        }
        if start > goal {
            throw CommandError("BAD START")
        }
        let chance = try probability(words[4])
        if chance == .zero || chance == .one {
            throw CommandError("BAD PROBABILITY")
        }
        var chain = Chain((0...goal).map { "s\($0)" })
        chain.p[0][0] = .one
        chain.p[goal][goal] = .one
        for i in 1..<goal {
            chain.p[i][i + 1] = chance
            chain.p[i][i - 1] = 1 - chance
        }
        let result = Absorption(chain)
        var ruin = Row(repeating: .zero, count: goal + 1)
        var duration = Row(repeating: .zero, count: goal + 1)
        ruin[0] = .one
        for i in 1..<goal {
            ruin[i] = result.probabilities[i - 1][0]
            duration[i] = result.means[i - 1]
        }
        chains[name] = chain
        emit(
            "GAMBLER \(name) g=\(goal) p=\(chance) start=s\(start) ruin=\(ruin[start].value) duration=\(duration[start].value)"
        )
        for i in 0...goal {
            emit("CAPITAL s\(i) ruin=\(ruin[i].value) win=\((1 - ruin[i]).value) duration=\(duration[i].value)")
        }
    }

    func command(_ words: [String]) throws {
        let op = words[0], name = words[1]
        switch op {
        case "CHAIN":
            try create(words)
            return
        case "BUILD":
            try build(words)
            return
        case "GAMBLER":
            try gambler(words)
            return
        default:
            break
        }
        guard var chain = chains[name] else {
            throw CommandError("UNKNOWN CHAIN \(name)")
        }
        let n = chain.size
        switch op {
        case "P":
            let from = try chain.state(words[2])
            let to = try chain.state(words[3])
            let chance = try probability(words[4])
            chain.p[from][to] = chance
            chains[name] = chain
            emit("P \(name) \(words[2]) \(words[3]) \(chance) rowsum=\(total(chain.p[from]))")
            return
        case "ROW":
            let state = try chain.state(words[2])
            if words.count - 3 != n {
                throw CommandError("BAD LENGTH")
            }
            let row = try words.dropFirst(3).map { try probability($0) }
            chain.p[state] = row
            chains[name] = chain
            emit("ROW \(name) \(words[2]) rowsum=\(total(row))")
            return
        case "SHOW":
            emit("MATRIX \(name) states=\(n)")
            display(chain)
            return
        case "CHECK":
            let sums = chain.p.map(total)
            let bad = chain.indices.filter { sums[$0] != .one }
            emit("CHECK \(name) \(bad.isEmpty ? "ok" : "bad=\(bad.count)")")
            for state in bad {
                emit("BADROW \(chain.names[state]) sum=\(sums[state])")
            }
            return
        default:
            break
        }
        for i in chain.indices {
            if total(chain.p[i]) != .one {
                throw CommandError("NOT STOCHASTIC \(chain.names[i])")
            }
        }
        let graph = Decomposition(chain)
        switch op {
        case "CLASSES":
            emit("CLASSES \(name) count=\(graph.classes.count)")
            for (index, group) in graph.classes.enumerated() {
                emit(
                    "CLASS \(index + 1) \(group.closed ? "RECURRENT" : "TRANSIENT") period=\(group.period) size=\(group.states.count) \(chain.labels(group.states))"
                )
                if group.period >= 2 {
                    for residue in 0..<group.period {
                        let states = group.states.filter { group.levels[$0] % group.period == residue }
                        emit("CYCLIC \(residue) \(chain.labels(states))")
                    }
                }
            }
        case "CLASSIFY":
            let absorbing = chain.indices.filter { chain.p[$0][$0] == .one }
            let absorbs = !absorbing.isEmpty && chain.indices
                .allSatisfy { i in absorbing.contains { graph.reach[i][$0] } }
            let edges = chain.indices.map { i in chain.indices.map { j in chain.p[i][j].numerator > 0 } }
            var power = edges
            var exponent: Int?
            let bound = (n - 1) * (n - 1) + 1
            for t in 1...bound {
                if power.allSatisfy({ $0.allSatisfy { $0 } }) {
                    exponent = t
                    break
                }
                if t == bound {
                    break
                }
                power = chain.indices.map { i in
                    chain.indices.map { j in chain.indices.contains { power[i][$0] && edges[$0][j] } }
                }
            }
            emit(
                "CLASSIFY \(name) absorbing_states=\(absorbing.count) absorbing=\(yes(absorbs)) ergodic=\(yes(graph.classes.count == 1)) regular=\(yes(exponent != nil)) exponent=\(exponent.map { String($0) } ?? "-")"
            )
        case "STEP":
            let initial = words[2], steps = Int(words[3])!
            var distribution = Row(repeating: .zero, count: n)
            if initial.first!.isNumber {
                let parts = split(initial, by: ",")
                if parts.count != n {
                    throw CommandError("BAD LENGTH")
                }
                distribution = try parts.map { try probability($0) }
                if total(distribution) != .one {
                    throw CommandError("BAD DISTRIBUTION")
                }
            } else {
                let state = try chain.state(initial)
                distribution[state] = .one
            }
            for _ in 0..<steps {
                distribution = multiply([distribution], chain.p)[0]
            }
            emit("STEP \(name) k=\(steps)")
            for i in chain.indices {
                emit("PROB \(chain.names[i]) \(distribution[i].value)")
            }
        case "POWER":
            let steps = Int(words[2])!
            var power = identity(n)
            for _ in 0..<steps {
                power = multiply(power, chain.p)
            }
            emit("POWER \(name) k=\(steps)")
            display(chain, values: power)
        case "STATIONARY":
            emit("STATIONARY \(name) count=\(graph.classes.filter(\.closed).count)")
            var number = 0
            for (index, group) in graph.classes.enumerated() where group.closed {
                let pi = stationary(chain, group.states)
                number += 1
                emit("DIST \(number) class=\(index + 1) size=\(group.states.count)")
                for (i, state) in group.states.enumerated() {
                    emit("PI \(chain.names[state]) \(pi[i].value)")
                }
            }
        case "RECURRENCE":
            let state = try chain.state(words[2])
            let group = graph.classes[graph.classOf[state]]
            if !group.closed {
                throw CommandError("TRANSIENT STATE \(words[2])")
            }
            let pi = stationary(chain, group.states)
            let rho = pi[group.states.firstIndex(of: state)!]
            emit("RECURRENCE \(name) \(words[2]) pi=\(rho.value) mean=\((1 / rho).value) period=\(group.period)")
        case "ABSORB":
            let absorbing = chain.indices.filter { chain.p[$0][$0] == .one }
            if absorbing.isEmpty {
                throw CommandError("NO ABSORBING STATE")
            }
            for i in chain.indices {
                if !absorbing
                    .contains(where: { graph.reach[i][$0] })
                {
                    throw CommandError("NOT ABSORBING \(chain.names[i])")
                }
            }
            let result = Absorption(chain)
            emit("ABSORB \(name) transient=\(result.transient.count) absorbing=\(absorbing.count)")
            if result.transient.isEmpty {
                return
            }
            emit("TRANSIENT \(chain.labels(result.transient))")
            emit("ABSORBING \(chain.labels(absorbing))")
            for (i, state) in result.transient.enumerated() {
                emit("N \(chain.names[state]) \(result.fundamental[i].map(\.description).joined(separator: " "))")
            }
            for (i, state) in result.transient.enumerated() {
                emit("STEPS \(chain.names[state]) mean=\(result.means[i].value) var=\(result.variances[i].value)")
            }
            for (i, state) in result.transient.enumerated() {
                emit("B \(chain.names[state]) \(result.probabilities[i].map(\.description).joined(separator: " "))")
            }
        case "HITTING":
            let targets = try chain.stateSet(Array(words.dropFirst(2)))
            let result = hitting(chain, targets, graph.reach)
            emit("HITTING \(name) targets=\(chain.labels(targets, separator: ","))")
            for i in chain.indices {
                emit(
                    "HIT \(chain.names[i]) prob=\(result.probabilities[i].value) time=\(result.times[i]?.value ?? "inf")"
                )
            }
        case "PASSAGE":
            let pi = try irreducible(chain, graph)
            var passage = matrix(n, n)
            for j in chain.indices {
                let result = hitting(chain, [j], graph.reach)
                for i in chain.indices {
                    passage[i][j] = i == j ? 1 / pi[j] : result.times[i]!
                }
            }
            var kemeny: Fraction = 0
            for j in 1..<n {
                kemeny = kemeny + pi[j] * passage[0][j]
            }
            emit("PASSAGE \(name) kemeny=\(kemeny.value)")
            display(chain, values: passage, prefix: "M")
        case "FIRSTPASSAGE":
            let from = try chain.state(words[2])
            let target = try chain.state(words[3])
            let steps = Int(words[4])!
            if steps == 0 {
                throw CommandError("BAD STEPS")
            }
            var previous = chain.indices.map { chain.p[$0][target] }
            var first: Row = [], cumulative: Row = []
            var sum: Fraction = 0
            for t in 1...steps {
                first.append(previous[from])
                sum = sum + previous[from]
                cumulative.append(sum)
                if t == steps {
                    break
                }
                var next = Row(repeating: .zero, count: n)
                for i in chain.indices {
                    for u in chain.indices where u != target {
                        next[i] = next[i] + chain.p[i][u] * previous[u]
                    }
                }
                previous = next
            }
            emit("FIRSTPASSAGE \(name) \(words[2]) \(words[3]) k=\(steps) total=\(sum.value)")
            for t in 0..<steps {
                emit("FP \(t + 1) \(first[t].value) cum=\(cumulative[t].value)")
            }
        case "PATHPROB":
            let path = try words.dropFirst(2).map { try chain.state($0) }
            var chance: Fraction = 1
            var zeroAt: Int?
            for i in 1..<path.count {
                chance = chance * chain.p[path[i - 1]][path[i]]
                if chance == .zero && zeroAt == nil {
                    zeroAt = i
                }
            }
            emit(
                "PATHPROB \(name) steps=\(path.count - 1) prob=\(chance.value)\(zeroAt.map { " zero_at=\($0)" } ?? "")"
            )
        case "MOSTLIKELY":
            let start = try chain.state(words[2])
            let steps = Int(words[3])!
            if steps == 0 {
                throw CommandError("BAD STEPS")
            }
            var best = matrix(steps + 1, n)
            best[steps] = Row(repeating: .one, count: n)
            for t in stride(from: steps - 1, through: 0, by: -1) {
                for i in chain.indices {
                    for j in chain.indices {
                        let candidate = chain.p[i][j] * best[t + 1][j]
                        if candidate > best[t][i] {
                            best[t][i] = candidate
                        }
                    }
                }
            }
            var path = [start]
            for t in 0..<steps {
                let current = path.last!
                let next = chain.indices.first { chain.p[current][$0] * best[t + 1][$0] == best[t][current] }!
                path.append(next)
            }
            emit("MOSTLIKELY \(name) \(words[2]) k=\(steps) prob=\(best[0][start].value)")
            emit("PATH \(chain.labels(path))")
        case "REVERSIBLE":
            let pi = try irreducible(chain, graph)
            var violations: [(from: Int, to: Int, forward: Fraction, backward: Fraction)] = []
            for i in chain.indices {
                for j in (i + 1)..<n {
                    let forward = pi[i] * chain.p[i][j], backward = pi[j] * chain.p[j][i]
                    if forward != backward {
                        violations.append((i, j, forward, backward))
                    }
                }
            }
            emit("REVERSIBLE \(name) \(violations.isEmpty ? "yes" : "no violations=\(violations.count)")")
            for violation in violations {
                emit(
                    "VIOLATION \(chain.names[violation.from]) \(chain.names[violation.to]) \(violation.forward.value) \(violation.backward.value)"
                )
            }
        case "REVERSE":
            let pi = try irreducible(chain, graph)
            var reversed = Chain(chain.names)
            var same = true
            for i in chain.indices {
                for j in chain.indices {
                    reversed.p[i][j] = pi[j] * chain.p[j][i] / pi[i]
                    if reversed.p[i][j] != chain.p[i][j] {
                        same = false
                    }
                }
            }
            chains[words[2]] = reversed
            emit("REVERSE \(name) \(words[2]) reversible=\(yes(same))")
            display(reversed)
        case "MIXING":
            let steps = Int(words[2])!
            if steps == 0 {
                throw CommandError("BAD STEPS")
            }
            let epsilon = try probability(words[3])
            let pi = try irreducible(chain, graph)
            var power = identity(n)
            var distances: [(value: Fraction, state: Int)] = []
            var mixingTime: Int?
            for t in 1...steps {
                power = multiply(power, chain.p)
                var worst: (value: Fraction, state: Int) = (.zero, 0)
                for i in chain.indices {
                    var distance: Fraction = 0
                    for j in chain.indices {
                        distance = distance + (power[i][j] - pi[j]).absolute
                    }
                    distance = distance / 2
                    if distance > worst.value {
                        worst = (distance, i)
                    }
                }
                distances.append(worst)
                if mixingTime == nil && worst.value <= epsilon {
                    mixingTime = t
                }
            }
            emit("MIXING \(name) k=\(steps) eps=\(epsilon) time=\(mixingTime.map { String($0) } ?? "none")")
            for (t, distance) in distances.enumerated() {
                emit("TV \(t + 1) \(distance.value.value) from=\(chain.names[distance.state])")
            }
        case "LUMP":
            var blocks: [[Int]] = [], seen = Set<Int>()
            for block in split(words[3], by: "|") {
                var states: [Int] = []
                for name in split(block, by: ",") {
                    let state = try chain.state(name)
                    if !seen.insert(state).inserted {
                        throw CommandError("BAD PARTITION")
                    }
                    states.append(state)
                }
                blocks.append(states.sorted())
            }
            if seen.count != n {
                throw CommandError("BAD PARTITION")
            }
            blocks.sort { $0[0] < $1[0] }
            var lumped = Chain(blocks.map { chain.names[$0[0]] })
            for k in blocks.indices {
                for l in blocks.indices {
                    let representative = blocks[k][0]
                    let expected = chain.blockSum(representative, blocks[l])
                    for state in blocks[k] {
                        let actual = chain.blockSum(state, blocks[l])
                        if actual != expected {
                            emit(
                                "LUMP \(name) not lumpable block=\(chain.names[representative]) target=\(chain.names[blocks[l][0]]) \(chain.names[representative])=\(expected.value) \(chain.names[state])=\(actual.value)"
                            )
                            return
                        }
                    }
                    lumped.p[k][l] = expected
                }
            }
            chains[words[2]] = lumped
            emit("LUMP \(name) \(words[2]) blocks=\(blocks.count)")
            display(lumped)
        case "REWARD":
            if words.count - 3 != n {
                throw CommandError("BAD LENGTH")
            }
            let gamma = try probability(words[2])
            if gamma == .one {
                throw CommandError("BAD DISCOUNT")
            }
            let rewards = words.dropFirst(3).map { Fraction(Int64($0)!) }
            var rows = matrix(n, n + 1)
            for i in chain.indices {
                for j in chain.indices {
                    rows[i][j] = delta(i, j) - gamma * chain.p[i][j]
                }
                rows[i][n] = rewards[i]
            }
            let discounted = solve(rows)
            var gains = Row(repeating: .zero, count: n)
            for group in graph.classes where group.closed {
                let pi = stationary(chain, group.states)
                var average: Fraction = 0
                for (j, state) in group.states.enumerated() {
                    average = average + pi[j] * rewards[state]
                }
                let result = hitting(chain, group.states, graph.reach, withTimes: false)
                for i in chain.indices {
                    gains[i] = gains[i] + result.probabilities[i] * average
                }
            }
            emit("REWARD \(name) gamma=\(gamma)")
            for i in chain.indices {
                emit("VALUE \(chain.names[i]) discounted=\(discounted[i][0].value) gain=\(gains[i].value)")
            }
        case "RESTRICT":
            let selected = try chain.stateSet(Array(words.dropFirst(3)))
            let inside = Set(selected)
            for state in selected {
                for j in chain.indices where !inside.contains(j) && chain.p[state][j].numerator > 0 {
                    throw CommandError("NOT CLOSED \(chain.names[state])")
                }
            }
            var restricted = Chain(selected.map { chain.names[$0] })
            for (i, from) in selected.enumerated() {
                for (j, to) in selected.enumerated() {
                    restricted.p[i][j] = chain.p[from][to]
                }
            }
            chains[words[2]] = restricted
            emit("RESTRICT \(name) \(words[2]) states=\(selected.count)")
            display(restricted)
        case "SIMULATE":
            let start = try chain.state(words[2])
            let steps = Int(words[3])!
            if steps == 0 {
                throw CommandError("BAD STEPS")
            }
            let seed = Int64(words[4])!
            if seed == 0 || seed >= 2_147_483_647 {
                throw CommandError("BAD SEED")
            }
            var random = seed, current = start
            var path = [start], visits = [Int](repeating: 0, count: n)
            visits[start] += 1
            for _ in 0..<steps {
                var common: Int64 = 1
                for chance in chain
                    .p[current]
                {
                    common = common / gcd(common, chance.denominator) * chance.denominator
                }
                random = 48_271 * random % 2_147_483_647
                let threshold = Fraction(random % common)
                var cumulative: Fraction = 0
                for j in chain.indices {
                    cumulative = cumulative + chain.p[current][j]
                    if cumulative * Fraction(common) > threshold {
                        current = j
                        break
                    }
                }
                path.append(current)
                visits[current] += 1
            }
            emit("SIMULATE \(name) \(words[2]) steps=\(steps) seed=\(seed) end=\(chain.names[current])")
            emit("PATH \(chain.labels(path))")
            for i in chain.indices {
                emit("VISIT \(chain.names[i]) \(visits[i])")
            }
        default:
            break
        }
    }
}

let count = Int(readLine()!)!
let analyzer = Analyzer()
for _ in 0..<count {
    let words = split(readLine()!)
    do { try analyzer.command(words) }
    catch { analyzer.emit("ERROR \(error)") }
}
print(analyzer.output.joined(separator: "\n"))
