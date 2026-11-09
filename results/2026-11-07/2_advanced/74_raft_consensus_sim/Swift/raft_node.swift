import Foundation

enum Command: Equatable {
    case noop, set(String, Int), add(String, Int), delete(String), get(String)
    var key: String? { switch self { case .noop: return nil; case let .set(key, _), let .add(key, _), let .delete(key), let .get(key): return key } }
    var text: String { switch self { case .noop: return "NOOP"; case let .set(key, value): return "SET \(key) \(value)"; case let .add(key, value): return "ADD \(key) \(value)"; case let .delete(key): return "DEL " + key; case let .get(key): return "GET " + key } }
}
struct Entry: Equatable { let term: Int; let command: Command; let request: Int }
enum Role: String { case follower = "FOLLOWER", candidate = "CANDIDATE", leader = "LEADER" }
struct NodeStatistics {
    var elections = 0, leaderTerms = 0, votesGranted = 0, leaderTicks = 0
    var aeOK = 0, aeFail = 0, appended = 0, truncated = 0, applies = 0
}
final class RaftNode {
    let number: Int
    var term = 0
    var votedFor: Int?
    var log: [Entry] = []
    var up = true
    var stats = NodeStatistics()
    var role = Role.follower
    var commit = 0, applied = 0
    var store: [String: Int] = [:]
    var knownLeader: Int?
    var votes: Set<Int> = []
    var electionDeadline: Int?, electionIndex: Int?
    var next: [Int: Int] = [:], match: [Int: Int] = [:]
    var heartbeatDeadline: Int?, quorumDeadline: Int?
    var heard: Set<Int> = []
    var transferTarget: Int?, transferDeadline: Int?
    var transferSent = false
    init(_ number: Int) { self.number = number }
    var lastIndex: Int { log.count }
    var lastTerm: Int { log.last?.term ?? 0 }
    func termAt(_ index: Int) -> Int { index == 0 ? 0 : log[index - 1].term }
    func acceptsLog(_ index: Int, _ term: Int) -> Bool { term > lastTerm || (term == lastTerm && index >= lastIndex) }
    func cancelTransfer() { transferTarget = nil; transferDeadline = nil; transferSent = false }
    func resetVolatile() {
        role = .follower; commit = 0; applied = 0; store = [:]; knownLeader = nil; votes = []; electionDeadline = nil; electionIndex = nil
        next = [:]; match = [:]; heartbeatDeadline = nil; quorumDeadline = nil; heard = []; cancelTransfer()
    }
    func crash() { up = false; resetVolatile() }
}
func applyCommand(_ store: inout [String: Int], _ command: Command) -> String? {
    switch command {
    case .noop: return nil
    case let .set(key, value): store[key] = value; return "ok"
    case let .add(key, increment): let value = store[key, default: 0] + increment; store[key] = value; return String(value)
    case let .delete(key): return store.removeValue(forKey: key) == nil ? "missing" : "deleted"
    case let .get(key): return store[key].map(String.init) ?? "missing"
    }
}
