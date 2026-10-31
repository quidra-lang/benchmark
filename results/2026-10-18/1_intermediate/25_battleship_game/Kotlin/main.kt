import kotlin.math.abs

private val shipNames = listOf("CARRIER", "BATTLESHIP", "CRUISER", "SUBMARINE", "DESTROYER")
private val lengths = intArrayOf(5, 4, 3, 3, 2)
private const val symbols = "CBRSD"
private val output = System.out.bufferedWriter(Charsets.US_ASCII)

private enum class Phase { SETUP, BATTLE, OVER }
private enum class Strategy { HUNT, PROB, RANDOM }
private enum class CellView { REEF, UNKNOWN, MISS, HIT, SUNK }
private enum class Result { ALREADY, MISS, HIT, SUNK }
private enum class Output { NORMAL, SINKS_ONLY, QUIET }
private class GameError(message: String) : Exception(message)

private fun fail(message: String): Nothing = throw GameError(message)
private fun emit(text: String) { output.write(text); output.write("\n") }
private fun advance(state: Long): Long = state * 48271 % 2147483647
private fun cellNumber(text: String): Int = (text[0] - 'A') * 10 + text.substring(1).toInt() - 1
private fun cellName(cell: Int): String = "${'A' + cell / 10}${cell % 10 + 1}"
private fun switchName(enabled: Boolean): String = if (enabled) "ON" else "OFF"
private fun adjacent(a: Int, b: Int): Boolean = abs(a / 10 - b / 10) <= 1 && abs(a % 10 - b % 10) <= 1

private fun neighbour(cell: Int, dr: Int, dc: Int): Int {
    val row = cell / 10 + dr
    val col = cell % 10 + dc
    return if (row in 0..9 && col in 0..9) row * 10 + col else -1
}

private data class Ship(val start: Int, val step: Int) {
    fun cell(i: Int): Int = start + i * step
    fun inBounds(length: Int): Boolean = if (step == 1) start % 10 + length <= 10 else start / 10 + length <= 10
    fun span(length: Int): String = "${cellName(start)}-${cellName(cell(length - 1))}"

    fun touches(length: Int, other: Ship, otherLength: Int): Boolean {
        for (i in 0 until length)
            for (j in 0 until otherLength)
                if (adjacent(cell(i), other.cell(j))) return true
        return false
    }
}

private data class Shot(val result: Result, val ship: Int = -1) {
    val isHit: Boolean get() = result == Result.HIT || result == Result.SUNK
    override fun toString(): String = if (result == Result.SUNK) "SUNK ${shipNames[ship]}" else result.name
}

private class Stats {
    var shots = 0L
    var hits = 0L
    var sunk = 0L
    var turns = 0L
    var streak = 0L
    var longest = 0L
    var wins = 0L

    fun record(shot: Shot) {
        shots++
        if (shot.isHit) {
            hits++
            streak++
            longest = maxOf(longest, streak)
        } else streak = 0
        if (shot.result == Result.SUNK) sunk++
    }
}

private class Player(number: Int) {
    val fleet = arrayOfNulls<Ship>(5)
    val board = IntArray(100) { -1 }
    val attacked = BooleanArray(100)
    val candidates = mutableListOf<Int>()
    val stats = Stats()
    var random = number.toLong() + 1
    var controller: Strategy? = null
    var torpedoUsed = false
    var sonarUsed = false

    fun clearFleet() { fleet.fill(null); board.fill(-1) }

    fun putShip(s: Int, ship: Ship) {
        fleet[s] = ship
        for (i in 0 until lengths[s]) board[ship.cell(i)] = s
    }

    fun attackedCount(s: Int): Int {
        val ship = fleet[s] ?: return 0
        return (0 until lengths[s]).count { attacked[ship.cell(it)] }
    }

    fun sunk(s: Int): Boolean = fleet[s] != null && attackedCount(s) == lengths[s]
    fun placed(): Int = fleet.count { it != null }
    fun afloat(): Int = fleet.indices.count { fleet[it] != null && !sunk(it) }
}

private class View(val cells: Array<CellView>, val remaining: BooleanArray, val excluded: BooleanArray) {
    fun candidate(c: Int): Boolean = c in 0..99 && cells[c] == CellView.UNKNOWN && !excluded[c]

    fun density(): IntArray {
        val scores = IntArray(100)
        for (s in lengths.indices) {
            if (!remaining[s]) continue
            for (start in 0 until 100)
                for (step in intArrayOf(1, 10)) {
                    val ship = Ship(start, step)
                    if (!ship.inBounds(lengths[s])) continue
                    var possible = true
                    var hits = 0
                    for (i in 0 until lengths[s]) {
                        val c = ship.cell(i)
                        if (excluded[c] || (cells[c] != CellView.UNKNOWN && cells[c] != CellView.HIT)) {
                            possible = false
                            break
                        }
                        if (cells[c] == CellView.HIT) hits++
                    }
                    if (possible)
                        for (i in 0 until lengths[s]) scores[ship.cell(i)] += 1 + 10 * hits
                }
        }
        return scores
    }

    fun best(scores: IntArray): Int {
        var best = -1
        for (c in cells.indices)
            if (cells[c] == CellView.UNKNOWN && (best < 0 || scores[c] > scores[best])) best = c
        return best
    }
}

private data class Choice(val cell: Int, val nextRandom: Long, val step: String? = null, val value: Int = 0) {
    val info: String get() = step ?: value.toString()
}

private data class Match(val winner: Int, val shots: LongArray, val hits: LongArray)

private class Game {
    var players = Array(2) { Player(it) }
    var reefs = BooleanArray(100)
    var salvo = false
    var chain = false
    var touch = false
    var phase = Phase.SETUP
    var current = 0
    var winner = -1

    fun allowance(p: Int): Int = if (salvo) players[p].afloat() else 1

    fun placementError(player: Player, s: Int, ship: Ship): String? {
        if (!ship.inBounds(lengths[s])) return "out of bounds"
        if ((0 until lengths[s]).any { reefs[ship.cell(it)] }) return "on reef"
        for (other in lengths.indices)
            if ((0 until lengths[s]).any { player.board[ship.cell(it)] == other }) return "overlaps ${shipNames[other]}"
        if (!touch)
            for (other in lengths.indices) {
                val placed = player.fleet[other] ?: continue
                if (ship.touches(lengths[s], placed, lengths[other])) return "touches ${shipNames[other]}"
            }
        return null
    }

    fun printPlaced(p: Int, s: Int) = emit("PLACED ${p + 1} ${shipNames[s]} ${players[p].fleet[s]!!.span(lengths[s])}")

    fun autoplace(p: Int, seed: Long): Long {
        val player = players[p]
        player.clearFleet()
        player.random = seed
        var attempts = 0L
        for (s in lengths.indices) {
            while (true) {
                attempts++
                player.random = advance(player.random)
                val step = if (player.random % 2 == 0L) 1 else 10
                player.random = advance(player.random)
                val k = (player.random % (10 * (11 - lengths[s]))).toInt()
                val start = if (step == 1) k / (11 - lengths[s]) * 10 + k % (11 - lengths[s]) else k
                val ship = Ship(start, step)
                if (placementError(player, s, ship) == null) {
                    player.putShip(s, ship)
                    break
                }
            }
        }
        return attempts
    }

    fun parseLayout(layout: String): List<Ship> {
        val fleet = mutableListOf<Ship>()
        for (s in lengths.indices) {
            val cells = (0 until 100).filter { layout[it / 10 * 11 + it % 10] == symbols[s] }
            if (cells.size != lengths[s]) fail("${shipNames[s]} has ${cells.size} cells")
            val ship = Ship(cells[0], cells[1] - cells[0])
            if ((ship.step != 1 && ship.step != 10) || !ship.inBounds(lengths[s]) || cells.indices.any { cells[it] != ship.cell(it) })
                fail("${shipNames[s]} not straight")
            if (cells.any { reefs[it] }) fail("${shipNames[s]} on reef")
            fleet.add(ship)
        }
        if (!touch)
            for (a in lengths.indices)
                for (b in a + 1 until 5)
                    if (fleet[a].touches(lengths[a], fleet[b], lengths[b])) fail("${shipNames[a]} touches ${shipNames[b]}")
        return fleet
    }

    fun view(p: Int): View {
        val opponent = players[1 - p]
        val remaining = BooleanArray(5) { !opponent.sunk(it) }
        val cells = Array(100) { c ->
            val s = opponent.board[c]
            when {
                reefs[c] -> CellView.REEF
                !opponent.attacked[c] -> CellView.UNKNOWN
                s < 0 -> CellView.MISS
                remaining[s] -> CellView.HIT
                else -> CellView.SUNK
            }
        }
        val excluded = BooleanArray(100)
        if (!touch)
            for (c in cells.indices) {
                if (cells[c] != CellView.SUNK) continue
                for (dr in -1..1)
                    for (dc in -1..1) {
                        if (dr == 0 && dc == 0) continue
                        val other = neighbour(c, dr, dc)
                        if (other >= 0) excluded[other] = true
                    }
            }
        return View(cells, remaining, excluded)
    }

    fun choose(p: Int, strategy: Strategy): Choice {
        val view = view(p)
        val player = players[p]
        if (strategy == Strategy.PROB) {
            val scores = view.density()
            val cell = view.best(scores)
            return Choice(cell, player.random, value = scores[cell])
        }
        if (strategy == Strategy.RANDOM) {
            val cells = (0 until 100).filter { view.candidate(it) }
            val next = advance(player.random)
            return Choice(cells[(next % cells.size).toInt()], next, value = cells.size)
        }
        for (h in 0 until 100) {
            if (view.cells[h] != CellView.HIT) continue
            for ((dr, dc) in listOf(0 to 1, 1 to 0)) {
                var front = neighbour(h, dr, dc)
                if (front < 0 || view.cells[front] != CellView.HIT) continue
                while (front >= 0 && view.cells[front] == CellView.HIT) front = neighbour(front, dr, dc)
                for (cell in intArrayOf(front, neighbour(h, -dr, -dc)))
                    if (view.candidate(cell)) return Choice(cell, player.random, step = "LINE")
            }
        }
        for (cell in player.candidates.asReversed())
            if (view.candidate(cell)) return Choice(cell, player.random, step = "STACK")
        val shortest = lengths.indices.filter { view.remaining[it] }.minOf { lengths[it] }
        val cell = (0 until 100).first { view.candidate(it) && (it / 10 + it % 10) % shortest == 0 }
        return Choice(cell, player.random, step = "PARITY")
    }

    fun shoot(p: Int, cell: Int): Shot {
        val player = players[p]
        val opponent = players[1 - p]
        val s = opponent.board[cell]
        val result = if (opponent.attacked[cell]) Result.ALREADY else {
            opponent.attacked[cell] = true
            when {
                s < 0 -> Result.MISS
                opponent.sunk(s) -> Result.SUNK
                else -> Result.HIT
            }
        }
        if (result == Result.HIT)
            for ((dr, dc) in listOf(0 to -1, 1 to 0, 0 to 1, -1 to 0)) {
                val c = neighbour(cell, dr, dc)
                if (c >= 0) player.candidates.add(c)
            }
        val shot = Shot(result, s)
        player.stats.record(shot)
        return shot
    }

    fun emitShot(p: Int, cell: Int, shot: Shot, mode: Output) {
        if (mode == Output.NORMAL) emit("SHOT ${p + 1} ${cellName(cell)} $shot")
        else if (mode == Output.SINKS_ONLY && shot.result == Result.SUNK)
            emit("SINK ${p + 1} ${shipNames[shot.ship]} ${players[p].stats.shots}")
    }

    fun finishTurn(p: Int, hit: Boolean, mode: Output) {
        players[p].stats.turns++
        if (players[1 - p].afloat() == 0) {
            phase = Phase.OVER
            winner = p
            players[p].stats.wins++
            if (mode == Output.NORMAL) emit("WINNER ${p + 1}")
        } else current = if (chain && hit) p else 1 - p
    }

    fun aiTurn(p: Int, strategy: Strategy, mode: Output) {
        val allowance = allowance(p)
        var hit = false
        for (i in 0 until allowance) {
            val choice = choose(p, strategy)
            players[p].random = choice.nextRandom
            val shot = shoot(p, choice.cell)
            emitShot(p, choice.cell, shot, mode)
            hit = hit || shot.isHit
            if (players[1 - p].afloat() == 0) break
        }
        finishTurn(p, hit, mode)
    }

    fun automaticControl() {
        while (phase == Phase.BATTLE) {
            val p = current
            val strategy = players[p].controller ?: break
            aiTurn(p, strategy, Output.NORMAL)
        }
    }

    fun turn(w: List<String>) {
        val cmd = w[0]
        val p = w[1].toInt() - 1
        if (phase == Phase.OVER) fail("game over")
        if (phase == Phase.SETUP && players.any { it.placed() != 5 }) fail("fleets not ready")
        if (p != current) fail("not your turn")
        val player = players[p]
        val opponent = players[1 - p]
        if (cmd == "FIRE") {
            val expected = allowance(p)
            if (w.size - 2 != expected) fail("expected $expected shots")
            for (text in w.drop(2)) if (reefs[cellNumber(text)]) fail("reef at $text")
        } else if (cmd == "TORPEDO" && player.torpedoUsed) fail("torpedo used")
        else if (cmd == "SONAR" && player.sonarUsed) fail("sonar used")
        phase = Phase.BATTLE
        if (cmd == "AI") { aiTurn(p, Strategy.valueOf(w[2]), Output.NORMAL); return }
        var hit = false
        when (cmd) {
            "FIRE" -> {
                for (text in w.drop(2)) {
                    val cell = cellNumber(text)
                    val shot = shoot(p, cell)
                    emitShot(p, cell, shot, Output.NORMAL)
                    hit = hit || shot.isHit
                    if (opponent.afloat() == 0) break
                }
            }
            "SONAR" -> {
                player.sonarUsed = true
                val centre = cellNumber(w[2])
                val count = (0 until 100).count { adjacent(it, centre) && opponent.board[it] >= 0 && !opponent.attacked[it] }
                emit("SONAR ${p + 1} ${w[2]} $count")
            }
            "TORPEDO" -> {
                player.torpedoUsed = true
                var result = "MISS"
                var stoppedAtShip = false
                for (i in 0 until 10) {
                    val cell = (w[2][0] - 'A') * 10 + if (w[3] == "W") i else 9 - i
                    if (reefs[cell]) { result = "REEF ${cellName(cell)}"; break }
                    if (opponent.board[cell] >= 0) {
                        val shot = shoot(p, cell)
                        hit = shot.isHit
                        result = "$shot ${cellName(cell)}"
                        stoppedAtShip = true
                        break
                    }
                    opponent.attacked[cell] = true
                }
                if (!stoppedAtShip) player.stats.record(Shot(Result.MISS))
                emit("TORPEDO ${p + 1} ${w[2]} ${w[3]} $result")
            }
        }
        finishTurn(p, hit, Output.NORMAL)
    }

    fun playMatch(seed1: Long, seed2: Long, first: Strategy, second: Strategy, mode: Output): Match {
        val game = Game()
        game.salvo = salvo
        game.chain = chain
        game.touch = touch
        game.reefs = reefs.copyOf()
        game.autoplace(0, seed1)
        game.autoplace(1, seed2)
        game.phase = Phase.BATTLE
        val strategies = arrayOf(first, second)
        while (game.phase == Phase.BATTLE) {
            val p = game.current
            game.aiTurn(p, strategies[p], mode)
        }
        return Match(game.winner, LongArray(2) { game.players[it].stats.shots }, LongArray(2) { game.players[it].stats.hits })
    }

    fun showBoard(p: Int, radar: Boolean) {
        emit("${if (radar) "RADAR" else "BOARD"} ${p + 1}")
        emit("  1 2 3 4 5 6 7 8 9 10")
        val view = view(p)
        val player = players[p]
        for (row in 0 until 10) emit(buildString {
            append('A' + row)
            for (col in 0 until 10) {
                val c = row * 10 + col
                val s = player.board[c]
                val mark = when {
                    radar -> "~.ox#"[view.cells[c].ordinal]
                    reefs[c] -> '~'
                    s >= 0 -> if (player.attacked[c]) symbols[s].lowercaseChar() else symbols[s]
                    player.attacked[c] -> 'o'
                    else -> '.'
                }
                append(' ').append(mark)
            }
        })
    }

    fun printDensity(p: Int) {
        val view = view(p)
        val scores = view.density()
        emit("DENSITY ${p + 1}")
        emit(" " + (1..10).joinToString("") { it.toString().padStart(5) })
        for (row in 0 until 10) emit(buildString {
            append('A' + row)
            for (col in 0 until 10) {
                val c = row * 10 + col
                val value = when (view.cells[c]) {
                    CellView.UNKNOWN -> scores[c].toString()
                    CellView.REEF -> "~"
                    else -> "-"
                }
                append(value.padStart(5))
            }
        })
        val best = view.best(scores)
        emit("BEST ${cellName(best)} ${scores[best]}")
    }

    fun execute(w: List<String>) {
        val cmd = w[0]
        if (cmd in setOf("PLACE", "REMOVE", "AUTOPLACE", "LAYOUT", "REEF", "SALVO", "CHAIN", "TOUCH") && phase != Phase.SETUP)
            fail("setup closed")
        when (cmd) {
            "NEW" -> {
                val wins = players.map { it.stats.wins }
                players = Array(2) { Player(it) }
                reefs = BooleanArray(100)
                salvo = false
                chain = false
                touch = false
                phase = Phase.SETUP
                current = 0
                winner = -1
                for (p in players.indices) players[p].stats.wins = wins[p]
                emit("NEW")
            }
            "SEED", "CONTROL" -> {
                val p = w[1].toInt() - 1
                if (cmd == "SEED") {
                    players[p].random = w[2].toLong()
                    emit("SEED ${p + 1} ${players[p].random}")
                } else {
                    players[p].controller = if (w[2] == "HUMAN") null else Strategy.valueOf(w[2])
                    emit("CONTROL ${p + 1} ${w[2]}")
                }
            }
            "SALVO", "CHAIN", "TOUCH" -> {
                val enabled = w[1] == "ON"
                when (cmd) { "SALVO" -> salvo = enabled; "CHAIN" -> chain = enabled; else -> touch = enabled }
                emit("$cmd ${w[1]}")
            }
            "PLACE" -> {
                val p = w[1].toInt() - 1
                val s = shipNames.indexOf(w[2])
                if (players[p].fleet[s] != null) fail("${shipNames[s]} already placed")
                val ship = Ship(cellNumber(w[3]), if (w[4] == "H") 1 else 10)
                placementError(players[p], s, ship)?.let { fail(it) }
                players[p].putShip(s, ship)
                printPlaced(p, s)
            }
            "REMOVE" -> {
                val p = w[1].toInt() - 1
                val s = shipNames.indexOf(w[2])
                val ship = players[p].fleet[s] ?: fail("${shipNames[s]} not placed")
                for (i in 0 until lengths[s]) players[p].board[ship.cell(i)] = -1
                players[p].fleet[s] = null
                emit("REMOVED ${p + 1} ${shipNames[s]}")
            }
            "AUTOPLACE" -> {
                val p = w[1].toInt() - 1
                val attempts = autoplace(p, w[2].toLong())
                emit("AUTOPLACE ${p + 1} attempts $attempts")
                for (s in lengths.indices) printPlaced(p, s)
            }
            "LAYOUT" -> {
                val p = w[1].toInt() - 1
                val fleet = parseLayout(w[2])
                players[p].clearFleet()
                fleet.forEachIndexed { s, ship -> players[p].putShip(s, ship) }
                emit("LAYOUT ${p + 1}")
                for (s in lengths.indices) printPlaced(p, s)
            }
            "REEF" -> {
                val c = cellNumber(w[1])
                if (reefs[c]) fail("reef exists at ${w[1]}")
                for (p in players.indices) {
                    val s = players[p].board[c]
                    if (s >= 0) fail("${w[1]} occupied by ${p + 1} ${shipNames[s]}")
                }
                reefs[c] = true
                emit("REEF ${w[1]}")
            }
            "FIRE", "AI", "TORPEDO", "SONAR" -> { turn(w); automaticControl() }
            "RESIGN" -> {
                if (phase != Phase.BATTLE) fail("not in battle")
                val p = w[1].toInt() - 1
                phase = Phase.OVER
                winner = 1 - p
                players[1 - p].stats.wins++
                emit("RESIGN ${p + 1}")
                emit("WINNER ${2 - p}")
            }
            "HINT", "DENSITY" -> {
                if (phase == Phase.OVER) fail("game over")
                val p = w[1].toInt() - 1
                if (cmd == "DENSITY") printDensity(p)
                else {
                    val choice = choose(p, Strategy.valueOf(w[2]))
                    emit("HINT ${p + 1} ${w[2]} ${cellName(choice.cell)} ${choice.info}")
                }
            }
            "SHOW", "RADAR" -> showBoard(w[1].toInt() - 1, cmd == "RADAR")
            "EXPORT" -> {
                val p = w[1].toInt() - 1
                val layout = players[p].board.toList().chunked(10).joinToString("/") { row ->
                    row.joinToString("") { if (it < 0) "." else symbols[it].toString() }
                }
                emit("EXPORT ${p + 1} $layout")
            }
            "FLEET" -> {
                val p = w[1].toInt() - 1
                val player = players[p]
                emit("FLEET ${p + 1} afloat ${player.afloat()}")
                for (s in lengths.indices) {
                    val ship = player.fleet[s]
                    if (ship == null) emit("${shipNames[s]} unplaced")
                    else emit("${shipNames[s]} ${ship.span(lengths[s])} ${player.attackedCount(s)}/${lengths[s]} ${if (player.sunk(s)) "SUNK" else "AFLOAT"}")
                }
            }
            "STATUS" -> {
                val prefix = "STATUS $phase salvo ${switchName(salvo)} chain ${switchName(chain)} touch ${switchName(touch)} reefs ${reefs.count { it }}"
                when (phase) {
                    Phase.SETUP -> emit("$prefix placed ${players[0].placed()} ${players[1].placed()}")
                    Phase.BATTLE -> emit("$prefix turn ${current + 1} shots ${allowance(current)} afloat ${players[0].afloat()} ${players[1].afloat()}")
                    Phase.OVER -> emit("$prefix winner ${winner + 1} afloat ${players[0].afloat()} ${players[1].afloat()}")
                }
            }
            "STATS" -> {
                for (p in players.indices) {
                    val s = players[p].stats
                    val accuracy = if (s.shots == 0L) "-" else "${s.hits * 100 / s.shots}%"
                    emit("STATS ${p + 1} shots ${s.shots} hits ${s.hits} sunk ${s.sunk} turns ${s.turns} streak ${s.longest} accuracy $accuracy wins ${s.wins}")
                }
            }
            "MATCH" -> {
                emit("MATCH 1 ${w[3]} 2 ${w[4]}")
                val result = playMatch(w[1].toLong(), w[2].toLong(), Strategy.valueOf(w[3]), Strategy.valueOf(w[4]), Output.SINKS_ONLY)
                emit("RESULT winner ${result.winner + 1} shots ${result.shots[0]} ${result.shots[1]} hits ${result.hits[0]} ${result.hits[1]}")
            }
            "SERIES" -> {
                val count = w[1].toInt()
                var random = w[2].toLong()
                val first = Strategy.valueOf(w[3])
                val second = Strategy.valueOf(w[4])
                val wins = LongArray(2)
                val shots = LongArray(2)
                val fastest = arrayOfNulls<Long>(2)
                repeat(count) {
                    random = advance(random)
                    val seed1 = random
                    random = advance(random)
                    val result = playMatch(seed1, random, first, second, Output.QUIET)
                    val side = result.winner
                    wins[side]++
                    for (p in 0..1) shots[p] += result.shots[p]
                    fastest[side] = fastest[side]?.let { minOf(it, result.shots[side]) } ?: result.shots[side]
                }
                val best = fastest.map { it?.toString() ?: "-" }
                emit("SERIES $count wins ${wins[0]} ${wins[1]} shots ${shots[0]} ${shots[1]} fastest ${best[0]} ${best[1]}")
            }
            "TOURNEY" -> {
                val count = w[1].toInt()
                var random = w[2].toLong()
                val wins = LongArray(3)
                val shots = LongArray(3)
                for (first in Strategy.entries)
                    for (second in Strategy.entries) {
                        if (first == second) continue
                        repeat(count) {
                            random = advance(random)
                            val seed1 = random
                            random = advance(random)
                            val result = playMatch(seed1, random, first, second, Output.QUIET)
                            wins[(if (result.winner == 0) first else second).ordinal]++
                            shots[first.ordinal] += result.shots[0]
                            shots[second.ordinal] += result.shots[1]
                        }
                    }
                val order = Strategy.entries.sortedWith(compareByDescending<Strategy> { wins[it.ordinal] }
                    .thenBy { shots[it.ordinal] }.thenBy { it.name })
                emit("TOURNEY $count")
                order.forEachIndexed { rank, strategy ->
                    emit("${rank + 1} $strategy wins ${wins[strategy.ordinal]} shots ${shots[strategy.ordinal]}")
                }
            }
        }
    }
}

fun main() {
    val count = readln().toInt()
    val game = Game()
    repeat(count) {
        val words = readln().split(' ')
        try { game.execute(words) }
        catch (error: GameError) { emit("ERROR ${error.message}") }
    }
    output.flush()
}
