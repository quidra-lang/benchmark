import Foundation

struct MonsterType {
    let name: String
    let symbol: UInt8
    let minDepth: Int
    let maxDepth: Int
    let weight: Int
    let hp: Dice
    let toHit: Int
    let defense: Int
    let damage: Dice
    let speed: Int
    let xp: Int
    let erratic: Bool
    let stationary: Bool
    let regenerates: Bool
    let poisonous: Bool
    init(_ words: [String]) {
        name = words[0]; symbol = words[1].utf8.first!; minDepth = Int(words[2])!; maxDepth = Int(words[3])!
        weight = Int(words[4])!; hp = Dice(words[5]); toHit = Int(words[6])!; defense = Int(words[7])!
        damage = Dice(words[8]); speed = Int(words[9])!; xp = Int(words[10])!
        erratic = words[11].contains("E"); stationary = words[11].contains("S")
        regenerates = words[11].contains("R"); poisonous = words[11].contains("P")
    }
}
enum PotionEffect { case heal(Dice), poison(Int), level }
enum ScrollEffect { case mapping, teleport, enchantWeapon, enchantArmor }
enum ItemCategory { case weapon(Dice, Int), armor(Int), potion(PotionEffect), scroll(ScrollEffect), food(Int), gold(Dice), amulet }
struct ItemType {
    let name: String
    let minDepth: Int
    let maxDepth: Int
    let weight: Int
    let category: ItemCategory
    init(name: String, minDepth: Int, maxDepth: Int, weight: Int, category: ItemCategory) {
        self.name = name; self.minDepth = minDepth; self.maxDepth = maxDepth; self.weight = weight; self.category = category
    }
    init(_ words: [String]) {
        name = words[1]; minDepth = Int(words[2])!; maxDepth = Int(words[3])!; weight = Int(words[4])!
        switch words[0] {
        case "weapon": category = .weapon(Dice(words[5]), Int(words[6])!)
        case "armor": category = .armor(Int(words[5])!)
        case "potion":
            switch words[5] {
            case "heal": category = .potion(.heal(Dice(words[6])))
            case "poison": category = .potion(.poison(Int(words[6])!))
            case "level": category = .potion(.level)
            default: preconditionFailure()
            }
        case "scroll":
            switch words[5] {
            case "mapping": category = .scroll(.mapping)
            case "teleport": category = .scroll(.teleport)
            case "enchant_weapon": category = .scroll(.enchantWeapon)
            case "enchant_armor": category = .scroll(.enchantArmor)
            default: preconditionFailure()
            }
        case "food": category = .food(Int(words[5])!)
        case "gold": category = .gold(Dice(words[5]))
        default: preconditionFailure()
        }
    }
    var symbol: UInt8 {
        switch category {
        case .weapon: return 41
        case .armor: return 91
        case .potion: return 33
        case .scroll: return 63
        case .food: return 37
        case .gold: return 36
        case .amulet: return 34
        }
    }
}
final class Monster {
    let number: Int
    let kind: Int
    var x: Int
    var y: Int
    var hp: Int
    let maxHP: Int
    var asleep: Bool
    var energy = 0
    var wasVisible = false
    init(_ number: Int, _ kind: Int, _ x: Int, _ y: Int, _ hp: Int, _ asleep: Bool) {
        self.number = number; self.kind = kind; self.x = x; self.y = y; self.hp = hp; maxHP = hp; self.asleep = asleep
    }
}
final class Item {
    let kind: Int
    let x: Int
    let y: Int
    var bonus = 0
    let amount: Int
    init(_ kind: Int, _ x: Int, _ y: Int, _ amount: Int = 0) { self.kind = kind; self.x = x; self.y = y; self.amount = amount }
    func displayName(_ types: [ItemType]) -> String {
        let type = types[kind]
        let name = type.name.replacingOccurrences(of: "_", with: " ")
        switch type.category {
        case .weapon, .armor: return "+\(bonus) \(name)"
        case .gold: return "\(amount) gold"
        default: return name
        }
    }
    func referenceName(_ types: [ItemType]) -> String {
        if case .gold = types[kind].category { return displayName(types) }
        return "the " + displayName(types)
    }
}
