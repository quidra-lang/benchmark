import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Path
import kotlin.math.abs

private data class Checkpoint(val command: Command, val stack: Int, val live: Pair, val allocated: Pair, val phase: Pair, val survivors: Pair, val reachable: Set<Int>)
private data class Pause(val line: Int, val work: Int, val freed: Pair, val collection: Boolean)
private data class Segment(val start: Int, val length: Int, val mutator: Boolean, val before: Int)
private fun used(objects: Collection<HeapObject>): Int = objects.sumOf {
    it.size
}
private fun pair(objects: Collection<HeapObject>): Pair {
    val pair = Pair();
    for (item in objects) pair.add(item);
    return pair
}
private fun reachable(roots: List<Int>, objects: List<HeapObject>): Set<Int> {
    val reached = mutableSetOf<Int>();
    val stack = ArrayDeque<Int>();
    for (root in roots) if (root != 0) stack.addLast(root)
    while (stack.isNotEmpty()) {
        val number = stack.removeLast();
        if (!reached.add(number)) continue;
        for (child in objects[number - 1].fields) if (child != 0) stack.addLast(child)
    }
    return reached
}
private fun fragmentation(blocks: List<FreeBlock>): String {
    val total = Heap.total(blocks);
    return Heap.percent(total - Heap.largest(blocks), total)
}
private fun join(blocks: List<List<String>>): List<String> {
    val lines = mutableListOf<String>();
    for (block in blocks) {
        if (lines.isNotEmpty()) lines.add("");
        lines.addAll(block)
    };
    return lines
}
private class Script(lines: List<String>) {
    val lineCount = lines.size
    val commands = mutableListOf<Command>()
    val errors = mutableListOf<String>()
    val counts = Mutator.names.associateWith {
        0
    }.toMutableMap()
    val roots = mutableListOf<Int>()
    val objects = mutableListOf<HeapObject>()
    val births = mutableListOf<Int>();
    val deaths = mutableListOf<Int>();
    val lifetimes = mutableListOf<Int>()
    val checkpoints = mutableListOf<Checkpoint>()
    val labels = mutableSetOf<String>()
    var alive = emptySet<Int>()
    var live = Pair();
    var peak = Pair()
    var clock = 0;
    var peakLine = 0;
    var phaseStart = 0
    init {
        for ((i, line) in lines.withIndex()) {
            val parsed = Mutator.parse(i + 1, line);
            var reason = parsed.error;
            if (reason.isEmpty()) reason = check(parsed.command!!);
            if (reason.isEmpty()) run(parsed.command!!) else errors.add("error line ${i + 1} $reason")
        }
    }
    fun check(command: Command): String {
        val name = command.name;
        val depth = roots.size
        if (name in setOf("ALLOC", "PUSH", "LOAD") && depth == 64) return "stack"
        if (name in setOf("LOAD", "SET", "OVERWRITE") && command.slot >= depth) return "stack"
        if (name in setOf("PUSH", "SET", "OVERWRITE") && command.source >= depth) return "stack"
        if (name == "POP" && command.count > depth) return "stack"
        if (name == "LOAD" || name == "SET") {
            val number = roots[command.slot];
            if (number == 0) return "null";
            if (command.field >= objects[number - 1].fields.size) return "field"
        }
        if (name == "CHECKPOINT" && command.label in labels) return "duplicate"
        return ""
    }
    fun value(source: Int): Int = if (source < 0) 0 else roots[source]
    fun execute(command: Command) {
        when (command.name) {
            "ALLOC" -> {
                val item = HeapObject(objects.size + 1, command.pointers, command.data);
                objects.add(item);
                births.add(clock);
                deaths.add(0);
                lifetimes.add(-1);
                clock += item.size;
                roots.add(item.number)
            }
            "PUSH" -> roots.add(value(command.source))
            "LOAD" -> roots.add(objects[roots[command.slot] - 1].fields[command.field])
            "POP" -> repeat(command.count) {
                roots.removeAt(roots.lastIndex)
            }
            "SET" -> objects[roots[command.slot] - 1].fields[command.field] = value(command.source)
            "OVERWRITE" -> roots[command.slot] = value(command.source)
        }
    }
    fun run(command: Command) {
        commands.add(command);
        counts[command.name] = counts.getValue(command.name) + 1;
        execute(command);
        val reached = reachable(roots, objects)
        for (number in alive) if (number !in reached) {
            deaths[number - 1] = command.line;
            lifetimes[number - 1] = clock - births[number - 1] - objects[number - 1].size
        }
        alive = reached;
        live = Pair();
        for (number in reached) live.add(objects[number - 1])
        if (peakLine == 0 || live.words > peak.words) {
            peak = live;
            peakLine = command.line
        }
        if (command.name == "CHECKPOINT") {
            labels.add(command.label);
            val allocated = pair(objects);
            val phase = Pair();
            val survivors = Pair()
            for (i in phaseStart until objects.size) {
                val item = objects[i];
                phase.add(item);
                if (item.number in reached) survivors.add(item)
            }
            phaseStart = objects.size;
            checkpoints.add(Checkpoint(command, roots.size, live, allocated, phase, survivors, reached))
        }
    }
    fun report(): List<String> {
        val lines = mutableListOf("script lines $lineCount valid ${commands.size} errors ${errors.size}");
        lines.addAll(errors)
        lines.add("commands " + Mutator.names.joinToString(" ") {
            "$it ${counts.getValue(it)}"
        })
        lines.add("allocated objects ${objects.size} words $clock sizes ${Heap.classes(objects.map { it.size })}")
        lines.add("peak_live objects ${peak.count} words ${peak.words} line $peakLine");
        lines.add("end_live objects ${live.count} words ${live.words} stack ${roots.size}")
        val bins = IntArray(6);
        val limits = intArrayOf(63, 255, 1023, 4095)
        for (lifetime in lifetimes) if (lifetime < 0) bins[5]++ else {
            var index = 0;
            while (index < limits.size && lifetime > limits[index]) index++;
            bins[index]++
        }
        lines.add("lifetimes 0-63 ${bins[0]} 64-255 ${bins[1]} 256-1023 ${bins[2]} 1024-4095 ${bins[3]} 4096+ ${bins[4]} live ${bins[5]}")
        for (checkpoint in checkpoints) lines.add("checkpoint ${checkpoint.command.label} line ${checkpoint.command.line} stack ${checkpoint.stack} live ${checkpoint.live} allocated ${checkpoint.allocated} phase ${checkpoint.phase} survivors ${checkpoint.survivors} survival ${Heap.percent(checkpoint.survivors.words, checkpoint.phase.words)}")
        return lines
    }
}
private fun onCycle(start: Int, members: Map<Int, HeapObject>): Boolean {
    val seen = mutableSetOf<Int>();
    val stack = ArrayDeque<Int>();
    for (child in members.getValue(start).fields) if (child in members) stack.addLast(child)
    while (stack.isNotEmpty()) {
        val number = stack.removeLast();
        if (number == start) return true;
        if (!seen.add(number)) continue;
        for (child in members.getValue(number).fields) if (child in members) stack.addLast(child)
    }
    return false
}
private fun leakReport(title: String, garbage: List<HeapObject>, deaths: List<Int>): List<String> {
    val members = garbage.associateBy {
        it.number
    }.toSortedMap();
    val neighbors = members.keys.associateWith {
        mutableListOf<Int>()
    }
    for (item in garbage) for (child in item.fields) if (child in members) {
        neighbors.getValue(item.number).add(child);
        neighbors.getValue(child).add(item.number)
    }
    val groups = mutableListOf<List<HeapObject>>();
    val grouped = mutableSetOf<Int>()
    for (number in members.keys) {
        if (!grouped.add(number)) continue
        val group = mutableListOf<HeapObject>();
        val stack = ArrayDeque<Int>();
        stack.addLast(number)
        while (stack.isNotEmpty()) {
            val current = stack.removeLast();
            group.add(members.getValue(current));
            for (other in neighbors.getValue(current)) if (grouped.add(other)) stack.addLast(other)
        }
        groups.add(group.sortedBy {
            it.number
        })
    }
    val lines = mutableListOf("$title groups ${groups.size} objects ${garbage.size} words ${used(garbage)}")
    for ((i, group) in groups.withIndex()) {
        var cycles = 0;
        var died = 0;
        val ids = mutableListOf<String>();
        for (item in group) {
            val cycle = onCycle(item.number, members);
            if (cycle) cycles++;
            died = maxOf(died, deaths[item.number - 1]);
            ids.add("${item.number}${if (cycle) "*" else ""}")
        };
        lines.add("group ${i + 1} objects ${group.size} words ${used(group)} cycle $cycles died $died ids ${ids.joinToString(" ")}")
    }
    return lines
}
private class RefCounting(size: Int, val deaths: List<Int>) : MarkSweep(size) {
    val released = mutableListOf<HeapObject>();
    val reports = mutableListOf<List<String>>()
    var increments = 0;
    var decrements = 0
    fun retain(number: Int) {
        if (number != 0) {
            lookup(number).count++;
            increments++
        }
    }
    fun release(number: Int) {
        if (number == 0) return
        val item = lookup(number);
        decrements++;
        item.count--;
        if (item.count != 0) return
        val pending = ArrayDeque<HeapObject>();
        pending.addLast(item)
        while (pending.isNotEmpty()) {
            val current = pending.removeLast();
            objects.remove(current);
            released.add(current);
            for (child in current.fields) if (child != 0) {
                decrements++;
                val target = lookup(child);
                target.count--;
                if (target.count == 0) pending.addLast(target)
            }
        }
    }
    fun cascade(line: Int): Pause? {
        if (released.isEmpty()) return null;
        val freed = pair(released);
        var work = 0;
        for (item in released) work += 1 + item.fields.size;
        released.clear();
        return Pause(line, work, freed, false)
    }
    override fun collect(roots: List<Int>, line: Int, request: Int) {
        val record = CollectionRecord(records.size + 1, line, request, "backup", freeList());
        Marking.mark(this, roots, record);
        val garbage = objects.filter {
            !it.marked
        }
        reports.add(leakReport("backup ${record.number} line $line", garbage, deaths));
        Marking.sweep(this, record)
        for (item in garbage) for (child in item.fields) if (child != 0 && lookup(child).marked) {
            lookup(child).count--;
            decrements++
        }
        record.finish(freeList());
        records.add(record)
    }
    fun finish(reachable: Set<Int>) {
        reports.add(leakReport("end", objects.filter {
            it.number !in reachable
        }, deaths))
    }
}
private class PauseStats(pauses: List<Pause>) {
    val count = pauses.size
    val collections = pauses.count {
        it.collection
    }
    val work = pauses.sumOf {
        it.work
    }
    val freed = pauses.sumOf {
        it.freed.words
    }
    val maximum = pauses.maxOfOrNull {
        it.work
    }
    ?: 0
    private val works = pauses.map {
        it.work
    }.sorted()
    val p50 = if (count == 0) "-" else works[(50 * count + 99) / 100 - 1].toString()
    val p90 = if (count == 0) "-" else works[(90 * count + 99) / 100 - 1].toString()
}
private class Timeline {
    val segments = mutableListOf<Segment>()
    var length = 0;
    var mutator = 0
    fun add(mutator: Boolean, units: Int) {
        if (units == 0) return;
        segments.add(Segment(length, units, mutator, this.mutator));
        length += units;
        if (mutator) this.mutator += units
    }
    fun prefix(position: Int): Int {
        var low = 0;
        var high = segments.size;
        while (low + 1 < high) {
            val middle = (low + high) / 2;
            if (segments[middle].start <= position) low = middle else high = middle
        };
        val segment = segments[low];
        return segment.before + if (segment.mutator) position - segment.start else 0
    }
    fun mmu(width: Int): String {
        if (width > length) return "-";
        var minimum = width;
        for (segment in segments) for (begin in intArrayOf(segment.start, segment.start + segment.length - width)) if (begin >= 0 && begin <= length - width) minimum = minOf(minimum, prefix(begin + width) - prefix(begin));
        return Heap.percent(minimum, width)
    }
}
private fun collector(entry: CollectorEntry, config: Config, script: Script): Collector = when (entry.type) {
    "MARK_SWEEP" -> MarkSweep(config.heap)
    "MARK_COMPACT" -> MarkCompact(config.heap)
    "COPYING" -> Copying(config.heap)
    "GENERATIONAL" -> Generational(config.heap, entry.young, entry.age)
    else -> RefCounting(config.heap, script.deaths)
}
private class Run(val entry: CollectorEntry, val config: Config, val script: Script) {
    val collector = collector(entry, config, script)
    val refcount = entry.type == "REFCOUNT";
    val generational = entry.type == "GENERATIONAL"
    val roots = mutableListOf<Int>();
    val cascades = mutableListOf<Pause>();
    val timeline = Timeline();
    val observations = mutableListOf<List<String>>()
    var peak = 0;
    var failedLine = 0;
    var failedSize = 0
    fun completed(): Boolean = failedLine == 0
    fun value(source: Int): Int = if (source < 0) 0 else roots[source]
    fun retain(value: Int) {
        if (refcount) (collector as RefCounting).retain(value)
    }
    fun release(value: Int) {
        if (refcount) (collector as RefCounting).release(value)
    }
    fun push(value: Int) {
        retain(value);
        roots.add(value)
    }
    fun simulate() {
        for (command in script.commands) {
            val before = collector.records.size;
            var units = 1;
            var placed = true
            if (command.name == "ALLOC") {
                val item = HeapObject(collector.placed.size + 1, command.pointers, command.data);
                units = item.size;
                placed = collector.allocate(item, roots, command.line);
                if (placed) {
                    push(item.number);
                    peak = maxOf(peak, used(collector.objects))
                }
            }
            else execute(command)
            for (record in collector.records.drop(before)) timeline.add(false, record.work)
            if (!placed) {
                failedLine = command.line;
                failedSize = units;
                return
            }
            timeline.add(true, units)
            if (refcount) {
                val cascade = (collector as RefCounting).cascade(command.line);
                if (cascade != null) {
                    cascades.add(cascade);
                    timeline.add(false, cascade.work)
                }
            }
        }
        if (refcount) (collector as RefCounting).finish(script.alive)
    }
    fun execute(command: Command) {
        when (command.name) {
            "PUSH" -> push(value(command.source))
            "LOAD" -> push(collector.lookup(roots[command.slot]).fields[command.field])
            "POP" -> repeat(command.count) {
                release(roots.removeAt(roots.lastIndex))
            }
            "SET" -> {
                val number = roots[command.slot];
                val value = value(command.source);
                if (generational) (collector as Generational).writeBarrier(number, value);
                retain(value);
                val item = collector.lookup(number);
                val previous = item.fields[command.field];
                item.fields[command.field] = value;
                release(previous)
            }
            "OVERWRITE" -> {
                val value = value(command.source);
                retain(value);
                val previous = roots[command.slot];
                roots[command.slot] = value;
                release(previous)
            }
            else -> observations.add(observe(script.checkpoints[observations.size]))
        }
    }
    fun observe(checkpoint: Checkpoint): List<String> {
        val live = Pair();
        val garbage = Pair();
        var pointers = 0;
        var forward = 0;
        var backward = 0;
        var distance = 0
        for (item in collector.objects) {
            if (item.number !in checkpoint.reachable) {
                garbage.add(item);
                continue
            };
            live.add(item);
            for (child in item.fields) if (child != 0) {
                pointers++;
                val difference = collector.lookup(child).address - item.address;
                if (difference > 0) forward++;
                if (difference < 0) backward++;
                distance += abs(difference)
            }
        }
        val blocks = collector.freeList()
        val lines = mutableListOf("heap objects ${pair(collector.objects)} reachable $live garbage $garbage", "free total ${Heap.total(blocks)} largest ${Heap.largest(blocks)} blocks ${blocks.size} sizes ${Heap.classes(blocks.map { it.length })} fragmentation ${fragmentation(blocks)}", "locality pointers $pointers forward $forward backward $backward mean_distance ${if (pointers == 0) "-" else Heap.dec2(distance, pointers)}")
        if (generational) {
            val gc = collector as Generational;
            val young = Pair();
            val old = Pair();
            val ages = IntArray(4);
            for (item in gc.objects) if (gc.young(item)) {
                young.add(item);
                ages[minOf(3, item.age)]++
            } else old.add(item);
            lines.add("generations young $young old $old remembered ${gc.remembered.size} ages 0:${ages[0]} 1:${ages[1]} 2:${ages[2]} 3+:${ages[3]}")
        }
        if (checkpoint.command.label in config.maps) {
            val map = Heap.map(config.heap, collector.objects, checkpoint.reachable, collector.inactive());
            for (start in map.indices step config.width) lines.add(start.toString().padStart(4, '0') + " " + map.substring(start, start + config.width))
        }
        return lines
    }
    fun pauses(): List<Pause> = collector.records.map {
        Pause(it.line, it.work, it.freed, true)
    }
    + cascades
    fun generationalLine(): String {
        val gc = collector as Generational;
        val promoted = Pair();
        var line = "generational"
        for (kind in listOf("minor", "major", "tenure", "full")) {
            val records = gc.records.filter {
                it.kind == kind
            };
            line += " $kind ${records.size} ${records.sumOf { it.work }}"
        }
        for (record in gc.records) promoted.add(record.promoted)
        return "$line promoted $promoted barrier ${gc.barriers} remembered ${gc.remembers}"
    }
    fun refcountLine(): String {
        val gc = collector as RefCounting;
        val freed = Pair();
        for (cascade in cascades) freed.add(cascade.freed);
        val largest = cascades.maxByOrNull {
            it.work
        }
        val maximum = if (largest == null) "max_cascade 0 0 line -" else "max_cascade ${largest.freed.count} ${largest.work} line ${largest.line}"
        return "refcount increments ${gc.increments} decrements ${gc.decrements} cascades ${cascades.size} freed $freed $maximum"
    }
    fun collectionLines(): List<String> {
        val lines = mutableListOf("collector ${entry.name} ${entry.type}")
        for (record in collector.records) lines.add("${record.number} line ${record.line} size ${record.request} kind ${record.kind} live ${record.live} freed ${record.freed} moved ${record.moved} promoted ${record.promoted} stack ${record.stack} work ${record.work} before ${record.before[0]} ${record.before[1]} after ${record.after[0]} ${record.after[1]}")
        val pauses = pauses();
        val stats = PauseStats(pauses)
        lines.add("totals collections ${stats.collections} pauses ${stats.count} work ${stats.work} freed ${stats.freed} pause p50 ${stats.p50} p90 ${stats.p90} max ${stats.maximum}")
        lines.add("utilization ${Heap.percent(timeline.mutator, timeline.length)} mmu " + config.windows.joinToString(" ") {
            "$it:${timeline.mmu(it)}"
        })
        if (generational) lines.add(generationalLine());
        if (refcount) lines.add(refcountLine())
        var previous = 0
        for (checkpoint in script.checkpoints) {
            if (!completed() && failedLine < checkpoint.command.line) lines.add("phase ${checkpoint.command.label} out_of_memory")
            else {
                val phase = PauseStats(pauses.filter {
                    previous < it.line && it.line <= checkpoint.command.line
                });
                lines.add("phase ${checkpoint.command.label} collections ${phase.collections} pauses ${phase.count} work ${phase.work} freed ${phase.freed} max_pause ${phase.maximum}")
            }
            previous = checkpoint.command.line
        }
        lines.add(if (completed()) "status completed" else "status out_of_memory line $failedLine size $failedSize")
        return lines
    }
    fun summary(): String {
        val stats = PauseStats(pauses());
        val live = collector.records.sumOf {
            it.live.count
        };
        val moved = collector.records.sumOf {
            it.moved.count
        };
        val moves = collector.placed.filter {
            it.moves > 0
        }.map {
            it.moves
        }
        val ending = if (completed()) {
            val blocks = collector.freeList();
            "${used(collector.objects)},${Heap.total(blocks)},${Heap.largest(blocks)},${fragmentation(blocks)}"
        } else "-,-,-,-"
        return "${entry.name},${entry.type},${if (completed()) "completed" else "out_of_memory"},${collector.records.size},${stats.count},$live,$moved,${moves.size},${moves.maxOrNull() ?: 0},${stats.freed},${stats.work},${stats.p50},${stats.p90},${stats.maximum},$peak,$ending"
    }
    fun leakLines(): List<String> {
        val lines = mutableListOf("collector ${entry.name}");
        for (report in (collector as RefCounting).reports) lines.addAll(report);
        if (!completed()) lines.add("status out_of_memory");
        return lines
    }
}
private fun write(name: String, lines: List<String>) {
    Files.writeString(Path.of("output", name), if (lines.isEmpty()) "" else lines.joinToString("\n", postfix = "\n"), StandardCharsets.US_ASCII)
}
fun main() {
    val config = Mutator.config();
    val script = Script(Mutator.lines("mutator.txt"));
    val runs = config.collectors.map {
        Run(it, config, script).also {
            run -> run.simulate()
        }
    }
    val mapBlocks = mutableListOf<List<String>>()
    for ((i, checkpoint) in script.checkpoints.withIndex()) for (run in runs) {
        val block = mutableListOf("checkpoint ${checkpoint.command.label} line ${checkpoint.command.line} collector ${run.entry.name}");
        if (i < run.observations.size) block.addAll(run.observations[i]) else block.add("out_of_memory");
        mapBlocks.add(block)
    }
    val summaries = mutableListOf("collector,type,status,collections,pauses,live,moved,moved_objects,max_moves,freed,total_work,p50_pause,p90_pause,max_pause,peak_used,end_used,end_free,largest_free,fragmentation");
    summaries.addAll(runs.map {
        it.summary()
    })
    val leakBlocks = runs.filter {
        it.refcount
    }.map {
        it.leakLines()
    }
    Files.createDirectories(Path.of("output"));
    write("mutator.txt", script.report());
    write("heap_maps.txt", join(mapBlocks));
    write("collections.txt", join(runs.map {
        it.collectionLines()
    }));
    write("summary.csv", summaries);
    write("leaks.txt", if (leakBlocks.isEmpty()) listOf("none") else join(leakBlocks))
}
