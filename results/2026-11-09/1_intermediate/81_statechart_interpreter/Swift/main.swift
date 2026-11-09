import Foundation

struct Reference: Error {
    let reason: String
}

struct Evaluation: Error {
}

struct Expr {
    let op: String
    let text: String
    let args: [Expr]

    init(_ op: String, _ text: String = "", _ args: [Expr] = []) {
        self.op = op
        self.text = text
        self.args = args
    }
}

func part(_ text: String, _ start: Int, _ end: Int? = nil) -> String {
    String(decoding: Array(text.utf8)[start..<(end ?? text.utf8.count)], as: UTF8.self)
}

final class Expression {
    var tokens = [String]()
    var at = 0
    let variables: [String: Int]
    let states: [String: Int]

    init(_ text: String, _ variables: [String: Int], _ states: [String: Int]) {
        self.variables = variables
        self.states = states
        let b = Array(text.utf8)
        var i = 0

        func digit(_ c: UInt8) -> Bool {
            c >= 48 && c <= 57
        }

        func letter(_ c: UInt8) -> Bool {
            c >= 65 && c <= 90 || c >= 97 && c <= 122
        }
        while i < b.count {
            if b[i] == 32 {
                i += 1
                continue
            }
            let start = i
            if digit(b[i]) {
                while i < b.count && digit(b[i]) {
                    i += 1
                }
            } else if letter(b[i]) || b[i] == 95 {
                while i < b.count && (letter(b[i]) || digit(b[i]) || b[i] == 95) {
                    i += 1
                }
            } else {
                i += 1
                if i < b.count && ["||", "&&", "==", "!=", "<=", ">="].contains(String(decoding: b[start...i], as: UTF8.self)) {
                    i += 1
                }
            }
            tokens.append(String(decoding: b[start..<i], as: UTF8.self))
        }
    }

    func parse(_ level: Int = 0) throws -> Expr {
        if level == 5 {
            let t = tokens[at]
            at += 1
            if t == "!" || t == "-" {
                return Expr("unary" + t, "", [try parse(5)])
            }
            if t == "(" {
                let e = try parse()
                at += 1
                return e
            }
            if t.utf8.first! >= 48 && t.utf8.first! <= 57 {
                return Expr("number", t)
            }
            if t == "in" {
                at += 1
                let name = tokens[at]
                at += 2
                if states[name] == nil {
                    throw Reference(reason: "unknown state \(name)")
                }
                return Expr("in", name)
            }
            if t != "_data" && variables[t] == nil {
                throw Reference(reason: "unknown variable \(t)")
            }
            return Expr("variable", t)
        }
        let operators: [String]
        switch level {
        case 0:
            operators = ["||"]
        case 1:
            operators = ["&&"]
        case 2:
            operators = ["==", "!=", "<", "<=", ">", ">="]
        case 3:
            operators = ["+", "-"]
        default:
            operators = ["*", "/", "%"]
        }
        var left = try parse(level + 1)
        while at < tokens.count && operators.contains(tokens[at]) {
            let op = tokens[at]
            at += 1
            left = Expr(op, "", [left, try parse(level + 1)])
        }
        return left
    }
}

struct Action {
    var kind: String
    var name = ""
    var expr: Expr?
    var text: String?
    var delay = 0

    init(_ kind: String) {
        self.kind = kind
    }
}

final class State {
    let id: String
    let kind: String
    let parent: Int
    var initialName: String?
    var deep = false
    var defaultName: String?
    var children = [Int]()
    var entries = [[Action]]()
    var exits = [[Action]]()
    var transitions = [Int]()
    var depth = 0
    var initial = -1
    var fallback = -1
    var history: [Int]?
    var entered = 0
    var taken = 0
    var dwell = 0
    var entryTime = 0

    init(_ id: String, _ kind: String, _ parent: Int) {
        self.id = id
        self.kind = kind
        self.parent = parent
    }
}

struct Transition {
    let source: Int
    let trigger: String
    let descriptors: [String]
    let delay: Int
    let guardExpr: Expr?
    let target: Int?
    let mode: String
    let actions: [Action]
}

struct Definition {
    let line: Int
    let text: String
    let node: Int?
}

struct Event {
    let name: String
    var value = 0
}

struct Reservation {
    let due: Int
    let creation: Int
    let transition: Int?
    let event: Event?
}

struct Trigger {
    let kind: String
    var event: Event?
    var transition: Int?

    init(_ kind: String, _ event: Event? = nil, _ transition: Int? = nil) {
        self.kind = kind
        self.event = event
        self.transition = transition
    }
}

struct Selected {
    let transition: Int
    let scope: Int?
    let exits: Set<Int>
}

final class Chart {
    var output = [String]()
    var states = [State("", "root", -1)]
    var ids = [String: Int]()
    var variables = [String: Int]()
    var transitions = [Transition]()
    var document = [Int]()
    var active = Set<Int>()
    var queue = [Event]()
    var reservations = [Reservation]()
    var time = 0
    var data = 0
    var trace = false
    var halted = false
    var macros = 0
    var micros = 0
    var creation = 0

    func children(_ i: Int) -> [Int] {
        states[i].children.filter {
            states[$0].kind != "history"
        }
    }

    func compound(_ i: Int) -> Bool {
        i == 0 || states[i].kind == "state" && !children(i).isEmpty
    }

    func parallel(_ i: Int) -> Bool {
        states[i].kind == "parallel" && !children(i).isEmpty
    }

    func atomic(_ i: Int) -> Bool {
        states[i].kind != "history" && children(i).isEmpty
    }

    func descendant(_ child: Int, _ ancestor: Int) -> Bool {
        var p = states[child].parent
        while p >= 0 {
            if p == ancestor {
                return true
            }
            p = states[p].parent
        }
        return false
    }

    func expression(_ text: String) throws -> Expr {
        try Expression(text, variables, ids).parse()
    }

    func actions(_ text: String) throws -> [Action] {
        try text.components(separatedBy: "; ").map {
            raw -> Action in
            let w = raw.components(separatedBy: " ")
            var a = Action(w[0])
            switch w[0] {
            case "raise":
                a.name = w[1]
                if w.count > 2 {
                    a.expr = try expression(w.dropFirst(2).joined(separator: " "))
                }
            case "send":
                a.name = w[1]
                a.delay = Int(w[2])!
                if w.count > 3 {
                    a.expr = try expression(w.dropFirst(3).joined(separator: " "))
                }
            case "cancel":
                a.name = w[1]
            case "log":
                let rest = part(raw, 4)
                if rest.hasPrefix("\"") {
                    let end = Array(rest.utf8).dropFirst().firstIndex(of: 34)!
                    a.text = part(rest, 1, end)
                    if end + 1 < rest.count {
                        a.expr = try expression(part(rest, end + 2))
                    }
                } else {
                    a.expr = try expression(rest)
                }
            default:
                if variables[w[0]] == nil {
                    throw Reference(reason: "unknown variable \(w[0])")
                }
                a.kind = "assign"
                a.name = w[0]
                a.expr = try expression(w.dropFirst(2).joined(separator: " "))
            }
            return a
        }
    }

    func definition(_ d: Definition) throws {
        let w = d.text.components(separatedBy: " ")
        if w[0] == "state", let i = d.node, let name = states[i].initialName {
            guard let child = ids[name] else {
                throw Reference(reason: "unknown state \(name)")
            }
            if states[child].parent != i || states[child].kind == "history" {
                throw Reference(reason: "\(name) is not a child of \(states[i].id)")
            }
        }
        if w[0] == "final" || w[0] == "history" {
            let s = states[d.node!]
            let p = states[s.parent]
            if p.kind != "state" || children(s.parent).isEmpty {
                throw Reference(reason: "\(s.id) needs a compound parent")
            }
            if let name = s.defaultName {
                guard let target = ids[name] else {
                    throw Reference(reason: "unknown state \(name)")
                }
                if !descendant(target, s.parent) || states[target].kind == "history" {
                    throw Reference(reason: "\(name) is not a descendant of \(p.id)")
                }
            }
        }
        if w[0] == "entry" || w[0] == "exit" {
            guard let i = ids[w[1]] else {
                throw Reference(reason: "unknown state \(w[1])")
            }
            if states[i].kind == "history" {
                throw Reference(reason: "\(w[1]) cannot have actions")
            }
            let range = d.text.range(of: " / ")!
            let a = try actions(String(d.text[range.upperBound...]))
            if w[0] == "entry" {
                states[i].entries.append(a)
            } else {
                states[i].exits.append(a)
            }
        }
        if w[0] == "on" {
            guard let source = ids[w[1]] else {
                throw Reference(reason: "unknown state \(w[1])")
            }
            if ["final", "history"].contains(states[source].kind) {
                throw Reference(reason: "\(w[1]) cannot have transitions")
            }
            var rest = part(d.text, 4 + w[1].count)
            let trigger: String
            var delay = 0
            var descriptors = [String]()
            if rest.hasPrefix("after ") {
                rest = part(rest, 6)
                let word = rest.components(separatedBy: " ")[0]
                delay = Int(word)!
                rest = String(rest.dropFirst(word.count).drop {
                    $0 == " "
                })
                trigger = "timer"
            } else {
                let word = rest.components(separatedBy: " ")[0]
                rest = String(rest.dropFirst(word.count).drop {
                    $0 == " "
                })
                trigger = word == "always" ? "always" : "event"
                if trigger == "event" {
                    descriptors = word.components(separatedBy: "|")
                }
            }
            var guardExpr: Expr?
            if rest.hasPrefix("[") {
                let end = Array(rest.utf8).firstIndex(of: 93)!
                guardExpr = try expression(part(rest, 1, end))
                rest = String(rest.dropFirst(end + 1).drop {
                    $0 == " "
                })
            }
            var target: Int?
            var mode = "internal"
            if rest.hasPrefix("-> ") || rest.hasPrefix("~> ") {
                mode = rest.hasPrefix("-") ? "external" : "local"
                rest = part(rest, 3)
                let name = rest.components(separatedBy: " ")[0]
                guard let i = ids[name] else {
                    throw Reference(reason: "unknown state \(name)")
                }
                target = i
                rest = String(rest.dropFirst(name.count).drop {
                    $0 == " "
                })
            }
            let a: [Action]
            if rest.hasPrefix("/ ") {
                a = try actions(part(rest, 2))
            } else {
                a = []
            }
            states[source].transitions.append(transitions.count)
            transitions.append(Transition(source: source, trigger: trigger, descriptors: descriptors, delay: delay, guardExpr: guardExpr, target: target, mode: mode, actions: a))
        }
    }

    func define(_ lines: [(Int, String)]) -> Bool {
        var errors = [Int: String]()
        var definitions = [Definition]()
        for (line, text) in lines {
            let w = text.components(separatedBy: " ")
            var node: Int?
            if ["state", "parallel", "final", "history"].contains(w[0]) {
                let parentName: String? = w.count > 2 && w[2] != "initial" ? w[2] : nil
                var reason: String?
                if ids[w[1]] != nil {
                    reason = "duplicate state \(w[1])"
                } else if let p = parentName, ids[p] == nil {
                    reason = "unknown state \(p)"
                } else if let p = parentName, ["final", "history"].contains(states[ids[p]!].kind) {
                    reason = "\(p) cannot have children"
                }
                if let reason = reason {
                    errors[line] = reason
                } else {
                    let parent = parentName.map {
                        ids[$0]!
                    } ?? 0
                    let s = State(w[1], w[0], parent)
                    if let at = w.firstIndex(of: "initial") {
                        s.initialName = w[at + 1]
                    }
                    s.deep = w[0] == "history" && w[3] == "deep"
                    if w[0] == "history" && w.count == 5 {
                        s.defaultName = w[4]
                    }
                    s.depth = states[parent].depth + 1
                    let i = states.count
                    node = i
                    ids[s.id] = i
                    states.append(s)
                    states[parent].children.append(i)
                }
            } else if w[0] == "var" {
                if variables[w[1]] != nil {
                    errors[line] = "duplicate variable \(w[1])"
                } else {
                    variables[w[1]] = Int(w[2])!
                }
            }
            definitions.append(Definition(line: line, text: text, node: node))
        }
        for d in definitions where errors[d.line] == nil {
            do {
                try definition(d)
            } catch let e as Reference {
                errors[d.line] = e.reason
            } catch {
            }
        }
        if !errors.isEmpty {
            for line in errors.keys.sorted() {
                output.append("error line \(line): \(errors[line]!)")
            }
            return false
        }
        for i in states.indices {
            if compound(i) {
                states[i].initial = states[i].initialName.map {
                    ids[$0]!
                } ?? children(i)[0]
            }
            if states[i].kind == "history" {
                states[i].fallback = states[i].defaultName.map {
                    ids[$0]!
                } ?? states[states[i].parent].initial
            }
        }

        func visit(_ i: Int) {
            document.append(i)
            for c in states[i].children {
                visit(c)
            }
        }
        for i in states[0].children {
            visit(i)
        }
        return true
    }

    func warnings() {
        var reached: Set<Int> = [states[0].initial]
        while true {
            let before = reached.count
            for i in Array(reached) {
                if states[i].parent != 0 {
                    reached.insert(states[i].parent)
                }
                if compound(i) {
                    reached.insert(states[i].initial)
                }
                if parallel(i) {
                    reached.formUnion(children(i))
                }
                for index in states[i].transitions {
                    if let t = transitions[index].target {
                        reached.insert(states[t].kind == "history" ? states[t].fallback : t)
                    }
                }
            }
            if before == reached.count {
                break
            }
        }
        for i in document where states[i].kind != "history" && !reached.contains(i) {
            output.append("warning: unreachable state \(states[i].id)")
        }
    }

    func evaluate(_ e: Expr) throws -> Int {
        if e.op == "number" {
            return Int(e.text)!
        }
        if e.op == "variable" {
            return e.text == "_data" ? data : variables[e.text]!
        }
        if e.op == "in" {
            return active.contains(ids[e.text]!) ? 1 : 0
        }
        let a = try evaluate(e.args[0])
        if e.op == "unary!" {
            return a == 0 ? 1 : 0
        }
        if e.op == "unary-" {
            return -a
        }
        if e.op == "&&" && a == 0 {
            return 0
        }
        if e.op == "||" && a != 0 {
            return 1
        }
        let b = try evaluate(e.args[1])
        if (e.op == "/" || e.op == "%") && b == 0 {
            throw Evaluation()
        }
        switch e.op {
        case "+":
            return a + b
        case "-":
            return a - b
        case "*":
            return a * b
        case "/":
            return a / b
        case "%":
            return a % b
        case "==":
            return a == b ? 1 : 0
        case "!=":
            return a != b ? 1 : 0
        case "<":
            return a < b ? 1 : 0
        case "<=":
            return a <= b ? 1 : 0
        case ">":
            return a > b ? 1 : 0
        case ">=":
            return a >= b ? 1 : 0
        default:
            return b != 0 ? 1 : 0
        }
    }

    func reserve(_ transition: Int?, _ event: Event?, _ delay: Int) {
        creation += 1
        reservations.append(Reservation(due: time + delay, creation: creation, transition: transition, event: event))
    }

    func runActions(_ actions: [Action]) {
        for a in actions {
            do {
                let v = try a.expr.map {
                    try evaluate($0)
                } ?? 0
                switch a.kind {
                case "assign":
                    variables[a.name] = v
                case "raise":
                    queue.append(Event(name: a.name, value: v))
                case "send":
                    reserve(nil, Event(name: a.name, value: v), a.delay)
                case "cancel":
                    reservations.removeAll {
                        $0.event?.name == a.name
                    }
                case "log":
                    output.append((a.text ?? "") + (a.expr == nil ? "" : String(v)))
                default:
                    break
                }
            } catch {
                queue.append(Event(name: "error.execution"))
                break
            }
        }
    }

    func effective(_ t: Transition) -> [Int] {
        guard let i = t.target else {
            return []
        }
        return states[i].kind == "history" ? states[i].history ?? [states[i].fallback] : [i]
    }

    func scope(_ t: Transition) -> Int? {
        if t.target == nil {
            return nil
        }
        let targets = effective(t)
        if t.mode == "local" && compound(t.source) && targets.allSatisfy( {
            descendant($0, t.source)
        }) {
            return t.source
        }
        var p = states[t.source].parent
        while !(compound(p) && targets.allSatisfy {
            descendant($0, p)
        }) {
            p = states[p].parent
        }
        return p
    }

    func matches(_ t: Transition, _ trigger: Trigger, _ index: Int) -> Bool {
        if trigger.kind == "always" {
            return t.trigger == "always"
        }
        if trigger.kind == "timer" {
            return index == trigger.transition
        }
        let name = trigger.event!.name
        return t.trigger == "event" && t.descriptors.contains {
            $0 == "*" || $0 == name || name.hasPrefix($0 + ".")
        }
    }

    func select(_ trigger: Trigger) -> [Selected] {
        var candidates = [Int]()
        var seen = Set<Int>()
        for leaf in document where active.contains(leaf) && atomic(leaf) {
            var source = leaf
            var chosen: Int?
            while source != 0 && chosen == nil {
                for index in states[source].transitions {
                    let t = transitions[index]
                    if !matches(t, trigger, index) {
                        continue
                    }
                    let enabled: Bool
                    do {
                        enabled = try t.guardExpr.map {
                            try evaluate($0) != 0
                        } ?? true
                    } catch {
                        queue.append(Event(name: "error.execution"))
                        enabled = false
                    }
                    if enabled {
                        chosen = index
                        break
                    }
                }
                source = states[source].parent
            }
            if let i = chosen, seen.insert(i).inserted {
                candidates.append(i)
            }
        }
        var occupied = Set<Int>()
        var result = [Selected]()
        for i in candidates {
            let p = scope(transitions[i])
            let exits = p.map {
                parent in Set(active.filter {
                    descendant($0, parent)
                })
            } ?? []
            if exits.isDisjoint(with: occupied) {
                result.append(Selected(transition: i, scope: p, exits: exits))
                occupied.formUnion(exits)
            }
        }
        return result
    }

    func expand(_ entries: inout Set<Int>) {
        while true {
            let before = entries.count
            for i in Array(entries) {
                if parallel(i) {
                    entries.formUnion(children(i))
                }
                if compound(i) && !children(i).contains(where: {
                    entries.contains($0)
                }) {
                    entries.insert(states[i].initial)
                }
            }
            if entries.count == before {
                return
            }
        }
    }

    func complete(_ i: Int) -> Bool {
        if compound(i) {
            return children(i).contains {
                states[$0].kind == "final" && active.contains($0)
            }
        }
        return parallel(i) && children(i).allSatisfy(complete)
    }

    func enter(_ entries: Set<Int>) {
        for i in document where entries.contains(i) {
            let s = states[i]
            active.insert(i)
            s.entered += 1
            s.entryTime = time
            for index in s.transitions where transitions[index].trigger == "timer" {
                reserve(index, nil, transitions[index].delay)
            }
            for a in s.entries {
                runActions(a)
            }
            if s.kind == "final" {
                let p = s.parent
                queue.append(Event(name: "done.state." + states[p].id))
                let g = states[p].parent
                if g >= 0 && parallel(g) && children(g).allSatisfy(complete) {
                    queue.append(Event(name: "done.state." + states[g].id))
                }
            }
        }
    }

    func list(_ values: [Int]) -> String {
        values.isEmpty ? "-" : values.map {
            states[$0].id
        }.joined(separator: ",")
    }

    func display(_ trigger: Trigger) -> String {
        if trigger.kind == "always" {
            return "always"
        }
        if trigger.kind == "timer" {
            let t = transitions[trigger.transition!]
            return "after(\(t.delay))@\(states[t.source].id)"
        }
        let e = trigger.event!
        return e.name + (e.value == 0 ? "" : "=\(e.value)")
    }

    func micro(_ selected: [Selected], _ trigger: Trigger) {
        let exits = Set(selected.flatMap {
            $0.exits
        })
        for i in document where states[i].kind == "history" && exits.contains(states[i].parent) {
            let p = states[i].parent
            states[i].history = document.filter {
                active.contains($0) && (states[i].deep ? atomic($0) && descendant($0, p) : states[$0].parent == p && states[$0].kind != "history")
            }
        }
        var entries = Set<Int>()
        for choice in selected {
            if let p = choice.scope {
                for target in effective(transitions[choice.transition]) {
                    var i = target
                    while i != p {
                        entries.insert(i)
                        i = states[i].parent
                    }
                }
            }
        }
        expand(&entries)
        if trace {
            output.append("[t=\(time)] \(display(trigger)) (\(list(selected.map { transitions[$0.transition].source }))): exit \(list(document.reversed().filter { exits.contains($0) })); enter \(list(document.filter { entries.contains($0) }))")
        }
        for i in document.reversed() where exits.contains(i) {
            let s = states[i]
            for a in s.exits {
                runActions(a)
            }
            active.remove(i)
            s.dwell += time - s.entryTime
            reservations.removeAll {
                $0.transition.map {
                    transitions[$0].source == i
                } ?? false
            }
        }
        for choice in selected {
            let t = transitions[choice.transition]
            runActions(t.actions)
            states[t.source].taken += 1
        }
        enter(entries)
    }

    func macrostep(_ trigger: Trigger) {
        macros += 1
        var count = 0

        func perform(_ selected: [Selected], _ trigger: Trigger) -> Bool {
            if selected.isEmpty {
                return true
            }
            if count == 1000 {
                output.append("LIVELOCK t=\(time)")
                halted = true
                return false
            }
            count += 1
            micros += 1
            micro(selected, trigger)
            return true
        }
        if trigger.kind == "start" {
            data = 0
            var entries: Set<Int> = [states[0].initial]
            expand(&entries)
            enter(entries)
        } else {
            data = trigger.event?.value ?? 0
            if !perform(select(trigger), trigger) {
                return
            }
        }
        while true {
            data = 0
            let always = Trigger("always")
            let selected = select(always)
            if !selected.isEmpty {
                if !perform(selected, always) {
                    return
                }
                continue
            }
            if queue.isEmpty {
                return
            }
            let event = queue.removeFirst()
            data = event.value
            let next = Trigger("event", event)
            if !perform(select(next), next) {
                return
            }
        }
    }

    func script(_ line: String) {
        if halted {
            return
        }
        let w = line.components(separatedBy: " ")
        switch w[0] {
        case "event":
            macrostep(Trigger("event", Event(name: w[1], value: w.count == 3 ? Int(w[2])! : 0)))
        case "tick":
            let finish = time + Int(w[1])!
            while !halted {
                guard let r = reservations.filter( {
                    $0.due <= finish
                }).min(by: {
                    ($0.due, $0.creation) < ($1.due, $1.creation)
                }) else {
                    break
                }
                reservations.removeAll {
                    $0.creation == r.creation
                }
                time = r.due
                if let t = r.transition {
                    macrostep(Trigger("timer", nil, t))
                } else {
                    macrostep(Trigger("event", r.event))
                }
            }
            if !halted {
                time = finish
            }
        case "set":
            if variables[w[1]] != nil {
                variables[w[1]] = Int(w[2])!
            } else {
                output.append("error: unknown variable \(w[1])")
            }
        case "trace":
            trace = w[1] == "on"
        case "eval":
            let text = part(line, 5)
            do {
                let e = try expression(text)
                data = 0
                do {
                    output.append("\(text) -> \(try evaluate(e))")
                } catch {
                    output.append("error: division by zero")
                }
            } catch let e as Reference {
                output.append("error: \(e.reason)")
            } catch {
            }
        case "dump":
            output.append("dump t=\(time)")
            for i in document where active.contains(i) {
                output.append(String(repeating: "  ", count: states[i].depth) + states[i].id)
            }
            for name in variables.keys.sorted() {
                output.append("  var \(name) = \(variables[name]!)")
            }
            for i in document {
                if let h = states[i].history {
                    output.append("  history \(states[i].id) = \(list(h))")
                }
            }
            for r in reservations.sorted(by: {
                ($0.due, $0.creation) < ($1.due, $1.creation)
            }) {
                if let i = r.transition {
                    let t = transitions[i]
                    output.append("  timer \(r.due) after(\(t.delay))@\(states[t.source].id)")
                } else {
                    output.append("  send \(r.due) \(r.event!.name) \(r.event!.value)")
                }
            }
        default:
            break
        }
    }

    func statistics() {
        output.append("end t=\(time) macrosteps=\(macros) microsteps=\(micros)")
        for i in document where states[i].kind != "history" {
            let s = states[i]
            let dwell = s.dwell + (active.contains(i) ? time - s.entryTime : 0)
            output.append("  \(s.id) entered=\(s.entered) taken=\(s.taken) time=\(dwell)")
        }
    }
}
var lines = [String]()
while let line = readLine() {
    lines.append(line)
}
var at = 1
for _ in 0..<Int(lines[0])! {
    print("chart " + String(lines[at].dropFirst(6)))
    at += 1
    var definitions = [(Int, String)]()
    while lines[at] != "RUN" {
        definitions.append((at + 1, lines[at]))
        at += 1
    }
    at += 1
    var scripts = [String]()
    while lines[at] != "END" {
        scripts.append(lines[at])
        at += 1
    }
    at += 1
    let chart = Chart()
    if chart.define(definitions) {
        chart.warnings()
        chart.macrostep(Trigger("start"))
        for line in scripts {
            chart.script(line)
        }
        chart.statistics()
    }
    for line in chart.output {
        print(line)
    }
}
