import Foundation

func real(_ value: Double, _ places: Int) -> String { let text = String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), places, value); return text.first == "-" && Double(text) == 0 ? String(text.dropFirst()) : text }
func symbols(_ mask: Int, _ count: Int) -> String { (0..<count).map { mask & (1 << $0) != 0 ? "*" : "." }.joined() }
func childOrder(_ rooted: Rooted, _ names: [String]) -> [Int: [Int]] { var minimum: [Int: String] = [:], children: [Int: [Int]] = [:]; for node in rooted.order.reversed() { if node < rooted.tree.size { minimum[node] = names[node]; children[node] = [] } else { let ordered = rooted.children[node]!.sorted { minimum[$0]! < minimum[$1]! }; children[node] = ordered; minimum[node] = minimum[ordered[0]]! } }; return children }
func newick(_ tree: Tree, _ names: [String], _ outgroup: Int, lengths: Bool = false, support: [Int: Int]? = nil) -> String {
    let rooted = tree.rooted(outgroup), children = childOrder(rooted, names)
    func text(_ node: Int) -> String { var result: String; if node < tree.size { result = names[node] } else { result = "(" + children[node]!.map { text($0) }.joined(separator: ",") + ")"; if let support, node != rooted.root { result += String(support[rooted.masks[node]!, default: 0]) } }; if lengths && node != rooted.root { result += ":" + real(tree.adjacent[node]![rooted.parents[node]!]!, 5) }; return result }
    return text(rooted.root) + ";"
}
func cladogram(_ tree: Tree, _ names: [String], _ outgroup: Int, _ support: [Int: Int]) -> [String] { let rooted = tree.rooted(outgroup), children = childOrder(rooted, names); var lines = ["*"]; func descend(_ node: Int, _ prefix: String) { for (index, child) in children[node]!.enumerated() { let last = index == children[node]!.count - 1, connector = last ? "`-- " : "|-- ", label = child < tree.size ? names[child] : "[\(support[rooted.masks[child]!, default: 0])]"; lines.append(prefix + connector + label); descend(child, prefix + (last ? "    " : "|   ")) } }; descend(rooted.root, ""); return lines }
func writeLines(_ name: String, _ lines: [String]) throws { try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true); try (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: false, encoding: .ascii) }
