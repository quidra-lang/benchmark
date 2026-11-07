final class Stop {
    let section: Int, turn: Bool, dwell: Int, arrival: Int, departure: Int
    var actualArrival: Int?, actualDeparture: Int?
    init(_ w: [String], _ layout: Layout) { section = layout.section(w[2]); turn = w[0] == "TURN"; dwell = Int(w[3])!; arrival = Int(w[4])!; departure = Int(w[5])! }
}
final class Train {
    let name: String, length: Int, acceleration: Int, deceleration: Int, maximum: Int, entry: Int, scheduledEntry: Int, initialSpeed: Int
    var stops: [Stop] = [], exit = 0, scheduledExit = 0, state = 0, up = true, path: [(Int, Int)] = [], head = 0, speed = 0, nextStop = 0, dwelling = false, awaiting: Int?, emergency = false, crossed: Int?, actualEntry: Int?, actualExit: Int?, distance = 0, maxSpeed = 0, standing = 0, passes = 0
    init(_ w: [String], _ layout: Layout) { name = w[1]; length = Int(w[2])!; acceleration = Int(w[3])!; deceleration = Int(w[4])!; maximum = Int(w[5])!; entry = layout.boundary(w[6]); scheduledEntry = Int(w[7])!; initialSpeed = Int(w[8])! }
    var headIndex: Int { path.lastIndex { $0.1 < head } ?? 0 }
    func body(_ layout: Layout) -> [(section: Int, start: Int, lo: Int, hi: Int)] {
        if state != 1 { return [] }
        return path.compactMap { section, start in
            let end = start + layout.sections[section].length
            return start < head && end > head - length ? (section, start, max(head - length, start), min(head, end)) : nil
        }
    }
}
enum Trains {
    static func braking(_ speed: Int, _ deceleration: Int) -> Int { let n = speed / deceleration; return n * speed - deceleration * n * (n + 1) / 2 }
    static func speed(_ train: Train, _ distance: Int?) -> Int {
        let low = max(train.speed - train.deceleration, 0)
        if train.emergency { return low }
        let high = min(train.speed + train.acceleration, train.maximum)
        for speed in stride(from: high, through: low, by: -1) { if distance == nil || speed + braking(speed, train.deceleration) <= distance! { return speed } }
        return low
    }
    static func read(_ layout: Layout, _ locks: Interlocking) -> ([Train], [(Int, Int, Int)]) {
        var trains: [Train] = [], requests: [(Int, Int, Int)] = []
        for w in inputLines("trains.txt") {
            if w[0] == "TRAIN" { trains.append(Train(w, layout)); continue }
            let i = trains.firstIndex { $0.name == w[1] }!
            switch w[0] { case "REQUEST": requests.append((Int(w[3])!, locks.route(w[2]), i)); case "EXIT": trains[i].exit = layout.boundary(w[2]); trains[i].scheduledExit = Int(w[3])!; default: trains[i].stops.append(Stop(w, layout)) }
        }
        return (trains, requests)
    }
}
