import java.util.ArrayDeque
import kotlin.math.abs

private class CommandError(message: String) : RuntimeException(message)
private fun fail(message: String): Nothing = throw CommandError(message)
private fun yes(value: Boolean): String = if (value) "yes" else "no"

private fun gcd(left: Long, right: Long): Long {
    var a = abs(left)
    var b = abs(right)
    while (b != 0L) {
        val remainder = a % b
        a = b
        b = remainder
    }
    return a
}

private data class Fraction private constructor(val numerator: Long, val denominator: Long) : Comparable<Fraction> {
    companion object {
        fun of(numerator: Long, denominator: Long = 1): Fraction {
            val sign = if (denominator < 0) -1 else 1
            val divisor = gcd(numerator, denominator)
            return Fraction(sign * numerator / divisor, sign * denominator / divisor)
        }
    }

    operator fun plus(other: Fraction): Fraction = of(
        numerator * other.denominator + other.numerator * denominator,
        denominator * other.denominator
    )
    operator fun minus(other: Fraction): Fraction = of(
        numerator * other.denominator - other.numerator * denominator,
        denominator * other.denominator
    )
    operator fun times(other: Fraction): Fraction = of(numerator * other.numerator, denominator * other.denominator)
    operator fun div(other: Fraction): Fraction = of(numerator * other.denominator, denominator * other.numerator)
    override fun compareTo(other: Fraction): Int =
        (numerator * other.denominator).compareTo(other.numerator * denominator)
    fun abs(): Fraction = of(abs(numerator), denominator)
    override fun toString(): String = "$numerator/$denominator"

    fun value(): String {
        val decimal = numerator % denominator * 1_000_000 / denominator
        return "$this(${numerator / denominator}.${decimal.toString().padStart(6, '0')})"
    }
}

private val ZERO = Fraction.of(0)
private val ONE = Fraction.of(1)
private val TWO = Fraction.of(2)
private typealias Matrix = Array<Array<Fraction>>

private fun probability(text: String): Fraction {
    val parts = text.split('/')
    val numerator = parts[0].toLong()
    val denominator = parts.getOrNull(1)?.toLong() ?: 1
    if (denominator == 0L || numerator > denominator) fail("BAD PROBABILITY")
    return Fraction.of(numerator, denominator)
}

private fun vector(size: Int): Array<Fraction> = Array(size) { ZERO }
private fun matrix(rows: Int, columns: Int): Matrix = Array(rows) { vector(columns) }
private fun Array<Fraction>.total(): Fraction = fold(ZERO) { sum, value -> sum + value }
private fun Array<Fraction>.text(): String = joinToString(" ")

private fun identity(size: Int): Matrix = matrix(size, size).also { result ->
    for (i in 0 until size) result[i][i] = ONE
}

private fun product(left: Matrix, right: Matrix): Matrix = Array(left.size) { i ->
    Array(right[0].size) { j -> right.indices.fold(ZERO) { sum, k -> sum + left[i][k] * right[k][j] } }
}

private fun eliminate(equations: Matrix): Matrix {
    for (column in equations.indices) {
        var pivotRow = column
        while (equations[pivotRow][column] == ZERO) pivotRow++
        val swapped = equations[column]
        equations[column] = equations[pivotRow]
        equations[pivotRow] = swapped
        val pivot = equations[column][column]
        for (j in equations[column].indices) equations[column][j] = equations[column][j] / pivot
        for (row in equations.indices) {
            if (row == column || equations[row][column] == ZERO) continue
            val factor = equations[row][column]
            for (j in equations[row].indices) {
                equations[row][j] = equations[row][j] - factor * equations[column][j]
            }
        }
    }
    return equations
}

private class Chain(states: List<String>) {
    val states = states.toList()
    val size: Int get() = states.size
    val transition = matrix(size, size)

    fun state(name: String): Int {
        val index = states.indexOf(name)
        if (index < 0) fail("UNKNOWN STATE $name")
        return index
    }

    fun rowSum(row: Int, selected: List<Int>): Fraction =
        selected.fold(ZERO) { sum, column -> sum + transition[row][column] }

    fun targets(names: List<String>): List<Int> {
        val selected = mutableSetOf<Int>()
        for (name in names) {
            val index = state(name)
            if (!selected.add(index)) fail("DUPLICATE STATE $name")
        }
        return selected.sorted()
    }

    fun absorbing(): List<Int> = states.indices.filter { transition[it][it] == ONE }
    fun names(indices: List<Int>, separator: String = " "): String = indices.joinToString(separator) { states[it] }

    fun display(lines: MutableList<String>, values: Matrix = transition, label: String = "ROW") {
        lines.add("STATES ${states.joinToString(" ")}")
        for (i in states.indices) lines.add("$label ${states[i]} ${values[i].text()}")
    }
}

private data class CommunicatingClass(val states: List<Int>, val closed: Boolean, val period: Int)

private class Graph(chain: Chain) {
    val reachable = Array(chain.size) { i -> BooleanArray(chain.size) { j -> i == j || chain.transition[i][j] != ZERO } }
    val classes = mutableListOf<CommunicatingClass>()
    val classOf = IntArray(chain.size) { -1 }
    val levels = IntArray(chain.size)

    init {
        val size = chain.size
        for (k in 0 until size) {
            for (i in 0 until size) {
                for (j in 0 until size) reachable[i][j] = reachable[i][j] || reachable[i][k] && reachable[k][j]
            }
        }
        for (root in 0 until size) {
            if (classOf[root] >= 0) continue
            val states = (0 until size).filter { reachable[root][it] && reachable[it][root] }
            for (state in states) classOf[state] = classes.size
            var closed = true
            val visited = BooleanArray(size)
            val queue = ArrayDeque<Int>()
            queue.addLast(root)
            visited[root] = true
            while (queue.isNotEmpty()) {
                val current = queue.removeFirst()
                for (next in 0 until size) {
                    if (chain.transition[current][next] == ZERO) continue
                    if (next !in states) {
                        closed = false
                    } else if (!visited[next]) {
                        visited[next] = true
                        levels[next] = levels[current] + 1
                        queue.addLast(next)
                    }
                }
            }
            var period = 0L
            for (i in states) {
                for (j in states) {
                    if (chain.transition[i][j] != ZERO) period = gcd(period, levels[i] + 1L - levels[j])
                }
            }
            classes.add(CommunicatingClass(states, closed, period.toInt()))
        }
    }

    fun reaches(source: Int, targets: List<Int>): Boolean = targets.any { reachable[source][it] }
    fun requireIrreducible() {
        if (classes.size != 1) fail("NOT IRREDUCIBLE")
    }
}

private fun stationary(chain: Chain, states: List<Int>): Array<Fraction> {
    val count = states.size
    val equations = matrix(count, count + 1)
    for (i in 0 until count - 1) {
        for (j in 0 until count) equations[i][j] = chain.transition[states[j]][states[i]] - if (i == j) ONE else ZERO
    }
    equations[count - 1].fill(ONE)
    eliminate(equations)
    return vector(chain.size).also { distribution ->
        for (i in states.indices) distribution[states[i]] = equations[i][count]
    }
}

private data class Hitting(val probabilities: Array<Fraction>, val times: Array<Fraction?>)

private fun hitting(chain: Chain, graph: Graph, targets: List<Int>, withTimes: Boolean): Hitting {
    val probabilities = vector(chain.size)
    val times = arrayOfNulls<Fraction>(chain.size)
    for (target in targets) {
        probabilities[target] = ONE
        times[target] = ZERO
    }
    val unknown = chain.states.indices.filter { it !in targets && graph.reaches(it, targets) }
    if (unknown.isNotEmpty()) {
        val count = unknown.size
        val equations = matrix(count, count + 1)
        for (i in unknown.indices) {
            for (j in unknown.indices) equations[i][j] = (if (i == j) ONE else ZERO) - chain.transition[unknown[i]][unknown[j]]
            equations[i][count] = chain.rowSum(unknown[i], targets)
        }
        eliminate(equations)
        for (i in unknown.indices) probabilities[unknown[i]] = equations[i][count]
    }
    if (withTimes) {
        val certain = unknown.filter { probabilities[it] == ONE }
        if (certain.isNotEmpty()) {
            val count = certain.size
            val equations = matrix(count, count + 1)
            for (i in certain.indices) {
                for (j in certain.indices) equations[i][j] = (if (i == j) ONE else ZERO) - chain.transition[certain[i]][certain[j]]
                equations[i][count] = ONE
            }
            eliminate(equations)
            for (i in certain.indices) times[certain[i]] = equations[i][count]
        }
    }
    return Hitting(probabilities, times)
}

private data class Absorption(
    val transient: List<Int>, val absorbing: List<Int>, val fundamental: Matrix,
    val means: Array<Fraction>, val variances: Array<Fraction>, val probabilities: Matrix
)

private fun absorption(chain: Chain): Absorption {
    val absorbing = chain.absorbing()
    val transient = chain.states.indices.filter { it !in absorbing }
    val count = transient.size
    val equations = matrix(count, 2 * count)
    for (i in transient.indices) {
        for (j in transient.indices) equations[i][j] = (if (i == j) ONE else ZERO) - chain.transition[transient[i]][transient[j]]
        equations[i][count + i] = ONE
    }
    eliminate(equations)
    val fundamental = Array(count) { equations[it].copyOfRange(count, 2 * count) }
    val means = Array(count) { fundamental[it].total() }
    val variances = vector(count)
    val probabilities = matrix(count, absorbing.size)
    for (i in transient.indices) {
        var second = ZERO
        for (j in transient.indices) {
            second += (TWO * fundamental[i][j] - if (i == j) ONE else ZERO) * means[j]
        }
        variances[i] = second - means[i] * means[i]
        for (j in absorbing.indices) {
            for (k in transient.indices) probabilities[i][j] = probabilities[i][j] + fundamental[i][k] * chain.transition[transient[k]][absorbing[j]]
        }
    }
    return Absorption(transient, absorbing, fundamental, means, variances, probabilities)
}

private fun build(words: List<String>, lines: MutableList<String>): Chain {
    val order = words[2].toInt()
    val tokens = words.drop(3)
    if (order != 1 && order != 2) fail("BAD ORDER")
    if (tokens.size <= order) fail("TOO FEW TOKENS")
    val states = mutableListOf<String>()
    val observations = mutableListOf<Int>()
    for (i in 0 until tokens.size - order + 1) {
        val name = if (order == 1) tokens[i] else "${tokens[i]}.${tokens[i + 1]}"
        var index = states.indexOf(name)
        if (index < 0) {
            if (states.size == 10) fail("TOO MANY STATES")
            index = states.size
            states.add(name)
        }
        observations.add(index)
    }
    val chain = Chain(states)
    val counts = Array(chain.size) { IntArray(chain.size) }
    val totals = IntArray(chain.size)
    for (i in 0 until observations.size - 1) {
        counts[observations[i]][observations[i + 1]]++
        totals[observations[i]]++
    }
    lines.add("BUILD ${words[1]} order=$order states=${chain.size} transitions=${observations.size - 1}")
    for (i in states.indices) {
        val line = StringBuilder("FROM ${states[i]} total=${totals[i]}")
        if (totals[i] == 0) {
            chain.transition[i][i] = ONE
            line.append(" absorbing")
        } else {
            for (j in states.indices) {
                chain.transition[i][j] = Fraction.of(counts[i][j].toLong(), totals[i].toLong())
                if (counts[i][j] > 0) line.append(" ${states[j]}:${counts[i][j]}")
            }
        }
        lines.add(line.toString())
    }
    return chain
}

private fun gambler(words: List<String>, lines: MutableList<String>): Chain {
    val goal = words[2].toInt()
    val start = words[3].toInt()
    if (goal == 0 || goal > 9) fail("BAD SIZE")
    if (start > goal) fail("BAD START")
    val chance = probability(words[4])
    if (chance == ZERO || chance == ONE) fail("BAD PROBABILITY")
    val chain = Chain((0..goal).map { "s$it" })
    chain.transition[0][0] = ONE
    chain.transition[goal][goal] = ONE
    for (i in 1 until goal) {
        chain.transition[i][i + 1] = chance
        chain.transition[i][i - 1] = ONE - chance
    }
    val result = absorption(chain)
    val ruin = vector(goal + 1)
    val duration = vector(goal + 1)
    ruin[0] = ONE
    for (i in result.transient.indices) {
        ruin[result.transient[i]] = result.probabilities[i][0]
        duration[result.transient[i]] = result.means[i]
    }
    lines.add("GAMBLER ${words[1]} g=$goal p=$chance start=s$start ruin=${ruin[start].value()} duration=${duration[start].value()}")
    for (i in 0..goal) {
        lines.add("CAPITAL s$i ruin=${ruin[i].value()} win=${(ONE - ruin[i]).value()} duration=${duration[i].value()}")
    }
    return chain
}

private fun execute(chains: MutableMap<String, Chain>, words: List<String>): List<String> {
    val command = words[0]
    val name = words[1]
    val lines = mutableListOf<String>()
    when (command) {
        "CHAIN" -> {
            val states = words.drop(2)
            if (states.size > 10) fail("TOO MANY STATES")
            val seen = mutableSetOf<String>()
            for (state in states) if (!seen.add(state)) fail("DUPLICATE STATE $state")
            chains[name] = Chain(states)
            lines.add("CHAIN $name states=${states.size}")
            return lines
        }
        "BUILD" -> {
            chains[name] = build(words, lines)
            return lines
        }
        "GAMBLER" -> {
            chains[name] = gambler(words, lines)
            return lines
        }
    }
    val chain = chains[name] ?: fail("UNKNOWN CHAIN $name")
    val size = chain.size
    val transition = chain.transition
    when (command) {
        "P" -> {
            val from = chain.state(words[2])
            val to = chain.state(words[3])
            val value = probability(words[4])
            transition[from][to] = value
            lines.add("P $name ${words[2]} ${words[3]} $value rowsum=${transition[from].total()}")
            return lines
        }
        "ROW" -> {
            val from = chain.state(words[2])
            if (words.size - 3 != size) fail("BAD LENGTH")
            val row = Array(size) { probability(words[3 + it]) }
            transition[from] = row
            lines.add("ROW $name ${words[2]} rowsum=${row.total()}")
            return lines
        }
        "SHOW" -> {
            lines.add("MATRIX $name states=$size")
            chain.display(lines)
            return lines
        }
        "CHECK" -> {
            val badRows = mutableListOf<String>()
            for (i in 0 until size) {
                val total = transition[i].total()
                if (total != ONE) badRows.add("BADROW ${chain.states[i]} sum=$total")
            }
            lines.add("CHECK $name ${if (badRows.isEmpty()) "ok" else "bad=${badRows.size}"}")
            lines.addAll(badRows)
            return lines
        }
    }
    for (i in 0 until size) if (transition[i].total() != ONE) fail("NOT STOCHASTIC ${chain.states[i]}")
    val graph = Graph(chain)
    when (command) {
        "CLASSES" -> {
            lines.add("CLASSES $name count=${graph.classes.size}")
            for ((index, group) in graph.classes.withIndex()) {
                val kind = if (group.closed) "RECURRENT" else "TRANSIENT"
                lines.add("CLASS ${index + 1} $kind period=${group.period} size=${group.states.size} ${chain.names(group.states)}")
                if (group.period >= 2) {
                    for (remainder in 0 until group.period) {
                        val cyclic = group.states.filter { graph.levels[it] % group.period == remainder }
                        lines.add("CYCLIC $remainder ${chain.names(cyclic)}")
                    }
                }
            }
        }
        "CLASSIFY" -> {
            val absorbing = chain.absorbing()
            val isAbsorbing = absorbing.isNotEmpty() && (0 until size).all { graph.reaches(it, absorbing) }
            val edges = Array(size) { i -> BooleanArray(size) { j -> transition[i][j] != ZERO } }
            var power = edges
            var exponent = 0
            val limit = (size - 1) * (size - 1) + 1
            for (step in 1..limit) {
                if (power.all { row -> row.all { it } }) {
                    exponent = step
                    break
                }
                if (step == limit) break
                power = Array(size) { i -> BooleanArray(size) { j -> (0 until size).any { k -> power[i][k] && edges[k][j] } } }
            }
            val exponentText = if (exponent == 0) "-" else exponent.toString()
            lines.add("CLASSIFY $name absorbing_states=${absorbing.size} absorbing=${yes(isAbsorbing)} " +
                      "ergodic=${yes(graph.classes.size == 1)} regular=${yes(exponent != 0)} exponent=$exponentText")
        }
        "STEP" -> {
            var distribution = vector(size)
            if (words[2][0].isDigit()) {
                val values = words[2].split(',')
                if (values.size != size) fail("BAD LENGTH")
                for (i in 0 until size) distribution[i] = probability(values[i])
                if (distribution.total() != ONE) fail("BAD DISTRIBUTION")
            } else {
                distribution[chain.state(words[2])] = ONE
            }
            val steps = words[3].toInt()
            repeat(steps) {
                val next = vector(size)
                for (j in 0 until size) {
                    for (i in 0 until size) next[j] = next[j] + distribution[i] * transition[i][j]
                }
                distribution = next
            }
            lines.add("STEP $name k=$steps")
            for (i in 0 until size) lines.add("PROB ${chain.states[i]} ${distribution[i].value()}")
        }
        "POWER" -> {
            val steps = words[2].toInt()
            var power = identity(size)
            repeat(steps) { power = product(power, transition) }
            lines.add("POWER $name k=$steps")
            chain.display(lines, power)
        }
        "STATIONARY" -> {
            lines.add("STATIONARY $name count=${graph.classes.count { it.closed }}")
            var distribution = 0
            for ((index, group) in graph.classes.withIndex()) {
                if (!group.closed) continue
                val pi = stationary(chain, group.states)
                lines.add("DIST ${++distribution} class=${index + 1} size=${group.states.size}")
                for (state in group.states) lines.add("PI ${chain.states[state]} ${pi[state].value()}")
            }
        }
        "RECURRENCE" -> {
            val state = chain.state(words[2])
            val group = graph.classes[graph.classOf[state]]
            if (!group.closed) fail("TRANSIENT STATE ${words[2]}")
            val rho = stationary(chain, group.states)[state]
            lines.add("RECURRENCE $name ${words[2]} pi=${rho.value()} mean=${(ONE / rho).value()} period=${group.period}")
        }
        "ABSORB" -> {
            val absorbing = chain.absorbing()
            if (absorbing.isEmpty()) fail("NO ABSORBING STATE")
            for (i in 0 until size) if (!graph.reaches(i, absorbing)) fail("NOT ABSORBING ${chain.states[i]}")
            val result = absorption(chain)
            val count = result.transient.size
            lines.add("ABSORB $name transient=$count absorbing=${absorbing.size}")
            if (count == 0) return lines
            lines.add("TRANSIENT ${chain.names(result.transient)}")
            lines.add("ABSORBING ${chain.names(absorbing)}")
            for (i in 0 until count) lines.add("N ${chain.states[result.transient[i]]} ${result.fundamental[i].text()}")
            for (i in 0 until count) {
                lines.add("STEPS ${chain.states[result.transient[i]]} mean=${result.means[i].value()} var=${result.variances[i].value()}")
            }
            for (i in 0 until count) lines.add("B ${chain.states[result.transient[i]]} ${result.probabilities[i].text()}")
        }
        "HITTING" -> {
            val targets = chain.targets(words.drop(2))
            val result = hitting(chain, graph, targets, true)
            lines.add("HITTING $name targets=${chain.names(targets, ",")}")
            for (i in 0 until size) {
                lines.add("HIT ${chain.states[i]} prob=${result.probabilities[i].value()} time=${result.times[i]?.value() ?: "inf"}")
            }
        }
        "PASSAGE" -> {
            graph.requireIrreducible()
            val pi = stationary(chain, graph.classes.first().states)
            val passage = matrix(size, size)
            for (j in 0 until size) {
                val times = hitting(chain, graph, listOf(j), true).times
                for (i in 0 until size) passage[i][j] = if (i == j) ONE / pi[j] else times[i]!!
            }
            val kemeny = (1 until size).fold(ZERO) { sum, j -> sum + pi[j] * passage[0][j] }
            lines.add("PASSAGE $name kemeny=${kemeny.value()}")
            chain.display(lines, passage, "M")
        }
        "FIRSTPASSAGE" -> {
            val from = chain.state(words[2])
            val target = chain.state(words[3])
            val steps = words[4].toInt()
            if (steps == 0) fail("BAD STEPS")
            var current = Array(size) { transition[it][target] }
            var cumulative = ZERO
            val records = mutableListOf<String>()
            for (step in 1..steps) {
                cumulative += current[from]
                records.add("FP $step ${current[from].value()} cum=${cumulative.value()}")
                if (step == steps) break
                val next = vector(size)
                for (i in 0 until size) {
                    for (j in 0 until size) if (j != target) next[i] = next[i] + transition[i][j] * current[j]
                }
                current = next
            }
            lines.add("FIRSTPASSAGE $name ${words[2]} ${words[3]} k=$steps total=${cumulative.value()}")
            lines.addAll(records)
        }
        "PATHPROB" -> {
            val path = words.drop(2).map(chain::state)
            var chance = ONE
            var zeroAt = 0
            for (i in 1 until path.size) {
                chance *= transition[path[i - 1]][path[i]]
                if (zeroAt == 0 && chance == ZERO) zeroAt = i
            }
            val suffix = if (zeroAt == 0) "" else " zero_at=$zeroAt"
            lines.add("PATHPROB $name steps=${path.size - 1} prob=${chance.value()}$suffix")
        }
        "MOSTLIKELY" -> {
            val start = chain.state(words[2])
            val steps = words[3].toInt()
            if (steps == 0) fail("BAD STEPS")
            val best = matrix(steps + 1, size)
            best[steps].fill(ONE)
            val choices = Array(steps) { IntArray(size) }
            for (step in steps - 1 downTo 0) {
                for (i in 0 until size) {
                    for (j in 0 until size) {
                        val candidate = transition[i][j] * best[step + 1][j]
                        if (candidate > best[step][i]) {
                            best[step][i] = candidate
                            choices[step][i] = j
                        }
                    }
                }
            }
            var current = start
            val path = mutableListOf(current)
            for (step in 0 until steps) {
                current = choices[step][current]
                path.add(current)
            }
            lines.add("MOSTLIKELY $name ${words[2]} k=$steps prob=${best[0][start].value()}")
            lines.add("PATH ${chain.names(path)}")
        }
        "REVERSIBLE" -> {
            graph.requireIrreducible()
            val pi = stationary(chain, graph.classes.first().states)
            val violations = mutableListOf<String>()
            for (i in 0 until size) {
                for (j in i + 1 until size) {
                    val forward = pi[i] * transition[i][j]
                    val backward = pi[j] * transition[j][i]
                    if (forward != backward) {
                        violations.add("VIOLATION ${chain.states[i]} ${chain.states[j]} ${forward.value()} ${backward.value()}")
                    }
                }
            }
            lines.add("REVERSIBLE $name ${if (violations.isEmpty()) "yes" else "no violations=${violations.size}"}")
            lines.addAll(violations)
        }
        "REVERSE" -> {
            graph.requireIrreducible()
            val pi = stationary(chain, graph.classes.first().states)
            val reversed = Chain(chain.states)
            var reversible = true
            for (i in 0 until size) {
                for (j in 0 until size) {
                    reversed.transition[i][j] = pi[j] * transition[j][i] / pi[i]
                    if (reversed.transition[i][j] != transition[i][j]) reversible = false
                }
            }
            chains[words[2]] = reversed
            lines.add("REVERSE $name ${words[2]} reversible=${yes(reversible)}")
            reversed.display(lines)
        }
        "MIXING" -> {
            val steps = words[2].toInt()
            if (steps == 0) fail("BAD STEPS")
            val epsilon = probability(words[3])
            graph.requireIrreducible()
            val pi = stationary(chain, graph.classes.first().states)
            var power = identity(size)
            var mixingTime = 0
            val records = mutableListOf<String>()
            for (step in 1..steps) {
                power = product(power, transition)
                var maximum = ZERO
                var worst = 0
                for (i in 0 until size) {
                    val distance = (0 until size).fold(ZERO) { sum, j -> sum + (power[i][j] - pi[j]).abs() } / TWO
                    if (distance > maximum) {
                        maximum = distance
                        worst = i
                    }
                }
                if (mixingTime == 0 && maximum <= epsilon) mixingTime = step
                records.add("TV $step ${maximum.value()} from=${chain.states[worst]}")
            }
            val timeText = if (mixingTime == 0) "none" else mixingTime.toString()
            lines.add("MIXING $name k=$steps eps=$epsilon time=$timeText")
            lines.addAll(records)
        }
        "LUMP" -> {
            val blocks = mutableListOf<List<Int>>()
            val seen = BooleanArray(size)
            for (group in words[3].split('|')) {
                val block = mutableListOf<Int>()
                for (stateName in group.split(',')) {
                    val state = chain.state(stateName)
                    if (seen[state]) fail("BAD PARTITION")
                    seen[state] = true
                    block.add(state)
                }
                blocks.add(block.sorted())
            }
            if (seen.any { !it }) fail("BAD PARTITION")
            blocks.sortBy { it.first() }
            val lumped = Chain(blocks.map { chain.states[it.first()] })
            for (k in blocks.indices) {
                val representative = blocks[k].first()
                for (l in blocks.indices) {
                    val target = blocks[l]
                    val expected = chain.rowSum(representative, target)
                    lumped.transition[k][l] = expected
                    for (state in blocks[k]) {
                        val actual = if (state == representative) expected else chain.rowSum(state, target)
                        if (actual != expected) {
                            lines.add("LUMP $name not lumpable block=${chain.states[representative]} target=${chain.states[target.first()]} " +
                                      "${chain.states[representative]}=${expected.value()} ${chain.states[state]}=${actual.value()}")
                            return lines
                        }
                    }
                }
            }
            chains[words[2]] = lumped
            lines.add("LUMP $name ${words[2]} blocks=${blocks.size}")
            lumped.display(lines)
        }
        "REWARD" -> {
            if (words.size - 3 != size) fail("BAD LENGTH")
            val discount = probability(words[2])
            if (discount == ONE) fail("BAD DISCOUNT")
            val rewards = Array(size) { Fraction.of(words[3 + it].toLong()) }
            val equations = matrix(size, size + 1)
            for (i in 0 until size) {
                for (j in 0 until size) equations[i][j] = (if (i == j) ONE else ZERO) - discount * transition[i][j]
                equations[i][size] = rewards[i]
            }
            eliminate(equations)
            val gains = vector(size)
            for (group in graph.classes) {
                if (!group.closed) continue
                val rho = stationary(chain, group.states)
                val gain = group.states.fold(ZERO) { sum, state -> sum + rho[state] * rewards[state] }
                val chances = hitting(chain, graph, group.states, false).probabilities
                for (i in 0 until size) gains[i] = gains[i] + chances[i] * gain
            }
            lines.add("REWARD $name gamma=$discount")
            for (i in 0 until size) lines.add("VALUE ${chain.states[i]} discounted=${equations[i][size].value()} gain=${gains[i].value()}")
        }
        "RESTRICT" -> {
            val selected = chain.targets(words.drop(3))
            for (state in selected) {
                for (j in 0 until size) if (j !in selected && transition[state][j] != ZERO) fail("NOT CLOSED ${chain.states[state]}")
            }
            val restricted = Chain(selected.map { chain.states[it] })
            for (i in selected.indices) {
                for (j in selected.indices) restricted.transition[i][j] = transition[selected[i]][selected[j]]
            }
            chains[words[2]] = restricted
            lines.add("RESTRICT $name ${words[2]} states=${selected.size}")
            restricted.display(lines)
        }
        "SIMULATE" -> {
            var current = chain.state(words[2])
            val steps = words[3].toInt()
            val seed = words[4].toLong()
            if (steps == 0) fail("BAD STEPS")
            if (seed == 0L || seed >= 2_147_483_647L) fail("BAD SEED")
            var random = seed
            val path = mutableListOf(current)
            val visits = IntArray(size)
            visits[current]++
            repeat(steps) {
                val row = transition[current]
                var denominator = 1L
                for (value in row) denominator = denominator / gcd(denominator, value.denominator) * value.denominator
                random = 48_271 * random % 2_147_483_647L
                val pick = random % denominator
                var cumulative = ZERO
                for (j in 0 until size) {
                    cumulative += row[j]
                    val boundary = cumulative.numerator * (denominator / cumulative.denominator)
                    if (boundary > pick) {
                        current = j
                        break
                    }
                }
                path.add(current)
                visits[current]++
            }
            lines.add("SIMULATE $name ${words[2]} steps=$steps seed=$seed end=${chain.states[current]}")
            lines.add("PATH ${chain.names(path)}")
            for (i in 0 until size) lines.add("VISIT ${chain.states[i]} ${visits[i]}")
        }
        else -> error(command)
    }
    return lines
}

fun main() {
    val input = System.`in`.bufferedReader()
    val count = input.readLine().toInt()
    val chains = mutableMapOf<String, Chain>()
    val output = StringBuilder()
    repeat(count) {
        val words = input.readLine().split(' ')
        try {
            for (line in execute(chains, words)) output.appendLine(line)
        } catch (error: CommandError) {
            output.appendLine("ERROR ${error.message}")
        }
    }
    print(output)
}
