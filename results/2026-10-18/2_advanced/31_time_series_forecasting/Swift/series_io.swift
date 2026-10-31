import Foundation

struct Inventory {
    var onHand = 0
    var leadTime = 0
    var review = 0
    var service = 0.0
}

struct Series {
    let name: String
    var periods: [String] = []
    var raw: [Int?] = []
    var events: [String: String] = [:]
    var inventory = Inventory()
}

struct Settings {
    let season: Int
    let holdout: Int
    let horizon: Int
    let cvStart: Int
    let combo: Int
    let alpha: [Double]
    let beta: [Double]
    let gamma: [Double]
    let phi: [Double]
    let maxAR: Int
    let maxLag: Int
    let ljungBox: [Int]
    let outlier: Double
    let interval: [Double]
}

func inputRows(_ name: String) -> [[String]] {
    let text = try! String(contentsOfFile: "input/" + name, encoding: .ascii)
    return text.split(separator: "\n").dropFirst().map {
        $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
    }
}

func readInputs() -> ([Series], Settings) {
    var series: [Series] = []
    for row in inputRows("series.csv") {
        if series.last?.name != row[0] {
            series.append(Series(name: row[0]))
        }
        let index = series.count - 1
        series[index].periods.append(row[1])
        series[index].raw.append(row[2] == "NA" ? nil : Int(row[2])!)
    }
    for row in inputRows("events.csv") {
        let index = series.firstIndex { $0.name == row[0] }!
        series[index].events[row[1]] = row[2]
    }
    for row in inputRows("inventory.csv") {
        let index = series.firstIndex { $0.name == row[0] }!
        series[index].inventory = Inventory(
            onHand: Int(row[1])!, leadTime: Int(row[2])!, review: Int(row[3])!, service: Double(row[4])!
        )
    }
    let text = try! String(contentsOfFile: "input/params.txt", encoding: .ascii)
    let rows = text.split(separator: "\n").map { $0.split(separator: " ").dropFirst().map(String.init) }
    func integer(_ i: Int) -> Int { Int(rows[i][0])! }
    func reals(_ i: Int) -> [Double] { rows[i].map { Double($0)! } }
    let settings = Settings(
        season: integer(0), holdout: integer(1), horizon: integer(2), cvStart: integer(3), combo: integer(4),
        alpha: reals(5), beta: reals(6), gamma: reals(7), phi: reals(8), maxAR: integer(9), maxLag: integer(10),
        ljungBox: rows[11].map { Int($0)! }, outlier: Double(rows[12][0])!, interval: reals(13)
    )
    return (series, settings)
}

func nextMonth(_ period: String) -> String {
    let parts = period.split(separator: "-").map { Int($0)! }
    let year = parts[0] + parts[1] / 12
    let month = parts[1] % 12 + 1
    return String(format: "%04d-%02d", year, month)
}

func real(_ value: Double) -> String {
    let result = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), value)
    return result == "-0.0000" ? "0.0000" : result
}

func optionalReal(_ value: Double?) -> String {
    value.map(real) ?? "NA"
}

func writeLines(_ name: String, _ lines: [String]) {
    try! FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    try! (lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: true, encoding: .ascii)
}
