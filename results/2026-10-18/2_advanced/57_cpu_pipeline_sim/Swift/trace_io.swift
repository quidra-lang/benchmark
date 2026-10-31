import Foundation

enum InstructionClass: String, CaseIterable { case alu = "ALU", multiply = "MUL", load = "LOAD", store = "STORE", branch = "BRANCH", jump = "JUMP", nop = "NOP" }
struct Instruction {
    let number: Int
    let line: Int
    let pc: Int
    let kind: InstructionClass
    let destination: Int?
    let firstSource: Int?
    let secondSource: Int?
    let taken: Bool
    let target: Int?
    let address: Int?
    var control: Bool { kind == .branch || kind == .jump }
    var nextPC: Int { taken ? target! : pc + 4 }
}
struct PredictorDefinition { let name: String; let scheme: String; let parameters: [Int] }
struct Variant { let name: String; let forwarding: Bool; let stage: String; let latency: Int }
struct Configuration {
    var btb = 0
    var ras = 0
    var predictors: [PredictorDefinition] = []
    var variants: [Variant] = []
    var primaryVariant = ""
    var primaryPredictor = ""
    var firstCycle = 0
    var lastCycle = 0
    var top = 0
    var interval = 0
}
func parseHex(_ text: String) -> Int? {
    let bytes = Array(text.utf8)
    return bytes.count == 8 && bytes.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) ? Int(text, radix: 16) : nil
}
func parseRegister(_ text: String) -> Int? {
    let bytes = Array(text.utf8)
    guard (2...3).contains(bytes.count), bytes[0] == 114, bytes.dropFirst().allSatisfy({ (48...57).contains($0) }), let value = Int(text.dropFirst()), value <= 31, text == "r\(value)" else { return nil }
    return value
}
func readLines(_ name: String) throws -> [String] { try String(contentsOfFile: "input/" + name, encoding: .ascii).components(separatedBy: "\n").dropLast().map { $0 } }
func readInputs() throws -> (trace: [String], config: Configuration) {
    var config = Configuration()
    for line in try readLines("config.txt") {
        let words = line.components(separatedBy: " ")
        switch words[0] {
        case "BTB": config.btb = Int(words[1])!
        case "RAS": config.ras = Int(words[1])!
        case "TOP": config.top = Int(words[1])!
        case "INTERVAL": config.interval = Int(words[1])!
        case "PREDICTOR": config.predictors.append(PredictorDefinition(name: words[1], scheme: words[2], parameters: words.dropFirst(3).map { Int($0)! }))
        case "VARIANT": config.variants.append(Variant(name: words[1], forwarding: words[2] == "ON", stage: words[3], latency: Int(words[4])!))
        case "PRIMARY": config.primaryVariant = words[1]; config.primaryPredictor = words[2]
        default: config.firstCycle = Int(words[1])!; config.lastCycle = Int(words[2])!
        }
    }
    return try (readLines("trace.txt"), config)
}
