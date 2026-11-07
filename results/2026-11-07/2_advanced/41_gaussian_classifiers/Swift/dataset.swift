import Foundation

struct Row {
    let id: Int
    let values: [Double]
    let label: String
    let classIndex: Int
}

struct FeatureSubset {
    let name: String
    let features: [Int]
}

struct Parameters {
    let prior: String
    let epsilon: Double
    let smoothingGrid: [Double]
    let gamma: Double
    let gammaGrid: [Double]
    let folds: Int
    let calibrationEdges: [Double]
    let rejectThresholds: [Double]
    let curve: [Int]
    let outlierThreshold: Double
    let bootstrapCount: Int
    let seed: Int
    let mapWidth: Int
    let mapHeight: Int
    let plotWidth: Int
    let plotHeight: Int
    let subsets: [FeatureSubset]
    let pairs: [[Int]]
}

struct Dataset {
    let features: [String]
    let classes: [String]
    let train: [Row]
    let test: [Row]
    let costs: [[Double]]
    let parameters: Parameters
}

func inputLines(_ path: String) throws -> [String] {
    try String(contentsOfFile: path, encoding: .ascii).split(separator: "\n").map(String.init)
}

func readTable(_ path: String) throws -> (features: [String], rows: [(id: Int, values: [Double], label: String)]) {
    let records = try inputLines(path).map { $0.components(separatedBy: ",") }
    let features = Array(records[0].dropFirst().dropLast())
    let rows = records.dropFirst().map { (id: Int($0[0])!, values: $0.dropFirst().dropLast().map { Double($0)! }, label: $0.last!) }
    return (features, rows)
}

func readParameters(_ features: [String]) throws -> Parameters {
    var values: [String: [String]] = [:]
    var subsets: [FeatureSubset] = []
    var pairs: [[Int]] = []
    let positions = Dictionary(uniqueKeysWithValues: features.enumerated().map { ($0.element, $0.offset) })
    for line in try inputLines("input/params.txt") {
        let words = line.split(separator: " ").map(String.init)
        let arguments = Array(words.dropFirst())
        if words[0] == "SUBSET" {
            subsets.append(FeatureSubset(name: arguments[0], features: arguments.dropFirst().map { positions[$0]! }))
        } else if words[0] == "PAIR" { pairs.append(arguments.map { positions[$0]! }) }
        else { values[words[0]] = arguments }
    }
    return Parameters(prior: values["PRIOR"]![0], epsilon: Double(values["VAR_SMOOTHING"]![0])!,
                       smoothingGrid: values["SMOOTHING_GRID"]!.map { Double($0)! }, gamma: Double(values["QDA_GAMMA"]![0])!,
                       gammaGrid: values["GAMMA_GRID"]!.map { Double($0)! }, folds: Int(values["CV_FOLDS"]![0])!,
                       calibrationEdges: values["CALIBRATION_EDGES"]!.map { Double($0)! },
                       rejectThresholds: values["REJECT_THRESHOLDS"]!.map { Double($0)! }, curve: values["CURVE"]!.map { Int($0)! },
                       outlierThreshold: Double(values["OUTLIER_THRESHOLD"]![0])!, bootstrapCount: Int(values["BOOTSTRAP"]![0])!,
                       seed: Int(values["BOOTSTRAP"]![1])!, mapWidth: Int(values["MAP_SIZE"]![0])!, mapHeight: Int(values["MAP_SIZE"]![1])!,
                       plotWidth: Int(values["PLOT_SIZE"]![0])!, plotHeight: Int(values["PLOT_SIZE"]![1])!, subsets: subsets, pairs: pairs)
}

func readInputs() throws -> Dataset {
    let training = try readTable("input/train.csv")
    let testing = try readTable("input/test.csv")
    let classes = Set(training.rows.map { $0.label }).sorted()
    let positions = Dictionary(uniqueKeysWithValues: classes.enumerated().map { ($0.element, $0.offset) })
    func rows(_ records: [(id: Int, values: [Double], label: String)]) -> [Row] {
        records.map { Row(id: $0.id, values: $0.values, label: $0.label, classIndex: positions[$0.label]!) }
    }
    let costRecords = try inputLines("input/costs.csv").map { $0.components(separatedBy: ",") }
    let columns = Array(costRecords[0].dropFirst())
    let byActual = Dictionary(uniqueKeysWithValues: costRecords.dropFirst().map { ($0[0], $0.dropFirst().map { Double($0)! }) })
    let costs = classes.map { name in classes.map { byActual[name]![columns.firstIndex(of: $0)!] } }
    return Dataset(features: training.features, classes: classes, train: rows(training.rows), test: rows(testing.rows),
                    costs: costs, parameters: try readParameters(training.features))
}
