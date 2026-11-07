import Foundation
func words(_ file: String) -> [[String]] { try! String(contentsOfFile: "input/" + file, encoding: .ascii).split(separator: "\n").map { $0.split(separator: " ").map(String.init) } }
func parseAddress(_ text: String) -> Int { text.split(separator: ".").reduce(0) { $0 * 256 + Int($1)! } }
func addressText(_ value: Int) -> String { "\(value >> 24).\((value >> 16) & 255).\((value >> 8) & 255).\(value & 255)" }
struct Prefix: Hashable, Comparable {
    let address: Int, length: Int
    init(_ text: String) { let pieces = text.split(separator: "/"); address = parseAddress(String(pieces[0])); length = Int(pieces[1])! }
    func contains(_ value: Int) -> Bool { length == 0 || value >> (32 - length) == address >> (32 - length) }
    var text: String { "\(addressText(address))/\(length)" }
    static func < (a: Self, b: Self) -> Bool { a.address == b.address ? a.length < b.length : a.address < b.address }
}
final class Link {
    let name: String, a: Int, b: Int, peer: Bool, delay: Int, mrai: Int
    var up = true, downs = 0
    init(_ w: [String]) { name = w[1]; a = Int(w[2])!; b = Int(w[3])!; peer = w[4] == "P2P"; delay = Int(w[5])!; mrai = Int(w[6])! }
    func other(_ x: Int) -> Int { x == a ? b : a }
    func role(_ x: Int) -> Int { peer ? 1 : x == a ? 0 : 2 }
    func roleText(_ x: Int) -> String { ["customer", "peer", "provider"][role(x)] }
    func symbol(_ x: Int) -> Character { Array("DPU")[role(x)] }
}
final class Topology {
    var routers: [Int: Int] = [:], links: [Link] = [], initial: [(Int, Prefix, String, Set<Community>)] = []
    var ases: [Int] { routers.keys.sorted() }
    init() {
        for w in words("topology.txt") {
            switch w[0] {
            case "AS": routers[Int(w[1])!] = parseAddress(w[2])
            case "LINK": links.append(Link(w))
            default: initial.append((Int(w[1])!, Prefix(w[2]), w[3], Set(w.dropFirst(4).map(Community.init))))
            }
        }
    }
    func sessions(_ x: Int) -> [Int] { links.indices.filter { links[$0].a == x || links[$0].b == x } }
    func connecting(_ a: Int, _ b: Int) -> Link { links.first { ($0.a == a && $0.b == b) || ($0.a == b && $0.b == a) }! }
}
