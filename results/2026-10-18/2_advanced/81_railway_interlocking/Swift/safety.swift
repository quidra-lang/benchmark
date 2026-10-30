final class Safety {
    static let names = ["OCCUPANCY", "POINT_MOTION", "CONFLICT", "SIGNAL_PASSING"]
    var checks = [0,0,0,0], violations = [0,0,0,0], records: [String] = []
    func record(_ time: Int, _ property: Int, _ details: String) { violations[property] += 1; records.append("VIOLATION \(time) \(Self.names[property]) \(details)") }
    func passing(_ time: Int, _ train: String, _ signal: String, _ red: Bool) { checks[3] += 1; if red { record(time, 3, train + " " + signal) } }
    func check(_ time: Int, _ layout: Layout, _ locks: Interlocking, _ occupancy: [[Int]], _ trains: [Train]) {
        for (s, section) in layout.sections.enumerated() { checks[0] += 1; if occupancy[s].count >= 2 { record(time, 0, section.name + " " + occupancy[s].map { trains[$0].name }.joined(separator: ",")) } }
        for (p, point) in layout.points.enumerated() where point.motion != nil {
            checks[1] += 1
            if !occupancy[point.common].isEmpty { record(time, 1, point.name + " occupied") }
            else if locks.pointLocks[p].contains(where: { locks.routes[$0.0].state == 2 || locks.routes[$0.0].state == 3 }) { record(time, 1, point.name + " locked") }
        }
        for a in locks.routes.indices where [1,3].contains(locks.routes[a].state) {
            for b in (a + 1)..<locks.routes.count where [1,3].contains(locks.routes[b].state) { checks[2] += 1; if locks.routes[a].conflicts.contains(b) || locks.routes[b].conflicts.contains(a) { record(time, 2, locks.routes[a].name + " " + locks.routes[b].name) } }
        }
    }
    func lines() -> [String] {
        (0..<4).map { "\(Self.names[$0]) \(violations[$0] == 0 ? "OK" : "FAIL") checks \(checks[$0]) violations \(violations[$0])" } + records + [violations.allSatisfy { $0 == 0 } ? "RESULT SAFE" : "RESULT UNSAFE"]
    }
}
