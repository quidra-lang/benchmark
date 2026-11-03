struct NumberedClause {
    let number: Int
    let literals: [Int]
}

struct Preprocessing {
    var clauses: [[Int]] = []
    var fixed: [Int: Bool] = [:]
    var active: [Int] = []
    var tautologies = 0
    var duplicateLiterals = 0
    var unitFixed = 0
    var unitRemoved = 0
    var subsumed = 0
    var pureFixed = 0
    var pureRemoved = 0
    var tautologyRecords: [Int] = []
    var unitRecords: [Int] = []
    var subsumedRecords: [Int] = []
    var pureRecords: [Int] = []
    var emptyClause: Int?
    let pure: Bool
    var removed: Int { tautologies + unitRemoved + subsumed + pureRemoved }
}

func preprocess(_ formula: Formula, usePure: Bool) -> Preprocessing {
    var result = Preprocessing(pure: usePure)
    var working: [NumberedClause] = []
    for (index, clause) in formula.clauses.enumerated() {
        let all = Set(clause)
        if clause.contains(where: { all.contains(-$0) }) {
            result.tautologies += 1
            result.tautologyRecords.append(index + 1)
            continue
        }
        var seen: Set<Int> = []
        var reduced: [Int] = []
        for literal in clause {
            if seen.insert(literal).inserted { reduced.append(literal) }
            else { result.duplicateLiterals += 1 }
        }
        working.append(NumberedClause(number: index + 1, literals: reduced))
    }
    while true {
        if let empty = working.first(where: { $0.literals.isEmpty }) {
            result.emptyClause = empty.number
            break
        }
        guard let unit = working.first(where: { $0.literals.count == 1 })?.literals[0] else { break }
        result.fixed[abs(unit)] = unit > 0
        result.unitFixed += 1
        var surviving: [NumberedClause] = []
        for clause in working {
            if clause.literals.contains(unit) {
                result.unitRemoved += 1
                result.unitRecords.append(clause.number)
            } else {
                surviving.append(NumberedClause(number: clause.number, literals: clause.literals.filter { $0 != -unit }))
            }
        }
        working = surviving
    }
    if result.emptyClause == nil {
        let sets = working.map { Set($0.literals) }
        var removed: Set<Int> = []
        for second in working.indices {
            for first in working.indices where first != second {
                if sets[first].isSubset(of: sets[second])
                    && (working[first].literals.count < working[second].literals.count || first < second) {
                    removed.insert(second)
                    break
                }
            }
        }
        result.subsumedRecords = removed.sorted().map { working[$0].number }
        result.subsumed = removed.count
        working = working.enumerated().filter { !removed.contains($0.offset) }.map { $0.element }
        if usePure {
            while true {
                let present = Set(working.flatMap { $0.literals })
                let pure = Set(present.filter { !present.contains(-$0) })
                if pure.isEmpty { break }
                for literal in pure { result.fixed[abs(literal)] = literal > 0 }
                result.pureFixed += pure.count
                var surviving: [NumberedClause] = []
                for clause in working {
                    if clause.literals.contains(where: { pure.contains($0) }) {
                        result.pureRemoved += 1
                        result.pureRecords.append(clause.number)
                    } else { surviving.append(clause) }
                }
                working = surviving
            }
        }
    }
    result.clauses = working.map { $0.literals }
    result.active = (1..<(formula.variables + 1)).filter { result.fixed[$0] == nil }
    result.tautologyRecords.sort()
    result.unitRecords.sort()
    result.subsumedRecords.sort()
    result.pureRecords.sort()
    return result
}
