import Foundation

struct Point {
    let id: Int
    let x: Int
    let y: Int
}

struct Params {
    let eps: [Int]
    let minPts: Int
    let maxEps: Int
    let extract: [Int]
    let xi: String
    let u: Int
    let v: Int
    let minSize: Int
    let width: Int
    let height: Int
    let kWidth: Int
    let kHeight: Int
    let plotWidth: Int
}

func readInputs() throws -> ([Point], Params) {
    let text = try String(contentsOfFile: "input/points.csv", encoding: .ascii)
    let points = text.split(separator: "\n").dropFirst().map { line in
        let row = line.split(separator: ",").map { Int($0)! }
        return Point(id: row[0], x: row[1], y: row[2])
    }.sorted { $0.id < $1.id }
    let input = try String(contentsOfFile: "input/params.txt", encoding: .ascii)
    let rows = Dictionary(uniqueKeysWithValues: input.split(separator: "\n").map { line in
        let fields = line.split(separator: " ").map(String.init)
        return (fields[0], Array(fields.dropFirst()))
    })
    func list(_ key: String) -> [Int] { rows[key]!.map { Int($0)! } }
    let xi = rows["XI"]![0]
    let ratio = xi.split(separator: "/").map { Int($0)! }
    let params = Params(
        eps: list("EPS"), minPts: list("MIN_PTS")[0], maxEps: list("OPTICS_MAX_EPS")[0],
        extract: list("EXTRACT_EPS"), xi: xi, u: ratio[0], v: ratio[1], minSize: list("XI_MIN_SIZE")[0],
        width: list("MAP_SIZE")[0], height: list("MAP_SIZE")[1],
        kWidth: list("KDIST_PLOT")[0], kHeight: list("KDIST_PLOT")[1], plotWidth: list("PLOT_WIDTH")[0]
    )
    return (points, params)
}
