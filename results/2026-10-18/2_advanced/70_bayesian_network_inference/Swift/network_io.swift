import Foundation

struct Network { let names: [String]; let states: [[String]]; let parents: [[Int]]; let expert: [Int: [[Double]]] }
enum EliminationMethod: String { case minfill = "MINFILL", given = "GIVEN" }
struct Settings { let alpha: Double; let method: EliminationMethod; let order: [Int]; let limit: Int; let seed: Int64; let sources: [String] }
struct Inputs { let network: Network; let samples: [[Int]]; let queries: [String]; let settings: Settings }
func inputLines(_ name: String) throws -> [String] { try String(contentsOfFile: "input/" + name, encoding: .ascii).split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(String.init) }
func lineFields(_ line: String) -> [String] { line.split(separator: " ").map(String.init) }
func readInputs() throws -> Inputs {
    let lines = try inputLines("network.txt").filter { !$0.isEmpty && $0.first != "#" }
    var names: [String] = [], states: [[String]] = [], parents: [[Int]] = [], expert: [Int: [[Double]]] = [:], numbers: [String: Int] = [:], position = 0
    while position < lines.count { let parts = lineFields(lines[position]); position += 1; switch parts[0] { case "VARIABLE": numbers[parts[1]] = names.count; names.append(parts[1]); states.append(Array(parts.dropFirst(2))); parents.append([]); case "PARENTS": parents[numbers[parts[1]]!] = parts.dropFirst(2).map { numbers[$0]! }; default: let variable = numbers[parts[1]]!, rows = parents[variable].reduce(1) { $0 * states[$1].count }; expert[variable] = lines[position..<(position + rows)].map { lineFields($0).map { Double($0)! } }; position += rows } }
    let network = Network(names: names, states: states, parents: parents, expert: expert), sampleLines = try inputLines("samples.csv"), columns = sampleLines[0].split(separator: ",").map { numbers[String($0)]! }
    var samples: [[Int]] = []
    for line in sampleLines.dropFirst() { var sample = Array(repeating: 0, count: names.count); for (variable, value) in zip(columns, line.split(separator: ",")) { sample[variable] = states[variable].firstIndex(of: String(value))! }; samples.append(sample) }
    let parameters = try inputLines("params.txt").map(lineFields), settings = Settings(alpha: Double(parameters[0][1])!, method: EliminationMethod(rawValue: parameters[1][1])!, order: parameters[2].dropFirst().map { numbers[$0]! }, limit: Int(parameters[3][1])!, seed: Int64(parameters[4][1])!, sources: parameters.dropFirst(5).map { $0[2] })
    return Inputs(network: network, samples: samples, queries: try inputLines("queries.txt"), settings: settings)
}
