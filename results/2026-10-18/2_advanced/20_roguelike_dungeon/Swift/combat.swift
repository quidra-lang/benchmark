struct Dice {
    let count: Int
    let sides: Int
    init(_ count: Int, _ sides: Int) { self.count = count; self.sides = sides }
    init(_ text: String) {
        let words = text.split(separator: "d")
        count = Int(words[0])!; sides = Int(words[1])!
    }
    func roll(_ generator: Minstd) -> Int { generator.roll(count, sides) }
}
enum AttackOutcome: Equatable { case miss, hit, critical }
func resolveAttack(_ generator: Minstd, _ toHit: Int, _ defense: Int, _ dice: Dice, _ bonus: Int) -> (AttackOutcome, Int) {
    let roll = 1 + generator.rnd(20)
    if roll == 1 { return (.miss, 0) }
    if roll == 20 { return (.critical, max(1, dice.roll(generator) + dice.roll(generator) + bonus)) }
    if roll + toHit >= defense { return (.hit, max(1, dice.roll(generator) + bonus)) }
    return (.miss, 0)
}
