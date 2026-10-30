import Foundation

enum Value: Equatable {
    case integer(Int)
    case string(String)
    case boolean(Bool)
    case bag([String])
    case error(String)

    var reason: String? { if case .error(let reason) = self { return reason }; return nil }
    var boolValue: Bool? { if case .boolean(let value) = self { return value }; return nil }
    var intValue: Int? { if case .integer(let value) = self { return value }; return nil }
    var notation: String {
        switch self {
        case .integer(let value): return String(value)
        case .string(let value): return "\"" + value + "\""
        case .boolean(let value): return value ? "true" : "false"
        case .bag(let values): return "[" + values.map { "\"" + $0 + "\"" }.joined(separator: ",") + "]"
        case .error(let reason): return reason
        }
    }
}

func readLines(_ path: String) throws -> [String] {
    try String(contentsOfFile: path, encoding: .ascii)
        .split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(String.init)
}

func inputValue(_ text: String) -> Value {
    if text == "true" || text == "false" { return .boolean(text == "true") }
    if text.hasPrefix("[") {
        return .bag(text == "[]" ? [] : String(text.dropFirst().dropLast()).components(separatedBy: ","))
    }
    if let integer = Int(text) { return .integer(integer) }
    return .string(text)
}

func attributes(_ fields: ArraySlice<String>) -> [String: Value] {
    Dictionary(uniqueKeysWithValues: fields.map {
        let pair = $0.split(separator: "=", maxSplits: 1)
        return (String(pair[0]), inputValue(String(pair[1])))
    })
}

func booleanResult(_ values: [Value], veto: Bool, operation: String) -> Value {
    let checked = values.map { value -> Value in
        value.boolValue != nil || value.reason != nil ? value : .error("type " + operation)
    }
    if checked.contains(.boolean(veto)) { return .boolean(veto) }
    if let error = checked.first(where: { $0.reason != nil }) { return error }
    return .boolean(!veto)
}

func operation(_ name: String, _ values: [Value]) -> Value {
    if let error = values.first(where: { $0.reason != nil }) { return error }
    if ["+", "-", "*", "<", "<=", ">", ">="].contains(name),
       let left = values[0].intValue, values.count == 1 || values[1].intValue != nil {
        if values.count == 1 { return .integer(-left) }
        let right = values[1].intValue!
        switch name {
        case "+": return .integer(left + right)
        case "-": return .integer(left - right)
        case "*": return .integer(left * right)
        case "<": return .boolean(left < right)
        case "<=": return .boolean(left <= right)
        case ">": return .boolean(left > right)
        default: return .boolean(left >= right)
        }
    }
    if name == "==" || name == "!=" {
        switch (values[0], values[1]) {
        case (.integer, .integer), (.string, .string), (.boolean, .boolean):
            return .boolean(name == "==" ? values[0] == values[1] : values[0] != values[1])
        default: break
        }
    } else if name == "in", case .string(let value) = values[0], case .bag(let bag) = values[1] {
        return .boolean(bag.contains(value))
    } else if name == "not", let value = values[0].boolValue {
        return .boolean(!value)
    } else if name == "starts_with" || name == "^=" {
        if case .string(let left) = values[0], case .string(let right) = values[1] { return .boolean(left.hasPrefix(right)) }
    } else if name == "size", case .bag(let bag) = values[0] { return .integer(bag.count) }
    return .error("type " + name)
}

func expression(_ tree: Expression, values: [String: Value], current: String? = nil) -> Value {
    switch tree {
    case .literal(let value): return value
    case .attribute(let reference): return values[reference] ?? .error("missing " + reference)
    case .current: return .string(current!)
    case .operation(let name, let arguments):
        if name == "present", case .attribute(let reference) = arguments[0] { return .boolean(values[reference] != nil) }
        if name == "any_of" || name == "all_of" {
            let value = expression(arguments[0], values: values, current: current)
            if value.reason != nil { return value }
            guard case .bag(let bag) = value else { return .error("type " + name) }
            let predicates = bag.map { expression(arguments[1], values: values, current: $0) }
            return booleanResult(predicates, veto: name == "any_of", operation: name)
        }
        let operands = arguments.map { expression($0, values: values, current: current) }
        if name == "and" || name == "or" { return booleanResult(operands, veto: name == "or", operation: name) }
        return operation(name, operands)
    }
}

enum TargetKind: String {
    case match = "MATCH"
    case noMatch = "NO_MATCH"
    case indeterminate = "INDETERMINATE"
}

struct TargetResult {
    let kind: TargetKind
    var reason: String? = nil
}

func targetGroup(_ results: [TargetResult], conjunction: Bool) -> TargetResult {
    if conjunction {
        if results.contains(where: { $0.kind == .noMatch }) { return TargetResult(kind: .noMatch) }
        if results.allSatisfy({ $0.kind == .match }) { return TargetResult(kind: .match) }
    } else if results.contains(where: { $0.kind == .match }) { return TargetResult(kind: .match) }
    if let error = results.first(where: { $0.kind == .indeterminate }) { return error }
    return TargetResult(kind: .noMatch)
}

func matchClause(_ clause: MatchClause, values: [String: Value]) -> TargetResult {
    guard let value = values[clause.reference] else {
        return clause.mandatory ? TargetResult(kind: .indeterminate, reason: "missing " + clause.reference)
            : TargetResult(kind: .noMatch)
    }
    let items: [Value]
    if case .bag(let bag) = value { items = bag.map(Value.string) } else { items = [value] }
    let literal = expression(clause.literal, values: values)
    let results = items.map { operation(clause.operation, [$0, literal]) }
    if results.contains(.boolean(true)) { return TargetResult(kind: .match) }
    if let reason = results.compactMap(\.reason).first { return TargetResult(kind: .indeterminate, reason: reason) }
    return TargetResult(kind: .noMatch)
}

final class Evaluation {
    let element: Element
    let target: TargetResult
    var decision = Decision.notApplicable
    var reason: String?
    var decisive: Element?
    var condition: Value?
    var children: [ChildState] = []
    var obligations: [(String, String)] = [], advice: [(String, String)] = []

    init(_ element: Element, target: TargetResult) { self.element = element; self.target = target }
    var notation: String { decision.rawValue + (decision.indeterminate ? " (\(reason!))" : "") }
    var finalNotation: String { notation + (decision.definite ? " by " + decisive!.identifier : "") }
}

final class Evaluator {
    let values: [String: Value]
    var coverage: [String: String] = [:]
    let recordCoverage: Bool

    init(_ values: [String: Value], recordCoverage: Bool = false) {
        self.values = values
        self.recordCoverage = recordCoverage
    }

    func target(_ element: Element) -> TargetResult {
        targetGroup(element.targets.map { line in
            targetGroup(line.map { alternative in
                targetGroup(alternative.map { matchClause($0, values: values) }, conjunction: true)
            }, conjunction: false)
        }, conjunction: true)
    }

    func attachments(_ result: Evaluation, supporters: [Evaluation]) {
        for supporter in supporters {
            result.obligations += supporter.obligations
            result.advice += supporter.advice
        }
        let effect = result.decision
        for (obligatory, definitions) in [(true, result.element.obligations), (false, result.element.advice)] {
            for definition in definitions where definition.effect == effect {
                let evaluated = definition.arguments.map { ($0.0, expression($0.1, values: values)) }
                if let error = evaluated.compactMap({ $0.1.reason }).first {
                    if obligatory {
                        result.decision = effect == .deny ? .indeterminateD : .indeterminateP
                        result.reason = "obligation \(definition.identifier): \(error)"
                        result.decisive = nil
                        result.obligations = []
                        result.advice = []
                        return
                    }
                    continue
                }
                let item = definition.identifier + evaluated.map { " \($0.0)=\($0.1.notation)" }.joined()
                if obligatory { result.obligations.append((definition.identifier, item)) }
                else { result.advice.append((definition.identifier, item)) }
            }
        }
    }

    func rule(_ element: Element, obligations: Bool = true) -> Evaluation {
        let result = Evaluation(element, target: target(element))
        let indeterminate: Decision = element.behavior == "DENY" ? .indeterminateD : .indeterminateP
        if result.target.kind == .indeterminate {
            result.decision = indeterminate
            result.reason = result.target.reason
        } else if result.target.kind == .match {
            var condition = element.condition.map { expression($0, values: values) } ?? .boolean(true)
            if condition.boolValue == nil && condition.reason == nil { condition = .error("type condition") }
            result.condition = condition
            if let reason = condition.reason { result.decision = indeterminate; result.reason = reason }
            else if condition.boolValue! {
                result.decision = Decision(rawValue: element.behavior)!
                result.decisive = element
                if obligations { attachments(result, supporters: []) }
            }
        }
        if recordCoverage {
            coverage[element.identifier] = result.decision == .permit ? "P" : result.decision == .deny ? "D"
                : result.decision == .notApplicable ? "-" : "I"
        }
        return result
    }

    func evaluate(_ element: Element) -> Evaluation {
        if element.kind == "rule" { return rule(element) }
        let result = Evaluation(element, target: target(element))
        if result.target.kind == .noMatch { return result }
        (result.decision, result.reason, result.children) = combine(element.behavior, children: element.children,
                                                                    evaluate: evaluate, target: target)
        if result.target.kind == .indeterminate {
            if result.decision.definite { result.decision = result.decision == .deny ? .indeterminateD : .indeterminateP }
            if result.decision.indeterminate { result.reason = result.target.reason }
        }
        if result.decision.definite {
            let supporters = result.children.compactMap { state -> Evaluation? in
                if case .evaluated(let child) = state, child.decision == result.decision { return child }
                return nil
            }
            result.decisive = supporters.first?.decisive ?? element
            attachments(result, supporters: supporters)
        }
        return result
    }
}

func treeLines(_ result: Evaluation, depth: Int = 0) -> [String] {
    let element = result.element, target = result.target.kind
    let prefix = String(repeating: " ", count: 2 + 2 * depth)
    var line = prefix + "\(element.kind) \(element.identifier) \(element.behavior) target \(target.rawValue)"
    if element.kind == "rule" && target == .match {
        let condition = result.condition!.reason != nil ? "INDETERMINATE" : result.condition!.boolValue! ? "TRUE" : "FALSE"
        line += " condition " + condition
    }
    var lines = [line + " -> " + result.notation]
    if element.kind != "rule" && target != .noMatch {
        for (child, state) in zip(element.children, result.children) {
            switch state {
            case .evaluated(let evaluation): lines += treeLines(evaluation, depth: depth + 1)
            case .skipped: lines.append(prefix + "  \(child.kind) \(child.identifier) skipped")
            case .checked(let checked):
                lines.append(prefix + "  \(child.kind) \(child.identifier) \(child.behavior) target \(checked.kind.rawValue)"
                    + (checked.kind == .indeterminate ? " (\(checked.reason!))" : ""))
            }
        }
    }
    return lines
}

func joinBlocks(_ blocks: [[String]]) -> [String] {
    var result: [String] = []
    for block in blocks { if !result.isEmpty { result.append("") }; result += block }
    return result
}

struct Request {
    let identifier: String
    let user: String
    let roles: String
    let action: String
    let resource: String
    let environment: [String: Value]
    let explain: Bool
}

struct Resource {
    let type: String
    let attributes: [String: Value]
}

struct Activation {
    let role: String
    let reason: String?
}

final class Engine {
    let rbac: RBAC
    let elements: [Element]
    let root: Element
    let rules: [Element]
    var subjects: [String: [String: Value]] = [:]
    var resources: [String: Resource] = [:]
    var domains: [(String, [Value])] = []
    var reference: [String: Value] = [:]
    var requests: [Request] = []
    var coverage: [String: String] = [:]
    var grantCounts: [Grant: Int] = [:]
    var decisions: [String: Int] = [:], decisive: [String: Int] = [:]
    var obligations: [String: Int] = [:], advice: [String: Int] = [:]
    var refused = 0

    init() throws {
        rbac = try RBAC()
        elements = try readPolicies()
        root = elements[0]
        rules = elements.filter { $0.kind == "rule" }
        for line in try readLines("input/attributes.txt") {
            let fields = line.split(separator: " ").map(String.init)
            switch fields[0] {
            case "SUBJECT": subjects[fields[1]] = attributes(fields.dropFirst(2))
            case "RESOURCE": resources[fields[1]] = Resource(type: fields[2], attributes: attributes(fields.dropFirst(3)))
            case "DOMAIN": domains.append((fields[1], fields.dropFirst(2).map(inputValue)))
            default: reference = attributes(fields.dropFirst())
            }
        }
        for line in try readLines("input/requests.txt") {
            var fields = line.split(separator: " ").map(String.init)
            let explain = fields.last == "EXPLAIN"
            if explain { fields.removeLast() }
            requests.append(Request(identifier: fields[0], user: fields[1], roles: fields[2], action: fields[3],
                                    resource: fields[4], environment: attributes(fields.dropFirst(5)), explain: explain))
        }
        for rule in rules { coverage[rule.identifier] = "" }
    }

    func check(_ request: Request) -> String? {
        if subjects[request.user] == nil { return "unknown user " + request.user }
        if resources[request.resource] == nil { return "unknown resource " + request.resource }
        guard let day = request.environment["day"]?.intValue, (1...365).contains(day) else { return "bad day" }
        return nil
    }

    func activate(_ user: String, specification: String, day: Int) -> ([Activation], [String]) {
        let authorized = rbac.authorized(user, day)
        let candidates = specification == "-" ? [] : specification == "*" ? authorized.sorted()
            : specification.components(separatedBy: ",")
        var active: Set<String> = [], seen: Set<String> = [], activations: [Activation] = []
        for candidate in candidates {
            var reason: String?
            if !rbac.roles.contains(candidate) { reason = "unknown" }
            else if seen.contains(candidate) { reason = "duplicate" }
            else if !authorized.contains(candidate) { reason = "unauthorized" }
            else {
                let closure = rbac.closure(active.union([candidate]))
                if let constraint = rbac.dsd.first(where: { $0.roles.intersection(closure).count >= $0.cardinality }) {
                    reason = "dsd " + constraint.name
                }
            }
            seen.insert(candidate)
            if reason == nil { active.insert(candidate) }
            activations.append(Activation(role: candidate, reason: reason))
        }
        return (activations, rbac.closure(active).sorted())
    }

    func prepare(_ request: Request) -> (activations: [Activation], roles: [String], grant: String?, values: [String: Value]) {
        let (activations, roles) = activate(request.user, specification: request.roles, day: request.environment["day"]!.intValue!)
        let resource = resources[request.resource]!
        let permission = Permission(action: request.action, type: resource.type)
        let grant = roles.first { rbac.permissions[$0]!.contains(permission) }
        var values: [String: Value] = [:]
        for (name, value) in subjects[request.user]! { values["subject." + name] = value }
        values["subject.id"] = .string(request.user)
        values["subject.role"] = .bag(roles)
        values["subject.rbac"] = .boolean(grant != nil)
        for (name, value) in resource.attributes { values["resource." + name] = value }
        values["resource.id"] = .string(request.resource)
        values["resource.type"] = .string(resource.type)
        values["action.id"] = .string(request.action)
        for (name, value) in request.environment { values["environment." + name] = value }
        return (activations, roles, grant, values)
    }

    func processRequests() -> ([String], [String]) {
        var lines: [String] = [], explanations: [[String]] = []
        for request in requests {
            var symbols: [String: String] = [:]
            if let error = check(request) {
                lines.append("\(request.identifier) ERROR \(error)")
                decisions["ERROR", default: 0] += 1
                if request.explain { explanations.append(["request " + request.identifier, "  error " + error]) }
            } else {
                let prepared = prepare(request), evaluator = Evaluator(prepared.values, recordCoverage: true)
                let result = evaluator.evaluate(root)
                symbols = evaluator.coverage
                lines.append(request.identifier + " " + result.finalNotation)
                for activation in prepared.activations {
                    if let reason = activation.reason { lines.append("  refused \(activation.role) \(reason)"); refused += 1 }
                }
                for (id, item) in result.obligations { lines.append("  obligation " + item); obligations[id, default: 0] += 1 }
                for (id, item) in result.advice { lines.append("  advice " + item); advice[id, default: 0] += 1 }
                if let grant = prepared.grant {
                    grantCounts[Grant(role: grant, permission: Permission(action: request.action,
                        type: resources[request.resource]!.type)), default: 0] += 1
                }
                decisions[result.decision.indeterminate ? "INDETERMINATE" : result.decision.rawValue, default: 0] += 1
                if result.decision.definite { decisive[result.decisive!.identifier, default: 0] += 1 }
                if request.explain {
                    var trace = ["request " + request.identifier,
                        "  user \(request.user) resource \(request.resource) type \(resources[request.resource]!.type) "
                            + "action \(request.action) day \(request.environment["day"]!.intValue!)"]
                    for activation in prepared.activations {
                        trace.append("  activate " + activation.role + (activation.reason.map { " refused " + $0 } ?? " ok"))
                    }
                    trace.append("  roles " + (prepared.roles.isEmpty ? "-" : prepared.roles.joined(separator: ",")))
                    trace.append("  rbac " + (prepared.grant.map { "yes " + $0 } ?? "no"))
                    trace += treeLines(result)
                    trace.append("  decision " + result.finalNotation)
                    explanations.append(trace)
                }
            }
            for rule in rules { coverage[rule.identifier]! += symbols[rule.identifier] ?? "." }
        }
        return (lines, joinBlocks(explanations))
    }

    func permissionReport() -> [String] {
        var blocks: [[String]] = []
        for user in Set(rbac.assignments.map(\.user)).sorted() {
            var assigned: [String: Set<Int>] = [:], authorized: [String: Set<Int>] = [:]
            for assignment in rbac.assignments where assignment.user == user {
                assigned[assignment.role, default: []].formUnion(assignment.first...assignment.last)
            }
            for (role, days) in assigned {
                for inherited in rbac.closure([role]) { authorized[inherited, default: []].formUnion(days) }
            }
            var lines = ["user " + user]
            for role in assigned.keys.sorted() { lines.append("  assigned \(role) \(dayNotation(assigned[role]!))") }
            for role in authorized.keys.sorted() { lines.append("  authorized \(role) \(dayNotation(authorized[role]!))") }
            var via: [Permission: [String]] = [:]
            for role in authorized.keys.sorted() {
                for permission in rbac.permissions[role]! { via[permission, default: []].append(role) }
            }
            for permission in via.keys.sorted() {
                let roles = via[permission]!
                let days = roles.reduce(into: Set<Int>()) { $0.formUnion(authorized[$1]!) }
                var effective = "-"
                if subjects[user] != nil {
                    let matching = resources.keys.filter { resources[$0]!.type == permission.type }
                    var permitted = 0
                    for resource in matching {
                        let request = Request(identifier: "", user: user, roles: "*", action: permission.action,
                                              resource: resource, environment: reference, explain: false)
                        if Evaluator(prepare(request).values).evaluate(root).decision == .permit { permitted += 1 }
                    }
                    effective = "\(permitted)/\(matching.count)"
                }
                lines.append("  permission \(permission.action) \(permission.type) \(dayNotation(days)) "
                    + "via \(roles.joined(separator: ",")) effective \(effective)")
            }
            blocks.append(lines)
        }
        return joinBlocks(blocks)
    }

    func domainAnalysis() -> [String] {
        var counts: [String: Int] = [:], examples: [String: String] = [:]
        var shadowed = Set(rules.filter { $0.parent!.behavior == "first-applicable" }.map(\.identifier))
        var blockers: [String: Set<String>] = [:]
        var pairs: [(Element, Element, Element)] = [], conflictCounts: [Int] = []
        var ancestors: [String: [String]] = [:]
        for rule in rules {
            var chain: [String] = [], parent = rule.parent
            while let current = parent { chain.append(current.identifier); parent = current.parent }
            ancestors[rule.identifier] = chain
        }
        for policy in elements where policy.kind == "policy" {
            for (index, earlier) in policy.children.enumerated() {
                for later in policy.children.dropFirst(index + 1) where earlier.behavior != later.behavior {
                    pairs.append((policy, earlier, later))
                    conflictCounts.append(0)
                }
            }
        }
        var pointCount = 0
        enumeratePoints(domains) { values in
            pointCount += 1
            let evaluator = Evaluator(values)
            var targets: [String: TargetKind] = [:], standalone: [String: Decision] = [:]
            for element in elements where element.kind != "rule" { targets[element.identifier] = evaluator.target(element).kind }
            for rule in rules { standalone[rule.identifier] = evaluator.rule(rule, obligations: false).decision }
            var applying: Set<String> = []
            for rule in rules {
                let id = rule.identifier
                guard standalone[id]!.definite, ancestors[id]!.allSatisfy({ targets[$0] == .match }) else { continue }
                applying.insert(id)
                counts[id, default: 0] += 1
                if examples[id] == nil {
                    examples[id] = domains.filter { $0.1.count >= 2 }.map { "\($0.0)=\(values[$0.0]!.notation)" }.joined(separator: " ")
                }
                if shadowed.contains(id) {
                    if let earlier = blocker(rule, standalone: standalone) { blockers[id, default: []].insert(earlier) }
                    else { shadowed.remove(id) }
                }
            }
            for (index, pair) in pairs.enumerated() where applying.contains(pair.1.identifier) && applying.contains(pair.2.identifier) {
                conflictCounts[index] += 1
            }
        }
        var lines = ["applicability \(pointCount)"]
        for rule in rules { lines.append("  \(rule.identifier) \(counts[rule.identifier, default: 0]) \(examples[rule.identifier] ?? "-")") }
        let dead = rules.filter { counts[$0.identifier, default: 0] == 0 }.map(\.identifier)
        lines.append("dead \(dead.count)")
        lines += dead.map { "  " + $0 }
        shadowed.subtract(dead)
        lines.append("shadowed \(shadowed.count)")
        for rule in rules where shadowed.contains(rule.identifier) {
            let names = rules.filter { blockers[rule.identifier, default: []].contains($0.identifier) }.map(\.identifier)
            lines.append("  \(rule.identifier) by \(names.joined(separator: ","))")
        }
        lines.append("conflicts \(conflictCounts.filter { $0 > 0 }.count)")
        for (index, pair) in pairs.enumerated() where conflictCounts[index] > 0 {
            lines.append("  \(pair.0.identifier) \(pair.1.identifier) \(pair.2.identifier) \(conflictCounts[index]) "
                + conflictWinner(pair.0, pair.1, pair.2))
        }
        return lines
    }

    func analysisReport() -> [String] {
        var lines = ["rbac \(rbac.diagnostics.count)"]
        for (number, keyword, reason) in rbac.diagnostics { lines.append("  line \(number) \(keyword) \(reason)") }
        lines.append("grants \(rbac.grants.count)")
        for grant in rbac.grants.sorted() {
            lines.append("  \(grant.role) \(grant.permission.action) \(grant.permission.type) \(grantCounts[grant, default: 0])")
        }
        lines += domainAnalysis()
        lines.append("coverage \(requests.count)")
        var uncovered: [String] = []
        for rule in rules {
            let symbols = coverage[rule.identifier]!, count = symbols.filter { $0 == "P" || $0 == "D" }.count
            lines.append("  \(rule.identifier) \(symbols) \(count)")
            if count == 0 { uncovered.append(rule.identifier) }
        }
        lines.append("uncovered \(uncovered.count)")
        lines += uncovered.map { "  " + $0 }
        lines.append("summary")
        for name in ["PERMIT", "DENY", "NOT_APPLICABLE", "INDETERMINATE", "ERROR"] {
            lines.append("  decision \(name) \(decisions[name, default: 0])")
        }
        lines.append("  refused \(refused)")
        for element in elements where decisive[element.identifier, default: 0] > 0 {
            lines.append("  decisive \(element.identifier) \(decisive[element.identifier]!)")
        }
        for (kind, counts) in [("obligation", obligations), ("advice", advice)] {
            for id in counts.keys.sorted() { lines.append("  \(kind) \(id) \(counts[id]!)") }
        }
        return lines
    }

    func run() throws {
        let (decisions, traces) = processRequests()
        let outputs = [("decisions.txt", decisions), ("traces.txt", traces),
                       ("permissions.txt", permissionReport()), ("analysis.txt", analysisReport())]
        try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
        for (name, lines) in outputs {
            let text = lines.map { $0 + "\n" }.joined()
            try text.write(toFile: "output/" + name, atomically: true, encoding: .ascii)
        }
    }
}

try Engine().run()
