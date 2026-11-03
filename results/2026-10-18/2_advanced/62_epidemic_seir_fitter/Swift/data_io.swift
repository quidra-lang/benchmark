import Foundation

struct AgeGroup { let name: String; let population: Int; let fatality: Double }
struct Intervention { var day: Int; var multiplier: Double }
struct Grid { let minimum: Double; let maximum: Double; let count: Int }
struct Scenario { let name: String; let multiplier: Double }
struct ContactChange { let name: String; let group: String; let factor: Double }
struct SimplexSettings { let beta: Double; let gamma: Double }
struct NelderMeadSettings { let alpha: Double; let chi: Double; let psi: Double; let omega: Double; let iterations: Int }
struct Settings {
    var sigma = 0.0
    var gamma = 0.0
    var exposed = 0.0
    var infectious = 0.0
    var betaGrid = Grid(minimum: 0, maximum: 0, count: 0)
    var rhoGrid = Grid(minimum: 0, maximum: 0, count: 0)
    var goldenIterations = 0
    var goldenRounds = 0
    var simplex = SimplexSettings(beta: 0, gamma: 0)
    var nelderMead = NelderMeadSettings(alpha: 0, chi: 0, psi: 0, omega: 0, iterations: 0)
    var holdout = 0
    var effectWidth = 0.0
    var outlier = 0.0
    var deathLag = 0
    var milestones: [Int] = []
    var generation = 0
    var horizon = 0
    var threshold = 0.0
    var scenarios: [Scenario] = []
    var contactChanges: [ContactChange] = []
}
struct Inputs { let cases: [Int]; let deaths: [Int]; let groups: [AgeGroup]; let contacts: [[Double]]; let interventions: [Intervention]; let settings: Settings }
func inputLines(_ name: String) throws -> [String] { try String(contentsOfFile: "input/" + name, encoding: .ascii).split(separator: "\n").map(String.init) }
func readInputs() throws -> Inputs {
    var cases: [Int] = [], deaths: [Int] = [], groups: [AgeGroup] = [], contacts: [[Double]] = [], interventions: [Intervention] = [], settings = Settings()
    for line in try inputLines("cases.csv").dropFirst() { let fields = line.split(separator: ","); cases.append(Int(fields[1])!); deaths.append(Int(fields[2])!) }
    for line in try inputLines("population.txt") { let fields = line.split(separator: " "); if fields[0] == "group" { groups.append(AgeGroup(name: String(fields[1]), population: Int(fields[2])!, fatality: Double(fields[3])!)) } else { contacts.append(fields.dropFirst().map { Double($0)! }) } }
    for line in try inputLines("interventions.txt") { let fields = line.split(separator: " "); interventions.append(Intervention(day: Int(fields[0])!, multiplier: Double(fields[1])!)) }
    for line in try inputLines("params.txt") {
        let fields = line.split(separator: " ").map(String.init)
        switch fields[0] {
        case "sigma": settings.sigma = Double(fields[1])!
        case "gamma": settings.gamma = Double(fields[1])!
        case "initial": settings.exposed = Double(fields[1])!; settings.infectious = Double(fields[2])!
        case "beta_grid": settings.betaGrid = Grid(minimum: Double(fields[1])!, maximum: Double(fields[2])!, count: Int(fields[3])!)
        case "rho_grid": settings.rhoGrid = Grid(minimum: Double(fields[1])!, maximum: Double(fields[2])!, count: Int(fields[3])!)
        case "golden": settings.goldenIterations = Int(fields[1])!; settings.goldenRounds = Int(fields[2])!
        case "simplex": settings.simplex = SimplexSettings(beta: Double(fields[1])!, gamma: Double(fields[2])!)
        case "nelder_mead": settings.nelderMead = NelderMeadSettings(alpha: Double(fields[1])!, chi: Double(fields[2])!, psi: Double(fields[3])!, omega: Double(fields[4])!, iterations: Int(fields[5])!)
        case "holdout": settings.holdout = Int(fields[1])!
        case "effect_width": settings.effectWidth = Double(fields[1])!
        case "outlier": settings.outlier = Double(fields[1])!
        case "death_lag": settings.deathLag = Int(fields[1])!
        case "milestones": settings.milestones = fields.dropFirst().map { Int($0)! }
        case "generation": settings.generation = Int(fields[1])!
        case "horizon": settings.horizon = Int(fields[1])!
        case "threshold": settings.threshold = Double(fields[1])!
        case "scenario": settings.scenarios.append(Scenario(name: fields[1], multiplier: Double(fields[2])!))
        default: settings.contactChanges.append(ContactChange(name: fields[1], group: fields[2], factor: Double(fields[3])!))
        }
    }
    return Inputs(cases: cases, deaths: deaths, groups: groups, contacts: contacts, interventions: interventions, settings: settings)
}
func writeOutputs(_ outputs: [(String, [String])]) throws { try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true); for (name, lines) in outputs { try (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: false, encoding: .ascii) } }
