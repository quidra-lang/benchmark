import Foundation

let issueTypes = ["BUG", "TASK", "STORY"]
let priorities = ["LOW", "MEDIUM", "HIGH", "CRITICAL"]
let workflows = [
    "BUG": ["OPEN", "TRIAGED", "IN_PROGRESS", "REVIEW", "RESOLVED", "CLOSED", "REOPENED"],
    "TASK": ["OPEN", "IN_PROGRESS", "DONE"],
    "STORY": ["BACKLOG", "READY", "IN_PROGRESS", "REVIEW", "DONE"]
]
let transitions: [String: Set<String>] = [
    "BUG": ["OPEN>TRIAGED", "TRIAGED>IN_PROGRESS", "IN_PROGRESS>REVIEW", "REVIEW>IN_PROGRESS",
            "REVIEW>RESOLVED", "RESOLVED>CLOSED", "RESOLVED>REOPENED", "CLOSED>REOPENED", "REOPENED>IN_PROGRESS"],
    "TASK": ["OPEN>IN_PROGRESS", "IN_PROGRESS>OPEN", "IN_PROGRESS>DONE"],
    "STORY": [
        "BACKLOG>READY",
        "READY>BACKLOG",
        "READY>IN_PROGRESS",
        "IN_PROGRESS>REVIEW",
        "REVIEW>IN_PROGRESS",
        "REVIEW>DONE"
    ]
]
let doneStates: Set<String> = ["RESOLVED", "CLOSED", "DONE"]
let allStates = Set(workflows.values.flatMap { $0 })
let estimates: Set<Int> = [0, 1, 2, 3, 5, 8, 13, 21]
let equalityOperators: Set<String> = ["=", "!="]
let orderOperators: Set<String> = ["=", "!=", "<", "<=", ">", ">="]
let fieldOperators: [String: Set<String>] = [
    "id": orderOperators, "type": equalityOperators, "status": equalityOperators,
    "priority": orderOperators, "assignee": equalityOperators, "reviewer": equalityOperators,
    "estimate": orderOperators, "sprint": equalityOperators, "comments": orderOperators,
    "blocked": equalityOperators, "done": equalityOperators, "title": ["~"]
]

struct CommandError: Error { let reason: String }
func yesNo(_ value: Bool) -> String {
    value ? "yes" : "no"
}
func numberList(_ numbers: Set<Int>) -> String {
    numbers.isEmpty ? "-" : numbers.sorted().map(String.init).joined(separator: ",")
}

final class Issue {
    let number: Int
    let kind: String
    let title: String
    var priority: String
    var state: String
    var assignee: String?
    var reviewer: String?
    var estimate: Int?
    var sprint: String?
    var comments = 0
    var blocks: Set<Int> = []
    var blockers: Set<Int> = []
    var duplicate: Int?
    var duplicates: Set<Int> = []
    var history: [String] = []

    init(number: Int, kind: String, priority: String, title: String) {
        self.number = number
        self.kind = kind
        self.priority = priority
        self.title = title
        state = workflows[kind]![0]
    }

    var done: Bool {
        doneStates.contains(state)
    }
    var points: Int {
        estimate ?? 0
    }
    var level: Int {
        priorities.firstIndex(of: priority)!
    }
    var estimateText: String {
        estimate.map(String.init) ?? "-"
    }
}

final class Sprint {
    let name: String
    var phase = "PLANNED"
    var start: Int?
    var end: Int?
    var velocity = 0
    var records: [Int: Int] = [:]
    init(_ name: String) {
        self.name = name
    }
}

enum QueryValue: Equatable {
    case none
    case number(Int)
    case text(String)
}

struct Condition {
    let field: String
    let operation: String
    let value: QueryValue

    func matches(_ issue: Issue, tracker: Tracker) -> Bool {
        let actual = tracker.fieldValue(issue, field: field)
        if operation == "~", case .text(let text) = actual, case .text(let part) = value {
            return text.contains(part)
        }
        if operation == "=" {
            return actual == value
        }
        if operation == "!=" {
            return actual != value
        }
        guard case .number(let a) = actual, case .number(let b) = value else {
            return false
        }
        switch operation {
        case "<":
            return a < b
        case "<=":
            return a <= b
        case ">":
            return a > b
        default:
            return a >= b
        }
    }
}

indirect enum QueryNode {
    case condition(Condition)
    case not(QueryNode)
    case and(QueryNode, QueryNode)
    case or(QueryNode, QueryNode)

    func matches(_ issue: Issue, tracker: Tracker) -> Bool {
        switch self {
        case .condition(let condition):
            return condition.matches(issue, tracker: tracker)
        case .not(let node):
            return !node.matches(issue, tracker: tracker)
        case .and(let a, let b):
            return a.matches(issue, tracker: tracker) && b.matches(issue, tracker: tracker)
        case .or(let a, let b):
            return a.matches(issue, tracker: tracker) || b.matches(issue, tracker: tracker)
        }
    }
}

final class QueryParser {
    let tokens: [String]
    let conditions: [Condition?]
    var position = 0
    init(tokens: [String], conditions: [Condition?]) {
        self.tokens = tokens
        self.conditions = conditions
    }

    func accept(_ token: String) -> Bool {
        if position < tokens.count && tokens[position] == token {
            position += 1
            return true
        }
        return false
    }

    func expression() -> QueryNode {
        var node = term()
        while accept("OR") {
            node = .or(node, term())
        }
        return node
    }

    func term() -> QueryNode {
        var node = factor()
        while accept("AND") {
            node = .and(node, factor())
        }
        return node
    }

    func factor() -> QueryNode {
        if accept("NOT") {
            return .not(factor())
        }
        if accept("(") {
            let node = expression()
            _ = accept(")")
            return node
        }
        let node = QueryNode.condition(conditions[position]!)
        position += 1
        return node
    }
}

func queryTokens(_ query: String) -> [String] {
    var tokens: [String] = []
    var current = ""
    for character in query {
        if character == " " || character == "(" || character == ")" {
            if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
            if character != " " {
                tokens.append(String(character))
            }
        } else {
            current.append(character)
        }
    }
    if !current.isEmpty {
        tokens.append(current)
    }
    return tokens
}

final class Tracker {
    var day = 1
    var users: Set<String> = []
    var issues: [Int: Issue] = [:]
    var sprints: [String: Sprint] = [:]
    var sprintOrder: [Sprint] = []

    var orderedIssues: [Issue] {
        issues.keys.sorted().map { issues[$0]! }
    }
    var activeSprint: Sprint? {
        sprintOrder.first { $0.phase == "ACTIVE" }
    }

    func requireIssue(_ text: String) throws -> Issue {
        guard let issue = issues[Int(text)!] else {
            throw CommandError(reason: "unknown issue")
        }
        return issue
    }
    func requireUser(_ text: String) throws -> String? {
        if text == "-" {
            return nil
        }
        guard users.contains(text) else {
            throw CommandError(reason: "unknown user")
        }
        return text
    }
    func requireSprint(_ name: String) throws -> Sprint {
        guard let sprint = sprints[name] else {
            throw CommandError(reason: "unknown sprint")
        }
        return sprint
    }
    func requireNotDone(_ issue: Issue) throws {
        if issue.done {
            throw CommandError(reason: "issue done")
        }
    }
    func record(_ issue: Issue, _ content: String) {
        issue.history.append("day \(day) " + content)
    }
    func unfinishedBlockers(_ issue: Issue) -> [Int] {
        issue.blockers.filter { !issues[$0]!.done }.sorted()
    }
    func blocked(_ issue: Issue) -> Bool {
        !issue.done && !unfinishedBlockers(issue).isEmpty
    }
    func wip(_ user: String?) -> Int {
        issues.values.filter { $0.assignee == user && $0.state == "IN_PROGRESS" }.count
    }
    func members(_ sprint: Sprint) -> [Issue] {
        orderedIssues.filter { $0.sprint == sprint.name }
    }
    func remaining(_ sprint: Sprint) -> Int {
        members(sprint).filter { !$0.done }.reduce(0) { $0 + $1.points }
    }
    func summary(_ sprint: Sprint) -> String {
        let members = members(sprint)
        return "issues \(members.count) points \(members.reduce(0) { $0 + $1.points })"
    }
    func notifications(_ before: [Int: Bool]) -> [String] {
        before.keys.sorted().compactMap { number in
            let after = blocked(issues[number]!)
            return after == before[number]! ? nil : "\(after ? "BLOCKED" : "UNBLOCKED") \(number)"
        }
    }
    func changeState(_ issue: Issue, to target: String) -> [String] {
        let before = Dictionary(uniqueKeysWithValues: issue.blocks.map { ($0, blocked(issues[$0]!)) })
        let line = "MOVE \(issue.number) \(issue.state) \(target)"
        record(issue, "MOVE \(issue.state) \(target)")
        issue.state = target
        return [line] + notifications(before)
    }
    func reaches(_ start: Int, _ goal: Int) -> Bool {
        var pending = [start]
        var visited: Set<Int> = []
        while let number = pending.popLast() {
            if number == goal {
                return true
            }
            if visited.insert(number).inserted {
                pending.append(contentsOf: issues[number]!.blocks)
            }
        }
        return false
    }

    func fieldValue(_ issue: Issue, field: String) -> QueryValue {
        switch field {
        case "id":
            return .number(issue.number)
        case "type":
            return .text(issue.kind)
        case "status":
            return .text(issue.state)
        case "priority":
            return .number(issue.level)
        case "assignee":
            return issue.assignee.map(QueryValue.text) ?? .none
        case "reviewer":
            return issue.reviewer.map(QueryValue.text) ?? .none
        case "estimate":
            return issue.estimate.map(QueryValue.number) ?? .none
        case "sprint":
            return issue.sprint.map(QueryValue.text) ?? .none
        case "comments":
            return .number(issue.comments)
        case "blocked":
            return .text(yesNo(blocked(issue)))
        case "done":
            return .text(yesNo(issue.done))
        default:
            return .text(issue.title.lowercased())
        }
    }

    func condition(_ token: String) throws -> Condition {
        let bytes = Array(token.utf8)
        var end = 0
        while end < bytes.count && (97...122).contains(bytes[end]) {
            end += 1
        }
        let field = String(decoding: bytes[..<end], as: UTF8.self)
        let rest = String(decoding: bytes[end...], as: UTF8.self)
        guard !field.isEmpty,
              let operation = [">=", "<=", "!=", "=", "<", ">", "~"].first(where: { rest.hasPrefix($0) })
        else {
            throw CommandError(reason: "syntax near " + token)
        }
        let text = String(rest.dropFirst(operation.count))
        guard !text.isEmpty else {
            throw CommandError(reason: "syntax near " + token)
        }
        guard let allowed = fieldOperators[field] else {
            throw CommandError(reason: "unknown field " + field)
        }
        guard allowed.contains(operation) else {
            throw CommandError(reason: "bad operator " + token)
        }
        let value: QueryValue
        if text == "-" && ["assignee", "reviewer", "estimate", "sprint"].contains(field) && equalityOperators
            .contains(operation)
        {
            value = .none
        } else if ["id", "estimate", "comments"].contains(field), (1...6).contains(text.count),
                  text.utf8.allSatisfy({ (48...57).contains($0) })
        {
            value = .number(Int(text)!)
        } else if field == "priority", let level = priorities.firstIndex(of: text) {
            value = .number(level)
        } else if field == "type" && issueTypes.contains(text) {
            value = .text(text)
        } else if field == "status" && allStates.contains(text) {
            value = .text(text)
        } else if ["assignee", "reviewer"].contains(field) && users.contains(text) {
            value = .text(text)
        } else if field == "sprint" && sprints[text] != nil {
            value = .text(text)
        } else if ["blocked", "done"].contains(field) && ["yes", "no"].contains(text) {
            value = .text(text)
        } else if field == "title" {
            value = .text(text.lowercased())
        } else {
            throw CommandError(reason: "bad value " + token)
        }
        return Condition(field: field, operation: operation, value: value)
    }

    func query(_ text: String) throws -> [String] {
        let tokens = queryTokens(text)
        var conditions: [Condition?] = []
        var expectingOperand = true
        var depth = 0
        for token in tokens {
            var parsed: Condition?
            if expectingOperand {
                if token == "(" {
                    depth += 1
                } else if ["AND", "OR", ")"].contains(token) {
                    throw CommandError(reason: "syntax near " + token)
                } else if token != "NOT" {
                    parsed = try condition(token)
                    expectingOperand = false
                }
            } else if token == "AND" || token == "OR" {
                expectingOperand = true
            } else if token == ")" && depth > 0 {
                depth -= 1
            } else {
                throw CommandError(reason: "syntax near " + token)
            }
            conditions.append(parsed)
        }
        guard !expectingOperand && depth == 0 else {
            throw CommandError(reason: "syntax at end")
        }
        let tree = QueryParser(tokens: tokens, conditions: conditions).expression()
        let matches = issues.values.filter { tree.matches($0, tracker: self) }.sorted {
            $0.level != $1.level ? $0.level > $1.level : $0.number < $1.number
        }
        return ["QUERY \(matches.count)"] + matches.map {
            "\($0.number) \($0.kind) \($0.priority) \($0.state) \($0.assignee ?? "-") \($0.estimateText) \($0.title)"
        }
    }

    func sprintCommand(_ words: [String]) throws -> [String] {
        let action = words[1]
        let name = words[2]
        if action == "NEW" {
            guard sprints[name] == nil else {
                throw CommandError(reason: "sprint exists")
            }
            let sprint = Sprint(name)
            sprints[name] = sprint
            sprintOrder.append(sprint)
            return ["SPRINT NEW " + name]
        }
        let sprint = try requireSprint(name)
        if action == "ADD" || action == "REMOVE" {
            let issue = try requireIssue(words[3])
            guard sprint.phase != "ENDED" else {
                throw CommandError(reason: "sprint ended")
            }
            if action == "ADD" {
                try requireNotDone(issue)
                if let old = issue.sprint,
                   sprints[old]!.phase != "ENDED"
                {
                    throw CommandError(reason: "in sprint " + old)
                }
                guard issue.state != "BACKLOG" else {
                    throw CommandError(reason: "not ready")
                }
                issue.sprint = name
            } else {
                guard issue.sprint == name else {
                    throw CommandError(reason: "not in sprint")
                }
                try requireNotDone(issue)
                issue.sprint = nil
            }
            record(issue, "SPRINT \(action) \(name)")
            return ["SPRINT \(action) \(name) \(issue.number) \(summary(sprint))"]
        }
        if action == "START" {
            guard sprint.phase == "PLANNED" else {
                throw CommandError(reason: "sprint not planned")
            }
            if let active = activeSprint {
                throw CommandError(reason: "sprint active " + active.name)
            }
            guard !members(sprint).isEmpty else {
                throw CommandError(reason: "sprint empty")
            }
            sprint.phase = "ACTIVE"
            sprint.start = day
            let points = remaining(sprint)
            sprint.records[day] = points
            return ["SPRINT START \(name) day \(day) \(summary(sprint)) remaining \(points)"]
        }
        guard sprint.phase == "ACTIVE" else {
            throw CommandError(reason: "sprint not active")
        }
        sprint.records[day] = remaining(sprint)
        let members = members(sprint)
        let finished = members.filter { $0.done }
        let returned = members.filter { !$0.done }
        sprint.velocity = finished.reduce(0) { $0 + $1.points }
        sprint.phase = "ENDED"
        sprint.end = day
        var lines =
            [
                "SPRINT END \(name) day \(day) velocity \(sprint.velocity) done \(finished.count) returned \(returned.count)"
            ]
        for issue in returned {
            issue.sprint = nil
            record(issue, "SPRINT RETURN " + name)
            lines.append("RETURNED \(issue.number)")
        }
        return lines
    }

    func command(_ line: String) throws -> [String] {
        let words = line.components(separatedBy: " ")
        switch words[0] {
        case "DAY":
            let target = Int(words[1])!
            guard target >= day else {
                throw CommandError(reason: "day backwards")
            }
            day = target
            return ["DAY \(day)"]
        case "USER":
            guard users.insert(words[1]).inserted else {
                throw CommandError(reason: "user exists")
            }
            return ["USER " + words[1]]
        case "CREATE":
            let number = Int(words[1])!
            let kind = words[2]
            let priority = words[3]
            guard issues[number] == nil else {
                throw CommandError(reason: "issue exists")
            }
            guard issueTypes.contains(kind) else {
                throw CommandError(reason: "bad type")
            }
            guard priorities.contains(priority) else {
                throw CommandError(reason: "bad priority")
            }
            let issue = Issue(
                number: number,
                kind: kind,
                priority: priority,
                title: words.dropFirst(4).joined(separator: " ")
            )
            issues[number] = issue
            record(issue, "CREATE \(kind) \(priority)")
            return ["CREATE \(number) \(kind) \(priority) \(issue.state)"]
        case "PRIORITY":
            let issue = try requireIssue(words[1])
            let priority = words[2]
            guard priorities.contains(priority) else {
                throw CommandError(reason: "bad priority")
            }
            try requireNotDone(issue)
            guard priority != issue.priority else {
                throw CommandError(reason: "no change")
            }
            let old = issue.priority
            issue.priority = priority
            record(issue, "PRIORITY \(old) \(priority)")
            return ["PRIORITY \(issue.number) \(old) \(priority)"]
        case "ASSIGN", "REVIEWER":
            let issue = try requireIssue(words[1])
            let user = try requireUser(words[2])
            try requireNotDone(issue)
            if words[0] == "ASSIGN" {
                guard user != issue.assignee else {
                    throw CommandError(reason: "no change")
                }
                guard user != nil || !["IN_PROGRESS", "REVIEW"].contains(issue.state)
                else {
                    throw CommandError(reason: "assignee required")
                }
                if issue
                    .state == "IN_PROGRESS" && wip(user) >= 3
                {
                    throw CommandError(reason: "wip limit " + words[2])
                }
                if issue.state == "REVIEW" && user == issue
                    .reviewer
                {
                    throw CommandError(reason: "reviewer is assignee")
                }
                issue.assignee = user
            } else {
                guard user != issue.reviewer else {
                    throw CommandError(reason: "no change")
                }
                if issue.state == "REVIEW" && user == nil {
                    throw CommandError(reason: "reviewer required")
                }
                if issue.state == "REVIEW" && user == issue
                    .assignee
                {
                    throw CommandError(reason: "reviewer is assignee")
                }
                issue.reviewer = user
            }
            record(issue, "\(words[0]) \(words[2])")
            return ["\(words[0]) \(issue.number) \(words[2])"]
        case "ESTIMATE":
            let issue = try requireIssue(words[1])
            let points = Int(words[2])!
            guard estimates.contains(points) else {
                throw CommandError(reason: "bad estimate")
            }
            try requireNotDone(issue)
            guard issue.estimate != points else {
                throw CommandError(reason: "no change")
            }
            let old = issue.estimateText
            issue.estimate = points
            record(issue, "ESTIMATE \(old) \(points)")
            return ["ESTIMATE \(issue.number) \(old) \(points)"]
        case "COMMENT":
            let issue = try requireIssue(words[1])
            _ = try requireUser(words[2])
            issue.comments += 1
            record(issue, "COMMENT \(words[2]) " + words.dropFirst(3).joined(separator: " "))
            return ["COMMENT \(issue.number) \(issue.comments)"]
        case "MOVE":
            let issue = try requireIssue(words[1])
            let target = words[2]
            if let duplicate = issue.duplicate {
                throw CommandError(reason: "duplicate of \(duplicate)")
            }
            guard workflows[issue.kind]!.contains(target) else {
                throw CommandError(reason: "bad state")
            }
            guard transitions[issue.kind]!.contains(issue.state + ">" + target)
            else {
                throw CommandError(reason: "cannot move \(issue.state) to \(target)")
            }
            if target == "IN_PROGRESS" {
                if issue
                    .kind == "STORY" &&
                    (activeSprint == nil || issue.sprint != activeSprint!.name)
                {
                    throw CommandError(reason: "not in active sprint")
                }
                guard let user = issue.assignee else {
                    throw CommandError(reason: "no assignee")
                }
                if wip(user) >= 3 {
                    throw CommandError(reason: "wip limit " + user)
                }
            }
            if target == "REVIEW" {
                guard issue.reviewer != nil else {
                    throw CommandError(reason: "no reviewer")
                }
                guard issue.reviewer != issue.assignee else {
                    throw CommandError(reason: "reviewer is assignee")
                }
            }
            if ["DONE", "RESOLVED"].contains(target),
               let blocker = unfinishedBlockers(issue).first
            {
                throw CommandError(reason: "blocked by \(blocker)")
            }
            if target == "READY" && issue.estimate == nil {
                throw CommandError(reason: "no estimate")
            }
            return changeState(issue, to: target)
        case "LINK", "UNLINK":
            let relation = words[2]
            let unlink = words[0] == "UNLINK"
            guard relation == "BLOCKS" || (!unlink && relation == "DUPLICATES")
            else {
                throw CommandError(reason: "bad link")
            }
            let a = try requireIssue(words[1])
            let b = try requireIssue(words[3])
            if unlink {
                guard a.blocks.contains(b.number) else {
                    throw CommandError(reason: "no link")
                }
            } else {
                guard a.number != b.number else {
                    throw CommandError(reason: "self link")
                }
                if relation == "BLOCKS" {
                    guard !a.blocks.contains(b.number) else {
                        throw CommandError(reason: "link exists")
                    }
                    guard !reaches(b.number, a.number) else {
                        throw CommandError(reason: "cycle")
                    }
                    try requireNotDone(b)
                } else {
                    guard a.kind == b.kind else {
                        throw CommandError(reason: "type mismatch")
                    }
                    try requireNotDone(a)
                    guard b.duplicate == nil else {
                        throw CommandError(reason: "target is duplicate")
                    }
                    a.duplicate = b.number
                    b.duplicates.insert(a.number)
                    record(a, "LINK DUPLICATES \(b.number)")
                    record(b, "LINK DUPLICATED_BY \(a.number)")
                    var lines = ["LINK \(a.number) DUPLICATES \(b.number)"]
                    lines += changeState(a, to: a.kind == "BUG" ? "CLOSED" : "DONE")
                    if let sprint = a.sprint, sprints[sprint]!.phase != "ENDED" {
                        a.sprint = nil
                        record(a, "SPRINT REMOVE " + sprint)
                    }
                    return lines
                }
            }
            let before = [b.number: blocked(b)]
            if unlink {
                a.blocks.remove(b.number)
                b.blockers.remove(a.number)
            } else {
                a.blocks.insert(b.number)
                b.blockers.insert(a.number)
            }
            record(a, "\(words[0]) BLOCKS \(b.number)")
            record(b, "\(words[0]) BLOCKED_BY \(a.number)")
            return ["\(words[0]) \(a.number) BLOCKS \(b.number)"] + notifications(before)
        case "SPRINT":
            return try sprintCommand(words)
        case "QUERY":
            return try query(words.dropFirst().joined(separator: " "))
        case "SHOW":
            let issue = try requireIssue(words[1])
            return [
                "ISSUE \(issue.number) \(issue.kind) \(issue.priority) \(issue.state) blocked \(yesNo(blocked(issue)))",
                "TITLE " + issue.title,
                "PEOPLE assignee \(issue.assignee ?? "-") reviewer \(issue.reviewer ?? "-")",
                "PLAN estimate \(issue.estimateText) sprint \(issue.sprint ?? "-") comments \(issue.comments)",
                "LINKS blocks \(numberList(issue.blocks)) blocked_by \(numberList(issue.blockers)) duplicate_of \(issue.duplicate.map(String.init) ?? "-") duplicated_by \(numberList(issue.duplicates))"
            ]
        case "HISTORY":
            let issue = try requireIssue(words[1])
            return ["HISTORY \(issue.number) \(issue.history.count)"] + issue.history
        case "BOARD":
            var lines = ["BOARD"]
            for kind in issueTypes {
                lines
                    .append(kind + workflows[kind]!.map { state in
                        " \(state) \(issues.values.filter { $0.kind == kind && $0.state == state }.count)"
                    }.joined())
            }
            let done = issues.values.filter { $0.done }.count
            lines.append("TOTAL \(issues.count) open \(issues.count - done) done \(done)")
            return lines
        case "WORKLOAD":
            var lines = ["WORKLOAD \(users.count)"]
            for user in users.sorted() {
                let assigned = issues.values.filter { !$0.done && $0.assignee == user }
                let progress = assigned.filter { $0.state == "IN_PROGRESS" }.count
                let review = assigned.filter { $0.state == "REVIEW" }.count
                let reviewing = issues.values.filter { $0.reviewer == user && $0.state == "REVIEW" }.count
                lines
                    .append(
                        "\(user) assigned \(assigned.count) in_progress \(progress) review \(review) reviewing \(reviewing) points \(assigned.reduce(0) { $0 + $1.points })"
                    )
            }
            return lines
        case "SPRINTS":
            return ["SPRINTS \(sprintOrder.count)"] + sprintOrder.map { sprint in
                if sprint.phase == "PLANNED" {
                    return "\(sprint.name) PLANNED \(summary(sprint))"
                }
                if sprint
                    .phase ==
                    "ACTIVE"
                {
                    return "\(sprint.name) ACTIVE start \(sprint.start!) \(summary(sprint)) remaining \(remaining(sprint))"
                }
                return "\(sprint.name) ENDED start \(sprint.start!) end \(sprint.end!) velocity \(sprint.velocity)"
            }
        case "BURNDOWN":
            let sprint = try requireSprint(words[1])
            guard sprint.phase != "PLANNED" else {
                throw CommandError(reason: "sprint not started")
            }
            let start = sprint.start!
            let last = sprint.phase == "ACTIVE" ? day : sprint.end!
            var lines = ["BURNDOWN \(sprint.name) \(sprint.phase) days \(last - start + 1)"]
            var points = 0
            for date in start...last {
                if let record = sprint.records[date] {
                    points = record
                }
                lines.append("day \(date) \(points)")
            }
            return lines
        default:
            return []
        }
    }

    func execute(_ line: String) -> [String] {
        let lines: [String]
        do { lines = try command(line) }
        catch let error as CommandError { lines = ["ERROR " + error.reason] }
        catch { fatalError("Unexpected error: \(error)") }
        if let sprint = activeSprint {
            sprint.records[day] = remaining(sprint)
        }
        return lines
    }
}

let tracker = Tracker()
if let line = readLine(), let count = Int(line) {
    var output: [String] = []
    for _ in 0..<count {
        guard let line = readLine() else {
            break
        }
        output += tracker.execute(line)
    }
    if !output.isEmpty {
        print(output.joined(separator: "\n"))
    }
}
