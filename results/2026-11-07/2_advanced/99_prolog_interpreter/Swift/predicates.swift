import Foundation
func control(_ key: Indicator) -> Bool {
    [Indicator(name: ",", arity: 2), Indicator(name: "!", arity: 0), Indicator(name: ";", arity: 2),
    Indicator(name: "->", arity: 2), Indicator(name: "\\+", arity: 1), Indicator(name: "catch", arity: 3)].contains(key) ||
    (key.name == "call" && (1...8).contains(key.arity))
}
func builtin(_ key: Indicator) -> Bool {
    let arities: [String: Int] = ["findall": 3, "throw": 1, "between": 3, "length": 2, "true": 0, "fail": 0, "false": 0,
    "=": 2, "\\=": 2, "==": 2, "\\==": 2, "var": 1, "nonvar": 1, "atom": 1, "number": 1, "integer": 1,
    "atomic": 1, "compound": 1, "callable": 1, "is_list": 1, "is": 2, "=:=": 2, "=\\=": 2,
    "<": 2, ">": 2, "=<": 2, ">=": 2, "functor": 3, "arg": 3, "=..": 2, "copy_term": 2,
    "atom_length": 2, "atom_chars": 2, "write": 1, "writeq": 1, "nl": 0]
    return arities[key.name] == key.arity
}
func integer(_ term: Term, _ store: Store) throws -> Int {
    switch store.dereference(term) {
        case .integer(let n): return n
        case .variable: throw PrologError(term: .atom("instantiation_error"))
        case let value: throw PrologError(term: typeError("integer", value))
    }
}
func atom(_ term: Term, _ store: Store) throws -> String {
    switch store.dereference(term) {
        case .atom(let name): return name
        case .variable: throw PrologError(term: .atom("instantiation_error"))
        case let value: throw PrologError(term: typeError("atom", value))
    }
}
func proper(_ term: Term, _ store: Store) throws -> [Term] {
    let (elements, tail) = store.parts(term)
    switch tail {
        case .atom("[]"): return elements
        case .variable: throw PrologError(term: .atom("instantiation_error"))
        default: throw PrologError(term: typeError("list", term))
    }
}
func arithmetic(_ term: Term, _ store: Store) throws -> Int {
    switch store.dereference(term) {
        case .variable: throw PrologError(term: .atom("instantiation_error"))
        case .integer(let n): return n
        case .atom(let name): throw PrologError(term: typeError("evaluable", indicatorTerm(Indicator(name: name, arity: 0))))
        case .compound(let name, let args):
        let valid = (args.count == 2 && ["+", "-", "*", "//", "mod", "rem", "min", "max"].contains(name)) ||
        (args.count == 1 && ["-", "abs"].contains(name))
        if !valid {
            throw PrologError(term: typeError("evaluable", indicatorTerm(Indicator(name: name, arity: args.count))))
        }
        let a = try arithmetic(args[0], store)
        let b = args.count == 2 ? try arithmetic(args[1], store) : 0
        if ["//", "mod", "rem"].contains(name) && b == 0 {
            throw PrologError(term: .compound("evaluation_error", [.atom("zero_divisor")]))
        }
        let result: Int
        switch name {
            case "+": result = a + b
            case "-": result = args.count == 1 ? -a : a - b
            case "*": result = a * b
            case "//": result = a / b
            case "rem": result = a % b
            case "mod":
            var quotient = a / b
            if a % b != 0 && (a < 0) != (b < 0) {
                quotient -= 1
            }
            result = a - b * quotient
            case "abs": result = abs(a)
            case "min": result = min(a, b)
            default: result = max(a, b)
        }
        if result < -2147483648 || result > 2147483647 {
            throw PrologError(term: .compound("evaluation_error", [.atom("int_overflow")]))
        }
        return result
    }
}
func deterministic(_ key: Indicator, _ args: [Term], _ store: Store, _ trail: Trail, _ output: inout String) throws -> Bool {
    let name = key.name
    switch name {
        case "true": return true
        case "fail", "false": return false
        case "=": return trail.unify(args[0], args[1], store)
        case "\\=":
        let mark = trail.mark
        let result = trail.unify(args[0], args[1], store)
        trail.undo(mark, store)
        return !result
        case "==", "\\==": return identical(args[0], args[1], store) == (name == "==")
        case "var", "nonvar", "atom", "number", "integer", "atomic", "compound", "callable", "is_list":
        let term = store.dereference(args[0])
        switch name {
            case "var": return term.variableID != nil
            case "nonvar": return term.variableID == nil
            case "atom": if case .atom = term {
                return true
            };
            return false
            case "number", "integer": if case .integer = term {
                return true
            };
            return false
            case "atomic": if case .integer = term {
                return true
            };
            if case .atom = term {
                return true
            };
            return false
            case "compound": if case .compound = term {
                return true
            };
            return false
            case "callable": return term.indicator != nil
            default: if case .atom("[]") = store.parts(term).1 {
                return true
            };
            return false
        }
        case "is":
        let value = try arithmetic(args[1], store)
        return trail.unify(args[0], .integer(value), store)
        case "=:=", "=\\=", "<", ">", "=<", ">=":
        let a = try arithmetic(args[0], store)
        let b = try arithmetic(args[1], store)
        switch name {
            case "=:=": return a == b
            case "=\\=": return a != b
            case "<": return a < b
            case ">": return a > b
            case "=<": return a <= b
            default: return a >= b
        }
        case "functor":
        let term = store.dereference(args[0])
        if term.variableID == nil {
            let functor: Term
            let arity: Int
            if case .compound(let name, let values) = term {
                functor = .atom(name);
                arity = values.count
            }
            else {
                functor = term;
                arity = 0
            }
            return trail.unify(args[1], functor, store) && trail.unify(args[2], .integer(arity), store)
        }
        let functor = store.dereference(args[1])
        let arity = store.dereference(args[2])
        if functor.variableID != nil || arity.variableID != nil {
            throw PrologError(term: .atom("instantiation_error"))
        }
        if case .compound = functor {
            throw PrologError(term: typeError("atomic", functor))
        }
        guard case .integer(let n) = arity else {
            throw PrologError(term: typeError("integer", arity))
        }
        if n < 0 {
            throw PrologError(term: domainError("not_less_than_zero", arity))
        }
        if n > 255 {
            throw PrologError(term: .compound("representation_error", [.atom("max_arity")]))
        }
        if n == 0 {
            return trail.unify(args[0], functor, store)
        }
        guard case .atom(let name) = functor else {
            throw PrologError(term: typeError("atom", functor))
        }
        let values = (0..<n).map {
            _ in store.fresh()
        }
        return trail.unify(args[0], .compound(name, values), store)
        case "arg":
        let n = store.dereference(args[0])
        let term = store.dereference(args[1])
        if n.variableID != nil || term.variableID != nil {
            throw PrologError(term: .atom("instantiation_error"))
        }
        guard case .integer(let index) = n else {
            throw PrologError(term: typeError("integer", n))
        }
        guard case .compound(_, let values) = term else {
            throw PrologError(term: typeError("compound", term))
        }
        return index >= 1 && index <= values.count && trail.unify(values[index - 1], args[2], store)
        case "=..":
        let term = store.dereference(args[0])
        if term.variableID == nil {
            let values: [Term]
            if case .compound(let name, let arguments) = term {
                values = [.atom(name)] + arguments
            }
            else {
                values = [term]
            }
            return trail.unify(list(values), args[1], store)
        }
        let values = try proper(args[1], store)
        if values.isEmpty {
            throw PrologError(term: domainError("non_empty_list", .atom("[]")))
        }
        let head = store.dereference(values[0])
        if head.variableID != nil {
            throw PrologError(term: .atom("instantiation_error"))
        }
        if values.count == 1 {
            if case .compound = head {
                throw PrologError(term: typeError("atomic", head))
            }
            return trail.unify(args[0], head, store)
        }
        guard case .atom(let name) = head else {
            throw PrologError(term: typeError("atom", head))
        }
        if values.count - 1 > 255 {
            throw PrologError(term: .compound("representation_error", [.atom("max_arity")]))
        }
        return trail.unify(args[0], .compound(name, Array(values.dropFirst())), store)
        case "copy_term": return trail.unify(store.copy(args[0]), args[1], store)
        case "atom_length":
        let name = try atom(args[0], store)
        let n = store.dereference(args[1])
        if n.variableID == nil {
            if case .integer = n {
            } else {
                throw PrologError(term: typeError("integer", n))
            }
        }
        return trail.unify(.integer(name.utf8.count), args[1], store)
        case "atom_chars":
        if store.dereference(args[0]).variableID == nil {
            let name = try atom(args[0], store)
            return trail.unify(args[1], list(name.map {
                .atom(String($0))
            }), store)
        }
        let values = try proper(args[1], store)
        var name = ""
        for value in values {
            let value = store.dereference(value)
            if value.variableID != nil {
                throw PrologError(term: .atom("instantiation_error"))
            }
            guard case .atom(let character) = value, character.utf8.count == 1 else {
                throw PrologError(term: typeError("character", value))
            }
            name += character
        }
        return trail.unify(args[0], .atom(name), store)
        case "write", "writeq":
        output += writeTerm(args[0], store, name == "writeq")
        return true
        case "nl": output += "\n";
        return true
        default: preconditionFailure()
    }
}
