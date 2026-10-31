import Foundation
func inputLines(_ file: String) -> [[String]] { try! String(contentsOfFile: "input/" + file, encoding: .ascii).split(separator: "\n").map { $0.split(separator: " ").map(String.init) } }
final class Section {
    let name: String, length: Int, row: Int, first: Int, last: Int
    var failed = false, occupiedSeconds = 0, lockedSeconds = 0, trains: Set<Int> = []
    init(_ w: [String]) { name = w[1]; length = Int(w[2])!; row = Int(w[3])!; first = Int(w[4])!; last = Int(w[5])! }
}
struct Motion { let target: Bool; var completion: Int? }
final class Point {
    let name: String, common: Int, normal: Int, reverse: Int, row: Int, column: Int
    var position = false, motion: Motion?, failed = false, throwsCount = 0, lockedSeconds = 0, movingSeconds = 0
    var detected: Bool { motion == nil && !failed }
    var display: Character { detected ? (position ? "R" : "N") : "?" }
    init(_ w: [String], common: Int, normal: Int, reverse: Int) { name = w[1]; self.common = common; self.normal = normal; self.reverse = reverse; row = Int(w[6])!; column = Int(w[7])! }
}
final class Signal {
    let name: String, section: Int, up: Bool, row: Int, column: Int
    var aspect = 0, seconds = [0,0,0], passes = 0
    init(_ w: [String], section: Int) { name = w[1]; self.section = section; up = w[3] == "UP"; row = Int(w[4])!; column = Int(w[5])! }
}
struct Buffer { let name: String; let section: Int; let end: Int; let row: Int; let column: Int }
struct Boundary { let name: String; let section: Int; let end: Int }
struct Label { let row: Int; let column: Int; let text: String }
enum Connection { case boundary(Int), buffer, joint(Int), point(Int) }
enum Beyond { case boundary(Int), buffer, section(Int), impassable }
final class Layout {
    var sections: [Section] = [], points: [Point] = [], signals: [Signal] = [], buffers: [Buffer] = [], boundaries: [Boundary] = [], labels: [Label] = [], connections: [[Connection?]] = []
    func section(_ name: String) -> Int { sections.firstIndex { $0.name == name }! }
    func point(_ name: String) -> Int { points.firstIndex { $0.name == name }! }
    func signal(_ section: Int, _ up: Bool) -> Int? { signals.firstIndex { $0.section == section && $0.up == up } }
    func boundary(_ name: String) -> Int { boundaries.firstIndex { $0.name == name }! }
    func beyond(_ section: Int, _ up: Bool) -> Beyond {
        switch connections[section][up ? 1 : 0]! {
        case .boundary(let b): return .boundary(b)
        case .buffer: return .buffer
        case .joint(let s): return .section(s)
        case .point(let index):
            let p = points[index]
            if p.motion != nil { return .impassable }
            let selected = p.position ? p.reverse : p.normal
            return section == p.common ? .section(selected) : section == selected ? .section(p.common) : .impassable
        }
    }
    init() {
        for w in inputLines("layout.txt") {
            switch w[0] {
            case "SECTION": sections.append(Section(w)); connections.append([nil, nil])
            case "JOINT": let a = section(w[1]), b = section(w[2]); connections[a][1] = .joint(b); connections[b][0] = .joint(a)
            case "POINT":
                let common = section(w[3]), normal = section(w[4]), reverse = section(w[5]), side = w[2] == "R" ? 1 : 0, index = points.count
                connections[common][side] = .point(index); connections[normal][1 - side] = .point(index); connections[reverse][1 - side] = .point(index)
                points.append(Point(w, common: common, normal: normal, reverse: reverse))
            case "SIGNAL": signals.append(Signal(w, section: section(w[2])))
            case "BUFFER":
                let s = section(w[2]), end = w[3] == "R" ? 1 : 0
                connections[s][end] = .buffer; buffers.append(Buffer(name: w[1], section: s, end: end, row: Int(w[4])!, column: Int(w[5])!))
            case "BOUNDARY":
                let s = section(w[2]), end = w[3] == "R" ? 1 : 0, index = boundaries.count
                connections[s][end] = .boundary(index); boundaries.append(Boundary(name: w[1], section: s, end: end))
            default: labels.append(Label(row: Int(w[1])!, column: Int(w[2])!, text: w[3]))
            }
        }
    }
}
