func squaredDistance(_ first: Point, _ second: Point) -> Int { let dx = first.x - second.x, dy = first.y - second.y; return dx * dx + dy * dy }
func integerSqrt(_ value: Int) -> Int {
    var low = 0, high = value + 1
    while low + 1 < high { let middle = (low + high) / 2; if middle <= value / middle { low = middle } else { high = middle } }
    return low
}
func advance(_ point: Point, _ goal: Point, _ step: Int) -> (Point, Bool) {
    let dx = goal.x - point.x, dy = goal.y - point.y, squared = squaredDistance(point, goal)
    if squared <= step * step { return (goal, true) }
    let length = integerSqrt(squared)
    return (Point(x: point.x + dx * step / length, y: point.y + dy * step / length), false)
}
func damageDealt(_ hp: Int, _ power: Int, _ armor: Int) -> Int { min(hp, max(1, power - armor)) }
struct Effect {
    var strength = 0, remaining = 0
    var source: Int? = nil
    var active: Bool { remaining > 0 }
    mutating func receive(_ strength: Int, _ duration: Int, _ source: Int? = nil) {
        if strength > self.strength { self.strength = strength; remaining = duration; self.source = source }
        else if strength == self.strength { remaining = max(remaining, duration) }
    }
    mutating func advanceTime() { remaining -= 1; if remaining == 0 { strength = 0; source = nil } }
}
struct Projectile {
    let number: Int
    let tower: Int
    let target: Int
    var position: Point
    var aim: Point
    let targets: Targets
    let stats: Level
    mutating func fly() -> Bool {
        if stats.shotSpeed == 0 { return true }
        let (position, arrived) = advance(self.position, aim, stats.shotSpeed)
        self.position = position
        return arrived
    }
}
