include("topology.jl")
include("policy.jl")
include("decision.jl")
include("simulator.jl")
include("report.jl")

const CONVERGENCE_HEADER = "event,time,kind,status,convergence_time,updates,withdrawals,drops,best_changes,routes_changed,max_exploration"

mutable struct BGPSession
    owner::Int
    link::Int
    incoming::Dict{IPPrefix,Any}
    outgoing::Dict{IPPrefix,Any}
    pending::Set{IPPrefix}
    timer::Int
    sent::Int
    received::Int
end

mutable struct BGPRouter
    origination::Dict{IPPrefix,Any}
    rib::Dict{IPPrefix,Any}
    sessions::Vector{BGPSession}
    changes::Int
end

mutable struct BGPPeriod
    number::Int
    event::NamedTuple
    before::Dict{Int,Dict{IPPrefix,Any}}
    counters::Dict{String,Int}
    exploration::Dict{Tuple{Int,IPPrefix},Int}
    best_lines::Vector{Any}
    convergence_time::Int
    delivery_times::Int
    states::Dict{Any,Int}
    divergence::Any
    status::String
    routes_changed::Int
end

mutable struct TraceRecord
    index::Int
    result::String
    visits::Tuple
    start::Int
    end_time::Int
end

mutable struct RingRecord
    prefix::IPPrefix
    path::Tuple
    start::Int
    end_time::Int
end

mutable struct BGPSimulation
    network::NamedTuple
    policies::NamedTuple
    defaults::Dict{String,Int}
    stepcap::Int
    traces::Vector{Tuple{Int,String,Int}}
    routers::Dict{Int,BGPRouter}
    sessions::Vector{BGPSession}
    by_session::Dict{Tuple{Int,Int},BGPSession}
    messages::BGPMessageQueue
    time::Int
    logs::Vector{String}
    periods::Vector{BGPPeriod}
    period::Any
    changed_prefixes::Set{IPPrefix}
    trace_records::Vector{TraceRecord}
    ongoing_traces::Dict{Int,TraceRecord}
    ring_records::Vector{RingRecord}
    ongoing_rings::Dict{Any,RingRecord}
end

function new_simulation(network, policies, defaults, stepcap, traces)
    routers = Dict{Int,BGPRouter}()
    sessions = BGPSession[]
    for owner in network.ases
        local_sessions = [BGPSession(
            owner,
            link,
            Dict{IPPrefix,Any}(),
            Dict{IPPrefix,Any}(),
            Set{IPPrefix}(),
            -1,
            0,
            0
        ) for link in network.at_as[owner]]
        routers[owner] = BGPRouter(Dict{IPPrefix,Any}(), Dict{IPPrefix,Any}(), local_sessions, 0)
        append!(sessions, local_sessions)
    end
    by_session = Dict((session.owner, session.link) => session for session in sessions)
    return BGPSimulation(
        network,
        policies,
        defaults,
        stepcap,
        traces,
        routers,
        sessions,
        by_session,
        BGPMessageQueue(),
        0,
        String[],
        BGPPeriod[],
        nothing,
        Set{IPPrefix}(),
        TraceRecord[],
        Dict{Int,TraceRecord}(),
        RingRecord[],
        Dict{Any,RingRecord}()
    )
end

function add_counter!(counts, key, amount=1)
    counts[key] = get(counts, key, 0) + amount
end

log_update!(simulation, content) = push!(simulation.logs, "$(simulation.time) $content")
message_text(
    message,
    network
) = "#$(message.serial) $(message.sender)->$(message.receiver) $(network.links[message.link].name) $(prefix_text(message.prefix))"

function collapse_runs(path)
    result = Int[]
    for owner in path
        (isempty(result) || result[end] != owner) && push!(result, owner)
    end
    return Tuple(result)
end

function valley_position(pattern)
    position = 1
    while position <= length(pattern) && pattern[position] == 'U'
        position += 1
    end
    position <= length(pattern) && pattern[position] == 'P' && (position += 1)
    while position <= length(pattern) && pattern[position] == 'D'
        position += 1
    end
    return position - 1
end

function import_route(simulation, session, prefix, attribute)
    link = simulation.network.links[session.link]
    rule = applied_rule(
        simulation.policies,
        "IMPORT",
        session.owner,
        link,
        prefix,
        attribute.path,
        attribute.communities
    )
    local_pref = simulation.defaults[link_role(link, session.owner)]
    rule !== nothing && haskey(rule.settings, "DENY") && return nothing, rule
    med, communities = attribute.med, attribute.communities
    if rule !== nothing
        local_pref = get(rule.settings, "LOCALPREF", local_pref)
        med = get(rule.settings, "MED", med)
        communities = edit_communities(communities, rule)
    end
    return learned_route(attribute, med, communities, local_pref, session.link), rule
end

function candidate_routes(simulation, owner, prefix)
    routes = Any[]
    for session in simulation.routers[owner].sessions
        if haskey(session.incoming, prefix)
            route, _ = import_route(simulation, session, prefix, session.incoming[prefix])
            route !== nothing && push!(routes, route)
        end
    end
    return routes
end

function advertised_content(simulation, session, prefix)
    owner, link = session.owner, simulation.network.links[session.link]
    route = get(simulation.routers[owner].rib, prefix, nothing)
    route === nothing && return nothing, nothing
    !route_local(route) && route_neighbor(route) == other_end(link, owner) && return nothing, nothing
    NO_EXPORT_COMMUNITY in route.communities && return nothing, nothing
    rule = applied_rule(simulation.policies, "EXPORT", owner, link, prefix, route.path, route.communities)
    rule !== nothing && haskey(rule.settings, "DENY") && return nothing, rule
    allowed = rule !== nothing && haskey(rule.settings, "ALLOW")
    if !allowed && !route_local(route)
        learning_link = simulation.network.links[route.link]
        link_role(
            learning_link,
            owner
        ) in ("peer", "provider") && link_role(link, owner) in ("peer", "provider") && return nothing, rule
    end
    prepend = rule === nothing ? 0 : get(rule.settings, "PREPEND", 0)
    med = rule === nothing ? 0 : get(rule.settings, "MED", 0)
    communities = rule === nothing ? route.communities : edit_communities(route.communities, rule)
    path = (fill(owner, 1 + prepend)..., route.path...)
    return bgp_attribute(path, route.origin, med, communities), rule
end

function process_pending!(simulation, session)
    sent = 0
    link = simulation.network.links[session.link]
    for prefix in sort!(collect(session.pending))
        content, rule = advertised_content(simulation, session, prefix)
        get(session.outgoing, prefix, nothing) == content && continue
        if content === nothing
            delete!(session.outgoing, prefix)
        else
            session.outgoing[prefix] = content
        end
        message = send_message!(
            simulation.messages,
            simulation.time,
            session.owner,
            other_end(link, session.owner),
            link,
            prefix,
            content
        )
        suffix = content === nothing ? "WITHDRAW" : "ANNOUNCE " * attribute_text(content)
        log_update!(simulation, "SEND $(message_text(message, simulation.network)) $suffix")
        session.sent += 1
        sent += 1
        add_counter!(simulation.period.counters, "updates")
        content === nothing && add_counter!(simulation.period.counters, "withdrawals")
        rule !== nothing && (rule.hits += 1)
    end
    empty!(session.pending)
    session.timer = sent > 0 && link.mrai >= 1 ? simulation.time + link.mrai : -1
end

function redecide!(simulation, owner, prefix)
    router = simulation.routers[owner]
    if haskey(router.origination, prefix)
        route = router.origination[prefix]
    else
        candidates = candidate_routes(simulation, owner, prefix)
        route = isempty(candidates) ? nothing : best_route(candidates, simulation.network)[1]
    end
    get(router.rib, prefix, nothing) == route && return
    if route === nothing
        delete!(router.rib, prefix)
    else
        router.rib[prefix] = route
    end
    log_update!(simulation, "BEST $owner $(prefix_text(prefix)) $(route_text(route, simulation.network))")
    router.changes += 1
    add_counter!(simulation.period.counters, "best_changes")
    add_counter!(simulation.period.exploration, (owner, prefix))
    push!(simulation.period.best_lines, (simulation.time, owner, prefix, route))
    push!(simulation.changed_prefixes, prefix)
    for session in router.sessions
        if simulation.network.links[session.link].up
            push!(session.pending, prefix)
            session.timer == -1 && process_pending!(simulation, session)
        end
    end
end

function receive_message!(simulation, message)
    session = simulation.by_session[(message.receiver, message.link)]
    prefix, content = message.prefix, message.content
    session.received += 1
    simulation.period.convergence_time = simulation.time - simulation.period.event.time
    if content === nothing
        delete!(session.incoming, prefix)
        result = "WITHDRAW"
    elseif message.receiver in content.path
        delete!(session.incoming, prefix)
        result = "ANNOUNCE loop"
    else
        session.incoming[prefix] = content
        route, rule = import_route(simulation, session, prefix, content)
        rule !== nothing && (rule.hits += 1)
        result = route === nothing ? "ANNOUNCE deny $(rule.name)" : rule === nothing ? "ANNOUNCE accept" : "ANNOUNCE accept $(rule.name)"
    end
    log_update!(simulation, "RECV $(message_text(message, simulation.network)) $result")
    redecide!(simulation, message.receiver, prefix)
end

function originate!(simulation, owner, prefix, origin, communities)
    simulation.routers[owner].origination[prefix] = originated_route(origin, parse_communities(communities))
    redecide!(simulation, owner, prefix)
end

function link_down!(simulation, link)
    link.up = false
    link.down_count += 1
    for message in remove_link_messages!(simulation.messages, link.number)
        log_update!(simulation, "DROP " * message_text(message, simulation.network))
        add_counter!(simulation.period.counters, "drops")
    end
    remembered = Dict{Int,Vector{IPPrefix}}()
    endpoints = sort!([link.first, link.second])
    for owner in endpoints
        session = simulation.by_session[(owner, link.number)]
        remembered[owner] = sort!(collect(keys(session.incoming)))
        empty!(session.incoming)
        empty!(session.outgoing)
        empty!(session.pending)
        session.timer = -1
    end
    for owner in endpoints, prefix in remembered[owner]
        redecide!(simulation, owner, prefix)
    end
end

function link_up!(simulation, link)
    link.up = true
    for owner in sort!([link.first, link.second])
        session = simulation.by_session[(owner, link.number)]
        session.pending = Set(keys(simulation.routers[owner].rib))
        process_pending!(simulation, session)
    end
end

function change_policy!(simulation, rule, active)
    rule.active = active
    router = simulation.routers[rule.owner]
    if rule.direction == "IMPORT"
        prefixes = Set{IPPrefix}()
        for session in router.sessions
            union!(prefixes, keys(session.incoming))
        end
        for prefix in sort!(collect(prefixes))
            redecide!(simulation, rule.owner, prefix)
        end
    else
        for session in router.sessions
            if simulation.network.links[session.link].up
                union!(session.pending, keys(router.rib))
                union!(session.pending, keys(session.outgoing))
                session.timer == -1 && process_pending!(simulation, session)
            end
        end
    end
end

function execute_event!(simulation, event)
    log_update!(simulation, "EVENT $(simulation.period.number) $(event.text)")
    fields = event.fields
    if event.kind == "INITIAL"
        for (owner, prefix, origin, communities) in simulation.network.initial
            originate!(simulation, owner, prefix, origin, communities)
        end
    elseif event.kind == "ANNOUNCE"
        originate!(simulation, parse(Int, fields[2]), parse_prefix(fields[3]), fields[4], fields[5:end])
    elseif event.kind == "WITHDRAW"
        owner, prefix = parse(Int, fields[2]), parse_prefix(fields[3])
        delete!(simulation.routers[owner].origination, prefix)
        redecide!(simulation, owner, prefix)
    elseif event.kind in ("LINK_DOWN", "LINK_UP")
        link = simulation.network.links[simulation.network.by_name[fields[3]]]
        event.kind == "LINK_DOWN" ? link_down!(simulation, link) : link_up!(simulation, link)
    else
        change_policy!(simulation, simulation.policies.by_name[fields[3]], event.kind == "POLICY_ON")
    end
end

function global_state(simulation)
    sessions = Any[]
    for session in simulation.sessions
        incoming = Tuple((
            prefix,
            session.incoming[prefix]
        ) for prefix in sort!(collect(keys(session.incoming))))
        outgoing = Tuple((
            prefix,
            session.outgoing[prefix]
        ) for prefix in sort!(collect(keys(session.outgoing))))
        pending = Tuple(sort!(collect(session.pending)))
        remaining = session.timer == -1 ? -1 : session.timer - simulation.time
        push!(sessions, (incoming, outgoing, pending, remaining))
    end
    messages = Tuple((
        message.arrival - simulation.time,
        message.receiver,
        message.sender,
        message.link,
        message.prefix,
        message.content
    ) for message in ordered_messages(simulation.messages))
    return Tuple(sessions), messages
end

function detect_divergence!(simulation)
    period = simulation.period
    (period.divergence !== nothing || period.delivery_times > simulation.stepcap) && return
    state = global_state(simulation)
    if haskey(period.states, state)
        first_time = period.states[state]
        cycle = [entry for entry in period.best_lines if first_time < entry[1] <= simulation.time]
        period.divergence = (first_time, simulation.time, cycle)
    else
        period.states[state] = simulation.time
    end
end

quiet(simulation) = isempty(simulation.messages.heap) && all(
    session -> isempty(session.pending),
    simulation.sessions
)

function run_period!(simulation, number, event, boundary)
    before = Dict(owner => copy(simulation.routers[owner].rib) for owner in simulation.network.ases)
    period = BGPPeriod(
        number,
        event,
        before,
        Dict{String,Int}(),
        Dict{Tuple{Int,IPPrefix},Int}(),
        Any[],
        0,
        0,
        Dict{Any,Int}(),
        nothing,
        "",
        0
    )
    simulation.period = period
    push!(simulation.periods, period)
    simulation.time = event.time
    empty!(simulation.changed_prefixes)
    execute_event!(simulation, event)
    while true
        delivered = false
        while next_message_time(simulation.messages) == simulation.time
            receive_message!(simulation, take_message!(simulation.messages))
            delivered = true
        end
        for session in simulation.sessions
            if session.timer == simulation.time
                session.timer = -1
                !isempty(session.pending) && process_pending!(simulation, session)
            end
        end
        !isempty(simulation.changed_prefixes) && forwarding_checks!(simulation)
        if delivered
            period.delivery_times += 1
            detect_divergence!(simulation)
        end
        is_quiet = quiet(simulation)
        if boundary === nothing
            (is_quiet || period.divergence !== nothing || period.delivery_times >= simulation.stepcap) && break
        elseif simulation.time == boundary
            break
        end
        moments = [session.timer for session in simulation.sessions if session.timer >= 0]
        delivery = next_message_time(simulation.messages)
        delivery !== nothing && push!(moments, delivery)
        boundary !== nothing && push!(moments, boundary)
        simulation.time = minimum(moments)
        empty!(simulation.changed_prefixes)
    end
    period.status = period.divergence !== nothing ? "DIVERGENT" : quiet(simulation) ? "CONVERGED" : boundary === nothing ? "CAPPED" : "UNSETTLED"
    for owner in simulation.network.ases
        old, current = before[owner], simulation.routers[owner].rib
        for prefix in union(keys(old), keys(current))
            get(old, prefix, nothing) != get(current, prefix, nothing) && (period.routes_changed += 1)
        end
    end
    empty!(period.states)
end

function trace_path(simulation, source, address)
    visits, hops = [source], Any[]
    owner = source
    while true
        matches = [prefix for prefix in keys(simulation.routers[owner].rib) if prefix_contains(
            prefix,
            address
        )]
        if isempty(matches)
            result = isempty(hops) ? "UNREACHABLE" : "BLACKHOLE"
            return (
                result=result,
                visits=Tuple(visits),
                hops=Tuple(hops),
                count=count(hop -> hop[3] != 0, hops),
                arrival=0
            )
        end
        prefix = argmax(prefix -> prefix[2], matches)
        route = simulation.routers[owner].rib[prefix]
        if route_local(route)
            push!(hops, (owner, prefix, 0))
            return (
                result="DELIVERED",
                visits=Tuple(visits),
                hops=Tuple(hops),
                count=count(hop -> hop[3] != 0, hops),
                arrival=owner
            )
        end
        push!(hops, (owner, prefix, route.link))
        owner = other_end(simulation.network.links[route.link], owner)
        repeated = owner in visits
        push!(visits, owner)
        repeated && return (
            result="LOOP",
            visits=Tuple(visits),
            hops=Tuple(hops),
            count=length(hops),
            arrival=0
        )
    end
end

function prefix_loops(simulation, prefix)
    arrows = Dict{Int,Int}()
    for owner in simulation.network.ases
        route = get(simulation.routers[owner].rib, prefix, nothing)
        route !== nothing && !route_local(route) && (arrows[owner] = other_end(
            simulation.network.links[route.link],
            owner
        ))
    end
    finished, loops = Set{Int}(), Set{Tuple}()
    for start in simulation.network.ases
        start in finished && continue
        path, positions, current = Int[], Dict{Int,Int}(), start
        while haskey(arrows, current) && !(current in finished) && !haskey(positions, current)
            positions[current] = length(path) + 1
            push!(path, current)
            current = arrows[current]
        end
        if haskey(positions, current)
            cycle = path[positions[current]:end]
            first_index = argmin(cycle)
            push!(loops, Tuple(vcat(cycle[first_index:end], cycle[1:first_index - 1])))
        end
        union!(finished, path)
    end
    return loops
end

function forwarding_checks!(simulation)
    for prefix in sort!(collect(simulation.changed_prefixes))
        loops = prefix_loops(simulation, prefix)
        for (key, record) in collect(simulation.ongoing_rings)
            if key[1] == prefix && !(key[2] in loops)
                record.end_time = simulation.time
                delete!(simulation.ongoing_rings, key)
            end
        end
        for loop in sort!(collect(loops))
            key = (prefix, loop)
            if !haskey(simulation.ongoing_rings, key)
                record = RingRecord(prefix, loop, simulation.time, -1)
                push!(simulation.ring_records, record)
                simulation.ongoing_rings[key] = record
            end
        end
    end
    for (index, (source, _, address)) in enumerate(simulation.traces)
        path = trace_path(simulation, source, address)
        bad = path.result in ("LOOP", "BLACKHOLE")
        record = get(simulation.ongoing_traces, index, nothing)
        if record !== nothing && (!bad || (record.result, record.visits) != (path.result, path.visits))
            record.end_time = simulation.time
            delete!(simulation.ongoing_traces, index)
        end
        if bad && !haskey(simulation.ongoing_traces, index)
            record = TraceRecord(index, path.result, path.visits, simulation.time, -1)
            push!(simulation.trace_records, record)
            simulation.ongoing_traces[index] = record
        end
    end
end

function period_csv(period)
    items = Any[period.number, period.event.time, period.event.kind, period.status, period.convergence_time]
    append!(
        items,
        [get(period.counters, name, 0) for name in ("updates", "withdrawals", "drops", "best_changes")]
    )
    push!(items, period.routes_changed, maximum(values(period.exploration); init=0))
    return join(items, ",")
end

function rib_lines(simulation)
    lines = String[]
    for owner in simulation.network.ases
        router = simulation.routers[owner]
        local_count = count(route_local, values(router.rib))
        sent, received = sum(session.sent for session in router.sessions), sum(session.received for session in router.sessions)
        push!(
            lines,
            "AS $owner routes $(length(router.rib)) local $local_count sent $sent received $received changes $(router.changes)"
        )
        for session in router.sessions
            accepted = count(
                entry -> import_route(simulation, session, entry[1], entry[2])[1] !== nothing,
                collect(session.incoming)
            )
            link = simulation.network.links[session.link]
            state = link.up ? "UP" : "DOWN"
            push!(
                lines,
                "SESSION $(link.name) $(other_end(link, owner)) $(link_role(link, owner)) $state in $(length(session.incoming)) accepted $accepted out $(length(session.outgoing)) sent $(session.sent) received $(session.received) flaps $(link.down_count)"
            )
        end
        for prefix in sort!(collect(keys(router.rib)))
            route = router.rib[prefix]
            candidates = candidate_routes(simulation, owner, prefix)
            line = "$(prefix_text(prefix)) $(route_text(route, simulation.network)) candidates $(length(candidates))"
            !route_local(route) && (line *= " reason " * best_route(candidates, simulation.network)[2])
            push!(lines, line)
            remaining = [candidate for candidate in candidates if candidate != route]
            while !isempty(remaining)
                alternate = best_route(remaining, simulation.network)[1]
                push!(lines, "ALT " * route_text(alternate, simulation.network))
                deleteat!(remaining, findfirst(==(alternate), remaining))
            end
        end
    end
    return lines
end

function trace_lines(simulation, source, address, value)
    path = trace_path(simulation, source, value)
    lines = ["TRACE $source $address $(path.result) hops $(path.count)"]
    for (owner, prefix, link_index) in path.hops
        beginning = "HOP $owner $(prefix_text(prefix))"
        if link_index == 0
            push!(lines, beginning * " LOCAL")
        else
            link = simulation.network.links[link_index]
            push!(lines, beginning * " next $(other_end(link, owner)) link $(link.name)")
        end
    end
    path.result == "LOOP" && push!(lines, "HOP $(path.visits[end]) REVISIT")
    path.result in ("BLACKHOLE", "UNREACHABLE") && push!(lines, "HOP $(path.visits[end]) NOROUTE")
    if isempty(path.hops)
        push!(lines, "CONTROL NONE")
    else
        route = simulation.routers[source].rib[path.hops[1][2]]
        notation = route_local(route) ? "LOCAL" : path_text(route.path)
        match = path.result == "DELIVERED" && collapse_runs(route.path) == path.visits[2:end]
        push!(lines, "CONTROL $notation " * (match ? "MATCH" : "MISMATCH"))
    end
    if path.count > 0
        pattern = join(link_direction(
            simulation.network.links[link],
            owner
        ) for (owner, _, link) in path.hops if link != 0)
        judgment = valley_position(pattern) == length(pattern) ? "VALLEYFREE" : "VALLEY"
        push!(lines, "PATTERN $pattern $judgment")
    end
    return lines
end

function path_lines(simulation)
    lines = String[]
    for (source, address, value) in simulation.traces
        append!(lines, trace_lines(simulation, source, address, value))
    end
    originated = Set{IPPrefix}()
    for owner in simulation.network.ases
        union!(originated, keys(simulation.routers[owner].origination))
    end
    prefixes = sort!(collect(originated))
    push!(lines, "PREFIXES" * (isempty(prefixes) ? "" : " " * join(prefix_text.(prefixes), ",")))
    for source in simulation.network.ases
        symbols = String[]
        for prefix in prefixes
            path = trace_path(simulation, source, prefix[1])
            if path.result == "DELIVERED"
                symbol = path.count == 0 ? "*" : haskey(
                    simulation.routers[path.arrival].origination,
                    prefix
                ) ? "+" : "X"
            else
                symbol = Dict("LOOP" => "L", "BLACKHOLE" => "B", "UNREACHABLE" => "U")[path.result]
            end
            push!(symbols, symbol)
        end
        push!(lines, "REACH $source" * (isempty(symbols) ? "" : " " * join(symbols)))
    end
    return lines
end

function audit_lines(simulation)
    lines = String[]
    loops, blackholes = 0, 0
    for record in sort(simulation.trace_records; by=record -> (record.start, record.index))
        source, address, _ = simulation.traces[record.index]
        record.result == "LOOP" ? (loops += 1) : (blackholes += 1)
        endpoint = record.end_time == -1 ? "END" : string(record.end_time)
        line = "$(record.result) $source $address from $(record.start) to $endpoint"
        record.result == "BLACKHOLE" && (line *= " at $(record.visits[end])")
        push!(lines, line * " path " * path_text(record.visits))
    end
    rings = sort(simulation.ring_records; by=record -> (record.start, record.prefix, record.path[1]))
    for record in rings
        endpoint = record.end_time == -1 ? "END" : string(record.end_time)
        push!(
            lines,
            "RING $(prefix_text(record.prefix)) from $(record.start) to $endpoint path $(path_text(record.path))"
        )
    end
    route_count, valleys = 0, 0
    for owner in simulation.network.ases, prefix in sort!(collect(keys(simulation.routers[owner].rib)))
        route = simulation.routers[owner].rib[prefix]
        route_local(route) && continue
        route_count += 1
        path = collapse_runs((owner, route.path...))
        pattern = join(link_direction(
            simulation.network.links[simulation.network.between[minmax(path[index], path[index + 1])][1]],
            path[index]
        ) for index in 1:length(path) - 1)
        violation = valley_position(pattern)
        if violation != length(pattern)
            valleys += 1
            push!(
                lines,
                "VALLEY $owner $(prefix_text(prefix)) path $(path_text(route.path)) pattern $pattern leaker $(path[violation + 1])"
            )
        end
    end
    for rule in simulation.policies.rules
        push!(lines, "RULE $(rule.name) $(rule.direction) $(rule.active ? "ON" : "OFF") hits $(rule.hits)")
    end
    divergent = 0
    for period in simulation.periods
        period.divergence === nothing && continue
        divergent += 1
        first_time, repeat_time, cycle = period.divergence
        push!(
            lines,
            "DIVERGENT event $(period.number) first $first_time repeat $repeat_time period $(repeat_time - first_time)"
        )
        oscillations = Dict{Tuple{Int,IPPrefix},Int}()
        for (time, owner, prefix, route) in cycle
            push!(lines, "CYCLE $time $owner $(prefix_text(prefix)) $(route_text(route, simulation.network))")
            add_counter!(oscillations, (owner, prefix))
        end
        for (owner, prefix) in sort!(collect(keys(oscillations)))
            push!(lines, "OSCILLATE $owner $(prefix_text(prefix)) changes $(oscillations[(owner, prefix)])")
        end
    end
    push!(
        lines,
        "SUMMARY loops $loops blackholes $blackholes rings $(length(rings)) routes $route_count valleys $valleys divergent $divergent end $(simulation.time)"
    )
    return lines
end

function main()
    network, policies, events = read_topology(), read_policies(), read_events()
    defaults, stepcap, traces = read_params()
    simulation = new_simulation(network, policies, defaults, stepcap, traces)
    for (index, event) in enumerate(events)
        boundary = index < length(events) ? events[index + 1].time - 1 : nothing
        run_period!(simulation, index - 1, event, boundary)
    end
    write_reports(Dict(
        "updates.txt" => simulation.logs,
        "convergence.csv" => vcat(CONVERGENCE_HEADER, period_csv.(simulation.periods)),
        "ribs.txt" => rib_lines(simulation),
        "paths.txt" => path_lines(simulation),
        "audit.txt" => audit_lines(simulation)
    ))
end

main()
