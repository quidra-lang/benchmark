using Printf

@enum Mode CHAIN LINEAR QUADRATIC DOUBLE ROBINHOOD CUCKOO
@enum Reporting SILENT REHASHES FULL TRACED
const MODES = Dict(string(mode) => mode for mode in instances(Mode))
const COMMANDS = Set(split("CREATE MAXLOAD MINLOAD TRACE HASH PUT ADD GET DEL PROBE GEN GENDEL RESIZE CONVERT CLEAR DUMP MAP STATS KEYS TOP SCAN CLUSTERS DIST COMPARE BENCH"))

struct CommandError <: Exception
    message::String
end
fail(message::String) = throw(CommandError(message))
struct Item
    key::String
    value::Int
end
struct Tombstone end
const Slot = Union{Nothing,Tombstone,Item}
const TOMB = Tombstone()
item_text(item::Item) = "$(item.key)=$(item.value)"
slot_text(slot::Slot) = isnothing(slot) ? "-" : slot isa Tombstone ? "D" : slot.key

Base.@kwdef mutable struct Counters
    probes::Int = 0
    rehashes::Int = 0
    inserts::Int = 0
    updates::Int = 0
    hits::Int = 0
    misses::Int = 0
    deletes::Int = 0
    absent::Int = 0
end
Base.@kwdef mutable struct Search
    position::Int = 0
    chain_index::Int = 0
    probes::Int = 0
    available::Int = 0
    path::Vector{String} = String[]
end
Base.@kwdef struct Placement
    success::Bool = false
    position::Int = 0
    reused::Bool = false
    movements::Int = 0
    pending::Union{Nothing,Item} = nothing
    moves::Vector{String} = String[]
end
struct ItemRecord
    item::Item
    position::Int
    cost::Int
end
mutable struct Table
    mode::Mode
    capacity::Int
    size::Int
    tomb::Int
    buckets::Vector{Vector{Item}}
    slots::Vector{Slot}
    counters::Counters
end
slot_count(mode::Mode, capacity::Int) = mode == CUCKOO ? 2capacity : capacity
slot_count(table::Table) = slot_count(table.mode, table.capacity)
function Table(mode::Mode, capacity::Int)
    buckets = mode == CHAIN ? [Item[] for _ in 1:capacity] : Vector{Item}[]
    slots = mode == CHAIN ? Slot[] : Slot[nothing for _ in 1:slot_count(mode, capacity)]
    Table(mode, capacity, 0, 0, buckets, slots, Counters())
end
mutable struct Simulator
    table::Union{Nothing,Table}
    maxload::Int
    minload::Int
    trace::Bool
end
Simulator() = Simulator(nothing, 75, 0, false)

function hash_key(key::String, base::Int, modulus::Int)
    value = 0
    for code in codeunits(key)
        value = mod(value * base + Int(code), modulus)
    end
    value
end
function is_prime(value::Int)
    value < 2 && return false
    for divisor in 2:isqrt(value)
        mod(value, divisor) == 0 && return false
    end
    true
end
function next_prime(value::Int)
    value = max(value, 2)
    while !is_prime(value)
        value += 1
    end
    value
end
function two_decimal(numerator::Int, denominator::Int)
    value = denominator == 0 ? 0 : div(100numerator, denominator)
    @sprintf("%d.%02d", div(value, 100), mod(value, 100))
end
function checked_mode(text::String)
    haskey(MODES, text) || fail("BAD MODE $text")
    MODES[text]
end
function checked_capacity(value::Int)
    2 <= value <= 10000 || fail("BAD CAPACITY")
    value
end
function check_generation(count::Int, width::Int, seed::Int)
    1 <= count <= 500 && 1 <= width <= 10 && 1 <= seed <= 2147483646 || fail("BAD ARGUMENT")
end
function generate_keys(count::Int, width::Int, seed::Int)
    result = String[]
    for _ in 1:count
        bytes = Vector{UInt8}(undef, width)
        for index in eachindex(bytes)
            seed = mod(48271seed, 2147483647)
            bytes[index] = UInt8(97 + mod(seed, 26))
        end
        push!(result, String(bytes))
    end
    result
end
function position_text(table::Table, position::Int)
    index = position - 1
    table.mode == CUCKOO ? "T$(div(index, table.capacity) + 1).$(mod(index, table.capacity))" : string(index)
end
distance(table::Table, item::Item, position::Int) =
    mod(position - 1 - hash_key(item.key, 31, table.capacity), table.capacity)
with_words(prefix::String, words::Vector{String}) = isempty(words) ? prefix : prefix * " " * join(words, " ")
path_line(search::Search) = with_words("PATH", isempty(search.path) ? ["none"] : search.path)
found(search::Search) = search.position != 0

function item_list(table::Table)
    if table.mode == CHAIN
        return Item[item for bucket in table.buckets for item in bucket]
    end
    Item[slot for slot in table.slots if slot isa Item]
end
function lookup(table::Table, key::String; trace::Bool = false)
    result = Search()
    function observe(position::Int, content::String)
        result.probes += 1
        trace && push!(result.path, "$(position_text(table, position)):$content")
    end
    home = hash_key(key, 31, table.capacity)
    if table.mode == CHAIN
        for (index, item) in enumerate(table.buckets[home + 1])
            observe(home + 1, item.key)
            if item.key == key
                result.position, result.chain_index = home + 1, index
                break
            end
        end
        return result
    end
    step = table.mode == DOUBLE ? 1 + hash_key(key, 37, table.capacity - 1) : 1
    limit = table.mode == CUCKOO ? 2 : table.capacity
    for offset in 0:limit-1
        index = mod(home + offset * step, table.capacity)
        if table.mode == QUADRATIC
            index = mod(home + offset * offset, table.capacity)
        elseif table.mode == CUCKOO && offset == 1
            index = table.capacity + hash_key(key, 37, table.capacity)
        end
        position = index + 1
        slot = table.slots[position]
        observe(position, slot_text(slot))
        if slot isa Item && slot.key == key
            result.position = position
            break
        end
        table.mode == CUCKOO && continue
        if isnothing(slot)
            result.available == 0 && (result.available = position)
            break
        end
        slot isa Tombstone && result.available == 0 && (result.available = position)
        table.mode == ROBINHOOD && distance(table, slot, position) < offset && break
    end
    result
end
function found_item(table::Table, search::Search)
    table.mode == CHAIN && return table.buckets[search.position][search.chain_index]
    table.slots[search.position]::Item
end

function place!(table::Table, item::Item; initial::Union{Nothing,Search} = nothing, trace::Bool = false)
    home = hash_key(item.key, 31, table.capacity) + 1
    if table.mode == CHAIN
        push!(table.buckets[home], item)
        return Placement(success = true, position = home)
    elseif table.mode in (LINEAR, QUADRATIC, DOUBLE)
        search = isnothing(initial) ? lookup(table, item.key) : initial
        position = search.available
        position == 0 && return Placement(pending = item)
        reused = table.slots[position] isa Tombstone
        reused && (table.tomb -= 1)
        table.slots[position] = item
        return Placement(success = true, position = position, reused = reused)
    end
    carried, movements, original = item, 0, 0
    moves = String[]
    if table.mode == ROBINHOOD
        position, traveled, source = home, 0, 0
        while true
            if isnothing(table.slots[position])
                trace && source != 0 && push!(moves, "SHIFT $(carried.key) $(source - 1) -> $(position - 1)")
                table.slots[position] = carried
                original == 0 && (original = position)
                return Placement(success = true, position = original, movements = movements, moves = moves)
            end
            resident = table.slots[position]::Item
            old_distance = distance(table, resident, position)
            if old_distance < traveled
                trace && source != 0 && push!(moves, "SHIFT $(carried.key) $(source - 1) -> $(position - 1)")
                table.slots[position], carried = carried, resident
                original == 0 && (original = position)
                source, traveled = position, old_distance
                movements += 1
            end
            position = mod(position, table.capacity) + 1
            traveled += 1
        end
    end
    part = 0
    while true
        position = part * table.capacity + hash_key(carried.key, part == 0 ? 31 : 37, table.capacity) + 1
        if isnothing(table.slots[position])
            table.slots[position] = carried
            original = lookup(table, item.key).position
            return Placement(success = true, position = original, movements = movements, moves = moves)
        end
        movements == table.capacity && return Placement(movements = movements, pending = carried, moves = moves)
        resident = table.slots[position]::Item
        trace && push!(moves, "KICK $(resident.key) $(position_text(table, position))")
        table.slots[position], carried = carried, resident
        movements += 1
        part = 1 - part
    end
end
function remove_item!(table::Table, search::Search; trace::Bool = false)
    position, shifted = search.position, 0
    moves = String[]
    if table.mode == CHAIN
        deleteat!(table.buckets[position], search.chain_index)
    elseif table.mode in (LINEAR, QUADRATIC, DOUBLE)
        table.slots[position] = TOMB
        table.tomb += 1
    else
        table.slots[position] = nothing
        if table.mode == ROBINHOOD
            source = mod(position, table.capacity) + 1
            while table.slots[source] isa Item && distance(table, table.slots[source], source) > 0
                destination = mod(source - 2, table.capacity) + 1
                trace && push!(moves, "SHIFT $(table.slots[source].key) $(source - 1) -> $(destination - 1)")
                table.slots[destination], table.slots[source] = table.slots[source], nothing
                shifted += 1
                source = mod(source, table.capacity) + 1
            end
        end
    end
    table.size -= 1
    shifted, moves
end

function rebuilt(mode::Mode, capacity::Int, items::Vector{Item})
    trial = Table(mode, capacity)
    for item in items
        place!(trial, item).success || return nothing
        trial.size += 1
    end
    trial
end
function adopt!(table::Table, trial::Table)
    table.mode, table.capacity = trial.mode, trial.capacity
    table.size, table.tomb = trial.size, trial.tomb
    table.buckets, table.slots = trial.buckets, trial.slots
    table
end
function automatic!(table::Table, capacity::Int, reason::String; pending::Union{Nothing,Item} = nothing)
    old = table.capacity
    items = item_list(table)
    !isnothing(pending) && push!(items, pending)
    while true
        trial = rebuilt(table.mode, capacity, items)
        if !isnothing(trial)
            adopt!(table, trial)
            table.counters.rehashes += 1
            return "REHASH $reason $old -> $capacity"
        end
        capacity = next_prime(2capacity)
    end
end
function load_check!(table::Table, maxload::Int)
    threshold = maxload * slot_count(table)
    100 * (table.size + table.tomb) <= threshold && return nothing
    200 * table.size > threshold && return automatic!(table, next_prime(2 * table.capacity), "load")
    automatic!(table, table.capacity, "tomb")
end
function shrink_check!(table::Table, minload::Int, maxload::Int)
    capacity = next_prime(div(table.capacity, 2))
    if 100 * table.size >= minload * slot_count(table) || capacity >= table.capacity ||
       100 * table.size > maxload * slot_count(table.mode, capacity)
        return nothing
    end
    trial = rebuilt(table.mode, capacity, item_list(table))
    isnothing(trial) && return nothing
    old = table.capacity
    adopt!(table, trial)
    table.counters.rehashes += 1
    "REHASH shrink $old -> $capacity"
end
function put_item!(table::Table, item::Item, add::Bool, maxload::Int, reporting::Reporting)
    trace = reporting == TRACED
    detailed = reporting in (FULL, TRACED)
    search = lookup(table, item.key; trace)
    table.counters.probes += search.probes
    command = add ? "ADD" : "PUT"
    lines = String[]
    if found(search)
        old = found_item(table, search).value
        add && (item = Item(item.key, old + item.value))
        if table.mode == CHAIN
            table.buckets[search.position][search.chain_index] = item
        else
            table.slots[search.position] = item
        end
        table.counters.updates += 1
        detailed && push!(lines, "$command $(item_text(item)) UPDATED old=$old at=$(position_text(table, search.position)) probes=$(search.probes)")
        trace && push!(lines, path_line(search))
        return false, lines
    end
    placed = place!(table, item; initial = search, trace)
    table.counters.inserts += 1
    if detailed
        row = "$command $(item_text(item)) NEW"
        if placed.success
            row *= " at=$(position_text(table, placed.position)) probes=$(search.probes)"
            placed.reused && (row *= " reused")
            table.mode == ROBINHOOD && (row *= " shifted=$(placed.movements)")
            table.mode == CUCKOO && (row *= " kicks=$(placed.movements)")
        else
            row *= " probes=$(search.probes)"
            row *= table.mode == QUADRATIC ? " full" : " kicks=$(placed.movements) failed"
        end
        push!(lines, row)
    end
    if trace
        push!(lines, path_line(search))
        append!(lines, placed.moves)
    end
    if placed.success
        table.size += 1
    else
        reason = table.mode == QUADRATIC ? "full" : "kicks"
        event = automatic!(table, next_prime(2 * table.capacity), reason; pending = placed.pending)
        reporting != SILENT && push!(lines, event)
    end
    event = load_check!(table, maxload)
    reporting != SILENT && !isnothing(event) && push!(lines, event)
    true, lines
end
function delete_item!(table::Table, key::String, minload::Int, maxload::Int, reporting::Reporting)
    trace = reporting == TRACED
    search = lookup(table, key; trace)
    table.counters.probes += search.probes
    lines, moves = String[], String[]
    if found(search)
        shifted, moves = remove_item!(table, search; trace)
        table.counters.deletes += 1
        row = "DEL $key OK at=$(position_text(table, search.position)) probes=$(search.probes)"
        table.mode == ROBINHOOD && (row *= " shifted=$shifted")
    else
        table.counters.absent += 1
        row = "DEL $key NOT FOUND probes=$(search.probes)"
    end
    reporting in (FULL, TRACED) && push!(lines, row)
    if trace
        push!(lines, path_line(search))
        append!(lines, moves)
    end
    if found(search)
        event = shrink_check!(table, minload, maxload)
        reporting != SILENT && !isnothing(event) && push!(lines, event)
    end
    found(search), lines
end
function get_item!(table::Table, key::String, trace::Bool)
    search = lookup(table, key; trace)
    table.counters.probes += search.probes
    if found(search)
        table.counters.hits += 1
        row = "GET $(item_text(found_item(table, search))) at=$(position_text(table, search.position)) probes=$(search.probes)"
    else
        table.counters.misses += 1
        row = "GET $key NOT FOUND probes=$(search.probes)"
    end
    trace ? [row, path_line(search)] : [row]
end

function record_items(table::Table)
    records = ItemRecord[]
    if table.mode == CHAIN
        for (position, bucket) in enumerate(table.buckets), (cost, item) in enumerate(bucket)
            push!(records, ItemRecord(item, position, cost))
        end
    else
        for (position, slot) in enumerate(table.slots)
            slot isa Item || continue
            cost = if table.mode == CUCKOO
                div(position - 1, table.capacity) + 1
            elseif table.mode in (LINEAR, ROBINHOOD)
                distance(table, slot, position) + 1
            else
                lookup(table, slot.key).probes
            end
            push!(records, ItemRecord(slot, position, cost))
        end
    end
    records
end
function table_metrics(table::Table)
    costs = [record.cost for record in record_items(table)]
    maximum(costs; init = 0), two_decimal(sum(costs), table.size)
end
function dump_table(table::Table)
    lines = ["DUMP $(table.mode) cap=$(table.capacity) size=$(table.size) tomb=$(table.tomb)"]
    if table.mode == CHAIN
        for (position, bucket) in enumerate(table.buckets)
            content = isempty(bucket) ? "-" : join(item_text.(bucket), " ")
            push!(lines, "$(position - 1) $content")
        end
    else
        for (position, slot) in enumerate(table.slots)
            index = position - 1
            prefix = table.mode == CUCKOO ? "T$(div(index, table.capacity) + 1) $(mod(index, table.capacity))" : string(index)
            content = slot isa Item ? item_text(slot) : slot_text(slot)
            slot isa Item && table.mode == ROBINHOOD && (content *= " d=$(distance(table, slot, position))")
            push!(lines, "$prefix $content")
        end
    end
    lines
end
gauge(value::Int) = value >= 10 ? '+' : Char(Int('0') + value)
function map_table(table::Table)
    lines = ["MAP $(table.mode) cap=$(table.capacity)"]
    costs = zeros(Int, slot_count(table))
    for record in record_items(table)
        costs[record.position] = record.cost
    end
    for part in 0:(table.mode == CUCKOO ? 1 : 0), start in 0:40:table.capacity-1
        chars = Char[]
        for index in start:min(start + 39, table.capacity - 1)
            if table.mode == CHAIN
                count = length(table.buckets[index + 1])
                push!(chars, count == 0 ? '.' : gauge(count))
            else
                position = part * table.capacity + index + 1
                slot = table.slots[position]
                char = isnothing(slot) ? '.' : slot isa Tombstone ? 'D' :
                       table.mode == CUCKOO ? '#' : gauge(costs[position] - 1)
                push!(chars, char)
            end
        end
        prefix = table.mode == CUCKOO ? "T$(part + 1) " : ""
        push!(lines, prefix * @sprintf("%05d", start) * " " * join(chars))
    end
    lines
end
function table_stats(table::Table)
    longest, average = table_metrics(table)
    load = two_decimal(100 * table.size, slot_count(table))
    c = table.counters
    ["STATS $(table.mode) size=$(table.size) cap=$(table.capacity) slots=$(slot_count(table)) tomb=$(table.tomb) load=$load% longest=$longest avg=$average probes=$(c.probes) rehashes=$(c.rehashes)",
     "OPS inserts=$(c.inserts) updates=$(c.updates) hits=$(c.hits) misses=$(c.misses) deletes=$(c.deletes) absent=$(c.absent)"]
end
function table_scan(table::Table, cursor::Int, limit::Int)
    collected = String[]
    while cursor < slot_count(table) && length(collected) < limit
        if table.mode == CHAIN
            append!(collected, [item.key for item in table.buckets[cursor + 1]])
        elseif table.slots[cursor + 1] isa Item
            push!(collected, table.slots[cursor + 1].key)
        end
        cursor += 1
    end
    cursor == slot_count(table) && (cursor = 0)
    with_words("SCAN next=$cursor", collected)
end
function histogram(values::Vector{Int})
    frequencies = Dict{Int,Int}()
    for value in values
        frequencies[value] = get(frequencies, value, 0) + 1
    end
    lines = String[]
    for value in sort!(collect(keys(frequencies)))
        count = frequencies[value]
        bar = repeat("#", min(count, 50)) * (count > 50 ? "+" : "")
        push!(lines, "$value $count $bar")
    end
    lines
end
function cluster_report(table::Table)
    runs = Int[]
    if table.mode == CHAIN
        runs = [length(bucket) for bucket in table.buckets if !isempty(bucket)]
    else
        for base in 0:table.capacity:length(table.slots)-1
            first_empty = findfirst(isnothing, view(table.slots, base+1:base+table.capacity))
            if isnothing(first_empty)
                push!(runs, table.capacity)
                continue
            end
            count = 0
            for offset in 1:table.capacity
                position = base + mod(first_empty - 1 + offset, table.capacity) + 1
                if !isnothing(table.slots[position])
                    count += 1
                elseif count > 0
                    push!(runs, count)
                    count = 0
                end
            end
        end
    end
    vcat(["CLUSTERS runs=$(length(runs)) longest=$(maximum(runs; init = 0))"], histogram(runs))
end
function cost_report(table::Table)
    costs = [record.cost for record in record_items(table)]
    vcat(["DIST keys=$(table.size) longest=$(maximum(costs; init = 0))"], histogram(costs))
end
function compare_modes(table::Table, capacity::Int, maxload::Int)
    items = sort(item_list(table); by = item -> item.key)
    lines = ["COMPARE keys=$(length(items)) cap=$capacity"]
    for mode in instances(Mode)
        trial = Table(mode, capacity)
        for item in items
            put_item!(trial, item, false, maxload, SILENT)
        end
        longest, average = table_metrics(trial)
        push!(lines, "$mode cap=$(trial.capacity) longest=$longest avg=$average probes=$(trial.counters.probes) rehashes=$(trial.counters.rehashes)")
    end
    lines
end
function benchmark(capacity::Int, count::Int, width::Int, seed::Int, maxload::Int)
    generated = generate_keys(2count, width, seed)
    lines = ["BENCH cap=$capacity count=$count len=$width seed=$seed"]
    for mode in instances(Mode)
        trial = Table(mode, capacity)
        for index in 1:count
            put_item!(trial, Item(generated[index], index), false, maxload, SILENT)
        end
        misses, probes = 0, 0
        for key in view(generated, count+1:2count)
            search = lookup(trial, key)
            if !found(search)
                misses += 1
                probes += search.probes
            end
        end
        _, average = table_metrics(trial)
        push!(lines, "$mode cap=$(trial.capacity) keys=$(trial.size) hit=$average misses=$misses miss=$(two_decimal(probes, misses)) rehashes=$(trial.counters.rehashes)")
    end
    lines
end

function execute!(sim::Simulator, line::String)
    words = String.(split(line, ' '))
    command = words[1]
    command in COMMANDS || fail("UNKNOWN COMMAND $command")
    number(index::Int) = parse(Int, words[index])
    if command == "CREATE"
        mode = checked_mode(words[2])
        capacity = next_prime(checked_capacity(number(3)))
        sim.table = Table(mode, capacity)
        return ["CREATE $mode cap=$capacity"]
    elseif command in ("MAXLOAD", "MINLOAD")
        value = number(2)
        if command == "MAXLOAD"
            10 <= value <= 95 || fail("BAD LOAD")
            sim.maxload = value
        else
            0 <= value <= 40 || fail("BAD LOAD")
            sim.minload = value
        end
        return ["$command $value"]
    elseif command == "TRACE"
        words[2] in ("ON", "OFF") || fail("BAD ARGUMENT")
        sim.trace = words[2] == "ON"
        return ["TRACE $(words[2])"]
    elseif command == "HASH"
        capacity = checked_capacity(number(3))
        key = words[2]
        return ["HASH $key m=$capacity h31=$(hash_key(key, 31, capacity)) h37=$(hash_key(key, 37, capacity)) step=$(1 + hash_key(key, 37, capacity - 1))"]
    elseif command == "BENCH"
        capacity = checked_capacity(number(2))
        count, width, seed = number(3), number(4), number(5)
        check_generation(count, width, seed)
        return benchmark(next_prime(capacity), count, width, seed, sim.maxload)
    end
    table = sim.table
    isnothing(table) && fail("NO TABLE")
    reporting = sim.trace ? TRACED : FULL
    if command in ("PUT", "ADD")
        _, lines = put_item!(table, Item(words[2], number(3)), command == "ADD", sim.maxload, reporting)
        return lines
    elseif command == "GET"
        return get_item!(table, words[2], sim.trace)
    elseif command == "DEL"
        _, lines = delete_item!(table, words[2], sim.minload, sim.maxload, reporting)
        return lines
    elseif command == "PROBE"
        search = lookup(table, words[2]; trace = true)
        row = with_words("PROBE $(words[2])", search.path)
        return [row * " $(found(search) ? "FOUND" : "MISS") probes=$(search.probes)"]
    elseif command in ("GEN", "GENDEL")
        count, width, seed = number(2), number(3), number(4)
        check_generation(count, width, seed)
        changed, lines = 0, String[]
        for (index, key) in enumerate(generate_keys(count, width, seed))
            success, output = command == "GEN" ? put_item!(table, Item(key, index), false, sim.maxload, REHASHES) :
                                                delete_item!(table, key, sim.minload, sim.maxload, REHASHES)
            changed += success
            append!(lines, output)
        end
        summary = command == "GEN" ? "new=$changed updated=$(count - changed)" : "deleted=$changed missing=$(count - changed)"
        push!(lines, "$command $count $summary")
        return lines
    elseif command in ("RESIZE", "CONVERT")
        mode, capacity = table.mode, table.capacity
        if command == "RESIZE"
            capacity = next_prime(checked_capacity(number(2)))
        else
            mode = checked_mode(words[2])
        end
        100 * table.size <= sim.maxload * slot_count(mode, capacity) || fail("TOO SMALL")
        trial = rebuilt(mode, capacity, item_list(table))
        isnothing(trial) && fail("REBUILD FAILED")
        row = command == "RESIZE" ? "RESIZE $(table.capacity) -> $capacity" : "CONVERT $(table.mode) -> $mode cap=$capacity"
        adopt!(table, trial)
        return [row]
    elseif command == "CLEAR"
        old = table.size
        adopt!(table, Table(table.mode, table.capacity))
        return ["CLEAR $old"]
    elseif command == "DUMP"
        return dump_table(table)
    elseif command == "MAP"
        return map_table(table)
    elseif command == "STATS"
        return table_stats(table)
    elseif command == "KEYS"
        sorted_keys = sort!([item.key for item in item_list(table)])
        return [with_words("KEYS $(table.size)", sorted_keys)]
    elseif command == "TOP"
        limit = number(2)
        1 <= limit <= 100 || fail("BAD ARGUMENT")
        records = sort(record_items(table); by = record -> (-record.cost, record.item.key))
        selected = records[1:min(limit, length(records))]
        return vcat(["TOP $(length(selected))"], ["$(record.item.key) cost=$(record.cost) at=$(position_text(table, record.position))" for record in selected])
    elseif command == "SCAN"
        cursor, limit = number(2), number(3)
        1 <= limit <= 100 || fail("BAD ARGUMENT")
        cursor < slot_count(table) || fail("BAD CURSOR")
        return [table_scan(table, cursor, limit)]
    elseif command == "CLUSTERS"
        return cluster_report(table)
    elseif command == "DIST"
        return cost_report(table)
    elseif command == "COMPARE"
        return compare_modes(table, next_prime(checked_capacity(number(2))), sim.maxload)
    end
    error("unreachable command")
end
function main()
    count = parse(Int, readline())
    simulator = Simulator()
    for _ in 1:count
        line = readline()
        try
            foreach(println, execute!(simulator, line))
        catch error
            error isa CommandError || rethrow()
            println("ERROR ", error.message)
        end
    end
end
main()
