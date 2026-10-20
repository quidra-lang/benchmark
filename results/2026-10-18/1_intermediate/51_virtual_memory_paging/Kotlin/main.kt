import kotlin.math.max
import kotlin.math.min

val policies = listOf("FIFO", "LRU", "LFU", "NRU", "AGING", "CLOCK", "ECLOCK", "WSCLOCK", "RANDOM", "OPT")
val output = mutableListOf<String>()
fun hex(value: Int) = "0x" + value.toString(16).uppercase()
fun address(s: String) = s.substring(2).toInt(16)
fun decimal(v: Long) = "${v / 100}." + (v % 100).toString().padStart(2, '0')
fun ratio(x: Int, y: Int) = decimal(if (y == 0) 0L else x * 10000L / y) + "%"
class CommandError(message: String) : RuntimeException(message)
data class Config(
    var page: Int = 256, var frames: Int = 4, var tlb: Int = 4, var sets: Int = 1,
    var tick: Int = 0, var tau: Int = 8, var seed: Long = 1,
    var policy: String = "FIFO", var scope: String = "GLOBAL", var asid: String = "OFF"
) {
    fun description() = "SYSTEM page=$page frames=$frames tlb=$tlb sets=$sets policy=$policy scope=$scope asid=$asid tick=$tick tau=$tau seed=$seed"
}
fun settings(tokens: List<String>): Config {
    val c = Config()
    val seen = mutableSetOf<String>()
    for (token in tokens.drop(1)) {
        val (key, value) = token.split('=')
        if (key !in listOf("page", "frames", "tlb", "sets", "policy", "scope", "asid", "tick", "tau", "seed")) throw CommandError("unknown key $key")
        if (!seen.add(key)) throw CommandError("duplicate key $key")
        val valid: Boolean
        when (key) {
            "policy" -> { valid = value in policies; if (valid) c.policy = value }
            "scope" -> { valid = value in listOf("GLOBAL", "LOCAL"); if (valid) c.scope = value }
            "asid" -> { valid = value in listOf("ON", "OFF"); if (valid) c.asid = value }
            else -> {
                val n = value.toLong()
                valid = when (key) {
                    "page" -> n in 16..4096L && (n and (n - 1)) == 0L
                    "frames" -> n in 1..16L
                    "tlb", "sets" -> n in 1..8L
                    "tick" -> n in 0..1000L
                    "tau" -> n in 1..1000L
                    else -> n in 1..2147483646L
                }
                if (valid) when (key) {
                    "page" -> c.page = n.toInt()
                    "frames" -> c.frames = n.toInt()
                    "tlb" -> c.tlb = n.toInt()
                    "sets" -> c.sets = n.toInt()
                    "tick" -> c.tick = n.toInt()
                    "tau" -> c.tau = n.toInt()
                    "seed" -> c.seed = n
                }
            }
        }
        if (!valid) throw CommandError("invalid $key")
    }
    if (c.tlb % c.sets != 0) throw CommandError("invalid sets")
    return c
}
class Page(val pid: Int, val number: Int) {
    var frame = -1; var slot = -1; var r = 0; var m = 0; var load = 0; var last = 0; var uses = 0; var age = 0; var references = 0
    var ro = false; var locked = false; var ever = false
    fun label() = "P$pid:$number"
}
class Process(val pid: Int, count: Int) {
    val pages = List(count) { Page(pid, it) }
    var accesses = 0; var faults = 0; var writebacks = 0; var segfaults = 0; var protfaults = 0; var peak = 0; var hand = 0
    var exited = false
    val history = mutableListOf<Int>()
    fun resident() = pages.count { it.frame >= 0 }
}
data class Access(val pid: Int, val op: String, val address: Int)
data class Log(val kind: String, val pid: Int, val op: String, val a: Int, val b: Int)
class Simulation(val c: Config, val future: List<Access>, val silent: Boolean) {
    val processes = sortedMapOf<Int, Process>()
    val frames = arrayOfNulls<Page>(c.frames)
    val tlb = List(c.sets) { mutableListOf<Page>() }
    val swap = sortedMapOf<Int, Page>()
    var cursor = -1; var time = 0; var faults = 0; var zero = 0; var swapin = 0; var tlbhits = 0; var writebacks = 0; var switches = 0; var previous = -1; var hand = 0
    var random = c.seed
    var fixed = false; var trace = false
    val faultHistory = mutableListOf<Boolean>()
    val log = mutableListOf<Log>()
    fun emit(text: String) { if (!silent) output.add(text) }
    fun process(pid: Int): Process {
        val p = processes[pid] ?: throw CommandError("unknown process $pid")
        if (p.exited) throw CommandError("process $pid exited")
        return p
    }
    fun quota(pid: Int) = c.frames / processes.size + if (processes.keys.indexOf(pid) < c.frames % processes.size) 1 else 0
    fun declare(pid: Int, count: Int) {
        if (fixed) throw CommandError("processes are fixed")
        if (pid in processes) throw CommandError("duplicate process $pid")
        if (count !in 1..256) throw CommandError("invalid page count")
        if (processes.size >= 8 || c.scope == "LOCAL" && processes.size == c.frames) throw CommandError("too many processes")
        processes[pid] = Process(pid, count)
    }
    fun invalidate(page: Page) { tlb.forEach { it.remove(page) } }
    fun write(p: Page) {
        writebacks++; processes.getValue(p.pid).writebacks++; p.m = 0
        if (p.slot < 0) {
            var slot = 0
            while (slot in swap) slot++
            p.slot = slot; swap[slot] = p
        }
    }
    fun nextUse(p: Page): Int {
        for (i in cursor + 1 until future.size) {
            val a = future[i]
            if (a.pid == p.pid && a.address / c.page == p.number) return i
        }
        return Int.MAX_VALUE
    }
    fun choose(original: List<Int>, owner: Process): Int {
        val unlocked = original.filter { !frames[it]!!.locked }
        val candidates = (if (unlocked.isNotEmpty()) unlocked else original).toMutableList()
        if (c.policy == "RANDOM") {
            random = random * 48271L % 2147483647L
            return candidates[(random % candidates.size).toInt()]
        }
        if (c.policy !in listOf("CLOCK", "ECLOCK", "WSCLOCK")) {
            fun rank(f: Int): Pair<Int, Int> {
                val p = frames[f]!!
                return when (c.policy) {
                    "FIFO" -> p.load to 0
                    "LRU" -> p.last to 0
                    "LFU" -> p.uses to p.load
                    "NRU" -> (2 * p.r + p.m) to f
                    "AGING" -> p.age to p.load
                    else -> -nextUse(p) to f
                }
            }
            return candidates.minWith(compareBy<Int> { rank(it).first }.thenBy { rank(it).second })
        }
        val h = if (c.scope == "GLOBAL") hand else owner.hand
        candidates.sortBy { (it - h + c.frames) % c.frames }
        var chosen = -1
        when (c.policy) {
            "CLOCK" -> {
                while (chosen < 0) for (f in candidates) {
                    if (frames[f]!!.r == 0) { chosen = f; break }
                    frames[f]!!.r = 0
                }
            }
            "ECLOCK" -> {
                while (chosen < 0) {
                    for (f in candidates) if (frames[f]!!.r == 0 && frames[f]!!.m == 0) { chosen = f; break }
                    if (chosen >= 0) break
                    for (f in candidates) {
                        if (frames[f]!!.r == 0 && frames[f]!!.m == 1) { chosen = f; break }
                        frames[f]!!.r = 0
                    }
                }
            }
            else -> {
                for (f in candidates) {
                    val p = frames[f]!!
                    if (p.r == 1) { p.r = 0; p.last = time }
                    else if (time - p.last > c.tau) {
                        if (p.m == 0) { chosen = f; break }
                        write(p)
                    }
                }
                if (chosen < 0) chosen = candidates.firstOrNull { frames[it]!!.m == 0 } ?: candidates.first()
            }
        }
        if (c.scope == "GLOBAL") hand = (chosen + 1) % c.frames else owner.hand = (chosen + 1) % c.frames
        return chosen
    }
    fun access(pid: Int, op: String, addr: Int) {
        fixed = true; cursor++
        val owner = process(pid)
        if (addr >= owner.pages.size * c.page) { owner.segfaults++; emit("SEGFAULT P$pid ${hex(addr)}"); return }
        val p = owner.pages[addr / c.page]
        if (op == "W" && p.ro) { owner.protfaults++; emit("PROTFAULT P$pid ${hex(addr)}"); return }
        time++; owner.accesses++
        val switched = previous >= 0 && previous != pid
        if (switched) { switches++; if (c.asid == "OFF") tlb.forEach { it.clear() } }
        previous = pid
        val set = tlb[p.number % c.sets]
        val hit = set.remove(p)
        var fault = false
        var result: String
        if (hit) { tlbhits++; result = "TLBHIT" }
        else if (p.frame >= 0) result = "HIT"
        else {
            fault = true; faults++; owner.faults++
            if (p.slot >= 0) { swapin++; result = "FAULT SWAPIN" }
            else { zero++; result = "FAULT ZERO" }
            var frame = -1
            val mayUseFree = c.scope == "GLOBAL" || owner.resident() < quota(pid)
            if (mayUseFree) frame = frames.indexOfFirst { it == null }
            if (frame < 0) {
                val candidates = frames.indices.filter { frames[it] != null && (c.scope == "GLOBAL" || frames[it]!!.pid == pid) }
                frame = choose(candidates, owner)
                val victim = frames[frame]!!
                result += " evict=${victim.label()}"; invalidate(victim)
                if (victim.m == 1) { write(victim); result += " writeback" }
                victim.frame = -1
            }
            frames[frame] = p; p.frame = frame; p.load = time; p.uses = 0; p.m = 0; p.age = 0
            owner.peak = max(owner.peak, owner.resident())
        }
        if (set.size == c.tlb / c.sets) set.removeAt(0)
        set.add(p)
        p.r = 1; if (op == "W") p.m = 1
        p.last = time; p.uses++; p.ever = true; p.references++
        owner.history.add(p.number); faultHistory.add(fault); log.add(Log("ACCESS", pid, op, addr, 0))
        val interrupt = c.tick > 0 && time % c.tick == 0
        if (interrupt) for (page in frames.filterNotNull()) { page.age = page.age / 2 + 128 * page.r; page.r = 0 }
        if (trace) {
            emit("t=$time P$pid $op ${hex(addr)} page=${p.number} frame=${p.frame} phys=${hex(p.frame * c.page + addr % c.page)} $result" + if (switched) " switch" else "")
            if (interrupt) emit("t=$time tick")
        }
    }
    fun exit(pid: Int) {
        val p = process(pid)
        var count = 0; var slots = 0
        for (page in p.pages) {
            if (page.frame >= 0) { frames[page.frame] = null; page.frame = -1; count++ }
            invalidate(page)
            if (page.slot >= 0) { swap.remove(page.slot); page.slot = -1; slots++ }
        }
        p.exited = true; log.add(Log("EXIT", pid, "", 0, 0))
        emit("EXIT P$pid freed=$count slots=$slots")
    }
    fun attributes(cmd: String, pid: Int, first: Int, last: Int, protection: String) {
        val p = process(pid)
        if (first > last || last >= p.pages.size) throw CommandError("invalid page range")
        for (i in first..last) {
            if (cmd == "PROTECT") p.pages[i].ro = protection == "RO" else p.pages[i].locked = cmd == "LOCK"
        }
        if (cmd != "PROTECT") log.add(Log(cmd, pid, "", first, last))
    }
    fun clean() {
        var count = 0
        for (p in frames.filterNotNull()) if (p.m == 1) { write(p); count++ }
        log.add(Log("CLEAN", 0, "", 0, 0)); emit("CLEAN written=$count")
    }
    fun rerun(policy: String, count: Int): Simulation {
        val config = c.copy(policy = policy, frames = count)
        val references = log.filter { it.kind == "ACCESS" }.map { Access(it.pid, it.op, it.a) }
        val replay = Simulation(config, references, true)
        for (p in processes.values) replay.declare(p.pid, p.pages.size)
        for (e in log) when (e.kind) {
            "ACCESS" -> replay.access(e.pid, e.op, e.a)
            "EXIT" -> replay.exit(e.pid)
            "CLEAN" -> replay.clean()
            else -> replay.attributes(e.kind, e.pid, e.a, e.b, "")
        }
        return replay
    }
    fun summary() {
        emit("SUMMARY policy=${c.policy} scope=${c.scope} time=$time")
        val seg = processes.values.sumOf { it.segfaults }; val prot = processes.values.sumOf { it.protfaults }
        emit("total faults=$faults zero=$zero swapin=$swapin faultrate=${ratio(faults, time)} tlbhits=$tlbhits tlbrate=${ratio(tlbhits, time)} writebacks=$writebacks switches=$switches segfaults=$seg protfaults=$prot")
        for (p in processes.values) emit("P${p.pid} accesses=${p.accesses} faults=${p.faults} writebacks=${p.writebacks} segfaults=${p.segfaults} protfaults=${p.protfaults} resident=${p.resident()} peak=${p.peak}" + (if (c.scope == "LOCAL") " quota=${quota(p.pid)}" else "") + if (p.exited) " exited" else "")
    }
    fun frameDump() {
        emit("FRAMES used=${frames.count { it != null }}/${c.frames}")
        for ((i, p) in frames.withIndex()) {
            if (p == null) emit("$i free")
            else emit("$i ${p.label()} R=${p.r} M=${p.m} load=${p.load} last=${p.last} uses=${p.uses} age=${p.age}" + if (p.locked) " locked" else "")
        }
        if (c.policy in listOf("CLOCK", "ECLOCK", "WSCLOCK")) {
            if (c.scope == "GLOBAL") emit("hand=$hand")
            else emit("hand" + processes.values.joinToString("") { " P${it.pid}=${it.hand}" })
        }
    }
    fun pageTable(pid: Int) {
        val p = process(pid)
        emit("PAGETABLE P$pid pages=${p.pages.size} resident=${p.resident()}")
        for (page in p.pages.filter { it.ever }) {
            val info = if (page.frame >= 0) "frame=${page.frame} R=${page.r} M=${page.m}" else if (page.slot >= 0) "swap=${page.slot}" else "zero"
            emit("${page.number} $info" + (if (page.ro) " RO" else "") + if (page.locked) " locked" else "")
        }
    }
    fun tlbDump() {
        emit("TLB used=${tlb.sumOf { it.size }}/${c.tlb} sets=${c.sets}")
        for ((i, set) in tlb.withIndex()) emit("set $i:" + set.asReversed().joinToString("") { " ${it.label()}->${it.frame}" })
    }
    fun compare() {
        emit("COMPARE accesses=$time frames=${c.frames}")
        val results = mutableMapOf<String, Simulation>()
        for (policy in policies) {
            val r = rerun(policy, c.frames); results[policy] = r
            emit("$policy faults=${r.faults} writebacks=${r.writebacks} tlbhits=${r.tlbhits}")
        }
        val ranking = policies.sortedWith(compareBy<String> { results.getValue(it).faults }.thenBy { results.getValue(it).writebacks })
        emit("ranking " + ranking.joinToString(" "))
    }
    fun execute(t: List<String>) {
        val cmd = t[0]
        fun n(i: Int) = t[i].toInt()
        if (cmd[0].isDigit()) { access(n(0), t[1], address(t[2])); return }
        when (cmd) {
            "PROCESS" -> declare(n(1), n(2))
            "EXIT" -> exit(n(1))
            "PROTECT", "LOCK", "UNLOCK" -> attributes(cmd, n(1), n(2), n(3), t.getOrElse(4) { "" })
            "TRACE" -> trace = t[1] == "ON"
            "SUMMARY" -> summary()
            "FRAMES" -> frameDump()
            "PAGETABLE" -> pageTable(n(1))
            "TLB" -> tlbDump()
            "SWAP" -> {
                emit("SWAP used=${swap.size}")
                for ((slot, page) in swap) emit("$slot ${page.label()}")
            }
            "CLEAN" -> clean()
            "COMPARE" -> compare()
            "CURVE" -> {
                val policy = t[1]; val lo = n(2); val hi = n(3)
                if (policy !in policies) throw CommandError("unknown policy")
                if (lo < 1 || lo > hi || hi > 16 || c.scope == "LOCAL" && lo < processes.size) throw CommandError("invalid frame range")
                emit("CURVE $policy frames=$lo..$hi")
                var prior = Int.MAX_VALUE
                for (f in lo..hi) {
                    val value = rerun(policy, f).faults
                    emit("F=$f faults=$value" + if (value > prior) " ANOMALY" else ""); prior = value
                }
            }
            "EAT" -> {
                val total = t[1].toLong() * time + t[2].toLong() * (2L * time - tlbhits) + t[3].toLong() * (swapin + writebacks)
                emit(if (time == 0) "EAT accesses=0" else "EAT accesses=$time total=$total average=${decimal(total * 100 / time)}")
            }
            "TIMELINE" -> {
                val w = n(1)
                if (w < 1) throw CommandError("invalid window")
                val text = StringBuilder("TIMELINE window=$w")
                for (i in faultHistory.indices step w) text.append(' ').append(faultHistory.subList(i, min(i + w, faultHistory.size)).count { it })
                emit(text.toString())
            }
            "WSET" -> {
                val pid = n(1); val p = process(pid); val w = n(2)
                if (w < 1) throw CommandError("invalid window")
                val pages = p.history.takeLast(w).toSortedSet()
                emit("WSET P$pid window=$w size=${pages.size}" + pages.joinToString("") { " $it" })
            }
            "HOT" -> {
                val pid = n(1); val p = process(pid); val k = n(2)
                if (k < 1) throw CommandError("invalid count")
                val pages = p.pages.filter { it.references > 0 }.sortedWith(compareByDescending<Page> { it.references }.thenBy { it.number }).take(k)
                emit("HOT P$pid" + pages.joinToString("") { " ${it.number}:${it.references}" })
            }
        }
    }
}
fun main() {
    val input = System.`in`.bufferedReader()
    val commands = mutableListOf<List<String>>()
    repeat(input.readLine().toInt()) {
        val t = input.readLine().split(' ')
        when (t[0]) {
            "LOOP" -> {
                val start = address(t[3]); val interval = t[4].toInt(); val length = t[5].toInt(); val repeats = t[6].toInt()
                repeat(repeats) { for (j in 0 until length) commands.add(listOf(t[1], t[2], hex(start + j * interval))) }
            }
            "RAND" -> {
                val lo = address(t[2]); val hi = address(t[3]); val count = t[4].toInt(); val rate = t[6].toInt()
                var x = t[5].toLong()
                repeat(count) {
                    x = x * 48271L % 2147483647L; val addr = lo + (x % (hi - lo)).toInt()
                    x = x * 48271L % 2147483647L
                    commands.add(listOf(t[1], if (x % 100 < rate) "W" else "R", hex(addr)))
                }
            }
            else -> commands.add(t)
        }
    }
    var simulation: Simulation? = null
    for ((i, t) in commands.withIndex()) {
        try {
            if (t[0] == "SYSTEM") {
                simulation = null
                val c = settings(t)
                val future = mutableListOf<Access>()
                for (j in i + 1 until commands.size) {
                    val entry = commands[j]
                    if (entry[0] == "SYSTEM") break
                    if (entry[0][0].isDigit()) future.add(Access(entry[0].toInt(), entry[1], address(entry[2])))
                }
                simulation = Simulation(c, future, false); output.add(c.description())
            } else if (simulation == null) output.add("ERROR no system")
            else simulation.execute(t)
        } catch (e: CommandError) { output.add("ERROR ${e.message}") }
    }
    if (output.isNotEmpty()) print(output.joinToString("\n", postfix = "\n"))
}
