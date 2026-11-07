import java.io.File

fun readBlocks(path: String): List<List<String>> {
    val result = mutableListOf<List<String>>(); var current = mutableListOf<String>(); var inside = false
    for (text in File(path).readLines()) {
        if (!inside) { if (text.isNotEmpty() && !text.startsWith('#')) { current = mutableListOf(text); inside = true } }
        else if (text == "END") { result += current; current = mutableListOf(); inside = false }
        else current += text
    }
    return result
}
fun validName(name: String): Boolean = name.length in 1..20 && name.all { it in 'a'..'z' || it in '0'..'9' || it == '_' }
fun numberList(numbers: List<Int>): String = if (numbers.isEmpty()) "-" else numbers.joinToString(",")
fun cellText(cell: Cell): String = "${cell.row + 1},${cell.column + 1}"
fun stateGrid(lines: List<String>): List<MutableList<Int>> = lines.map { it.map(::charState).toMutableList() }
fun gridColumns(grid: List<List<Int>>): List<List<Int>> = grid.first().indices.map { lineCells(grid, false, it) }
fun differingCells(first: List<List<Int>>, second: List<List<Int>>): List<Cell> = first.indices.flatMap { row -> first[row].indices.filter { first[row][it] != second[row][it] }.map { Cell(row, it) } }
data class Given(val row: Int, val column: Int, val state: Int) { val cell: Cell get() = Cell(row, column) }
data class RawGiven(val row: Int, val column: Int, val value: String)
fun checkClues(lines: List<String>, kind: String, length: Int): Pair<List<List<Int>>, String> {
    val result = mutableListOf<List<Int>>()
    for ((index, text) in lines.withIndex()) { val clue = parseClue(text) ?: return emptyList<List<Int>>() to "bad clue $kind ${index + 1}"; if (!clueFits(clue, length)) return emptyList<List<Int>>() to "$kind ${index + 1} too long"; result += clue }
    return result to ""
}
class Puzzle(texts: List<String>) {
    val name = texts[0].drop(7)
    private val dimensions = texts[1].split(' ')
    val width = dimensions[1].toInt()
    val height = dimensions[2].toInt()
    val rowLines: List<String>
    val columnLines: List<String>
    val givenLines: List<RawGiven>
    val answerPresent: Boolean
    val answerLines: List<String>
    var rowClues = emptyList<List<Int>>()
    var columnClues = emptyList<List<Int>>()
    val givens = mutableListOf<Given>()
    var answer = emptyList<MutableList<Int>>()
    init {
        var position = 3
        while (texts[position] != "COLUMNS") position++
        rowLines = texts.subList(3, position).toList(); position++
        val columns = mutableListOf<String>(); val given = mutableListOf<RawGiven>()
        while (position < texts.size && isClueLine(texts[position])) columns += texts[position++]
        while (position < texts.size && texts[position].startsWith("GIVEN ")) { val fields = texts[position++].split(' '); given += RawGiven(fields[1].toInt(), fields[2].toInt(), fields[3]) }
        columnLines = columns; givenLines = given; answerPresent = position < texts.size; answerLines = if (answerPresent) texts.drop(position + 1) else emptyList()
    }
    fun validate(earlier: Set<String>): String {
        if (!validName(name)) return "bad name"
        if (name in earlier) return "duplicate name"
        if (width !in 1..30 || height !in 1..30) return "bad size"
        if (rowLines.size != height) return "row count ${rowLines.size} expected $height"
        if (columnLines.size != width) return "column count ${columnLines.size} expected $width"
        val (rows, rowProblem) = checkClues(rowLines, "row", width); if (rowProblem.isNotEmpty()) return rowProblem
        val (columns, columnProblem) = checkClues(columnLines, "column", height); if (columnProblem.isNotEmpty()) return columnProblem
        rowClues = rows; columnClues = columns
        val rowTotal = rows.sumOf { it.sum() }; val columnTotal = columns.sumOf { it.sum() }
        if (rowTotal != columnTotal) return "total mismatch rows=$rowTotal columns=$columnTotal"
        val taken = mutableSetOf<Cell>()
        for ((index, given) in givenLines.withIndex()) {
            if (given.row !in 1..height || given.column !in 1..width || given.value !in listOf("#", ".")) return "bad given ${index + 1}"
            if (!taken.add(Cell(given.row, given.column))) return "duplicate given ${index + 1}"
            givens += Given(given.row - 1, given.column - 1, if (given.value == "#") FILLED else EMPTY)
        }
        if (answerPresent) { if (answerLines.size != height || answerLines.any { it.length != width || it.any { character -> character !in "#.?" } }) return "bad answer"; answer = stateGrid(answerLines) }
        return ""
    }
}
class Picture(texts: List<String>) {
    val name = texts[0].drop(8)
    val rows = texts.drop(1)
    fun validate(earlier: Set<String>): String {
        if (!validName(name)) return "bad name"
        if (name in earlier) return "duplicate name"
        if (rows.size !in 1..30) return "bad height"
        for ((index, row) in rows.withIndex()) if (row.length !in 1..30 || row.length != rows.first().length || row.any { it != '#' && it != '.' }) return "bad row ${index + 1}"
        return ""
    }
}
data class Logical(val grid: List<List<Int>>, val details: Propagation, val result: String)
fun logicalSolve(rows: List<List<Int>>, columns: List<List<Int>>, givens: List<Given>, precise: Boolean): Logical {
    val grid = List(rows.size) { MutableList(columns.size) { UNKNOWN } }
    for (given in givens) grid[given.row][given.column] = given.state
    val details = propagate(grid, rows, columns, precise, BooleanArray(rows.size) { true }, BooleanArray(columns.size) { true })
    val result = details.conflict?.let { "contradiction at=${it.label}" } ?: if (determinedCount(grid) == rows.size * columns.size) "solved" else "stuck"
    return Logical(grid, details, result)
}
class Analysis(rows: List<List<Int>>, columns: List<List<Int>>, givens: List<Given>) {
    val simple = logicalSolve(rows, columns, givens, false)
    val logic = logicalSolve(rows, columns, givens, true)
    val search = Search(rows, columns)
    var searched = false
    var solutions = emptyList<List<List<Int>>>()
    var difficulty = "-"
    var status = "contradiction"
    init {
        if (logic.details.conflict == null) {
            if (logic.result == "solved") { status = "unique"; solutions = listOf(logic.grid); difficulty = if (simple.result == "solved") "easy" else "medium" }
            else { searched = true; search.run(logic.grid); solutions = search.solutions; status = if (solutions.isEmpty()) "none" else if (solutions.size == 1) "unique" else "multiple"; if (status == "unique") difficulty = "hard" }
        }
    }
    val lineSolves: Int get() = logic.details.steps.size + search.lineSolves
    val guesses: Int get() = search.guesses.size
    val maxDepth: Int get() = search.maxDepth
}
fun clueStatistics(rows: List<List<Int>>, columns: List<List<Int>>): String {
    val rowBlocks = rows.sumOf { it.size }; val columnBlocks = columns.sumOf { it.size }; val filled = rows.sumOf { it.sum() }; val maxBlock = (rows + columns).flatten().maxOrNull() ?: 0
    val fixed = rows.count { it.isEmpty() || it.sum() + it.size - 1 == columns.size } + columns.count { it.isEmpty() || it.sum() + it.size - 1 == rows.size }
    return "row_blocks=$rowBlocks column_blocks=$columnBlocks filled=$filled max_block=$maxBlock fixed_lines=$fixed"
}
fun stepStatistics(details: Propagation): String {
    val steps = details.steps.filter { !it.contradiction }; val productive = steps.count { it.gain > 0 }; val best = steps.maxOfOrNull { it.gain } ?: 0
    val at = if (best == 0) "-" else steps.first { it.gain == best }.label
    return "productive=$productive idle=${steps.size - productive} best=$best at=$at"
}
fun featuresText(grid: List<List<Int>>): String {
    val height = grid.size; val width = grid.first().size; val seen = Array(height) { BooleanArray(width) }
    var filled = 0; var components = 0; var largest = 0; var minRow = height; var minColumn = width; var maxRow = -1; var maxColumn = -1
    var lr = true; var ud = true; var rot180 = true
    for (row in 0 until height) for (column in 0 until width) {
        lr = lr && grid[row][column] == grid[row][width - 1 - column]; ud = ud && grid[row][column] == grid[height - 1 - row][column]; rot180 = rot180 && grid[row][column] == grid[height - 1 - row][width - 1 - column]
        if (grid[row][column] != FILLED) continue
        filled++; minRow = minOf(minRow, row); minColumn = minOf(minColumn, column); maxRow = maxOf(maxRow, row); maxColumn = maxOf(maxColumn, column)
        if (seen[row][column]) continue
        seen[row][column] = true
        val stack = ArrayDeque<Cell>(); stack.addLast(Cell(row, column)); var count = 0
        while (stack.isNotEmpty()) {
            val current = stack.removeLast(); count++
            for ((dr, dc) in listOf(-1 to 0, 1 to 0, 0 to -1, 0 to 1)) { val r = current.row + dr; val c = current.column + dc; if (r in 0 until height && c in 0 until width && grid[r][c] == FILLED && !seen[r][c]) { seen[r][c] = true; stack.addLast(Cell(r, c)) } }
        }
        components++; largest = maxOf(largest, count)
    }
    val bbox = if (filled == 0) "-" else "${minRow + 1},${minColumn + 1},${maxRow + 1},${maxColumn + 1}"
    val symmetries = listOf("lr" to lr, "ud" to ud, "rot180" to rot180).filter { it.second }.map { it.first }
    return "filled=$filled components=$components largest=$largest bbox=$bbox symmetry=${if (symmetries.isEmpty()) "none" else symmetries.joinToString(",")}"
}
fun unknownSummary(lines: List<List<Int>>): String = lines.mapIndexedNotNull { index, cells -> val count = cells.count { it == UNKNOWN }; if (count > 0) "${index + 1}:$count" else null }.joinToString(" ")
fun searchLines(search: Search): List<String> = listOf("search guesses=${search.guesses.size} max_depth=${search.maxDepth} backtracks=${search.backtracks} solutions=${search.solutions.size} line_solves=${search.lineSolves}") + search.guesses.map { "guess ${it.number} depth=${it.depth} cell=${cellText(it.cell)} value=${stateChar(it.value)} solves=${it.solves} known=${it.known} result=${it.result}" }
fun displayLines(analysis: Analysis): List<String> {
    val names = mutableListOf<String>(); val grids = mutableListOf<List<List<Int>>>()
    if (analysis.status == "contradiction") { names += "partial"; grids += analysis.logic.grid }
    else { if (analysis.simple.result == "stuck") { names += "simple"; grids += analysis.simple.grid }; if (analysis.logic.result == "stuck") { names += "logic"; grids += analysis.logic.grid }; if (analysis.status == "multiple") { names += listOf("first", "second"); grids += analysis.solutions } }
    return if (names.isEmpty()) emptyList() else gridDisplay(names, grids)
}
fun evaluateGivens(puzzle: Puzzle, analysis: Analysis): String {
    if (puzzle.givens.isEmpty() || analysis.status == "multiple") return ""
    val numbers = puzzle.givens.indices.filter { index -> val others = puzzle.givens.filterIndexed { position, _ -> position != index }; val status = Analysis(puzzle.rowClues, puzzle.columnClues, others).status; status == "unique" || analysis.status != "unique" && status == "multiple" }.map { it + 1 }
    return "givens ${if (analysis.status == "unique") "redundant" else "blame"}=${numberList(numbers)}"
}
data class Grading(val result: String, val lines: List<String>)
fun gradeAnswer(puzzle: Puzzle, analysis: Analysis): Grading {
    val rows = (0 until puzzle.height).filter { !hasPlacement(puzzle.answer[it], puzzle.rowClues[it]) }; val columns = (0 until puzzle.width).filter { !hasPlacement(lineCells(puzzle.answer, false, it), puzzle.columnClues[it]) }
    val givens = puzzle.givens.indices.filter { val given = puzzle.givens[it]; val state = puzzle.answer[given.row][given.column]; state != UNKNOWN && state != given.state }
    val known = determinedCount(puzzle.answer); val mismatched = rows.isNotEmpty() || columns.isNotEmpty() || givens.isNotEmpty()
    val result = if (known < puzzle.width * puzzle.height) "partial" else if (mismatched) "wrong" else "correct"
    var text = "answer result=$result known=$known rows=${numberList(rows.map { it + 1 })} columns=${numberList(columns.map { it + 1 })} givens=${numberList(givens.map { it + 1 })}"
    if (result == "partial") {
        var extendable = false
        if (!mismatched) {
            val additions = puzzle.givens.toMutableList(); val givenCells = puzzle.givens.map { it.cell }.toSet()
            for (row in 0 until puzzle.height) for (column in 0 until puzzle.width) if (puzzle.answer[row][column] != UNKNOWN && Cell(row, column) !in givenCells) additions += Given(row, column, puzzle.answer[row][column])
            extendable = Analysis(puzzle.rowClues, puzzle.columnClues, additions).status in listOf("unique", "multiple")
        }
        text += " extendable=${if (extendable) "yes" else "no"}"
    }
    if (analysis.status == "unique") { val differs = puzzle.answer.indices.sumOf { row -> puzzle.answer[row].indices.count { puzzle.answer[row][it] != UNKNOWN && puzzle.answer[row][it] != analysis.solutions[0][row][it] } }; text += " differs=$differs" }
    val lines = mutableListOf(text)
    for ((isRow, indices) in listOf(true to rows, false to columns)) for (index in indices) { val clue = if (isRow) puzzle.rowClues[index] else puzzle.columnClues[index]; val cells = lineCells(puzzle.answer, isRow, index); val suffix = if (result == "partial") "cells=${stateString(cells)}" else "got=${clueText(runClue(cells), ",")}"; lines += "mismatch ${lineLabel(isRow, index)} expected=${clueText(clue, ",")} $suffix" }
    return Grading(result, lines)
}

class Report(val puzzle: Puzzle) {
    val analysis = Analysis(puzzle.rowClues, puzzle.columnClues, puzzle.givens)
    val evaluation = evaluateGivens(puzzle, analysis)
    val grading = if (puzzle.answerPresent) gradeAnswer(puzzle, analysis) else Grading("-", emptyList())
    val score: Int get() = analysis.lineSolves + 25 * analysis.guesses
    val paragraph: List<String> get() {
        val lines = mutableListOf("PUZZLE ${puzzle.name}",
            "size=${puzzle.width}x${puzzle.height} givens=${puzzle.givens.size} status=${analysis.status} difficulty=${analysis.difficulty}",
            "clues ${clueStatistics(puzzle.rowClues, puzzle.columnClues)}",
            "simple known=${determinedCount(analysis.simple.grid)} line_solves=${analysis.simple.details.steps.size} result=${analysis.simple.result}",
            "logic known=${determinedCount(analysis.logic.grid)} line_solves=${analysis.logic.details.steps.size} result=${analysis.logic.result}",
            "steps ${stepStatistics(analysis.logic.details)}")
        if (puzzle.width * puzzle.height <= 49) lines += "trace ${analysis.logic.details.record}"
        if (analysis.logic.result == "stuck") lines += "stuck rows=${unknownSummary(analysis.logic.grid)} columns=${unknownSummary(gridColumns(analysis.logic.grid))}"
        analysis.logic.details.conflict?.let { conflict -> val clue = if (conflict.isRow) puzzle.rowClues[conflict.index] else puzzle.columnClues[conflict.index]; lines += "conflict line=${conflict.label} clue=${clueText(clue, ",")} cells=${stateString(lineCells(analysis.logic.grid, conflict.isRow, conflict.index))}" }
        if (analysis.searched) lines += searchLines(analysis.search)
        if (analysis.status == "multiple") { val cells = differingCells(analysis.solutions[0], analysis.solutions[1]); lines += "differ count=${cells.size} cells=${cells.joinToString(" ", transform = ::cellText)}" }
        lines += displayLines(analysis)
        if (analysis.status == "unique") { lines += "sheet"; lines += answerSheet(puzzle.rowClues, puzzle.columnClues, analysis.solutions[0]); lines += "picture ${featuresText(analysis.solutions[0])}" }
        if (evaluation.isNotEmpty()) lines += evaluation
        if (puzzle.answerPresent) lines += grading.lines
        return lines
    }
    val statsRow: String get() = listOf(puzzle.name, analysis.status, analysis.difficulty, puzzle.width, puzzle.height, puzzle.givens.size, determinedCount(analysis.simple.grid), determinedCount(analysis.logic.grid), analysis.lineSolves, analysis.guesses, analysis.maxDepth, analysis.solutions.size, grading.result).joinToString(",")
}
fun difficultyOrder(value: String): Int = if (value == "easy") 0 else if (value == "medium") 1 else 2
fun rankingLines(reports: List<Report>): List<String> = listOf("RANKING") + reports.filter { it.analysis.status == "unique" }.sortedWith(compareBy<Report> { difficultyOrder(it.analysis.difficulty) }.thenBy { it.score }.thenBy { it.puzzle.name }).mapIndexed { index, report -> "rank ${index + 1} ${report.puzzle.name} ${report.analysis.difficulty} score=${report.score} size=${report.puzzle.width}x${report.puzzle.height}" }
fun joinParagraphs(paragraphs: List<List<String>>): List<String> = paragraphs.flatMapIndexed { index, paragraph -> (if (index == 0) emptyList() else listOf("")) + paragraph }
fun writeLines(name: String, lines: List<String>) { File("output").mkdirs(); File("output/$name").writeText(if (lines.isEmpty()) "" else lines.joinToString("\n", postfix = "\n")) }
fun processPuzzles(blocks: List<List<String>>): List<Report> {
    val earlier = mutableSetOf<String>(); val reports = mutableListOf<Report>(); val paragraphs = mutableListOf<List<String>>(); val stats = mutableListOf("puzzle,status,difficulty,width,height,givens,simple_known,logic_known,line_solves,guesses,max_depth,solutions,answer")
    for (block in blocks) {
        val puzzle = Puzzle(block); val problem = puzzle.validate(earlier)
        earlier += puzzle.name
        if (problem.isNotEmpty()) { paragraphs += listOf("PUZZLE ${puzzle.name}", "error $problem"); stats += puzzle.name + ",invalid" + ",-".repeat(11) }
        else { val report = Report(puzzle); reports += report; paragraphs += report.paragraph; stats += report.statsRow }
    }
    fun countStatus(status: String): Int = reports.count { it.analysis.status == status }
    fun countDifficulty(difficulty: String): Int = reports.count { it.analysis.difficulty == difficulty }
    paragraphs += rankingLines(reports)
    paragraphs += listOf("SUMMARY puzzles=${blocks.size} invalid=${blocks.size - reports.size} contradiction=${countStatus("contradiction")} none=${countStatus("none")} unique=${countStatus("unique")} multiple=${countStatus("multiple")} easy=${countDifficulty("easy")} medium=${countDifficulty("medium")} hard=${countDifficulty("hard")} line_solves=${reports.sumOf { it.analysis.lineSolves }} guesses=${reports.sumOf { it.analysis.guesses }}")
    writeLines("solutions.txt", joinParagraphs(paragraphs)); writeLines("stats.csv", stats)
    return reports
}
class Generation(val grid: List<List<Int>>) {
    val rowClues = grid.map(::runClue)
    val columnClues = gridColumns(grid).map(::runClue)
    val givens = mutableListOf<Given>()
    val log = mutableListOf<String>()
    val initial = Analysis(rowClues, columnClues, emptyList())
    val finalAnalysis: Analysis
    init {
        var current = initial
        while (current.status == "multiple") {
            val chosen = differingCells(current.solutions[0], current.solutions[1]).first(); val value = grid[chosen.row][chosen.column]
            givens += Given(chosen.row, chosen.column, value); current = Analysis(rowClues, columnClues, givens)
            log += "# hint ${givens.size} cell=${cellText(chosen)} value=${stateChar(value)} status=${current.status}"
        }
        val original = givens.toList()
        for (given in original) { val others = givens.filter { it.cell != given.cell }; if (Analysis(rowClues, columnClues, others).status == "unique") { givens.clear(); givens.addAll(others); log += "# drop cell=${cellText(given.cell)}" } }
        current = Analysis(rowClues, columnClues, givens)
        var logicHints = 0
        while (current.difficulty == "hard") {
            val chosen = guessCell(current.logic.grid); val value = grid[chosen.row][chosen.column]
            givens += Given(chosen.row, chosen.column, value); current = Analysis(rowClues, columnClues, givens); logicHints++
            log += "# logic hint $logicHints cell=${cellText(chosen)} value=${stateChar(value)} difficulty=${current.difficulty}"
        }
        finalAnalysis = current
    }
    fun puzzleLines(name: String): List<String> = listOf("PUZZLE $name", "SIZE ${columnClues.size} ${rowClues.size}", "ROWS") + rowClues.map { clueText(it) } + listOf("COLUMNS") + columnClues.map { clueText(it) } + givens.sortedWith(compareBy<Given> { it.row }.thenBy { it.column }).map { "GIVEN ${it.row + 1} ${it.column + 1} ${stateChar(it.state)}" } + listOf("END")
}
fun processPictures(blocks: List<List<String>>, reports: List<Report>) {
    val earlier = mutableSetOf<String>(); val paragraphs = mutableListOf<List<String>>()
    var valid = 0; var unique = 0; var lineLogic = 0; var hinted = 0; var hints = 0
    for (block in blocks) {
        val picture = Picture(block); val problem = picture.validate(earlier)
        earlier += picture.name
        if (problem.isNotEmpty()) { paragraphs += listOf("# picture ${picture.name} error $problem"); continue }
        val generation = Generation(stateGrid(picture.rows))
        val duplicate = reports.firstOrNull { it.puzzle.rowClues == generation.rowClues && it.puzzle.columnClues == generation.columnClues }?.puzzle?.name ?: "-"
        valid++; if (generation.initial.status == "unique") unique++; if (generation.initial.difficulty in listOf("easy", "medium")) lineLogic++; if (generation.givens.isNotEmpty()) hinted++; hints += generation.givens.size
        val lines = listOf("# picture ${picture.name} size=${generation.grid.first().size}x${generation.grid.size} ${featuresText(generation.grid)}",
            "# clues ${clueStatistics(generation.rowClues, generation.columnClues)} duplicate_of=$duplicate",
            "# plain status=${generation.initial.status} difficulty=${generation.initial.difficulty} line_solves=${generation.initial.lineSolves} guesses=${generation.initial.guesses}") + generation.log + listOf("# final status=${generation.finalAnalysis.status} difficulty=${generation.finalAnalysis.difficulty} hints=${generation.givens.size} line_solves=${generation.finalAnalysis.lineSolves} guesses=${generation.finalAnalysis.guesses}") + generation.puzzleLines(picture.name)
        paragraphs += lines
    }
    paragraphs += listOf("# SUMMARY pictures=${blocks.size} invalid=${blocks.size - valid} unique=$unique line_logic=$lineLogic hinted=$hinted hints=$hints")
    writeLines("generated.txt", joinParagraphs(paragraphs))
}
fun main() { val reports = processPuzzles(readBlocks("input/puzzles.txt")); processPictures(readBlocks("input/pictures.txt"), reports) }
