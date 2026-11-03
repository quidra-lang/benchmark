import Foundation

func symbolLines(_ symbol: Symbol) -> [String] { symbol.map { $0.map { $0 == 1 ? "#" : "." }.joined() } }

func pbmText(_ symbol: Symbol, quietZone: Int, scale: Int) -> String {
    let width = (symbol.count + 2 * quietZone) * scale
    let margin = String(repeating: "0", count: quietZone * scale), emptyRow = String(repeating: "0", count: width)
    var lines = ["P1", "\(width) \(width)"] + Array(repeating: emptyRow, count: quietZone * scale)
    for row in symbol {
        let pixels = margin + row.map { String(repeating: String($0), count: scale) }.joined() + margin
        lines += Array(repeating: pixels, count: scale)
    }
    lines += Array(repeating: emptyRow, count: quietZone * scale)
    return lines.joined(separator: "\n") + "\n"
}
