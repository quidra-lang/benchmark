import Foundation

let pi = 3.141592653589793
func total<S: Sequence>(_ values: S) -> Double where S.Element == Double { var result = 0.0; for value in values { result += value }; return result }
struct Trial { let aircraft: Int; let name: String; let status: String; var blocker: Conflict? = nil }
struct ResolutionRound { let target: Conflict; let trials: [Trial]; let accepted: Trial? }
struct ResolutionResult { let plans: [Plan]; let trajectories: [Trajectory]; let rounds: [ResolutionRound]; let resolved: Set<AircraftPair>; let unresolved: [Conflict] }
func findBlocker(_ aircraft: Int, _ proposed: Trajectory, _ partner: Int, _ trajectories: [Trajectory], _ unresolved: Set<AircraftPair>, _ start: Double, _ settings: Settings) -> Conflict? {
    var blockers: [Conflict] = []
    for other in trajectories.indices where other != aircraft {
        let pair = AircraftPair(aircraft, other)
        if unresolved.contains(pair) { continue }
        let first = pair.first == aircraft ? proposed : trajectories[pair.first], second = pair.second == aircraft ? proposed : trajectories[pair.second]
        blockers += pairConflicts(pair, first, second, settings).filter { other == partner || $0.start < start + Double(settings.lookahead) }
    }
    return blockers.min(by: conflictPrecedes)
}
func resolvePlans(_ input: Inputs) -> ResolutionResult {
    let settings = input.settings, actions = manoeuvres(settings.maximumDelay)
    var plans = input.plans, trajectories = input.plans.map { buildTrajectory($0, input.types) }, unresolvedPairs: Set<AircraftPair> = [], resolvedPairs: Set<AircraftPair> = [], rounds: [ResolutionRound] = [], unresolved: [Conflict] = []
    while true {
        guard let target = allConflicts(trajectories, settings).first(where: { !unresolvedPairs.contains($0.pair) }) else { break }
        let a = target.pair.first, b = target.pair.second, priority = lowerPriority(plans[a], plans[b]) ? [a, b] : [b, a]
        var trials: [Trial] = [], accepted: Trial?
        for aircraft in priority {
            if accepted != nil { break }
            let partner = aircraft == a ? b : a
            for manoeuvre in actions {
                guard var proposal = propose(plans[aircraft], manoeuvre, input.types, settings) else { trials.append(Trial(aircraft: aircraft, name: manoeuvre.name, status: "infeasible")); continue }
                let trajectory = buildTrajectory(proposal, input.types)
                if let blocker = findBlocker(aircraft, trajectory, partner, trajectories, unresolvedPairs, target.start, settings) { trials.append(Trial(aircraft: aircraft, name: manoeuvre.name, status: "blocked", blocker: blocker)) }
                else {
                    let trial = Trial(aircraft: aircraft, name: manoeuvre.name, status: "accepted")
                    proposal.history.append(manoeuvre.name); plans[aircraft] = proposal; trajectories[aircraft] = trajectory
                    trials.append(trial); accepted = trial; break
                }
            }
        }
        if accepted == nil { unresolvedPairs.insert(target.pair); unresolved.append(target) } else { resolvedPairs.insert(target.pair) }
        rounds.append(ResolutionRound(target: target, trials: trials, accepted: accepted))
    }
    return ResolutionResult(plans: plans, trajectories: trajectories, rounds: rounds, resolved: resolvedPairs, unresolved: unresolved)
}
func track(_ segment: Segment) -> Double { let angle = atan2(segment.velocity.x, segment.velocity.y) * 180 / pi; return angle < 0 ? angle + 360 : angle }
func contains(_ sector: Sector, _ point: Vector3) -> Bool { Double(sector.x1) / 10 <= point.x && point.x < Double(sector.x2) / 10 && Double(sector.y1) / 10 <= point.y && point.y < Double(sector.y2) / 10 && Double(sector.lower * 100) <= point.z && point.z < Double(sector.upper * 100) }
struct ClassifiedConflict {
    let value: Conflict
    let levelA: Double; let levelB: Double; let trackA: Double; let trackB: Double; let angle: Double
    let geometry: String; let severity: String; let sector: Int?; let outcome: String
}
func classify(_ conflicts: [Conflict], _ sectors: [Sector], _ finalPairs: Set<AircraftPair>, _ resolved: Set<AircraftPair>, _ horizontal: Int) -> [ClassifiedConflict] {
    conflicts.map { conflict in
        let piece = conflict.closest, a = piece.a, b = piece.b, pa = a.position(piece.loss.tc), pb = b.position(piece.loss.tc), ta = track(a), tb = track(b), difference = abs(ta - tb)
        let product = a.velocity.x * b.velocity.x + a.velocity.y * b.velocity.y, cross = a.velocity.x * b.velocity.y - a.velocity.y * b.velocity.x
        let geometry = product * product > cross * cross ? (product < 0 ? "head_on" : "trailing") : "crossing"
        let severity = 10 * piece.loss.distance < Double(4 * horizontal) ? "HIGH" : 10 * piece.loss.distance < Double(7 * horizontal) ? "MEDIUM" : "LOW"
        let midpoint = Vector3(x: (pa.x + pb.x) / 2, y: (pa.y + pb.y) / 2, z: (pa.z + pb.z) / 2), sector = sectors.firstIndex { contains($0, midpoint) }
        let outcome = finalPairs.contains(conflict.pair) ? "remaining" : resolved.contains(conflict.pair) ? "resolved" : "indirect"
        return ClassifiedConflict(value: conflict, levelA: pa.z / 100, levelB: pb.z / 100, trackA: ta, trackB: tb, angle: difference > 180 ? 360 - difference : difference, geometry: geometry, severity: severity, sector: sector, outcome: outcome)
    }
}
struct Transit { let aircraft: Int; let sector: Int; let entry: Double; let exit: Double; var previous: Int? = nil; var next: Int? = nil }
func insideInterval(_ segment: Segment, _ sector: Sector) -> (Double, Double)? {
    let limits = [(Double(sector.x1) / 10, Double(sector.x2) / 10), (Double(sector.y1) / 10, Double(sector.y2) / 10), (Double(sector.lower * 100), Double(sector.upper * 100))]
    var lo = segment.ts, hi = segment.te
    for axis in 0..<3 {
        let p = segment.start[axis], v = segment.velocity[axis], low = limits[axis].0, high = limits[axis].1
        if v == 0 { if !(low <= p && p < high) { return nil } }
        else { let first = (low - p) / v, second = (high - p) / v; lo = max(lo, segment.ts + min(first, second)); hi = min(hi, segment.ts + max(first, second)) }
    }
    return hi - lo > 1e-6 ? (lo, hi) : nil
}
func sectorTransits(_ trajectories: [Trajectory], _ sectors: [Sector]) -> [Transit] {
    var result: [Transit] = []
    for aircraft in trajectories.indices {
        var transits: [Transit] = []
        for (index, sector) in sectors.enumerated() {
            var combined: [(Double, Double)] = []
            for segment in trajectories[aircraft].segments {
                guard let interval = insideInterval(segment, sector) else { continue }
                if !combined.isEmpty && interval.0 - combined.last!.1 <= 1e-6 { combined[combined.count - 1].1 = interval.1 } else { combined.append(interval) }
            }
            transits += combined.map { Transit(aircraft: aircraft, sector: index, entry: $0.0, exit: $0.1) }
        }
        transits.sort { $0.entry == $1.entry ? $0.sector < $1.sector : $0.entry < $1.entry }
        for index in transits.indices.dropFirst() {
            if abs(transits[index].entry - transits[index - 1].exit) <= 1e-6 { transits[index - 1].next = transits[index].sector; transits[index].previous = transits[index - 1].sector }
        }
        result += transits
    }
    return result
}
func occupancyTable(_ trajectories: [Trajectory], _ sectors: [Sector], _ times: [Int]) -> [[Int]] {
    var values = Array(repeating: Array(repeating: 0, count: times.count), count: sectors.count)
    for (index, time) in times.enumerated() { for trajectory in trajectories { if let observed = trajectory.observation(Double(time)) { for sector in sectors.indices where contains(sectors[sector], observed.position) { values[sector][index] += 1 } } } }
    return values
}
struct Snapshot { let plans: [Plan]; let trajectories: [Trajectory]; let conflicts: [ClassifiedConflict]; let transits: [Transit]; let occupancy: [[Int]] }
func makeSnapshot(_ plans: [Plan], _ trajectories: [Trajectory], _ conflicts: [Conflict], _ finalPairs: Set<AircraftPair>, _ resolved: Set<AircraftPair>, _ input: Inputs) -> Snapshot {
    Snapshot(plans: plans, trajectories: trajectories, conflicts: classify(conflicts, input.sectors, finalPairs, resolved, input.settings.dh), transits: sectorTransits(trajectories, input.sectors), occupancy: occupancyTable(trajectories, input.sectors, input.settings.samples))
}
func trajectoriesCSV(_ snapshot: Snapshot) -> [String] {
    var lines = ["callsign,segment,leg,phase,t_start,t_end,x_start,y_start,fl_start,x_end,y_end,fl_end"]
    for aircraft in snapshot.plans.indices { for segment in snapshot.trajectories[aircraft].segments {
        lines.append([snapshot.plans[aircraft].callsign, String(segment.number), String(segment.leg), segment.phase, decimal(segment.ts), decimal(segment.te), decimal(segment.start.x), decimal(segment.start.y), String(Int(segment.start.z / 100)), decimal(segment.end.x), decimal(segment.end.y), String(Int(segment.end.z / 100))].joined(separator: ","))
    } }
    return lines
}
func conflictLines(_ label: String, _ snapshot: Snapshot, _ input: Inputs) -> [String] {
    let conflicts = snapshot.conflicts, plans = snapshot.plans, settings = input.settings
    var lines = ["CONFLICTS plan=\(label) count=\(conflicts.count)"]
    for (index, classified) in conflicts.enumerated() {
        let conflict = classified.value, piece = conflict.closest, loss = piece.loss, a = piece.a, b = piece.b, sector = classified.sector.map { input.sectors[$0].name } ?? "-"
        lines += ["CONFLICT \(index + 1) \(conflict.pair.name(plans)) start=\(decimal(conflict.start)) end=\(decimal(conflict.end)) duration=\(decimal(conflict.end - conflict.start)) outcome=\(classified.outcome)", "  CPA t=\(decimal(loss.tc)) dist=\(decimal(loss.distance)) vert=\(decimal(loss.vertical, 1)) levels=\(decimal(classified.levelA, 2))/\(decimal(classified.levelB, 2)) tracks=\(decimal(classified.trackA, 1))/\(decimal(classified.trackB, 1)) angle=\(decimal(classified.angle, 1))", "  TYPE geometry=\(classified.geometry) phases=\(a.phase)/\(b.phase) segments=\(a.number)/\(b.number) sector=\(sector) severity=\(classified.severity)"]
        for piece in conflict.pieces { lines.append("  PIECE \(piece.a.number)/\(piece.b.number) \(decimal(piece.loss.lo)) \(decimal(piece.loss.hi))") }
    }
    let closest = conflicts.map { $0.value.closest.loss.distance }.min().map { decimal($0) } ?? "-"
    lines.append("SUMMARY count=\(conflicts.count) total=\(decimal(total(conflicts.map { $0.value.end - $0.value.start }))) min_dist=\(closest) head_on=\(conflicts.filter { $0.geometry == "head_on" }.count) crossing=\(conflicts.filter { $0.geometry == "crossing" }.count) trailing=\(conflicts.filter { $0.geometry == "trailing" }.count) high=\(conflicts.filter { $0.severity == "HIGH" }.count) medium=\(conflicts.filter { $0.severity == "MEDIUM" }.count) low=\(conflicts.filter { $0.severity == "LOW" }.count)")
    let involved = plans.indices.filter { aircraft in conflicts.contains { $0.value.pair.contains(aircraft) } }
    for aircraft in involved {
        let matching = conflicts.filter { $0.value.pair.contains(aircraft) }, partners = Set(matching.map { $0.value.pair.first == aircraft ? $0.value.pair.second : $0.value.pair.first }).sorted().map { plans[$0].callsign }.joined(separator: ",")
        lines.append("FLIGHT \(plans[aircraft].callsign) conflicts=\(matching.count) first=\(decimal(matching.map { $0.value.start }.min()!)) partners=\(partners)")
    }
    lines.append("TIMELINE from=\(settings.sampleStart) to=\(settings.sampleEnd) step=60")
    for aircraft in involved {
        let symbols = settings.samples.map { time -> String in if snapshot.trajectories[aircraft].activeSegment(Double(time)) == nil { return "." }; return conflicts.contains { $0.value.pair.contains(aircraft) && $0.value.active(Double(time)) } ? "X" : "-" }.joined()
        lines.append(plans[aircraft].callsign + " " + symbols)
    }
    return lines
}
func resolutionLines(_ initial: Snapshot, _ revised: Snapshot, _ resolution: ResolutionResult) -> [String] {
    let plans = revised.plans
    var lines: [String] = []
    for (index, round) in resolution.rounds.enumerated() {
        let target = round.target
        lines.append("ROUND \(index + 1) \(target.pair.name(plans)) start=\(decimal(target.start)) end=\(decimal(target.end)) dist=\(decimal(target.closest.loss.distance))")
        for trial in round.trials {
            var line = "  TRY \(plans[trial.aircraft].callsign) \(trial.name) \(trial.status)"
            if let blocker = trial.blocker { line += " \(blocker.pair.name(plans)) start=\(decimal(blocker.start))" }
            lines.append(line)
        }
        if let accepted = round.accepted { lines.append("  RESULT resolved \(plans[accepted.aircraft].callsign) \(accepted.name)") } else { lines.append("  RESULT unresolved") }
    }
    var totalExtra = 0.0
    for aircraft in plans.indices {
        let old = initial.plans[aircraft], new = plans[aircraft], oldArrival = initial.trajectories[aircraft].arrival, newArrival = revised.trajectories[aircraft].arrival, extra = newArrival - oldArrival
        let before = initial.conflicts.filter { $0.value.pair.contains(aircraft) }.count, after = revised.conflicts.filter { $0.value.pair.contains(aircraft) }.count, history = new.history.isEmpty ? "-" : new.history.joined(separator: ",")
        totalExtra += extra
        lines.append("FLIGHT \(new.callsign) departure=\(new.departure + new.delay) delay=\(new.delay) level=\(signed(new.offset)) speed=\(old.speed)->\(new.speed) arrival=\(decimal(oldArrival))->\(decimal(newArrival)) extra=\(decimal(extra)) length=\(decimal(revised.trajectories[aircraft].length)) conflicts=\(before)->\(after) manoeuvres=\(history)")
    }
    for conflict in resolution.unresolved { lines.append("UNRESOLVED \(conflict.pair.name(plans)) start=\(decimal(conflict.start)) dist=\(decimal(conflict.closest.loss.distance))") }
    let attempts = resolution.rounds.flatMap { $0.trials }, accepted = resolution.rounds.compactMap { $0.accepted }
    lines.append("TOTAL rounds=\(resolution.rounds.count) resolved=\(accepted.count) unresolved=\(resolution.unresolved.count) level=\(accepted.filter { $0.name.hasPrefix("level_") }.count) speed=\(accepted.filter { $0.name == "speed_down" }.count) delay=\(accepted.filter { $0.name.hasPrefix("delay_") }.count) total_delay=\(plans.map { $0.delay }.reduce(0, +)) total_extra=\(decimal(totalExtra)) trials=\(attempts.count) infeasible=\(attempts.filter { $0.status == "infeasible" }.count) blocked=\(attempts.filter { $0.status == "blocked" }.count)")
    return lines
}
func transitLines(_ snapshot: Snapshot, _ sectors: [Sector]) -> [String] {
    ["callsign,sector,entry,exit,duration,from,to"] + snapshot.transits.map { transit in
        [snapshot.plans[transit.aircraft].callsign, sectors[transit.sector].name, decimal(transit.entry), decimal(transit.exit), decimal(transit.exit - transit.entry), transit.previous.map { sectors[$0].name } ?? "-", transit.next.map { sectors[$0].name } ?? "-"].joined(separator: ",")
    }
}
struct LevelUsage { var aircraft: Set<Int> = []; var time = 0.0 }
func levelUsage(_ trajectories: [Trajectory]) -> [Int: LevelUsage] {
    var usage: [Int: LevelUsage] = [:]
    for aircraft in trajectories.indices { for segment in trajectories[aircraft].segments where segment.phase == "LVL" {
        let level = Int(segment.start.z / 100)
        usage[level, default: LevelUsage()].aircraft.insert(aircraft); usage[level]!.time += segment.te - segment.ts
    } }
    return usage
}
struct Handoff: Hashable { let source: Int; let destination: Int }
func sectorReports(_ initial: Snapshot, _ revised: Snapshot, _ input: Inputs) -> (load: [String], report: [String]) {
    let sectors = input.sectors, samples = input.settings.samples
    var load = ["sector,period,start,end,entries_initial,entries_final,peak_initial,peak_final,mean_final,capacity,status"], report: [String] = []
    for (index, sector) in sectors.enumerated() {
        let before = initial.occupancy[index], after = revised.occupancy[index], capacity = sector.capacity
        for first in stride(from: 0, to: samples.count, by: 5) {
            let start = samples[first], end = start + 300, pi = before[first..<(first + 5)].max()!, pf = after[first..<(first + 5)].max()!
            let ei = initial.transits.filter { $0.sector == index && Double(start) <= $0.entry && $0.entry < Double(end) }.count
            let ef = revised.transits.filter { $0.sector == index && Double(start) <= $0.entry && $0.entry < Double(end) }.count
            let mean = Double(after[first..<(first + 5)].reduce(0, +)) / 5, status = pf > capacity ? "OVER" : pi > capacity ? "RELIEVED" : "OK"
            load.append([sector.name, String(first / 5 + 1), String(start), String(end), String(ei), String(ef), String(pi), String(pf), decimal(mean, 1), String(capacity), status].joined(separator: ","))
        }
        report.append("SECTOR \(sector.name) x=\(sector.x1)..\(sector.x2) y=\(sector.y1)..\(sector.y2) fl=\(sector.lower)..\(sector.upper) capacity=\(capacity)")
        for (label, snapshot) in [("INITIAL", initial), ("FINAL", revised)] {
            let matching = snapshot.transits.filter { $0.sector == index }, dwell = total(matching.map { $0.exit - $0.entry }), occupancy = snapshot.occupancy[index]
            let over = stride(from: 0, to: samples.count, by: 5).filter { occupancy[$0..<($0 + 5)].max()! > capacity }.count, count = snapshot.conflicts.filter { $0.sector == index }.count
            let mean = matching.isEmpty ? "-" : decimal(dwell / Double(matching.count))
            report.append("\(label) entries=\(matching.count) time=\(decimal(dwell)) mean=\(mean) peak=\(occupancy.max()!) over=\(over) conflicts=\(count)")
        }
        let height = max(capacity + 1, after.max()!)
        report += chart(stride(from: height, through: 1, by: -1).map { level in after.map { $0 >= level ? "#" : level == capacity ? "-" : "." }.joined() })
    }
    let before = levelUsage(initial.trajectories), after = levelUsage(revised.trajectories)
    report.append("LEVELS")
    for level in Set(before.keys).union(after.keys).sorted(by: >) {
        let old = before[level] ?? LevelUsage(), new = after[level] ?? LevelUsage()
        report.append("LEVEL \(level) flights=\(old.aircraft.count)->\(new.aircraft.count) time=\(decimal(old.time))->\(decimal(new.time))")
    }
    var handoffs: [Handoff: Int] = [:]
    for transit in revised.transits { if let next = transit.next { handoffs[Handoff(source: transit.sector, destination: next), default: 0] += 1 } }
    report.append("HANDOFFS plan=final count=\(handoffs.values.reduce(0, +))")
    for pair in handoffs.keys.sorted(by: { $0.source == $1.source ? $0.destination < $1.destination : $0.source < $1.source }) { report.append("HANDOFF \(sectors[pair.source].name) \(sectors[pair.destination].name) \(handoffs[pair]!)") }
    return (load, report)
}
struct AlertObservation { let time: Int; let loss: Double; let distance: Double }
struct Alert { let pair: AircraftPair; let first: Int; var last: Int; var samples: Int; let predicted: Double; var minimum: Double }
func alertLines(_ label: String, _ snapshot: Snapshot, _ settings: Settings) -> [String] {
    var observations: [AircraftPair: [AlertObservation]] = [:]
    for time in settings.samples {
        let positions = snapshot.trajectories.map { $0.observation(Double(time)) }, aircraft = positions.indices.filter { positions[$0] != nil }
        for (index, first) in aircraft.enumerated() { for second in aircraft.dropFirst(index + 1) {
            let a = positions[first]!, b = positions[second]!
            if let loss = lossInterval(a.position - b.position, a.segment.velocity - b.segment.velocity, 0, Double(settings.alert), Double(settings.dh), Double(settings.dv)) { observations[AircraftPair(first, second), default: []].append(AlertObservation(time: time, loss: Double(time) + loss.lo, distance: loss.distance)) }
        } }
    }
    var alerts: [Alert] = []
    for pair in observations.keys.sorted() {
        var groups: [Alert] = []
        for observation in observations[pair]! {
            if !groups.isEmpty && observation.time - groups.last!.last == 60 {
                let index = groups.count - 1
                groups[index].last = observation.time; groups[index].samples += 1; groups[index].minimum = min(groups[index].minimum, observation.distance)
            } else { groups.append(Alert(pair: pair, first: observation.time, last: observation.time, samples: 1, predicted: observation.loss, minimum: observation.distance)) }
        }
        alerts += groups
    }
    alerts.sort { $0.first == $1.first ? $0.pair < $1.pair : $0.first < $1.first }
    var lines = ["ALERTS plan=\(label) horizon=\(settings.alert) count=\(alerts.count)"], detected: Set<Int> = [], leads: [Double] = []
    for (index, alert) in alerts.enumerated() {
        let matches = snapshot.conflicts.indices.filter { let conflict = snapshot.conflicts[$0].value; return conflict.pair == alert.pair && conflict.start < Double(alert.last + settings.alert) && conflict.end > Double(alert.first) }
        var status = "status=false lead=-"
        if let first = matches.first { let lead = snapshot.conflicts[first].value.start - Double(alert.first); leads.append(lead); status = "status=true lead=" + decimal(lead) }
        detected.formUnion(matches)
        lines.append("ALERT \(index + 1) \(alert.pair.name(snapshot.plans)) first=\(alert.first) last=\(alert.last) samples=\(alert.samples) predicted=\(decimal(alert.predicted)) min_dist=\(decimal(alert.minimum)) \(status)")
    }
    let missed = snapshot.conflicts.indices.filter { !detected.contains($0) }
    for index in missed { let conflict = snapshot.conflicts[index].value; lines.append("MISSED \(conflict.pair.name(snapshot.plans)) start=\(decimal(conflict.start)) end=\(decimal(conflict.end))") }
    let mean = leads.isEmpty ? "-" : decimal(total(leads) / Double(leads.count))
    lines.append("SUMMARY alerts=\(alerts.count) true=\(leads.count) false=\(alerts.count - leads.count) missed=\(missed.count) mean_lead=\(mean)")
    return lines
}
struct Cell: Hashable { let column: Int; let row: Int }
func radarCell(_ point: Vector3, _ radar: Radar) -> Cell? {
    let column = Int(floor((10 * point.x - Double(radar.x0)) * Double(radar.width) / Double(radar.x1 - radar.x0)))
    let bottom = Int(floor((10 * point.y - Double(radar.y0)) * Double(radar.height) / Double(radar.y1 - radar.y0)))
    return column >= 0 && column < radar.width && bottom >= 0 && bottom < radar.height ? Cell(column: column, row: radar.height - 1 - bottom) : nil
}
struct RadarObservation { let aircraft: Int; let point: Vector3; let segment: Segment; let cell: Cell? }
func radarSnapshot(_ label: String, _ snapshot: Snapshot, _ time: Int, _ settings: Settings) -> [String] {
    let radar = settings.radar
    let observations: [RadarObservation] = snapshot.trajectories.indices.compactMap { aircraft in
        guard let observed = snapshot.trajectories[aircraft].observation(Double(time)) else { return nil }
        return RadarObservation(aircraft: aircraft, point: observed.position, segment: observed.segment, cell: radarCell(observed.position, radar))
    }
    let active = snapshot.conflicts.map { $0.value }.filter { $0.active(Double(time)) }, conflicted = Set(active.flatMap { [$0.pair.first, $0.pair.second] })
    var grid = Array(repeating: Array(repeating: UInt8(46), count: radar.width), count: radar.height)
    var cells = Array(repeating: Array(repeating: [Int](), count: radar.width), count: radar.height)
    for observation in observations { if let cell = observation.cell { cells[cell.row][cell.column].append(observation.aircraft) } }
    for row in 0..<radar.height { for column in 0..<radar.width {
        let aircraft = cells[row][column]
        if aircraft.count > 1 { grid[row][column] = UInt8(48 + aircraft.count) }
        else if let aircraft = aircraft.first { let character = snapshot.plans[aircraft].callsign.utf8.first!; grid[row][column] = conflicted.contains(aircraft) ? character + 32 : character }
    } }
    for observation in observations {
        if let predicted = snapshot.trajectories[observation.aircraft].observation(Double(time + settings.leader)), let cell = radarCell(predicted.position, radar), grid[cell.row][cell.column] == 46 { grid[cell.row][cell.column] = 42 }
    }
    var lines = ["RADAR plan=\(label) t=\(time) aircraft=\(observations.count) conflicts=\(active.count)"] + chart(grid.map { String(decoding: $0, as: UTF8.self) })
    for observation in observations {
        let point = observation.point, segment = observation.segment, cell = observation.cell.map { "\($0.column),\($0.row)" } ?? "outside"
        lines.append("\(snapshot.plans[observation.aircraft].callsign) x=\(decimal(point.x)) y=\(decimal(point.y)) fl=\(decimal(point.z / 100, 2)) track=\(decimal(track(segment), 1)) phase=\(segment.phase) cell=\(cell)")
    }
    let positions = Dictionary(uniqueKeysWithValues: observations.map { ($0.aircraft, $0.point) })
    for conflict in active {
        let difference = positions[conflict.pair.first]! - positions[conflict.pair.second]!
        lines.append("CONFLICT \(conflict.pair.name(snapshot.plans)) dist=\(decimal(sqrt(difference.x * difference.x + difference.y * difference.y))) vert=\(decimal(abs(difference.z), 1))")
    }
    return lines
}
func radarDensity(_ label: String, _ snapshot: Snapshot, _ settings: Settings) -> [String] {
    let radar = settings.radar
    var density = Array(repeating: Array(repeating: 0, count: radar.width), count: radar.height)
    for time in settings.samples { for trajectory in snapshot.trajectories {
        if let observed = trajectory.observation(Double(time)), let cell = radarCell(observed.position, radar) { density[cell.row][cell.column] += 1 }
    } }
    let maximum = density.flatMap { $0 }.max()!, rows = density.map { row in row.map { $0 == 0 ? "." : $0 < 10 ? String($0) : "#" }.joined() }
    return ["DENSITY plan=\(label) from=\(settings.sampleStart) to=\(settings.sampleEnd) step=60 max=\(maximum)"] + chart(rows)
}
func flightStrips(_ initial: Snapshot, _ revised: Snapshot, _ sectors: [Sector]) -> [String] {
    var lines: [String] = []
    for aircraft in revised.plans.indices {
        let plan = revised.plans[aircraft], original = initial.trajectories[aircraft], newTrajectory = revised.trajectories[aircraft], history = plan.history.isEmpty ? "-" : plan.history.joined(separator: ",")
        lines.append("STRIP \(plan.callsign) type=\(plan.type) waypoints=\(plan.waypoints.count) length=\(decimal(newTrajectory.length)) manoeuvres=\(history)")
        for (index, waypoint) in plan.waypoints.enumerated() {
            let old = original.waypointTimes[index], new = newTrajectory.waypointTimes[index]
            lines.append("WPT \(index) at=\(waypoint.x):\(waypoint.y) eta=\(decimal(old.time))->\(decimal(new.time)) fl=\(old.level)->\(new.level)")
        }
        let transits = revised.transits.filter { $0.aircraft == aircraft }, sequence = transits.isEmpty ? "-" : transits.map { "\(sectors[$0.sector].name)@\(decimal($0.entry))" }.joined(separator: ",")
        lines.append("SECTORS " + sequence)
    }
    return lines
}
let input = try readInputs(), initialTrajectories = input.plans.map { buildTrajectory($0, input.types) }, initialConflicts = allConflicts(initialTrajectories, input.settings), resolution = resolvePlans(input), finalConflicts = allConflicts(resolution.trajectories, input.settings), finalPairs = Set(finalConflicts.map { $0.pair })
let initial = makeSnapshot(input.plans, initialTrajectories, initialConflicts, finalPairs, resolution.resolved, input), revised = makeSnapshot(resolution.plans, resolution.trajectories, finalConflicts, finalPairs, resolution.resolved, input), sectors = sectorReports(initial, revised, input)
var radarLines: [String] = []
for time in input.settings.snapshots { radarLines += radarSnapshot("initial", initial, time, input.settings); radarLines += radarSnapshot("final", revised, time, input.settings) }
radarLines += radarDensity("initial", initial, input.settings); radarLines += radarDensity("final", revised, input.settings)
let outputs = [("trajectories.csv", trajectoriesCSV(revised)), ("conflicts.txt", conflictLines("initial", initial, input) + conflictLines("final", revised, input)), ("resolutions.txt", resolutionLines(initial, revised, resolution)), ("sector_transits.csv", transitLines(revised, input.sectors)), ("sector_load.csv", sectors.load), ("sector_report.txt", sectors.report), ("alerts.txt", alertLines("initial", initial, input.settings) + alertLines("final", revised, input.settings)), ("radar.txt", radarLines), ("strips.txt", flightStrips(initial, revised, input.sectors))]
for (name, lines) in outputs { try writeLines(name, lines) }
