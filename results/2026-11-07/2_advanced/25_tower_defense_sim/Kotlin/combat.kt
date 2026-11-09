import kotlin.math.max
import kotlin.math.min

object Combat {
    data class Advance(val point: Point, val arrived: Boolean)
    fun squaredDistance(first: Point, second: Point): Long {
        val dx = first.x.toLong() - second.x
        val dy = first.y.toLong() - second.y
        return dx * dx + dy * dy
    }
    fun isqrt(value: Long): Int {
        var low = 0L
        var high = value + 1
        while (low + 1 < high) { val middle = (low + high) / 2; if (middle <= value / middle) low = middle else high = middle }
        return low.toInt()
    }
    fun advance(point: Point, goal: Point, step: Int): Advance {
        val dx = goal.x.toLong() - point.x
        val dy = goal.y.toLong() - point.y
        val squared = dx * dx + dy * dy
        if (squared <= step.toLong() * step) return Advance(goal, true)
        val length = isqrt(squared)
        return Advance(Point(point.x + (dx * step / length).toInt(), point.y + (dy * step / length).toInt()), false)
    }
    fun damage(hp: Int, power: Int, armor: Int): Int = min(hp, max(1, power - armor))
}

class Effect {
    var strength = 0
    var remaining = 0
    var source = 0
    val active: Boolean get() = remaining > 0
    fun receive(strength: Int, duration: Int, source: Int) {
        if (strength > this.strength) { this.strength = strength; remaining = duration; this.source = source }
        else if (strength == this.strength) remaining = max(remaining, duration)
    }
    fun advanceTime() { remaining--; if (remaining == 0) { strength = 0; source = 0 } }
}

class Projectile(val number: Int, sourceTower: Tower, sourceTarget: Enemy) {
    val tower = sourceTower.number
    val target = sourceTarget.number
    val targets = sourceTower.kind.targets
    val stats = sourceTower.stats()
    var position = sourceTower.center()
    var aim = sourceTarget.position()
    fun fly(): Boolean {
        if (stats.shotSpeed == 0) return true
        val movement = Combat.advance(position, aim, stats.shotSpeed)
        position = movement.point
        return movement.arrived
    }
}
