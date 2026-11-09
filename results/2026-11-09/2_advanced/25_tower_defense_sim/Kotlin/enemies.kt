class EnemyType(fields: List<String>, known: Map<String, EnemyType>) {
    val name = fields[1]
    val symbol = fields[2][0]
    val movement = fields[3]
    val hp = fields[4].toInt()
    val armor = fields[5].toInt()
    val speed = fields[6].toInt()
    val bounty = fields[7].toInt()
    val lives = fields[8].toInt()
    val regen = fields[9].toInt()
    val splitInto = if (fields[10] == "-") null else known.getValue(fields[10])
    val splitCount = fields[11].toInt()
    var spawned = 0
    var kills = 0
    var leaks = 0
    var damage = 0
}
data class Group(val kind: EnemyType, val spawn: Int, val count: Int, val delay: Int, val interval: Int, val multiplier: Int) {
    fun spawnTick(start: Int, index: Int): Int = start + delay + index * interval
    companion object {
        fun parse(fields: List<String>, known: Map<String, EnemyType>): Group = Group(known.getValue(fields[1]), fields[2].toInt(), fields[3].toInt(), fields[4].toInt(), fields[5].toInt(), fields[6].toInt())
    }
}
class Wave(val reward: Int) {
    val groups = mutableListOf<Group>()
    val enemyCount: Int get() = groups.sumOf { it.count }
}
data class WaveData(val types: List<EnemyType>, val waves: List<Wave>)

object Enemies {
    fun parse(lines: List<String>): WaveData {
        val known = linkedMapOf<String, EnemyType>()
        val waves = mutableListOf<Wave>()
        for (line in lines) {
            val fields = line.split(' ')
            when (fields[0]) {
                "enemy" -> { val type = EnemyType(fields, known); known[type.name] = type }
                "wave" -> waves.add(Wave(fields[1].toInt()))
                else -> waves.last().groups.add(Group.parse(fields, known))
            }
        }
        return WaveData(known.values.toList(), waves)
    }
}

class Enemy(val number: Int, val kind: EnemyType, val multiplier: Int) {
    val maxHp = kind.hp * multiplier / 100
    var hp = maxHp
    val slow = Effect()
    val burn = Effect()
    var alive = true
    var cell = Cell(0, 0)
    var next = Cell(0, 0)
    var progress = 0
    var point = Point(0, 0)
    val flying: Boolean get() = kind.movement == "air"
    fun position(): Point = if (flying) point else Point(100 * cell.x + (next.x - cell.x) * progress, 100 * cell.y + (next.y - cell.y) * progress)
    fun occupiedCell(): Cell = if (flying) Cell((point.x + 50) / 100, (point.y + 50) / 100) else if (progress < 50) cell else next
    fun remaining(field: DistanceField): Int = if (flying) Combat.isqrt(Combat.squaredDistance(point, field.grid.exit.center())) else 100 * field.at(next) + 100 - progress
    fun slowedSpeed(): Int = if (slow.active) kind.speed * (100 - slow.strength) / 100 else kind.speed
    fun split(number: Int): Enemy = Enemy(number, kind.splitInto!!, multiplier).also {
        it.cell = cell; it.next = next; it.progress = progress; it.point = point
    }
}
