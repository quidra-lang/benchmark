path_text(path) = join(path, ",")
attribute_text(attribute) = "path $(path_text(attribute.path)) origin $(attribute.origin) med $(attribute.med) comm $(communities_text(attribute.communities))"

function route_text(route, network)
    route === nothing && return "NONE"
    communities = communities_text(route.communities)
    route_local(route) && return "LOCAL origin $(route.origin) comm $communities"
    return "next $(route_neighbor(route)) path $(path_text(route.path)) link $(network.links[route.link].name) lp $(route.local_pref) med $(route.med) origin $(route.origin) comm $communities"
end

function write_reports(reports)
    mkpath("output")
    for (name, lines) in reports
        write(joinpath("output", name), join((line * "\n" for line in lines)))
    end
end
