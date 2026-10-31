const TRANSACTION_TYPES = ("BusRd", "BusRdX", "BusUpgr", "BusWr", "WB")
const SERVICE_TYPES = ("l1", "upgrade", "through", "cache", "l2", "memory")
const MISS_TYPES = ("compulsory", "capacity", "conflict", "coherence")
const SNOOP_COUNTERS = ("invalidations_sent", "invalidations_received", "supplied", "back_invalidations")

counter_value(counters, key) = get(counters, key, 0)
function add_count!(counters, key, amount=1)
    counters[key] = counter_value(counters, key) + amount
end

function reduced_fraction(p, q)
    factor = gcd(p, q)
    return "$(p ÷ factor)/$(q ÷ factor)"
end

function decimal_notation(p, q)
    value = (2 * p * 100 + q) ÷ (2 * q)
    return "$(value ÷ 100).$(lpad(string(value % 100), 2, '0'))"
end

core_string(cores) = isempty(cores) ? "-" : join(sort!(collect(cores)))
range_counts(keys, counts) = join(("$key:$(counter_value(counts, key))" for key in keys), " ")
count_pairs(keys, counts) = join(("$key $(counter_value(counts, key))" for key in keys), " ")

mutable struct CoreCounters
    simple::Dict{String,Int}
    misses::Dict{String,Int}
    service::Dict{String,Int}
    bus::Dict{String,Int}
    snoop::Dict{String,Int}
    finish::Int
end

CoreCounters() = CoreCounters((Dict{String,Int}() for _ in 1:5)..., 0)

function total_counters(per_core)
    total = CoreCounters()
    for item in per_core
        for section in (:simple, :misses, :service, :bus, :snoop)
            for (key, value) in getproperty(item, section)
                add_count!(getproperty(total, section), key, value)
            end
        end
        total.finish = max(total.finish, item.finish)
    end
    return total
end

function six_lines(label, entry)
    simple, misses = entry.simple, entry.misses
    latency, accesses = counter_value(simple, "latency"), counter_value(simple, "accesses")
    return [
        "$label " * count_pairs(("accesses", "reads", "writes", "hits", "misses", "fences"), simple),
        "$label misses " * count_pairs((MISS_TYPES..., "true_sharing", "false_sharing"), misses),
        "$label service " * count_pairs(SERVICE_TYPES, entry.service),
        "$label bus " * count_pairs(TRANSACTION_TYPES, entry.bus),
        "$label snoop " * count_pairs(SNOOP_COUNTERS, entry.snoop),
        "$label time latency $latency amat $(reduced_fraction(latency, accesses)) $(decimal_notation(latency, accesses)) fence_stall $(counter_value(simple, "fence_stall")) finish $(entry.finish)"
    ]
end
