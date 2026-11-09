enum Finish { case signal(Int), buffer, boundary }
final class Route {
    let name: String, start: Int, finish: Finish, finishName: String, up: Bool, points: [(Int, Bool)], sections: [Int], overlap: [Int], flank: [(Int, Bool)], conflicts: [Int], approach: Int
    var state = 0, passed: Set<Int> = [], overlapLocked = false, counter = 0, release: Int?, statistics = Array(repeating: 0, count: 7)
    init(_ w: [String], _ layout: Layout, _ names: [String]) {
        name = w[1]; start = layout.signals.firstIndex { $0.name == w[2] }!; finishName = w[3]; up = layout.signals[start].up
        if let signal = layout.signals.firstIndex(where: { $0.name == w[3] }) { finish = .signal(signal) }
        else if layout.buffers.contains(where: { $0.name == w[3] }) { finish = .buffer }
        else { finish = .boundary }
        func pointList(_ text: String) -> [(Int, Bool)] { text == "-" ? [] : text.split(separator: ",").map { let fields = $0.split(separator: ":"); return (layout.point(String(fields[0])), fields[1] == "R") } }
        func sectionList(_ text: String) -> [Int] { text == "-" ? [] : text.split(separator: ",").map { layout.section(String($0)) } }
        points = pointList(w[4]); sections = sectionList(w[5]); overlap = sectionList(w[6]); flank = pointList(w[7]); conflicts = w[8] == "-" ? [] : w[8].split(separator: ",").map { names.firstIndex(of: String($0))! }; approach = Int(w[9])!
    }
}
final class Interlocking {
    static let states = ["none", "LOCKED", "USED", "APPROACH"]
    var routes: [Route], sectionRoute: [Int?], sectionOverlap: [Set<Int>], pointLocks: [[(Int, Bool)]]
    func route(_ name: String) -> Int { routes.firstIndex { $0.name == name }! }
    init(_ layout: Layout) {
        let lines = inputLines("routes.txt"), names = lines.map { $0[1] }
        routes = lines.map { Route($0, layout, names) }; sectionRoute = Array(repeating: nil, count: layout.sections.count); sectionOverlap = Array(repeating: [], count: layout.sections.count); pointLocks = Array(repeating: [], count: layout.points.count)
    }
    func lock(_ index: Int) {
        let r = routes[index]; r.state = 1; r.passed.removeAll(); r.overlapLocked = true; r.counter = 0; r.release = nil
        for s in r.sections { sectionRoute[s] = index }
        for s in r.overlap { sectionOverlap[s].insert(index) }
        for (p, q) in r.points + r.flank { pointLocks[p].append((index, q)) }
    }
    func unlockSection(_ route: Int, _ section: Int, _ layout: Layout) {
        if sectionRoute[section] == route { sectionRoute[section] = nil }
        for (p, point) in layout.points.enumerated() where point.common == section { pointLocks[p].removeAll { $0.0 == route } }
    }
    func unlockOverlap(_ route: Int, _ layout: Layout) {
        for section in routes[route].overlap {
            sectionOverlap[section].remove(route)
            for (p, point) in layout.points.enumerated() where point.common == section { pointLocks[p].removeAll { $0.0 == route } }
        }
        routes[route].overlapLocked = false
    }
    func release(_ route: Int, _ layout: Layout) {
        for section in routes[route].sections where sectionRoute[section] == route { sectionRoute[section] = nil }
        if routes[route].overlapLocked { unlockOverlap(route, layout) }
        for p in pointLocks.indices { pointLocks[p].removeAll { $0.0 == route } }
        routes[route].state = 0; routes[route].release = nil
    }
}
