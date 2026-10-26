import kotlin.math.abs

object Fov {
    val names = listOf("N", "NE", "E", "SE", "S", "SW", "W", "NW")
    val directions = listOf(Position(0, -1), Position(1, -1), Position(1, 0), Position(1, 1), Position(0, 1), Position(-1, 1), Position(-1, 0), Position(-1, -1))
    fun passable(level: Level, x: Int, y: Int) = level.terrain[y][x] in ".#+<>"
    fun canMove(level: Level, x: Int, y: Int, dx: Int, dy: Int) = passable(level, x + dx, y + dy) && (dx == 0 || dy == 0 || level.terrain[y][x] != '+' && level.terrain[y + dy][x + dx] != '+')
    fun line(x0: Int, y0: Int, x1: Int, y1: Int): List<Position> {
        val dx = abs(x1 - x0)
        val dy = abs(y1 - y0)
        val sx = if (x1 > x0) 1 else -1
        val sy = if (y1 > y0) 1 else -1
        var error = dx - dy
        var x = x0
        var y = y0
        val cells = mutableListOf<Position>()
        while (x != x1 || y != y1) {
            val twice = 2 * error
            if (twice > -dy) { error -= dy; x += sx }
            if (twice < dx) { error += dx; y += sy }
            cells.add(Position(x, y))
        }
        return cells
    }
    fun fieldOfView(level: Level, px: Int, py: Int, radius: Int): Array<BooleanArray> {
        val visible = Array(level.height) { BooleanArray(level.width) }
        for (y in maxOf(0, py - radius) until minOf(level.height, py + radius + 1)) for (x in maxOf(0, px - radius) until minOf(level.width, px + radius + 1)) {
            if ((x - px) * (x - px) + (y - py) * (y - py) > radius * radius) continue
            val cells = line(px, py, x, y)
            visible[y][x] = cells.dropLast(1).all { passable(level, it.x, it.y) }
        }
        return visible
    }
    fun distances(level: Level, px: Int, py: Int): Array<IntArray> {
        val distance = Array(level.height) { IntArray(level.width) { -1 } }
        distance[py][px] = 0
        val queue = ArrayDeque<Position>()
        queue.addLast(Position(px, py))
        while (queue.isNotEmpty()) {
            val point = queue.removeFirst()
            for (direction in directions) {
                val x = point.x + direction.x
                val y = point.y + direction.y
                if (canMove(level, point.x, point.y, direction.x, direction.y) && distance[y][x] < 0) {
                    distance[y][x] = distance[point.y][point.x] + 1
                    queue.addLast(Position(x, y))
                }
            }
        }
        return distance
    }
}
