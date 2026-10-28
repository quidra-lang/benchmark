INF <- 9007199254740991
core_distances <- function(points, neighborhoods, min_pts) vapply(seq_along(points), function(index) {
    neighbors <- neighborhoods[[index]]
    if (length(neighbors) < min_pts) INF else sort(vapply(
        neighbors,
        function(other) squared_distance(points[[index]], points[[other]]),
        0
    ))[min_pts]
}, 0)
optics_ordering <- function(points, neighborhoods, core) {
    n <- length(points)
    reach <- rep(INF, n)
    predecessor <- integer(n)
    processed <- logical(n)
    ordering <- integer()
    for (start in seq_len(n)) {
        if (processed[start]) next
        seeds <- logical(n)
        seeds[start] <- TRUE
        while (any(seeds)) {
            choices <- which(seeds)
            current <- choices[which.min(reach[choices])]
            seeds[current] <- FALSE
            processed[current] <- TRUE
            ordering <- c(ordering, current)
            if (core[current] == INF) next
            for (other in neighborhoods[[current]]) {
                if (processed[other]) next
                distance <- max(core[current], squared_distance(points[[current]], points[[other]]))
                if (distance < reach[other]) {
                    reach[other] <- distance
                    predecessor[other] <- current
                    seeds[other] <- TRUE
                }
            }
        }
    }
    list(ordering = ordering, reach = reach, predecessor = predecessor)
}
