data class Dice(val count: Int, val sides: Int) {
    fun roll(rng: Minstd) = rng.roll(count, sides)
    companion object {
        fun parse(token: String): Dice {
            val parts = token.split('d')
            return Dice(parts[0].toInt(), parts[1].toInt())
        }
    }
}
data class Attack(val outcome: String, val damage: Int)
object Combat {
    fun resolve(rng: Minstd, toHit: Int, defense: Int, dice: Dice, bonus: Int): Attack {
        val roll = 1 + rng.rnd(20)
        if (roll == 1) return Attack("miss", 0)
        if (roll == 20) return Attack("critical", maxOf(1, dice.roll(rng) + dice.roll(rng) + bonus))
        if (roll + toHit >= defense) return Attack("hit", maxOf(1, dice.roll(rng) + bonus))
        return Attack("miss", 0)
    }
}
