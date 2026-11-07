import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Path

data class Cell(val x: Int, val y: Int) { fun center(): Point = Point(100 * x, 100 * y) }
data class Point(val x: Int, val y: Int)

class GridMap(val width: Int, val height: Int, val rows: List<String>) {
    val spawns: List<Cell>
    val exit: Cell

    init {
        val found = sortedMapOf<Int, Cell>()
        var destination = Cell(0, 0)
        for (y in 0 until height) for (x in 0 until width) {
            val terrain = rows[y][x]
            if (terrain in '1'..'9') found[terrain - '0'] = Cell(x, y)
            else if (terrain == 'E') destination = Cell(x, y)
        }
        spawns = found.values.toList()
        exit = destination
    }

    fun inside(cell: Cell): Boolean = cell.x in 0 until width && cell.y in 0 until height
    fun terrain(cell: Cell): Char = rows[cell.y][cell.x]
    fun rock(cell: Cell): Boolean = terrain(cell) == '#'
    fun water(cell: Cell): Boolean = terrain(cell) == '~'
    fun buildable(cell: Cell): Boolean = terrain(cell) == '.'

    companion object {
        fun read(): GridMap {
            val lines = Files.readAllLines(Path.of("input", "map.txt"), StandardCharsets.US_ASCII)
            val dimensions = lines[0].split(' ').map(String::toInt)
            return GridMap(dimensions[0], dimensions[1], lines.drop(1).take(dimensions[1]))
        }
    }
}
