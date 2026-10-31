data class ShortRun(val cell: Int, val direction: String)
class Slot(val index: Int, val number: Int, val across: Boolean, val cells: IntArray) {
    val length = cells.size
    val label = number.toString() + (if (across) "A" else "D")
    val crossings = mutableListOf<Int>()
}
class Layout(val grid: Grid) {
    val numbers = IntArray(grid.size)
    val acrossSlot = IntArray(grid.size) { -1 }
    val downSlot = IntArray(grid.size) { -1 }
    val slots = mutableListOf<Slot>()
    init {
        var count = 0
        for (row in 0 until grid.height) for (column in 0 until grid.width) for (across in listOf(true, false)) {
            if (!Slots.starts(grid, row, column, across)) continue
            val length = Slots.length(grid, row, column, across)
            if (length < 3) continue
            val start = grid.cell(row, column)
            if (numbers[start] == 0) numbers[start] = ++count
            val cells = IntArray(length) { i -> grid.cell(row + (if (across) 0 else i), column + (if (across) i else 0)) }
            val slot = Slot(slots.size, numbers[start], across, cells)
            slots.add(slot)
            val owners = if (across) acrossSlot else downSlot
            for (cell in cells) owners[cell] = slot.index
        }
        for (slot in slots) {
            val owners = if (slot.across) downSlot else acrossSlot
            for (cell in slot.cells) if (owners[cell] >= 0) slot.crossings.add(owners[cell])
            slot.crossings.sort()
        }
    }
    fun owners(cell: Int) = (if (acrossSlot[cell] < 0) 0 else 1) + (if (downSlot[cell] < 0) 0 else 1)
    fun orphan() = grid.whites().firstOrNull { owners(it) == 0 } ?: -1
}
object Slots {
    fun starts(grid: Grid, row: Int, column: Int, across: Boolean) = grid.open(row, column) && !grid.open(row - (if (across) 0 else 1), column - (if (across) 1 else 0))
    fun length(grid: Grid, row: Int, column: Int, across: Boolean): Int {
        var length = 0
        while (grid.open(row + (if (across) 0 else length), column + (if (across) length else 0))) length++
        return length
    }
    fun shortRun(grid: Grid): ShortRun? {
        for (row in 0 until grid.height) for (column in 0 until grid.width) for (across in listOf(true, false))
            if (starts(grid, row, column, across) && length(grid, row, column, across) == 2) return ShortRun(grid.cell(row, column), if (across) "across" else "down")
        return null
    }
}
