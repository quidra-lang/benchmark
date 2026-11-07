class MonsterType(tokens: List<String>) {
    val name = tokens[0]
    val symbol = tokens[1][0]
    val minDepth = tokens[2].toInt()
    val maxDepth = tokens[3].toInt()
    val weight = tokens[4].toInt()
    val hp = Dice.parse(tokens[5])
    val toHit = tokens[6].toInt()
    val defense = tokens[7].toInt()
    val damage = Dice.parse(tokens[8])
    val speed = tokens[9].toInt()
    val xp = tokens[10].toInt()
    val erratic = 'E' in tokens[11]
    val stationary = 'S' in tokens[11]
    val regenerates = 'R' in tokens[11]
    val poisonous = 'P' in tokens[11]
}
class ItemType(val category: String, val name: String, val minDepth: Int, val maxDepth: Int, val weight: Int) {
    lateinit var dice: Dice
    var toHit = 0
    var armor = 0
    var effect = ""
    var poisonTurns = 0
    var nutrition = 0
    companion object {
        fun parse(tokens: List<String>): ItemType {
            val kind = ItemType(tokens[0], tokens[1], tokens[2].toInt(), tokens[3].toInt(), tokens[4].toInt())
            when (kind.category) {
                "weapon" -> { kind.dice = Dice.parse(tokens[5]); kind.toHit = tokens[6].toInt() }
                "armor" -> kind.armor = tokens[5].toInt()
                "potion" -> {
                    kind.effect = tokens[5]
                    if (kind.effect == "heal") kind.dice = Dice.parse(tokens[6])
                    else if (kind.effect == "poison") kind.poisonTurns = tokens[6].toInt()
                }
                "scroll" -> kind.effect = tokens[5]
                "food" -> kind.nutrition = tokens[5].toInt()
                "gold" -> kind.dice = Dice.parse(tokens[5])
            }
            return kind
        }
        fun amulet() = ItemType("amulet", "amulet", 0, 0, 0)
    }
}
class Monster(val number: Int, val kind: MonsterType, var x: Int, var y: Int, var hp: Int, var asleep: Boolean) {
    val maxHp = hp
    var energy = 0
    var wasVisible = false
}
class Item(val kind: ItemType, val x: Int, val y: Int, val amount: Int = 0) {
    var bonus = 0
    fun symbol() = when (kind.category) {
        "weapon" -> ')'; "armor" -> '['; "potion" -> '!'; "scroll" -> '?'; "food" -> '%'; "gold" -> '$'; "amulet" -> '"'
        else -> error("Invalid item class")
    }
    fun displayName(): String {
        val name = kind.name.replace('_', ' ')
        if (kind.category == "weapon" || kind.category == "armor") return "+$bonus $name"
        return if (kind.category == "gold") "$amount gold" else name
    }
    fun referenceName() = if (kind.category == "gold") displayName() else "the " + displayName()
}
