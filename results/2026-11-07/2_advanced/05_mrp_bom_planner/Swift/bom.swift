struct BomRow {
    let parent: String
    let child: String
    let quantity: Int
    let scrap: Int
    func need(_ parentQuantity: Int) -> Int { (parentQuantity * quantity * (100 + scrap) + 99) / 100 }
}

final class Bom {
    var children: [String: [BomRow]]
    var parents: [String: [BomRow]]
    init(items: [String: Item]) {
        children = Dictionary(uniqueKeysWithValues: items.keys.map { ($0, [BomRow]()) })
        parents = children
    }
    func manufactured(_ id: String) -> Bool { !children[id]!.isEmpty }
    func add(_ row: BomRow) {
        children[row.parent]!.append(row)
        children[row.parent]!.sort { $0.child < $1.child }
        parents[row.child]!.append(row)
        parents[row.child]!.sort { $0.parent < $1.parent }
    }
    func path(start: String, target: String) -> [String]? {
        var visited: Set<String> = []
        func search(_ id: String) -> [String]? {
            if id == target { return [id] }
            visited.insert(id)
            for row in children[id]! where !visited.contains(row.child) {
                if let rest = search(row.child) { return [id] + rest }
            }
            return nil
        }
        return search(start)
    }
    func lowLevelCodes() -> [String: Int] {
        var codes: [String: Int] = [:]
        func code(_ id: String) -> Int {
            if let value = codes[id] { return value }
            let value = parents[id]!.map { code($0.parent) + 1 }.max() ?? 0
            codes[id] = value
            return value
        }
        for id in children.keys { _ = code(id) }
        return codes
    }
    func cumulativeLeadTimes(_ items: [String: Item]) -> [String: Int] {
        var times: [String: Int] = [:]
        func time(_ id: String) -> Int {
            if let value = times[id] { return value }
            let value = items[id]!.leadTime + (children[id]!.map { time($0.child) }.max() ?? 0)
            times[id] = value
            return value
        }
        for id in children.keys { _ = time(id) }
        return times
    }
}

func readBom(items: [String: Item], errors: inout [String]) throws -> Bom {
    let bom = Bom(items: items)
    for (line, fields) in try csvRows("bom.csv") {
        let parent = fields[0]
        let child = fields[1]
        let quantity = Int(fields[2])!
        let scrap = Int(fields[3])!
        var reason: String?
        if items[parent] == nil { reason = "unknown item \(parent)" }
        else if items[child] == nil { reason = "unknown item \(child)" }
        else if quantity < 1 { reason = "bad quantity \(quantity)" }
        else if scrap > 50 { reason = "bad scrap \(scrap)" }
        else if parent == child { reason = "cycle \(parent) -> \(parent)" }
        else if bom.children[parent]!.contains(where: { $0.child == child }) { reason = "duplicate \(parent) -> \(child)" }
        else if let path = bom.path(start: child, target: parent) { reason = "cycle \(parent) -> " + path.joined(separator: " -> ") }
        if let reason { errors.append("bom.csv line \(line): \(reason)") }
        else { bom.add(BomRow(parent: parent, child: child, quantity: quantity, scrap: scrap)) }
    }
    return bom
}
