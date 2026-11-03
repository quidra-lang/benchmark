import Foundation

let transactionKinds: [TransactionKind] = [.read, .readExclusive, .upgrade, .write, .writeback]
let services = ["l1", "upgrade", "through", "cache", "l2", "memory"]
let missKinds = ["compulsory", "capacity", "conflict", "coherence"]
let snoopCounters = ["invalidations_sent", "invalidations_received", "supplied", "back_invalidations"]

func fraction(_ numerator: Int, _ denominator: Int) -> String {
    var a = numerator, b = denominator
    while b != 0 { (a, b) = (b, a % b) }
    return "\(numerator / a)/\(denominator / a)"
}
func decimal(_ numerator: Int, _ denominator: Int) -> String {
    let value = (2 * numerator * 100 + denominator) / (2 * denominator)
    return "\(value / 100)." + String(format: "%02d", value % 100)
}
func coreString(_ cores: Set<Int>) -> String { cores.isEmpty ? "-" : cores.sorted().map(String.init).joined() }

final class Counters {
    var values: [String: Int] = [:]
    var finish = 0
    subscript(_ key: String) -> Int {
        get { values[key, default: 0] }
        set { values[key] = newValue }
    }
}

func totalCounters(_ cores: [Counters]) -> Counters {
    let total = Counters()
    for core in cores {
        for (key, value) in core.values { total[key] += value }
        total.finish = max(total.finish, core.finish)
    }
    return total
}

func rangeCounts(_ values: [Int], labels: [String], limits: [Int]) -> String {
    var counts = Array(repeating: 0, count: labels.count)
    for value in values { counts[limits.firstIndex(where: { value <= $0 }) ?? limits.count] += 1 }
    return zip(labels, counts).map { "\($0.0):\($0.1)" }.joined(separator: " ")
}

func sixLines(_ label: String, _ c: Counters) -> [String] {
    ["\(label) accesses \(c["accesses"]) reads \(c["reads"]) writes \(c["writes"]) hits \(c["hits"]) misses \(c["misses"]) fences \(c["fences"])",
     "\(label) misses " + missKinds.map { "\($0) \(c[$0])" }.joined(separator: " ") + " true_sharing \(c["true_sharing"]) false_sharing \(c["false_sharing"])",
     "\(label) service " + services.map { "\($0) \(c[$0])" }.joined(separator: " "),
     "\(label) bus " + transactionKinds.map { "\($0.rawValue) \(c[$0.rawValue])" }.joined(separator: " "),
     "\(label) snoop " + snoopCounters.map { "\($0) \(c[$0])" }.joined(separator: " "),
     "\(label) time latency \(c["latency"]) amat \(fraction(c["latency"], c["accesses"])) \(decimal(c["latency"], c["accesses"])) fence_stall \(c["fence_stall"]) finish \(c.finish)"]
}
