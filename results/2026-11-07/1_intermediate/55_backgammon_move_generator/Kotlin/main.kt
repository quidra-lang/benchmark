private val colors = listOf("W", "B")
private val results = listOf("single", "gammon", "backgammon", "drop")
private val strategies = setOf("BEST", "FIRST", "RANDOM")

private class Failure(message: String) : RuntimeException(message)

private fun fail(message: String): Nothing = throw Failure(message)

private fun requireValue(valid: Boolean, message: String = "bad arguments") {
    if (!valid) fail(message)
}

private fun number(text: String, low: Int, high: Int, message: String = "bad arguments"): Int {
    requireValue(text.matches(Regex("[0-9]+")), message)
    val n = text.toLongOrNull() ?: fail(message)
    requireValue(n >= low && n <= high, message)
    return n.toInt()
}

private class Position(val men: Array<IntArray> = Array(2) { IntArray(26) }) {
    companion object {
        fun initial(): Position {
            val p = Position()
            for (c in 0..1) {
                p.men[c][24] = 2
                p.men[c][13] = 5
                p.men[c][8] = 3
                p.men[c][6] = 5
            }
            return p
        }
    }

    fun duplicate() = Position(Array(2) { men[it].clone() })

    fun key() = men[0].joinToString(",") + ";" + men[1].joinToString(",")

    fun board(p: Int) = men[0][p] - men[1][25 - p]

    fun opposing(c: Int, p: Int) = men[1 - c][25 - p]

    fun pips(c: Int) = (1..25).sumOf { it * men[c][it] }

    fun keith(c: Int): Int {
        val v = men[c]
        return pips(c) +
            2 * maxOf(v[1] - 1, 0) +
            maxOf(v[2] - 1, 0) +
            maxOf(v[3] - 3, 0) +
            (4..6).count { v[it] == 0 }
    }

    fun rear(c: Int) = (25 downTo 1).find { men[c][it] > 0 } ?: 0

    fun contact() = rear(0) + rear(1) > 25

    fun home(c: Int) = (7..25).all { men[c][it] == 0 }

    fun starts(c: Int) = if (men[c][25] > 0) listOf(25) else (24 downTo 1).filter { men[c][it] > 0 }

    fun move(c: Int, source: Int, die: Int): Outcome? {
        var target = source - die
        var hit = false
        if (target >= 1) {
            if (opposing(c, target) >= 2) return null
            hit = opposing(c, target) == 1
        } else {
            if (!home(c)) return null
            if (target < 0 && (source + 1..6).any { men[c][it] > 0 }) return null
            target = 0
        }
        val after = duplicate()
        after.men[c][source]--
        after.men[c][target]++
        if (hit) {
            after.men[1 - c][25 - target]--
            after.men[1 - c][25]++
        }
        return Outcome(after, target, hit)
    }
}

private data class Outcome(val position: Position, val target: Int, val hit: Boolean)

private data class Move(val source: Int, val target: Int)

private val moveOrder = compareByDescending<Move> { it.source }.thenByDescending { it.target }

private fun point(p: Int) =
    when (p) {
        25 -> "bar"
        0 -> "off"
        else -> p.toString()
    }

private data class Sequence(
    val position: Position,
    val moves: List<Move>,
    val used: List<Int>,
    val hits: Set<Int>,
)

private class Play(s: Sequence) {
    val position = s.position
    val hits = s.hits
    val key = s.moves.sortedWith(moveOrder).toMutableList()
    val notation: String

    init {
        while (true) {
            var first = -1
            var second = -1
            search@ for (i in key.indices) {
                val middle = key[i].target
                if (middle < 1 || middle in hits) continue
                for (j in key.indices) if (key[j].source == middle) {
                    first = i
                    second = j
                    break@search
                }
            }
            if (first < 0) break
            val merged = Move(key[first].source, key[second].target)
            key.removeAt(maxOf(first, second))
            key.removeAt(minOf(first, second))
            key.add(merged)
            key.sortWith(moveOrder)
        }
        val elements = mutableListOf<String>()
        val starred = mutableSetOf<Int>()
        var i = 0
        while (i < key.size) {
            val m = key[i]
            var end = i + 1
            while (end < key.size && key[end] == m) end++
            var text = "${point(m.source)}/${point(m.target)}"
            if (m.target in hits && starred.add(m.target)) text += "*"
            if (end - i >= 2) text += "(${end - i})"
            elements.add(text)
            i = end
        }
        notation = if (elements.isEmpty()) "none" else elements.joinToString(" ")
    }
}

private fun comparePlays(a: Play, b: Play): Int {
    for (i in 0 until minOf(a.key.size, b.key.size)) {
        val result = moveOrder.compare(a.key[i], b.key[i])
        if (result != 0) return result
    }
    return b.key.size.compareTo(a.key.size)
}

private class Generator(position: Position, val color: Int, first: Int, second: Int) {
    val sequences = mutableListOf<Sequence>()
    val shortest = mutableMapOf<String, Int>()
    val maximum: Int
    val plays: List<Play>

    init {
        explore(
            position,
            if (first == second) List(4) { first } else listOf(first, second),
            emptyList(),
            emptyList(),
            emptySet(),
        )
        maximum = sequences.maxOf { it.moves.size }
        val largerRequired =
            maximum == 1 &&
                first != second &&
                sequences.any { it.moves.size == 1 && it.used[0] == maxOf(first, second) }
        val seen = mutableSetOf<String>()
        plays =
            sequences
                .filter {
                    it.moves.size == maximum &&
                        (!largerRequired || it.used[0] == maxOf(first, second)) &&
                        seen.add(it.position.key())
                }
                .map { Play(it) }
                .sortedWith(::comparePlays)
    }

    fun explore(
        p: Position,
        remaining: List<Int>,
        moves: List<Move>,
        used: List<Int>,
        hits: Set<Int>,
    ) {
        val key = p.key()
        shortest[key] = minOf(shortest[key] ?: Int.MAX_VALUE, moves.size)
        sequences.add(Sequence(p, moves, used, hits))
        val tried = mutableSetOf<Int>()
        for (i in remaining.indices) {
            val die = remaining[i]
            if (!tried.add(die)) continue
            val rest = remaining.toMutableList().also { it.removeAt(i) }
            for (source in p.starts(color)) {
                val outcome = p.move(color, source, die) ?: continue
                explore(
                    outcome.position,
                    rest,
                    moves + Move(source, outcome.target),
                    used + die,
                    if (outcome.hit) hits + outcome.target else hits,
                )
            }
        }
    }
}

private fun terms(p: Position, c: Int): IntArray {
    val pip = p.pips(1 - c) - p.pips(c)
    var blots = 0
    var home = 0
    var prime = 0
    var run = 0
    var anchors = 0
    for (point in 1..24) {
        if (p.men[c][point] == 1) {
            val distances =
                (0 until point).filter { p.opposing(c, it) > 0 }.map { point - it }.toSet()
            for (a in 1..6) for (b in 1..6) if (
                a in distances ||
                    b in distances ||
                    a + b in distances ||
                    a == b && (3 * a in distances || 4 * a in distances)
            )
                blots++
        }
        run = if (p.men[c][point] >= 2) run + 1 else 0
        prime = maxOf(prime, run)
        if (p.men[c][point] >= 2 && point <= 6) home++
        if (p.men[c][point] >= 2 && point >= 19) anchors++
    }
    return intArrayOf(pip, blots, home, prime, anchors, p.men[1 - c][25] - p.men[c][25])
}

private fun evaluate(p: Position, c: Int): Int {
    val t = terms(p, c)
    return 2 * t[0] - t[1] + 4 * t[2] + 3 * t[3] + 3 * t[4] + 6 * t[5]
}

private fun result(p: Position, winner: Int): String {
    val loser = p.men[1 - winner]
    if (loser[0] > 0) return "single"
    if (loser[25] > 0 || (19..24).any { loser[it] > 0 }) return "backgammon"
    return "gammon"
}

private fun multiplier(result: String) =
    when (result) {
        "gammon" -> 2
        "backgammon" -> 3
        else -> 1
    }

private class State {
    var position = Position.initial()
    var side = 0
    var cube = 1
    var owner = -1
    var pending = false
    var over = false
    var score = IntArray(2)

    fun duplicate(): State {
        val s = State()
        s.position = position.duplicate()
        s.side = side
        s.cube = cube
        s.owner = owner
        s.pending = pending
        s.over = over
        s.score = score.clone()
        return s
    }

    fun ownerName() = if (owner < 0) "center" else colors[owner]
}

private fun cube(s: State, prohibited: Boolean): String {
    val c = s.side
    if (s.owner == 1 - c || s.cube == 64 || prohibited) return "unavailable"
    if (s.position.contact()) {
        val e = evaluate(s.position, c)
        return if (e < 60) "no double" else if (e <= 100) "double take" else "double drop"
    }
    val v = 8 * s.position.keith(c) - 7 * s.position.keith(1 - c)
    val limit = if (s.owner == -1) 28 else 21
    return if (v > limit) "no double" else if (v >= 14) "double take" else "double drop"
}

private data class Entry(val record: String, val before: State, val after: State)

private var state = State()
private val history = mutableListOf<Entry>()
private val redo = mutableListOf<Entry>()
private val output = StringBuilder()

private fun emit(text: String) {
    output.append(text).append('\n')
}

private fun end(winner: Int, result: String, points: Int) {
    state.over = true
    state.score[winner] += points
    emit("result ${colors[winner]} $result $points")
}

private fun commit(p: Play, first: Int, second: Int) {
    val before = state.duplicate()
    val side = state.side
    state.position = p.position
    if (state.position.men[side][0] == 15) {
        val r = result(state.position, side)
        end(side, r, multiplier(r) * state.cube)
    } else state.side = 1 - side
    history.add(Entry("${colors[side]} $first-$second ${p.notation}", before, state.duplicate()))
    redo.clear()
}

private fun parsePlay(elements: List<String>): List<Move>? {
    if (elements == listOf("none")) return emptyList()
    val moves = mutableListOf<Move>()
    for (element in elements) {
        val match = Regex("(.*)\\(([234])\\)").matchEntire(element)
        val count = match?.groupValues?.get(2)?.toInt() ?: 1
        val path = match?.groupValues?.get(1) ?: element
        val parts = path.split('/')
        if (parts.size < 2) return null
        val points = mutableListOf<Int>()
        for (i in parts.indices) {
            var part = parts[i]
            val point: Int
            if (i == 0 && part == "bar") point = 25
            else if (i > 0 && part == "off") point = 0
            else {
                if (i > 0 && part.endsWith('*')) part = part.dropLast(1)
                if (!part.matches(Regex("[1-9][0-9]?"))) return null
                point = part.toInt()
                if (point > 24) return null
            }
            points.add(point)
        }
        for (i in 1 until points.size) {
            if (points[i - 1] <= points[i]) return null
            repeat(count) { moves.add(Move(points[i - 1], points[i])) }
        }
    }
    return moves
}

private fun play(first: Int, second: Int, elements: List<String>) {
    val moves = parsePlay(elements)
    if (moves == null) {
        emit("ILLEGAL syntax")
        return
    }
    val c = state.side
    val original = state.position
    val after = original.duplicate()
    val destinations = mutableSetOf<Int>()
    for (m in moves) {
        after.men[c][m.source]--
        after.men[c][m.target]++
        if (m.target > 0) destinations.add(m.target)
    }
    for (p in destinations) if (original.opposing(c, p) == 1) {
        after.men[1 - c][25 - p]--
        after.men[1 - c][25]++
    }
    val error =
        when {
            after.men[c].any { it < 0 } -> "no checker"
            after.men[c][25] > 0 && moves.any { it.source != 25 } -> "bar"
            moves.any { it.target > 0 && original.opposing(c, it.target) >= 2 } -> "blocked"
            moves.any { it.target == 0 } && !after.home(c) -> "bear-off"
            else -> null
        }
    if (error != null) {
        emit("ILLEGAL $error")
        return
    }
    val g = Generator(original, c, first, second)
    val key = after.key()
    val found = g.plays.find { it.position.key() == key }
    if (found != null) {
        emit("OK ${found.notation}")
        commit(found, first, second)
        return
    }
    val shortest = g.shortest[key]
    emit(
        "ILLEGAL " +
            if (shortest == null) "impossible"
            else if (shortest < g.maximum) "too few dice" else "larger die required",
    )
}

private fun ranked(plays: List<Play>, c: Int): List<Play> {
    val scores = plays.associateWith { evaluate(it.position, c) }
    return plays.sortedWith { a, b ->
        val comparison = scores.getValue(b).compareTo(scores.getValue(a))
        if (comparison == 0) comparePlays(a, b) else comparison
    }
}

private class Dice(seed: Int) {
    var value = seed.toLong()

    fun next(): Long {
        value = value * 48271 % 2147483647
        return value
    }

    fun roll() = (next() % 6).toInt() + 1
}

private class Game {
    val lines = mutableListOf<String>()
    var plays = 0
    var winner = 0
    var points = 0
    var result = ""

    fun finish(winner: Int, result: String, points: Int) {
        this.winner = winner
        this.result = result
        this.points = points
    }
}

private fun simulate(
    s: State,
    strategies: List<String>,
    dice: Dice,
    opening: List<Int>? = null,
    target: Int = 0,
    matchPoints: IntArray = IntArray(2),
    crawford: Boolean = false,
): Game {
    val game = Game()
    var turn = 1
    while (true) {
        val side = s.side
        val other = 1 - side
        val first: Int
        val second: Int
        if (turn == 1 && opening != null) {
            first = opening[0]
            second = opening[1]
        } else {
            val decision = cube(s, target > 0 && (crawford || matchPoints[side] + s.cube >= target))
            if (decision.startsWith("double"))
                game.lines.add("$turn ${colors[side]} doubles ${2 * s.cube}")
            if (decision == "double drop") {
                game.lines.add("$turn ${colors[other]} drops")
                game.finish(side, "drop", s.cube)
                return game
            }
            if (decision == "double take") {
                game.lines.add("$turn ${colors[other]} takes")
                s.cube *= 2
                s.owner = other
            }
            first = dice.roll()
            second = dice.roll()
        }
        val plays = Generator(s.position, side, first, second).plays
        val chosen =
            when (strategies[side]) {
                "BEST" -> ranked(plays, side).first()
                "FIRST" -> plays.first()
                else -> plays[(dice.next() % plays.size).toInt()]
            }
        s.position = chosen.position
        game.plays++
        game.lines.add("$turn ${colors[side]} $first-$second ${chosen.notation}")
        if (s.position.men[side][0] == 15) {
            val r = result(s.position, side)
            game.finish(side, r, multiplier(r) * s.cube)
            return game
        }
        s.side = other
        turn++
    }
}

private fun positionText() =
    "POS " +
        (1..24).joinToString(",") { state.position.board(it).toString() } +
        " ${state.position.men[0][25]} ${state.position.men[1][25]} ${colors[state.side]}"

private fun boardLine(fields: List<String>) {
    emit(
        fields.take(6).joinToString("") { it.padStart(3) } +
            " |" +
            fields.drop(6).joinToString("") { it.padStart(3) },
    )
}

private fun board() {
    fun row(points: List<Int>, r: Int) {
        boardLine(
            points.map { p ->
                val value = state.position.board(p)
                val count = kotlin.math.abs(value)
                if (count < r) "."
                else if (r == 5 && count > 5) count.toString() else if (value > 0) "W" else "B"
            },
        )
    }
    boardLine((13..24).map { it.toString() })
    for (r in 1..5) row((13..24).toList(), r)
    val status =
        if (state.over) "game over"
        else colors[state.side] + if (state.pending) " doubles" else " to move"
    emit(
        "bar W${state.position.men[0][25]} B${state.position.men[1][25]} | off W${state.position.men[0][0]} B${state.position.men[1][0]} | cube ${state.cube} ${state.ownerName()} | $status",
    )
    for (r in 5 downTo 1) row((12 downTo 1).toList(), r)
    boardLine((12 downTo 1).map { it.toString() })
}

private fun shots() {
    val c = state.side
    val blots = (24 downTo 1).filter { state.position.men[c][it] == 1 }
    val counts = blots.associateWith { 0 }.toMutableMap()
    var total = 0
    val rolls = mutableListOf<String>()
    for (a in 6 downTo 1) for (b in a downTo 1) {
        val plays = Generator(state.position, 1 - c, a, b).plays
        val hit = blots.filter { blot -> plays.any { 25 - blot in it.hits } }
        val weight = if (a == b) 1 else 2
        if (hit.isNotEmpty()) {
            total += weight
            rolls.add("$a-$b")
        }
        for (p in hit) counts[p] = counts.getValue(p) + weight
    }
    emit("shots $total/36" + if (rolls.isEmpty()) "" else " ${rolls.joinToString(" ")}")
    for (p in blots) emit("blot $p ${counts.getValue(p)}/36")
}

private fun execute(words: List<String>) {
    val c = words[0]
    val a = words.drop(1)
    val known =
        setOf(
            "NEW",
            "POS",
            "SHOW",
            "BOARD",
            "PIPS",
            "RACE",
            "MOVES",
            "PLAY",
            "AUTO",
            "HINT",
            "EVAL",
            "SHOTS",
            "CUBE",
            "DOUBLE",
            "TAKE",
            "DROP",
            "RESIGN",
            "SCORE",
            "HISTORY",
            "UNDO",
            "REDO",
            "GAME",
            "MATCH",
            "STATS",
        )
    if (c !in known) fail("unknown command")
    if (c == "POS") {
        requireValue(a.size == 4, "bad position")
        val points = a[0].split(',')
        requireValue(points.size == 24, "bad position")
        val p = Position()
        p.men[0][25] = number(a[1], 0, 15, "bad position")
        p.men[1][25] = number(a[2], 0, 15, "bad position")
        requireValue(a[3] in colors, "bad position")
        for (i in points.indices) {
            requireValue(points[i].matches(Regex("-?[0-9]+")), "bad position")
            val v = points[i].toIntOrNull() ?: fail("bad position")
            requireValue(v in -15..15, "bad position")
            if (v > 0) p.men[0][i + 1] = v else p.men[1][24 - i] = -v
        }
        for (side in 0..1) {
            p.men[side][0] = 15 - p.men[side].sum()
            requireValue(p.men[side][0] in 0..14, "bad position")
        }
        val score = state.score
        state = State()
        state.position = p
        state.side = colors.indexOf(a[3])
        state.score = score
        history.clear()
        redo.clear()
        emit("OK")
        return
    }
    var first = 0
    var second = 0
    var amount = 0
    var seed = 0
    when (c) {
        "MOVES",
        "PLAY",
        "AUTO",
        "HINT" -> {
            requireValue(if (c == "PLAY") a.size >= 3 else a.size == if (c == "HINT") 3 else 2)
            first = number(a[0], 1, 6)
            second = number(a[1], 1, 6)
            if (c == "HINT") amount = number(a[2], 1, 1000)
        }
        "UNDO",
        "REDO" -> {
            requireValue(a.size == 1)
            amount = number(a[0], 1, 1000)
        }
        "RESIGN" -> requireValue(a.size == 1 && a[0] in results.take(3))
        "GAME" -> {
            requireValue(a.size == 3)
            seed = number(a[0], 1, 2147483646)
            requireValue(a[1] in strategies && a[2] in strategies)
        }
        "MATCH",
        "STATS" -> {
            requireValue(a.size == 2)
            amount = number(a[0], 1, if (c == "MATCH") 15 else 50)
            seed = number(a[1], 1, 2147483646)
        }
        else -> requireValue(a.isEmpty())
    }
    if (
        c in
            setOf(
                "RACE",
                "MOVES",
                "PLAY",
                "AUTO",
                "HINT",
                "EVAL",
                "SHOTS",
                "CUBE",
                "DOUBLE",
                "TAKE",
                "DROP",
                "RESIGN",
                "GAME",
            ) && state.over
    )
        fail("game over")
    if (c in setOf("PLAY", "AUTO", "CUBE", "DOUBLE", "RESIGN", "GAME") && state.pending)
        fail("double pending")
    when (c) {
        "NEW" -> {
            val score = state.score
            state = State()
            state.score = score
            history.clear()
            redo.clear()
            emit("OK")
        }
        "SHOW" -> emit(positionText())
        "BOARD" -> board()
        "PIPS" -> emit("pips W ${state.position.pips(0)} B ${state.position.pips(1)}")
        "RACE" ->
            emit(
                if (state.position.contact()) "contact"
                else "race W ${state.position.keith(0)} B ${state.position.keith(1)}",
            )
        "MOVES" -> {
            val plays = Generator(state.position, state.side, first, second).plays
            plays.forEach { emit(it.notation) }
            emit("total ${plays.size}")
        }
        "PLAY" -> play(first, second, a.drop(2))
        "AUTO",
        "HINT" -> {
            val plays =
                ranked(Generator(state.position, state.side, first, second).plays, state.side)
            if (c == "AUTO") {
                val p = plays.first()
                emit("OK ${p.notation} eval ${evaluate(p.position, state.side)}")
                commit(p, first, second)
            } else
                plays.take(amount).forEach {
                    emit("${evaluate(it.position, state.side)} ${it.notation}")
                }
        }
        "EVAL" -> {
            val t = terms(state.position, state.side)
            emit(
                "eval ${evaluate(state.position, state.side)} pips ${t[0]} blots ${t[1]} home ${t[2]} prime ${t[3]} anchors ${t[4]} bar ${t[5]}",
            )
        }
        "SHOTS" -> shots()
        "CUBE" -> emit("cube ${cube(state, false)}")
        "DOUBLE" -> {
            if (state.owner == 1 - state.side || state.cube == 64) fail("cube unavailable")
            state.pending = true
            redo.clear()
            emit("OK double ${2 * state.cube}")
        }
        "TAKE" -> {
            if (!state.pending) fail("no double")
            state.pending = false
            state.cube *= 2
            state.owner = 1 - state.side
            redo.clear()
            emit("OK take ${state.cube} ${state.ownerName()}")
        }
        "DROP" -> {
            if (!state.pending) fail("no double")
            state.pending = false
            redo.clear()
            emit("OK drop")
            end(state.side, "drop", state.cube)
        }
        "RESIGN" -> {
            redo.clear()
            emit("OK resign")
            end(1 - state.side, a[0], multiplier(a[0]) * state.cube)
        }
        "SCORE" -> emit("score W ${state.score[0]} B ${state.score[1]}")
        "HISTORY" -> {
            emit("history ${history.size}")
            history.forEachIndexed { i, e -> emit("${i + 1} ${e.record}") }
        }
        "UNDO" -> {
            if (amount > history.size) fail("cannot undo")
            val index = history.size - amount
            val removed = history.subList(index, history.size).toList()
            state = removed.first().before.duplicate()
            history.subList(index, history.size).clear()
            redo.addAll(0, removed)
            emit("OK")
        }
        "REDO" -> {
            if (amount > redo.size) fail("cannot redo")
            val entries = redo.take(amount)
            redo.subList(0, amount).clear()
            history.addAll(entries)
            state = entries.last().after.duplicate()
            emit("OK")
        }
        "GAME" -> {
            val g = simulate(state.duplicate(), listOf(a[1], a[2]), Dice(seed))
            g.lines.forEach { emit(it) }
            emit("result ${colors[g.winner]} ${g.result} ${g.points}")
        }
        "MATCH",
        "STATS" -> {
            val dice = Dice(seed)
            val points = IntArray(2)
            val counts = Array(4) { IntArray(2) }
            var turns = 0
            var games = 0
            var crawfordPlayed = false
            while (if (c == "MATCH") maxOf(points[0], points[1]) < amount else games < amount) {
                val crawford =
                    c == "MATCH" && !crawfordPlayed && maxOf(points[0], points[1]) == amount - 1
                var white: Int
                var black: Int
                do {
                    white = dice.roll()
                    black = dice.roll()
                } while (white == black)
                val start = State()
                start.side = if (white > black) 0 else 1
                val firstPlayer = start.side
                val g =
                    simulate(
                        start,
                        listOf("BEST", "BEST"),
                        dice,
                        listOf(white, black),
                        if (c == "MATCH") amount else 0,
                        points,
                        crawford,
                    )
                games++
                turns += g.plays
                points[g.winner] += g.points
                counts[results.indexOf(g.result)][g.winner]++
                if (crawford) crawfordPlayed = true
                if (c == "MATCH")
                    emit(
                        "game $games" +
                            (if (crawford) " crawford" else "") +
                            " start ${colors[firstPlayer]} turns ${g.plays} result ${colors[g.winner]} ${g.result} ${g.points} score ${points[0]}-${points[1]}",
                    )
            }
            if (c == "MATCH")
                emit("match ${colors[if (points[0] >= amount) 0 else 1]} ${points[0]}-${points[1]}")
            else {
                for (i in 0..3) emit("${results[i]} W ${counts[i][0]} B ${counts[i][1]}")
                emit("points W ${points[0]} B ${points[1]}")
                emit("turns $turns")
            }
        }
    }
}

fun main() {
    val reader = System.`in`.bufferedReader()
    repeat(reader.readLine().toInt()) {
        try {
            execute(reader.readLine().split(' '))
        } catch (error: Failure) {
            emit("ERROR ${error.message}")
        }
        print(output)
        System.out.flush()
        output.setLength(0)
    }
}
