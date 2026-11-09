data class Cell(val row: Int, val column: Int)
fun guessCell(grid: List<List<Int>>): Cell {
    val rows = grid.map { row -> row.count { it == UNKNOWN } }
    val columns = grid.first().indices.map { column -> grid.count { it[column] == UNKNOWN } }
    var best = Cell(-1, -1); var score = 0
    for (row in grid.indices) for (column in grid[row].indices) if (grid[row][column] == UNKNOWN) { val candidate = rows[row] + columns[column]; if (best.row < 0 || candidate < score) { best = Cell(row, column); score = candidate } }
    return best
}
data class Guess(val number: Int, val depth: Int, val cell: Cell, val value: Int, val solves: Int, val known: Int, val result: String)
class Search(val rowClues: List<List<Int>>, val columnClues: List<List<Int>>) {
    val guesses = mutableListOf<Guess>()
    val solutions = mutableListOf<List<List<Int>>>()
    var backtracks = 0
    var maxDepth = 0
    var lineSolves = 0
    fun run(grid: List<List<Int>>, depth: Int = 1): Boolean {
        val chosen = guessCell(grid)
        for (value in listOf(FILLED, EMPTY)) {
            val child = grid.map { it.toMutableList() }
            child[chosen.row][chosen.column] = value
            val rows = BooleanArray(rowClues.size); val columns = BooleanArray(columnClues.size)
            rows[chosen.row] = true; columns[chosen.column] = true
            val details = propagate(child, rowClues, columnClues, true, rows, columns); val known = determinedCount(child)
            val result = if (details.conflict != null) { backtracks++; "contradiction at=${details.conflict!!.label}" } else if (known == rowClues.size * columnClues.size) { solutions += child; "solution${solutions.size}" } else "open"
            maxDepth = maxOf(maxDepth, depth); lineSolves += details.steps.size
            guesses += Guess(guesses.size + 1, depth, chosen, value, details.steps.size, known, result)
            if (result == "open") { if (run(child, depth + 1)) return true } else if (solutions.size == 2) return true
        }
        return false
    }
}
