import Foundation

struct Group {
    let name: String
    var values: [Int64]
}

struct PairedSample {
    let before: [Int64]
    let after: [Int64]
    let differences: [Int64]
}

struct Settings {
    let seed: Int64
    let bootstrap: Int
    let permutations: Int
    let confidence: Int
    let pilot: Int
    let powerSims: Int
    let powerPerms: Int
    let bins: Int
}

struct Dataset {
    let groups: [Group]
    let paired: PairedSample
    let settings: Settings
    let pairs: [(first: Int, second: Int)]
}

func hundredths(_ text: String) -> Int64 {
    let fields = text.split(separator: ".").map(String.init)
    let fraction = fields.count == 1 ? "00" : fields[1] + String(repeating: "0", count: 2 - fields[1].count)
    return Int64(fields[0])! * 100 + Int64(fraction)!
}

func readLines(_ path: String) throws -> [String] {
    try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n").map(String.init)
}

func loadDataset(_ folder: String) throws -> Dataset {
    var groups: [Group] = []
    var byName: [String: Int] = [:]
    for line in try readLines("\(folder)/samples.csv").dropFirst() {
        let fields = line.split(separator: ",").map(String.init)
        if byName[fields[0]] == nil {
            byName[fields[0]] = groups.count
            groups.append(Group(name: fields[0], values: []))
        }
        groups[byName[fields[0]]!].values.append(hundredths(fields[1]))
    }
    var before: [Int64] = []
    var after: [Int64] = []
    for line in try readLines("\(folder)/paired.csv").dropFirst() {
        let fields = line.split(separator: ",").map(String.init)
        before.append(hundredths(fields[1]))
        after.append(hundredths(fields[2]))
    }
    let differences = zip(before, after).map { first, second in second - first }
    let lines = try readLines("\(folder)/params.txt")
    let entries = lines.prefix(7).map { $0.split(separator: " ").dropFirst().map { Int64($0)! } }
    let settings = Settings(seed: entries[0][0], bootstrap: Int(entries[1][0]), permutations: Int(entries[2][0]),
        confidence: Int(entries[3][0]), pilot: Int(entries[4][0]), powerSims: Int(entries[5][0]),
        powerPerms: Int(entries[5][1]), bins: Int(entries[6][0]))
    let pairs = lines.dropFirst(7).map { line -> (Int, Int) in
        let fields = line.split(separator: " ").map(String.init)
        return (byName[fields[1]]!, byName[fields[2]]!)
    }
    return Dataset(groups: groups, paired: PairedSample(before: before, after: after, differences: differences),
        settings: settings, pairs: pairs)
}
