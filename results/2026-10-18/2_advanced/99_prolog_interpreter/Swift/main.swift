import Foundation
final class Writer {
    let store: Store
    let quoted: Bool
    var names: [Int: String] = [:]
    var generated = 0
    init(_ store: Store, _ quoted: Bool) {
        self.store = store;
        self.quoted = quoted
    }
    func atom(_ name: String) -> String {
        let bytes = Array(name.utf8)
        let plain = (!bytes.isEmpty && lower(bytes[0]) && bytes.allSatisfy {
            alpha($0) || digit($0) || $0 == 95
        }) ||
        (!bytes.isEmpty && name != "." && bytes.allSatisfy(symbol)) || ["[]", "!", ";"].contains(name)
        if !quoted || plain {
            return name
        }
        return "'" + name.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "'", with: "\\'")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\t", with: "\\t") + "'"
    }
    func term(_ source: Term, _ limit: Int = 1200, _ operand: Bool = false) -> String {
        switch store.dereference(source) {
            case .integer(let n): return String(n)
            case .variable(let id):
            if names[id] == nil {
                generated += 1;
                names[id] = "_G\(generated)"
            }
            return names[id]!
            case .atom(let name):
            let text = atom(name)
            return operand && isOperator(name) ? "(\(text))" : text
            case .compound(let name, let args):
            if name == "." && args.count == 2 {
                let (elements, tail) = store.parts(.compound(name, args))
                var text = "[" + elements.map {
                    term($0, 999)
                }.joined(separator: ",")
                if case .atom("[]") = tail {
                } else {
                    text += "|" + term(tail, 999)
                }
                return text + "]"
            }
            if args.count == 2, let (p, left, right) = infix(name) {
                let a = term(args[0], left, true)
                let b = term(args[1], right, true)
                let text: String
                if name == "," {
                    text = a + "," + b
                }
                else if alpha(name.utf8.first!) {
                    text = a + " " + name + " " + b
                }
                else {
                    let before = a.utf8.last.map(symbol) ?? false
                    let after = b.utf8.first.map(symbol) ?? false
                    text = a + (before ? " " : "") + name + (after ? " " : "") + b
                }
                return p > limit ? "(\(text))" : text
            }
            if args.count == 1, let p = prefix(name) {
                let argument = term(args[0], p, true)
                let space = argument.utf8.first.map {
                    symbol($0) || digit($0) || $0 == 40
                } ?? false
                let text = name + (space ? " " : "") + argument
                return p > limit ? "(\(text))" : text
            }
            return atom(name) + "(" + args.map {
                term($0, 999)
            }.joined(separator: ",") + ")"
        }
    }
}
func writeTerm(_ term: Term, _ store: Store, _ quoted: Bool = true) -> String {
    Writer(store, quoted).term(term)
}
func indicatorText(_ key: Indicator) -> String {
    writeTerm(indicatorTerm(key), Store())
}
func goalConversion(_ term: Term, _ store: Store) -> Term? {
    switch store.dereference(term) {
        case .variable(let id): return .compound("call", [.variable(id)])
        case .integer: return nil
        case .compound(let name, let args) where [",", ";", "->"].contains(name) && args.count == 2:
        guard let left = goalConversion(args[0], store), let right = goalConversion(args[1], store) else {
            return nil
        }
        return .compound(name, [left, right])
        case let value: return value
    }
}
final class Consult {
    let database = Database()
    let store = Store()
    var reports: [String] = []
    var counts = [[0, 0, 0], [0, 0, 0]]
    func warning(_ file: Int, _ line: Int, _ message: String) {
        counts[file][2] += 1
        reports.append("\(file == 0 ? "prelude.pl" : "program.pl"):\(line): warning: \(message)")
    }
    func read(_ file: Int, _ text: String) {
        let name = file == 0 ? "prelude.pl" : "program.pl"
        let tokens = lex(text, 1)
        let source = text.components(separatedBy: "\n")
        var start = 0
        var last: Int?
        var discontiguous: Set<Int> = []
        while tokens[start].kind != "eof" {
            let line = tokens[start].line
            let parsed: Parsed
            do {
                parsed = try Reader(tokens, start, store).clause()
            }
            catch let error as ReadError {
                counts[file][1] += 1
                reports.append("\(name):\(error.line):\(error.column): syntax error: \(error.message)")
                if !error.eof {
                    reports.append("    " + source[error.line - 1])
                    reports.append(String(repeating: " ", count: error.column + 3) + "^")
                }
                start = error.index
                while tokens[start].kind != "eof" && tokens[start].kind != "end" {
                    start += 1
                }
                if tokens[start].kind == "end" {
                    start += 1
                }
                continue
            } catch {
                preconditionFailure()
            }
            start = parsed.next
            let head: Term
            let body: Term?
            if case .compound(":-", let args) = parsed.term, args.count == 2 {
                head = args[0];
                body = args[1]
            }
            else {
                head = parsed.term;
                body = nil
            }
            var error: Term?
            if head.variableID != nil {
                error = .atom("instantiation_error")
            }
            if case .integer = head {
                error = typeError("callable", head)
            }
            let key = head.indicator
            if error == nil, let key = key, control(key) || builtin(key) {
                error = .compound("permission_error", [.atom("modify"), .atom("static_procedure"), indicatorTerm(key)])
            }
            let converted = body.flatMap {
                goalConversion($0, store)
            }
            if error == nil && body != nil && converted == nil {
                error = typeError("callable", body!)
            }
            if let error = error {
                counts[file][1] += 1
                reports.append("\(name):\(line): error: \(writeTerm(error, store))")
                continue
            }
            let indicator = key!
            let index: Int
            if let found = database.find(indicator) {
                index = found
            }
            else {
                index = database.predicates.count;
                database.predicates.append(Predicate(indicator: indicator))
            }
            if file == 1 && database.predicates[index].clauses.contains(where: {
                $0.file == "prelude.pl"
            }) {
                warning(file, line, "redefining prelude procedure " + indicatorText(indicator))
                database.predicates[index].clauses.removeAll()
            }
            if database.predicates[index].clauses.contains(where: {
                $0.file == name
            }) && last != index && discontiguous.insert(index).inserted {
                warning(file, line, "clauses of \(indicatorText(indicator)) are not together")
            }
            database.predicates[index].clauses.append(Clause(head: head, body: converted, file: name, line: line))
            last = index
            counts[file][0] += 1
            let singletons = parsed.variables.filter {
                !$0.name.hasPrefix("_") && $0.count == 1
            }.map(\.name)
            if !singletons.isEmpty {
                warning(file, line, "singleton variables: " + singletons.joined(separator: ", "))
            }
            let repeated = parsed.variables.filter {
                $0.name.hasPrefix("_") && $0.name.count > 1 && $0.count >= 2
            }.map(\.name)
            if !repeated.isEmpty {
                warning(file, line, "variables starting with _ occur more than once: " + repeated.joined(separator: ", "))
            }
        }
    }
    func undefined() {
        func visit(_ term: Term, _ result: inout [Indicator]) {
            guard let key = term.indicator else {
                return
            }
            let args = term.arguments
            if [",", ";", "->"].contains(key.name) && key.arity == 2 {
                visit(args[0], &result);
                visit(args[1], &result)
            } else if ["\\+", "call"].contains(key.name) && key.arity == 1 {
                visit(args[0], &result)
            }
            else if key == Indicator(name: "findall", arity: 3) {
                visit(args[1], &result)
            }
            else if key == Indicator(name: "catch", arity: 3) {
                visit(args[0], &result);
                visit(args[2], &result)
            }
            else if !control(key) && !builtin(key) {
                result.append(key)
            }
        }
        var warnings: [(Int, Int, String)] = []
        var reported: Set<Indicator> = []
        for predicate in database.predicates {
            for clause in predicate.clauses {
                if let body = clause.body {
                    var indicators: [Indicator] = []
                    visit(body, &indicators)
                    for key in indicators where database.find(key) == nil && reported.insert(key).inserted {
                        warnings.append((clause.file == "prelude.pl" ? 0 : 1, clause.line,
                        "undefined procedure \(indicatorText(key)) called from \(indicatorText(predicate.indicator))"))
                    }
                }
            }
        }
        for (file, line, message) in warnings {
            warning(file, line, message)
        }
        for (i, name) in ["prelude.pl", "program.pl"].enumerated() {
            reports.append("\(name): clauses=\(counts[i][0]) errors=\(counts[i][1]) warnings=\(counts[i][2])")
        }
        reports.append("database: predicates=\(database.predicates.count) clauses=\(database.predicates.reduce(0) { $0 + $1.clauses.count })")
    }
    func listing() -> [String] {
        var output: [String] = []
        for (p, predicate) in database.predicates.enumerated() {
            if p > 0 {
                output.append("")
            }
            for clause in predicate.clauses {
                let variables = store.variables([clause.head] + (clause.body.map {
                    [$0]
                } ?? []))
                var counts: [Int: Int] = [:]
                for id in variables {
                    counts[id, default: 0] += 1
                }
                let writer = Writer(store, true)
                var number = 0
                for id in variables where writer.names[id] == nil {
                    if counts[id] == 1 {
                        writer.names[id] = "_"
                    }
                    else {
                        writer.names[id] = String(UnicodeScalar(65 + number % 26)!) + (number >= 26 ? String(number / 26) : "")
                        number += 1
                    }
                }
                let head = writer.term(clause.head)
                if let body = clause.body {
                    output.append(head + " :-")
                    var goals: [Term] = []
                    var rest = body
                    while case .compound(",", let args) = rest, args.count == 2 {
                        goals.append(args[0]);
                        rest = args[1]
                    }
                    goals.append(rest)
                    for (i, goal) in goals.enumerated() {
                        output.append("    " + writer.term(goal, 999) + (i + 1 == goals.count ? "." : ","))
                    }
                } else {
                    output.append(head + ".")
                }
            }
        }
        return output
    }
}
struct Profile {
    var calls = 0
    var tries = 0
}
enum Goal {
    case term(Term)
    case ite(Int)
    case naf(Int)
    case exit(Choice)
    case collect(Choice)
}
struct Entry {
    let goal: Goal
    let barrier: Int
    let context: Choice?
    static func term(_ term: Term, _ barrier: Int, _ context: Choice?) -> Entry {
        Entry(goal: .term(term), barrier: barrier, context: context)
    }
}
final class Goals {
    let entry: Entry
    let next: Goals?
    init(_ entry: Entry, _ next: Goals?) {
        self.entry = entry;
        self.next = next
    }
}
enum ChoiceKind {
    case alternative
    case clauses(Int, [Int], Int, Term, Int, Choice?)
    case between(Int, Term, Int)
    case length(Term, Term, Int, Int)
    case catcher(Term, Term, Choice?)
    case findall(Term, Term, [Term])
}
final class Choice {
    let mark: Int
    let resume: Goals?
    var kind: ChoiceKind
    init(_ mark: Int, _ resume: Goals?, _ kind: ChoiceKind) {
        self.mark = mark;
        self.resume = resume;
        self.kind = kind
    }
}
final class Engine {
    let database: Database
    let store: Store
    let trail = Trail()
    var profile: [Indicator: Profile]
    var goals: Goals?
    var choices: [Choice] = []
    var solutions = 0
    var inferences = 0
    var choicepoints = 0
    var backtracks = 0
    var limitReached = false
    var output = ""
    var answers: [String] = []
    init(_ database: Database, _ profile: [Indicator: Profile], _ store: Store, _ query: Term) {
        self.database = database;
        self.profile = profile;
        self.store = store
        goals = Goals(.term(.compound("call", [query]), 0, nil), nil)
    }
    @discardableResult func push(_ kind: ChoiceKind, _ resume: Goals?) -> Choice {
        choicepoints += 1
        let result = Choice(trail.mark, resume, kind)
        choices.append(result)
        return result
    }
    func prepend(_ entries: [Entry]) {
        for entry in entries.reversed() {
            goals = Goals(entry, goals)
        }
    }
    func cut(_ height: Int) {
        if choices.count > height {
            choices.removeLast(choices.count - height)
        }
    }
    func inference(_ key: Indicator) -> Bool {
        if inferences == 20000 {
            limitReached = true;
            return false
        }
        inferences += 1
        profile[key, default: Profile()].calls += 1
        return true
    }
    func unify(_ a: Term, _ b: Term) -> Bool {
        trail.unify(a, b, store)
    }
    func tryClause(_ predicate: Int, _ clause: Int, _ goal: Term, _ barrier: Int, _ context: Choice?, _ resume: Goals?) -> Bool {
        profile[database.predicates[predicate].indicator, default: Profile()].tries += 1
        let (head, body) = database.copy(predicate, clause, store)
        if !unify(head, goal) {
            return false
        }
        goals = resume
        if let body = body {
            goals = Goals(.term(body, barrier, context), goals)
        }
        return true
    }
    func execute(_ entry: Entry) throws -> Bool {
        let barrier = entry.barrier
        let context = entry.context
        let term: Term
        switch entry.goal {
            case .ite(let height): cut(height);
            return true
            case .naf(let height): cut(height);
            return false
            case .exit(let point):
            if choices.last === point {
                choices.removeLast()
            }
            return true
            case .collect(let point):
            guard case .findall(let template, let result, var values) = point.kind else {
                preconditionFailure()
            }
            values.append(store.copy(template))
            point.kind = .findall(template, result, values)
            return false
            case .term(let value): term = store.dereference(value)
        }
        let key = term.indicator!
        let args = term.arguments
        if control(key) {
            switch key.name {
                case ",": prepend([.term(args[0], barrier, context), .term(args[1], barrier, context)])
                case "!": cut(barrier)
                case ";":
                let height = choices.count
                push(.alternative, Goals(.term(args[1], barrier, context), goals))
                let left = store.dereference(args[0])
                if case .compound("->", let branches) = left, branches.count == 2 {
                    prepend([.term(branches[0], height + 1, context), Entry(goal: .ite(height), barrier: barrier, context: context), .term(branches[1], barrier, context)])
                } else {
                    prepend([.term(left, barrier, context)])
                }
                case "->":
                let height = choices.count
                prepend([.term(args[0], height, context), Entry(goal: .ite(height), barrier: barrier, context: context), .term(args[1], barrier, context)])
                case "\\+":
                let height = choices.count
                push(.alternative, goals)
                prepend([.term(.compound("call", [args[0]]), barrier, context), Entry(goal: .naf(height), barrier: barrier, context: context)])
                case "call":
                let first = store.dereference(args[0])
                if first.variableID != nil {
                    throw PrologError(term: errorBall(.atom("instantiation_error"), key))
                }
                if case .integer = first {
                    throw PrologError(term: errorBall(typeError("callable", first), key))
                }
                let applied: Term
                if args.count == 1 {
                    applied = first
                }
                else {
                    switch first {
                        case .atom(let name): applied = .compound(name, Array(args.dropFirst()))
                        case .compound(let name, let values): applied = .compound(name, values + Array(args.dropFirst()))
                        default: preconditionFailure()
                    }
                }
                guard let converted = goalConversion(applied, store) else {
                    throw PrologError(term: errorBall(typeError("callable", applied), key))
                }
                prepend([.term(converted, choices.count, context)])
                case "catch":
                let point = push(.catcher(args[1], args[2], context), goals)
                prepend([.term(.compound("call", [args[0]]), barrier, point), Entry(goal: .exit(point), barrier: barrier, context: context)])
                default: preconditionFailure()
            }
            return true
        }
        if !inference(key) {
            return false
        }
        switch key {
            case Indicator(name: "findall", arity: 3):
            let point = push(.findall(args[0], args[2], []), goals)
            goals = nil
            prepend([.term(.compound("call", [args[1]]), barrier, context), Entry(goal: .collect(point), barrier: barrier, context: context)])
            return true
            case Indicator(name: "throw", arity: 1):
            let ball = store.dereference(args[0])
            throw PrologError(term: ball.variableID == nil ? ball : errorBall(.atom("instantiation_error"), key))
            case Indicator(name: "between", arity: 3):
            do {
                let low = try integer(args[0], store)
                let high = try integer(args[1], store)
                let variable = store.dereference(args[2])
                if case .integer(let n) = variable {
                    return low <= n && n <= high
                }
                if variable.variableID == nil {
                    throw PrologError(term: typeError("integer", variable))
                }
                if low > high {
                    return false
                }
                if low < high {
                    push(.between(high, variable, low + 1), goals)
                }
                return unify(variable, .integer(low))
            } catch let error as PrologError {
                throw PrologError(term: errorBall(error.term, key))
            }
            case Indicator(name: "length", arity: 2):
            let length = store.dereference(args[1])
            if length.variableID == nil {
                guard case .integer(let n) = length else {
                    throw PrologError(term: errorBall(typeError("integer", length), key))
                }
                if n < 0 {
                    throw PrologError(term: errorBall(domainError("not_less_than_zero", length), key))
                }
            }
            let (elements, tail) = store.parts(args[0])
            let prefix = elements.count
            if case .atom("[]") = tail {
                return unify(args[1], .integer(prefix))
            }
            if tail.variableID == nil {
                throw PrologError(term: errorBall(typeError("list", args[0]), key))
            }
            if case .integer(let n) = length {
                if n < prefix {
                    return false
                }
                return unify(tail, list((0..<(n - prefix)).map {
                    _ in store.fresh()
                }))
            }
            push(.length(tail, length, prefix, prefix + 1), goals)
            return unify(tail, .atom("[]")) && unify(length, .integer(prefix))
            default:
            if builtin(key) {
                do {
                    return try deterministic(key, args, store, trail, &output)
                }
                catch let error as PrologError {
                    throw PrologError(term: errorBall(error.term, key))
                }
            }
            guard let predicate = database.find(key) else {
                throw PrologError(term: errorBall(.compound("existence_error", [.atom("procedure"), indicatorTerm(key)]), key))
            }
            let candidates = database.candidates(predicate, term, store)
            if candidates.isEmpty {
                return false
            }
            let height = choices.count
            let resume = goals
            if candidates.count > 1 {
                push(.clauses(predicate, candidates, 1, term, height, context), resume)
            }
            return tryClause(predicate, candidates[0], term, height, context, resume)
        }
    }
    func backtrack() -> Bool {
        retry: while true {
            backtracks += 1
            while let point = choices.last {
                trail.undo(point.mark, store)
                switch point.kind {
                    case .alternative:
                    choices.removeLast();
                    goals = point.resume;
                    return true
                    case .clauses(let predicate, let candidates, let next, let goal, let barrier, let context):
                    if next + 1 == candidates.count {
                        choices.removeLast()
                    }
                    else {
                        point.kind = .clauses(predicate, candidates, next + 1, goal, barrier, context)
                    }
                    if tryClause(predicate, candidates[next], goal, barrier, context, point.resume) {
                        return true
                    }
                    continue retry
                    case .between(let high, let variable, let next):
                    if !inference(Indicator(name: "between", arity: 3)) {
                        return false
                    }
                    if next == high {
                        choices.removeLast()
                    }
                    else {
                        point.kind = .between(high, variable, next + 1)
                    }
                    if unify(variable, .integer(next)) {
                        goals = point.resume;
                        return true
                    }
                    continue retry
                    case .length(let tail, let length, let prefix, let next):
                    if !inference(Indicator(name: "length", arity: 2)) {
                        return false
                    }
                    point.kind = .length(tail, length, prefix, next + 1)
                    let elements = (0..<(next - prefix)).map {
                        _ in store.fresh()
                    }
                    if unify(tail, list(elements)) && unify(length, .integer(next)) {
                        goals = point.resume;
                        return true
                    }
                    continue retry
                    case .catcher: choices.removeLast()
                    case .findall(_, let result, let values):
                    choices.removeLast()
                    if unify(list(values), result) {
                        goals = point.resume;
                        return true
                    }
                    continue retry
                }
            }
            return false
        }
    }
    func exception(_ original: Term, _ initial: Choice?) -> Bool {
        let ball = store.copy(original)
        var context = initial
        while let point = context {
            guard let index = choices.firstIndex(where: {
                $0 === point
            }), case .catcher(let catcher, let recovery, let parent) = point.kind else {
                preconditionFailure()
            }
            choices.removeLast(choices.count - index)
            trail.undo(point.mark, store)
            let mark = trail.mark
            let copied = store.copy(ball)
            if unify(copied, catcher) {
                goals = point.resume
                prepend([.term(.compound("call", [recovery]), choices.count, parent)])
                return true
            }
            trail.undo(mark, store)
            context = parent
        }
        answers.append("uncaught exception: " + writeTerm(ball, store))
        return false
    }
    func answer(_ source: [Variable]) -> String {
        let variables = source.filter {
            !$0.name.hasPrefix("_")
        }
        let values = variables.map {
            store.dereference($0.term)
        }
        let writer = Writer(store, true)
        for (variable, value) in zip(variables, values) {
            if let id = value.variableID, writer.names[id] == nil {
                writer.names[id] = variable.name
            }
        }
        var items: [String] = []
        for (i, variable) in variables.enumerated() {
            if let id = values[i].variableID {
                if let previous = (0..<i).reversed().first(where: {
                    values[$0].variableID == id
                }) {
                    items.append(variables[previous].name + " = " + variable.name)
                }
            } else {
                items.append(variable.name + " = " + writer.term(values[i], 699, true))
            }
        }
        return items.isEmpty ? "true" : items.joined(separator: ", ")
    }
    func run(_ variables: [Variable], _ limit: Int?) {
        while true {
            guard let current = goals else {
                solutions += 1
                let text = answer(variables)
                if limit == solutions || choices.isEmpty {
                    answers.append(text + ".");
                    return
                }
                answers.append(text + " ;")
                if !backtrack() {
                    answers.append(limitReached ? "inference limit exceeded" : "false.");
                    return
                }
                continue
            }
            goals = current.next
            do {
                if try !execute(current.entry) {
                    if limitReached || !backtrack() {
                        answers.append(limitReached ? "inference limit exceeded" : "false.");
                        return
                    }
                }
            } catch let error as PrologError {
                if !exception(error.term, current.entry.context) {
                    return
                }
            } catch {
                preconditionFailure()
            }
        }
    }
}
func linesText(_ lines: [String]) -> String {
    lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
}
func write(_ name: String, _ text: String) throws {
    try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    try text.write(toFile: "output/" + name, atomically: true, encoding: .utf8)
}
let consult = Consult()
consult.read(0, try String(contentsOfFile: "input/prelude.pl", encoding: .utf8))
consult.read(1, try String(contentsOfFile: "input/program.pl", encoding: .utf8))
consult.undefined()
var answers: [String] = []
var output = ""
var statistics: [String] = []
var totals = [0, 0, 0, 0]
var profile: [Indicator: Profile] = [:]
let queries = try String(contentsOfFile: "input/queries.txt", encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
let queryLines = queries.last == "" ? queries.dropLast() : queries[...]
for (i, source) in queryLines.enumerated() {
    let line = String(source)
    answers.append(line)
    output += "== query \(i + 1) ==\n"
    let at = line.range(of: "?- ")!.lowerBound
    let prefix = String(line[..<at]).trimmingCharacters(in: .whitespaces)
    let limit = prefix.isEmpty ? nil : Int(prefix)
    let start = line.index(at, offsetBy: 3)
    let tokens = lex(String(line[start...]), line.distance(from: line.startIndex, to: start) + 1)
    let store = consult.store.clone()
    do {
        let parsed = try Reader(tokens, 0, store).clause(true)
        let engine = Engine(consult.database, profile, store, parsed.term)
        engine.run(parsed.variables, limit)
        profile = engine.profile
        answers.append(contentsOf: engine.answers)
        output += engine.output
        if !engine.output.isEmpty && !engine.output.hasSuffix("\n") {
            output += "\n"
        }
        statistics.append("query \(i + 1): solutions=\(engine.solutions) inferences=\(engine.inferences) choicepoints=\(engine.choicepoints) backtracks=\(engine.backtracks)")
        totals[0] += engine.solutions;
        totals[1] += engine.inferences
        totals[2] += engine.choicepoints;
        totals[3] += engine.backtracks
    } catch let error as ReadError {
        answers.append("syntax error at column \(error.column): \(error.message)")
        statistics.append("query \(i + 1): syntax error")
    }
}
statistics.append("total: solutions=\(totals[0]) inferences=\(totals[1]) choicepoints=\(totals[2]) backtracks=\(totals[3])")
statistics.append("== profile ==")
let entries = profile.filter {
    $0.value.calls > 0
}.map {
    (indicatorText($0.key), $0.key, $0.value)
}.sorted {
    $0.2.calls != $1.2.calls ? $0.2.calls > $1.2.calls : $0.0 < $1.0
}
for (text, key, counts) in entries {
    statistics.append("\(text) calls=\(counts.calls)" + (consult.database.find(key) != nil ? " tries=\(counts.tries)" : ""))
}
try write("consult.txt", linesText(consult.reports))
try write("listing.txt", linesText(consult.listing()))
try write("answers.txt", linesText(answers))
try write("write_output.txt", output)
try write("stats.txt", linesText(statistics))
