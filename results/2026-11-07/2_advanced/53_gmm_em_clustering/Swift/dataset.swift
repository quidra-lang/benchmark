import Foundation

struct Vector2 { let x: Double; let y: Double }
struct Observation { let id: String; let position: Vector2 }
enum CovarianceKind: String { case full = "FULL", tied = "TIED", diagonal = "DIAG", spherical = "SPHERICAL" }
struct InitialValues { let weights: [Double]; let means: [Vector2]; let covariances: [Covariance] }
struct Settings {
    let counts: [Int]
    let iterations: Int
    let types: [CovarianceKind]
    let epsilon: Double
    let tolerance: Double
    let kmeansIterations: Int
    let folds: Int
    let uncertain: Double
    let lowDensity: Double
    let edges: [Double]
    let xmin: Double
    let xmax: Double
    let ymin: Double
    let ymax: Double
    let width: Int
    let height: Int
}

func inputLines(_ filename: String) throws -> [String] { try String(contentsOfFile: "input/" + filename, encoding: .ascii).components(separatedBy: "\n").dropLast().map { $0 } }
func readObservations() throws -> [Observation] {
    try inputLines("points.csv").dropFirst().map { line in
        let fields = line.components(separatedBy: ",")
        return Observation(id: fields[0], position: Vector2(x: Double(fields[1])!, y: Double(fields[2])!))
    }
}
func readInitialValues() throws -> [Int: InitialValues] {
    let rows = try inputLines("init.txt").filter { !$0.isEmpty }.map { $0.components(separatedBy: " ") }
    var result: [Int: InitialValues] = [:], cursor = 0
    while cursor < rows.count {
        let count = Int(rows[cursor][1])!, weights = rows[cursor + 1].dropFirst().map { Double($0)! }
        var means: [Vector2] = [], covariances: [Covariance] = []
        for row in rows[(cursor + 2)..<(cursor + count + 2)] {
            means.append(Vector2(x: Double(row[2])!, y: Double(row[3])!))
            covariances.append(Covariance(a: Double(row[4])!, b: Double(row[5])!, c: Double(row[6])!))
        }
        result[count] = InitialValues(weights: weights, means: means, covariances: covariances)
        cursor += count + 2
    }
    return result
}
func readSettings() throws -> Settings {
    let fields = Dictionary(uniqueKeysWithValues: try inputLines("params.txt").map { line in let parts = line.components(separatedBy: " "); return (parts[0], Array(parts.dropFirst())) })
    func integer(_ key: String) -> Int { Int(fields[key]![0])! }
    func number(_ key: String) -> Double { Double(fields[key]![0])! }
    return Settings(counts: fields["K"]!.map { Int($0)! }, iterations: integer("ITERATIONS"), types: fields["TYPES"]!.map { CovarianceKind(rawValue: $0)! }, epsilon: number("REGULARIZATION"), tolerance: number("SETTLE_TOLERANCE"), kmeansIterations: integer("KMEANS_MAX_ITERATIONS"), folds: integer("CV_FOLDS"), uncertain: number("UNCERTAIN_THRESHOLD"), lowDensity: number("LOW_DENSITY_THRESHOLD"), edges: fields["GOF_EDGES"]!.map { Double($0)! }, xmin: Double(fields["MAP_X"]![0])!, xmax: Double(fields["MAP_X"]![1])!, ymin: Double(fields["MAP_Y"]![0])!, ymax: Double(fields["MAP_Y"]![1])!, width: Int(fields["MAP_SIZE"]![0])!, height: Int(fields["MAP_SIZE"]![1])!)
}
