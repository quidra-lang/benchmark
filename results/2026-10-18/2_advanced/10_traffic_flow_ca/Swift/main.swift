import Foundation

func timeText(_ step: Int) -> String { let text = String(step); return String(repeating: "0", count: max(0, 4 - text.count)) + text }
func flag(_ value: Bool) -> String { value ? "Y" : "N" }
func optional(_ value: Int) -> String { value == 0 ? "-" : String(value) }
struct Ratio {
    let numerator: Int
    let denominator: Int
    init(_ numerator: Int, _ denominator: Int = 1) { let divisor = gcd(numerator, denominator); self.numerator = numerator / divisor; self.denominator = denominator / divisor }
    func times(_ weight: Int, _ total: Int) -> Ratio { Ratio(numerator * weight, denominator * total) }
    func plus(_ other: Ratio) -> Ratio { let common = gcd(denominator, other.denominator); return Ratio(numerator * (other.denominator / common) + other.numerator * (denominator / common), denominator / common * other.denominator) }
    var text: String { "\(numerator)/\(denominator)" }
}
struct Route { let segments: [String]; let share: Ratio }
final class Source {
    let node: String
    let rates: [(Int, Int)]
    let segment: Segment
    var queue: [Vehicle] = []
    var head = 0, queueStart = 0, queueMax = 0
    init(_ node: String, _ rates: [(Int, Int)], _ segment: Segment) { self.node = node; self.rates = rates; self.segment = segment }
    var count: Int { queue.count - head }
    func rate(_ step: Int) -> Int { rates.first { step <= $0.1 }?.0 ?? 0 }
}
struct Detector { let name: String; let segment: Segment; let cell: Int; let width: Int }
final class Diagram {
    let segment: Segment
    let lane: Int
    let start: Int
    let end: Int
    var lines: [String] = []
    init(_ segment: Segment, _ lane: Int, _ start: Int, _ end: Int) { self.segment = segment; self.lane = lane; self.start = start; self.end = end }
}
struct Ring { let number: Int; let length: Int; let vmax: Int; let warmup: Int; let measure: Int; let seed: Int; let counts: [Int] }
final class Interval {
    var arrivals = 0, insertions = 0, exits = 0, vehicleSteps = 0, speedSum = 0
    var passing: [Int]
    var occupancy: [Int]
    var occupancySpeed: [Int]
    init(_ count: Int) { passing = Array(repeating: 0, count: count); occupancy = passing; occupancySpeed = passing }
}
final class Move {
    let vehicle: Vehicle
    let segment: Segment
    let cell: Int
    var speed = 0
    init(_ vehicle: Vehicle) { self.vehicle = vehicle; segment = vehicle.segment!; cell = vehicle.cell }
}
func runRing(_ ring: Ring, _ count: Int, _ moving: Int, _ stopped: Int) -> Int {
    let rng = Minstd(ring.seed)
    var positions = (0..<count).map { $0 * ring.length / count }
    var speeds = Array(repeating: 0, count: count)
    var total = 0
    for step in 1...(ring.warmup + ring.measure) {
        let order = (0..<count).sorted { positions[$0] > positions[$1] }
        var next = Array(repeating: 0, count: count)
        for (rank, index) in order.enumerated() {
            let ahead = order[(rank + count - 1) % count]
            let gap = (positions[ahead] - positions[index] - 1 + ring.length) % ring.length
            next[index] = randomSlowdown(min(speeds[index] + 1, ring.vmax, gap), speeds[index], rng.draw(), moving, stopped)
        }
        for index in 0..<count { positions[index] = (positions[index] + next[index]) % ring.length }
        speeds = next
        if step > ring.warmup { total += next.reduce(0, +) }
    }
    return total
}
final class Simulation {
    var segments: [Segment] = []
    var segmentByID: [String: Segment] = [:]
    var junctions: [Junction] = []
    var incidents: [Incident] = []
    var stops: [BusStop] = []
    var classes: [VehicleClass] = []
    var sources: [Source] = []
    var sinks: [String] = []
    var seed = 1, steps = 0, dawdle = 0, dawdleStopped = 0, intervalLength = 1, binWidth = 1
    var detectors: [Detector] = []
    var diagrams: [Diagram] = []
    var trackNumbers: [Int] = []
    var rings: [Ring] = []
    var rng = Minstd(1)
    var vehicles: [Vehicle] = []
    var intervals: [Interval] = []
    var events: [String] = []
    var tracks: [Int: [String]] = [:]
    func load() throws {
        for file in ["network.txt", "demand.txt", "params.txt"] {
            for line in try String(contentsOfFile: "input/\(file)", encoding: .utf8).split(separator: "\n") {
                let fields = line.split(separator: " ").map(String.init)
                func n(_ index: Int) -> Int { Int(fields[index])! }
                switch fields[0] {
                case "SEGMENT":
                    let segment = Segment(fields[1], fields[2], fields[3], n(4), n(5), n(6)); segments.append(segment); segmentByID[segment.id] = segment
                case "JUNCTION":
                    let junction = Junction(fields[1], n(2), Array(fields.dropFirst(3))); junctions.append(junction)
                    for segment in segments where segment.end == junction.node { segment.junction = junction }
                case "INCIDENT": incidents.append(Incident(segmentByID[fields[1]]!, n(2), n(3), n(4), n(5)))
                case "STOP":
                    let segment = segmentByID[fields[1]]!, stop = BusStop(segmentByID[fields[1]]!, n(2), n(3)); segment.stop = stop; stops.append(stop)
                case "CLASS": classes.append(VehicleClass(name: fields[1], vmax: n(2), weight: n(3), overtakes: fields[4] == "Y", stops: fields[5] == "Y"))
                case "SOURCE":
                    let rates = fields.dropFirst(2).map { token -> (Int, Int) in let pair = token.split(separator: ":"); return (Int(pair[0])!, Int(pair[1])!) }
                    sources.append(Source(fields[1], rates, segments.first { $0.start == fields[1] }!))
                case "SINK": sinks.append(fields[1])
                case "TURN": segmentByID[fields[1]]!.turns.append(Turn(segmentByID[fields[2]]!, n(3)))
                case "seed": seed = n(1)
                case "steps": steps = n(1)
                case "dawdle": dawdle = n(1); dawdleStopped = n(2)
                case "interval": intervalLength = n(1)
                case "bin": binWidth = n(1)
                case "detector": detectors.append(Detector(name: fields[1], segment: segmentByID[fields[2]]!, cell: n(3), width: n(4)))
                case "diagram": diagrams.append(Diagram(segmentByID[fields[1]]!, n(2), n(3), n(4)))
                case "track": trackNumbers = fields.dropFirst().map { Int($0)! }; for number in trackNumbers { tracks[number] = [] }
                default: rings.append(Ring(number: rings.count + 1, length: n(1), vmax: n(2), warmup: n(3), measure: n(4), seed: n(5), counts: fields.dropFirst(6).map { Int($0)! }))
                }
            }
        }
    }
    func record(_ step: Int, _ text: String) { events.append(timeText(step) + " " + text) }
    func present(_ segment: Segment) -> [Vehicle] { (1...segment.lanes).flatMap { segment.vehicleNumbers($0).map { vehicles[$0 - 1] } } }
    func enter(_ vehicle: Vehicle, _ segment: Segment) {
        vehicle.route.append(segment.id); segment.entered += 1
        if segment.junction != nil { vehicle.turn = segment.turns[select(segment.turns.map(\.weight), rng.draw())] }
    }
    func arrive(_ step: Int) {
        let interval = intervals.last!
        for source in sources where rng.draw() % 1000 < source.rate(step) {
            let kind = classes[select(classes.map(\.weight), rng.draw())]
            let vehicle = Vehicle(vehicles.count + 1, kind, source.node, step)
            vehicles.append(vehicle); source.queue.append(vehicle); interval.arrivals += 1
        }
    }
    func insert(_ step: Int) {
        for source in sources {
            let segment = source.segment
            while source.count > 0 {
                var lane = 0, best = -1
                for candidate in 1...segment.lanes where segment.cells[candidate - 1][0] == 0 {
                    let first = segment.first(candidate)
                    if first > best { lane = candidate; best = first }
                }
                if lane == 0 { break }
                let vehicle = source.queue[source.head]; source.head += 1
                vehicle.place(segment, lane, 0); vehicle.inserted = step; enter(vehicle, segment); intervals.last!.insertions += 1
            }
            if source.count > 0 && source.queueStart == 0 { source.queueStart = step; source.queueMax = 0 }
            if source.queueStart != 0 {
                source.queueMax = max(source.queueMax, source.count)
                if source.count == 0 { record(step, "QUEUE \(source.node) from \(source.queueStart) max \(source.queueMax)"); source.queueStart = 0 }
            }
        }
    }
    func desiredLane(_ vehicle: Vehicle) -> (Int, Int) {
        let segment = vehicle.segment!, lane = vehicle.lane, cell = vehicle.cell, top = vehicle.maxSpeed()
        let here = segment.free(lane, cell, top + 1), want = min(vehicle.speed + 1, top), ahead = cell + segment.free(lane, cell, top + 1) + 1
        if here < top + 1 && ahead < segment.length && segment.cells[lane - 1][ahead] == -1 {
            for target in [lane + 1, lane - 1] where (1...segment.lanes).contains(target) {
                if segment.free(target, cell, top + 1) > here && segment.safe(target, cell) { return (target, 2) }
            }
        }
        if vehicle.headingForStop() { return lane >= 2 && segment.safe(lane - 1, cell) ? (lane - 1, 1) : (lane, 1) }
        if vehicle.vehicleClass.overtakes && lane < segment.lanes && here < want && segment.free(lane + 1, cell, top + 1) > here && segment.safe(lane + 1, cell) { return (lane + 1, 0) }
        if lane >= 2 && segment.free(lane - 1, cell, top + 1) > want && segment.safe(lane - 1, cell) { return (lane - 1, 1) }
        return (lane, 0)
    }
    func changeLanes() {
        var changes: [(Vehicle, Int, Int)] = []
        for segment in segments where segment.lanes >= 2 {
            var reserved: Set<Int> = []
            for lane in 1...segment.lanes {
                for number in segment.vehicleNumbers(lane) {
                    let vehicle = vehicles[number - 1]
                    if vehicle.dwell > 0 { continue }
                    let (target, kind) = desiredLane(vehicle), key = target * segment.length + vehicle.cell
                    if target != lane && reserved.insert(key).inserted { changes.append((vehicle, target, kind)) }
                }
            }
        }
        for (vehicle, target, kind) in changes { let segment = vehicle.segment!; vehicle.place(segment, target, vehicle.cell); vehicle.laneChanges += 1; segment.changes[kind] += 1 }
    }
    func determineSpeed(_ vehicle: Vehicle, _ step: Int) -> Int {
        let segment = vehicle.segment!, lane = vehicle.lane, cell = vehicle.cell
        let accelerated = min(vehicle.speed + 1, vehicle.maxSpeed())
        var gap = segment.free(lane, cell, accelerated)
        if gap < accelerated && cell + gap == segment.length - 1 {
            if segment.junction == nil { gap = accelerated }
            else if segment.junction!.green(segment.id, step) { let target = vehicle.turn!.target; gap += target.free(min(lane, target.lanes), -1, accelerated - gap) }
        }
        if vehicle.headingForStop() { gap = min(gap, segment.stop!.cell - cell) }
        var speed = randomSlowdown(min(accelerated, gap), vehicle.speed, rng.draw(), dawdle, dawdleStopped)
        if vehicle.dwell > 0 { speed = 0; vehicle.dwell -= 1 }
        return speed
    }
    func move(_ moves: [Move], _ step: Int) {
        var passing: [Move] = []
        for move in moves {
            let vehicle = move.vehicle, segment = move.segment
            if move.cell + move.speed < segment.length { vehicle.place(segment, vehicle.lane, move.cell + move.speed) }
            else if segment.junction == nil { vehicle.leave(); vehicle.exited = step; vehicle.sink = segment.end; intervals.last!.exits += 1 }
            else { passing.append(move) }
        }
        for move in passing {
            let vehicle = move.vehicle, segment = move.segment, turn = move.vehicle.turn!, target = move.vehicle.turn!.target
            let lane = min(vehicle.lane, target.lanes), overshoot = move.cell + move.speed - segment.length
            let cell = min(overshoot, target.first(lane) - 1)
            if cell < overshoot { segment.blocked += 1 }
            if cell >= 0 {
                vehicle.place(target, lane, cell); move.speed = segment.length - move.cell + cell; segment.passed += 1; turn.vehicles += 1; enter(vehicle, target)
            } else { vehicle.place(segment, vehicle.lane, segment.length - 1); move.speed = segment.length - 1 - move.cell }
        }
    }
    func aggregateVehicle(_ move: Move, _ step: Int) {
        let vehicle = move.vehicle, speed = move.speed, interval = intervals.last!
        vehicle.steps += 1; vehicle.distance += speed
        if speed == 0 { vehicle.stoppedSteps += 1; if vehicle.speed > 0 { vehicle.stopCount += 1 } }
        vehicle.speed = speed; interval.vehicleSteps += 1; interval.speedSum += speed
        if vehicle.headingForStop() && vehicle.lane == 1 {
            let segment = vehicle.segment!, stop = vehicle.segment!.stop!
            if vehicle.cell == stop.cell { vehicle.completedStops.insert(segment.id); vehicle.dwell = stop.dwell; stop.buses += 1; record(step, "BUS_STOP \(vehicle.number) \(segment.id) cell \(stop.cell)") }
        }
        if tracks[vehicle.number] != nil { tracks[vehicle.number]!.append(vehicle.segment.map { "\(timeText(step)) \($0.id) \(vehicle.lane) \(vehicle.cell) \(vehicle.speed)" } ?? "\(timeText(step)) EXIT \(vehicle.speed)") }
        for (index, detector) in detectors.enumerated() where move.segment === detector.segment && move.cell < detector.cell {
            if vehicle.segment !== detector.segment || vehicle.cell >= detector.cell { interval.passing[index] += 1 }
        }
    }
    func aggregateState(_ step: Int) {
        let interval = intervals.last!
        for (index, detector) in detectors.enumerated() {
            for vehicle in present(detector.segment) where (detector.cell..<(detector.cell + detector.width)).contains(vehicle.cell) { interval.occupancy[index] += 1; interval.occupancySpeed[index] += vehicle.speed }
        }
        for segment in segments {
            let vehicles = present(segment), count = vehicles.count
            segment.vehicleSum += count; segment.speedSum += vehicles.reduce(0) { $0 + $1.speed }; segment.maxVehicles = max(segment.maxVehicles, count)
            if let junction = segment.junction {
                let green = junction.green(segment.id, step), queued = vehicles.filter { $0.speed == 0 }.count
                if green { segment.greenSteps += 1 }
                segment.queueSum += queued; segment.maxQueue = max(segment.maxQueue, queued)
                if step < steps && queued > 0 && green && !junction.green(segment.id, step + 1) { segment.failures += 1 }
            }
        }
        for diagram in diagrams where (diagram.start...diagram.end).contains(step) {
            let segment = diagram.segment, signal = diagram.segment.junction.map { $0.green(diagram.segment.id, step) ? "G" : "R" } ?? "E"
            diagram.lines.append("\(timeText(step)) \(segment.cellsText(diagram.lane, vehicles)) \(signal)")
        }
    }
    func run() {
        rng = Minstd(seed)
        for step in 1...steps {
            for incident in incidents { if let event = incident.update(step) { record(step, "\(event) \(incident.segment.id) lane \(incident.lane) cell \(incident.cell)") } }
            if (step - 1) % intervalLength == 0 { intervals.append(Interval(detectors.count)) }
            arrive(step); insert(step); changeLanes()
            let moves = segments.flatMap { segment in (1...segment.lanes).flatMap { lane in segment.vehicleNumbers(lane).reversed().map { Move(vehicles[$0 - 1]) } } }
            for move in moves { move.speed = determineSpeed(move.vehicle, step) }
            move(moves, step)
            for move in moves { aggregateVehicle(move, step) }
            aggregateState(step)
        }
        for source in sources where source.queueStart != 0 { record(steps, "QUEUE \(source.node) from \(source.queueStart) max \(source.queueMax) open") }
    }
    func routes(_ segment: Segment) -> [Route] {
        if segment.junction == nil { return [Route(segments: [segment.id], share: Ratio(1))] }
        let total = segment.turns.reduce(0) { $0 + $1.weight }
        return segment.turns.flatMap { turn in routes(turn.target).map { Route(segments: [segment.id] + $0.segments, share: $0.share.times(turn.weight, total)) } }
    }
    func travelBlock(_ heading: String, _ group: [Vehicle]) -> [String] {
        let times = group.map(\.travelTime).sorted()
        if times.isEmpty { return ["\(heading) exited 0"] }
        return ["\(heading) exited \(times.count) min \(times[0]) p50 \(percentile(times, 50)) p90 \(percentile(times, 90)) max \(times.last!) mean \(decimal(times.reduce(0, +), times.count, 2))"] + histogram(times, binWidth)
    }
    func outcome(_ group: [Vehicle], _ total: Int) -> String { "vehicles \(group.count) share \(fraction(group.count, total)) mean \(decimal(group.reduce(0) { $0 + $1.travelTime }, group.count, 2))" }
    func travelLines() -> [String] {
        let exited = vehicles.filter { $0.exited != 0 }
        var lines = classes.flatMap { kind in travelBlock("CLASS " + kind.name, exited.filter { $0.vehicleClass.name == kind.name }) }
        lines += travelBlock("ALL", exited)
        for source in sources {
            let group = exited.filter { $0.source == source.node }, options = routes(source.segment)
            lines.append("SOURCE \(source.node) exited \(group.count)")
            for route in options { lines.append("  ROUTE \(route.segments.joined(separator: ",")) expected \(route.share.text) " + outcome(group.filter { $0.route == route.segments }, group.count)) }
            for sink in sinks {
                let shares = options.filter { segmentByID[$0.segments.last!]!.end == sink }.map(\.share)
                if !shares.isEmpty { let share = shares.reduce(Ratio(0)) { $0.plus($1) }; lines.append("  SINK \(sink) expected \(share.text) " + outcome(group.filter { $0.sink == sink }, group.count)) }
            }
        }
        return lines
    }
    func classBlock(_ heading: String, _ group: [Vehicle]) -> [String] {
        let inserted = group.filter { $0.inserted != 0 }.count, exited = group.filter { $0.exited != 0 }, count = group.filter { $0.exited != 0 }.count
        let steps = group.reduce(0) { $0 + $1.steps }, distance = group.reduce(0) { $0 + $1.distance }
        return [heading,
            "  generated \(group.count) inserted \(inserted) exited \(count) in_network \(inserted - count) queued \(group.count - inserted)",
            "  vehicle_steps \(steps) distance \(distance) mean_speed \(fraction(distance, steps)) = \(decimal(distance, steps, 3))",
            "  travel \(decimal(exited.reduce(0) { $0 + $1.travelTime }, count, 2)) entry_delay \(decimal(exited.reduce(0) { $0 + $1.inserted - $1.arrival }, count, 2)) stopped \(decimal(exited.reduce(0) { $0 + $1.stoppedSteps }, count, 2)) stops \(decimal(exited.reduce(0) { $0 + $1.stopCount }, count, 2)) lane_changes \(decimal(exited.reduce(0) { $0 + $1.laneChanges }, count, 2))"]
    }
    func classLines() -> [String] {
        classes.flatMap { kind in classBlock("CLASS \(kind.name) vmax \(kind.vmax) weight \(kind.weight) overtake \(flag(kind.overtakes)) stops \(flag(kind.stops))", vehicles.filter { $0.vehicleClass.name == kind.name }) } + classBlock("ALL", vehicles)
    }
    func networkLines() -> [String] {
        var lines = segments.map { segment in "SEGMENT \(segment.id) \(segment.start) \(segment.end) length \(segment.length) lanes \(segment.lanes) limit \(segment.limit) entered \(segment.entered) mean_vehicles \(decimal(segment.vehicleSum, steps, 3)) density \(decimal(segment.vehicleSum, steps * segment.length * segment.lanes, 4)) mean_speed \(decimal(segment.speedSum, segment.vehicleSum, 2)) max_vehicles \(segment.maxVehicles) changes \(segment.changes.map(String.init).joined(separator: "/"))" }
        for junction in junctions {
            lines += junction.planLines()
            for segment in segments where segment.end == junction.node {
                lines.append("  IN \(segment.id) green \(segment.greenSteps) passed \(segment.passed) blocked \(segment.blocked) max_queue \(segment.maxQueue) mean_queue \(decimal(segment.queueSum, steps, 3)) failures \(segment.failures)")
                lines += segment.turns.map { "    TURN \($0.target.id) weight \($0.weight) vehicles \($0.vehicles)" }
            }
        }
        lines += stops.map { "STOP \($0.segment.id) cell \($0.cell) dwell \($0.dwell) buses \($0.buses)" }
        lines += incidents.map { "INCIDENT \($0.segment.id) lane \($0.lane) cell \($0.cell) planned \($0.start)-\($0.end) active " + ($0.activeStart == 0 ? "none" : "\($0.activeStart)-\($0.activeEnd)") }
        return lines
    }
    func detectorLines() -> [String] {
        var lines = ["detector,interval,flow,density,speed"]
        for (index, detector) in detectors.enumerated() {
            for (number, interval) in intervals.enumerated() { lines.append("\(detector.name),\(number + 1),\(interval.passing[index]),\(decimal(interval.occupancy[index], intervalLength * detector.width * detector.segment.lanes, 4)),\(decimal(interval.occupancySpeed[index], interval.occupancy[index], 2))") }
        }
        return lines
    }
    func timelineLines() -> [String] {
        var lines = ["interval,arrived,inserted,exited,in_network,queued,mean_speed"], arrived = 0, inserted = 0, exited = 0
        for (index, interval) in intervals.enumerated() { arrived += interval.arrivals; inserted += interval.insertions; exited += interval.exits; lines.append("\(index + 1),\(interval.arrivals),\(interval.insertions),\(interval.exits),\(inserted - exited),\(arrived - inserted),\(decimal(interval.speedSum, interval.vehicleSteps, 2))") }
        return lines
    }
    func trackLines() -> [String] {
        trackNumbers.flatMap { number -> [String] in
            if number > vehicles.count { return ["VEHICLE \(number) none"] }
            let vehicle = vehicles[number - 1]
            return ["VEHICLE \(number) class \(vehicle.vehicleClass.name) source \(vehicle.source) arrival \(vehicle.arrival) inserted \(optional(vehicle.inserted)) exited \(optional(vehicle.exited)) sink \(vehicle.sink)", "ROUTE " + (vehicle.route.isEmpty ? "-" : vehicle.route.joined(separator: " "))] + tracks[number]!
        }
    }
    func fundamentalLines() -> [String] {
        ["ring,vehicles,density,flow,speed"] + rings.flatMap { ring in ring.counts.map { count in let total = runRing(ring, count, dawdle, dawdleStopped); return "\(ring.number),\(count),\(decimal(count, ring.length, 4)),\(decimal(total, ring.length * ring.measure, 4)),\(decimal(total, count * ring.measure, 3))" } }
    }
    func write() throws {
        let space = diagrams.flatMap { ["DIAGRAM \($0.segment.id) lane \($0.lane) steps \($0.start)-\($0.end)"] + $0.lines }
        let outputs = [("spacetime.txt", space), ("detectors.csv", detectorLines()), ("travel_times.txt", travelLines()), ("class_stats.txt", classLines()), ("network_stats.txt", networkLines()), ("timeline.csv", timelineLines()), ("tracks.txt", trackLines()), ("fundamental.csv", fundamentalLines()), ("events.txt", events)]
        try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
        for (name, lines) in outputs { try (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n").write(toFile: "output/\(name)", atomically: true, encoding: .utf8) }
    }
}
let simulation = Simulation()
try simulation.load()
simulation.run()
try simulation.write()
