import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Path
import kotlin.math.max
import kotlin.math.min

private const val WAVE_COLUMNS = "wave,start,end,status,spawned,peak,kills,leaks,lives_lost,bounty,reward,interest,gold,lives"
private val incomeFields = listOf("bounty", "reward", "interest", "early", "refund")
private fun readLines(name: String): List<String> = Files.readAllLines(Path.of("input", name), StandardCharsets.US_ASCII)
private fun writeLines(name: String, lines: List<String>) {
    Files.writeString(Path.of("output", name), if (lines.isEmpty()) "" else lines.joinToString("\n") + "\n", StandardCharsets.US_ASCII)
}
private fun oneDecimal(numerator: Long, denominator: Int): String {
    if (denominator == 0) return "-"
    val rounded = (20 * numerator + denominator) / (2L * denominator)
    return "${rounded / 10}.${rounded % 10}"
}
private fun digit(count: Int): Char = if (count == 0) '.' else if (count < 10) ('0'.code + count).toChar() else '*'
private fun ruled(rows: Array<CharArray>): List<String> {
    val lines = mutableListOf("  " + rows[0].indices.joinToString("") { (it % 10).toString() })
    for (y in rows.indices) lines.add("${y % 10} " + rows[y].concatToString())
    return lines
}

private class Params(lines: List<String>) {
    private val fields = lines.map { it.split(' ') }
    val gold = fields[0][1].toInt()
    val lives = fields[1][1].toInt()
    val interestRate = fields[2][1].toInt()
    val interestCap = fields[2][2].toInt()
    val sellRate = fields[3][1].toInt()
    val start = fields[4][1].toInt()
    val interval = fields[4][2].toInt()
    val early = fields[5][1].toInt()
    val snapshots = fields[6].drop(1).map(String::toInt).toSet()
}
private data class Action(val tick: Int, val command: String, val arguments: List<String>) {
    companion object {
        fun parse(line: String): Action { val fields = line.split(' '); return Action(fields[0].toInt(), fields[1], fields.drop(2)) }
    }
}
private class WaveRecord(val number: Int, val plan: Wave, val start: Int) {
    val released = IntArray(plan.groups.size)
    val towerDamage = mutableMapOf<Int, Int>()
    var end = 0
    var status = ""
    var spawned = 0
    var peak = 0
    var kills = 0
    var leaks = 0
    var livesLost = 0
    var bounty = 0
    var reward = 0
    var interest = 0
    var gold = 0
    var lives = 0
    fun allReleased(): Boolean = released.indices.all { released[it] == plan.groups[it].count }
    fun close(status: String, tick: Int, gold: Int, lives: Int) { this.status = status; end = tick; this.gold = gold; this.lives = lives }
    fun row(towerCount: Int): String {
        val values = mutableListOf<Any>(number, start, end, status, spawned, peak, kills, leaks, livesLost, bounty, reward, interest, gold, lives)
        for (number in 1..towerCount) values.add(towerDamage.getOrDefault(number, 0))
        return values.joinToString(",")
    }
}

private class Game(val grid: GridMap, types: List<TowerType>, data: WaveData, val params: Params) {
    private val towerTypes = types.associateBy { it.name }
    private val enemyTypes = data.types
    private val waves = data.waves
    private val exitCenter = grid.exit.center()
    private val towers = mutableListOf<Tower>()
    private val enemies = mutableListOf<Enemy>()
    private val allEnemies = mutableListOf<Enemy>()
    private var projectiles = mutableListOf<Projectile>()
    private val records = mutableListOf<WaveRecord>()
    private val income = incomeFields.associateWith { 0 }.toMutableMap()
    private val killCounts = Array(grid.height) { IntArray(grid.width) }
    private var field = DistanceField(grid, emptySet())
    private var active: WaveRecord? = null
    private var nextStart: Int? = params.start
    private var outcome: String? = null
    private var tick = 0
    private var gold = params.gold
    private var lives = params.lives
    private var projectileCount = 0
    private var spent = 0
    private var done = 0
    private var refused = 0
    val events = mutableListOf<String>()
    val snapshots = mutableListOf<String>()

    private fun record(vararg parts: Any) { events.add(tick.toString() + if (parts.isEmpty()) "" else " " + parts.joinToString(" ")) }
    private fun addIncome(name: String, amount: Int) { income[name] = income.getValue(name) + amount }
    private fun standingTowers(): List<Tower> = towers.filter { it.standing }
    private fun towerCells(): Set<Cell> = standingTowers().map { it.cell }.toSet()
    private fun towerAt(cell: Cell): Tower? = towers.firstOrNull { it.standing && it.cell == cell }
    private fun standingTower(text: String): Tower? { val number = text.toInt(); return if (number in 1..towers.size && towers[number - 1].standing) towers[number - 1] else null }
    private fun groundEnemies(): List<Enemy> = enemies.filter { !it.flying }

    fun run(actions: List<Action>) {
        var index = 0
        while (true) {
            tick++
            while (index < actions.size && actions[index].tick == tick) perform(actions[index++])
            spawnEnemies()
            moveEnemies()
            if (outcome != null) break
            fireTowers()
            moveProjectiles()
            checkWaveEnd()
            if (tick in params.snapshots) snapshots.addAll(block("SNAPSHOT"))
            if (outcome != null) break
        }
        snapshots.addAll(finalBlock())
    }
    private fun perform(action: Action) {
        val success = when (action.command) {
            "BUILD" -> build(action.arguments)
            "UPGRADE" -> upgrade(action.arguments)
            "SELL" -> sell(action.arguments)
            "TARGET" -> setTarget(action.arguments)
            else -> callWave()
        }
        if (success) done++ else refused++
    }
    private fun buildRefusal(name: String, cell: Cell): String? {
        if (name !in towerTypes) return "type"
        if (!grid.inside(cell)) return "bounds"
        if (!grid.buildable(cell)) return "terrain"
        if (towerAt(cell) != null) return "tower"
        if (gold < towerTypes.getValue(name).levels[0].cost) return "gold"
        val walkers = groundEnemies()
        if (walkers.any { it.cell == cell || it.next == cell }) return "enemy"
        val trial = DistanceField(grid, towerCells() + cell)
        if (grid.spawns.any { trial.at(it) < 0 }) return "blocked"
        if (walkers.any { trial.at(it.next) < 0 }) return "blocked"
        return null
    }
    private fun build(args: List<String>): Boolean {
        val name = args[0]
        val cell = Cell(args[1].toInt(), args[2].toInt())
        val reason = buildRefusal(name, cell)
        if (reason != null) { record("BUILD_REFUSED", name, args[1], args[2], reason); return false }
        val kind = towerTypes.getValue(name)
        val cost = kind.levels[0].cost
        val tower = Tower(towers.size + 1, kind, cell, tick)
        towers.add(tower); gold -= cost; spent += cost
        record("BUILD", "T${tower.number}", name, cell.x, cell.y, "cost", cost, "gold", gold)
        updateField()
        return true
    }
    private fun upgrade(args: List<String>): Boolean {
        val tower = standingTower(args[0])
        val reason = when {
            tower == null -> "notower"
            tower.level == tower.kind.levels.size -> "maxlevel"
            gold < tower.kind.levels[tower.level].cost -> "gold"
            else -> {
                val cost = tower.kind.levels[tower.level].cost
                gold -= cost; spent += cost; tower.level++; tower.investment += cost
                record("UPGRADE", "T${tower.number}", "level", tower.level, "cost", cost, "gold", gold)
                return true
            }
        }
        record("UPGRADE_REFUSED", "T${args[0]}", reason)
        return false
    }
    private fun sell(args: List<String>): Boolean {
        val tower = standingTower(args[0])
        if (tower == null) { record("SELL_REFUSED", "T${args[0]}", "notower"); return false }
        val rate = if (tick == tower.built) 100 else params.sellRate
        val refund = tower.investment * rate / 100
        tower.sold = tick; gold += refund; addIncome("refund", refund)
        record("SELL", "T${tower.number}", "refund", refund, "gold", gold)
        updateField()
        return true
    }
    private fun setTarget(args: List<String>): Boolean {
        val tower = standingTower(args[0])
        val reason = when {
            tower == null -> "notower"
            args[1] !in Towers.targetModes -> "mode"
            else -> { tower.mode = args[1]; record("TARGET", "T${tower.number}", tower.mode); return true }
        }
        record("TARGET_REFUSED", "T${args[0]}", reason)
        return false
    }
    private fun callWave(): Boolean {
        if (active != null) { record("CALL_REFUSED", "active"); return false }
        val bonus = (nextStart!! - tick) * params.early
        gold += bonus; addIncome("early", bonus); nextStart = tick
        record("CALL", records.size + 1, "bonus", bonus, "gold", gold)
        return true
    }
    private fun updateField() {
        val before = field
        field = DistanceField(grid, towerCells())
        for ((i, spawn) in grid.spawns.withIndex()) if (before.at(spawn) != field.at(spawn)) record("REPATH", i + 1, before.at(spawn), field.at(spawn))
    }
    private fun startWave() {
        val plan = waves[records.size]
        val wave = WaveRecord(records.size + 1, plan, tick)
        active = wave; records.add(wave); nextStart = null
        record("WAVE_START", wave.number, "enemies", plan.enemyCount)
    }
    private fun addEnemy(enemy: Enemy) { enemies.add(enemy); allEnemies.add(enemy); active!!.spawned++; enemy.kind.spawned++ }
    private fun removeEnemy(enemy: Enemy) { enemy.alive = false; enemies.remove(enemy) }
    private fun spawnEnemies() {
        if (tick == nextStart) startWave()
        val wave = active ?: return
        for ((i, group) in wave.plan.groups.withIndex()) {
            val released = wave.released[i]
            if (released == group.count || group.spawnTick(wave.start, released) != tick) continue
            wave.released[i]++
            val spawn = grid.spawns[group.spawn - 1]
            val enemy = Enemy(allEnemies.size + 1, group.kind, group.multiplier)
            if (enemy.flying) enemy.point = spawn.center() else { enemy.cell = spawn; enemy.next = field.next(spawn) }
            addEnemy(enemy)
            record("SPAWN", "E${enemy.number}", enemy.kind.name, group.spawn, "hp", enemy.hp)
        }
        wave.peak = max(wave.peak, enemies.size)
    }
    private fun moveEnemies() { for (enemy in enemies.toList()) { moveEnemy(enemy); if (outcome != null) return } }
    private fun moveEnemy(enemy: Enemy) {
        if (enemy.burn.active) {
            val source = towers[enemy.burn.source - 1]
            val damage = min(enemy.hp, enemy.burn.strength)
            enemy.hp -= damage; credit(source, enemy, damage); enemy.burn.advanceTime()
            if (enemy.hp == 0) { kill(enemy, source); return }
        }
        enemy.hp = min(enemy.hp + enemy.kind.regen, enemy.maxHp)
        val speed = enemy.slowedSpeed()
        if (enemy.slow.active) enemy.slow.advanceTime()
        val arrived = if (enemy.flying) {
            val movement = Combat.advance(enemy.point, exitCenter, speed)
            enemy.point = movement.point
            movement.arrived
        } else walk(enemy, speed)
        if (arrived) leak(enemy)
    }
    private fun walk(enemy: Enemy, originalSpeed: Int): Boolean {
        var speed = if (grid.water(enemy.occupiedCell())) originalSpeed / 2 else originalSpeed
        while (speed > 0) {
            val rest = 100 - enemy.progress
            if (speed < rest) { enemy.progress += speed; speed = 0 }
            else {
                speed -= rest; enemy.cell = enemy.next; enemy.progress = 0
                if (enemy.cell == grid.exit) return true
                enemy.next = field.next(enemy.cell)
            }
        }
        return false
    }
    private fun leak(enemy: Enemy) {
        removeEnemy(enemy)
        val lost = min(lives, enemy.kind.lives)
        lives -= lost
        val wave = active!!
        wave.leaks++; wave.livesLost += lost; enemy.kind.leaks++
        record("LEAK", "E${enemy.number}", enemy.kind.name, "lives", lives)
        if (lives == 0) { record("DEFEAT"); outcome = "defeat"; wave.close("lost", tick, gold, lives); active = null }
    }
    private fun fireTowers() {
        for (tower in standingTowers()) {
            if (tick < tower.ready) continue
            val target = tower.selectTarget(enemies, field) ?: continue
            projectileCount++
            projectiles.add(Projectile(projectileCount, tower, target))
            tower.shots++; tower.ready = tick + tower.stats().interval
            record("SHOT", "T${tower.number}", "E${target.number}")
        }
    }
    private fun moveProjectiles() {
        val flying = mutableListOf<Projectile>()
        for (projectile in projectiles) {
            val target = allEnemies[projectile.target - 1]
            if (target.alive) projectile.aim = target.position()
            if (projectile.fly()) impact(projectile) else flying.add(projectile)
        }
        projectiles = flying
    }
    private fun impact(projectile: Projectile) {
        val tower = towers[projectile.tower - 1]
        val target = allEnemies[projectile.target - 1]
        val victims = if (projectile.stats.splash == 0) {
            if (target.alive) listOf(target) else emptyList()
        } else enemies.filter { Towers.canAim(projectile.targets, it) && Combat.squaredDistance(it.position(), projectile.aim) <= projectile.stats.splash.toLong() * projectile.stats.splash }
        if (victims.isEmpty()) tower.fizzles++
        for (enemy in victims) {
            tower.hits++
            val damage = Combat.damage(enemy.hp, projectile.stats.power, enemy.kind.armor)
            enemy.hp -= damage; credit(tower, enemy, damage)
            if (enemy.hp == 0) { kill(enemy, tower); continue }
            if (projectile.stats.slowRate > 0) enemy.slow.receive(projectile.stats.slowRate, projectile.stats.slowTime, 0)
            if (projectile.stats.burnAmount > 0) enemy.burn.receive(projectile.stats.burnAmount, projectile.stats.burnTime, tower.number)
        }
    }
    private fun credit(tower: Tower, enemy: Enemy, damage: Int) {
        tower.damage += damage; enemy.kind.damage += damage
        val waveDamage = active!!.towerDamage
        waveDamage[tower.number] = waveDamage.getOrDefault(tower.number, 0) + damage
    }
    private fun kill(enemy: Enemy, tower: Tower) {
        removeEnemy(enemy)
        val cell = enemy.occupiedCell()
        killCounts[cell.y][cell.x]++
        val bounty = enemy.kind.bounty
        val wave = active!!
        tower.kills++; wave.kills++; enemy.kind.kills++; gold += bounty; wave.bounty += bounty; addIncome("bounty", bounty)
        record("KILL", "E${enemy.number}", enemy.kind.name, "T${tower.number}", "bounty", bounty, "gold", gold)
        repeat(enemy.kind.splitCount) {
            val child = enemy.split(allEnemies.size + 1)
            addEnemy(child)
            record("SPAWN", "E${child.number}", child.kind.name, "E${enemy.number}", "hp", child.hp)
        }
    }
    private fun checkWaveEnd() {
        val wave = active ?: return
        if (enemies.isNotEmpty() || !wave.allReleased()) return
        val reward = wave.plan.reward
        gold += reward
        val interest = min(params.interestCap, gold * params.interestRate / 100)
        gold += interest
        wave.reward = reward; wave.interest = interest; addIncome("reward", reward); addIncome("interest", interest); active = null
        record("WAVE_END", wave.number, "reward", reward, "interest", interest, "gold", gold)
        if (wave.number == waves.size) { record("VICTORY"); outcome = "victory" } else nextStart = tick + params.interval
        wave.close("cleared", tick, gold, lives)
    }
    private fun mapPicture(): Array<CharArray> {
        val rows = grid.rows.map(String::toCharArray).toTypedArray()
        for (spawn in grid.spawns) for (cell in field.path(spawn)) if (grid.terrain(cell) == '.' || grid.terrain(cell) == '~') rows[cell.y][cell.x] = '+'
        for (tower in standingTowers()) rows[tower.cell.y][tower.cell.x] = tower.kind.symbol
        for ((cell, group) in enemies.groupBy { it.occupiedCell() }) rows[cell.y][cell.x] = if (group.size == 1) group[0].kind.symbol else '*'
        return rows
    }
    private fun flowPicture(): Array<CharArray> = Array(grid.height) { y ->
        CharArray(grid.width) { x ->
            val cell = Cell(x, y)
            val terrain = grid.terrain(cell)
            val tower = towerAt(cell)
            when {
                terrain == '#' || terrain == 'E' -> terrain
                tower != null -> tower.kind.symbol
                field.at(cell) < 0 -> '?'
                else -> "^>v<"[field.direction(cell)]
            }
        }
    }
    private fun coveragePicture(): Array<CharArray> {
        val standing = standingTowers()
        return Array(grid.height) { y -> CharArray(grid.width) { x ->
            val cell = Cell(x, y)
            val tower = towerAt(cell)
            if (grid.rock(cell)) '#' else if (tower != null) tower.kind.symbol else digit(standing.count { it.inRange(cell.center()) })
        } }
    }
    private fun killsPicture(): Array<CharArray> = Array(grid.height) { y -> CharArray(grid.width) { x ->
        if (killCounts[y][x] > 0) digit(killCounts[y][x]) else if (grid.rock(Cell(x, y))) '#' else '.'
    } }
    private fun block(label: String): List<String> {
        val next = if (active == null && outcome == null) nextStart.toString() else "-"
        val lines = mutableListOf("$label $tick wave ${records.size} next $next gold $gold lives $lives")
        lines.addAll(ruled(mapPicture()))
        for ((i, spawn) in grid.spawns.withIndex()) lines.add("PATH ${i + 1} length ${field.at(spawn)}")
        for (tower in standingTowers()) lines.add("T${tower.number} ${tower.kind.name} ${tower.cell.x} ${tower.cell.y} level ${tower.level} mode ${tower.mode} ready ${tower.ready}")
        for (enemy in enemies) {
            val point = enemy.position()
            lines.add("E${enemy.number} ${enemy.kind.name} ${point.x} ${point.y} hp ${enemy.hp}/${enemy.maxHp} slow ${enemy.slow.strength} ${enemy.slow.remaining} burn ${enemy.burn.strength} ${enemy.burn.remaining}")
        }
        for (projectile in projectiles) lines.add("P${projectile.number} T${projectile.tower} E${projectile.target} ${projectile.position.x} ${projectile.position.y}")
        return lines
    }
    private fun finalBlock(): List<String> {
        val lines = block("FINAL").toMutableList()
        lines.add("FLOW"); lines.addAll(ruled(flowPicture())); lines.add("COVERAGE"); lines.addAll(ruled(coveragePicture())); lines.add("KILLS"); lines.addAll(ruled(killsPicture()))
        return lines
    }
    fun waveLines(): List<String> = listOf(WAVE_COLUMNS + towers.joinToString("") { ",T${it.number}" }) + records.map { it.row(towers.size) }
    private fun mvpLine(): String {
        var best: Tower? = null
        for (tower in towers) if (best == null || tower.damage > best.damage) best = tower
        return if (best == null) "mvp -" else "mvp T${best.number} damage ${best.damage}"
    }
    private fun towerLine(tower: Tower, totalDamage: Int): String {
        val state = if (tower.standing) "active" else "sold ${tower.sold}"
        return "TOWER T${tower.number} ${tower.kind.name} ${tower.cell.x} ${tower.cell.y} level ${tower.level} mode ${tower.mode} $state shots ${tower.shots} hits ${tower.hits} fizzles ${tower.fizzles} kills ${tower.kills} damage ${tower.damage} per_shot ${oneDecimal(tower.damage.toLong(), tower.shots)} share ${oneDecimal(100L * tower.damage, totalDamage)} invested ${tower.investment}"
    }
    fun summaryLines(actionCount: Int): List<String> {
        val cleared = records.filter { it.status == "cleared" }
        val perfect = cleared.count { it.leaks == 0 }
        val spawned = enemyTypes.sumOf { it.spawned }
        val killed = enemyTypes.sumOf { it.kills }
        val leaked = enemyTypes.sumOf { it.leaks }
        val totalDamage = towers.sumOf { it.damage }
        val score = 10L * killed + 100L * lives + 50L * perfect + gold
        val lines = mutableListOf(
            "outcome $outcome", "ticks $tick", "waves ${cleared.size}/${waves.size} perfect $perfect", "lives $lives/${params.lives}", "gold $gold",
            "enemies spawned $spawned killed $killed leaked $leaked", "income " + incomeFields.joinToString(" ") { "$it ${income.getValue(it)}" }, "spent $spent", "damage $totalDamage",
            "actions total $actionCount done $done refused $refused unused ${actionCount - done - refused}", "score $score", mvpLine()
        )
        for (type in enemyTypes) lines.add("ENEMY ${type.name} spawned ${type.spawned} killed ${type.kills} leaked ${type.leaks} damage ${type.damage}")
        for (tower in towers) lines.add(towerLine(tower, totalDamage))
        return lines
    }
}

fun main() {
    val grid = GridMap.read()
    val towerTypes = Towers.parse(readLines("towers.txt"))
    val data = Enemies.parse(readLines("waves.txt"))
    val actions = readLines("actions.txt").map(Action::parse)
    val params = Params(readLines("params.txt"))
    val game = Game(grid, towerTypes, data, params)
    game.run(actions)
    Files.createDirectories(Path.of("output"))
    writeLines("events.txt", game.events)
    writeLines("waves.csv", game.waveLines())
    writeLines("snapshots.txt", game.snapshots)
    writeLines("summary.txt", game.summaryLines(actions.size))
}
