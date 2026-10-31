struct Child {
    let role: String, x: Int, y: Int, node: BoxNode
}
final class BoxNode {
    let width: Int, height: Int, baseline: Int, description: String
    var children: [Child] = [], strings: [(Int, Int, String)] = []
    init(_ width: Int, _ height: Int, _ baseline: Int, _ description: String) {
        self.width = width;
        self.height = height;
        self.baseline = baseline;
        self.description = description
    }
    static func text(_ display: String, _ description: String) -> BoxNode {
        let node = BoxNode(display.count, 1, 0, description);
        node.string(0, 0, display);
        return node
    }
    func child(_ node: BoxNode, _ x: Int, _ y: Int, _ role: String = "") {
        children.append(Child(role: role, x: x, y: y, node: node))
    }
    func string(_ x: Int, _ y: Int, _ text: String) {
        strings.append((x, y, text))
    }
    func delimiter(_ text: String, _ x: Int) {
        for (y, line) in Boxes.delimiter(text, height).enumerated() {
            string(x, y, line)
        }
    }
}
enum Boxes {
    static func delimiter(_ text: String, _ height: Int) -> [String] {
        if text == "." {
            return []
        }
        let plain = text == "\\{" ? "{" : text == "\\}" ? "}" : text
        if height == 1 {
            return [plain]
        }
        var glyph = Array(repeating: plain, count: height)
        if text == "(" || text == "\\{" {
            glyph = Array(repeating: "|", count: height);
            glyph[0] = "/";
            glyph[height - 1] = "\\"
            if text == "\\{" && height >= 3 {
                glyph[(height - 1) / 2] = "<"
            }
        } else if text == ")" || text == "\\}" {
            glyph = Array(repeating: "|", count: height);
            glyph[0] = "\\";
            glyph[height - 1] = "/"
            if text == "\\}" && height >= 3 {
                glyph[(height - 1) / 2] = ">"
            }
        }
        return glyph
    }
    static func large(_ name: String) -> [String] {
        name == "sum" ? ["\\--", " > ", "/--"] : name == "prod" ? ["___", "| |", "| |"] : [" /", " |", "/ "]
    }
    static func atomType(_ kind: String, _ value: String) -> Int {
        if kind == "command" {
            return Lexer.symbol(String(value.dropFirst()))!.1
        }
        if kind != "symbol" {
            return 0
        }
        switch value {
            case "+", "-", "*": return 2
            case "=", "<", ">", ":": return 3
            case "(", "[": return 4
            case ")", "]", "!": return 5
            case ",", ";": return 6
            default: return 0
        }
    }
}
