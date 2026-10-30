#include "coherence.h"
Transaction *bus_assign(Bus *bus, int core, TransactionKind kind, Number block, Number requested) {
    Number start = requested > bus->free ? requested : bus->free;
    bus->wait += start - requested;
    bus->free = start + bus->latency;
    Transactions_add(&bus->transactions,
                     (Transaction){.number = (Number)bus->transactions.count + 1,
                                   .start = start,
                                   .block = block,
                                   .core = core,
                                   .kind = kind,
                                   .supplier = -1});
    return &bus->transactions.items[bus->transactions.count - 1];
}
char *bus_line(const Bus *bus, const Transaction *tx, int line_size, int cores) {
    (void)bus;
    char *out = format("%lld %lld c%d %s %s", tx->number, tx->start, tx->core,
                       transaction_names[tx->kind], hex_address(tx->block * line_size));
    if (tx->kind == WB)
        return out;
    Names snoops = {0};
    for (int core = 0; core < cores; ++core)
        if (tx->snoop_old[core])
            Names_add(&snoops, format("c%d:%c>%c", core, tx->snoop_old[core], tx->snoop_new[core]));
    out = format("%s snoop %s", out, snoops.count ? join(snoops, " ") : "none");
    if (tx->kind == BUS_UPGR)
        return out;
    if (tx->kind == BUS_RD || tx->kind == BUS_RDX)
        out = format("%s data %s", out,
                     tx->supplier >= 0 ? format("c%d", tx->supplier)
                     : tx->l2_hit      ? "L2"
                                       : "mem");
    out = format("%s l2 %s", out, tx->l2_hit ? "hit" : "miss");
    if (tx->evicted) {
        Names copies = {0};
        for (int core = 0; core < cores; ++core)
            if (tx->copies[core])
                Names_add(&copies, format("c%d:%c", core, tx->copies[core]));
        out = format("%s evict %s %s %s", out, hex_address(tx->evicted_block * line_size),
                     copies.count ? join(copies, " ") : "none",
                     tx->dirty_eviction ? "dirty" : "clean");
    }
    return out;
}
