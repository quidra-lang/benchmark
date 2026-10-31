import kotlin.math.abs
import kotlin.math.min
private val POLICIES = listOf("COST", "NEAREST", "ROUND", "ETA")
private val KEYS = listOf("FLOORS", "CARS", "CAPACITY", "DOOR", "START", "POLICY", "ZONES", "PARK", "PATIENCE", "BYPASS", "PERIOD", "LIMIT", "COMPARE")
private val ARGS = mapOf("CALL" to 3, "CANCEL" to 1, "OUT" to 1, "IN" to 1, "HOLD" to 2, "FIRE" to 1, "RESET" to 0, "WHERE" to 1, "STATUS" to 0)
private class Invalid(message: String) : RuntimeException(message)
private fun requireThat(ok: Boolean, message: String) {
    if (!ok) throw Invalid(message)
}
private fun joined(items: Collection<*>) = items.joinToString(",").ifEmpty {
    "-"
}
private fun avg(total: Long, count: Int): String {
    if (count == 0) return "-"
    val n = total * 100 / count
    return "${n / 100}.${(n % 100).toString().padStart(2, '0')}"
}
private fun bound(key: String, text: String, low: Int, high: Int): Int {
    val n = text.toInt()
    requireThat(n in low..high, "bad value for $key")
    return n
}
private class Config(lines: List<List<String>>) {
    var floors = 0
    var cars = 0
    var capacity = 0
    var door = 0
    var park = -1
    var patience = -1
    var bypass = 100
    var period = -1
    var limit = 1000
    var starts = emptyList<Int>()
    var homes = emptyList<Int>()
    var zones = emptyList<IntRange>()
    var policy = "COST"
    var compare = emptyList<String>()
    init {
        val entries = mutableMapOf<String, List<String>>()
        for (a in lines) {
            val k = a[0]
            requireThat(k in KEYS, "unknown key $k")
            requireThat(k !in entries, "duplicate key $k")
            entries[k] = a.drop(1)
        }
        for (k in KEYS.take(5)) requireThat(k in entries, "missing key $k")
        for (k in KEYS) {
            val v = entries[k] ?: continue
            val n = v.size
            val countOK = when (k) {
                "START", "ZONES" -> n == cars
                "PARK" -> n == cars + 1
                "COMPARE" -> n in 1..4
                else -> n == 1
            }
            requireThat(countOK, "wrong number of values for $k")
            when (k) {
                "FLOORS" -> floors = bound(k, v[0], 2, 50)
                "CARS" -> cars = bound(k, v[0], 1, 8)
                "CAPACITY" -> capacity = bound(k, v[0], 1, 20)
                "DOOR" -> door = bound(k, v[0], 1, 9)
                "START" -> starts = v.map {
                    bound(k, it, 1, floors)
                }
                "POLICY" -> {
                    requireThat(v[0] in POLICIES, "bad value for $k")
                    policy = v[0]
                }
                "ZONES" -> zones = v.map {
                    val z = it.split(':').map(String::toInt)
                    requireThat(z[0] >= 1 && z[0] < z[1] && z[1] <= floors, "bad value for $k")
                    z[0]..z[1]
                }
                "PARK" -> {
                    park = bound(k, v[0], 0, 100)
                    homes = v.drop(1).map {
                        bound(k, it, 1, floors)
                    }
                }
                "PATIENCE" -> patience = bound(k, v[0], 1, 1000)
                "BYPASS" -> bypass = bound(k, v[0], 50, 100)
                "PERIOD" -> period = bound(k, v[0], 1, 1000)
                "LIMIT" -> limit = bound(k, v[0], 1, 5000)
                "COMPARE" -> {
                    requireThat(v.all {
                        it in POLICIES
                    }
                    && v.toSet().size == v.size, "bad value for $k")
                    compare = v
                }
            }
        }
        if (zones.isEmpty()) zones = List(cars) {
            1..floors
        }
        for (i in 0 until cars) {
            requireThat(starts[i] in zones[i], "car ${i + 1} starts outside its zone")
            requireThat(park < 0 || homes[i] in zones[i], "car ${i + 1} home outside its zone")
        }
    }
    fun serves(i: Int, a: Int, b: Int) = a in zones[i] && b in zones[i]
    fun header(out: MutableList<String>) {
        out.add("config: floors=$floors cars=$cars capacity=$capacity door=$door policy=$policy park=${if (park < 0) "off" else park} patience=${if (patience < 0) "off" else patience} bypass=$bypass period=${if (period < 0) "off" else period} limit=$limit compare=${joined(compare)}")
        for (i in 0 until cars) out.add("E${i + 1}: start=${starts[i]} zone=${zones[i].first}-${zones[i].last} home=${if (park < 0) "-" else homes[i]}")
    }
}
private data class Raw(val line: Int, val words: List<String>)
private data class Event(val time: Int, val command: String, val values: List<Int>)
private fun validate(c: Config, raw: List<Raw>, out: MutableList<String>): List<Event> {
    val events = mutableListOf<Event>()
    var last = 0
    var groups = 0
    var fire = false
    val gone = mutableSetOf<Int>()
    for (r in raw) {
        val a = r.words
        val t = a[0].toInt()
        val cmd = a[1]
        var problem: String? = null
        var v = emptyList<Int>()
        if (cmd !in ARGS) problem = "unknown command $cmd"
        else if (a.size - 2 != ARGS[cmd]) problem = "wrong number of arguments for $cmd"
        else if (t < last) problem = "time goes backwards"
        else {
            v = a.drop(2).map(String::toInt)
            val x = v.firstOrNull() ?: 0
            problem = when (cmd) {
                "CALL" -> when {
                    x !in 1..c.floors || v[1] !in 1..c.floors -> "bad floor"
                    x == v[1] -> "same floor"
                    v[2] !in 1..99 -> "bad count"
                    (0 until c.cars).none {
                        c.serves(it, x, v[1])
                    } -> "no car serves $x->${v[1]}"
                    fire -> "fire service active"
                    else -> null
                }
                "CANCEL", "WHERE" -> if (x !in 1..groups) "unknown group" else null
                "OUT", "IN" -> when {
                    x !in 1..c.cars -> "bad car"
                    cmd == "OUT" && x in gone -> "car $x already out"
                    cmd == "IN" && x !in gone -> "car $x already in"
                    else -> null
                }
                "HOLD" -> when {
                    x !in 1..c.cars -> "bad car"
                    v[1] !in 1..9 -> "bad ticks"
                    else -> null
                }
                "FIRE" -> when {
                    x !in 1..c.floors -> "bad floor"
                    fire -> "fire already active"
                    else -> null
                }
                "RESET" -> if (!fire) "fire not active" else null
                else -> null
            }
        }
        if (problem != null) {
            out.add("line ${r.line}: $problem")
            continue
        }
        last = t
        when (cmd) {
            "CALL" -> groups++
            "OUT" -> gone.add(v[0])
            "IN" -> gone.remove(v[0])
            "FIRE" -> fire = true
            "RESET" -> fire = false
        }
        events.add(Event(t, cmd, v))
    }
    return events
}
private class Group(val number: Int, val landing: Int, val destination: Int, val count: Int, val time: Int) {
    val label get() = "G$number"
    val direction = (destination - landing).compareTo(0)
    var waiting = count
    var boarded = 0
    var delivered = 0
    var lost = 0
    var lastBoard = 0
    var lastAlight = 0
    var waitTotal = 0L
    var travelTotal = 0L
    var car: Car? = null
    val cars = sortedSetOf<Int>()
}
private data class Passenger(val group: Group, val count: Int, val boarded: Int)
private class Car(val number: Int, var floor: Int) {
    val label get() = "E$number"
    var direction = 0
    var door = 0
    var idleStart = 0
    var distance = 0
    var stops = 0
    var boarded = 0
    var busy = 0
    var energy = 0L
    var service = true
    val calls = mutableListOf<Group>()
    var passengers = mutableListOf<Passenger>()
    fun load() = passengers.sumOf {
        it.count
    }
    fun targets() = passengers.map {
        it.group.destination
    }.toSet() + calls.map {
        it.landing
    }
}
private class Simulation(val c: Config, val events: List<Event>, val policy: String) {
    val cars = List(c.cars) {
        Car(it + 1, c.starts[it])
    }
    val groups = mutableListOf<Group>()
    val pending = mutableListOf<Group>()
    val log = mutableListOf<String>()
    var time = 0
    var fireFloor = 0
    var lastRound = 0
    var abandoned = 0
    var evacuated = 0
    var delivered = 0
    var maxWait = 0
    var waitTotal = 0L
    var travelTotal = 0L
    var status = ""
    fun emit(s: String) {
        log.add("$time $s")
    }
    fun bypass(e: Car) = e.load() * 100 >= c.capacity * c.bypass
    fun cost(e: Car, g: Group): Int {
        val f = e.floor
        val d = e.direction
        val x = g.landing
        if (policy == "NEAREST" || d == 0) return abs(f - x)
        val targets = e.targets()
        val distance: Int
        val via: Int
        if (g.direction == d && (x - f) * d >= 0) {
            distance = abs(x - f)
            via = targets.count {
                (it - f) * d > 0 && (x - it) * d > 0
            }
        }
        else {
            val m = if (d > 0) (targets + f).max() else (targets + f).min()
            distance = abs(f - m) + abs(m - x)
            via = targets.count {
                (it - f) * d > 0
            }
        }
        return if (policy == "COST") distance else distance + c.door * via + e.door
    }
    fun assign(g: Group, excluded: Car? = null): Boolean {
        val candidates = cars.filter {
            it.service && it !== excluded && c.serves(it.number - 1, g.landing, g.destination)
        }
        if (candidates.isEmpty()) return false
        val chosen = if (policy == "ROUND") candidates.firstOrNull {
            it.number > lastRound
        } ?: candidates.first() else candidates.minBy {
            cost(it, g)
        }
        if (policy == "ROUND") lastRound = chosen.number
        emit("${chosen.label} ASSIGN ${g.label}" + if (policy == "ROUND") "" else " cost=${cost(chosen, g)}")
        g.car?.calls?.remove(g)
        chosen.calls.add(g)
        g.car = chosen
        return true
    }
    fun dispatch(g: Group) {
        if (!assign(g)) {
            pending.add(g)
            emit("PENDING ${g.label}")
        }
    }
    fun walk(g: Group, word: String) {
        if (g.car == null) pending.remove(g) else {
            g.car!!.calls.remove(g)
            g.car = null
        }
        emit("$word ${g.label} x${g.waiting}")
        g.lost += g.waiting
        abandoned += g.waiting
        g.waiting = 0
    }
    fun event(event: Event) {
        val v = event.values
        val x = v.firstOrNull() ?: 0
        when (event.command) {
            "CALL" -> {
                val g = Group(groups.size + 1, x, v[1], v[2], time)
                groups.add(g)
                emit("CALL ${g.label} $x->${v[1]} x${v[2]}")
                dispatch(g)
            }
            "CANCEL" -> {
                val g = groups[x - 1]
                if (g.waiting > 0) walk(g, "CANCEL") else emit("CANCEL ${g.label} ignored")
            }
            "OUT" -> {
                val e = cars[x - 1]
                e.service = false
                emit("${e.label} OUT")
                val old = e.calls.toList()
                e.calls.clear()
                for (g in old) {
                    g.car = null
                    dispatch(g)
                }
            }
            "IN" -> {
                val e = cars[x - 1]
                e.service = true
                e.idleStart = time
                emit("${e.label} IN")
                val old = pending.toList()
                pending.clear()
                for (g in old) if (!assign(g)) pending.add(g)
            }
            "HOLD" -> {
                val e = cars[x - 1]
                if (e.door > 0) {
                    e.door += v[1]
                    emit("${e.label} HOLD ${e.door}")
                } else emit("${e.label} HOLD ignored")
            }
            "FIRE" -> {
                fireFloor = x
                emit("FIRE $x")
                for (g in groups) if (g.waiting > 0) walk(g, "ABANDON")
            }
            "RESET" -> {
                fireFloor = 0
                emit("RESET")
                cars.forEach {
                    it.idleStart = time
                }
            }
            "WHERE" -> {
                val g = groups[x - 1]
                val riding = cars.mapNotNull {
                    e -> val n = e.passengers.filter {
                        it.group === g
                    }.sumOf {
                        it.count
                    }
                    if (n == 0) null else "${e.label}x$n"
                }
                emit("WHERE ${g.label} waiting=${g.waiting} car=${if (g.waiting == 0) "-" else g.car?.label ?: "pending"} riding=${joined(riding)} delivered=${g.delivered} lost=${g.lost}")
            }
            "STATUS" -> {
                for (e in cars) emit("STATUS ${e.label} floor=${e.floor} dir=${if (e.direction == 0) "idle" else if (e.direction > 0) "up" else "down"} door=${e.door} load=${e.load()} stops=${joined(e.passengers.map { it.group.destination }.toSortedSet())} calls=${joined(e.calls.map { it.label })} service=${if (e.service) "in" else "out"}")
                emit("STATUS pending=${joined(pending.map { it.label })}")
            }
        }
    }
    fun direction(e: Car): Int {
        val f = e.floor
        val d = e.direction
        val here = if (bypass(e)) emptyList() else e.calls.filter {
            it.landing == f
        }
        val targets = e.targets()
        if (d != 0 && (targets.any {
            (it - f) * d > 0
        }
        || here.any {
            it.direction == d
        })) return d
        if (here.isNotEmpty()) return here.first().direction
        if (d != 0 && targets.any {
            (it - f) * d < 0
        }) return -d
        if (d == 0 && e.calls.isNotEmpty()) return (e.calls.first().landing - f).compareTo(0)
        return 0
    }
    fun deliver(p: Passenger) {
        val g = p.group
        val wait = p.boarded - g.time
        val travel = time - g.time
        g.delivered += p.count
        g.lastAlight = time
        g.waitTotal += wait.toLong() * p.count
        g.travelTotal += travel.toLong() * p.count
        delivered += p.count
        waitTotal += wait.toLong() * p.count
        travelTotal += travel.toLong() * p.count
        maxWait = maxOf(maxWait, wait)
    }
    fun open(e: Car) {
        emit("${e.label} OPEN ${e.floor}")
        e.door = c.door
        e.stops++
        e.energy += 2
        val keep = mutableListOf<Passenger>()
        for (p in e.passengers) {
            if (p.group.destination == e.floor) {
                emit("${e.label} ALIGHT ${p.group.label} x${p.count}")
                deliver(p)
            }
            else if (fireFloor != 0) {
                emit("${e.label} EVACUATE ${p.group.label} x${p.count}")
                p.group.lost += p.count
                evacuated += p.count
            }
            else keep.add(p)
        }
        e.passengers = keep
        if (fireFloor != 0) return
        val n = direction(e)
        if (n != 0) e.direction = n
        val boarding = e.calls.filter {
            it.landing == e.floor && it.direction == n
        }
        for (g in boarding) {
            val k = min(c.capacity - e.load(), g.waiting)
            if (k > 0) {
                e.passengers.add(Passenger(g, k, time))
                e.boarded += k
                g.waiting -= k
                g.boarded += k
                g.lastBoard = time
                g.cars.add(e.number)
                emit("${e.label} BOARD ${g.label} x$k")
            }
            if (g.waiting == 0) {
                e.calls.remove(g)
                g.car = null
            } else {
                emit("${e.label} LEFT ${g.label} x${g.waiting}")
                assign(g, e)
            }
        }
    }
    fun move(e: Car, d: Int) {
        e.energy += if (d > 0) 3L + e.load() else 1L
        e.distance++
        e.floor += d
    }
    fun advance(e: Car) {
        val old = e.floor
        if (e.door > 0) e.door--
        if (e.door == 0) {
            val n = if (fireFloor == 0) direction(e) else (fireFloor - e.floor).compareTo(0)
            val stop = if (fireFloor != 0) n == 0 && e.passengers.isNotEmpty() else e.passengers.any {
                it.group.destination == e.floor
            }
            || !bypass(e) && e.calls.any {
                it.landing == e.floor && it.direction == n
            }
            if (stop) open(e)
            else if (n != 0) {
                e.direction = n
                move(e, n)
            }
            else {
                if (e.direction != 0) {
                    emit("${e.label} IDLE ${e.floor}")
                    e.direction = 0
                    e.idleStart = time
                }
                if (fireFloor == 0 && e.service && c.park >= 0 && e.floor != c.homes[e.number - 1] && time - e.idleStart >= c.park) {
                    move(e, (c.homes[e.number - 1] - e.floor).compareTo(0))
                    if (e.floor == c.homes[e.number - 1]) emit("${e.label} PARK ${e.floor}")
                }
            }
        }
        if (e.door > 0 || e.floor != old) e.busy++
    }
    fun settled(e: Car) = e.door == 0 && e.passengers.isEmpty() && e.calls.isEmpty() && (if (fireFloor != 0) e.floor == fireFloor else !e.service || c.park < 0 || e.floor == c.homes[e.number - 1])
    fun run() {
        var index = 0
        while (true) {
            if (c.patience >= 0) for (g in groups) if (g.waiting > 0 && time == g.time + c.patience) walk(g, "ABANDON")
            while (index < events.size && events[index].time == time) event(events[index++])
            cars.forEach {
                advance(it)
            }
            if (index == events.size && cars.all {
                settled(it)
            }) {
                status = "end"
                emit("END")
                return
            }
            if (time == c.limit) {
                status = "abort"
                emit("ABORT")
                return
            }
            time++
        }
    }
    fun averages() = "avg_wait=${avg(waitTotal, delivered)} avg_travel=${avg(travelTotal, delivered)} max_wait=${if (delivered == 0) "-" else maxWait}"
    fun breakdown(label: String, gs: List<Group>) = "$label: groups=${gs.size} passengers=${gs.sumOf { it.count }} delivered=${gs.sumOf { it.delivered }} avg_wait=${avg(gs.sumOf { it.waitTotal }, gs.sumOf { it.delivered })}"
    fun report(out: MutableList<String>) {
        for (g in groups) out.add("${g.label} t=${g.time} ${g.landing}->${g.destination} n=${g.count} delivered=${g.delivered} lost=${g.lost} wait=${if (g.boarded == g.count) g.lastBoard - g.time else "-"} travel=${if (g.delivered == g.count) g.lastAlight - g.time else "-"} cars=${joined(g.cars)}")
        for (e in cars) {
            val u = e.busy.toLong() * 1000 / (time + 1)
            out.add("${e.label} distance=${e.distance} stops=${e.stops} boarded=${e.boarded} busy=${e.busy} util=${u / 10}.${u % 10}% energy=${e.energy}")
        }
        for (f in groups.map {
            it.landing
        }.toSortedSet()) out.add(breakdown("F$f", groups.filter {
            it.landing == f
        }))
        if (c.period > 0) for (p in groups.map {
            it.time / c.period
        }.toSortedSet()) out.add(breakdown("P$p ${p * c.period}-${p * c.period + c.period - 1}", groups.filter {
            it.time / c.period == p
        }))
        out.add("summary: groups=${groups.size} passengers=${groups.sumOf { it.count }} delivered=$delivered abandoned=$abandoned evacuated=$evacuated ${averages()} end=$time")
    }
}
private class Scenario(val name: String) {
    var config: Config? = null
    var sim: Simulation? = null
    fun outcome() = sim?.let {
        if (it.status == "abort") "aborted" else if (it.delivered == 0) "empty" else "ranked"
    } ?: "invalid"
}
fun main() {
    val reader = System.`in`.bufferedReader()
    val q = reader.readLine().toInt()
    var lineNo = 1
    val scenarios = mutableListOf<Scenario>()
    val out = mutableListOf<String>()
    repeat(q) {
        val s = Scenario(reader.readLine().split(' ')[1])
        lineNo++
        scenarios.add(s)
        val settings = mutableListOf<List<String>>()
        val raw = mutableListOf<Raw>()
        while (true) {
            val line = reader.readLine()
            lineNo++
            if (line == "END") break
            val a = line.split(' ')
            if (a[0][0].isDigit()) raw.add(Raw(lineNo, a)) else settings.add(a)
        }
        out.add("== ${s.name} ==")
        try {
            val c = Config(settings)
            s.config = c
            c.header(out)
            val events = validate(c, raw, out)
            val sim = Simulation(c, events, c.policy)
            s.sim = sim
            sim.run()
            out.addAll(sim.log)
            sim.report(out)
            for (p in c.compare) {
                val rerun = Simulation(c, events, p)
                rerun.run()
                out.add("compare $p: delivered=${rerun.delivered} ${rerun.averages()} end=${rerun.time} status=${rerun.status}")
            }
        } catch (e: Invalid) {
            out.add("error: ${e.message}")
        }
    }
    out.add("== ranking ==")
    val ranked = scenarios.filter {
        it.outcome() == "ranked"
    }.sortedWith {
        a, b -> val x = a.sim!!
        val y = b.sim!!
        val r = (x.waitTotal * y.delivered).compareTo(y.waitTotal * x.delivered)
        if (r != 0) r else (x.travelTotal * y.delivered).compareTo(y.travelTotal * x.delivered)
    }
    ranked.forEachIndexed {
        i, s -> out.add("${i + 1}. ${s.name} policy=${s.config!!.policy} ${s.sim!!.averages()}")
    }
    for (s in scenarios) if (s.outcome() != "ranked") out.add("- ${s.name} ${s.outcome()}")
    out.add("== policies ==")
    for (p in POLICIES) {
        val runs = ranked.filter {
            it.config!!.policy == p
        }.map {
            it.sim!!
        }
        if (runs.isNotEmpty()) {
            val n = runs.sumOf {
                it.delivered
            }
            out.add("$p: runs=${runs.size} avg_wait=${avg(runs.sumOf { it.waitTotal }, n)} avg_travel=${avg(runs.sumOf { it.travelTotal }, n)}")
        }
    }
    println(out.joinToString("\n"))
}
