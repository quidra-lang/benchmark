import kotlin.math.abs

data class Position(val x: Int, val y: Int)
data class RoomCell(val room: Int, val x: Int, val y: Int)
data class Room(val x: Int, val y: Int, val width: Int, val height: Int) {
    fun center() = Position(x + width / 2, y + height / 2)
}
class Region(val x: Int, val y: Int, val width: Int, val height: Int) {
    lateinit var first: Region
    lateinit var second: Region
    var leaf = -1
}
class Level(val depth: Int, val width: Int, val height: Int) {
    val terrain = Array(height) { CharArray(width) { ' ' } }
    val memory = Array(height) { CharArray(width) { ' ' } }
    val rooms = mutableListOf<Room>()
    lateinit var arrival: Position
    lateinit var target: Position
    var arrivalRoom = 0
    var monstersCreated = 0
    var itemsPlaced = 0
    var kills = 0
    var picked = 0
    val monsters = mutableListOf<Monster>()
    val items = mutableListOf<Item>()
    fun monsterAt(x: Int, y: Int) = monsters.firstOrNull { it.x == x && it.y == y }
    fun itemAt(x: Int, y: Int) = items.firstOrNull { it.x == x && it.y == y }
    fun drawInterior(rng: Minstd, index: Int): Position {
        val room = rooms[index]
        val x = room.x + 1 + rng.rnd(room.width - 2)
        val y = room.y + 1 + rng.rnd(room.height - 2)
        return Position(x, y)
    }
    fun drawRoom(rng: Minstd): RoomCell {
        val room = rng.rnd(rooms.size)
        val cell = drawInterior(rng, room)
        return RoomCell(room, cell.x, cell.y)
    }
}
class DungeonGen(private val rng: Minstd, private val minSize: Int, private val maxSplit: Int, private val roomMin: Int, private val roomMax: Int) {
    fun generate(depth: Int, width: Int, height: Int): Level {
        val level = Level(depth, width, height)
        val root = Region(0, 0, width, height)
        val leaves = mutableListOf<Region>()
        split(root, 0, leaves)
        for (leaf in leaves) level.rooms.add(makeRoom(level, leaf))
        connect(level, root)
        chooseStairs(level)
        return level
    }
    private fun split(region: Region, depth: Int, leaves: MutableList<Region>) {
        val cv = region.width >= 2 * minSize
        val ch = region.height >= 2 * minSize
        if (depth == maxSplit || !(cv || ch)) { region.leaf = leaves.size; leaves.add(region); return }
        val vertical = if (cv && ch) {
            when {
                4 * region.width >= 5 * region.height -> true
                4 * region.height >= 5 * region.width -> false
                else -> rng.draw() % 2 == 0
            }
        } else cv
        if (vertical) {
            val cut = minSize + rng.rnd(region.width - 2 * minSize + 1)
            region.first = Region(region.x, region.y, cut, region.height)
            region.second = Region(region.x + cut, region.y, region.width - cut, region.height)
        } else {
            val cut = minSize + rng.rnd(region.height - 2 * minSize + 1)
            region.first = Region(region.x, region.y, region.width, cut)
            region.second = Region(region.x, region.y + cut, region.width, region.height - cut)
        }
        split(region.first, depth + 1, leaves)
        split(region.second, depth + 1, leaves)
    }
    private fun makeRoom(level: Level, region: Region): Room {
        val width = roomMin + rng.rnd(minOf(roomMax, region.width - 1) - roomMin + 1)
        val height = roomMin + rng.rnd(minOf(roomMax, region.height - 1) - roomMin + 1)
        val x = region.x + rng.rnd(region.width - width)
        val y = region.y + rng.rnd(region.height - height)
        for (row in y until y + height) for (column in x until x + width) level.terrain[row][column] = when {
            row == y || row == y + height - 1 -> '-'
            column == x || column == x + width - 1 -> '|'
            else -> '.'
        }
        return Room(x, y, width, height)
    }
    private fun connect(level: Level, region: Region): MutableList<Int> {
        if (region.leaf >= 0) return mutableListOf(region.leaf)
        val first = connect(level, region.first)
        val second = connect(level, region.second)
        var bestA = -1
        var bestB = -1
        var bestDistance = 0
        for (a in first) for (b in second) {
            val start = level.rooms[a].center()
            val end = level.rooms[b].center()
            val distance = abs(start.x - end.x) + abs(start.y - end.y)
            if (bestA < 0 || distance < bestDistance) { bestA = a; bestB = b; bestDistance = distance }
        }
        val horizontalFirst = rng.draw() % 2 == 0
        dig(level, level.rooms[bestA].center(), level.rooms[bestB].center(), horizontalFirst)
        first.addAll(second)
        return first
    }
    private fun dig(level: Level, start: Position, end: Position, horizontalFirst: Boolean) {
        val path = mutableListOf<Position>()
        val sx = if (end.x >= start.x) 1 else -1
        val sy = if (end.y >= start.y) 1 else -1
        if (horizontalFirst) {
            var x = start.x
            while (true) { path.add(Position(x, start.y)); if (x == end.x) break; x += sx }
            var y = start.y
            while (true) { path.add(Position(end.x, y)); if (y == end.y) break; y += sy }
        } else {
            var y = start.y
            while (true) { path.add(Position(start.x, y)); if (y == end.y) break; y += sy }
            var x = start.x
            while (true) { path.add(Position(x, end.y)); if (x == end.x) break; x += sx }
        }
        for (point in path) when (level.terrain[point.y][point.x]) {
            ' ' -> level.terrain[point.y][point.x] = '#'
            '-', '|' -> level.terrain[point.y][point.x] = '+'
        }
    }
    private fun chooseStairs(level: Level) {
        val drawn = level.drawRoom(rng)
        level.arrivalRoom = drawn.room
        level.arrival = Position(drawn.x, drawn.y)
        level.terrain[drawn.y][drawn.x] = '<'
        var other = rng.rnd(level.rooms.size - 1)
        if (other >= drawn.room) other++
        level.target = level.drawInterior(rng, other)
    }
}
