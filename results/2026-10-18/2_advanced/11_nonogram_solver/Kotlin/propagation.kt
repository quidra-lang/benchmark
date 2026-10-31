fun lineLabel(isRow: Boolean, index: Int): String = (if (isRow) "R" else "C") + (index + 1)
fun lineCells(grid: List<List<Int>>, isRow: Boolean, index: Int): List<Int> = if (isRow) grid[index].toList() else grid.map { it[index] }
fun determinedCount(grid: List<List<Int>>): Int = grid.sumOf { row -> row.count { it != UNKNOWN } }
data class Step(val isRow: Boolean, val index: Int, val gain: Int, val contradiction: Boolean) {
    val label: String get() = lineLabel(isRow, index)
    val text: String get() = label + if (contradiction) "!" else "+$gain"
}
class Propagation { val steps = mutableListOf<Step>(); var conflict: Step? = null; val record: String get() = steps.joinToString(" ") { it.text } }
fun propagate(grid: List<MutableList<Int>>, rowClues: List<List<Int>>, columnClues: List<List<Int>>, precise: Boolean, rowMarks: BooleanArray, columnMarks: BooleanArray): Propagation {
    val rows = rowMarks.copyOf(); val columns = columnMarks.copyOf(); val result = Propagation()
    while (true) {
        val row = rows.indexOf(true); val column = if (row < 0) columns.indexOf(true) else -1
        if (row < 0 && column < 0) return result
        val isRow = row >= 0; val index = if (isRow) row else column
        val clue = if (isRow) { rows[index] = false; rowClues[index] } else { columns[index] = false; columnClues[index] }
        val cells = lineCells(grid, isRow, index)
        val solved = solveLine(cells, clue, precise)
        if (solved == null) { val step = Step(isRow, index, 0, true); result.conflict = step; result.steps += step; return result }
        var gain = 0
        for (position in cells.indices) if (cells[position] == UNKNOWN && solved[position] != UNKNOWN) {
            gain++
            if (isRow) { grid[index][position] = solved[position]; columns[position] = true } else { grid[position][index] = solved[position]; rows[position] = true }
        }
        result.steps += Step(isRow, index, gain, false)
    }
}
