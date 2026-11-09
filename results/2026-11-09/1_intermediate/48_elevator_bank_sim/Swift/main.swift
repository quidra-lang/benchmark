import Foundation
let policies = ["COST", "NEAREST", "ROUND", "ETA"]
let configKeys = ["FLOORS", "CARS", "CAPACITY", "DOOR", "START", "POLICY", "ZONES", "PARK", "PATIENCE", "BYPASS", "PERIOD", "LIMIT", "COMPARE"]
let argumentCounts = ["CALL": 3, "CANCEL": 1, "OUT": 1, "IN": 1, "HOLD": 2, "FIRE": 1, "RESET": 0, "WHERE": 1, "STATUS": 0]
func sign(_ n: Int) -> Int {
    n == 0 ? 0 : n > 0 ? 1 : -1
}
func joined(_ a: [String]) -> String {
    a.isEmpty ? "-" : a.joined(separator: ",")
}
func average(_ total: Int, _ count: Int) -> String {
    count == 0 ? "-" : "\(total * 100 / count / 100)." + String(format: "%02d", total * 100 / count % 100)
}
struct ConfigError: Error {
    let message: String
}
func check(_ good: Bool, _ message: String) throws {
    if !good {
        throw ConfigError(message: message)
    }
}
final class Config {
    var floors = 0, cars = 0, capacity = 0, door = 0, bypass = 100, limit = 1000
    var park: Int?, patience: Int?, period: Int?
    var starts: [Int] = [], homes: [Int] = [], zones: [(Int, Int)] = []
    var policy = "COST", compare: [String] = []
    func contains(_ e: Int, _ f: Int) -> Bool {
        zones[e].0 <= f && f <= zones[e].1
    }
    static func parse(_ settings: [[String]]) throws -> Config {
        var entries: [String: [String]] = [:]
        for w in settings {
            try check(configKeys.contains(w[0]), "unknown key \(w[0])")
            try check(entries[w[0]] == nil, "duplicate key \(w[0])")
            entries[w[0]] = Array(w.dropFirst())
        }
        for k in configKeys.prefix(5) {
            try check(entries[k] != nil, "missing key \(k)")
        }
        let c = Config()
        for k in configKeys {
            guard let a = entries[k] else {
                continue
            }
            let count = k == "START" || k == "ZONES" ? a.count == c.cars : k == "PARK" ? a.count == c.cars + 1 : k == "COMPARE" ? (1...4).contains(a.count) : a.count == 1
            try check(count, "wrong number of values for \(k)")
            func bound(_ s: String, _ lo: Int, _ hi: Int) throws -> Int {
                let n = Int(s)!
                try check(n >= lo && n <= hi, "bad value for \(k)")
                return n
            }
            switch k {
                case "FLOORS": c.floors = try bound(a[0], 2, 50)
                case "CARS": c.cars = try bound(a[0], 1, 8)
                case "CAPACITY": c.capacity = try bound(a[0], 1, 20)
                case "DOOR": c.door = try bound(a[0], 1, 9)
                case "START": c.starts = try a.map {
                    try bound($0, 1, c.floors)
                }
                case "POLICY": try check(policies.contains(a[0]), "bad value for \(k)")
                c.policy = a[0]
                case "ZONES": c.zones = try a.map {
                    s in let z = s.split(separator: ":").map {
                        Int($0)!
                    }
                    try check(1 <= z[0] && z[0] < z[1] && z[1] <= c.floors, "bad value for ZONES")
                    return (z[0], z[1])
                }
                case "PARK": c.park = try bound(a[0], 0, 100)
                c.homes = try a.dropFirst().map {
                    try bound($0, 1, c.floors)
                }
                case "PATIENCE": c.patience = try bound(a[0], 1, 1000)
                case "BYPASS": c.bypass = try bound(a[0], 50, 100)
                case "PERIOD": c.period = try bound(a[0], 1, 1000)
                case "LIMIT": c.limit = try bound(a[0], 1, 5000)
                default: try check(a.allSatisfy {
                    policies.contains($0)
                }
                && Set(a).count == a.count, "bad value for \(k)")
                c.compare = a
            }
        }
        if c.zones.isEmpty {
            c.zones = Array(repeating: (1, c.floors), count: c.cars)
        }
        for e in 0..<c.cars {
            try check(c.contains(e, c.starts[e]), "car \(e + 1) starts outside its zone")
            if c.park != nil {
                try check(c.contains(e, c.homes[e]), "car \(e + 1) home outside its zone")
            }
        }
        return c
    }
    var header: [String] {
        func opt(_ n: Int?) -> String {
            n.map(String.init) ?? "off"
        }
        var lines = ["config: floors=\(floors) cars=\(cars) capacity=\(capacity) door=\(door) policy=\(policy) park=\(opt(park)) patience=\(opt(patience)) bypass=\(bypass) period=\(opt(period)) limit=\(limit) compare=\(joined(compare))"]
        for e in 0..<cars {
            lines.append("E\(e + 1): start=\(starts[e]) zone=\(zones[e].0)-\(zones[e].1) home=\(park == nil ? "-" : String(homes[e]))")
        }
        return lines
    }
}
struct Event {
    let time: Int, command: String, values: [Int]
}
func validate(_ c: Config, _ raw: [(Int, [String])], _ output: inout [String]) -> [Event] {
    var accepted: [Event] = [], last = 0, groups = 0, fire = false, outs: Set<Int> = []
    for (line, w) in raw {
        let time = Int(w[0])!, cmd = w[1]
        var error: String?, a: [Int] = []
        if argumentCounts[cmd] == nil {
            error = "unknown command \(cmd)"
        } else if w.count - 2 != argumentCounts[cmd]! {
            error = "wrong number of arguments for \(cmd)"
        } else if time < last {
            error = "time goes backwards"
        } else {
            a = w.dropFirst(2).map {
                Int($0)!
            }
            func floor(_ f: Int) -> Bool {
                f >= 1 && f <= c.floors
            }
            func car(_ e: Int) -> Bool {
                e >= 1 && e <= c.cars
            }
            switch cmd {
                case "CALL":
                if !floor(a[0]) || !floor(a[1]) {
                    error = "bad floor"
                } else if a[0] == a[1] {
                    error = "same floor"
                } else if !(1...99).contains(a[2]) {
                    error = "bad count"
                } else if !(0..<c.cars).contains(where: {
                    c.contains($0, a[0]) && c.contains($0, a[1])
                }
                ) {
                    error = "no car serves \(a[0])->\(a[1])"
                } else if fire {
                    error = "fire service active"
                }
                case "CANCEL", "WHERE": if a[0] < 1 || a[0] > groups {
                    error = "unknown group"
                }
                case "OUT", "IN": if !car(a[0]) {
                    error = "bad car"
                } else if cmd == "OUT" && outs.contains(a[0]) {
                    error = "car \(a[0]) already out"
                } else if cmd == "IN" && !outs.contains(a[0]) {
                    error = "car \(a[0]) already in"
                }
                case "HOLD": if !car(a[0]) {
                    error = "bad car"
                } else if !(1...9).contains(a[1]) {
                    error = "bad ticks"
                }
                case "FIRE": if !floor(a[0]) {
                    error = "bad floor"
                } else if fire {
                    error = "fire already active"
                }
                case "RESET": if !fire {
                    error = "fire not active"
                }
                default: break
            }
        }
        if let error {
            output.append("line \(line): \(error)")
            continue
        }
        last = time
        if cmd == "CALL" {
            groups += 1
        }
        if cmd == "OUT" {
            outs.insert(a[0])
        }
        if cmd == "IN" {
            outs.remove(a[0])
        }
        if cmd == "FIRE" {
            fire = true
        }
        if cmd == "RESET" {
            fire = false
        }
        accepted.append(Event(time: time, command: cmd, values: a))
    }
    return accepted
}
final class Group {
    let number: Int, a: Int, b: Int, count: Int, time: Int
    var waiting: Int, boarded = 0, delivered = 0, lost = 0, lastBoard = 0, lastAlight = 0, waitTotal = 0, travelTotal = 0
    var car: Int?, cars: Set<Int> = []
    init(_ number: Int, _ a: Int, _ b: Int, _ count: Int, _ time: Int) {
        self.number = number
        self.a = a
        self.b = b
        self.count = count
        self.time = time
        waiting = count
    }
    var label: String {
        "G\(number)"
    }
    var direction: Int {
        sign(b - a)
    }
}
struct Passenger {
    let group: Group, count: Int, time: Int
}
final class Car {
    let number: Int
    var floor: Int, direction = 0, door = 0, idleStart = 0, distance = 0, stops = 0, boarded = 0, busy = 0, energy = 0, service = true
    var calls: [Group] = [], passengers: [Passenger] = []
    init(_ number: Int, _ floor: Int) {
        self.number = number
        self.floor = floor
    }
    var label: String {
        "E\(number)"
    }
    var load: Int {
        passengers.reduce(0) {
            $0 + $1.count
        }
    }
    var targets: Set<Int> {
        Set(passengers.map {
            $0.group.b
        }
        + calls.map(\.a))
    }
}
final class Simulation {
    let config: Config, events: [Event], policy: String, cars: [Car]
    var groups: [Group] = [], pending: [Group] = [], log: [String] = [], fire: Int?
    var lastRound = 0, time = 0, abandoned = 0, evacuated = 0, delivered = 0, waitTotal = 0, travelTotal = 0, maxWait = 0, status = ""
    init(_ c: Config, _ events: [Event], _ policy: String) {
        config = c
        self.events = events
        self.policy = policy
        cars = c.starts.enumerated().map {
            Car($0.offset + 1, $0.element)
        }
    }
    func emit(_ text: String) {
        log.append("\(time) \(text)")
    }
    func bypass(_ c: Car) -> Bool {
        c.load * 100 >= config.capacity * config.bypass
    }
    func cost(_ c: Car, _ g: Group) -> Int {
        let f = c.floor, d = c.direction, x = g.a
        if policy == "NEAREST" || d == 0 {
            return abs(f - x)
        }
        let targets = c.targets
        let distance: Int, via: Int
        if g.direction == d && (x - f) * d >= 0 {
            distance = abs(x - f)
            via = targets.filter {
                ($0 - f) * d > 0 && (x - $0) * d > 0
            }
            .count
        } else {
            let all = targets.union([f]), m = d > 0 ? all.max()! : all.min()!
            distance = abs(f - m) + abs(m - x)
            via = targets.filter {
                ($0 - f) * d > 0
            }
            .count
        }
        return policy == "COST" ? distance : distance + config.door * via + c.door
    }
    @discardableResult func assign(_ g: Group, _ excluded: Car? = nil) -> Bool {
        let candidates = cars.filter {
            $0.service && $0 !== excluded && config.contains($0.number - 1, g.a) && config.contains($0.number - 1, g.b)
        }
        if candidates.isEmpty {
            return false
        }
        let chosen: Car
        if policy == "ROUND" {
            chosen = candidates.first {
                $0.number > lastRound
            }
            ?? candidates[0]
            lastRound = chosen.number
            emit("\(chosen.label) ASSIGN \(g.label)")
        } else {
            chosen = candidates.min {
                cost($0, g) < cost($1, g) || cost($0, g) == cost($1, g) && $0.number < $1.number
            }!
            emit("\(chosen.label) ASSIGN \(g.label) cost=\(cost(chosen, g))")
        }
        if let old = g.car {
            cars[old].calls.removeAll {
                $0 === g
            }
        }
        chosen.calls.append(g)
        g.car = chosen.number - 1
        return true
    }
    func dispatch(_ g: Group) {
        if !assign(g) {
            pending.append(g)
            emit("PENDING \(g.label)")
        }
    }
    func walk(_ g: Group, _ word: String) {
        if let e = g.car {
            cars[e].calls.removeAll {
                $0 === g
            }
        } else {
            pending.removeAll {
                $0 === g
            }
        }
        g.car = nil
        emit("\(word) \(g.label) x\(g.waiting)")
        g.lost += g.waiting
        abandoned += g.waiting
        g.waiting = 0
    }
    func execute(_ e: Event) {
        let a = e.values
        switch e.command {
            case "CALL": let g = Group(groups.count + 1, a[0], a[1], a[2], time)
            groups.append(g)
            emit("CALL \(g.label) \(g.a)->\(g.b) x\(g.count)")
            dispatch(g)
            case "CANCEL": let g = groups[a[0] - 1]
            if g.waiting > 0 {
                walk(g, "CANCEL")
            } else {
                emit("CANCEL \(g.label) ignored")
            }
            case "OUT": let c = cars[a[0] - 1]
            c.service = false
            emit("\(c.label) OUT")
            let calls = c.calls
            c.calls = []
            for g in calls {
                g.car = nil
                dispatch(g)
            }
            case "IN": let c = cars[a[0] - 1]
            c.service = true
            c.idleStart = time
            emit("\(c.label) IN")
            let waiting = pending
            pending = []
            for g in waiting {
                if !assign(g) {
                    pending.append(g)
                }
            }
            case "HOLD": let c = cars[a[0] - 1]
            if c.door > 0 {
                c.door += a[1]
                emit("\(c.label) HOLD \(c.door)")
            } else {
                emit("\(c.label) HOLD ignored")
            }
            case "FIRE": fire = a[0]
            emit("FIRE \(a[0])")
            for g in groups where g.waiting > 0 {
                walk(g, "ABANDON")
            }
            case "RESET": fire = nil
            emit("RESET")
            for c in cars {
                c.idleStart = time
            }
            case "WHERE":
            let g = groups[a[0] - 1], place = g.waiting == 0 ? "-" : g.car.map {
                cars[$0].label
            }
            ?? "pending"
            let riding = cars.compactMap {
                c -> String? in let n = c.passengers.filter {
                    $0.group === g
                }
                .reduce(0) {
                    $0 + $1.count
                }
                return n == 0 ? nil : "\(c.label)x\(n)"
            }
            emit("WHERE \(g.label) waiting=\(g.waiting) car=\(place) riding=\(joined(riding)) delivered=\(g.delivered) lost=\(g.lost)")
            case "STATUS":
            for c in cars {
                emit("STATUS \(c.label) floor=\(c.floor) dir=\(c.direction > 0 ? "up" : c.direction < 0 ? "down" : "idle") door=\(c.door) load=\(c.load) stops=\(joined(Set(c.passengers.map { $0.group.b }).sorted().map(String.init))) calls=\(joined(c.calls.map(\.label))) service=\(c.service ? "in" : "out")")
            }
            emit("STATUS pending=\(joined(pending.map(\.label)))")
            default: break
        }
    }
    func direction(_ c: Car) -> Int {
        let f = c.floor, d = c.direction, here = bypass(c) ? [] : c.calls.filter {
            $0.a == f
        }, targets = c.targets
        if d != 0 && (targets.contains {
            ($0 - f) * d > 0
        }
        || here.contains {
            $0.direction == d
        }
        ) {
            return d
        }
        if let first = here.first {
            return first.direction
        }
        if d != 0 && targets.contains(where: {
            ($0 - f) * d < 0
        }
        ) {
            return -d
        }
        if d == 0, let first = c.calls.first {
            return sign(first.a - f)
        }
        return 0
    }
    func move(_ c: Car, _ d: Int) {
        c.energy += d > 0 ? 3 + c.load : 1
        c.distance += 1
        c.floor += d
    }
    func open(_ c: Car) {
        emit("\(c.label) OPEN \(c.floor)")
        c.door = config.door
        c.stops += 1
        c.energy += 2
        var riding: [Passenger] = []
        for p in c.passengers {
            let g = p.group
            if g.b == c.floor {
                emit("\(c.label) ALIGHT \(g.label) x\(p.count)")
                let w = p.time - g.time, r = time - g.time
                g.delivered += p.count
                g.lastAlight = time
                g.waitTotal += w * p.count
                g.travelTotal += r * p.count
                delivered += p.count
                waitTotal += w * p.count
                travelTotal += r * p.count
                maxWait = max(maxWait, w)
            } else if fire != nil {
                emit("\(c.label) EVACUATE \(g.label) x\(p.count)")
                g.lost += p.count
                evacuated += p.count
            } else {
                riding.append(p)
            }
        }
        c.passengers = riding
        if fire != nil {
            return
        }
        let n = direction(c)
        if n != 0 {
            c.direction = n
        }
        for g in c.calls.filter({
            $0.a == c.floor && $0.direction == n
        }
        ) {
            let k = min(config.capacity - c.load, g.waiting)
            if k > 0 {
                c.passengers.append(Passenger(group: g, count: k, time: time))
                c.boarded += k
                g.waiting -= k
                g.boarded += k
                g.lastBoard = time
                g.cars.insert(c.number)
                emit("\(c.label) BOARD \(g.label) x\(k)")
            }
            if g.waiting == 0 {
                c.calls.removeAll {
                    $0 === g
                }
                g.car = nil
            } else {
                emit("\(c.label) LEFT \(g.label) x\(g.waiting)")
                assign(g, c)
            }
        }
    }
    func advance(_ c: Car) {
        let old = c.floor
        if c.door > 0 {
            c.door -= 1
        }
        if c.door == 0 {
            let n = fire.map {
                sign($0 - c.floor)
            }
            ?? direction(c)
            let stop = fire != nil ? n == 0 && !c.passengers.isEmpty : c.passengers.contains {
                $0.group.b == c.floor
            }
            || !bypass(c) && c.calls.contains {
                $0.a == c.floor && $0.direction == n
            }
            if stop {
                open(c)
            } else if n != 0 {
                c.direction = n
                move(c, n)
            } else {
                if c.direction != 0 {
                    emit("\(c.label) IDLE \(c.floor)")
                    c.direction = 0
                    c.idleStart = time
                }
                if fire == nil && c.service, let p = config.park {
                    let h = config.homes[c.number - 1]
                    if c.floor != h && time - c.idleStart >= p {
                        move(c, sign(h - c.floor))
                        if c.floor == h {
                            emit("\(c.label) PARK \(h)")
                        }
                    }
                }
            }
        }
        if c.door > 0 || c.floor != old {
            c.busy += 1
        }
    }
    func run() {
        var index = 0
        while true {
            if let p = config.patience {
                for g in groups where g.waiting > 0 && time == g.time + p {
                    walk(g, "ABANDON")
                }
            }
            while index < events.count && events[index].time == time {
                execute(events[index])
                index += 1
            }
            for c in cars {
                advance(c)
            }
            let settled = cars.allSatisfy {
                c in c.door == 0 && c.passengers.isEmpty && c.calls.isEmpty && (fire.map {
                    c.floor == $0
                }
                ?? (!c.service || config.park == nil || c.floor == config.homes[c.number - 1]))
            }
            if index == events.count && settled {
                status = "end"
                emit("END")
                return
            }
            if time == config.limit {
                status = "abort"
                emit("ABORT")
                return
            }
            time += 1
        }
    }
    var averages: String {
        "avg_wait=\(average(waitTotal, delivered)) avg_travel=\(average(travelTotal, delivered)) max_wait=\(delivered == 0 ? "-" : String(maxWait))"
    }
    var report: [String] {
        var lines: [String] = []
        for g in groups {
            lines.append("\(g.label) t=\(g.time) \(g.a)->\(g.b) n=\(g.count) delivered=\(g.delivered) lost=\(g.lost) wait=\(g.boarded == g.count ? String(g.lastBoard - g.time) : "-") travel=\(g.delivered == g.count ? String(g.lastAlight - g.time) : "-") cars=\(joined(g.cars.sorted().map(String.init)))")
        }
        for c in cars {
            let x = c.busy * 1000 / (time + 1)
            lines.append("\(c.label) distance=\(c.distance) stops=\(c.stops) boarded=\(c.boarded) busy=\(c.busy) util=\(x / 10).\(x % 10)% energy=\(c.energy)")
        }
        func breakdown(_ label: String, _ gs: [Group]) -> String {
            "\(label): groups=\(gs.count) passengers=\(gs.reduce(0) { $0 + $1.count }) delivered=\(gs.reduce(0) { $0 + $1.delivered }) avg_wait=\(average(gs.reduce(0) { $0 + $1.waitTotal }, gs.reduce(0) { $0 + $1.delivered }))"
        }
        for f in Set(groups.map(\.a)).sorted() {
            lines.append(breakdown("F\(f)", groups.filter {
                $0.a == f
            }
            ))
        }
        if let w = config.period {
            for k in Set(groups.map {
                $0.time / w
            }
            ).sorted() {
                lines.append(breakdown("P\(k) \(k * w)-\(k * w + w - 1)", groups.filter {
                    $0.time / w == k
                }
                ))
            }
        }
        lines.append("summary: groups=\(groups.count) passengers=\(groups.reduce(0) { $0 + $1.count }) delivered=\(delivered) abandoned=\(abandoned) evacuated=\(evacuated) \(averages) end=\(time)")
        return lines
    }
}
final class Scenario {
    let name: String, number: Int
    var config: Config?, simulation: Simulation?
    init(_ name: String, _ number: Int) {
        self.name = name
        self.number = number
    }
    var outcome: String {
        guard let s = simulation else {
            return "invalid"
        }
        return s.status == "abort" ? "aborted" : s.delivered == 0 ? "empty" : "ranked"
    }
}
var input: [String] = []
while let line = readLine() {
    input.append(line)
}
let q = Int(input[0])!
var index = 1, scenarios: [Scenario] = [], output: [String] = []
for number in 0..<q {
    let s = Scenario(input[index].split(separator: " ").map(String.init)[1], number)
    index += 1
    scenarios.append(s)
    var settings: [[String]] = [], raw: [(Int, [String])] = []
    while input[index] != "END" {
        let w = input[index].split(separator: " ").map(String.init)
        if w[0].first!.isNumber {
            raw.append((index + 1, w))
        } else {
            settings.append(w)
        }
        index += 1
    }
    index += 1
    output.append("== \(s.name) ==")
    do {
        let c = try Config.parse(settings)
        s.config = c
        output += c.header
        let events = validate(c, raw, &output), sim = Simulation(c, events, c.policy)
        s.simulation = sim
        sim.run()
        output += sim.log
        output += sim.report
        for p in c.compare {
            let r = Simulation(c, events, p)
            r.run()
            output.append("compare \(p): delivered=\(r.delivered) \(r.averages) end=\(r.time) status=\(r.status)")
        }
    } catch let e as ConfigError {
        output.append("error: \(e.message)")
    } catch {
        fatalError("Unexpected error")
    }
}
output.append("== ranking ==")
let ranked = scenarios.filter {
    $0.outcome == "ranked"
}
.sorted {
    a, b in let x = a.simulation!, y = b.simulation!
    if x.waitTotal * y.delivered != y.waitTotal * x.delivered {
        return x.waitTotal * y.delivered < y.waitTotal * x.delivered
    }
    if x.travelTotal * y.delivered != y.travelTotal * x.delivered {
        return x.travelTotal * y.delivered < y.travelTotal * x.delivered
    }
    return a.number < b.number
}
for (i, s) in ranked.enumerated() {
    output.append("\(i + 1). \(s.name) policy=\(s.config!.policy) \(s.simulation!.averages)")
}
for s in scenarios where s.outcome != "ranked" {
    output.append("- \(s.name) \(s.outcome)")
}
output.append("== policies ==")
for p in policies {
    let runs = ranked.filter {
        $0.config!.policy == p
    }
    .map {
        $0.simulation!
    }
    if !runs.isEmpty {
        let n = runs.reduce(0) {
            $0 + $1.delivered
        }
        output.append("\(p): runs=\(runs.count) avg_wait=\(average(runs.reduce(0) { $0 + $1.waitTotal }, n)) avg_travel=\(average(runs.reduce(0) { $0 + $1.travelTotal }, n))")
    }
}
print(output.joined(separator: "\n"))
