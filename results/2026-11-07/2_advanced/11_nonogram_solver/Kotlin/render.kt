fun stateChar(state: Int): String = if (state == FILLED) "#" else if (state == EMPTY) "." else "?"
fun charState(character: Char): Int = if (character == '#') FILLED else if (character == '.') EMPTY else UNKNOWN
fun stateString(cells: List<Int>): String = cells.joinToString("", transform = ::stateChar)
fun gridDisplay(names: List<String>, grids: List<List<List<Int>>>): List<String> = listOf("grid ${names.joinToString(" ")}") + grids.first().indices.map { row -> grids.joinToString(" | ") { stateString(it[row]) } }
fun answerSheet(rows: List<List<Int>>, columns: List<List<Int>>, grid: List<List<Int>>): List<String> {
    val tokens = columns.map { clueText(it).split(' ') }
    val width = tokens.flatten().maxOf { it.length } + 1; val depth = tokens.maxOf { it.size }; val margin = rows.maxOf { clueText(it).length }
    val lines = mutableListOf<String>()
    for (row in 0 until depth) lines += (" ".repeat(margin) + tokens.joinToString("") { column -> val skipped = depth - column.size; if (row >= skipped) column[row - skipped].padStart(width) else " ".repeat(width) }).trimEnd(' ')
    for (row in grid.indices) lines += clueText(rows[row]).padStart(margin) + grid[row].joinToString("") { " ".repeat(width - 1) + stateChar(it) }
    return lines
}
