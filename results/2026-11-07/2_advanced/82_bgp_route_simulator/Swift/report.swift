import Foundation
enum Report {
    static func path(_ path: [Int]) -> String { path.map(String.init).joined(separator: ",") }
    static func attribute(_ a: Attribute) -> String { "path \(path(a.path)) origin \(a.origin) med \(a.med) comm \(Community.text(a.communities))" }
    static func route(_ route: Route?, _ topology: Topology) -> String {
        guard let route else { return "NONE" }
        let a = route.attribute
        if let link = route.link { return "next \(route.neighbor) path \(path(a.path)) link \(topology.links[link].name) lp \(route.localPref) med \(a.med) origin \(a.origin) comm \(Community.text(a.communities))" }
        return "LOCAL origin \(a.origin) comm \(Community.text(a.communities))"
    }
    static func write(_ name: String, _ lines: [String]) { try! FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true); try! (lines.isEmpty ? "" : lines.map { line in var text = line; while text.last == " " { text.removeLast() }; return text }.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: false, encoding: .ascii) }
}
