import Foundation

struct Product {
    let name: String
    let category: String
    let price: Int
}
final class Transaction {
    let tid: String
    let customer: String
    let day: Int
    var counts: [String: Int] = [:]
    var products: Set<String> { Set(counts.keys) }
    var units: Int { counts.values.reduce(0, +) }
    init(_ tid: String, _ customer: String, _ day: Int) { self.tid = tid; self.customer = customer; self.day = day }
    func add(_ name: String) -> Bool { let duplicate = counts[name] != nil; counts[name, default: 0] += 1; return duplicate }
}
func readLines(_ path: String) throws -> [String] { try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n").map(String.init) }
func readRecords(_ name: String) throws -> [[String]] { try readLines("input/\(name)").dropFirst().map { $0.split(separator: ",").map(String.init) } }
func contains(_ items: Set<String>, _ candidate: [String]) -> Bool { candidate.allSatisfy { items.contains($0) } }
func extendedBasket(_ items: Set<String>, _ taxonomy: [String: String]) -> Set<String> { items.union(items.map { taxonomy[$0]! }) }
struct BasketIndex {
    let baskets: [Set<String>]
    private let columns: [String: Set<Int>]
    init(_ baskets: [Set<String>]) {
        self.baskets = baskets
        var columns: [String: Set<Int>] = [:]
        for (index, basket) in baskets.enumerated() { for item in basket { columns[item, default: []].insert(index) } }
        self.columns = columns
    }
    func count(_ items: [String]) -> Int {
        if items.isEmpty { return baskets.count }
        guard var matches = columns[items[0]] else { return 0 }
        for item in items.dropFirst() { guard let column = columns[item] else { return 0 }; matches.formIntersection(column) }
        return matches.count
    }
}
