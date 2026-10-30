data class Cell(val row: Int, val column: Int)
class Canvas(val main: Int, secondary: Int, val direction: String) {
    val vertical = direction in listOf("TB", "BT")
    val rows = if (vertical) main else secondary
    val columns = if (vertical) secondary else main
    val lines = Array(rows) {
        IntArray(columns)
    }
    val arrows = Array(rows) {
        CharArray(columns)
    }
    val boxes = Array(rows) {
        CharArray(columns)
    }
    val highlighted = Array(rows) {
        BooleanArray(columns)
    }
    fun map(main: Int, secondary: Int): Cell {
        val m = if (direction in listOf("BT", "RL")) this.main - 1 - main else main
        return if (vertical) Cell(m, secondary) else Cell(secondary, m)
    }
    fun line(m: Int, c: Int, main: Boolean) {
        val p = map(m, c)
        lines[p.row][p.column] = lines[p.row][p.column] or if (main == vertical) 1 else 2
    }
    fun corner(m: Int, c: Int) {
        val p = map(m, c); lines[p.row][p.column] = lines[p.row][p.column] or 4
    }
    fun arrow(m: Int, c: Int, reversed: Boolean) {
        val p = map(m, c)
        arrows[p.row][p.column] = when {
            direction == "TB" && !reversed || direction == "BT" && reversed -> 'v'
            direction == "TB" && reversed || direction == "BT" && !reversed -> '^'
            direction == "LR" && !reversed || direction == "RL" && reversed -> '>'
            else -> '<'
        }
    }
    fun highlight(row: Int, column: Int) {
        highlighted[row][column] = true
    }
    fun label(row: Int, column: Int, text: String) {
        for ((i, c) in text.withIndex()) boxes[row][column + i] = c
    }
    fun crossings(): Int = lines.sumOf {
        row -> row.count {
            it and 3 == 3
        }
    }
    fun report(): List<String> {
        val result = mutableListOf("    " + (0 until columns).joinToString("") {
            (it % 10).toString()
        })
        for (row in 0 until rows) {
            val text = StringBuilder(row.toString().padStart(3, ' ') + " ")
            for (column in 0 until columns) text.append(when {
                boxes[row][column] != '\u0000' -> boxes[row][column]
                arrows[row][column] != '\u0000' -> arrows[row][column]
                highlighted[row][column] -> '#'
                lines[row][column] == 0 -> ' '
                lines[row][column] == 1 -> '|'
                lines[row][column] == 2 -> '-'
                else -> '+'
            })
            result.add(text.toString().trimEnd(' '))
        }
        return result
    }
}
