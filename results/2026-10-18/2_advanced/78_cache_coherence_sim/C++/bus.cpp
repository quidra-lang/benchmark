#include "coherence.hpp"
Transaction &Bus::assign(int core, TransactionKind kind, Number block, Number requested) {
    Number start = std::max(requested, free);
    wait += start - requested;
    free = start + latency;
    transactions.push_back(Transaction{Number(transactions.size()) + 1, start, core, kind, block});
    return transactions.back();
}
std::string Bus::log_line(const Transaction &tx, int line_size) const {
    std::string out = text(tx.number, " ", tx.start, " c", tx.core, " ",
                           transaction_names[int(tx.kind)], " ", hex_address(tx.block * line_size));
    if (tx.kind == TransactionKind::WB)
        return out;
    out += " snoop " + (tx.snoops.empty() ? "none" : join(tx.snoops));
    if (tx.kind == TransactionKind::BusUpgr)
        return out;
    if (tx.kind == TransactionKind::BusRd || tx.kind == TransactionKind::BusRdX)
        out += " data " + tx.source;
    out += std::string(" l2 ") + (tx.l2_hit ? "hit" : "miss");
    if (tx.evicted)
        out += text(" evict ", hex_address(*tx.evicted * line_size), " ",
                    tx.copies.empty() ? "none" : join(tx.copies), " ",
                    tx.dirty_eviction ? "dirty" : "clean");
    return out;
}
