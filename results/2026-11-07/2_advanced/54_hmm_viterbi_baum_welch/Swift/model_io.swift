import Foundation

func normalize(_ values: [Double]) -> [Double] { let sum = values.reduce(0, +); return values.map { $0 / sum } }
struct Model {
    let name: String
    let states: [String]
    let symbols: [String]
    let missing: String
    let initial: [Double]
    let transition: [[Double]]
    let emission: [[Double]]
    var count: Int { states.count }
    init(_ name: String, _ states: [String], _ symbols: [String], _ missing: String, _ initial: [Double], _ transition: [[Double]], _ emission: [[Double]]) {
        self.name = name; self.states = states; self.symbols = symbols; self.missing = missing
        self.initial = normalize(initial); self.transition = transition.map { normalize($0) }; self.emission = emission.map { normalize($0) }
    }
}
struct RawInputs { let model: Model; let sequences: [[String]]; let labeled: [[String]]; let parameters: [[String]] }
func readTokens(_ name: String) throws -> [[String]] { try String(contentsOfFile: "input/" + name, encoding: .ascii).split(separator: "\n").map { $0.components(separatedBy: " ") } }
func readInputs() throws -> RawInputs {
    let rows = try readTokens("model.txt"), states = Array(rows[0].dropFirst()), symbols = Array(rows[1].dropFirst()), count = states.count
    let model = Model("INITIAL", states, symbols, rows[2][1], rows[3].dropFirst().map { Double($0)! }, rows[4..<(4 + count)].map { $0.dropFirst(2).map { Double($0)! } }, rows[(4 + count)..<(4 + 2 * count)].map { $0.dropFirst(2).map { Double($0)! } })
    return try RawInputs(model: model, sequences: readTokens("sequences.txt"), labeled: readTokens("labeled.txt"), parameters: readTokens("params.txt"))
}
func real(_ value: Double?, _ places: Int = 4) -> String {
    guard let value else { return "-" }
    let text = String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), places, value)
    return text.first == "-" && Double(text) == 0 ? String(text.dropFirst()) : text
}
func modelLines(_ model: Model) -> [String] {
    var lines = ["MODEL " + model.name, "STATES " + model.states.joined(separator: " "), "SYMBOLS " + model.symbols.joined(separator: " "), "MISSING " + model.missing, "INITIAL " + model.initial.map { real($0) }.joined(separator: " ")]
    for i in 0..<model.count { lines.append("TRANSITION " + model.states[i] + " " + model.transition[i].map { real($0) }.joined(separator: " ")) }
    for i in 0..<model.count { lines.append("EMISSION " + model.states[i] + " " + model.emission[i].map { real($0) }.joined(separator: " ")) }
    return lines
}
func writeLines(_ name: String, _ lines: [String]) throws {
    try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    try (lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: false, encoding: .ascii)
}
