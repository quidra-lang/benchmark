import java.util.Locale

private enum class Kind { TWO_SIDED, ROOMMATE, HOUSING }
private enum class Side { ANY, PROPOSER, RECEIVER }
private enum class Source { GS, GSR, BOSTON, EGALITARIAN, MINREGRET }
private class CommandError(message: String) : RuntimeException("ERROR $message")
private fun fail(message: String): Nothing = throw CommandError(message)

private data class Agent(val name: String, var preference: List<Int> = emptyList(), var capacity: Int = 1)
private data class Saved(val source: Source, val partners: IntArray)
private data class Run(val partners: IntArray, val count: Int, val history: List<String> = emptyList())
private data class Rotation(val pairs: List<Pair<Int, Int>>)
private data class Candidate(val partners: IntArray, val origin: Int, val via: Int, val cost: Int, val regret: Int)
private data class Lattice(val matchings: List<Candidate>, val rotations: List<Rotation>)

private fun emptyMatching(size: Int) = IntArray(size) { -1 }
private fun listText(values: List<String>) = if (values.isEmpty()) "-" else values.joinToString(" ")

private class Market(
    val name: String,
    val kind: Kind,
    val agents: List<Agent>,
    val proposers: Int = 0,
    val houses: List<String> = emptyList(),
    var current: Saved? = null,
) {
    fun requireKind(expected: Kind) {
        if (kind != expected) fail("WRONG TYPE $name")
    }

    fun findAgent(name: String) = agents.indexOfFirst { it.name == name }

    fun agent(name: String, side: Side = Side.ANY): Int {
        val index = findAgent(name)
        if (index < 0) fail("UNKNOWN AGENT $name")
        if (side == Side.PROPOSER && index >= proposers) fail("NOT PROPOSER $name")
        if (side == Side.RECEIVER && index < proposers) fail("NOT RECEIVER $name")
        return index
    }

    fun rank(a: Int, partner: Int): Int {
        val preference = agents[a].preference
        val index = preference.indexOf(partner)
        return if (index < 0) preference.size + 1 else index + 1
    }

    fun accepts(a: Int, b: Int) = b in agents[a].preference
    fun partnerName(partner: Int) = if (partner < 0) "*" else agents[partner].name
    fun pairs(partners: IntArray) = (0 until proposers).joinToString(" ") { "${agents[it].name}-${partnerName(partners[it])}" }
    fun allocation(allocation: IntArray) = agents.indices.joinToString(" ") {
        "${agents[it].name}-${if (allocation[it] < 0) "*" else houses[allocation[it]]}"
    }

    fun effective(a: Int): List<Int> {
        val preference = agents[a].preference
        val own = preference.indexOf(a)
        return if (own < 0) preference + a else preference.take(own + 1)
    }

    fun save(source: Source, partners: IntArray) {
        current = Saved(source, partners.copyOf())
    }

    fun deferred(reverse: Boolean = false, verbose: Boolean = false): Run {
        val n = agents.size
        val next = IntArray(n)
        val counts = IntArray(n)
        val holding = Array(n) { mutableListOf<Int>() }
        val queue = ArrayDeque<Int>()
        fun able(a: Int) = counts[a] < agents[a].capacity && next[a] < agents[a].preference.size
        for (a in if (reverse) proposers until n else 0 until proposers) if (able(a)) queue.addLast(a)
        var proposals = 0
        val history = mutableListOf<String>()
        while (queue.isNotEmpty()) {
            val x = queue.removeFirst()
            val y = agents[x].preference[next[x]++]
            proposals++
            var action = "REJECT"
            val held = holding[y]
            if (accepts(y, x)) {
                if (held.size < agents[y].capacity) {
                    held.add(x)
                    counts[x]++
                    action = "HOLD"
                } else {
                    val worst = held.indices.maxBy { rank(y, held[it]) }
                    val rejected = held[worst]
                    if (rank(y, x) < rank(y, rejected)) {
                        held[worst] = x
                        counts[rejected]--
                        counts[x]++
                        action = "HOLD REJECT ${agents[rejected].name}"
                        if (able(rejected) && rejected !in queue) queue.addLast(rejected)
                    }
                }
            }
            if (verbose) history.add("PROPOSE ${agents[x].name} ${agents[y].name} $action")
            if (able(x)) queue.addLast(x)
        }
        val partners = emptyMatching(proposers)
        for (y in agents.indices) for (x in holding[y]) {
            if (reverse) partners[y] = x else partners[x] = y
        }
        return Run(partners, proposals, history)
    }

    fun boston(): Run {
        val partners = emptyMatching(proposers)
        val remaining = IntArray(agents.size) { agents[it].capacity }
        val rounds = (0 until proposers).maxOf { agents[it].preference.size }
        var applications = 0
        for (round in 0 until rounds) {
            val applicants = emptyMatching(proposers)
            for (p in 0 until proposers) if (partners[p] < 0 && round < agents[p].preference.size) {
                applicants[p] = agents[p].preference[round]
                applications++
            }
            for (r in proposers until agents.size) for (p in agents[r].preference) {
                if (remaining[r] > 0 && applicants[p] == r) {
                    partners[p] = r
                    remaining[r]--
                }
            }
        }
        return Run(partners, applications)
    }

    fun rotations(partners: IntArray): List<Rotation> {
        val owners = emptyMatching(agents.size)
        val successors = emptyMatching(proposers)
        for (p in 0 until proposers) if (partners[p] >= 0) owners[partners[p]] = p
        for (p in 0 until proposers) {
            if (partners[p] < 0) continue
            for (r in agents[p].preference.drop(rank(p, partners[p]))) {
                if (accepts(r, p) && (owners[r] < 0 || rank(r, p) < rank(r, owners[r]))) {
                    successors[p] = owners[r]
                    break
                }
            }
        }
        val result = mutableListOf<Rotation>()
        val covered = BooleanArray(proposers)
        for (start in 0 until proposers) {
            if (covered[start]) continue
            val seen = BooleanArray(proposers)
            val path = mutableListOf<Int>()
            var p = start
            while (p >= 0 && !seen[p]) {
                seen[p] = true
                path.add(p)
                p = successors[p]
            }
            if (p == start) {
                for (a in path) covered[a] = true
                result.add(Rotation(path.map { it to partners[it] }))
            }
        }
        return result
    }

    fun candidate(partners: IntArray, origin: Int, via: Int): Candidate {
        var cost = 0
        var regret = 0
        for (p in 0 until proposers) if (partners[p] >= 0) {
            val r = partners[p]
            val a = rank(p, r)
            val b = rank(r, p)
            cost += a + b
            regret = maxOf(regret, a, b)
        }
        return Candidate(partners, origin, via, cost, regret)
    }

    fun enumerate(): Lattice {
        if (agents.drop(proposers).any { it.capacity != 1 }) fail("NOT ONE TO ONE")
        val matchings = mutableListOf(candidate(deferred().partners, 0, 0))
        val numbered = mutableListOf<Rotation>()
        var index = 0
        while (index < matchings.size) {
            val partners = matchings[index].partners
            for (rotation in rotations(partners)) {
                var number = numbered.indexOf(rotation)
                if (number < 0) {
                    number = numbered.size
                    numbered.add(rotation)
                }
                val next = partners.copyOf()
                val pairs = rotation.pairs
                for (i in pairs.indices) next[pairs[i].first] = pairs[(i + 1) % pairs.size].second
                if (matchings.any { it.partners.contentEquals(next) }) continue
                if (matchings.size == 50) fail("TOO MANY MATCHINGS")
                matchings.add(candidate(next, index + 1, number + 1))
            }
            index++
        }
        return Lattice(matchings, numbered)
    }

    fun check(words: List<String>): List<String> {
        if (kind == Kind.HOUSING) fail("WRONG TYPE $name")
        val partners = emptyMatching(agents.size)
        val counts = IntArray(agents.size)
        for (word in words.drop(2)) {
            val (left, right) = word.split('-')
            val two = kind == Kind.TWO_SIDED
            val x = agent(left, if (two) Side.PROPOSER else Side.ANY)
            val y = agent(right, if (two) Side.RECEIVER else Side.ANY)
            if (partners[x] >= 0) fail("DUPLICATE AGENT $left")
            if (two) {
                if (++counts[y] > agents[y].capacity) fail("OVER CAPACITY $right")
            } else {
                if (x == y || partners[y] >= 0) fail("DUPLICATE AGENT $right")
                partners[y] = x
            }
            partners[x] = y
        }
        val unacceptable = mutableListOf<Pair<Int, Int>>()
        val blocking = mutableListOf<Pair<Int, Int>>()
        if (kind == Kind.TWO_SIDED) {
            for (p in 0 until proposers) {
                val partner = partners[p]
                if (partner >= 0 && (!accepts(p, partner) || !accepts(partner, p))) unacceptable.add(p to partner)
                for (r in proposers until agents.size) {
                    if (partners[p] == r || !accepts(p, r) || !accepts(r, p) || rank(p, r) >= rank(p, partners[p])) continue
                    val worst = (0 until proposers).filter { partners[it] == r }.maxOfOrNull { rank(r, it) } ?: 0
                    if (counts[r] < agents[r].capacity || rank(r, p) < worst) blocking.add(p to r)
                }
            }
        } else {
            for (a in agents.indices) for (b in a + 1 until agents.size) {
                val mutual = accepts(a, b) && accepts(b, a)
                if (partners[a] == b) {
                    if (!mutual) unacceptable.add(a to b)
                } else if (mutual && rank(a, b) < rank(a, partners[a]) && rank(b, a) < rank(b, partners[b])) blocking.add(a to b)
            }
        }
        if (unacceptable.isEmpty() && blocking.isEmpty()) return listOf("CHECK $name STABLE")
        return buildList {
            add("CHECK $name UNSTABLE unacceptable=${unacceptable.size} blocking=${blocking.size}")
            for ((a, b) in unacceptable) add("UNACCEPTABLE ${agents[a].name} ${agents[b].name}")
            for ((a, b) in blocking) add("BLOCKING ${agents[a].name} ${agents[b].name}")
        }
    }

    fun table(lists: List<List<Int>>) = agents.indices.map { a ->
        "TABLE ${agents[a].name} ${listText(lists[a].map { agents[it].name })}"
    }

    fun roommates(verbose: Boolean): List<String> {
        requireKind(Kind.ROOMMATE)
        val n = agents.size
        for (agent in agents) if (agent.preference.size < n - 1) fail("INCOMPLETE ${agent.name}")
        val lists = agents.map { it.preference.toMutableList() }
        val held = emptyMatching(n)
        val queue = ArrayDeque((0 until n).toList())
        var proposals = 0
        var failure = -1
        while (queue.isNotEmpty()) {
            val x = queue.removeFirst()
            val y = lists[x].first()
            if (held[y] >= 0) queue.addLast(held[y])
            held[y] = x
            proposals++
            val removed = lists[y].drop(lists[y].indexOf(x) + 1)
            for (w in removed) removePair(lists, y, w)
            failure = lists.indexOfFirst { it.isEmpty() }
            if (failure >= 0) break
        }
        val history = mutableListOf<String>()
        var rotations = 0
        if (failure < 0 && verbose) history.addAll(table(lists))
        while (failure < 0) {
            var p = lists.indexOfFirst { it.size >= 2 }
            if (p < 0) break
            val positions = emptyMatching(n)
            val path = mutableListOf<Int>()
            while (positions[p] < 0) {
                positions[p] = path.size
                path.add(p)
                val q = lists[p][1]
                p = lists[q].last()
            }
            val cycle = path.drop(positions[p])
            val front = cycle.map { lists[it].first() }
            rotations++
            val notation = cycle.indices.joinToString(" ") { "${agents[cycle[it]].name}-${agents[front[it]].name}" }
            history.add("ROTATION $rotations $notation")
            val removals = mutableListOf<Pair<Int, Int>>()
            for (i in cycle.indices) {
                val u = front[(i + 1) % front.size]
                for (w in lists[u].drop(lists[u].indexOf(cycle[i]) + 1)) removals.add(u to w)
            }
            for ((a, b) in removals) removePair(lists, a, b)
            if (verbose) history.addAll(table(lists))
            failure = lists.indexOfFirst { it.isEmpty() }
        }
        return buildList {
            add("ROOMMATES $name proposals=$proposals")
            addAll(history)
            if (failure >= 0) add("NO STABLE MATCHING ${agents[failure].name}")
            else add("MATCHING " + agents.indices.filter { it < lists[it].first() }
                .joinToString(" ") { "${agents[it].name}-${agents[lists[it].first()].name}" })
        }
    }

    fun ttc(): List<String> {
        val n = agents.size
        val remaining = BooleanArray(n) { true }
        val effective = agents.indices.map { effective(it) }
        val allocation = emptyMatching(n)
        val history = mutableListOf<String>()
        while (true) {
            val start = remaining.indexOfFirst { it }
            if (start < 0) break
            val points = IntArray(n)
            for (a in agents.indices) if (remaining[a]) points[a] = effective[a].first { remaining[it] }
            val seen = BooleanArray(n)
            var p = start
            while (!seen[p]) { seen[p] = true; p = points[p] }
            val first = p
            val cycle = mutableListOf<String>()
            do {
                allocation[p] = points[p]
                remaining[p] = false
                cycle.add("${agents[p].name}:${houses[points[p]]}")
                p = points[p]
            } while (p != first)
            history.add("CYCLE ${history.size + 1} ${cycle.joinToString(" ")}")
        }
        return listOf("TTC $name cycles=${history.size}") + history + "ALLOCATION ${allocation(allocation)}"
    }

    fun serial(words: List<String>): List<String> {
        val order = mutableListOf<Int>()
        for (name in words.drop(2)) {
            val a = agent(name)
            if (a in order) fail("DUPLICATE AGENT $name")
            order.add(a)
        }
        if (order.size != agents.size) fail("BAD ORDER")
        val taken = BooleanArray(agents.size)
        val allocation = emptyMatching(agents.size)
        for (a in order) {
            val house = agents[a].preference.firstOrNull { !taken[it] } ?: continue
            allocation[a] = house
            taken[house] = true
        }
        val worse = agents.indices.filter { allocation[it] < 0 || allocation[it] !in effective(it) }.map { agents[it].name }
        return listOf("SERIAL $name assigned=${allocation.count { it >= 0 }}", "ALLOCATION ${allocation(allocation)}", "WORSE ${listText(worse)}")
    }

    fun hr(): List<String> {
        val a = deferred().partners
        val h = deferred(reverse = true).partners
        val unmatched = (0 until proposers).filter { a[it] < 0 }.map { agents[it].name }
        val output = mutableListOf("HR $name residents=$proposers hospitals=${agents.size - proposers}",
            "RESIDENT-OPTIMAL ${pairs(a)}", "HOSPITAL-OPTIMAL ${pairs(h)}", "UNMATCHED ${listText(unmatched)}")
        var rural = (0 until proposers).all { (a[it] < 0) == (h[it] < 0) }
        for (r in proposers until agents.size) {
            val first = (0 until proposers).filter { a[it] == r }
            val second = (0 until proposers).filter { h[it] == r }
            val same = first == second
            val capacity = agents[r].capacity
            output.add("HOSPITAL ${agents[r].name} cap=$capacity resident=${first.size} hospital=${second.size} same=${if (same) "YES" else "NO"}")
            rural = rural && first.size == second.size && (first.size == capacity || same)
        }
        output.add(if (rural) "RURAL HOLDS" else "RURAL FAILS")
        return output
    }

    fun manipulate(a: Int): List<String> {
        val truth = agents[a].preference
        val b0 = boston().partners[a]
        val g0 = deferred().partners[a]
        val output = mutableListOf("MANIPULATE $name ${agents[a].name} boston=${partnerName(b0)} gs=${partnerName(g0)} swaps=${maxOf(0, truth.size - 1)}")
        for (i in 0 until truth.size - 1) {
            val trial = Market(name, kind, agents.map { it.copy() }, proposers, houses, current)
            val swapped = truth.toMutableList()
            swapped[i] = truth[i + 1]
            swapped[i + 1] = truth[i]
            trial.agents[a].preference = swapped.toList()
            val b = trial.boston().partners[a]
            val g = trial.deferred().partners[a]
            val swap = "${i + 1} ${agents[truth[i]].name} ${agents[truth[i + 1]].name}"
            if (rank(a, b) < rank(a, b0)) output.add("IMPROVE BOSTON $swap result=${partnerName(b)}")
            if (rank(a, g) < rank(a, g0)) output.add("IMPROVE GS $swap result=${partnerName(g)}")
        }
        if (output.size == 1) output.add("NO IMPROVEMENT")
        return output
    }

    fun stats(): List<String> {
        val saved = current ?: fail("NO MATCHING")
        val sums = IntArray(2)
        val first = IntArray(2)
        val occupied = BooleanArray(agents.size)
        var pairs = 0
        for (p in 0 until proposers) {
            val r = saved.partners[p]
            if (r < 0) continue
            pairs++
            occupied[r] = true
            val ranks = intArrayOf(rank(p, r), rank(r, p))
            for (i in 0..1) { sums[i] += ranks[i]; if (ranks[i] == 1) first[i]++ }
        }
        val unmatched = intArrayOf(proposers - pairs, (proposers until agents.size).count { !occupied[it] })
        val output = mutableListOf("STATS $name source=${saved.source} pairs=$pairs")
        for ((i, label) in listOf("PROPOSERS", "RECEIVERS").withIndex()) {
            var average = "-"
            var truncated = "-"
            if (pairs > 0) {
                val divisor = gcd(sums[i], pairs)
                val cents = 100 * sums[i] / pairs
                average = "${sums[i] / divisor}/${pairs / divisor}"
                truncated = "%d.%02d".format(Locale.ROOT, cents / 100, cents % 100)
            }
            output.add("$label sum=${sums[i]} average=$average truncated=$truncated first=${first[i]} unmatched=${unmatched[i]}")
        }
        return output
    }

    fun show(): List<String> = buildList {
        add(when (kind) {
            Kind.TWO_SIDED -> "SHOW $name MARKET proposers=$proposers receivers=${agents.size - proposers}"
            Kind.ROOMMATE -> "SHOW $name ROOMS agents=${agents.size}"
            Kind.HOUSING -> "SHOW $name HOUSES agents=${agents.size}"
        })
        for ((a, agent) in agents.withIndex()) {
            val prefix = when (kind) {
                Kind.TWO_SIDED -> if (a < proposers) "PROPOSER ${agent.name}" else "RECEIVER ${agent.name} cap=${agent.capacity}"
                Kind.ROOMMATE -> "AGENT ${agent.name}"
                Kind.HOUSING -> "AGENT ${agent.name} house=${houses[a]}"
            }
            val preference = listText(agent.preference.map { if (kind == Kind.HOUSING) houses[it] else agents[it].name })
            add("$prefix $preference")
        }
        if (kind == Kind.TWO_SIDED) add("CURRENT ${current?.source ?: "-"}")
    }
}

private fun removePair(lists: List<MutableList<Int>>, a: Int, b: Int) {
    lists[a].remove(b)
    lists[b].remove(a)
}

private fun gcd(first: Int, second: Int): Int {
    var a = first
    var b = second
    while (b != 0) { val remainder = a % b; a = b; b = remainder }
    return a
}

private class Lab {
    val markets = mutableMapOf<String, Market>()

    fun create(words: List<String>): List<String> {
        val op = words[0]
        val name = words[1]
        if (name in markets) fail("DUPLICATE MARKET $name")
        val kind = when (op) { "ROOMS" -> Kind.ROOMMATE; "HOUSES" -> Kind.HOUSING; else -> Kind.TWO_SIDED }
        if (op == "RANDOM") {
            val n = words[2].toInt()
            val seed = words[3].toLong()
            var state = seed
            val agents = List(2 * n) { Agent("${if (it < n) "P" else "R"}${it % n + 1}") }
            for (a in agents.indices) {
                val preference = MutableList(n) { (if (a < n) n else 0) + it }
                for (i in n downTo 2) {
                    state = 48271L * state % 2147483647L
                    val j = (state % i).toInt()
                    val first = preference[i - 1]
                    preference[i - 1] = preference[j]
                    preference[j] = first
                }
                agents[a].preference = preference.toList()
            }
            markets[name] = Market(name, kind, agents, n)
            return listOf("RANDOM $name n=$n seed=$seed")
        }
        val names = mutableListOf<String>()
        val houses = mutableListOf<String>()
        var proposers = 0
        for (word in words.drop(2)) {
            if (word == "|") { proposers = names.size; continue }
            val pair = if (kind == Kind.HOUSING) word.split(':') else listOf(word)
            if (pair[0] in names) fail("DUPLICATE AGENT ${pair[0]}")
            if (kind == Kind.HOUSING) {
                if (pair[1] in houses) fail("DUPLICATE HOUSE ${pair[1]}")
                houses.add(pair[1])
            }
            names.add(pair[0])
        }
        markets[name] = Market(name, kind, names.map { Agent(it) }, proposers, houses.toList())
        return listOf(if (kind == Kind.TWO_SIDED) "MARKET $name proposers=$proposers receivers=${names.size - proposers}" else "$op $name agents=${names.size}")
    }

    fun execute(line: String): List<String> {
        val words = line.split(' ')
        val op = words[0]
        val name = words[1]
        if (op in setOf("MARKET", "ROOMS", "HOUSES", "RANDOM")) return create(words)
        val market = markets[name] ?: fail("UNKNOWN MARKET $name")
        when (op) {
            "SHOW" -> return market.show()
            "PREF" -> {
                val a = market.agent(words[2])
                val preference = mutableListOf<Int>()
                for (word in words.drop(3)) {
                    val b = if (market.kind == Kind.HOUSING) market.houses.indexOf(word) else market.findAgent(word)
                    if (b < 0 || (market.kind == Kind.TWO_SIDED && (a < market.proposers) == (b < market.proposers))
                        || (market.kind == Kind.ROOMMATE && a == b)) fail("BAD CHOICE $word")
                    if (b in preference) fail("DUPLICATE CHOICE $word")
                    preference.add(b)
                }
                market.agents[a].preference = preference.toList()
                if (market.kind == Kind.TWO_SIDED) market.current = null
                return listOf("PREF $name ${words[2]} length=${preference.size}")
            }
            "CHECK" -> return market.check(words)
            "ROOMMATES" -> return market.roommates(words.size == 3)
            "TTC", "SERIAL" -> {
                market.requireKind(Kind.HOUSING)
                return if (op == "TTC") market.ttc() else market.serial(words)
            }
        }
        market.requireKind(Kind.TWO_SIDED)
        return when (op) {
            "CAPACITY" -> {
                val r = market.agent(words[2], Side.RECEIVER)
                val capacity = words[3].toInt()
                market.agents[r].capacity = capacity
                market.current = null
                listOf("CAPACITY $name ${words[2]} $capacity")
            }
            "GS", "GSR", "BOSTON" -> {
                val result = if (op == "BOSTON") market.boston() else market.deferred(op == "GSR", words.size == 3)
                market.save(Source.valueOf(op), result.partners)
                listOf("$op $name ${if (op == "BOSTON") "applications" else "proposals"}=${result.count}") + result.history + "MATCHING ${market.pairs(result.partners)}"
            }
            "HR" -> market.hr()
            "MANIPULATE" -> market.manipulate(market.agent(words[2], Side.PROPOSER))
            "STATS" -> market.stats()
            "LATTICE", "EGALITARIAN", "MINREGRET" -> {
                val lattice = market.enumerate()
                if (op == "LATTICE") buildList {
                    add("LATTICE $name matchings=${lattice.matchings.size} rotations=${lattice.rotations.size}")
                    for ((i, candidate) in lattice.matchings.withIndex()) {
                        val origin = if (candidate.origin == 0) "-" else candidate.origin.toString()
                        val via = if (candidate.via == 0) "-" else candidate.via.toString()
                        add("MATCHING ${i + 1} from=$origin via=$via cost=${candidate.cost} regret=${candidate.regret} ${market.pairs(candidate.partners)}")
                    }
                    for ((i, rotation) in lattice.rotations.withIndex()) {
                        val notation = rotation.pairs.joinToString(" ") { (p, r) -> "${market.agents[p].name}-${market.agents[r].name}" }
                        add("ROTATION ${i + 1} $notation")
                    }
                } else {
                    val egalitarian = op == "EGALITARIAN"
                    val best = lattice.matchings.indices.minBy { if (egalitarian) lattice.matchings[it].cost else lattice.matchings[it].regret }
                    val selected = lattice.matchings[best]
                    market.save(Source.valueOf(op), selected.partners)
                    val metric = if (egalitarian) "cost=${selected.cost}" else "regret=${selected.regret}"
                    listOf("$op $name matching=${best + 1} $metric", "MATCHING ${market.pairs(selected.partners)}")
                }
            }
            else -> error("Unknown command in well-formed input")
        }
    }
}

fun main() {
    val input = System.`in`.bufferedReader()
    val output = System.out.bufferedWriter()
    val lab = Lab()
    repeat(input.readLine().toInt()) {
        val line = input.readLine()
        try {
            for (row in lab.execute(line)) { output.write(row); output.write("\n") }
        } catch (error: CommandError) { output.write(error.message!!); output.write("\n") }
    }
    output.flush()
}
