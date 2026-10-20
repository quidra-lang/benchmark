const POLICIES = ("COST", "NEAREST", "ROUND", "ETA")
const CONFIG_KEYS = ("FLOORS", "CARS", "CAPACITY", "DOOR", "START", "POLICY", "ZONES", "PARK", "PATIENCE", "BYPASS", "PERIOD", "LIMIT", "COMPARE")
const ARITY = Dict("CALL" => 3, "CANCEL" => 1, "OUT" => 1, "IN" => 1, "HOLD" => 2, "FIRE" => 1, "RESET" => 0, "WHERE" => 1, "STATUS" => 0)
struct ConfigError <: Exception
    reason::String
end
fail(s) = throw(ConfigError(s))
joined(xs) = isempty(xs) ? "-" : join(xs, ',')
function average(total, count)
    count == 0 && return "-"
    x = 100total ÷ count
    string(x ÷ 100, ".", lpad(x % 100, 2, '0'))
end
mutable struct Config
    floors::Int
    cars::Int
    capacity::Int
    door::Int
    starts::Vector{Int}
    policy::String
    zones::Vector{Tuple{Int,Int}}
    park::Int
    homes::Vector{Int}
    patience::Int
    bypass::Int
    period::Int
    limit::Int
    compare::Vector{String}
end
function parse_config(settings)
    entries = Dict{String,Vector{String}}()
    for w in settings
        k = w[1]
        k in CONFIG_KEYS || fail("unknown key $k")
        haskey(entries, k) && fail("duplicate key $k")
        entries[k] = w[2:end]
    end
    for k in CONFIG_KEYS[1:5]
        haskey(entries, k) || fail("missing key $k")
    end
    c = Config(0, 0, 0, 0, Int[], "COST", Tuple{Int,Int}[], -1, Int[], 0, 100, 0, 1000, String[])
    for k in CONFIG_KEYS
        haskey(entries, k) || continue
        v = entries[k]
        expected = k in ("START", "ZONES") ? c.cars : k == "PARK" ? c.cars + 1 : 1
        correct = k == "COMPARE" ? 1 <= length(v) <= 4 : length(v) == expected
        correct || fail("wrong number of values for $k")
        bounded(s, lo, hi) = let x = parse(Int, s)
            lo <= x <= hi || fail("bad value for $k")
            x
        end
        if k == "FLOORS"
            c.floors = bounded(v[1], 2, 50)
        elseif k == "CARS"
            c.cars = bounded(v[1], 1, 8)
        elseif k == "CAPACITY"
            c.capacity = bounded(v[1], 1, 20)
        elseif k == "DOOR"
            c.door = bounded(v[1], 1, 9)
        elseif k == "START"
            c.starts = [bounded(s, 1, c.floors) for s in v]
        elseif k == "POLICY"
            v[1] in POLICIES || fail("bad value for $k")
            c.policy = v[1]
        elseif k == "ZONES"
            for s in v
                a, b = parse.(Int, split(s, ':'))
                1 <= a < b <= c.floors || fail("bad value for $k")
                push!(c.zones, (a, b))
            end
        elseif k == "PARK"
            c.park = bounded(v[1], 0, 100)
            c.homes = [bounded(s, 1, c.floors) for s in v[2:end]]
        elseif k == "PATIENCE"
            c.patience = bounded(v[1], 1, 1000)
        elseif k == "BYPASS"
            c.bypass = bounded(v[1], 50, 100)
        elseif k == "PERIOD"
            c.period = bounded(v[1], 1, 1000)
        elseif k == "LIMIT"
            c.limit = bounded(v[1], 1, 5000)
        else
            (all(s -> s in POLICIES, v) && allunique(v)) || fail("bad value for $k")
            c.compare = v
        end
    end
    isempty(c.zones) && (c.zones = fill((1, c.floors), c.cars))
    for i in 1:c.cars
        lo, hi = c.zones[i]
        lo <= c.starts[i] <= hi || fail("car $i starts outside its zone")
        c.park >= 0 && !(lo <= c.homes[i] <= hi) && fail("car $i home outside its zone")
    end
    c
end
struct ElevatorEvent
    time::Int
    command::String
    args::Vector{Int}
end
function validate_events(c, lines, output)
    accepted = ElevatorEvent[]
    lasttime = groups = 0
    out = Set{Int}()
    fire = false
    for (line, w) in lines
        t = parse(Int, w[1])
        cmd = w[2]
        reason = ""
        v = Int[]
        if !haskey(ARITY, cmd)
            reason = "unknown command $cmd"
        elseif length(w) - 2 != ARITY[cmd]
            reason = "wrong number of arguments for $cmd"
        elseif t < lasttime
            reason = "time goes backwards"
        else
            v = parse.(Int, w[3:end])
            if cmd == "CALL"
                a, b, n = v
                if !(1 <= a <= c.floors && 1 <= b <= c.floors)
                    reason = "bad floor"
                elseif a == b
                    reason = "same floor"
                elseif !(1 <= n <= 99)
                    reason = "bad count"
                elseif !any(lo <= a <= hi && lo <= b <= hi for (lo, hi) in c.zones)
                    reason = "no car serves $a->$b"
                elseif fire
                    reason = "fire service active"
                end
            elseif cmd in ("CANCEL", "WHERE")
                !(1 <= v[1] <= groups) && (reason = "unknown group")
            elseif cmd in ("OUT", "IN", "HOLD")
                e = v[1]
                if !(1 <= e <= c.cars)
                    reason = "bad car"
                elseif cmd == "OUT" && e in out
                    reason = "car $e already out"
                elseif cmd == "IN" && !(e in out)
                    reason = "car $e already in"
                elseif cmd == "HOLD" && !(1 <= v[2] <= 9)
                    reason = "bad ticks"
                end
            elseif cmd == "FIRE"
                if !(1 <= v[1] <= c.floors)
                    reason = "bad floor"
                elseif fire
                    reason = "fire already active"
                end
            elseif cmd == "RESET" && !fire
                reason = "fire not active"
            end
        end
        if !isempty(reason)
            push!(output, "line $line: $reason")
            continue
        end
        push!(accepted, ElevatorEvent(t, cmd, v))
        lasttime = t
        if cmd == "CALL"
            groups += 1
        elseif cmd == "OUT"
            push!(out, v[1])
        elseif cmd == "IN"
            delete!(out, v[1])
        elseif cmd == "FIRE"
            fire = true
        elseif cmd == "RESET"
            fire = false
        end
    end
    accepted
end
mutable struct Group
    number::Int
    landing::Int
    destination::Int
    count::Int
    time::Int
    direction::Int
    waiting::Int
    car::Int
    boarded::Int
    delivered::Int
    lost::Int
    lastboard::Int
    lastalight::Int
    cars::Set{Int}
    waittotal::Int
    traveltotal::Int
end
struct Passenger
    group::Group
    count::Int
    boarded::Int
end
mutable struct Car
    number::Int
    floor::Int
    low::Int
    high::Int
    home::Int
    direction::Int
    door::Int
    passengers::Vector{Passenger}
    calls::Vector{Group}
    service::Bool
    idlestart::Int
    distance::Int
    stops::Int
    boarded::Int
    busy::Int
    energy::Int
end
mutable struct Simulation
    config::Config
    policy::String
    cars::Vector{Car}
    groups::Vector{Group}
    pending::Vector{Group}
    fire::Int
    lastround::Int
    time::Int
    status::String
    log::Vector{String}
    logging::Bool
    abandoned::Int
    evacuated::Int
    delivered::Int
    waittotal::Int
    traveltotal::Int
    maxwait::Int
end
function Simulation(c, policy, logging)
    cars = [Car(i, c.starts[i], c.zones[i]..., c.park >= 0 ? c.homes[i] : 0,
                0, 0, Passenger[], Group[], true, 0, 0, 0, 0, 0, 0) for i in 1:c.cars]
    Simulation(c, policy, cars, Group[], Group[], 0, 0, 0, "", String[], logging, 0, 0, 0, 0, 0, 0)
end
function log!(s, parts...)
    s.logging && push!(s.log, string(s.time, " ", join(parts, " ")))
end
load(c) = sum((p.count for p in c.passengers); init=0)
targets(c) = union(Set(p.group.destination for p in c.passengers), Set(g.landing for g in c.calls))
bypassing(s, c) = load(c) * 100 >= s.config.capacity * s.config.bypass
function cost(s, c, g)
    f, d, x = c.floor, c.direction, g.landing
    (s.policy == "NEAREST" || d == 0) && return abs(f - x)
    floors = targets(c)
    if g.direction == d && (x - f) * d >= 0
        distance = abs(x - f)
        via = count(y -> (y - f) * d > 0 && (x - y) * d > 0, floors)
    else
        m = d > 0 ? maximum(union(floors, Set([f]))) : minimum(union(floors, Set([f])))
        distance = abs(f - m) + abs(m - x)
        via = count(y -> (y - f) * d > 0, floors)
    end
    s.policy == "COST" ? distance : distance + s.config.door * via + c.door
end
function assign!(s, g, excluded=0)
    candidates = [c for c in s.cars if c.service && c.number != excluded &&
                  c.low <= g.landing <= c.high && c.low <= g.destination <= c.high]
    isempty(candidates) && return false
    if s.policy == "ROUND"
        next = findfirst(c -> c.number > s.lastround, candidates)
        chosen = candidates[isnothing(next) ? 1 : next]
        s.lastround = chosen.number
        log!(s, "E$(chosen.number)", "ASSIGN", "G$(g.number)")
    else
        costs = [cost(s, c, g) for c in candidates]
        i = argmin(costs)
        chosen = candidates[i]
        log!(s, "E$(chosen.number)", "ASSIGN", "G$(g.number)", "cost=$(costs[i])")
    end
    g.car != 0 && filter!(x -> x !== g, s.cars[g.car].calls)
    push!(chosen.calls, g)
    g.car = chosen.number
    true
end
function dispatch!(s, g)
    if !assign!(s, g)
        push!(s.pending, g)
        log!(s, "PENDING", "G$(g.number)")
    end
end
function walk!(s, g, word)
    if g.car == 0
        filter!(x -> x !== g, s.pending)
    else
        filter!(x -> x !== g, s.cars[g.car].calls)
        g.car = 0
    end
    log!(s, word, "G$(g.number)", "x$(g.waiting)")
    g.lost += g.waiting
    s.abandoned += g.waiting
    g.waiting = 0
end
function event!(s, event)
    cmd, v = event.command, event.args
    if cmd == "CALL"
        a, b, n = v
        g = Group(length(s.groups) + 1, a, b, n, s.time, sign(b - a), n, 0,
                  0, 0, 0, 0, 0, Set{Int}(), 0, 0)
        push!(s.groups, g)
        log!(s, "CALL", "G$(g.number)", "$a->$b", "x$n")
        dispatch!(s, g)
    elseif cmd == "CANCEL"
        g = s.groups[v[1]]
        g.waiting > 0 ? walk!(s, g, "CANCEL") : log!(s, "CANCEL", "G$(g.number)", "ignored")
    elseif cmd == "OUT"
        c = s.cars[v[1]]
        c.service = false
        log!(s, "E$(c.number)", "OUT")
        calls = copy(c.calls)
        empty!(c.calls)
        for g in calls
            g.car = 0
            dispatch!(s, g)
        end
    elseif cmd == "IN"
        c = s.cars[v[1]]
        c.service = true
        c.idlestart = s.time
        log!(s, "E$(c.number)", "IN")
        pending = copy(s.pending)
        empty!(s.pending)
        for g in pending
            assign!(s, g) || push!(s.pending, g)
        end
    elseif cmd == "HOLD"
        c = s.cars[v[1]]
        if c.door > 0
            c.door += v[2]
            log!(s, "E$(c.number)", "HOLD", c.door)
        else
            log!(s, "E$(c.number)", "HOLD", "ignored")
        end
    elseif cmd == "FIRE"
        s.fire = v[1]
        log!(s, "FIRE", s.fire)
        for g in s.groups
            g.waiting > 0 && walk!(s, g, "ABANDON")
        end
    elseif cmd == "RESET"
        s.fire = 0
        log!(s, "RESET")
        for c in s.cars
            c.idlestart = s.time
        end
    elseif cmd == "WHERE"
        g = s.groups[v[1]]
        place = g.waiting == 0 ? "-" : g.car == 0 ? "pending" : "E$(g.car)"
        riding = String[]
        for c in s.cars
            n = sum((p.count for p in c.passengers if p.group === g); init=0)
            n > 0 && push!(riding, "E$(c.number)x$n")
        end
        log!(s, "WHERE", "G$(g.number)", "waiting=$(g.waiting)", "car=$place",
             "riding=$(joined(riding))", "delivered=$(g.delivered)", "lost=$(g.lost)")
    elseif cmd == "STATUS"
        for c in s.cars
            stops = sort(unique([p.group.destination for p in c.passengers]))
            calls = ["G$(g.number)" for g in c.calls]
            direction = c.direction == 0 ? "idle" : c.direction > 0 ? "up" : "down"
            service = c.service ? "in" : "out"
            log!(s, "STATUS", "E$(c.number)", "floor=$(c.floor)", "dir=$direction",
                 "door=$(c.door)", "load=$(load(c))", "stops=$(joined(stops))",
                 "calls=$(joined(calls))", "service=$service")
        end
        log!(s, "STATUS", "pending=$(joined(["G$(g.number)" for g in s.pending]))")
    end
end
function direction(s, c)
    f, d = c.floor, c.direction
    here = bypassing(s, c) ? Group[] : [g for g in c.calls if g.landing == f]
    floors = targets(c)
    if d != 0 && (any(y -> (y - f) * d > 0, floors) || any(g -> g.direction == d, here))
        return d
    elseif !isempty(here)
        return here[1].direction
    elseif d != 0 && any(y -> (y - f) * d < 0, floors)
        return -d
    elseif d == 0 && !isempty(c.calls)
        return sign(c.calls[1].landing - f)
    end
    0
end
function move!(c, step)
    c.energy += step > 0 ? 3 + load(c) : 1
    c.distance += 1
    c.floor += step
end
function open!(s, c)
    log!(s, "E$(c.number)", "OPEN", c.floor)
    c.door = s.config.door
    c.stops += 1
    c.energy += 2
    riding = Passenger[]
    for p in c.passengers
        g = p.group
        if g.destination == c.floor
            log!(s, "E$(c.number)", "ALIGHT", "G$(g.number)", "x$(p.count)")
            wait = p.boarded - g.time
            travel = s.time - g.time
            g.delivered += p.count
            g.lastalight = s.time
            g.waittotal += wait * p.count
            g.traveltotal += travel * p.count
            s.delivered += p.count
            s.waittotal += wait * p.count
            s.traveltotal += travel * p.count
            s.maxwait = max(s.maxwait, wait)
        elseif s.fire != 0
            log!(s, "E$(c.number)", "EVACUATE", "G$(g.number)", "x$(p.count)")
            g.lost += p.count
            s.evacuated += p.count
        else
            push!(riding, p)
        end
    end
    c.passengers = riding
    s.fire != 0 && return
    heading = direction(s, c)
    heading != 0 && (c.direction = heading)
    boarding = [g for g in c.calls if g.landing == c.floor && g.direction == heading]
    for g in boarding
        n = min(s.config.capacity - load(c), g.waiting)
        if n > 0
            push!(c.passengers, Passenger(g, n, s.time))
            c.boarded += n
            g.waiting -= n
            g.boarded += n
            g.lastboard = s.time
            push!(g.cars, c.number)
            log!(s, "E$(c.number)", "BOARD", "G$(g.number)", "x$n")
        end
        if g.waiting == 0
            filter!(x -> x !== g, c.calls)
            g.car = 0
        else
            log!(s, "E$(c.number)", "LEFT", "G$(g.number)", "x$(g.waiting)")
            assign!(s, g, c.number)
        end
    end
end
function advance!(s, c)
    oldfloor = c.floor
    c.door > 0 && (c.door -= 1)
    if c.door == 0
        if s.fire != 0
            heading = sign(s.fire - c.floor)
            stopping = heading == 0 && !isempty(c.passengers)
        else
            heading = direction(s, c)
            stopping = any(p -> p.group.destination == c.floor, c.passengers) ||
                       (!bypassing(s, c) && any(g -> g.landing == c.floor && g.direction == heading, c.calls))
        end
        if stopping
            open!(s, c)
        elseif heading != 0
            c.direction = heading
            move!(c, heading)
        else
            if c.direction != 0
                log!(s, "E$(c.number)", "IDLE", c.floor)
                c.direction = 0
                c.idlestart = s.time
            end
            if s.fire == 0 && c.service && c.home != 0 && c.floor != c.home && s.time - c.idlestart >= s.config.park
                move!(c, sign(c.home - c.floor))
                c.floor == c.home && log!(s, "E$(c.number)", "PARK", c.home)
            end
        end
    end
    (c.door > 0 || c.floor != oldfloor) && (c.busy += 1)
end
function settled(s, c)
    (c.door > 0 || !isempty(c.passengers) || !isempty(c.calls)) && return false
    s.fire != 0 ? c.floor == s.fire : !c.service || c.home == 0 || c.floor == c.home
end
function run!(s, events)
    index = 1
    while true
        if s.config.patience > 0
            for g in s.groups
                g.waiting > 0 && s.time == g.time + s.config.patience && walk!(s, g, "ABANDON")
            end
        end
        while index <= length(events) && events[index].time == s.time
            event!(s, events[index])
            index += 1
        end
        for c in s.cars
            advance!(s, c)
        end
        if index > length(events) && all(c -> settled(s, c), s.cars)
            s.status = "end"
            log!(s, "END")
            return
        elseif s.time == s.config.limit
            s.status = "abort"
            log!(s, "ABORT")
            return
        end
        s.time += 1
    end
end
function averages(s)
    "avg_wait=$(average(s.waittotal, s.delivered)) avg_travel=$(average(s.traveltotal, s.delivered)) max_wait=$(s.delivered == 0 ? "-" : s.maxwait)"
end
function breakdown(label, groups)
    passengers = sum((g.count for g in groups); init=0)
    delivered = sum((g.delivered for g in groups); init=0)
    total = sum((g.waittotal for g in groups); init=0)
    "$label: groups=$(length(groups)) passengers=$passengers delivered=$delivered avg_wait=$(average(total, delivered))"
end
function report!(output, s)
    for g in s.groups
        wait = g.boarded == g.count ? string(g.lastboard - g.time) : "-"
        travel = g.delivered == g.count ? string(g.lastalight - g.time) : "-"
        cars = joined(sort(collect(g.cars)))
        push!(output, "G$(g.number) t=$(g.time) $(g.landing)->$(g.destination) n=$(g.count) delivered=$(g.delivered) lost=$(g.lost) wait=$wait travel=$travel cars=$cars")
    end
    for c in s.cars
        tenths = c.busy * 1000 ÷ (s.time + 1)
        push!(output, "E$(c.number) distance=$(c.distance) stops=$(c.stops) boarded=$(c.boarded) busy=$(c.busy) util=$(tenths ÷ 10).$(tenths % 10)% energy=$(c.energy)")
    end
    for floor in sort(unique([g.landing for g in s.groups]))
        push!(output, breakdown("F$floor", [g for g in s.groups if g.landing == floor]))
    end
    width = s.config.period
    if width > 0
        for period in sort(unique([g.time ÷ width for g in s.groups]))
            groups = [g for g in s.groups if g.time ÷ width == period]
            push!(output, breakdown("P$period $(period * width)-$(period * width + width - 1)", groups))
        end
    end
    passengers = sum((g.count for g in s.groups); init=0)
    push!(output, "summary: groups=$(length(s.groups)) passengers=$passengers delivered=$(s.delivered) abandoned=$(s.abandoned) evacuated=$(s.evacuated) $(averages(s)) end=$(s.time)")
end
function main()
    lines = readlines()
    output = String[]
    names = String[]
    configs = Union{Nothing,Config}[]
    results = Union{Nothing,Simulation}[]
    index = 2
    for _ in 1:parse(Int, lines[1])
        name = String(split(lines[index])[2])
        index += 1
        settings = Vector{String}[]
        eventlines = Tuple{Int,Vector{String}}[]
        while lines[index] != "END"
            w = String.(split(lines[index]))
            if isdigit(w[1][1])
                push!(eventlines, (index, w))
            else
                push!(settings, w)
            end
            index += 1
        end
        index += 1
        push!(names, name)
        push!(output, "== $name ==")
        config = nothing
        try
            config = parse_config(settings)
        catch err
            err isa ConfigError || rethrow()
            push!(output, "error: $(err.reason)")
        end
        push!(configs, config)
        if isnothing(config)
            push!(results, nothing)
            continue
        end
        c = config
        park = c.park < 0 ? "off" : string(c.park)
        patience = c.patience == 0 ? "off" : string(c.patience)
        period = c.period == 0 ? "off" : string(c.period)
        push!(output, "config: floors=$(c.floors) cars=$(c.cars) capacity=$(c.capacity) door=$(c.door) policy=$(c.policy) park=$park patience=$patience bypass=$(c.bypass) period=$period limit=$(c.limit) compare=$(joined(c.compare))")
        for i in 1:c.cars
            lo, hi = c.zones[i]
            home = c.park < 0 ? "-" : string(c.homes[i])
            push!(output, "E$i: start=$(c.starts[i]) zone=$lo-$hi home=$home")
        end
        events = validate_events(c, eventlines, output)
        s = Simulation(c, c.policy, true)
        run!(s, events)
        append!(output, s.log)
        report!(output, s)
        push!(results, s)
        for policy in c.compare
            rerun = Simulation(c, policy, false)
            run!(rerun, events)
            push!(output, "compare $policy: delivered=$(rerun.delivered) $(averages(rerun)) end=$(rerun.time) status=$(rerun.status)")
        end
    end
    push!(output, "== ranking ==")
    ranked = [i for i in eachindex(results) if !isnothing(results[i]) && results[i].status == "end" && results[i].delivered > 0]
    function precedes(i, j)
        a, b = results[i], results[j]
        wa, wb = a.waittotal * b.delivered, b.waittotal * a.delivered
        wa != wb && return wa < wb
        ta, tb = a.traveltotal * b.delivered, b.traveltotal * a.delivered
        ta != tb ? ta < tb : i < j
    end
    sort!(ranked; lt=precedes)
    for (rank, i) in enumerate(ranked)
        push!(output, "$rank. $(names[i]) policy=$(configs[i].policy) $(averages(results[i]))")
    end
    for i in eachindex(results)
        i in ranked && continue
        s = results[i]
        outcome = isnothing(s) ? "invalid" : s.status == "abort" ? "aborted" : "empty"
        push!(output, "- $(names[i]) $outcome")
    end
    push!(output, "== policies ==")
    for policy in POLICIES
        runs = [results[i] for i in ranked if configs[i].policy == policy]
        isempty(runs) && continue
        count = sum(s.delivered for s in runs)
        wait = sum(s.waittotal for s in runs)
        travel = sum(s.traveltotal for s in runs)
        push!(output, "$policy: runs=$(length(runs)) avg_wait=$(average(wait, count)) avg_travel=$(average(travel, count))")
    end
    foreach(println, output)
end
main()
