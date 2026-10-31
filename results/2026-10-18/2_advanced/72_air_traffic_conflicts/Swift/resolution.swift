import Foundation

enum Manoeuvre {
    case level(Int), speed, delay(Int)
    var name: String { switch self { case let .level(amount): return amount > 0 ? "level_up" : "level_down"; case .speed: return "speed_down"; case let .delay(amount): return "delay_\(amount)" } }
}
func manoeuvres(_ maximumDelay: Int) -> [Manoeuvre] { [.level(10), .level(-10), .speed] + stride(from: 60, through: maximumDelay, by: 60).map { .delay($0) } }
func lowerPriority(_ first: Plan, _ second: Plan) -> Bool { let a = first.departure + first.delay, b = second.departure + second.delay; return a == b ? first.callsign > second.callsign : a > b }
func propose(_ plan: Plan, _ manoeuvre: Manoeuvre, _ types: [String: AircraftType], _ settings: Settings) -> Plan? {
    var changed = plan
    switch manoeuvre {
    case let .level(amount): changed.offset += amount; if changed.levels.contains(where: { $0 < settings.minimumLevel || $0 > settings.maximumLevel }) { return nil }
    case .speed: changed.speed = changed.speed * 9 / 10; if changed.speed < types[changed.type]!.minimum { return nil }
    case let .delay(amount): changed.delay += amount
    }
    return changed
}
