import Foundation
struct Request { let number: Int; let route: Int; let time: Int; var reason: String }
func position(_ reverse: Bool) -> String { reverse ? "R" : "N" }
final class Simulation {
    let layout: Layout, locks: Interlocking, trains: [Train], scheduled: [(Int, Int, Int)], script: [(Int, [String])], end: Int, throwTime: Int, overlapTime: Int, snapshotTimes: [Int], checker = Safety()
    var occupancy: [[Int]], queue: [Request] = [], requestCount = 0, granted = 0, dropped = 0, events: [String] = [], snapshots: [String] = [], time = 0
    init() {
        let layout = Layout(), locks = Interlocking(layout), (trains, scheduled) = Trains.read(layout, locks), params = inputLines("params.txt").map { $0.dropFirst().map { Int($0)! } }
        self.layout = layout; self.locks = locks; self.trains = trains; self.scheduled = scheduled
        script = inputLines("events.txt").map { (Int($0[0])!, Array($0.dropFirst())) }; end = params[0][0]; throwTime = params[1][0]; overlapTime = params[2][0]; snapshotTimes = params[3]; occupancy = Array(repeating: [], count: layout.sections.count)
    }
    func log(_ text: String) { events.append("\(time) \(text)") }
    var occupied: [Bool] { layout.sections.indices.map { layout.sections[$0].failed || !occupancy[$0].isEmpty } }
    func addRequest(_ route: Int, _ requester: String) {
        requestCount += 1; queue.append(Request(number: requestCount, route: route, time: time, reason: "none")); locks.routes[route].statistics[0] += 1
        log("REQUEST q\(requestCount) \(locks.routes[route].name) \(requester)")
    }
    func startThrow(_ point: Int, _ target: Bool) { layout.points[point].motion = Motion(target: target, completion: time + throwTime); log("MOVE \(layout.points[point].name) \(position(target)) until \(time + throwTime)") }
    func cancel(_ route: Int) {
        let requests = queue.filter { $0.route == route }, r = locks.routes[route]
        if !requests.isEmpty { for request in requests { log("DROP q\(request.number) \(r.name)"); dropped += 1 }; queue.removeAll { $0.route == route }; return }
        if r.state == 1 {
            r.statistics[3] += 1
            let signal = layout.signals[r.start]
            if signal.aspect != 0 && occupied[signal.section] { r.state = 3; r.release = time + r.approach; log("CANCEL \(r.name) approach until \(r.release!)") }
            else { locks.release(route, layout); log("CANCEL \(r.name) released") }
        } else { log("CANCEL \(r.name) \(r.state == 0 ? "none" : "refused")") }
    }
    func event(_ w: [String]) {
        switch w[0] {
        case "REQUEST": addRequest(locks.route(w[1]), "OPERATOR")
        case "CANCEL": cancel(locks.route(w[1]))
        case "THROW":
            let p = layout.point(w[1]), target = w[2] == "R", point = layout.points[p]
            let result: String
            if !locks.pointLocks[p].isEmpty { result = "locked" }
            else if point.failed { result = "failed" }
            else if point.motion != nil { result = "moving" }
            else if occupied[point.common] { result = "occupied" }
            else if point.position == target { result = "none" }
            else { result = "start" }
            log("THROW \(point.name) \(position(target)) \(result)")
            if result == "start" { startThrow(p, target) }
        case "TCFAIL", "TCFIX": layout.sections[layout.section(w[1])].failed = w[0] == "TCFAIL"; log(w[0] + " " + w[1])
        case "POINTFAIL": let point = layout.points[layout.point(w[1])]; point.failed = true; if point.motion != nil { point.motion!.completion = nil }; log("POINTFAIL " + w[1])
        default:
            let point = layout.points[layout.point(w[1])]; point.failed = false; log("POINTFIX " + w[1])
            if point.motion != nil { point.motion!.completion = time + throwTime; log("MOVE \(w[1]) \(position(point.motion!.target)) until \(time + throwTime)") }
        }
    }
    func reason(_ route: Int) -> String? {
        let r = locks.routes[route], occupied = self.occupied
        func opposite(_ other: Int) -> Bool { locks.routes[other].up != r.up }
        if r.state != 0 { return "busy" }
        if let other = r.conflicts.first(where: { [1,3].contains(locks.routes[$0].state) }) { return "conflict " + locks.routes[other].name }
        for section in r.sections {
            if occupied[section] { return "occupied " + layout.sections[section].name }
            if locks.sectionRoute[section] != nil || locks.sectionOverlap[section].contains(where: opposite) { return "locked " + layout.sections[section].name }
        }
        for section in r.overlap {
            if occupied[section] { return "occupied " + layout.sections[section].name }
            if locks.sectionRoute[section].map(opposite) == true || locks.sectionOverlap[section].contains(where: opposite) { return "locked " + layout.sections[section].name }
        }
        for (p, target) in r.points + r.flank {
            let point = layout.points[p]
            if locks.pointLocks[p].contains(where: { $0.1 != target }) { return "point \(point.name) locked" }
            if (point.motion?.target ?? point.position) == target { continue }
            if point.failed { return "point \(point.name) failed" }
            if point.motion != nil { return "point \(point.name) moving" }
            if occupied[point.common] { return "point \(point.name) occupied" }
        }
        return nil
    }
    func judgeRequests() {
        var i = 0
        while i < queue.count {
            let route = queue[i].route, r = locks.routes[route]
            if let reason = reason(route) {
                if reason != queue[i].reason { log("WAIT q\(queue[i].number) \(r.name) \(reason)"); queue[i].reason = reason }
                i += 1
            } else {
                let request = queue.remove(at: i); locks.lock(route)
                let wait = time - request.time; granted += 1; r.statistics[1] += 1; r.statistics[4] += wait; r.statistics[5] = max(r.statistics[5], wait)
                log("GRANT q\(request.number) \(r.name) wait \(wait)")
                for (p, target) in r.points + r.flank where layout.points[p].motion == nil && layout.points[p].position != target { startThrow(p, target) }
            }
        }
    }
    func passSignal(_ train: Train, _ index: Int) {
        let route = locks.routes.firstIndex { $0.start == index && [1,3].contains($0.state) }, signal = layout.signals[index]
        log("PASS \(train.name) \(signal.name) \(Signals.aspects[signal.aspect]) \(route.map { locks.routes[$0].name } ?? "-")")
        signal.passes += 1; train.passes += 1
        if let route { locks.routes[route].state = 2; locks.routes[route].statistics[2] += 1 }
        if signal.aspect == 0 { log("SPAD \(train.name) \(signal.name)"); train.emergency = true }
        checker.passing(time, train.name, signal.name, signal.aspect == 0)
    }
    func runTrain(_ train: Train, _ entered: inout Set<Int>) {
        if train.state == 2 { return }
        if train.state == 0 {
            let boundary = layout.boundaries[train.entry]
            if time < train.scheduledEntry || occupied[boundary.section] || entered.contains(train.entry) { return }
            entered.insert(train.entry); train.state = 1; train.up = boundary.end == 0; train.path = [(boundary.section, 0)]; train.head = 0; train.speed = train.initialSpeed; train.actualEntry = time
            log("ENTER \(train.name) \(boundary.name)")
        }
        if train.dwelling {
            let stop = train.stops[train.nextStop]
            if time < stop.actualArrival! + stop.dwell || time < stop.departure { return }
            train.dwelling = false; train.awaiting = train.nextStop; train.nextStop += 1
            if stop.turn {
                let (section, start) = train.path[train.headIndex], end = start + layout.sections[section].length
                train.path = train.body(layout).reversed().map { ($0.section, end - ($0.start + layout.sections[$0.section].length)) }
                train.head = end - (train.head - train.length); train.up.toggle(); log("REVERSE \(train.name) \(layout.sections[stop.section].name)")
            }
        }
        let oldSpeed = train.speed
        var distance: Int?
        if train.crossed == nil {
            let first = train.path[train.headIndex]
            var section = first.0, d = first.1 + layout.sections[first.0].length - train.head
            search: while true {
                if layout.signal(section, train.up).map({ layout.signals[$0].aspect == 0 }) == true || (train.nextStop < train.stops.count && train.stops[train.nextStop].section == section) { distance = d; break }
                switch layout.beyond(section, train.up) {
                case .boundary: distance = nil; break search
                case .buffer, .impassable: distance = d; break search
                case .section(let next): d += layout.sections[next].length; section = next
                }
            }
        }
        let speed = Trains.speed(train, distance)
        var remaining = speed, headIndex = train.headIndex
        while remaining > 0 {
            if train.crossed != nil { train.head += remaining; break }
            let (section, start) = train.path[headIndex], end = start + layout.sections[section].length
            if train.head + remaining <= end { train.head += remaining; break }
            remaining -= end - train.head; train.head = end
            if let signal = layout.signal(section, train.up) { passSignal(train, signal) }
            if let stop = train.awaiting, train.stops[stop].section == section { log("DEPART \(train.name) \(layout.sections[section].name)"); train.stops[stop].actualDeparture = time; train.awaiting = nil }
            switch layout.beyond(section, train.up) {
            case .boundary: train.crossed = end
            case .section(let next): train.path.append((next, end)); headIndex = train.path.count - 1
            default: fatalError()
            }
        }
        train.speed = speed; train.distance += speed; train.maxSpeed = max(train.maxSpeed, speed)
        if speed == 0 { train.emergency = false }
        let (section, start) = train.path[train.headIndex]
        var arrived = false
        if train.nextStop < train.stops.count {
            let stop = train.stops[train.nextStop]
            if speed == 0 && section == stop.section && train.head == start + layout.sections[section].length { stop.actualArrival = time; train.dwelling = true; arrived = true; log("ARRIVE \(train.name) \(layout.sections[section].name)") }
        }
        if speed == 0 && !arrived { train.standing += 1; if oldSpeed > 0 { log("HOLD \(train.name) \(layout.sections[section].name)") } }
        if let boundary = train.crossed, train.head - train.length >= boundary { train.state = 2; train.actualExit = time; log("EXIT \(train.name) \(layout.boundaries[train.exit].name)") }
    }
    func releaseSections() {
        let occupied = self.occupied
        for route in locks.routes.indices where locks.routes[route].state == 2 {
            let r = locks.routes[route]
            for section in r.sections where locks.sectionRoute[section] == route && occupied[section] { r.passed.insert(section) }
            for section in r.sections {
                if locks.sectionRoute[section] != route { continue }
                if r.passed.contains(section) && !occupied[section] { locks.unlockSection(route, section, layout); log("RELEASE \(r.name) \(layout.sections[section].name)") }
                else { break }
            }
            if r.sections.allSatisfy({ locks.sectionRoute[$0] != route }) { locks.release(route, layout); log("DONE " + r.name) }
            else if !r.overlap.isEmpty && r.overlapLocked {
                r.counter = occupied[r.sections.last!] ? r.counter + 1 : 0
                if r.counter == overlapTime { locks.unlockOverlap(route, layout); log("OVERLAP " + r.name) }
            }
        }
    }
    func statistics() {
        for route in locks.routes where route.state != 0 { route.statistics[6] += 1 }
        for (p, point) in layout.points.enumerated() { if !locks.pointLocks[p].isEmpty { point.lockedSeconds += 1 }; if point.motion != nil { point.movingSeconds += 1 } }
        for (s, section) in layout.sections.enumerated() {
            if section.failed || !occupancy[s].isEmpty { section.occupiedSeconds += 1 }
            if locks.sectionRoute[s] != nil || !locks.sectionOverlap[s].isEmpty { section.lockedSeconds += 1 }
            section.trains.formUnion(occupancy[s])
        }
        for signal in layout.signals { signal.seconds[signal.aspect] += 1 }
    }
    func snapshot() -> [String] {
        var height = 0, width = 0
        for s in layout.sections { height = max(height, s.row + 1); width = max(width, s.last + 1) }
        for p in layout.points { height = max(height, p.row + 1); width = max(width, p.column + 1) }
        for s in layout.signals { height = max(height, s.row + 1); width = max(width, s.column + 1) }
        for b in layout.buffers { height = max(height, b.row + 1); width = max(width, b.column + 1) }
        for label in layout.labels { height = max(height, label.row + 1); width = max(width, label.column + label.text.count) }
        var grid = Array(repeating: Array(repeating: Character(" "), count: width), count: height)
        for label in layout.labels { for (i, c) in label.text.enumerated() { grid[label.row][label.column + i] = c } }
        for (s, section) in layout.sections.enumerated() {
            let character: Character = section.failed ? "#" : locks.sectionRoute[s] != nil ? "=" : !locks.sectionOverlap[s].isEmpty ? "~" : "-"
            for column in section.first...section.last { grid[section.row][column] = character }
        }
        for (i, train) in trains.enumerated() {
            for body in train.body(layout) {
                let section = layout.sections[body.section], length = section.length, n = section.last - section.first + 1
                let p = train.up ? body.lo - body.start : length - (body.hi - body.start), q = train.up ? body.hi - body.start : length - (body.lo - body.start)
                for j in 0..<n where p * n < (j + 1) * length && q * n > j * length {
                    let old = grid[section.row][section.first + j]
                    grid[section.row][section.first + j] = old.isLowercase || old == "*" ? "*" : Character(UnicodeScalar(97 + i)!)
                }
            }
        }
        for b in layout.buffers { grid[b.row][b.column] = "|" }
        for p in layout.points { grid[p.row][p.column] = p.display }
        for s in layout.signals { grid[s.row][s.column] = Array("XYG")[s.aspect] }
        var lines = ["SNAPSHOT \(time)"]
        for var row in grid { while row.last == " " { row.removeLast() }; lines.append(String(row)) }
        for (i, train) in trains.enumerated() where train.state == 1 {
            let sections = train.body(layout).map { layout.sections[$0.section].name }.joined(separator: ",")
            lines.append("TRAIN \(Character(UnicodeScalar(97 + i)!)) \(train.name) \(train.up ? "UP" : "DOWN") \(train.speed) \(sections)")
        }
        let routes = locks.routes.filter { $0.state != 0 }.map { "\($0.name)/\(Interlocking.states[$0.state])" }
        lines.append("ROUTES " + (routes.isEmpty ? "-" : routes.joined(separator: " ")))
        return lines
    }
    func run() {
        for time in 0...end {
            self.time = time
            for point in layout.points where point.motion?.completion == time { point.position = point.motion!.target; point.motion = nil; point.throwsCount += 1; log("POINT \(point.name) \(position(point.position))") }
            for r in locks.routes.indices where locks.routes[r].state == 3 && locks.routes[r].release == time { locks.release(r, layout); log("TIMEOUT " + locks.routes[r].name) }
            for (t, route, train) in scheduled where t == time { addRequest(route, trains[train].name) }
            for (t, words) in script where t == time { event(words) }
            judgeRequests()
            let aspects = Signals.decide(layout, locks, occupied)
            for i in aspects.indices where aspects[i] != layout.signals[i].aspect { layout.signals[i].aspect = aspects[i]; log("SIGNAL \(layout.signals[i].name) \(Signals.aspects[aspects[i]])") }
            var entered: Set<Int> = []
            for train in trains { runTrain(train, &entered) }
            occupancy = Array(repeating: [], count: layout.sections.count)
            for (i, train) in trains.enumerated() { for body in train.body(layout) { occupancy[body.section].append(i) } }
            releaseSections(); checker.check(time, layout, locks, occupancy, trains); statistics()
            if snapshotTimes.contains(time) { snapshots += snapshot() }
        }
    }
    func reports() -> ([String], [String]) {
        var summary: [String] = []
        for r in locks.routes { let s = r.statistics; summary.append("ROUTE \(r.name) \(layout.signals[r.start].name)-\(r.finishName) requests \(s[0]) grants \(s[1]) uses \(s[2]) cancels \(s[3]) wait \(s[4]) maxwait \(s[5]) locked \(s[6])") }
        for p in layout.points { summary.append("POINT \(p.name) throws \(p.throwsCount) locked \(p.lockedSeconds) moving \(p.movingSeconds) final \(p.display)") }
        for s in layout.sections { summary.append("SECTION \(s.name) occupied \(s.occupiedSeconds) locked \(s.lockedSeconds) trains \(s.trains.count)") }
        for s in layout.signals { summary.append("SIGNAL \(s.name) red \(s.seconds[0]) yellow \(s.seconds[1]) green \(s.seconds[2]) passes \(s.passes)") }
        var counts = [0,0,0]
        for (i, train) in trains.enumerated() { counts[train.state] += 1; summary.append("TRAIN \(train.name) \(Character(UnicodeScalar(97 + i)!)) \(["WAITING", "RUNNING", "EXITED"][train.state]) distance \(train.distance) maxspeed \(train.maxSpeed) standing \(train.standing) passes \(train.passes)") }
        summary.append("TRAINS total \(trains.count) exited \(counts[2]) running \(counts[1]) waiting \(counts[0])")
        var csv = ["train,location,scheduled,actual,delay"], punctuality = [0,0,0,0,0]
        for train in trains {
            var records: [(String, Int, Int?)] = [("enter:" + layout.boundaries[train.entry].name, train.scheduledEntry, train.actualEntry)]
            for stop in train.stops { records.append(("arr:" + layout.sections[stop.section].name, stop.arrival, stop.actualArrival)); records.append(("dep:" + layout.sections[stop.section].name, stop.departure, stop.actualDeparture)) }
            records.append(("exit:" + layout.boundaries[train.exit].name, train.scheduledExit, train.actualExit))
            for (location, scheduled, actual) in records {
                if let actual { let delay = actual - scheduled; punctuality[delay > 0 ? 1 : 0] += 1; punctuality[3] += max(delay, 0); punctuality[4] = max(punctuality[4], delay); csv.append("\(train.name),\(location),\(scheduled),\(actual),\(delay)") }
                else { punctuality[2] += 1; csv.append("\(train.name),\(location),\(scheduled),-,-") }
            }
        }
        summary.append("PUNCTUALITY on_time \(punctuality[0]) late \(punctuality[1]) missing \(punctuality[2]) total_delay \(punctuality[3]) max_delay \(punctuality[4])")
        summary.append("REQUESTS total \(requestCount) granted \(granted) dropped \(dropped) pending \(queue.count)")
        return (csv, summary)
    }
}
func write(_ name: String, _ lines: [String]) {
    try! FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    try! (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: false, encoding: .ascii)
}
let simulation = Simulation()
simulation.run()
let (trainLog, summary) = simulation.reports()
write("events.txt", simulation.events); write("snapshots.txt", simulation.snapshots); write("train_log.csv", trainLog); write("safety.txt", simulation.checker.lines()); write("summary.txt", summary)
