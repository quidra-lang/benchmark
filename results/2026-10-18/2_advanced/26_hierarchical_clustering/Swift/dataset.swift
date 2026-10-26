import Foundation

struct Observation {
    let id: String
    let label: String
    let values: [Double]
}

struct Settings {
    let distance: DistanceKind
    let standardize: Bool
    let linkages: [Linkage]
    let cutHeights: [Double]
    let cutCounts: [Int]
    let inconsistencyDepth: Int
    let inconsistencyDepthText: String
    let inconsistencyCount: Int
    let gapMaxK: Int
    let listSize: Int
    let width: Int
    let compareLinkage: Linkage
    let replicates: Int
    let percent: Int
    let seed: Int
    let refineIterations: Int

    init(_ rows: [[String]]) {
        distance = DistanceKind(rawValue: rows[0][0])!
        standardize = rows[1][0] == "yes"
        linkages = rows[2].map { Linkage(rawValue: $0)! }
        cutHeights = rows[3].map { Double($0)! }
        cutCounts = rows[4].map { Int($0)! }
        inconsistencyDepth = rows[5][0].utf8.reduce(0) { min(120, $0 * 10 + Int($1 - 48)) }
        inconsistencyDepthText = rows[5][0]
        inconsistencyCount = Int(rows[5][1])!
        gapMaxK = Int(rows[6][0])!
        listSize = Int(rows[7][0])!
        width = Int(rows[8][0])!
        compareLinkage = Linkage(rawValue: rows[9][0])!
        replicates = Int(rows[10][0])!
        percent = Int(rows[10][1])!
        seed = Int(rows[10][2])!
        refineIterations = Int(rows[11][0])!
    }
}

func readInputLines(_ name: String) throws -> [String] {
    try String(contentsOfFile: "input/" + name, encoding: .ascii).split(separator: "\n").map(String.init)
}

func readObservations() throws -> ([String], [Observation]) {
    let lines = try readInputLines("data.csv")
    let names = lines[0].split(separator: ",").dropFirst(2).map(String.init)
    let observations = lines.dropFirst().map { line -> Observation in
        let fields = line.split(separator: ",").map(String.init)
        return Observation(id: fields[0], label: fields[1], values: fields.dropFirst(2).map { Double($0)! })
    }
    return (names, observations)
}

func readSettings() throws -> Settings {
    Settings(try readInputLines("params.txt").map { $0.split(separator: " ").dropFirst().map(String.init) })
}

func writeLines(_ name: String, _ lines: [String]) throws {
    let text = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    try text.write(toFile: "output/" + name, atomically: false, encoding: .ascii)
}
