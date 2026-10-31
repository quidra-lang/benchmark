object Render {
    fun decimal(numerator: Int, denominator: Int, places: Int): String {
        var scale = 1
        repeat(places) { scale *= 10 }
        val rounded = (2 * numerator * scale + denominator) / (2 * denominator)
        return "${rounded / scale}." + (rounded % scale).toString().padStart(places, '0')
    }
    fun gridLines(grid: Grid, letters: CharArray) = (0 until grid.height).map { row -> String(letters, row * grid.width, grid.width) }
    fun numberLines(layout: Layout): List<String> {
        val grid = layout.grid
        return (0 until grid.height).map { row ->
            (0 until grid.width).joinToString(" ") { column ->
                val cell = grid.cell(row, column)
                when {
                    !grid.open(row, column) -> "##"
                    layout.numbers[cell] > 0 -> layout.numbers[cell].toString().padStart(2)
                    else -> " ."
                }
            }
        }
    }
    fun listLine(slot: Slot, clue: String, entry: String, score: String, theme: Boolean) = "${slot.number}. $clue (${slot.length}) $entry $score" + if (theme) " theme" else ""
}
