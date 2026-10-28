import Foundation

func decimalScale(_ places: Int) -> Int { (0..<places).reduce(1) { scale, _ in scale * 10 } }
func scaledDecimal(_ value: Double, _ places: Int) -> Int {
    let integer = Int(floor(abs(value) * Double(decimalScale(places)) + 0.5))
    return value < 0 ? -integer : integer
}
func decimal(_ value: Double?, _ places: Int) -> String {
    guard let value else { return "-" }
    let integer = scaledDecimal(value, places), scale = decimalScale(places), absolute = abs(integer)
    let remainder = String(absolute % scale)
    return (integer < 0 ? "-" : "") + String(absolute / scale) + "." + String(repeating: "0", count: places - remainder.count) + remainder
}
func timeNotation(_ sample: Int) -> String { "\(sample / 100)." + (sample % 100 < 10 ? "0" : "") + String(sample % 100) }
func writeLines(_ filename: String, _ lines: [String]) throws { try (lines.joined(separator: "\n") + "\n").write(toFile: "output/" + filename, atomically: false, encoding: .ascii) }
func stationOrdered(_ picks: [Pick]) -> [Pick] { picks.sorted { $0.station.order < $1.station.order } }
func observations(_ picks: [Pick], corrections: [Double]? = nil) -> [Observation] {
    stationOrdered(picks).map { Observation(station: $0.station, time: $0.time - (corrections?[$0.station.order] ?? 0)) }
}

struct Jackknife {
    let station: Station
    let dx: Double
    let dy: Double
    let dz: Double
    let shift: Double
}
struct Quality {
    let ellipse: Ellipse
    let gap: Double
    let dmin: Double
    let grade: String
    let horizontalShift: Double
    let depthShift: Double
    let jackknife: [Jackknife]
    let maximum: Jackknife
}

final class Event {
    let number: Int
    let candidate: Candidate
    let used: [Pick]
    let first: LocationRun
    var observations: [Observation] = []
    var startRMS = 0.0
    var refined: Refinement?
    var quality: Quality?
    var magnitudes: [PickMagnitude] = []
    var ml: Double?
    var md = 0.0
    var correctedML: Double?
    var cluster = 0
    var solution: Solution { refined?.solution ?? first.refined.solution }
    init(_ number: Int, _ candidate: Candidate, _ used: [Pick], _ first: LocationRun) { self.number = number; self.candidate = candidate; self.used = used; self.first = first }
}

func locateCandidates(_ candidates: [Candidate], _ params: Parameters) -> [Event] {
    var events: [Event] = []
    for candidate in candidates {
        let initial = stationOrdered(candidate.picks), first = runLocation(observations(stationOrdered(candidate.picks)), params)
        candidate.passes.append((initial, first))
        var dropped: [(Pick, Double)] = [], retained: [Pick] = []
        for (pick, error) in zip(initial, first.refined.residuals) {
            if abs(error) > params.residualLimit { dropped.append((pick, error)) } else { retained.append(pick) }
        }
        candidate.dropped = dropped
        if !dropped.isEmpty && retained.count < params.minStations {
            candidate.rejected = true
            for pick in initial { pick.state = .rejected }
            continue
        }
        let adopted: LocationRun
        if dropped.isEmpty { adopted = first } else { adopted = runLocation(observations(retained), params); candidate.passes.append((retained, adopted)) }
        let number = events.count + 1
        candidate.event = number
        for (pick, error) in zip(retained, adopted.refined.residuals) { pick.state = .used; pick.event = number; pick.firstResidual = error }
        for (pick, _) in dropped { pick.state = .dropped; pick.event = number }
        events.append(Event(number, candidate, retained, adopted))
    }
    return events
}

func stationTimeCorrections(_ events: [Event], _ stations: [Station]) -> [Double] {
    var values = Array(repeating: [Double](), count: stations.count)
    for event in events { for pick in event.used { values[pick.station.order].append(pick.firstResidual!) } }
    return values.map { $0.isEmpty ? 0 : orderedSum($0) / Double($0.count) }
}

func azimuthGap(_ solution: Solution, _ picks: [Pick]) -> Double {
    let angles = picks.map { pick -> Double in
        var angle = atan2(Double(pick.station.x) - solution.x, Double(pick.station.y) - solution.y) * 180 / pi
        if angle < 0 { angle += 360 }
        return angle
    }.sorted()
    let gaps = (1..<angles.count).map { angles[$0] - angles[$0 - 1] } + [angles[0] + 360 - angles.last!]
    return gaps.max()!
}

func qualityForEvent(_ event: Event, _ params: Parameters) -> Quality {
    let refined = event.refined!, solution = event.solution, used = event.used
    let ellipse = errorEllipse(solution, event.observations, params.velocity), gap = azimuthGap(solution, used)
    let dmin = used.map { pick -> Double in
        let dx = Double(pick.station.x) - solution.x, dy = Double(pick.station.y) - solution.y
        return sqrt(dx * dx + dy * dy)
    }.min()!
    func fits(_ bounds: [Double]) -> Bool { gap <= bounds[0] && refined.rms <= bounds[1] && ellipse.semiMajor <= bounds[2] }
    let grade = fits(params.qualityA) ? "A" : fits(params.qualityB) ? "B" : "C"
    let first = event.first.refined.solution, dx = solution.x - event.first.refined.solution.x, dy = solution.y - event.first.refined.solution.y
    var jackknife: [Jackknife] = []
    for (index, pick) in used.enumerated() {
        let remaining = event.observations.enumerated().filter { $0.offset != index }.map { $0.element }
        let alternative = geiger(solution, remaining, params.velocity).solution
        let dx = alternative.x - solution.x, dy = alternative.y - solution.y, dz = alternative.z - solution.z
        jackknife.append(Jackknife(station: pick.station, dx: dx, dy: dy, dz: dz, shift: sqrt(dx * dx + dy * dy)))
    }
    var maximum = jackknife[0]
    for jack in jackknife.dropFirst() where jack.shift > maximum.shift { maximum = jack }
    return Quality(ellipse: ellipse, gap: gap, dmin: dmin, grade: grade, horizontalShift: sqrt(dx * dx + dy * dy), depthShift: solution.z - first.z, jackknife: jackknife, maximum: maximum)
}

func relocateEvents(_ events: [Event], _ params: Parameters, _ corrections: [Double]) {
    for event in events {
        let corrected = observations(event.used, corrections: corrections)
        event.observations = corrected
        event.startRMS = rms(event.first.refined.solution, corrected, params.velocity)
        event.refined = geiger(event.first.refined.solution, corrected, params.velocity)
        for (pick, error) in zip(event.used, event.refined!.residuals) { pick.residual = error }
        event.quality = qualityForEvent(event, params)
    }
}

func computeMagnitudes(_ events: [Event], _ stations: [Station], _ params: Parameters) -> (corrections: [Double], residuals: [[Double]]) {
    var residuals = Array(repeating: [Double](), count: stations.count)
    for event in events {
        event.magnitudes = event.used.map { perPickMagnitude($0, distance(event.solution, $0.station) / 1000, params) }
        let local = event.magnitudes.compactMap { $0.local }
        event.ml = local.isEmpty ? nil : median(local)
        event.md = median(event.magnitudes.map { $0.durationMagnitude })
        for item in event.magnitudes { if let local = item.local { residuals[item.pick.station.order].append(local - event.ml!) } }
    }
    let corrections = residuals.map { $0.isEmpty ? 0 : orderedSum($0) / Double($0.count) }
    for event in events {
        let corrected = event.magnitudes.compactMap { item in item.local.map { $0 - corrections[item.pick.station.order] } }
        event.correctedML = corrected.isEmpty ? nil : median(corrected)
    }
    return (corrections, residuals)
}

struct TravelRegression { let count: Int; let velocity: Double; let intercept: Double; let rms: Double }

func travelTimeRegression(_ events: [Event]) -> TravelRegression {
    let points = events.flatMap { event in event.used.map { (distance(event.solution, $0.station) / 1000, $0.time - event.solution.origin) } }
    let n = Double(points.count), sd = orderedSum(points.map { $0.0 }), st = orderedSum(points.map { $0.1 })
    let sdd = orderedSum(points.map { $0.0 * $0.0 }), sdt = orderedSum(points.map { $0.0 * $0.1 })
    let slope = (n * sdt - sd * st) / (n * sdd - sd * sd), intercept = (st - slope * sd) / n
    let squared = orderedSum(points.map { point -> Double in let error = point.1 - intercept - slope * point.0; return error * error })
    return TravelRegression(count: points.count, velocity: 1000 / slope, intercept: intercept, rms: sqrt(squared / n))
}

struct Cluster {
    let number: Int
    let members: [Int]
    let x: Double
    let y: Double
    let z: Double
    let span: Double
}

func clusterEvents(_ events: [Event], _ params: Parameters) -> [Cluster] {
    var neighbors = Array(repeating: [Int](), count: events.count)
    if events.count >= 2 {
        for i in 0..<(events.count - 1) {
            for j in (i + 1)..<events.count {
                let a = events[i].solution, b = events[j].solution
                if abs(a.origin - b.origin) > params.cluster[1] { continue }
                let dx = a.x - b.x, dy = a.y - b.y, dz = a.z - b.z
                if sqrt(dx * dx + dy * dy + dz * dz) <= params.cluster[0] { neighbors[i].append(j); neighbors[j].append(i) }
            }
        }
    }
    var visited = Array(repeating: false, count: events.count), clusters: [Cluster] = []
    for first in events.indices where !visited[first] {
        visited[first] = true
        var queue = [first], cursor = 0
        while cursor < queue.count {
            let current = queue[cursor]
            cursor += 1
            for other in neighbors[current].sorted() where !visited[other] { visited[other] = true; queue.append(other) }
        }
        let members = queue.sorted(), count = Double(members.count), number = clusters.count + 1
        for member in members { events[member].cluster = number }
        let origins = members.map { events[$0].solution.origin }
        clusters.append(Cluster(number: number, members: members.map { events[$0].number }, x: orderedSum(members.map { events[$0].solution.x }) / count,
                                y: orderedSum(members.map { events[$0].solution.y }) / count, z: orderedSum(members.map { events[$0].solution.z }) / count, span: origins.max()! - origins.min()!))
    }
    return clusters
}

func reassociateUnassigned(_ picks: [Pick], _ events: [Event], _ corrections: [Double], _ params: Parameters) -> [Pick] {
    var stationSets = events.map { Set($0.used.map { $0.station.order }) }, added: [Pick] = []
    for pick in picks where pick.state == .unassociated {
        var best: (index: Int, residual: Double)?
        for (index, event) in events.enumerated() where !stationSets[index].contains(pick.station.order) {
            let residual = pick.time - event.solution.origin - distance(event.solution, pick.station) / params.velocity - corrections[pick.station.order]
            if abs(residual) <= params.residualLimit && (best == nil || abs(residual) < abs(best!.residual)) { best = (index, residual) }
        }
        if let best { pick.state = .added; pick.event = events[best.index].number; pick.residual = best.residual; stationSets[best.index].insert(pick.station.order); added.append(pick) }
    }
    return added
}

func picksFile(_ picks: [Pick]) -> [String] {
    ["station,sample,time_s,duration,snr,amplitude,clipped,event,status,residual"] + picks.map { pick in
        let number = pick.state == .used || pick.state == .dropped || pick.state == .added ? pick.event! : 0
        let residual = pick.state == .used || pick.state == .added ? decimal(pick.residual!, 4) : "-"
        return [pick.station.code, String(pick.sample), timeNotation(pick.sample), String(pick.duration), decimal(pick.ratio, 2),
                String(pick.amplitude), pick.clipped ? "yes" : "no", String(number), pick.state.rawValue, residual].joined(separator: ",")
    }
}

func formatSolution(_ label: String, _ solution: Solution, _ rms: Double, index: Int? = nil) -> String {
    label + (index.map { " " + String($0) } ?? "") + " x=\(decimal(solution.x, 1)) y=\(decimal(solution.y, 1)) z=\(decimal(solution.z, 1)) t0=\(decimal(solution.origin, 3)) rms=\(decimal(rms, 4))"
}

func locationPassLines(_ number: Int, _ picks: [Pick], _ run: LocationRun, _ velocity: Double) -> [String] {
    var lines = ["PASS \(number) stations=" + picks.map { $0.station.code }.joined(separator: ","), formatSolution("GRID", run.grid.solution, run.grid.rms),
                 "PROFILE " + run.grid.profile.map { decimal($0, 4) }.joined(separator: " ")]
    lines += run.refined.trace.map { formatSolution("ITER", $0.solution, $0.rms, index: $0.number) }
    for (pick, residual) in zip(picks, run.refined.residuals) {
        let d = distance(run.refined.solution, pick.station)
        lines.append("RES \(pick.station.code) dist=\(decimal(d, 1)) tt=\(decimal(d / velocity, 4)) obs=\(timeNotation(pick.sample)) res=\(decimal(residual, 4))")
    }
    return lines
}

func candidateLines(_ candidates: [Candidate], _ velocity: Double) -> [String] {
    var lines: [String] = []
    for candidate in candidates {
        lines.append("CANDIDATE \(candidate.number) picks=\(candidate.picks.count) first=\(timeNotation(candidate.first.sample))")
        let first = candidate.passes[0]
        lines += locationPassLines(1, first.picks, first.run, velocity)
        for dropped in candidate.dropped { lines.append("DROP \(dropped.pick.station.code) res=\(decimal(dropped.error, 4))") }
        if candidate.rejected { lines.append("RESULT REJECTED stations=\(candidate.picks.count - candidate.dropped.count)") }
        else {
            if candidate.passes.count == 2 { let second = candidate.passes[1]; lines += locationPassLines(2, second.picks, second.run, velocity) }
            lines.append("RESULT EVENT \(candidate.event!)")
        }
    }
    return lines
}

func eventLocationLines(_ event: Event, _ velocity: Double, _ corrections: [Double]) -> [String] {
    let refined = event.refined!, quality = event.quality!, ellipse = event.quality!.ellipse
    var lines = ["EVENT \(event.number)", formatSolution("START", event.first.refined.solution, event.startRMS)]
    lines += refined.trace.map { formatSolution("ITER", $0.solution, $0.rms, index: $0.number) }
    for pick in event.used {
        let d = distance(event.solution, pick.station)
        lines.append("RES \(pick.station.code) dist=\(decimal(d, 1)) tt=\(decimal(d / velocity, 4)) obs=\(timeNotation(pick.sample)) corr=\(decimal(corrections[pick.station.order], 4)) res=\(decimal(pick.residual!, 4))")
    }
    lines += ["ELLIPSE smaj=\(decimal(ellipse.semiMajor, 1)) smin=\(decimal(ellipse.semiMinor, 1)) az=\(decimal(ellipse.azimuth, 1)) erz=\(decimal(ellipse.depthError, 1)) ert=\(decimal(ellipse.timeError, 4))",
              "SHIFT dh=\(decimal(quality.horizontalShift, 1)) dz=\(decimal(quality.depthShift, 1))",
              "GAP \(decimal(quality.gap, 1)) DMIN \(decimal(quality.dmin, 1)) QUALITY \(quality.grade)"]
    for jack in quality.jackknife { lines.append("JACK \(jack.station.code) dx=\(decimal(jack.dx, 1)) dy=\(decimal(jack.dy, 1)) dz=\(decimal(jack.dz, 1)) shift=\(decimal(jack.shift, 1))") }
    lines.append("JACKKNIFE max=\(decimal(quality.maximum.shift, 1)) station=\(quality.maximum.station.code)")
    return lines
}

func locationFile(_ picks: [Pick], _ candidates: [Candidate], _ events: [Event], _ stations: [Station], _ corrections: [Double], _ regression: TravelRegression, _ clusters: [Cluster], _ added: [Pick], _ params: Parameters) -> [String] {
    var lines = candidateLines(candidates, params.velocity) + ["CORRECTIONS"]
    for station in stations {
        let count = picks.filter { $0.state == .used && $0.station.order == station.order }.count
        lines.append("\(station.code) n=\(count) correction=\(decimal(corrections[station.order], 4))")
    }
    for event in events { lines += eventLocationLines(event, params.velocity, corrections) }
    lines.append("FIT n=\(regression.count) velocity=\(decimal(regression.velocity, 1)) intercept=\(decimal(regression.intercept, 4)) rms=\(decimal(regression.rms, 4))")
    for cluster in clusters where cluster.members.count >= 2 {
        lines.append("CLUSTER \(cluster.number) events=" + cluster.members.map(String.init).joined(separator: ",") + " x=\(decimal(cluster.x, 1)) y=\(decimal(cluster.y, 1)) z=\(decimal(cluster.z, 1)) span=\(decimal(cluster.span, 3))")
    }
    lines.append("ADDED")
    for pick in added { lines.append("\(pick.station.code) sample=\(pick.sample) event=\(pick.event!) res=\(decimal(pick.residual!, 4))") }
    lines.append("SUMMARY picks=\(picks.count) candidates=\(candidates.count) events=\(events.count) rejected=\(candidates.filter { $0.rejected }.count) unassociated=\(picks.filter { $0.state == .unassociated }.count)")
    let depths = events.map { $0.solution.z }, grades = events.map { $0.quality!.grade }
    lines += ["DEPTH min=\(decimal(depths.min()!, 1)) median=\(decimal(median(depths), 1)) max=\(decimal(depths.max()!, 1))",
              "QUALITY A=\(grades.filter { $0 == "A" }.count) B=\(grades.filter { $0 == "B" }.count) C=\(grades.filter { $0 == "C" }.count) mean_rms=\(decimal(orderedSum(events.map { $0.refined!.rms }) / Double(events.count), 4))"]
    return lines
}

func catalogRows(_ events: [Event]) -> [String] {
    ["event,origin_time,x,y,depth,rms,stations,gap,dmin,smaj,smin,azimuth,erz,ml,md,quality,cluster"] + events.map { event in
        let solution = event.solution, quality = event.quality!, ellipse = event.quality!.ellipse
        return [String(event.number), decimal(solution.origin, 3), decimal(solution.x, 1), decimal(solution.y, 1), decimal(solution.z, 1), decimal(event.refined!.rms, 4),
                String(event.used.count), decimal(quality.gap, 1), decimal(quality.dmin, 1), decimal(ellipse.semiMajor, 1), decimal(ellipse.semiMinor, 1),
                decimal(ellipse.azimuth, 1), decimal(ellipse.depthError, 1), decimal(event.ml, 2), decimal(event.md, 2), quality.grade, String(event.cluster)].joined(separator: ",")
    }
}

func plotFrame(_ grid: [[Character]]) -> [String] {
    let border = "+" + String(repeating: "-", count: grid[0].count) + "+"
    return [border] + grid.map { "|" + String($0) + "|" } + [border]
}

func drawTimeline(_ events: [Event], _ params: Parameters) -> [String] {
    let duration = params.timeline[0], width = params.timeline[1], low = params.timeline[2], high = params.timeline[3], height = params.timeline[4]
    var rows = Array(repeating: Array<Character>(repeating: " ", count: width), count: height)
    for event in events {
        guard let ml = event.ml else { continue }
        let t = scaledDecimal(event.solution.origin, 3), magnitude = scaledDecimal(ml, 2)
        if t < 0 || t >= 1000 * duration || magnitude < 100 * low { continue }
        let column = t * width / (1000 * duration), level = min((magnitude - 100 * low) * height / (100 * (high - low)), height - 1)
        for index in 0...level {
            let row = height - 1 - index
            if index == level { rows[row][column] = "o" } else if rows[row][column] == " " { rows[row][column] = "|" }
        }
    }
    return ["TIMELINE t=0..\(duration) ML=\(low)..\(high)"] + plotFrame(rows)
}

func magnitudeRelation(_ events: [Event]) -> String {
    let selected = events.filter { $0.ml != nil }
    let x = selected.map { $0.md }, y = selected.map { $0.ml! }
    let xm = orderedSum(x) / Double(selected.count), ym = orderedSum(y) / Double(selected.count)
    let xx = orderedSum(x.map { ($0 - xm) * ($0 - xm) }), xy = orderedSum(x.indices.map { (x[$0] - xm) * (y[$0] - ym) }), yy = orderedSum(y.map { ($0 - ym) * ($0 - ym) })
    let slope = xy / xx
    return "MLMD n=\(selected.count) slope=\(decimal(slope, 3)) intercept=\(decimal(ym - slope * xm, 3)) r=\(decimal(xy / sqrt(xx * yy), 3)) mean_diff=\(decimal(ym - xm, 3))"
}

func magnitudeFile(_ events: [Event], _ statistics: FrequencyStatistics, _ params: Parameters) -> [String] {
    var lines: [String] = []
    for event in events {
        lines.append("EVENT \(event.number) ML=\(decimal(event.ml, 2)) n=\(event.magnitudes.filter { $0.local != nil }.count) MD=\(decimal(event.md, 2))")
        for item in event.magnitudes {
            let pick = item.pick, prefix = "\(item.pick.station.code) r=\(decimal(item.radius, 3)) amp=\(item.pick.amplitude) "
            if let local = item.local { lines.append(prefix + "ml=\(decimal(local, 2)) res=\(decimal(local - event.ml!, 2)) dur=\(pick.duration) md=\(decimal(item.durationMagnitude, 2))") }
            else { lines.append(prefix + "clipped dur=\(pick.duration) md=\(decimal(item.durationMagnitude, 2))") }
        }
    }
    lines.append("CORRECTED")
    for event in events { lines.append("EVENT \(event.number) MLC=\(decimal(event.correctedML, 2))") }
    lines.append("FMD")
    let classes = statistics.classes
    for value in classes.keys.min()!...classes.keys.max()! {
        let cumulative = classes.filter { $0.key >= value }.values.reduce(0, +)
        lines.append("M=\(magnitudeClass(value)) N=\(classes[value] ?? 0) CUM=\(cumulative)")
    }
    lines += ["MC \(magnitudeClass(statistics.completeness))", "BVALUE \(decimal(statistics.bValue, 3)) SIGMA \(decimal(statistics.sigma, 3)) N \(statistics.count)",
              "AVALUE \(decimal(statistics.aValue, 3))", magnitudeRelation(events)]
    return lines + drawTimeline(events, params)
}

func stationFile(_ stations: [Station], _ events: [Event], _ magnitudeCorrections: [Double], _ magnitudeResiduals: [[Double]]) -> [String] {
    var lines: [String] = []
    for station in stations {
        let picks = station.picks, used = events.flatMap { $0.used.filter { $0.station.order == station.order } }
        let before = used.isEmpty ? nil : sqrt(orderedSum(used.map { $0.firstResidual! * $0.firstResidual! }) / Double(used.count))
        let after = used.isEmpty ? nil : sqrt(orderedSum(used.map { $0.residual! * $0.residual! }) / Double(used.count))
        let states: [PickState] = [.used, .dropped, .added, .rejected, .unassociated]
        lines += ["STATION \(station.code) x=\(station.x) y=\(station.y) elevation=\(station.elevation)",
                  "SAMPLES start=\(station.start) count=\(station.samples.count) mean=\(station.mean) noise=\(decimal(station.noise, 1)) peak=\(station.peak) clipped=\(station.clippedSamples)",
                  "TRIGGERS total=\(station.triggers) short=\(station.shortTriggers) picks=\(picks.count)",
                  "PICKS " + states.map { state in "\(state.rawValue)=\(picks.filter { $0.state == state }.count)" }.joined(separator: " "),
                  "RESIDUALS n=\(used.count) rms=\(decimal(before, 4)) correction=\(decimal(station.timeCorrection, 4)) after=\(decimal(after, 4))",
                  "MAGNITUDES n=\(magnitudeResiduals[station.order].count) correction=\(decimal(magnitudeCorrections[station.order], 2))"]
    }
    return lines
}

typealias PlotPosition = (column: Int, row: Int)
struct EventPositions { let map: PlotPosition?; let ew: PlotPosition?; let ns: PlotPosition? }

func eventSymbol(_ event: Event) -> Character {
    guard let ml = event.ml else { return "?" }
    let scaled = scaledDecimal(ml, 2)
    return scaled < 100 ? "." : scaled < 200 ? "o" : scaled < 300 ? "O" : "@"
}

func placePoint(_ grid: inout [[Character]], _ position: PlotPosition?, _ symbol: Character) {
    guard let position else { return }
    let ranks: [Character: Int] = [" ": -1, "?": 0, ".": 1, "o": 2, "O": 3, "@": 4, "^": 5]
    if ranks[symbol]! > ranks[grid[position.row][position.column]]! { grid[position.row][position.column] = symbol }
}

func plottedPositions(_ event: Event, _ params: Parameters) -> EventPositions {
    let x = scaledDecimal(event.solution.x, 1), y = scaledDecimal(event.solution.y, 1), z = scaledDecimal(event.solution.z, 1)
    let left = params.mapArea[0], right = params.mapArea[1], bottom = params.mapArea[2], top = params.mapArea[3]
    let width = params.mapSize[0], height = params.mapSize[1], depthLimit = params.section[0], sectionHeight = params.section[1]
    var map: PlotPosition?, ew: PlotPosition?, ns: PlotPosition?
    if 10 * left <= x && x < 10 * right && 10 * bottom <= y && y < 10 * top {
        map = ((x - 10 * left) * width / (10 * (right - left)), height - 1 - (y - 10 * bottom) * height / (10 * (top - bottom)))
    }
    let sectionRow = z * sectionHeight / (10 * depthLimit)
    if 10 * left <= x && x < 10 * right && z < 10 * depthLimit { ew = ((x - 10 * left) * width / (10 * (right - left)), sectionRow) }
    if 10 * bottom <= y && y < 10 * top && z < 10 * depthLimit { ns = ((y - 10 * bottom) * width / (10 * (top - bottom)), sectionRow) }
    return EventPositions(map: map, ew: ew, ns: ns)
}

func stationMapPoint(_ station: Station, _ params: Parameters) -> PlotPosition? {
    let left = params.mapArea[0], right = params.mapArea[1], bottom = params.mapArea[2], top = params.mapArea[3]
    if station.x < left || station.x >= right || station.y < bottom || station.y >= top { return nil }
    return ((station.x - left) * params.mapSize[0] / (right - left), params.mapSize[1] - 1 - (station.y - bottom) * params.mapSize[1] / (top - bottom))
}

func positionText(_ position: PlotPosition?) -> String { position.map { "\($0.column),\($0.row)" } ?? "outside" }

func mapFile(_ events: [Event], _ stations: [Station], _ params: Parameters) -> [String] {
    let left = params.mapArea[0], right = params.mapArea[1], bottom = params.mapArea[2], top = params.mapArea[3]
    let width = params.mapSize[0], mapHeight = params.mapSize[1], depthLimit = params.section[0], sectionHeight = params.section[1]
    var map = Array(repeating: Array<Character>(repeating: " ", count: width), count: mapHeight)
    var ew = Array(repeating: Array<Character>(repeating: " ", count: width), count: sectionHeight), ns = ew
    let locations = events.map { plottedPositions($0, params) }
    for (index, event) in events.enumerated() {
        let position = locations[index], symbol = eventSymbol(event)
        placePoint(&map, position.map, symbol); placePoint(&ew, position.ew, symbol); placePoint(&ns, position.ns, symbol)
    }
    let stationLocations = stations.map { stationMapPoint($0, params) }
    for position in stationLocations { placePoint(&map, position, "^") }
    var lines = ["MAP x=\(left)..\(right) y=\(bottom)..\(top)"] + plotFrame(map)
    lines += ["SECTION EW x=\(left)..\(right) z=0..\(depthLimit)"] + plotFrame(ew)
    lines += ["SECTION NS y=\(bottom)..\(top) z=0..\(depthLimit)"] + plotFrame(ns)
    lines.append("LEGEND ^ station . ML<1 o ML<2 O ML<3 @ ML>=3 ? no ML")
    for (index, station) in stations.enumerated() { lines.append("STATION \(station.code) map=\(positionText(stationLocations[index]))") }
    for (index, event) in events.enumerated() {
        let position = locations[index]
        lines.append("EVENT \(event.number) \(eventSymbol(event)) map=\(positionText(position.map)) ew=\(positionText(position.ew)) ns=\(positionText(position.ns))")
    }
    return lines
}

let input = try loadInputs()
let stations = input.stations, params = input.params
let picks = stations.flatMap { detectStation($0, params) }.sorted { $0.sample == $1.sample ? $0.station.order < $1.station.order : $0.sample < $1.sample }
let candidates = associate(picks, params.associationWindow, params.minStations)
let events = locateCandidates(candidates, params)
let corrections = stationTimeCorrections(events, stations)
for station in stations { station.timeCorrection = corrections[station.order] }
relocateEvents(events, params, corrections)
let magnitudes = computeMagnitudes(events, stations, params)
let regression = travelTimeRegression(events)
let clusters = clusterEvents(events, params)
let added = reassociateUnassigned(picks, events, corrections, params)
let statistics = frequencyStatistics(events.compactMap { $0.ml })
try writeLines("picks.csv", picksFile(picks))
try writeLines("locations.txt", locationFile(picks, candidates, events, stations, corrections, regression, clusters, added, params))
try writeLines("catalog.csv", catalogRows(events))
try writeLines("magnitudes.txt", magnitudeFile(events, statistics, params))
try writeLines("stations.txt", stationFile(stations, events, magnitudes.corrections, magnitudes.residuals))
try writeLines("map.txt", mapFile(events, stations, params))
