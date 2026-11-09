bgp_attribute <- function(path, origin, med, communities) list(
    path = as.integer(path),
    origin = origin,
    med = med,
    communities = communities
)
originated_route <- function(origin, communities) list(
    path = integer(),
    origin = origin,
    med = 0L,
    communities = communities,
    local_pref = -1L,
    link = 0L
)
learned_route <- function(attribute, med, communities, local_pref, link) list(
    path = attribute$path,
    origin = attribute$origin,
    med = med,
    communities = communities,
    local_pref = local_pref,
    link = link
)
route_local <- function(route) route$link == 0L
route_neighbor <- function(route) route$path[1L]

best_route <- function(candidates, network) {
    remaining <- candidates
    if (length(remaining) == 1L) return(list(route = remaining[[1L]], reason = "ONLY"))
    for (reason in c("LOCALPREF", "ASPATH", "ORIGIN", "MED", "ROUTERID", "LINK")) {
        if (reason == "MED") {
            neighbors <- vapply(remaining, route_neighbor, 0L)
            meds <- vapply(remaining, function(route) route$med, 0L)
            keep <- vapply(
                seq_along(remaining),
                function(index) meds[index] == min(meds[neighbors == neighbors[index]]),
                FALSE
            )
        } else {
            key <- function(route) switch(
                reason,
                LOCALPREF = -route$local_pref,
                ASPATH = length(route$path),
                ORIGIN = match(route$origin, c("IGP", "EGP", "INCOMPLETE")),
                ROUTERID = network$router_ids[[as.character(route_neighbor(route))]],
                LINK = route$link
            )
            values <- vapply(remaining, key, 0)
            keep <- values == min(values)
        }
        remaining <- remaining[keep]
        if (length(remaining) == 1L) return(list(route = remaining[[1L]], reason = reason))
    }
}
