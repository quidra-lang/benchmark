import java.util.Locale

private class CommandError(message: String) : RuntimeException(message)
private fun fail(message: String): Nothing = throw CommandError(message)
private fun format(pattern: String, vararg values: Any?): String = String.format(Locale.ROOT, pattern, *values)

private fun integer(word: String, minimum: Long, maximum: Long): Long {
    if (word.isEmpty() || word.length > 10 || word.length > 1 && word[0] == '0') fail("bad value $word")
    var value = 0L
    for (digit in word) {
        if (digit !in '0'..'9') fail("bad value $word")
        value = value * 10 + (digit - '0')
    }
    if (value !in minimum..maximum) fail("bad value $word")
    return value
}

private fun choice(word: String, vararg choices: String): String {
    if (word !in choices) fail("bad value $word")
    return word
}

private fun on(word: String) = choice(word, "ON", "OFF") == "ON"
private fun onOff(value: Boolean) = if (value) "ON" else "OFF"

private enum class State { IDLE, INSURANCE, PLAY }
private enum class Finish { BUST, SURRENDER, CHARLIE }
private enum class Action {
    HIT, STAND, DOUBLE, SPLIT, SURRENDER;
    val text: String get() = name.lowercase(Locale.ROOT)
}
private enum class DoubleRule(val text: String) { ANY("ANY"), HARD_9("9-11"), HARD_10("10-11") }
private enum class Outcome {
    BLACKJACK, WIN, CHARLIE, PUSH, LOSE, BUST, SURRENDER;
    val text: String get() = name.lowercase(Locale.ROOT)
    fun profit(bet: Long, rules: Rules): Long = when (this) {
        BLACKJACK -> if (rules.sixToFive) bet * 6 / 5 else bet * 3 / 2
        WIN, CHARLIE -> bet
        PUSH -> 0L
        SURRENDER -> bet / 2 - bet
        LOSE, BUST -> -bet
    }
}

private enum class Command {
    SHOE, RULE, RULES, PLAYER, LEAVE, REBUY, BET, SIDE, DEAL, INSURANCE,
    HIT, STAND, DOUBLE, SPLIT, SURRENDER, HINT, AUTO, STATUS, COUNT, STATS;

    val action: Action? get() = when (this) {
        HIT -> Action.HIT
        STAND -> Action.STAND
        DOUBLE -> Action.DOUBLE
        SPLIT -> Action.SPLIT
        SURRENDER -> Action.SURRENDER
        else -> null
    }
    val namedPlayer: Boolean get() = when (this) {
        LEAVE, REBUY, BET, SIDE, INSURANCE, HIT, STAND, DOUBLE, SPLIT, SURRENDER, AUTO -> true
        else -> false
    }
    val idleOnly: Boolean get() = when (this) {
        SHOE, RULE, PLAYER, LEAVE, REBUY, BET, SIDE, DEAL -> true
        else -> false
    }
    companion object {
        fun parse(word: String): Command = entries.firstOrNull { it.name == word } ?: fail("unknown command $word")
    }
}

private data class Rules(
    val hitSoft17: Boolean = false,
    val penetration: Int = 75,
    val minimum: Long = 10,
    val maximum: Long = 500,
    val sixToFive: Boolean = false,
    val doubleAfterSplit: Boolean = true,
    val doubling: DoubleRule = DoubleRule.ANY,
    val hands: Int = 4,
    val resplitAces: Boolean = false,
    val surrender: Boolean = true,
    val charlie: Int = 0,
    val sideMaximum: Long = 25,
) {
    fun changed(name: String, word: String): Rules = when (name) {
        "DEALER" -> copy(hitSoft17 = choice(word, "S17", "H17") == "H17")
        "PEN" -> copy(penetration = integer(word, 50, 90).toInt())
        "MIN" -> copy(minimum = integer(word, 1, 10000))
        "MAX" -> copy(maximum = integer(word, 1, 10000))
        "BJ" -> copy(sixToFive = choice(word, "3:2", "6:5") == "6:5")
        "DAS" -> copy(doubleAfterSplit = on(word))
        "DOUBLE" -> copy(doubling = when (choice(word, "ANY", "9-11", "10-11")) {
            "ANY" -> DoubleRule.ANY
            "9-11" -> DoubleRule.HARD_9
            else -> DoubleRule.HARD_10
        })
        "HANDS" -> copy(hands = integer(word, 1, 4).toInt())
        "RSA" -> copy(resplitAces = on(word))
        "SURRENDER" -> copy(surrender = on(word))
        "CHARLIE" -> copy(charlie = choice(word, "0", "5", "6", "7").toInt())
        "SIDEMAX" -> copy(sideMaximum = integer(word, 0, 1000))
        else -> fail("unknown rule $name")
    }

    override fun toString(): String = format(
        "rules DEALER %s PEN %d MIN %d MAX %d BJ %s DAS %s DOUBLE %s HANDS %d RSA %s SURRENDER %s CHARLIE %d SIDEMAX %d",
        if (hitSoft17) "H17" else "S17", penetration, minimum, maximum, if (sixToFive) "6:5" else "3:2",
        onOff(doubleAfterSplit), doubling.text, hands, onOff(resplitAces), onOff(surrender), charlie, sideMaximum,
    )
}

private data class Card(val code: Int) {
    val rank: Int get() = code % 13
    val suit: Int get() = code / 13
    val point: Int get() = minOf(rank + 1, 10)
    val black: Boolean get() = suit == 0 || suit == 3
    val hilo: Int get() = when (point) { in 2..6 -> 1; 1, 10 -> -1; else -> 0 }
    override fun toString() = "${"A23456789TJQK"[rank]}${"CDHS"[suit]}"
}

private data class Total(val value: Int, val soft: Boolean)

private class Hand(
    cards: List<Card> = emptyList(),
    var bet: Long = 0,
    val split: Boolean = false,
    val splitAces: Boolean = false,
) {
    val cards = cards.toMutableList()
    var finished = false
    var reason: Finish? = null
    val total: Total get() {
        val sum = cards.sumOf { it.point }
        val soft = cards.any { it.rank == 0 } && sum + 10 <= 21
        return Total(sum + if (soft) 10 else 0, soft)
    }
    val natural: Boolean get() = !split && cards.size == 2 && total.value == 21

    override fun toString(): String {
        val total = total
        val status = when {
            natural -> "blackjack"
            total.value > 21 -> "bust ${total.value}"
            total.soft -> "soft ${total.value}"
            else -> total.value.toString()
        }
        return "${cards.joinToString(" ")} ($status)"
    }

    fun outcome(dealer: Int, dealerNatural: Boolean): Outcome {
        if (dealerNatural) return if (natural) Outcome.PUSH else Outcome.LOSE
        if (natural) return Outcome.BLACKJACK
        return when (reason) {
            Finish.BUST -> Outcome.BUST
            Finish.SURRENDER -> Outcome.SURRENDER
            Finish.CHARLIE -> Outcome.CHARLIE
            null -> when {
                dealer > 21 || total.value > dealer -> Outcome.WIN
                total.value == dealer -> Outcome.PUSH
                else -> Outcome.LOSE
            }
        }
    }
}

private class Statistics {
    var rounds = 0
    var hands = 0
    var wins = 0
    var losses = 0
    var pushes = 0
    var blackjacks = 0
    var busts = 0
    var surrenders = 0
    var doubles = 0
    var splits = 0

    fun record(result: Outcome) {
        hands++
        when (result) {
            Outcome.BLACKJACK, Outcome.WIN, Outcome.CHARLIE -> wins++
            Outcome.PUSH -> pushes++
            else -> losses++
        }
        when (result) {
            Outcome.BLACKJACK -> blackjacks++
            Outcome.BUST -> busts++
            Outcome.SURRENDER -> surrenders++
            else -> Unit
        }
    }

    override fun toString() = "rounds $rounds hands $hands wins $wins losses $losses pushes $pushes" +
        " blackjacks $blackjacks busts $busts surrenders $surrenders doubles $doubles splits $splits"
}

private class Player(val name: String, val seat: Int, var bankroll: Long) {
    var bet = 0L
    var side = 0L
    var insurance = 0L
    var net = 0L
    val hands = mutableListOf<Hand>()
    val stats = Statistics()
    fun handName(index: Int) = "$name[${index + 1}]"
}

private class Shoe(val decks: Int, seed: Long) {
    val cards = Array(52 * decks) { Card(it % 52) }
    var drawn = 0
    var running = 0
    private var random = seed
    init { shuffle() }

    fun shuffle() {
        for (i in cards.indices) cards[i] = Card(i % 52)
        for (i in cards.lastIndex downTo 1) {
            random = random * 48271 % 2147483647
            val j = (random % (i + 1)).toInt()
            val saved = cards[i]
            cards[i] = cards[j]
            cards[j] = saved
        }
        drawn = 0
        running = 0
    }

    fun cut(penetration: Int) = cards.size * penetration / 100
    fun draw(visible: Boolean): Card {
        val card = cards[drawn++]
        if (visible) running += card.hilo
        return card
    }
}

private data class Turn(val player: Player, val index: Int, val hand: Hand) {
    val name: String get() = player.handName(index)
}

private class Table {
    private var rules = Rules()
    private val seats = arrayOfNulls<Player>(7)
    private val participants = mutableListOf<Player>()
    private val output = mutableListOf<String>()
    private var shoe: Shoe? = null
    private var state = State.IDLE
    private var round = 0
    private var dealerBlackjacks = 0
    private var dealerBusts = 0
    private var insuranceTurn = 0
    private var dealer = Hand()
    private var holeVisible = false

    private fun emit(pattern: String, vararg values: Any?) { output += format(pattern, *values) }
    private fun find(name: String) = seats.firstOrNull { it?.name == name }
    private fun draw(visible: Boolean = true) = shoe!!.draw(visible)
    private fun current(): Turn? {
        for (player in participants) {
            for ((index, hand) in player.hands.withIndex()) if (!hand.finished) return Turn(player, index, hand)
        }
        return null
    }

    private fun reveal() {
        if (!holeVisible) {
            shoe!!.running += dealer.cards[1].hilo
            holeVisible = true
        }
        emit("dealer: %s", dealer)
    }

    private fun finishCheck(player: Player, hand: Hand) {
        val value = hand.total.value
        when {
            value > 21 -> { hand.finished = true; hand.reason = Finish.BUST }
            rules.charlie != 0 && hand.cards.size == rules.charlie -> { hand.finished = true; hand.reason = Finish.CHARLIE }
            value == 21 -> hand.finished = true
            hand.splitAces && hand.cards.size == 2 -> {
                hand.finished = !(hand.cards.all { it.rank == 0 } && rules.resplitAces && player.hands.size < rules.hands)
            }
        }
    }

    private fun settle(dealerNatural: Boolean) {
        val dealerTotal = dealer.total.value
        for (player in participants) {
            for ((index, hand) in player.hands.withIndex()) {
                val result = hand.outcome(dealerTotal, dealerNatural)
                val profit = result.profit(hand.bet, rules)
                player.bankroll += hand.bet + profit
                player.net += profit
                player.stats.record(result)
                emit("%s %s %+d", player.handName(index), result.text, profit)
            }
            emit("%s bankroll %d", player.name, player.bankroll)
        }
        for (player in seats.filterNotNull()) { player.bet = 0; player.side = 0 }
        state = State.IDLE
    }

    private fun dealerTurn() {
        reveal()
        val needsDraw = participants.any { player -> player.hands.any { it.reason == null && !it.natural } }
        var drew = false
        if (needsDraw) {
            while (true) {
                val total = dealer.total
                if (!(total.value <= 16 || total.value == 17 && total.soft && rules.hitSoft17)) break
                dealer.cards += draw()
                drew = true
                emit("dealer hits: %s", dealer)
            }
        }
        if (drew && dealer.total.value > 21) dealerBusts++
        settle(false)
    }

    private fun advance() {
        while (true) {
            val turn = current()
            if (turn == null) { dealerTurn(); return }
            if (turn.hand.cards.size != 1) return
            turn.hand.cards += draw()
            emit("%s: %s", turn.name, turn.hand)
            finishCheck(turn.player, turn.hand)
            if (!turn.hand.finished) return
        }
    }

    private fun peek() {
        val natural = dealer.natural
        emit("dealer peeks: %s", if (natural) "blackjack" else "no blackjack")
        for (player in participants) {
            if (player.insurance == 0L) continue
            val profit = player.insurance * if (natural) 2 else -1
            player.bankroll += player.insurance + profit
            player.net += profit
            emit("%s insurance %+d", player.name, profit)
        }
        if (natural) {
            dealerBlackjacks++
            reveal()
            settle(true)
        } else {
            state = State.PLAY
            advance()
        }
    }

    private fun deal() {
        val pile = shoe!!
        if (pile.drawn >= pile.cut(rules.penetration)) { pile.shuffle(); emit("shuffle") }
        emit("round %d", ++round)
        participants.clear()
        for (player in seats.filterNotNull()) {
            if (player.bet == 0L) continue
            participants += player
            player.bankroll -= player.bet + player.side
            player.insurance = 0
            player.stats.rounds++
            player.hands.clear()
            player.hands += Hand(bet = player.bet)
        }
        dealer = Hand()
        holeVisible = false
        for (player in participants) player.hands[0].cards += draw()
        dealer.cards += draw()
        for (player in participants) {
            val hand = player.hands[0]
            hand.cards += draw()
            hand.finished = hand.natural
        }
        dealer.cards += draw(false)
        for (player in participants) emit("%s: %s", player.handName(0), player.hands[0])
        emit("dealer: %s ??", dealer.cards[0])
        for (player in participants) {
            if (player.side == 0L) continue
            val (first, second) = player.hands[0].cards
            val (result, multiplier) = when {
                first.rank != second.rank -> "lose" to -1
                first.suit == second.suit -> "perfect" to 25
                first.black == second.black -> "colored" to 12
                else -> "mixed" to 6
            }
            val profit = player.side * multiplier
            player.bankroll += player.side + profit
            player.net += profit
            emit("%s side %s %+d", player.name, result, profit)
        }
        when (dealer.cards[0].point) {
            1 -> { state = State.INSURANCE; insuranceTurn = 0; emit("insurance offered") }
            10 -> peek()
            else -> { state = State.PLAY; advance() }
        }
    }

    private fun actionProblem(action: Action, player: Player, hand: Hand): String? {
        when (action) {
            Action.HIT -> if (hand.splitAces) return "split aces"
            Action.DOUBLE -> {
                if (hand.splitAces) return "split aces"
                if (hand.cards.size != 2) return "two cards only"
                val total = hand.total
                val minimum = if (rules.doubling == DoubleRule.HARD_10) 10 else 9
                if (rules.doubling != DoubleRule.ANY && (total.soft || total.value !in minimum..11)
                    || !rules.doubleAfterSplit && hand.split) return "double not allowed"
                if (player.bankroll < hand.bet) return "insufficient funds"
            }
            Action.SPLIT -> {
                if (hand.cards.size != 2) return "two cards only"
                if (hand.cards[0].point != hand.cards[1].point) return "not a pair"
                if (player.hands.size >= rules.hands) return "hand limit"
                if (player.bankroll < hand.bet) return "insufficient funds"
            }
            Action.SURRENDER -> {
                if (!rules.surrender || hand.split) return "surrender not allowed"
                if (hand.cards.size != 2) return "two cards only"
            }
            Action.STAND -> Unit
        }
        return null
    }

    private fun recommend(): Action {
        val turn = current()!!
        val hand = turn.hand
        fun possible(action: Action) = actionProblem(action, turn.player, hand) == null
        val up = if (dealer.cards[0].point == 1) 11 else dealer.cards[0].point
        if (hand.splitAces) return if (possible(Action.SPLIT)) Action.SPLIT else Action.STAND
        if (possible(Action.SPLIT)) {
            val pair = hand.cards[0].point
            if (pair == 1 || pair == 8 || pair == 9 && up !in listOf(7, 10, 11)
                || pair in listOf(2, 3, 7) && up <= 7 || pair == 6 && up <= 6 || pair == 4 && up in 5..6) return Action.SPLIT
        }
        val total = hand.total
        val value = total.value
        val symbol = if (total.soft) when {
            value >= 19 -> "S"
            value == 18 -> when (up) { in 3..6 -> "Ds"; 2, 7, 8 -> "S"; else -> "H" }
            value == 17 && up in 3..6 || value in 15..16 && up in 4..6 || value in 13..14 && up in 5..6 -> "D"
            else -> "H"
        } else when {
            value >= 17 -> "S"
            value >= 13 -> when {
                up <= 6 -> "S"
                value == 16 && up >= 9 || value == 15 && up == 10 -> "R"
                else -> "H"
            }
            value == 12 -> if (up in 4..6) "S" else "H"
            value == 11 && up <= 10 || value == 10 && up <= 9 || value == 9 && up in 3..6 -> "D"
            else -> "H"
        }
        return when (symbol) {
            "S" -> Action.STAND
            "D" -> if (possible(Action.DOUBLE)) Action.DOUBLE else Action.HIT
            "Ds" -> if (possible(Action.DOUBLE)) Action.DOUBLE else Action.STAND
            "R" -> if (possible(Action.SURRENDER)) Action.SURRENDER else Action.HIT
            else -> Action.HIT
        }
    }

    private fun perform(action: Action) {
        val turn = current()!!
        val player = turn.player
        val hand = turn.hand
        val name = turn.name
        when (action) {
            Action.SPLIT -> {
                val (first, second) = hand.cards
                val aces = hand.splitAces || first.rank == 0
                player.bankroll -= hand.bet
                player.stats.splits++
                emit("%s splits %s %s", name, first, second)
                val replacement = Hand(listOf(first), hand.bet, split = true, splitAces = aces)
                player.hands[turn.index] = replacement
                player.hands.add(turn.index + 1, Hand(listOf(second), hand.bet, split = true, splitAces = aces))
                replacement.cards += draw()
                emit("%s: %s", name, replacement)
                finishCheck(player, replacement)
            }
            Action.STAND, Action.SURRENDER -> {
                hand.finished = true
                if (action == Action.SURRENDER) hand.reason = Finish.SURRENDER
                emit("%s %s: %s", name, if (action == Action.STAND) "stands" else "surrenders", hand)
            }
            Action.HIT, Action.DOUBLE -> {
                if (action == Action.DOUBLE) {
                    player.bankroll -= hand.bet
                    hand.bet *= 2
                    player.stats.doubles++
                }
                hand.cards += draw()
                emit("%s %s: %s", name, if (action == Action.DOUBLE) "doubles" else "hits", hand)
                finishCheck(player, hand)
                if (action == Action.DOUBLE) hand.finished = true
            }
        }
        advance()
    }

    private fun status() {
        when (state) {
            State.IDLE -> emit("table idle round %d", round)
            State.INSURANCE -> emit("table insurance round %d next %s", round, participants[insuranceTurn].name)
            State.PLAY -> emit("table play round %d turn %s", round, current()!!.name)
        }
        if (state != State.IDLE) emit("dealer: %s ??", dealer.cards[0])
        for (player in seats.filterNotNull()) {
            emit("seat %d %s bankroll %d bet %d side %d", player.seat + 1, player.name, player.bankroll, player.bet, player.side)
            if (state != State.IDLE && player in participants) {
                for ((index, hand) in player.hands.withIndex()) emit("%s: %s bet %d", player.handName(index), hand, hand.bet)
            }
        }
    }

    fun execute(words: List<String>): List<String> {
        output.clear()
        val command = Command.parse(words[0])
        val action = command.action
        var target: Player? = null
        var amount = 0L
        var seed = 0L
        var proposed: Rules? = null
        when (command) {
            Command.SHOE -> { amount = integer(words[1], 1, 8); seed = integer(words[2], 1, 2147483646) }
            Command.RULE -> proposed = rules.changed(words[1], words[2])
            Command.PLAYER -> {
                val name = words[1]
                if (name.isEmpty() || name.length > 8 || name.any { it !in 'A'..'Z' }) fail("bad name $name")
                amount = integer(words[2], 1, 1000000)
            }
            else -> if (command.namedPlayer) {
                target = find(words[1]) ?: fail("unknown player ${words[1]}")
                if (command in listOf(Command.REBUY, Command.BET, Command.SIDE, Command.INSURANCE)) {
                    amount = integer(words[2], if (command == Command.REBUY) 1 else 0, 1000000)
                }
            }
        }
        if (command.idleOnly && state != State.IDLE) fail("round in progress")
        if (command == Command.INSURANCE && state != State.INSURANCE) fail("no insurance")
        if (action != null || command == Command.AUTO || command == Command.HINT) {
            if (state == State.IDLE) fail("no round")
            if (state == State.INSURANCE) fail("insurance pending")
        }
        if (action != null || command == Command.AUTO) {
            val turn = current()!!
            if (turn.player !== target) fail("waiting for ${turn.name}")
            if (action != null) {
                actionProblem(action, turn.player, turn.hand)?.let { fail(it) }
                perform(action)
            } else {
                while (state == State.PLAY && current()!!.player === target) perform(recommend())
            }
            return output
        }
        when (command) {
            Command.SHOE -> {
                val pile = Shoe(amount.toInt(), seed)
                shoe = pile
                emit("shoe %d decks %d cards cut %d", pile.decks, pile.cards.size, pile.cut(rules.penetration))
            }
            Command.RULE -> {
                val next = proposed!!
                if (next.minimum > next.maximum) fail("min above max")
                rules = next
                emit("rule %s %s", words[1], words[2])
            }
            Command.RULES -> emit("%s", rules)
            Command.PLAYER -> {
                if (find(words[1]) != null) fail("player exists")
                val seat = seats.indexOfFirst { it == null }
                if (seat < 0) fail("table full")
                seats[seat] = Player(words[1], seat, amount)
                emit("%s sits at seat %d with %d", words[1], seat + 1, amount)
            }
            Command.LEAVE -> {
                val player = target!!
                emit("%s leaves with %d net %+d", player.name, player.bankroll, player.net)
                seats[player.seat] = null
            }
            Command.REBUY -> {
                val player = target!!
                player.bankroll += amount
                emit("%s rebuys %d bankroll %d", player.name, amount, player.bankroll)
            }
            Command.BET -> {
                val player = target!!
                if (amount != 0L) {
                    if (amount !in rules.minimum..rules.maximum) fail("bet out of limits")
                    if (amount + player.side > player.bankroll) fail("insufficient funds")
                }
                player.bet = amount
                if (amount == 0L) { player.side = 0; emit("%s bet cleared", player.name) }
                else emit("%s bets %d", player.name, amount)
            }
            Command.SIDE -> {
                val player = target!!
                if (amount != 0L) {
                    if (player.bet == 0L) fail("no bet")
                    if (amount > rules.sideMaximum) fail("side out of limits")
                    if (player.bet + amount > player.bankroll) fail("insufficient funds")
                }
                player.side = amount
                if (amount == 0L) emit("%s side cleared", player.name)
                else emit("%s side %d", player.name, amount)
            }
            Command.DEAL -> {
                if (shoe == null) fail("no shoe")
                if (seats.none { it != null && it.bet != 0L }) fail("no bets")
                deal()
            }
            Command.INSURANCE -> {
                val player = target!!
                val waiting = participants[insuranceTurn]
                if (player !== waiting) fail("waiting for ${waiting.name}")
                if (amount > player.bet / 2) fail("insurance out of limits")
                if (amount > player.bankroll) fail("insufficient funds")
                player.bankroll -= amount
                player.insurance = amount
                if (amount == 0L) emit("%s declines insurance", player.name)
                else emit("%s insures %d", player.name, amount)
                if (++insuranceTurn == participants.size) peek()
            }
            Command.HINT -> emit("hint %s: %s", current()!!.name, recommend().text)
            Command.STATUS -> status()
            Command.COUNT -> {
                val pile = shoe ?: fail("no shoe")
                val remaining = pile.cards.size - pile.drawn
                val scaled = kotlin.math.abs(pile.running.toLong()) * 5200 / remaining
                emit("count running %d true %s%d.%02d remaining %d", pile.running, if (pile.running < 0) "-" else "", scaled / 100, scaled % 100, remaining)
            }
            Command.STATS -> {
                val players = seats.filterNotNull()
                if (players.isEmpty()) fail("no players")
                for (player in players) emit("stats %s %s net %+d", player.name, player.stats, player.net)
                emit("stats dealer rounds %d blackjacks %d busts %d", round, dealerBlackjacks, dealerBusts)
            }
            else -> Unit
        }
        return output
    }
}

fun main() {
    val input = System.`in`.bufferedReader(Charsets.UTF_8)
    val table = Table()
    System.out.bufferedWriter(Charsets.UTF_8).use { output ->
        repeat(input.readLine().toInt()) {
            val words = input.readLine().split(' ')
            try {
                for (line in table.execute(words)) { output.write(line); output.write("\n") }
            } catch (failure: CommandError) {
                output.write("error: ${failure.message}\n")
            }
        }
    }
}
