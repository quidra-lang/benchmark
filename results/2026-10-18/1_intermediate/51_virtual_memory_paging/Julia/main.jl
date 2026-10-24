using Printf
const POLICIES = ["FIFO", "LRU", "LFU", "NRU", "AGING", "CLOCK", "ECLOCK", "WSCLOCK", "RANDOM", "OPT"]
const CLOCKS = ["CLOCK", "ECLOCK", "WSCLOCK"]
struct CommandError <: Exception
    text::String
end
fail(s) = throw(CommandError(s))
num(s) = parse(Int, s)
addr(s) = parse(Int, s[3:end]; base=16)
hex(n) = "0x" * uppercase(string(n; base=16))
function ratio(x, y)
    v = y == 0 ? 0 : div(10000x, y)
    @sprintf("%d.%02d%%", div(v, 100), mod(v, 100))
end
function settings(words)
    c = Dict{String,Union{Int,String}}("page"=>256, "frames"=>4, "tlb"=>4, "sets"=>1, "policy"=>"FIFO", "scope"=>"GLOBAL", "asid"=>"OFF", "tick"=>0, "tau"=>8, "seed"=>1)
    seen = Set{String}()
    limits = Dict("frames"=>(1,16), "tlb"=>(1,8), "sets"=>(1,8), "tick"=>(0,1000), "tau"=>(1,1000), "seed"=>(1,2147483646))
    for word in words
        k, text = String.(split(word, '='))
        haskey(c, k) || fail("unknown key $k")
        k in seen && fail("duplicate key $k")
        push!(seen, k)
        value = text
        if k in ("policy", "scope", "asid")
            choices = k == "policy" ? POLICIES : k == "scope" ? ["GLOBAL", "LOCAL"] : ["ON", "OFF"]
            text in choices || fail("invalid $k")
        else
            value = num(text)
            if k == "page"
                (16 <= value <= 4096 && (value & (value - 1)) == 0) || fail("invalid $k")
            else
                lo, hi = limits[k]
                lo <= value <= hi || fail("invalid $k")
            end
        end
        c[k] = value
    end
    mod(c["tlb"], c["sets"]) == 0 || fail("invalid sets")
    c
end
mutable struct Page
    pid::Int
    number::Int
    frame::Int
    slot::Int
    ro::Bool
    locked::Bool
    seen::Bool
    r::Int
    m::Int
    load::Int
    last::Int
    uses::Int
    age::Int
end
Page(pid, n) = Page(pid, n, -1, -1, false, false, false, 0, 0, 0, 0, 0, 0)
label(p::Page) = "P$(p.pid):$(p.number)"
mutable struct VMProcess
    pid::Int
    pages::Vector{Page}
    faults::Int
    writes::Int
    seg::Int
    prot::Int
    resident::Int
    peak::Int
    hand::Int
    exited::Bool
    history::Vector{Int}
end
VMProcess(pid, n) = VMProcess(pid, [Page(pid, i) for i in 0:(n - 1)], 0, 0, 0, 0, 0, 0, 0, false, Int[])
struct Access
    pid::Int
    op::String
    address::Int
end
struct Event
    kind::String
    pid::Int
    op::String
    address::Int
    first::Int
    last::Int
    locked::Bool
end
Event(kind; pid=0, op="", address=0, first=0, last=0, locked=false) = Event(kind, pid, op, address, first, last, locked)
mutable struct Simulation
    config::Dict{String,Union{Int,String}}
    processes::Dict{Int,VMProcess}
    frames::Vector{Union{Nothing,Page}}
    slots::Vector{Union{Nothing,Page}}
    tlb::Vector{Vector{Page}}
    refs::Vector{Tuple{Int,Int}}
    position::Int
    time::Int
    counts::Dict{String,Int}
    lastpid::Int
    hand::Int
    random::Int
    history::Vector{Int}
end
function Simulation(c, refs)
    counts = Dict(k=>0 for k in ("faults", "zero", "swapin", "tlbhits", "writebacks", "switches"))
    Simulation(c, Dict{Int,VMProcess}(), Union{Nothing,Page}[nothing for _ in 1:c["frames"]], Union{Nothing,Page}[], [Page[] for _ in 1:c["sets"]], refs, 0, 0, counts, 0, 0, c["seed"], Int[])
end
pids(s::Simulation) = sort(collect(keys(s.processes)))
function process(s, pid)
    haskey(s.processes, pid) || fail("unknown process $pid")
    p = s.processes[pid]
    p.exited && fail("process $pid exited")
    p
end
function quota(s, pid)
    ids = pids(s)
    q, r = divrem(s.config["frames"], length(ids))
    q + (findfirst(==(pid), ids) <= r)
end
function removetlb!(s, p)
    filter!(x -> x !== p, s.tlb[mod(p.number, s.config["sets"]) + 1])
end
function writeback!(s, p)
    s.counts["writebacks"] += 1
    s.processes[p.pid].writes += 1
    p.m = 0
    if p.slot < 0
        i = findfirst(isnothing, s.slots)
        if i === nothing
            push!(s.slots, nothing)
            i = length(s.slots)
        end
        p.slot = i - 1
        s.slots[i] = p
    end
end
function nextuse(s, p)
    for i in (s.position + 1):length(s.refs)
        s.refs[i] == (p.pid, p.number) && return i
    end
    length(s.refs) + 1
end
function choose!(s, proc, candidates)
    c = s.config
    policy = c["policy"]
    if policy == "RANDOM"
        s.random = mod(48271s.random, 2147483647)
        return candidates[mod(s.random, length(candidates)) + 1]
    elseif policy in CLOCKS
        hand = c["scope"] == "LOCAL" ? proc.hand : s.hand
        order = sort(candidates; by=f -> mod(f - 1 - hand, c["frames"]))
        chosen = 0
        if policy == "CLOCK"
            while chosen == 0
                for f in order
                    p = s.frames[f]
                    if p.r == 0
                        chosen = f
                        break
                    end
                    p.r = 0
                end
            end
        elseif policy == "ECLOCK"
            while chosen == 0
                for f in order
                    p = s.frames[f]
                    if p.r == 0 && p.m == 0
                        chosen = f
                        break
                    end
                end
                chosen != 0 && break
                for f in order
                    p = s.frames[f]
                    if p.r == 0 && p.m == 1
                        chosen = f
                        break
                    end
                    p.r = 0
                end
            end
        else
            for f in order
                p = s.frames[f]
                if p.r == 1
                    p.r, p.last = 0, s.time
                elseif s.time - p.last > c["tau"]
                    if p.m == 0
                        chosen = f
                        break
                    end
                    writeback!(s, p)
                end
            end
            if chosen == 0
                i = findfirst(f -> s.frames[f].m == 0, order)
                chosen = i === nothing ? order[1] : order[i]
            end
        end
        if c["scope"] == "LOCAL"
            proc.hand = mod(chosen, c["frames"])
        else
            s.hand = mod(chosen, c["frames"])
        end
        return chosen
    end
    function rank(f)
        p = s.frames[f]
        policy == "FIFO" && return (p.load, f)
        policy == "LRU" && return (p.last, f)
        policy == "LFU" && return (p.uses, p.load)
        policy == "NRU" && return (2p.r + p.m, f)
        policy == "AGING" && return (p.age, p.load)
        (-nextuse(s, p), f)
    end
    first(sort(candidates; by=rank))
end
function target!(s, p)
    globalmode = s.config["scope"] == "GLOBAL"
    if globalmode || p.resident < quota(s, p.pid)
        i = findfirst(isnothing, s.frames)
        i !== nothing && return i
    end
    candidates = [f for f in eachindex(s.frames) if s.frames[f] !== nothing && (globalmode || s.frames[f].pid == p.pid)]
    unlocked = filter(f -> !s.frames[f].locked, candidates)
    choose!(s, p, isempty(unlocked) ? candidates : unlocked)
end
function access!(s, a::Access, position)
    s.position = position
    s.time += 1
    c = s.config
    p = s.processes[a.pid]
    switched = s.lastpid != 0 && s.lastpid != a.pid
    if switched
        s.counts["switches"] += 1
        c["asid"] == "OFF" && foreach(empty!, s.tlb)
    end
    s.lastpid = a.pid
    n, off = divrem(a.address, c["page"])
    page = p.pages[n + 1]
    set = s.tlb[mod(n, c["sets"]) + 1]
    hit = any(x -> x === page, set)
    result = ""
    fault = 0
    if hit
        s.counts["tlbhits"] += 1
        result = "TLBHIT"
        removetlb!(s, page)
    elseif page.frame >= 0
        result = "HIT"
    else
        fault = 1
        p.faults += 1
        s.counts["faults"] += 1
        source = page.slot < 0 ? "zero" : "swapin"
        s.counts[source] += 1
        result = "FAULT " * uppercase(source)
        f = target!(s, p)
        victim = s.frames[f]
        if victim !== nothing
            result *= " evict=$(label(victim))"
            victim.frame = -1
            s.processes[victim.pid].resident -= 1
            removetlb!(s, victim)
            if victim.m == 1
                writeback!(s, victim)
                result *= " writeback"
            end
        end
        s.frames[f] = page
        page.frame, page.load = f - 1, s.time
        page.uses = page.m = page.age = 0
        p.resident += 1
        p.peak = max(p.peak, p.resident)
    end
    length(set) == div(c["tlb"], c["sets"]) && pop!(set)
    pushfirst!(set, page)
    page.r = 1
    a.op == "W" && (page.m = 1)
    page.last = s.time
    page.uses += 1
    page.seen = true
    push!(p.history, n)
    push!(s.history, fault)
    physical = page.frame * c["page"] + off
    line = "t=$(s.time) P$(a.pid) $(a.op) $(hex(a.address)) page=$n frame=$(page.frame) phys=$(hex(physical)) $result"
    switched && (line *= " switch")
    lines = [line]
    if c["tick"] > 0 && mod(s.time, c["tick"]) == 0
        for pg in s.frames
            pg === nothing && continue
            pg.age = div(pg.age, 2) + 128pg.r
            pg.r = 0
        end
        push!(lines, "t=$(s.time) tick")
    end
    lines
end
function exit!(s, pid)
    freed = slots = 0
    for (i, pg) in enumerate(s.frames)
        if pg !== nothing && pg.pid == pid
            s.frames[i] = nothing
            pg.frame = -1
            removetlb!(s, pg)
            freed += 1
        end
    end
    for (i, pg) in enumerate(s.slots)
        if pg !== nothing && pg.pid == pid
            s.slots[i] = nothing
            pg.slot = -1
            slots += 1
        end
    end
    p = s.processes[pid]
    p.resident, p.exited = 0, true
    freed, slots
end
function clean!(s)
    written = 0
    for pg in s.frames
        if pg !== nothing && pg.m == 1
            writeback!(s, pg)
            written += 1
        end
    end
    written
end
function lock!(s, e::Event)
    for pg in s.processes[e.pid].pages[(e.first + 1):(e.last + 1)]
        pg.locked = e.locked
    end
end
function rerun(s, events, policy, frames)
    c = copy(s.config)
    c["policy"], c["frames"] = policy, frames
    refs = [(e.pid, div(e.address, c["page"])) for e in events if e.kind == "ACCESS"]
    r = Simulation(c, refs)
    for id in pids(s)
        r.processes[id] = VMProcess(id, length(s.processes[id].pages))
    end
    pos = 0
    for e in events
        if e.kind == "ACCESS"
            pos += 1
            access!(r, Access(e.pid, e.op, e.address), pos)
        elseif e.kind == "EXIT"
            exit!(r, e.pid)
        elseif e.kind == "CLEAN"
            clean!(r)
        else
            lock!(r, e)
        end
    end
    r
end
function command!(s, words, position, events, trace)
    cmd, v = words[1], words[2:end]
    n(i) = num(v[i])
    c = s.config
    if cmd == "PROCESS"
        id, count = n(1), n(2)
        position > 0 && fail("processes are fixed")
        haskey(s.processes, id) && fail("duplicate process $id")
        1 <= count <= 256 || fail("invalid page count")
        (length(s.processes) >= 8 || (c["scope"] == "LOCAL" && length(s.processes) >= c["frames"])) && fail("too many processes")
        s.processes[id] = VMProcess(id, count)
    elseif cmd == "EXIT"
        p = process(s, n(1))
        f, slots = exit!(s, p.pid)
        push!(events, Event("EXIT"; pid=p.pid))
        println("EXIT P$(p.pid) freed=$f slots=$slots")
    elseif cmd in ("PROTECT", "LOCK", "UNLOCK")
        p = process(s, n(1))
        first, last = n(2), n(3)
        (first > last || last >= length(p.pages)) && fail("invalid page range")
        if cmd == "PROTECT"
            for pg in p.pages[(first + 1):(last + 1)]
                pg.ro = v[4] == "RO"
            end
        else
            e = Event("LOCK"; pid=p.pid, first=first, last=last, locked=cmd == "LOCK")
            lock!(s, e)
            push!(events, e)
        end
    elseif cmd == "TRACE"
        return v[1] == "ON"
    elseif cmd == "SUMMARY"
        println("SUMMARY policy=$(c["policy"]) scope=$(c["scope"]) time=$(s.time)")
        k = s.counts
        seg = sum((p.seg for p in values(s.processes)); init=0)
        prot = sum((p.prot for p in values(s.processes)); init=0)
        println("total faults=$(k["faults"]) zero=$(k["zero"]) swapin=$(k["swapin"]) faultrate=$(ratio(k["faults"], s.time)) tlbhits=$(k["tlbhits"]) tlbrate=$(ratio(k["tlbhits"], s.time)) writebacks=$(k["writebacks"]) switches=$(k["switches"]) segfaults=$seg protfaults=$prot")
        for id in pids(s)
            p = s.processes[id]
            tail = c["scope"] == "LOCAL" ? " quota=$(quota(s, id))" : ""
            p.exited && (tail *= " exited")
            println("P$id accesses=$(length(p.history)) faults=$(p.faults) writebacks=$(p.writes) segfaults=$(p.seg) protfaults=$(p.prot) resident=$(p.resident) peak=$(p.peak)$tail")
        end
    elseif cmd == "FRAMES"
        println("FRAMES used=$(count(!isnothing, s.frames))/$(c["frames"])")
        for (i, pg) in enumerate(s.frames)
            if pg === nothing
                println("$(i - 1) free")
            else
                tail = pg.locked ? " locked" : ""
                println("$(i - 1) $(label(pg)) R=$(pg.r) M=$(pg.m) load=$(pg.load) last=$(pg.last) uses=$(pg.uses) age=$(pg.age)$tail")
            end
        end
        if c["policy"] in CLOCKS
            println(c["scope"] == "GLOBAL" ? "hand=$(s.hand)" : "hand" * join((" P$id=$(s.processes[id].hand)" for id in pids(s))))
        end
    elseif cmd == "PAGETABLE"
        p = process(s, n(1))
        println("PAGETABLE P$(p.pid) pages=$(length(p.pages)) resident=$(p.resident)")
        for pg in p.pages
            pg.seen || continue
            text = pg.frame >= 0 ? "frame=$(pg.frame) R=$(pg.r) M=$(pg.m)" : pg.slot >= 0 ? "swap=$(pg.slot)" : "zero"
            pg.ro && (text *= " RO")
            pg.locked && (text *= " locked")
            println("$(pg.number) $text")
        end
    elseif cmd == "TLB"
        println("TLB used=$(sum(length, s.tlb))/$(c["tlb"]) sets=$(c["sets"])")
        for (i, set) in enumerate(s.tlb)
            println("set $(i - 1):", join((" $(label(pg))->$(pg.frame)" for pg in set)))
        end
    elseif cmd == "SWAP"
        println("SWAP used=$(count(!isnothing, s.slots))")
        for (i, pg) in enumerate(s.slots)
            pg !== nothing && println("$(i - 1) $(label(pg))")
        end
    elseif cmd == "CLEAN"
        println("CLEAN written=$(clean!(s))")
        push!(events, Event("CLEAN"))
    elseif cmd == "COMPARE"
        println("COMPARE accesses=$(s.time) frames=$(c["frames"])")
        results = Tuple{Int,Int,Int,String}[]
        for (i, policy) in enumerate(POLICIES)
            r = rerun(s, events, policy, c["frames"])
            k = r.counts
            println("$policy faults=$(k["faults"]) writebacks=$(k["writebacks"]) tlbhits=$(k["tlbhits"])")
            push!(results, (k["faults"], k["writebacks"], i, policy))
        end
        println("ranking ", join((x[4] for x in sort(results)), " "))
    elseif cmd == "CURVE"
        policy, lo, hi = v[1], n(2), n(3)
        policy in POLICIES || fail("unknown policy")
        (1 <= lo <= hi <= 16 && !(c["scope"] == "LOCAL" && lo < length(s.processes))) || fail("invalid frame range")
        println("CURVE $policy frames=$lo..$hi")
        previous = -1
        for f in lo:hi
            faults = rerun(s, events, policy, f).counts["faults"]
            println("F=$f faults=$faults", previous >= 0 && faults > previous ? " ANOMALY" : "")
            previous = faults
        end
    elseif cmd == "EAT"
        if s.time == 0
            println("EAT accesses=0")
        else
            total = n(1) * s.time + n(2) * (2s.time - s.counts["tlbhits"]) + n(3) * (s.counts["swapin"] + s.counts["writebacks"])
            average = div(100total, s.time)
            @printf("EAT accesses=%d total=%d average=%d.%02d\n", s.time, total, div(average, 100), mod(average, 100))
        end
    elseif cmd == "TIMELINE"
        w = n(1)
        w >= 1 || fail("invalid window")
        totals = [sum(s.history[i:min(i + w - 1, end)]) for i in 1:w:length(s.history)]
        println("TIMELINE window=$w", join((" $x" for x in totals)))
    elseif cmd in ("WSET", "HOT")
        p = process(s, n(1))
        k = n(2)
        k >= 1 || fail(cmd == "WSET" ? "invalid window" : "invalid count")
        if cmd == "WSET"
            pages = sort(unique(p.history[max(1, length(p.history) - k + 1):end]))
            println("WSET P$(p.pid) window=$k size=$(length(pages))", join((" $x" for x in pages)))
        else
            counts = Dict{Int,Int}()
            for pg in p.history
                counts[pg] = get(counts, pg, 0) + 1
            end
            pages = sort(collect(keys(counts)); by=x -> (-counts[x], x))
            println("HOT P$(p.pid)", join((" $pg:$(counts[pg])" for pg in pages[1:min(k, end)])))
        end
    end
    trace
end
function expand(lines)
    items = Union{Access,Vector{String}}[]
    for line in lines
        w = String.(split(line))
        if isdigit(w[1][1])
            push!(items, Access(num(w[1]), w[2], addr(w[3])))
        elseif w[1] == "LOOP"
            for _ in 1:num(w[7]), i in 0:(num(w[6]) - 1)
                push!(items, Access(num(w[2]), w[3], addr(w[4]) + i * num(w[5])))
            end
        elseif w[1] == "RAND"
            x = num(w[6])
            lo, hi = addr(w[3]), addr(w[4])
            for _ in 1:num(w[5])
                x = mod(48271x, 2147483647)
                address = lo + mod(x, hi - lo)
                x = mod(48271x, 2147483647)
                push!(items, Access(num(w[2]), mod(x, 100) < num(w[7]) ? "W" : "R", address))
            end
        else
            push!(items, w)
        end
    end
    items
end
function main()
    n = num(readline())
    items = expand([readline() for _ in 1:n])
    s = nothing
    trace = false
    position = 0
    events = Event[]
    for (index, item) in enumerate(items)
        try
            if item isa Vector{String} && item[1] == "SYSTEM"
                s = nothing
                c = settings(item[2:end])
                refs = Tuple{Int,Int}[]
                for future in items[(index + 1):end]
                    future isa Vector{String} && future[1] == "SYSTEM" && break
                    future isa Access && push!(refs, (future.pid, div(future.address, c["page"])))
                end
                s = Simulation(c, refs)
                trace, position, events = false, 0, Event[]
                println("SYSTEM ", join(("$k=$(c[k])" for k in ("page", "frames", "tlb", "sets", "policy", "scope", "asid", "tick", "tau", "seed")), " "))
            else
                s === nothing && fail("no system")
                if item isa Access
                    position += 1
                    p = process(s, item.pid)
                    if item.address >= length(p.pages) * s.config["page"]
                        p.seg += 1
                        println("SEGFAULT P$(item.pid) $(hex(item.address))")
                    elseif item.op == "W" && p.pages[div(item.address, s.config["page"]) + 1].ro
                        p.prot += 1
                        println("PROTFAULT P$(item.pid) $(hex(item.address))")
                    else
                        lines = access!(s, item, position)
                        push!(events, Event("ACCESS"; pid=item.pid, op=item.op, address=item.address))
                        trace && foreach(println, lines)
                    end
                else
                    trace = command!(s, item, position, events, trace)
                end
            end
        catch e
            e isa CommandError || rethrow()
            println("ERROR ", e.text)
        end
    end
end
main()
