import Foundation

struct Eviction {
    let block: Int
    let copies: [String]
    let dirty: Bool
}

final class Transaction {
    let number: Int, start: Int, core: Int, block: Int
    let kind: TransactionKind
    var snoops: [String] = []
    var snoopHits = 0, invalidations = 0
    var supplier: Int?
    var flush = false
    var l2Hit: Bool?
    var eviction: Eviction?
    var source = ""
    init(number: Int, start: Int, core: Int, kind: TransactionKind, block: Int) {
        self.number = number; self.start = start; self.core = core; self.kind = kind; self.block = block
    }
}

final class Bus {
    let latency: Int
    var free = 0, wait = 0
    var transactions: [Transaction] = []
    var busy: Int { latency * transactions.count }
    init(_ latency: Int) { self.latency = latency }
    func assign(core: Int, kind: TransactionKind, block: Int, requested: Int) -> Transaction {
        let start = max(requested, free)
        wait += start - requested; free = start + latency
        let tx = Transaction(number: transactions.count + 1, start: start, core: core, kind: kind, block: block)
        transactions.append(tx)
        return tx
    }
    func line(_ tx: Transaction, lineSize: Int) -> String {
        var line = "\(tx.number) \(tx.start) c\(tx.core) \(tx.kind.rawValue) \(hexAddress(tx.block * lineSize))"
        if tx.kind == .writeback { return line }
        line += " snoop " + (tx.snoops.isEmpty ? "none" : tx.snoops.joined(separator: " "))
        if tx.kind == .upgrade { return line }
        if tx.kind == .read || tx.kind == .readExclusive { line += " data " + tx.source }
        line += " l2 " + (tx.l2Hit! ? "hit" : "miss")
        if let eviction = tx.eviction {
            line += " evict \(hexAddress(eviction.block * lineSize)) "
                + (eviction.copies.isEmpty ? "none" : eviction.copies.joined(separator: " "))
                + (eviction.dirty ? " dirty" : " clean")
        }
        return line
    }
}
