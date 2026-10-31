import Foundation

enum CoherenceProtocol: String {
    case vi = "VI"
    case msi = "MSI"
    case mesi = "MESI"
    case moesi = "MOESI"
}

enum CacheState: String {
    case invalid = "I"
    case valid = "V"
    case modified = "M"
    case owned = "O"
    case exclusive = "E"
    case shared = "S"
    case clean = "C"
    case dirty = "D"

    var dirtyL1: Bool { self == .modified || self == .owned }
}

enum Operation: String {
    case read = "R"
    case write = "W"
    case fence = "FENCE"
}

enum TransactionKind: String {
    case read = "BusRd"
    case readExclusive = "BusRdX"
    case upgrade = "BusUpgr"
    case write = "BusWr"
    case writeback = "WB"
}

func requester(_ coherence: CoherenceProtocol, old: CacheState, operation: Operation,
               otherHasLine: Bool) -> (TransactionKind?, CacheState) {
    if coherence == .vi {
        if operation == .read { return old == .invalid ? (.read, .valid) : (nil, .valid) }
        return (.write, old == .invalid ? .invalid : .valid)
    }
    if old == .invalid {
        if operation == .write { return (.readExclusive, .modified) }
        return (.read, coherence == .msi || otherHasLine ? .shared : .exclusive)
    }
    if operation == .read { return (nil, old) }
    if old == .modified || old == .exclusive { return (nil, .modified) }
    return (.upgrade, .modified)
}

func snoop(_ coherence: CoherenceProtocol, old: CacheState, transaction: TransactionKind) -> (CacheState, Bool, Bool) {
    if coherence == .vi { return (transaction == .read ? .valid : .invalid, false, false) }
    if transaction == .read {
        if old == .modified { return coherence == .moesi ? (.owned, true, false) : (.shared, true, true) }
        if old == .owned { return (.owned, true, false) }
        return (.shared, false, false)
    }
    return (.invalid, transaction == .readExclusive && old.dirtyL1, false)
}
