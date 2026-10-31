import Foundation

struct WeeklyQuantity { let item: String; let week: Int; let quantity: Int; let line: Int }
struct Inquiry { let id: String; let item: String; let quantity: Int; let week: Int; let line: Int }
struct Placement { let inquiry: Inquiry; let week: Int }
struct Demand {
    let item: String
    let week: Int
    let kind: String
    let quantity: Int
    var line = 0
    var orderID = ""
    var parent = ""
    var parentOrder = 0
}
struct PlannedOrder { let item: String; let number: Int; let receipt: Int; let quantity: Int; let originalRelease: Int; let release: Int }
struct OrderKey: Hashable { let item: String; let number: Int }
struct WeekKey: Hashable { let item: String; let week: Int }

final class ItemPlan {
    let demands: [Demand]
    var gross: [Int]
    var receipts: [Int]
    var onHand: [Int]
    var net: [Int]
    var plannedReceipts: [Int]
    var plannedReleases: [Int]
    var orders: [PlannedOrder] = []
    var pastDue: Int { orders.filter { $0.originalRelease < 1 }.reduce(0) { $0 + $1.quantity } }

    init(demands: [Demand], horizon: Int) {
        self.demands = demands
        gross = Array(repeating: 0, count: horizon + 1)
        receipts = gross; onHand = gross; net = gross; plannedReceipts = gross; plannedReleases = gross
    }
}

struct Plan { let items: [String: ItemPlan]; let loads: [String: [Int]] }
struct Promise { let inquiry: Inquiry; let promised: Int?; let material: Int?; let reason: String }

final class Planner {
    let items: [String: Item]
    let bom: Bom
    let centers: [String: WorkCenter]
    let routings: [String: [Operation]]
    let mps: [WeeklyQuantity]
    let receipts: [WeeklyQuantity]
    let horizon: Int
    let codes: [String: Int]
    let cumulative: [String: Int]
    let order: [String]
    let receiptsByItem: [String: [WeeklyQuantity]]

    init(items: [String: Item], bom: Bom, centers: [String: WorkCenter], routings: [String: [Operation]], mps: [WeeklyQuantity], receipts: [WeeklyQuantity], horizon: Int) {
        self.items = items; self.bom = bom; self.centers = centers; self.routings = routings
        self.mps = mps; self.receipts = receipts; self.horizon = horizon
        let codes = bom.lowLevelCodes()
        self.codes = codes
        cumulative = bom.cumulativeLeadTimes(items)
        order = items.keys.sorted { codes[$0]! == codes[$1]! ? $0 < $1 : codes[$0]! < codes[$1]! }
        receiptsByItem = Dictionary(grouping: receipts, by: { $0.item }).mapValues { $0.sorted { $0.week == $1.week ? $0.line < $1.line : $0.week < $1.week } }
    }

    func run(_ placements: [Placement]) -> Plan {
        var demands = Dictionary(uniqueKeysWithValues: items.keys.map { ($0, [Demand]()) })
        for row in mps { demands[row.item]!.append(Demand(item: row.item, week: row.week, kind: "MPS", quantity: row.quantity, line: row.line)) }
        for placement in placements {
            let inquiry = placement.inquiry
            demands[inquiry.item]!.append(Demand(item: inquiry.item, week: placement.week, kind: "ORDER", quantity: inquiry.quantity, line: inquiry.line, orderID: inquiry.id))
        }
        var plans: [String: ItemPlan] = [:]
        for id in order {
            let item = items[id]!
            let plan = ItemPlan(demands: demands[id]!, horizon: horizon)
            for demand in plan.demands { plan.gross[demand.week] += demand.quantity }
            for receipt in receiptsByItem[id, default: []] { plan.receipts[receipt.week] += receipt.quantity }
            plan.onHand[0] = item.onHand
            for week in 1...horizon {
                let available = plan.onHand[week - 1] + plan.receipts[week] - plan.gross[week]
                if available < item.safety {
                    plan.net[week] = item.safety - available
                    let quantity = lotSize(item, week: week, projected: available, receipts: plan.receipts, gross: plan.gross, horizon: horizon)
                    let original = week - item.leadTime
                    let release = max(1, original)
                    plan.orders.append(PlannedOrder(item: id, number: plan.orders.count + 1, receipt: week, quantity: quantity, originalRelease: original, release: release))
                    plan.plannedReceipts[week] = quantity
                    plan.plannedReleases[release] += quantity
                }
                plan.onHand[week] = available + plan.plannedReceipts[week]
            }
            plans[id] = plan
            for planned in plan.orders {
                for row in bom.children[id]! { demands[row.child]!.append(Demand(item: row.child, week: planned.release, kind: "DEPENDENT", quantity: row.need(planned.quantity), parent: id, parentOrder: planned.number)) }
            }
        }
        var loads = Dictionary(uniqueKeysWithValues: centers.keys.map { ($0, Array(repeating: 0, count: horizon + 1)) })
        for id in order {
            for planned in plans[id]!.orders {
                let operations = routings[id, default: []]
                for (index, operation) in operations.enumerated() {
                    let week = operationWeek(receipt: planned.receipt, leadTime: items[id]!.leadTime, index: index, count: operations.count)
                    loads[operation.center]![week] += operation.minutes(planned.quantity)
                }
            }
        }
        return Plan(items: plans, loads: loads)
    }

    func promise(_ inquiries: [Inquiry]) -> (base: Plan, finalPlan: Plan, promises: [Promise]) {
        let base = run([])
        var current = base
        var placements: [Placement] = []
        var promises: [Promise] = []
        for inquiry in inquiries {
            var promised: Int?
            var material: Int?
            var firstReason = ""
            for week in inquiry.week...horizon {
                let placement = Placement(inquiry: inquiry, week: week)
                let trial = run(placements + [placement])
                var reason = order.first { trial.items[$0]!.pastDue > current.items[$0]!.pastDue }
                if reason == nil {
                    if material == nil { material = week }
                    capacityCheck: for center in centers.keys.sorted() {
                        for period in 1...horizon {
                            let available = centers[center]!.available
                            if max(0, trial.loads[center]![period] - available) > max(0, current.loads[center]![period] - available) {
                                reason = "\(center) week \(period)"
                                break capacityCheck
                            }
                        }
                    }
                }
                if week == inquiry.week { firstReason = reason ?? "" }
                if reason == nil {
                    promised = week
                    placements.append(placement)
                    current = trial
                    break
                }
            }
            promises.append(Promise(inquiry: inquiry, promised: promised, material: material, reason: firstReason))
        }
        return (base, current, promises)
    }
}

struct Allocation { let demand: Demand; let share: Int }
final class Supply {
    let kind: String
    let item: String
    let week: Int
    let quantity: Int
    let line: Int
    let planned: PlannedOrder?
    var excess: Int
    var allocations: [Allocation] = []

    init(kind: String, item: String, week: Int, quantity: Int, line: Int = 0, planned: PlannedOrder? = nil) {
        self.kind = kind; self.item = item; self.week = week; self.quantity = quantity; self.line = line; self.planned = planned
        excess = quantity
    }
}
struct RootDemand: Hashable { let item: String; let kind: String; let week: Int; let orderID: String }

final class Pegging {
    let planner: Planner
    let plan: Plan
    var supplies: [String: [Supply]] = [:]
    var plannedSupplies: [OrderKey: Supply] = [:]
    var rootCache: [OrderKey: Set<RootDemand>] = [:]

    init(planner: Planner, plan: Plan) {
        self.planner = planner; self.plan = plan
        for id in planner.order {
            let item = planner.items[id]!
            let itemPlan = plan.items[id]!
            var demands: [Demand] = []
            if item.safety > 0 { demands.append(Demand(item: id, week: 0, kind: "SAFETY", quantity: item.safety)) }
            let kindOrder = ["MPS": 0, "ORDER": 1, "DEPENDENT": 2]
            demands += itemPlan.demands.sorted {
                if $0.week != $1.week { return $0.week < $1.week }
                if $0.kind != $1.kind { return kindOrder[$0.kind]! < kindOrder[$1.kind]! }
                if $0.kind == "ORDER" { return $0.line < $1.line }
                return $0.parent == $1.parent ? $0.parentOrder < $1.parentOrder : $0.parent < $1.parent
            }
            var itemSupplies: [Supply] = []
            if item.onHand > 0 { itemSupplies.append(Supply(kind: "STOCK", item: id, week: 0, quantity: item.onHand)) }
            var arrivals = planner.receiptsByItem[id, default: []].map { Supply(kind: "RECEIPT", item: id, week: $0.week, quantity: $0.quantity, line: $0.line) }
            for order in itemPlan.orders {
                let supply = Supply(kind: "ORDER", item: id, week: order.receipt, quantity: order.quantity, planned: order)
                arrivals.append(supply)
                plannedSupplies[OrderKey(item: id, number: order.number)] = supply
            }
            itemSupplies += arrivals.sorted {
                if $0.week != $1.week { return $0.week < $1.week }
                if $0.kind != $1.kind { return $0.kind == "RECEIPT" }
                return $0.line < $1.line
            }
            var supplyIndex = 0
            for demand in demands {
                var remaining = demand.quantity
                while remaining > 0 {
                    while itemSupplies[supplyIndex].excess == 0 { supplyIndex += 1 }
                    let supply = itemSupplies[supplyIndex]
                    let share = min(remaining, supply.excess)
                    supply.allocations.append(Allocation(demand: demand, share: share))
                    supply.excess -= share
                    remaining -= share
                }
            }
            supplies[id] = itemSupplies
        }
    }

    func roots(_ key: OrderKey) -> Set<RootDemand> {
        if let roots = rootCache[key] { return roots }
        var result: Set<RootDemand> = []
        for allocation in plannedSupplies[key]!.allocations {
            let demand = allocation.demand
            if demand.kind == "DEPENDENT" { result.formUnion(roots(OrderKey(item: demand.parent, number: demand.parentOrder))) }
            else { result.insert(RootDemand(item: demand.item, kind: demand.kind, week: demand.week, orderID: demand.orderID)) }
        }
        rootCache[key] = result
        return result
    }

    func allocationLines(_ supply: Supply, depth: Int, recurse: Bool) -> [String] {
        var lines: [String] = []
        for allocation in supply.allocations {
            let demand = allocation.demand
            let detail: String
            switch demand.kind {
            case "SAFETY": detail = "SAFETY \(demand.item)"
            case "MPS": detail = "MPS \(demand.item) week \(demand.week)"
            case "ORDER": detail = "ORDER \(demand.orderID) \(demand.item) week \(demand.week)"
            default: detail = "\(demand.parent) order \(demand.parentOrder) week \(demand.week)"
            }
            lines.append(String(repeating: " ", count: 2 * depth) + "ALLOC \(allocation.share) \(detail)")
            if recurse && demand.kind == "DEPENDENT" {
                lines += allocationLines(plannedSupplies[OrderKey(item: demand.parent, number: demand.parentOrder)]!, depth: depth + 1, recurse: true)
            }
        }
        return lines
    }

    func report(_ ids: [String]) -> [String] {
        var lines: [String] = []
        func whereUsed(_ id: String, _ depth: Int, _ cumulative: Int) {
            for row in planner.bom.parents[id]! {
                let extended = cumulative * row.quantity
                lines.append("\(String(repeating: ".", count: depth))\(depth) \(row.parent) qty \(row.quantity) ext \(extended)")
                whereUsed(row.parent, depth + 1, extended)
            }
        }
        let kindOrder = ["MPS": 0, "ORDER": 1, "SAFETY": 2]
        for id in ids {
            lines.append("PEG \(id) orders \(plan.items[id]!.orders.count)")
            whereUsed(id, 1, 1)
            let itemSupplies = supplies[id]!
            let ordered = itemSupplies.filter { $0.kind == "STOCK" } + itemSupplies.filter { $0.kind == "RECEIPT" } + itemSupplies.filter { $0.kind == "ORDER" }.sorted { $0.planned!.number < $1.planned!.number }
            for supply in ordered {
                if supply.kind == "STOCK" { lines.append("STOCK quantity \(supply.quantity)") }
                else if supply.kind == "RECEIPT" { lines.append("RECEIPT line \(supply.line) week \(supply.week) quantity \(supply.quantity)") }
                else {
                    let order = supply.planned!
                    lines.append("ORDER \(order.number) receipt \(order.receipt) release \(order.release) quantity \(order.quantity)")
                }
                lines += allocationLines(supply, depth: 1, recurse: supply.kind == "ORDER")
                if supply.excess > 0 { lines.append("  EXCESS \(supply.excess)") }
                if let order = supply.planned {
                    let demands = roots(OrderKey(item: id, number: order.number)).sorted {
                        if $0.item != $1.item { return $0.item < $1.item }
                        if $0.kind != $1.kind { return kindOrder[$0.kind]! < kindOrder[$1.kind]! }
                        return $0.week == $1.week ? $0.orderID < $1.orderID : $0.week < $1.week
                    }
                    for root in demands {
                        switch root.kind {
                        case "SAFETY": lines.append("  ROOT SAFETY \(root.item)")
                        case "MPS": lines.append("  ROOT MPS \(root.item) week \(root.week)")
                        default: lines.append("  ROOT ORDER \(root.orderID) \(root.item) week \(root.week)")
                        }
                    }
                }
            }
        }
        return lines
    }
}

func gridReport(_ planner: Planner, _ plan: Plan) -> [String] {
    var lines: [String] = []
    for id in planner.order {
        let item = planner.items[id]!
        let p = plan.items[id]!
        lines.append("ITEM \(id) LLC \(planner.codes[id]!) LT \(item.leadTime) LOT \(item.lotLabel) SS \(item.safety) OH \(item.onHand) \(item.description)")
        let rows = [("WEEK", Array(1...planner.horizon)), ("GROSS", Array(p.gross.dropFirst())), ("RECEIPTS", Array(p.receipts.dropFirst())), ("ON_HAND", Array(p.onHand.dropFirst())), ("NET", Array(p.net.dropFirst())), ("PLAN_RCPT", Array(p.plannedReceipts.dropFirst())), ("PLAN_REL", Array(p.plannedReleases.dropFirst()))]
        for (label, values) in rows { lines.append(tableRow(label, values: values, width: 6)) }
        lines.append("TOTAL gross \(p.gross.reduce(0, +)) receipts \(p.receipts.reduce(0, +)) planned \(p.plannedReceipts.reduce(0, +)) orders \(p.orders.count) ending \(p.onHand[planner.horizon])")
    }
    return lines
}

func exceptionReport(_ planner: Planner, _ plan: Plan, errors: [String]) -> [String] {
    var lines = errors.map { "ERROR \($0)" }
    let kinds = ["BELOW_SAFETY", "PAST_DUE", "RELEASE", "EXPEDITE", "DEFER", "CANCEL", "NO_ROUTING", "NO_DEMAND", "OVERLOAD"]
    var counts = Dictionary(uniqueKeysWithValues: kinds.map { ($0, 0) })
    func emit(_ kind: String, _ detail: String) { counts[kind]! += 1; lines.append("\(kind) \(detail)") }
    for id in planner.order {
        let item = planner.items[id]!
        let p = plan.items[id]!
        if item.onHand < item.safety { emit("BELOW_SAFETY", "\(id) on hand \(item.onHand) safety \(item.safety)") }
        for order in p.orders {
            if order.originalRelease < 1 { emit("PAST_DUE", "\(id) order \(order.number) receipt \(order.receipt) release \(order.originalRelease) late \(1 - order.originalRelease) quantity \(order.quantity)") }
            else if order.originalRelease == 1 { emit("RELEASE", "\(id) order \(order.number) receipt \(order.receipt) quantity \(order.quantity)") }
        }
        var withoutReceipts = Array(repeating: 0, count: planner.horizon + 1)
        withoutReceipts[0] = item.onHand
        for week in 1...planner.horizon { withoutReceipts[week] = withoutReceipts[week - 1] - p.gross[week] }
        var prior = 0
        for receipt in planner.receiptsByItem[id, default: []] {
            let need = (1...planner.horizon).first { withoutReceipts[$0] + prior < item.safety }
            let detail = "\(id) receipt line \(receipt.line) week \(receipt.week) quantity \(receipt.quantity)"
            if let need {
                if need < receipt.week { emit("EXPEDITE", "\(detail) to \(need)") }
                else if need > receipt.week { emit("DEFER", "\(detail) to \(need)") }
            } else { emit("CANCEL", detail) }
            prior += receipt.quantity
        }
        if planner.bom.manufactured(id) && planner.routings[id, default: []].isEmpty { emit("NO_ROUTING", id) }
        if p.gross.reduce(0, +) == 0 && item.onHand > 0 { emit("NO_DEMAND", "\(id) on hand \(item.onHand)") }
    }
    for id in planner.centers.keys.sorted() {
        for week in 1...planner.horizon where plan.loads[id]![week] > planner.centers[id]!.available { emit("OVERLOAD", "\(id) week \(week) load \(plan.loads[id]![week]) available \(planner.centers[id]!.available)") }
    }
    lines.append("SUMMARY errors \(errors.count) " + kinds.map { "\($0.lowercased()) \(counts[$0]!)" }.joined(separator: " "))
    return lines
}

func capacityReport(_ planner: Planner, _ plan: Plan) -> [String] {
    var lines: [String] = []
    let totals = Dictionary(uniqueKeysWithValues: planner.centers.keys.map { ($0, plan.loads[$0]!.reduce(0, +)) })
    for id in planner.centers.keys.sorted() {
        let center = planner.centers[id]!
        let loads = plan.loads[id]!
        let leveled = leveledLoads(loads, available: center.available)
        lines.append("CENTER \(id) minutes \(center.minutes) efficiency \(center.efficiency) available \(center.available) \(center.description)")
        let rows = [("WEEK", Array(1...planner.horizon)), ("LOAD", Array(loads.dropFirst())), ("UTIL", loads.dropFirst().map { percent($0, center.available) }), ("OVER", loads.dropFirst().map { max(0, $0 - center.available) }), ("LEVELED", Array(leveled.dropFirst()))]
        for (label, values) in rows { lines.append(tableRow(label, values: values, width: 7)) }
        var peak = 0
        for week in 1...planner.horizon where loads[week] > loads[peak] { peak = week }
        lines.append("TOTAL load \(totals[id]!) available \(center.available * planner.horizon) utilization \(percent(totals[id]!, center.available * planner.horizon)) overloaded \(loads.dropFirst().filter { $0 > center.available }.count) peak \(peak) backlog \(max(0, leveled[1] - center.available))")
    }
    let ranked = planner.centers.keys.sorted {
        let left = totals[$0]! * planner.centers[$1]!.available
        let right = totals[$1]! * planner.centers[$0]!.available
        return left == right ? $0 < $1 : left > right
    }
    for (index, id) in ranked.enumerated() { lines.append("RANK \(index + 1) \(id) load \(totals[id]!) utilization \(percent(totals[id]!, planner.centers[id]!.available * planner.horizon))") }
    return lines
}

func promiseReport(_ planner: Planner, base: Plan, finalPlan: Plan, promises: [Promise], pegging: Pegging) -> [String] {
    var lines: [String] = []
    var onTime = 0
    var late = 0
    var rejected = 0
    for promise in promises {
        let inquiry = promise.inquiry
        let header = "ORDER \(inquiry.id) \(inquiry.item) quantity \(inquiry.quantity) requested \(inquiry.week)"
        if let week = promise.promised {
            if week == inquiry.week { onTime += 1; lines.append("\(header) promised \(week)") }
            else { late += 1; lines.append("\(header) promised \(week) late \(week - inquiry.week) material \(promise.material!) reason \(promise.reason)") }
        } else {
            rejected += 1
            lines.append("\(header) rejected material \(promise.material.map(String.init) ?? "none") reason \(promise.reason)")
        }
        if promise.promised != nil {
            for id in planner.order {
                for order in finalPlan.items[id]!.orders where pegging.roots(OrderKey(item: id, number: order.number)).contains(where: { $0.kind == "ORDER" && $0.orderID == inquiry.id }) {
                    lines.append("  SUPPLY \(id) order \(order.number) receipt \(order.receipt) release \(order.release) quantity \(order.quantity)")
                }
            }
        }
    }
    for id in planner.order {
        let before = base.items[id]!
        let after = finalPlan.items[id]!
        if let first = (1...planner.horizon).first(where: { before.plannedReceipts[$0] != after.plannedReceipts[$0] }) {
            lines.append("CHANGE \(id) from \(first) planned \(before.plannedReceipts.reduce(0, +)) -> \(after.plannedReceipts.reduce(0, +)) orders \(before.orders.count) -> \(after.orders.count)")
        }
    }
    lines.append("SUMMARY orders \(promises.count) on_time \(onTime) late \(late) rejected \(rejected)")
    return lines
}

func releaseReport(_ planner: Planner, _ plan: Plan) -> [String] {
    var lines: [String] = []
    var available = Dictionary(uniqueKeysWithValues: planner.items.map { ($0.key, $0.value.onHand + plan.items[$0.key]!.receipts[1]) })
    let orders = planner.order.flatMap { plan.items[$0]!.orders }.filter { $0.release == 1 }.sorted {
        if $0.originalRelease != $1.originalRelease { return $0.originalRelease < $1.originalRelease }
        return $0.item == $1.item ? $0.number < $1.number : $0.item < $1.item
    }
    var make = 0
    var readyCount = 0
    var short = 0
    var buy = 0
    var value = 0
    for order in orders {
        let id = order.item
        let item = planner.items[id]!
        let late = order.originalRelease < 1 ? " late \(1 - order.originalRelease)" : ""
        if !planner.bom.manufactured(id) {
            let purchase = order.quantity * item.material
            buy += 1; value += purchase
            lines.append("BUY \(id) order \(order.number) receipt \(order.receipt) quantity \(order.quantity)\(late) value \(money(purchase))")
            continue
        }
        make += 1
        let picks = planner.bom.children[id]!.map { (child: $0.child, need: $0.need(order.quantity)) }
        let ready = picks.allSatisfy { $0.need <= available[$0.child]! }
        if ready { readyCount += 1 } else { short += 1 }
        lines.append("MAKE \(id) order \(order.number) receipt \(order.receipt) quantity \(order.quantity)\(late) \(ready ? "READY" : "SHORT")")
        for pick in picks { lines.append("  PICK \(pick.child) need \(pick.need) available \(available[pick.child]!) short \(max(0, pick.need - available[pick.child]!))") }
        if ready { for pick in picks { available[pick.child]! -= pick.need } }
        let operations = planner.routings[id, default: []]
        for (index, operation) in operations.enumerated() {
            lines.append("  OPERATION \(operation.number) \(operation.center) week \(operationWeek(receipt: order.receipt, leadTime: item.leadTime, index: index, count: operations.count)) minutes \(operation.minutes(order.quantity))")
        }
    }
    lines.append("SUMMARY make \(make) ready \(readyCount) short \(short) buy \(buy) value \(money(value))")
    return lines
}

func treeReport(_ planner: Planner, quantity: Int) -> [String] {
    var lines: [String] = []
    for id in planner.items.keys.sorted() where planner.bom.manufactured(id) && planner.bom.parents[id]!.isEmpty {
        let item = planner.items[id]!
        lines.append("TREE \(id) quantity \(quantity)")
        lines.append("0 \(id) ext 1 gross \(quantity) lt \(item.leadTime) cum \(planner.cumulative[id]!) \(item.description)")
        var totals: [String: Int] = [:]
        func visit(_ parent: String, _ depth: Int, _ extended: Int, _ gross: Int) {
            for row in planner.bom.children[parent]! {
                let child = planner.items[row.child]!
                let nextExtended = extended * row.quantity
                let need = row.need(gross)
                totals[row.child, default: 0] += need
                lines.append("\(String(repeating: ".", count: depth))\(depth) \(row.child) qty \(row.quantity) scrap \(row.scrap) ext \(nextExtended) gross \(need) lt \(child.leadTime) cum \(planner.cumulative[row.child]!) \(child.description)")
                visit(row.child, depth + 1, nextExtended, need)
            }
        }
        visit(id, 1, 1, quantity)
        for child in totals.keys.sorted() { lines.append("SUM \(child) \(totals[child]!)") }
        var path = [id]
        while planner.bom.manufactured(path[path.count - 1]) {
            let next = planner.bom.children[path[path.count - 1]]!.sorted {
                planner.cumulative[$0.child]! == planner.cumulative[$1.child]! ? $0.child < $1.child : planner.cumulative[$0.child]! > planner.cumulative[$1.child]!
            }[0]
            path.append(next.child)
        }
        lines.append("CRITICAL \(path.joined(separator: " -> ")) cum \(planner.cumulative[id]!)")
    }
    return lines
}

func readWeekly(_ name: String, items: [String: Item], horizon: Int, unique: Bool, errors: inout [String]) throws -> [WeeklyQuantity] {
    var result: [WeeklyQuantity] = []
    var seen: Set<WeekKey> = []
    for (line, fields) in try csvRows(name) {
        let id = fields[0]
        let week = Int(fields[1])!
        let quantity = Int(fields[2])!
        let key = WeekKey(item: id, week: week)
        let reason: String?
        if items[id] == nil { reason = "unknown item \(id)" }
        else if !(1...horizon).contains(week) { reason = "week \(week) outside horizon" }
        else if quantity < 1 { reason = "bad quantity \(quantity)" }
        else if unique && seen.contains(key) { reason = "duplicate \(id) week \(week)" }
        else { reason = nil }
        if let reason { errors.append("\(name) line \(line): \(reason)") }
        else { result.append(WeeklyQuantity(item: id, week: week, quantity: quantity, line: line)); seen.insert(key) }
    }
    return result
}

func readInquiries(items: [String: Item], horizon: Int, errors: inout [String]) throws -> [Inquiry] {
    var result: [Inquiry] = []
    var seen: Set<String> = []
    for (line, fields) in try csvRows("orders.csv") {
        let id = fields[0]
        let item = fields[1]
        let quantity = Int(fields[2])!
        let week = Int(fields[3])!
        let reason: String?
        if seen.contains(id) { reason = "duplicate order \(id)" }
        else if items[item] == nil { reason = "unknown item \(item)" }
        else if !(1...horizon).contains(week) { reason = "week \(week) outside horizon" }
        else if quantity < 1 { reason = "bad quantity \(quantity)" }
        else { reason = nil }
        if let reason { errors.append("orders.csv line \(line): \(reason)") }
        else { result.append(Inquiry(id: id, item: item, quantity: quantity, week: week, line: line)); seen.insert(id) }
    }
    return result
}

func csvRows(_ name: String) throws -> [(line: Int, fields: [String])] {
    let text = try String(contentsOfFile: "input/\(name)", encoding: .utf8)
    return text.components(separatedBy: "\n").dropLast().dropFirst().enumerated().map { ($0.offset + 2, $0.element.components(separatedBy: ",")) }
}

func runMRP() throws {
    let parameters = try String(contentsOfFile: "input/params.txt", encoding: .utf8).split(separator: "\n").map { $0.split(separator: " ").map(String.init) }
    let horizon = Int(parameters.first { $0[0] == "horizon" }![1])!
    let peg = Array(parameters.first { $0[0] == "peg" }!.dropFirst())
    let treeQuantity = Int(parameters.first { $0[0] == "tree_quantity" }![1])!
    var errors: [String] = []
    let items = try readItems(errors: &errors)
    let bom = try readBom(items: items, errors: &errors)
    let centers = try readCenters(errors: &errors)
    let routings = try readRoutings(items: items, centers: centers, bom: bom, errors: &errors)
    let mps = try readWeekly("mps.csv", items: items, horizon: horizon, unique: true, errors: &errors)
    let receipts = try readWeekly("receipts.csv", items: items, horizon: horizon, unique: false, errors: &errors)
    let inquiries = try readInquiries(items: items, horizon: horizon, errors: &errors)
    let planner = Planner(items: items, bom: bom, centers: centers, routings: routings, mps: mps, receipts: receipts, horizon: horizon)
    let promised = planner.promise(inquiries)
    let finalPlan = promised.finalPlan
    let pegging = Pegging(planner: planner, plan: finalPlan)
    let costs = standardCosts(items: items, bom: bom, order: planner.order)
    let usages = Dictionary(uniqueKeysWithValues: items.keys.map { ($0, finalPlan.items[$0]!.gross.reduce(0, +)) })
    let values = Dictionary(uniqueKeysWithValues: items.keys.map { ($0, usages[$0]! * costs[$0]!.total) })
    let classes = abcClasses(values)
    let costLines = ["item,material,labor,total,usage,value,class"] + items.keys.sorted().map { id -> String in
        let cost = costs[id]!
        return "\(id),\(money(cost.material)),\(money(cost.labor)),\(money(cost.total)),\(usages[id]!),\(money(values[id]!)),\(classes[id]!)"
    }
    var valueLines = ["week,inventory,purchases,labor"]
    for week in 1...horizon {
        var inventory = 0
        var purchases = 0
        var labor = 0
        for id in planner.order {
            let plan = finalPlan.items[id]!
            inventory += plan.onHand[week] * costs[id]!.total
            if bom.manufactured(id) { labor += plan.plannedReleases[week] * items[id]!.labor }
            else { purchases += plan.plannedReleases[week] * items[id]!.material }
        }
        valueLines.append("\(week),\(money(inventory)),\(money(purchases)),\(money(labor))")
    }
    try writeReport("mrp_grid.txt", lines: gridReport(planner, finalPlan))
    try writeReport("pegging.txt", lines: pegging.report(peg))
    try writeReport("bom_tree.txt", lines: treeReport(planner, quantity: treeQuantity))
    try writeReport("cost_rollup.csv", lines: costLines)
    try writeReport("exceptions.txt", lines: exceptionReport(planner, finalPlan, errors: errors))
    try writeReport("capacity.txt", lines: capacityReport(planner, finalPlan))
    try writeReport("promises.txt", lines: promiseReport(planner, base: promised.base, finalPlan: finalPlan, promises: promised.promises, pegging: pegging))
    try writeReport("releases.txt", lines: releaseReport(planner, finalPlan))
    try writeReport("value_plan.csv", lines: valueLines)
}

try runMRP()
