struct SearchStatistics {
    var decisions = 0
    var propagations = 0
    var conflicts = 0
    var maxDepth = 0

    mutating func accumulate(_ other: SearchStatistics) {
        decisions += other.decisions
        propagations += other.propagations
        conflicts += other.conflicts
        maxDepth = max(maxDepth, other.maxDepth)
    }
}

enum TrailKind: String {
    case decision = "D", flip = "F", propagation = "P"
}

struct TrailEntry {
    let literal: Int
    let kind: TrailKind
}

struct RoundResult {
    let model: [Bool]?
    let trace: [String]
    let statistics: SearchStatistics
}

final class DPLL {
    var clauses: [[Int]]
    var assignment: [Bool?]
    var watches: [Int: [Int]] = [:]
    var trail: [TrailEntry] = []
    var queueHead = 0
    var trace: [String] = []
    var statistics = SearchStatistics()

    init(_ variables: Int, _ clauses: [[Int]]) {
        self.clauses = clauses
        assignment = Array(repeating: nil, count: variables + 1)
    }

    func value(_ literal: Int) -> Bool? {
        assignment[abs(literal)].map { literal > 0 ? $0 : !$0 }
    }

    func assign(_ literal: Int, _ kind: TrailKind) {
        assignment[abs(literal)] = literal > 0
        trail.append(TrailEntry(literal: literal, kind: kind))
        trace.append(kind.rawValue + String(literal))
    }

    func conflict() {
        statistics.conflicts += 1
        trace.append("C")
    }

    func result(_ satisfiable: Bool) -> RoundResult {
        RoundResult(model: satisfiable ? assignment.map { $0 ?? false } : nil, trace: trace, statistics: statistics)
    }

    func propagate() -> Bool {
        while queueHead < trail.count {
            let falseLiteral = -trail[queueHead].literal
            queueHead += 1
            var index = 0
            while index < watches[falseLiteral, default: []].count {
                let clauseID = watches[falseLiteral]![index]
                if clauses[clauseID][0] == falseLiteral { clauses[clauseID].swapAt(0, 1) }
                let other = clauses[clauseID][0]
                if value(other) == true {
                    index += 1
                    continue
                }
                let substitute = (2..<clauses[clauseID].count).first { value(clauses[clauseID][$0]) != false }
                if let substitute {
                    clauses[clauseID].swapAt(1, substitute)
                    watches[falseLiteral]!.remove(at: index)
                    watches[clauses[clauseID][1], default: []].append(clauseID)
                    continue
                }
                if value(other) == false {
                    conflict()
                    return false
                }
                if value(other) == nil {
                    assign(other, .propagation)
                    statistics.propagations += 1
                }
                index += 1
            }
        }
        return true
    }

    func run() -> RoundResult {
        for (index, clause) in clauses.enumerated() where clause.count >= 2 {
            watches[clause[0], default: []].append(index)
            watches[clause[1], default: []].append(index)
        }
        for clause in clauses {
            if clause.isEmpty || (clause.count == 1 && value(clause[0]) == false) {
                conflict()
                return result(false)
            }
            if clause.count == 1 && value(clause[0]) == nil {
                assign(clause[0], .propagation)
                statistics.propagations += 1
            }
        }
        while true {
            if !propagate() {
                while let last = trail.last, last.kind != .decision {
                    assignment[abs(last.literal)] = nil
                    trail.removeLast()
                }
                guard let decision = trail.popLast() else { return result(false) }
                assignment[abs(decision.literal)] = nil
                assign(-decision.literal, .flip)
                queueHead = trail.count - 1
                continue
            }
            var counts: [Int: Int] = [:]
            for clause in clauses where !clause.contains(where: { value($0) == true }) {
                for literal in clause where value(literal) == nil { counts[literal, default: 0] += 1 }
            }
            guard let chosen = counts.keys.sorted(by: { first, second in
                if counts[first]! != counts[second]! { return counts[first]! > counts[second]! }
                return abs(first) == abs(second) ? first > second : abs(first) < abs(second)
            }).first else { return result(true) }
            assign(chosen, .decision)
            statistics.decisions += 1
            statistics.maxDepth = max(statistics.maxDepth, trail.filter { $0.kind != .propagation }.count)
        }
    }
}

func runRound(_ variables: Int, _ clauses: [[Int]]) -> RoundResult { DPLL(variables, clauses).run() }
