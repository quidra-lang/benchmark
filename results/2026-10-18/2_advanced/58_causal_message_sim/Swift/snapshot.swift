import Foundation

struct SnapshotRecord { let time: Int; let reason: String; let balance: Int; let lamport: Int; let vector: [Int]; let pending: [Int] }
struct MarkerTimes { let sent: Int; var accepted: Int? }
final class Snapshot {
    let name: String
    let start: Int
    var completion: Int?
    var records: [SnapshotRecord?]
    var channelStates: [ChannelKey: [Int]]
    var markers: [ChannelKey: MarkerTimes] = [:]
    var accepted = Set<ChannelKey>()
    var ignored: [(process: Int, time: Int)] = []
    init(_ name: String, _ start: Int, _ count: Int, _ channels: [ChannelKey]) { self.name = name; self.start = start; records = Array(repeating: nil, count: count); channelStates = Dictionary(uniqueKeysWithValues: channels.map { ($0, []) }) }
    func record(_ index: Int, _ process: ProcessState, _ time: Int, _ reason: String) { records[index] = SnapshotRecord(time: time, reason: reason, balance: process.balance, lamport: process.lamport, vector: process.vector, pending: process.holdback) }
    func acceptMarker(_ channel: ChannelKey, _ time: Int) { accepted.insert(channel); markers[channel]!.accepted = time; if accepted.count == records.count * (records.count - 1) { completion = time } }
    var cut: [Int] { records.indices.map { records[$0]!.vector[$0] } }
    var vectorConsistent: Bool { let frontier = cut; return records.allSatisfy { lessEqual($0!.vector, frontier) } }
    func recordedCopies(_ order: [ChannelKey]) -> (channels: [Int], pending: [Int]) { (order.flatMap { channelStates[$0]! }, records.flatMap { $0!.pending }) }
}
struct CutDetails { let orphans: [Int]; let transit: [Int]; let balances: Int; let money: Int; var consistent: Bool { orphans.isEmpty } }
func cutDetails(_ cut: [Int], _ processes: [ProcessState], _ events: [Event], _ copies: [MessageCopy]) -> CutDetails {
    var orphans: [Int] = [], transit: [Int] = []
    for (i, copy) in copies.enumerated() {
        let sent = events[copy.sendEvent].localNumber <= cut[copy.source], received = copy.receiveEvent.map { events[$0].localNumber <= cut[copy.destination] } ?? false
        if received && !sent { orphans.append(i) }; if sent && !received { transit.append(i) }
    }
    let balances = processes.indices.reduce(0) { $0 + processes[$1].balanceAtCut(cut[$1], events) }, money = balances + transit.reduce(0) { $0 + copies[$1].amount }
    return CutDetails(orphans: orphans, transit: transit, balances: balances, money: money)
}
func transitMatch(_ channels: [Int], _ pending: [Int], _ transit: [Int]) -> Bool { (channels + pending).sorted() == transit.sorted() }
func copyLabel(_ copy: MessageCopy, _ names: [String]) -> String { "m\(copy.message + 1)->\(names[copy.destination])" }
