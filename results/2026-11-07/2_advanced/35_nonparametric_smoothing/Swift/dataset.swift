import Foundation

struct Sample {
    let position: Int
    let ordinate: Int
    var x: Double { Double(position) / 100 }
    var y: Double { Double(ordinate) / 100 }
}

struct SeriesData {
    let name: String
    var points: [Sample]
}

struct TestPoint {
    let series: String
    let position: Int
}

struct Settings {
    let windows: [String]
    let kernels: [String]
    let bandwidths: [String]
    let degrees: [String]
    let spans: [String]
    let robustIterations: Int
    let lambdas: [String]
    let folds: Int
    let isotonic: [String]
    let gridPoints: Int
    let bandZ: Double
    let bandMethods: [String]
    let outlierThreshold: Int
    let bootstrapCount: Int
    let trim: Int
    let seed: Int
    let plotSeries: [String]
    let plotMethods: [String]
    let width: Int
    let height: Int
}

func hundredths(_ text: String) -> Int { Int(text.replacingOccurrences(of: ".", with: ""))! }

func inputRows(_ name: String) throws -> [[String]] {
    let text = try String(contentsOfFile: "input/" + name, encoding: .ascii)
    return text.split(separator: "\n").dropFirst().map { $0.split(separator: ",").map(String.init) }
}

func readDataset() throws -> ([SeriesData], [TestPoint], Settings) {
    var series: [SeriesData] = []
    var indices: [String: Int] = [:]
    for row in try inputRows("series.csv") {
        if indices[row[0]] == nil {
            indices[row[0]] = series.count
            series.append(SeriesData(name: row[0], points: []))
        }
        series[indices[row[0]]!].points.append(Sample(position: hundredths(row[1]), ordinate: hundredths(row[2])))
    }
    for i in series.indices { series[i].points.sort { $0.position < $1.position } }
    let tests = try inputRows("test_points.csv").map { TestPoint(series: $0[0], position: hundredths($0[1])) }
    let text = try String(contentsOfFile: "input/params.txt", encoding: .ascii)
    let fields = Dictionary(uniqueKeysWithValues: text.split(separator: "\n").map { line in
        let parts = line.split(separator: " ").map(String.init)
        return (parts[0], Array(parts.dropFirst()))
    })
    func values(_ key: String) -> [String] { fields[key]! }
    func integer(_ key: String) -> Int { Int(values(key)[0])! }
    let bootstrap = values("BOOTSTRAP").map { Int($0)! }
    let size = values("PLOT_SIZE").map { Int($0)! }
    let settings = Settings(
        windows: values("WINDOWS"), kernels: values("KERNELS"), bandwidths: values("BANDWIDTHS"),
        degrees: values("LOESS_DEGREES"), spans: values("SPANS"), robustIterations: integer("ROBUST_ITERATIONS"),
        lambdas: values("LAMBDAS"), folds: integer("CV_FOLDS"), isotonic: values("ISOTONIC"),
        gridPoints: integer("GRID_POINTS"), bandZ: Double(values("BAND_Z")[0])!, bandMethods: values("BAND_METHODS"),
        outlierThreshold: hundredths(values("OUTLIER_THRESHOLD")[0]),
        bootstrapCount: bootstrap[0], trim: bootstrap[1], seed: bootstrap[2],
        plotSeries: values("PLOT_SERIES"), plotMethods: values("PLOT_METHODS"), width: size[0], height: size[1]
    )
    return (series, tests, settings)
}
