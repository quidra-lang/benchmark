private val ALGOS = listOf("FCFS", "SJF", "SRTF", "RR", "PRIORITY", "HRRN", "EDF", "LOTTERY", "MLFQ")
private val KEYS = listOf("cs", "q", "k", "s", "seed")
private val METRICS = listOf("turnaround", "waiting", "response")
private val EVENTS = listOf("PREEMPT", "EXPIRE", "DEMOTE", "BOOST", "AGE")
private val RANGES = mapOf("cs" to 0L..5L, "q" to 1L..20L, "k" to 1L..50L, "s" to 0L..500L, "seed" to 1L..2147483646L)
private class Failure(message: String) : RuntimeException(message)
private fun checkBad(bad: Boolean, message: String) {
    if (bad) throw Failure(message)
}
private fun ratio(u: Long, v: Int): String {
    val n = u * 100 / v
    return "${n / 100}.${(n % 100).toString().padStart(2, '0')}"
}
private fun allowed(a: String) = when (a) {
    "RR" -> listOf("cs", "q")
    "PRIORITY" -> listOf("cs", "k")
    "MLFQ" -> listOf("cs", "s")
    "LOTTERY" -> listOf("cs", "q", "seed")
    else -> listOf("cs")
}
private fun parameters(words: List<String>, algo: String?, preset: String? = null): MutableMap<String, Long> {
    val p = linkedMapOf("cs" to 0L, "q" to 4L, "k" to 5L, "s" to 0L, "seed" to 1L)
    val seen = mutableSetOf<String>()
    if (preset != null) seen.add(preset)
    for (word in words) {
        val (k, text) = word.split('=')
        val v = text.toLong()
        checkBad(k !in KEYS, "unknown key $k")
        checkBad(algo != null && k !in allowed(algo), "key $k not allowed for $algo")
        checkBad(k in seen, "duplicate key $k")
        checkBad(v !in RANGES.getValue(k), "invalid $k")
        seen.add(k)
        p[k] = v
    }
    return p
}
private fun notation(p: Map<String, Long>, algo: String? = null) = (if (algo == null) KEYS else allowed(algo)).joinToString(" ") {
    "$it=${p.getValue(it)}"
}
private class RandomState(var x: Long) {
    fun draw(n: Int): Int {
        x = 48271 * x % 2147483647
        return (x % n).toInt()
    }
}
private class Process(val id: String, val arrival: Int, var priority: Int, val bursts: List<Int>) {
    var deadline = 0
    fun absolute() = if (deadline == 0) Int.MAX_VALUE else arrival + deadline
    fun describe() = "$id arrival=$arrival priority=$priority deadline=${if (deadline == 0) "none" else deadline} bursts=${bursts.mapIndexed { i, b -> "${if (i % 2 == 0) "C" else "I"}$b" }.joinToString(",")}"
}
private class Burst(val length: Int, val ready: Int) {
    var start = -1
    var end = 0
    var slices = 0
}
private class Job(val p: Process) {
    val id get() = p.id
    var state = "FUTURE"
    var burst = 0
    var left = p.bursts[0]
    var effective = p.priority
    var wait = 0
    var level = 0
    var used = 0
    var enqueued = 0
    var start = -1
    var finish = 0
    val records = mutableListOf<Burst>()
    val timeline = StringBuilder()
    fun advance() {
        left = p.bursts[++burst]
    }
    fun slices() = records.sumOf {
        it.slices
    }
    fun metrics(): List<Long> {
        val turn = finish - p.arrival
        return listOf(turn.toLong(), (turn - p.bursts.sum()).toLong(), (start - p.arrival).toLong())
    }
    fun missed() = p.deadline > 0 && finish > p.absolute()
}
private class Simulation(processes: Collection<Process>, val algo: String, val p: Map<String, Long>, val snapshotTime: Int = -1) {
    val jobs = processes.sortedBy {
        it.id
    }.map {
        Job(it)
    }
    val queues = List(3) {
        mutableListOf<Job>()
    }
    var cpu = "IDLE"
    var current: Job? = null
    var previous: Job? = null
    var time = 0
    var switchLeft = 0
    var runLength = 0
    var switches = 0
    val random = RandomState(p.getValue("seed"))
    val events = mutableListOf<String>()
    val labels = mutableListOf<String>()
    val cpuStates = mutableListOf<String>()
    val lengths = mutableListOf<Int>()
    val counts = mutableMapOf<String, Int>()
    var snapshot: List<String>? = null
    init {
        run()
    }
    fun event(kind: String, vararg details: Any) {
        events.add((listOf(time, kind) + details).joinToString(" "))
        counts[kind] = counts.getOrDefault(kind, 0) + 1
    }
    fun enqueue(j: Job) {
        j.state = "READY"
        j.enqueued = time
        queues[if (algo == "MLFQ") j.level else 0].add(j)
    }
    fun release() {
        cpu = "IDLE"
        current = null
    }
    fun start(j: Job) {
        current = j
        cpu = "RUN"
        j.state = "RUN"
        runLength = 0
        if (j.start < 0) j.start = time
        if (j.records.last().start < 0) j.records.last().start = time
    }
    fun preempts(j: Job): Boolean = when (algo) {
        "SRTF" -> queues[0].any {
            it.left < j.left
        }
        "PRIORITY" -> queues[0].any {
            it.effective < j.effective
        }
        "EDF" -> queues[0].any {
            it.p.absolute() < j.p.absolute()
        }
        "MLFQ" -> queues.take(j.level).any {
            it.isNotEmpty()
        }
        else -> false
    }
    fun choose(q: List<Job>): Job {
        var best = q.first()
        if (algo == "LOTTERY") {
            var r = random.draw(q.sumOf {
                10 - it.p.priority
            })
            for (j in q) {
                r -= 10 - j.p.priority
                if (r < 0) return j
            }
        }
        for (j in q) {
            val better = when (algo) {
                "SJF", "SRTF" -> j.left < best.left
                "PRIORITY" -> j.effective < best.effective
                "EDF" -> j.p.absolute() < best.p.absolute()
                "HRRN" -> (time - j.enqueued + j.left).toLong() * best.left > (time - best.enqueued + best.left).toLong() * j.left
                else -> false
            }
            if (better) best = j
        }
        return best
    }
    fun run() {
        while (true) {
            if (algo == "PRIORITY") for (j in queues[0]) {
                j.wait++
                if (j.wait.toLong() == p.getValue("k")) {
                    j.wait = 0
                    if (j.effective > 0) {
                        j.effective--
                        event("AGE", j.id, j.effective)
                    }
                }
            }
            for (j in jobs) if (j.state == "IO" && j.left == 0) {
                j.advance()
                j.records.add(Burst(j.left, time))
                enqueue(j)
                event("IODONE", j.id)
            }
            for (j in jobs) if (j.state == "FUTURE" && j.p.arrival == time) {
                j.records.add(Burst(j.left, time))
                enqueue(j)
                event("ARRIVE", j.id)
            }
            if (cpu == "SWITCH" && switchLeft == 0) {
                start(current!!)
                event("START", current!!.id)
            }
            else if (cpu == "RUN") {
                val j = current!!
                if (j.left == 0 && j.burst == j.p.bursts.lastIndex) {
                    j.state = "DONE"
                    j.finish = time
                    event("DONE", j.id)
                    release()
                }
                else {
                    val demoted = algo == "MLFQ" && j.level < 2 && j.used == (if (j.level == 0) 4 else 8)
                    if (demoted) {
                        j.level++
                        j.used = 0
                        event("DEMOTE", j.id, j.level)
                    }
                    when {
                        j.left == 0 -> {
                            j.advance()
                            j.state = "IO"
                            event("IO", j.id, j.left)
                            release()
                        }
                        demoted -> {
                            enqueue(j)
                            release()
                        }
                        algo in listOf("RR", "LOTTERY") && runLength.toLong() == p.getValue("q") -> {
                            enqueue(j)
                            event("EXPIRE", j.id)
                            release()
                        }
                        preempts(j) -> {
                            enqueue(j)
                            event("PREEMPT", j.id)
                            release()
                        }
                    }
                }
            }
            if (jobs.all {
                it.state == "DONE"
            }) break
            val interval = p.getValue("s")
            if (algo == "MLFQ" && interval > 0 && time > 0 && time % interval == 0L) {
                queues[0].addAll(queues[1])
                queues[0].addAll(queues[2])
                queues[1].clear()
                queues[2].clear()
                jobs.forEach {
                    it.level = 0
                    it.used = 0
                }
                event("BOOST")
            }
            if (cpu == "IDLE") {
                val q = queues.firstOrNull {
                    it.isNotEmpty()
                }
                if (q != null) {
                    val j = if (algo == "MLFQ") q.first() else choose(q)
                    q.remove(j)
                    j.effective = j.p.priority
                    j.wait = 0
                    j.records.last().slices++
                    val switched = j !== previous
                    if (switched) switches++
                    if (switched && p.getValue("cs") > 0) {
                        current = j
                        cpu = "SWITCH"
                        j.state = "SWITCH"
                        switchLeft = p.getValue("cs").toInt()
                        event("SWITCH", j.id)
                    }
                    else {
                        start(j)
                        event("DISPATCH", j.id)
                    }
                }
            }
            if (time == snapshotTime) capture()
            for (j in jobs) j.timeline.append(when (j.state) {
                "READY" -> '.'
                "SWITCH" -> 's'
                "RUN" -> '#'
                "IO" -> 'i'
                else -> '-'
            })
            lengths.add(queues.sumOf {
                it.size
            })
            cpuStates.add(cpu)
            when (cpu) {
                "RUN" -> {
                    val j = current!!
                    j.left--
                    j.used++
                    runLength++
                    previous = j
                    labels.add(j.id)
                    if (j.left == 0) j.records.last().end = time + 1
                }
                "SWITCH" -> {
                    switchLeft--
                    labels.add("CS")
                }
                else -> labels.add("IDLE")
            }
            for (j in jobs) if (j.state == "IO") j.left--
            time++
        }
        if (snapshot == null) capture()
    }
    fun capture() {
        val lines = mutableListOf("CPU $cpu" + (current?.let {
            " ${it.id}"
        } ?: ""))
        for (i in 0 until (if (algo == "MLFQ") 3 else 1)) lines.add("QUEUE${if (algo == "MLFQ") i else ""} ${queues[i].joinToString(" ") { it.id }.ifEmpty { "none" }}")
        for (j in jobs) {
            var s = "${j.id} ${j.state}"
            s += when (j.state) {
                "FUTURE" -> " at=${j.p.arrival}"
                "DONE" -> " at=${j.finish}"
                else -> " burst=${j.burst + 1} left=${j.left}" + if (algo == "PRIORITY") " prio=${j.effective}" else if (algo == "MLFQ") " level=${j.level} used=${j.used}" else ""
            }
            lines.add(s)
        }
        snapshot = lines
    }
    fun totals() = List(3) {
        i -> jobs.sumOf {
            it.metrics()[i]
        }
    }
    fun averages(): String {
        val t = totals()
        return "turnaround=${ratio(t[0], jobs.size)} waiting=${ratio(t[1], jobs.size)} response=${ratio(t[2], jobs.size)}"
    }
    fun ticks(a: Int, b: Int) = listOf("RUN", "SWITCH", "IDLE").map {
        state -> cpuStates.subList(a, b).count {
            it == state
        }
    }
    fun util() = ratio(ticks(0, time)[0] * 100L, time)
    fun missed() = jobs.count {
        it.missed()
    }
    fun met() = jobs.count {
        it.p.deadline > 0 && !it.missed()
    }
}
private class Scheduler {
    val registry = sortedMapOf<String, Process>()
    val output = StringBuilder()
    fun emit(s: String) {
        output.append(s).append('\n')
    }
    fun process(id: String): Process {
        checkBad(id !in registry, "unknown process $id")
        return registry.getValue(id)
    }
    fun algorithm(algo: String) {
        checkBad(algo !in ALGOS, "unknown algorithm $algo")
    }
    fun prepare(words: List<String>, algo: String? = null, preset: String? = null): MutableMap<String, Long> {
        val p = parameters(words, algo, preset)
        checkBad(registry.isEmpty(), "no processes")
        return p
    }
    fun sim(algo: String, p: Map<String, Long>) = Simulation(registry.values, algo, p)
    fun table(cells: List<String>) = cells.first().padEnd(8) + cells.drop(1).joinToString("") {
        " ${it.padStart(8)}"
    }
    fun execute(line: String) {
        val a = line.split(' ')
        val c = a[0]
        try {
            when (c) {
                "PROC" -> {
                    val id = a[1]
                    checkBad(id in registry, "duplicate process $id")
                    checkBad(registry.size == 10, "too many processes")
                    val arrival = a[2].toInt()
                    val priority = a[3].toInt()
                    checkBad(arrival > 200, "invalid arrival $id")
                    checkBad(priority > 9, "invalid priority $id")
                    val words = a.drop(4)
                    checkBad(words.size % 2 == 0, "invalid bursts $id")
                    val bursts = words.mapIndexed {
                        i, word -> val n = word.drop(1).toInt()
                        checkBad(word[0] != (if (i % 2 == 0) 'C' else 'I') || n !in 1..30, "invalid bursts $id")
                        n
                    }
                    registry[id] = Process(id, arrival, priority, bursts)
                    emit("PROC $id cpu=${bursts.filterIndexed { i, _ -> i % 2 == 0 }.sum()} io=${bursts.filterIndexed { i, _ -> i % 2 == 1 }.sum()}")
                }
                "GEN" -> {
                    val n = a[2].toInt()
                    for (i in 1..n) checkBad("${a[1]}$i" in registry, "duplicate process ${a[1]}$i")
                    checkBad(registry.size + n > 10, "too many processes")
                    emit("GEN count=$n")
                    val random = RandomState(a[3].toLong())
                    for (i in 1..n) {
                        val arrival = random.draw(21)
                        val priority = random.draw(10)
                        val m = 1 + random.draw(3)
                        val bursts = mutableListOf<Int>()
                        repeat(m) {
                            j -> if (j > 0) bursts.add(1 + random.draw(8))
                            bursts.add(1 + random.draw(9))
                        }
                        val p = Process("${a[1]}$i", arrival, priority, bursts)
                        registry[p.id] = p
                        emit(p.describe())
                    }
                }
                "SETPRIO" -> {
                    val p = process(a[1])
                    val v = a[2].toInt()
                    checkBad(v > 9, "invalid priority ${p.id}")
                    p.priority = v
                    emit("SETPRIO ${p.id} priority=$v")
                }
                "DEADLINE" -> {
                    val p = process(a[1])
                    val v = a[2].toInt()
                    checkBad(v > 1000, "invalid deadline ${p.id}")
                    p.deadline = v
                    emit("DEADLINE ${p.id} ${if (v == 0) "none" else v}")
                }
                "DROP" -> {
                    val p = process(a[1])
                    registry.remove(p.id)
                    emit("DROP ${p.id}")
                }
                "CLEAR" -> {
                    val n = registry.size
                    registry.clear()
                    emit("CLEAR count=$n")
                }
                "LIST" -> {
                    emit("LIST count=${registry.size}")
                    registry.values.forEach {
                        emit(it.describe())
                    }
                }
                else -> simulationCommand(c, a)
            }
        } catch (e: Failure) {
            emit("ERROR ${e.message}")
        }
    }
    fun simulationCommand(c: String, a: List<String>) {
        if (c == "COMPARE" || c == "RANK") {
            val metric = if (c == "RANK") a[1] else null
            if (metric != null) checkBad(metric !in METRICS + listOf("end", "switches", "missed"), "unknown metric $metric")
            val p = prepare(a.drop(if (metric == null) 1 else 2))
            val sims = ALGOS.map {
                sim(it, p)
            }
            if (metric == null) {
                emit("COMPARE ${notation(p)}")
                emit(table(listOf("ALGO", "TURN", "WAIT", "RESP", "UTIL", "END", "SWITCH", "MISS")))
                for (s in sims) emit(table(listOf(s.algo) + s.totals().map {
                    ratio(it, s.jobs.size)
                } + listOf(s.util(), s.time.toString(), s.switches.toString(), s.missed().toString())))
                emit("BEST " + METRICS.mapIndexed {
                    i, name -> "$name=${sims.minBy { it.totals()[i] }.algo}"
                }.joinToString(" "))
            } else {
                emit("RANK $metric ${notation(p)}")
                val index = METRICS.indexOf(metric)
                val values = sims.map {
                    s -> if (index >= 0) s.totals()[index] else when (metric) {
                        "end" -> s.time.toLong()
                        "switches" -> s.switches.toLong()
                        else -> s.missed().toLong()
                    }
                }
                for (i in values.indices.sortedBy {
                    values[it]
                }) {
                    val value = values[i]
                    emit("${1 + values.count { it < value }} ${ALGOS[i]} ${if (index >= 0) ratio(value, registry.size) else value}")
                }
            }
            return
        }
        val algo = a[1]
        algorithm(algo)
        if (c == "DIFF") {
            val second = a[2]
            algorithm(second)
            val p = prepare(a.drop(3))
            val one = sim(algo, p)
            val two = sim(second, p)
            emit("DIFF $algo $second ${notation(p)}")
            var win = 0
            var loss = 0
            var ties = 0
            one.jobs.zip(two.jobs).forEach {
                (j, other) -> val x = j.metrics()
                val y = other.metrics()
                emit("${j.id} turnaround=${x[0]}/${y[0]} waiting=${x[1]}/${y[1]} response=${x[2]}/${y[2]}")
                when {
                    x[0] < y[0] -> win++
                    x[0] > y[0] -> loss++
                    else -> ties++
                }
            }
            emit("WINS $algo=$win $second=$loss ties=$ties")
            return
        }
        if (c == "SWEEP") {
            val key = a[2]
            checkBad(key !in KEYS, "unknown key $key")
            checkBad(key !in allowed(algo), "key $key not allowed for $algo")
            val lo = a[3].toLong()
            val hi = a[4].toLong()
            checkBad(lo > hi || lo !in RANGES.getValue(key) || hi !in RANGES.getValue(key) || hi - lo > 20, "invalid range")
            val p = prepare(a.drop(5), algo, key)
            emit("SWEEP $algo $key $lo $hi")
            var best = lo
            var total = Long.MAX_VALUE
            for (v in lo..hi) {
                p[key] = v
                val s = sim(algo, p)
                emit("${notation(p, algo)} ${s.averages()} util=${s.util()} end=${s.time} switches=${s.switches}")
                if (s.totals()[1] < total) {
                    total = s.totals()[1]
                    best = v
                }
            }
            emit("BEST $key=$best")
            return
        }
        val extra = if (c in listOf("WINDOW", "SNAPSHOT")) a[2].toInt() else 0
        if (c == "WINDOW") checkBad(extra !in 1..1000, "invalid window")
        val p = prepare(a.drop(if (c in listOf("WINDOW", "SNAPSHOT")) 3 else 2), algo)
        val s = Simulation(registry.values, algo, p, if (c == "SNAPSHOT") extra else -1)
        val header = "$c $algo ${notation(p, algo)}"
        when (c) {
            "TRACE" -> {
                emit(header)
                s.events.forEach {
                    emit(it)
                }
                emit("END ${s.time}")
            }
            "TIMELINE" -> {
                checkBad(s.time > 100, "too long ${s.time}")
                emit("$header end=${s.time}")
                for (j in s.jobs) emit("${j.id.padEnd(8)} ${j.timeline}")
            }
            "SNAPSHOT" -> {
                emit("$header t=$extra")
                s.snapshot!!.forEach {
                    emit(it)
                }
            }
            "BURSTS" -> {
                emit(header)
                for (j in s.jobs) j.records.forEachIndexed {
                    i, b -> emit("${j.id} #${i + 1} len=${b.length} ready=${b.ready} start=${b.start} end=${b.end} wait=${b.end - b.ready - b.length} slices=${b.slices}")
                }
            }
            "WINDOW" -> {
                emit("$header width=$extra")
                for (start in 0 until s.time step extra) {
                    val end = minOf(start + extra, s.time)
                    val t = s.ticks(start, end)
                    val counts = sortedMapOf<String, Int>()
                    for (i in start until end) if (s.cpuStates[i] == "RUN") counts[s.labels[i]] = counts.getOrDefault(s.labels[i], 0) + 1
                    val top = counts.entries.maxByOrNull {
                        it.value
                    }?.key ?: "none"
                    emit("$start-$end busy=${t[0]} switch=${t[1]} idle=${t[2]} util=${ratio(t[0] * 100L, end - start)} top=$top")
                }
            }
            "STATS" -> {
                emit(header)
                for (i in 0..2) {
                    val values = s.jobs.map {
                        it.metrics()[i]
                    }
                    val low = values.min()
                    val high = values.max()
                    val sorted = values.sorted()
                    val n = sorted.size
                    val doubled = sorted[n / 2] + sorted[(n - 1) / 2]
                    emit("${METRICS[i]} min=$low (${s.jobs[values.indexOf(low)].id}) max=$high (${s.jobs[values.indexOf(high)].id}) median=${doubled / 2}.${if (doubled % 2 == 0L) 0 else 5} total=${s.totals()[i]}")
                }
            }
            "RUN" -> {
                emit(header)
                val segments = mutableListOf<String>()
                var start = 0
                for (t in 1..s.time) if (t == s.time || s.labels[t] != s.labels[start]) {
                    segments.add("[$start-$t ${s.labels[start]}]")
                    start = t
                }
                segments.chunked(8).forEach {
                    emit("GANTT " + it.joinToString(""))
                }
                for (j in s.jobs) {
                    val m = j.metrics()
                    emit("${j.id} arrival=${j.p.arrival} done=${j.finish} turnaround=${m[0]} waiting=${m[1]} response=${m[2]} slices=${j.slices()}" + if (j.p.deadline == 0) "" else " deadline=${j.p.absolute()} late=${maxOf(0, j.finish - j.p.absolute())}")
                }
                emit("AVERAGE ${s.averages()}")
                val t = s.ticks(0, s.time)
                emit("CPU end=${s.time} busy=${t[0]} switch=${t[1]} idle=${t[2]} switches=${s.switches} util=${s.util()}")
                emit("QUEUE max=${s.lengths.max()} avg=${ratio(s.lengths.sumOf { it.toLong() }, s.time)}")
                emit("EVENTS " + EVENTS.joinToString(" ") {
                    "${it.lowercase()}=${s.counts.getOrDefault(it, 0)}"
                })
                emit("DEADLINE met=${s.met()} missed=${s.missed()}")
            }
        }
    }
}
fun main() {
    val reader = System.`in`.bufferedReader()
    val s = Scheduler()
    repeat(reader.readLine().toInt()) {
        s.execute(reader.readLine())
    }
    print(s.output)
}
