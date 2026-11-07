struct Clause {
    let head: Term
    let body: Term?
    let file: String
    let line: Int
}
struct Predicate {
    let indicator: Indicator
    var clauses: [Clause] = []
}
final class Database {
    var predicates: [Predicate] = []
    func find(_ key: Indicator) -> Int? {
        predicates.firstIndex {
            $0.indicator == key
        }
    }
    func candidates(_ index: Int, _ goal: Term, _ store: Store) -> [Int] {
        let args = goal.arguments
        return predicates[index].clauses.indices.filter {
            args.isEmpty || sameKind(args[0], predicates[index].clauses[$0].head.arguments[0], store)
        }
    }
    func copy(_ predicate: Int, _ clause: Int, _ store: Store) -> (Term, Term?) {
        let source = predicates[predicate].clauses[clause]
        var terms = [source.head]
        if let body = source.body {
            terms.append(body)
        }
        let copies = store.copyMany(terms)
        return (copies[0], copies.count == 2 ? copies[1] : nil)
    }
}
