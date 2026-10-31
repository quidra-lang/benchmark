import Foundation

enum BoundaryKind: String { case fixed, convective, insulated }
struct Segment { let name: String; let edge: Edge; let kind: BoundaryKind; let faces: [FaceAddress]; let coefficient: Double?; let temperature: Double? }
struct Period { let on: Int; let off: Int }
struct Source {
    let name: String
    let cells: [Int]
    let power: Double
    let periods: [Period]
    var weight: Double { power / Double(cells.count) }
    func operating(_ time: Int) -> Bool { periods.contains { $0.on <= time && time < $0.off } }
    func dutyRatio(_ end: Int) -> Double { Double(periods.reduce(0) { $0 + min($1.off, end) - min($1.on, end) }) / Double(end) }
}
enum TransientMethod: String { case ftcs, backward = "backward_euler", crank = "crank_nicolson" }
struct Run { let name: String; let method: TransientMethod; let step: Int; var dt: Double { Double(step) / 1000 } }
struct Probe { let name: String; let cell: Int }
struct Parameters {
    var initial = 0.0
    var endTime = 0
    var snapshotTimes: [Int] = []
    var probeEvery = 0
    var probes: [Probe] = []
    var runs: [Run] = []
    var reference = ""
    var tolerance = 0.0
    var maximumIterations = 0
    var omega = 0.0
    var bands: [Double] = []
    var alarm = 0.0
    var limit = 0.0
}
struct Face { let neighbor: Int?; let conductance: Double; let temperature: Double? }
func readBoundary(_ mesh: Mesh) throws -> (segments: [Segment], sources: [Source]) {
    var segments: [Segment] = [], sources: [Source] = []
    for line in try String(contentsOfFile: "input/boundary.txt", encoding: .ascii).split(separator: "\n") {
        let fields = line.components(separatedBy: " ")
        if fields[0] == "segment" {
            let edge = Edge(rawValue: fields[2])!, kind = BoundaryKind(rawValue: fields[5])!, coefficient = kind == .convective ? Double(fields[6])! : nil, temperature = kind == .fixed ? Double(fields[6])! : kind == .convective ? Double(fields[7])! : nil
            segments.append(Segment(name: fields[1], edge: edge, kind: kind, faces: mesh.segmentFaces(edge, Int(fields[3])!, Int(fields[4])!), coefficient: coefficient, temperature: temperature))
        } else {
            let cells = mesh.sourceCells(Int(fields[2])!, Int(fields[3])!, Int(fields[4])!, Int(fields[5])!), times = fields.dropFirst(7).map { Int($0)! }, periods = stride(from: 0, to: times.count, by: 2).map { Period(on: times[$0], off: times[$0 + 1]) }
            sources.append(Source(name: fields[1], cells: cells, power: Double(fields[6])!, periods: periods))
        }
    }
    return (segments, sources)
}
func readParameters(_ mesh: Mesh) throws -> Parameters {
    var params = Parameters()
    for line in try String(contentsOfFile: "input/params.txt", encoding: .ascii).split(separator: "\n") {
        let fields = line.components(separatedBy: " ")
        switch fields[0] {
        case "initial": params.initial = Double(fields[1])!
        case "end_time": params.endTime = Int(fields[1])!
        case "snapshots": params.snapshotTimes = fields.dropFirst().map { Int($0)! }
        case "probe_every": params.probeEvery = Int(fields[1])!
        case "probe": params.probes.append(Probe(name: fields[1], cell: mesh.cell(Int(fields[2])!, Int(fields[3])!)))
        case "run": params.runs.append(Run(name: fields[1], method: TransientMethod(rawValue: fields[2])!, step: Int(fields[3])!))
        case "reference": params.reference = fields[1]
        case "tolerance": params.tolerance = Double(fields[1])!
        case "max_iterations": params.maximumIterations = Int(fields[1])!
        case "omega": params.omega = Double(fields[1])!
        case "bands": params.bands = fields.dropFirst().map { Double($0)! }
        case "alarm": params.alarm = Double(fields[1])!
        default: params.limit = Double(fields[1])!
        }
    }
    return params
}
func sourceTerms(_ sources: [Source], _ count: Int, _ time: Int? = nil) -> (field: [Double], power: Double) {
    var field = Array(repeating: 0.0, count: count), powers: [Double] = []
    for source in sources {
        if let time, !source.operating(time) { continue }
        powers.append(source.power)
        for point in source.cells { field[point] += source.weight }
    }
    return (field, orderedSum(powers))
}
struct PlateSystem {
    let mesh: Mesh
    let materials: [Material]
    let segments: [Segment]
    let sources: [Source]
    let cellMaterial: [Int]
    let materialCells: [[Int]]
    let capacity: [Double]
    let faces: [[Face]]
    let diagonal: [Double]
    let beta: [Double]
    let sourceAll: [Double]
    let totalPower: Double
    let maximumStep: Double
    init(_ mesh: Mesh, _ materials: [Material], _ segments: [Segment], _ sources: [Source]) {
        let numbers = Dictionary(uniqueKeysWithValues: materials.enumerated().map { ($0.element.code, $0.offset) }), cellMaterial = mesh.codes.map { numbers[$0]! }, cellMaterials = cellMaterial.map { materials[$0] }
        let capacities = cellMaterials.map { heatCapacity($0, mesh.dx, mesh.thickness) }
        var faces = mesh.neighbors.enumerated().map { p, neighbors in neighbors.map { neighbor -> Face in
            let g = neighbor.map { interiorConductance(cellMaterials[p].conductivity, cellMaterials[$0].conductivity, mesh.thickness) } ?? 0
            return Face(neighbor: neighbor, conductance: g, temperature: nil)
        } }
        for segment in segments {
            for address in segment.faces {
                let conductivity = cellMaterials[address.cell].conductivity, g: Double
                switch segment.kind { case .fixed: g = fixedConductance(conductivity, mesh.thickness); case .convective: g = convectiveConductance(conductivity, segment.coefficient!, mesh.dx, mesh.thickness); case .insulated: g = 0 }
                faces[address.cell][address.face] = Face(neighbor: nil, conductance: g, temperature: segment.temperature)
            }
        }
        let diagonal = faces.map { orderedSum($0.map { $0.conductance }) }, beta = faces.map { row in orderedSum(row.compactMap { face in face.temperature.map { face.conductance * $0 } }) }, sourcesAll = sourceTerms(sources, mesh.count)
        self.mesh = mesh; self.materials = materials; self.segments = segments; self.sources = sources; self.cellMaterial = cellMaterial; materialCells = materials.indices.map { material in cellMaterial.indices.filter { cellMaterial[$0] == material } }
        capacity = capacities; self.faces = faces; self.diagonal = diagonal; self.beta = beta; sourceAll = sourcesAll.field; totalPower = sourcesAll.power; maximumStep = capacities.indices.map { capacities[$0] / diagonal[$0] }.min()!
    }
}
enum RunStatus: String { case accepted, step, unstable }
func runStatus(_ run: Run, _ system: PlateSystem, _ params: Parameters) -> RunStatus {
    var times = [params.endTime, params.probeEvery] + params.snapshotTimes
    for source in system.sources { for period in source.periods { times += [period.on, period.off] } }
    if times.contains(where: { $0 % run.step != 0 }) { return .step }
    if run.method == .ftcs && run.dt > system.maximumStep { return .unstable }
    return .accepted
}
func hottestCell(_ field: [Double]) -> Int { var best = 0; for i in field.indices.dropFirst() { if field[i] > field[best] { best = i } }; return best }
func fieldSummary(_ prefix: String, _ mesh: Mesh, _ field: [Double]) -> String { let hottest = hottestCell(field); return "\(prefix) max \(real(field[hottest], 2)) at \(mesh.coordinates(hottest)) min \(real(field.min()!, 2)) mean \(real(orderedSum(field) / Double(mesh.count), 2))" }
func storedHeat(_ system: PlateSystem, _ field: [Double], _ initial: Double, _ cells: [Int]? = nil) -> Double { orderedSum((cells ?? Array(field.indices)).map { system.capacity[$0] * (field[$0] - initial) }) }
func segmentFlow(_ system: PlateSystem, _ segment: Segment, _ field: [Double]) -> Double { segment.kind == .insulated ? 0 : orderedSum(segment.faces.map { let face = system.faces[$0.cell][$0.face]; return face.conductance * (face.temperature! - field[$0.cell]) }) }
func stepBoundaryEnergy(_ system: PlateSystem, _ segment: Segment, _ run: Run, _ previous: [Double], _ updated: [Double], _ intermediate: [Double]?) -> Double {
    if segment.kind == .insulated { return 0 }
    let terms = segment.faces.map { address -> Double in
        let face = system.faces[address.cell][address.face], temperature: Double
        if run.method == .ftcs { temperature = previous[address.cell] }
        else if segment.edge.horizontal { temperature = intermediate![address.cell] }
        else if run.method == .backward { temperature = updated[address.cell] }
        else { temperature = (previous[address.cell] + updated[address.cell]) / 2 }
        return face.conductance * (face.temperature! - temperature)
    }
    return run.dt * orderedSum(terms)
}
struct FieldSnapshot { let field: [Double]; let stored: Double; let boundary: Double; let generated: Double }
struct Peak { let temperature: Double; let time: Int; let cell: Int }
struct Alarm { let time: Int; let cell: Int }
struct ProbeSample { let time: Int; let values: [Double] }
final class RunResult {
    let run: Run
    let status: RunStatus
    var snapshots: [Int: FieldSnapshot] = [:]
    var probeSamples: [ProbeSample] = []
    var segmentEnergy: [Double] = []
    var generated = 0.0
    var peak: Peak?
    var alarm: Alarm?
    var above = 0
    var steps = 0
    var finalField: [Double] = []
    var stored = 0.0
    var boundary = 0.0
    var balance = false
    init(_ run: Run, _ status: RunStatus) { self.run = run; self.status = status }
    func observe(_ system: PlateSystem, _ params: Parameters, _ time: Int, _ field: [Double]) {
        let hottest = hottestCell(field), temperature = field[hottest]
        if peak == nil || temperature > peak!.temperature { peak = Peak(temperature: temperature, time: time, cell: hottest) }
        if temperature >= params.alarm { if alarm == nil { alarm = Alarm(time: time, cell: hottest) }; if time > 0 { above += run.step } }
        if time % params.probeEvery == 0 { probeSamples.append(ProbeSample(time: time, values: params.probes.map { field[$0.cell] })) }
        if params.snapshotTimes.contains(time) { snapshots[time] = FieldSnapshot(field: field, stored: storedHeat(system, field, params.initial), boundary: orderedSum(segmentEnergy), generated: generated) }
    }
}
func simulateRun(_ run: Run, _ system: PlateSystem, _ params: Parameters) -> RunResult {
    let result = RunResult(run, .accepted)
    result.steps = params.endTime / run.step; result.segmentEnergy = Array(repeating: 0, count: system.segments.count)
    var field = Array(repeating: params.initial, count: system.mesh.count)
    result.observe(system, params, 0, field)
    for step in 0..<result.steps {
        let sources = sourceTerms(system.sources, system.mesh.count, step * run.step), updated = advance(run.method, system, field, sources.field, run.dt)
        for (j, segment) in system.segments.enumerated() { result.segmentEnergy[j] += stepBoundaryEnergy(system, segment, run, field, updated.field, updated.intermediate) }
        result.generated += run.dt * sources.power; field = updated.field; result.observe(system, params, (step + 1) * run.step, field)
    }
    result.finalField = field; result.stored = storedHeat(system, field, params.initial); result.boundary = orderedSum(result.segmentEnergy)
    result.balance = abs(result.stored - result.boundary - result.generated) <= 0.000001 * (abs(result.stored) + abs(result.boundary) + abs(result.generated))
    return result
}
struct SteadySolution { let rhs: [Double]; let field: [Double]; let base: [Double]; let responses: [[Double]] }
func solveSteady(_ system: PlateSystem) -> SteadySolution {
    let rhs = system.beta.indices.map { system.beta[$0] + system.sourceAll[$0] }
    var vectors = [rhs, system.beta]
    for source in system.sources { var vector = Array(repeating: 0.0, count: system.mesh.count); let value = 1 / Double(source.cells.count); for point in source.cells { vector[point] = value }; vectors.append(vector) }
    let fields = bandSolve(system, vectors)
    return SteadySolution(rhs: rhs, field: fields[0], base: fields[1], responses: Array(fields.dropFirst(2)))
}
struct SolverAnalysis { let result: IterationResult; let milestones: [String]; let error: Double; let residual: Double }
func runIterativeMethods(_ system: PlateSystem, _ params: Parameters, _ solution: SteadySolution) -> (analyses: [SolverAnalysis], rho: Double, omega: Double) {
    let jacobi = iterate(system, params.initial, params.tolerance, params.maximumIterations, .jacobi), rho = jacobi.rate, omega = 2 / (1 + sqrt(1 - rho * rho))
    var results = [jacobi]
    for method in SolverMethod.allCases.dropFirst() { results.append(iterate(system, params.initial, params.tolerance, params.maximumIterations, method, method == .estimated ? omega : params.omega)) }
    let analyses = results.map { result -> SolverAnalysis in
        let milestones = [1000.0, 100, 10, 1].map { factor in result.changes.firstIndex { $0 < params.tolerance * factor }.map { String($0 + 1) } ?? "never" }, error = result.field.indices.map { abs(result.field[$0] - solution.field[$0]) }.max()!
        return SolverAnalysis(result: result, milestones: milestones, error: error, residual: maximumResidual(system, result.field, solution.rhs))
    }
    return (analyses, rho, omega)
}

struct MaterialPair: Hashable, Comparable { let first: Int; let second: Int; static func < (a: MaterialPair, b: MaterialPair) -> Bool { a.first == b.first ? a.second < b.second : a.first < b.first } }
struct InterfaceFlow { var faces = 0; var forward = 0.0; var backward = 0.0 }
func interfaceLines(_ system: PlateSystem, _ field: [Double]) -> [String] {
    var pairs: [MaterialPair: InterfaceFlow] = [:]
    for point in field.indices {
        for direction in [1, 3] {
            let face = system.faces[point][direction]
            guard let neighbor = face.neighbor else { continue }
            let a = system.cellMaterial[point], b = system.cellMaterial[neighbor]
            if a == b { continue }
            let key = MaterialPair(first: min(a, b), second: max(a, b)), value = face.conductance * (field[point] - field[neighbor]), flow = a < b ? value : -value
            pairs[key, default: InterfaceFlow()].faces += 1
            if flow > 0 { pairs[key, default: InterfaceFlow()].forward += flow } else if flow < 0 { pairs[key, default: InterfaceFlow()].backward += abs(flow) }
        }
    }
    return pairs.keys.sorted().map { key in let value = pairs[key]!; return "interface \(system.materials[key.first].code) \(system.materials[key.second].code) faces \(value.faces) forward \(real(value.forward, 4)) backward \(real(value.backward, 4))" }
}
func maximumGradient(_ system: PlateSystem, _ field: [Double]) -> (value: Double, point: Int, neighbor: Int) {
    var maximum = -1.0, selected = (0, 0)
    for point in field.indices { for direction in [1, 3] { if let neighbor = system.faces[point][direction].neighbor { let gradient = abs(field[point] - field[neighbor]) / system.mesh.dx; if gradient > maximum { maximum = gradient; selected = (point, neighbor) } } } }
    return (maximum, selected.0, selected.1)
}
func steadyStateLines(_ system: PlateSystem, _ params: Parameters, _ solution: SteadySolution, _ iterative: [SolverAnalysis]) -> [String] {
    let field = solution.field, mesh = system.mesh, responses = solution.responses, duties = system.sources.map { $0.dutyRatio(params.endTime) }
    var lines = [fieldSummary("steady", mesh, field)] + temperatureLines(mesh, field)
    for (i, material) in system.materials.enumerated() { let cells = system.materialCells[i], values = cells.map { field[$0] }; lines.append("material \(material.code) \(material.name) cells \(cells.count) min \(real(values.min()!, 2)) max \(real(values.max()!, 2)) mean \(real(orderedSum(values) / Double(cells.count), 2))") }
    for (i, source) in system.sources.enumerated() { let values = source.cells.map { field[$0] }; lines.append("source \(source.name) power \(real(source.power, 4)) duty \(real(duties[i], 4)) mean \(real(orderedSum(values) / Double(source.cells.count), 2)) max \(real(values.max()!, 2))") }
    for source in system.sources { for j in system.sources.indices { let coefficient = orderedSum(source.cells.map { responses[j][$0] }) / Double(source.cells.count); lines.append("influence \(source.name) \(system.sources[j].name) \(real(coefficient, 4))") } }
    var maximumError = 0.0, dutyField: [Double] = []
    for point in field.indices {
        var full = solution.base[point], average = full
        for j in system.sources.indices { full += system.sources[j].power * responses[j][point]; average += (duties[j] * system.sources[j].power) * responses[j][point] }
        maximumError = max(maximumError, abs(full - field[point])); dutyField.append(average)
    }
    lines.append("superposition \(maximumError <= 0.000001 ? "ok" : "failed")")
    for (i, source) in system.sources.enumerated() {
        for segment in system.segments {
            let value = segment.kind == .insulated ? 0 : orderedSum(segment.faces.map { system.faces[$0.cell][$0.face].conductance * responses[i][$0.cell] })
            lines.append("path \(source.name) \(segment.name) \(real(value, 4))")
        }
    }
    lines.append(fieldSummary("duty_steady", mesh, dutyField))
    for (i, source) in system.sources.enumerated() {
        var minimum: Double?, selected = 0
        for point in field.indices { let power = (params.limit - (field[point] - source.power * responses[i][point])) / responses[i][point]; if minimum == nil || power < minimum! { minimum = power; selected = point } }
        lines.append("headroom \(source.name) max_power \(real(minimum!, 4)) at \(mesh.coordinates(selected))")
    }
    lines += interfaceLines(system, field)
    var flows: [Double] = []
    for segment in system.segments { let flow = segmentFlow(system, segment, field); flows.append(flow); lines.append("segment \(segment.name) \(segment.edge.rawValue) \(segment.kind.rawValue) flow \(real(flow, 4))") }
    let balanced = abs(orderedSum(flows) + system.totalPower) <= 0.000001 * (orderedSum(flows.map { abs($0) }) + system.totalPower), gradient = maximumGradient(system, field)
    lines += ["sources \(real(system.totalPower, 4))", "balance \(balanced ? "ok" : "failed")", "max_gradient \(real(gradient.value, 2)) between \(mesh.coordinates(gradient.point)) and \(mesh.coordinates(gradient.neighbor))"]
    for analysis in iterative {
        let result = analysis.result, omega = result.method == .sor || result.method == .estimated ? " omega \(real(result.omega, 4))" : ""
        lines.append("solver \(result.method.rawValue)\(omega) iterations \(result.count) converged \(result.converged ? "yes" : "no") rate \(real(result.rate, 6)) milestones \(analysis.milestones.joined(separator: " "))")
    }
    return lines
}
func rejectedRunLine(_ result: RunResult, _ maximum: Double? = nil) -> String {
    var line = "run \(result.run.name) \(result.run.method.rawValue) dt \(timeText(result.run.step)) rejected \(result.status.rawValue)"
    if result.status == .unstable, let maximum { line += " max_dt \(real(maximum, 4))" }
    return line
}
func snapshotLines(_ system: PlateSystem, _ params: Parameters, _ results: [RunResult]) -> [String] {
    var lines: [String] = []
    for result in results {
        if result.status != .accepted { lines.append(rejectedRunLine(result, system.maximumStep)); continue }
        for time in params.snapshotTimes { let field = result.snapshots[time]!.field, prefix = "run \(result.run.name) \(result.run.method.rawValue) dt \(timeText(result.run.step)) time \(timeText(time))"; lines.append(fieldSummary(prefix, system.mesh, field)); lines += temperatureLines(system.mesh, field) }
    }
    return lines
}
func probeLines(_ params: Parameters, _ results: [RunResult]) -> [String] {
    var lines = ["run,time,probe,temperature"]
    for result in results where result.status == .accepted { for sample in result.probeSamples { for (i, probe) in params.probes.enumerated() { lines.append("\(result.run.name),\(timeText(sample.time)),\(probe.name),\(real(sample.values[i], 3))") } } }
    return lines
}
func probeSummaryLines(_ params: Parameters, _ result: RunResult) -> [String] {
    params.probes.enumerated().map { i, probe in
        let first = result.probeSamples[0]
        var maximum = first.values[i], minimum = maximum, maximumTime = first.time, minimumTime = first.time
        for sample in result.probeSamples.dropFirst() { if sample.values[i] > maximum { maximum = sample.values[i]; maximumTime = sample.time }; if sample.values[i] < minimum { minimum = sample.values[i]; minimumTime = sample.time } }
        return "probe_summary \(result.run.name) \(probe.name) max \(real(maximum, 3)) time \(timeText(maximumTime)) min \(real(minimum, 3)) time \(timeText(minimumTime))"
    }
}
func energyLines(_ system: PlateSystem, _ params: Parameters, _ result: RunResult) -> [String] {
    let name = result.run.name
    var lines = ["energy \(name) stored \(real(result.stored, 2)) boundary \(real(result.boundary, 2)) source \(real(result.generated, 2)) balance \(result.balance ? "ok" : "failed")"]
    for time in params.snapshotTimes { let snapshot = result.snapshots[time]!; lines.append("energy_at \(name) time \(timeText(time)) stored \(real(snapshot.stored, 2)) boundary \(real(snapshot.boundary, 2)) source \(real(snapshot.generated, 2))") }
    for (i, material) in system.materials.enumerated() { lines.append("energy_material \(name) \(material.code) \(real(storedHeat(system, result.finalField, params.initial, system.materialCells[i]), 2))") }
    for (i, segment) in system.segments.enumerated() { lines.append("energy_segment \(name) \(segment.name) \(real(result.segmentEnergy[i], 2))") }
    return lines
}
func comparisonLines(_ system: PlateSystem, _ params: Parameters, _ results: [RunResult], _ reference: RunResult, _ solution: SteadySolution, _ iterative: [SolverAnalysis], _ rho: Double, _ omega: Double) -> [String] {
    var lines = ["ftcs_max_dt \(real(system.maximumStep, 4))"]
    for result in results {
        if result.status != .accepted { lines.append(rejectedRunLine(result)); continue }
        let run = result.run, peak = result.peak!, alarm = result.alarm.map { "\(timeText($0.time)) at \(system.mesh.coordinates($0.cell))" } ?? "never"
        lines.append("run \(run.name) \(run.method.rawValue) dt \(timeText(run.step)) steps \(result.steps) peak \(real(peak.temperature, 2)) time \(timeText(peak.time)) at \(system.mesh.coordinates(peak.cell)) alarm \(alarm) above \(timeText(result.above))")
        lines += energyLines(system, params, result) + probeSummaryLines(params, result)
        if run.name != reference.run.name {
            for time in params.snapshotTimes {
                let field = result.snapshots[time]!.field, other = reference.snapshots[time]!.field, errors = field.indices.map { abs(field[$0] - other[$0]) }, rms = sqrt(orderedSum(errors.map { $0 * $0 }) / Double(field.count))
                lines.append("compare \(run.name) \(reference.run.name) time \(timeText(time)) max_diff \(real(errors.max()!, 6)) rms_diff \(real(rms, 6))")
            }
        }
        let difference = result.finalField.indices.map { abs(result.finalField[$0] - solution.field[$0]) }.max()!
        lines.append("final \(run.name) steady_max_diff \(real(difference, 6))")
    }
    lines.append("steady direct max_residual \(real(maximumResidual(system, solution.field, solution.rhs), 6))")
    for analysis in iterative { lines.append("steady \(analysis.result.method.rawValue) iterations \(analysis.result.count) max_diff \(real(analysis.error, 6)) max_residual \(real(analysis.residual, 6))") }
    lines += ["jacobi_spectral_radius \(real(rho, 6)) squared \(real(rho * rho, 6))", "omega_estimated \(real(omega, 4))"]
    return lines
}
func isothermOutput(_ system: PlateSystem, _ params: Parameters, _ solution: SteadySolution, _ reference: RunResult) -> [String] {
    let steady = isothermLines(system.mesh, solution.field, params.bands)
    var lines = ["isotherms steady counts " + steady.counts.map(String.init).joined(separator: " ")] + steady.lines
    for time in params.snapshotTimes { let map = isothermLines(system.mesh, reference.snapshots[time]!.field, params.bands); lines += ["isotherms \(reference.run.name) time \(timeText(time)) counts " + map.counts.map(String.init).joined(separator: " ")] + map.lines }
    return lines
}

let mesh = try readPlate(), materials = try readMaterials(), boundary = try readBoundary(mesh), params = try readParameters(mesh)
let system = PlateSystem(mesh, materials, boundary.segments, boundary.sources), solution = solveSteady(system), iterative = runIterativeMethods(system, params, solution)
let results = params.runs.map { run -> RunResult in let status = runStatus(run, system, params); return status == .accepted ? simulateRun(run, system, params) : RunResult(run, status) }
let reference = results.first { $0.run.name == params.reference }!
try writeLines("snapshots.txt", snapshotLines(system, params, results))
try writeLines("probes.csv", probeLines(params, results))
try writeLines("steady_state.txt", steadyStateLines(system, params, solution, iterative.analyses))
try writeLines("solver_comparison.txt", comparisonLines(system, params, results, reference, solution, iterative.analyses, iterative.rho, iterative.omega))
try writeLines("isotherms.txt", isothermOutput(system, params, solution, reference))
