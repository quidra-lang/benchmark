const val DIRECTIONS = "udlr"
val DELTAS = listOf(-1 to 0, 1 to 0, 0 to -1, 0 to 1)
val TURNS = mapOf(
    "ROT90" to "rlud",
    "ROT180" to "durl",
    "ROT270" to "lrdu",
    "FLIPH" to "udrl",
    "FLIPV" to "dulr",
)
const val STEP_LETTERS = "udlrUDLR"
const val LEVEL_CHARACTERS = "#-.\$*@+"
const val MAX_SIDE = 10
const val MAX_LIMIT = 100000
val NUMBER_WORD = Regex("0|[1-9][0-9]{0,5}")
val NAME_WORD = Regex("[a-z]{1,8}")

enum class Kind { NUMBER, STEPS, DIRECTION, NAME, TRANSFORM, TEXT }

enum class Command(vararg val kinds: Kind) {
    IMPORT(Kind.TEXT),
    VALID,
    INFO,
    SHOW,
    EXPORT,
    MOVE(Kind.STEPS),
    PUSH(Kind.NUMBER, Kind.NUMBER, Kind.DIRECTION),
    BRING(Kind.NUMBER, Kind.NUMBER, Kind.NUMBER, Kind.NUMBER),
    PATH(Kind.NUMBER, Kind.NUMBER),
    UNDO(Kind.NUMBER),
    REDO(Kind.NUMBER),
    RESET,
    STATUS,
    HISTORY,
    BOXES,
    REACH,
    DEADSQUARES,
    DEADLOCK,
    BOUND,
    SAVE(Kind.NAME),
    RESTORE(Kind.NAME),
    CHECK(Kind.STEPS),
    SOLVE(Kind.NUMBER),
    HINT(Kind.NUMBER),
    PLAY,
    TRANSFORM(Kind.TRANSFORM),
}

class CommandException(message: String) : Exception(message)

class StepException(reason: String) : Exception(reason)

data class Position(val player: Int, val boxes: List<Int>)

data class Push(val box: Int, val direction: Char)

class SearchNode(val boxes: List<Int>, val representative: Int, val parent: Int?, val push: Push?)

class SearchResult(
    val outcome: String,
    val expanded: Int,
    val states: Int,
    val notation: String = "",
)

class Simulation(val position: Position, val letters: String, val failure: String?)

data class Snapshot(val position: Position, val history: String)

data class Solution(val notation: String, val position: Position)

class Assignment(val order: List<Int>, val pushes: List<Int>) {
    val total = pushes.sum()
}

fun decode(text: String, allowed: String): String? {
    val result = StringBuilder()
    var index = 0
    while (index < text.length) {
        val start = index
        while (index < text.length && text[index].isDigit()) {
            index++
        }
        val count = text.substring(start, index)
        if (count.length > 2 || count.startsWith("0") || index == text.length) {
            return null
        }
        if (text[index] !in allowed) {
            return null
        }
        result.append(text[index].toString().repeat(if (count.isEmpty()) 1 else count.toInt()))
        index++
    }
    return result.toString()
}

fun encode(text: String): String {
    val result = StringBuilder()
    var start = 0
    while (start < text.length) {
        var end = start
        while (end < text.length && text[end] == text[start]) {
            end++
        }
        val run = end - start
        if (run > 1) {
            result.append(run)
        }
        result.append(text[start])
        start = end
    }
    return result.toString()
}

fun stepSequence(word: String): String = decode(word, STEP_LETTERS)!!.lowercase()

fun validArgument(kind: Kind, text: String): Boolean = when (kind) {
    Kind.NUMBER -> NUMBER_WORD.matches(text)
    Kind.STEPS -> decode(text, STEP_LETTERS) != null
    Kind.DIRECTION -> text.length == 1 && text in DIRECTIONS
    Kind.NAME -> NAME_WORD.matches(text)
    Kind.TRANSFORM -> text in TURNS
    Kind.TEXT -> true
}

fun pushCount(letters: CharSequence): Int = letters.count { it.isUpperCase() }

fun turnLetters(letters: CharSequence, kind: String): String {
    val turn = TURNS.getValue(kind)
    return letters.map { letter ->
        val direction = turn[DIRECTIONS.indexOf(letter.lowercaseChar())]
        if (letter.isUpperCase()) direction.uppercaseChar() else direction
    }.joinToString("")
}

fun moveBox(boxes: List<Int>, source: Int, destination: Int): List<Int> =
    boxes.map { if (it == source) destination else it }.sorted()

fun counted(label: String, letters: CharSequence): String =
    if (letters.isEmpty()) "$label 0" else "$label ${letters.length} $letters"

fun permutations(items: List<Int>): List<List<Int>> =
    if (items.isEmpty()) {
        listOf(emptyList())
    } else {
        items.flatMap { item -> permutations(items - item).map { listOf(item) + it } }
    }

fun findInterior(height: Int, width: Int, walls: BooleanArray, start: Int): BooleanArray {
    val interior = BooleanArray(height * width)
    interior[start] = true
    val stack = ArrayDeque(listOf(start))
    while (stack.isNotEmpty()) {
        val cell = stack.removeLast()
        val row = cell / width
        val column = cell % width
        for ((dRow, dColumn) in DELTAS) {
            val nextRow = row + dRow
            val nextColumn = column + dColumn
            if (nextRow in 0 until height && nextColumn in 0 until width) {
                val neighbor = nextRow * width + nextColumn
                if (!walls[neighbor] && !interior[neighbor]) {
                    interior[neighbor] = true
                    stack.addLast(neighbor)
                }
            }
        }
    }
    return interior
}

class Level(
    val height: Int,
    val width: Int,
    val walls: BooleanArray,
    val goals: BooleanArray,
    val interior: BooleanArray,
) {
    val size = height * width
    private val offsets = DELTAS.map { (dRow, dColumn) -> dRow * width + dColumn }
    val goalCells = (0 until size).filter { goals[it] }
    var reason: String? = null
    var distances = listOf<Array<Int?>>()
    var dead = BooleanArray(size)

    fun offsetOf(direction: Char): Int = offsets[DIRECTIONS.indexOf(direction)]

    fun cellText(cell: Int): String = "${cell / width + 1} ${cell % width + 1}"

    fun cellAt(row: Int, column: Int): Int = (row - 1) * width + column - 1

    fun contains(row: Int, column: Int): Boolean = row in 1..height && column in 1..width

    private fun onBorder(cell: Int): Boolean {
        val row = cell / width
        val column = cell % width
        return row == 0 || row == height - 1 || column == 0 || column == width - 1
    }

    fun invalidity(players: Int, boxes: List<Int>): String? {
        if (players != 1) {
            return "players $players"
        }
        if (boxes.isEmpty()) {
            return "no boxes"
        }
        if (boxes.size != goalCells.size) {
            return "boxes ${boxes.size} goals ${goalCells.size}"
        }
        for (cell in 0 until size) {
            if (interior[cell] && onBorder(cell)) {
                return "open ${cellText(cell)}"
            }
        }
        for (cell in 0 until size) {
            if ((goals[cell] || cell in boxes) && !interior[cell]) {
                return "outside ${cellText(cell)}"
            }
        }
        return null
    }

    fun analyze() {
        distances = goalCells.map { pushDistances(it) }
        dead = BooleanArray(size) { interior[it] && goalDistance(it) == null }
    }

    private fun pushDistances(goal: Int): Array<Int?> {
        val distance = arrayOfNulls<Int>(size)
        distance[goal] = 0
        val queue = ArrayDeque(listOf(goal))
        while (queue.isNotEmpty()) {
            val cell = queue.removeFirst()
            for (offset in offsets) {
                val box = cell - offset
                if (interior[box] && interior[box - offset] && distance[box] == null) {
                    distance[box] = distance[cell]!! + 1
                    queue.addLast(box)
                }
            }
        }
        return distance
    }

    fun goalDistance(cell: Int): Int? = distances.mapNotNull { it[cell] }.minOrNull()

    fun boxesOnGoals(boxes: List<Int>): Int = boxes.count { goals[it] }

    fun solved(boxes: List<Int>): Boolean = boxesOnGoals(boxes) == boxes.size

    fun reachable(player: Int, boxes: List<Int>): BooleanArray {
        val seen = BooleanArray(size)
        seen[player] = true
        val stack = ArrayDeque(listOf(player))
        while (stack.isNotEmpty()) {
            val cell = stack.removeLast()
            for (offset in offsets) {
                val neighbor = cell + offset
                if (interior[neighbor] && !seen[neighbor] && neighbor !in boxes) {
                    seen[neighbor] = true
                    stack.addLast(neighbor)
                }
            }
        }
        return seen
    }

    fun representative(player: Int, boxes: List<Int>): Int = reachable(player, boxes).indexOf(true)

    fun walkPath(start: Int, target: Int, boxes: List<Int>): String {
        val cameFrom = arrayOfNulls<Pair<Int, Char>>(size)
        val queue = ArrayDeque(listOf(start))
        while (queue.isNotEmpty()) {
            val cell = queue.removeFirst()
            for (direction in DIRECTIONS) {
                val neighbor = cell + offsetOf(direction)
                if (interior[neighbor] && neighbor !in boxes && neighbor != start &&
                    cameFrom[neighbor] == null
                ) {
                    cameFrom[neighbor] = cell to direction
                    queue.addLast(neighbor)
                }
            }
        }
        val directions = StringBuilder()
        var cell = target
        while (cell != start) {
            val (previous, direction) = cameFrom[cell]!!
            directions.append(direction)
            cell = previous
        }
        return directions.reverse().toString()
    }

    fun step(position: Position, direction: Char): Pair<Position, Char> {
        val offset = offsetOf(direction)
        val target = position.player + offset
        if (walls[target]) {
            throw StepException("wall")
        }
        if (target !in position.boxes) {
            return Position(target, position.boxes) to direction
        }
        val beyond = target + offset
        if (walls[beyond] || beyond in position.boxes) {
            throw StepException("blocked")
        }
        val boxes = moveBox(position.boxes, target, beyond)
        return Position(target, boxes) to direction.uppercaseChar()
    }

    fun pushable(box: Int, direction: Char, boxes: List<Int>, reachable: BooleanArray): Boolean {
        val offset = offsetOf(direction)
        val destination = box + offset
        return reachable[box - offset] && interior[destination] && destination !in boxes
    }

    private fun sideBlocked(
        box: Int,
        sides: List<Int>,
        boxes: List<Int>,
        assumed: List<Int>,
    ): Boolean {
        if (sides.any { walls[it] || it in assumed }) {
            return true
        }
        if (sides.all { dead[it] }) {
            return true
        }
        val extended = assumed + box
        return sides.any { it in boxes && frozen(it, boxes, extended) }
    }

    fun frozen(box: Int, boxes: List<Int>, assumed: List<Int>): Boolean {
        val horizontal = listOf(box + offsetOf('l'), box + offsetOf('r'))
        val vertical = listOf(box + offsetOf('u'), box + offsetOf('d'))
        return sideBlocked(box, horizontal, boxes, assumed) &&
            sideBlocked(box, vertical, boxes, assumed)
    }

    fun hasFrozenBox(boxes: List<Int>): Boolean =
        boxes.any { !goals[it] && frozen(it, boxes, emptyList()) }

    private fun splitRows(symbols: List<Char>): List<String> =
        symbols.chunked(width) { it.joinToString("") }

    private fun symbol(cell: Int, position: Position): Char = when {
        walls[cell] -> '#'
        cell == position.player -> if (goals[cell]) '+' else '@'
        cell in position.boxes -> if (goals[cell]) '*' else '$'
        else -> if (goals[cell]) '.' else '-'
    }

    fun render(position: Position): List<String> =
        splitRows((0 until size).map { symbol(it, position) })

    private fun deadSymbol(cell: Int): Char = when {
        walls[cell] -> '#'
        goals[cell] -> '.'
        dead[cell] -> 'x'
        else -> '-'
    }

    fun deadMap(): List<String> = splitRows((0 until size).map { deadSymbol(it) })

    private fun mapCell(kind: String, cell: Int): Int {
        val row = cell / width
        val column = cell % width
        val lastRow = height - 1
        val lastColumn = width - 1
        return when (kind) {
            "ROT90" -> column * height + lastRow - row
            "ROT180" -> (lastRow - row) * width + lastColumn - column
            "ROT270" -> (lastColumn - column) * height + row
            "FLIPH" -> row * width + lastColumn - column
            else -> (lastRow - row) * width + column
        }
    }

    fun mapPosition(kind: String, position: Position): Position =
        Position(mapCell(kind, position.player), position.boxes.map { mapCell(kind, it) }.sorted())

    fun transformed(kind: String): Level {
        val rotated = kind == "ROT90" || kind == "ROT270"
        val movedWalls = BooleanArray(size)
        val movedGoals = BooleanArray(size)
        val movedInterior = BooleanArray(size)
        for (cell in 0 until size) {
            val moved = mapCell(kind, cell)
            movedWalls[moved] = walls[cell]
            movedGoals[moved] = goals[cell]
            movedInterior[moved] = interior[cell]
        }
        val level = if (rotated) {
            Level(width, height, movedWalls, movedGoals, movedInterior)
        } else {
            Level(height, width, movedWalls, movedGoals, movedInterior)
        }
        level.analyze()
        return level
    }
}

fun buildLevel(rows: List<String>): Pair<Level, Position> {
    val height = rows.size
    val width = rows[0].length
    val cells = rows.joinToString("")
    val walls = BooleanArray(cells.length) { cells[it] == '#' }
    val goals = BooleanArray(cells.length) { cells[it] in ".*+" }
    val players = cells.indices.filter { cells[it] in "@+" }
    val boxes = cells.indices.filter { cells[it] in "\$*" }
    val interior = if (players.size == 1) {
        findInterior(height, width, walls, players[0])
    } else {
        BooleanArray(cells.length)
    }
    val level = Level(height, width, walls, goals, interior)
    level.reason = level.invalidity(players.size, boxes)
    if (level.reason == null) {
        level.analyze()
    }
    return level to Position(players.firstOrNull() ?: -1, boxes)
}

fun solutionPushes(nodes: List<SearchNode>): List<Push> =
    generateSequence(nodes.last()) { node -> node.parent?.let { nodes[it] } }
        .mapNotNull { it.push }
        .toList()
        .reversed()

fun solutionNotation(level: Level, start: Position, pushes: List<Push>): String {
    var position = start
    val notation = StringBuilder()
    for ((box, direction) in pushes) {
        val offset = level.offsetOf(direction)
        notation.append(level.walkPath(position.player, box - offset, position.boxes))
        notation.append(direction.uppercaseChar())
        position = Position(box, moveBox(position.boxes, box, box + offset))
    }
    return notation.toString()
}

fun pushSearch(
    level: Level,
    start: Position,
    fixed: List<Int>,
    target: Int?,
    pruning: Boolean,
    limit: Int?,
): SearchResult {
    val first = SearchNode(start.boxes, level.representative(start.player, start.boxes), null, null)
    val nodes = mutableListOf(first)
    val known = hashSetOf(first.boxes to first.representative)
    var expanded = 0
    while (expanded < nodes.size) {
        if (expanded == limit) {
            return SearchResult("limit", expanded, nodes.size)
        }
        val node = nodes[expanded]
        expanded++
        val reachable = level.reachable(node.representative, node.boxes)
        for (box in node.boxes) {
            if (box in fixed) {
                continue
            }
            for (direction in DIRECTIONS) {
                if (!level.pushable(box, direction, node.boxes, reachable)) {
                    continue
                }
                val destination = box + level.offsetOf(direction)
                val boxes = moveBox(node.boxes, box, destination)
                if (pruning && (level.dead[destination] || level.hasFrozenBox(boxes))) {
                    continue
                }
                val representative = level.representative(box, boxes)
                if (!known.add(boxes to representative)) {
                    continue
                }
                nodes.add(SearchNode(boxes, representative, expanded - 1, Push(box, direction)))
                val reached = if (target == null) level.solved(boxes) else destination == target
                if (reached) {
                    val notation = solutionNotation(level, start, solutionPushes(nodes))
                    return SearchResult("found", expanded, nodes.size, notation)
                }
            }
        }
    }
    return SearchResult("no solution", expanded, nodes.size)
}

class Sokoban(rows: List<String>) {
    val output = StringBuilder()
    private lateinit var level: Level
    private lateinit var initial: Position
    private lateinit var current: Position
    private var history = StringBuilder()
    private var redoList = StringBuilder()
    private val snapshots = mutableMapOf<String, Snapshot>()
    private var solution: Solution? = null

    init {
        load(rows)
    }

    private fun emit(line: String) {
        output.append(line).append('\n')
    }

    private fun load(rows: List<String>) {
        val (loadedLevel, position) = buildLevel(rows)
        level = loadedLevel
        initial = position
        current = position
        history = StringBuilder()
        redoList = StringBuilder()
        snapshots.clear()
        solution = null
    }

    private fun cellArgument(arguments: List<String>, index: Int): Int =
        level.cellAt(arguments[index].toInt(), arguments[index + 1].toInt())

    private fun simulate(directions: String): Simulation {
        var position = current
        val letters = StringBuilder()
        try {
            for (direction in directions) {
                val (next, letter) = level.step(position, direction)
                position = next
                letters.append(letter)
            }
        } catch (failure: StepException) {
            val reason = "step ${letters.length + 1} ${failure.message}"
            return Simulation(position, letters.toString(), reason)
        }
        return Simulation(position, letters.toString(), null)
    }

    private fun takeSteps(directions: String): Simulation {
        val simulation = simulate(directions)
        current = simulation.position
        history.append(simulation.letters)
        if (simulation.letters.isNotEmpty()) {
            redoList.clear()
        }
        return simulation
    }

    private fun progress(boxes: List<Int>): String {
        val onGoals = level.boxesOnGoals(boxes)
        val text = "goals $onGoals/${boxes.size}"
        return if (onGoals == boxes.size) "$text solved" else text
    }

    private fun searchSolution(limit: Int): Pair<String, String?> {
        if (level.solved(current.boxes)) {
            return "already solved" to null
        }
        val result = pushSearch(level, current, emptyList(), null, true, limit)
        val counts = "expanded ${result.expanded} states ${result.states}"
        if (result.outcome != "found") {
            return "${result.outcome} $counts" to null
        }
        val notation = result.notation
        return "solution pushes ${pushCount(notation)} moves ${notation.length} $counts" to notation
    }

    private fun loadRows(width: Int, rows: List<String>) {
        rows.forEachIndexed { index, row ->
            if (row.length != width || row.any { it !in LEVEL_CHARACTERS }) {
                throw CommandException("bad row ${index + 1}")
            }
        }
        load(rows)
        emit("loaded ${rows.size}x$width")
    }

    private fun importLevel(text: String) {
        val decoded = text.split("|").map { decode(it, LEVEL_CHARACTERS) }
        val rows = decoded.filterNotNull()
        if (rows.size != decoded.size || rows.size > MAX_SIDE) {
            throw CommandException("bad level")
        }
        val width = rows[0].length
        if (rows.any { it.length != width } || width !in 1..MAX_SIDE) {
            throw CommandException("bad level")
        }
        load(rows)
        emit("loaded ${rows.size}x$width")
    }

    private fun valid() {
        emit(level.reason?.let { "invalid $it" } ?: "valid")
    }

    private fun info() {
        val walls = level.walls.count { it }
        val cells = level.interior.count { it }
        val dead = level.dead.count { it }
        emit(
            "size ${level.height}x${level.width} walls $walls cells $cells " +
                "boxes ${current.boxes.size} dead $dead",
        )
    }

    private fun show() {
        level.render(current).forEach { emit(it) }
    }

    private fun exportLevel() {
        emit("level " + level.render(current).joinToString("|") { encode(it) })
    }

    private fun move(word: String) {
        val simulation = takeSteps(stepSequence(word))
        if (simulation.letters.isNotEmpty()) {
            emit("moved ${simulation.letters}")
        }
        simulation.failure?.let { throw CommandException(it) }
    }

    private fun push(box: Int, direction: Char) {
        val offset = level.offsetOf(direction)
        val boxes = current.boxes
        if (box !in boxes) {
            throw CommandException("no box")
        }
        val destination = box + offset
        if (!level.interior[destination] || destination in boxes) {
            throw CommandException("blocked")
        }
        if (!level.reachable(current.player, boxes)[box - offset]) {
            throw CommandException("unreachable")
        }
        val path = level.walkPath(current.player, box - offset, boxes)
        emit("pushed ${takeSteps(path + direction).letters}")
    }

    private fun bring(source: Int, target: Int) {
        if (source !in current.boxes) {
            throw CommandException("no box")
        }
        if (source == target) {
            emit("brought 0")
            return
        }
        val fixed = current.boxes.filter { it != source }
        val result = pushSearch(level, current, fixed, target, false, null)
        if (result.outcome != "found") {
            throw CommandException("no route")
        }
        takeSteps(result.notation.lowercase())
        emit("brought ${pushCount(result.notation)} ${result.notation}")
    }

    private fun path(target: Int) {
        if (!level.reachable(current.player, current.boxes)[target]) {
            throw CommandException("unreachable")
        }
        val simulation = takeSteps(level.walkPath(current.player, target, current.boxes))
        emit(counted("path", simulation.letters))
    }

    private fun undo(requested: Int) {
        if (history.isEmpty()) {
            throw CommandException("nothing to undo")
        }
        val count = minOf(requested, history.length)
        repeat(count) {
            val letter = history.last()
            history.deleteAt(history.lastIndex)
            val direction = letter.lowercaseChar()
            val offset = level.offsetOf(direction)
            val player = current.player
            val boxes = if (letter.isUpperCase()) {
                moveBox(current.boxes, player + offset, player)
            } else {
                current.boxes
            }
            current = Position(player - offset, boxes)
            redoList.append(direction)
        }
        emit("undone $count")
    }

    private fun redo(requested: Int) {
        if (redoList.isEmpty()) {
            throw CommandException("nothing to redo")
        }
        val count = minOf(requested, redoList.length)
        repeat(count) {
            val direction = redoList.last()
            redoList.deleteAt(redoList.lastIndex)
            val (position, letter) = level.step(current, direction)
            current = position
            history.append(letter)
        }
        emit("redone $count")
    }

    private fun reset() {
        current = initial
        history = StringBuilder()
        redoList = StringBuilder()
        emit("reset")
    }

    private fun status() {
        emit("moves ${history.length} pushes ${pushCount(history)} ${progress(current.boxes)}")
    }

    private fun showHistory() {
        emit(counted("history", history))
    }

    private fun showBoxes() {
        val boxes = current.boxes
        val reachable = level.reachable(current.player, boxes)
        emit("boxes ${boxes.size}")
        for (box in boxes) {
            val distance = level.goalDistance(box) ?: "dead"
            val directions = DIRECTIONS.filter { level.pushable(box, it, boxes, reachable) }
            emit("box ${level.cellText(box)} $distance ${directions.ifEmpty { "-" }}")
        }
    }

    private fun reach() {
        val reachable = level.reachable(current.player, current.boxes)
        emit("reach ${reachable.count { it }} first ${level.cellText(reachable.indexOf(true))}")
    }

    private fun deadSquares() {
        emit("dead ${level.dead.count { it }}")
        level.deadMap().forEach { emit(it) }
    }

    private fun deadlock() {
        val boxes = current.boxes
        val dead = boxes.firstOrNull { level.dead[it] }
        if (dead != null) {
            emit("deadlock dead ${level.cellText(dead)}")
            return
        }
        val frozen = boxes.firstOrNull { !level.goals[it] && level.frozen(it, boxes, emptyList()) }
        emit(if (frozen != null) "deadlock frozen ${level.cellText(frozen)}" else "no deadlock")
    }

    private fun bound() {
        val boxes = current.boxes
        var best: Assignment? = null
        for (order in permutations(level.goalCells.indices.toList())) {
            val pushes = boxes.zip(order) { box, goal -> level.distances[goal][box] }
            if (null in pushes) {
                continue
            }
            val assignment = Assignment(order, pushes.filterNotNull())
            if (best == null || assignment.total < best.total) {
                best = assignment
            }
        }
        if (best == null) {
            emit("bound none")
            return
        }
        emit("bound ${best.total}")
        for (index in boxes.indices) {
            val goal = level.goalCells[best.order[index]]
            emit(
                "box ${level.cellText(boxes[index])} goal ${level.cellText(goal)} " +
                    "pushes ${best.pushes[index]}",
            )
        }
    }

    private fun save(name: String) {
        snapshots[name] = Snapshot(current, history.toString())
        emit("saved $name moves ${history.length}")
    }

    private fun restore(name: String) {
        val snapshot = snapshots[name] ?: throw CommandException("no snapshot $name")
        current = snapshot.position
        history = StringBuilder(snapshot.history)
        redoList.clear()
        emit("restored $name moves ${history.length}")
    }

    private fun check(word: String) {
        val simulation = simulate(stepSequence(word))
        if (simulation.failure != null) {
            emit("check fail ${simulation.failure}")
            return
        }
        val letters = simulation.letters
        val progress = progress(simulation.position.boxes)
        emit("check ok moves ${letters.length} pushes ${pushCount(letters)} $progress")
    }

    private fun solve(limit: Int) {
        val (summary, notation) = searchSolution(limit)
        emit(summary)
        solution = null
        if (notation != null) {
            emit(notation)
            solution = Solution(notation, current)
        }
    }

    private fun hint(limit: Int) {
        val (summary, notation) = searchSolution(limit)
        if (notation == null) {
            emit(summary)
            return
        }
        val part = notation.substring(0, notation.indexOfFirst { it.isUpperCase() } + 1)
        takeSteps(part.lowercase())
        emit("hint $part")
    }

    private fun play() {
        val stored = solution
        if (stored == null || stored.position != current) {
            throw CommandException("no solution")
        }
        takeSteps(stored.notation.lowercase())
        emit("played pushes ${pushCount(stored.notation)} moves ${stored.notation.length}")
    }

    private fun transform(kind: String) {
        val old = level
        level = old.transformed(kind)
        initial = old.mapPosition(kind, initial)
        current = old.mapPosition(kind, current)
        history = StringBuilder(turnLetters(history, kind))
        redoList = StringBuilder(turnLetters(redoList, kind))
        snapshots.replaceAll { _, snapshot ->
            Snapshot(old.mapPosition(kind, snapshot.position), turnLetters(snapshot.history, kind))
        }
        solution = solution?.let {
            Solution(turnLetters(it.notation, kind), old.mapPosition(kind, it.position))
        }
        emit("transformed ${level.height}x${level.width}")
    }

    private fun checkValues(command: Command, arguments: List<String>) {
        val cellCount = when (command) {
            Command.PATH, Command.PUSH -> 1
            Command.BRING -> 2
            else -> 0
        }
        for (index in 0 until 2 * cellCount step 2) {
            if (!level.contains(arguments[index].toInt(), arguments[index + 1].toInt())) {
                throw CommandException("bad value")
            }
        }
        if ((command == Command.UNDO || command == Command.REDO) && arguments[0].toInt() < 1) {
            throw CommandException("bad value")
        }
        if ((command == Command.SOLVE || command == Command.HINT) &&
            arguments[0].toInt() !in 1..MAX_LIMIT
        ) {
            throw CommandException("bad value")
        }
    }

    private fun runCommand(name: String, arguments: List<String>) {
        val command = Command.entries.find { it.name == name }
            ?: throw CommandException("unknown command $name")
        val kinds = command.kinds
        if (arguments.size != kinds.size ||
            !kinds.zip(arguments).all { (kind, text) -> validArgument(kind, text) }
        ) {
            throw CommandException("bad arguments")
        }
        if (command != Command.IMPORT && command != Command.VALID) {
            if (level.reason != null) {
                throw CommandException("invalid level")
            }
            checkValues(command, arguments)
        }
        when (command) {
            Command.IMPORT -> importLevel(arguments[0])
            Command.VALID -> valid()
            Command.INFO -> info()
            Command.SHOW -> show()
            Command.EXPORT -> exportLevel()
            Command.MOVE -> move(arguments[0])
            Command.PUSH -> push(cellArgument(arguments, 0), arguments[2][0])
            Command.BRING -> bring(cellArgument(arguments, 0), cellArgument(arguments, 2))
            Command.PATH -> path(cellArgument(arguments, 0))
            Command.UNDO -> undo(arguments[0].toInt())
            Command.REDO -> redo(arguments[0].toInt())
            Command.RESET -> reset()
            Command.STATUS -> status()
            Command.HISTORY -> showHistory()
            Command.BOXES -> showBoxes()
            Command.REACH -> reach()
            Command.DEADSQUARES -> deadSquares()
            Command.DEADLOCK -> deadlock()
            Command.BOUND -> bound()
            Command.SAVE -> save(arguments[0])
            Command.RESTORE -> restore(arguments[0])
            Command.CHECK -> check(arguments[0])
            Command.SOLVE -> solve(arguments[0].toInt())
            Command.HINT -> hint(arguments[0].toInt())
            Command.PLAY -> play()
            Command.TRANSFORM -> transform(arguments[0])
        }
    }

    fun execute(words: List<String>, rows: List<String>) {
        try {
            if (words[0] == "LOAD") {
                loadRows(words[2].toInt(), rows)
            } else {
                runCommand(words[0], words.drop(1))
            }
        } catch (error: CommandException) {
            emit("error: ${error.message}")
        }
    }
}

fun main() {
    val height = readln().split(" ")[0].toInt()
    val game = Sokoban(List(height) { readln() })
    val count = readln().trim().toInt()
    repeat(count) {
        val words = readln().split(" ")
        val rows = if (words[0] == "LOAD") List(words[1].toInt()) { readln() } else emptyList()
        game.execute(words, rows)
    }
    print(game.output)
}
