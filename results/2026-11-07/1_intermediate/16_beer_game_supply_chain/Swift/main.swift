import Foundation

private extension String {
    func padStart(_ width: Int) -> String {
        String(repeating: " ", count: max(0, width - count)) + self
    }
}

private let stageNames = ["RETAILER", "WHOLESALER", "DISTRIBUTOR", "FACTORY"]
private let policyParameters = [
    "FIXED": 1, "PASS": 0, "BASESTOCK": 1, "MINMAX": 2,
    "MOVAVG": 2, "SMOOTH": 2, "STERMAN": 4
]

private enum GameError: Error {
    case invalid(String)
}

private func fail(_ reason: String) -> GameError { .invalid(reason) }

private func money(_ value: Int) -> String {
    "\(value / 100)." + String(format: "%02d", value % 100)
}

private func floorDiv(_ numerator: Int, _ denominator: Int) -> Int {
    numerator >= 0 ? numerator / denominator :
        -((-numerator + denominator - 1) / denominator)
}

private func decimal(_ numerator: Int, _ denominator: Int, places: Int) -> String {
    var scale = 1
    for _ in 0..<places { scale *= 10 }
    let value = floorDiv(numerator * scale, denominator)
    return "\(value / scale)." +
        String(format: "%0*d", places, value % scale)
}

private func variation(_ values: [Int]) -> Int {
    let sum = values.reduce(0, +)
    return values.count * values.reduce(0) { $0 + $1 * $1 } - sum * sum
}

private struct Policy {
    let name: String
    let args: [Int]
    let description: String
}

private func parsePolicy(_ tokens: [String]) throws -> Policy {
    let name = tokens.first ?? ""
    guard let count = policyParameters[name] else {
        throw fail("unknown policy \(name)")
    }
    if tokens.count - 1 != count {
        throw fail("\(name) needs \(count) parameters")
    }
    let values = tokens.dropFirst().enumerated().map { index, token in
        Int(name == "STERMAN" && index < 3 ?
            token.replacingOccurrences(of: ".", with: "") : token)!
    }
    let valid: Bool
    switch name {
    case "FIXED": valid = 0...1000 ~= values[0]
    case "PASS": valid = true
    case "BASESTOCK": valid = 0...10000 ~= values[0]
    case "MINMAX": valid = 0 <= values[0] && values[0] < values[1] && values[1] <= 10000
    case "MOVAVG": valid = 1...52 ~= values[0] && 0...10000 ~= values[1]
    case "SMOOTH": valid = 1...10 ~= values[0] && 0...10000 ~= values[1]
    default:
        valid = values.prefix(3).allSatisfy { 0...100 ~= $0 } &&
            0...10000 ~= values[3]
    }
    if !valid { throw fail("invalid parameter for \(name)") }
    return Policy(name: name, args: values, description: tokens.joined(separator: " "))
}

private struct Initial {
    let inventory: Int
    let quantity: Int
    let shippingDelay: Int
    let orderDelay: Int
    let holding: Int
    let backlogRate: Int
    let policy: Policy
}

private struct Record {
    let received: Int
    let incoming: Int
    let shipped: Int
    let before: Int
    let ontime: Int
    let inventory: Int
    let backlog: Int
    var order = 0
    var holding = 0
    var backlogCost = 0
    var cost = 0
}

private struct PlantRecord {
    let incoming: Int
    let produced: Int
    let backlog: Int
}

private final class Stage {
    var inventory: Int
    var backlog = 0
    var shipping: [Int]
    var orders: [Int]
    var policy: Policy
    var expected: Int
    var holding: Int
    var backlogRate: Int
    var lot = 1
    var capacity: Int?
    var records: [Record] = []

    init(_ initial: Initial) {
        inventory = initial.inventory
        shipping = Array(repeating: initial.quantity, count: initial.shippingDelay)
        orders = Array(repeating: initial.quantity, count: initial.orderDelay)
        policy = initial.policy
        expected = 100 * initial.quantity
        holding = initial.holding
        backlogRate = initial.backlogRate
    }

    func copy() -> Stage {
        let initial = Initial(
            inventory: inventory, quantity: 0, shippingDelay: 0, orderDelay: 0,
            holding: holding, backlogRate: backlogRate, policy: policy
        )
        let result = Stage(initial)
        result.backlog = backlog
        result.shipping = shipping
        result.orders = orders
        result.expected = expected
        result.lot = lot
        result.capacity = capacity
        result.records = records
        return result
    }
}

private final class Simulation {
    let initials: [Initial]
    var week = 0
    var demands: [Int]
    var stages: [Stage]
    var plantBacklog = 0
    var plantCapacity: Int?
    var plantRecords: [PlantRecord] = []
    var visibility = "OFF"

    init(initials: [Initial], demands: [Int]) {
        self.initials = initials
        self.demands = demands
        stages = initials.map(Stage.init)
    }

    func copy() -> Simulation {
        let result = Simulation(initials: initials, demands: demands)
        result.week = week
        result.stages = stages.map { $0.copy() }
        result.plantBacklog = plantBacklog
        result.plantCapacity = plantCapacity
        result.plantRecords = plantRecords
        result.visibility = visibility
        return result
    }

    func signal(_ index: Int, _ observedWeek: Int, current: [Int]? = nil) -> Int {
        if visibility == "ON" { return demands[observedWeek - 1] }
        if let current, observedWeek == week + 1 { return current[index] }
        return stages[index].records[observedWeek - 1].incoming
    }

    func setPolicy(_ index: Int, _ policy: Policy) {
        let stage = stages[index]
        stage.policy = policy
        if policy.name == "STERMAN" {
            stage.expected = 100 * (week != 0 ?
                signal(index, week) : initials[index].quantity)
        }
    }

    func positions() -> ([Int], [Int]) {
        var supply: [Int] = []
        var positions: [Int] = []
        for (index, stage) in stages.enumerated() {
            let upstream = index < 3 ? stages[index + 1].backlog : plantBacklog
            let line = stage.orders.reduce(0, +) + upstream + stage.shipping.reduce(0, +)
            supply.append(line)
            positions.append(stage.inventory + line - stage.backlog)
        }
        return (supply, positions)
    }

    private func policyOrder(_ index: Int, incoming: [Int],
                             line: Int, position: Int) -> Int {
        let stage = stages[index]
        let policy = stage.policy
        let args = policy.args
        let thisWeek = week + 1
        let observed = signal(index, thisWeek, current: incoming)
        switch policy.name {
        case "FIXED":
            return args[0]
        case "PASS":
            return incoming[index]
        case "BASESTOCK":
            return max(0, args[0] - position)
        case "MINMAX":
            return position <= args[0] ? args[1] - position : 0
        case "MOVAVG":
            let k = min(args[0], thisWeek)
            let forecast = (thisWeek - k + 1...thisWeek).reduce(0) {
                $0 + signal(index, $1, current: incoming)
            } / k
            let delay = initials[index].shippingDelay + initials[index].orderDelay
            return max(0, args[1] + forecast * delay - position)
        case "SMOOTH":
            return max(0, observed + floorDiv(args[1] - position, args[0]))
        default:
            let theta = args[0]
            let alpha = args[1]
            let beta = args[2]
            let target = args[3]
            stage.expected = (100 * theta * observed +
                              (100 - theta) * stage.expected) / 100
            let net = stage.inventory - stage.backlog
            return max(
                0, floorDiv(
                    100 * stage.expected +
                    alpha * (100 * (target - net) - beta * line), 10000
                )
            )
        }
    }

    func step() -> [Record] {
        var received: [Int] = []
        for stage in stages {
            let amount = stage.shipping.removeFirst()
            stage.inventory += amount
            received.append(amount)
        }
        var incoming = [demands[week]]
        for i in 0..<3 { incoming.append(stages[i].orders.removeFirst()) }
        let plantIncoming = stages[3].orders.removeFirst()

        var records: [Record] = []
        for (index, stage) in stages.enumerated() {
            let before = stage.backlog
            let requested = before + incoming[index]
            var shipped = min(stage.inventory, requested)
            if let capacity = stage.capacity { shipped = min(shipped, capacity) }
            stage.inventory -= shipped
            stage.backlog = requested - shipped
            if index > 0 { stages[index - 1].shipping.append(shipped) }
            records.append(Record(
                received: received[index], incoming: incoming[index],
                shipped: shipped, before: before,
                ontime: min(max(0, shipped - before), incoming[index]),
                inventory: stage.inventory, backlog: stage.backlog
            ))
        }

        let requested = plantBacklog + plantIncoming
        let produced = min(requested, plantCapacity ?? requested)
        plantBacklog = requested - produced
        stages[3].shipping.append(produced)

        let (supply, positions) = positions()
        let orders = stages.indices.map {
            policyOrder($0, incoming: incoming, line: supply[$0], position: positions[$0])
        }
        for (index, stage) in stages.enumerated() {
            let quantity = (orders[index] + stage.lot - 1) / stage.lot * stage.lot
            stage.orders.append(quantity)
            records[index].order = quantity
            records[index].holding = stage.holding * stage.inventory
            records[index].backlogCost = stage.backlogRate * stage.backlog
            records[index].cost = records[index].holding + records[index].backlogCost
            stage.records.append(records[index])
        }
        plantRecords.append(PlantRecord(
            incoming: plantIncoming, produced: produced, backlog: plantBacklog
        ))
        week += 1
        return records
    }

    func costs() -> [Int] {
        stages.map { $0.records.reduce(0) { $0 + $1.cost } }
    }
}

private struct CompareRow {
    let cost: Int
    let index: Int
    let description: String
    let fill: String
    let bullwhip: String
}

private final class Game {
    private let initials: [Initial]
    private var base: [Int] = []
    private var simulation: Simulation
    private var snapshots: [String: Simulation] = [:]
    private(set) var output: [String] = []

    init(_ settings: [[String]]) {
        initials = settings.map { fields in
            Initial(
                inventory: Int(fields[1])!, quantity: Int(fields[2])!,
                shippingDelay: Int(fields[3])!, orderDelay: Int(fields[4])!,
                holding: Int(fields[5])!, backlogRate: Int(fields[6])!,
                policy: try! parsePolicy(Array(fields.dropFirst(7)))
            )
        }
        simulation = Simulation(initials: initials, demands: [])
    }

    private func emit(_ parts: Any...) {
        output.append(parts.map { String(describing: $0) }.joined(separator: " "))
    }

    private func stageIndex(_ text: String) throws -> Int {
        guard let index = stageNames.firstIndex(of: text) else {
            throw fail("unknown stage \(text)")
        }
        return index
    }

    private func target(_ text: String) throws -> [Int] {
        text == "ALL" ? Array(0..<4) : [try stageIndex(text)]
    }

    private func requireWeeks() throws {
        if simulation.week == 0 { throw fail("no weeks simulated") }
    }

    private func rangeCheck(_ arguments: [String], limit: Int) throws -> (Int, Int) {
        if arguments.isEmpty { return (1, limit) }
        let first = Int(arguments[0])!
        let last = Int(arguments[1])!
        if first < 1 || first > last || last > limit {
            throw fail("bad range \(arguments[0]) \(arguments[1])")
        }
        return (first, last)
    }

    private func modeCheck(_ mode: String) throws {
        if !["ORDERS", "INV", "BACK", "NET"].contains(mode) {
            throw fail("unknown mode \(mode)")
        }
    }

    private func values(_ index: Int, mode: String) -> [Int] {
        simulation.stages[index].records.map { record in
            switch mode {
            case "NET": return record.inventory - record.backlog
            case "ORDERS": return record.order
            case "INV": return record.inventory
            default: return record.backlog
            }
        }
    }

    private func initialize(_ demands: [Int]? = nil) {
        if let demands { base = demands }
        simulation = Simulation(initials: initials, demands: base)
    }

    private func trial(_ policies: [Policy]) -> Simulation {
        let current = simulation
        let test = Simulation(initials: initials, demands: current.demands)
        test.visibility = current.visibility
        test.plantCapacity = current.plantCapacity
        for index in 0..<4 {
            let previous = current.stages[index]
            let stage = test.stages[index]
            stage.lot = previous.lot
            stage.capacity = previous.capacity
            stage.holding = previous.holding
            stage.backlogRate = previous.backlogRate
            test.setPolicy(index, policies[index])
        }
        while test.week < test.demands.count {
            _ = test.step()
        }
        return test
    }

    private func demand(_ values: [Int]) {
        initialize(values)
        emit(
            "DEMAND", "weeks", values.count, "total", values.reduce(0, +),
            "min", values.min()!, "max", values.max()!
        )
    }

    private func generate(_ a: [String]) throws {
        let weeks = Int(a[0])!
        let baseLevel = Int(a[1])!
        let spread = Int(a[2])!
        var seed = Int(a[3])!
        var changes: [(String, Int, Int)] = []
        var i = 4
        while i < a.count {
            changes.append((a[i], Int(a[i + 1])!, Int(a[i + 2])!))
            i += 3
        }
        for (_, week, _) in changes {
            if week < 1 || week > weeks {
                throw fail("week \(week) outside horizon")
            }
        }
        var levels: [Int] = []
        for week in 1...weeks {
            var level = baseLevel
            for (kind, start, amount) in changes {
                if kind == "STEP" && week >= start {
                    level += amount
                } else if kind == "PULSE" && week == start {
                    level += amount
                } else if kind == "RAMP" && week >= start {
                    level += amount * (week - start + 1)
                }
            }
            if level < 0 { throw fail("negative level at week \(week)") }
            levels.append(level)
        }
        let values = levels.map { level -> Int in
            seed = 48271 * seed % 2147483647
            return level + seed % spread
        }
        demand(values)
    }

    private func showStatus() {
        let s = simulation
        emit("STATUS", "week", s.week, "of", s.demands.count)
        let (supply, positions) = s.positions()
        for (index, stage) in s.stages.enumerated() {
            var text = "\(stageNames[index]) inv \(stage.inventory) back \(stage.backlog) " +
                "transit \(stage.shipping.map(String.init).joined(separator: ",")) " +
                "pending \(stage.orders.map(String.init).joined(separator: ",")) " +
                "supply \(supply[index]) position \(positions[index]) policy \(stage.policy.description)"
            if stage.policy.name == "STERMAN" {
                text += " expect \(money(stage.expected))"
            }
            emit(text)
        }
        emit("PLANT", "back", s.plantBacklog)
    }

    private func showWeek(_ week: Int) {
        let s = simulation
        emit("WEEK", week, "demand", s.demands[week - 1])
        for (index, stage) in s.stages.enumerated() {
            let record = stage.records[week - 1]
            emit(
                stageNames[index], "recv", record.received, "in", record.incoming,
                "ship", record.shipped, "inv", record.inventory, "back", record.backlog,
                "order", record.order, "cost", money(record.cost)
            )
        }
        let plant = s.plantRecords[week - 1]
        emit("PLANT", "in", plant.incoming, "made", plant.produced, "back", plant.backlog)
    }

    private func table(_ index: Int, first: Int, last: Int) {
        let labels = ["week", "in", "ship", "recv", "inv", "back", "order", "cost"]
        let widths = [4, 6, 6, 6, 6, 6, 6, 9]
        func format(_ words: [String]) -> String {
            zip(words, widths).map { word, width in
                String(repeating: " ", count: max(0, width - word.count)) + word
            }.joined(separator: " ")
        }
        emit("TABLE", stageNames[index], "\(first)-\(last)")
        emit(format(labels))
        for week in first...last {
            let r = simulation.stages[index].records[week - 1]
            emit(format([
                "\(week)", "\(r.incoming)", "\(r.shipped)", "\(r.received)",
                "\(r.inventory)", "\(r.backlog)", "\(r.order)", money(r.cost)
            ]))
        }
    }

    private func costs() {
        emit("COSTS", "week", simulation.week)
        var totalHolding = 0
        var totalBacklog = 0
        for (index, stage) in simulation.stages.enumerated() {
            let holding = stage.records.reduce(0) { $0 + $1.holding }
            let backlog = stage.records.reduce(0) { $0 + $1.backlogCost }
            totalHolding += holding
            totalBacklog += backlog
            emit(
                stageNames[index], "holding", money(holding), "backlog", money(backlog),
                "total", money(holding + backlog)
            )
        }
        emit(
            "TOTAL", "holding", money(totalHolding), "backlog", money(totalBacklog),
            "total", money(totalHolding + totalBacklog)
        )
    }

    private func fillText(_ records: [Record]) -> (Int, Int, String) {
        let ordered = records.reduce(0) { $0 + $1.incoming }
        let ontime = records.reduce(0) { $0 + $1.ontime }
        let fill = ordered == 0 ? "n/a" :
            decimal(ontime * 100, ordered, places: 2) + "%"
        return (ordered, ontime, fill)
    }

    private func bullwhip() {
        let s = simulation
        let n = s.week
        let demands = Array(s.demands.prefix(n))
        let demandVariance = variation(demands)
        emit(
            "BULLWHIP", "weeks", "1-\(n)", "demand",
            "mean", decimal(demands.reduce(0, +), n, places: 4),
            "var", decimal(demandVariance, n * n, places: 4)
        )
        var previous = demandVariance
        for (index, stage) in s.stages.enumerated() {
            let orders = stage.records.map { $0.order }
            let variance = variation(orders)
            emit(
                stageNames[index], "mean", decimal(orders.reduce(0, +), n, places: 4),
                "var", decimal(variance, n * n, places: 4),
                "ratio", demandVariance == 0 ? "n/a" :
                    decimal(variance, demandVariance, places: 4),
                "step", previous == 0 ? "n/a" :
                    decimal(variance, previous, places: 4)
            )
            previous = variance
        }
    }

    private func peaks() {
        let s = simulation
        emit("PEAKS", "weeks", "1-\(s.week)")
        for (index, stage) in s.stages.enumerated() {
            let inventories = stage.records.map { $0.inventory }
            let backlogs = stage.records.map { $0.backlog }
            let maximumInventory = inventories.max()!
            let maximumBacklog = backlogs.max()!
            var longest = 0
            var run = 0
            var start = 0
            var bestStart = 0
            var bestEnd = 0
            for (position, backlog) in backlogs.enumerated() {
                let week = position + 1
                if backlog > 0 {
                    if run == 0 { start = week }
                    run += 1
                    if run > longest {
                        longest = run
                        bestStart = start
                        bestEnd = week
                    }
                } else {
                    run = 0
                }
            }
            emit(
                stageNames[index], "max_inv", maximumInventory,
                "week", maximumInventory == 0 ? "-" :
                    "\(inventories.firstIndex(of: maximumInventory)! + 1)",
                "max_back", maximumBacklog,
                "week", maximumBacklog == 0 ? "-" :
                    "\(backlogs.firstIndex(of: maximumBacklog)! + 1)",
                "longest_stockout", longest == 0 ? "0" :
                    "\(longest) weeks \(bestStart)-\(bestEnd)"
            )
        }
    }

    private func leadtime(_ index: Int) {
        let stage = simulation.stages[index]
        let initial = initials[index]
        let nominal = initial.shippingDelay + initial.orderDelay
        var received = 0
        var cumulative: [Int] = []
        for record in stage.records {
            received += record.received
            cumulative.append(received - nominal * initial.quantity)
        }
        var ordered = 0
        var count = 0
        var leads: [Int] = []
        for (position, record) in stage.records.enumerated() {
            ordered += record.order
            if record.order == 0 { continue }
            count += 1
            for u in (position + 1)..<stage.records.count {
                if cumulative[u] >= ordered {
                    leads.append(u - position)
                    break
                }
            }
        }
        emit(
            "LEADTIME", stageNames[index], "nominal", nominal, "orders", count,
            "completed", leads.count, "open", count - leads.count,
            "min", leads.min().map(String.init) ?? "-",
            "avg", leads.isEmpty ? "-" :
                decimal(leads.reduce(0, +), leads.count, places: 2),
            "max", leads.max().map(String.init) ?? "-"
        )
    }

    private func plot(_ index: Int, mode: String, first: Int, last: Int) {
        let numbers = Array(values(index, mode: mode)[first - 1..<last])
        let maximum = numbers.max()!
        if mode == "NET" {
            emit(
                "PLOT", stageNames[index], mode, "\(first)-\(last)",
                "min", numbers.min()!, "max", maximum
            )
            let scale = numbers.map { abs($0) }.max()!
            for (offset, value) in numbers.enumerated() {
                let week = first + offset
                let length = scale == 0 ? 0 : abs(value) * 25 / scale
                let left = value < 0 ?
                    String(repeating: " ", count: 25 - length) +
                    String(repeating: "-", count: length) :
                    String(repeating: " ", count: 25)
                let right = value > 0 ? String(repeating: "+", count: length) : ""
                emit(String(format: "%3d", week) + " \(left)|\(right) \(value)")
            }
        } else {
            emit("PLOT", stageNames[index], mode, "\(first)-\(last)", "max", maximum)
            for (offset, value) in numbers.enumerated() {
                let length = maximum == 0 ? 0 : value * 50 / maximum
                emit(
                    String(format: "%3d", first + offset) + " |" +
                    String(repeating: "#", count: length) + " \(value)"
                )
            }
        }
    }

    private func command(_ name: String, _ a: [String]) throws {
        let s = simulation
        switch name {
        case "DEMAND":
            demand(a.map { Int($0)! })
        case "GENERATE":
            try generate(a)
        case "RUN":
            if s.week == s.demands.count {
                throw fail("horizon reached at week \(s.demands.count)")
            }
            let first = s.week + 1
            let count = min(Int(a[0])!, s.demands.count - s.week)
            var cost = 0
            for _ in 0..<count {
                let records = s.step()
                for (index, record) in records.enumerated() {
                    cost += record.cost
                    if record.before == 0 && record.backlog > 0 {
                        emit(
                            "STOCKOUT", stageNames[index], "week", s.week,
                            "backlog", record.backlog
                        )
                    } else if record.before > 0 && record.backlog == 0 {
                        emit("RECOVER", stageNames[index], "week", s.week)
                    }
                }
            }
            let total = s.demands[first - 1..<s.week].reduce(0, +)
            emit("RUN", "\(first)-\(s.week)", "demand", total, "cost", money(cost))
            if s.week == s.demands.count { emit("HORIZON", s.week) }
        case "RESET":
            initialize()
            emit("RESET", "week", 0)
        case "SAVE":
            snapshots[a[0]] = s.copy()
            emit("SAVE", a[0], "week", s.week)
        case "LOAD":
            guard let snapshot = snapshots[a[0]] else {
                throw fail("no snapshot \(a[0])")
            }
            simulation = snapshot.copy()
            emit("LOAD", a[0], "week", simulation.week)
        case "SET":
            let targets = try target(a[0])
            let policy = try parsePolicy(Array(a.dropFirst()))
            for index in targets { s.setPolicy(index, policy) }
            emit("SET", a[0], policy.description)
        case "BATCH":
            let index = try stageIndex(a[0])
            let lot = Int(a[1])!
            if !(1...100).contains(lot) {
                throw fail("invalid batch size \(a[1])")
            }
            s.stages[index].lot = lot
            emit("BATCH", a[0], lot)
        case "CAPACITY":
            let index = a[0] == "PLANT" ? nil : try stageIndex(a[0])
            let capacity = a[1] == "OFF" ? nil : Int(a[1])
            if let capacity, capacity > 10000 {
                throw fail("invalid capacity \(a[1])")
            }
            if let index {
                s.stages[index].capacity = capacity
            } else {
                s.plantCapacity = capacity
            }
            emit("CAPACITY", a[0], a[1])
        case "COST":
            let index = try stageIndex(a[0])
            let holding = Int(a[1])!
            let backlog = Int(a[2])!
            if holding > 1000 || backlog > 1000 { throw fail("invalid cost") }
            s.stages[index].holding = holding
            s.stages[index].backlogRate = backlog
            emit("COST", a[0], "holding", holding, "backlog", backlog)
        case "VISIBILITY":
            if !["ON", "OFF"].contains(a[0]) {
                throw fail("unknown visibility \(a[0])")
            }
            s.visibility = a[0]
            emit("VISIBILITY", a[0])
        case "SHOCK":
            let week = Int(a[0])!
            let demand = Int(a[1])!
            if week < 1 || week > s.demands.count {
                throw fail("week \(a[0]) outside horizon")
            }
            if week <= s.week { throw fail("week \(a[0]) already simulated") }
            let old = s.demands[week - 1]
            s.demands[week - 1] = demand
            emit("SHOCK", "week", week, old, "->", demand)
        case "STATUS":
            showStatus()
        case "SETTINGS":
            emit("SETTINGS")
            for (index, stage) in s.stages.enumerated() {
                let initial = initials[index]
                emit(
                    stageNames[index], "holding", stage.holding,
                    "backlog", stage.backlogRate, "batch", stage.lot,
                    "capacity", stage.capacity.map(String.init) ?? "OFF",
                    "delays", initial.shippingDelay, initial.orderDelay
                )
            }
            emit("PLANT", "capacity", s.plantCapacity.map(String.init) ?? "OFF")
            emit("VISIBILITY", s.visibility)
        case "WEEK":
            try requireWeeks()
            let week = Int(a[0])!
            if !(1...s.week).contains(week) { throw fail("bad week \(a[0])") }
            showWeek(week)
        case "TABLE":
            let index = try stageIndex(a[0])
            try requireWeeks()
            let (first, last) = try rangeCheck(Array(a.dropFirst()), limit: s.week)
            table(index, first: first, last: last)
        case "CHAIN":
            try requireWeeks()
            let (first, last) = try rangeCheck(a, limit: s.week)
            emit("CHAIN", "\(first)-\(last)")
            let header = "week".padStart(4) + " " + "demand".padStart(6) +
                " " + stageNames.map { $0.padStart(11) }.joined(separator: " ")
            emit(header)
            for week in first...last {
                let orders = s.stages.map { $0.records[week - 1].order }
                let values = orders.map { String(format: "%11d", $0) }.joined(separator: " ")
                emit(
                    String(format: "%4d %6d ", week, s.demands[week - 1]) + values
                )
            }
        case "DEMANDS":
            let (first, last) = try rangeCheck(a, limit: s.demands.count)
            let numbers = Array(s.demands[first - 1..<last])
            emit(
                "DEMANDS", "\(first)-\(last)", "total", numbers.reduce(0, +),
                "min", numbers.min()!, "max", numbers.max()!
            )
            emit(numbers.map(String.init).joined(separator: " "))
        case "COSTS":
            costs()
        case "SUMMARY":
            try requireWeeks()
            emit("SUMMARY", "weeks", "1-\(s.week)")
            for (index, stage) in s.stages.enumerated() {
                let orders = stage.records.map { $0.order }
                emit(
                    stageNames[index], "avg_inv",
                    decimal(stage.records.reduce(0) { $0 + $1.inventory }, s.week, places: 2),
                    "avg_back",
                    decimal(stage.records.reduce(0) { $0 + $1.backlog }, s.week, places: 2),
                    "orders", orders.reduce(0, +),
                    "min", orders.min()!, "max", orders.max()!,
                    "zero_weeks", orders.filter { $0 == 0 }.count
                )
            }
        case "BALANCE":
            emit("BALANCE", "week", s.week)
            for (index, stage) in s.stages.enumerated() {
                emit(
                    stageNames[index], "start", initials[index].inventory,
                    "received", stage.records.reduce(0) { $0 + $1.received },
                    "shipped", stage.records.reduce(0) { $0 + $1.shipped },
                    "end", stage.inventory, "owed", stage.backlog
                )
            }
            let initialGoods = initials.reduce(0) {
                $0 + $1.inventory + $1.quantity * $1.shippingDelay
            }
            emit(
                "SYSTEM", "initial", initialGoods,
                "produced", s.plantRecords.reduce(0) { $0 + $1.produced },
                "delivered", s.stages[0].records.reduce(0) { $0 + $1.shipped },
                "stock", s.stages.reduce(0) { $0 + $1.inventory },
                "transit", s.stages.reduce(0) { $0 + $1.shipping.reduce(0, +) }
            )
        case "FILLRATE":
            try requireWeeks()
            emit("FILLRATE", "weeks", "1-\(s.week)")
            for (index, stage) in s.stages.enumerated() {
                let (ordered, ontime, fill) = fillText(stage.records)
                let stockouts = stage.records.filter { $0.backlog > 0 }.count
                emit(
                    stageNames[index], "fill", fill, "ontime", ontime,
                    "ordered", ordered, "stockout_weeks", stockouts,
                    "service", decimal(
                        (s.week - stockouts) * 100, s.week, places: 2
                    ) + "%"
                )
            }
        case "BULLWHIP":
            try requireWeeks()
            bullwhip()
        case "PEAKS":
            try requireWeeks()
            peaks()
        case "LEADTIME":
            let index = try stageIndex(a[0])
            try requireWeeks()
            leadtime(index)
        case "PLOT", "HISTOGRAM":
            let index = try stageIndex(a[0])
            try modeCheck(a[1])
            let width = name == "HISTOGRAM" ? Int(a[2])! : 0
            if name == "HISTOGRAM" && !(1...100).contains(width) {
                throw fail("invalid width \(a[2])")
            }
            try requireWeeks()
            if name == "PLOT" {
                let (first, last) = try rangeCheck(Array(a.dropFirst(2)), limit: s.week)
                plot(index, mode: a[1], first: first, last: last)
            } else {
                var histogram: [Int: Int] = [:]
                for value in values(index, mode: a[1]) {
                    histogram[floorDiv(value, width), default: 0] += 1
                }
                emit(
                    "HISTOGRAM", a[0], a[1], "width", width, "weeks", "1-\(s.week)"
                )
                for bucket in histogram.keys.min()!...histogram.keys.max()! {
                    let count = histogram[bucket, default: 0]
                    let label = "\(bucket * width)..\(bucket * width + width - 1)"
                    if count != 0 {
                        emit(label, count, String(repeating: "*", count: count))
                    } else {
                        emit(label, count)
                    }
                }
            }
        case "COMPARE":
            var policies: [Policy] = []
            var start = 0
            for end in 0...a.count {
                if end == a.count || a[end] == "/" {
                    policies.append(try parsePolicy(Array(a[start..<end])))
                    start = end + 1
                }
            }
            var rows: [CompareRow] = []
            for (index, policy) in policies.enumerated() {
                let result = trial(Array(repeating: policy, count: 4))
                let cost = result.costs().reduce(0, +)
                let fill = fillText(result.stages[0].records).2
                let demandVariance = variation(result.demands)
                let factoryVariance = variation(result.stages[3].records.map { $0.order })
                let ratio = demandVariance == 0 ? "n/a" :
                    decimal(factoryVariance, demandVariance, places: 4)
                rows.append(CompareRow(
                    cost: cost, index: index, description: policy.description,
                    fill: fill, bullwhip: ratio
                ))
            }
            rows.sort {
                $0.cost != $1.cost ? $0.cost < $1.cost : $0.index < $1.index
            }
            emit("COMPARE", policies.count, "weeks", s.demands.count)
            for (index, row) in rows.enumerated() {
                emit(
                    index + 1, row.description, "total", money(row.cost),
                    "fill", row.fill, "bullwhip", row.bullwhip
                )
            }
        case "OPTIMIZE":
            let indices = try target(a[0])
            let low = Int(a[1])!
            let high = Int(a[2])!
            if low > high { throw fail("bad range \(a[1]) \(a[2])") }
            if high - low > 200 { throw fail("range too large") }
            var best: (Int, Int, Int)?
            for value in low...high {
                var policies = s.stages.map { $0.policy }
                for index in indices {
                    policies[index] = Policy(
                        name: "BASESTOCK", args: [value],
                        description: "BASESTOCK \(value)"
                    )
                }
                let costs = trial(policies).costs()
                let objective = indices.reduce(0) { $0 + costs[$1] }
                let total = costs.reduce(0, +)
                if best == nil || objective < best!.0 ||
                    (objective == best!.0 && value < best!.1) {
                    best = (objective, value, total)
                }
            }
            emit(
                "OPTIMIZE", a[0], "BASESTOCK", best!.1,
                "cost", money(best!.0), "total", money(best!.2)
            )
        default:
            throw fail("unknown command \(name)")
        }
    }

    func execute(_ line: String) {
        let fields = line.split(separator: " ").map(String.init)
        if fields.isEmpty { return }
        do {
            try command(fields[0], Array(fields.dropFirst()))
        } catch GameError.invalid(let reason) {
            emit("ERROR", reason)
        } catch {
            fatalError("Unexpected error: \(error)")
        }
    }
}

let input = String(
    data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8
)!.split(whereSeparator: \.isNewline).map(String.init)
let settings = (0..<4).map { input[$0].split(separator: " ").map(String.init) }
let game = Game(settings)
for line in input.dropFirst(4) {
    if line == "END" { break }
    game.execute(line)
}
if !game.output.isEmpty { print(game.output.joined(separator: "\n")) }
