import kotlin.math.abs

const val SEATS = "NESW"
const val SUITS = "CDSH"
const val RANKS = "23456789TJQKA"
const val TWO_OF_CLUBS = 0
const val JD = 22
const val QS = 36
const val KS = 37
const val AS = 38

val COMMANDS = setOf(
    "RULE", "BOT", "SETTINGS", "GAME", "MATCH", "ROTATE", "NEW", "ABANDON", "STACK", "DEAL",
    "SHOW", "PASS", "PLAY", "AUTO", "UNDO", "CLAIM", "LEGAL", "PREVIEW", "SCORE", "TAKEN",
    "TRICKS", "VOIDS", "UNSEEN", "STATS", "HISTORY", "REPLAY",
)
val BY_RANK = compareBy<Int>({ it % 13 }, { it / 13 })
val BY_RANK_DESCENDING = compareBy<Int>({ -(it % 13) }, { it / 13 })

enum class Strategy { BASIC, LOW, HIGH, SMART, MOON }

enum class State { NONE, BETWEEN, PASSING, PLAYING }

enum class Direction(val offset: Int) {
    LEFT(1),
    RIGHT(3),
    ACROSS(2),
    HOLD(0);

    companion object {
        fun of(code: Char) = entries.first { it.name[0] == code }
    }
}

class CommandError(reason: String) : Exception(reason)

fun fail(reason: String): Nothing = throw CommandError(reason)

fun seatName(seat: Int) = SEATS[seat].toString()

fun cardText(card: Int) = "${RANKS[card % 13]}${SUITS[card / 13]}"

fun cardsText(cards: Iterable<Int>) =
    cards.sorted().joinToString(" ", transform = ::cardText).ifEmpty { "-" }

fun seatValue(word: String): Int {
    if (word.length != 1 || word[0] !in SEATS) fail("bad seat $word")
    return SEATS.indexOf(word[0])
}

fun cardValue(word: String): Int {
    if (word.length != 2 || word[0] !in RANKS || word[1] !in SUITS) fail("bad card $word")
    return SUITS.indexOf(word[1]) * 13 + RANKS.indexOf(word[0])
}

fun strategyValue(word: String) =
    Strategy.entries.find { it.name == word } ?: fail("bad value $word")

fun bounded(word: String, low: Int, high: Int) =
    word.toIntOrNull()?.takeIf { it in low..high } ?: fail("bad value $word")

fun choice(word: String, vararg allowed: String) =
    if (word in allowed) word else fail("bad value $word")

fun switchValue(word: String) = choice(word, "ON", "OFF") == "ON"

fun passValue(word: String) =
    if (word.matches(Regex("[LRAH]{1,8}"))) word else fail("bad value $word")

fun onOff(on: Boolean) = if (on) "ON" else "OFF"

fun lowest(cards: Iterable<Int>) = cards.minWith(BY_RANK)

fun highest(cards: Iterable<Int>) = cards.minWith(BY_RANK_DESCENDING)

fun isPenalty(card: Int) = card == QS || card / 13 == 3

fun countSuit(cards: Iterable<Int>, suit: Int) = cards.count { it / 13 == suit }

fun pairs(label: String, values: List<Any>) =
    label + values.withIndex().joinToString("") { (seat, value) -> " ${SEATS[seat]} $value" }

fun ranking(scores: IntArray) = (0 until 4).sortedBy { scores[it] }

fun checkDistinct(cards: List<Int>) {
    val seen = mutableSetOf<Int>()
    for (card in cards) {
        if (!seen.add(card)) fail("duplicate card ${cardText(card)}")
    }
}

fun averageText(total: Int, games: Int): String {
    val cents = (100 * total).floorDiv(games)
    val sign = if (cents < 0) "-" else ""
    return "$sign${abs(cents) / 100}.${(abs(cents) % 100).toString().padStart(2, '0')}"
}

class Generator(var state: Long) {
    fun draw(): Long {
        state = 48271 * state % 2147483647
        return state
    }

    fun shuffle(deck: MutableList<Int>) {
        for (i in deck.lastIndex downTo 1) {
            val j = (draw() % (i + 1)).toInt()
            deck[i] = deck[j].also { deck[j] = deck[i] }
        }
    }
}

data class Rules(
    val target: Int = 100,
    val limit: Int = 100,
    val moon: String = "ADD",
    val jack: Boolean = false,
    val qsBreak: Boolean = false,
    val blood: Boolean = false,
    val pass: String = "LRAH",
) {
    fun withRule(name: String, word: String) = when (name) {
        "TARGET" -> copy(target = bounded(word, 1, 1000))
        "LIMIT" -> copy(limit = bounded(word, 1, 100))
        "MOON" -> copy(moon = choice(word, "ADD", "SUB", "AUTO"))
        "JACK" -> copy(jack = switchValue(word))
        "QSBREAK" -> copy(qsBreak = switchValue(word))
        "BLOOD" -> copy(blood = switchValue(word))
        "PASS" -> copy(pass = passValue(word))
        else -> fail("unknown rule $name")
    }

    fun text() = "rules TARGET $target LIMIT $limit MOON $moon JACK ${onOff(jack)} " +
        "QSBREAK ${onOff(qsBreak)} BLOOD ${onOff(blood)} PASS $pass"
}

data class Stats(
    val tricks: Int = 0,
    val hearts: Int = 0,
    val queens: Int = 0,
    val moons: Int = 0,
) {
    operator fun plus(other: Stats) = Stats(
        tricks + other.tricks,
        hearts + other.hearts,
        queens + other.queens,
        moons + other.moons,
    )

    fun text() = "tricks $tricks hearts $hearts queens $queens moons $moons"
}

data class Play(val seat: Int, val card: Int)

data class LogLine(val level: Int, val text: String)

class HandRecord(
    val number: Int,
    val direction: Direction,
    val points: List<Int>,
    val shooter: Int?,
    val record: List<String>,
)

class Snapshot(val round: Round, val logLength: Int, val play: Play)

fun trickWinner(plays: List<Play>): Int {
    val led = plays[0].card / 13
    return plays.filter { it.card / 13 == led }.maxBy { it.card % 13 }.seat
}

fun playsText(plays: List<Play>) =
    plays.joinToString(" ") { "${seatName(it.seat)} ${cardText(it.card)}" }

// Everything that UNDO restores when a played card is taken back.
class Round(
    val hands: List<MutableSet<Int>> = List(4) { mutableSetOf() },
    val taken: List<MutableSet<Int>> = List(4) { mutableSetOf() },
    val tricks: MutableList<List<Play>> = mutableListOf(),
    val trickCounts: IntArray = IntArray(4),
    var current: MutableList<Play> = mutableListOf(),
    var leader: Int = 0,
    var broken: Boolean = false,
    val record: MutableList<String> = mutableListOf(),
) {
    fun copy() = Round(
        hands.map { it.toMutableSet() },
        taken.map { it.toMutableSet() },
        tricks.toMutableList(),
        trickCounts.copyOf(),
        current.toMutableList(),
        leader,
        broken,
        record.toMutableList(),
    )
}

class Game(val rules: Rules, val bots: Array<Strategy>, val generator: Generator) {
    var state = State.BETWEEN
    var number = 0
    var direction = Direction.HOLD
    val scores = IntArray(4)
    val stats = Array(4) { Stats() }
    val stacked = mutableMapOf<Int, Set<Int>>()
    val passes = mutableMapOf<Int, List<Int>>()
    var round = Round()
    val undoStack = ArrayDeque<Snapshot>()
    val history = mutableListOf<HandRecord>()
    val log = mutableListOf<LogLine>()

    fun copy() = Game(rules, bots, Generator(generator.state)).also {
        it.state = state
        it.number = number
        it.direction = direction
        scores.copyInto(it.scores)
        stats.copyInto(it.stats)
        it.stacked += stacked
        it.passes += passes
        it.round = round.copy()
        it.undoStack += undoStack
        it.history += history
        it.log += log
    }

    fun point(card: Int) = when {
        card == QS -> 13
        card / 13 == 3 -> 1
        card == JD && rules.jack -> -10
        else -> 0
    }

    fun points(cards: Iterable<Int>) = cards.sumOf(::point)

    fun trickPoints(plays: List<Play>) = plays.sumOf { point(it.card) }

    fun write(level: Int, line: String) {
        log += LogLine(level, line)
        if (level > 0) round.record += line
    }

    fun deal() {
        number++
        direction = Direction.of(rules.pass[(number - 1) % rules.pass.length])
        round = Round()
        val used = stacked.values.flatten().toSet()
        val deck = (0 until 52).filter { it !in used }.toMutableList()
        generator.shuffle(deck)
        val free = (0 until 4).filter { it !in stacked }
        for ((seat, cards) in stacked) round.hands[seat] += cards
        deck.forEachIndexed { i, card -> round.hands[free[i % free.size]] += card }
        stacked.clear()
        passes.clear()
        undoStack.clear()
        write(1, "hand $number pass $direction")
        for (seat in 0 until 4) write(2, "${seatName(seat)}: ${cardsText(round.hands[seat])}")
        if (direction == Direction.HOLD) beginPlay() else state = State.PASSING
    }

    fun beginPlay() {
        state = State.PLAYING
        round.leader = (0 until 4).first { TWO_OF_CLUBS in round.hands[it] }
        write(2, "lead ${seatName(round.leader)}")
    }

    fun passCards(seat: Int, cards: List<Int>) {
        round.hands[seat] -= cards.toSet()
        passes[seat] = cards
        write(2, "${seatName(seat)} passes ${cardsText(cards)}")
        if (passes.size == 4) {
            for ((source, passed) in passes) round.hands[(source + direction.offset) % 4] += passed
            beginPlay()
        }
    }

    fun actor() = (round.leader + round.current.size) % 4

    fun legal(): Set<Int> {
        val hand = round.hands[actor()]
        if (round.current.isEmpty()) {
            if (round.tricks.isEmpty()) return setOf(TWO_OF_CLUBS)
            val nonHearts = hand.filter { it / 13 != 3 }.toSet()
            return if (!round.broken && nonHearts.isNotEmpty()) nonHearts else hand.toSet()
        }
        val suit = round.current[0].card / 13
        val followers = hand.filter { it / 13 == suit }.toSet()
        if (followers.isNotEmpty()) return followers
        if (round.tricks.isEmpty() && !rules.blood) {
            val safe = hand.filterNot(::isPenalty).toSet()
            if (safe.isNotEmpty()) return safe
        }
        return hand.toSet()
    }

    fun choosePass(seat: Int): List<Int> {
        val hand = round.hands[seat]
        val low = hand.sortedWith(BY_RANK)
        val high = hand.sortedWith(BY_RANK_DESCENDING)
        val hearts = high.filter { it / 13 == 3 }
        val special = listOf(QS, KS, AS).filter { it in hand }
        val order = when (bots[seat]) {
            Strategy.LOW -> high
            Strategy.HIGH -> low
            Strategy.MOON -> low.filter { it / 13 != 3 } + low.filter { it / 13 == 3 }
            Strategy.SMART -> {
                val isProtected = QS in hand && countSuit(hand, 2) >= 5
                val shortSuit = listOf(0, 1)
                    .filter { countSuit(hand, it) > 0 }
                    .minByOrNull { countSuit(hand, it) }
                val shortCards = high.filter { it / 13 == shortSuit }
                (if (isProtected) emptyList() else special) + shortCards + hearts + high
            }
            Strategy.BASIC -> special + hearts + high
        }
        return order.distinct().take(3)
    }

    fun queenPlayed() = round.taken.any { QS in it } || round.current.any { it.card == QS }

    fun othersTookPenalty(seat: Int) =
        (0 until 4).any { it != seat && round.taken[it].any(::isPenalty) }

    fun choosePlay(): Int {
        val seat = actor()
        val hand = round.hands[seat]
        val playable = legal()
        var strategy = bots[seat]
        if (strategy == Strategy.LOW) return lowest(playable)
        if (strategy == Strategy.HIGH) return highest(playable)
        if (strategy == Strategy.MOON && othersTookPenalty(seat)) strategy = Strategy.BASIC
        if (round.current.isEmpty()) {
            if (strategy == Strategy.SMART && !queenPlayed() && QS !in hand) {
                val smallSpades = playable.filter { it / 13 == 2 && it % 13 < 10 }
                if (smallSpades.isNotEmpty()) return lowest(smallSpades)
            }
            val suits = playable.map { it / 13 }.distinct().sorted()
            if (strategy == Strategy.MOON) {
                val suit = suits.maxBy { countSuit(playable, it) }
                return highest(playable.filter { it / 13 == suit })
            }
            val suit = suits.minBy { countSuit(playable, it) }
            return lowest(playable.filter { it / 13 == suit })
        }
        val led = round.current[0].card / 13
        if (countSuit(hand, led) > 0) {
            val winning = round.current.filter { it.card / 13 == led }.maxOf { it.card % 13 }
            if (strategy == Strategy.MOON) {
                val high = highest(playable)
                return if (high % 13 > winning) high else lowest(playable)
            }
            val lower = playable.filter { it % 13 < winning }
            if (lower.isNotEmpty()) return highest(lower)
            if (strategy == Strategy.SMART && round.current.size == 3) {
                val withoutQueen = playable - QS
                return if (withoutQueen.isEmpty()) QS else highest(withoutQueen)
            }
            return lowest(playable)
        }
        if (strategy == Strategy.MOON) {
            val safe = playable.filterNot(::isPenalty)
            return lowest(safe.ifEmpty { playable })
        }
        if (QS in playable) return QS
        if (strategy == Strategy.SMART && !queenPlayed()) {
            if (AS in playable) return AS
            if (KS in playable) return KS
        }
        val hearts = playable.filter { it / 13 == 3 }
        return highest(hearts.ifEmpty { playable })
    }

    fun trickLine(plays: List<Play>, number: Int) = "trick $number: ${playsText(plays)} -> " +
        "${seatName(trickWinner(plays))} ${trickPoints(plays)}"

    fun play(card: Int) {
        val seat = actor()
        undoStack.addLast(Snapshot(round.copy(), log.size, Play(seat, card)))
        round.hands[seat] -= card
        round.current.add(Play(seat, card))
        if (card / 13 == 3 || card == QS && rules.qsBreak) round.broken = true
        if (round.current.size == 4) {
            val winner = trickWinner(round.current)
            round.taken[winner] += round.current.map { it.card }
            round.trickCounts[winner]++
            round.tricks.add(round.current)
            write(2, trickLine(round.current, round.tricks.size))
            round.current = mutableListOf()
            round.leader = winner
            if (round.tricks.size == 13) finishHand()
        }
    }

    fun undoCard(): Play {
        val snapshot = undoStack.removeLast()
        round = snapshot.round
        log.subList(snapshot.logLength, log.size).clear()
        return snapshot.play
    }

    fun claim(seat: Int) {
        val remaining = round.hands.flatten()
        round.hands.forEach { it.clear() }
        val count = 13 - round.tricks.size
        round.taken[seat] += remaining
        round.trickCounts[seat] += count
        write(2, "claim ${seatName(seat)} tricks $count points ${points(remaining)}")
        finishHand()
    }

    fun gameOver(totals: IntArray) = number >= rules.limit || totals.max() >= rules.target

    fun finishHand() {
        val handPoints = IntArray(4) { points(round.taken[it]) }
        val shooter = (0 until 4).firstOrNull { round.taken[it].count(::isPenalty) == 14 }
        if (shooter != null) {
            handPoints[shooter] -= 26
            var method = rules.moon
            if (method == "AUTO") {
                val added = IntArray(4) {
                    scores[it] + handPoints[it] + if (it == shooter) 0 else 26
                }
                method = if (gameOver(added) && ranking(added)[0] != shooter) "SUB" else "ADD"
            }
            if (method == "SUB") {
                handPoints[shooter] -= 26
            } else {
                for (seat in 0 until 4) {
                    if (seat != shooter) handPoints[seat] += 26
                }
            }
            write(1, "moon ${seatName(shooter)} $method")
        }
        for (seat in 0 until 4) {
            val cards = round.taken[seat]
            scores[seat] += handPoints[seat]
            stats[seat] += Stats(
                round.trickCounts[seat],
                countSuit(cards, 3),
                if (QS in cards) 1 else 0,
                if (shooter == seat) 1 else 0,
            )
        }
        write(1, pairs("points", handPoints.asList()))
        write(1, pairs("scores", scores.asList()))
        history +=
            HandRecord(number, direction, handPoints.asList(), shooter, round.record.toList())
        val over = gameOver(scores)
        state = if (over) State.NONE else State.BETWEEN
        if (over) {
            write(0, "game over hands $number")
            ranking(scores).forEachIndexed { place, seat ->
                write(0, "rank ${place + 1} ${seatName(seat)} ${scores[seat]}")
            }
            statsLines().forEach { write(0, it) }
        }
    }

    fun statsLines() = (0 until 4).map { "stats ${seatName(it)} ${stats[it].text()}" }

    fun autoPass() {
        for (seat in 0 until 4) {
            if (seat !in passes) passCards(seat, choosePass(seat))
        }
    }

    fun autoHand() {
        if (state == State.PASSING) autoPass()
        while (state == State.PLAYING) play(choosePlay())
    }

    fun autoGame() {
        if (state == State.PASSING || state == State.PLAYING) autoHand()
        while (state != State.NONE) {
            deal()
            autoHand()
        }
    }
}

class Table {
    private var rules = Rules()
    private val bots = Array(4) { Strategy.BASIC }
    private var game: Game? = null

    private fun activeGame() = game?.takeIf { it.state != State.NONE }

    private fun requireGame() = activeGame() ?: fail("no game")

    private fun requireHand() = activeGame()
        ?.takeIf { it.state == State.PASSING || it.state == State.PLAYING }
        ?: fail("no hand")

    private fun requirePlaying() =
        activeGame()?.takeIf { it.state == State.PLAYING } ?: fail("not playing")

    private fun requirePassing() =
        activeGame()?.takeIf { it.state == State.PASSING } ?: fail("not passing")

    private fun requireBetween(): Game {
        val game = requireGame()
        if (game.state != State.BETWEEN) fail("hand in progress")
        return game
    }

    private fun simulate(command: String, seed: Int, count: Int): List<String> {
        val generator = Generator(seed.toLong())
        if (command == "GAME") {
            val game = Game(rules, bots, generator)
            game.autoGame()
            return listOf("game seed $seed") + game.log.filter { it.level <= count }.map { it.text }
        }
        val rounds = if (command == "ROTATE") 4 else 1
        val places = Array(4) { IntArray(4) }
        val totals = IntArray(4)
        val stats = Array(4) { Stats() }
        var hands = 0
        for (rotation in 0 until rounds) {
            val strategies = Array(4) { bots[(it - rotation).mod(4)] }
            repeat(count) {
                val game = Game(rules, strategies, generator)
                game.autoGame()
                hands += game.number
                val order = ranking(game.scores)
                for (original in 0 until 4) {
                    val actual = (original + rotation) % 4
                    places[original][order.indexOf(actual)]++
                    totals[original] += game.scores[actual]
                    stats[original] += game.stats[actual]
                }
            }
        }
        val games = rounds * count
        val output = mutableListOf("${command.lowercase()} seed $seed games $games hands $hands")
        for (seat in 0 until 4) {
            val name = seatName(seat) + if (command == "ROTATE") " ${bots[seat]}" else ""
            output += "$name places ${places[seat].joinToString(" ")} total ${totals[seat]} " +
                "average ${averageText(totals[seat], games)} ${stats[seat].text()}"
        }
        return output
    }

    fun command(words: List<String>): List<String> {
        val name = words[0]
        val args = words.drop(1)
        if (name !in COMMANDS) fail("unknown command $name")
        return when (name) {
            "RULE" -> {
                val changed = rules.withRule(args[0], args[1])
                if (activeGame() != null) fail("game in progress")
                rules = changed
                listOf("rule ${args[0]} ${args[1]}")
            }
            "BOT" -> {
                val seat = seatValue(args[0])
                bots[seat] = strategyValue(args[1])
                listOf("bot ${seatName(seat)} ${args[1]}")
            }
            "SETTINGS" -> listOf(rules.text(), pairs("bots", bots.asList()))
            "GAME", "MATCH", "ROTATE" -> {
                val seed = bounded(args[0], 1, 2147483646)
                val count = when (name) {
                    "GAME" -> bounded(args[1], 0, 2)
                    "MATCH" -> bounded(args[1], 1, 50)
                    else -> bounded(args[1], 1, 10)
                }
                simulate(name, seed, count)
            }
            "NEW" -> {
                val seed = bounded(args[0], 1, 2147483646)
                if (activeGame() != null) fail("game in progress")
                game = Game(rules, bots, Generator(seed.toLong()))
                listOf("new game seed $seed")
            }
            "ABANDON" -> {
                requireGame()
                game = null
                listOf("game abandoned")
            }
            else -> tableCommand(name, args)
        }
    }

    private fun tableCommand(name: String, args: List<String>): List<String> {
        // Validate argument words before any state-dependent checks or mutation.
        val seat = if (name in listOf("STACK", "PASS", "PLAY", "CLAIM")) seatValue(args[0]) else -1
        val cards =
            if (name in listOf("STACK", "PASS", "PLAY")) args.drop(1).map(::cardValue) else listOf()
        if (name == "STACK" && cards.size != 13) fail("need 13 cards")
        if (name == "AUTO" && args[0] !in listOf("PASS", "CARD", "TRICK", "HAND", "GAME")) {
            fail("bad value ${args[0]}")
        }

        val game = when (name) {
            "STACK", "DEAL" -> requireBetween()
            "SHOW" -> requireHand()
            "PASS" -> requirePassing()
            "PLAY", "UNDO", "CLAIM", "LEGAL", "PREVIEW", "TAKEN", "TRICKS", "VOIDS", "UNSEEN" ->
                requirePlaying()
            "AUTO" -> when (args[0]) {
                "PASS" -> requirePassing()
                "CARD", "TRICK" -> requirePlaying()
                "HAND" -> requireHand()
                else -> requireGame()
            }
            else -> requireGame()
        }
        val round = game.round
        val before = game.log.size
        val prefix = mutableListOf<String>()
        when (name) {
            "STACK" -> {
                checkDistinct(cards)
                for (card in cards) {
                    val owner = (0 until 4).firstOrNull {
                        it != seat && card in game.stacked[it].orEmpty()
                    }
                    if (owner != null) fail("${cardText(card)} stacked for ${seatName(owner)}")
                }
                game.stacked[seat] = cards.toSet()
                return listOf("stacked ${seatName(seat)}")
            }
            "DEAL" -> game.deal()
            "SHOW" -> return (0 until 4).map { "${seatName(it)}: ${cardsText(round.hands[it])}" }
            "PASS" -> {
                if (seat in game.passes) fail("${seatName(seat)} already passed")
                checkDistinct(cards)
                val missing = cards.firstOrNull { it !in round.hands[seat] }
                if (missing != null) fail("${seatName(seat)} does not hold ${cardText(missing)}")
                game.passCards(seat, cards)
            }
            "PLAY" -> {
                val card = cards[0]
                if (seat != game.actor()) fail("waiting for ${seatName(game.actor())}")
                if (card !in round.hands[seat]) {
                    fail("${seatName(seat)} does not hold ${cardText(card)}")
                }
                if (card !in game.legal()) {
                    if (round.current.isEmpty()) {
                        fail(if (round.tricks.isEmpty()) "must lead 2C" else "hearts not broken")
                    }
                    val led = round.current[0].card / 13
                    if (countSuit(round.hands[seat], led) > 0) fail("must follow ${SUITS[led]}")
                    fail("no points on first trick")
                }
                prefix += "${seatName(seat)} plays ${cardText(card)}"
                game.play(card)
            }
            "AUTO" -> when (args[0]) {
                "PASS" -> game.autoPass()
                "CARD" -> {
                    val actor = game.actor()
                    val card = game.choosePlay()
                    prefix += "${seatName(actor)} plays ${cardText(card)}"
                    game.play(card)
                }
                "TRICK" -> {
                    val count = round.tricks.size
                    while (game.state == State.PLAYING && game.round.tricks.size == count) {
                        game.play(game.choosePlay())
                    }
                }
                "HAND" -> game.autoHand()
                else -> game.autoGame()
            }
            "UNDO" -> {
                if (game.undoStack.isEmpty()) fail("nothing to undo")
                val (undoneSeat, undoneCard) = game.undoCard()
                return listOf("undo ${seatName(undoneSeat)} ${cardText(undoneCard)}")
            }
            "CLAIM" -> {
                if (seat != game.actor()) fail("waiting for ${seatName(game.actor())}")
                if (round.current.isNotEmpty()) fail("trick in progress")
                val beaten = round.hands[seat].any { card ->
                    (0 until 4).any { other ->
                        other != seat &&
                            round.hands[other].any { it / 13 == card / 13 && it % 13 > card % 13 }
                    }
                }
                if (beaten) fail("claim rejected")
                game.claim(seat)
            }
            "LEGAL" -> {
                val bot = cardText(game.choosePlay())
                val playable = cardsText(game.legal())
                return listOf("legal ${seatName(game.actor())}: $playable bot $bot")
            }
            "PREVIEW" -> return game.legal().sorted().map { card ->
                val copy = game.copy()
                val count = copy.round.tricks.size
                copy.play(card)
                while (copy.state == State.PLAYING && copy.round.tricks.size == count) {
                    copy.play(copy.choosePlay())
                }
                val trick = copy.round.tricks.last()
                "preview ${cardText(card)} -> ${seatName(trickWinner(trick))} " +
                    copy.trickPoints(trick)
            }
            "SCORE" -> {
                val output = mutableListOf(pairs("scores", game.scores.asList()))
                if (game.state == State.PLAYING) {
                    output += pairs("taken", round.taken.map(game::points))
                }
                return output
            }
            "TAKEN" -> return (0 until 4).map { other ->
                val scoring = round.taken[other].filter { game.point(it) != 0 }
                "${seatName(other)}: ${cardsText(scoring)}"
            }
            "TRICKS" -> {
                val output = round.tricks
                    .mapIndexed { i, trick -> game.trickLine(trick, i + 1) }
                    .toMutableList()
                if (round.current.isNotEmpty()) output += "current: ${playsText(round.current)}"
                return output.ifEmpty { listOf("no tricks") }
            }
            "VOIDS" -> {
                val voids = List(4) { sortedSetOf<Int>() }
                val tricks = (round.tricks + listOf(round.current)).filter { it.isNotEmpty() }
                for (trick in tricks) {
                    val led = trick[0].card / 13
                    for (play in trick) {
                        if (play.card / 13 != led) voids[play.seat] += led
                    }
                }
                val texts = voids.map { missing ->
                    missing.joinToString("") { SUITS[it].toString() }.ifEmpty { "-" }
                }
                return listOf(pairs("voids", texts))
            }
            "UNSEEN" -> {
                val actor = game.actor()
                val played = round.taken.flatten() + round.current.map { it.card }
                val unseen = (0 until 52).filter { it !in round.hands[actor] && it !in played }
                return listOf("unseen ${seatName(actor)}: ${cardsText(unseen)}")
            }
            "STATS" -> return game.statsLines()
            "HISTORY" -> return game.history.map { hand ->
                val moon = hand.shooter?.let { " moon ${seatName(it)}" }.orEmpty()
                "hand ${hand.number} pass ${hand.direction} ${pairs("points", hand.points)}$moon"
            }.ifEmpty { listOf("no hands") }
            "REPLAY" -> return game.history[bounded(args[0], 1, game.history.size) - 1].record
        }
        return prefix + game.log.drop(before).map { it.text }
    }
}

fun main() {
    val lines = generateSequence(::readlnOrNull).toList()
    val table = Table()
    val output = StringBuilder()
    for (line in lines.drop(1).take(lines[0].trim().toInt())) {
        val result = try {
            table.command(line.split(" "))
        } catch (error: CommandError) {
            listOf("error: ${error.message}")
        }
        result.forEach { output.appendLine(it) }
    }
    print(output)
}
