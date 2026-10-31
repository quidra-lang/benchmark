import Foundation

enum ColumnKind {
    case numeric, categorical
}

enum CellValue {
    case missing, number(Double), label(String)
    var isMissing: Bool { if case .missing = self { return true }; return false }
    var numericValue: Double? { if case .number(let value) = self { return value }; return nil }
    var labelValue: String? { if case .label(let value) = self { return value }; return nil }
}

typealias Record = [String: CellValue]

struct DataFrame {
    let columns: [String]
    let kinds: [String: ColumnKind]
    let rows: [Record]
}

struct Parameters {
    let rankTolerance: Double
    let removeAlpha: Double
    let confidence: Double
    let leverage: Double
    let studentized: Double
    let cook: Double
    let dffits: Double
    let vif: Double
    let durbinWatson: Double
    let breuschPagan: Double
    let normality: Double
    let bestSubsets: Int
    let plotWidth: Int
    let plotHeight: Int
    let plotLimit: Double
}

func inputLines(_ path: String) throws -> [String] {
    try String(contentsOfFile: path, encoding: .ascii).split(separator: "\n").map(String.init)
}

func readCSV(_ path: String, kinds suppliedKinds: [String: ColumnKind]? = nil) throws -> DataFrame {
    let lines = try inputLines(path)
    let columns = lines[0].components(separatedBy: ",")
    let records = lines.dropFirst().map { $0.components(separatedBy: ",") }
    var kinds: [String: ColumnKind] = [:]
    for (index, column) in columns.enumerated() {
        if let suppliedKinds { kinds[column] = suppliedKinds[column]! }
        else {
            let categorical = records.contains { $0[index] != "NA" && $0[index].first! >= "A" && $0[index].first! <= "Z" }
            kinds[column] = categorical ? .categorical : .numeric
        }
    }
    let rows = records.map { values -> Record in
        var row: Record = [:]
        for (column, value) in zip(columns, values) {
            if value == "NA" { row[column] = .missing }
            else if kinds[column] == .numeric { row[column] = .number(Double(value)!) }
            else { row[column] = .label(value) }
        }
        return row
    }
    return DataFrame(columns: columns, kinds: kinds, rows: rows)
}

func readParameters() throws -> Parameters {
    let settings = Dictionary(uniqueKeysWithValues: try inputLines("input/params.txt").map { line in
        let words = line.split(separator: " ").map(String.init)
        return (words[0], Array(words.dropFirst()))
    })
    return Parameters(rankTolerance: Double(settings["RANK_TOL"]![0])!, removeAlpha: Double(settings["ALPHA_REMOVE"]![0])!,
                       confidence: Double(settings["CONFIDENCE"]![0])!, leverage: Double(settings["LEVERAGE"]![0])!,
                       studentized: Double(settings["STUDENTIZED"]![0])!, cook: Double(settings["COOK"]![0])!,
                       dffits: Double(settings["DFFITS"]![0])!, vif: Double(settings["VIF"]![0])!,
                       durbinWatson: Double(settings["DURBIN_WATSON"]![0])!, breuschPagan: Double(settings["BREUSCH_PAGAN"]![0])!,
                       normality: Double(settings["NORMALITY"]![0])!, bestSubsets: Int(settings["BEST_SUBSETS"]![0])!,
                       plotWidth: Int(settings["PLOT"]![0])!, plotHeight: Int(settings["PLOT"]![1])!, plotLimit: Double(settings["PLOT"]![2])!)
}
