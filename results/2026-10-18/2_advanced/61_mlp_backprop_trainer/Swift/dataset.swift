import Foundation

struct Image { let id: String; let label: Int; let pixels: [UInt8]; var vector: [Double] }
enum OptimizerKind { case sgd, momentum(Double), adam(Double, Double, Double)
    var name: String { switch self { case .sgd: return "SGD"; case .momentum: return "MOMENTUM"; case .adam: return "ADAM" } }
}
struct RunDefinition { let name: String; let networkName: String; let optimizer: OptimizerKind; let rate: Double; let decay: Double }
struct Settings {
    var seed = 0
    var batchSize = 0
    var maximumEpochs = 0
    var patience = 0
    var rateStep = 0
    var rateGamma = 0.0
    var gradientStride = 0
    var calibrationBins = 0
    var pruning: [Int] = []
    var noise: [Int] = []
    var runs: [RunDefinition] = []
}
struct Inputs { let images: [Image]; let testing: [Image]; let networks: [Network]; let settings: Settings }
struct MINSTD {
    var state: Int
    mutating func draw() -> Int { state = 48271 * state % 2147483647; return state }
    mutating func shuffle(_ values: inout [Int]) { if values.count >= 2 { for size in stride(from: values.count, through: 2, by: -1) { let index = draw() % size; values.swapAt(size - 1, index) } } }
}
func inputText(_ name: String) throws -> String { try String(contentsOfFile: "input/" + name, encoding: .ascii) }
func readImages(_ name: String) throws -> [Image] { try inputText(name).split(separator: "\n").dropFirst().map { line in let fields = line.split(separator: ","), pixels = Array(fields[2].utf8); return Image(id: String(fields[0]), label: Int(fields[1])!, pixels: pixels, vector: pixels.map { $0 == 49 ? 1 : 0 }) } }
func readSettings() throws -> Settings {
    var settings = Settings()
    for line in try inputText("params.txt").split(separator: "\n") {
        let fields = line.split(separator: " ").map(String.init)
        switch fields[0] {
        case "SEED": settings.seed = Int(fields[1])!
        case "BATCH_SIZE": settings.batchSize = Int(fields[1])!
        case "MAX_EPOCHS": settings.maximumEpochs = Int(fields[1])!
        case "PATIENCE": settings.patience = Int(fields[1])!
        case "LR_STEP": settings.rateStep = Int(fields[1])!; settings.rateGamma = Double(fields[2])!
        case "GRADIENT_CHECK_STRIDE": settings.gradientStride = Int(fields[1])!
        case "CALIBRATION_BINS": settings.calibrationBins = Int(fields[1])!
        case "PRUNE": settings.pruning = fields.dropFirst().map { Int($0)! }
        case "NOISE": settings.noise = fields.dropFirst().map { Int($0)! }
        default:
            let optimizer: OptimizerKind
            if fields[3] == "SGD" { optimizer = .sgd } else if fields[3] == "MOMENTUM" { optimizer = .momentum(Double(fields[6])!) } else { optimizer = .adam(Double(fields[6])!, Double(fields[7])!, Double(fields[8])!) }
            settings.runs.append(RunDefinition(name: fields[1], networkName: fields[2], optimizer: optimizer, rate: Double(fields[4])!, decay: Double(fields[5])!))
        }
    }
    return settings
}
func readInputs() throws -> Inputs {
    let blocks = try inputText("network.txt").trimmingCharacters(in: .newlines).components(separatedBy: "\n\n"), dimensions = blocks[0].split(separator: " "), width = Int(dimensions[1])!, height = Int(dimensions[2])!, weightBlocks = try inputText("weights.txt").trimmingCharacters(in: .newlines).components(separatedBy: "\n\n")
    var networks: [Network] = []
    for (index, block) in blocks.dropFirst().enumerated() {
        let lines = block.split(separator: "\n"), name = String(lines[0].split(separator: " ")[1]), definitions = lines.dropFirst().map { line -> LayerDefinition in let fields = line.split(separator: " "); return LayerDefinition(units: Int(fields[1])!, activation: Activation(rawValue: String(fields[2]))!) }
        var initial: [Double] = []
        for line in weightBlocks[index].split(separator: "\n") { let fields = line.split(separator: " "); if fields[0] == "W" || fields[0] == "B" { initial += fields.dropFirst().map { Double($0)! } } }
        networks.append(Network(name: name, width: width, height: height, definitions: definitions, initial: initial))
    }
    return try Inputs(images: readImages("train.csv"), testing: readImages("test.csv"), networks: networks, settings: readSettings())
}
