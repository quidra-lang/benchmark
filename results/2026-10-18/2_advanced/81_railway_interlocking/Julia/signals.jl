function signal_aspects(layout, routes, route_order, occupied)
    cleared = Dict{String,Any}()
    for name in layout.signal_order
        signal = layout.signals[name]
        cleared[name] = nothing
        for route_name in route_order
            route = routes[route_name]
            route.start != name && continue
            route.state != "LOCKED" && continue
            all(
                requirement -> point_detected(layout.points[requirement[1]]) && layout.points[requirement[1]].position == requirement[2],
                route.requirements
            ) || continue
            if !any(occupied, vcat(route.sections, route.overlap))
                cleared[name] = route
                break
            end
        end
    end
    result = Tuple{TrackSignal,String}[]
    for name in layout.signal_order
        route = cleared[name]
        if route === nothing
            aspect = "RED"
        elseif haskey(layout.signals, route.finish)
            aspect = cleared[route.finish] === nothing ? "YELLOW" : "GREEN"
        else
            aspect = haskey(layout.buffers, route.finish) ? "YELLOW" : "GREEN"
        end
        push!(result, (layout.signals[name], aspect))
    end
    return result
end
