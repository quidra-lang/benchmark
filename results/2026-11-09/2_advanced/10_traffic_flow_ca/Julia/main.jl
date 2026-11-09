include("minstd.jl")
include("road.jl")
include("vehicles.jl")
include("signals.jl")
include("stats.jl")
using .RandomTraffic, .Road, .Vehicles, .TrafficSignals, .TrafficStats

Base.@kwdef mutable struct Source
    node::String
    rates::Vector{Tuple{Int,Int}}
    segment::Int
    queue::Vector{Int} = Int[]
    head::Int = 1
    queue_start::Int = 0
    queue_max::Int = 0
end
struct Detector
    name::String
    segment::Int
    cell::Int
    width::Int
end
struct Diagram
    segment::Int
    lane::Int
    start::Int
    finish::Int
    lines::Vector{String}
end
struct Ring
    number::Int
    length::Int
    vmax::Int
    warmup::Int
    measure::Int
    seed::Int
    counts::Vector{Int}
end
Base.@kwdef mutable struct Interval
    arrivals::Int = 0
    insertions::Int = 0
    exits::Int = 0
    vehicle_steps::Int = 0
    speed_sum::Int = 0
    passing::Vector{Int}
    occupancy::Vector{Int}
    occupancy_speed::Vector{Int}
end
Interval(count) = Interval(passing=zeros(Int, count), occupancy=zeros(Int, count), occupancy_speed=zeros(Int, count))
mutable struct Move
    vehicle::Vehicle
    segment::Int
    cell::Int
    speed::Int
end
Base.@kwdef mutable struct Simulation
    segments::Vector{Segment} = Segment[]
    by_id::Dict{String,Int} = Dict{String,Int}()
    junctions::Vector{Junction} = Junction[]
    incidents::Vector{Incident} = Incident[]
    stops::Vector{BusStop} = BusStop[]
    classes::Vector{VehicleClass} = VehicleClass[]
    sources::Vector{Source} = Source[]
    sinks::Vector{String} = String[]
    steps::Int = 0
    dawdle::Int = 0
    dawdle_stopped::Int = 0
    interval_length::Int = 1
    bin_width::Int = 1
    detectors::Vector{Detector} = Detector[]
    diagrams::Vector{Diagram} = Diagram[]
    track_numbers::Vector{Int} = Int[]
    tracks::Dict{Int,Vector{String}} = Dict{Int,Vector{String}}()
    rings::Vector{Ring} = Ring[]
    rng::Minstd = Minstd(1)
    vehicles::Vector{Vehicle} = Vehicle[]
    intervals::Vector{Interval} = Interval[]
    events::Vector{String} = String[]
end
time_text(step) = lpad(step, 4, '0')
flag_text(flag) = flag ? "Y" : "N"
optional_text(value) = value == 0 ? "-" : string(value)
share_text(value) = frac(numerator(value), denominator(value))
function load!(sim)
    for name in ["network.txt", "demand.txt", "params.txt"]
        for line in readlines(joinpath("input", name))
            tokens = String.(split(line))
            kind, fields = tokens[1], tokens[2:end]
            if kind == "SEGMENT"
                id, start, finish = fields[1:3]
                count, lanes, limit = parse.(Int, fields[4:end])
                push!(sim.segments, Segment(id, start, finish, count, lanes, limit))
                sim.by_id[id] = length(sim.segments)
            elseif kind == "JUNCTION"
                j = Junction(fields[1], parse(Int, fields[2]), fields[3:end])
                push!(sim.junctions, j)
                for (i, segment) in enumerate(sim.segments)
                    if segment.finish == j.node
                        segment.junction = length(sim.junctions)
                        push!(j.incoming, i)
                    end
                end
            elseif kind == "INCIDENT"
                lane, cell, start, finish = parse.(Int, fields[2:end])
                push!(sim.incidents, Incident(segment=sim.by_id[fields[1]], lane=lane, cell=cell, start=start, finish=finish))
            elseif kind == "STOP"
                index = sim.by_id[fields[1]]
                cell, dwell = parse.(Int, fields[2:end])
                stop = BusStop(index, cell, dwell, 0)
                sim.segments[index].stop = stop
                push!(sim.stops, stop)
            elseif kind == "CLASS"
                push!(sim.classes, VehicleClass(fields[1], parse(Int, fields[2]), parse(Int, fields[3]), fields[4] == "Y", fields[5] == "Y"))
            elseif kind == "SOURCE"
                rates = Tuple{Int,Int}[Tuple(parse.(Int, split(token, ':'))) for token in fields[2:end]]
                entry = findfirst(s -> s.start == fields[1], sim.segments)
                push!(sim.sources, Source(node=fields[1], rates=rates, segment=entry))
            elseif kind == "SINK"
                push!(sim.sinks, fields[1])
            elseif kind == "TURN"
                push!(sim.segments[sim.by_id[fields[1]]].turns, Turn(sim.by_id[fields[2]], parse(Int, fields[3]), 0))
            elseif kind == "seed"
                sim.rng = Minstd(parse(Int, fields[1]))
            elseif kind == "steps"
                sim.steps = parse(Int, fields[1])
            elseif kind == "dawdle"
                sim.dawdle, sim.dawdle_stopped = parse.(Int, fields)
            elseif kind == "interval"
                sim.interval_length = parse(Int, fields[1])
            elseif kind == "bin"
                sim.bin_width = parse(Int, fields[1])
            elseif kind == "detector"
                push!(sim.detectors, Detector(fields[1], sim.by_id[fields[2]], parse(Int, fields[3]), parse(Int, fields[4])))
            elseif kind == "diagram"
                lane, start, finish = parse.(Int, fields[2:end])
                push!(sim.diagrams, Diagram(sim.by_id[fields[1]], lane, start, finish, String[]))
            elseif kind == "track"
                sim.track_numbers = parse.(Int, fields)
                sim.tracks = Dict(number => String[] for number in sim.track_numbers)
            else
                values = parse.(Int, fields)
                push!(sim.rings, Ring(length(sim.rings)+1, values[1:5]..., values[6:end]))
            end
        end
    end
end
record!(sim, step, text) = push!(sim.events, "$(time_text(step)) $text")
green_at(sim, segment, step) = green(sim.junctions[segment.junction], segment.id, step)
function vehicles_on(sim, segment)
    [sim.vehicles[number] for lane in 1:segment.lanes for number in segment.cells[:, lane] if number > 0]
end
function enter!(sim, vehicle, index)
    segment = sim.segments[index]
    push!(vehicle.route, index)
    segment.entered += 1
    if segment.junction != 0
        vehicle.turn = select_weight([turn.weight for turn in segment.turns], draw!(sim.rng))
    end
end
function source_rate(source, step)
    for (rate, finish) in source.rates
        step <= finish && return rate
    end
    0
end
function arrive!(sim, step)
    weights = [kind.weight for kind in sim.classes]
    for (i, source) in enumerate(sim.sources)
        if mod(draw!(sim.rng), 1000) < source_rate(source, step)
            kind = select_weight(weights, draw!(sim.rng))
            number = length(sim.vehicles)+1
            push!(sim.vehicles, Vehicle(number=number, kind=kind, source=i, arrival=step))
            push!(source.queue, number)
            sim.intervals[end].arrivals += 1
        end
    end
end
function entry_lane(segment)
    best, largest = 0, -1
    for lane in 1:segment.lanes
        first = first_cell(segment, lane)
        if is_empty(segment, lane, 0) && first > largest
            best, largest = lane, first
        end
    end
    best
end
function insert_vehicles!(sim, step)
    interval = sim.intervals[end]
    for source in sim.sources
        segment = sim.segments[source.segment]
        while source.head <= length(source.queue)
            lane = entry_lane(segment)
            lane == 0 && break
            vehicle = sim.vehicles[source.queue[source.head]]
            source.head += 1
            place!(vehicle, sim.segments, source.segment, lane, 0)
            vehicle.inserted = step
            enter!(sim, vehicle, source.segment)
            interval.insertions += 1
        end
        size = length(source.queue)-source.head+1
        if size > 0 && source.queue_start == 0
            source.queue_start, source.queue_max = step, 0
        end
        if source.queue_start != 0
            source.queue_max = max(source.queue_max, size)
            if size == 0
                record!(sim, step, "QUEUE $(source.node) from $(source.queue_start) max $(source.queue_max)")
                source.queue_start = 0
            end
        end
    end
end
function desired_lane(sim, vehicle)
    s = sim.segments[vehicle.segment]
    lane, cell = vehicle.lane, vehicle.cell
    top = max_speed(vehicle, sim.classes, sim.segments)
    here, want = free_cells(s, lane, cell, top+1), min(vehicle.speed+1, top)
    ahead = cell+here+1
    if here < top+1 && ahead < s.length && is_obstacle(s, lane, ahead)
        for target in (lane+1, lane-1)
            1 <= target <= s.lanes || continue
            if free_cells(s, target, cell, top+1) > here && safe(s, target, cell)
                return target, 3
            end
        end
    end
    if heading_for_stop(vehicle, sim.classes, sim.segments)
        return lane >= 2 && safe(s, lane-1, cell) ? (lane-1, 2) : (lane, 0)
    end
    if sim.classes[vehicle.kind].overtakes && lane+1 <= s.lanes && here < want && free_cells(s, lane+1, cell, top+1) > here && safe(s, lane+1, cell)
        return lane+1, 1
    end
    if lane >= 2 && free_cells(s, lane-1, cell, top+1) > want && safe(s, lane-1, cell)
        return lane-1, 2
    end
    lane, 0
end
function change_lanes!(sim)
    changes = Tuple{Int,Int,Int}[]
    for s in sim.segments
        s.lanes >= 2 || continue
        reserved = falses(s.length, s.lanes)
        for lane in 1:s.lanes, cell in 0:s.length-1
            number = s.cells[cell+1, lane]
            number > 0 || continue
            vehicle = sim.vehicles[number]
            vehicle.dwell == 0 || continue
            target, kind = desired_lane(sim, vehicle)
            if target != lane && !reserved[cell+1, target]
                reserved[cell+1, target] = true
                push!(changes, (number, target, kind))
            end
        end
    end
    for (number, target, kind) in changes
        vehicle = sim.vehicles[number]
        s = sim.segments[vehicle.segment]
        place!(vehicle, sim.segments, vehicle.segment, target, vehicle.cell)
        vehicle.lane_changes += 1
        s.changes[kind] += 1
    end
end
function processing_order(sim)
    [Move(sim.vehicles[number], index, cell, 0) for (index, s) in enumerate(sim.segments) for lane in 1:s.lanes for cell in s.length-1:-1:0 for number in (s.cells[cell+1, lane],) if number > 0]
end
function determine_speed!(sim, vehicle, step)
    s = sim.segments[vehicle.segment]
    lane, cell = vehicle.lane, vehicle.cell
    accelerated = min(vehicle.speed+1, max_speed(vehicle, sim.classes, sim.segments))
    gap = free_cells(s, lane, cell, accelerated)
    if gap < accelerated && cell+gap == s.length-1
        if s.junction == 0
            gap = accelerated
        elseif green_at(sim, s, step)
            target = sim.segments[s.turns[vehicle.turn].target]
            gap += free_cells(target, min(lane, target.lanes), -1, accelerated-gap)
        end
    end
    heading_for_stop(vehicle, sim.classes, sim.segments) && (gap = min(gap, s.stop.cell-cell))
    speed = random_slowdown(min(accelerated, gap), vehicle.speed, draw!(sim.rng), sim.dawdle, sim.dawdle_stopped)
    if vehicle.dwell > 0
        speed = 0
        vehicle.dwell -= 1
    end
    speed
end
function move_vehicles!(sim, moves, step)
    passing = Move[]
    for move in moves
        vehicle, s = move.vehicle, sim.segments[move.segment]
        if move.cell+move.speed < s.length
            place!(vehicle, sim.segments, move.segment, vehicle.lane, move.cell+move.speed)
        elseif s.junction == 0
            leave!(vehicle, sim.segments)
            vehicle.exited, vehicle.sink = step, s.finish
            sim.intervals[end].exits += 1
        else
            push!(passing, move)
        end
    end
    passing
end
function pass_junctions!(sim, passing)
    for move in passing
        vehicle, s = move.vehicle, sim.segments[move.segment]
        turn = s.turns[vehicle.turn]
        target = sim.segments[turn.target]
        lane = min(vehicle.lane, target.lanes)
        overshoot = move.cell+move.speed-s.length
        cell = min(overshoot, first_cell(target, lane)-1)
        s.blocked += cell < overshoot
        if cell >= 0
            place!(vehicle, sim.segments, turn.target, lane, cell)
            move.speed = s.length-move.cell+cell
            s.passed += 1
            turn.vehicles += 1
            enter!(sim, vehicle, turn.target)
        else
            place!(vehicle, sim.segments, move.segment, vehicle.lane, s.length-1)
            move.speed = s.length-1-move.cell
        end
    end
end
function track_line(sim, vehicle, step)
    vehicle.segment == 0 && return "$(time_text(step)) EXIT $(vehicle.speed)"
    "$(time_text(step)) $(sim.segments[vehicle.segment].id) $(vehicle.lane) $(vehicle.cell) $(vehicle.speed)"
end
function aggregate_vehicle!(sim, move, step)
    v, speed = move.vehicle, move.speed
    v.steps += 1
    v.distance += speed
    if speed == 0
        v.stopped_steps += 1
        v.stop_count += v.speed > 0
    end
    v.speed = speed
    interval = sim.intervals[end]
    interval.vehicle_steps += 1
    interval.speed_sum += speed
    if heading_for_stop(v, sim.classes, sim.segments) && v.lane == 1
        stop = sim.segments[v.segment].stop
        if v.cell == stop.cell
            push!(v.completed_stops, v.segment)
            v.dwell = stop.dwell
            stop.buses += 1
            record!(sim, step, "BUS_STOP $(v.number) $(sim.segments[v.segment].id) cell $(stop.cell)")
        end
    end
    haskey(sim.tracks, v.number) && push!(sim.tracks[v.number], track_line(sim, v, step))
    for (i, detector) in enumerate(sim.detectors)
        if move.segment == detector.segment && move.cell < detector.cell && (v.segment != detector.segment || v.cell >= detector.cell)
            interval.passing[i] += 1
        end
    end
end
function aggregate_state!(sim, step)
    interval = sim.intervals[end]
    for (i, detector) in enumerate(sim.detectors)
        for v in vehicles_on(sim, sim.segments[detector.segment])
            if detector.cell <= v.cell < detector.cell+detector.width
                interval.occupancy[i] += 1
                interval.occupancy_speed[i] += v.speed
            end
        end
    end
    for s in sim.segments
        present = vehicles_on(sim, s)
        s.vehicle_sum += length(present)
        s.speed_sum += sum((v.speed for v in present); init=0)
        s.max_vehicles = max(s.max_vehicles, length(present))
        if s.junction != 0
            is_green = green_at(sim, s, step)
            s.green_steps += is_green
            queued = count(v -> v.speed == 0, present)
            s.queue_sum += queued
            s.max_queue = max(s.max_queue, queued)
            s.failures += step < sim.steps && queued > 0 && is_green && !green_at(sim, s, step+1)
        end
    end
    for diagram in sim.diagrams
        if diagram.start <= step <= diagram.finish
            s = sim.segments[diagram.segment]
            light = s.junction == 0 ? "E" : green_at(sim, s, step) ? "G" : "R"
            push!(diagram.lines, "$(time_text(step)) $(cells_text(s, diagram.lane, sim.vehicles)) $light")
        end
    end
end
function run!(sim)
    for step in 1:sim.steps
        for incident in sim.incidents
            event = update_incident!(incident, sim.segments, step)
            if event !== nothing
                record!(sim, step, "$event $(sim.segments[incident.segment].id) lane $(incident.lane) cell $(incident.cell)")
            end
        end
        mod(step-1, sim.interval_length) == 0 && push!(sim.intervals, Interval(length(sim.detectors)))
        arrive!(sim, step)
        insert_vehicles!(sim, step)
        change_lanes!(sim)
        moves = processing_order(sim)
        for move in moves
            move.speed = determine_speed!(sim, move.vehicle, step)
        end
        passing = move_vehicles!(sim, moves, step)
        pass_junctions!(sim, passing)
        for move in moves
            aggregate_vehicle!(sim, move, step)
        end
        aggregate_state!(sim, step)
    end
    for source in sim.sources
        source.queue_start != 0 && record!(sim, sim.steps, "QUEUE $(source.node) from $(source.queue_start) max $(source.queue_max) open")
    end
end
struct Route
    segments::Vector{Int}
    share::Rational{Int}
    sink::String
end
function enumerate_routes(sim, index)
    s = sim.segments[index]
    s.junction == 0 && return [Route([index], 1//1, s.finish)]
    total = sum(turn.weight for turn in s.turns)
    result = Route[]
    for turn in s.turns
        for route in enumerate_routes(sim, turn.target)
            push!(result, Route(vcat(index, route.segments), route.share * (turn.weight//total), route.sink))
        end
    end
    result
end
function travel_block(heading, vehicles, width)
    times = sort!([travel_time(v) for v in vehicles])
    isempty(times) && return ["$heading exited 0"]
    lines = ["$heading exited $(length(times)) min $(times[1]) p50 $(percentile(times, 50)) p90 $(percentile(times, 90)) max $(times[end]) mean $(dec(sum(times), length(times), 2))"]
    append!(lines, histogram_lines(times, width))
end
function outcome_text(vehicles, exited_count)
    total = sum((travel_time(v) for v in vehicles); init=0)
    "vehicles $(length(vehicles)) share $(frac(length(vehicles), exited_count)) mean $(dec(total, length(vehicles), 2))"
end
function travel_time_lines(sim)
    exited = filter(v -> v.exited != 0, sim.vehicles)
    lines = String[]
    for (i, kind) in enumerate(sim.classes)
        append!(lines, travel_block("CLASS $(kind.name)", filter(v -> v.kind == i, exited), sim.bin_width))
    end
    append!(lines, travel_block("ALL", exited, sim.bin_width))
    for (i, source) in enumerate(sim.sources)
        group = filter(v -> v.source == i, exited)
        push!(lines, "SOURCE $(source.node) exited $(length(group))")
        routes = enumerate_routes(sim, source.segment)
        for route in routes
            matched = filter(v -> v.route == route.segments, group)
            ids = join([sim.segments[j].id for j in route.segments], ",")
            push!(lines, "  ROUTE $ids expected $(share_text(route.share)) $(outcome_text(matched, length(group)))")
        end
        for sink in sim.sinks
            shares = [route.share for route in routes if route.sink == sink]
            isempty(shares) && continue
            matched = filter(v -> v.sink == sink, group)
            push!(lines, "  SINK $sink expected $(share_text(sum(shares))) $(outcome_text(matched, length(group)))")
        end
    end
    lines
end
function class_block(heading, vehicles)
    inserted = count(v -> v.inserted != 0, vehicles)
    exited = filter(v -> v.exited != 0, vehicles)
    n = length(exited)
    steps = sum((v.steps for v in vehicles); init=0)
    distance = sum((v.distance for v in vehicles); init=0)
    travel = sum((travel_time(v) for v in exited); init=0)
    delay = sum((v.inserted-v.arrival for v in exited); init=0)
    stopped = sum((v.stopped_steps for v in exited); init=0)
    stops = sum((v.stop_count for v in exited); init=0)
    changes = sum((v.lane_changes for v in exited); init=0)
    [heading,
     "  generated $(length(vehicles)) inserted $inserted exited $n in_network $(inserted-n) queued $(length(vehicles)-inserted)",
     "  vehicle_steps $steps distance $distance mean_speed $(frac(distance, steps)) = $(dec(distance, steps, 3))",
     "  travel $(dec(travel, n, 2)) entry_delay $(dec(delay, n, 2)) stopped $(dec(stopped, n, 2)) stops $(dec(stops, n, 2)) lane_changes $(dec(changes, n, 2))"]
end
function class_stats_lines(sim)
    lines = String[]
    for (i, kind) in enumerate(sim.classes)
        heading = "CLASS $(kind.name) vmax $(kind.vmax) weight $(kind.weight) overtake $(flag_text(kind.overtakes)) stops $(flag_text(kind.stops))"
        append!(lines, class_block(heading, filter(v -> v.kind == i, sim.vehicles)))
    end
    append!(lines, class_block("ALL", sim.vehicles))
end
function network_stats_lines(sim)
    lines = String[]
    for s in sim.segments
        capacity = sim.steps*s.length*s.lanes
        push!(lines, "SEGMENT $(s.id) $(s.start) $(s.finish) length $(s.length) lanes $(s.lanes) limit $(s.limit) entered $(s.entered) mean_vehicles $(dec(s.vehicle_sum, sim.steps, 3)) density $(dec(s.vehicle_sum, capacity, 4)) mean_speed $(dec(s.speed_sum, s.vehicle_sum, 2)) max_vehicles $(s.max_vehicles) changes $(join(s.changes, "/"))")
    end
    for j in sim.junctions
        append!(lines, plan_lines(j))
        for index in j.incoming
            s = sim.segments[index]
            push!(lines, "  IN $(s.id) green $(s.green_steps) passed $(s.passed) blocked $(s.blocked) max_queue $(s.max_queue) mean_queue $(dec(s.queue_sum, sim.steps, 3)) failures $(s.failures)")
            for turn in s.turns
                push!(lines, "    TURN $(sim.segments[turn.target].id) weight $(turn.weight) vehicles $(turn.vehicles)")
            end
        end
    end
    for stop in sim.stops
        push!(lines, "STOP $(sim.segments[stop.segment].id) cell $(stop.cell) dwell $(stop.dwell) buses $(stop.buses)")
    end
    for incident in sim.incidents
        active = incident.active_start == 0 ? "none" : "$(incident.active_start)-$(incident.active_end)"
        push!(lines, "INCIDENT $(sim.segments[incident.segment].id) lane $(incident.lane) cell $(incident.cell) planned $(incident.start)-$(incident.finish) active $active")
    end
    lines
end
function timeline_lines(sim)
    lines = ["interval,arrived,inserted,exited,in_network,queued,mean_speed"]
    arrived = inserted = exited = 0
    for (i, interval) in enumerate(sim.intervals)
        arrived += interval.arrivals
        inserted += interval.insertions
        exited += interval.exits
        push!(lines, "$i,$(interval.arrivals),$(interval.insertions),$(interval.exits),$(inserted-exited),$(arrived-inserted),$(dec(interval.speed_sum, interval.vehicle_steps, 2))")
    end
    lines
end
function track_lines(sim)
    lines = String[]
    for number in sim.track_numbers
        if number > length(sim.vehicles)
            push!(lines, "VEHICLE $number none")
            continue
        end
        v = sim.vehicles[number]
        push!(lines, "VEHICLE $number class $(sim.classes[v.kind].name) source $(sim.sources[v.source].node) arrival $(v.arrival) inserted $(optional_text(v.inserted)) exited $(optional_text(v.exited)) sink $(v.sink)")
        ids = isempty(v.route) ? "-" : join([sim.segments[i].id for i in v.route], " ")
        push!(lines, "ROUTE $ids")
        append!(lines, sim.tracks[number])
    end
    lines
end
function run_ring(ring, count, dawdle, stopped)
    rng = Minstd(ring.seed)
    positions = [fld(i*ring.length, count) for i in 0:count-1]
    speeds = zeros(Int, count)
    total = 0
    for step in 1:ring.warmup+ring.measure
        order = sortperm(positions; rev=true)
        updated = zeros(Int, count)
        for (rank, index) in enumerate(order)
            ahead = order[rank == 1 ? count : rank-1]
            gap = mod(positions[ahead]-positions[index]-1, ring.length)
            speed = min(speeds[index]+1, ring.vmax, gap)
            updated[index] = random_slowdown(speed, speeds[index], draw!(rng), dawdle, stopped)
        end
        for i in 1:count
            positions[i] = mod(positions[i]+updated[i], ring.length)
        end
        speeds = updated
        step > ring.warmup && (total += sum(speeds))
    end
    total
end
function fundamental_lines(sim)
    lines = ["ring,vehicles,density,flow,speed"]
    for ring in sim.rings, count in ring.counts
        total = run_ring(ring, count, sim.dawdle, sim.dawdle_stopped)
        push!(lines, "$(ring.number),$count,$(dec(count, ring.length, 4)),$(dec(total, ring.length*ring.measure, 4)),$(dec(total, count*ring.measure, 3))")
    end
    lines
end
function main()
    sim = Simulation()
    load!(sim)
    run!(sim)
    spacetime = String[]
    for d in sim.diagrams
        push!(spacetime, "DIAGRAM $(sim.segments[d.segment].id) lane $(d.lane) steps $(d.start)-$(d.finish)")
        append!(spacetime, d.lines)
    end
    detectors = ["detector,interval,flow,density,speed"]
    for (i, detector) in enumerate(sim.detectors)
        capacity = sim.interval_length*detector.width*sim.segments[detector.segment].lanes
        for (k, interval) in enumerate(sim.intervals)
            occupancy = interval.occupancy[i]
            push!(detectors, "$(detector.name),$k,$(interval.passing[i]),$(dec(occupancy, capacity, 4)),$(dec(interval.occupancy_speed[i], occupancy, 2))")
        end
    end
    names = ["spacetime.txt", "detectors.csv", "travel_times.txt", "class_stats.txt", "network_stats.txt", "timeline.csv", "tracks.txt", "fundamental.csv", "events.txt"]
    reports = [spacetime, detectors, travel_time_lines(sim), class_stats_lines(sim), network_stats_lines(sim), timeline_lines(sim), track_lines(sim), fundamental_lines(sim), sim.events]
    mkpath("output")
    for (name, lines) in zip(names, reports)
        open(joinpath("output", name), "w") do io
            for line in lines
                println(io, line)
            end
        end
    end
end
main()
