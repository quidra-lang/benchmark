import java.io.File
import kotlin.math.abs

private val UNARMED = Dice(1, 2)
private val USAGE = listOf("picked", "quaffed", "read", "eaten", "wielded", "worn")
private val COMMAND_CLASSES = mapOf("quaff" to "potion", "read" to "scroll", "wield" to "weapon", "wear" to "armor", "eat" to "food")
private fun readRows(name: String) = File("input", name).readLines(Charsets.US_ASCII).map { it.split(' ') }
private fun decimal(a: Int, b: Int): String {
    if (b == 0) return "-"
    val z = (20 * a + b) / (2 * b)
    return "${z / 10}.${z % 10}"
}
private fun exploration(level: Level): Pair<Int, Int> {
    var explored = 0
    var total = 0
    for (y in 0 until level.height) for (x in 0 until level.width) if (level.terrain[y][x] != ' ') {
        total++
        if (level.memory[y][x] != ' ') explored++
    }
    return explored to total
}
private class Config(rows: List<List<String>>) {
    private val values = rows.associate { it.first() to it.drop(1) }
    private fun number(key: String, index: Int) = values.getValue(key)[index].toInt()
    val generationSeed = number("seed", 0)
    val gameSeed = number("seed", 1)
    val width = number("map", 0)
    val height = number("map", 1)
    val minSize = number("bsp", 0)
    val maxSplit = number("bsp", 1)
    val roomMin = number("room", 0)
    val roomMax = number("room", 1)
    val levels = number("levels", 0)
    val monsterBase = number("monsters", 0)
    val monsterStep = number("monsters", 1)
    val itemBase = number("items", 0)
    val itemStep = number("items", 1)
    val sleepChance = number("sleep", 0)
    val wakeChance = number("sleep", 1)
    val radius = number("fov", 0)
    val maxHp = number("player", 0)
    val regenInterval = number("player", 1)
    val hitDie = Dice.parse(values.getValue("hitdie").first())
    val foodStart = number("food", 0)
    val foodMax = number("food", 1)
    val foodHungry = number("food", 2)
    val foodWeak = number("food", 3)
    val packLimit = number("pack", 0)
    val startItems = values.getValue("start")
    val xpLevels = values.getValue("xp").map { it.toInt() }
    val checkpoints = values.getValue("checkpoints").map { it.toInt() }.toSet()
}
private data class Command(val name: String, val argument: String?)
private fun expandCommands(rows: List<List<String>>): List<Command> {
    val commands = mutableListOf<Command>()
    for (row in rows) {
        val name = row[0]
        val argument = if (name == "wait" || row.size < 2) null else row[1]
        val count = if (name == "wait") { if (row.size == 2) row[1].toInt() else 1 } else if (row.size == 3) row[2].toInt() else 1
        repeat(count) { commands.add(Command(name, argument)) }
    }
    return commands
}
private class Player(config: Config, arrival: Position) {
    var x = arrival.x
    var y = arrival.y
    var depth = 1
    var hp = config.maxHp
    var maxHp = config.maxHp
    var level = 1
    var xp = 0
    var gold = 0
    var satiation = config.foodStart
    var poison = 0
    val pack = mutableListOf<Item>()
    var weapon: Item? = null
    var armor: Item? = null
    fun defense(): Int {
        val worn = armor
        return if (worn == null) 10 else 10 + worn.kind.armor + worn.bonus
    }
}
private class AttackStats {
    var count = 0
    var hits = 0
    var criticals = 0
    var damage = 0
    fun record(attack: Attack) {
        count++
        if (attack.outcome != "miss") { hits++; damage += attack.damage }
        if (attack.outcome == "critical") criticals++
    }
    fun line(label: String) = "$label $count hits $hits criticals $criticals damage $damage accuracy ${decimal(100 * hits, count)}"
}
private class Game(private val config: Config, private val monsterTypes: List<MonsterType>, private val itemTypes: List<ItemType>, private val commands: List<Command>) {
    private val generationRng = Minstd(config.generationSeed)
    private val rng = Minstd(config.gameSeed)
    private val levels = mutableListOf<Level>()
    private val player: Player
    private var turn = 1
    private var succeeded = 0
    private var failed = 0
    private var unused = 0
    private var moves = 0
    private var poisonDamage = 0
    private var starvationDamage = 0
    val messages = mutableListOf<String>()
    val mapLines = mutableListOf<String>()
    private lateinit var visible: Array<BooleanArray>
    private lateinit var distance: Array<IntArray>
    private var result: String? = null
    private var cause: String? = null
    private val playerAttacks = AttackStats()
    private val monsterAttacks = AttackStats()
    private val usage = IntArray(6)
    private val kills = monsterTypes.associate { it.name to 0 }.toMutableMap()
    init {
        buildLevels()
        player = Player(config, levels.first().arrival)
        giveStartItems()
    }
    private fun buildLevels() {
        val generator = DungeonGen(generationRng, config.minSize, config.maxSplit, config.roomMin, config.roomMax)
        for (depth in 1..config.levels) {
            val level = generator.generate(depth, config.width, config.height)
            if (depth < config.levels) level.terrain[level.target.y][level.target.x] = '>'
            else level.items.add(Item(ItemType.amulet(), level.target.x, level.target.y))
            placeMonsters(level)
            placeItems(level)
            levels.add(level)
        }
    }
    private fun placeMonsters(level: Level) {
        val count = config.monsterBase + config.monsterStep * (level.depth - 1)
        val candidates = monsterTypes.filter { level.depth in it.minDepth..it.maxDepth }
        val weights = candidates.map { it.weight }
        for (number in 1..count) {
            val kind = candidates[generationRng.select(weights)]
            var cell: RoomCell
            do { cell = level.drawRoom(generationRng) } while (cell.room == level.arrivalRoom || level.terrain[cell.y][cell.x] != '.' || level.monsterAt(cell.x, cell.y) != null)
            val hp = kind.hp.roll(generationRng)
            val asleep = generationRng.draw() % 100 < config.sleepChance
            level.monsters.add(Monster(number, kind, cell.x, cell.y, hp, asleep))
        }
        level.monstersCreated = count
    }
    private fun placeItems(level: Level) {
        val count = config.itemBase + config.itemStep * (level.depth - 1)
        val candidates = itemTypes.filter { level.depth in it.minDepth..it.maxDepth }
        val weights = candidates.map { it.weight }
        repeat(count) {
            val kind = candidates[generationRng.select(weights)]
            var cell: RoomCell
            do { cell = level.drawRoom(generationRng) } while (level.terrain[cell.y][cell.x] != '.' || level.itemAt(cell.x, cell.y) != null)
            val amount = if (kind.category == "gold") kind.dice.roll(generationRng) else 0
            level.items.add(Item(kind, cell.x, cell.y, amount))
        }
        level.itemsPlaced = level.items.size
    }
    private fun giveStartItems() {
        val kinds = itemTypes.associateBy { it.name }
        for (name in config.startItems) {
            val item = Item(kinds.getValue(name), player.x, player.y)
            player.pack.add(item)
            if (item.kind.category == "weapon" && player.weapon == null) player.weapon = item
            if (item.kind.category == "armor" && player.armor == null) player.armor = item
        }
    }
    private fun currentLevel() = levels[player.depth - 1]
    private fun say(text: String) { messages.add(turn.toString().padStart(4, '0') + " " + text) }
    private fun hunger() = when {
        player.satiation > config.foodHungry -> "normal"
        player.satiation > config.foodWeak -> "hungry"
        player.satiation > 0 -> "weak"
        else -> "starving"
    }
    private fun finish(result: String, cause: String) { this.result = result; this.cause = cause }
    private fun die(cause: String) { say("You die."); finish("died", cause) }
    private fun updateView() {
        val level = currentLevel()
        visible = Fov.fieldOfView(level, player.x, player.y, config.radius)
        for (y in 0 until level.height) for (x in 0 until level.width) if (visible[y][x]) {
            val item = level.itemAt(x, y)
            level.memory[y][x] = item?.symbol() ?: level.terrain[y][x]
        }
        for (monster in level.monsters) {
            val seen = visible[monster.y][monster.x]
            if (seen && !monster.wasVisible) say("You see the ${monster.kind.name}.")
            monster.wasVisible = seen
        }
    }
    fun run() {
        updateView()
        for (command in commands) {
            if (result != null) unused++
            else if (!execute(command)) failed++
            else { succeeded++; if (result == null) advanceTurn() }
        }
        if (result == null) finish("alive", "commands_exhausted")
    }
    private fun advanceTurn() {
        updateView()
        monstersAct()
        if (result != null) return
        endTurn()
        if (result != null) return
        if (turn in config.checkpoints) writeCheckpoint()
        turn++
    }
    private fun execute(command: Command): Boolean = when (command.name) {
        "move" -> { val direction = Fov.directions[Fov.names.indexOf(command.argument)]; move(direction.x, direction.y) }
        "wait" -> true
        "pickup" -> pickup()
        "descend" -> descend()
        else -> useItem(command.name, command.argument!!.toInt())
    }
    private fun move(dx: Int, dy: Int): Boolean {
        val level = currentLevel()
        val x = player.x + dx
        val y = player.y + dy
        if (!Fov.passable(level, x, y)) { say("You bump into a wall."); return false }
        if (!Fov.canMove(level, player.x, player.y, dx, dy)) { say("You cannot move diagonally through a door."); return false }
        val monster = level.monsterAt(x, y)
        if (monster != null) { playerAttack(level, monster); return true }
        player.x = x
        player.y = y
        moves++
        val item = level.itemAt(x, y)
        if (item != null) say("You see ${item.referenceName()} here.")
        else if (level.terrain[y][x] == '>') say("There is a staircase down here.")
        return true
    }
    private fun pickup(): Boolean {
        val level = currentLevel()
        val item = level.itemAt(player.x, player.y)
        if (item == null) { say("There is nothing here."); return false }
        when {
            item.kind.category == "gold" -> { player.gold += item.amount; say("You pick up ${item.displayName()}.") }
            item.kind.category == "amulet" -> { say("You pick up the amulet."); say("You win!"); finish("won", "amulet") }
            player.pack.size >= config.packLimit -> { say("Your pack is full."); return false }
            else -> { player.pack.add(item); say("You pick up the ${item.displayName()} (${player.pack.size}).") }
        }
        level.items.remove(item)
        level.picked++
        usage[0]++
        return true
    }
    private fun descend(): Boolean {
        if (currentLevel().terrain[player.y][player.x] != '>') { say("There are no stairs here."); return false }
        player.depth++
        val arrival = currentLevel().arrival
        player.x = arrival.x
        player.y = arrival.y
        say("You descend to depth ${player.depth}.")
        return true
    }
    private fun useItem(name: String, number: Int): Boolean {
        if (number > player.pack.size) { say("You do not have that item."); return false }
        val item = player.pack[number - 1]
        if (item.kind.category != COMMAND_CLASSES.getValue(name)) { say("You cannot $name that."); return false }
        return when (name) { "quaff" -> quaff(item); "read" -> readScroll(item); "wield" -> wield(item); "wear" -> wear(item); else -> eat(item) }
    }
    private fun quaff(item: Item): Boolean {
        player.pack.remove(item)
        usage[1]++
        say("You quaff the ${item.displayName()}.")
        when (item.kind.effect) {
            "heal" -> {
                player.hp += item.kind.dice.roll(rng)
                if (player.hp > player.maxHp) { player.maxHp++; player.hp = player.maxHp }
                player.poison = 0
                say("You feel better.")
            }
            "poison" -> { player.poison += item.kind.poisonTurns; say("You feel very sick.") }
            "level" -> { say("You feel more experienced."); if (player.level <= config.xpLevels.size) gainXp(config.xpLevels[player.level - 1] - player.xp) }
        }
        return true
    }
    private fun readScroll(item: Item): Boolean {
        val level = currentLevel()
        player.pack.remove(item)
        usage[2]++
        say("You read the ${item.displayName()}.")
        when (item.kind.effect) {
            "mapping" -> {
                for (y in 0 until level.height) for (x in 0 until level.width) if (level.terrain[y][x] != ' ' && level.memory[y][x] == ' ') level.memory[y][x] = level.terrain[y][x]
                say("A map forms in your mind.")
            }
            "teleport" -> {
                var cell: RoomCell
                do { cell = level.drawRoom(rng) } while (cell.x == player.x && cell.y == player.y || level.monsterAt(cell.x, cell.y) != null)
                player.x = cell.x
                player.y = cell.y
                say("You are teleported.")
            }
            "enchant_weapon" -> {
                val weapon = player.weapon
                if (weapon == null) say("Your hands twitch.")
                else { say("Your ${weapon.displayName()} glows blue."); weapon.bonus++ }
            }
            "enchant_armor" -> {
                val armor = player.armor
                if (armor == null) say("Your skin tingles.")
                else { say("Your ${armor.displayName()} glows silver."); armor.bonus++ }
            }
        }
        return true
    }
    private fun wield(item: Item): Boolean {
        if (item === player.weapon) { say("You are already wielding that."); return false }
        player.weapon = item
        usage[4]++
        say("You are now wielding the ${item.displayName()}.")
        return true
    }
    private fun wear(item: Item): Boolean {
        if (item === player.armor) { say("You are already wearing that."); return false }
        player.armor = item
        usage[5]++
        say("You are now wearing the ${item.displayName()}.")
        return true
    }
    private fun eat(item: Item): Boolean {
        player.pack.remove(item)
        usage[3]++
        player.satiation = minOf(player.satiation + item.kind.nutrition, config.foodMax)
        say("You eat the ${item.displayName()}.")
        return true
    }
    private fun playerAttack(level: Level, monster: Monster) {
        val weapon = player.weapon
        monster.asleep = false
        var toHit = player.level + (if (weapon == null) 0 else weapon.kind.toHit + weapon.bonus)
        val bonus = weapon?.bonus ?: 0
        val dice = weapon?.kind?.dice ?: UNARMED
        if (hunger() == "weak" || hunger() == "starving") toHit -= 2
        val name = monster.kind.name
        val attack = Combat.resolve(rng, toHit, monster.kind.defense, dice, bonus)
        playerAttacks.record(attack)
        if (attack.outcome == "miss") { say("You miss the $name."); return }
        say("You hit the $name" + (if (attack.outcome == "critical") " hard for " else " for ") + "${attack.damage}.")
        monster.hp -= attack.damage
        if (monster.hp <= 0) {
            say("You kill the $name.")
            level.monsters.remove(monster)
            level.kills++
            kills[name] = kills.getValue(name) + 1
            gainXp(monster.kind.xp)
        }
    }
    private fun gainXp(amount: Int) {
        player.xp += amount
        while (player.level <= config.xpLevels.size && player.xp >= config.xpLevels[player.level - 1]) {
            player.level++
            val gained = config.hitDie.roll(rng)
            player.maxHp += gained
            player.hp += gained
            say("Welcome to level ${player.level}.")
        }
    }
    private fun monsterAttack(monster: Monster) {
        val kind = monster.kind
        val attack = Combat.resolve(rng, kind.toHit, player.defense(), kind.damage, 0)
        monsterAttacks.record(attack)
        if (attack.outcome == "miss") { say("The ${kind.name} misses you."); return }
        say("The ${kind.name}" + (if (attack.outcome == "critical") " hits you hard for " else " hits you for ") + "${attack.damage}.")
        player.hp -= attack.damage
        if (player.hp <= 0) die("killed_by " + kind.name)
        else if (kind.poisonous) { player.poison += 5; say("You are poisoned.") }
    }
    private fun monstersAct() {
        val level = currentLevel()
        distance = Fov.distances(level, player.x, player.y)
        for (monster in level.monsters) {
            monster.energy += monster.kind.speed
            while (monster.energy >= 2) { monster.energy -= 2; monsterAction(level, monster); if (result != null) return }
        }
    }
    private fun monsterAction(level: Level, monster: Monster) {
        val sees = visible[monster.y][monster.x]
        when {
            monster.asleep -> { if (sees && rng.draw() % 100 < config.wakeChance) { monster.asleep = false; say("The ${monster.kind.name} wakes up.") } }
            monster.kind.stationary -> { if (canAttack(level, monster)) monsterAttack(monster) }
            monster.kind.erratic && rng.draw() % 2 == 0 -> wander(level, monster)
            sees -> chase(level, monster)
            else -> wander(level, monster)
        }
    }
    private fun canAttack(level: Level, monster: Monster): Boolean {
        val dx = player.x - monster.x
        val dy = player.y - monster.y
        return maxOf(abs(dx), abs(dy)) == 1 && Fov.canMove(level, monster.x, monster.y, dx, dy)
    }
    private fun wander(level: Level, monster: Monster) {
        val direction = Fov.directions[rng.draw() % 8]
        if (!Fov.canMove(level, monster.x, monster.y, direction.x, direction.y)) return
        val x = monster.x + direction.x
        val y = monster.y + direction.y
        if (x == player.x && y == player.y) monsterAttack(monster)
        else if (level.monsterAt(x, y) == null) { monster.x = x; monster.y = y }
    }
    private fun chase(level: Level, monster: Monster) {
        if (canAttack(level, monster)) { monsterAttack(monster); return }
        val here = distance[monster.y][monster.x]
        var best: Position? = null
        var bestDistance = 0
        for (direction in Fov.directions) {
            if (!Fov.canMove(level, monster.x, monster.y, direction.x, direction.y)) continue
            val x = monster.x + direction.x
            val y = monster.y + direction.y
            val next = distance[y][x]
            if (next < 0 || here >= 0 && next >= here || level.monsterAt(x, y) != null || x == player.x && y == player.y) continue
            if (best == null || next < bestDistance) { best = Position(x, y); bestDistance = next }
        }
        if (best != null) { monster.x = best.x; monster.y = best.y }
    }
    private fun endTurn() {
        for (monster in currentLevel().monsters) if (monster.kind.regenerates && monster.hp < monster.maxHp) monster.hp++
        if (player.poison > 0) {
            player.hp--
            poisonDamage++
            if (player.hp <= 0) { die("poison"); return }
            player.poison--
            if (player.poison == 0) say("You feel less sick.")
        }
        if (player.satiation == 0) {
            player.hp--
            starvationDamage++
            if (player.hp <= 0) { die("starvation"); return }
        } else {
            val before = hunger()
            player.satiation--
            val after = hunger()
            if (after != before) say(when (after) { "hungry" -> "You are getting hungry."; "weak" -> "You feel weak from hunger."; else -> "You are starving." })
        }
        if (turn % config.regenInterval == 0 && player.poison == 0 && player.satiation > 0 && player.hp < player.maxHp) player.hp++
    }
    private fun viewSymbol(level: Level, x: Int, y: Int): Char {
        if (x == player.x && y == player.y) return '@'
        val monster = level.monsterAt(x, y)
        if (monster != null) return monster.kind.symbol
        return level.itemAt(x, y)?.symbol() ?: level.terrain[y][x]
    }
    private fun mapRows(level: Level, current: Boolean): List<String> {
        val border = "+" + "-".repeat(level.width) + "+"
        val lines = mutableListOf(border)
        for (y in 0 until level.height) {
            val row = StringBuilder("|")
            for (x in 0 until level.width) row.append(if (current && visible[y][x]) viewSymbol(level, x, y) else level.memory[y][x])
            row.append('|')
            lines.add(row.toString())
        }
        lines.add(border)
        return lines
    }
    private fun status() = "STATUS hp ${player.hp}/${player.maxHp} level ${player.level} xp ${player.xp} defense ${player.defense()} gold ${player.gold} food ${player.satiation} ${hunger()} poison ${player.poison}"
    private fun writeCheckpoint() {
        mapLines.add("CHECKPOINT turn $turn depth ${player.depth}")
        mapLines.addAll(mapRows(currentLevel(), true))
        mapLines.add(status())
    }
    fun finalBlock(): List<String> {
        val lines = mutableListOf("FINAL turn $succeeded depth ${player.depth}")
        for (level in levels.take(player.depth)) {
            val (explored, total) = exploration(level)
            lines.add("LEVEL ${level.depth} explored $explored/$total")
            lines.addAll(mapRows(level, level.depth == player.depth))
        }
        lines.add(status())
        return lines
    }
    private fun itemLabel(item: Item?) = item?.displayName() ?: "-"
    fun stats(): List<String> {
        val lines = mutableListOf("result $result", "cause $cause", "turns $succeeded", "depth ${player.depth}", "level ${player.level}", "xp ${player.xp}",
            "hp ${player.hp}/${player.maxHp}", "defense ${player.defense()}", "gold ${player.gold}", "food ${player.satiation} ${hunger()}", "poison ${player.poison}",
            "weapon ${itemLabel(player.weapon)}", "armor ${itemLabel(player.armor)}", "commands ${commands.size} executed $succeeded failed $failed unused $unused", "moves $moves",
            playerAttacks.line("player_attacks"), monsterAttacks.line("monster_attacks"), "poison_damage $poisonDamage starvation_damage $starvationDamage")
        lines.add(USAGE.indices.joinToString(" ") { "${USAGE[it]} ${usage[it]}" })
        lines.add("kills ${kills.values.sum()}")
        for (kind in monsterTypes) if (kills.getValue(kind.name) > 0) lines.add("KILL ${kind.name} ${kills.getValue(kind.name)}")
        for (level in levels) {
            val (explored, total) = exploration(level)
            lines.add("LEVEL ${level.depth} rooms ${level.rooms.size} explored $explored/$total ${decimal(100 * explored, total)} monsters ${level.kills}/${level.monstersCreated} items ${level.picked}/${level.itemsPlaced}")
        }
        for ((i, item) in player.pack.withIndex()) lines.add("INVENTORY ${i + 1} ${item.displayName()}" + when {
            item === player.weapon -> " (wielded)"
            item === player.armor -> " (worn)"
            else -> ""
        })
        return lines
    }
}
fun main() {
    val config = Config(readRows("config.txt"))
    val monsters = readRows("monsters.txt").map { MonsterType(it) }
    val items = readRows("items.txt").map { ItemType.parse(it) }
    val game = Game(config, monsters, items, expandCommands(readRows("commands.txt")))
    game.run()
    val maps = game.mapLines + game.finalBlock()
    val files = linkedMapOf("messages.txt" to game.messages, "maps.txt" to maps, "stats.txt" to game.stats())
    File("output").mkdirs()
    for ((name, lines) in files) File("output", name).writeText(if (lines.isEmpty()) "" else lines.joinToString("\n") + "\n", Charsets.US_ASCII)
}
