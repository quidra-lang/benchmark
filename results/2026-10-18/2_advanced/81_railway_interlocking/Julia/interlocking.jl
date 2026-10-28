mutable struct RailRoute
    name::String
    start::String
    finish::String
    requirements::Vector{Tuple{String,String}}
    sections::Vector{String}
    overlap::Vector{String}
    conflicts::Vector{String}
    approach_time::Int
    direction::String
    state::String
    release_time::Int
    passed::Set{String}
    overlap_locked::Bool
    overlap_counter::Int
    requests::Int
    grants::Int
    uses::Int
    cancels::Int
    wait::Int
    maxwait::Int
    locked_seconds::Int
end

route_names(text) = text == "-" ? String[] : String.(split(text, ','))
function read_routes(layout)
    routes, order = Dict{String,RailRoute}(), String[]
    for line in readlines("input/routes.txt")
        fields = String.(split(line, ' '))[2:end]
        requirements = Tuple{String,String}[]
        for text in (fields[4], fields[7]), item in route_names(text)
            name, position = split(item, ':')
            push!(requirements, (String(name), String(position)))
        end
        route = RailRoute(
            fields[1],
            fields[2],
            fields[3],
            requirements,
            route_names(fields[5]),
            route_names(fields[6]),
            route_names(fields[8]),
            parse(Int, fields[9]),
            layout.signals[fields[2]].direction,
            "",
            -1,
            Set{String}(),
            false,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0
        )
        routes[route.name] = route
        push!(order, route.name)
    end
    return routes, order
end

function lock_route!(layout, route)
    route.state, route.release_time = "LOCKED", -1
    empty!(route.passed)
    route.overlap_locked, route.overlap_counter = true, 0
    for name in route.sections
        layout.sections[name].route_lock = route.name
    end
    for name in route.overlap
        push!(layout.sections[name].overlap_locks, route.name)
    end
    for (name, position) in route.requirements
        push!(layout.points[name].locks, (route.name, position))
    end
end

function unlock_points!(layout, route, sections=nothing)
    for name in layout.point_order
        point = layout.points[name]
        if sections === nothing || point.common in sections
            filter!(lock -> lock[1] != route.name, point.locks)
        end
    end
end

function unlock_section!(layout, route, name)
    section = layout.sections[name]
    section.route_lock == route.name && (section.route_lock = "")
    unlock_points!(layout, route, Set([name]))
end

function unlock_overlap!(layout, route)
    for name in route.overlap
        delete!(layout.sections[name].overlap_locks, route.name)
    end
    unlock_points!(layout, route, Set(route.overlap))
    route.overlap_locked = false
end

function release_route!(layout, route)
    for name in route.sections
        layout.sections[name].route_lock == route.name && (layout.sections[name].route_lock = "")
    end
    route.overlap_locked && unlock_overlap!(layout, route)
    unlock_points!(layout, route)
    route.state, route.release_time = "", -1
end
