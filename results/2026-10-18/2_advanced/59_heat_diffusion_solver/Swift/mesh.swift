import Foundation

enum Edge: String {
    case left, right, top, bottom
    var face: Int { switch self { case .left: return 0; case .right: return 1; case .top: return 2; case .bottom: return 3 } }
    var horizontal: Bool { self == .left || self == .right }
}
struct FaceAddress: Hashable { let cell: Int; let face: Int }
struct Mesh {
    let width: Int
    let height: Int
    let dx: Double
    let thickness: Double
    let codes: [String]
    let neighbors: [[Int?]]
    var count: Int { width * height }
    init(_ width: Int, _ height: Int, _ dx: Double, _ thickness: Double, _ rows: [String]) {
        self.width = width; self.height = height; self.dx = dx; self.thickness = thickness; codes = rows.flatMap { $0.map(String.init) }
        neighbors = (0..<height).flatMap { r in (0..<width).map { c -> [Int?] in let p = r * width + c; return [c > 0 ? p - 1 : nil, c + 1 < width ? p + 1 : nil, r > 0 ? p - width : nil, r + 1 < height ? p + width : nil] } }
    }
    func cell(_ row: Int, _ column: Int) -> Int { row * width + column }
    func coordinates(_ point: Int) -> String { "\(point / width) \(point % width)" }
    func segmentFaces(_ edge: Edge, _ start: Int, _ end: Int) -> [FaceAddress] {
        if edge == .top || edge == .bottom { let row = edge == .top ? 0 : height - 1; return (start...end).map { FaceAddress(cell: cell(row, $0), face: edge.face) } }
        let column = edge == .left ? 0 : width - 1
        return (start...end).map { FaceAddress(cell: cell($0, column), face: edge.face) }
    }
    func sourceCells(_ r1: Int, _ c1: Int, _ r2: Int, _ c2: Int) -> [Int] { (r1...r2).flatMap { r in (c1...c2).map { cell(r, $0) } } }
}
func readPlate() throws -> Mesh {
    let rows = try String(contentsOfFile: "input/plate.txt", encoding: .ascii).split(separator: "\n").map(String.init), fields = rows[0].components(separatedBy: " ")
    return Mesh(Int(fields[0])!, Int(fields[1])!, Double(fields[2])!, Double(fields[3])!, Array(rows.dropFirst()))
}
