const val UNKNOWN = 0
const val FILLED = 1
const val EMPTY = 2
fun fitTable(cells: List<Int>, clue: List<Int>): Array<BooleanArray> {
    val empties = IntArray(cells.size + 1)
    for (index in cells.indices) empties[index + 1] = empties[index] + if (cells[index] == EMPTY) 1 else 0
    val table = Array(cells.size + 1) { BooleanArray(clue.size + 1) }
    table[0][0] = true
    for (end in 1..cells.size) {
        for (count in 0..clue.size) {
            var fits = cells[end - 1] != FILLED && table[end - 1][count]
            if (!fits && count > 0) { val start = end - clue[count - 1]; if (start >= 0 && empties[end] == empties[start]) fits = if (start == 0) count == 1 else cells[start - 1] != FILLED && table[start - 1][count - 1] }
            table[end][count] = fits
        }
    }
    return table
}
class LinePlacements(val cells: List<Int>, val clue: List<Int>) {
    val before = fitTable(cells, clue)
    val after = fitTable(cells.asReversed(), clue.asReversed())
    val consistent: Boolean get() = before[cells.size][clue.size]
    fun canStart(block: Int, start: Int): Boolean {
        val end = start + clue[block]
        if (EMPTY in cells.subList(start, end)) return false
        val left = if (start == 0) block == 0 else cells[start - 1] != FILLED && before[start - 1][block]
        val rest = clue.size - block - 1
        val right = if (end == cells.size) rest == 0 else cells[end] != FILLED && after[cells.size - end - 1][rest]
        return left && right
    }
    fun starts(block: Int): List<Int> = (0..cells.size - clue[block]).filter { canStart(block, it) }
    fun canBeEmpty(index: Int): Boolean = cells[index] != FILLED && (0..clue.size).any { before[index][it] && after[cells.size - index - 1][clue.size - it] }
}
fun hasPlacement(cells: List<Int>, clue: List<Int>): Boolean = LinePlacements(cells, clue).consistent
fun solveLine(cells: List<Int>, clue: List<Int>, precise: Boolean): List<Int>? {
    val placements = LinePlacements(cells, clue)
    if (!placements.consistent) return null
    val result = cells.toMutableList(); val fillable = BooleanArray(cells.size); val covered = BooleanArray(cells.size)
    for ((block, length) in clue.withIndex()) {
        val starts = placements.starts(block)
        if (precise) { for (start in starts) for (index in start until start + length) fillable[index] = true }
        else { val low = starts.first(); val high = starts.last(); for (index in high until low + length) if (result[index] == UNKNOWN) result[index] = FILLED; for (index in low until high + length) covered[index] = true }
    }
    for (index in cells.indices) if (result[index] == UNKNOWN) {
        if (precise) { val emptiable = placements.canBeEmpty(index); if (fillable[index] && !emptiable) result[index] = FILLED else if (emptiable && !fillable[index]) result[index] = EMPTY }
        else if (!covered[index]) result[index] = EMPTY
    }
    return result
}
