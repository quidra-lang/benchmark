enum Signals {
    static let aspects = ["RED", "YELLOW", "GREEN"]
    static func decide(_ layout: Layout, _ locks: Interlocking, _ occupied: [Bool]) -> [Int] {
        var cleared: [Int?] = Array(repeating: nil, count: layout.signals.count)
        for (i, r) in locks.routes.enumerated() where r.state == 1 {
            if (r.points + r.flank).allSatisfy({ layout.points[$0.0].detected && layout.points[$0.0].position == $0.1 }) && (r.sections + r.overlap).allSatisfy({ !occupied[$0] }) { cleared[r.start] = i }
        }
        return cleared.map { route in
            guard let route else { return 0 }
            switch locks.routes[route].finish { case .signal(let signal): return cleared[signal] == nil ? 1 : 2; case .buffer: return 1; case .boundary: return 2 }
        }
    }
}
