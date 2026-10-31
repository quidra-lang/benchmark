bgp_attribute(path, origin, med, communities) = (
    path=Tuple(path),
    origin=origin,
    med=med,
    communities=Tuple(communities)
)
originated_route(origin, communities) = (
    path=(),
    origin=origin,
    med=0,
    communities=Tuple(communities),
    local_pref=-1,
    link=0
)
learned_route(attribute, med, communities, local_pref, link) = (
    path=attribute.path,
    origin=attribute.origin,
    med=med,
    communities=Tuple(communities),
    local_pref=local_pref,
    link=link
)
route_local(route) = route.link == 0
route_neighbor(route) = route.path[1]

function best_route(candidates, network)
    remaining = copy(candidates)
    length(remaining) == 1 && return remaining[1], "ONLY"
    for reason in ("LOCALPREF", "ASPATH", "ORIGIN", "MED", "ROUTERID", "LINK")
        if reason == "MED"
            minima = Dict{Int,Int}()
            for route in remaining
                neighbor = route_neighbor(route)
                minima[neighbor] = min(get(minima, neighbor, route.med), route.med)
            end
            remaining = [route for route in remaining if route.med == minima[route_neighbor(route)]]
        else
            key = if reason == "LOCALPREF"
                route -> -route.local_pref
            elseif reason == "ASPATH"
                route -> length(route.path)
            elseif reason == "ORIGIN"
                route -> findfirst(==(route.origin), ("IGP", "EGP", "INCOMPLETE"))
            elseif reason == "ROUTERID"
                route -> network.router_ids[route_neighbor(route)]
            else
                route -> route.link
            end
            low = minimum(key, remaining)
            remaining = [route for route in remaining if key(route) == low]
        end
        length(remaining) == 1 && return remaining[1], reason
    end
end
