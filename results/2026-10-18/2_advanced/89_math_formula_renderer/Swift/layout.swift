struct Params {
    let width: Int, indent: Int, rel: Int, binary: Int, punctuation: Int, colGap: Int, rowGap: Int
}
enum Layout {
    static func types(_ node: Node) -> (Int, Int) {
        switch node {
            case .atom(let kind, let value, _): let type = Boxes.atomType(kind, value);
            return (type, type)
            case .delimited: return (4, 5)
            case .script(let base, _, _): return types(base)
            case .binary(let name, _, let base) where name == "overset" || name == "underset": return types(base)
            default: return (0, 0)
        }
    }
    static func word(_ node: Node) -> Bool {
        switch node {
            case .atom(let kind, let value, _) where kind == "command": let name = String(value.dropFirst());
            return Lexer.greek.contains(name) || name == "infty"
            case .script(let base, _, _): return word(base)
            default: return false
        }
    }
    static func alphanumeric(_ node: Node) -> Bool {
        if word(node) {
            return true
        }
        switch node {
            case .atom(let kind, _, _): return kind == "identifier" || kind == "number"
            case .script(let base, _, _): return alphanumeric(base)
            case .accent(let name, let body) where ["overline", "hat", "vec", "dot", "tilde"].contains(name): return alphanumeric(body)
            default: return false
        }
    }
    static func spacing(_ nodes: [Node], _ script: Bool, _ params: Params) -> ([(Int, Int)], [Int]) {
        var types = nodes.map(self.types)
        for i in types.indices {
            if types[i].0 == 2 && (i == 0 || [1, 2, 3, 4, 6].contains(types[i - 1].1)) {
                types[i] = (0, 0)
            }
            if [3, 5, 6].contains(types[i].0) && i > 0 && types[i - 1].1 == 2 {
                types[i - 1] = (0, 0)
            }
        }
        if let last = types.last, last.1 == 2 {
            types[types.count - 1] = (0, 0)
        }
        let table = [[0,1,2,3,0,0,0],[1,1,0,3,0,0,0],[2,2,0,0,2,0,0],[3,3,0,0,3,0,0],[0,0,0,0,0,0,0],[0,1,2,3,0,0,0],[4,4,0,4,4,4,4]]
        var gaps: [Int] = []
        for i in 0..<max(0, nodes.count - 1) {
            let gap: Int
            if alphanumeric(nodes[i]) && alphanumeric(nodes[i + 1]) && (word(nodes[i]) || word(nodes[i + 1])) {
                gap = 1
            }
            else {
                switch table[types[i].1][types[i + 1].0] {
                    case 0: gap = 0;
                    case 1: gap = 1;
                    case 2: gap = script ? 0 : params.binary;
                    case 3: gap = script ? 0 : params.rel;
                    default: gap = script ? 0 : params.punctuation
                }
            }
            gaps.append(gap)
        }
        return (types, gaps)
    }
    static func row(_ elements: [BoxNode], _ gaps: [Int], _ description: String, _ roles: [String] = []) -> BoxNode {
        let ascent = elements.map(\.baseline).max() ?? 0, descent = elements.map {
            $0.height - 1 - $0.baseline
        }.max() ?? 0
        let result = BoxNode(elements.reduce(0) {
            $0 + $1.width
        } + gaps.reduce(0, +), ascent + descent + 1, ascent, description)
        var x = 0
        for (i, box) in elements.enumerated() {
            result.child(box, x, ascent - box.baseline, i < roles.count ? roles[i] : "");
            x += box.width + (i < gaps.count ? gaps[i] : 0)
        }
        return result
    }
}
