import Foundation

let waveColumns = "wave,start,end,status,spawned,peak,kills,leaks,lives_lost,bounty,reward,interest,gold,lives"
func readLines(_ name: String) throws -> [String] { try String(contentsOfFile: "input/" + name, encoding: .utf8).split(whereSeparator: \.isNewline).map(String.init) }
func writeLines(_ name: String, _ lines: [String]) throws { try (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: true, encoding: .utf8) }
func oneDecimal(_ numerator: Int, _ denominator: Int) -> String { if denominator == 0 { return "-" }; let rounded = (20 * numerator + denominator) / (2 * denominator); return "\(rounded / 10).\(rounded % 10)" }
func digit(_ count: Int) -> UInt8 { count == 0 ? 46 : (count <= 9 ? UInt8(count) + 48 : 42) }
func ruled(_ rows: [[UInt8]]) -> [String] { ["  " + rows[0].indices.map { String($0 % 10) }.joined()] + rows.enumerated().map { "\($0.offset % 10) " + String(decoding: $0.element, as: UTF8.self) } }
struct Params {
    let gold: Int
    let lives: Int
    let interestRate: Int
    let interestCap: Int
    let sellRate: Int
    let start: Int
    let interval: Int
    let early: Int
    let snapshots: Set<Int>
    init(_ lines: [String]) {
        let values = lines.map { $0.split(separator: " ").dropFirst().map { Int($0)! } }
        gold = values[0][0]; lives = values[1][0]; interestRate = values[2][0]; interestCap = values[2][1]
        sellRate = values[3][0]; start = values[4][0]; interval = values[4][1]; early = values[5][0]; snapshots = Set(values[6])
    }
}
enum Command { case build(String, Cell), upgrade(Int), sell(Int), target(Int, String), call }
struct Action {
    let tick: Int
    let command: Command
    init(_ line: String) {
        let fields = line.split(separator: " ").map(String.init)
        tick = Int(fields[0])!
        switch fields[1] {
        case "BUILD": command = .build(fields[2], Cell(x: Int(fields[3])!, y: Int(fields[4])!))
        case "UPGRADE": command = .upgrade(Int(fields[2])!)
        case "SELL": command = .sell(Int(fields[2])!)
        case "TARGET": command = .target(Int(fields[2])!, fields[3])
        default: command = .call
        }
    }
}
enum WaveStatus: String { case active, cleared, lost }
final class WaveRecord {
    let number: Int
    let start: Int
    var end = 0
    var status = WaveStatus.active
    var released: [Int]
    var spawned = 0, peak = 0, kills = 0, leaks = 0, livesLost = 0, bounty = 0, reward = 0, interest = 0, gold = 0, lives = 0
    var towerDamage: [Int: Int] = [:]
    init(_ number: Int, _ start: Int, _ groupCount: Int) { self.number = number; self.start = start; released = Array(repeating: 0, count: groupCount) }
    func close(_ status: WaveStatus, _ tick: Int, _ gold: Int, _ lives: Int) { self.status = status; end = tick; self.gold = gold; self.lives = lives }
    func csvRow(_ towerCount: Int) -> String {
        var fields = [String(number), String(start), String(end), status.rawValue, String(spawned), String(peak), String(kills), String(leaks), String(livesLost), String(bounty), String(reward), String(interest), String(gold), String(lives)]
        fields += (0..<towerCount).map { String(towerDamage[$0, default: 0]) }
        return fields.joined(separator: ",")
    }
}
enum Outcome: String { case victory, defeat }
struct Income { var bounty = 0, reward = 0, interest = 0, early = 0, refund = 0 }
final class Game {
    let grid: GridMap
    let towerTypes: [TowerType]
    let enemyTypes: [EnemyType]
    let waves: [Wave]
    let params: Params
    var tick = 0
    var gold: Int
    var lives: Int
    var towers: [Tower] = []
    var enemies: [Enemy] = []
    var projectiles: [Projectile] = []
    var projectileCount = 0
    var records: [WaveRecord] = []
    var active: Int? = nil
    var nextStart: Int?
    var outcome: Outcome? = nil
    var field: DistanceField
    var killCounts: [[Int]]
    var income = Income()
    var spent = 0, done = 0, refused = 0
    var events: [String] = [], snapshots: [String] = []
    init(_ grid: GridMap, _ towerTypes: [TowerType], _ enemyTypes: [EnemyType], _ waves: [Wave], _ params: Params) {
        self.grid = grid; self.towerTypes = towerTypes; self.enemyTypes = enemyTypes; self.waves = waves; self.params = params
        gold = params.gold; lives = params.lives; nextStart = params.start
        field = DistanceField(grid, []); killCounts = Array(repeating: Array(repeating: 0, count: grid.width), count: grid.height)
    }
    func record(_ body: String) { events.append("\(tick) " + body) }
    func run(_ actions: [Action]) {
        var index = 0
        while true {
            tick += 1
            while index < actions.count && actions[index].tick == tick { perform(actions[index].command); index += 1 }
            spawnEnemies(); moveEnemies()
            if outcome != nil { break }
            fireTowers(); moveProjectiles(); checkWaveEnd()
            if params.snapshots.contains(tick) { snapshots += block("SNAPSHOT") }
            if outcome != nil { break }
        }
        snapshots += finalBlock()
    }
    var towerCells: Set<Cell> { Set(towers.filter(\.standing).map(\.cell)) }
    func towerAt(_ cell: Cell) -> Tower? { towers.first { $0.standing && $0.cell == cell } }
    func standingTower(_ number: Int) -> Tower? { number >= 1 && number <= towers.count && towers[number - 1].standing ? towers[number - 1] : nil }
    func perform(_ command: Command) {
        let success: Bool
        switch command { case .build(let name, let cell): success = build(name, cell); case .upgrade(let number): success = upgrade(number); case .sell(let number): success = sell(number); case .target(let number, let mode): success = setTarget(number, mode); case .call: success = callWave() }
        if success { done += 1 } else { refused += 1 }
    }
    func buildRefusal(_ name: String, _ cell: Cell) -> String? {
        guard let kind = towerTypes.firstIndex(where: { $0.name == name }) else { return "type" }
        if !grid.inside(cell) { return "bounds" }
        if !grid.buildable(cell) { return "terrain" }
        if towerAt(cell) != nil { return "tower" }
        if gold < towerTypes[kind].levels[0].cost { return "gold" }
        for enemy in enemies where enemy.alive { if case .ground(let current, let next, _) = enemy.position, current == cell || next == cell { return "enemy" } }
        var cells = towerCells; cells.insert(cell)
        let trial = DistanceField(grid, cells)
        if grid.spawns.contains(where: { trial.at($0) == nil }) { return "blocked" }
        for enemy in enemies where enemy.alive { if case .ground(_, let next, _) = enemy.position, trial.at(next) == nil { return "blocked" } }
        return nil
    }
    func build(_ name: String, _ cell: Cell) -> Bool {
        if let reason = buildRefusal(name, cell) { record("BUILD_REFUSED \(name) \(cell.x) \(cell.y) \(reason)"); return false }
        let kind = towerTypes.firstIndex { $0.name == name }!
        let cost = towerTypes[kind].levels[0].cost
        let tower = Tower(towers.count + 1, kind, towerTypes, cell, tick)
        towers.append(tower); gold -= cost; spent += cost
        record("BUILD T\(tower.number) \(name) \(cell.x) \(cell.y) cost \(cost) gold \(gold)")
        updateField(); return true
    }
    func upgrade(_ number: Int) -> Bool {
        guard let tower = standingTower(number) else { record("UPGRADE_REFUSED T\(number) notower"); return false }
        if tower.level + 1 == towerTypes[tower.kind].levels.count { record("UPGRADE_REFUSED T\(number) maxlevel"); return false }
        let cost = towerTypes[tower.kind].levels[tower.level + 1].cost
        if gold < cost { record("UPGRADE_REFUSED T\(number) gold"); return false }
        gold -= cost; spent += cost; tower.level += 1; tower.investment += cost
        record("UPGRADE T\(number) level \(tower.level + 1) cost \(cost) gold \(gold)"); return true
    }
    func sell(_ number: Int) -> Bool {
        guard let tower = standingTower(number) else { record("SELL_REFUSED T\(number) notower"); return false }
        let rate = tick == tower.built ? 100 : params.sellRate
        let refund = tower.investment * rate / 100
        tower.sold = tick; gold += refund; income.refund += refund
        record("SELL T\(number) refund \(refund) gold \(gold)"); updateField(); return true
    }
    func setTarget(_ number: Int, _ mode: String) -> Bool {
        guard let tower = standingTower(number) else { record("TARGET_REFUSED T\(number) notower"); return false }
        guard let value = TargetMode(rawValue: mode) else { record("TARGET_REFUSED T\(number) mode"); return false }
        tower.mode = value; record("TARGET T\(number) \(mode)"); return true
    }
    func callWave() -> Bool {
        if active != nil { record("CALL_REFUSED active"); return false }
        let bonus = (nextStart! - tick) * params.early
        gold += bonus; income.early += bonus; nextStart = tick
        record("CALL \(records.count + 1) bonus \(bonus) gold \(gold)"); return true
    }
    func updateField() {
        let updated = DistanceField(grid, towerCells)
        for (number, spawn) in grid.spawns.enumerated() {
            let old = field.at(spawn)!, new = updated.at(spawn)!
            if old != new { record("REPATH \(number + 1) \(old) \(new)") }
        }
        field = updated
    }
    func startWave() {
        let index = records.count, plan = waves[records.count]
        records.append(WaveRecord(index + 1, tick, plan.groups.count)); active = index; nextStart = nil
        record("WAVE_START \(index + 1) enemies \(plan.enemyCount)")
    }
    func addEnemy(_ enemy: Enemy) { records[active!].spawned += 1; enemyTypes[enemy.kind].spawned += 1; enemies.append(enemy) }
    func spawnEnemies() {
        if nextStart == tick { startWave() }
        guard let wave = active else { return }
        let record = records[wave]
        for (index, group) in waves[wave].groups.enumerated() {
            let released = record.released[index]
            if released == group.count || group.spawnTick(record.start, released) != tick { continue }
            record.released[index] += 1
            let spawn = grid.spawns[group.spawn]
            let position: EnemyPosition = enemyTypes[group.kind].movement == .air ? .air(cellCenter(spawn)) : .ground(spawn, field.nextCell(spawn), 0)
            let enemy = Enemy(enemies.count + 1, group.kind, enemyTypes, group.multiplier, position)
            addEnemy(enemy)
            self.record("SPAWN E\(enemy.number) \(enemyTypes[group.kind].name) \(group.spawn + 1) hp \(enemy.hp)")
        }
        record.peak = max(record.peak, enemies.filter(\.alive).count)
    }
    func moveEnemies() {
        let order = enemies.indices.filter { enemies[$0].alive }
        for index in order { moveEnemy(enemies[index]); if outcome != nil { return } }
    }
    func moveEnemy(_ enemy: Enemy) {
        if enemy.burn.active {
            let source = towers[enemy.burn.source!], damage = min(enemy.hp, enemy.burn.strength)
            enemy.hp -= damage; credit(source, enemy, damage); enemy.burn.advanceTime()
            if enemy.hp == 0 { kill(enemy, source); return }
        }
        enemy.hp = min(enemy.hp + enemyTypes[enemy.kind].regen, enemy.maxHP)
        let speed = enemy.slowedSpeed(enemyTypes)
        if enemy.slow.active { enemy.slow.advanceTime() }
        let arrived: Bool
        switch enemy.position {
        case .air(let point): let (point, reached) = advance(point, cellCenter(grid.exit), speed); enemy.position = .air(point); arrived = reached
        case .ground: arrived = walk(enemy, speed)
        }
        if arrived { leak(enemy) }
    }
    func walk(_ enemy: Enemy, _ initialSpeed: Int) -> Bool {
        var speed = grid.isWater(enemy.occupiedCell) ? initialSpeed / 2 : initialSpeed
        guard case .ground(let current, let following, let amount) = enemy.position else { return false }
        var cell = current, next = following, progress = amount, arrived = false
        while speed > 0 {
            let rest = 100 - progress
            if speed < rest { progress += speed; speed = 0 }
            else { speed -= rest; cell = next; progress = 0; if cell == grid.exit { arrived = true; break }; next = field.nextCell(cell) }
        }
        enemy.position = .ground(cell, next, progress)
        return arrived
    }
    func leak(_ enemy: Enemy) {
        enemy.alive = false
        let kind = enemyTypes[enemy.kind], lost = min(lives, enemyTypes[enemy.kind].lives), wave = records[active!]
        lives -= lost; wave.leaks += 1; wave.livesLost += lost; kind.leaks += 1
        record("LEAK E\(enemy.number) \(kind.name) lives \(lives)")
        if lives == 0 { record("DEFEAT"); outcome = .defeat; wave.close(.lost, tick, gold, lives); active = nil }
    }
    func fireTowers() {
        for tower in towers where tower.standing && tick >= tower.ready {
            if let target = tower.selectTarget(enemies, enemyTypes, towerTypes, field) {
                let stats = tower.stats(towerTypes)
                projectileCount += 1
                projectiles.append(Projectile(number: projectileCount, tower: tower.number - 1, target: target, position: tower.center, aim: enemies[target].point, targets: towerTypes[tower.kind].targets, stats: stats))
                tower.shots += 1; tower.ready = tick + stats.interval
                record("SHOT T\(tower.number) E\(enemies[target].number)")
            }
        }
    }
    func moveProjectiles() {
        let flying = projectiles
        projectiles = []
        for var projectile in flying {
            if enemies[projectile.target].alive { projectile.aim = enemies[projectile.target].point }
            if projectile.fly() { impact(projectile) } else { projectiles.append(projectile) }
        }
    }
    func impact(_ projectile: Projectile) {
        let tower = towers[projectile.tower]
        let victims: [Int]
        if projectile.stats.splash == 0 { victims = enemies[projectile.target].alive ? [projectile.target] : [] }
        else {
            let radius = projectile.stats.splash * projectile.stats.splash
            victims = enemies.indices.filter { enemies[$0].alive && projectile.targets.canAim(enemyTypes[enemies[$0].kind].movement) && squaredDistance(enemies[$0].point, projectile.aim) <= radius }
        }
        if victims.isEmpty { tower.fizzles += 1 }
        for index in victims {
            let enemy = enemies[index]
            tower.hits += 1
            let damage = damageDealt(enemy.hp, projectile.stats.power, enemyTypes[enemy.kind].armor)
            enemy.hp -= damage; credit(tower, enemy, damage)
            if enemy.hp == 0 { kill(enemy, tower); continue }
            if projectile.stats.slowRate > 0 { enemy.slow.receive(projectile.stats.slowRate, projectile.stats.slowTime) }
            if projectile.stats.burnAmount > 0 { enemy.burn.receive(projectile.stats.burnAmount, projectile.stats.burnTime, projectile.tower) }
        }
    }
    func credit(_ tower: Tower, _ enemy: Enemy, _ damage: Int) { tower.damage += damage; enemyTypes[enemy.kind].damage += damage; records[active!].towerDamage[tower.number - 1, default: 0] += damage }
    func kill(_ enemy: Enemy, _ tower: Tower) {
        enemy.alive = false
        let cell = enemy.occupiedCell, kind = enemyTypes[enemy.kind], wave = records[active!]
        killCounts[cell.y][cell.x] += 1; tower.kills += 1; wave.kills += 1; kind.kills += 1
        gold += kind.bounty; wave.bounty += kind.bounty; income.bounty += kind.bounty
        record("KILL E\(enemy.number) \(kind.name) T\(tower.number) bounty \(kind.bounty) gold \(gold)")
        for _ in 0..<kind.splitCount {
            let child = enemy.split(enemies.count + 1, enemyTypes)
            addEnemy(child); record("SPAWN E\(child.number) \(enemyTypes[child.kind].name) E\(enemy.number) hp \(child.hp)")
        }
    }
    func checkWaveEnd() {
        guard let index = active else { return }
        let wave = records[index], plan = waves[index]
        if enemies.contains(where: \.alive) || zip(wave.released, plan.groups).contains(where: { $0.0 != $0.1.count }) { return }
        gold += plan.reward
        let interest = min(params.interestCap, gold * params.interestRate / 100)
        gold += interest; wave.reward = plan.reward; wave.interest = interest; income.reward += plan.reward; income.interest += interest; active = nil
        record("WAVE_END \(wave.number) reward \(plan.reward) interest \(interest) gold \(gold)")
        if wave.number == waves.count { record("VICTORY"); outcome = .victory } else { nextStart = tick + params.interval }
        wave.close(.cleared, tick, gold, lives)
    }
    func mapPicture() -> [[UInt8]] {
        var rows = grid.rows
        for spawn in grid.spawns { for cell in field.path(spawn) { if [46, 126].contains(grid.terrain(cell)) { rows[cell.y][cell.x] = 43 } } }
        for tower in towers where tower.standing { rows[tower.cell.y][tower.cell.x] = towerTypes[tower.kind].symbol }
        var occupants: [Cell: (Int, UInt8)] = [:]
        for enemy in enemies where enemy.alive {
            let cell = enemy.occupiedCell
            if let old = occupants[cell] { occupants[cell] = (old.0 + 1, old.1) } else { occupants[cell] = (1, enemyTypes[enemy.kind].symbol) }
        }
        for (cell, group) in occupants { rows[cell.y][cell.x] = group.0 == 1 ? group.1 : 42 }
        return rows
    }
    func flowPicture() -> [[UInt8]] {
        let arrows = Array("^>v<".utf8)
        return (0..<grid.height).map { y in (0..<grid.width).map { x in
            let cell = Cell(x: x, y: y), terrain = grid.terrain(Cell(x: x, y: y))
            if terrain == 35 || terrain == 69 { return terrain }
            if let tower = towerAt(cell) { return towerTypes[tower.kind].symbol }
            return field.at(cell) == nil ? 63 : arrows[field.direction(cell)]
        } }
    }
    func coveragePicture() -> [[UInt8]] {
        (0..<grid.height).map { y in (0..<grid.width).map { x in
            let cell = Cell(x: x, y: y)
            if grid.isRock(cell) { return UInt8(35) }
            if let tower = towerAt(cell) { return towerTypes[tower.kind].symbol }
            return digit(towers.filter { $0.standing && $0.inRange(cellCenter(cell), towerTypes) }.count)
        } }
    }
    func killsPicture() -> [[UInt8]] {
        (0..<grid.height).map { y in (0..<grid.width).map { x in let count = killCounts[y][x]; return count > 0 ? digit(count) : (grid.isRock(Cell(x: x, y: y)) ? 35 : 46) } }
    }
    func block(_ label: String) -> [String] {
        let next = active == nil && outcome == nil ? String(nextStart!) : "-"
        var lines = ["\(label) \(tick) wave \(records.count) next \(next) gold \(gold) lives \(lives)"] + ruled(mapPicture())
        for (number, spawn) in grid.spawns.enumerated() { lines.append("PATH \(number + 1) length \(field.at(spawn)!)") }
        for tower in towers where tower.standing { lines.append("T\(tower.number) \(towerTypes[tower.kind].name) \(tower.cell.x) \(tower.cell.y) level \(tower.level + 1) mode \(tower.mode.rawValue) ready \(tower.ready)") }
        for enemy in enemies where enemy.alive {
            let point = enemy.point
            lines.append("E\(enemy.number) \(enemyTypes[enemy.kind].name) \(point.x) \(point.y) hp \(enemy.hp)/\(enemy.maxHP) slow \(enemy.slow.strength) \(enemy.slow.remaining) burn \(enemy.burn.strength) \(enemy.burn.remaining)")
        }
        for projectile in projectiles { lines.append("P\(projectile.number) T\(towers[projectile.tower].number) E\(enemies[projectile.target].number) \(projectile.position.x) \(projectile.position.y)") }
        return lines
    }
    func finalBlock() -> [String] { block("FINAL") + ["FLOW"] + ruled(flowPicture()) + ["COVERAGE"] + ruled(coveragePicture()) + ["KILLS"] + ruled(killsPicture()) }
    func waveLines() -> [String] { [waveColumns + towers.map { ",T\($0.number)" }.joined()] + records.map { $0.csvRow(towers.count) } }
    func summaryLines(_ actionCount: Int) -> [String] {
        let cleared = records.filter { $0.status == .cleared }, perfect = records.filter { $0.status == .cleared && $0.leaks == 0 }.count
        let spawned = enemyTypes.reduce(0) { $0 + $1.spawned }, killed = enemyTypes.reduce(0) { $0 + $1.kills }, leaked = enemyTypes.reduce(0) { $0 + $1.leaks }
        let totalDamage = towers.reduce(0) { $0 + $1.damage }, score = 10 * killed + 100 * lives + 50 * perfect + gold
        var lines = ["outcome \(outcome!.rawValue)", "ticks \(tick)", "waves \(cleared.count)/\(waves.count) perfect \(perfect)", "lives \(lives)/\(params.lives)", "gold \(gold)",
            "enemies spawned \(spawned) killed \(killed) leaked \(leaked)", "income bounty \(income.bounty) reward \(income.reward) interest \(income.interest) early \(income.early) refund \(income.refund)",
            "spent \(spent)", "damage \(totalDamage)", "actions total \(actionCount) done \(done) refused \(refused) unused \(actionCount - done - refused)", "score \(score)"]
        var best: Tower? = nil
        for tower in towers { if best == nil || tower.damage > best!.damage { best = tower } }
        lines.append(best.map { "mvp T\($0.number) damage \($0.damage)" } ?? "mvp -")
        for kind in enemyTypes { lines.append("ENEMY \(kind.name) spawned \(kind.spawned) killed \(kind.kills) leaked \(kind.leaks) damage \(kind.damage)") }
        for tower in towers {
            let state = tower.sold.map { "sold \($0)" } ?? "active"
            lines.append("TOWER T\(tower.number) \(towerTypes[tower.kind].name) \(tower.cell.x) \(tower.cell.y) level \(tower.level + 1) mode \(tower.mode.rawValue) \(state) shots \(tower.shots) hits \(tower.hits) fizzles \(tower.fizzles) kills \(tower.kills) damage \(tower.damage) per_shot \(oneDecimal(tower.damage, tower.shots)) share \(oneDecimal(100 * tower.damage, totalDamage)) invested \(tower.investment)")
        }
        return lines
    }
}
func main() throws {
    let grid = try GridMap("input/map.txt"), towerTypes = parseTowerTypes(try readLines("towers.txt"))
    let (enemyTypes, waves) = parseWaves(try readLines("waves.txt"))
    let actions = try readLines("actions.txt").map(Action.init), params = Params(try readLines("params.txt"))
    let game = Game(grid, towerTypes, enemyTypes, waves, params)
    game.run(actions)
    try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    try writeLines("events.txt", game.events); try writeLines("waves.csv", game.waveLines())
    try writeLines("snapshots.txt", game.snapshots); try writeLines("summary.txt", game.summaryLines(actions.count))
}
try main()
