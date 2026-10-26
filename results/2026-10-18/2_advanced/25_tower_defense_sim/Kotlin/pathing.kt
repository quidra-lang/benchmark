import java.util.ArrayDeque

object Pathing {
    val directions = listOf(Cell(0, -1), Cell(1, 0), Cell(0, 1), Cell(-1, 0))
    fun neighbor(cell: Cell, direction: Int): Cell = Cell(cell.x + directions[direction].x, cell.y + directions[direction].y)
}

class DistanceField(val grid: GridMap, towers: Set<Cell>) {
    private val distances = Array(grid.height) { IntArray(grid.width) { -1 } }

    init {
        distances[grid.exit.y][grid.exit.x] = 0
        val queue = ArrayDeque<Cell>()
        queue.add(grid.exit)
        while (queue.isNotEmpty()) {
            val cell = queue.removeFirst()
            for (direction in 0 until 4) {
                val next = Pathing.neighbor(cell, direction)
                if (grid.inside(next) && !grid.rock(next) && next !in towers && at(next) < 0) {
                    distances[next.y][next.x] = at(cell) + 1
                    queue.add(next)
                }
            }
        }
    }

    fun at(cell: Cell): Int = distances[cell.y][cell.x]
    fun direction(cell: Cell): Int {
        var best = -1
        var distance = 0
        for (direction in 0 until 4) {
            val next = Pathing.neighbor(cell, direction)
            if (!grid.inside(next) || at(next) < 0) continue
            if (best < 0 || at(next) < distance) { best = direction; distance = at(next) }
        }
        return best
    }
    fun next(cell: Cell): Cell = Pathing.neighbor(cell, direction(cell))
    fun path(start: Cell): List<Cell> {
        val cells = mutableListOf(start)
        while (cells.last() != grid.exit) cells.add(next(cells.last()))
        return cells
    }
}
