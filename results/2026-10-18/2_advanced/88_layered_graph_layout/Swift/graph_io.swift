import Foundation
struct Settings {
    static let names = ["layering", "width", "promotion", "heuristic", "sweeps", "node_sep", "dummy_sep", "layer_gap", "direction", "sifting", "reduce", "restarts", "seed"]
    var values = ["longest", "4", "off", "barycenter", "12", "2", "1", "3", "TB", "off", "off", "0", "1"]
    func text(_ name: String) -> String {
        values[Self.names.firstIndex(of: name)!]
    }
    func integer(_ name: String) -> Int {
        Int(text(name))!
    }
    func on(_ name: String) -> Bool {
        text(name) == "on"
    }
    mutating func set(_ name: String, _ value: String) -> Bool {
        guard let index = Self.names.firstIndex(of: name) else {
            return false
        }
        let words: [String]
        switch name {
            case "layering": words = ["longest", "coffman"]
            case "promotion", "sifting", "reduce": words = ["on", "off"]
            case "heuristic": words = ["barycenter", "median"]
            case "direction": words = ["TB", "BT", "LR", "RL"]
            default: words = []
        }
        if !words.isEmpty {
            if !words.contains(value) {
                return false
            };
            values[index] = value;
            return true
        }
        let low: Int, high: Int
        switch name {
            case "width": low = 1;
            high = 40
            case "sweeps": low = 0;
            high = 50
            case "node_sep", "dummy_sep": low = 1;
            high = 9
            case "layer_gap": low = 2;
            high = 9
            case "restarts": low = 0;
            high = 9
            default: low = 1;
            high = 2147483646
        }
        guard !value.isEmpty, value.count <= 10, value.utf8.allSatisfy({
            (48...57).contains($0)
        }), let number = Int(value), low <= number, number <= high else {
            return false
        }
        values[index] = String(number)
        return true
    }
}
final class Graph {
    let name: String
    var settings: Settings, nodes: [(Int, String)] = [], edges: [(Int, Int)] = [], path: (Int, Int)?
    var loops = 0, duplicates = 0, error: (String, Int)?
    init(_ name: String, _ settings: Settings) {
        self.name = name;
        self.settings = settings
    }
}
enum GraphIO {
    static func read() -> [Graph] {
        var defaults = Settings()
        for line in (try! String(contentsOfFile: "input/params.txt", encoding: .ascii)).split(separator: "\n") where line.first != "#" {
            let a = line.split(separator: " ").map(String.init);
            _ = defaults.set(a[0], a[1])
        }
        var result: [Graph] = [], current: Graph?, nodes: [Int: String] = [:]
        let lines = try! String(contentsOfFile: "input/graphs.txt", encoding: .ascii).components(separatedBy: "\n")
        for (i, line) in lines.enumerated() where !line.isEmpty && line.first != "#" {
            let a = line.split(separator: " ").map(String.init)
            if a[0] == "GRAPH" {
                current = Graph(a[1], defaults);
                nodes = [:];
                continue
            }
            let graph = current!
            if a[0] == "END" {
                if graph.error == nil && nodes.isEmpty {
                    graph.error = ("no_nodes", i + 1)
                }
                graph.nodes = nodes.keys.sorted().map {
                    ($0, nodes[$0]!)
                }
                if graph.error == nil {
                    let numbering = Dictionary(uniqueKeysWithValues: graph.nodes.enumerated().map {
                        ($0.element.0, $0.offset)
                    })
                    graph.edges = graph.edges.map {
                        (numbering[$0.0]!, numbering[$0.1]!)
                    }
                    graph.path = graph.path.map {
                        (numbering[$0.0]!, numbering[$0.1]!)
                    }
                }
                result.append(graph);
                current = nil;
                continue
            }
            if graph.error != nil {
                continue
            }
            let error: String?
            switch a[0] {
                case "OPTION": error = graph.settings.set(a[1], a[2]) ? nil : "bad_option"
                case "NODE":
                let id = Int(a[1])!
                if nodes[id] != nil {
                    error = "duplicate_node"
                }
                else if nodes.count == 40 {
                    error = "too_many_nodes"
                }
                else {
                    nodes[id] = a[2];
                    error = nil
                }
                case "EDGE":
                let u = Int(a[1])!, v = Int(a[2])!
                if nodes[u] == nil || nodes[v] == nil {
                    error = "unknown_node"
                }
                else if u == v {
                    graph.loops += 1;
                    error = nil
                }
                else if graph.edges.contains(where: {
                    $0.0 == u && $0.1 == v
                }) {
                    graph.duplicates += 1;
                    error = nil
                }
                else {
                    graph.edges.append((u, v));
                    error = nil
                }
                default:
                let u = Int(a[1])!, v = Int(a[2])!
                if nodes[u] == nil || nodes[v] == nil {
                    error = "unknown_node"
                }
                else {
                    graph.path = (u, v);
                    error = nil
                }
            }
            if let error {
                graph.error = (error, i + 1)
            }
        }
        return result
    }
}
