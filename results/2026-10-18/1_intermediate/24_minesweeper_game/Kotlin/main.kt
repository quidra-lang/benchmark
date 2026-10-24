import java.util.TreeMap
import kotlin.math.abs

private val output = System.out.bufferedWriter()
private fun emit(line: String) { output.write(line); output.write("\n") }
private class CommandError(message: String) : RuntimeException(message)
private fun fail(message: String): Nothing = throw CommandError(message)

private enum class State {
    READY, PLAYING, WON, LOST;
    fun finished() = this == WON || this == LOST
}
private enum class Mark { NONE, FLAG, QUESTION }
private enum class Safety { BLOCK, CELL, NONE }
private enum class MoveKind(val text: String) {
    REVEAL("reveal"), FLAG("flag"), UNFLAG("unflag"), QUESTION("question"), CHORD("chord"),
    AUTO_REVEAL("auto-reveal"), AUTO_FLAG("auto-flag"), GUESS("guess")
}
private enum class Command(val arguments: Int) {
    NEW(4), PRESET(2), LAYOUT(2), SAFETY(1), RESTART(0), REVEAL(2), FLAG(2), UNFLAG(2), QUESTION(2),
    CHORD(2), UNDO(0), SHOW(0), STATUS(0), CELL(2), HISTORY(1), REPLAY(1), HINT(0), AUTO(0),
    ANALYZE(0), PROB(2), FRONTIER(0), SOLVE(0), BOARDINFO(0), STATS(0);

    val hasCell get() = when (this) { REVEAL, FLAG, UNFLAG, QUESTION, CHORD, CELL, PROB -> true; else -> false }
    val needsUnfinished get() = when (this) {
        REVEAL, FLAG, UNFLAG, QUESTION, CHORD, UNDO, HINT, AUTO, ANALYZE, PROB, FRONTIER, SOLVE -> true
        else -> false
    }
    val recordsUndo get() = when (this) { REVEAL, FLAG, UNFLAG, QUESTION, CHORD, AUTO, SOLVE -> true; else -> false }
}

private fun numberWord(word: String): Long {
    if (word.length !in 1..10 || word.length > 1 && word[0] == '0' || word.any { it !in '0'..'9' }) fail("bad arguments")
    return word.toLong()
}

private fun fraction(numerator: Long, denominator: Long): String {
    var a = numerator
    var b = denominator
    while (b != 0L) { val rest = a % b; a = b; b = rest }
    return "${numerator / a}/${denominator / a}"
}

private fun buildNeighbors(width: Int, height: Int) = Array(width * height) { cell ->
    val x = cell % width
    val y = cell / width
    buildList {
        for (dy in -1..1) for (dx in -1..1) {
            if ((dx != 0 || dy != 0) && x + dx in 0 until width && y + dy in 0 until height) add((y + dy) * width + x + dx)
        }
    }.toIntArray()
}

private data class Move(val kind: MoveKind, val cell: Int)
private data class Snapshot(val command: Command, val revealed: BooleanArray, val marks: Array<Mark>, val moves: Int)
private data class Constraint(val cell: Int, val remaining: Int, val unknown: List<Int>)
private enum class ReasonKind { SINGLE, SUBSET, COUNT }
private data class Reason(val kind: ReasonKind, val a: Int = 0, val b: Int = 0) {
    fun text(game: Game) = when (kind) {
        ReasonKind.SINGLE -> "single ${game.coord(a)}"
        ReasonKind.SUBSET -> "subset ${game.coord(a)} ${game.coord(b)}"
        ReasonKind.COUNT -> "count"
    }
}

private class Deduction {
    val safe = TreeMap<Int, Reason>()
    val mines = TreeMap<Int, Reason>()
    fun empty() = safe.isEmpty() && mines.isEmpty()
    fun add(isSafe: Boolean, cell: Int, reason: Reason) { (if (isSafe) safe else mines).putIfAbsent(cell, reason) }
}

private data class AutoResult(var rounds: Int = 0, var flagged: Int = 0, var opened: Int = 0, var guesses: Int = 0)

private class Game(
    val width: Int, val height: Int, val mineCount: Int, val seed: Long,
    val neighbors: Array<IntArray> = buildNeighbors(width, height)
) {
    val cells = width * height
    val safeCells = cells - mineCount
    var determined = false
    val mine = BooleanArray(cells)
    val numbers = IntArray(cells)
    var revealed = BooleanArray(cells)
    var marks = Array(cells) { Mark.NONE }
    var state = State.READY
    var exploded: Int? = null
    val moves = mutableListOf<Move>()
    val undo = ArrayDeque<Snapshot>()

    fun coord(cell: Int) = "${cell % width},${cell / width}"
    fun unknown(cell: Int) = !revealed[cell] && marks[cell] != Mark.FLAG
    fun remaining() = mineCount - marks.count { it == Mark.FLAG }
    fun opened() = revealed.count { it }

    fun copy(keepMoves: Boolean): Game {
        val copy = Game(width, height, mineCount, seed, neighbors) // Geometry is immutable.
        mine.copyInto(copy.mine)
        numbers.copyInto(copy.numbers)
        revealed.copyInto(copy.revealed)
        marks.copyInto(copy.marks)
        copy.determined = determined
        copy.state = state
        copy.exploded = exploded
        if (keepMoves) copy.moves.addAll(moves)
        return copy
    }

    fun restart() {
        revealed.fill(false)
        marks.fill(Mark.NONE)
        moves.clear()
        undo.clear()
        exploded = null
        state = if (determined) State.PLAYING else State.READY
    }

    fun numberBoard() {
        for (cell in 0 until cells) numbers[cell] = neighbors[cell].count { mine[it] }
    }

    fun placeMines(first: Int, safety: Safety) {
        val sx = first % width
        val sy = first / width
        val candidates = (0 until cells).filter { cell ->
            when (safety) {
                Safety.NONE -> true
                Safety.CELL -> cell != first
                Safety.BLOCK -> abs(cell % width - sx) >= 2 || abs(cell / width - sy) >= 2
            }
        }.toMutableList()
        var random = seed
        repeat(mineCount) {
            random = 48271 * random % 2147483647
            mine[candidates.removeAt((random % candidates.size).toInt())] = true
        }
        numberBoard()
        determined = true
        state = State.PLAYING
    }

    fun reveal(cell: Int, safety: Safety): Int {
        if (!determined) placeMines(cell, safety)
        if (mine[cell]) { state = State.LOST; exploded = cell; return 0 }
        val queue = ArrayDeque<Int>()
        revealed[cell] = true
        marks[cell] = Mark.NONE
        queue.addLast(cell)
        var opened = 1
        while (queue.isNotEmpty()) {
            val current = queue.removeFirst()
            if (numbers[current] != 0) continue
            for (next in neighbors[current]) if (unknown(next)) {
                revealed[next] = true
                marks[next] = Mark.NONE
                queue.addLast(next)
                opened++
            }
        }
        return opened
    }

    fun chord(cell: Int, safety: Safety): Int {
        var opened = 0
        for (next in neighbors[cell]) {
            if (unknown(next)) opened += reveal(next, safety)
            if (state == State.LOST) break
        }
        return opened
    }

    fun checkWin() {
        if (state != State.PLAYING || opened() != safeCells) return
        state = State.WON
        for (cell in 0 until cells) if (mine[cell]) marks[cell] = Mark.FLAG
    }

    fun show() {
        for (y in 0 until height) emit(buildString {
            for (x in 0 until width) {
                val cell = y * width + x
                append(when {
                    state == State.LOST && mine[cell] -> if (cell == exploded) '!' else if (marks[cell] == Mark.FLAG) 'F' else '*'
                    state == State.LOST && marks[cell] == Mark.FLAG -> 'X'
                    revealed[cell] -> if (numbers[cell] == 0) '.' else '0' + numbers[cell]
                    marks[cell] == Mark.FLAG -> 'F'
                    marks[cell] == Mark.QUESTION -> '?'
                    else -> '#'
                })
            }
        })
    }

    fun endingOutput() {
        if (state == State.LOST) { emit("boom ${coord(exploded!!)}"); show() }
        else if (state == State.WON) emit("win moves ${moves.size}")
    }

    fun constraints(): List<Constraint> = buildList {
        for (cell in 0 until cells) {
            if (!revealed[cell] || numbers[cell] == 0) continue
            val flags = neighbors[cell].count { marks[it] == Mark.FLAG }
            val unknownCells = neighbors[cell].filter(::unknown)
            if (unknownCells.isNotEmpty()) add(Constraint(cell, numbers[cell] - flags, unknownCells))
        }
    }

    fun deduce(): Deduction {
        val constraints = constraints()
        val result = Deduction()
        for (rule in 1..2) {
            for (c in constraints) {
                val target = if (rule == 1) 0 else c.unknown.size
                if (c.remaining != target) continue
                for (cell in c.unknown) result.add(rule == 1, cell, Reason(ReasonKind.SINGLE, c.cell))
            }
            if (!result.empty()) return result
        }
        val at = arrayOfNulls<Constraint>(cells)
        for (c in constraints) at[c.cell] = c
        for (a in constraints) {
            val ax = a.cell % width
            val ay = a.cell / width
            // Nonempty subset pairs share a neighbor; their centers are within two cells.
            for (y in maxOf(0, ay - 2)..minOf(height - 1, ay + 2)) {
                for (x in maxOf(0, ax - 2)..minOf(width - 1, ax + 2)) {
                    val b = at[y * width + x] ?: continue
                    if (a.unknown.size >= b.unknown.size || !b.unknown.containsAll(a.unknown)) continue
                    val difference = b.remaining - a.remaining
                    if (difference != 0 && difference != b.unknown.size - a.unknown.size) continue
                    for (cell in b.unknown) if (cell !in a.unknown) result.add(difference == 0, cell, Reason(ReasonKind.SUBSET, a.cell, b.cell))
                }
            }
        }
        if (!result.empty()) return result
        if (state == State.PLAYING && remaining() == 0) {
            for (cell in 0 until cells) if (unknown(cell)) result.add(true, cell, Reason(ReasonKind.COUNT))
        }
        return result
    }

    fun hint() {
        val result = deduce()
        when {
            result.safe.isNotEmpty() -> {
                val first = result.safe.firstEntry()
                emit("hint safe ${coord(first.key)} by ${first.value.text(this)}")
            }
            result.mines.isNotEmpty() -> {
                val first = result.mines.firstEntry()
                emit("hint mine ${coord(first.key)} by ${first.value.text(this)}")
            }
            else -> emit("hint none")
        }
    }

    fun autoPlay(safety: Safety): AutoResult {
        val total = AutoResult()
        while (state == State.PLAYING) {
            val result = deduce()
            if (result.empty()) break
            total.rounds++
            for (cell in result.safe.keys) {
                if (revealed[cell]) continue
                moves.add(Move(MoveKind.AUTO_REVEAL, cell))
                total.opened += reveal(cell, safety)
                checkWin()
                if (state.finished()) return total
            }
            for (cell in result.mines.keys) if (unknown(cell)) {
                marks[cell] = Mark.FLAG
                total.flagged++
                moves.add(Move(MoveKind.AUTO_FLAG, cell))
            }
        }
        return total
    }

    fun solve(safety: Safety): AutoResult {
        val total = AutoResult()
        while (!state.finished()) {
            val step = autoPlay(safety)
            total.rounds += step.rounds
            total.flagged += step.flagged
            total.opened += step.opened
            if (state.finished()) break
            val frontier = Frontier(this)
            for (id in frontier.components.indices) frontier.count(id)
            val unknownCount = (0 until cells).count(::unknown).toLong()
            val remainingCount = remaining().coerceAtLeast(0).toLong()
            var choice: Int? = null
            var bestNumerator = 0L
            var bestDenominator = 1L
            for (cell in 0 until cells) {
                if (!unknown(cell)) continue
                val id = frontier.componentOf[cell]
                val numerator = if (id < 0) remainingCount else frontier.ways[cell]
                val denominator = if (id < 0) unknownCount else frontier.components[id].configs
                if (denominator == 0L) continue
                if (choice == null || numerator * bestDenominator < bestNumerator * denominator) {
                    choice = cell
                    bestNumerator = numerator
                    bestDenominator = denominator
                }
            }
            val cell = choice ?: break
            total.guesses++
            moves.add(Move(MoveKind.GUESS, cell))
            total.opened += reveal(cell, safety)
            checkWin()
        }
        return total
    }

    fun probability(cell: Int) {
        val frontier = Frontier(this)
        val id = frontier.componentOf[cell]
        if (id < 0) { emit("prob ${coord(cell)} unconstrained"); return }
        frontier.count(id)
        val component = frontier.components[id]
        if (component.configs == 0L) emit("prob ${coord(cell)} inconsistent")
        else emit("prob ${coord(cell)} ${fraction(frontier.ways[cell], component.configs)} size ${component.cells.size} configs ${component.configs}")
    }

    fun frontierReport() {
        val frontier = Frontier(this)
        emit("frontier ${frontier.components.sumOf { it.cells.size }} components ${frontier.components.size}")
        for (id in frontier.components.indices) {
            frontier.count(id)
            val c = frontier.components[id]
            val start = "component ${coord(c.cells.first())} size ${c.cells.size}"
            if (c.configs == 0L) emit("$start inconsistent")
            else emit("$start configs ${c.configs} min ${c.minimum} max ${c.maximum}")
        }
    }

    fun replay(count: Int, safety: Safety) {
        val copy = copy(false)
        copy.restart()
        for (move in moves.take(count)) {
            val cell = move.cell
            when (move.kind) {
                MoveKind.REVEAL, MoveKind.AUTO_REVEAL, MoveKind.GUESS -> copy.reveal(cell, safety)
                MoveKind.CHORD -> copy.chord(cell, safety)
                MoveKind.FLAG, MoveKind.AUTO_FLAG -> copy.marks[cell] = Mark.FLAG
                MoveKind.UNFLAG -> copy.marks[cell] = Mark.NONE
                MoveKind.QUESTION -> copy.marks[cell] = if (copy.marks[cell] == Mark.QUESTION) Mark.NONE else Mark.QUESTION
            }
            copy.checkWin()
        }
        emit("replay $count/${moves.size}")
        copy.show()
    }

    fun boardInfo() {
        val visited = BooleanArray(cells)
        var openings = 0
        var largest = 0
        var isolated = 0
        for (cell in 0 until cells) {
            if (mine[cell]) continue
            if (numbers[cell] != 0) {
                if (neighbors[cell].none { !mine[it] && numbers[it] == 0 }) isolated++
            } else if (!visited[cell]) {
                openings++
                val covered = BooleanArray(cells)
                val queue = ArrayDeque<Int>()
                queue.addLast(cell)
                visited[cell] = true
                covered[cell] = true
                while (queue.isNotEmpty()) {
                    for (next in neighbors[queue.removeFirst()]) {
                        covered[next] = true
                        if (numbers[next] == 0 && !visited[next]) { visited[next] = true; queue.addLast(next) }
                    }
                }
                largest = maxOf(largest, covered.count { it })
            }
        }
        emit("3bv ${openings + isolated} openings $openings largest $largest mines $mineCount safe $safeCells")
    }

    fun process(command: Command, cell: Int, value: Long, safety: Safety) {
        when (command) {
            Command.REVEAL, Command.FLAG, Command.UNFLAG, Command.QUESTION, Command.PROB -> {
                if (revealed[cell]) fail("already revealed")
                if ((command == Command.REVEAL || command == Command.PROB) && marks[cell] == Mark.FLAG) fail("flagged")
                if (command == Command.FLAG && marks[cell] == Mark.FLAG) fail("already flagged")
                if (command == Command.UNFLAG && marks[cell] != Mark.FLAG) fail("not flagged")
            }
            else -> {}
        }
        when (command) {
            Command.RESTART -> { restart(); emit("restart ${width}x$height mines $mineCount") }
            Command.REVEAL -> {
                moves.add(Move(MoveKind.REVEAL, cell))
                val opened = reveal(cell, safety)
                if (state != State.LOST) { emit("revealed $opened"); checkWin() }
                endingOutput()
            }
            Command.FLAG -> {
                marks[cell] = Mark.FLAG
                moves.add(Move(MoveKind.FLAG, cell))
                emit("flagged ${coord(cell)} left ${remaining()}")
            }
            Command.UNFLAG -> {
                marks[cell] = Mark.NONE
                moves.add(Move(MoveKind.UNFLAG, cell))
                emit("unflagged ${coord(cell)} left ${remaining()}")
            }
            Command.QUESTION -> {
                moves.add(Move(MoveKind.QUESTION, cell))
                marks[cell] = if (marks[cell] == Mark.QUESTION) Mark.NONE else Mark.QUESTION
                emit("${if (marks[cell] == Mark.NONE) "unmarked" else "questioned"} ${coord(cell)} left ${remaining()}")
            }
            Command.CHORD -> {
                if (!revealed[cell]) fail("not revealed")
                if (numbers[cell] == 0) fail("no number")
                val flags = neighbors[cell].count { marks[it] == Mark.FLAG }
                if (flags != numbers[cell]) fail("flags $flags of ${numbers[cell]}")
                if (neighbors[cell].none(::unknown)) fail("nothing to reveal")
                moves.add(Move(MoveKind.CHORD, cell))
                val opened = chord(cell, safety)
                if (state != State.LOST) { emit("chorded $opened"); checkWin() }
                endingOutput()
            }
            Command.UNDO -> {
                val snapshot = undo.removeLastOrNull() ?: fail("nothing to undo")
                revealed = snapshot.revealed
                marks = snapshot.marks
                // Operations only append, so truncating restores the saved move record.
                moves.subList(snapshot.moves, moves.size).clear()
                emit("undo ${snapshot.command.name.lowercase()} moves ${moves.size}")
            }
            Command.SHOW -> show()
            Command.STATUS -> emit("status ${state.name.lowercase()} left ${remaining()} moves ${moves.size} revealed ${opened()}/$safeCells")
            Command.CELL -> {
                if (revealed[cell]) {
                    val flags = neighbors[cell].count { marks[it] == Mark.FLAG }
                    val unknownCount = neighbors[cell].count(::unknown)
                    emit("cell ${coord(cell)} number ${numbers[cell]} flags $flags unknown $unknownCount")
                } else {
                    val opened = neighbors[cell].count { revealed[it] }
                    emit("cell ${coord(cell)} hidden mark ${marks[cell].name.lowercase()} open $opened")
                }
            }
            Command.HISTORY -> {
                emit("history ${moves.size}")
                val count = minOf(value, moves.size.toLong()).toInt()
                for (i in moves.size - count until moves.size) {
                    val move = moves[i]
                    emit("${i + 1} ${move.kind.text} ${coord(move.cell)}")
                }
            }
            Command.REPLAY -> {
                if (value > moves.size) fail("no move $value")
                replay(value.toInt(), safety)
            }
            Command.HINT -> hint()
            Command.AUTO, Command.SOLVE -> {
                val result = if (command == Command.AUTO) autoPlay(safety) else solve(safety)
                if (command == Command.SOLVE) emit("solve guesses ${result.guesses} rounds ${result.rounds} flagged ${result.flagged} revealed ${result.opened}")
                else emit("auto rounds ${result.rounds} flagged ${result.flagged} revealed ${result.opened}")
                endingOutput()
            }
            Command.ANALYZE -> {
                val copy = copy(true)
                val result = copy.autoPlay(safety)
                when (copy.state) {
                    State.LOST -> emit("analyze boom ${copy.coord(copy.exploded!!)} rounds ${result.rounds}")
                    State.WON -> emit("analyze clear rounds ${result.rounds}")
                    else -> emit("analyze stuck rounds ${result.rounds} revealed ${copy.opened()}/${copy.safeCells}")
                }
            }
            Command.PROB -> probability(cell)
            Command.FRONTIER -> frontierReport()
            Command.BOARDINFO -> boardInfo()
            else -> error("Unexpected command $command")
        }
    }
}

private class Component {
    val cells = mutableListOf<Int>()
    var configs = 0L
    var minimum = 0
    var maximum = 0
}
private data class Restriction(val mask: Int, val target: Int)

private fun root(parent: IntArray, cell: Int): Int {
    var current = cell
    while (parent[current] != current) { parent[current] = parent[parent[current]]; current = parent[current] }
    return current
}

private class Frontier(game: Game) {
    private val constraints = game.constraints()
    val componentOf = IntArray(game.cells) { -1 }
    val components = mutableListOf<Component>()
    val ways = LongArray(game.cells)

    init {
        val parent = IntArray(game.cells) { it }
        val ids = IntArray(game.cells) { -1 }
        val present = BooleanArray(game.cells)
        for (c in constraints) for (cell in c.unknown) {
            present[cell] = true
            val left = root(parent, cell)
            val right = root(parent, c.unknown.first())
            parent[left] = right
        }
        for (cell in 0 until game.cells) if (present[cell]) {
            val representative = root(parent, cell)
            if (ids[representative] < 0) { ids[representative] = components.size; components.add(Component()) }
            val id = ids[representative]
            componentOf[cell] = id
            components[id].cells.add(cell)
        }
    }

    fun count(id: Int) {
        val component = components[id]
        val local = IntArray(componentOf.size)
        for ((i, cell) in component.cells.withIndex()) local[cell] = i
        val restrictions = constraints.filter { componentOf[it.unknown.first()] == id }.map { c ->
            Restriction(c.unknown.fold(0) { mask, cell -> mask or (1 shl local[cell]) }, c.remaining)
        }
        val search = Search(component.cells.size, restrictions)
        search.visit(0, 0)
        component.configs = search.configs
        component.minimum = search.minimum
        component.maximum = search.maximum
        for ((i, cell) in component.cells.withIndex()) ways[cell] = search.ways[i]
    }
}

private class Search(val size: Int, val restrictions: List<Restriction>) {
    val ways = LongArray(size)
    var configs = 0L
    var minimum = size + 1
    var maximum = 0

    fun visit(depth: Int, mines: Int) {
        val assigned = (1 shl depth) - 1
        for (c in restrictions) {
            val used = (c.mask and mines).countOneBits()
            val left = (c.mask and assigned.inv()).countOneBits()
            if (used > c.target || used + left < c.target) return
        }
        if (depth == size) {
            val count = mines.countOneBits()
            configs++
            minimum = minOf(minimum, count)
            maximum = maxOf(maximum, count)
            for (i in 0 until size) if (mines and (1 shl i) != 0) ways[i]++
        } else {
            visit(depth + 1, mines)
            visit(depth + 1, mines or (1 shl depth))
        }
    }
}

private class Statistics {
    var played = 0
    var won = 0
    var lost = 0
    var streak = 0
    var best = 0
    var fastest: Int? = null

    fun finish(game: Game) {
        played++
        if (game.state == State.WON) {
            won++
            streak++
            best = maxOf(best, streak)
            fastest = fastest?.let { minOf(it, game.moves.size) } ?: game.moves.size
        } else { lost++; streak = 0 }
    }

    fun show() {
        val rate = if (played == 0) "-" else "${won * 100 / played}%"
        emit("stats played $played won $won lost $lost rate $rate streak $streak best $best fastest ${fastest?.toString() ?: "-"}")
    }
}

private class Table {
    var game: Game? = null
    var safety = Safety.BLOCK
    val stats = Statistics()

    fun layout(width: Int, height: Int, rows: List<String>) {
        for ((i, row) in rows.withIndex()) if (row.length != width || row.any { it != '*' && it != '.' }) fail("bad row ${i + 1}")
        val count = rows.sumOf { it.count { c -> c == '*' } }
        if (count == 0 || count == width * height) fail("bad mine count $count")
        val next = Game(width, height, count, 0)
        for (y in 0 until height) for (x in 0 until width) next.mine[y * width + x] = rows[y][x] == '*'
        next.determined = true
        next.state = State.PLAYING
        next.numberBoard()
        game = next
        emit("layout ${width}x$height mines $count")
    }

    fun execute(words: List<String>) {
        val command = Command.entries.firstOrNull { it.name == words[0] } ?: fail("unknown command ${words[0]}")
        if (words.size != command.arguments + 1) fail("bad arguments")
        val values = LongArray(4)
        var nextSafety = safety
        if (command == Command.PRESET) {
            val preset = when (words[1]) {
                "beginner" -> intArrayOf(9, 9, 10)
                "intermediate" -> intArrayOf(16, 16, 40)
                "expert" -> intArrayOf(30, 16, 99)
                else -> fail("bad arguments")
            }
            for (i in 0..2) values[i] = preset[i].toLong()
            values[3] = numberWord(words[2])
        } else if (command == Command.SAFETY) {
            nextSafety = when (words[1]) {
                "block" -> Safety.BLOCK
                "cell" -> Safety.CELL
                "none" -> Safety.NONE
                else -> fail("bad arguments")
            }
        } else for (i in 1 until words.size) values[i - 1] = numberWord(words[i])
        if (command == Command.NEW || command == Command.PRESET) {
            val (width, height, mines, seed) = values
            if (width !in 1L..30L || height !in 1L..30L || mines < 1 || mines > width * height - 9 || seed !in 1L..2147483646L) fail("bad value")
            game = Game(width.toInt(), height.toInt(), mines.toInt(), seed)
            emit("new ${width}x$height mines $mines")
            return
        }
        if (command == Command.HISTORY && values[0] == 0L) fail("bad value")
        if (command == Command.SAFETY) { safety = nextSafety; emit("safety ${words[1]}"); return }
        if (command == Command.STATS) { stats.show(); return }
        val current = game ?: fail("no game")
        if (command.hasCell && (values[0] >= current.width || values[1] >= current.height)) fail("out of range")
        if (command.needsUnfinished && current.state.finished()) fail("game over")
        if ((command == Command.ANALYZE || command == Command.BOARDINFO) && !current.determined) fail("not started")
        val snapshot = if (command.recordsUndo) Snapshot(command, current.revealed.copyOf(), current.marks.copyOf(), current.moves.size) else null
        val wasFinished = current.state.finished()
        val cell = if (command.hasCell) values[1].toInt() * current.width + values[0].toInt() else 0
        current.process(command, cell, values[0], safety)
        if (snapshot != null && current.moves.size > snapshot.moves) current.undo.addLast(snapshot)
        if (!wasFinished && current.state.finished()) stats.finish(current)
    }
}

fun main() {
    val input = System.`in`.bufferedReader()
    val count = input.readLine().toInt()
    val table = Table()
    repeat(count) {
        val words = input.readLine().split(' ')
        try {
            if (words[0] == "LAYOUT") {
                val width = words[1].toInt()
                val height = words[2].toInt()
                val rows = List(height) { input.readLine() }
                table.layout(width, height, rows)
            } else table.execute(words)
        } catch (error: CommandError) { emit("error: ${error.message}") }
    }
    output.flush()
}
