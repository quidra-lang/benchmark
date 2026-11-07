import java.util.TreeMap

private data class Process(val id: Int, var maximum: List<Int>, val created: Int, var allocation: List<Int>) {
    fun need(): List<Int> = sub(maximum, allocation)
    fun duplicate() = copy(maximum = maximum.toList(), allocation = allocation.toList())
}
private data class Waiting(val id: Int, val vector: List<Int>, val since: Int)
private data class Event(val command: Int, val kind: String, val id: Int, val vector: List<Int>, val waited: Int = 0)
private data class State(
    var total: List<Int>, var available: List<Int> = total.toList(),
    val processes: TreeMap<Int, Process> = TreeMap(),
    var queue: MutableList<Waiting> = mutableListOf(),
    val history: MutableList<Event> = mutableListOf()
) {
    fun duplicate(): State {
        val s = State(total.toList(), available.toList())
        processes.forEach { (id, p) -> s.processes[id] = p.duplicate() }
        s.queue.addAll(queue.map { it.copy(vector = it.vector.toList()) })
        s.history.addAll(history.map { it.copy(vector = it.vector.toList()) })
        return s
    }
}
private data class Check(val sequence: List<Int>, val remaining: List<Int>)
private data class Decision(val reason: String?, val sequence: List<Int> = emptyList())
private var state = State(emptyList())
private val snapshots = mutableMapOf<String, State>()
private var mode = "AVOID"
private var policy = "ALLOC"
private var tracing = false
private var autodetect = false
private var command = 0
private val output = StringBuilder()
private val kinds = listOf("granted", "blocked", "unblocked", "released", "finished", "aborted", "cancelled")
private fun emit(line: String) { output.append(line.trimEnd()).append('\n') }
private fun pn(id: Int) = "P$id"
private fun pl(ids: List<Int>) = ids.joinToString(" ") { pn(it) }
private fun vl(v: List<Int>) = v.joinToString(",", "(", ")")
private fun type(i: Int) = ('A'.code + i).toChar().toString()
private fun add(a: List<Int>, b: List<Int>) = a.indices.map { a[it] + b[it] }
private fun sub(a: List<Int>, b: List<Int>) = a.indices.map { a[it] - b[it] }
private fun fits(a: List<Int>, b: List<Int>) = a.indices.all { a[it] <= b[it] }
private fun fail(message: String): Nothing = throw IllegalArgumentException(message)
private fun waiting(id: Int) = state.queue.find { it.id == id }
private fun requestOf(id: Int) = waiting(id)?.vector ?: List(state.total.size) { 0 }
private fun requireProcess(id: Int, unblocked: Boolean = false): Process {
    val p = state.processes[id] ?: fail("unknown process ${pn(id)}")
    if (unblocked && waiting(id) != null) fail("process ${pn(id)} is blocked")
    return p
}
private fun vector(words: List<String>, start: Int): List<Int> {
    if (words.size - start != state.total.size) fail("wrong vector length")
    return words.drop(start).map { it.toInt() }
}
private fun check(available: List<Int>, detecting: Boolean, traced: Boolean, excluded: Set<Int> = emptySet()): Check {
    var work = available.toList()
    val remaining = mutableListOf<Int>()
    val idle = mutableListOf<Int>()
    val sequence = mutableListOf<Int>()
    for (p in state.processes.values) {
        if (p.id in excluded) work = add(work, p.allocation)
        else if (detecting && p.allocation.sum() == 0) idle.add(p.id)
        else remaining.add(p.id)
    }
    val prefix = if (detecting) "[detect]" else "[safety]"
    if (traced) emit("$prefix start work=${vl(work)}" + if (idle.isEmpty()) "" else " idle ${pl(idle)}")
    while (true) {
        val chosen = remaining.find { id -> fits(if (detecting) requestOf(id) else state.processes.getValue(id).need(), work) } ?: break
        work = add(work, state.processes.getValue(chosen).allocation)
        remaining.remove(chosen)
        sequence.add(chosen)
        if (traced) emit("$prefix ${pn(chosen)} can finish, work=${vl(work)}")
    }
    if (traced && remaining.isNotEmpty()) emit("$prefix stuck work=${vl(work)} remaining ${pl(remaining)}")
    return Check(sequence, remaining)
}
private fun detect(traced: Boolean) = check(state.available, true, traced).remaining
private fun rejection(p: Process, v: List<Int>): String? {
    if (waiting(p.id) != null) return "process ${pn(p.id)} is blocked"
    if (v.sum() == 0) return "zero vector"
    if (!fits(v, p.need())) return "request exceeds need"
    if (mode == "ORDER") {
        val last = p.allocation.indexOfLast { it > 0 }
        if ((0..last).any { v[it] > 0 }) return "resource order violation"
    }
    return null
}
private fun decision(p: Process, v: List<Int>, traced: Boolean): Decision {
    if (!fits(v, state.available)) return Decision("insufficient resources")
    if (mode != "AVOID") return Decision(null)
    val old = p.allocation
    p.allocation = add(old, v)
    val result = check(sub(state.available, v), false, traced)
    p.allocation = old
    return Decision(if (result.remaining.isEmpty()) null else "unsafe state", result.sequence)
}
private fun allocate(p: Process, v: List<Int>) {
    p.allocation = add(p.allocation, v)
    state.available = sub(state.available, v)
}
private fun record(kind: String, id: Int, v: List<Int>, waited: Int = 0) {
    state.history.add(Event(command, kind, id, v.toList(), waited))
}
private fun retry() {
    val kept = mutableListOf<Waiting>()
    for (w in state.queue) {
        val p = state.processes.getValue(w.id)
        if (decision(p, w.vector, tracing).reason == null) {
            allocate(p, w.vector)
            emit("unblocked ${pn(w.id)} ${vl(w.vector)}")
            record("unblocked", w.id, w.vector, command - w.since)
        } else kept.add(w)
    }
    state.queue = kept
}
private fun terminate(id: Int, kind: String) {
    val p = state.processes.remove(id)!!
    state.queue.removeAll { it.id == id }
    state.available = add(state.available, p.allocation)
    emit("$kind ${pn(id)} released ${vl(p.allocation)}")
    record(kind, id, p.allocation)
}
private fun compareLists(a: List<Int>, b: List<Int>): Int {
    for (i in 0 until minOf(a.size, b.size)) {
        val c = a[i].compareTo(b[i])
        if (c != 0) return c
    }
    return a.size.compareTo(b.size)
}
private data class Edge(val destination: Int, val resource: Int)
private fun graph(resources: Boolean) {
    val m = state.total.size
    if (resources && state.total.any { it != 1 }) fail("not single-instance")
    val edges = state.processes.keys.associateWith { mutableListOf<Edge>() }
    var any = false
    if (!resources) {
        for (p in state.processes.values) {
            val req = requestOf(p.id)
            for (q in state.processes.values) {
                if (p.id == q.id) continue
                val labels = (0 until m).filter { req[it] > state.available[it] && q.allocation[it] > 0 }
                if (labels.isNotEmpty()) {
                    edges.getValue(p.id).add(Edge(q.id, -1))
                    emit("${pn(p.id)} -> ${pn(q.id)} on ${labels.joinToString(",") { type(it) }}")
                    any = true
                }
            }
        }
        if (!any) emit("no wait edges")
    } else {
        val holders = IntArray(m) { -1 }
        for (p in state.processes.values) for (i in 0 until m) if (p.allocation[i] > 0) holders[i] = p.id
        for (i in 0 until m) if (holders[i] >= 0) emit("assign ${type(i)} -> ${pn(holders[i])}")
        for (p in state.processes.values) {
            val req = requestOf(p.id)
            for (i in 0 until m) if (req[i] > 0) {
                emit("request ${pn(p.id)} -> ${type(i)}")
                if (holders[i] >= 0) edges.getValue(p.id).add(Edge(holders[i], i))
            }
        }
        for (p in state.processes.values) {
            val req = requestOf(p.id)
            val need = p.need()
            for (i in 0 until m) if (need[i] > 0 && req[i] == 0) emit("claim ${pn(p.id)} -> ${type(i)}")
        }
    }
    val cycles = mutableListOf<Pair<List<Int>, String>>()
    for (start in state.processes.keys) {
        val visited = mutableSetOf(start)
        fun search(current: Int, key: List<Int>, labels: List<String>) {
            for (edge in edges.getValue(current)) {
                val next = edge.destination
                if (next < start) continue
                val nextKey = key + (if (resources) listOf(edge.resource, next) else listOf(next))
                val nextLabels = labels + (if (resources) listOf(type(edge.resource), pn(next)) else listOf(pn(next)))
                if (next == start) {
                    if (resources || visited.size > 1) cycles.add(nextKey to "cycle: ${nextLabels.joinToString(" -> ")}")
                } else if (next !in visited) {
                    visited.add(next)
                    search(next, nextKey, nextLabels)
                    visited.remove(next)
                }
            }
        }
        search(start, listOf(start), listOf(pn(start)))
    }
    cycles.sortWith { a, b -> compareLists(a.first, b.first) }
    cycles.forEach { emit(it.second) }
    if (cycles.isEmpty()) emit("no cycles")
}
private fun table(v: List<Int>) = v.indices.joinToString(" ") { v[it].toString().padStart(state.total[it].toString().length) }
private fun showState() {
    val names = state.total.indices.joinToString(" ") { type(it).padStart(state.total[it].toString().length) }
    val headings = listOf("Allocation", "Max", "Need", "Request")
    val widths = headings.map { maxOf(it.length, names.length) }
    fun row(heading: String, fields: List<String>) {
        emit(heading.padEnd(9) + fields.indices.joinToString("") { "  " + fields[it].padEnd(widths[it]) })
    }
    row("Process", headings)
    row("", List(4) { names })
    for (p in state.processes.values) row(pn(p.id), listOf(table(p.allocation), table(p.maximum), table(p.need()), table(requestOf(p.id))))
    row("Available", listOf(table(state.available), "", "", ""))
    row("Total", listOf(table(state.total), "", "", ""))
    emit("blocked queue: " + if (state.queue.isEmpty()) "empty" else state.queue.joinToString(", ") { "${pn(it.id)} ${vl(it.vector)} since t=${it.since}" })
}
private fun stats() {
    for (i in state.total.indices) {
        val total = state.total[i]
        val used = total - state.available[i]
        val requested = state.queue.sumOf { it.vector[i] }
        val percent = used * 1000 / total
        emit("${type(i)}: allocated $used/$total (${percent / 10}.${percent % 10}%), requested $requested")
    }
    emit("events: " + kinds.joinToString(", ") { kind -> "$kind ${state.history.count { it.kind == kind }}" })
    val waits = state.history.filter { it.kind == "unblocked" }
    if (waits.isEmpty()) emit("waits: none")
    else {
        val total = waits.sumOf { it.waited }
        val average = total * 100 / waits.size
        emit("waits: ${waits.size} unblocked, total $total, average ${average / 100}.${(average % 100).toString().padStart(2, '0')}")
    }
}
private fun execute(w: List<String>) {
    val c = w[0]
    if (c in listOf("MODE", "POLICY", "TRACE", "AUTODETECT")) {
        when (c) {
            "MODE" -> mode = w[1]
            "POLICY" -> policy = w[1]
            "TRACE" -> tracing = w[1] == "ON"
            "AUTODETECT" -> autodetect = w[1] == "ON"
        }
        emit("${c.lowercase()} ${w[1]}")
        return
    }
    if (c == "RESOURCES") { state = State(w.drop(1).map { it.toInt() }); emit("resources ${vl(state.total)}"); return }
    if (c in listOf("PROCESS", "CLAIM", "REQUEST", "WHATIF", "RELEASE")) {
        val id = w[1].toInt()
        val v = vector(w, 2)
        val name = pn(id)
        if (c == "PROCESS") {
            if (id in state.processes) fail("duplicate process $name")
            if (!fits(v, state.total)) fail("max exceeds total")
            state.processes[id] = Process(id, v, command, List(v.size) { 0 })
            emit("process $name max ${vl(v)}")
            return
        }
        val p = requireProcess(id, c == "CLAIM" || c == "RELEASE")
        if (c == "CLAIM") {
            if (!fits(p.allocation, v)) fail("claim below allocation")
            if (!fits(v, state.total)) fail("max exceeds total")
            val old = p.maximum
            p.maximum = v
            val unsafe = mode == "AVOID" && check(state.available, false, tracing).remaining.isNotEmpty()
            p.maximum = old
            if (unsafe) fail("claim makes state unsafe")
            p.maximum = v
            emit("claim $name max ${vl(v)}")
            retry()
            return
        }
        if (c == "RELEASE") {
            if (v.sum() == 0) fail("zero vector")
            if (!fits(v, p.allocation)) fail("release exceeds allocation")
            p.allocation = sub(p.allocation, v)
            state.available = add(state.available, v)
            emit("released $name ${vl(v)}")
            record("released", id, v)
            retry()
            return
        }
        val reject = rejection(p, v)
        val prefix = "whatif $name ${vl(v)}"
        if (reject != null) {
            if (c == "REQUEST") fail(reject)
            emit("$prefix: rejected ($reject)")
            return
        }
        val d = decision(p, v, tracing)
        if (c == "WHATIF") {
            if (d.reason != null) emit("$prefix: blocked (${d.reason})")
            else emit("$prefix: granted" + if (mode == "AVOID") ", safe sequence ${pl(d.sequence)}" else "")
        } else if (d.reason == null) {
            allocate(p, v)
            emit("granted $name ${vl(v)}")
            record("granted", id, v)
        } else {
            state.queue.add(Waiting(id, v, command))
            emit("blocked $name ${vl(v)}: ${d.reason}")
            record("blocked", id, v)
            if (autodetect) { val dead = detect(tracing); if (dead.isNotEmpty()) emit("deadlock detected: ${pl(dead)}") }
        }
        return
    }
    if (c == "ADD" || c == "REMOVE") {
        val v = vector(w, 1)
        if (v.sum() == 0) fail("zero vector")
        if (c == "ADD") {
            state.total = add(state.total, v)
            state.available = add(state.available, v)
            emit("added ${vl(v)} total ${vl(state.total)}")
            retry()
        } else {
            if (!fits(v, state.available)) fail("remove exceeds available")
            val total = sub(state.total, v)
            val available = sub(state.available, v)
            if (total.any { it == 0 }) fail("total must stay positive")
            if (state.processes.values.any { !fits(it.maximum, total) }) fail("max exceeds total")
            if (mode == "AVOID" && check(available, false, tracing).remaining.isNotEmpty()) fail("removal makes state unsafe")
            state.total = total
            state.available = available
            emit("removed ${vl(v)} total ${vl(total)}")
        }
        return
    }
    when (c) {
        "FINISH", "ABORT" -> {
            val id = w[1].toInt()
            requireProcess(id, c == "FINISH")
            terminate(id, if (c == "FINISH") "finished" else "aborted")
            retry()
        }
        "CANCEL" -> {
            val id = w[1].toInt()
            requireProcess(id)
            val entry = waiting(id) ?: fail("process ${pn(id)} is not blocked")
            state.queue.remove(entry)
            emit("cancelled ${pn(id)} ${vl(entry.vector)}")
            record("cancelled", id, entry.vector)
        }
        "MAXGRANT" -> {
            val id = w[1].toInt()
            val p = requireProcess(id, true)
            val result = MutableList(state.total.size) { 0 }
            for (i in result.indices) {
                val v = MutableList(result.size) { 0 }
                for (amount in p.need()[i] downTo 1) {
                    v[i] = amount
                    if (rejection(p, v) == null && decision(p, v, false).reason == null) { result[i] = amount; break }
                }
            }
            emit("maxgrant ${pn(id)}: ${vl(result)}")
        }
        "SAFE" -> {
            if (state.processes.isEmpty()) emit("safe: no processes")
            else { val r = check(state.available, false, tracing); emit(if (r.remaining.isEmpty()) "safe: ${pl(r.sequence)}" else "unsafe: ${pl(r.remaining)} cannot finish") }
        }
        "SEQUENCES" -> {
            if (state.processes.isEmpty()) { emit("safe sequences: no processes"); return }
            val limit = w[1].toInt()
            var count = 0
            val path = mutableListOf<Int>()
            val found = mutableListOf<String>()
            fun search(work: List<Int>) {
                if (path.size == state.processes.size) { count++; if (found.size < limit) found.add(pl(path)); return }
                for (p in state.processes.values) if (p.id !in path && fits(p.need(), work)) {
                    path.add(p.id)
                    search(add(work, p.allocation))
                    path.removeAt(path.lastIndex)
                }
            }
            search(state.available)
            emit("safe sequences: $count")
            found.forEach { emit(it) }
        }
        "DEFICIT" -> {
            val results = mutableListOf<String>()
            for (i in state.total.indices) {
                val limit = state.processes.values.sumOf { it.need()[i] }
                var result = "-"
                for (x in 0..limit) {
                    val work = state.available.toMutableList()
                    work[i] += x
                    if (check(work, false, false).remaining.isEmpty()) { result = x.toString(); break }
                }
                results.add(result)
            }
            emit("deficit: ${results.joinToString(",", "(", ")")}")
        }
        "STATE" -> showState()
        "STATS" -> stats()
        "DETECT" -> { val dead = detect(tracing); emit(if (dead.isEmpty()) "no deadlock" else "deadlocked: ${pl(dead)}") }
        "VICTIMS" -> {
            val dead = detect(false)
            if (dead.isEmpty()) { emit("no deadlock"); return }
            val groups = (1 until (1 shl dead.size)).map { mask -> dead.indices.filter { (mask and (1 shl it)) != 0 }.map { dead[it] } }.toMutableList()
            groups.sortWith { a, b ->
                var result = a.size.compareTo(b.size)
                if (result == 0) result = a.sumOf { state.processes.getValue(it).allocation.sum() }.compareTo(b.sumOf { state.processes.getValue(it).allocation.sum() })
                if (result == 0) result = compareLists(a, b)
                result
            }
            for (group in groups) if (check(state.available, true, false, group.toSet()).remaining.isEmpty()) { emit("victims: ${pl(group)}"); break }
        }
        "RECOVER" -> {
            var dead = detect(tracing)
            var count = 0
            if (w.size > 1) { for (id in dead) { terminate(id, "aborted"); count++ }; if (count > 0) retry() }
            else while (dead.isNotEmpty()) {
                var victim = dead.first()
                for (id in dead) {
                    val a = state.processes.getValue(id)
                    val b = state.processes.getValue(victim)
                    val better = when (policy) {
                        "ALLOC" -> a.allocation.sum() < b.allocation.sum() || (a.allocation.sum() == b.allocation.sum() && id > victim)
                        "NEED" -> a.need().sum() > b.need().sum() || (a.need().sum() == b.need().sum() && id > victim)
                        else -> a.created > b.created
                    }
                    if (better) victim = id
                }
                terminate(victim, "aborted")
                retry()
                count++
                dead = detect(tracing)
            }
            emit(if (count == 0) "no deadlock" else "recovered: $count aborted")
        }
        "WAITGRAPH" -> graph(false)
        "GRAPH" -> graph(true)
        "HISTORY" -> {
            var any = false
            for (e in state.history) {
                if (w.size > 1 && !(if (w[1].first().isDigit()) e.id == w[1].toInt() else e.kind == w[1])) continue
                emit("t=${e.command} ${e.kind} ${pn(e.id)} ${vl(e.vector)}" + if (e.kind == "unblocked") " waited ${e.waited}" else "")
                any = true
            }
            if (!any) emit("no events")
        }
        "SNAPSHOT" -> { snapshots[w[1]] = state.duplicate(); emit("saved ${w[1]}") }
        "RESTORE" -> { state = snapshots[w[1]]?.duplicate() ?: fail("unknown snapshot ${w[1]}"); emit("restored ${w[1]}") }
    }
}
fun main() {
    val input = System.`in`.bufferedReader()
    val n = input.readLine().toInt()
    for (i in 1..n) {
        command = i
        try { execute(input.readLine().split(' ')) }
        catch (error: IllegalArgumentException) { emit("error: ${error.message}") }
    }
    print(output)
}
