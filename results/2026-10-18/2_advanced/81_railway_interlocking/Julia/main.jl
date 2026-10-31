include("layout.jl")
include("interlocking.jl")
include("signals.jl")
include("trains.jl")
include("safety.jl")

mutable struct RouteRequest
    number::Int
    route::String
    time::Int
    reason::String
end

mutable struct RailSimulation
    layout::TrackLayout
    routes::Dict{String,RailRoute}
    route_order::Vector{String}
    trains::Dict{String,RailTrain}
    train_order::Vector{String}
    planned::Dict{Int,Vector{Tuple{String,String}}}
    events::Dict{Int,Vector{Tuple{String,Vector{String}}}}
    end_time::Int
    throw_time::Int
    overlap_time::Int
    snapshot_times::Set{Int}
    time::Int
    request_count::Int
    dropped::Int
    queue::Vector{RouteRequest}
    log_lines::Vector{String}
    snapshots::Vector{String}
    safety::RailSafety
end

function read_simulation()
    layout = read_layout()
    routes, route_order = read_routes(layout)
    trains, train_order, requests = read_trains()
    planned = Dict{Int,Vector{Tuple{String,String}}}()
    for (time, train, route) in requests
        push!(get!(planned, time, Tuple{String,String}[]), (train, route))
    end
    events = Dict{Int,Vector{Tuple{String,Vector{String}}}}()
    for line in readlines("input/events.txt")
        fields = String.(split(line, ' '))
        push!(get!(events, parse(Int, fields[1]), Tuple{String,Vector{String}}[]), (fields[2], fields[3:end]))
    end
    settings = Dict{String,Vector{Int}}()
    for line in readlines("input/params.txt")
        fields = split(line, ' ')
        settings[String(fields[1])] = parse.(Int, fields[2:end])
    end
    return RailSimulation(
        layout,
        routes,
        route_order,
        trains,
        train_order,
        planned,
        events,
        settings["END"][1],
        settings["THROW"][1],
        settings["OVERLAP"][1],
        Set(settings["SNAPSHOTS"]),
        0,
        0,
        0,
        RouteRequest[],
        String[],
        String[],
        RailSafety()
    )
end

log_event!(simulation, content) = push!(simulation.log_lines, "$(simulation.time) $content")
track_occupied(
    simulation,
    name
) = simulation.layout.sections[name].failed || !isempty(simulation.layout.sections[name].occupants)

function start_throw!(simulation, point, target)
    point.moving, point.target = true, target
    point.completion = simulation.time + simulation.throw_time
    log_event!(simulation, "MOVE $(point.name) $target until $(point.completion)")
end

function complete_throws!(simulation)
    for name in simulation.layout.point_order
        point = simulation.layout.points[name]
        if point.moving && point.completion == simulation.time
            point.position = point.target
            point.moving, point.completion = false, -1
            point.throws += 1
            log_event!(simulation, "POINT $name $(point.position)")
        end
    end
end

function release_approaches!(simulation)
    for name in simulation.route_order
        route = simulation.routes[name]
        if route.state == "APPROACH" && route.release_time == simulation.time
            release_route!(simulation.layout, route)
            log_event!(simulation, "TIMEOUT $name")
        end
    end
end

function add_request!(simulation, name, requester)
    simulation.request_count += 1
    request = RouteRequest(simulation.request_count, name, simulation.time, "")
    push!(simulation.queue, request)
    simulation.routes[name].requests += 1
    log_event!(simulation, "REQUEST q$(request.number) $name $requester")
end

function cancel_route!(simulation, name)
    removed = [request for request in simulation.queue if request.route == name]
    if !isempty(removed)
        for request in removed
            log_event!(simulation, "DROP q$(request.number) $name")
            simulation.dropped += 1
        end
        filter!(request -> request.route != name, simulation.queue)
        return
    end
    route = simulation.routes[name]
    if route.state == "LOCKED"
        route.cancels += 1
        signal = simulation.layout.signals[route.start]
        if signal.aspect != "RED" && track_occupied(simulation, signal.section)
            route.state = "APPROACH"
            route.release_time = simulation.time + route.approach_time
            log_event!(simulation, "CANCEL $name approach until $(route.release_time)")
        else
            release_route!(simulation.layout, route)
            log_event!(simulation, "CANCEL $name released")
        end
    else
        log_event!(simulation, "CANCEL $name " * (isempty(route.state) ? "none" : "refused"))
    end
end

function individual_throw!(simulation, name, target)
    point = simulation.layout.points[name]
    result = !isempty(point.locks) ? "locked" : point.failed ? "failed" : point.moving ? "moving" : track_occupied(
        simulation,
        point.common
    ) ? "occupied" : point.position == target ? "none" : "start"
    log_event!(simulation, "THROW $name $target $result")
    result == "start" && start_throw!(simulation, point, target)
end

function execute_events!(simulation)
    for (command, arguments) in get(simulation.events, simulation.time, Tuple{String,Vector{String}}[])
        name = arguments[1]
        if command == "REQUEST"
            add_request!(simulation, name, "OPERATOR")
        elseif command == "CANCEL"
            cancel_route!(simulation, name)
        elseif command == "THROW"
            individual_throw!(simulation, name, arguments[2])
        elseif command in ("TCFAIL", "TCFIX")
            simulation.layout.sections[name].failed = command == "TCFAIL"
            log_event!(simulation, "$command $name")
        else
            point = simulation.layout.points[name]
            point.failed = command == "POINTFAIL"
            point.failed && point.moving && (point.completion = -1)
            log_event!(simulation, "$command $name")
            !point.failed && point.moving && start_throw!(simulation, point, point.target)
        end
    end
end

opposite_lock(simulation, names, route) = any(
    name -> simulation.routes[name].direction != route.direction,
    names
)

function request_reason(simulation, route)
    !isempty(route.state) && return "busy"
    for name in route.conflicts
        simulation.routes[name].state in ("LOCKED", "APPROACH") && return "conflict $name"
    end
    for name in route.sections
        section = simulation.layout.sections[name]
        track_occupied(simulation, name) && return "occupied $name"
        (!isempty(section.route_lock) || opposite_lock(
            simulation,
            section.overlap_locks,
            route
        )) && return "locked $name"
    end
    for name in route.overlap
        section = simulation.layout.sections[name]
        track_occupied(simulation, name) && return "occupied $name"
        locks = copy(section.overlap_locks)
        !isempty(section.route_lock) && push!(locks, section.route_lock)
        opposite_lock(simulation, locks, route) && return "locked $name"
    end
    for (name, target) in route.requirements
        point = simulation.layout.points[name]
        any(lock -> lock[2] != target, point.locks) && return "point $name locked"
        ((!point.moving && point.position == target) || (point.moving && point.target == target)) && continue
        point.failed && return "point $name failed"
        point.moving && return "point $name moving"
        track_occupied(simulation, point.common) && return "point $name occupied"
    end
    return nothing
end

function judge_requests!(simulation)
    waiting = RouteRequest[]
    for request in simulation.queue
        route = simulation.routes[request.route]
        reason = request_reason(simulation, route)
        if reason !== nothing
            if reason != request.reason
                log_event!(simulation, "WAIT q$(request.number) $(route.name) $reason")
                request.reason = reason
            end
            push!(waiting, request)
            continue
        end
        lock_route!(simulation.layout, route)
        wait = simulation.time - request.time
        route.grants += 1
        route.wait += wait
        route.maxwait = max(route.maxwait, wait)
        log_event!(simulation, "GRANT q$(request.number) $(route.name) wait $wait")
        for (name, target) in route.requirements
            point = simulation.layout.points[name]
            !point.moving && point.position != target && start_throw!(simulation, point, target)
        end
    end
    simulation.queue = waiting
end

function decide_signals!(simulation)
    decisions = signal_aspects(
        simulation.layout,
        simulation.routes,
        simulation.route_order,
        name -> track_occupied(simulation, name)
    )
    for (signal, aspect) in decisions
        if signal.aspect != aspect
            signal.aspect = aspect
            log_event!(simulation, "SIGNAL $(signal.name) $aspect")
        end
    end
end

function occupied_parts(simulation, train)
    parts = Tuple{String,Int,Int,Int}[]
    if train.state == "RUNNING"
        tail = train.head - train.length
        for (name, start) in train.path
            stop = start + simulation.layout.sections[name].length
            if start < train.head && stop > tail
                push!(parts, (name, start, max(tail, start), min(train.head, stop)))
            end
        end
    end
    return parts
end

function head_section(train)
    for (name, start) in Iterators.reverse(train.path)
        start < train.head && return name, start
    end
    return train.path[1]
end

function enter_train!(simulation, train, entered_boundaries)
    train.state == "EXITED" && return false
    train.state == "RUNNING" && return true
    boundary = simulation.layout.boundaries[train.entry]
    (simulation.time < train.entry_time || track_occupied(
        simulation,
        boundary.section
    ) || train.entry in entered_boundaries) && return false
    train.state, train.direction = "RUNNING", boundary.endpoint == "L" ? "UP" : "DOWN"
    train.path = [(boundary.section, 0)]
    train.head, train.speed, train.entered = 0, train.entry_speed, simulation.time
    push!(entered_boundaries, train.entry)
    log_event!(simulation, "ENTER $(train.name) $(train.entry)")
    return true
end

function reverse_train!(simulation, train, stop)
    name, start = head_section(train)
    endpoint = start + simulation.layout.sections[name].length
    parts = occupied_parts(simulation, train)
    train.path = [(
        section,
        endpoint - (origin + simulation.layout.sections[section].length)
    ) for (section, origin, _, _) in Iterators.reverse(parts)]
    train.head = endpoint - (train.head - train.length)
    train.direction = train.direction == "UP" ? "DOWN" : "UP"
    log_event!(simulation, "REVERSE $(train.name) $(stop.section)")
end

function finish_dwell!(simulation, train)
    !train.dwelling && return true
    stop = next_stop(train)
    (simulation.time < stop.arrival + stop.dwell || simulation.time < stop.scheduled_departure) && return false
    train.dwelling, train.awaiting_departure = false, stop
    train.stop_index += 1
    stop.kind == "TURN" && reverse_train!(simulation, train, stop)
    return true
end

function limit_distance(simulation, train)
    !isempty(train.boundary) && return nothing
    name, start = head_section(train)
    distance = start + simulation.layout.sections[name].length - train.head
    stop = next_stop(train)
    while true
        signal = get(simulation.layout.signals_at, (name, train.direction), nothing)
        signal !== nothing && signal.aspect == "RED" && return distance
        stop !== nothing && stop.section == name && return distance
        kind, following = beyond(simulation.layout, name, train.direction)
        kind == "boundary" && return nothing
        kind in ("buffer", "impassable") && return distance
        distance += simulation.layout.sections[following].length
        name = following
    end
end

function pass_signal!(simulation, train, signal)
    route = nothing
    for name in simulation.route_order
        item = simulation.routes[name]
        if item.start == signal.name && item.state in ("LOCKED", "APPROACH")
            route = item
            break
        end
    end
    route_name = route === nothing ? "-" : route.name
    log_event!(simulation, "PASS $(train.name) $(signal.name) $(signal.aspect) $route_name")
    signal.passes += 1
    train.passes += 1
    if route !== nothing
        route.state = "USED"
        route.uses += 1
    end
    if signal.aspect == "RED"
        log_event!(simulation, "SPAD $(train.name) $(signal.name)")
        safety_check!(simulation.safety, simulation.time, "SIGNAL_PASSING", train.name * " " * signal.name)
        train.emergency = true
    else
        safety_check!(simulation.safety, simulation.time, "SIGNAL_PASSING")
    end
end

function move_train!(simulation, train, distance)
    name, start = head_section(train)
    remaining = distance
    while remaining > 0
        if !isempty(train.boundary)
            train.head += remaining
            break
        end
        endpoint = start + simulation.layout.sections[name].length
        if train.head + remaining <= endpoint
            train.head += remaining
            break
        end
        remaining -= endpoint - train.head
        train.head = endpoint
        signal = get(simulation.layout.signals_at, (name, train.direction), nothing)
        signal !== nothing && pass_signal!(simulation, train, signal)
        stop = train.awaiting_departure
        if stop !== nothing && stop.section == name
            log_event!(simulation, "DEPART $(train.name) $name")
            stop.departure = simulation.time
            train.awaiting_departure = nothing
        end
        kind, following = beyond(simulation.layout, name, train.direction)
        if kind == "boundary"
            train.boundary, train.boundary_coordinate = following, endpoint
        else
            name, start = following, endpoint
            push!(train.path, (name, start))
        end
    end
end

function after_movement!(simulation, train, speed, previous_speed)
    train.speed = speed
    train.distance += speed
    train.maximum_speed = max(train.maximum_speed, speed)
    speed == 0 && (train.emergency = false)
    name, start = head_section(train)
    stop = next_stop(train)
    arrived = stop !== nothing && speed == 0 && name == stop.section && train.head == start + simulation.layout.sections[name].length
    if arrived
        train.dwelling, stop.arrival = true, simulation.time
        log_event!(simulation, "ARRIVE $(train.name) $name")
    end
    if speed == 0 && !arrived
        train.standing += 1
        previous_speed > 0 && log_event!(simulation, "HOLD $(train.name) $name")
    end
    if !isempty(train.boundary) && train.head - train.length >= train.boundary_coordinate
        train.state, train.exited = "EXITED", simulation.time
        log_event!(simulation, "EXIT $(train.name) $(train.boundary)")
    end
end

function run_trains!(simulation)
    entered_boundaries = Set{String}()
    for name in simulation.train_order
        train = simulation.trains[name]
        enter_train!(simulation, train, entered_boundaries) || continue
        finish_dwell!(simulation, train) || continue
        distance = limit_distance(simulation, train)
        previous_speed = train.speed
        speed = select_speed(train, distance)
        move_train!(simulation, train, speed)
        after_movement!(simulation, train, speed, previous_speed)
    end
end

function recompute_occupancy!(simulation)
    for name in simulation.layout.section_order
        empty!(simulation.layout.sections[name].occupants)
    end
    for name in simulation.train_order
        train = simulation.trains[name]
        for (section, _, _, _) in occupied_parts(simulation, train)
            occupants = simulation.layout.sections[section].occupants
            !(name in occupants) && push!(occupants, name)
        end
    end
end

function sectional_release!(simulation)
    for name in simulation.route_order
        route = simulation.routes[name]
        route.state != "USED" && continue
        remaining = [section for section in route.sections if simulation.layout.sections[section].route_lock == name]
        for section in remaining
            track_occupied(simulation, section) && push!(route.passed, section)
        end
        for section in remaining
            (!(section in route.passed) || track_occupied(simulation, section)) && break
            unlock_section!(simulation.layout, route, section)
            log_event!(simulation, "RELEASE $name $section")
        end
        if !any(section -> simulation.layout.sections[section].route_lock == name, route.sections)
            release_route!(simulation.layout, route)
            log_event!(simulation, "DONE $name")
        elseif !isempty(route.overlap) && route.overlap_locked
            route.overlap_counter = track_occupied(
                simulation,
                route.sections[end]
            ) ? route.overlap_counter + 1 : 0
            if route.overlap_counter >= simulation.overlap_time
                unlock_overlap!(simulation.layout, route)
                log_event!(simulation, "OVERLAP $name")
            end
        end
    end
end

function record_statistics!(simulation)
    for name in simulation.route_order
        route = simulation.routes[name]
        route.locked_seconds += Int(!isempty(route.state))
    end
    for name in simulation.layout.point_order
        point = simulation.layout.points[name]
        point.locked_seconds += Int(!isempty(point.locks))
        point.moving_seconds += Int(point.moving)
    end
    for name in simulation.layout.section_order
        section = simulation.layout.sections[name]
        section.occupied_seconds += Int(track_occupied(simulation, name))
        section.locked_seconds += Int(!isempty(section.route_lock) || !isempty(section.overlap_locks))
        union!(section.trains, section.occupants)
    end
    for name in simulation.layout.signal_order
        signal = simulation.layout.signals[name]
        signal.seconds[signal.aspect] += 1
    end
end

function diagram(simulation)
    layout = simulation.layout
    rows = [layout.sections[name].row for name in layout.section_order]
    columns = [layout.sections[name].last for name in layout.section_order]
    symbols = Any[layout.points[name] for name in layout.point_order]
    append!(symbols, [layout.signals[name] for name in layout.signal_order])
    append!(symbols, [layout.buffers[name] for name in layout.buffer_order])
    append!(rows, [item.row for item in symbols])
    append!(columns, [item.column for item in symbols])
    append!(rows, [row for (row, _, _) in layout.labels])
    append!(columns, [column + length(text) - 1 for (_, column, text) in layout.labels])
    grid = fill(' ', maximum(rows) + 1, maximum(columns) + 1)
    for (row, column, text) in layout.labels, (offset, character) in enumerate(text)
        grid[row + 1, column + offset] = character
    end
    for name in layout.section_order
        section = layout.sections[name]
        character = section.failed ? '#' : !isempty(section.route_lock) ? '=' : !isempty(section.overlap_locks) ? '~' : '-'
        grid[section.row + 1, section.first + 1:section.last + 1] .= character
    end
    for name in simulation.train_order
        train = simulation.trains[name]
        for (section_name, start, low, high) in occupied_parts(simulation, train)
            section = layout.sections[section_name]
            span, cells = section.length, section.last - section.first + 1
            left, right = train.direction == "UP" ? (low - start, high - start) : (
                span - (high - start),
                span - (low - start)
            )
            for cell in 0:cells - 1
                if left * cells < (cell + 1) * span && right * cells > cell * span
                    column = section.first + cell + 1
                    previous = grid[section.row + 1, column]
                    grid[
                        section.row + 1,
                        column
                    ] = ('a' <= previous <= 'z' || previous == '*') ? '*' : train.symbol
                end
            end
        end
    end
    for name in layout.buffer_order
        buffer = layout.buffers[name]
        grid[buffer.row + 1, buffer.column + 1] = '|'
    end
    for name in layout.point_order
        point = layout.points[name]
        grid[point.row + 1, point.column + 1] = point_detected(point) ? point.position[1] : '?'
    end
    for name in layout.signal_order
        signal = layout.signals[name]
        grid[signal.row + 1, signal.column + 1] = Dict(
            "RED" => 'X',
            "YELLOW" => 'Y',
            "GREEN" => 'G'
        )[signal.aspect]
    end
    return [rstrip(character -> character == ' ', join(grid[row, :])) for row in axes(grid, 1)]
end

function snapshot(simulation)
    lines = ["SNAPSHOT $(simulation.time)"]
    append!(lines, diagram(simulation))
    for name in simulation.train_order
        train = simulation.trains[name]
        if train.state == "RUNNING"
            sections = join((section for (section, _, _, _) in occupied_parts(simulation, train)), ",")
            line = "TRAIN $(train.symbol) $name $(train.direction) $(train.speed)"
            isempty(sections) || (line *= " " * sections)
            push!(lines, line)
        end
    end
    routes = ["$name/$(simulation.routes[name].state)" for name in simulation.route_order if !isempty(simulation.routes[name].state)]
    push!(lines, "ROUTES " * (isempty(routes) ? "-" : join(routes, " ")))
    return lines
end

function train_rows(simulation)
    rows = Tuple{String,String,Int,Int}[]
    for name in simulation.train_order
        train = simulation.trains[name]
        push!(rows, (name, "enter:" * train.entry, train.entry_time, train.entered))
        for stop in train.stops
            push!(rows, (name, "arr:" * stop.section, stop.scheduled_arrival, stop.arrival))
            push!(rows, (name, "dep:" * stop.section, stop.scheduled_departure, stop.departure))
        end
        push!(rows, (name, "exit:" * train.exit, train.scheduled_exit, train.exited))
    end
    return rows
end

function train_report(rows)
    lines = ["train,location,scheduled,actual,delay"]
    for (name, location, scheduled, actual) in rows
        timing = actual < 0 ? "-,-" : "$actual,$(actual - scheduled)"
        push!(lines, "$name,$location,$scheduled,$timing")
    end
    return lines
end

function punctuality(rows)
    on_time, late, missing, total_delay, maximum_delay = 0, 0, 0, 0, 0
    for (_, _, scheduled, actual) in rows
        if actual < 0
            missing += 1
        elseif actual <= scheduled
            on_time += 1
        else
            late += 1
            total_delay += actual - scheduled
            maximum_delay = max(maximum_delay, actual - scheduled)
        end
    end
    return "PUNCTUALITY on_time $on_time late $late missing $missing total_delay $total_delay max_delay $maximum_delay"
end

function summary_lines(simulation, rows)
    lines = String[]
    for name in simulation.route_order
        route = simulation.routes[name]
        push!(
            lines,
            "ROUTE $name $(route.start)-$(route.finish) requests $(route.requests) grants $(route.grants) uses $(route.uses) cancels $(route.cancels) wait $(route.wait) maxwait $(route.maxwait) locked $(route.locked_seconds)"
        )
    end
    for name in simulation.layout.point_order
        point = simulation.layout.points[name]
        final = point_detected(point) ? point.position : "?"
        push!(
            lines,
            "POINT $name throws $(point.throws) locked $(point.locked_seconds) moving $(point.moving_seconds) final $final"
        )
    end
    for name in simulation.layout.section_order
        section = simulation.layout.sections[name]
        push!(
            lines,
            "SECTION $name occupied $(section.occupied_seconds) locked $(section.locked_seconds) trains $(length(section.trains))"
        )
    end
    for name in simulation.layout.signal_order
        signal = simulation.layout.signals[name]
        push!(
            lines,
            "SIGNAL $name red $(signal.seconds["RED"]) yellow $(signal.seconds["YELLOW"]) green $(signal.seconds["GREEN"]) passes $(signal.passes)"
        )
    end
    for name in simulation.train_order
        train = simulation.trains[name]
        push!(
            lines,
            "TRAIN $name $(train.symbol) $(train.state) distance $(train.distance) maxspeed $(train.maximum_speed) standing $(train.standing) passes $(train.passes)"
        )
    end
    state_count(state) = count(name -> simulation.trains[name].state == state, simulation.train_order)
    push!(
        lines,
        "TRAINS total $(length(simulation.train_order)) exited $(state_count("EXITED")) running $(state_count("RUNNING")) waiting $(state_count("WAITING"))"
    )
    push!(lines, punctuality(rows))
    grants = sum(simulation.routes[name].grants for name in simulation.route_order)
    push!(
        lines,
        "REQUESTS total $(simulation.request_count) granted $grants dropped $(simulation.dropped) pending $(length(simulation.queue))"
    )
    return lines
end

function main()
    simulation = read_simulation()
    for time in 0:simulation.end_time
        simulation.time = time
        complete_throws!(simulation)
        release_approaches!(simulation)
        for (train, route) in get(simulation.planned, time, Tuple{String,String}[])
            add_request!(simulation, route, train)
        end
        execute_events!(simulation)
        judge_requests!(simulation)
        decide_signals!(simulation)
        run_trains!(simulation)
        recompute_occupancy!(simulation)
        sectional_release!(simulation)
        inspect_safety!(simulation.safety, time, simulation.layout, simulation.routes, simulation.route_order)
        record_statistics!(simulation)
        time in simulation.snapshot_times && append!(simulation.snapshots, snapshot(simulation))
    end
    rows = train_rows(simulation)
    reports = (
        ("events.txt", simulation.log_lines),
        ("snapshots.txt", simulation.snapshots),
        ("train_log.csv", train_report(rows)),
        ("safety.txt", safety_report(simulation.safety)),
        ("summary.txt", summary_lines(simulation, rows))
    )
    mkpath("output")
    for (name, lines) in reports
        write(joinpath("output", name), join((line * "\n" for line in lines)))
    end
end

main()
