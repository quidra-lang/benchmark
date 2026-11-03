class Grid(val rows: List<String>) {
    val height = rows.size
    val width = rows.first().length
    val cells = rows.joinToString("").toCharArray()
    val size get() = height * width
    fun cell(row: Int, column: Int) = row * width + column
    fun location(cell: Int) = "${cell / width + 1},${cell % width + 1}"
    fun open(row: Int, column: Int) = row in 0 until height && column in 0 until width && rows[row][column] != '#'
    fun given(cell: Int) = cells[cell] != '#' && cells[cell] != '.'
    fun whites() = cells.indices.filter { cells[it] != '#' }
    fun asymmetric(symmetry: String): Int {
        for (row in 0 until height) for (column in 0 until width) {
            val otherRow = if (symmetry == "rot180") height - 1 - row else row
            if (open(row, column) != open(otherRow, width - 1 - column)) return cell(row, column)
        }
        return -1
    }
    fun components(): Int {
        val seen = BooleanArray(size)
        var count = 0
        val dr = intArrayOf(-1, 1, 0, 0)
        val dc = intArrayOf(0, 0, -1, 1)
        for (start in whites()) {
            if (seen[start]) continue
            count++
            seen[start] = true
            val stack = ArrayDeque<Int>()
            stack.addLast(start)
            while (stack.isNotEmpty()) {
                val point = stack.removeLast()
                val row = point / width
                val column = point % width
                for (i in 0..3) if (open(row + dr[i], column + dc[i])) {
                    val neighbor = cell(row + dr[i], column + dc[i])
                    if (!seen[neighbor]) { seen[neighbor] = true; stack.addLast(neighbor) }
                }
            }
        }
        return count
    }
}
