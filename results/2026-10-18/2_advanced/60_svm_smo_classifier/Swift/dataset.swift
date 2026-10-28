import Foundation

struct Point { let x: Double; let y: Double }
struct Example { let id: String; let point: Point; let label: Int }
struct MulticlassExample { let id: String; let point: Point; let classNumber: Int }
struct PegasosParameters { let regularization: Double; let iterations: Int; let seed: Int }
struct Settings {
    var coefficients: [Double] = []
    var kernels: [Kernel] = []
    var tolerance = 0.0
    var epsilon = 0.0
    var maximumPasses = 0
    var foldCount = 0
    var learningPercentages: [Int] = []
    var newtonIterations = 0
    var multiclassName = ""
    var multiclassCoefficient = 0.0
    var pegasos = PegasosParameters(regularization: 0, iterations: 0, seed: 0)
    var xmin = 0.0
    var xmax = 0.0
    var ymin = 0.0
    var ymax = 0.0
    var width = 0
    var height = 0
}
struct Inputs { let training: [Example]; let testing: [Example]; let multiTraining: [MulticlassExample]; let multiTesting: [MulticlassExample]; let settings: Settings }
func readLines(_ name: String) throws -> [String] { try String(contentsOfFile: "input/" + name, encoding: .ascii).split(separator: "\n").map(String.init) }
func readBinary(_ name: String) throws -> [Example] { try readLines(name).dropFirst().map { line in let fields = line.components(separatedBy: ","); return Example(id: fields[0], point: Point(x: Double(fields[1])!, y: Double(fields[2])!), label: Int(fields[3])!) } }
func readSettings() throws -> Settings {
    var settings = Settings()
    for line in try readLines("params.txt") {
        let fields = line.components(separatedBy: " ")
        switch fields[0] {
        case "C_GRID": settings.coefficients = fields.dropFirst().map { Double($0)! }
        case "KERNEL":
            let kind: KernelKind
            if fields[2] == "linear" { kind = .linear }
            else if fields[2] == "poly" { kind = .polynomial(Int(fields[3])!, Double(fields[4])!, Double(fields[5])!) }
            else { kind = .rbf(Double(fields[3])!) }
            settings.kernels.append(Kernel(name: fields[1], kind: kind))
        case "TOLERANCE": settings.tolerance = Double(fields[1])!
        case "EPS": settings.epsilon = Double(fields[1])!
        case "MAX_PASSES": settings.maximumPasses = Int(fields[1])!
        case "FOLDS": settings.foldCount = Int(fields[1])!
        case "LEARNING_CURVE": settings.learningPercentages = fields.dropFirst().map { Int($0)! }
        case "NEWTON_ITERATIONS": settings.newtonIterations = Int(fields[1])!
        case "MULTICLASS": settings.multiclassName = fields[1]; settings.multiclassCoefficient = Double(fields[2])!
        case "PEGASOS": settings.pegasos = PegasosParameters(regularization: Double(fields[1])!, iterations: Int(fields[2])!, seed: Int(fields[3])!)
        case "PLOT_X": settings.xmin = Double(fields[1])!; settings.xmax = Double(fields[2])!
        case "PLOT_Y": settings.ymin = Double(fields[1])!; settings.ymax = Double(fields[2])!
        default: settings.width = Int(fields[1])!; settings.height = Int(fields[2])!
        }
    }
    return settings
}
func readInputs() throws -> Inputs {
    let training = try readBinary("train.csv"), testing = try readBinary("test.csv")
    var multiTraining: [MulticlassExample] = [], multiTesting: [MulticlassExample] = []
    for line in try readLines("multiclass.csv").dropFirst() { let fields = line.components(separatedBy: ","), example = MulticlassExample(id: fields[0], point: Point(x: Double(fields[1])!, y: Double(fields[2])!), classNumber: Int(fields[3])!); if fields[4] == "train" { multiTraining.append(example) } else { multiTesting.append(example) } }
    return try Inputs(training: training, testing: testing, multiTraining: multiTraining, multiTesting: multiTesting, settings: readSettings())
}
