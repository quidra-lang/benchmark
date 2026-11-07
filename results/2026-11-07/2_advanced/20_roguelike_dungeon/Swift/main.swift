import Foundation

struct Config {
    let generationSeed: Int
    let gameSeed: Int
    let width: Int
    let height: Int
    let minSize: Int
    let maxSplit: Int
    let roomMin: Int
    let roomMax: Int
    let levels: Int
    let monsterBase: Int
    let monsterStep: Int
    let itemBase: Int
    let itemStep: Int
    let sleepChance: Int
    let wakeChance: Int
    let radius: Int
    let maxHP: Int
    let regenInterval: Int
    let hitDie: Dice
    let foodStart: Int
    let foodMax: Int
    let foodHungry: Int
    let foodWeak: Int
    let packLimit: Int
    let startItems: [String]
    let xpLevels: [Int]
    let checkpoints: Set<Int>
    init(_ rows: [[String]]) {
        let entries = Dictionary(uniqueKeysWithValues: rows.map { ($0[0], Array($0.dropFirst())) })
        func integer(_ key: String, _ position: Int) -> Int { Int(entries[key]![position])! }
        generationSeed = integer("seed", 0); gameSeed = integer("seed", 1)
        width = integer("map", 0); height = integer("map", 1); minSize = integer("bsp", 0); maxSplit = integer("bsp", 1)
        roomMin = integer("room", 0); roomMax = integer("room", 1); levels = integer("levels", 0)
        monsterBase = integer("monsters", 0); monsterStep = integer("monsters", 1); itemBase = integer("items", 0); itemStep = integer("items", 1)
        sleepChance = integer("sleep", 0); wakeChance = integer("sleep", 1); radius = integer("fov", 0)
        maxHP = integer("player", 0); regenInterval = integer("player", 1); hitDie = Dice(entries["hitdie"]![0])
        foodStart = integer("food", 0); foodMax = integer("food", 1); foodHungry = integer("food", 2); foodWeak = integer("food", 3)
        packLimit = integer("pack", 0); startItems = entries["start"]!; xpLevels = entries["xp"]!.map { Int($0)! }
        checkpoints = Set(entries["checkpoints"]!.map { Int($0)! })
    }
}
func readRows(_ name: String) throws -> [[String]] {
    try String(contentsOfFile: "input/" + name, encoding: .utf8).split(separator: "\n").map { $0.split(separator: " ").map(String.init) }
}
enum UseAction: String {
    case quaff, read, wield, wear, eat
    func accepts(_ category: ItemCategory) -> Bool {
        switch (self, category) {
        case (.quaff, .potion), (.read, .scroll), (.wield, .weapon), (.wear, .armor), (.eat, .food): return true
        default: return false
        }
    }
}
enum Command { case move(Int, Int), wait, pickup, descend, use(UseAction, Int) }
func expandCommands(_ rows: [[String]]) -> [Command] {
    var commands: [Command] = []
    for words in rows {
        let command: Command
        let count: Int
        switch words[0] {
        case "move":
            let (dx, dy) = directions[directionNames.firstIndex(of: words[1])!]
            command = .move(dx, dy); count = words.count > 2 ? Int(words[2])! : 1
        case "wait": command = .wait; count = words.count > 1 ? Int(words[1])! : 1
        case "pickup": command = .pickup; count = 1
        case "descend": command = .descend; count = 1
        default: command = .use(UseAction(rawValue: words[0])!, Int(words[1])!); count = 1
        }
        commands += Array(repeating: command, count: count)
    }
    return commands
}
func decimalOne(_ numerator: Int, _ denominator: Int) -> String {
    if denominator == 0 { return "-" }
    let rounded = (20 * numerator + denominator) / (2 * denominator)
    return "\(rounded / 10).\(rounded % 10)"
}
func exploration(_ level: Level) -> (Int, Int) {
    var explored = 0
    var total = 0
    for y in 0..<level.height { for x in 0..<level.width where level.terrain[y][x] != 32 {
        total += 1
        if level.memory[y][x] != 32 { explored += 1 }
    } }
    return (explored, total)
}
final class Player {
    var x: Int
    var y: Int
    var depth = 1
    var hp: Int
    var maxHP: Int
    var level = 1
    var xp = 0
    var gold = 0
    var food: Int
    var poison = 0
    var pack: [Item] = []
    var weapon: Item?
    var armor: Item?
    init(_ x: Int, _ y: Int, _ hp: Int, _ food: Int) { self.x = x; self.y = y; self.hp = hp; maxHP = hp; self.food = food }
    func defense(_ types: [ItemType]) -> Int {
        if let armor, case .armor(let value) = types[armor.kind].category { return 10 + value + armor.bonus }
        return 10
    }
}
struct AttackStats {
    var count = 0
    var hits = 0
    var criticals = 0
    var damage = 0
    mutating func record(_ outcome: AttackOutcome, _ amount: Int) {
        count += 1
        if outcome != .miss { hits += 1; damage += amount }
        if outcome == .critical { criticals += 1 }
    }
    func line(_ label: String) -> String { "\(label) \(count) hits \(hits) criticals \(criticals) damage \(damage) accuracy \(decimalOne(100 * hits, count))" }
}
final class Game {
    let config: Config
    let monsterTypes: [MonsterType]
    let itemTypes: [ItemType]
    let commands: [Command]
    let generator: Minstd
    let levels: [Level]
    let player: Player
    var turn = 1
    var messages: [String] = []
    var mapLines: [String] = []
    var visible: [[Bool]]
    var distance: [[Int?]] = []
    var result: String?
    var cause = ""
    var succeeded = 0
    var failed = 0
    var unused = 0
    var moves = 0
    var playerAttacks = AttackStats()
    var monsterAttacks = AttackStats()
    var poisonDamage = 0
    var starvationDamage = 0
    var usage = Array(repeating: 0, count: 6)
    var kills: [Int]
    var current: Level { levels[player.depth - 1] }
    init(_ config: Config, _ monsterTypes: [MonsterType], _ originalItems: [ItemType], _ commands: [Command]) {
        self.config = config; self.monsterTypes = monsterTypes; self.commands = commands
        let originalNames = Dictionary(uniqueKeysWithValues: originalItems.enumerated().map { ($0.element.name, $0.offset) })
        let amulet = originalItems.count
        let itemTypes = originalItems + [ItemType(name: "amulet", minDepth: 0, maxDepth: 0, weight: 0, category: .amulet)]
        self.itemTypes = itemTypes
        let generation = Minstd(config.generationSeed)
        let builder = LevelGenerator(minimum: config.minSize, maxSplit: config.maxSplit, roomMin: config.roomMin, roomMax: config.roomMax)
        var levels: [Level] = []
        for depth in 1...config.levels {
            let level = builder.generate(generation, depth, config.width, config.height)
            let cell = level.target
            if depth < config.levels { level.terrain[cell.y][cell.x] = 62 }
            else { level.items.append(Item(amulet, cell.x, cell.y)) }
            Game.placeMonsters(level, monsterTypes, config, generation)
            Game.placeItems(level, itemTypes, config, generation)
            levels.append(level)
        }
        self.levels = levels
        let arrival = levels[0].arrival
        let player = Player(arrival.x, arrival.y, config.maxHP, config.foodStart)
        for name in config.startItems {
            let kind = originalNames[name]!
            let item = Item(kind, arrival.x, arrival.y)
            player.pack.append(item)
            if case .weapon = itemTypes[kind].category, player.weapon == nil { player.weapon = item }
            if case .armor = itemTypes[kind].category, player.armor == nil { player.armor = item }
        }
        self.player = player
        generator = Minstd(config.gameSeed)
        kills = Array(repeating: 0, count: monsterTypes.count)
        visible = Array(repeating: Array(repeating: false, count: config.width), count: config.height)
    }
    private static func placeMonsters(_ level: Level, _ types: [MonsterType], _ config: Config, _ generator: Minstd) {
        let candidates = types.indices.filter { types[$0].minDepth <= level.depth && level.depth <= types[$0].maxDepth }
        let weights = candidates.map { types[$0].weight }
        let count = config.monsterBase + config.monsterStep * (level.depth - 1)
        for index in 0..<count {
            let kind = candidates[generator.select(weights)]
            var cell: Cell
            while true {
                let (room, drawn) = level.drawRoomCell(generator)
                cell = drawn
                if room != level.arrivalRoom && level.terrain[cell.y][cell.x] == 46 && level.monsterAt(cell.x, cell.y) == nil { break }
            }
            let hp = types[kind].hp.roll(generator)
            let asleep = generator.draw() % 100 < config.sleepChance
            level.monsters.append(Monster(index + 1, kind, cell.x, cell.y, hp, asleep))
        }
        level.monstersCreated = count
    }
    private static func placeItems(_ level: Level, _ types: [ItemType], _ config: Config, _ generator: Minstd) {
        let candidates = types.indices.filter { types[$0].minDepth <= level.depth && level.depth <= types[$0].maxDepth }
        let weights = candidates.map { types[$0].weight }
        let count = config.itemBase + config.itemStep * (level.depth - 1)
        for _ in 0..<count {
            let kind = candidates[generator.select(weights)]
            var cell: Cell
            while true {
                cell = level.drawRoomCell(generator).1
                if level.terrain[cell.y][cell.x] == 46 && level.itemAt(cell.x, cell.y) == nil { break }
            }
            let amount: Int
            if case .gold(let dice) = types[kind].category { amount = dice.roll(generator) } else { amount = 0 }
            level.items.append(Item(kind, cell.x, cell.y, amount))
        }
        level.itemsPlaced = level.items.count
    }
    func say(_ text: String) {
        let number = String(turn)
        messages.append(String(repeating: "0", count: max(0, 4 - number.count)) + number + " " + text)
    }
    func hungerState() -> String {
        if player.food > config.foodHungry { return "normal" }
        if player.food > config.foodWeak { return "hungry" }
        return player.food > 0 ? "weak" : "starving"
    }
    func die(_ cause: String) { say("You die."); result = "died"; self.cause = cause }
    func updateView() {
        let level = current
        visible = fieldOfView(level, player.x, player.y, config.radius)
        for y in 0..<level.height { for x in 0..<level.width where visible[y][x] {
            level.memory[y][x] = level.itemAt(x, y).map { itemTypes[$0.kind].symbol } ?? level.terrain[y][x]
        } }
        for monster in level.monsters {
            let seen = visible[monster.y][monster.x]
            if seen && !monster.wasVisible { say("You see the \(monsterTypes[monster.kind].name).") }
            monster.wasVisible = seen
        }
    }
    func run() {
        updateView()
        for command in commands {
            if result != nil { unused += 1; continue }
            if !execute(command) { failed += 1; continue }
            succeeded += 1
            if result == nil { advanceTurn() }
        }
        if result == nil { result = "alive"; cause = "commands_exhausted" }
    }
    func advanceTurn() {
        updateView()
        let level = current
        distance = distances(level, player.x, player.y)
        for monster in level.monsters {
            monster.energy += monsterTypes[monster.kind].speed
            while monster.energy >= 2 {
                monster.energy -= 2
                monsterAction(monster)
                if result != nil { return }
            }
        }
        endTurn()
        if result != nil { return }
        if config.checkpoints.contains(turn) {
            mapLines.append("CHECKPOINT turn \(turn) depth \(player.depth)")
            mapLines += mapRows(level, true)
            mapLines.append(statusLine())
        }
        turn += 1
    }
    func execute(_ command: Command) -> Bool {
        switch command {
        case .move(let dx, let dy): return movePlayer(dx, dy)
        case .wait: return true
        case .pickup: return pickup()
        case .descend: return descend()
        case .use(let action, let number): return useItem(action, number)
        }
    }
    func movePlayer(_ dx: Int, _ dy: Int) -> Bool {
        let level = current
        let x = player.x + dx
        let y = player.y + dy
        if !passable(level, x, y) { say("You bump into a wall."); return false }
        if !canMove(level, player.x, player.y, dx, dy) { say("You cannot move diagonally through a door."); return false }
        if let monster = level.monsterAt(x, y) { playerAttack(monster); return true }
        player.x = x; player.y = y; moves += 1
        if let item = level.itemAt(x, y) { say("You see \(item.referenceName(itemTypes)) here.") }
        else if level.terrain[y][x] == 62 { say("There is a staircase down here.") }
        return true
    }
    func pickup() -> Bool {
        let level = current
        guard let item = level.itemAt(player.x, player.y) else { say("There is nothing here."); return false }
        let name = item.displayName(itemTypes)
        switch itemTypes[item.kind].category {
        case .gold: player.gold += item.amount; say("You pick up \(name).")
        case .amulet: say("You pick up the amulet."); say("You win!"); result = "won"; cause = "amulet"
        default:
            if player.pack.count >= config.packLimit { say("Your pack is full."); return false }
            player.pack.append(item)
            say("You pick up the \(name) (\(player.pack.count)).")
        }
        level.items.removeAll { $0 === item }
        level.picked += 1; usage[0] += 1
        return true
    }
    func descend() -> Bool {
        if current.terrain[player.y][player.x] != 62 { say("There are no stairs here."); return false }
        player.depth += 1
        player.x = current.arrival.x; player.y = current.arrival.y
        say("You descend to depth \(player.depth).")
        return true
    }
    func useItem(_ action: UseAction, _ number: Int) -> Bool {
        if number > player.pack.count { say("You do not have that item."); return false }
        let index = number - 1
        let item = player.pack[index]
        let category = itemTypes[item.kind].category
        if !action.accepts(category) { say("You cannot \(action.rawValue) that."); return false }
        switch action {
        case .wield:
            if player.weapon === item { say("You are already wielding that."); return false }
            player.weapon = item; usage[4] += 1; say("You are now wielding the \(item.displayName(itemTypes)).")
        case .wear:
            if player.armor === item { say("You are already wearing that."); return false }
            player.armor = item; usage[5] += 1; say("You are now wearing the \(item.displayName(itemTypes)).")
        case .quaff:
            player.pack.remove(at: index); usage[1] += 1; say("You quaff the \(item.displayName(itemTypes)).")
            guard case .potion(let effect) = category else { preconditionFailure() }
            switch effect {
            case .heal(let dice):
                player.hp += dice.roll(generator)
                if player.hp > player.maxHP { player.maxHP += 1; player.hp = player.maxHP }
                player.poison = 0; say("You feel better.")
            case .poison(let turns): player.poison += turns; say("You feel very sick.")
            case .level:
                say("You feel more experienced.")
                if player.level <= config.xpLevels.count { gainXP(config.xpLevels[player.level - 1] - player.xp) }
            }
        case .read:
            player.pack.remove(at: index); usage[2] += 1; say("You read the \(item.displayName(itemTypes)).")
            guard case .scroll(let effect) = category else { preconditionFailure() }
            readScroll(effect)
        case .eat:
            player.pack.remove(at: index); usage[3] += 1
            guard case .food(let nutrition) = category else { preconditionFailure() }
            player.food = min(config.foodMax, player.food + nutrition)
            say("You eat the \(item.displayName(itemTypes)).")
        }
        return true
    }
    func readScroll(_ effect: ScrollEffect) {
        let level = current
        switch effect {
        case .mapping:
            for y in 0..<level.height { for x in 0..<level.width where level.terrain[y][x] != 32 && level.memory[y][x] == 32 { level.memory[y][x] = level.terrain[y][x] } }
            say("A map forms in your mind.")
        case .teleport:
            while true {
                let cell = level.drawRoomCell(generator).1
                if (cell.x != player.x || cell.y != player.y) && level.monsterAt(cell.x, cell.y) == nil { player.x = cell.x; player.y = cell.y; break }
            }
            say("You are teleported.")
        case .enchantWeapon:
            if let weapon = player.weapon { say("Your \(weapon.displayName(itemTypes)) glows blue."); weapon.bonus += 1 }
            else { say("Your hands twitch.") }
        case .enchantArmor:
            if let armor = player.armor { say("Your \(armor.displayName(itemTypes)) glows silver."); armor.bonus += 1 }
            else { say("Your skin tingles.") }
        }
    }
    func playerAttack(_ monster: Monster) {
        monster.asleep = false
        let kind = monsterTypes[monster.kind]
        var toHit = player.level
        var dice = Dice(1, 2)
        var bonus = 0
        if let weapon = player.weapon, case .weapon(let damage, let hit) = itemTypes[weapon.kind].category {
            toHit += hit + weapon.bonus; dice = damage; bonus = weapon.bonus
        }
        if ["weak", "starving"].contains(hungerState()) { toHit -= 2 }
        let (outcome, damage) = resolveAttack(generator, toHit, kind.defense, dice, bonus)
        playerAttacks.record(outcome, damage)
        if outcome == .miss { say("You miss the \(kind.name)."); return }
        say("You hit the \(kind.name)\(outcome == .critical ? " hard" : "") for \(damage).")
        monster.hp -= damage
        if monster.hp <= 0 {
            say("You kill the \(kind.name).")
            current.monsters.removeAll { $0 === monster }; current.kills += 1; kills[monster.kind] += 1
            gainXP(kind.xp)
        }
    }
    func gainXP(_ amount: Int) {
        player.xp += amount
        while player.level <= config.xpLevels.count && player.xp >= config.xpLevels[player.level - 1] {
            player.level += 1
            let gained = config.hitDie.roll(generator)
            player.maxHP += gained; player.hp += gained
            say("Welcome to level \(player.level).")
        }
    }
    func monsterAttack(_ monster: Monster) {
        let kind = monsterTypes[monster.kind]
        let (outcome, damage) = resolveAttack(generator, kind.toHit, player.defense(itemTypes), kind.damage, 0)
        monsterAttacks.record(outcome, damage)
        if outcome == .miss { say("The \(kind.name) misses you."); return }
        say("The \(kind.name) hits you\(outcome == .critical ? " hard" : "") for \(damage).")
        player.hp -= damage
        if player.hp <= 0 { die("killed_by \(kind.name)") }
        else if kind.poisonous { player.poison += 5; say("You are poisoned.") }
    }
    func canAttack(_ monster: Monster) -> Bool {
        let dx = player.x - monster.x
        let dy = player.y - monster.y
        return max(abs(dx), abs(dy)) == 1 && canMove(current, monster.x, monster.y, dx, dy)
    }
    func monsterAction(_ monster: Monster) {
        let kind = monsterTypes[monster.kind]
        let sees = visible[monster.y][monster.x]
        if monster.asleep {
            if sees && generator.draw() % 100 < config.wakeChance { monster.asleep = false; say("The \(kind.name) wakes up.") }
        } else if kind.stationary {
            if canAttack(monster) { monsterAttack(monster) }
        } else if kind.erratic && generator.draw() % 2 == 0 { wander(monster) }
        else if sees { chase(monster) }
        else { wander(monster) }
    }
    func wander(_ monster: Monster) {
        let (dx, dy) = directions[generator.rnd(8)]
        if !canMove(current, monster.x, monster.y, dx, dy) { return }
        let x = monster.x + dx
        let y = monster.y + dy
        if x == player.x && y == player.y { monsterAttack(monster) }
        else if current.monsterAt(x, y) == nil { monster.x = x; monster.y = y }
    }
    func chase(_ monster: Monster) {
        if canAttack(monster) { monsterAttack(monster); return }
        let here = distance[monster.y][monster.x]
        var best: (Int, Int, Int)?
        for (dx, dy) in directions {
            if !canMove(current, monster.x, monster.y, dx, dy) { continue }
            let x = monster.x + dx
            let y = monster.y + dy
            guard let value = distance[y][x] else { continue }
            if let here, value >= here { continue }
            if current.monsterAt(x, y) != nil || x == player.x && y == player.y { continue }
            if best == nil || value < best!.0 { best = (value, x, y) }
        }
        if let best { monster.x = best.1; monster.y = best.2 }
    }
    func endTurn() {
        for monster in current.monsters where monsterTypes[monster.kind].regenerates && monster.hp < monster.maxHP { monster.hp += 1 }
        if player.poison > 0 {
            player.hp -= 1; poisonDamage += 1
            if player.hp <= 0 { die("poison"); return }
            player.poison -= 1
            if player.poison == 0 { say("You feel less sick.") }
        }
        if player.food == 0 {
            player.hp -= 1; starvationDamage += 1
            if player.hp <= 0 { die("starvation"); return }
        } else {
            let before = hungerState()
            player.food -= 1
            let after = hungerState()
            if before != after {
                switch after {
                case "hungry": say("You are getting hungry.")
                case "weak": say("You feel weak from hunger.")
                case "starving": say("You are starving.")
                default: preconditionFailure()
                }
            }
        }
        if turn % config.regenInterval == 0 && player.poison == 0 && player.food > 0 && player.hp < player.maxHP { player.hp += 1 }
    }
    func mapRows(_ level: Level, _ currentLevel: Bool) -> [String] {
        let border = "+" + String(repeating: "-", count: level.width) + "+"
        var rows = [border]
        for y in 0..<level.height {
            var row: [UInt8] = [124]
            for x in 0..<level.width {
                let symbol: UInt8
                if !currentLevel || !visible[y][x] { symbol = level.memory[y][x] }
                else if x == player.x && y == player.y { symbol = 64 }
                else if let monster = level.monsterAt(x, y) { symbol = monsterTypes[monster.kind].symbol }
                else if let item = level.itemAt(x, y) { symbol = itemTypes[item.kind].symbol }
                else { symbol = level.terrain[y][x] }
                row.append(symbol)
            }
            row.append(124); rows.append(String(decoding: row, as: UTF8.self))
        }
        rows.append(border)
        return rows
    }
    func statusLine() -> String {
        "STATUS hp \(player.hp)/\(player.maxHP) level \(player.level) xp \(player.xp) defense \(player.defense(itemTypes)) gold \(player.gold) food \(player.food) \(hungerState()) poison \(player.poison)"
    }
    func finalBlock() -> [String] {
        var lines = ["FINAL turn \(succeeded) depth \(player.depth)"]
        for level in levels.prefix(player.depth) {
            let (explored, total) = exploration(level)
            lines.append("LEVEL \(level.depth) explored \(explored)/\(total)")
            lines += mapRows(level, level.depth == player.depth)
        }
        lines.append(statusLine())
        return lines
    }
    func statsLines() -> [String] {
        var lines = ["result \(result!)", "cause \(cause)", "turns \(succeeded)", "depth \(player.depth)", "level \(player.level)", "xp \(player.xp)",
            "hp \(player.hp)/\(player.maxHP)", "defense \(player.defense(itemTypes))", "gold \(player.gold)", "food \(player.food) \(hungerState())", "poison \(player.poison)",
            "weapon \(player.weapon.map { $0.displayName(itemTypes) } ?? "-")", "armor \(player.armor.map { $0.displayName(itemTypes) } ?? "-")",
            "commands \(commands.count) executed \(succeeded) failed \(failed) unused \(unused)", "moves \(moves)", playerAttacks.line("player_attacks"), monsterAttacks.line("monster_attacks"),
            "poison_damage \(poisonDamage) starvation_damage \(starvationDamage)",
            "picked \(usage[0]) quaffed \(usage[1]) read \(usage[2]) eaten \(usage[3]) wielded \(usage[4]) worn \(usage[5])", "kills \(kills.reduce(0, +))"]
        for index in monsterTypes.indices where kills[index] > 0 { lines.append("KILL \(monsterTypes[index].name) \(kills[index])") }
        for level in levels {
            let (explored, total) = exploration(level)
            lines.append("LEVEL \(level.depth) rooms \(level.rooms.count) explored \(explored)/\(total) \(decimalOne(100 * explored, total)) monsters \(level.kills)/\(level.monstersCreated) items \(level.picked)/\(level.itemsPlaced)")
        }
        for (index, item) in player.pack.enumerated() {
            let marker = player.weapon === item ? " (wielded)" : (player.armor === item ? " (worn)" : "")
            lines.append("INVENTORY \(index + 1) \(item.displayName(itemTypes))\(marker)")
        }
        return lines
    }
}

let config = Config(try readRows("config.txt"))
let monsterTypes = try readRows("monsters.txt").map(MonsterType.init)
let itemTypes = try readRows("items.txt").map(ItemType.init)
let commands = expandCommands(try readRows("commands.txt"))
let game = Game(config, monsterTypes, itemTypes, commands)
game.run()
try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
for (name, lines) in [("messages.txt", game.messages), ("maps.txt", game.mapLines + game.finalBlock()), ("stats.txt", game.statsLines())] {
    let text = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    try text.write(toFile: "output/" + name, atomically: true, encoding: .utf8)
}
