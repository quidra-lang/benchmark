mutable struct BusTransaction
    number::Int
    start::Int
    core::Int
    kind::String
    block::Int
    snoops::Vector{String}
    snoop_hits::Int
    invalidations::Int
    supplier::Int
    flushed::Bool
    l2::String
    eviction::Any
    source::String
end

mutable struct MemoryBus
    latency::Int
    free::Int
    wait::Int
    transactions::Vector{BusTransaction}
end

MemoryBus(latency) = MemoryBus(latency, 0, 0, BusTransaction[])

function bus_assign!(bus, core, kind, block, requested)
    start = max(requested, bus.free)
    bus.wait += start - requested
    bus.free = start + bus.latency
    transaction = BusTransaction(
        length(bus.transactions) + 1,
        start,
        core,
        kind,
        block,
        String[],
        0,
        0,
        -1,
        false,
        "",
        nothing,
        ""
    )
    push!(bus.transactions, transaction)
    return transaction
end

function bus_line(transaction, line_size)
    tx = transaction
    output = "$(tx.number) $(tx.start) c$(tx.core) $(tx.kind) $(hex_address(tx.block * line_size))"
    tx.kind == "WB" && return output
    output *= " snoop " * (isempty(tx.snoops) ? "none" : join(tx.snoops, " "))
    tx.kind == "BusUpgr" && return output
    tx.kind in ("BusRd", "BusRdX") && (output *= " data " * tx.source)
    output *= " l2 " * tx.l2
    if tx.eviction !== nothing
        evicted = tx.eviction
        copies = isempty(evicted.copies) ? "none" : join(evicted.copies, " ")
        quality = evicted.dirty ? "dirty" : "clean"
        output *= " evict $(hex_address(evicted.block * line_size)) $copies $quality"
    end
    return output
end
