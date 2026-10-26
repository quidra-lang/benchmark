import Foundation

struct Page {
    let id: Int
    let host: String
    let title: String
    let words: [String]
}

struct LinkRecord {
    let line: Int
    let source: Int
    let target: Int
}

struct Link: Hashable, Comparable {
    let source: Int
    let target: Int

    init(_ source: Int, _ target: Int) { self.source = source; self.target = target }
    static func < (first: Link, second: Link) -> Bool {
        first.source == second.source ? first.target < second.target : first.source < second.source
    }
}

struct Query {
    let number: Int
    let words: [String]
    let seeds: [Int]
}

struct Settings {
    let damping: Double
    let iterations: Int
    let tolerance: Double
    let sweep: [Double]
    let trusted: [Int]
    let spamTop: Int
    let spamThreshold: Double
    let hitsIterations: Int
    let topK: Int
    let rootLimit: Int
    let neighborLimit: Int
}

func asciiLess(_ first: String, _ second: String) -> Bool {
    first.utf8.lexicographicallyPrecedes(second.utf8)
}

func readLines(_ path: String) throws -> [String] {
    try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n").map(String.init)
}

func readPages(_ path: String) throws -> [Page] {
    try readLines(path).dropFirst().map { line in
        let fields = line.split(separator: ",").map(String.init)
        return Page(id: Int(fields[0])!, host: fields[1], title: fields[2], words: fields[2].split(separator: " ").map(String.init))
    }
}

func readLinks(_ path: String) throws -> [LinkRecord] {
    try readLines(path).dropFirst().enumerated().map { number, line in
        let fields = line.split(separator: ",")
        return LinkRecord(line: number + 2, source: Int(fields[0])!, target: Int(fields[1])!)
    }
}

func readQueries(_ path: String) throws -> [Query] {
    try readLines(path).enumerated().map { number, line in
        let parts = line.components(separatedBy: " | ")
        return Query(number: number + 1, words: parts[0].split(separator: " ").map(String.init),
            seeds: parts[1].split(separator: " ").map { Int($0)! })
    }
}

func readSettings(_ path: String) throws -> Settings {
    let entries = try readLines(path).map { $0.split(separator: " ").dropFirst().map(String.init) }
    func integer(_ index: Int) -> Int { Int(entries[index][0])! }
    return Settings(damping: Double(entries[0][0])!, iterations: integer(1), tolerance: Double(entries[2][0])!,
        sweep: entries[3].map { Double($0)! }, trusted: entries[4].map { Int($0)! }, spamTop: integer(5),
        spamThreshold: Double(entries[6][0])!, hitsIterations: integer(7), topK: integer(8),
        rootLimit: integer(9), neighborLimit: integer(10))
}
