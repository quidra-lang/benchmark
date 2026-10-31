import Foundation

struct Annotation {
    let sample: Int
    let label: String
    var beat: Int?
}

func readLines(_ path: String) throws -> [String] {
    var lines = try String(contentsOfFile: path, encoding: .ascii).components(separatedBy: "\n")
    if lines.last == "" { lines.removeLast() }
    return lines
}

func readECG() throws -> [Int] {
    try readLines("input/ecg.csv").dropFirst().map { Int($0.split(separator: ",")[1])! }
}

func readAnnotations() throws -> [Annotation] {
    try readLines("input/annotations.csv").dropFirst().map { line in
        let parts = line.split(separator: ",")
        return Annotation(sample: Int(parts[0])!, label: String(parts[1]))
    }
}

func readParameters() throws -> [String: Int] {
    var parameters: [String: Int] = [:]
    for line in try readLines("input/params.txt") {
        let parts = line.split(separator: " ")
        parameters[String(parts[0])] = Int(parts[1])!
    }
    return parameters
}

func writeLines(_ filename: String, _ lines: [String]) throws {
    try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    let text = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    try text.write(toFile: "output/" + filename, atomically: true, encoding: .ascii)
}
