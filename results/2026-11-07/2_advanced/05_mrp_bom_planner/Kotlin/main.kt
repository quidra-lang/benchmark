import java.io.File

data class WeeklyQuantity(val item: String, val week: Int, val quantity: Long, val line: Int)
data class Inquiry(val id: String, val item: String, val quantity: Long, val week: Int, val line: Int)
data class Placement(val inquiry: Inquiry, val week: Int)
data class Demand(val item: String, val week: Int, val kind: String, val quantity: Long, val line: Int = 0, val orderId: String = "", val parent: String = "", val parentOrder: Int = 0)
data class PlannedOrder(val item: String, val number: Int, val receipt: Int, val quantity: Long, val originalRelease: Int, val release: Int)
data class OrderKey(val item: String, val number: Int)

class ItemPlan(val demands: List<Demand>, horizon: Int) {
    val gross = LongArray(horizon + 1)
    val receipts = LongArray(horizon + 1)
    val onHand = LongArray(horizon + 1)
    val net = LongArray(horizon + 1)
    val plannedReceipts = LongArray(horizon + 1)
    val plannedReleases = LongArray(horizon + 1)
    val orders = mutableListOf<PlannedOrder>()
    fun pastDue() = orders.filter { it.originalRelease < 1 }.sumOf { it.quantity }
}

data class Plan(val items: Map<String, ItemPlan>, val loads: Map<String, LongArray>)

class Planner(val items: Map<String, Item>, val bom: Bom, val centers: Map<String, WorkCenter>, val routings: Map<String, List<Operation>>, val mps: List<WeeklyQuantity>, val receipts: List<WeeklyQuantity>, val horizon: Int) {
    val codes = bom.lowLevelCodes()
    val cumulative = bom.cumulativeLeadTimes(items)
    val order = items.keys.sortedWith(compareBy<String> { codes.getValue(it) }.thenBy { it })
    val receiptsByItem = receipts.groupBy { it.item }.mapValues { it.value.sortedWith(compareBy<WeeklyQuantity> { receipt -> receipt.week }.thenBy { receipt -> receipt.line }) }

    fun run(placements: List<Placement>): Plan {
        val demands = items.keys.associateWith { mutableListOf<Demand>() }
        for (row in mps) demands.getValue(row.item).add(Demand(row.item, row.week, "MPS", row.quantity, row.line))
        for ((inquiry, week) in placements) demands.getValue(inquiry.item).add(Demand(inquiry.item, week, "ORDER", inquiry.quantity, inquiry.line, inquiry.id))
        val plans = mutableMapOf<String, ItemPlan>()
        for (id in order) {
            val item = items.getValue(id)
            val plan = ItemPlan(demands.getValue(id).toList(), horizon)
            for (demand in plan.demands) plan.gross[demand.week] += demand.quantity
            for (receipt in receiptsByItem[id].orEmpty()) plan.receipts[receipt.week] += receipt.quantity
            plan.onHand[0] = item.onHand
            for (week in 1..horizon) {
                val available = plan.onHand[week - 1] + plan.receipts[week] - plan.gross[week]
                if (available < item.safety) {
                    plan.net[week] = item.safety - available
                    val quantity = lotSize(item, week, available, plan.receipts, plan.gross, horizon)
                    val original = week - item.leadTime
                    val release = maxOf(1, original)
                    val planned = PlannedOrder(id, plan.orders.size + 1, week, quantity, original, release)
                    plan.orders += planned
                    plan.plannedReceipts[week] = quantity
                    plan.plannedReleases[release] += quantity
                }
                plan.onHand[week] = available + plan.plannedReceipts[week]
            }
            plans[id] = plan
            for (planned in plan.orders) for (row in bom.children.getValue(id)) demands.getValue(row.child).add(Demand(row.child, planned.release, "DEPENDENT", row.need(planned.quantity), parent = id, parentOrder = planned.number))
        }
        val loads = centers.keys.associateWith { LongArray(horizon + 1) }
        for (id in order) for (planned in plans.getValue(id).orders) {
            val operations = routings[id].orEmpty()
            for ((index, operation) in operations.withIndex()) {
                val week = operationWeek(planned.receipt, items.getValue(id).leadTime, index, operations.size)
                loads.getValue(operation.center)[week] += operation.minutes(planned.quantity)
            }
        }
        return Plan(plans, loads)
    }

    fun promise(inquiries: List<Inquiry>): Triple<Plan, Plan, List<Promise>> {
        val base = run(emptyList())
        var current = base
        val placements = mutableListOf<Placement>()
        val promises = mutableListOf<Promise>()
        for (inquiry in inquiries) {
            var promised: Int? = null
            var material: Int? = null
            var firstReason = ""
            for (week in inquiry.week..horizon) {
                val trial = run(placements + Placement(inquiry, week))
                var reason = order.firstOrNull { trial.items.getValue(it).pastDue() > current.items.getValue(it).pastDue() }
                if (reason == null) {
                    if (material == null) material = week
                    loop@ for (center in centers.keys.sorted()) for (period in 1..horizon) {
                        val available = centers.getValue(center).available
                        if (maxOf(0L, trial.loads.getValue(center)[period] - available) > maxOf(0L, current.loads.getValue(center)[period] - available)) {
                            reason = "$center week $period"
                            break@loop
                        }
                    }
                }
                if (week == inquiry.week) firstReason = reason ?: ""
                if (reason == null) {
                    promised = week
                    placements += Placement(inquiry, week)
                    current = trial
                    break
                }
            }
            promises += Promise(inquiry, promised, material, firstReason)
        }
        return Triple(base, current, promises)
    }
}

data class Promise(val inquiry: Inquiry, val promised: Int?, val material: Int?, val reason: String)
data class Allocation(val demand: Demand, val share: Long)
class Supply(val kind: String, val item: String, val week: Int, val quantity: Long, val line: Int = 0, val planned: PlannedOrder? = null) {
    var excess = quantity
    val allocations = mutableListOf<Allocation>()
}
data class RootDemand(val item: String, val kind: String, val week: Int = 0, val orderId: String = "")

class Pegging(val planner: Planner, val plan: Plan) {
    val supplies = mutableMapOf<String, List<Supply>>()
    val plannedSupplies = mutableMapOf<OrderKey, Supply>()
    val rootCache = mutableMapOf<OrderKey, Set<RootDemand>>()
    init {
        for (id in planner.order) {
            val item = planner.items.getValue(id)
            val itemPlan = plan.items.getValue(id)
            val demands = mutableListOf<Demand>()
            if (item.safety > 0L) demands += Demand(id, 0, "SAFETY", item.safety)
            val kindOrder = mapOf("MPS" to 0, "ORDER" to 1, "DEPENDENT" to 2)
            demands += itemPlan.demands.sortedWith(compareBy<Demand> { it.week }.thenBy { kindOrder.getValue(it.kind) }.thenBy { if (it.kind == "ORDER") it.line else 0 }.thenBy { it.parent }.thenBy { it.parentOrder })
            val itemSupplies = mutableListOf<Supply>()
            if (item.onHand > 0L) itemSupplies += Supply("STOCK", id, 0, item.onHand)
            val arrivals = planner.receiptsByItem[id].orEmpty().map { Supply("RECEIPT", id, it.week, it.quantity, it.line) } + itemPlan.orders.map { order -> Supply("ORDER", id, order.receipt, order.quantity, planned = order).also { plannedSupplies[OrderKey(id, order.number)] = it } }
            itemSupplies += arrivals.sortedWith(compareBy<Supply> { it.week }.thenBy { if (it.kind == "RECEIPT") 0 else 1 }.thenBy { it.line })
            var supplyIndex = 0
            for (demand in demands) {
                var remaining = demand.quantity
                while (remaining > 0L) {
                    while (itemSupplies[supplyIndex].excess == 0L) supplyIndex++
                    val supply = itemSupplies[supplyIndex]
                    val share = minOf(remaining, supply.excess)
                    supply.allocations += Allocation(demand, share)
                    supply.excess -= share
                    remaining -= share
                }
            }
            supplies[id] = itemSupplies
        }
    }

    fun roots(key: OrderKey): Set<RootDemand> {
        rootCache[key]?.let { return it }
        val result = mutableSetOf<RootDemand>()
        for (allocation in plannedSupplies.getValue(key).allocations) {
            val demand = allocation.demand
            if (demand.kind == "DEPENDENT") result += roots(OrderKey(demand.parent, demand.parentOrder))
            else result += RootDemand(demand.item, demand.kind, demand.week, demand.orderId)
        }
        rootCache[key] = result
        return result
    }

    fun allocationLines(supply: Supply, depth: Int, recurse: Boolean): List<String> {
        val lines = mutableListOf<String>()
        for ((demand, share) in supply.allocations) {
            val detail = when (demand.kind) {
                "SAFETY" -> "SAFETY ${demand.item}"
                "MPS" -> "MPS ${demand.item} week ${demand.week}"
                "ORDER" -> "ORDER ${demand.orderId} ${demand.item} week ${demand.week}"
                else -> "${demand.parent} order ${demand.parentOrder} week ${demand.week}"
            }
            lines += " ".repeat(2 * depth) + "ALLOC $share $detail"
            if (recurse && demand.kind == "DEPENDENT") lines += allocationLines(plannedSupplies.getValue(OrderKey(demand.parent, demand.parentOrder)), depth + 1, true)
        }
        return lines
    }

    fun report(ids: List<String>): List<String> {
        val lines = mutableListOf<String>()
        fun whereUsed(id: String, depth: Int, cumulative: Long) {
            for (row in planner.bom.parents.getValue(id)) {
                val extended = cumulative * row.quantity
                lines += "${".".repeat(depth)}$depth ${row.parent} qty ${row.quantity} ext $extended"
                whereUsed(row.parent, depth + 1, extended)
            }
        }
        val kindOrder = mapOf("MPS" to 0, "ORDER" to 1, "SAFETY" to 2)
        for (id in ids) {
            lines += "PEG $id orders ${plan.items.getValue(id).orders.size}"
            whereUsed(id, 1, 1L)
            val itemSupplies = supplies.getValue(id)
            val ordered = itemSupplies.filter { it.kind == "STOCK" } + itemSupplies.filter { it.kind == "RECEIPT" } + itemSupplies.filter { it.kind == "ORDER" }.sortedBy { it.planned!!.number }
            for (supply in ordered) {
                val order = supply.planned
                lines += when (supply.kind) { "STOCK" -> "STOCK quantity ${supply.quantity}"; "RECEIPT" -> "RECEIPT line ${supply.line} week ${supply.week} quantity ${supply.quantity}"; else -> "ORDER ${order!!.number} receipt ${order.receipt} release ${order.release} quantity ${order.quantity}" }
                lines += allocationLines(supply, 1, supply.kind == "ORDER")
                if (supply.excess > 0L) lines += "  EXCESS ${supply.excess}"
                if (order != null) for (root in roots(OrderKey(id, order.number)).sortedWith(compareBy<RootDemand> { it.item }.thenBy { kindOrder.getValue(it.kind) }.thenBy { it.week }.thenBy { it.orderId })) {
                    lines += when (root.kind) { "SAFETY" -> "  ROOT SAFETY ${root.item}"; "MPS" -> "  ROOT MPS ${root.item} week ${root.week}"; else -> "  ROOT ORDER ${root.orderId} ${root.item} week ${root.week}" }
                }
            }
        }
        return lines
    }
}

fun gridReport(planner: Planner, plan: Plan): List<String> {
    val lines = mutableListOf<String>()
    for (id in planner.order) {
        val item = planner.items.getValue(id)
        val p = plan.items.getValue(id)
        lines += "ITEM $id LLC ${planner.codes.getValue(id)} LT ${item.leadTime} LOT ${item.lotLabel()} SS ${item.safety} OH ${item.onHand} ${item.description}"
        for ((label, values) in listOf("WEEK" to (1..planner.horizon).map(Int::toLong), "GROSS" to p.gross.drop(1), "RECEIPTS" to p.receipts.drop(1), "ON_HAND" to p.onHand.drop(1), "NET" to p.net.drop(1), "PLAN_RCPT" to p.plannedReceipts.drop(1), "PLAN_REL" to p.plannedReleases.drop(1))) lines += tableRow(label, values, 6)
        lines += "TOTAL gross ${p.gross.sum()} receipts ${p.receipts.sum()} planned ${p.plannedReceipts.sum()} orders ${p.orders.size} ending ${p.onHand.last()}"
    }
    return lines
}

fun exceptionReport(planner: Planner, plan: Plan, errors: List<String>): List<String> {
    val lines = errors.map { "ERROR $it" }.toMutableList()
    val kinds = listOf("BELOW_SAFETY", "PAST_DUE", "RELEASE", "EXPEDITE", "DEFER", "CANCEL", "NO_ROUTING", "NO_DEMAND", "OVERLOAD")
    val counts = kinds.associateWith { 0 }.toMutableMap()
    fun emit(kind: String, detail: String) { counts[kind] = counts.getValue(kind) + 1; lines += "$kind $detail" }
    for (id in planner.order) {
        val item = planner.items.getValue(id)
        val p = plan.items.getValue(id)
        if (item.onHand < item.safety) emit("BELOW_SAFETY", "$id on hand ${item.onHand} safety ${item.safety}")
        for (order in p.orders) {
            if (order.originalRelease < 1) emit("PAST_DUE", "$id order ${order.number} receipt ${order.receipt} release ${order.originalRelease} late ${1 - order.originalRelease} quantity ${order.quantity}")
            else if (order.originalRelease == 1) emit("RELEASE", "$id order ${order.number} receipt ${order.receipt} quantity ${order.quantity}")
        }
        val withoutReceipts = LongArray(planner.horizon + 1)
        withoutReceipts[0] = item.onHand
        for (week in 1..planner.horizon) withoutReceipts[week] = withoutReceipts[week - 1] - p.gross[week]
        var prior = 0L
        for (receipt in planner.receiptsByItem[id].orEmpty()) {
            val need = (1..planner.horizon).firstOrNull { withoutReceipts[it] + prior < item.safety }
            val detail = "$id receipt line ${receipt.line} week ${receipt.week} quantity ${receipt.quantity}"
            when { need == null -> emit("CANCEL", detail); need < receipt.week -> emit("EXPEDITE", "$detail to $need"); need > receipt.week -> emit("DEFER", "$detail to $need") }
            prior += receipt.quantity
        }
        if (planner.bom.manufactured(id) && planner.routings[id].orEmpty().isEmpty()) emit("NO_ROUTING", id)
        if (p.gross.sum() == 0L && item.onHand > 0L) emit("NO_DEMAND", "$id on hand ${item.onHand}")
    }
    for (id in planner.centers.keys.sorted()) for (week in 1..planner.horizon) if (plan.loads.getValue(id)[week] > planner.centers.getValue(id).available) emit("OVERLOAD", "$id week $week load ${plan.loads.getValue(id)[week]} available ${planner.centers.getValue(id).available}")
    lines += "SUMMARY errors ${errors.size} " + kinds.joinToString(" ") { "${it.lowercase()} ${counts.getValue(it)}" }
    return lines
}

fun capacityReport(planner: Planner, plan: Plan): List<String> {
    val lines = mutableListOf<String>()
    val totals = planner.centers.keys.associateWith { plan.loads.getValue(it).sum() }
    for (id in planner.centers.keys.sorted()) {
        val center = planner.centers.getValue(id)
        val loads = plan.loads.getValue(id)
        val leveled = leveledLoads(loads, center.available)
        lines += "CENTER $id minutes ${center.minutes} efficiency ${center.efficiency} available ${center.available} ${center.description}"
        for ((label, values) in listOf("WEEK" to (1..planner.horizon).map(Int::toLong), "LOAD" to loads.drop(1), "UTIL" to loads.drop(1).map { percent(it, center.available) }, "OVER" to loads.drop(1).map { maxOf(0L, it - center.available) }, "LEVELED" to leveled.drop(1))) lines += tableRow(label, values, 7)
        var peak = 0
        for (week in 1..planner.horizon) if (loads[week] > loads[peak]) peak = week
        lines += "TOTAL load ${totals.getValue(id)} available ${center.available * planner.horizon.toLong()} utilization ${percent(totals.getValue(id), center.available * planner.horizon.toLong())} overloaded ${loads.drop(1).count { it > center.available }} peak $peak backlog ${maxOf(0L, leveled[1] - center.available)}"
    }
    val ranked = planner.centers.keys.sortedWith { a, b ->
        val comparison = (totals.getValue(b) * planner.centers.getValue(a).available).compareTo(totals.getValue(a) * planner.centers.getValue(b).available)
        if (comparison == 0) a.compareTo(b) else comparison
    }
    for ((index, id) in ranked.withIndex()) lines += "RANK ${index + 1} $id load ${totals.getValue(id)} utilization ${percent(totals.getValue(id), planner.centers.getValue(id).available * planner.horizon.toLong())}"
    return lines
}

fun promiseReport(planner: Planner, base: Plan, finalPlan: Plan, promises: List<Promise>, pegging: Pegging): List<String> {
    val lines = mutableListOf<String>()
    var onTime = 0
    var late = 0
    var rejected = 0
    for (promise in promises) {
        val inquiry = promise.inquiry
        val header = "ORDER ${inquiry.id} ${inquiry.item} quantity ${inquiry.quantity} requested ${inquiry.week}"
        when {
            promise.promised == null -> { rejected++; lines += "$header rejected material ${promise.material ?: "none"} reason ${promise.reason}" }
            promise.promised == inquiry.week -> { onTime++; lines += "$header promised ${promise.promised}" }
            else -> { late++; lines += "$header promised ${promise.promised} late ${promise.promised - inquiry.week} material ${promise.material} reason ${promise.reason}" }
        }
        if (promise.promised != null) for (id in planner.order) for (order in finalPlan.items.getValue(id).orders) if (pegging.roots(OrderKey(id, order.number)).any { it.kind == "ORDER" && it.orderId == inquiry.id }) lines += "  SUPPLY $id order ${order.number} receipt ${order.receipt} release ${order.release} quantity ${order.quantity}"
    }
    for (id in planner.order) {
        val before = base.items.getValue(id)
        val after = finalPlan.items.getValue(id)
        val first = (1..planner.horizon).firstOrNull { before.plannedReceipts[it] != after.plannedReceipts[it] }
        if (first != null) lines += "CHANGE $id from $first planned ${before.plannedReceipts.sum()} -> ${after.plannedReceipts.sum()} orders ${before.orders.size} -> ${after.orders.size}"
    }
    lines += "SUMMARY orders ${promises.size} on_time $onTime late $late rejected $rejected"
    return lines
}

fun releaseReport(planner: Planner, plan: Plan): List<String> {
    val lines = mutableListOf<String>()
    val available = planner.items.mapValues { (id, item) -> item.onHand + plan.items.getValue(id).receipts[1] }.toMutableMap()
    val orders = planner.order.flatMap { plan.items.getValue(it).orders }.filter { it.release == 1 }.sortedWith(compareBy<PlannedOrder> { it.originalRelease }.thenBy { it.item }.thenBy { it.number })
    var make = 0
    var readyCount = 0
    var short = 0
    var buy = 0
    var value = 0L
    for (order in orders) {
        val id = order.item
        val item = planner.items.getValue(id)
        val late = if (order.originalRelease < 1) " late ${1 - order.originalRelease}" else ""
        if (!planner.bom.manufactured(id)) {
            val purchase = order.quantity * item.material
            buy++; value += purchase
            lines += "BUY $id order ${order.number} receipt ${order.receipt} quantity ${order.quantity}$late value ${money(purchase)}"
            continue
        }
        make++
        val picks = planner.bom.children.getValue(id).map { it.child to it.need(order.quantity) }
        val ready = picks.all { (child, need) -> need <= available.getValue(child) }
        if (ready) readyCount++ else short++
        lines += "MAKE $id order ${order.number} receipt ${order.receipt} quantity ${order.quantity}$late ${if (ready) "READY" else "SHORT"}"
        for ((child, need) in picks) lines += "  PICK $child need $need available ${available.getValue(child)} short ${maxOf(0L, need - available.getValue(child))}"
        if (ready) for ((child, need) in picks) available[child] = available.getValue(child) - need
        val operations = planner.routings[id].orEmpty()
        for ((index, operation) in operations.withIndex()) lines += "  OPERATION ${operation.number} ${operation.center} week ${operationWeek(order.receipt, item.leadTime, index, operations.size)} minutes ${operation.minutes(order.quantity)}"
    }
    lines += "SUMMARY make $make ready $readyCount short $short buy $buy value ${money(value)}"
    return lines
}

fun treeReport(planner: Planner, quantity: Long): List<String> {
    val lines = mutableListOf<String>()
    for (id in planner.items.keys.sorted().filter { planner.bom.manufactured(it) && planner.bom.parents.getValue(it).isEmpty() }) {
        val item = planner.items.getValue(id)
        lines += "TREE $id quantity $quantity"
        lines += "0 $id ext 1 gross $quantity lt ${item.leadTime} cum ${planner.cumulative.getValue(id)} ${item.description}"
        val totals = sortedMapOf<String, Long>()
        fun visit(parent: String, depth: Int, extended: Long, gross: Long) {
            for (row in planner.bom.children.getValue(parent)) {
                val child = planner.items.getValue(row.child)
                val nextExtended = extended * row.quantity
                val need = row.need(gross)
                totals[row.child] = totals.getOrDefault(row.child, 0L) + need
                lines += "${".".repeat(depth)}$depth ${row.child} qty ${row.quantity} scrap ${row.scrap} ext $nextExtended gross $need lt ${child.leadTime} cum ${planner.cumulative.getValue(row.child)} ${child.description}"
                visit(row.child, depth + 1, nextExtended, need)
            }
        }
        visit(id, 1, 1L, quantity)
        for ((child, total) in totals) lines += "SUM $child $total"
        val path = mutableListOf(id)
        while (planner.bom.manufactured(path.last())) {
            val next = planner.bom.children.getValue(path.last()).sortedWith(compareByDescending<BomRow> { planner.cumulative.getValue(it.child) }.thenBy { it.child }).first()
            path += next.child
        }
        lines += "CRITICAL ${path.joinToString(" -> ")} cum ${planner.cumulative.getValue(id)}"
    }
    return lines
}

fun readWeekly(name: String, items: Map<String, Item>, horizon: Int, unique: Boolean, errors: MutableList<String>): List<WeeklyQuantity> {
    val result = mutableListOf<WeeklyQuantity>()
    val seen = mutableSetOf<Pair<String, Int>>()
    for ((line, fields) in csvRows(name)) {
        val id = fields[0]
        val week = fields[1].toInt()
        val quantity = fields[2].toLong()
        val reason = when { id !in items -> "unknown item $id"; week !in 1..horizon -> "week $week outside horizon"; quantity < 1 -> "bad quantity $quantity"; unique && (id to week) in seen -> "duplicate $id week $week"; else -> null }
        if (reason != null) errors += "$name line $line: $reason"
        else { result += WeeklyQuantity(id, week, quantity, line); seen += id to week }
    }
    return result
}

fun readInquiries(items: Map<String, Item>, horizon: Int, errors: MutableList<String>): List<Inquiry> {
    val result = mutableListOf<Inquiry>()
    val seen = mutableSetOf<String>()
    for ((line, fields) in csvRows("orders.csv")) {
        val id = fields[0]
        val item = fields[1]
        val quantity = fields[2].toLong()
        val week = fields[3].toInt()
        val reason = when { id in seen -> "duplicate order $id"; item !in items -> "unknown item $item"; week !in 1..horizon -> "week $week outside horizon"; quantity < 1 -> "bad quantity $quantity"; else -> null }
        if (reason != null) errors += "orders.csv line $line: $reason"
        else { result += Inquiry(id, item, quantity, week, line); seen += id }
    }
    return result
}

fun csvRows(name: String) = File("input/$name").readLines().drop(1).mapIndexed { index, line -> index + 2 to line.split(',') }

fun main() {
    val parameters = File("input/params.txt").readLines().map { it.split(' ') }
    val horizon = parameters.first { it[0] == "horizon" }[1].toInt()
    val peg = parameters.first { it[0] == "peg" }.drop(1)
    val treeQuantity = parameters.first { it[0] == "tree_quantity" }[1].toLong()
    val errors = mutableListOf<String>()
    val items = readItems(errors)
    val bom = readBom(items, errors)
    val centers = readCenters(errors)
    val routings = readRoutings(items, centers, bom, errors)
    val mps = readWeekly("mps.csv", items, horizon, true, errors)
    val receipts = readWeekly("receipts.csv", items, horizon, false, errors)
    val inquiries = readInquiries(items, horizon, errors)
    val planner = Planner(items, bom, centers, routings, mps, receipts, horizon)
    val (base, finalPlan, promises) = planner.promise(inquiries)
    val pegging = Pegging(planner, finalPlan)
    val costs = standardCosts(items, bom, planner.order)
    val usages = items.keys.associateWith { finalPlan.items.getValue(it).gross.sum() }
    val values = items.keys.associateWith { usages.getValue(it) * costs.getValue(it).total }
    val classes = abcClasses(values)
    val costLines = listOf("item,material,labor,total,usage,value,class") + items.keys.sorted().map { id -> val cost = costs.getValue(id); "$id,${money(cost.material)},${money(cost.labor)},${money(cost.total)},${usages.getValue(id)},${money(values.getValue(id))},${classes.getValue(id)}" }
    val valueLines = mutableListOf("week,inventory,purchases,labor")
    for (week in 1..horizon) {
        var inventory = 0L
        var purchases = 0L
        var labor = 0L
        for (id in planner.order) {
            val plan = finalPlan.items.getValue(id)
            inventory += plan.onHand[week] * costs.getValue(id).total
            if (bom.manufactured(id)) labor += plan.plannedReleases[week] * items.getValue(id).labor
            else purchases += plan.plannedReleases[week] * items.getValue(id).material
        }
        valueLines += "$week,${money(inventory)},${money(purchases)},${money(labor)}"
    }
    writeReport("mrp_grid.txt", gridReport(planner, finalPlan))
    writeReport("pegging.txt", pegging.report(peg))
    writeReport("bom_tree.txt", treeReport(planner, treeQuantity))
    writeReport("cost_rollup.csv", costLines)
    writeReport("exceptions.txt", exceptionReport(planner, finalPlan, errors))
    writeReport("capacity.txt", capacityReport(planner, finalPlan))
    writeReport("promises.txt", promiseReport(planner, base, finalPlan, promises, pegging))
    writeReport("releases.txt", releaseReport(planner, finalPlan))
    writeReport("value_plan.csv", valueLines)
}
