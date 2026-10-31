data class Level(val cost: Int, val range: Int, val power: Int, val interval: Int, val shotSpeed: Int, val splash: Int, val slowRate: Int, val slowTime: Int, val burnAmount: Int, val burnTime: Int) {
    companion object {
        fun parse(line: String): Level {
            val values = line.split(' ').drop(1).map(String::toInt)
            return Level(values[0], values[1], values[2], values[3], values[4], values[5], values[6], values[7], values[8], values[9])
        }
    }
}
data class TowerType(val name: String, val symbol: Char, val targets: String, val levels: List<Level>)

object Towers {
    val targetModes = setOf("FIRST", "LAST", "STRONGEST", "WEAKEST", "CLOSEST")
    fun parse(lines: List<String>): List<TowerType> {
        val types = mutableListOf<TowerType>()
        var index = 0
        while (index < lines.size) {
            val fields = lines[index].split(' ')
            val count = fields[4].toInt()
            val levels = (1..count).map { Level.parse(lines[index + it]) }
            types.add(TowerType(fields[1], fields[2][0], fields[3], levels))
            index += count + 1
        }
        return types
    }
    fun canAim(targets: String, enemy: Enemy): Boolean = targets == "both" || targets == enemy.kind.movement
}

class Tower(val number: Int, val kind: TowerType, val cell: Cell, val built: Int) {
    var level = 1
    var mode = "FIRST"
    var ready = built
    var investment = kind.levels[0].cost
    var sold: Int? = null
    var shots = 0
    var hits = 0
    var fizzles = 0
    var kills = 0
    var damage = 0
    val standing: Boolean get() = sold == null
    fun stats(): Level = kind.levels[level - 1]
    fun center(): Point = cell.center()
    fun inRange(point: Point): Boolean = Combat.squaredDistance(center(), point) <= stats().range.toLong() * stats().range
    private fun targetKey(enemy: Enemy, field: DistanceField): Long = when (mode) {
        "FIRST" -> enemy.remaining(field).toLong()
        "LAST" -> -enemy.remaining(field).toLong()
        "STRONGEST" -> -enemy.hp.toLong()
        "WEAKEST" -> enemy.hp.toLong()
        else -> Combat.squaredDistance(center(), enemy.position())
    }
    fun selectTarget(enemies: List<Enemy>, field: DistanceField): Enemy? {
        var best: Enemy? = null
        var bestKey = 0L
        for (enemy in enemies) {
            if (!Towers.canAim(kind.targets, enemy) || !inRange(enemy.position())) continue
            val key = targetKey(enemy, field)
            if (best == null || key < bestKey || key == bestKey && enemy.number < best.number) { best = enemy; bestKey = key }
        }
        return best
    }
}
