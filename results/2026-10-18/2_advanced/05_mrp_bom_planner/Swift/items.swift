struct Item {
    let id: String
    let leadTime: Int
    let rule: String
    let parameters: [Int]
    let safety: Int
    let onHand: Int
    let material: Int
    let labor: Int
    let description: String
    var lotLabel: String {
        if rule == "LFL" { return rule }
        if rule == "MIN" { return "MIN \(parameters[0])/\(parameters[1])" }
        return "\(rule) \(parameters[0])"
    }
}

func lotParameters(_ rule: String, text: String) -> [Int]? {
    let values = text.split(separator: "/").map { Int($0)! }
    let valid: Bool
    switch rule {
    case "LFL": valid = values.count == 1 && values[0] == 0
    case "MIN": valid = values.count == 2 && values.allSatisfy { $0 >= 1 }
    default: valid = values.count == 1 && values[0] >= 1
    }
    return valid ? values : nil
}

func readItems(errors: inout [String]) throws -> [String: Item] {
    var items: [String: Item] = [:]
    for (line, fields) in try csvRows("items.csv") {
        let id = fields[0]
        let rule = fields[2]
        let reason: String?
        if items[id] != nil { reason = "duplicate item \(id)" }
        else if !["LFL", "FOQ", "POQ", "MIN"].contains(rule) { reason = "unknown lot rule \(rule)" }
        else if lotParameters(rule, text: fields[3]) == nil { reason = "bad lot parameter \(fields[3]) for \(rule)" }
        else { reason = nil }
        if let reason { errors.append("items.csv line \(line): \(reason)") }
        else { items[id] = Item(id: id, leadTime: Int(fields[1])!, rule: rule, parameters: lotParameters(rule, text: fields[3])!, safety: Int(fields[4])!, onHand: Int(fields[5])!, material: Int(fields[6])!, labor: Int(fields[7])!, description: fields[8]) }
    }
    return items
}
