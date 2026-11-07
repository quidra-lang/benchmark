import Foundation

struct Vector3 {
    let x: Double; let y: Double; let z: Double
    subscript(_ axis: Int) -> Double { axis == 0 ? x : axis == 1 ? y : z }
    static func - (_ first: Vector3, _ second: Vector3) -> Vector3 { Vector3(x: first.x - second.x, y: first.y - second.y, z: first.z - second.z) }
}
struct Segment {
    let number: Int; let leg: Int; let phase: String; let ts: Double; let te: Double
    let start: Vector3; let velocity: Vector3; let end: Vector3
    func position(_ time: Double) -> Vector3 { let elapsed = time - ts; return Vector3(x: start.x + velocity.x * elapsed, y: start.y + velocity.y * elapsed, z: start.z + velocity.z * elapsed) }
}
struct WaypointTime { let time: Double; let level: Int }
struct Trajectory {
    let segments: [Segment]; let arrival: Double; let length: Double; let waypointTimes: [WaypointTime]
    func activeSegment(_ time: Double) -> Segment? {
        if time < segments[0].ts || time >= segments.last!.te { return nil }
        return segments.first { $0.ts <= time && time < $0.te }
    }
    func observation(_ time: Double) -> (position: Vector3, segment: Segment)? { activeSegment(time).map { ($0.position(time), $0) } }
}
func buildTrajectory(_ plan: Plan, _ types: [String: AircraftType]) -> Trajectory {
    let waypoints = plan.waypoints, type = types[plan.type]!
    var current = Double(plan.departure + plan.delay), level = plan.level + plan.offset, segments: [Segment] = [], routeLength = 0.0
    var times = [WaypointTime(time: current, level: level)]
    for leg in 1..<waypoints.count {
        let first = waypoints[leg - 1], last = waypoints[leg], dx = last.x - first.x, dy = last.y - first.y
        let length = sqrt(Double(dx * dx + dy * dy)) / 10, duration = length * 3600 / Double(plan.speed)
        let vx = (Double(dx) / 10) / duration, vy = (Double(dy) / 10) / duration
        let target = last.level.map { $0 + plan.offset } ?? level, x = Double(first.x) / 10, y = Double(first.y) / 10
        routeLength += length
        let start = Vector3(x: x, y: y, z: Double(level * 100)), end = Vector3(x: Double(last.x) / 10, y: Double(last.y) / 10, z: Double(target * 100))
        if target == level {
            segments.append(Segment(number: segments.count + 1, leg: leg, phase: "LVL", ts: current, te: current + duration, start: start, velocity: Vector3(x: vx, y: vy, z: 0), end: end))
        } else {
            let climbing = target > level, rate = climbing ? type.climb : type.descent, vz = climbing ? Double(rate) / 60 : -(Double(rate) / 60)
            let changeTime = Double(abs(target - level) * 6000) / Double(rate), change = Vector3(x: x + vx * changeTime, y: y + vy * changeTime, z: Double(target * 100))
            segments.append(Segment(number: segments.count + 1, leg: leg, phase: climbing ? "CLB" : "DES", ts: current, te: current + changeTime, start: start, velocity: Vector3(x: vx, y: vy, z: vz), end: change))
            segments.append(Segment(number: segments.count + 1, leg: leg, phase: "LVL", ts: current + changeTime, te: current + duration, start: change, velocity: Vector3(x: vx, y: vy, z: 0), end: end))
        }
        current += duration; level = target; times.append(WaypointTime(time: current, level: level))
    }
    return Trajectory(segments: segments, arrival: current, length: routeLength, waypointTimes: times)
}
