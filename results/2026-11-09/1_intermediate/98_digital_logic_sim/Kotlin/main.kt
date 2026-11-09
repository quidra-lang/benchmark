import java.util.PriorityQueue

private val types = listOf("AND", "OR", "NAND", "NOR", "XOR", "XNOR", "NOT", "BUF", "MUX2", "DFF")
private val counts =
    "BUILD:1 RESET:0 SET:3 APPLY:2 PULSE:3 CLOCK:4 RUN:1 WATCH:1 UNWATCH:1 SHOW:0 CHECK:2 PROBE:1 WAVE:2 HISTORY:1 ACTIVITY:1 STATUS:0 MODULES:0 NETLIST:1 HIERARCHY:1 STATS:1 TRUTHTABLE:1 EQUIV:2 FAULTS:1 CRITICAL:1 PERIOD:1"
        .split(' ')
        .associate {
            val p = it.split(':')
            p[0] to p[1].toInt()
        }
private val simulationCommands =
    "RESET SET APPLY PULSE CLOCK RUN WATCH UNWATCH SHOW CHECK PROBE WAVE HISTORY ACTIVITY STATUS"
        .split(' ')
        .toSet()

private fun fail(s: String): Nothing = throw IllegalArgumentException(s)

private fun nameOK(s: String) = Regex("[a-z][a-z0-9_]{0,15}").matches(s)

private fun numberOK(s: String) = Regex("0|[1-9][0-9]{0,8}").matches(s)

private fun number(s: String, positive: Boolean = false): Int {
    if (!numberOK(s) || (positive && s == "0")) fail("bad number $s")
    return s.toInt()
}

private fun value(s: String): Char {
    if (s !in listOf("0", "1", "X")) fail("bad value $s")
    return s[0]
}

private fun bits(r: Int, n: Int) =
    (0 until n).joinToString("") { ((r shr (n - 1 - it)) and 1).toString() }

private fun logic(kind: String, a: List<Char>): Char {
    var y =
        when (kind) {
            "AND",
            "NAND" -> if ('0' in a) '0' else if ('X' in a) 'X' else '1'
            "OR",
            "NOR" -> if ('1' in a) '1' else if ('X' in a) 'X' else '0'
            "XOR",
            "XNOR" -> if ('X' in a) 'X' else if (a.count { it == '1' } % 2 == 1) '1' else '0'
            "MUX2" ->
                if (a[0] == 'X') if (a[1] == a[2]) a[1] else 'X' else a[if (a[0] == '0') 1 else 2]
            else -> a[0]
        }
    if (kind in listOf("NAND", "NOR", "XNOR", "NOT"))
        y =
            when (y) {
                '0' -> '1'
                '1' -> '0'
                else -> 'X'
            }
    return y
}

private sealed interface Item

private data class Gate(
    val name: String,
    val kind: String,
    val inputs: List<String>,
    val output: String,
    val delay: Int,
) : Item

private data class Instance(
    val name: String,
    val module: Mod,
    val connections: Map<String, String>,
) : Item

private data class Mod(
    val name: String,
    val inputs: List<String>,
    val outputs: List<String>,
    val body: List<Item>,
)

private data class Arrival(
    val late: Map<String, Int>,
    val early: Map<String, Int>,
    val previous: Map<String, String>,
)

private class Circuit(m: Mod) {
    val name = m.name
    val inputs = m.inputs
    val outputs = m.outputs
    val gates = mutableListOf<Gate>()
    val signals: List<String>
    val driver = mutableMapOf<String, Gate>()
    val readers = mutableMapOf<String, MutableList<Gate>>()
    val flops = mutableListOf<Gate>()
    val order = mutableListOf<Gate>()
    val loop: Boolean

    init {
        expand(m, "", emptyMap())
        signals = inputs + gates.map { it.output }
        for (s in signals) readers[s] = mutableListOf()
        for (g in gates) {
            driver[g.output] = g
            if (g.kind == "DFF") flops.add(g)
            for (s in g.inputs.distinct()) readers.getValue(s).add(g)
        }
        val waiting = mutableMapOf<Gate, Int>()
        val ready = ArrayDeque<Gate>()
        for (g in gates) {
            if (g.kind == "DFF") continue
            val n = g.inputs.distinct().count { driver[it]?.kind?.let { k -> k != "DFF" } == true }
            waiting[g] = n
            if (n == 0) ready.addLast(g)
        }
        while (ready.isNotEmpty()) {
            val g = ready.removeLast()
            order.add(g)
            for (r in readers.getValue(g.output)) if (r.kind != "DFF") {
                val n = waiting.getValue(r) - 1
                waiting[r] = n
                if (n == 0) ready.addLast(r)
            }
        }
        loop = order.size != waiting.size
    }

    private fun expand(m: Mod, prefix: String, ports: Map<String, String>) {
        fun actual(s: String) = ports[s] ?: prefix + s
        for (x in m.body) when (x) {
            is Gate ->
                gates.add(
                    Gate(
                        prefix + x.name,
                        x.kind,
                        x.inputs.map { actual(it) },
                        actual(x.output),
                        x.delay,
                    ),
                )
            is Instance ->
                expand(
                    x.module,
                    prefix + x.name + ".",
                    x.connections.mapValues { actual(it.value) },
                )
        }
    }

    fun combinational() {
        if (flops.isNotEmpty()) fail("$name is not combinational")
        if (loop) fail("$name has a combinational loop")
        if (inputs.size > 8) fail("too many inputs ${inputs.size}")
    }

    fun evaluate(b: String, stuck: String = "", v: Char = 'X'): String {
        val values =
            inputs.mapIndexed { i, s -> s to if (s == stuck) v else b[i] }.toMap().toMutableMap()
        for (g in order) values[g.output] =
            if (g.output == stuck) v else logic(g.kind, g.inputs.map { values.getValue(it) })
        return outputs.map { values.getValue(it) }.joinToString("")
    }

    fun arrivals(period: Boolean): Arrival {
        val late = mutableMapOf<String, Int>()
        val early = mutableMapOf<String, Int>()
        val prev = mutableMapOf<String, String>()
        if (period)
            for (g in flops) {
                late[g.output] = g.delay
                early[g.output] = g.delay
            }
        else
            for (s in inputs) {
                late[s] = 0
                early[s] = 0
            }
        for (g in order) {
            val a = g.inputs.filter { it in late }
            if (a.isEmpty()) continue
            var best = a[0]
            for (s in a) if (late.getValue(s) > late.getValue(best)) best = s
            late[g.output] = late.getValue(best) + g.delay
            early[g.output] = a.minOf { early.getValue(it) } + g.delay
            prev[g.output] = best
        }
        return Arrival(late, early, prev)
    }
}

private data class Event(val time: Int, val sequence: Long, val signal: String, val value: Char)

private data class Change(val time: Int, val value: Char)

private class Simulation(val c: Circuit) {
    val watch = mutableListOf<String>()
    val values = mutableMapOf<String, Char>()
    val history = mutableMapOf<String, MutableList<Change>>()
    val queue = PriorityQueue(compareBy<Event> { it.time }.thenBy { it.sequence })
    var time = 0
    var sequence = 0L
    var processed = 0L
    var halted = false

    init {
        reset()
    }

    fun reset() {
        values.clear()
        history.clear()
        for (s in c.signals) {
            values[s] = 'X'
            history[s] = mutableListOf()
        }
        queue.clear()
        time = 0
        sequence = 0
        processed = 0
        halted = false
    }

    fun schedule(t: Int, s: String, v: Char) {
        queue.add(Event(t, sequence++, s, v))
    }

    fun describe(a: List<String>) = a.map { "$it=${values.getValue(it)}" }

    fun run(end: Int) {
        var total = 0
        var glitches = 0
        while (queue.isNotEmpty() && queue.peek().time < end) {
            val t = queue.peek().time
            var count = 0
            val original = mutableMapOf<String, Char>()
            while (queue.isNotEmpty() && queue.peek().time == t) {
                if (count == 1000) {
                    println("halted: oscillation at time $t")
                    queue.clear()
                    time = t
                    halted = true
                    return
                }
                val e = queue.remove()
                count++
                processed++
                val old = values.getValue(e.signal)
                if (old == e.value) continue
                original.putIfAbsent(e.signal, old)
                values[e.signal] = e.value
                for (g in c.readers.getValue(e.signal)) if (g.kind != "DFF")
                    schedule(
                        t + g.delay,
                        g.output,
                        logic(g.kind, g.inputs.map { values.getValue(it) }),
                    )
                else if (e.signal == g.inputs[0] && old == '0' && e.value == '1')
                    schedule(t + g.delay, g.output, values.getValue(g.inputs[1]))
            }
            total += count
            for ((s, v) in original) if (values[s] == v) glitches++
            else history.getValue(s).add(Change(t, values.getValue(s)))
            for (s in watch) if (s in original && values[s] != original[s])
                println("$t $s ${values[s]}")
        }
        time = end
        println("run $end events $total glitches $glitches pending ${queue.size}")
    }
}

private class Simulator {
    val modules = linkedMapOf<String, Mod>()
    var sim: Simulation? = null

    fun lookup(name: String) = modules[name] ?: fail("unknown module $name")

    fun signal(s: String) {
        if (s !in sim!!.values) fail("unknown signal $s")
    }

    fun input(s: String) {
        if (s !in sim!!.c.inputs) fail("not an input $s")
    }

    fun time(w: String): Int {
        val t = number(w)
        if (t < sim!!.time) fail("time $t is in the past")
        return t
    }

    fun define(header: Int, lines: List<String>) {
        var line = header
        try {
            val w = lines[0].split(' ')
            if (
                w.size < 5 ||
                    w[2] != "IN" ||
                    w.drop(3).count { it == "OUT" } != 1 ||
                    w.last() == "OUT"
            )
                fail("bad module header")
            val name = w[1]
            if (!Regex("[A-Z][A-Z0-9_]{0,15}").matches(name)) fail("bad module name $name")
            if (name in modules) fail("duplicate module $name")
            val split = w.drop(3).indexOf("OUT") + 3
            val ins = w.subList(3, split)
            val outs = w.drop(split + 1)
            val seen = mutableSetOf<String>()
            for (p in ins + outs) {
                if (!nameOK(p)) fail("bad name $p")
                if (!seen.add(p)) fail("duplicate port $p")
            }
            val driven = ins.toMutableSet()
            val used = mutableSetOf<String>()
            val body = mutableListOf<Item>()
            val reads = mutableListOf<Pair<Int, String>>()
            var gates = 0
            for (i in 1 until lines.size) {
                line = header + i
                val a = lines[i].split(' ')
                val kind = a[0]
                if (kind in types) {
                    if (a.size < 5 || a[a.size - 3] != "->" || a.count { it == "->" } != 1)
                        fail("bad gate syntax")
                    val n = a[1]
                    if (!nameOK(n)) fail("bad name $n")
                    val inputs = a.subList(2, a.size - 3)
                    val output = a[a.size - 2]
                    val delay = a.last()
                    val lo =
                        when (kind) {
                            "NOT",
                            "BUF" -> 1
                            "MUX2" -> 3
                            else -> 2
                        }
                    val hi = if (types.indexOf(kind) < 6) 8 else lo
                    if (inputs.size !in lo..hi) fail("bad input count ${inputs.size} for $kind")
                    for (s in inputs + output) if (!nameOK(s)) fail("bad name $s")
                    if (!numberOK(delay) || delay.toInt() > 1000) fail("bad delay $delay")
                    if (n in used) fail("duplicate name $n")
                    if (output in driven) fail("multiple drivers for $output")
                    used.add(n)
                    driven.add(output)
                    body.add(Gate(n, kind, inputs, output, delay.toInt()))
                    gates++
                    for (s in inputs) reads.add(line to s)
                } else if (kind == "INST") {
                    if (a.size < 3) fail("bad instance syntax")
                    val n = a[1]
                    if (!nameOK(n)) fail("bad name $n")
                    val m = lookup(a[2])
                    val connections = linkedMapOf<String, String>()
                    for (word in a.drop(3)) {
                        val p = word.split('=')
                        if (p.size != 2 || p[0].isEmpty() || p[1].isEmpty())
                            fail("bad connection $word")
                        if (p[0] !in m.inputs && p[0] !in m.outputs) fail("unknown port ${p[0]}")
                        if (p[0] in connections) fail("duplicate connection ${p[0]}")
                        if (!nameOK(p[1])) fail("bad name ${p[1]}")
                        connections[p[0]] = p[1]
                    }
                    for (p in m.inputs) if (p !in connections) fail("unconnected input $p")
                    if (n in used) fail("duplicate name $n")
                    for ((p, s) in connections) if (p in m.outputs && !driven.add(s))
                        fail("multiple drivers for $s")
                    used.add(n)
                    body.add(Instance(n, m, connections))
                    for ((p, s) in connections) if (p in m.inputs) reads.add(line to s)
                } else fail("unknown statement $kind")
            }
            for (s in outs) reads.add(header to s)
            for ((n, s) in reads) if (s !in driven) {
                line = n
                fail("undriven signal $s")
            }
            modules[name] = Mod(name, ins, outs, body)
            println(
                "defined $name inputs ${ins.size} outputs ${outs.size} gates $gates instances ${body.size-gates}",
            )
        } catch (e: IllegalArgumentException) {
            println("error: line $line: ${e.message}")
        }
    }

    fun hierarchy(m: Mod, depth: Int) {
        for (x in m.body) if (x is Instance) {
            println("  ".repeat(depth) + x.name + " " + x.module.name)
            hierarchy(x.module, depth + 1)
        }
    }

    fun execute(line: Int, w: List<String>) {
        try {
            val cmd = w[0]
            val a = w.drop(1)
            val n = counts[cmd] ?: fail("unknown command $cmd")
            if (a.size < n || (cmd !in setOf("WATCH", "UNWATCH", "SHOW") && a.size != n))
                fail("wrong argument count")
            if (cmd in simulationCommands && sim == null) fail("no circuit")
            if (cmd in setOf("SET", "APPLY", "PULSE", "CLOCK", "RUN") && sim!!.halted)
                fail("simulation halted")
            if (cmd == "MODULES") {
                println("modules ${modules.size}")
                for (m in modules.values) println(
                    "${m.name} inputs ${m.inputs.size} outputs ${m.outputs.size} gates ${Circuit(m).gates.size}",
                )
                return
            }
            if (
                cmd in
                    setOf(
                        "BUILD",
                        "NETLIST",
                        "HIERARCHY",
                        "STATS",
                        "TRUTHTABLE",
                        "EQUIV",
                        "FAULTS",
                        "CRITICAL",
                        "PERIOD",
                    )
            ) {
                val m = lookup(a[0])
                val m2 = if (cmd == "EQUIV") lookup(a[1]) else null
                val c = Circuit(m)
                when (cmd) {
                    "BUILD" -> {
                        sim = Simulation(c)
                        println("built ${c.name} signals ${c.signals.size} gates ${c.gates.size}")
                    }
                    "NETLIST" -> {
                        println("netlist ${c.name} gates ${c.gates.size} signals ${c.signals.size}")
                        for (g in c.gates) println(
                            "${g.name} ${g.kind} ${g.inputs.joinToString(" ")} -> ${g.output} ${g.delay}",
                        )
                    }
                    "HIERARCHY" -> {
                        println(c.name)
                        hierarchy(m, 1)
                    }
                    "STATS" -> {
                        val levels = mutableMapOf<String, Int>()
                        var depth = 0
                        for (g in c.order) {
                            val v = g.inputs.maxOf { levels[it] ?: 0 } + 1
                            levels[g.output] = v
                            depth = maxOf(depth, v)
                        }
                        println(
                            "stats ${c.name} gates ${c.gates.size} signals ${c.signals.size} depth ${if(c.loop)"-" else depth}",
                        )
                        println(
                            "types" +
                                types
                                    .mapNotNull { t ->
                                        val count = c.gates.count { it.kind == t }
                                        if (count > 0) " $t $count" else null
                                    }
                                    .joinToString(""),
                        )
                        var best = c.signals[0]
                        for (s in c.signals) if (
                            c.readers.getValue(s).size > c.readers.getValue(best).size
                        )
                            best = s
                        println("max fanout $best ${c.readers.getValue(best).size}")
                    }
                    "CRITICAL",
                    "PERIOD" -> {
                        val period = cmd == "PERIOD"
                        if (period && c.flops.isEmpty()) fail("${c.name} has no flip-flops")
                        if (c.loop) fail("${c.name} has a combinational loop")
                        val arr = c.arrivals(period)
                        val ends = if (period) c.flops.map { it.inputs[1] } else c.outputs
                        val heading =
                            if (period) "flip-flops ${c.flops.size} period" else "critical"
                        var best: String? = null
                        for (s in ends) {
                            if (!period)
                                println(
                                    if (s in arr.late) "$s min ${arr.early[s]} max ${arr.late[s]}"
                                    else "$s unreachable",
                                )
                            if (
                                s in arr.late &&
                                    (best == null || arr.late.getValue(s) > arr.late.getValue(best))
                            )
                                best = s
                        }
                        if (best == null) println("$heading none")
                        else {
                            var current = best!!
                            val path = mutableListOf(current)
                            while (current in arr.previous) {
                                current = arr.previous.getValue(current)
                                path.add(current)
                            }
                            println(
                                "$heading ${arr.late[best]}: ${path.reversed().joinToString(" -> ")}",
                            )
                        }
                    }
                    else -> {
                        c.combinational()
                        val rows = (0 until (1 shl c.inputs.size)).map { bits(it, c.inputs.size) }
                        val expected = rows.map { c.evaluate(it) }
                        if (cmd == "TRUTHTABLE") {
                            println((c.inputs + "|" + c.outputs).joinToString(" "))
                            for (r in rows.indices) println(
                                (rows[r].map { it.toString() } +
                                        "|" +
                                        expected[r].map { it.toString() })
                                    .joinToString(" "),
                            )
                        } else if (cmd == "EQUIV") {
                            val d = Circuit(m2!!)
                            d.combinational()
                            if (c.inputs.size != d.inputs.size || c.outputs.size != d.outputs.size)
                                fail("port mismatch")
                            for (r in rows.indices) {
                                val v = d.evaluate(rows[r])
                                if (v != expected[r]) {
                                    println("not equivalent at ${rows[r]}: ${expected[r]} vs $v")
                                    return
                                }
                            }
                            println("equivalent")
                        } else {
                            val undetected = mutableListOf<String>()
                            val tests = sortedSetOf<Int>()
                            for (s in c.signals) for (v in "01") {
                                val r =
                                    rows.indices.firstOrNull {
                                        c.evaluate(rows[it], s, v) != expected[it]
                                    }
                                if (r == null) undetected.add("$s/$v") else tests.add(r)
                            }
                            val total = 2 * c.signals.size
                            println("faults $total detected ${total-undetected.size}")
                            for (f in undetected) println("undetected $f")
                            println((listOf("tests") + tests.map { rows[it] }).joinToString(" "))
                        }
                    }
                }
                return
            }
            val s = sim!!
            when (cmd) {
                "RESET" -> {
                    s.reset()
                    println("reset")
                }
                "SET" -> {
                    val t = time(a[0])
                    input(a[1])
                    val v = value(a[2])
                    s.schedule(t, a[1], v)
                    println("set ${a[1]} $v at $t")
                }
                "APPLY" -> {
                    val t = time(a[0])
                    val b = a[1]
                    if (b.length != s.c.inputs.size || b.any { it !in "01X" }) fail("bad vector $b")
                    for (i in b.indices) s.schedule(t, s.c.inputs[i], b[i])
                    println("apply $b at $t")
                }
                "PULSE",
                "CLOCK" -> {
                    input(a[0])
                    val t = time(a[1])
                    val width = number(a[2], true)
                    if (cmd == "PULSE") {
                        s.schedule(t, a[0], '1')
                        s.schedule(t + width, a[0], '0')
                        println("pulse ${a[0]} $t ${t+width}")
                    } else {
                        val count = number(a[3], true)
                        for (i in 0 until count) s.schedule(
                            t + i * width,
                            a[0],
                            if (i % 2 == 0) '0' else '1',
                        )
                        println("clock ${a[0]} events $count last ${t+(count-1)*width}")
                    }
                }
                "RUN" -> {
                    val t = number(a[0])
                    if (t <= s.time) fail("time $t is not after ${s.time}")
                    s.run(t)
                }
                "WATCH",
                "UNWATCH" -> {
                    val seen = mutableSetOf<String>()
                    for (x in a) {
                        signal(x)
                        val watched = x in s.watch
                        if (if (cmd == "WATCH") watched || x in seen else !watched || x in seen)
                            fail((if (cmd == "WATCH") "already watched " else "not watched ") + x)
                        seen.add(x)
                    }
                    if (cmd == "WATCH") s.watch.addAll(a) else s.watch.removeAll(seen)
                    println(
                        "watching " +
                            if (s.watch.isEmpty()) "nothing" else s.watch.joinToString(" "),
                    )
                }
                "SHOW" -> {
                    for (x in a) signal(x)
                    println(
                        (if (a.isNotEmpty()) s.describe(a)
                            else s.describe(s.c.inputs) + "|" + s.describe(s.c.outputs))
                            .joinToString(" "),
                    )
                }
                "CHECK" -> {
                    signal(a[0])
                    val v = value(a[1])
                    println(
                        "check ${a[0]}=$v " +
                            if (s.values[a[0]] == v) "ok" else "failed (${s.values[a[0]]})",
                    )
                }
                "PROBE" -> {
                    val x = a[0]
                    signal(x)
                    val g = s.c.driver[x]
                    println(
                        "$x=${s.values[x]} driven by " +
                            if (g == null) "input"
                            else
                                "${g.name} ${g.kind} ${s.describe(g.inputs).joinToString(" ")} delay ${g.delay}",
                    )
                    val readers = s.c.readers.getValue(x)
                    println(
                        (listOf("fanout", readers.size.toString()) + readers.map { it.name })
                            .joinToString(" "),
                    )
                }
                "WAVE" -> {
                    val first = number(a[0])
                    val last = number(a[1])
                    if (!(first < last && last <= s.time)) fail("bad range $first $last")
                    if (s.watch.isEmpty()) fail("nothing watched")
                    for (x in s.watch) {
                        val h = s.history.getValue(x)
                        var i = 0
                        var v = 'X'
                        val wave = buildString {
                            for (t in first until last) {
                                while (i < h.size && h[i].time <= t) v = h[i++].value
                                append(v)
                            }
                        }
                        println("$x $wave")
                    }
                }
                "HISTORY" -> {
                    val x = a[0]
                    signal(x)
                    val h = s.history.getValue(x)
                    println(
                        (listOf("history", x, "changes", h.size.toString()) +
                                h.map { "${it.time}:${it.value}" })
                            .joinToString(" "),
                    )
                }
                "ACTIVITY" -> {
                    val k = number(a[0], true)
                    for (x in
                        s.c.signals
                            .sortedWith(
                                compareBy<String> { -s.history.getValue(it).size }.thenBy { it },
                            )
                            .take(k)) println("$x ${s.history.getValue(x).size}")
                }
                "STATUS" -> {
                    println(
                        "circuit ${s.c.name} time ${s.time} pending ${s.queue.size} events ${s.processed} halted ${if(s.halted)"yes" else "no"}",
                    )
                    println(
                        "values 0:${s.values.values.count{it=='0'}} 1:${s.values.values.count{it=='1'}} X:${s.values.values.count{it=='X'}}",
                    )
                }
            }
        } catch (e: IllegalArgumentException) {
            println("error: line $line: ${e.message}")
        }
    }
}

fun main() {
    val lines = generateSequence(::readLine).toList()
    val simulator = Simulator()
    var i = 0
    while (i < lines.size && lines[i] != "END") {
        val w = lines[i].split(' ')
        if (w[0] == "MODULE") {
            var end = i + 1
            while (lines[end] != "ENDMODULE") end++
            simulator.define(i + 1, lines.subList(i, end))
            i = end + 1
        } else {
            simulator.execute(i + 1, w)
            i++
        }
    }
}
