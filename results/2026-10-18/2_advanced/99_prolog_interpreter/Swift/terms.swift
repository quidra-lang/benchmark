import Foundation
struct Indicator: Hashable {
    let name: String
    let arity: Int
}
indirect enum Term: Sendable {
    case integer(Int)
    case atom(String)
    case variable(Int)
    case compound(String, [Term])
    var indicator: Indicator? {
        switch self {
            case .atom(let name): return Indicator(name: name, arity: 0)
            case .compound(let name, let args): return Indicator(name: name, arity: args.count)
            default: return nil
        }
    }
    var arguments: [Term] {
        if case .compound(_, let args) = self {
            return args
        }
        return []
    }
    var variableID: Int? {
        if case .variable(let id) = self {
            return id
        }
        return nil
    }
}
final class Store {
    var bindings: [Term?] = []
    func clone() -> Store {
        let result = Store()
        result.bindings = bindings
        return result
    }
    func fresh() -> Term {
        let result = Term.variable(bindings.count)
        bindings.append(nil)
        return result
    }
    func dereference(_ term: Term) -> Term {
        var result = term
        while case .variable(let id) = result, let binding = bindings[id] {
            result = binding
        }
        return result
    }
    func copy(_ term: Term) -> Term {
        var names: [Int: Term] = [:]
        return copy(term, names: &names)
    }
    func copyMany(_ terms: [Term]) -> [Term] {
        var names: [Int: Term] = [:]
        return terms.map {
            copy($0, names: &names)
        }
    }
    private func copy(_ term: Term, names: inout [Int: Term]) -> Term {
        switch dereference(term) {
            case .variable(let id):
            if let result = names[id] {
                return result
            }
            let result = fresh()
            names[id] = result
            return result
            case .compound(let name, let args):
            return .compound(name, args.map {
                copy($0, names: &names)
            })
            case let result: return result
        }
    }
    func parts(_ term: Term) -> ([Term], Term) {
        var elements: [Term] = []
        var tail = dereference(term)
        while case .compound(".", let args) = tail, args.count == 2 {
            elements.append(args[0])
            tail = dereference(args[1])
        }
        return (elements, tail)
    }
    func variables(_ terms: [Term]) -> [Int] {
        var pending = Array(terms.reversed())
        var result: [Int] = []
        while let term = pending.popLast() {
            switch dereference(term) {
                case .variable(let id): result.append(id)
                case .compound(_, let args): pending.append(contentsOf: args.reversed())
                default: break
            }
        }
        return result
    }
}
func list(_ elements: [Term], _ tail: Term = .atom("[]")) -> Term {
    elements.reversed().reduce(tail) {
        .compound(".", [$1, $0])
    }
}
func indicatorTerm(_ key: Indicator) -> Term {
    .compound("/", [.atom(key.name), .integer(key.arity)])
}
func typeError(_ kind: String, _ term: Term) -> Term {
    .compound("type_error", [.atom(kind), term])
}
func domainError(_ kind: String, _ term: Term) -> Term {
    .compound("domain_error", [.atom(kind), term])
}
func errorBall(_ error: Term, _ key: Indicator) -> Term {
    .compound("error", [error, indicatorTerm(key)])
}
struct PrologError: Error {
    let term: Term
}
func sameKind(_ a: Term, _ b: Term, _ store: Store) -> Bool {
    let a = store.dereference(a)
    let b = store.dereference(b)
    if a.variableID != nil || b.variableID != nil {
        return true
    }
    switch (a, b) {
        case (.integer(let x), .integer(let y)): return x == y
        case (.atom(let x), .atom(let y)): return x == y
        case (.compound(let x, let xs), .compound(let y, let ys)):
        return x == y && xs.count == ys.count
        default: return false
    }
}
