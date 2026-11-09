import Foundation

struct Table {
    let names: [String]
    let ids: [String]
    let rows: [[Double?]]
}

struct Settings {
    let missing: String
    let scaling: String
    let components: String
    let cumulativeTarget: Double
    let parallelIterations: Int
    let seed: Int64
    let t2Limit: Double
    let speLimit: Double
    let varimaxCycles: Int
    let topRows: Int
    let screeWidth: Int
    let biplotWidth: Int
    let biplotHeight: Int
    let circleRadius: Int
    let diagnosticWidth: Int
    let diagnosticHeight: Int
}

func readLines(_ path: String) throws -> [String] {
    try String(contentsOfFile: path, encoding: .ascii).split(separator: "\n").map(String.init)
}

func readTable(_ path: String) throws -> Table {
    let lines = try readLines(path)
    let names = Array(lines[0].components(separatedBy: ",").dropFirst())
    let fields = lines.dropFirst().map { $0.components(separatedBy: ",") }
    return Table(names: names, ids: fields.map { $0[0] }, rows: fields.map { $0.dropFirst().map { $0 == "NA" ? nil : Double($0)! } })
}

func readSettings(_ path: String) throws -> Settings {
    let entries = Dictionary(uniqueKeysWithValues: try readLines(path).map { line in
        let fields = line.components(separatedBy: " ")
        return (fields[0], Array(fields.dropFirst()))
    })
    return Settings(missing: entries["MISSING"]![0], scaling: entries["SCALING"]![0], components: entries["COMPONENTS"]![0],
                    cumulativeTarget: Double(entries["CUMULATIVE_TARGET"]![0])!, parallelIterations: Int(entries["PARALLEL"]![0])!,
                    seed: Int64(entries["PARALLEL"]![1])!, t2Limit: Double(entries["T2_LIMIT"]![0])!, speLimit: Double(entries["SPE_LIMIT"]![0])!,
                    varimaxCycles: Int(entries["VARIMAX_CYCLES"]![0])!, topRows: Int(entries["TOP_ROWS"]![0])!,
                    screeWidth: Int(entries["SCREE_WIDTH"]![0])!, biplotWidth: Int(entries["BIPLOT_SIZE"]![0])!,
                    biplotHeight: Int(entries["BIPLOT_SIZE"]![1])!, circleRadius: Int(entries["CIRCLE_RADIUS"]![0])!,
                    diagnosticWidth: Int(entries["DIAGNOSTIC_SIZE"]![0])!, diagnosticHeight: Int(entries["DIAGNOSTIC_SIZE"]![1])!)
}
