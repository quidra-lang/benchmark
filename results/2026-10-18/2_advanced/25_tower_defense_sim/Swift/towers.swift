import Foundation

enum Targets {
    case ground, air, both
    init(_ text: String) { self = text == "ground" ? .ground : (text == "air" ? .air : .both) }
    func canAim(_ movement: Movement) -> Bool { switch self { case .ground: return movement == .ground; case .air: return movement == .air; case .both: return true } }
}
struct Level {
    let cost: Int
    let range: Int
    let power: Int
    let interval: Int
    let shotSpeed: Int
    let splash: Int
    let slowRate: Int
    let slowTime: Int
    let burnAmount: Int
    let burnTime: Int
    init(_ fields: [String]) {
        let values = fields.dropFirst().map { Int($0)! }
        cost = values[0]; range = values[1]; power = values[2]; interval = values[3]; shotSpeed = values[4]
        splash = values[5]; slowRate = values[6]; slowTime = values[7]; burnAmount = values[8]; burnTime = values[9]
    }
}
struct TowerType { let name: String; let symbol: UInt8; let targets: Targets; let levels: [Level] }
func parseTowerTypes(_ lines: [String]) -> [TowerType] {
    var types: [TowerType] = [], index = 0
    while index < lines.count {
        let fields = lines[index].split(separator: " ").map(String.init), count = Int(lines[index].split(separator: " ")[4])!
        let levels = lines[(index + 1)..<(index + 1 + count)].map { Level($0.split(separator: " ").map(String.init)) }
        types.append(TowerType(name: fields[1], symbol: fields[2].utf8.first!, targets: Targets(fields[3]), levels: levels)); index += count + 1
    }
    return types
}
enum TargetMode: String { case first = "FIRST", last = "LAST", strongest = "STRONGEST", weakest = "WEAKEST", closest = "CLOSEST" }
final class Tower {
    let number: Int
    let kind: Int
    let cell: Cell
    var level = 0
    var mode = TargetMode.first
    var ready: Int
    var investment: Int
    let built: Int
    var sold: Int? = nil
    var shots = 0, hits = 0, fizzles = 0, kills = 0, damage = 0
    init(_ number: Int, _ kind: Int, _ types: [TowerType], _ cell: Cell, _ tick: Int) { self.number = number; self.kind = kind; self.cell = cell; ready = tick; investment = types[kind].levels[0].cost; built = tick }
    var standing: Bool { sold == nil }
    var center: Point { cellCenter(cell) }
    func stats(_ types: [TowerType]) -> Level { types[kind].levels[level] }
    func inRange(_ point: Point, _ types: [TowerType]) -> Bool { let reach = stats(types).range; return squaredDistance(center, point) <= reach * reach }
    func selectTarget(_ enemies: [Enemy], _ types: [EnemyType], _ towerTypes: [TowerType], _ field: DistanceField) -> Int? {
        var best: Int? = nil, bestKey = 0
        for (index, enemy) in enemies.enumerated() {
            if !enemy.alive || !towerTypes[kind].targets.canAim(types[enemy.kind].movement) || !inRange(enemy.point, towerTypes) { continue }
            let key: Int
            switch mode { case .first: key = enemy.remaining(field); case .last: key = -enemy.remaining(field); case .strongest: key = -enemy.hp; case .weakest: key = enemy.hp; case .closest: key = squaredDistance(center, enemy.point) }
            if best == nil || key < bestKey { best = index; bestKey = key }
        }
        return best
    }
}
