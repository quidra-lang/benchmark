import java.io.BufferedReader
import java.io.InputStreamReader

private val stageNames = listOf("RETAILER", "WHOLESALER", "DISTRIBUTOR", "FACTORY")
private val parameters = mapOf(
    "FIXED" to 1, "PASS" to 0, "BASESTOCK" to 1, "MINMAX" to 2,
    "MOVAVG" to 2, "SMOOTH" to 2, "STERMAN" to 4
)
private val modes = mapOf("ORDERS" to "order", "INV" to "inventory", "BACK" to "backlog")

private class CommandError(message: String) : RuntimeException(message)

private fun fail(message: String): Nothing = throw CommandError(message)

private fun money(value: Long): String =
    (value / 100).toString() + "." + (value % 100).toString().padStart(2, '0')

private fun decimal(numerator: Long, denominator: Long, places: Int): String {
    var scale = 1L
    repeat(places) { scale *= 10 }
    val value = Math.floorDiv(numerator * scale, denominator)
    return (value / scale).toString() + "." +
        (value % scale).toString().padStart(places, '0')
}

private fun variation(values: List<Int>): Long {
    val sum = values.sumOf { it.toLong() }
    val squares = values.sumOf { it.toLong() * it }
    return values.size.toLong() * squares - sum * sum
}

private data class Policy(val name: String, val args: List<Int>, val description: String)

private fun parsePolicy(tokens: List<String>): Policy {
    val name = tokens.firstOrNull() ?: fail("unknown policy ")
    val count = parameters[name] ?: fail("unknown policy $name")
    if (tokens.size - 1 != count) fail("$name needs $count parameters")
    val values = tokens.drop(1).mapIndexed { index, token ->
        if (name == "STERMAN" && index < 3) token.replace(".", "").toInt()
        else token.toInt()
    }
    val valid = when (name) {
        "FIXED" -> values[0] in 0..1000
        "PASS" -> true
        "BASESTOCK" -> values[0] in 0..10000
        "MINMAX" -> 0 <= values[0] && values[0] < values[1] && values[1] <= 10000
        "MOVAVG" -> values[0] in 1..52 && values[1] in 0..10000
        "SMOOTH" -> values[0] in 1..10 && values[1] in 0..10000
        else -> values.take(3).all { it in 0..100 } && values[3] in 0..10000
    }
    if (!valid) fail("invalid parameter for $name")
    return Policy(name, values, tokens.joinToString(" "))
}

private data class Initial(
    val inventory: Int,
    val quantity: Int,
    val shippingDelay: Int,
    val orderDelay: Int,
    val holding: Int,
    val backlogRate: Int,
    val policy: Policy
)

private data class Record(
    val received: Int,
    val incoming: Int,
    val shipped: Int,
    val before: Int,
    val ontime: Int,
    val inventory: Int,
    val backlog: Int,
    var order: Int = 0,
    var holding: Long = 0,
    var backlogCost: Long = 0,
    var cost: Long = 0
)

private data class PlantRecord(val incoming: Int, val produced: Int, val backlog: Int)

private class Stage(initial: Initial) {
    var inventory = initial.inventory
    var backlog = 0
    val shipping = MutableList(initial.shippingDelay) { initial.quantity }
    val orders = MutableList(initial.orderDelay) { initial.quantity }
    var policy = initial.policy
    var expected = 100 * initial.quantity
    var holding = initial.holding
    var backlogRate = initial.backlogRate
    var lot = 1
    var capacity: Int? = null
    val records = mutableListOf<Record>()

    fun copy(): Stage {
        val initial = Initial(inventory, 0, 0, 0, holding, backlogRate, policy)
        val result = Stage(initial)
        result.backlog = backlog
        result.shipping.addAll(shipping)
        result.orders.addAll(orders)
        result.expected = expected
        result.lot = lot
        result.capacity = capacity
        result.records.addAll(records.map { it.copy() })
        return result
    }
}

private class Simulation(val initials: List<Initial>, demands: List<Int>) {
    var week = 0
    val demands = demands.toMutableList()
    val stages = initials.map { Stage(it) }.toMutableList()
    var plantBacklog = 0
    var plantCapacity: Int? = null
    val plantRecords = mutableListOf<PlantRecord>()
    var visibility = "OFF"

    fun copy(): Simulation {
        val result = Simulation(initials, demands)
        result.week = week
        result.plantBacklog = plantBacklog
        result.plantCapacity = plantCapacity
        result.visibility = visibility
        result.plantRecords.addAll(plantRecords)
        for (i in stages.indices) result.stages[i] = stages[i].copy()
        return result
    }

    fun signal(index: Int, observedWeek: Int, current: List<Int>? = null): Int {
        if (visibility == "ON") return demands[observedWeek - 1]
        if (current != null && observedWeek == week + 1) return current[index]
        return stages[index].records[observedWeek - 1].incoming
    }

    fun setPolicy(index: Int, policy: Policy) {
        val stage = stages[index]
        stage.policy = policy
        if (policy.name == "STERMAN") {
            stage.expected = 100 * if (week != 0) signal(index, week) else initials[index].quantity
        }
    }

    fun positions(): Pair<List<Int>, List<Int>> {
        val supply = mutableListOf<Int>()
        val positions = mutableListOf<Int>()
        for ((index, stage) in stages.withIndex()) {
            val upstreamBacklog = if (index < 3) stages[index + 1].backlog else plantBacklog
            val line = stage.orders.sum() + upstreamBacklog + stage.shipping.sum()
            supply.add(line)
            positions.add(stage.inventory + line - stage.backlog)
        }
        return supply to positions
    }

    private fun policyOrder(index: Int, incoming: List<Int>, line: Int, position: Int): Int {
        val stage = stages[index]
        val policy = stage.policy
        val args = policy.args
        val currentWeek = week + 1
        val signal = signal(index, currentWeek, incoming)
        return when (policy.name) {
            "FIXED" -> args[0]
            "PASS" -> incoming[index]
            "BASESTOCK" -> maxOf(0, args[0] - position)
            "MINMAX" -> if (position <= args[0]) args[1] - position else 0
            "MOVAVG" -> {
                val k = minOf(args[0], currentWeek)
                val forecast = (currentWeek - k + 1..currentWeek).sumOf {
                    signal(index, it, incoming)
                } / k
                val delay = initials[index].shippingDelay + initials[index].orderDelay
                maxOf(0, args[1] + forecast * delay - position)
            }
            "SMOOTH" -> maxOf(0, signal + Math.floorDiv(args[1] - position, args[0]))
            else -> {
                val theta = args[0]
                val alpha = args[1]
                val beta = args[2]
                val target = args[3]
                stage.expected =
                    (100 * theta * signal + (100 - theta) * stage.expected) / 100
                val net = stage.inventory - stage.backlog
                maxOf(
                    0,
                    Math.floorDiv(
                        100L * stage.expected +
                        alpha.toLong() * (100L * (target - net) - beta.toLong() * line),
                        10000L
                    ).toInt()
                )
            }
        }
    }

    fun step(): List<Record> {
        val received = mutableListOf<Int>()
        for (stage in stages) {
            val amount = stage.shipping.removeAt(0)
            stage.inventory += amount
            received.add(amount)
        }
        val incoming = mutableListOf(demands[week])
        for (i in 0..2) incoming.add(stages[i].orders.removeAt(0))
        val plantIncoming = stages[3].orders.removeAt(0)

        val records = mutableListOf<Record>()
        for ((index, stage) in stages.withIndex()) {
            val before = stage.backlog
            val requested = before + incoming[index]
            var shipped = minOf(stage.inventory, requested)
            stage.capacity?.let { shipped = minOf(shipped, it) }
            stage.inventory -= shipped
            stage.backlog = requested - shipped
            if (index > 0) stages[index - 1].shipping.add(shipped)
            records.add(
                Record(
                    received[index], incoming[index], shipped, before,
                    minOf(maxOf(0, shipped - before), incoming[index]),
                    stage.inventory, stage.backlog
                )
            )
        }
        val requested = plantBacklog + plantIncoming
        val produced = minOf(requested, plantCapacity ?: requested)
        plantBacklog = requested - produced
        stages[3].shipping.add(produced)

        val (supply, positions) = positions()
        val orders = stages.indices.map { policyOrder(it, incoming, supply[it], positions[it]) }
        for ((index, stage) in stages.withIndex()) {
            val quantity = (orders[index] + stage.lot - 1) / stage.lot * stage.lot
            stage.orders.add(quantity)
            records[index].apply {
                order = quantity
                holding = stage.holding.toLong() * stage.inventory
                backlogCost = stage.backlogRate.toLong() * stage.backlog
                cost = holding + backlogCost
            }
            stage.records.add(records[index])
        }
        plantRecords.add(PlantRecord(plantIncoming, produced, plantBacklog))
        week++
        return records
    }

    fun costs(): List<Long> = stages.map { stage -> stage.records.sumOf { it.cost } }
}

private class Game(settings: List<List<String>>) {
    private val initials = settings.map { a ->
        Initial(
            a[1].toInt(), a[2].toInt(), a[3].toInt(), a[4].toInt(),
            a[5].toInt(), a[6].toInt(), parsePolicy(a.drop(7))
        )
    }
    private var base = listOf<Int>()
    private var simulation = Simulation(initials, base)
    private val snapshots = mutableMapOf<String, Simulation>()
    val output = mutableListOf<String>()

    private fun emit(vararg parts: Any) {
        output.add(parts.joinToString(" ") { it.toString() })
    }

    private fun stageIndex(text: String): Int {
        val result = stageNames.indexOf(text)
        if (result < 0) fail("unknown stage $text")
        return result
    }

    private fun target(text: String): List<Int> =
        if (text == "ALL") (0..3).toList() else listOf(stageIndex(text))

    private fun requireWeeks() {
        if (simulation.week == 0) fail("no weeks simulated")
    }

    private fun rangeCheck(args: List<String>, limit: Int): Pair<Int, Int> {
        if (args.isEmpty()) return 1 to limit
        val first = args[0].toInt()
        val last = args[1].toInt()
        if (first < 1 || first > last || last > limit) {
            fail("bad range ${args[0]} ${args[1]}")
        }
        return first to last
    }

    private fun modeCheck(mode: String) {
        if (mode !in listOf("ORDERS", "INV", "BACK", "NET")) fail("unknown mode $mode")
    }

    private fun values(index: Int, mode: String): List<Int> =
        simulation.stages[index].records.map {
            when (mode) {
                "NET" -> it.inventory - it.backlog
                "ORDERS" -> it.order
                "INV" -> it.inventory
                else -> it.backlog
            }
        }

    private fun initialize(demands: List<Int>? = null) {
        if (demands != null) base = demands.toList()
        simulation = Simulation(initials, base)
    }

    private fun trial(policies: List<Policy>): Simulation {
        val current = simulation
        val trial = Simulation(initials, current.demands)
        trial.visibility = current.visibility
        trial.plantCapacity = current.plantCapacity
        for (index in 0..3) {
            val previous = current.stages[index]
            val stage = trial.stages[index]
            stage.lot = previous.lot
            stage.capacity = previous.capacity
            stage.holding = previous.holding
            stage.backlogRate = previous.backlogRate
            trial.setPolicy(index, policies[index])
        }
        while (trial.week < trial.demands.size) trial.step()
        return trial
    }

    private fun demand(values: List<Int>) {
        initialize(values)
        emit(
            "DEMAND", "weeks", values.size, "total", values.sum(),
            "min", values.min(), "max", values.max()
        )
    }

    private fun generate(a: List<String>) {
        val weeks = a[0].toInt()
        val baseLevel = a[1].toInt()
        val spread = a[2].toInt()
        var seed = a[3].toLong()
        val changes = mutableListOf<Triple<String, Int, Int>>()
        var i = 4
        while (i < a.size) {
            changes.add(Triple(a[i], a[i + 1].toInt(), a[i + 2].toInt()))
            i += 3
        }
        for ((_, week, _) in changes) {
            if (week !in 1..weeks) fail("week $week outside horizon")
        }
        val levels = mutableListOf<Int>()
        for (week in 1..weeks) {
            var level = baseLevel
            for ((kind, start, amount) in changes) {
                if (kind == "STEP" && week >= start) level += amount
                else if (kind == "PULSE" && week == start) level += amount
                else if (kind == "RAMP" && week >= start) level += amount * (week - start + 1)
            }
            if (level < 0) fail("negative level at week $week")
            levels.add(level)
        }
        val generated = levels.map {
            seed = 48271L * seed % 2147483647L
            it + (seed % spread).toInt()
        }
        demand(generated)
    }

    private fun showStatus() {
        val s = simulation
        emit("STATUS", "week", s.week, "of", s.demands.size)
        val (supply, positions) = s.positions()
        for ((index, stage) in s.stages.withIndex()) {
            var text = "${stageNames[index]} inv ${stage.inventory} back ${stage.backlog} " +
                "transit ${stage.shipping.joinToString(",")} pending ${stage.orders.joinToString(",")} " +
                "supply ${supply[index]} position ${positions[index]} policy ${stage.policy.description}"
            if (stage.policy.name == "STERMAN") text += " expect ${money(stage.expected.toLong())}"
            emit(text)
        }
        emit("PLANT", "back", s.plantBacklog)
    }

    private fun showWeek(week: Int) {
        val s = simulation
        emit("WEEK", week, "demand", s.demands[week - 1])
        for ((index, stage) in s.stages.withIndex()) {
            val r = stage.records[week - 1]
            emit(
                stageNames[index], "recv", r.received, "in", r.incoming,
                "ship", r.shipped, "inv", r.inventory, "back", r.backlog,
                "order", r.order, "cost", money(r.cost)
            )
        }
        val plant = s.plantRecords[week - 1]
        emit("PLANT", "in", plant.incoming, "made", plant.produced, "back", plant.backlog)
    }

    private fun table(index: Int, first: Int, last: Int) {
        val widths = listOf(4, 6, 6, 6, 6, 6, 6, 9)
        val labels = listOf("week", "in", "ship", "recv", "inv", "back", "order", "cost")
        fun formatted(values: List<String>): String =
            values.zip(widths).joinToString(" ") { (value, width) -> value.padStart(width) }

        emit("TABLE", stageNames[index], "$first-$last")
        emit(formatted(labels))
        for (week in first..last) {
            val r = simulation.stages[index].records[week - 1]
            emit(
                formatted(
                    listOf(
                        week.toString(), r.incoming.toString(), r.shipped.toString(),
                        r.received.toString(), r.inventory.toString(), r.backlog.toString(),
                        r.order.toString(), money(r.cost)
                    )
                )
            )
        }
    }

    private fun costs() {
        val s = simulation
        emit("COSTS", "week", s.week)
        var holding = 0L
        var backlog = 0L
        for ((index, stage) in s.stages.withIndex()) {
            val amount = stage.records.sumOf { it.holding }
            val missing = stage.records.sumOf { it.backlogCost }
            holding += amount
            backlog += missing
            emit(
                stageNames[index], "holding", money(amount), "backlog",
                money(missing), "total", money(amount + missing)
            )
        }
        emit(
            "TOTAL", "holding", money(holding), "backlog",
            money(backlog), "total", money(holding + backlog)
        )
    }

    private fun fillText(records: List<Record>): Triple<Int, Int, String> {
        val ordered = records.sumOf { it.incoming }
        val ontime = records.sumOf { it.ontime }
        val fill = if (ordered == 0) "n/a" else
            decimal(ontime.toLong() * 100, ordered.toLong(), 2) + "%"
        return Triple(ordered, ontime, fill)
    }

    private fun bullwhip() {
        val s = simulation
        val n = s.week
        val demand = s.demands.take(n)
        val demandVar = variation(demand)
        emit(
            "BULLWHIP", "weeks", "1-$n", "demand", "mean",
            decimal(demand.sumOf { it.toLong() }, n.toLong(), 4),
            "var", decimal(demandVar, n.toLong() * n, 4)
        )
        var previous = demandVar
        for ((index, stage) in s.stages.withIndex()) {
            val order = stage.records.map { it.order }
            val v = variation(order)
            emit(
                stageNames[index], "mean", decimal(order.sumOf { it.toLong() }, n.toLong(), 4),
                "var", decimal(v, n.toLong() * n, 4),
                "ratio", if (demandVar == 0L) "n/a" else decimal(v, demandVar, 4),
                "step", if (previous == 0L) "n/a" else decimal(v, previous, 4)
            )
            previous = v
        }
    }

    private fun peaks() {
        val s = simulation
        emit("PEAKS", "weeks", "1-${s.week}")
        for ((index, stage) in s.stages.withIndex()) {
            val inventories = stage.records.map { it.inventory }
            val backlogs = stage.records.map { it.backlog }
            val maximumInventory = inventories.max()
            val maximumBacklog = backlogs.max()
            var longest = 0
            var run = 0
            var start = 0
            var bestStart = 0
            var bestEnd = 0
            for ((index0, backlog) in backlogs.withIndex()) {
                val week = index0 + 1
                if (backlog > 0) {
                    if (run == 0) start = week
                    run++
                    if (run > longest) {
                        longest = run
                        bestStart = start
                        bestEnd = week
                    }
                } else run = 0
            }
            emit(
                stageNames[index], "max_inv", maximumInventory,
                "week", if (maximumInventory != 0) inventories.indexOf(maximumInventory) + 1 else "-",
                "max_back", maximumBacklog, "week",
                if (maximumBacklog != 0) backlogs.indexOf(maximumBacklog) + 1 else "-",
                "longest_stockout", if (longest != 0) "$longest weeks $bestStart-$bestEnd" else "0"
            )
        }
    }

    private fun leadtime(index: Int) {
        val s = simulation
        val stage = s.stages[index]
        val initial = initials[index]
        val nominal = initial.shippingDelay + initial.orderDelay
        val cumulative = mutableListOf<Int>()
        var received = 0
        for (record in stage.records) {
            received += record.received
            cumulative.add(received - nominal * initial.quantity)
        }
        var ordered = 0
        var count = 0
        val leads = mutableListOf<Int>()
        for ((t, r) in stage.records.withIndex()) {
            ordered += r.order
            if (r.order == 0) continue
            count++
            for (u in t + 1 until stage.records.size) {
                if (cumulative[u] >= ordered) {
                    leads.add(u - t)
                    break
                }
            }
        }
        emit(
            "LEADTIME", stageNames[index], "nominal", nominal, "orders", count,
            "completed", leads.size, "open", count - leads.size,
            "min", leads.minOrNull()?.toString() ?: "-",
            "avg", if (leads.isEmpty()) "-" else decimal(leads.sum().toLong(), leads.size.toLong(), 2),
            "max", leads.maxOrNull()?.toString() ?: "-"
        )
    }

    private fun plot(index: Int, mode: String, first: Int, last: Int) {
        val values = values(index, mode).subList(first - 1, last)
        val maximum = values.max()
        if (mode == "NET") {
            emit("PLOT", stageNames[index], mode, "$first-$last", "min", values.min(), "max", maximum)
            val scale = values.maxOf { kotlin.math.abs(it) }
            for ((index0, value) in values.withIndex()) {
                val week = first + index0
                val length = if (scale != 0) kotlin.math.abs(value) * 25 / scale else 0
                val left = if (value < 0) " ".repeat(25 - length) + "-".repeat(length)
                           else " ".repeat(25)
                val right = if (value > 0) "+".repeat(length) else ""
                emit(week.toString().padStart(3) + " $left|$right $value")
            }
        } else {
            emit("PLOT", stageNames[index], mode, "$first-$last", "max", maximum)
            for ((index0, value) in values.withIndex()) {
                val week = first + index0
                val length = if (maximum != 0) value * 50 / maximum else 0
                emit(week.toString().padStart(3) + " |" + "#".repeat(length) + " $value")
            }
        }
    }

    private fun command(command: String, a: List<String>) {
        val s = simulation
        when (command) {
            "DEMAND" -> demand(a.map { it.toInt() })
            "GENERATE" -> generate(a)
            "RUN" -> {
                if (s.week == s.demands.size) {
                    fail("horizon reached at week ${s.demands.size}")
                }
                val first = s.week + 1
                val count = minOf(a[0].toInt(), s.demands.size - s.week)
                var cost = 0L
                repeat(count) {
                    val records = s.step()
                    for ((index, r) in records.withIndex()) {
                        cost += r.cost
                        if (r.before == 0 && r.backlog > 0) {
                            emit("STOCKOUT", stageNames[index], "week", s.week, "backlog", r.backlog)
                        } else if (r.before > 0 && r.backlog == 0) {
                            emit("RECOVER", stageNames[index], "week", s.week)
                        }
                    }
                }
                emit(
                    "RUN", "$first-${s.week}", "demand",
                    s.demands.subList(first - 1, s.week).sum(), "cost", money(cost)
                )
                if (s.week == s.demands.size) emit("HORIZON", s.week)
            }
            "RESET" -> {
                initialize()
                emit("RESET", "week", 0)
            }
            "SAVE" -> {
                snapshots[a[0]] = s.copy()
                emit("SAVE", a[0], "week", s.week)
            }
            "LOAD" -> {
                val snapshot = snapshots[a[0]] ?: fail("no snapshot ${a[0]}")
                simulation = snapshot.copy()
                emit("LOAD", a[0], "week", simulation.week)
            }
            "SET" -> {
                val indices = target(a[0])
                val policy = parsePolicy(a.drop(1))
                for (index in indices) s.setPolicy(index, policy)
                emit("SET", a[0], policy.description)
            }
            "BATCH" -> {
                val index = stageIndex(a[0])
                val lot = a[1].toInt()
                if (lot !in 1..100) fail("invalid batch size ${a[1]}")
                s.stages[index].lot = lot
                emit("BATCH", a[0], lot)
            }
            "CAPACITY" -> {
                val index = if (a[0] == "PLANT") null else stageIndex(a[0])
                val capacity = if (a[1] == "OFF") null else a[1].toInt()
                if (capacity != null && capacity > 10000) fail("invalid capacity ${a[1]}")
                if (index == null) s.plantCapacity = capacity else s.stages[index].capacity = capacity
                emit("CAPACITY", a[0], a[1])
            }
            "COST" -> {
                val index = stageIndex(a[0])
                val holding = a[1].toInt()
                val backlog = a[2].toInt()
                if (holding > 1000 || backlog > 1000) fail("invalid cost")
                s.stages[index].holding = holding
                s.stages[index].backlogRate = backlog
                emit("COST", a[0], "holding", holding, "backlog", backlog)
            }
            "VISIBILITY" -> {
                if (a[0] !in listOf("ON", "OFF")) fail("unknown visibility ${a[0]}")
                s.visibility = a[0]
                emit("VISIBILITY", a[0])
            }
            "SHOCK" -> {
                val week = a[0].toInt()
                val demand = a[1].toInt()
                if (week !in 1..s.demands.size) fail("week ${a[0]} outside horizon")
                if (week <= s.week) fail("week ${a[0]} already simulated")
                val old = s.demands[week - 1]
                s.demands[week - 1] = demand
                emit("SHOCK", "week", week, old, "->", demand)
            }
            "STATUS" -> showStatus()
            "SETTINGS" -> {
                emit("SETTINGS")
                for ((index, stage) in s.stages.withIndex()) {
                    val initial = initials[index]
                    emit(
                        stageNames[index], "holding", stage.holding,
                        "backlog", stage.backlogRate, "batch", stage.lot,
                        "capacity", stage.capacity?.toString() ?: "OFF",
                        "delays", initial.shippingDelay, initial.orderDelay
                    )
                }
                emit("PLANT", "capacity", s.plantCapacity?.toString() ?: "OFF")
                emit("VISIBILITY", s.visibility)
            }
            "WEEK" -> {
                requireWeeks()
                val week = a[0].toInt()
                if (week !in 1..s.week) fail("bad week ${a[0]}")
                showWeek(week)
            }
            "TABLE" -> {
                val index = stageIndex(a[0])
                requireWeeks()
                val (first, last) = rangeCheck(a.drop(1), s.week)
                table(index, first, last)
            }
            "CHAIN" -> {
                requireWeeks()
                val (first, last) = rangeCheck(a, s.week)
                emit("CHAIN", "$first-$last")
                emit(
                    "week".padStart(4) + " " + "demand".padStart(6) + " " +
                    stageNames.joinToString(" ") { it.padStart(11) }
                )
                for (week in first..last) {
                    val orders = s.stages.map { it.records[week - 1].order }
                    emit(
                        week.toString().padStart(4) + " " +
                        s.demands[week - 1].toString().padStart(6) + " " +
                        orders.joinToString(" ") { it.toString().padStart(11) }
                    )
                }
            }
            "DEMANDS" -> {
                val (first, last) = rangeCheck(a, s.demands.size)
                val values = s.demands.subList(first - 1, last)
                emit(
                    "DEMANDS", "$first-$last", "total", values.sum(),
                    "min", values.min(), "max", values.max()
                )
                emit(values.joinToString(" "))
            }
            "COSTS" -> costs()
            "SUMMARY" -> {
                requireWeeks()
                emit("SUMMARY", "weeks", "1-${s.week}")
                for ((index, stage) in s.stages.withIndex()) {
                    val orders = stage.records.map { it.order }
                    emit(
                        stageNames[index],
                        "avg_inv", decimal(stage.records.sumOf { it.inventory.toLong() }, s.week.toLong(), 2),
                        "avg_back", decimal(stage.records.sumOf { it.backlog.toLong() }, s.week.toLong(), 2),
                        "orders", orders.sum(), "min", orders.min(), "max", orders.max(),
                        "zero_weeks", orders.count { it == 0 }
                    )
                }
            }
            "BALANCE" -> {
                emit("BALANCE", "week", s.week)
                for ((index, stage) in s.stages.withIndex()) {
                    emit(
                        stageNames[index], "start", initials[index].inventory,
                        "received", stage.records.sumOf { it.received },
                        "shipped", stage.records.sumOf { it.shipped },
                        "end", stage.inventory, "owed", stage.backlog
                    )
                }
                val initialGoods = initials.sumOf {
                    it.inventory + it.quantity * it.shippingDelay
                }
                emit(
                    "SYSTEM", "initial", initialGoods,
                    "produced", s.plantRecords.sumOf { it.produced },
                    "delivered", s.stages[0].records.sumOf { it.shipped },
                    "stock", s.stages.sumOf { it.inventory },
                    "transit", s.stages.sumOf { it.shipping.sum() }
                )
            }
            "FILLRATE" -> {
                requireWeeks()
                emit("FILLRATE", "weeks", "1-${s.week}")
                for ((index, stage) in s.stages.withIndex()) {
                    val (ordered, ontime, fill) = fillText(stage.records)
                    val stockouts = stage.records.count { it.backlog > 0 }
                    emit(
                        stageNames[index], "fill", fill, "ontime", ontime,
                        "ordered", ordered, "stockout_weeks", stockouts,
                        "service", decimal((s.week - stockouts).toLong() * 100, s.week.toLong(), 2) + "%"
                    )
                }
            }
            "BULLWHIP" -> {
                requireWeeks()
                bullwhip()
            }
            "PEAKS" -> {
                requireWeeks()
                peaks()
            }
            "LEADTIME" -> {
                val index = stageIndex(a[0])
                requireWeeks()
                leadtime(index)
            }
            "PLOT", "HISTOGRAM" -> {
                val index = stageIndex(a[0])
                modeCheck(a[1])
                val width = if (command == "HISTOGRAM") a[2].toInt() else 0
                if (command == "HISTOGRAM" && width !in 1..100) fail("invalid width ${a[2]}")
                requireWeeks()
                if (command == "PLOT") {
                    val (first, last) = rangeCheck(a.drop(2), s.week)
                    plot(index, a[1], first, last)
                } else {
                    val histogram = values(index, a[1]).groupingBy { Math.floorDiv(it, width) }.eachCount()
                    emit("HISTOGRAM", a[0], a[1], "width", width, "weeks", "1-${s.week}")
                    for (bucket in histogram.keys.min()..histogram.keys.max()) {
                        val count = histogram[bucket] ?: 0
                        emit(
                            "${bucket * width}..${bucket * width + width - 1}", count,
                            if (count != 0) " " + "*".repeat(count) else ""
                        )
                        if (count != 0) output[output.lastIndex] = output.last().replace("  *", " *")
                        else output[output.lastIndex] = output.last().trimEnd()
                    }
                }
            }
            "COMPARE" -> {
                val policies = mutableListOf<Policy>()
                var start = 0
                for (end in 0..a.size) {
                    if (end == a.size || a[end] == "/") {
                        policies.add(parsePolicy(a.subList(start, end)))
                        start = end + 1
                    }
                }
                val rows = policies.mapIndexed { index, policy ->
                    val trial = trial(List(4) { policy })
                    val costs = trial.costs().sum()
                    val fill = fillText(trial.stages[0].records).third
                    val demandVariation = variation(trial.demands)
                    val factoryVariation = variation(trial.stages[3].records.map { it.order })
                    val ratio = if (demandVariation == 0L) "n/a" else
                        decimal(factoryVariation, demandVariation, 4)
                    listOf(costs, index, policy.description, fill, ratio)
                }
                val order = rows.sortedWith(
                    compareBy<List<Any>> { it[0] as Long }.thenBy { it[1] as Int }
                )
                emit("COMPARE", policies.size, "weeks", s.demands.size)
                for ((rank, row) in order.withIndex()) {
                    emit(
                        rank + 1, row[2], "total", money(row[0] as Long),
                        "fill", row[3], "bullwhip", row[4]
                    )
                }
            }
            "OPTIMIZE" -> {
                val indices = target(a[0])
                val low = a[1].toInt()
                val high = a[2].toInt()
                if (low > high) fail("bad range ${a[1]} ${a[2]}")
                if (high - low > 200) fail("range too large")
                var best: Triple<Long, Int, Long>? = null
                for (goal in low..high) {
                    val policies = s.stages.map { it.policy }.toMutableList()
                    for (index in indices) {
                        policies[index] = Policy("BASESTOCK", listOf(goal), "BASESTOCK $goal")
                    }
                    val costs = trial(policies).costs()
                    val objective = indices.sumOf { costs[it] }
                    val row = Triple(objective, goal, costs.sum())
                    if (best == null || row.first < best!!.first ||
                        (row.first == best!!.first && goal < best!!.second)) {
                        best = row
                    }
                }
                emit(
                    "OPTIMIZE", a[0], "BASESTOCK", best!!.second,
                    "cost", money(best!!.first), "total", money(best!!.third)
                )
            }
            else -> fail("unknown command $command")
        }
    }

    fun execute(line: String) {
        val words = line.split(" ")
        val command = words.first()
        try {
            command(command, words.drop(1))
        } catch (error: CommandError) {
            emit("ERROR", error.message ?: "")
        }
    }
}

fun main() {
    val reader = BufferedReader(InputStreamReader(System.`in`))
    val settings = List(4) { reader.readLine().split(" ") }
    val game = Game(settings)
    while (true) {
        val line = reader.readLine() ?: break
        if (line == "END") break
        game.execute(line)
    }
    if (game.output.isNotEmpty()) print(game.output.joinToString("\n", postfix = "\n"))
}
