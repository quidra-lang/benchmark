struct WorkCenter {
    let id: String
    let minutes: Int
    let efficiency: Int
    let description: String
    var available: Int { minutes * efficiency / 100 }
}
struct Operation {
    let item: String
    let number: Int
    let center: String
    let setup: Int
    let run: Int
    func minutes(_ quantity: Int) -> Int { setup + quantity * run }
}

func readCenters(errors: inout [String]) throws -> [String: WorkCenter] {
    var centers: [String: WorkCenter] = [:]
    for (line, fields) in try csvRows("workcenters.csv") {
        let id = fields[0]
        let efficiency = Int(fields[2])!
        let reason: String?
        if centers[id] != nil { reason = "duplicate center \(id)" }
        else if !(50...150).contains(efficiency) { reason = "bad efficiency \(efficiency)" }
        else { reason = nil }
        if let reason { errors.append("workcenters.csv line \(line): \(reason)") }
        else { centers[id] = WorkCenter(id: id, minutes: Int(fields[1])!, efficiency: efficiency, description: fields[3]) }
    }
    return centers
}

func readRoutings(items: [String: Item], centers: [String: WorkCenter], bom: Bom, errors: inout [String]) throws -> [String: [Operation]] {
    var routings: [String: [Operation]] = [:]
    for (line, fields) in try csvRows("routings.csv") {
        let id = fields[0]
        let number = Int(fields[1])!
        let center = fields[2]
        let run = Int(fields[4])!
        let reason: String?
        if items[id] == nil { reason = "unknown item \(id)" }
        else if centers[center] == nil { reason = "unknown center \(center)" }
        else if !bom.manufactured(id) { reason = "purchased item \(id)" }
        else if run < 1 { reason = "bad run time \(run)" }
        else if routings[id, default: []].contains(where: { $0.number == number }) { reason = "duplicate \(id) operation \(number)" }
        else { reason = nil }
        if let reason { errors.append("routings.csv line \(line): \(reason)") }
        else { routings[id, default: []].append(Operation(item: id, number: number, center: center, setup: Int(fields[3])!, run: run)) }
    }
    return routings.mapValues { $0.sorted { $0.number < $1.number } }
}

func operationWeek(receipt: Int, leadTime: Int, index: Int, count: Int) -> Int { max(1, receipt - leadTime + index * leadTime / count) }
func leveledLoads(_ loads: [Int], available: Int) -> [Int] {
    var result = Array(repeating: 0, count: loads.count)
    var carry = 0
    for week in stride(from: loads.count - 1, through: 2, by: -1) {
        let total = loads[week] + carry
        result[week] = min(total, available)
        carry = total - result[week]
    }
    result[1] = loads[1] + carry
    return result
}
