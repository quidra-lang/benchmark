import Foundation
enum Report {
    static func name(_ agent: Int) -> String {
        String(UnicodeScalar(65 + agent)!)
    }
    static func cell(_ cell: Cell) -> String {
        "\(cell.x),\(cell.y)"
    }
    static func conflict(_ conflict: Conflict) -> String {
        conflict.vertex ? "vertex t \(conflict.time) \(name(conflict.a)) \(name(conflict.b)) at \(cell(conflict.destination))" : "edge t \(conflict.time) \(name(conflict.a)) \(name(conflict.b)) from \(cell(conflict.source)) to \(cell(conflict.destination))"
    }
    static func actions(_ path: Path) -> String {
        if path.count < 2 {
            return ""
        }
        return (1..<path.count).map {
            i -> String in let a = path[i - 1], b = path[i];
            if a == b {
                return "."
            }
            if b.y < a.y {
                return "N"
            }
            if b.x > a.x {
                return "E"
            }
            return b.y > a.y ? "S" : "W"
        }.joined()
    }
    static func ratio(_ a: Int, _ b: Int) -> String {
        var x = a, y = b;
        while y > 0 {
            let r = x % y;
            x = y;
            y = r
        }
        return "\(a / x)/\(b / x)"
    }
    static func csv(_ values: [String]) -> String {
        values.joined(separator: ",")
    }
    static func write(_ name: String, _ lines: [String]) {
        try! FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true);
        try! (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: false, encoding: .ascii)
    }
}
