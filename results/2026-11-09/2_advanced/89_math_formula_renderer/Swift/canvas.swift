import Foundation
enum Canvas {
    static func paint(_ box: BoxNode, _ x: Int, _ y: Int, _ grid: inout [[UInt8]]) {
        for (dx, dy, text) in box.strings {
            for (i, c) in text.utf8.enumerated() where c != 32 {
                grid[y + dy][x + dx + i] = c
            }
        }
        for child in box.children {
            paint(child.node, x + child.x, y + child.y, &grid)
        }
    }
    static func describe(_ box: BoxNode, _ x: Int, _ y: Int, _ level: Int, _ role: String, _ lines: inout [String], _ kinds: inout [String: Int], _ depth: inout Int) {
        lines.append(String(repeating: " ", count: level * 2) + role + box.description + " x=\(x) y=\(y) w=\(box.width) h=\(box.height) b=\(box.baseline)")
        kinds[String(box.description.split(separator: " ")[0]), default: 0] += 1
        depth = max(depth, level + 1)
        for child in box.children {
            describe(child.node, x + child.x, y + child.y, level + 1, child.role, &lines, &kinds, &depth)
        }
    }
    static func trim(_ text: String) -> String {
        String(text.reversed().drop(while: {
            $0 == " "
        }).reversed())
    }
    static func lines(_ grid: [[UInt8]]) -> [String] {
        grid.map {
            row in var bytes = row;
            while bytes.last == 32 {
                bytes.removeLast()
            };
            return String(bytes: bytes, encoding: .ascii)!
        }
    }
}
