import Foundation
struct Cell: Hashable {
    let row: Int, column: Int
}
final class Canvas {
    let main: Int, direction: String, rows: Int, columns: Int
    var lines: [[UInt8]], arrows: [[UInt8]], boxes: [[UInt8]], highlighted: [[Bool]]
    init(_ main: Int, _ secondary: Int, _ direction: String) {
        self.main = main;
        self.direction = direction
        let vertical = direction == "TB" || direction == "BT"
        rows = vertical ? main : secondary;
        columns = vertical ? secondary : main
        lines = Array(repeating: Array(repeating: 0, count: columns), count: rows);
        arrows = lines;
        boxes = lines
        highlighted = Array(repeating: Array(repeating: false, count: columns), count: rows)
    }
    func map(_ main: Int, _ secondary: Int) -> Cell {
        let m = direction == "BT" || direction == "RL" ? self.main - 1 - main : main
        return direction == "TB" || direction == "BT" ? Cell(row: m, column: secondary) : Cell(row: secondary, column: m)
    }
    func line(_ m: Int, _ c: Int, _ main: Bool) {
        let p = map(m, c), vertical = direction == "TB" || direction == "BT";
        lines[p.row][p.column] |= main == vertical ? 1 : 2
    }
    func corner(_ m: Int, _ c: Int) {
        let p = map(m, c);
        lines[p.row][p.column] |= 4
    }
    func arrow(_ m: Int, _ c: Int, _ reversed: Bool) {
        let p = map(m, c), arrow: UInt8
        switch (direction, reversed) {
            case ("TB", false), ("BT", true): arrow = 118
            case ("TB", true), ("BT", false): arrow = 94
            case ("LR", false), ("RL", true): arrow = 62
            default: arrow = 60
        }
        arrows[p.row][p.column] = arrow
    }
    func highlight(_ row: Int, _ column: Int) {
        highlighted[row][column] = true
    }
    func label(_ row: Int, _ column: Int, _ text: String) {
        for (i, c) in text.utf8.enumerated() {
            boxes[row][column + i] = c
        }
    }
    func crossings() -> Int {
        lines.reduce(0) {
            $0 + $1.filter {
                $0 & 3 == 3
            }.count
        }
    }
    func report() -> [String] {
        var result = ["    " + (0..<columns).map {
            String($0 % 10)
        }.joined()]
        for row in 0..<rows {
            let number = String(row)
            var text = Array((String(repeating: " ", count: 3 - number.count) + number + " ").utf8)
            for column in 0..<columns {
                let c: UInt8
                if boxes[row][column] != 0 {
                    c = boxes[row][column]
                }
                else if arrows[row][column] != 0 {
                    c = arrows[row][column]
                }
                else if highlighted[row][column] {
                    c = 35
                }
                else {
                    switch lines[row][column] {
                        case 0: c = 32;
                        case 1: c = 124;
                        case 2: c = 45;
                        default: c = 43
                    }
                }
                text.append(c)
            }
            while text.last == 32 {
                text.removeLast()
            }
            result.append(String(bytes: text, encoding: .ascii)!)
        }
        return result
    }
}
