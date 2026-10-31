import Foundation

struct Settings {
    let characteristic: String
    let lsl: Int
    let usl: Int
    let target: Int
    let size: Int
    let phase1: Int
    let passes: Int
    let rules: [String: [Int]]
    let cusumK: Double
    let cusumH: Double
    let lambda: Double
    let ewmaL: Double
    let maSpan: Int
    let eventGap: Int
    let ciZ: Double
    let bin: Int
    let rollingWindow: Int
    let rollingStep: Int

    init(_ lines: [String]) {
        var fields: [String: String] = [:]
        var rules: [String: [Int]] = [:]
        for line in lines {
            let words = line.split(separator: " ").map(String.init)
            if words[0] == "rules" { rules[words[1]] = words.dropFirst(2).map { Int($0)! } }
            else { fields[words[0]] = words[1] }
        }
        characteristic = fields["characteristic"]!
        lsl = Int(fields["lsl"]!)!
        usl = Int(fields["usl"]!)!
        target = Int(fields["target"]!)!
        size = Int(fields["subgroup_size"]!)!
        phase1 = Int(fields["phase1_subgroups"]!)!
        passes = Int(fields["max_passes"]!)!
        self.rules = rules
        cusumK = Double(fields["cusum_k"]!)!
        cusumH = Double(fields["cusum_h"]!)!
        lambda = Double(fields["ewma_lambda"]!)!
        ewmaL = Double(fields["ewma_l"]!)!
        maSpan = Int(fields["ma_span"]!)!
        eventGap = Int(fields["event_gap"]!)!
        ciZ = Double(fields["ci_z"]!)!
        bin = Int(fields["histogram_bin"]!)!
        rollingWindow = Int(fields["rolling_window"]!)!
        rollingStep = Int(fields["rolling_step"]!)!
    }
}
struct Lot {
    let number: Int
    let inspected: Int
    let defectives: Int
    let defects: Int
}
struct ControlConstants {
    let values: [Double]
    var a2: Double { values[0] }
    var a3: Double { values[1] }
    var b3: Double { values[2] }
    var b4: Double { values[3] }
    var d3: Double { values[4] }
    var d4: Double { values[5] }
    var d2: Double { values[6] }
    var c4: Double { values[7] }
}
func controlConstants(_ size: Int) -> ControlConstants {
    let table: [[Double]] = [
        [1.880, 2.659, 0, 3.267, 0, 3.267, 1.128, 0.7979],
        [1.023, 1.954, 0, 2.568, 0, 2.574, 1.693, 0.8862],
        [0.729, 1.628, 0, 2.266, 0, 2.282, 2.059, 0.9213],
        [0.577, 1.427, 0, 2.089, 0, 2.114, 2.326, 0.9400],
        [0.483, 1.287, 0.030, 1.970, 0, 2.004, 2.534, 0.9515],
        [0.419, 1.182, 0.118, 1.882, 0.076, 1.924, 2.704, 0.9594],
        [0.373, 1.099, 0.185, 1.815, 0.136, 1.864, 2.847, 0.9650],
        [0.337, 1.032, 0.239, 1.761, 0.184, 1.816, 2.970, 0.9693],
        [0.308, 0.975, 0.284, 1.716, 0.223, 1.777, 3.078, 0.9727]
    ]
    return ControlConstants(values: table[size - 2])
}
func readLines(_ path: String) throws -> [String] {
    try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n").map(String.init)
}
func readSettings() throws -> Settings { Settings(try readLines("input/spec.txt")) }
func readMeasurements() throws -> [Int] {
    try readLines("input/measurements.csv").dropFirst().map { Int($0.split(separator: ",")[2])! }
}
func readLots() throws -> [Lot] {
    try readLines("input/attributes.csv").dropFirst().map { line in
        let values = line.split(separator: ",").map { Int($0)! }
        return Lot(number: values[0], inspected: values[1], defectives: values[2], defects: values[3])
    }
}
