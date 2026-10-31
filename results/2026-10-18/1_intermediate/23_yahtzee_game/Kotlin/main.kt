private val categories = listOf(
    "ONES", "TWOS", "THREES", "FOURS", "FIVES", "SIXES", "THREEKIND",
    "FOURKIND", "FULLHOUSE", "SMALL", "LARGE", "YAHTZEE", "CHANCE"
)
private val powers = intArrayOf(1, 6, 36, 216, 1296, 7776)
private val factorial = intArrayOf(1, 1, 2, 6, 24, 120)
private const val CODES = 46656
private val output = System.out.bufferedWriter()

private enum class Strategy { KIND, STRAIGHT, HIGH, UPPER }
private enum class JokerRule { FORCED, FREE, OFF }
private data class Rules(val rolls: Int = 3, val joker: JokerRule = JokerRule.FORCED)
private class CommandError(message: String) : RuntimeException(message)

private fun fail(message: String): Nothing = throw CommandError(message)
private fun emit(line: String) { output.write(line); output.write("\n") }

private fun positive(word: String, maximum: Long): Long {
    if (word[0] !in '1'..'9' || word.any { it !in '0'..'9' }) fail("bad value $word")
    val value = word.toLong()
    if (value > maximum) fail("bad value $word")
    return value
}

private fun validName(word: String) {
    if (word.length > 8 || word.any { it !in 'A'..'Z' }) fail("bad name $word")
}

private fun strategy(word: String): Strategy = Strategy.entries.firstOrNull { it.name == word }
    ?: fail("bad strategy $word")

private fun pattern(word: String): Int {
    if (word.length != 5 || word.any { it != '0' && it != '1' }) fail("bad pattern $word")
    return word.fold(0) { mask, c -> 2 * mask + (c - '0') }
}

private fun fraction(numerator: Long, denominator: Long): String {
    var a = numerator
    var b = denominator
    while (b != 0L) { val rest = a % b; a = b; b = rest }
    val n = numerator / a
    val d = denominator / a
    return if (d == 1L) n.toString() else "$n/$d"
}

private fun average(sum: Long, count: Int): String {
    val value = if (count == 0) 0L else 100L * sum / count
    return "${value / 100}.${(value % 100).toString().padStart(2, '0')}"
}

private fun held(mask: Int, die: Int) = mask and (1 shl (4 - die)) != 0
private fun patternText(mask: Int) = mask.toString(2).padStart(5, '0')
private fun faceText(faces: IntArray, mask: Int) = faces.indices.filter { held(mask, it) }
    .joinToString(" ") { faces[it].toString() }.ifEmpty { "-" }

private fun faceCounts(faces: IntArray): IntArray {
    val counts = IntArray(6)
    for (face in faces) counts[face - 1]++
    return counts
}

private fun decode(code: Int): IntArray {
    var remaining = code
    return IntArray(6) { val count = remaining % 6; remaining /= 6; count }
}

private fun heldCode(faces: IntArray, mask: Int) = faces.indices.filter { held(mask, it) }.sumOf { powers[faces[it] - 1] }

private fun frequent(counts: IntArray): Int {
    var best = 0
    for (i in 1..5) if (counts[i] >= counts[best]) best = i
    return best
}

private fun normalScore(category: Int, counts: IntArray): Int {
    if (category < 6) return (category + 1) * counts[category]
    val sum = counts.indices.sumOf { (it + 1) * counts[it] }
    val maximum = counts.max()
    val bits = counts.indices.filter { counts[it] > 0 }.fold(0) { mask, i -> mask or (1 shl i) }
    return when (category) {
        6 -> if (maximum >= 3) sum else 0
        7 -> if (maximum >= 4) sum else 0
        8 -> if (2 in counts && 3 in counts) 25 else 0
        9 -> if (bits and 15 == 15 || bits and 30 == 30 || bits and 60 == 60) 30 else 0
        10 -> if (bits == 31 || bits == 62) 40 else 0
        11 -> if (maximum == 5) 50 else 0
        else -> sum
    }
}

private class Player(val name: String) {
    var strategy = Strategy.KIND
    val scores = IntArray(13) { -1 }
    var yahtzeeBonus = 0
    fun upper() = (0 until 6).sumOf { scores[it].coerceAtLeast(0) }
    fun upperBonus() = if (upper() >= 63) 35 else 0
    fun total() = scores.sumOf { it.coerceAtLeast(0) } + upperBonus() + yahtzeeBonus
    fun round() = scores.count { it >= 0 } + 1
}

private data class Candidates(val points: IntArray, val allowed: Int, val best: Int, val yahtzeeFace: Int, val joker: Boolean)

private fun evaluate(player: Player, counts: IntArray, rule: JokerRule): Candidates {
    val face = counts.indexOfFirst { it == 5 }
    var allowed = categories.indices.filter { player.scores[it] < 0 }.fold(0) { mask, c -> mask or (1 shl c) }
    val joker = rule != JokerRule.OFF && face >= 0 && player.scores[11] >= 0
    if (joker && rule == JokerRule.FORCED) {
        val upper = 1 shl face
        if (allowed and upper != 0) allowed = upper
        else if (allowed and 0x1fc0 != 0) allowed = allowed and 0x1fc0
    }
    val points = IntArray(13) { -1 }
    var best = -1
    for (c in categories.indices) {
        if (player.scores[c] >= 0) continue
        points[c] = when {
            allowed and (1 shl c) == 0 -> 0
            joker && c in 8..10 -> when (c) { 8 -> 25; 9 -> 30; else -> 40 }
            else -> normalScore(c, counts)
        }
        if (best < 0 || points[c] > points[best]) best = c
    }
    return Candidates(points, allowed, best, face, joker)
}

private data class Outcome(val code: Int, val weight: Int)

private fun makeOutcomes(): List<List<Outcome>> = List(6) { size ->
    buildList {
        fun fill(face: Int, left: Int, code: Int, divisor: Int) {
            if (face == 6) {
                if (left == 0) add(Outcome(code, factorial[size] / divisor))
                return
            }
            for (n in 0..left) fill(face + 1, left - n, code + n * powers[face], divisor * factorial[n])
        }
        fill(0, size, 0, 1)
    }
}

private val outcomes = makeOutcomes()

private data class Turn(val seat: Int = 0, val rolls: Int = 0, val faces: IntArray = IntArray(5), val hold: Int = 0)
private data class ScoreEntry(val before: Turn, val category: Int, val points: Int, val bonus: Int, val joker: Boolean)
private data class RedoEntry(val after: Turn?, val entry: ScoreEntry)

private class Game(seed: Long, names: List<String>, val rules: Rules, val verbose: Boolean) {
    val players = names.map(::Player)
    var randomState = seed
    val faceCounts = LongArray(6)
    val loaded = ArrayDeque<Int>()
    val entries = mutableListOf<ScoreEntry>()
    val redo = ArrayDeque<RedoEntry>()
    var turn: Turn? = Turn()

    fun checkTurn(): Turn = turn ?: fail("game over")

    fun rolled(): Turn {
        val current = checkTurn()
        if (current.rolls == 0) fail("not rolled")
        return current
    }

    fun rollsLeft(): Turn {
        val current = rolled()
        if (current.rolls == rules.rolls) fail("no rolls left")
        return current
    }

    fun roll() {
        val before = checkTurn()
        if (before.rolls == rules.rolls) fail("no rolls left")
        if (before.hold == 31) fail("all dice held")
        redo.clear()
        val faces = before.faces.copyOf()
        for (i in faces.indices) {
            if (before.rolls > 0 && held(before.hold, i)) continue
            faces[i] = loaded.removeFirstOrNull() ?: run {
                randomState = 48271 * randomState % 2147483647
                (randomState % 6 + 1).toInt()
            }
            faceCounts[faces[i] - 1]++
        }
        val current = before.copy(rolls = before.rolls + 1, faces = faces)
        turn = current
        if (verbose) emit("${players[current.seat].name} roll ${current.rolls}: ${faceText(faces, 31)}")
    }

    fun hold(mask: Int) {
        val before = rollsLeft()
        redo.clear()
        turn = before.copy(hold = mask)
        if (verbose) emit("${players[before.seat].name} holds ${patternText(mask)}: ${faceText(before.faces, mask)}")
    }

    fun keep(values: List<Int>) {
        val current = rollsLeft()
        var mask = 0
        for (value in values) {
            val die = current.faces.indices.firstOrNull { !held(mask, it) && current.faces[it] == value }
                ?: fail("not showing $value")
            mask = mask or (1 shl (4 - die))
        }
        hold(mask)
    }

    fun score(category: Int, preview: Boolean = false) {
        val before = rolled()
        val player = players[before.seat]
        if (player.scores[category] >= 0) fail("${categories[category]} already used")
        val candidates = evaluate(player, faceCounts(before.faces), rules.joker)
        if (candidates.allowed and (1 shl category) == 0) {
            val required = if (player.scores[candidates.yahtzeeFace] < 0) categories[candidates.yahtzeeFace] else "lower box"
            fail("joker requires $required")
        }
        val points = candidates.points[category]
        val bonus = if (candidates.yahtzeeFace >= 0 && player.scores[11] == 50) 100 else 0
        val upper = player.upper()
        val gainedUpper = if (category < 6 && upper < 63 && upper + points >= 63) 35 else 0
        if (verbose) emit(buildString {
            append("${player.name} ${if (preview) "would score" else "scores"} $points in ${categories[category]}")
            if (candidates.joker) append(" joker")
            if (bonus != 0) append(" ybonus 100")
            if (gainedUpper != 0) append(" ubonus 35")
            append(" total ${player.total() + points + bonus + gainedUpper}")
        })
        if (preview) return
        redo.clear()
        entries.add(ScoreEntry(before, category, points, bonus, candidates.joker))
        player.scores[category] = points
        player.yahtzeeBonus += bonus
        val next = if (entries.size == 13 * players.size) null else Turn(seat = (before.seat + 1) % players.size)
        turn = next
        if (verbose) {
            if (next == null) emit("game over")
            else emit("turn ${players[next.seat].round()} ${players[next.seat].name}")
        }
    }

    fun undo() {
        if (entries.isEmpty()) fail("nothing to undo")
        val entry = entries.removeAt(entries.lastIndex)
        redo.addLast(RedoEntry(turn, entry))
        val player = players[entry.before.seat]
        player.scores[entry.category] = -1
        player.yahtzeeBonus -= entry.bonus
        turn = entry.before
        emit("undo ${player.name} ${categories[entry.category]} ${entry.points}")
    }

    fun redo() {
        val saved = redo.removeLastOrNull() ?: fail("nothing to redo")
        val entry = saved.entry
        val player = players[entry.before.seat]
        player.scores[entry.category] = entry.points
        player.yahtzeeBonus += entry.bonus
        entries.add(entry)
        turn = saved.after
        emit("redo ${player.name} ${categories[entry.category]} ${entry.points}")
    }

    fun botHold(strategy: Strategy): Int {
        val faces = checkTurn().faces
        val counts = faceCounts(faces)
        val favorite = frequent(counts) + 1
        var mask = 0
        if (strategy == Strategy.STRAIGHT) {
            var bestStart = 0
            var bestLength = 0
            for (start in 0..5) {
                var end = start
                while (end < 6 && counts[end] > 0) end++
                if (end - start >= bestLength) { bestStart = start; bestLength = end - start }
            }
            if (bestLength >= 3) {
                for (face in bestStart + 1..bestStart + bestLength) {
                    mask = mask or (1 shl (4 - faces.indexOf(face)))
                }
                return mask
            }
        }
        for (i in faces.indices) {
            if (if (strategy == Strategy.HIGH) faces[i] >= 5 else faces[i] == favorite) mask = mask or (1 shl (4 - i))
        }
        return mask
    }

    fun botTurn() {
        val player = players[checkTurn().seat]
        val strategy = player.strategy
        if (checkTurn().rolls == 0) roll()
        while (checkTurn().rolls < rules.rolls) {
            val mask = botHold(strategy)
            if (mask == 31) break
            hold(mask)
            roll()
        }
        val counts = faceCounts(checkTurn().faces)
        val candidates = evaluate(player, counts, rules.joker)
        val favorite = frequent(counts)
        val category = if (strategy == Strategy.UPPER && counts[favorite] >= 3 && candidates.allowed and (1 shl favorite) != 0)
            favorite else candidates.best
        score(category)
    }

    fun ranking() = players.indices.sortedWith(compareByDescending<Int> { players[it].total() }.thenBy { it })

    fun odds(mask: Int) {
        val current = rollsLeft()
        val player = players[current.seat]
        val code = heldCode(current.faces, mask)
        val rerolled = 5 - mask.countOneBits()
        val sums = LongArray(13)
        val chances = LongArray(13)
        var best = 0L
        val denominator = powers[rerolled].toLong()
        for (outcome in outcomes[rerolled]) {
            val candidates = evaluate(player, decode(code + outcome.code), rules.joker)
            for (c in categories.indices) if (candidates.points[c] >= 0) {
                sums[c] += outcome.weight.toLong() * candidates.points[c]
                if (candidates.points[c] > 0) chances[c] += outcome.weight
            }
            best += outcome.weight.toLong() * candidates.points[candidates.best]
        }
        emit("odds ${patternText(mask)} outcomes $denominator")
        for (c in categories.indices) if (player.scores[c] < 0) {
            emit("${categories[c]} expect ${fraction(sums[c], denominator)} chance ${fraction(chances[c], denominator)}")
        }
        emit("best expect ${fraction(best, denominator)}")
    }

    fun advise() {
        val current = rollsLeft()
        val depth = rules.rolls - current.rolls
        val adviser = Adviser(players[current.seat], rules.joker, depth)
        var best = -1L
        var chosen = 0
        var denominator = 1L
        repeat(depth) { denominator *= 7776 }
        for (mask in 0..31) {
            val value = adviser.expected(heldCode(current.faces, mask), depth)
            if (value > best) { best = value; chosen = mask }
        }
        emit("advise ${patternText(chosen)}: ${faceText(current.faces, chosen)} expect ${fraction(best, denominator)}")
    }

    fun cardRow(heading: String, cell: (Player) -> String) {
        emit(buildString {
            append(heading.padEnd(9))
            for (player in players) { append(' '); append(cell(player).padStart(maxOf(4, player.name.length))) }
        })
    }

    fun report(command: String) {
        when (command) {
            "STATUS" -> {
                val current = turn
                if (current == null) emit("status game over")
                else {
                    val player = players[current.seat]
                    emit("status round ${player.round()} player ${player.name} rolls ${current.rolls} dice " +
                        "${faceText(current.faces, if (current.rolls == 0) 0 else 31)} holds ${patternText(current.hold)}")
                }
            }
            "CARD" -> {
                cardRow("CATEGORY") { it.name }
                for (c in categories.indices) cardRow(categories[c]) { if (it.scores[c] < 0) "-" else it.scores[c].toString() }
                cardRow("UPPER") { it.upper().toString() }
                cardRow("BONUS") { it.upperBonus().toString() }
                cardRow("YBONUS") { it.yahtzeeBonus.toString() }
                cardRow("TOTAL") { it.total().toString() }
            }
            "BONUS" -> for (player in players) {
                val upper = player.upper()
                val maximum = upper + (0 until 6).filter { player.scores[it] < 0 }.sumOf { 5 * (it + 1) }
                val state = if (upper >= 63) "made" else if (maximum < 63) "lost" else "open"
                emit("bonus ${player.name} upper $upper need ${maxOf(63 - upper, 0)} max $maximum $state")
            }
            "STATS" -> for ((i, player) in players.withIndex()) {
                val saved = entries.filter { it.before.seat == i }
                val rolls = saved.sumOf { it.before.rolls }
                val zeros = saved.count { it.points == 0 }
                val yahtzees = saved.count { entry -> entry.before.faces.all { it == entry.before.faces[0] } }
                val sum = saved.sumOf { it.points.toLong() }
                emit("stats ${player.name} turns ${saved.size} rolls $rolls zeros $zeros yahtzees $yahtzees average ${average(sum, saved.size)}")
            }
            "LOG" -> {
                for ((i, entry) in entries.withIndex()) emit(buildString {
                    append("log ${i + 1} ${players[entry.before.seat].name} ${faceText(entry.before.faces, 31)} ${categories[entry.category]} ${entry.points}")
                    if (entry.joker) append(" joker")
                    if (entry.bonus != 0) append(" ybonus 100")
                })
                if (entries.isEmpty()) emit("no scores")
            }
            "FACES" -> {
                val total = faceCounts.sum()
                val squares = faceCounts.sumOf { it * it }
                emit("faces ${faceCounts.joinToString(" ")} total $total chi2 ${fraction(6 * squares - total * total, maxOf(total, 1))}")
            }
            "STANDINGS" -> {
                val order = ranking()
                val leader = players[order.first()].total()
                for ((rank, i) in order.withIndex()) {
                    val player = players[i]
                    emit("standing ${rank + 1} ${player.name} ${player.total()} behind ${leader - player.total()}")
                }
            }
        }
    }
}

private class Adviser(val player: Player, val joker: JokerRule, depth: Int) {
    private val values = Array(depth + 1) { LongArray(CODES) { -1L } }
    private val expectations = Array(depth + 1) { LongArray(CODES) { -1L } }

    private fun value(code: Int, depth: Int): Long {
        if (values[depth][code] >= 0) return values[depth][code]
        val counts = decode(code)
        val result = if (depth == 0) {
            val candidates = evaluate(player, counts, joker)
            candidates.points[candidates.best].toLong()
        } else searchHolds(counts, 0, 0, depth)
        values[depth][code] = result
        return result
    }

    private fun searchHolds(counts: IntArray, face: Int, code: Int, depth: Int): Long {
        if (face == 6) return expected(code, depth)
        var best = -1L
        for (n in 0..counts[face]) best = maxOf(best, searchHolds(counts, face + 1, code + n * powers[face], depth))
        return best
    }

    fun expected(code: Int, depth: Int): Long {
        if (expectations[depth][code] >= 0) return expectations[depth][code]
        val kept = decode(code).sum()
        var sum = 0L
        for (outcome in outcomes[5 - kept]) sum += outcome.weight * value(code + outcome.code, depth - 1)
        val result = sum * powers[kept]
        expectations[depth][code] = result
        return result
    }
}

private class PlayerRecord(var games: Int = 0, var wins: Int = 0, var best: Int = 0, var sum: Long = 0)

private class Table {
    var game: Game? = null
    var rules = Rules()
    val records = mutableMapOf<String, PlayerRecord>()

    fun requireGame(): Game = game ?: fail("no game")

    fun simulate(seed: Long, count: Int, bots: List<Strategy>) {
        val wins = IntArray(bots.size)
        val sums = LongArray(bots.size)
        val best = IntArray(bots.size)
        val bonus = IntArray(bots.size)
        val yahtzee = IntArray(bots.size)
        val names = listOf("A", "B", "C", "D", "E", "F").take(bots.size)
        var state = seed
        repeat(count) {
            val trial = Game(state, names, rules, false)
            for ((i, bot) in bots.withIndex()) trial.players[i].strategy = bot
            while (trial.turn != null) trial.botTurn()
            state = trial.randomState
            wins[trial.ranking().first()]++
            for ((i, player) in trial.players.withIndex()) {
                val total = player.total()
                sums[i] += total
                best[i] = maxOf(best[i], total)
                if (player.upperBonus() == 35) bonus[i]++
                if (player.scores[11] == 50) yahtzee[i]++
            }
        }
        emit("sim seed $seed games $count players ${bots.size}")
        for ((i, bot) in bots.withIndex()) {
            emit("seat ${i + 1} $bot wins ${wins[i]} average ${average(sums[i], count)} best ${best[i]} bonus ${bonus[i]} yahtzee ${yahtzee[i]}")
        }
    }

    fun execute(words: List<String>) {
        when (words[0]) {
            "RULE" -> {
                val next = when (words[1]) {
                    "ROLLS" -> rules.copy(rolls = positive(words[2], 4).toInt())
                    "JOKER" -> rules.copy(joker = JokerRule.entries.firstOrNull { it.name == words[2] } ?: fail("bad value ${words[2]}"))
                    else -> fail("unknown rule ${words[1]}")
                }
                if (game != null) fail("game in progress")
                rules = next
                emit("rule ${words[1]} ${words[2]}")
            }
            "GAME" -> {
                val seed = positive(words[1], 2147483646)
                val names = words.drop(2)
                names.forEach(::validName)
                if (names.size > 6) fail("too many players")
                if (game != null) fail("game in progress")
                for ((i, name) in names.withIndex()) if ((0 until i).any { names[it] == name }) fail("duplicate name $name")
                game = Game(seed, names, rules, true)
                emit("game seed $seed players ${names.joinToString(" ")}")
                emit("turn 1 ${names.first()}")
            }
            "BOT" -> {
                validName(words[1])
                val bot = strategy(words[2])
                val player = requireGame().players.firstOrNull { it.name == words[1] } ?: fail("no player ${words[1]}")
                player.strategy = bot
                emit("bot ${words[1]} ${words[2]}")
            }
            "LOAD", "KEEP" -> {
                val values = words.drop(1).map { positive(it, 6).toInt() }
                val current = requireGame()
                if (words[0] == "KEEP") current.keep(values)
                else { current.loaded.addAll(values); emit("loaded ${current.loaded.size}") }
            }
            "ROLL" -> requireGame().roll()
            "HOLD", "ODDS" -> {
                val mask = pattern(words[1])
                if (words[0] == "HOLD") requireGame().hold(mask) else requireGame().odds(mask)
            }
            "SCORE", "WHATIF" -> {
                val category = categories.indexOf(words[1])
                if (category < 0) fail("bad category ${words[1]}")
                requireGame().score(category, words[0] == "WHATIF")
            }
            "UNDO" -> requireGame().undo()
            "REDO" -> requireGame().redo()
            "SUGGEST" -> {
                val current = requireGame()
                val turn = current.rolled()
                val candidates = evaluate(current.players[turn.seat], faceCounts(turn.faces), current.rules.joker)
                emit(buildString {
                    append("suggest")
                    for (c in categories.indices) if (candidates.points[c] >= 0) append(" ${categories[c]} ${candidates.points[c]}")
                    append(" best ${categories[candidates.best]} ${candidates.points[candidates.best]}")
                })
            }
            "ADVISE" -> requireGame().advise()
            "AUTO" -> {
                val count = positive(words[1], 100).toInt()
                val current = requireGame()
                current.checkTurn()
                current.redo.clear()
                for (i in 0 until count) { if (current.turn == null) break; current.botTurn() }
            }
            "STATUS", "CARD", "BONUS", "STATS", "LOG", "FACES", "STANDINGS" -> requireGame().report(words[0])
            "END" -> {
                val current = requireGame()
                emit("end ${if (current.turn == null) "final" else "abandoned"}")
                for ((rank, i) in current.ranking().withIndex()) {
                    val player = current.players[i]
                    val total = player.total()
                    emit("rank ${rank + 1} ${player.name} $total")
                    if (current.turn == null) {
                        val record = records.getOrPut(player.name) { PlayerRecord() }
                        record.games++
                        if (rank == 0) record.wins++
                        record.sum += total
                        record.best = maxOf(record.best, total)
                    }
                }
                game = null
            }
            "RECORDS" -> {
                val order = records.entries.sortedWith(compareByDescending<Map.Entry<String, PlayerRecord>> { it.value.wins }
                    .thenByDescending { it.value.best }.thenBy { it.key })
                for ((name, record) in order) {
                    emit("record $name games ${record.games} wins ${record.wins} best ${record.best} average ${average(record.sum, record.games)}")
                }
                if (records.isEmpty()) emit("no records")
            }
            "SIM" -> {
                val seed = positive(words[1], 2147483646)
                val count = positive(words[2], 50).toInt()
                val bots = words.drop(3).map(::strategy)
                if (bots.size > 6) fail("too many players")
                simulate(seed, count, bots)
            }
            else -> fail("unknown command ${words[0]}")
        }
    }
}

fun main() {
    val input = System.`in`.bufferedReader()
    val count = input.readLine().toInt()
    val table = Table()
    repeat(count) {
        try { table.execute(input.readLine().split(' ')) }
        catch (error: CommandError) { emit("error: ${error.message}") }
    }
    output.flush()
}
