import Foundation

enum Replacement: String {
    case lru = "LRU"
    case fifo = "FIFO"
    case plru = "PLRU"
}

struct Scenario {
    let name: String
    let coherence: CoherenceProtocol
    let l1: Replacement
    let l2: Replacement
    let order: Int
}

struct Region {
    let name: String
    let start: Int
    let end: Int
}

struct Configuration {
    var cores = 0, line = 0, l1Size = 0, l1Ways = 0, l2Size = 0, l2Ways = 0
    var t1 = 0, t2 = 0, tm = 0, tb = 0, interval = 0, top = 0
    var scenarios: [Scenario] = []
    var primary = ""
    var regions: [Region] = []
    var watch: [Int] = []
    var l1Sets: Int { l1Size / (line * l1Ways) }
    var l2Sets: Int { l2Size / (line * l2Ways) }
    var capacity: Int { l1Sets * l1Ways }

    init() throws {
        for line in try readLines("input/config.txt") {
            let f = line.split(separator: " ").map(String.init)
            switch f[0] {
            case "CORES": cores = Int(f[1])!
            case "LINE": self.line = Int(f[1])!
            case "L1": l1Size = Int(f[1])!; l1Ways = Int(f[2])!
            case "L2": l2Size = Int(f[1])!; l2Ways = Int(f[2])!
            case "LATENCY": t1 = Int(f[1])!; t2 = Int(f[2])!; tm = Int(f[3])!; tb = Int(f[4])!
            case "SCENARIO": scenarios.append(Scenario(name: f[1], coherence: CoherenceProtocol(rawValue: f[2])!,
                l1: Replacement(rawValue: f[3])!, l2: Replacement(rawValue: f[4])!, order: scenarios.count))
            case "PRIMARY": primary = f[1]
            case "INTERVAL": interval = Int(f[1])!
            case "TOP": top = Int(f[1])!
            case "REGION": regions.append(Region(name: f[1], start: Int(f[2], radix: 16)!, end: Int(f[3], radix: 16)!))
            case "WATCH": watch.append(Int(f[1], radix: 16)! / self.line)
            default: break
            }
        }
    }
}

func readLines(_ path: String) throws -> [String] {
    try String(contentsOfFile: path, encoding: .ascii).split(separator: "\n", omittingEmptySubsequences: false)
        .dropLast().map(String.init)
}

func decimalInteger(_ value: String, maximum: Int = Int.max) -> Bool {
    !value.isEmpty && value.count <= maximum && (value == "0" || value.first != "0")
        && value.utf8.allSatisfy { (48...57).contains($0) }
}

func validHexAddress(_ value: String) -> Bool {
    value.count == 8 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
}

func hexAddress(_ value: Int) -> String { String(format: "%08x", value) }
func writeLines(_ filename: String, _ lines: [String]) throws {
    try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    try lines.map { $0 + "\n" }.joined().write(toFile: "output/" + filename, atomically: true, encoding: .ascii)
}
