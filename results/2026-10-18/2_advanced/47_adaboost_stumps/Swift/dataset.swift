import Foundation

struct Row {
    let id: String
    let values: [Double]
    let label: Int
    func relabeled(_ label: Int) -> Row { Row(id: id, values: values, label: label) }
    func restricted(_ features: [Int]) -> Row { Row(id: id, values: features.map { values[$0] }, label: label) }
}

struct Parameters {
    let rounds: Int
    let variants: [String]
    let bins: Int
    let smoothing: Double
    let convergence: Double
    let clip: Double
    let folds: Int
    let margins: [Double]
    let classes: Int
    let sammeRounds: Int
    let permutationRepeats: Int
    let permutationSeed: Int64
    let noiseSeed: Int64
    let noise: [Int]
    let sizes: [Int]
    let shrinkage: [Double]
    let bootstrapSamples: Int
    let bootstrapSeed: Int64
}

struct Inputs {
    let features: [String]
    let train: [Row]
    let test: [Row]
    let multiFeatures: [String]
    let multiTrain: [Row]
    let multiTest: [Row]
    let params: Parameters
}

func readLines(_ path: String) throws -> [String] {
    try String(contentsOfFile: path, encoding: .ascii).split(separator: "\n").map(String.init)
}

func readBinary(_ path: String) throws -> (features: [String], rows: [Row]) {
    let lines = try readLines(path)
    let features = Array(lines[0].components(separatedBy: ",").dropFirst().dropLast())
    let rows = lines.dropFirst().map { line -> Row in
        let fields = line.components(separatedBy: ",")
        return Row(id: fields[0], values: fields.dropFirst().dropLast().map { Double($0)! }, label: Int(fields.last!)!)
    }
    return (features, rows)
}

func readInputs() throws -> Inputs {
    let train = try readBinary("input/train.csv"), test = try readBinary("input/test.csv")
    let multi = try readLines("input/multiclass.csv")
    let features = Array(multi[0].components(separatedBy: ",").dropFirst().dropLast(2))
    var multiTrain: [Row] = [], multiTest: [Row] = []
    for line in multi.dropFirst() {
        let fields = line.components(separatedBy: ",")
        let row = Row(id: fields[0], values: fields.dropFirst().dropLast(2).map { Double($0)! }, label: Int(fields[fields.count - 2])!)
        if fields.last! == "train" { multiTrain.append(row) } else { multiTest.append(row) }
    }
    let settings = Dictionary(uniqueKeysWithValues: try readLines("input/params.txt").map { line in
        let fields = line.components(separatedBy: " ")
        return (fields[0], Array(fields.dropFirst()))
    })
    func integer(_ key: String) -> Int { Int(settings[key]![0])! }
    func real(_ key: String) -> Double { Double(settings[key]![0])! }
    let params = Parameters(rounds: integer("ROUNDS"), variants: settings["VARIANTS"]!, bins: integer("BINS"), smoothing: real("SMOOTHING"),
                            convergence: real("CONVERGENCE"), clip: real("CLIP"), folds: integer("FOLDS"), margins: settings["MARGINS"]!.map { Double($0)! },
                            classes: integer("CLASSES"), sammeRounds: integer("SAMME_ROUNDS"), permutationRepeats: integer("PERMUTATION"),
                            permutationSeed: Int64(settings["PERMUTATION"]![1])!, noiseSeed: Int64(settings["NOISE"]![0])!,
                            noise: settings["NOISE"]!.dropFirst().map { Int($0)! }, sizes: settings["SIZES"]!.map { Int($0)! },
                            shrinkage: settings["SHRINKAGE"]!.map { Double($0)! }, bootstrapSamples: integer("BOOTSTRAP"), bootstrapSeed: Int64(settings["BOOTSTRAP"]![1])!)
    return Inputs(features: train.features, train: train.rows, test: test.rows, multiFeatures: features, multiTrain: multiTrain, multiTest: multiTest, params: params)
}
