import Foundation

enum Movement: Equatable { case ground, air }
final class EnemyType {
    let name: String
    let symbol: UInt8
    let movement: Movement
    let hp: Int
    let armor: Int
    let speed: Int
    let bounty: Int
    let lives: Int
    let regen: Int
    let splitInto: Int?
    let splitCount: Int
    var spawned = 0, kills = 0, leaks = 0, damage = 0
    init(_ fields: [String], _ known: [String: Int]) {
        name = fields[1]; symbol = fields[2].utf8.first!; movement = fields[3] == "air" ? .air : .ground
        hp = Int(fields[4])!; armor = Int(fields[5])!; speed = Int(fields[6])!; bounty = Int(fields[7])!
        lives = Int(fields[8])!; regen = Int(fields[9])!; splitInto = known[fields[10]]; splitCount = Int(fields[11])!
    }
}
struct Group {
    let kind: Int
    let spawn: Int
    let count: Int
    let delay: Int
    let interval: Int
    let multiplier: Int
    func spawnTick(_ start: Int, _ index: Int) -> Int { start + delay + index * interval }
}
struct Wave {
    let reward: Int
    var groups: [Group] = []
    var enemyCount: Int { groups.reduce(0) { $0 + $1.count } }
}
func parseWaves(_ lines: [String]) -> ([EnemyType], [Wave]) {
    var types: [EnemyType] = [], known: [String: Int] = [:], waves: [Wave] = []
    for line in lines {
        let fields = line.split(separator: " ").map(String.init)
        if fields[0] == "enemy" { let type = EnemyType(fields, known); known[type.name] = types.count; types.append(type) }
        else if fields[0] == "wave" { waves.append(Wave(reward: Int(fields[1])!)) }
        else { waves[waves.count - 1].groups.append(Group(kind: known[fields[1]]!, spawn: Int(fields[2])! - 1, count: Int(fields[3])!, delay: Int(fields[4])!, interval: Int(fields[5])!, multiplier: Int(fields[6])!)) }
    }
    return (types, waves)
}
enum EnemyPosition { case ground(Cell, Cell, Int), air(Point) }
final class Enemy {
    let number: Int
    let kind: Int
    let multiplier: Int
    let maxHP: Int
    var hp: Int
    var slow = Effect(), burn = Effect()
    var alive = true
    var position: EnemyPosition
    init(_ number: Int, _ kind: Int, _ types: [EnemyType], _ multiplier: Int, _ position: EnemyPosition) {
        self.number = number; self.kind = kind; self.multiplier = multiplier
        let hp = types[kind].hp * multiplier / 100
        maxHP = hp; self.hp = hp; self.position = position
    }
    var point: Point {
        switch position {
        case .air(let point): return point
        case .ground(let cell, let next, let progress): return Point(x: 100 * cell.x + (next.x - cell.x) * progress, y: 100 * cell.y + (next.y - cell.y) * progress)
        }
    }
    var occupiedCell: Cell {
        switch position { case .air(let point): return Cell(x: (point.x + 50) / 100, y: (point.y + 50) / 100); case .ground(let cell, let next, let progress): return progress < 50 ? cell : next }
    }
    func remaining(_ field: DistanceField) -> Int {
        switch position { case .air(let point): return integerSqrt(squaredDistance(point, cellCenter(field.exit))); case .ground(_, let next, let progress): return 100 * field.at(next)! + 100 - progress }
    }
    func slowedSpeed(_ types: [EnemyType]) -> Int { slow.active ? types[kind].speed * (100 - slow.strength) / 100 : types[kind].speed }
    func split(_ number: Int, _ types: [EnemyType]) -> Enemy { Enemy(number, types[kind].splitInto!, types, multiplier, position) }
}
