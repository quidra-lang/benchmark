import Foundation

let filterNames = ["cv", "ca", "abg", "imm", "rts"]
struct TrackingSettings {
    var model = MotionModel.cv
    var qCV = 0.0
    var qCA = 0.0
    var sigma = 0.0
    var velocityVariance = 0.0
    var accelerationVariance = 0.0
    var gate = 0.0
    var requiredHits = 0
    var confirmationWindow = 0
    var deletionMisses = 0
    var abg: [Double] = []
    var immQ: [Double] = []
    var immTransition: Matrix = []
    var immInitial: [Double] = []
    var matchDistance = 0.0
    var cutoff = 0.0
    var consistencyBound = 0.0
    var nisEdges: [Double] = []
    var xmin = 0.0
    var xmax = 0.0
    var ymin = 0.0
    var ymax = 0.0
    var width = 0
    var height = 0
}
struct Target { let number: Int; var positions: [Int: [Double]]; var scans: [Int] }
struct Inputs { let measurements: [[[Double]]]; let times: [Double]; let targets: [Target]; let settings: TrackingSettings }
func inputLines(_ name: String) throws -> [String] { try String(contentsOfFile: "input/" + name, encoding: .ascii).split(separator: "\n").map(String.init) }
func readInputs() throws -> Inputs {
    var measurements: [[[Double]]] = [[]], times = [0.0], targets: [Target] = [], settings = TrackingSettings()
    for line in try inputLines("measurements.csv").dropFirst() { let fields = line.split(separator: ","), scan = Int(fields[0])!; if measurements.count == scan { measurements.append([]); times.append(Double(fields[1])!) }; measurements[scan].append([Double(fields[2])!, Double(fields[3])!]) }
    for line in try inputLines("truth.csv").dropFirst() { let fields = line.split(separator: ","), number = Int(fields[0])!, scan = Int(fields[1])!; if targets.last?.number != number { targets.append(Target(number: number, positions: [:], scans: [])) }; targets[targets.count - 1].positions[scan] = [Double(fields[2])!, Double(fields[3])!]; targets[targets.count - 1].scans.append(scan) }
    for line in try inputLines("params.txt") {
        let fields = line.split(separator: " ").map(String.init)
        switch fields[0] {
        case "MODEL": settings.model = MotionModel(rawValue: fields[1])!
        case "Q_CV": settings.qCV = Double(fields[1])!
        case "Q_CA": settings.qCA = Double(fields[1])!
        case "SIGMA": settings.sigma = Double(fields[1])!
        case "INIT_VELOCITY_VARIANCE": settings.velocityVariance = Double(fields[1])!
        case "INIT_ACCELERATION_VARIANCE": settings.accelerationVariance = Double(fields[1])!
        case "GATE": settings.gate = Double(fields[1])!
        case "CONFIRM": settings.requiredHits = Int(fields[1])!; settings.confirmationWindow = Int(fields[2])!
        case "DELETE": settings.deletionMisses = Int(fields[1])!
        case "ABG": settings.abg = fields.dropFirst().map { Double($0)! }
        case "IMM_Q": settings.immQ = fields.dropFirst().map { Double($0)! }
        case "IMM_TRANSITION": settings.immTransition = [fields[1...2].map { Double($0)! }, fields[3...4].map { Double($0)! }]
        case "IMM_INITIAL": settings.immInitial = fields.dropFirst().map { Double($0)! }
        case "MATCH_DISTANCE": settings.matchDistance = Double(fields[1])!
        case "OSPA_CUTOFF": settings.cutoff = Double(fields[1])!
        case "CONSISTENCY_BOUND": settings.consistencyBound = Double(fields[1])!
        case "NIS_EDGES": settings.nisEdges = fields.dropFirst().map { Double($0)! }
        case "PLOT_X": settings.xmin = Double(fields[1])!; settings.xmax = Double(fields[2])!
        case "PLOT_Y": settings.ymin = Double(fields[1])!; settings.ymax = Double(fields[2])!
        default: settings.width = Int(fields[1])!; settings.height = Int(fields[2])!
        }
    }
    return Inputs(measurements: measurements, times: times, targets: targets, settings: settings)
}
func listed(_ keyword: String, _ items: [String]) -> String { keyword + " " + (items.isEmpty ? "none" : items.joined(separator: " ")) }
func optional(_ number: Int?) -> String { number.map(String.init) ?? "-" }
struct Segment { let first: Int; var last: Int; let label: Int }
func segments(_ items: [(Int, Int)]) -> [Segment] { var result: [Segment] = []; for (scan, label) in items { if let last = result.last, last.last + 1 == scan && last.label == label { result[result.count - 1].last = scan } else { result.append(Segment(first: scan, last: scan, label: label)) } }; return result }
func pathLength(_ positions: [[Double]]) -> Double { total((1..<positions.count).map { distance(positions[$0 - 1], positions[$0]) }) }
func rmse(_ errors: [Double]) -> Double { sqrt(total(errors) / Double(errors.count)) }
func filterScores(_ values: [Double]) -> String { let rounded = values.map { Double(real($0))! }; var best = 0; for index in rounded.indices.dropFirst() { if rounded[index] < rounded[best] { best = index } }; return values.indices.map { "\(filterNames[$0]) \(real(values[$0]))" }.joined(separator: " ") + " best \(filterNames[best])" }
func framed(_ rows: [[String]]) -> [String] { let border = "+" + String(repeating: "-", count: rows[0].count) + "+"; return [border] + rows.map { "|" + $0.joined() + "|" } + [border] }
enum TrackStatus: String { case tentative, confirmed, deleted }
final class Track {
    let number: Int
    let birth: Int
    var lastHit: Int
    var confirmed: Int?
    var deleted: Int?
    var status = TrackStatus.tentative
    var hits = 1
    var consecutiveMisses = 0
    var observations: [Int: [Double]]
    var nis: [Int: Double] = [:]
    var kalman: Kalman
    var target: Int?
    var primaryMatches: [Int: Int] = [:]
    var estimates = Array(repeating: [Int: [Double]](), count: 5)
    var modelLogs = [0.0, 0.0]
    var primaryCovariances: [Int: Matrix] = [:]
    var high: [Int: Double] = [:]
    var nisValues: [Double] = []
    var longestGap = 0
    var path = 0.0
    var common: [Int] = []
    var meanDistance = 0.0
    var span: [Int] { Array(birth...lastHit) }
    init(_ number: Int, _ scan: Int, _ measurement: [Double], _ kalman: Kalman) { self.number = number; birth = scan; lastHit = scan; observations = [scan: measurement]; self.kalman = kalman }
}
struct TargetResult { let track: Track; let position: [Double]; let velocity: [Double]; let velocityCount: Int; let nees: [Double] }
final class Analysis {
    let input: Inputs
    let settings: TrackingSettings
    let scans: Int
    let primary: Int
    var tracks: [Track] = []
    var evaluated: [Track] = []
    var trackRows = ["track,scan,x,y,vx,vy,status"]
    var associationLog: [String] = []
    var conflictMeasurements = 0
    var conflictTracks = 0
    var greedyDifferences = 0
    var labels: [[[Int: Int]]] = []
    var ospaValues = Array(repeating: [Double](), count: 5)
    var scanSizes: [(Int, Int)] = []
    var continuities: [[Continuity]] = []
    var matchedTracks: [Int: Track] = [:]
    var targetResults: [Int: TargetResult] = [:]
    var overallPosition: [Double] = []
    var overallVelocity: [Double] = []
    init(_ input: Inputs) { self.input = input; settings = input.settings; scans = input.measurements.count - 1; primary = input.settings.model == .cv ? 0 : 1 }
    func makeKalman(_ model: MotionModel, _ measurement: [Double]) -> Kalman { Kalman(model, model == .cv ? settings.qCV : settings.qCA, settings.sigma, settings.velocityVariance, settings.accelerationVariance, measurement) }
    func trackAllScans() {
        for scan in 1...scans {
            let live = tracks.filter { $0.status != .deleted }, measurements = input.measurements[scan]
            if scan > 1 { for track in live { track.kalman.predict(input.times[scan] - input.times[scan - 1]) } }
            var usable: [Pair: Double] = [:], innovations: [Pair: Innovation] = [:], rowGates = Array(repeating: 0, count: live.count), columnGates = Array(repeating: 0, count: measurements.count)
            for (row, track) in live.enumerated() { for (column, measurement) in measurements.enumerated() { let innovation = track.kalman.innovation(measurement); if innovation.distanceSquared <= settings.gate { let pair = Pair(row: row, column: column); usable[pair] = innovation.distanceSquared; innovations[pair] = innovation; rowGates[row] += 1; columnGates[column] += 1 } } }
            let assigned = optimalAssignment(live.count, measurements.count, usable), ordered = usable.keys.sorted { first, second in if usable[first]! != usable[second]! { return usable[first]! < usable[second]! }; return pairBefore(first, second) }
            var greedy: [Pair] = [], usedRows: Set<Int> = [], usedColumns: Set<Int> = []
            for pair in ordered where !usedRows.contains(pair.row) && !usedColumns.contains(pair.column) { greedy.append(pair); usedRows.insert(pair.row); usedColumns.insert(pair.column) }
            greedy.sort(by: pairBefore); if assigned != greedy { greedyDifferences += 1 }
            let matches = Dictionary(uniqueKeysWithValues: assigned.map { ($0.row, $0.column) })
            var missed: [String] = [], confirmed: [String] = [], deleted: [String] = []
            for (row, track) in live.enumerated() {
                if let column = matches[row] { let pair = Pair(row: row, column: column), measurement = measurements[column]; track.kalman.update(measurement, innovations[pair]); track.observations[scan] = measurement; track.nis[scan] = usable[pair]!; track.lastHit = scan; track.hits += 1; track.consecutiveMisses = 0 }
                else { track.consecutiveMisses += 1; missed.append(String(track.number)) }
                if track.status == .confirmed { if track.consecutiveMisses >= settings.deletionMisses { track.status = .deleted; track.deleted = scan; deleted.append(String(track.number)) } }
                else if track.hits >= settings.requiredHits { track.status = .confirmed; track.confirmed = scan; confirmed.append(String(track.number)) }
                else if scan - track.birth + 1 >= settings.confirmationWindow { track.status = .deleted; track.deleted = scan; deleted.append(String(track.number)) }
            }
            let assignedColumns = Set(assigned.map { $0.column })
            var newTracks: [Track] = [], newDescriptions: [String] = []
            for (column, measurement) in measurements.enumerated() where !assignedColumns.contains(column) { let track = Track(tracks.count + 1, scan, measurement, makeKalman(settings.model, measurement)); tracks.append(track); newTracks.append(track); newDescriptions.append("\(track.number):\(column + 1)") }
            let conflictsM = columnGates.filter { $0 >= 2 }.count, conflictsT = rowGates.filter { $0 >= 2 }.count
            conflictMeasurements += conflictsM; conflictTracks += conflictsT
            associationLog += ["scan \(scan) tracks \(live.count) measurements \(measurements.count)", listed("gate", usable.keys.sorted(by: pairBefore).map { "\(live[$0.row].number):\($0.column + 1)=\(real(usable[$0]!))" }), listed("assign", assigned.map { "\(live[$0.row].number):\($0.column + 1)" }), listed("greedy", greedy.map { "\(live[$0.row].number):\($0.column + 1)" }), listed("missed", missed), listed("new", newDescriptions), listed("confirmed", confirmed), listed("deleted", deleted), "status tentative \(tracks.filter { $0.status == .tentative }.count) confirmed \(tracks.filter { $0.status == .confirmed }.count)", "conflicts measurements \(conflictsM) tracks \(conflictsT)"]
            for track in live + newTracks { trackRows.append(([String(track.number), String(scan)] + track.kalman.state.prefix(4).map { real($0) } + [track.status.rawValue]).joined(separator: ",")) }
        }
        evaluated = tracks.filter { $0.confirmed != nil }
    }
    func abgEstimates(_ track: Track) -> [Int: [Double]] {
        var state = track.observations[track.birth]! + [0.0, 0, 0, 0], estimates: [Int: [Double]] = [:]
        for scan in track.span { if scan > track.birth { let interval = input.times[scan] - input.times[scan - 1], measurement = track.observations[scan]; for axis in 0..<2 { var position = state[axis], velocity = state[axis + 2], acceleration = state[axis + 4]; position = position + interval * velocity + interval * interval * acceleration / 2; velocity = velocity + interval * acceleration; if let measurement { let residual = measurement[axis] - position; position += settings.abg[0] * residual; velocity += settings.abg[1] * residual / interval; acceleration += 2 * settings.abg[2] * residual / (interval * interval) }; state[axis] = position; state[axis + 2] = velocity; state[axis + 4] = acceleration } }; estimates[scan] = Array(state.prefix(4)) }
        return estimates
    }
    func compareFilters() {
        for track in evaluated {
            var histories: [[FilterSnapshot]] = []
            for (index, model) in [MotionModel.cv, .ca].enumerated() { var kalman = makeKalman(model, track.observations[track.birth]!), history: [FilterSnapshot] = [], likelihood = 0.0; for scan in track.span { if scan > track.birth { kalman.predict(input.times[scan] - input.times[scan - 1]); if let measurement = track.observations[scan] { likelihood += kalman.update(measurement).logLikelihood } }; track.estimates[index][scan] = Array(kalman.state.prefix(4)); history.append(kalman.snapshot()) }; histories.append(history); track.modelLogs[index] = likelihood }
            track.estimates[2] = abgEstimates(track)
            let primaryHistory = histories[primary], smoothed = smooth(primaryHistory)
            for (index, scan) in track.span.enumerated() { track.primaryCovariances[scan] = primaryHistory[index].covariance; track.estimates[4][scan] = Array(smoothed[index].prefix(4)) }
            var imm = IMM(settings.immQ, settings.immTransition, settings.immInitial, settings.sigma, settings.velocityVariance, track.observations[track.birth]!), gap = 0
            for scan in track.span { if scan > track.birth { imm.step(input.times[scan] - input.times[scan - 1], track.observations[scan]) }; track.estimates[3][scan] = imm.estimate(); track.high[scan] = imm.probabilities[1]; gap = track.observations[scan] == nil ? gap + 1 : 0; track.longestGap = max(track.longestGap, gap) }
            track.nisValues = track.span.compactMap { track.nis[$0] }; track.path = pathLength(track.span.map { track.estimates[4][$0]! })
        }
    }
    func evaluateScans() {
        labels = Array(repeating: Array(repeating: [Int: Int](), count: input.targets.count), count: 5)
        for scan in 1...scans {
            let tracks = evaluated.filter { $0.birth <= scan && scan <= $0.lastHit }, targets = input.targets.indices.filter { input.targets[$0].positions[scan] != nil }, positions = targets.map { input.targets[$0].positions[scan]! }
            scanSizes.append((targets.count, tracks.count))
            for filter in 0..<5 { let estimates = tracks.map { $0.estimates[filter][scan]! }; var usable: [Pair: Double] = [:]; for row in estimates.indices { for column in positions.indices { let value = distance(estimates[row], positions[column]); if value <= settings.matchDistance { usable[Pair(row: row, column: column)] = value } } }; for pair in optimalAssignment(tracks.count, targets.count, usable) { let track = tracks[pair.row], target = targets[pair.column]; labels[filter][target][scan] = track.number; if filter == primary { track.primaryMatches[scan] = target } }; ospaValues[filter].append(ospa(estimates, positions, settings.cutoff)) }
        }
        continuities = (0..<5).map { filter in input.targets.indices.map { target in continuity(input.targets[target].scans.map { labels[filter][target][$0] }) } }
    }
    func matchTracks() {
        var usable: [Pair: Double] = [:], details: [Pair: [Int]] = [:]
        for (row, track) in evaluated.enumerated() { for (column, target) in input.targets.enumerated() { let common = track.span.filter { target.positions[$0] != nil }; if common.isEmpty { continue }; let distances = Dictionary(uniqueKeysWithValues: common.map { ($0, distance(track.estimates[primary][$0]!, target.positions[$0]!)) }); if !distances.values.contains(where: { $0 < settings.cutoff }) { continue }; let union = Set(track.span + target.scans).sorted(), cost = total(union.map { distances[$0].map { min(settings.cutoff, $0) } ?? settings.cutoff }) / Double(union.count), pair = Pair(row: row, column: column); usable[pair] = cost; details[pair] = common } }
        for pair in optimalAssignment(evaluated.count, input.targets.count, usable) { let track = evaluated[pair.row]; track.target = pair.column; track.common = details[pair]!; track.meanDistance = usable[pair]!; matchedTracks[pair.column] = track }
    }
    func evaluateErrors() {
        var allPosition = Array(repeating: [Double](), count: 5), allVelocity = Array(repeating: [Double](), count: 5)
        for (targetIndex, target) in input.targets.enumerated() {
            guard let track = matchedTracks[targetIndex] else { continue }
            var velocities: [Int: [Double]] = [:], positions: [Double] = [], speeds: [Double] = [], nees: [Double] = []
            for scan in track.common { if let previous = target.positions[scan - 1], let following = target.positions[scan + 1] { let interval = input.times[scan + 1] - input.times[scan - 1]; velocities[scan] = (0..<2).map { (following[$0] - previous[$0]) / interval } } }
            for filter in 0..<5 { let positionErrors = track.common.map { squaredDistance(track.estimates[filter][$0]!, target.positions[$0]!) }, velocityErrors = velocities.keys.sorted().map { squaredDistance(Array(track.estimates[filter][$0]![2...3]), velocities[$0]!) }; positions.append(rmse(positionErrors)); speeds.append(rmse(velocityErrors)); allPosition[filter] += positionErrors; allVelocity[filter] += velocityErrors }
            for scan in track.common { let estimate = track.estimates[primary][scan]!, position = target.positions[scan]!, error = [estimate[0] - position[0], estimate[1] - position[1]], covariance = track.primaryCovariances[scan]!.prefix(2).map { Array($0.prefix(2)) }; nees.append(quadratic2(error, inverse(covariance))) }
            targetResults[targetIndex] = TargetResult(track: track, position: positions, velocity: speeds, velocityCount: velocities.count, nees: nees)
        }
        overallPosition = allPosition.map { rmse($0) }; overallVelocity = allVelocity.map { rmse($0) }
    }
}
extension Analysis {
    func summarySection() -> [String] { ["summary", "scans \(scans)", "measurements \(input.measurements.reduce(0) { $0 + $1.count })", "targets \(input.targets.count)", "tracks_created \(tracks.count)", "tracks_confirmed \(evaluated.count)", "false_tracks \(evaluated.filter { $0.primaryMatches.isEmpty }.count)", "missed_targets \(input.targets.count - matchedTracks.count)", "measurements_used \(evaluated.reduce(0) { $0 + $1.hits })", "conflict_measurements \(conflictMeasurements)", "conflict_tracks \(conflictTracks)", "greedy_differences \(greedyDifferences)"] }
    func targetsSection() -> [String] {
        var lines = ["targets"]
        for target in input.targets { let length = pathLength(target.scans.map { target.positions[$0]! }), first = target.scans.first!, last = target.scans.last!, speed = length / (input.times[last] - input.times[first]); lines.append("target \(target.number) first \(first) last \(last) scans \(target.scans.count) path \(real(length)) mean_speed \(real(speed))") }
        return lines
    }
    func tracksSection() -> [String] {
        var lines = ["tracks"]
        for track in evaluated { let count = track.nisValues.count, mean = total(track.nisValues) / Double(count), inside = track.nisValues.filter { $0 <= settings.consistencyBound }.count; lines.append("track \(track.number) birth \(track.birth) confirmed \(track.confirmed!) end \(track.lastHit) deleted \(optional(track.deleted)) hits \(track.hits) misses \(track.span.count - track.hits) longest_gap \(track.longestGap) path \(real(track.path)) nis \(real(mean)) nis_inside \(inside)/\(count)") }
        return lines
    }
    func matchingSection() -> [String] {
        var lines = ["matching"]
        for track in evaluated { var line = "track \(track.number) target \(track.target.map { String(input.targets[$0].number) } ?? "-")"; if track.target != nil { line += " common \(track.common.count) mean_distance \(real(track.meanDistance))" }; line += " matched_scans \(track.primaryMatches.count) "; let groups = segments(track.primaryMatches.keys.sorted().map { ($0, track.primaryMatches[$0]!) }); line += listed("segments", groups.map { "\($0.first)-\($0.last):\(input.targets[$0.label].number)" }); lines.append(line) }
        return lines
    }
    func rmseSection() -> [String] {
        var lines = ["rmse"]
        for (index, target) in input.targets.enumerated() { guard let result = targetResults[index] else { lines.append("target \(target.number) track -"); continue }; lines.append("target \(target.number) track \(result.track.number) common \(result.track.common.count) " + filterScores(result.position)); lines.append("target \(target.number) velocity \(result.velocityCount) " + filterScores(result.velocity)) }
        lines += ["overall position " + filterScores(overallPosition), "overall velocity " + filterScores(overallVelocity)]
        return lines
    }
    func consistencySection() -> [String] {
        var lines = ["consistency"]
        for (index, target) in input.targets.enumerated() { guard let result = targetResults[index] else { lines.append("target \(target.number) track -"); continue }; let inside = result.nees.filter { $0 <= settings.consistencyBound }.count; lines.append("target \(target.number) track \(result.track.number) nees \(real(total(result.nees) / Double(result.nees.count))) inside \(inside)/\(result.nees.count)") }
        let values = evaluated.flatMap { $0.nisValues }, edges = settings.nisEdges
        var observed = Array(repeating: 0, count: edges.count + 1), expected: [Double] = [], lower = 0.0
        for value in values { let index = edges.firstIndex { value < $0 } ?? edges.count; observed[index] += 1 }
        for index in 0...edges.count { let upperProbability = index == edges.count ? 0 : exp(-edges[index] / 2); expected.append(Double(values.count) * (exp(-lower / 2) - upperProbability)); if index < edges.count { lower = edges[index] } }
        lines.append("nis_histogram total \(values.count) observed " + observed.map(String.init).joined(separator: " ") + " expected " + expected.map { real($0) }.joined(separator: " "))
        return lines
    }
    func modelsSection() -> [String] { ["models"] + evaluated.map { track in "track \(track.number) updates \(track.nisValues.count) cv \(real(track.modelLogs[0])) ca \(real(track.modelLogs[1])) better \(track.modelLogs[0] >= track.modelLogs[1] ? "cv" : "ca")" } }
    func ospaSection() -> [String] {
        var lines = ["ospa cutoff \(real(settings.cutoff)) order 2", "scan targets tracks cv ca abg imm rts"]
        for index in scanSizes.indices { lines.append("\(index + 1) \(scanSizes[index].0) \(scanSizes[index].1) " + (0..<5).map { real(ospaValues[$0][index]) }.joined(separator: " ")) }
        lines.append("mean " + ospaValues.map { real(total($0) / Double(scans)) }.joined(separator: " "))
        return lines
    }
    func continuitySection() -> [String] {
        var lines = ["continuity"]
        for filter in 0..<5 { let values = continuities[filter]; lines.append("\(filterNames[filter]) covered \(values.reduce(0) { $0 + $1.covered }) breaks \(values.reduce(0) { $0 + $1.breaks }) swaps \(values.reduce(0) { $0 + $1.swaps })"); for (index, target) in input.targets.enumerated() { let value = values[index]; lines.append("  target \(target.number) scans \(target.scans.count) covered \(value.covered) breaks \(value.breaks) swaps \(value.swaps) delay \(optional(value.delay))") } }
        return lines
    }
    func immSection() -> [String] {
        var lines = ["imm"]
        for track in evaluated { let span = track.span, mean = total(span.map { track.high[$0]! }) / Double(span.count); var maximum = span[0]; for scan in span.dropFirst() { if track.high[scan]! > track.high[maximum]! { maximum = scan } }; let high = span.filter { track.high[$0]! > 0.5 }, groups = segments(high.map { ($0, 0) }); lines.append("track \(track.number) mean_high \(real(mean)) max_high \(real(track.high[maximum]!)) at \(maximum) high_scans \(high.count) " + listed("segments", groups.map { "\($0.first)-\($0.last)" })) }
        return lines
    }
    func evaluationLines() -> [String] { let sections = [summarySection(), targetsSection(), tracksSection(), matchingSection(), rmseSection(), consistencySection(), modelsSection(), ospaSection(), continuitySection(), immSection()]; var lines: [String] = []; for section in sections { if !lines.isEmpty { lines.append("") }; lines += section }; return lines }
    func plotCell(_ point: [Double]) -> (row: Int, column: Int)? { let dx = (settings.xmax - settings.xmin) / Double(settings.width), dy = (settings.ymax - settings.ymin) / Double(settings.height), column = Int(floor((point[0] - settings.xmin) / dx)), row = Int(floor((settings.ymax - point[1]) / dy)); return row >= 0 && row < settings.height && column >= 0 && column < settings.width ? (row, column) : nil }
    func plotLines() -> [String] {
        let width = settings.width, height = settings.height, letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz").map(String.init), characters = Dictionary(uniqueKeysWithValues: evaluated.enumerated().map { ($0.element.number, letters[$0.offset]) })
        var trajectory = Array(repeating: Array(repeating: " ", count: width), count: height)
        for target in input.targets { for scan in target.scans { if let cell = plotCell(target.positions[scan]!) { trajectory[cell.row][cell.column] = "." } } }
        for track in evaluated { for scan in track.span { if let cell = plotCell(track.estimates[4][scan]!) { trajectory[cell.row][cell.column] = characters[track.number]! } } }
        var lines = ["tracks x \(real(settings.xmin)) \(real(settings.xmax)) y \(real(settings.ymin)) \(real(settings.ymax)) size \(width) \(height)"] + framed(trajectory)
        for track in evaluated { lines.append("\(characters[track.number]!) track \(track.number) target \(track.target.map { String(input.targets[$0].number) } ?? "-")") }
        var counts = Array(repeating: Array(repeating: 0, count: width), count: height)
        for scan in 1...scans { for measurement in input.measurements[scan] { if let cell = plotCell(measurement) { counts[cell.row][cell.column] += 1 } } }
        let density = counts.map { row in row.map { $0 == 0 ? " " : $0 < 10 ? String($0) : "#" } }
        lines += ["", "measurements"] + framed(density) + ["", "timeline"]
        for (index, target) in input.targets.enumerated() { let timeline = (1...scans).map { scan -> String in if target.positions[scan] == nil { return " " }; if let label = labels[primary][index][scan] { return characters[label]! }; return "." }; lines.append("\(target.number) |" + timeline.joined() + "|") }
        let heights = ospaValues[primary].map { Int(floor(10 * $0 / settings.cutoff)) }, bars = (0..<10).map { row in heights.map { $0 >= 10 - row ? "#" : " " } }
        lines += ["", "ospa \(filterNames[primary])"] + framed(bars)
        return lines
    }
    func write() throws {
        try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
        var smoothed = ["track,scan,x,y,vx,vy"]
        for track in evaluated { for scan in track.span { smoothed.append(([String(track.number), String(scan)] + track.estimates[4][scan]!.map { real($0) }).joined(separator: ",")) } }
        let outputs = [("tracks.csv", trackRows), ("smoothed.csv", smoothed), ("association_log.txt", associationLog), ("evaluation.txt", evaluationLines()), ("track_plot.txt", plotLines())]
        for (name, lines) in outputs { try (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: false, encoding: .ascii) }
    }
}
let analysis = try Analysis(readInputs())
analysis.trackAllScans()
analysis.compareFilters()
analysis.evaluateScans()
analysis.matchTracks()
analysis.evaluateErrors()
try analysis.write()
