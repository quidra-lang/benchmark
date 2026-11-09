include("config_io.jl")
include("cache.jl")
include("protocol.jl")
include("bus.jl")
include("stats.jl")

mutable struct MemoryEvent
    number::Int
    cycle::Int
    core::Int
    operation::String
    address::Int
    block::Int
    word::Int
    distance::Int
end

function validate_trace(lines, config)
    events, rejected = MemoryEvent[], Tuple{Int,String}[]
    latest = 0
    for (line_number, line) in enumerate(lines)
        fields = split(line, ' '; keepempty=true)
        reason = ""
        if !(length(fields) in (3, 4)) || any(isempty, fields)
            reason = "fields"
        elseif !decimal_integer(fields[1], 7)
            reason = "cycle"
        elseif !decimal_integer(fields[2]) || parse(Int, fields[2]) >= config.cores
            reason = "core"
        elseif !(fields[3] in (
            "R",
            "W",
            "FENCE"
        )) || (fields[3] == "FENCE" ? length(fields) != 3 : length(fields) != 4)
            reason = "op"
        elseif fields[3] != "FENCE" && (!valid_hex_address(fields[4]) || parse(Int, fields[4]; base=16) % 4 != 0 || parse(
            Int,
            fields[4]; base=16
        ) > 2147483647)
            reason = "address"
        elseif parse(Int, fields[1]) < latest
            reason = "order"
        end
        if !isempty(reason)
            push!(rejected, (line_number, reason))
            continue
        end
        cycle, core = parse.(Int, fields[1:2])
        latest = cycle
        address = fields[3] == "FENCE" ? 0 : parse(Int, fields[4]; base=16)
        push!(
            events,
            MemoryEvent(
                length(events) + 1,
                cycle,
                core,
                String(fields[3]),
                address,
                address ÷ config.line_size,
                (address % config.line_size) ÷ 4,
                0
            )
        )
    end
    return events, rejected
end

function per_core_events(events, core_count)
    groups = [MemoryEvent[] for _ in 1:core_count]
    for event in events
        push!(groups[event.core + 1], event)
    end
    return groups
end

function fenwick_add!(tree, index, amount)
    while index <= length(tree)
        tree[index] += amount
        index += index & -index
    end
end

function fenwick_sum(tree, index)
    total = 0
    while index > 0
        total += tree[index]
        index -= index & -index
    end
    return total
end

function reuse_analysis(events, config)
    analyses = NamedTuple[]
    capacities = [config.cap ÷ 4, config.cap ÷ 2, config.cap, 2 * config.cap, 4 * config.cap]
    labels = ("1", "2-4", "5-16", "17-64", "65-256", "257+")
    for (core_index, ordered) in enumerate(per_core_events(events, config.cores))
        accesses = [event for event in ordered if event.operation != "FENCE"]
        last_position = Dict{Int,Int}()
        tree = zeros(Int, length(accesses))
        distances = Dict{String,Int}()
        lru = Dict(capacity => 0 for capacity in capacities)
        cold = 0
        for (index, event) in enumerate(accesses)
            previous = get(last_position, event.block, 0)
            if previous == 0
                cold += 1
                distance = 0
            else
                distance = fenwick_sum(tree, index - 1) - fenwick_sum(tree, previous - 1)
                bucket = distance == 1 ? 1 : distance <= 4 ? 2 : distance <= 16 ? 3 : distance <= 64 ? 4 : distance <= 256 ? 5 : 6
                add_count!(distances, labels[bucket])
                fenwick_add!(tree, previous, -1)
            end
            event.distance = distance
            for capacity in capacities
                (distance == 0 || distance > capacity) && (lru[capacity] += 1)
            end
            fenwick_add!(tree, index, 1)
            last_position[event.block] = index
        end
        next_use = fill(length(accesses) + 1, length(accesses))
        future = Dict{Int,Int}()
        for index in length(accesses):-1:1
            block = accesses[index].block
            next_use[index] = get(future, block, length(accesses) + 1)
            future[block] = index
        end
        resident = Dict{Int,Int}()
        opt = 0
        for (index, event) in enumerate(accesses)
            if !haskey(resident, event.block)
                opt += 1
                if length(resident) == config.cap
                    victim = argmax(block -> (resident[block], -block), collect(keys(resident)))
                    delete!(resident, victim)
                end
            end
            resident[event.block] = next_use[index]
        end
        push!(
            analyses,
            (
                core=core_index - 1,
                accesses=length(accesses),
                lines=length(last_position),
                distances=distances,
                cold=cold,
                lru=lru,
                capacities=capacities,
                opt=opt
            )
        )
    end
    return analyses
end

function static_sharing(events)
    lines = Dict{Int,Any}()
    for event in events
        event.operation == "FENCE" && continue
        info = get!(lines, event.block) do
            (cores=Set{Int}(), writers=Set{Int}(), counts=Dict{String,Int}(), words=Dict{Int,Any}())
        end
        push!(info.cores, event.core)
        kind = event.operation == "W" ? "writes" : "reads"
        add_count!(info.counts, kind)
        event.operation == "W" && push!(info.writers, event.core)
        word = get!(info.words, event.word) do
            (reads=Set{Int}(), writes=Set{Int}())
        end
        push!(getproperty(word, Symbol(kind)), event.core)
    end
    return lines
end

mutable struct SimulationState
    config::NamedTuple
    scenario::NamedTuple
    l1::Vector{HierarchyCache}
    l2::HierarchyCache
    bus::MemoryBus
    cores::Vector{CoreCounters}
    event_lists::Vector{Vector{MemoryEvent}}
    indices::Vector{Int}
    ready::Vector{Int}
    write_completion::Vector{Int}
    seen::Vector{Set{Int}}
    invalidations::Dict{Tuple{Int,Int},Set{Int}}
    l2_counters::Dict{String,Int}
    accesses::Vector{NamedTuple}
    watch_lines::Vector{String}
    handoffs::Dict{Int,Int}
    last_writer::Dict{Int,Int}
    word_state::Dict{Tuple{Int,Int},Tuple{Int,Set{Int}}}
    communications::Matrix{Int}
    shared_misses::Dict{Tuple{Int,String},Int}
    total::CoreCounters
    finish::Int
end

function initial_state(config, scenario, events)
    return SimulationState(config, scenario,
        [HierarchyCache(config.l1_sets, config.l1_ways, scenario.l1) for _ in 1:config.cores],
        HierarchyCache(config.l2_sets, config.l2_ways, scenario.l2), MemoryBus(config.tb),
        [CoreCounters() for _ in 1:config.cores], per_core_events(events, config.cores),
        ones(Int, config.cores), zeros(Int, config.cores), zeros(Int, config.cores),
        [Set{Int}() for _ in 1:config.cores], Dict{Tuple{Int,Int},Set{Int}}(), Dict{String,Int}(),
        NamedTuple[], String[], Dict{Int,Int}(), Dict{Int,Int}(), Dict{Tuple{Int,Int},Tuple{Int,Set{Int}}}(),
        zeros(Int, config.cores, config.cores), Dict{Tuple{Int,String},Int}(), CoreCounters(), 0)
end

line_states(state, block) = vcat(
    [cache_state(cache, block) for cache in state.l1],
    cache_state(state.l2, block)
)

function next_event(state)
    chosen = nothing
    for core in 0:state.config.cores - 1
        index = state.indices[core + 1]
        ordered = state.event_lists[core + 1]
        if index <= length(ordered)
            event = ordered[index]
            issue = max(event.cycle, state.ready[core + 1])
            if chosen === nothing || (issue, core) < (chosen[1], chosen[2])
                chosen = (issue, core, event)
            end
        end
    end
    return chosen
end

function issue_transaction!(state, core, kind, block, request_cycle)
    tx = bus_assign!(state.bus, core, kind, block, request_cycle)
    add_count!(state.cores[core + 1].bus, kind)
    kind == "WB" && add_count!(state.l2_counters, "writebacks")
    return tx
end

function snoop_others!(state, tx, word)
    for core in 0:state.config.cores - 1
        core == tx.core && continue
        cache = state.l1[core + 1]
        old = cache_state(cache, tx.block)
        old == "I" && continue
        updated, supplies, flushed = snoop_transition(state.scenario.protocol, old, tx.kind)
        push!(tx.snoops, "c$core:$old>$updated")
        tx.snoop_hits += 1
        if updated == "I"
            cache_remove!(cache, tx.block)
            tx.invalidations += 1
            add_count!(state.cores[tx.core + 1].snoop, "invalidations_sent")
            add_count!(state.cores[core + 1].snoop, "invalidations_received")
            state.invalidations[(core, tx.block)] = Set([word])
        else
            cache_change!(cache, tx.block, updated)
        end
        if supplies
            tx.supplier = core
            add_count!(state.cores[core + 1].snoop, "supplied")
        end
        flushed && (tx.flushed = true)
    end
    tx.flushed && add_count!(state.l2_counters, "flushes")
end

function access_l2!(state, tx)
    cache = state.l2
    add_count!(state.l2_counters, "lookups")
    if cache_state(cache, tx.block) != "I"
        tx.l2 = "hit"
        add_count!(state.l2_counters, "hits")
        cache_touch!(cache, tx.block)
    else
        tx.l2 = "miss"
        add_count!(state.l2_counters, "misses")
        evicted = cache_fill!(cache, tx.block, "C")
        if evicted !== nothing
            copies = String[]
            dirty = evicted.state == "D"
            for core in 0:state.config.cores - 1
                l1 = state.l1[core + 1]
                old = cache_state(l1, evicted.block)
                old == "I" && continue
                cache_remove!(l1, evicted.block)
                push!(copies, "c$core:$old")
                add_count!(state.cores[core + 1].snoop, "back_invalidations")
                old in DIRTY_STATES && (dirty = true)
            end
            tx.eviction = (block=evicted.block, copies=copies, dirty=dirty)
            add_count!(state.l2_counters, "evictions")
            dirty && add_count!(state.l2_counters, "dirty_evictions")
        end
    end
    (tx.flushed || tx.kind == "BusWr") && cache_change!(cache, tx.block, "D")
end

function run_bus_transaction!(state, core, kind, block, word, request_cycle)
    tx = issue_transaction!(state, core, kind, block, request_cycle)
    snoop_others!(state, tx, word)
    kind != "BusUpgr" && access_l2!(state, tx)
    completion = tx.start + state.config.tb
    if kind == "BusWr"
        completion += state.config.t2 + (tx.l2 == "miss" ? state.config.tm : 0)
    elseif kind != "BusUpgr"
        if tx.supplier >= 0
            tx.source = "c$(tx.supplier)"
        elseif tx.l2 == "hit"
            completion += state.config.t2
            tx.source = "L2"
        else
            completion += state.config.t2 + state.config.tm
            tx.source = "mem"
        end
    end
    return completion, tx
end

function write_back!(state, core, old_line)
    issue_transaction!(state, core, "WB", old_line.block, state.bus.free)
    cache_touch!(state.l2, old_line.block)
    cache_change!(state.l2, old_line.block, "D")
end

function classify_miss(state, event)
    !(event.block in state.seen[event.core + 1]) && return "compulsory", nothing
    record = get(state.invalidations, (event.core, event.block), nothing)
    record !== nothing && return "coherence", event.word in record ? "true_sharing" : "false_sharing"
    event.distance > state.config.cap && return "capacity", nothing
    return "conflict", nothing
end

function communicate!(state, event)
    key = (event.block, event.word)
    previous, readers = get(state.word_state, key, (-1, Set{Int}()))
    if event.operation == "W"
        former = get(state.last_writer, event.block, -1)
        former >= 0 && former != event.core && add_count!(state.handoffs, event.block)
        state.last_writer[event.block] = event.core
        state.word_state[key] = (event.core, Set{Int}())
    elseif previous >= 0 && previous != event.core && !(event.core in readers)
        state.communications[previous + 1, event.core + 1] += 1
        push!(readers, event.core)
        state.word_state[key] = (previous, readers)
    end
end

function render_watch!(state, event, issue, before)
    for block in state.config.watch
        after = line_states(state, block)
        block != event.block && before[block] == after && continue
        columns = join(("c$core:$(after[core + 1])" for core in 0:state.config.cores - 1), " ")
        push!(
            state.watch_lines,
            "$(event.number) $issue c$(event.core) $(event.operation) $(hex_address(event.address)) line $(hex_address(block * state.config.line_size)) $columns L2:$(after[end])"
        )
    end
end

function handle_access!(state, event, issue, primary)
    config = state.config
    core, block, word, operation = event.core, event.block, event.word, event.operation
    counters, cache = state.cores[core + 1], state.l1[core + 1]
    before = primary ? Dict(block => line_states(state, block) for block in config.watch) : nothing
    old = cache_state(cache, block)
    hit = old != "I"
    add_count!(counters.simple, "accesses")
    add_count!(counters.simple, operation == "R" ? "reads" : "writes")
    add_count!(counters.simple, hit ? "hits" : "misses")
    other_copy = any(k -> k != core && cache_state(state.l1[k + 1], block) != "I", 0:config.cores - 1)
    kind, updated = requester_transition(state.scenario.protocol, old, operation, other_copy)
    miss_kind = nothing
    if hit
        cache_touch!(cache, block)
    else
        miss_kind, sharing = classify_miss(state, event)
        add_count!(counters.misses, miss_kind)
        if sharing !== nothing
            add_count!(counters.misses, sharing)
            add_count!(state.shared_misses, (block, sharing))
        end
    end
    push!(state.seen[core + 1], block)
    if operation == "W"
        for ((other, other_block), words) in state.invalidations
            other != core && other_block == block && push!(words, word)
        end
    end
    primary && communicate!(state, event)
    if kind === nothing
        completion = issue + config.t1
        service = "l1"
    else
        completion, tx = run_bus_transaction!(state, core, kind, block, word, issue + config.t1)
        service = kind == "BusUpgr" ? "upgrade" : kind == "BusWr" ? "through" : tx.supplier >= 0 ? "cache" : tx.l2 == "hit" ? "l2" : "memory"
    end
    if old != "I"
        cache_change!(cache, block, updated)
    elseif updated != "I"
        evicted = cache_fill!(cache, block, updated)
        delete!(state.invalidations, (core, block))
        evicted !== nothing && evicted.state in DIRTY_STATES && write_back!(state, core, evicted)
    end
    latency = completion - issue
    add_count!(counters.service, service)
    add_count!(counters.simple, "latency", latency)
    add_count!(counters.simple, operation == "R" ? "read_latency" : "write_latency", latency)
    if operation == "R"
        state.ready[core + 1] = completion
    else
        state.ready[core + 1] = issue + config.t1
        state.write_completion[core + 1] = max(state.write_completion[core + 1], completion)
    end
    counters.finish = max(counters.finish, completion)
    push!(
        state.accesses,
        (
            number=event.number,
            issue=issue,
            core=core,
            operation=operation,
            address=event.address,
            block=block,
            word=word,
            latency=latency,
            service=service,
            miss_kind=miss_kind,
            hit=hit
        )
    )
    primary && render_watch!(state, event, issue, before)
end

function simulate(config, scenario, events, primary)
    state = initial_state(config, scenario, events)
    while true
        chosen = next_event(state)
        chosen === nothing && break
        issue, core, event = chosen
        state.indices[core + 1] += 1
        if event.operation == "FENCE"
            counters = state.cores[core + 1]
            completion = max(issue, state.write_completion[core + 1])
            add_count!(counters.simple, "fences")
            add_count!(counters.simple, "fence_stall", completion - issue)
            counters.finish = max(counters.finish, completion)
            state.ready[core + 1] = completion
        else
            handle_access!(state, event, issue, primary)
        end
    end
    state.total = total_counters(state.cores)
    state.finish = state.total.finish
    return state
end

function trace_config_lines(config, trace, events, rejected)
    lines = ["trace lines $(length(trace)) accepted $(length(events)) rejected $(length(rejected))"]
    append!(lines, ["reject line $number $reason" for (number, reason) in rejected])
    push!(
        lines,
        "geometry cores $(config.cores) line $(config.line_size) l1 $(config.l1_size) $(config.l1_ways) sets $(config.l1_sets) l2 $(config.l2_size) $(config.l2_ways) sets $(config.l2_sets)"
    )
    push!(lines, "latency l1 $(config.t1) l2 $(config.t2) memory $(config.tm) bus $(config.tb)")
    return lines
end

function reuse_lines(analyses, config)
    lines = String[]
    labels = ("1", "2-4", "5-16", "17-64", "65-256", "257+")
    for record in analyses
        push!(
            lines,
            "reuse c$(record.core) accesses $(record.accesses) lines $(record.lines) distance $(range_counts(labels, record.distances)) cold $(record.cold)"
        )
        push!(
            lines,
            "mrc c$(record.core) lru $(range_counts(record.capacities, record.lru)) opt $(config.cap):$(record.opt)"
        )
    end
    return lines
end

function length_histogram(accesses)
    counts = Dict{String,Int}()
    labels = ("1", "2-9", "10-29", "30-99", "100-299", "300+")
    for event in accesses
        latency = event.latency
        bucket = latency == 1 ? 1 : latency <= 9 ? 2 : latency <= 29 ? 3 : latency <= 99 ? 4 : latency <= 299 ? 5 : 6
        add_count!(counts, labels[bucket])
    end
    return range_counts(labels, counts)
end

function scenario_report(state)
    config, scenario, total, bus = state.config, state.scenario, state.total, state.bus
    lines = ["scenario $(scenario.name) $(scenario.protocol) $(scenario.l1) $(scenario.l2)"]
    for (index, counters) in enumerate(state.cores)
        append!(lines, six_lines("c$(index - 1)", counters))
    end
    append!(lines, six_lines("total", total))
    l2 = state.l2_counters
    push!(
        lines,
        "l2 " * count_pairs(
            ("lookups", "hits", "misses", "flushes", "writebacks", "evictions", "dirty_evictions"),
            l2
        )
    )
    transactions = length(bus.transactions)
    busy = config.tb * transactions
    push!(
        lines,
        "bus transactions $transactions busy $busy wait $(bus.wait) utilization $(decimal_notation(100 * busy, state.finish))"
    )
    kinds = total.bus
    data_bytes = config.line_size * sum(counter_value(kinds, kind) for kind in (
        "BusRd",
        "BusRdX",
        "WB"
    )) + 4 * counter_value(kinds, "BusWr")
    memory_bytes = config.line_size * (counter_value(l2, "misses") + counter_value(l2, "dirty_evictions"))
    push!(
        lines,
        "traffic command_bytes $(8 * transactions) data_bytes $data_bytes memory_bytes $memory_bytes"
    )
    snoops = [tx for tx in bus.transactions if tx.kind != "WB"]
    fanout = Dict{Int,Int}()
    for tx in snoops
        tx.kind in ("BusRdX", "BusUpgr", "BusWr") && add_count!(fanout, tx.invalidations)
    end
    probes = (config.cores - 1) * length(snoops)
    hits = sum((tx.snoop_hits for tx in snoops); init=0)
    push!(lines, "snoops probes $probes hits $hits fanout $(range_counts(0:config.cores - 1, fanout))")
    push!(
        lines,
        "latencies reads $(counter_value(total.simple, "read_latency")) writes $(counter_value(total.simple, "write_latency")) histogram $(length_histogram(state.accesses))"
    )
    return lines
end

function ranking_lines(states)
    ordered = sort(states; by=state -> (state.finish, length(state.bus.transactions), state.scenario.order))
    lines = ["ranking"]
    for (rank, state) in enumerate(ordered)
        latency, accesses = counter_value(state.total.simple, "latency"), counter_value(
            state.total.simple,
            "accesses"
        )
        push!(
            lines,
            "$rank $(state.scenario.name) finish $(state.finish) transactions $(length(state.bus.transactions)) amat $(reduced_fraction(latency, accesses)) $(decimal_notation(latency, accesses))"
        )
    end
    return lines
end

function hot_lines(state)
    counts = Dict{Int,Dict{String,Int}}()
    cores = Dict{Int,Set{Int}}()
    for tx in state.bus.transactions
        numbers = get!(counts, tx.block, Dict{String,Int}())
        add_count!(numbers, tx.kind)
        add_count!(numbers, "invalidations", tx.invalidations)
        push!(get!(cores, tx.block, Set{Int}()), tx.core)
    end
    for event in state.accesses
        if event.miss_kind !== nothing && haskey(counts, event.block)
            numbers = counts[event.block]
            add_count!(numbers, "misses")
            event.miss_kind == "coherence" && add_count!(numbers, "coherence")
        end
    end
    tx_total(block) = sum(counter_value(counts[block], kind) for kind in TRANSACTION_TYPES)
    blocks = sort!(collect(keys(counts)); by=block -> (-tx_total(block), block))
    lines = ["hot $(state.scenario.name)"]
    for (rank, block) in enumerate(blocks[1:min(end, state.config.top)])
        numbers = counts[block]
        push!(
            lines,
            "$rank $(hex_address(block * state.config.line_size)) transactions $(tx_total(block)) $(count_pairs(TRANSACTION_TYPES, numbers)) misses $(counter_value(numbers, "misses")) coherence $(counter_value(numbers, "coherence")) invalidations $(counter_value(numbers, "invalidations")) cores $(core_string(cores[block]))"
        )
    end
    return lines
end

function interval_lines(state)
    config = state.config
    width = config.interval
    count = state.finish ÷ width + 1
    accesses = zeros(Int, count, config.cores)
    misses, transactions, busy = zeros(Int, count), zeros(Int, count), zeros(Int, count)
    for event in state.accesses
        bucket = event.issue ÷ width + 1
        accesses[bucket, event.core + 1] += 1
        event.miss_kind !== nothing && (misses[bucket] += 1)
    end
    for tx in state.bus.transactions
        start, stop = tx.start, tx.start + config.tb
        start ÷ width < count && (transactions[start ÷ width + 1] += 1)
        for bucket in start ÷ width:(stop - 1) ÷ width
            if bucket < count
                busy[bucket + 1] += max(0, min(stop, (bucket + 1) * width) - max(start, bucket * width))
            end
        end
    end
    lines = ["intervals $(state.scenario.name) $width"]
    for bucket in 0:count - 1
        start = bucket * width
        values = join(accesses[bucket + 1, :], " ")
        push!(
            lines,
            "$bucket $start-$(start + width - 1) accesses $values misses $(misses[bucket + 1]) transactions $(transactions[bucket + 1]) busy $(busy[bucket + 1]) utilization $(decimal_notation(100 * busy[bucket + 1], width))"
        )
    end
    return lines
end

function slowest_lines(state)
    ordered = sort(state.accesses; by=event -> (-event.latency, event.number))
    lines = ["slowest $(state.scenario.name)"]
    for (rank, event) in enumerate(ordered[1:min(end, state.config.top)])
        push!(
            lines,
            "$rank event $(event.number) cycle $(event.issue) c$(event.core) $(event.operation) $(hex_address(event.address)) latency $(event.latency) service $(event.service)"
        )
    end
    return lines
end

function region_for(address, config)
    for region in config.regions
        region.low <= address <= region.high && return region.name
    end
    return "other"
end

function region_lines(state)
    config = state.config
    names = vcat([region.name for region in config.regions], "other")
    counts = Dict(name => Dict{String,Int}() for name in names)
    for event in state.accesses
        numbers = counts[region_for(event.address, config)]
        add_count!(numbers, "accesses")
        add_count!(numbers, event.operation == "R" ? "reads" : "writes")
        add_count!(numbers, "latency", event.latency)
        add_count!(numbers, event.hit ? "hits" : event.miss_kind)
    end
    for tx in state.bus.transactions
        add_count!(counts[region_for(tx.block * config.line_size, config)], "transactions")
    end
    lines = ["regions $(state.scenario.name)"]
    for name in names
        numbers = counts[name]
        accesses, latency = counter_value(numbers, "accesses"), counter_value(numbers, "latency")
        amat = accesses == 0 ? "-" : reduced_fraction(latency, accesses) * " " * decimal_notation(
            latency,
            accesses
        )
        push!(
            lines,
            "$name $(count_pairs(("accesses", "reads", "writes", "hits", MISS_TYPES..., "transactions", "latency"), numbers)) amat $amat"
        )
    end
    return lines
end

function sharing_lines(static, state)
    lines = String[]
    totals = Dict{String,Int}()
    blocks = sort!([block for (block, info) in static if length(info.cores) >= 2 && !isempty(info.writers)])
    for block in blocks
        info = static[block]
        true_line = any(
            word -> !isempty(word.writes) && length(union(word.reads, word.writes)) >= 2,
            values(info.words)
        )
        true_miss = counter_value(state.shared_misses, (block, "true_sharing"))
        false_miss = counter_value(state.shared_misses, (block, "false_sharing"))
        add_count!(totals, "coherence", true_miss + false_miss)
        add_count!(totals, "true", true_miss)
        add_count!(totals, "false", false_miss)
        add_count!(totals, true_line ? "true_lines" : "false_lines")
        words = join(
            ("w$number=$(core_string(info.words[number].reads))/$(core_string(info.words[number].writes))" for number in sort!(collect(keys(info.words)))),
            " "
        )
        quality = true_line ? "true" : "false"
        push!(
            lines,
            "$(hex_address(block * state.config.line_size)) $quality cores $(core_string(info.cores)) writers $(core_string(info.writers)) reads $(counter_value(info.counts, "reads")) writes $(counter_value(info.counts, "writes")) handoffs $(counter_value(state.handoffs, block)) coherence $(true_miss + false_miss) true $true_miss false $false_miss words $words"
        )
    end
    push!(
        lines,
        "lines $(length(blocks)) $(count_pairs(("true_lines", "false_lines", "coherence", "true", "false"), totals))"
    )
    push!(lines, "communication")
    for core in 0:state.config.cores - 1
        push!(lines, "c$core " * join(state.communications[core + 1, :], " "))
    end
    return lines
end

function final_state_lines(state)
    config = state.config
    lines = String[]
    caches = vcat(state.l1, state.l2)
    for (index, cache) in enumerate(caches)
        label = index <= config.cores ? "c$(index - 1)" : "L2"
        for row in 1:cache.number_sets
            ways = [cache.blocks[row, way] == -1 ? "-" : hex_address(cache.blocks[row, way] * config.line_size) * ":" * cache.states[
                row,
                way
            ] for way in 1:cache.ways]
            push!(
                lines,
                "$label $(row - 1) $(join(ways, " ")) $(lowercase(cache.replacement)) $(cache_order(cache, row)) fills $(cache.fills[row]) evictions $(cache.evictions[row])"
            )
        end
        entries = cache_lines(cache)
        counts = Dict{String,Int}()
        for item in entries
            add_count!(counts, item.state)
        end
        if index <= config.cores
            push!(lines, "$label lines $(length(entries)) " * count_pairs(("M", "O", "E", "S", "V"), counts))
        else
            resident = Set(item.block for cache in state.l1 for item in cache_lines(cache))
            push!(
                lines,
                "L2 lines $(length(entries)) dirty $(counter_value(counts, "D")) clean $(counter_value(counts, "C")) in_l1 $(length(resident))"
            )
        end
    end
    return lines
end

function main()
    config, trace = read_config(), read_trace()
    events, rejected = validate_trace(trace, config)
    reuse, static = reuse_analysis(events, config), static_sharing(events)
    states = [simulate(
        config,
        scenario,
        events,
        scenario.name == config.primary
    ) for scenario in config.scenarios]
    primary = first(state for state in states if state.scenario.name == config.primary)
    sections = [trace_config_lines(config, trace, events, rejected), reuse_lines(reuse, config)]
    append!(sections, [scenario_report(state) for state in states])
    append!(
        sections,
        [
            ranking_lines(states),
            hot_lines(primary),
            interval_lines(primary),
            slowest_lines(primary),
            region_lines(primary)
        ]
    )
    lines = String[]
    for (index, section) in enumerate(sections)
        index > 1 && push!(lines, "")
        append!(lines, section)
    end
    write_lines("stats.txt", lines)
    write_lines("bus_log.txt", [bus_line(tx, config.line_size) for tx in primary.bus.transactions])
    write_lines("watch.txt", primary.watch_lines)
    write_lines("sharing.txt", sharing_lines(static, primary))
    write_lines("final_state.txt", final_state_lines(primary))
end

main()
