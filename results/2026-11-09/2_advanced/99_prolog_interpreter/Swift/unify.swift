final class Trail {
    var bindings: [Int] = []
    var mark: Int {
        bindings.count
    }
    func undo(_ mark: Int, _ store: Store) {
        while bindings.count > mark {
            store.bindings[bindings.removeLast()] = nil
        }
    }
    func unify(_ a: Term, _ b: Term, _ store: Store) -> Bool {
        var pending = [(a, b)]
        while let pair = pending.popLast() {
            let x = store.dereference(pair.0)
            let y = store.dereference(pair.1)
            if let id = x.variableID {
                if y.variableID == id {
                    continue
                }
                store.bindings[id] = y
                bindings.append(id)
                continue
            }
            if let id = y.variableID {
                store.bindings[id] = x
                bindings.append(id)
                continue
            }
            switch (x, y) {
                case (.integer(let a), .integer(let b)) where a == b: break
                case (.atom(let a), .atom(let b)) where a == b: break
                case (.compound(let a, let xs), .compound(let b, let ys)) where a == b && xs.count == ys.count:
                for i in xs.indices.reversed() {
                    pending.append((xs[i], ys[i]))
                }
                default: return false
            }
        }
        return true
    }
}
func identical(_ a: Term, _ b: Term, _ store: Store) -> Bool {
    var pending = [(a, b)]
    while let pair = pending.popLast() {
        switch (store.dereference(pair.0), store.dereference(pair.1)) {
            case (.variable(let a), .variable(let b)) where a == b: break
            case (.integer(let a), .integer(let b)) where a == b: break
            case (.atom(let a), .atom(let b)) where a == b: break
            case (.compound(let a, let xs), .compound(let b, let ys)) where a == b && xs.count == ys.count:
            for i in xs.indices.reversed() {
                pending.append((xs[i], ys[i]))
            }
            default: return false
        }
    }
    return true
}
