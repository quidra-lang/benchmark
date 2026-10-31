const SAFETY_PROPERTIES = ("OCCUPANCY", "POINT_MOTION", "CONFLICT", "SIGNAL_PASSING")
struct RailSafety
    checks::Dict{String,Int}
    violations::Dict{String,Int}
    records::Vector{String}
end
RailSafety() = RailSafety(
    Dict(name => 0 for name in SAFETY_PROPERTIES),
    Dict(name => 0 for name in SAFETY_PROPERTIES),
    String[]
)

function safety_check!(safety, time, kind, details=nothing)
    safety.checks[kind] += 1
    if details !== nothing
        safety.violations[kind] += 1
        push!(safety.records, "VIOLATION $time $kind $details")
    end
end

function inspect_safety!(safety, time, layout, routes, route_order)
    for name in layout.section_order
        section = layout.sections[name]
        details = length(section.occupants) >= 2 ? name * " " * join(section.occupants, ",") : nothing
        safety_check!(safety, time, "OCCUPANCY", details)
    end
    for name in layout.point_order
        point = layout.points[name]
        if point.moving
            details = nothing
            if !isempty(layout.sections[point.common].occupants)
                details = name * " occupied"
            elseif any(lock -> routes[lock[1]].state in ("USED", "APPROACH"), point.locks)
                details = name * " locked"
            end
            safety_check!(safety, time, "POINT_MOTION", details)
        end
    end
    locked = [routes[name] for name in route_order if routes[name].state in ("LOCKED", "APPROACH")]
    for first_index in eachindex(locked), second_index in first_index + 1:length(locked)
        first_route, second_route = locked[first_index], locked[second_index]
        conflict = second_route.name in first_route.conflicts || first_route.name in second_route.conflicts
        safety_check!(
            safety,
            time,
            "CONFLICT",
            conflict ? first_route.name * " " * second_route.name : nothing
        )
    end
end

function safety_report(safety)
    lines = String[]
    for kind in SAFETY_PROPERTIES
        verdict = safety.violations[kind] == 0 ? "OK" : "FAIL"
        push!(lines, "$kind $verdict checks $(safety.checks[kind]) violations $(safety.violations[kind])")
    end
    append!(lines, safety.records)
    push!(lines, "RESULT " * (isempty(safety.records) ? "SAFE" : "UNSAFE"))
    return lines
end
