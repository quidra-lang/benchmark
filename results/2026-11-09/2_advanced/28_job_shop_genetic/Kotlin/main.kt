import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Path

private val rules = listOf("SPT", "LPT", "MWKR", "FIFO")
private data class Move(val first: Int, val second: Int)
private data class Shift(val ident: Int, val oldStart: Int, val newStart: Int)
private data class Iteration(val number: Int, val moves: Int, val tabu: Int, val move: Move, val aspiration: Boolean, val value: Int, val best: Int)
private data class Baseline(val rule: String, val schedule: Schedule, val dispatch: Dispatch, val search: Search)
private class Params {
    val values = Files.readAllLines(Path.of("input/ga_params.txt")).associate {
        val fields = it.split(" ");
        fields[0] to fields.drop(1)
    }
    fun value(key: String): Int = values.getValue(key)[0].toInt()
    fun fraction(key: String): IntArray = values.getValue(key)[0].split("/").map {
        it.toInt()
    }.toIntArray()
}
private fun percent(part: Int, whole: Int): String {
    val value = (2000 * part + whole) / (2 * whole);
    return "${value / 10}.${value % 10}%"
}
private fun letter(number: Int): Char = ('A'.code + number - 1).toChar()
private fun gcd(a: Int, b: Int): Int {
    var first = a;
    var second = b;
    while (second != 0) {
        val old = second;
        second = first % second;
        first = old
    };
    return first
}
private fun copy(order: List<List<Int>>): List<MutableList<Int>> = order.map {
    it.toMutableList()
}
private fun orderStarts(instance: Instance, order: List<List<Int>>, durations: IntArray): IntArray {
    val starts = IntArray(durations.size) {
        -1
    };
    val completions = IntArray(durations.size);
    val positions = IntArray(instance.machineCount);
    var placed = 0
    while (placed < starts.size) for (m in 0 until instance.machineCount) {
        val sequence = order[m]
        while (positions[m] < sequence.size) {
            val position = positions[m];
            val ident = sequence[position];
            val previous = instance.operations[ident].previous
            if (previous >= 0 && starts[previous] < 0) break
            starts[ident] = maxOf(if (previous < 0) 0 else completions[previous], if (position == 0) 0 else completions[sequence[position - 1]])
            completions[ident] = starts[ident] + durations[ident];
            positions[m]++;
            placed++
        }
    }
    return starts
}
private fun makespan(starts: IntArray, durations: IntArray): Int = starts.indices.maxOf {
    starts[it] + durations[it]
}
private fun schedule(instance: Instance, order: List<List<Int>>): Schedule = Schedule(instance, orderStarts(instance, order, instance.durations))
private fun evaluate(instance: Instance, order: List<List<Int>>, durations: IntArray): Int = makespan(orderStarts(instance, order, durations), durations)
private fun apply(instance: Instance, order: List<List<Int>>, move: Move): List<List<Int>> {
    val result = copy(order);
    val sequence = result[instance.operations[move.first].machine - 1];
    val position = sequence.indexOf(move.first)
    sequence[position] = move.second;
    sequence[position + 1] = move.first
    return result
}
private fun distances(first: Schedule, second: Schedule): IntArray = IntArray(first.instance.machineCount) {
    m ->
    val rank = second.order[m].withIndex().associate {
        it.value to it.index
    };
    val sequence = first.order[m];
    var count = 0
    for (i in sequence.indices) for (j in i + 1 until sequence.size) if (rank.getValue(sequence[i]) > rank.getValue(sequence[j])) count++
    count
}
private fun jackson(machine: Machine): Int {
    val tasks = machine.operations;
    val remaining = tasks.map {
        it.duration
    }.toIntArray();
    var time = 0;
    var bound = 0
    while (remaining.any {
        it != 0
    }) {
        val release = tasks.indices.filter {
            remaining[it] > 0
        }.minOf {
            tasks[it].head
        };
        time = maxOf(time, release)
        var selected = -1
        for (i in tasks.indices) if (remaining[i] > 0 && tasks[i].head <= time && (selected < 0 || tasks[i].tail > tasks[selected].tail)) selected = i
        var delta = remaining[selected]
        for (task in tasks) if (task.head > time) delta = minOf(delta, task.head - time)
        time += delta;
        remaining[selected] -= delta
        if (remaining[selected] == 0) bound = maxOf(bound, time + tasks[selected].tail)
    }
    return bound
}
private class Schedule(val instance: Instance, val starts: IntArray) {
    val completions = IntArray(starts.size) {
        starts[it] + instance.durations[it]
    }
    val makespan = completions.max()
    val byStart = starts.indices.sortedWith(compareBy<Int> {
        starts[it]
    }.thenBy {
        it
    })
    val order = List(instance.machineCount) {
        mutableListOf<Int>()
    }
    val machinePrevious = IntArray(starts.size) {
        -1
    }
    val machineNext = IntArray(starts.size) {
        -1
    }
    init {
        for (ident in byStart) order[instance.operations[ident].machine - 1].add(ident)
        for (sequence in order) for (i in 1 until sequence.size) {
            machinePrevious[sequence[i]] = sequence[i - 1];
            machineNext[sequence[i - 1]] = sequence[i]
        }
    }
    fun chromosome(): List<Int> = byStart.map {
        instance.operations[it].job
    }
    fun path(): List<Int> {
        var current = completions.indexOfFirst {
            it == makespan
        };
        val path = mutableListOf(current)
        while (starts[current] != 0) {
            val previous = machinePrevious[current];
            current = if (previous >= 0 && completions[previous] == starts[current]) previous else instance.operations[current].previous;
            path.add(current)
        }
        return path.reversed()
    }
    fun blocks(): List<List<Int>> {
        val blocks = mutableListOf<MutableList<Int>>()
        for (ident in path()) {
            if (blocks.isEmpty() || instance.operations[blocks.last().last()].machine != instance.operations[ident].machine) blocks.add(mutableListOf());
            blocks.last().add(ident)
        }
        return blocks
    }
    fun moves(): List<Move> = blocks().flatMap {
        block -> block.zipWithNext {
            first, second -> Move(first, second)
        }
    }
    fun pathCount(): Int {
        val ways = IntArray(starts.size);
        var total = 0
        for (ident in byStart) {
            if (starts[ident] == 0) ways[ident] = 1
            else for (previous in intArrayOf(instance.operations[ident].previous, machinePrevious[ident])) if (previous >= 0 && completions[previous] == starts[ident]) ways[ident] += ways[previous]
            if (completions[ident] == makespan) total += ways[ident]
        }
        return total
    }
    fun shift(ident: Int): Pair<Int, Int>? {
        val operation = instance.operations[ident];
        val sequence = order[operation.machine - 1];
        val position = sequence.indexOf(ident);
        val ready = if (operation.previous < 0) 0 else completions[operation.previous]
        for (insert in 0 until position) {
            val low = if (insert == 0) 0 else completions[sequence[insert - 1]];
            val high = starts[sequence[insert]];
            val start = maxOf(low, ready);
            if (start + operation.duration <= high) return start to insert
        }
        return null
    }
    fun shiftable(): Int = starts.indices.count {
        shift(it) != null
    }
    fun slacks(): Pair<IntArray, IntArray> {
        val latest = IntArray(starts.size);
        val slack = IntArray(starts.size);
        val free = IntArray(starts.size)
        for (ident in byStart.asReversed()) {
            var limit = makespan;
            var startLimit = makespan
            for (next in intArrayOf(instance.operations[ident].next, machineNext[ident])) if (next >= 0) {
                limit = minOf(limit, latest[next]);
                startLimit = minOf(startLimit, starts[next])
            }
            latest[ident] = limit - instance.durations[ident];
            slack[ident] = latest[ident] - starts[ident];
            free[ident] = startLimit - completions[ident]
        }
        return slack to free
    }
    fun pathCounts(): IntArray {
        val counts = IntArray(instance.machineCount);
        for (ident in path()) counts[instance.operations[ident].machine - 1]++;
        return counts
    }
    fun bottleneck(): Int {
        val counts = pathCounts();
        return counts.indices.maxBy {
            counts[it]
        }
        + 1
    }
    fun flow(): Int = instance.jobs.sumOf {
        completions[it.operations.last().ident]
    }
    fun idle(): Int = makespan * instance.machineCount - instance.durations.sum()
    fun letters(machine: Int): String = order[machine - 1].joinToString("") {
        letter(instance.operations[it].job).toString()
    }
}
private class Search(instance: Instance, order: List<List<Int>>, params: Params) {
    val start = evaluate(instance, order, instance.durations)
    val records = mutableListOf<Iteration>()
    var bestOrder = order
    var best = start
    var found = 0
    var reason = "limit"
    init {
        var current = order;
        val expiry = mutableMapOf<Move, Int>()
        for (iteration in 1..params.value("tabu_iterations")) {
            val moves = schedule(instance, current).moves()
            if (moves.isEmpty()) {
                reason = "no_moves";
                break
            }
            var chosen: Move? = null;
            var value = Int.MAX_VALUE;
            var tabuCount = 0;
            var aspiration = false
            for (move in moves) {
                val candidate = evaluate(instance, apply(instance, current, move), instance.durations);
                val tabu = expiry.getOrDefault(move, 0) >= iteration
                if (tabu) tabuCount++
                if ((!tabu || candidate < best) && candidate < value) {
                    chosen = move;
                    value = candidate;
                    aspiration = tabu
                }
            }
            if (chosen == null) {
                reason = "all_tabu";
                break
            }
            current = apply(instance, current, chosen);
            expiry[Move(chosen.second, chosen.first)] = iteration + params.value("tabu_tenure")
            if (value < best) {
                bestOrder = current;
                best = value;
                found = iteration
            }
            records.add(Iteration(iteration, moves.size, tabuCount, chosen, aspiration, value, best))
        }
    }
}
private class Solver(val instance: Instance, val params: Params) {
    val baselines = mutableListOf<Baseline>()
    val records = mutableListOf<IntArray>()
    val progress = mutableListOf("generation,best,mean,worst,distinct")
    val shifts = mutableListOf<Shift>()
    val jacksons = instance.machines.map {
        jackson(it)
    }.toIntArray()
    val jobBound = instance.jobs.maxBy {
        it.work
    }
    val machineBound = instance.machines.maxBy {
        it.bound
    }
    val jacksonMachine = jacksons.indices.maxBy {
        jacksons[it]
    }
    val lower = maxOf(jobBound.work, machineBound.bound, jacksons[jacksonMachine])
    val random = Minstd(params.value("seed"))
    var population = mutableListOf<MutableList<Int>>()
    lateinit var values: IntArray
    var crossovers = 0;
    var swaps = 0;
    var inserts = 0;
    var activeValue = 0;
    var activeDecisions = 0;
    var activatedValue = 0
    lateinit var ga: Schedule
    lateinit var result: Schedule
    lateinit var search: Search
    fun ranking(): List<Int> = values.indices.sortedWith(compareBy<Int> {
        values[it]
    }.thenBy {
        it
    })
    fun mutate(child: MutableList<Int>) {
        if (random.chance(params.fraction("swap_mutation"))) {
            swaps++;
            Genetic.swap(random, child)
        };
        if (random.chance(params.fraction("insert_mutation"))) {
            inserts++;
            Genetic.insert(random, child)
        }
    }
    fun solve() {
        for (rule in rules) {
            val dispatch = DispatchRules.schedule(instance, rule);
            val schedule = Schedule(instance, dispatch.starts);
            baselines.add(Baseline(rule, schedule, dispatch, Search(instance, schedule.order, params)));
            population.add(schedule.chromosome().toMutableList())
        }
        while (population.size < params.value("population")) {
            val sequence = instance.jobs.flatMap {
                job -> List(job.operations.size) {
                    job.number
                }
            }.toMutableList();
            random.shuffle(sequence);
            population.add(sequence)
        }
        var previousBest = Int.MAX_VALUE
        for (generation in 0..params.value("generations")) {
            values = population.map {
                makespan(Genetic.decode(instance, it), instance.durations)
            }.toIntArray()
            val best = ranking().first()
            if (values[best] < previousBest) records.add(intArrayOf(generation, values[best], best + 1))
            previousBest = values[best]
            if (generation.toString() in params.values.getValue("checkpoints")) {
                val total = values.sum();
                val divisor = gcd(total, values.size);
                progress.add("$generation,${values.min()},${total / divisor}/${values.size / divisor},${values.max()},${population.toSet().size}")
            }
            if (generation == params.value("generations")) break
            val offspring = ranking().take(params.value("elitism")).map {
                population[it].toMutableList()
            }.toMutableList()
            while (offspring.size < population.size) {
                val first = population[Genetic.tournament(random, values, params.value("tournament"))];
                val second = population[Genetic.tournament(random, values, params.value("tournament"))]
                val children = if (random.chance(params.fraction("crossover"))) {
                    crossovers++;
                    Genetic.crossover(random, first, second, instance.jobs)
                } else listOf(first.toMutableList(), second.toMutableList())
                mutate(children[0]);
                mutate(children[1]);
                offspring.addAll(children)
            }
            population = offspring
        }
        val chromosome = population[ranking().first()];
        ga = Schedule(instance, Genetic.decode(instance, chromosome))
        val positions = IntArray(instance.operations.size);
        for ((i, operation) in Genetic.operations(instance, chromosome).withIndex()) positions[operation.ident] = i + 1
        val active = DispatchRules.schedule(instance, "GENES", positions);
        activeValue = makespan(active.starts, instance.durations);
        activeDecisions = active.decisions
        val activated = copy(ga.order)
        while (true) {
            val current = schedule(instance, activated);
            val selected = current.byStart.firstOrNull {
                current.shift(it) != null
            }
            ?: break
            val shift = current.shift(selected)!!;
            val sequence = activated[instance.operations[selected].machine - 1];
            sequence.remove(selected);
            sequence.add(shift.second, selected);
            shifts.add(Shift(selected, current.starts[selected], shift.first))
        }
        activatedValue = evaluate(instance, activated, instance.durations);
        search = Search(instance, activated, params);
        result = schedule(instance, search.bestOrder)
    }
    fun baselineLines(): List<String> {
        val lines = mutableListOf("INSTANCE jobs ${instance.jobs.size} machines ${instance.machineCount} operations ${instance.operations.size} work ${instance.durations.sum()} errors ${instance.errors.size}")
        for (error in instance.errors) lines.add("ERROR $error")
        for (job in instance.jobs) lines.add("JOB J${job.number} operations ${job.operations.size} work ${job.work} route ${job.operations.joinToString(" ") { "M${it.machine}" }}")
        for (machine in instance.machines) lines.add("MACHINE M${machine.number} operations ${machine.operations.size} load ${machine.load} head ${machine.head} tail ${machine.tail} bound ${machine.bound} jackson ${jacksons[machine.number - 1]}")
        lines.add("BOUND job ${jobBound.work} J${jobBound.number}");
        lines.add("BOUND machine ${machineBound.bound} M${machineBound.number}");
        lines.add("BOUND jackson ${jacksons[jacksonMachine]} M${jacksonMachine + 1}");
        lines.add("BOUND lower $lower")
        for (baseline in baselines) {
            val schedule = baseline.schedule
            lines.add("RULE ${baseline.rule} makespan ${schedule.makespan} gap ${percent(schedule.makespan - lower, lower)} flow ${schedule.flow()} idle ${schedule.idle()} decisions ${baseline.dispatch.decisions} ties ${baseline.dispatch.ties}")
            lines.add("PATH ${baseline.rule} operations ${schedule.path().size} blocks ${schedule.blocks().size} critical_paths ${schedule.pathCount()} bottleneck M${schedule.bottleneck()}")
            lines.add("TABU ${baseline.rule} makespan ${schedule.makespan} -> ${baseline.search.best} found ${baseline.search.found} iterations ${baseline.search.records.size} stop ${baseline.search.reason}")
        }
        val best = baselines.minBy {
            it.schedule.makespan
        };
        lines.add("BEST ${best.rule} makespan ${best.schedule.makespan}")
        for (machine in instance.machines) lines.add("UTILIZATION M${machine.number} " + baselines.joinToString(" ") {
            "${it.rule} ${percent(machine.load, it.schedule.makespan)}"
        })
        return lines
    }
    fun scheduleLines(): List<String> {
        val lines = mutableListOf("GA best ${ga.makespan} generation ${records.last()[0]} crossovers $crossovers swaps $swaps inserts $inserts")
        for (record in records) lines.add("RECORD generation ${record[0]} makespan ${record[1]} individual ${record[2]}")
        val seen = mutableSetOf<List<Int>>();
        var rank = 0
        for (index in ranking()) if (seen.add(population[index])) {
            if (rank == 5) break;
            rank++;
            val other = Schedule(instance, Genetic.decode(instance, population[index]));
            lines.add("TOP $rank individual ${index + 1} makespan ${values[index]} distance ${distances(other, ga).sum()}")
        }
        lines.add("GA_CHROMOSOME ${population[ranking().first()].joinToString(" ")}");
        lines.add("ACTIVE_DECODE makespan $activeValue decisions $activeDecisions")
        for ((i, shift) in shifts.withIndex()) {
            val operation = instance.operations[shift.ident];
            lines.add("SHIFT ${i + 1} ${operation.code} M${operation.machine} start ${shift.oldStart} -> ${shift.newStart}")
        }
        lines.add("ACTIVATED makespan ${ga.makespan} -> $activatedValue shifts ${shifts.size}");
        lines.add("SCHEDULE makespan ${result.makespan} lower_bound $lower gap ${percent(result.makespan - lower, lower)} improvement ${ga.makespan - result.makespan} shiftable ${result.shiftable()}");
        lines.add("CHROMOSOME ${result.chromosome().joinToString(" ")}")
        lines.add("LEGEND " + instance.jobs.joinToString(" ") {
            "${letter(it.number)}=J${it.number}"
        })
        val (scale, columns) = Gantt.scale(result.makespan, params.value("gantt_width"));
        val onPath = result.path().toSet();
        val intervals = List(instance.machineCount) {
            mutableListOf<Interval>()
        }
        for (operation in instance.operations) {
            val mark = if (operation.ident in onPath) letter(operation.job).lowercaseChar() else letter(operation.job);
            intervals[operation.machine - 1].add(Interval(result.starts[operation.ident], result.completions[operation.ident], mark))
        }
        lines.add("GANTT scale $scale columns $columns");
        lines.add(Gantt.time(scale, columns));
        lines.add(Gantt.rule(columns))
        for (m in 0 until instance.machineCount) lines.add(Gantt.row("M${m + 1}", intervals[m], scale, columns))
        lines.add(Gantt.busy(intervals, scale, columns))
        for (job in instance.jobs) lines.add(Gantt.row("J${job.number}", job.operations.map {
            Interval(result.starts[it.ident], result.completions[it.ident], ('0'.code + it.machine % 10).toChar())
        }, scale, columns))
        for (machine in instance.machines) lines.add("ORDER M${machine.number} FINAL ${result.letters(machine.number)} " + baselines.joinToString(" ") {
            "${it.rule} ${it.schedule.letters(machine.number)}"
        })
        for (machine in instance.machines) {
            val sequence = result.order[machine.number - 1];
            val texts = mutableListOf<String>();
            val idle = mutableListOf<String>();
            var gaps = 0;
            var longest = 0;
            var end = 0
            for ((i, ident) in sequence.withIndex()) {
                val start = result.starts[ident];
                if (start > end) {
                    idle.add("$end-$start");
                    if (i > 0) {
                        gaps++;
                        longest = maxOf(longest, start - end)
                    }
                };
                texts.add("J${instance.operations[ident].job}:$start-${result.completions[ident]}");
                end = result.completions[ident]
            }
            if (end < result.makespan) idle.add("$end-${result.makespan}")
            lines.add("MACHINE M${machine.number} load ${machine.load} idle ${result.makespan - machine.load} utilization ${percent(machine.load, result.makespan)} gaps $gaps longest_gap $longest sequence ${texts.joinToString(" ")}")
            lines.add("IDLE M${machine.number} ${if (idle.isEmpty()) "none" else idle.joinToString(" ")}")
        }
        var waiting = 0
        for (job in instance.jobs) {
            val completion = result.completions[job.operations.last().ident];
            waiting += completion - job.work;
            lines.add("JOB J${job.number} operations ${job.operations.size} work ${job.work} start ${result.starts[job.operations.first().ident]} completion $completion waiting ${completion - job.work}")
        }
        lines.add("TOTAL flow ${result.flow()} waiting $waiting idle ${result.idle()}")
        val others = baselines.map {
            it.schedule
        }
        + ga;
        val distances = others.map {
            distances(result, it)
        };
        var pairsTotal = 0
        for (machine in instance.machines) {
            val count = machine.operations.size;
            val pairs = count * (count - 1) / 2;
            pairsTotal += pairs;
            lines.add("DISTANCE M${machine.number} pairs $pairs " + (0 until 5).joinToString(" ") {
                "${if (it == 4) "GA" else rules[it]} ${distances[it][machine.number - 1]}"
            })
        }
        lines.add("DISTANCE total pairs $pairsTotal " + (0 until 5).joinToString(" ") {
            "${if (it == 4) "GA" else rules[it]} ${distances[it].sum()}"
        })
        return lines
    }
    fun pathLines(): List<String> {
        val lines = mutableListOf("SEARCH start ${search.start} iterations ${params.value("tabu_iterations")} tenure ${params.value("tabu_tenure")}")
        for (iteration in search.records) {
            val first = instance.operations[iteration.move.first];
            val second = instance.operations[iteration.move.second];
            lines.add("ITER ${iteration.number} moves ${iteration.moves} tabu ${iteration.tabu} swap M${first.machine} ${first.code} ${second.code} ${if (iteration.aspiration) "aspiration" else "free"} makespan ${iteration.value} best ${iteration.best}")
        }
        lines.add("STOP iterations ${search.records.size} reason ${search.reason} best ${search.best} found ${search.found}");
        val path = result.path();
        val blocks = result.blocks()
        lines.add("PATH operations ${path.size} blocks ${blocks.size} makespan ${result.makespan} critical_paths ${result.pathCount()}")
        for ((i, ident) in path.withIndex()) {
            val operation = instance.operations[ident];
            val link = if (i == 0) "start" else if (result.machinePrevious[ident] == path[i - 1]) "machine" else "job";
            lines.add("NODE ${i + 1} ${operation.code} M${operation.machine} ${result.starts[ident]}-${result.completions[ident]} $link")
        }
        for ((i, block) in blocks.withIndex()) lines.add("BLOCK ${i + 1} M${instance.operations[block.first()].machine} ${result.starts[block.first()]}-${result.completions[block.last()]} ${block.joinToString(" ") { instance.operations[it].code }}")
        for ((i, move) in result.moves().withIndex()) {
            val first = instance.operations[move.first];
            val second = instance.operations[move.second];
            lines.add("NEIGHBOUR ${i + 1} M${first.machine} ${first.code} ${second.code} makespan ${evaluate(instance, apply(instance, result.order, move), instance.durations)}")
        }
        val (slack, free) = result.slacks();
        lines.add("CRITICAL operations ${slack.count { it == 0 }} total ${instance.operations.size}")
        for ((label, values) in listOf("SLACK" to slack, "FREE" to free)) for (job in instance.jobs) lines.add("$label J${job.number} ${job.operations.joinToString(" ") { values[it.ident].toString() }}")
        val counts = result.pathCounts()
        for (machine in instance.machines) {
            val durations = instance.durations.copyOf();
            var critical = 0;
            for (operation in machine.operations) {
                durations[operation.ident] += (operation.duration + 9) / 10;
                if (slack[operation.ident] == 0) critical++
            };
            val sensitivity = evaluate(instance, result.order, durations);
            lines.add("MACHINE M${machine.number} critical $critical path ${counts[machine.number - 1]} sensitivity $sensitivity delta ${sensitivity - result.makespan}")
        }
        val bottleneck = result.bottleneck();
        lines.add("BOTTLENECK M$bottleneck path ${counts[bottleneck - 1]}")
        return lines
    }
}
private fun write(name: String, lines: List<String>) {
    Files.writeString(Path.of("output", name), lines.joinToString("\n", postfix = "\n"), StandardCharsets.US_ASCII)
}
fun main() {
    val solver = Solver(Instance(), Params());
    solver.solve();
    Files.createDirectories(Path.of("output"))
    write("baselines.txt", solver.baselineLines());
    write("ga_progress.csv", solver.progress);
    write("best_schedule.txt", solver.scheduleLines());
    write("critical_path.txt", solver.pathLines())
}
