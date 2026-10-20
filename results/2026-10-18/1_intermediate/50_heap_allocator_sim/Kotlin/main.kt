import kotlin.math.max
import kotlin.math.min

val modes = listOf("FIRST", "NEXT", "BEST", "WORST", "SEGFIT", "BUDDY")
val counterNames = listOf("allocs", "frees", "reallocs", "moves", "failures", "collected")
fun power(n: Int) = n > 0 && (n and (n - 1)) == 0
fun sizeClass(n: Int) = 31 - Integer.numberOfLeadingZeros(n)
fun random(x: Long) = x * 48271L % 2147483647L
class CommandError(message: String) : RuntimeException(message)
class Block(var start: Int, var size: Int) {
    var owner = ""
    var requested = 0
    var stamp = 0
    var used = false
    var contents = IntArray(0)
    val end get() = start + size
    val payload get() = start + 8
    val area get() = "$start+$size"
}
class Heap(val mode: String, var size: Int) {
    var rover = 0
    var age = 0
    var blocks = mutableListOf(register(Block(0, size)))
    val buddy get() = mode == "BUDDY"
    fun register(b: Block): Block { b.stamp = ++age; return b }
    fun required(n: Int): Int {
        val s = (n + 7) / 8 * 8 + 8
        if (!buddy) return s
        var p = 32
        while (p < s) p *= 2
        return p
    }
    fun used() = blocks.filter { it.used }
    fun free() = blocks.filter { !it.used }
    fun total() = used().sumOf { it.size }
    fun frag(): Int {
        val f = free().sumOf { it.size }
        val l = free().maxOfOrNull { it.size } ?: 0
        return if (f == 0) 0 else (f - l) * 100 / f
    }
    fun locate(p: Int) = blocks.indexOfFirst { p < it.end }
    fun allocate(s: Int, al: Int): Block? {
        val ri = locate(rover)
        var chosen = -1
        var placement = 0
        var bestA = Int.MAX_VALUE
        var bestB = Int.MAX_VALUE
        for ((i, b) in blocks.withIndex()) {
            if (b.used) continue
            var p = (b.start + 8 + al - 1) / al * al - 8
            if (p > b.start && p - b.start < 16) p += al
            if (p + s > b.end) continue
            val a = when (mode) {
                "NEXT" -> (i - ri + blocks.size) % blocks.size
                "BEST", "BUDDY" -> b.size
                "WORST" -> -b.size
                "SEGFIT" -> sizeClass(b.size)
                else -> b.start
            }
            val c = when (mode) {
                "BEST", "BUDDY", "WORST" -> b.start
                "SEGFIT" -> -b.stamp
                else -> 0
            }
            if (a < bestA || a == bestA && c < bestB) {
                chosen = i; placement = p; bestA = a; bestB = c
            }
        }
        if (chosen < 0) return null
        val b: Block
        if (buddy) {
            b = blocks[chosen]
            halve(chosen, s)
        } else {
            val old = blocks.removeAt(chosen)
            val parts = mutableListOf<Block>()
            if (placement > old.start) parts.add(register(Block(old.start, placement - old.start)))
            b = Block(placement, old.end - placement)
            parts.add(b)
            if (b.size - s >= 16) {
                parts.add(register(Block(placement + s, b.size - s)))
                b.size = s
            }
            blocks.addAll(chosen, parts)
        }
        b.used = true
        if (mode == "NEXT") rover = if (b.end == size) 0 else b.end
        return b
    }
    fun halve(i: Int, s: Int) {
        val b = blocks[i]
        while (b.size > s) {
            b.size /= 2
            blocks.add(i + 1, register(Block(b.end, b.size)))
        }
    }
    fun merge(i: Int) { blocks[i].size += blocks.removeAt(i + 1).size }
    fun coalesce(index: Int): Pair<Block, Int> {
        var i = index
        var merges = 0
        if (buddy) {
            while (blocks[i].size < size) {
                val b = blocks[i]
                val j = if (b.start % (2 * b.size) == 0) i + 1 else i - 1
                if (j !in blocks.indices || blocks[j].used || blocks[j].size != b.size) break
                i = min(i, j)
                merge(i); merges++
            }
        } else {
            if (i + 1 < blocks.size && !blocks[i + 1].used) { merge(i); merges++ }
            if (i > 0 && !blocks[i - 1].used) { i--; merge(i); merges++ }
        }
        return register(blocks[i]) to merges
    }
    fun release(b: Block): Pair<Block, Int> {
        b.used = false; b.owner = ""; b.requested = 0; b.contents = IntArray(0)
        return coalesce(blocks.indexOf(b))
    }
    fun resize(b: Block, s: Int): String? {
        val i = blocks.indexOf(b)
        if (s <= b.size) {
            if (buddy) {
                if (s == b.size) return "kept"
                halve(i, s)
            } else {
                if (b.size - s < 16) return "kept"
                blocks.add(i + 1, Block(b.start + s, b.size - s))
                b.size = s
                coalesce(i + 1)
            }
            return "shrunk"
        }
        if (buddy) {
            var t = b.size
            var j = i
            while (t < s) {
                j++
                if (b.start % (2 * t) != 0 || j >= blocks.size || blocks[j].used || blocks[j].size != t) return null
                t *= 2
            }
            blocks.subList(i + 1, j + 1).clear()
            b.size = s
        } else {
            if (i + 1 >= blocks.size || blocks[i + 1].used || b.size + blocks[i + 1].size < s) return null
            val total = b.size + blocks.removeAt(i + 1).size
            b.size = if (total - s >= 16) s else total
            if (total - s >= 16) blocks.add(i + 1, register(Block(b.end, total - s)))
        }
        return "grown"
    }
    fun trim(): Int {
        val old = size
        if (buddy) {
            while (!blocks.last().used && blocks.last().size * 2 == size) {
                blocks.removeAt(blocks.lastIndex); size /= 2
            }
        } else if (blocks.size > 1 && !blocks.last().used) size = blocks.removeAt(blocks.lastIndex).start
        if (rover >= size) rover = 0
        return old - size
    }
}
fun experiment(mode: String, s: Int, seed: Long, ops: Int, maxreq: Int): String {
    val h = Heap(mode, s)
    val live = mutableListOf<Block>()
    var x = seed
    var ok = 0; var fail = 0; var peak = 0
    repeat(ops) {
        x = random(x)
        val alloc = live.isEmpty() || x % 3 != 0L
        x = random(x)
        if (alloc) {
            val b = h.allocate(h.required(1 + (x % maxreq).toInt()), 8)
            if (b == null) fail++ else { ok++; live.add(b) }
        } else h.release(live.removeAt((x % live.size).toInt()))
        peak = max(peak, h.total())
    }
    return "BENCH $mode ok=$ok fail=$fail peak=$peak used=${h.total()} frag=${h.frag()} blocks=${h.blocks.size}"
}
class Allocator {
    var heap: Heap? = null
    val live = mutableMapOf<String, Block>()
    val freed = mutableSetOf<String>()
    val roots = mutableSetOf<String>()
    val links = mutableMapOf<String, MutableSet<String>>()
    val history = mutableMapOf<String, MutableList<String>>()
    var counters = IntArray(6)
    var peak = 0
    val out = mutableListOf<String>()
    fun fail(s: String): Nothing = throw CommandError(s)
    fun record(id: String, s: String) { out.add(s); history.getOrPut(id) { mutableListOf() }.add(s) }
    fun block(id: String): Block = live[id] ?: fail(if (id in freed) "USE AFTER FREE $id" else "UNKNOWN ID $id")
    fun range(id: String, off: Int, len: Int): Block {
        val b = block(id)
        if (off + len > b.requested) fail("OUT OF BOUNDS $id")
        return b
    }
    fun oom(id: String): Nothing { counters[4]++; fail("OUT OF MEMORY $id") }
    fun allocate(kind: String, id: String, n: Int, al: Int = 8, fill: Int = -1) {
        if (n == 0) fail("BAD SIZE")
        if (id in live) fail("DUPLICATE ID $id")
        val h = heap!!
        val b = h.allocate(h.required(n), al) ?: oom(id)
        b.owner = id; b.requested = n; b.contents = IntArray(n) { fill }
        live[id] = b; freed.remove(id); counters[0]++
        record(id, "$kind $id addr=${b.payload} block=${b.size}")
    }
    fun release(id: String): String {
        val b = live.remove(id)!!
        val size = b.size
        freed.add(id); roots.remove(id); links.remove(id)
        links.values.forEach { it.remove(id) }
        val (f, merges) = heap!!.release(b)
        return "block=$size merges=$merges free=${f.area}"
    }
    fun free(id: String) {
        if (id in freed) fail("DOUBLE FREE $id")
        if (id !in live) fail("UNKNOWN ID $id")
        val detail = release(id)
        counters[1]++; record(id, "FREE $id $detail")
    }
    fun realloc(id: String, n: Int) {
        if (n == 0) { free(id); return }
        if (id in freed) fail("USE AFTER FREE $id")
        var b = live[id]
        if (b == null) { allocate("MALLOC", id, n); return }
        val original = b
        val contents = IntArray(n) { if (it < original.requested) original.contents[it] else -1 }
        val old = b.payload
        val h = heap!!
        var kind = h.resize(b, h.required(n))
        if (kind == null) {
            val moved = h.allocate(h.required(n), 8) ?: oom(id)
            moved.owner = id; live[id] = moved; h.release(b); b = moved
            counters[3]++; kind = "moved from=$old"
        }
        b.requested = n; b.contents = contents; counters[2]++
        record(id, "REALLOC $id addr=${b.payload} block=${b.size} $kind")
    }
    fun reachable(): Set<String> {
        val seen = roots.toMutableSet()
        val stack = roots.toMutableList()
        while (stack.isNotEmpty()) {
            val id = stack.removeAt(stack.lastIndex)
            for (dst in links[id].orEmpty()) if (seen.add(dst)) stack.add(dst)
        }
        return seen
    }
    fun tree(a: Int, s: Int, depth: Int) {
        val b = heap!!.blocks.find { it.start == a && it.size == s }
        val prefix = " ".repeat(depth * 2) + "$a+$s"
        if (b != null) out.add(prefix + if (b.used) " USED ${b.owner}" else " FREE")
        else {
            out.add("$prefix split")
            tree(a, s / 2, depth + 1); tree(a + s / 2, s / 2, depth + 1)
        }
    }
    fun execute(line: String) {
        val t = line.split(' ')
        val cmd = t[0]
        val a = t.drop(1)
        fun n(i: Int) = a[i].toInt()
        try {
            if (heap == null && cmd != "HEAP" && cmd != "BENCH") fail("NO HEAP")
            val h = heap
            when (cmd) {
                "HEAP" -> {
                    val s = n(0)
                    if (s !in 32..65536 || s % 8 != 0 || a[1] == "BUDDY" && !power(s)) fail("BAD HEAP SIZE")
                    heap = Heap(a[1], s)
                    live.clear(); freed.clear(); roots.clear(); links.clear(); history.clear(); counters = IntArray(6); peak = 0
                    out.add("HEAP size=$s mode=${a[1]}")
                }
                "BENCH" -> {
                    val s = n(0)
                    if (s !in 32..65536 || !power(s)) fail("BAD HEAP SIZE")
                    out.add("BENCH heap=$s seed=${a[1]} ops=${a[2]} maxreq=${a[3]}")
                    for (m in modes) out.add(experiment(m, s, a[1].toLong(), n(2), n(3)))
                }
                "MALLOC" -> allocate(cmd, a[0], n(1))
                "CALLOC" -> allocate(cmd, a[0], n(1) * n(2), 8, 0)
                "MEMALIGN" -> {
                    if (h!!.buddy) fail("UNSUPPORTED IN BUDDY MODE")
                    if (n(1) !in 8..4096 || !power(n(1))) fail("BAD ALIGNMENT")
                    allocate(cmd, a[0], n(2), n(1))
                }
                "REALLOC" -> realloc(a[0], n(1))
                "FREE" -> free(a[0])
                "FILL" -> {
                    val b = range(a[0], n(1), n(2))
                    b.contents.fill(n(3), n(1), n(1) + n(2))
                    out.add("FILL ${a[0]} ${a[1]}+${a[2]} = ${a[3]}")
                }
                "COPY" -> {
                    val dst = range(a[0], n(1), n(4)); val src = range(a[2], n(3), n(4))
                    src.contents.copyOfRange(n(3), n(3) + n(4)).copyInto(dst.contents, n(1))
                    out.add("COPY ${a[0]} ${a[1]}+${a[4]} from ${a[2]} ${a[3]}")
                }
                "READ" -> {
                    val b = range(a[0], n(1), n(2))
                    val values = b.contents.slice(n(1) until n(1) + n(2)).joinToString(" ") { if (it < 0) "?" else "$it" }
                    out.add("READ ${a[0]} ${a[1]}+${a[2]} = $values")
                }
                "ROOT", "UNROOT" -> {
                    block(a[0])
                    if (cmd == "ROOT") roots.add(a[0]) else if (!roots.remove(a[0])) fail("NOT ROOT ${a[0]}")
                    out.add("$cmd ${a[0]}")
                }
                "LINK", "UNLINK" -> {
                    block(a[0]); block(a[1])
                    if (cmd == "LINK") links.getOrPut(a[0]) { mutableSetOf() }.add(a[1])
                    else if (links[a[0]]?.remove(a[1]) != true) fail("NO LINK ${a[0]} ${a[1]}")
                    out.add("$cmd ${a[0]} ${a[1]}")
                }
                "GC" -> {
                    val seen = reachable()
                    val garbage = h!!.used().filter { it.owner !in seen }
                    out.add("GC collected=${garbage.size} bytes=${garbage.sumOf { it.size }}")
                    for (b in garbage) { val id = b.owner; record(id, "COLLECT $id ${release(id)}") }
                    counters[5] += garbage.size
                }
                "SBRK" -> {
                    val k = n(0)
                    if (h!!.buddy) { if (k != h.size || h.size * 2 > 65536) fail("BAD SBRK SIZE") }
                    else if (k < 16 || k % 8 != 0 || h.size + k > 65536) fail("BAD SBRK SIZE")
                    h.blocks.add(Block(h.size, k)); h.size += k
                    val f = h.coalesce(h.blocks.lastIndex).first
                    out.add("SBRK heap=${h.size} free=${f.area}")
                }
                "TRIM" -> { val released = h!!.trim(); out.add("TRIM heap=${h.size} released=$released") }
                "COMPACT" -> {
                    if (h!!.buddy) fail("UNSUPPORTED IN BUDDY MODE")
                    val used = h.used().toMutableList()
                    val moved = mutableListOf<Pair<Block, Int>>()
                    var pos = 0
                    for (b in used) {
                        if (b.start != pos) { moved.add(b to b.payload); b.start = pos }
                        pos += b.size
                    }
                    if (pos < h.size) used.add(h.register(Block(pos, h.size - pos)))
                    h.blocks = used; h.rover = 0; counters[3] += moved.size
                    out.add("COMPACT moved=${moved.size} free=" + if (pos < h.size) "$pos+${h.size - pos}" else "none")
                    for ((b, old) in moved) record(b.owner, "MOVE ${b.owner} $old -> ${b.payload}")
                }
                "WHO" -> {
                    val p = n(0)
                    val detail = if (p >= h!!.size) "outside" else {
                        val b = h.blocks[h.locate(p)]
                        if (!b.used) "free ${b.area}"
                        else if (p < b.payload) "header ${b.owner}"
                        else (if (p - b.payload < b.requested) "data" else "slack") + " ${b.owner}+${p - b.payload}"
                    }
                    out.add("WHO $p $detail")
                }
                "DUMP" -> {
                    out.add("DUMP mode=${h!!.mode} heap=${h.size} blocks=${h.blocks.size}" + if (h.mode == "NEXT") " rover=${h.rover}" else "")
                    for (b in h.blocks) out.add("${b.start} ${b.size} " + if (b.used) "USED ${b.owner} req=${b.requested}" else "FREE")
                }
                "MAP" -> {
                    out.add("MAP heap=${h!!.size}")
                    val units = buildString {
                        for (b in h.blocks) {
                            append(if (b.used) 'H' else 'F')
                            repeat(b.size / 8 - 1) { append(if (!b.used) '.' else if (it * 8 < b.requested) '#' else '-') }
                        }
                    }
                    for (i in units.indices step 64) out.add((i * 8).toString().padStart(5, '0') + " " + units.substring(i, min(i + 64, units.length)))
                }
                "FREELIST" -> {
                    val free = h!!.free().let { if (h.mode == "SEGFIT") it.sortedByDescending { b -> b.stamp } else it }
                    out.add("FREELIST count=${free.size}")
                    for ((k, group) in free.groupBy { sizeClass(it.size) }.toSortedMap()) out.add("${1 shl k}-${(1 shl (k + 1)) - 1}: " + group.joinToString(" ") { it.area })
                }
                "TREE" -> {
                    if (!h!!.buddy) fail("REQUIRES BUDDY MODE")
                    out.add("TREE heap=${h.size}"); tree(0, h.size, 0)
                }
                "STATS" -> {
                    val used = h!!.used(); val free = h.free()
                    out.add("STATS used=${h.total()} used_blocks=${used.size} free=${free.sumOf { it.size }} free_blocks=${free.size} largest=${free.maxOfOrNull { it.size } ?: 0} frag=${h.frag()} requested=${used.sumOf { it.requested }} peak=$peak")
                    out.add("OPS " + counterNames.indices.joinToString(" ") { "${counterNames[it]}=${counters[it]}" })
                }
                "LEAKS" -> {
                    val seen = reachable()
                    out.add("LEAKS count=${live.size} requested=${live.values.sumOf { it.requested }} lost=${live.keys.count { it !in seen }}")
                    for ((id, b) in live.toSortedMap()) out.add("LEAK $id addr=${b.payload} block=${b.size} req=${b.requested} " + if (id in seen) "reachable" else "lost")
                }
                "HISTORY" -> {
                    val events = history[a[0]].orEmpty()
                    out.add("HISTORY ${a[0]} events=${events.size}"); out.addAll(events)
                }
            }
        } catch (e: CommandError) { out.add("ERROR ${e.message}") }
        heap?.let { peak = max(peak, it.total()) }
    }
}
fun main() {
    val input = System.`in`.bufferedReader()
    val allocator = Allocator()
    repeat(input.readLine().toInt()) { allocator.execute(input.readLine()) }
    print(allocator.out.joinToString("\n", postfix = "\n"))
}
