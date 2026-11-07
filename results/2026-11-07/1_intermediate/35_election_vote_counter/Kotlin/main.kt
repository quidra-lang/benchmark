import java.util.Locale

private const val LIMIT = 7
private typealias Row = IntArray
private typealias Matrix = Array<IntArray>
private typealias Relation = Array<BooleanArray>

private enum class Kind {
    PLURALITY, RUNOFF, IRV, COOMBS, BUCKLIN, BORDA, BALDWIN, NANSON, BLACK,
    VETO, CONDORCET, COPELAND, MINIMAX, SCHULZE, RANKEDPAIRS, KEMENY, APPROVAL, STV
}
private enum class MinimaxKind { WINNING, MARGIN, OPPOSITION }

private data class Method(val kind: Kind, val parameter: Int = 0, val minimax: MinimaxKind = MinimaxKind.WINNING) {
    val rankable: Boolean get() = kind != Kind.CONDORCET && kind != Kind.STV
    override fun toString(): String = when (kind) {
        Kind.MINIMAX -> "$kind $minimax"
        Kind.APPROVAL, Kind.STV -> "$kind $parameter"
        else -> kind.toString()
    }
    companion object {
        fun parse(words: List<String>, start: Int = 0): Method {
            val kind = Kind.valueOf(words[start])
            return when (kind) {
                Kind.MINIMAX -> Method(kind, minimax = MinimaxKind.valueOf(words[start + 1]))
                Kind.APPROVAL, Kind.STV -> Method(kind, words[start + 1].toInt())
                else -> Method(kind)
            }
        }
    }
}

private val summaryMethods = listOf(
    Kind.PLURALITY, Kind.RUNOFF, Kind.IRV, Kind.COOMBS, Kind.BUCKLIN, Kind.BORDA,
    Kind.BALDWIN, Kind.NANSON, Kind.BLACK, Kind.VETO, Kind.COPELAND, Kind.MINIMAX,
    Kind.SCHULZE, Kind.RANKEDPAIRS, Kind.KEMENY
).map { Method(it) }

private data class Ballot(val votes: Int, val ranking: List<Int>)
private data class Outcome(val order: List<Int>, val lines: List<String>)
private data class Removal(val candidate: Int, val tie: Boolean)
private data class Standing(val order: List<Int>, val tie: Boolean)
private data class Edge(val from: Int, val to: Int)

private class Tallies {
    val first = IntArray(LIMIT)
    val last = IntArray(LIMIT)
    val borda = IntArray(LIMIT)
    val approval = Array(LIMIT) { IntArray(LIMIT) }
    var nonblank = 0
}

private class CommandError(reason: String) : RuntimeException(reason)
private fun bit(a: Int): Int = 1 shl a
private fun members(field: Int): List<Int> = (0 until LIMIT).filter { (field and bit(it)) != 0 }
private fun mask(list: List<Int>): Int = list.fold(0) { field, a -> field or bit(a) }
private fun effective(ranking: List<Int>, field: Int): List<Int> = ranking.filter { (field and bit(it)) != 0 }
private fun sum(field: Int, scores: Row): Int = members(field).sumOf { scores[it] }
private fun majority(field: Int, scores: Row): Boolean {
    val total = sum(field, scores)
    return members(field).any { 2 * scores[it] > total }
}
private fun tieMark(tie: Boolean): String = if (tie) " (tie)" else ""
private fun money(value: Int): String = "%d.%02d".format(Locale.ROOT, value / 100, value % 100)
private fun closure(field: Int, relation: Relation) {
    val list = members(field)
    for (via in list) for (a in list) for (b in list) {
        relation[a][b] = relation[a][b] || relation[a][via] && relation[via][b]
    }
}

private class Election(val number: Int, val names: List<String>) {
    var active = bit(names.size) - 1
    var tiebreak = members(active).sortedBy { names[it] }
        private set
    private val priority = IntArray(LIMIT)
    val groups = mutableListOf<Ballot>()
    val entryEnds = mutableListOf<Int>()
    var total = 0
    private val cache = arrayOfNulls<Tallies>(1 shl LIMIT)
    private var pairs: Matrix? = null

    init { updateTiebreak(tiebreak) }

    fun updateTiebreak(order: List<Int>) {
        order.forEachIndexed { i, a -> priority[a] = i }
        tiebreak = order
    }
    fun candidate(name: String): Int {
        val a = names.indexOf(name)
        if (a < 0) throw CommandError("unknown candidate $name")
        return a
    }
    fun checkedNames(words: List<String>): List<Int> {
        val result = mutableListOf<Int>()
        for (name in words) {
            val a = candidate(name)
            if (a in result) throw CommandError("duplicate candidate $name")
            result.add(a)
        }
        return result
    }
    fun namesText(list: List<Int>, separator: String = ", "): String = list.joinToString(separator) { names[it] }
    fun values(field: Int, scores: Row, cents: Boolean = false): String = members(field).joinToString(", ") {
        "${names[it]} ${if (cents) money(scores[it]) else scores[it].toString()}"
    }
    private fun ordered(field: Int, scores: Row, descending: Boolean = true): MutableList<Int> =
        members(field).sortedWith { a, b ->
            val comparison = if (descending) scores[b].compareTo(scores[a]) else scores[a].compareTo(scores[b])
            if (comparison != 0) comparison else priority[a].compareTo(priority[b])
        }.toMutableList()

    private fun finish(order: List<Int>, tie: Boolean, lines: MutableList<String>): Outcome {
        lines.add("winner: ${names[order.first()]}${tieMark(tie)}")
        return Outcome(order, lines)
    }
    fun invalidate() { cache.fill(null); pairs = null }
    fun finishEntry() { entryEnds.add(groups.size); invalidate() }

    fun tallies(field: Int): Tallies {
        cache[field]?.let { return it }
        val scores = Tallies()
        val candidates = members(field)
        val size = candidates.size
        for (group in groups) {
            val ranking = effective(group.ranking, field)
            val ranked = mask(ranking)
            if (ranking.isNotEmpty()) {
                scores.first[ranking.first()] += group.votes
                scores.nonblank += group.votes
            }
            if (ranking.size == size) scores.last[ranking.last()] += group.votes
            else for (a in candidates) if ((ranked and bit(a)) == 0) scores.last[a] += group.votes
            ranking.forEachIndexed { j, a ->
                scores.borda[a] += group.votes * (size - j - 1)
                for (depth in j until size) scores.approval[depth][a] += group.votes
            }
        }
        cache[field] = scores
        return scores
    }
    fun pairwise(): Matrix {
        pairs?.let { return it }
        val matrix = Array(LIMIT) { IntArray(LIMIT) }
        for (group in groups) {
            val positions = IntArray(LIMIT) { LIMIT }
            group.ranking.forEachIndexed { i, a -> positions[a] = i }
            for (a in names.indices) for (b in names.indices) {
                if (positions[a] < positions[b]) matrix[a][b] += group.votes
            }
        }
        pairs = matrix
        return matrix
    }
    private fun condorcet(field: Int, loser: Boolean = false): Int? {
        val matrix = pairwise()
        val list = members(field)
        return list.firstOrNull { a -> list.all { b ->
            a == b || if (loser) matrix[a][b] < matrix[b][a] else matrix[a][b] > matrix[b][a]
        } }
    }
    private fun lookBack(field: Int, history: List<Row>): Removal {
        val current = history.last()
        val minimum = members(field).minOf { current[it] }
        var choices = members(field).filter { current[it] == minimum }
        val tie = choices.size > 1
        for (i in history.lastIndex - 1 downTo 0) {
            val scores = history[i]
            val low = choices.minOf { scores[it] }
            choices = choices.filter { scores[it] == low }
        }
        return Removal(choices.maxBy { priority[it] }, tie)
    }

    fun elimination(field: Int, coombs: Boolean = false, exhausted: Boolean = false): Outcome {
        var remaining = field
        val removed = mutableListOf<Int>()
        val history = mutableListOf<Row>()
        val lines = mutableListOf<String>()
        while (true) {
            val scores = tallies(remaining)
            val activeVotes = sum(remaining, scores.first)
            var line = "round ${lines.size + 1}: " + if (exhausted)
                "active $activeVotes, exhausted ${total - activeVotes}" else values(remaining, scores.first)
            if (remaining.countOneBits() == 1 || majority(remaining, scores.first)) {
                lines.add(line)
                val order = ordered(remaining, scores.first) + removed.asReversed()
                return if (exhausted) Outcome(order, lines) else finish(order, false, lines)
            }
            val choice = if (coombs) {
                val maximum = members(remaining).maxOf { scores.last[it] }
                val choices = members(remaining).filter { scores.last[it] == maximum }
                line += "; last ${values(remaining, scores.last)}"
                Removal(ordered(mask(choices), scores.first).last(), choices.size > 1)
            } else {
                history.add(scores.first)
                lookBack(remaining, history)
            }
            if (!exhausted) line += "; eliminated ${names[choice.candidate]}${tieMark(choice.tie)}"
            lines.add(line)
            removed.add(choice.candidate)
            remaining = remaining and bit(choice.candidate).inv()
        }
    }
    private fun runoff(field: Int): Outcome {
        val first = tallies(field).first
        val order = ordered(field, first)
        val lines = mutableListOf("round 1: ${values(field, first)}")
        var tie = false
        if (!majority(field, first)) {
            val a = order[0]
            val b = order[1]
            val finalists = bit(a) or bit(b)
            val advanceTie = order.size >= 3 && first[b] == first[order[2]]
            val second = tallies(finalists).first
            tie = second[a] == second[b]
            if (second[b] > second[a]) { order[0] = b; order[1] = a }
            lines.add("finalists: ${namesText(members(finalists))}${tieMark(advanceTie)}")
            lines.add("round 2: ${values(finalists, second)}")
        }
        return finish(order, tie, lines)
    }
    private fun bucklin(field: Int): Outcome {
        val scores = tallies(field)
        val majority = scores.nonblank / 2 + 1
        val lines = mutableListOf("majority: $majority")
        var finalDepth = 0
        val list = members(field)
        for (depth in list.indices) {
            finalDepth = depth
            lines.add("round ${depth + 1}: ${values(field, scores.approval[depth])}")
            if (list.any { scores.approval[depth][it] >= majority }) break
        }
        val order = list.sortedWith { a, b ->
            var comparison = 0
            for (depth in finalDepth downTo 0) {
                comparison = scores.approval[depth][b].compareTo(scores.approval[depth][a])
                if (comparison != 0) break
            }
            if (comparison != 0) comparison else priority[a].compareTo(priority[b])
        }
        return finish(order, scores.approval[finalDepth][order[0]] == scores.approval[finalDepth][order[1]], lines)
    }
    private fun bordaElimination(field: Int, nanson: Boolean): Outcome {
        var remaining = field
        var tail = emptyList<Int>()
        val lines = mutableListOf<String>()
        val history = mutableListOf<Row>()
        while (remaining.countOneBits() >= 2) {
            val scores = tallies(remaining).borda
            var line = "round ${lines.size + 1}: ${values(remaining, scores)}"
            val removed = if (nanson) {
                val total = sum(remaining, scores)
                val below = members(remaining).filter { scores[it] * remaining.countOneBits() < total }
                if (below.isEmpty()) { lines.add(line); break }
                line += "; eliminated ${namesText(below)}"
                ordered(mask(below), scores)
            } else {
                history.add(scores)
                val choice = lookBack(remaining, history)
                line += "; eliminated ${names[choice.candidate]}${tieMark(choice.tie)}"
                listOf(choice.candidate)
            }
            lines.add(line)
            remaining = remaining and mask(removed).inv()
            tail = removed + tail
        }
        val finalOrder = ordered(remaining, IntArray(LIMIT))
        return finish(finalOrder + tail, nanson && finalOrder.size > 1, lines)
    }

    fun pairLines(field: Int, matrix: Matrix): List<String> {
        val list = members(field)
        val lines = mutableListOf<String>()
        for (i in list.indices) for (j in i + 1 until list.size) {
            val a = list[i]
            val b = list[j]
            val result = if (matrix[a][b] == matrix[b][a]) "tie" else names[if (matrix[a][b] > matrix[b][a]) a else b]
            lines.add("${names[a]} vs ${names[b]}: ${matrix[a][b]}-${matrix[b][a]} ($result)")
        }
        return lines
    }
    private fun condorcetReport(field: Int): Outcome {
        val winner = condorcet(field)
        val loser = condorcet(field, true)
        val matrix = pairwise()
        val weak = Array(LIMIT) { BooleanArray(LIMIT) }
        val strong = Array(LIMIT) { BooleanArray(LIMIT) }
        val list = members(field)
        for (a in list) for (b in list) {
            weak[a][b] = matrix[a][b] >= matrix[b][a]
            strong[a][b] = matrix[a][b] > matrix[b][a]
        }
        closure(field, weak)
        closure(field, strong)
        val smith = list.filter { a -> list.all { b -> weak[a][b] } }
        val schwartz = list.filter { a -> list.all { b -> !strong[b][a] || strong[a][b] } }
        return Outcome(emptyList(), listOf(
            "winner: ${winner?.let { names[it] } ?: "NONE"}", "loser: ${loser?.let { names[it] } ?: "NONE"}",
            "smith: ${namesText(smith)}", "schwartz: ${namesText(schwartz)}"
        ))
    }
    private fun topological(field: Int, relation: Relation): Standing {
        var remaining = field
        val order = mutableListOf<Int>()
        var tie = false
        while (remaining != 0) {
            val list = members(remaining)
            val choices = list.filter { a -> list.all { b -> a == b || !relation[b][a] } }
            if (order.isEmpty()) tie = choices.size > 1
            val a = choices.minBy { priority[it] }
            order.add(a)
            remaining = remaining and bit(a).inv()
        }
        return Standing(order, tie)
    }
    private fun schulze(field: Int): Outcome {
        val matrix = pairwise()
        val paths = Array(LIMIT) { IntArray(LIMIT) }
        val list = members(field)
        for (a in list) for (b in list) if (matrix[a][b] > matrix[b][a]) paths[a][b] = matrix[a][b]
        for (via in list) for (a in list) for (b in list) {
            if (a != via && b != via && a != b) paths[a][b] = maxOf(paths[a][b], minOf(paths[a][via], paths[via][b]))
        }
        val relation = Array(LIMIT) { BooleanArray(LIMIT) }
        for (a in list) for (b in list) relation[a][b] = paths[a][b] > paths[b][a]
        val result = topological(field, relation)
        val lines = pairLines(field, paths).toMutableList()
        lines.add("ranking: ${namesText(result.order, " > ")}")
        return finish(result.order, result.tie, lines)
    }
    private fun rankedPairs(field: Int): Outcome {
        val matrix = pairwise()
        val list = members(field)
        val edges = buildList { for (a in list) for (b in list) if (matrix[a][b] > matrix[b][a]) add(Edge(a, b)) }
            .sortedWith(compareBy<Edge>({ -matrix[it.from][it.to] }, { matrix[it.to][it.from] }, { priority[it.from] }, { priority[it.to] }))
        val locked = Array(LIMIT) { BooleanArray(LIMIT) }
        val reached = Array(LIMIT) { BooleanArray(LIMIT) }
        val lines = mutableListOf<String>()
        for ((a, b) in edges) {
            val skip = reached[b][a]
            lines.add("${if (skip) "skip" else "lock"} ${names[a]}>${names[b]} ${matrix[a][b]}-${matrix[b][a]}")
            if (!skip) {
                locked[a][b] = true
                reached[a][b] = true
                closure(field, reached)
            }
        }
        val result = topological(field, locked)
        return finish(result.order, result.tie, lines)
    }
    private fun kemeny(field: Int): Outcome {
        val matrix = pairwise()
        val best = IntArray(1 shl LIMIT)
        val ways = IntArray(1 shl LIMIT)
        val heads = IntArray(1 shl LIMIT)
        ways[0] = 1
        for (subset in 1..field) {
            if ((subset and field.inv()) != 0) continue
            best[subset] = -1
            val list = members(subset)
            for (a in list) {
                val rest = subset and bit(a).inv()
                val score = best[rest] + list.filter { it != a }.sumOf { matrix[a][it] }
                if (score > best[subset]) { best[subset] = score; ways[subset] = 0; heads[subset] = 0 }
                if (score == best[subset]) { ways[subset] += ways[rest]; heads[subset] = heads[subset] or bit(a) }
            }
        }
        val order = mutableListOf<Int>()
        var remaining = field
        while (remaining != 0) {
            val a = tiebreak.first { (heads[remaining] and bit(it)) != 0 }
            order.add(a)
            remaining = remaining and bit(a).inv()
        }
        val lines = mutableListOf("score: ${best[field]}", "optimal: ${ways[field]}", "ranking: ${namesText(order, " > ")}")
        return finish(order, heads[field].countOneBits() > 1, lines)
    }
    private fun stv(field: Int, seats: Int): Outcome {
        val value = IntArray(groups.size) { if (effective(groups[it].ranking, field).isEmpty()) 0 else 100 }
        val owner = IntArray(groups.size)
        val quota = tallies(field).nonblank * 100 / (seats + 1) + 1
        val lines = mutableListOf("quota: ${money(quota)}")
        var continuing = field
        val elected = mutableListOf<Int>()
        val history = mutableListOf<Row>()
        while (true) {
            val scores = IntArray(LIMIT)
            var exhausted = 0
            owner.fill(-1)
            for (i in groups.indices) {
                if (value[i] == 0) continue
                val group = groups[i]
                owner[i] = group.ranking.firstOrNull { (continuing and bit(it)) != 0 } ?: -1
                val amount = group.votes * value[i]
                if (owner[i] < 0) exhausted += amount else scores[owner[i]] += amount
            }
            history.add(scores)
            val line = "round ${history.size}: ${values(continuing, scores, true)}; exhausted ${money(exhausted)}"
            val order = ordered(continuing, scores)
            if (order.size == seats - elected.size) {
                lines.add("$line; elected ${namesText(order)}")
                elected.addAll(order)
                break
            }
            val a = order.first()
            if (scores[a] >= quota) {
                val surplus = scores[a] - quota
                elected.add(a)
                continuing = continuing and bit(a).inv()
                for (i in groups.indices) if (owner[i] == a) value[i] = value[i] * surplus / scores[a]
                lines.add("$line; elected ${names[a]} (surplus ${money(surplus)})")
                if (elected.size == seats) break
            } else {
                val choice = lookBack(continuing, history)
                continuing = continuing and bit(choice.candidate).inv()
                lines.add("$line; excluded ${names[choice.candidate]}${tieMark(choice.tie)}")
            }
        }
        lines.add("elected: ${namesText(elected)}")
        return Outcome(emptyList(), lines)
    }

    fun tally(field: Int, method: Method): Outcome {
        when (method.kind) {
            Kind.RUNOFF -> return runoff(field)
            Kind.IRV, Kind.COOMBS -> return elimination(field, method.kind == Kind.COOMBS)
            Kind.BUCKLIN -> return bucklin(field)
            Kind.BALDWIN, Kind.NANSON -> return bordaElimination(field, method.kind == Kind.NANSON)
            Kind.CONDORCET -> return condorcetReport(field)
            Kind.SCHULZE -> return schulze(field)
            Kind.RANKEDPAIRS -> return rankedPairs(field)
            Kind.KEMENY -> return kemeny(field)
            Kind.STV -> return stv(field, method.parameter)
            else -> Unit
        }
        val base = tallies(field)
        val lines = mutableListOf<String>()
        var label: String? = "scores"
        var descending = true
        var condorcetWinner: Int? = null
        val scores = when (method.kind) {
            Kind.PLURALITY -> { label = "votes"; base.first }
            Kind.BORDA, Kind.BLACK -> {
                if (method.kind == Kind.BLACK) {
                    condorcetWinner = condorcet(field)
                    lines.add("condorcet: ${condorcetWinner?.let { names[it] } ?: "NONE"}")
                }
                base.borda
            }
            Kind.VETO -> { label = "vetoes"; descending = false; base.last }
            Kind.APPROVAL -> { label = "approvals"; base.approval[minOf(method.parameter, field.countOneBits()) - 1] }
            Kind.COPELAND -> {
                val matrix = pairwise()
                val scores = IntArray(LIMIT)
                val list = members(field)
                val descriptions = list.map { a ->
                    var wins = 0
                    var draws = 0
                    var losses = 0
                    for (b in list) if (a != b) {
                        when {
                            matrix[a][b] > matrix[b][a] -> wins++
                            matrix[a][b] == matrix[b][a] -> draws++
                            else -> losses++
                        }
                    }
                    scores[a] = 2 * wins + draws
                    "${names[a]} ${scores[a] / 2}.${scores[a] % 2 * 5} ($wins-$draws-$losses)"
                }
                lines.add("scores: ${descriptions.joinToString(", ")}")
                label = null
                scores
            }
            Kind.MINIMAX -> {
                val matrix = pairwise()
                val scores = IntArray(LIMIT)
                val list = members(field)
                descending = false
                for (a in list) for (b in list) if (a != b) {
                    val opposition = matrix[b][a]
                    val support = matrix[a][b]
                    val value = when {
                        method.minimax == MinimaxKind.OPPOSITION -> opposition
                        opposition <= support -> 0
                        method.minimax == MinimaxKind.MARGIN -> opposition - support
                        else -> opposition
                    }
                    scores[a] = maxOf(scores[a], value)
                }
                scores
            }
            else -> error("unreachable method")
        }
        val order = ordered(field, scores, descending)
        var tie = scores[order[0]] == scores[order[1]]
        condorcetWinner?.let { a ->
            order.remove(a)
            order.add(0, a)
            tie = false
        }
        if (label != null) lines.add("$label: ${values(field, scores)}")
        return finish(order, tie, lines)
    }
    fun ballotsReport(): List<String> {
        val counts = mutableMapOf<String, Int>()
        for (group in groups) {
            val ranking = effective(group.ranking, active)
            val notation = if (ranking.isEmpty()) "-" else namesText(ranking, ">")
            counts[notation] = counts.getOrDefault(notation, 0) + group.votes
        }
        val ranked = counts.keys.sortedWith(compareByDescending<String> { counts.getValue(it) }.thenBy { it })
        return listOf("total $total, blank ${counts.getOrDefault("-", 0)}, distinct ${counts.size}") + ranked.map { "${counts[it]} $it" }
    }
}

private class Lab {
    private var election: Election? = null
    private var number = 0

    fun execute(line: String): List<String> {
        val words = line.split(' ')
        val command = words[0]
        if (command == "CANDIDATES") {
            val names = words.drop(1)
            if (names.size < 2) throw CommandError("too few candidates")
            val seen = mutableSetOf<String>()
            for (name in names) if (!seen.add(name)) throw CommandError("duplicate candidate $name")
            election = Election(++number, names)
            return listOf("election $number: ${names.size} candidates")
        }
        val e = election ?: throw CommandError("no election")
        when (command) {
            "BALLOT" -> {
                val ranking = if (words[2] == "-") emptyList() else e.checkedNames(words[2].split('>'))
                val votes = words[1].toInt()
                e.groups.add(Ballot(votes, ranking))
                e.total += votes
                e.finishEntry()
                return emptyList()
            }
            "RANDOM" -> {
                val count = words[1].toInt()
                var state = words[2].toLong()
                repeat(count) {
                    val ranking = members(e.active).toMutableList()
                    for (i in ranking.lastIndex downTo 1) {
                        state = 48271 * state % 2147483647
                        val j = (state % (i + 1)).toInt()
                        val saved = ranking[i]
                        ranking[i] = ranking[j]
                        ranking[j] = saved
                    }
                    state = 48271 * state % 2147483647
                    val length = (state % ranking.size).toInt() + 1
                    e.groups.add(Ballot(1, ranking.take(length)))
                }
                e.total += count
                e.finishEntry()
                return emptyList()
            }
            "UNDO" -> {
                if (e.entryEnds.isEmpty()) throw CommandError("nothing to undo")
                e.entryEnds.removeAt(e.entryEnds.lastIndex)
                val end = e.entryEnds.lastOrNull() ?: 0
                val removed = e.groups.subList(end, e.groups.size)
                e.total -= removed.sumOf { it.votes }
                removed.clear()
                e.invalidate()
                return emptyList()
            }
            "WITHDRAW", "RESTORE" -> {
                val a = e.candidate(words[1])
                val active = (e.active and bit(a)) != 0
                if (command == "WITHDRAW") {
                    if (!active) throw CommandError("already withdrawn ${words[1]}")
                    if (e.active.countOneBits() <= 2) throw CommandError("too few candidates")
                    e.active = e.active and bit(a).inv()
                } else {
                    if (active) throw CommandError("not withdrawn ${words[1]}")
                    e.active = e.active or bit(a)
                }
                return emptyList()
            }
            "TIEBREAK" -> {
                val order = e.checkedNames(words.drop(1))
                if (order.size != e.names.size) throw CommandError("incomplete tiebreak")
                e.updateTiebreak(order)
                return emptyList()
            }
            "STATUS" -> {
                val withdrawn = members((bit(e.names.size) - 1) and e.active.inv())
                return listOf("[$line]", "election ${e.number}", "active: ${e.namesText(members(e.active))}",
                    "withdrawn: ${if (withdrawn.isEmpty()) "none" else e.namesText(withdrawn)}",
                    "tiebreak: ${e.namesText(e.tiebreak)}", "ballots: ${e.total} in ${e.entryEnds.size} entries")
            }
        }
        if (e.entryEnds.isEmpty()) throw CommandError("no ballots")
        val requested = if (command == "RANKING" || command == "SPOILERS") {
            val method = Method.parse(words, 1)
            if (!method.rankable) throw CommandError("not rankable")
            if (command == "SPOILERS" && e.active.countOneBits() < 3) throw CommandError("too few candidates")
            method
        } else null
        val compared = IntArray(2)
        if (command == "COMPARE") {
            for (i in 0..1) {
                compared[i] = e.candidate(words[i + 1])
                if ((e.active and bit(compared[i])) == 0) throw CommandError("withdrawn candidate ${words[i + 1]}")
            }
            if (compared[0] == compared[1]) throw CommandError("same candidate")
        }
        if (command == "STV" && words[1].toInt() >= e.active.countOneBits()) throw CommandError("too many seats")
        val lines = mutableListOf("[$line]")
        when (command) {
            "RANKING", "SPOILERS" -> {
                val method = requested!!
                val result = e.tally(e.active, method)
                if (command == "RANKING") lines.add(e.namesText(result.order, " > "))
                else {
                    val winner = result.order.first()
                    lines.add("winner: ${e.names[winner]}")
                    for (a in members(e.active)) if (a != winner) {
                        val other = e.tally(e.active and bit(a).inv(), method).order.first()
                        lines.add("without ${e.names[a]}: ${e.names[other]}${if (other != winner) " (changed)" else ""}")
                    }
                }
            }
            "BALLOTS" -> lines.addAll(e.ballotsReport())
            "PROFILE" -> {
                val scores = e.tallies(e.active)
                val size = e.active.countOneBits()
                for (a in members(e.active)) {
                    val counts = (0 until size).joinToString(" ") { j ->
                        (scores.approval[j][a] - if (j == 0) 0 else scores.approval[j - 1][a]).toString()
                    }
                    lines.add("${e.names[a]}: $counts unranked ${e.total - scores.approval[size - 1][a]}")
                }
            }
            "PAIRWISE" -> lines.addAll(e.pairLines(e.active, e.pairwise()))
            "EXHAUSTED" -> lines.addAll(e.elimination(e.active, exhausted = true).lines)
            "SUMMARY", "COMPARE" -> {
                val wins = IntArray(LIMIT)
                val ahead = List(2) { mutableListOf<String>() }
                for (method in summaryMethods) {
                    val result = e.tally(e.active, method)
                    if (command == "SUMMARY") {
                        val winner = result.order.first()
                        wins[winner]++
                        lines.add("$method: ${e.names[winner]}")
                    } else {
                        val side = if (result.order.indexOf(compared[0]) < result.order.indexOf(compared[1])) 0 else 1
                        ahead[side].add(method.toString())
                    }
                }
                if (command == "SUMMARY") lines.add("wins: ${e.values(e.active, wins)}")
                else {
                    val matrix = e.pairwise()
                    val (a, b) = compared
                    lines.add("${e.names[a]} ${matrix[a][b]}, ${e.names[b]} ${matrix[b][a]}, neither ${e.total - matrix[a][b] - matrix[b][a]}")
                    for (i in 0..1) lines.add("${e.names[compared[i]]} ahead: ${if (ahead[i].isEmpty()) "none" else ahead[i].joinToString(", ")}")
                }
            }
            else -> lines.addAll(e.tally(e.active, Method.parse(words)).lines)
        }
        return lines
    }
}

fun main() {
    val input = System.`in`.bufferedReader()
    val output = System.out.bufferedWriter()
    val count = input.readLine().toInt()
    val lab = Lab()
    repeat(count) {
        val line = input.readLine()
        try {
            for (row in lab.execute(line)) { output.write(row); output.write("\n") }
        } catch (error: CommandError) {
            output.write("ERROR ${error.message}\n")
        }
    }
    output.flush()
}
