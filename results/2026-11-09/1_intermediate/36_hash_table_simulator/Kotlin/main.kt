enum class Mode { CHAIN, LINEAR, QUADRATIC, DOUBLE, ROBINHOOD, CUCKOO }
enum class Reporting {
    SILENT, REHASHES, FULL, TRACE;
    val trace get() = this == TRACE
    val details get() = this == FULL || this == TRACE
}
class CommandError(reason: String) : RuntimeException(reason)
fun fail(reason: String): Nothing = throw CommandError(reason)

data class Item(val key: String, val value: Long) {
    override fun toString() = "$key=$value"
}
data class Slot(val item: Item? = null, val deleted: Boolean = false) {
    val empty get() = item == null && !deleted
    val content get() = item?.key ?: if (deleted) "D" else "-"
    companion object {
        val EMPTY = Slot()
        val TOMB = Slot(deleted = true)
    }
}
class Counters {
    var probes = 0L
    var rehashes = 0L
    var inserts = 0L
    var updates = 0L
    var hits = 0L
    var misses = 0L
    var deletes = 0L
    var absent = 0L
}
class Search {
    var item: Item? = null
    var position = -1
    var chainIndex = -1
    var available: Int? = null
    var probes = 0
    val path = mutableListOf<String>()
}
class Placement {
    var position: Int? = null
    var pending: Item? = null
    var reused = false
    var movements = 0
    val moves = mutableListOf<String>()
}
data class Removal(val shifted: Int, val moves: List<String>)
data class Mutation(val changed: Boolean, val lines: List<String>)
data class Cost(val key: String, val position: Int, val probes: Int)
data class Metrics(val longest: Int, val average: String)

fun parseMode(word: String) = Mode.entries.firstOrNull { it.name == word } ?: fail("BAD MODE $word")
fun hash(key: String, base: Int, modulus: Int) = key.fold(0) { value, ch -> (value * base + ch.code) % modulus }
fun prime(value: Int): Int {
    var candidate = maxOf(value, 2)
    while (true) {
        var divisor = 2
        while (divisor <= candidate / divisor && candidate % divisor != 0) divisor++
        if (divisor > candidate / divisor) return candidate
        candidate++
    }
}
fun decimal(numerator: Long, denominator: Long): String {
    val value = if (denominator == 0L) 0L else 100 * numerator / denominator
    return "${value / 100}.${(value % 100).toString().padStart(2, '0')}"
}
fun gauge(value: Int) = if (value < 10) ('0'.code + value).toChar() else '+'
fun histogram(values: List<Int>) = values.groupingBy { it }.eachCount().toSortedMap().map { (value, count) ->
    "$value $count ${"#".repeat(minOf(count, 50))}${if (count > 50) "+" else ""}"
}
fun generate(count: Int, length: Int, seed: Long): List<String> {
    var state = seed
    return List(count) {
        buildString {
            repeat(length) {
                state = 48271 * state % 2147483647
                append(('a'.code + state % 26).toInt().toChar())
            }
        }
    }
}
fun capacity(value: Long): Int {
    if (value !in 2L..10000L) fail("BAD CAPACITY")
    return value.toInt()
}
fun checkGeneration(count: Long, length: Long, seed: Long) {
    if (count !in 1L..500L || length !in 1L..10L || seed !in 1L..2147483646L) fail("BAD ARGUMENT")
}

class HashTable(var mode: Mode, var cap: Int) {
    var size = 0
    var tomb = 0
    val counters = Counters()
    var buckets: List<MutableList<Item>> = if (mode == Mode.CHAIN) List(cap) { mutableListOf() } else emptyList()
    var slots = Array(if (mode == Mode.CHAIN) 0 else slotCount) { Slot.EMPTY }
    val slotCount get() = cap * if (mode == Mode.CUCKOO) 2 else 1

    fun position(index: Int) = if (mode == Mode.CUCKOO) "T${index / cap + 1}.${index % cap}" else index.toString()
    fun distance(item: Item, index: Int) = (index + cap - hash(item.key, 31, cap)) % cap
    fun items(): List<Item> = if (mode == Mode.CHAIN) buckets.flatten() else slots.mapNotNull { it.item }
    fun search(key: String, trace: Boolean = false): Search {
        val result = Search()
        fun observe(index: Int, content: String) {
            result.probes++
            if (trace) result.path += "${position(index)}:$content"
        }
        val home = hash(key, 31, cap)
        if (mode == Mode.CHAIN) {
            for ((index, item) in buckets[home].withIndex()) {
                observe(home, item.key)
                if (item.key == key) {
                    result.item = item
                    result.position = home
                    result.chainIndex = index
                    break
                }
            }
            return result
        }
        val step = if (mode == Mode.DOUBLE) 1 + hash(key, 37, cap - 1) else 1
        for (i in 0 until if (mode == Mode.CUCKOO) 2 else cap) {
            val index = if (mode == Mode.CUCKOO) {
                if (i == 0) home else cap + hash(key, 37, cap)
            } else ((home + if (mode == Mode.QUADRATIC) i.toLong() * i else i.toLong() * step) % cap).toInt()
            val slot = slots[index]
            observe(index, slot.content)
            if (slot.item?.key == key) {
                result.item = slot.item
                result.position = index
                break
            }
            if (mode == Mode.CUCKOO) continue
            if (slot.empty) { result.available = result.available ?: index; break }
            if (slot.deleted) { result.available = result.available ?: index; continue }
            if (mode == Mode.ROBINHOOD && distance(slot.item!!, index) < i) break
        }
        return result
    }
    fun place(item: Item, initial: Search? = null, trace: Boolean = false): Placement {
        val result = Placement()
        val home = hash(item.key, 31, cap)
        if (mode == Mode.CHAIN) {
            buckets[home].add(item)
            result.position = home
            return result
        }
        if (mode == Mode.LINEAR || mode == Mode.QUADRATIC || mode == Mode.DOUBLE) {
            val index = (initial ?: search(item.key)).available
            if (index == null) { result.pending = item; return result }
            result.reused = slots[index].deleted
            if (result.reused) tomb--
            slots[index] = Slot(item)
            result.position = index
            return result
        }
        var carried = item
        if (mode == Mode.ROBINHOOD) {
            var index = home
            var traveled = 0
            var from: Int? = null
            while (true) {
                val resident = slots[index].item
                if (resident == null) {
                    if (trace && from != null) result.moves += "SHIFT ${carried.key} $from -> $index"
                    slots[index] = Slot(carried)
                    result.position = result.position ?: index
                    return result
                }
                val residentDistance = distance(resident, index)
                if (residentDistance < traveled) {
                    if (trace && from != null) result.moves += "SHIFT ${carried.key} $from -> $index"
                    slots[index] = Slot(carried)
                    carried = resident
                    result.position = result.position ?: index
                    from = index
                    traveled = residentDistance
                    result.movements++
                }
                index = (index + 1) % cap
                traveled++
            }
        }
        var part = 0
        while (true) {
            val index = part * cap + hash(carried.key, if (part == 0) 31 else 37, cap)
            val resident = slots[index].item
            if (resident == null) {
                slots[index] = Slot(carried)
                result.position = search(item.key).position
                return result
            }
            if (result.movements == cap) { result.pending = carried; return result }
            if (trace) result.moves += "KICK ${resident.key} ${position(index)}"
            slots[index] = Slot(carried)
            carried = resident
            result.movements++
            part = 1 - part
        }
    }
    fun remove(found: Search, trace: Boolean): Removal {
        var shifted = 0
        val moves = mutableListOf<String>()
        if (mode == Mode.CHAIN) buckets[found.position].removeAt(found.chainIndex)
        else if (mode == Mode.LINEAR || mode == Mode.QUADRATIC || mode == Mode.DOUBLE) {
            slots[found.position] = Slot.TOMB
            tomb++
        } else {
            slots[found.position] = Slot.EMPTY
            if (mode == Mode.ROBINHOOD) {
                var source = (found.position + 1) % cap
                while (true) {
                    val item = slots[source].item ?: break
                    if (distance(item, source) == 0) break
                    val destination = (source + cap - 1) % cap
                    if (trace) moves += "SHIFT ${item.key} $source -> $destination"
                    slots[destination] = slots[source]
                    slots[source] = Slot.EMPTY
                    shifted++
                    source = (source + 1) % cap
                }
            }
        }
        size--
        return Removal(shifted, moves)
    }
    companion object {
        fun rebuild(mode: Mode, cap: Int, items: List<Item>): HashTable? {
            val trial = HashTable(mode, cap)
            for (item in items) {
                if (trial.place(item).position == null) return null
                trial.size++
            }
            return trial
        }
    }
    fun adopt(replacement: HashTable) {
        mode = replacement.mode
        cap = replacement.cap
        size = replacement.size
        tomb = replacement.tomb
        buckets = replacement.buckets
        slots = replacement.slots
    }
    fun automatic(capacity: Int, reason: String, pending: Item? = null): String {
        var target = capacity
        val old = cap
        val listed = items().toMutableList()
        if (pending != null) listed += pending
        while (true) {
            val trial = rebuild(mode, target, listed)
            if (trial != null) {
                adopt(trial)
                counters.rehashes++
                return "REHASH $reason $old -> $cap"
            }
            target = prime(2 * target)
        }
    }
    fun loadCheck(maximum: Int): String? {
        val threshold = maximum.toLong() * slotCount
        if ((size + tomb) * 100L <= threshold) return null
        val grow = size * 200L > threshold
        return automatic(if (grow) prime(2 * cap) else cap, if (grow) "load" else "tomb")
    }
    fun shrinkCheck(minimum: Int, maximum: Int): String? {
        val target = prime(cap / 2)
        val count = target * if (mode == Mode.CUCKOO) 2 else 1
        if (size * 100L >= minimum.toLong() * slotCount || target >= cap || size * 100L > maximum.toLong() * count) return null
        val trial = rebuild(mode, target, items()) ?: return null
        val old = cap
        adopt(trial)
        counters.rehashes++
        return "REHASH shrink $old -> $cap"
    }
    fun pathLine(found: Search) = "PATH " + if (found.path.isEmpty()) "none" else found.path.joinToString(" ")
    fun put(item: Item, add: Boolean, maximum: Int, reporting: Reporting): Mutation {
        val found = search(item.key, reporting.trace)
        counters.probes += found.probes
        val command = if (add) "ADD" else "PUT"
        val lines = mutableListOf<String>()
        val old = found.item
        if (old != null) {
            val stored = Item(item.key, if (add) old.value + item.value else item.value)
            if (mode == Mode.CHAIN) buckets[found.position][found.chainIndex] = stored else slots[found.position] = Slot(stored)
            counters.updates++
            if (reporting.details) lines += "$command $stored UPDATED old=${old.value} at=${position(found.position)} probes=${found.probes}"
            if (reporting.trace) lines += pathLine(found)
            return Mutation(false, lines)
        }
        val placed = place(item, found, reporting.trace)
        counters.inserts++
        val index = placed.position
        if (reporting.details) {
            var row = "$command $item NEW"
            if (index != null) {
                row += " at=${position(index)} probes=${found.probes}"
                if (placed.reused) row += " reused"
                if (mode == Mode.ROBINHOOD) row += " shifted=${placed.movements}"
                if (mode == Mode.CUCKOO) row += " kicks=${placed.movements}"
            } else {
                row += " probes=${found.probes}"
                row += if (mode == Mode.QUADRATIC) " full" else " kicks=${placed.movements} failed"
            }
            lines += row
        }
        if (reporting.trace) { lines += pathLine(found); lines += placed.moves }
        if (index != null) size++ else {
            val rehash = automatic(prime(2 * cap), if (mode == Mode.QUADRATIC) "full" else "kicks", placed.pending)
            if (reporting != Reporting.SILENT) lines += rehash
        }
        loadCheck(maximum)?.let { if (reporting != Reporting.SILENT) lines += it }
        return Mutation(true, lines)
    }
    fun delete(key: String, minimum: Int, maximum: Int, reporting: Reporting): Mutation {
        val found = search(key, reporting.trace)
        counters.probes += found.probes
        val lines = mutableListOf<String>()
        if (found.item == null) {
            counters.absent++
            if (reporting.details) lines += "DEL $key NOT FOUND probes=${found.probes}"
            if (reporting.trace) lines += pathLine(found)
            return Mutation(false, lines)
        }
        val removed = remove(found, reporting.trace)
        counters.deletes++
        if (reporting.details) {
            var row = "DEL $key OK at=${position(found.position)} probes=${found.probes}"
            if (mode == Mode.ROBINHOOD) row += " shifted=${removed.shifted}"
            lines += row
        }
        if (reporting.trace) { lines += pathLine(found); lines += removed.moves }
        shrinkCheck(minimum, maximum)?.let { if (reporting != Reporting.SILENT) lines += it }
        return Mutation(true, lines)
    }
    fun get(key: String, trace: Boolean): List<String> {
        val found = search(key, trace)
        counters.probes += found.probes
        val item = found.item
        val row = if (item != null) {
            counters.hits++
            "GET $item at=${position(found.position)} probes=${found.probes}"
        } else {
            counters.misses++
            "GET $key NOT FOUND probes=${found.probes}"
        }
        return if (trace) listOf(row, pathLine(found)) else listOf(row)
    }
    fun costs(): List<Cost> = buildList {
        if (mode == Mode.CHAIN) {
            for ((index, bucket) in buckets.withIndex()) {
                for ((place, item) in bucket.withIndex()) add(Cost(item.key, index, place + 1))
            }
        } else {
            for ((index, slot) in slots.withIndex()) {
                val item = slot.item ?: continue
                val cost = when (mode) {
                    Mode.CUCKOO -> index / cap + 1
                    Mode.LINEAR, Mode.ROBINHOOD -> distance(item, index) + 1
                    else -> search(item.key).probes
                }
                add(Cost(item.key, index, cost))
            }
        }
    }
    fun metrics(): Metrics {
        val values = costs()
        return Metrics(values.maxOfOrNull { it.probes } ?: 0, decimal(values.sumOf { it.probes.toLong() }, size.toLong()))
    }
    fun dump(): List<String> = buildList {
        add("DUMP $mode cap=$cap size=${this@HashTable.size} tomb=$tomb")
        if (mode == Mode.CHAIN) {
            for ((index, bucket) in buckets.withIndex()) add("$index " + if (bucket.isEmpty()) "-" else bucket.joinToString(" "))
        } else {
            for ((index, slot) in slots.withIndex()) {
                val prefix = if (mode == Mode.CUCKOO) "T${index / cap + 1} ${index % cap}" else index.toString()
                var content = slot.item?.toString() ?: slot.content
                if (mode == Mode.ROBINHOOD && slot.item != null) content += " d=${distance(slot.item, index)}"
                add("$prefix $content")
            }
        }
    }
    fun map(): List<String> = buildList {
        add("MAP $mode cap=$cap")
        val costBySlot = IntArray(slotCount)
        if (mode != Mode.CHAIN) for (cost in costs()) costBySlot[cost.position] = cost.probes
        for (part in 0 until if (mode == Mode.CUCKOO) 2 else 1) {
            for (start in 0 until cap step 40) {
                val text = buildString {
                    for (index in start until minOf(start + 40, cap)) {
                        append(if (mode == Mode.CHAIN) {
                            if (buckets[index].isEmpty()) '.' else gauge(buckets[index].size)
                        } else {
                            val position = part * cap + index
                            val slot = slots[position]
                            when {
                                slot.empty -> '.'
                                slot.deleted -> 'D'
                                mode == Mode.CUCKOO -> '#'
                                else -> gauge(costBySlot[position] - 1)
                            }
                        })
                    }
                }
                val prefix = if (mode == Mode.CUCKOO) "T${part + 1} " else ""
                add("$prefix${start.toString().padStart(5, '0')} $text")
            }
        }
    }
    fun statistics(): List<String> {
        val values = metrics()
        val c = counters
        return listOf("STATS $mode size=$size cap=$cap slots=$slotCount tomb=$tomb load=${decimal(100L * size, slotCount.toLong())}% " +
            "longest=${values.longest} avg=${values.average} probes=${c.probes} rehashes=${c.rehashes}",
            "OPS inserts=${c.inserts} updates=${c.updates} hits=${c.hits} misses=${c.misses} deletes=${c.deletes} absent=${c.absent}")
    }
    fun scan(cursor: Int, limit: Int): String {
        var next = cursor
        val keys = mutableListOf<String>()
        while (next < slotCount && keys.size < limit) {
            if (mode == Mode.CHAIN) keys += buckets[next].map { it.key }
            else slots[next].item?.let { keys += it.key }
            next++
        }
        if (next == slotCount) next = 0
        return "SCAN next=$next" + if (keys.isEmpty()) "" else " " + keys.joinToString(" ")
    }
    fun clusters(): List<String> {
        val runs = mutableListOf<Int>()
        if (mode == Mode.CHAIN) runs += buckets.filter { it.isNotEmpty() }.map { it.size }
        else {
            for (base in slots.indices step cap) {
                val empty = (0 until cap).firstOrNull { slots[base + it].empty }
                if (empty == null) { runs += cap; continue }
                var length = 0
                for (offset in 1..cap) {
                    if (!slots[base + (empty + offset) % cap].empty) length++
                    else if (length > 0) { runs += length; length = 0 }
                }
            }
        }
        return listOf("CLUSTERS runs=${runs.size} longest=${runs.maxOrNull() ?: 0}") + histogram(runs)
    }
    fun distribution(): List<String> {
        val values = costs().map { it.probes }
        return listOf("DIST keys=$size longest=${values.maxOrNull() ?: 0}") + histogram(values)
    }
}

fun compare(table: HashTable, cap: Int, maximum: Int): List<String> = buildList {
    val items = table.items().sortedBy { it.key }
    add("COMPARE keys=${items.size} cap=$cap")
    for (mode in Mode.entries) {
        val trial = HashTable(mode, cap)
        for (item in items) trial.put(item, false, maximum, Reporting.SILENT)
        val values = trial.metrics()
        add("$mode cap=${trial.cap} longest=${values.longest} avg=${values.average} probes=${trial.counters.probes} rehashes=${trial.counters.rehashes}")
    }
}
fun benchmark(cap: Int, count: Int, length: Int, seed: Long, maximum: Int): List<String> = buildList {
    val keys = generate(2 * count, length, seed)
    add("BENCH cap=$cap count=$count len=$length seed=$seed")
    for (mode in Mode.entries) {
        val trial = HashTable(mode, cap)
        for (index in 0 until count) trial.put(Item(keys[index], index + 1L), false, maximum, Reporting.SILENT)
        var misses = 0L
        var probes = 0L
        for (key in keys.subList(count, 2 * count)) {
            val found = trial.search(key)
            if (found.item == null) { misses++; probes += found.probes }
        }
        add("$mode cap=${trial.cap} keys=${trial.size} hit=${trial.metrics().average} misses=$misses miss=${decimal(probes, misses)} rehashes=${trial.counters.rehashes}")
    }
}

class Simulator {
    var table: HashTable? = null
    var maximum = 75
    var minimum = 0
    var trace = false
    companion object {
        val COMMANDS = setOf("CREATE", "MAXLOAD", "MINLOAD", "TRACE", "HASH", "PUT", "ADD", "GET", "DEL", "PROBE", "GEN", "GENDEL", "RESIZE", "CONVERT",
            "CLEAR", "DUMP", "MAP", "STATS", "KEYS", "TOP", "SCAN", "CLUSTERS", "DIST", "COMPARE", "BENCH")
    }
    fun execute(line: String): List<String> {
        val words = line.split(' ')
        val command = words[0]
        fun number(index: Int) = words[index].toLong()
        if (command !in COMMANDS) fail("UNKNOWN COMMAND $command")
        when (command) {
            "CREATE" -> {
                val mode = parseMode(words[1])
                val cap = prime(capacity(number(2)))
                table = HashTable(mode, cap)
                return listOf("CREATE $mode cap=$cap")
            }
            "MAXLOAD", "MINLOAD" -> {
                val value = number(1)
                if (value !in if (command == "MAXLOAD") 10L..95L else 0L..40L) fail("BAD LOAD")
                if (command == "MAXLOAD") maximum = value.toInt() else minimum = value.toInt()
                return listOf("$command $value")
            }
            "TRACE" -> {
                if (words[1] != "ON" && words[1] != "OFF") fail("BAD ARGUMENT")
                trace = words[1] == "ON"
                return listOf("TRACE ${words[1]}")
            }
            "HASH" -> {
                val cap = capacity(number(2))
                val key = words[1]
                return listOf("HASH $key m=$cap h31=${hash(key, 31, cap)} h37=${hash(key, 37, cap)} step=${1 + hash(key, 37, cap - 1)}")
            }
            "BENCH" -> {
                val cap = prime(capacity(number(1)))
                val count = number(2); val length = number(3); val seed = number(4)
                checkGeneration(count, length, seed)
                return benchmark(cap, count.toInt(), length.toInt(), seed, maximum)
            }
        }
        val current = table ?: fail("NO TABLE")
        val reporting = if (trace) Reporting.TRACE else Reporting.FULL
        return when (command) {
            "PUT", "ADD" -> current.put(Item(words[1], number(2)), command == "ADD", maximum, reporting).lines
            "GET" -> current.get(words[1], trace)
            "DEL" -> current.delete(words[1], minimum, maximum, reporting).lines
            "PROBE" -> {
                val found = current.search(words[1], true)
                val path = if (found.path.isEmpty()) "" else " " + found.path.joinToString(" ")
                listOf("PROBE ${words[1]}$path ${if (found.item == null) "MISS" else "FOUND"} probes=${found.probes}")
            }
            "GEN", "GENDEL" -> {
                val count = number(1); val length = number(2); val seed = number(3)
                checkGeneration(count, length, seed)
                val lines = mutableListOf<String>()
                var changed = 0
                for ((index, key) in generate(count.toInt(), length.toInt(), seed).withIndex()) {
                    val result = if (command == "GEN") current.put(Item(key, index + 1L), false, maximum, Reporting.REHASHES)
                        else current.delete(key, minimum, maximum, Reporting.REHASHES)
                    if (result.changed) changed++
                    lines += result.lines
                }
                lines += if (command == "GEN") "GEN $count new=$changed updated=${count - changed}"
                    else "GENDEL $count deleted=$changed missing=${count - changed}"
                lines
            }
            "RESIZE", "CONVERT" -> {
                val cap = if (command == "RESIZE") prime(capacity(number(1))) else current.cap
                val mode = if (command == "CONVERT") parseMode(words[1]) else current.mode
                val slots = cap * if (mode == Mode.CUCKOO) 2 else 1
                if (current.size * 100L > maximum.toLong() * slots) fail("TOO SMALL")
                val replacement = HashTable.rebuild(mode, cap, current.items()) ?: fail("REBUILD FAILED")
                val row = if (command == "RESIZE") "RESIZE ${current.cap} -> $cap" else "CONVERT ${current.mode} -> $mode cap=$cap"
                current.adopt(replacement)
                listOf(row)
            }
            "CLEAR" -> {
                val size = current.size
                current.adopt(HashTable(current.mode, current.cap))
                listOf("CLEAR $size")
            }
            "DUMP" -> current.dump()
            "MAP" -> current.map()
            "STATS" -> current.statistics()
            "KEYS" -> {
                val keys = current.items().map { it.key }.sorted()
                listOf("KEYS ${keys.size}" + if (keys.isEmpty()) "" else " " + keys.joinToString(" "))
            }
            "TOP" -> {
                val limit = number(1)
                if (limit !in 1L..100L) fail("BAD ARGUMENT")
                val selected = current.costs().sortedWith(compareByDescending<Cost> { it.probes }.thenBy { it.key }).take(limit.toInt())
                listOf("TOP ${selected.size}") + selected.map { "${it.key} cost=${it.probes} at=${current.position(it.position)}" }
            }
            "SCAN" -> {
                val cursor = number(1); val limit = number(2)
                if (limit !in 1L..100L) fail("BAD ARGUMENT")
                if (cursor >= current.slotCount) fail("BAD CURSOR")
                listOf(current.scan(cursor.toInt(), limit.toInt()))
            }
            "CLUSTERS" -> current.clusters()
            "DIST" -> current.distribution()
            "COMPARE" -> compare(current, prime(capacity(number(1))), maximum)
            else -> error("Unreachable command")
        }
    }
}

fun main() {
    val input = System.`in`.bufferedReader()
    val output = System.out.bufferedWriter()
    val count = input.readLine()?.toInt() ?: return
    val simulator = Simulator()
    repeat(count) {
        try {
            for (line in simulator.execute(input.readLine())) { output.write(line); output.write("\n") }
        } catch (error: CommandError) { output.write("ERROR ${error.message}\n") }
    }
    output.flush()
}
