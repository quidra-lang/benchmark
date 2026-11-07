import java.io.BufferedReader
import java.io.InputStreamReader
import kotlin.math.abs
import kotlin.math.min

private val stations = listOf("GRILL", "FRY", "COLD", "BAR")
private val courses = listOf("DRINK", "STARTER", "MAIN", "DESSERT")

private class CommandError(message: String) : RuntimeException(message)

private fun cents(text: String): Long = text.replace(".", "").toLong()
private fun money(value: Long): String {
    val magnitude = abs(value)
    return (if (value < 0) "-" else "") + magnitude / 100 + "." +
        (magnitude % 100).toString().padStart(2, '0')
}
private fun clock(time: Int): String {
    val minutes = 660 + time
    return (minutes / 60).toString().padStart(2, '0') + ":" +
        (minutes % 60).toString().padStart(2, '0')
}
private fun rounded(value: Long, rate: Int): Long = (value * rate + 50) / 100

private class Staff(val name: String) {
    var parties = 0
    var sales = 0L
    var tips = 0L
}
private class TableInfo(val number: Int, val seats: Int) {
    var check: Check? = null
}
private class Check(
    val party: String, val size: Int, var table: TableInfo,
    val server: Staff, val seated: Int
) {
    val lines = mutableListOf<OrderLine>()
    var paid = 0L
    var discount = 0
    var closed = false
}
private class MenuItem(
    val name: String, val station: String, val prep: Int,
    val price: Long, val course: String, var stock: Int?
)
private class OrderLine(
    val id: Int, val check: Check, var seat: Int,
    val item: String, val quantity: Int, val station: String,
    val prep: Int, val price: Long, val course: String
) {
    var status = "ORDERED"
    var reason: String? = null
    var fire = 0
    var ready = 0
    var started = false
}
private class StationState(val capacity: Int) {
    var up = true
    val queue = mutableListOf<OrderLine>()
    val cooking = mutableListOf<OrderLine>()
    val tickets = mutableListOf<Int>()
    var remakes = 0
}
private data class WaitingEntry(val party: String, val size: Int, val joined: Int)
private data class Amounts(
    val subtotal: Long, val discount: Long, val service: Long,
    val tax: Long, val total: Long, val due: Long
)

private class Restaurant {
    private var now = 0
    private val tables = mutableMapOf<Int, TableInfo>()
    private val servers = mutableListOf<Staff>()
    private val waiting = mutableListOf<WaitingEntry>()
    private val menu = mutableMapOf<String, MenuItem>()
    private val lines = mutableListOf<OrderLine>()
    private val stationState = stations.associateWith {
        StationState(if (it == "BAR") 2 else 1)
    }
    private var happyRate = 0
    private var happyEnd = 0
    private var covers = 0
    private var parties = 0
    private var turns = 0
    private var totalStay = 0
    private val sales = courses.associateWith { 0L }.toMutableMap()
    private val totals = listOf("subtotal", "discount", "service", "tax", "total")
        .associateWith { 0L }.toMutableMap()
    private val payments = mutableMapOf("CASH" to 0L, "CARD" to 0L)
    private var tips = 0L
    private var comps = 0
    private var compAmount = 0L
    private var voids = 0
    private val served = mutableMapOf<String, Int>()
    val output = mutableListOf<String>()

    private fun emit(vararg parts: Any) {
        output.add(parts.joinToString(" ") { it.toString() })
    }

    private fun fail(message: String): Nothing = throw CommandError(message)

    private fun table(text: String): TableInfo =
        tables[text.toInt()] ?: fail("unknown table $text")

    private fun check(text: String): Check =
        table(text).check ?: fail("table $text is free")

    private fun line(text: String): OrderLine {
        val number = text.toInt()
        if (number !in 1..lines.size) fail("unknown line $text")
        return lines[number - 1]
    }

    private fun unlocked(check: Check) {
        if (check.paid > 0L) fail("check for table " + check.table.number + " is locked")
    }

    private fun modifiable(line: OrderLine) {
        if (line.status == "VOID") fail("#" + line.id + " is void")
        if (line.check.closed) fail("#" + line.id + " is on a closed check")
        unlocked(line.check)
    }

    private fun active(check: Check): List<OrderLine> =
        check.lines.filter { it.status != "VOID" }

    private fun unserved(check: Check) {
        val count = active(check).count { it.status != "SERVED" }
        if (count > 0) fail("table " + check.table.number + " has $count unserved items")
    }

    private fun station(name: String): StationState =
        stationState[name] ?: fail("unknown station $name")

    private fun course(name: String) {
        if (name !in courses) fail("unknown course $name")
    }

    private fun item(name: String): MenuItem = menu[name] ?: fail("unknown item $name")

    private fun load(server: Staff): Int =
        tables.values.count { it.check?.server === server }

    private fun selectTable(size: Int): TableInfo? =
        tables.values.filter { it.check == null && it.seats >= size }
            .minWithOrNull(compareBy<TableInfo>({ it.seats }, { it.number }))

    private fun seat(party: String, size: Int, table: TableInfo): Check {
        val server = servers.withIndex().minWithOrNull(
            compareBy<IndexedValue<Staff>>({ load(it.value) }, { it.index })
        )!!.value
        val check = Check(party, size, table, server, now)
        table.check = check
        server.parties++
        covers += size
        parties++
        return check
    }

    private fun processWaiting() {
        val remaining = mutableListOf<WaitingEntry>()
        for (entry in waiting) {
            val table = selectTable(entry.size)
            if (table == null) {
                remaining.add(entry)
            } else {
                val check = seat(entry.party, entry.size, table)
                emit("SEATED", entry.party, entry.size, "table", table.number,
                     "server", check.server.name, "waited", now - entry.joined)
            }
        }
        waiting.clear()
        waiting.addAll(remaining)
    }

    private fun amount(line: OrderLine): Long =
        if (line.reason == null) line.price * line.quantity else 0L

    private fun amounts(check: Check): Amounts {
        val subtotal = active(check).sumOf { amount(it) }
        val discount = rounded(subtotal, check.discount)
        val after = subtotal - discount
        val service = if (check.size >= 6) rounded(after, 18) else 0L
        val tax = rounded(after, 8)
        val total = after + service + tax
        return Amounts(subtotal, discount, service, tax, total, total - check.paid)
    }

    private fun close(check: Check) {
        val amounts = amounts(check)
        turns++
        totalStay += now - check.seated
        for (line in active(check)) {
            sales[line.course] = sales.getValue(line.course) + amount(line)
        }
        val updates = mapOf(
            "subtotal" to amounts.subtotal, "discount" to amounts.discount,
            "service" to amounts.service, "tax" to amounts.tax, "total" to amounts.total
        )
        for ((name, value) in updates) totals[name] = totals.getValue(name) + value
        check.server.sales += amounts.total
        check.closed = true
        check.table.check = null
        emit("FREE", "table", check.table.number, check.party, "stayed", now - check.seated)
        processWaiting()
    }

    private fun start(station: StationState, time: Int) {
        while (station.up && station.queue.isNotEmpty() &&
               station.cooking.size < station.capacity) {
            val line = station.queue.removeAt(0)
            line.status = "COOKING"
            line.ready = time + line.prep
            line.started = true
            station.cooking.add(line)
        }
    }

    private fun tick(minutes: Int) {
        val finish = now + minutes
        emit("TICK", clock(finish))
        while (true) {
            val cooking = stations.flatMap { station(it).cooking }
            val time = cooking.minOfOrNull { it.ready } ?: break
            if (time > finish) break
            for (name in stations) {
                val station = station(name)
                val finished = station.cooking.filter { it.ready == time }.sortedBy { it.id }
                station.cooking.removeAll { it.ready == time }
                for (line in finished) {
                    line.status = "READY"
                    station.tickets.add(time - line.fire)
                    emit("READY", clock(time), name, "#" + line.id, line.item,
                         "x" + line.quantity, "table", line.check.table.number, "seat", line.seat)
                }
            }
            for (name in stations) start(station(name), time)
        }
        now = finish
    }

    private fun seatTotals(check: Check): Map<Int, Long> {
        val sums = mutableMapOf<Int, Long>()
        for (line in active(check)) {
            sums[line.seat] = (sums[line.seat] ?: 0L) + amount(line)
        }
        return sums
    }

    private fun allocate(values: Map<Int, Long>, rate: Int): Map<Int, Long> {
        val result = values.mapValues { (_, value) -> value * rate / 100 }.toMutableMap()
        val remaining = rounded(values.values.sum(), rate) - result.values.sum()
        val order = values.keys.sortedWith(
            compareBy<Int>({ -(values.getValue(it) * rate % 100) }, { it })
        )
        for (i in 0 until remaining.toInt()) {
            val seat = order[i]
            result[seat] = result.getValue(seat) + 1
        }
        return result
    }

    private fun bill(check: Check) {
        emit("BILL", "table", check.table.number, check.party, "guests", check.size)
        val totals = seatTotals(check)
        for (seat in totals.keys.sorted()) {
            emit("SEAT", seat, money(totals.getValue(seat)))
            for (line in active(check)) {
                if (line.seat != seat) continue
                val parts = mutableListOf<Any>("#" + line.id, line.item,
                                               "x" + line.quantity, money(amount(line)))
                if (line.reason != null) parts.addAll(listOf("COMP", line.reason!!))
                emit(*parts.toTypedArray())
            }
        }
        val a = amounts(check)
        emit("SUBTOTAL", money(a.subtotal))
        if (check.discount != 0) emit("DISCOUNT", check.discount.toString() + "%", money(a.discount))
        if (check.size >= 6) emit("SERVICE", money(a.service))
        emit("TAX", money(a.tax))
        emit("TOTAL", money(a.total))
        if (check.paid > 0L) {
            emit("PAID", money(check.paid))
            emit("DUE", money(a.due))
        }
    }

    private fun report() {
        emit("REPORT", clock(now))
        emit("COVERS", covers, "parties", parties)
        emit("TURNS", turns, "avg_stay", if (turns > 0) totalStay / turns else "-")
        val salesLine = mutableListOf<Any>("SALES")
        for (course in courses) salesLine.addAll(listOf(course, money(sales.getValue(course))))
        emit(*salesLine.toTypedArray())
        val totalsLine = mutableListOf<Any>("TOTALS")
        for (key in listOf("subtotal", "discount", "service", "tax", "total")) {
            totalsLine.addAll(listOf(key, money(totals.getValue(key))))
        }
        emit(*totalsLine.toTypedArray())
        emit("PAYMENTS", "cash", money(payments.getValue("CASH")),
             "card", money(payments.getValue("CARD")), "tips", money(tips))
        emit("COMPS", comps, money(compAmount), "VOIDS", voids)
        val mostServed = served.entries.filter { it.value > 0 }
            .sortedWith(compareBy<Map.Entry<String, Int>>({ -it.value }, { it.key }))
            .take(3)
        for ((i, entry) in mostServed.withIndex()) emit("TOP", i + 1, entry.key, entry.value)
        for (name in stations) {
            val station = station(name)
            val tickets = station.tickets
            emit(name, "tickets", tickets.size,
                 "avg", if (tickets.isEmpty()) "-" else (tickets.sum() / tickets.size).toString(),
                 "max", if (tickets.isEmpty()) "-" else tickets.max().toString(),
                 "remakes", station.remakes)
        }
        for (server in servers) {
            emit("SERVER", server.name, "tables", load(server), "parties", server.parties,
                 "sales", money(server.sales), "tips", money(server.tips))
        }
    }

    private fun run(command: String, a: List<String>) {
        when (command) {
            "TABLE" -> {
                val number = a[0].toInt()
                if (tables.containsKey(number)) fail("table " + a[0] + " already exists")
                val table = TableInfo(number, a[1].toInt())
                tables[number] = table
                emit("TABLE", number, "seats", table.seats)
                processWaiting()
            }
            "STAFF" -> {
                if (servers.any { it.name == a[0] }) fail(a[0] + " is already on duty")
                servers.add(Staff(a[0]))
                emit("STAFF", a[0])
            }
            "SEAT" -> {
                val seated = tables.values.firstOrNull { it.check?.party == a[0] }
                if (seated != null) fail(a[0] + " is already seated at table " + seated.number)
                if (waiting.any { it.party == a[0] }) fail(a[0] + " is already waiting")
                val size = a[1].toInt()
                if (tables.values.none { it.seats >= size }) fail("no table for party of $size")
                if (servers.isEmpty()) fail("no server on duty")
                val table = selectTable(size)
                if (table == null) {
                    waiting.add(WaitingEntry(a[0], size, now))
                    emit("WAIT", a[0], size, "position", waiting.size)
                } else {
                    val check = seat(a[0], size, table)
                    emit("SEAT", a[0], size, "table", table.number, "server", check.server.name)
                }
            }
            "CANCEL" -> {
                val index = waiting.indexOfFirst { it.party == a[0] }
                if (index < 0) fail(a[0] + " is not waiting")
                val entry = waiting.removeAt(index)
                emit("CANCEL", entry.party, entry.size, "waited", now - entry.joined)
            }
            "MOVE" -> {
                val from = table(a[0])
                val to = table(a[1])
                val check = from.check ?: fail("table " + a[0] + " is free")
                if (to.check != null) fail("table " + a[1] + " is occupied")
                if (to.seats < check.size) fail("table " + a[1] + " is too small for " + check.party)
                from.check = null
                to.check = check
                check.table = to
                emit("MOVE", check.party, "table", from.number, "->", to.number)
                processWaiting()
            }
            "MENU" -> {
                station(a[1])
                course(a[4])
                val previous = menu[a[0]]
                val item = MenuItem(a[0], a[1], a[2].toInt(), cents(a[3]), a[4], previous?.stock)
                menu[a[0]] = item
                emit("MENU", if (previous == null) "ADD" else "UPDATE",
                     item.name, item.station, item.prep, money(item.price), item.course)
            }
            "STOCK" -> {
                val item = item(a[0])
                item.stock = a[1].toInt()
                emit("STOCK", item.name, item.stock!!)
            }
            "HAPPY" -> {
                happyRate = a[0].toInt()
                happyEnd = now + a[1].toInt()
                emit("HAPPY", happyRate.toString() + "%", "until", clock(happyEnd))
            }
            "ITEMS" -> {
                val items = menu.values.sortedWith(compareBy<MenuItem>({ courses.indexOf(it.course) }, { it.name }))
                emit("ITEMS", items.size)
                for (item in items) {
                    emit(item.course, item.name, item.station, item.prep,
                         money(item.price), item.stock?.toString() ?: "-")
                }
            }
            "ORDER" -> {
                val check = check(a[0])
                unlocked(check)
                val seat = a[1].toInt()
                if (seat > check.size) fail("seat $seat out of range for table " + a[0])
                val item = item(a[2])
                val quantity = a[3].toInt()
                if (item.stock != null && item.stock!! < quantity) {
                    fail("only " + item.stock + " " + item.name + " left")
                }
                val happy = item.course == "DRINK" && now < happyEnd
                val price = item.price - if (happy) rounded(item.price, happyRate) else 0L
                val line = OrderLine(lines.size + 1, check, seat, item.name, quantity,
                                     item.station, item.prep, price, item.course)
                lines.add(line)
                check.lines.add(line)
                val parts = mutableListOf<Any>("ORDER", "#" + line.id, "table", check.table.number,
                                               "seat", seat, item.name, "x" + quantity, money(amount(line)))
                if (happy) parts.add("HAPPY")
                emit(*parts.toTypedArray())
                if (item.stock != null) {
                    item.stock = item.stock!! - quantity
                    if (item.stock == 0) emit("SOLDOUT", item.name)
                }
            }
            "FIRE" -> {
                val check = check(a[0])
                course(a[1])
                val orders = check.lines.filter { it.course == a[1] && it.status == "ORDERED" }
                if (orders.isEmpty()) fail("nothing to fire for " + a[1] + " at table " + a[0])
                if (a[1] == "MAIN" || a[1] == "DESSERT") {
                    val earlier = if (a[1] == "MAIN") listOf("STARTER") else listOf("STARTER", "MAIN")
                    for (name in earlier) {
                        if (check.lines.any { it.course == name && it.status == "ORDERED" }) {
                            fail("fire $name first")
                        }
                    }
                }
                for (line in orders) {
                    line.status = "QUEUED"
                    line.fire = now
                    station(line.station).queue.add(line)
                }
                val ids = orders.map { "#" + it.id }
                emit("FIRE", "table", check.table.number, a[1], *ids.toTypedArray())
                for (name in stations) start(station(name), now)
            }
            "TICK" -> tick(a[0].toInt())
            "SERVE" -> {
                val check = check(a[0])
                val ready = check.lines.filter { it.status == "READY" }
                if (ready.isEmpty()) fail("nothing ready for table " + a[0])
                for (line in ready) {
                    line.status = "SERVED"
                    served[line.item] = (served[line.item] ?: 0) + line.quantity
                }
                emit("SERVE", "table", check.table.number, *ready.map { "#" + it.id }.toTypedArray())
            }
            "RUSH" -> {
                val line = line(a[0])
                if (line.status != "QUEUED") fail("#" + line.id + " is not queued")
                val station = station(line.station)
                station.queue.remove(line)
                station.queue.add(0, line)
                emit("RUSH", "#" + line.id, line.station)
            }
            "REMAKE" -> {
                val line = line(a[0])
                if (line.check.closed) fail("#" + line.id + " is on a closed check")
                if (line.status !in setOf("READY", "SERVED")) {
                    fail("#" + line.id + " is not ready or served")
                }
                line.status = "QUEUED"
                line.fire = now
                val station = station(line.station)
                station.queue.add(0, line)
                station.remakes++
                emit("REMAKE", "#" + line.id, line.item, line.station)
                start(station, now)
            }
            "VOID" -> {
                val line = line(a[0])
                if (line.status == "VOID") fail("#" + line.id + " is already void")
                if (line.started) fail("#" + line.id + " has already started")
                if (line.status == "QUEUED") station(line.station).queue.remove(line)
                line.status = "VOID"
                val item = menu.getValue(line.item)
                if (item.stock != null) item.stock = item.stock!! + line.quantity
                voids++
                emit("VOID", "#" + line.id, line.item, "x" + line.quantity)
            }
            "STATION" -> {
                val station = station(a[0])
                if (a[1] == "DOWN" && !station.up) fail("station " + a[0] + " is already down")
                if (a[1] == "UP" && station.up) fail("station " + a[0] + " is not down")
                station.up = a[1] == "UP"
                if (station.up) start(station, now)
                emit("STATION", a[0], a[1])
            }
            "COMP", "TRANSFER" -> {
                val line = line(a[0])
                modifiable(line)
                if (command == "COMP") {
                    if (line.reason != null) fail("#" + line.id + " is already comped")
                    val amount = amount(line)
                    emit("COMP", "#" + line.id, line.item, money(amount), a[1])
                    comps++
                    compAmount += amount
                    line.reason = a[1]
                } else {
                    val seat = a[1].toInt()
                    if (seat > line.check.size) {
                        fail("seat $seat out of range for table " + line.check.table.number)
                    }
                    if (seat == line.seat) fail("#" + line.id + " is already on seat $seat")
                    emit("TRANSFER", "#" + line.id, "seat", line.seat, "->", seat)
                    line.seat = seat
                }
            }
            "DISCOUNT" -> {
                val check = check(a[0])
                unlocked(check)
                check.discount = a[1].toInt()
                emit("DISCOUNT", "table", check.table.number, check.discount.toString() + "%")
            }
            "BILL" -> bill(check(a[0]))
            "SPLIT" -> {
                val check = check(a[0])
                val amount = amounts(check)
                if (amount.due == 0L) fail("nothing to split for table " + a[0])
                if (a[1] == "EVEN") {
                    val ways = a[2].toInt()
                    if (ways > check.size) fail("cannot split table " + a[0] + " $ways ways")
                    emit("SPLIT", "table", check.table.number, "EVEN", ways,
                         "due", money(amount.due))
                    val quotient = amount.due / ways
                    val remainder = amount.due % ways
                    for (i in 1..ways) {
                        emit("PAYER", i, money(quotient + if (i <= remainder) 1L else 0L))
                    }
                } else {
                    if (check.paid > 0L) fail("table " + a[0] + " has payments")
                    val seatValues = seatTotals(check)
                    val discounts = allocate(seatValues, check.discount)
                    val after = seatValues.mapValues { (seat, amount) -> amount - discounts.getValue(seat) }
                    val services = allocate(after, if (check.size >= 6) 18 else 0)
                    val taxes = allocate(after, 8)
                    emit("SPLIT", "table", check.table.number, "BYSEAT", "total", money(amount.total))
                    for (seat in seatValues.keys.sorted()) {
                        emit("SEAT", seat, "subtotal", money(seatValues.getValue(seat)),
                             "discount", money(discounts.getValue(seat)),
                             "service", money(services.getValue(seat)),
                             "tax", money(taxes.getValue(seat)),
                             "total", money(after.getValue(seat) + services.getValue(seat) + taxes.getValue(seat)))
                    }
                }
            }
            "PAY" -> {
                val check = check(a[0])
                if (a[1] !in setOf("CASH", "CARD")) fail("unknown method " + a[1])
                unserved(check)
                val due = amounts(check).due
                if (due == 0L) fail("nothing to pay for table " + a[0])
                val value = cents(a[2])
                val applied = min(value, due)
                check.paid += applied
                payments[a[1]] = payments.getValue(a[1]) + applied
                if (value < due) {
                    emit("PAY", "table", check.table.number, a[1], money(value),
                         "remaining", money(due - value))
                } else {
                    emit("PAY", "table", check.table.number, a[1], money(value),
                         if (a[1] == "CASH") "change" else "tip", money(value - due))
                    if (a[1] == "CARD") {
                        tips += value - due
                        check.server.tips += value - due
                    }
                    close(check)
                }
            }
            "CLOSE" -> {
                val check = check(a[0])
                unserved(check)
                val due = amounts(check).due
                if (due != 0L) fail("table " + a[0] + " still owes " + money(due))
                close(check)
            }
            "STATUS" -> {
                val check = check(a[0])
                emit("STATUS", "table", check.table.number, check.party,
                     "guests", check.size, "since", clock(check.seated))
                for (line in check.lines) {
                    val parts = mutableListOf<Any>("#" + line.id, "seat", line.seat, line.item,
                                                   "x" + line.quantity, line.course, line.status)
                    if (line.status == "COOKING") parts.addAll(listOf("until", clock(line.ready)))
                    if (line.reason != null) parts.addAll(listOf("COMP", line.reason!!))
                    emit(*parts.toTypedArray())
                }
            }
            "KITCHEN" -> {
                emit("KITCHEN", clock(now))
                for (name in stations) {
                    val station = station(name)
                    val cooking = station.cooking.sortedWith(compareBy<OrderLine>({ it.ready }, { it.id }))
                        .map { "#" + it.id + "@" + clock(it.ready) }
                    val queue = station.queue.map { "#" + it.id }
                    emit(name, if (station.up) "up" else "down", "cooking",
                         if (cooking.isEmpty()) "-" else cooking.joinToString(" "),
                         "queue", if (queue.isEmpty()) "-" else queue.joinToString(" "))
                }
            }
            "FLOOR" -> {
                val ordered = tables.values.sortedBy { it.number }
                val free = ordered.count { it.check == null }
                emit("FLOOR", clock(now), "free", free, "seated", ordered.size - free,
                     "waiting", waiting.size)
                for (table in ordered) {
                    val check = table.check
                    if (check == null) {
                        emit("table", table.number, "seats", table.seats, "free")
                    } else {
                        val parts = mutableListOf<Any>("table", table.number, "seats", table.seats,
                                                       check.party, "guests", check.size, "server",
                                                       check.server.name, "since", clock(check.seated),
                                                       "items", active(check).size, "total",
                                                       money(amounts(check).total))
                        if (check.paid > 0L) parts.addAll(listOf("paid", money(check.paid)))
                        emit(*parts.toTypedArray())
                    }
                }
                for ((i, entry) in waiting.withIndex()) {
                    emit("WAITING", i + 1, entry.party, entry.size, "since", clock(entry.joined))
                }
            }
            "REPORT" -> report()
        }
    }

    fun execute(line: String) {
        val fields = line.trim().split(" ")
        try {
            run(fields[0], fields.drop(1))
        } catch (error: CommandError) {
            emit("ERROR", error.message ?: "")
        }
    }
}

fun main() {
    val reader = BufferedReader(InputStreamReader(System.`in`))
    val count = reader.readLine().toInt()
    val restaurant = Restaurant()
    repeat(count) { restaurant.execute(reader.readLine()) }
    if (restaurant.output.isNotEmpty()) print(restaurant.output.joinToString("\n") + "\n")
}
