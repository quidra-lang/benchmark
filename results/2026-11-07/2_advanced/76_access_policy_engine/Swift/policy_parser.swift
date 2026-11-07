import Foundation

struct MatchClause {
    let reference: String
    let mandatory: Bool
    let operation: String
    let literal: Expression
}

struct Attachment {
    let effect: Decision
    let identifier: String
    let arguments: [(String, Expression)]
}

final class Element {
    let kind: String
    let identifier: String
    let behavior: String
    weak var parent: Element?
    var targets: [[[MatchClause]]] = []
    var children: [Element] = []
    var condition: Expression?
    var obligations: [Attachment] = []
    var advice: [Attachment] = []

    init(kind: String, identifier: String, behavior: String, parent: Element?) {
        self.kind = kind.lowercased()
        self.identifier = identifier
        self.behavior = behavior
        self.parent = parent
    }
}

func readPolicies() throws -> [Element] {
    var elements: [Element] = [], stack: [Element] = []
    for raw in try readLines("input/policies.txt") {
        let line = raw.drop { $0 == " " }
        if line.isEmpty || line.hasPrefix("#") { continue }
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        let keyword = parts[0], rest = parts.count == 2 ? parts[1] : ""
        switch keyword {
        case "POLICYSET", "POLICY", "RULE":
            let fields = rest.split(separator: " ").map(String.init)
            let element = Element(kind: keyword, identifier: fields[0], behavior: fields[1], parent: stack.last)
            stack.last?.children.append(element)
            elements.append(element)
            stack.append(element)
        case "END": stack.removeLast()
        case "TARGET":
            let alternatives = rest.components(separatedBy: " | ").map { alternative in
                alternative.components(separatedBy: " & ").map { clause -> MatchClause in
                    let fields = clause.split(separator: " ").map(String.init)
                    let mandatory = fields[0].hasSuffix("!")
                    return MatchClause(reference: mandatory ? String(fields[0].dropLast()) : fields[0],
                                       mandatory: mandatory, operation: fields[1], literal: parseExpression(fields[2]))
                }
            }
            stack.last!.targets.append(alternatives)
        case "CONDITION": stack.last!.condition = parseExpression(rest)
        default:
            let fields = rest.split(separator: " ", maxSplits: 2).map(String.init)
            let arguments: [(String, Expression)] = fields.count < 3 ? []
                : fields[2].components(separatedBy: ";").map { part in
                    let pair = part.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1)
                    return (String(pair[0]), parseExpression(String(pair[1])))
                }
            let attachment = Attachment(effect: Decision(rawValue: fields[0])!, identifier: fields[1], arguments: arguments)
            if keyword == "OBLIGATION" { stack.last!.obligations.append(attachment) }
            else { stack.last!.advice.append(attachment) }
        }
    }
    return elements
}
