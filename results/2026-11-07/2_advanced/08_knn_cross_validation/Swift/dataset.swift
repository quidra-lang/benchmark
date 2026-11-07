import Foundation

struct Row {
    let id: String
    let values: [Double]
    let label: String?
    let target: Double?
}
struct Settings {
    let scalings: [String]
    let ks: [Int]
    let metrics: [String]
    let weightings: [String]
    let folds: Int
    let editK: Int
    let curve: [Int]
    let bins: [Double]
    let top: Int
    init(_ entries: [String: [String]]) {
        scalings = entries["SCALINGS"]!
        ks = entries["K_VALUES"]!.map { Int($0)! }
        metrics = entries["METRICS"]!
        weightings = entries["WEIGHTINGS"]!
        folds = Int(entries["FOLDS"]![0])!
        editK = Int(entries["EDIT_K"]![0])!
        curve = entries["CURVE"]!.map { Int($0)! }
        bins = entries["BINS"]!.map { Double($0)! }
        top = Int(entries["TOP"]![0])!
    }
}
struct Dataset {
    let features: [String]
    let train: [Row]
    let test: [Row]
    let settings: Settings
}
func readLines(_ path: String) throws -> [String] { try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n").map(String.init) }
func readRows(_ name: String) throws -> ([String], [Row]) {
    let lines = try readLines("input/\(name)")
    let header = lines[0].split(separator: ",").map(String.init)
    let rows = lines.dropFirst().map { line -> Row in
        let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        return Row(id: fields[0], values: fields[1..<(fields.count - 2)].map { Double($0)! }, label: fields[fields.count - 2].isEmpty ? nil : fields[fields.count - 2], target: fields.last!.isEmpty ? nil : Double(fields.last!)!)
    }
    return (Array(header[1..<(header.count - 2)]), rows)
}
func readDataset() throws -> Dataset {
    let (features, train) = try readRows("train.csv")
    let (_, test) = try readRows("test.csv")
    let entries = try readLines("input/params.txt").map { line -> (String, [String]) in let words = line.split(separator: " ").map(String.init); return (words[0], Array(words.dropFirst())) }
    return Dataset(features: features, train: train, test: test, settings: Settings(Dictionary(uniqueKeysWithValues: entries)))
}
