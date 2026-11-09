NOISE <- -1L
dbscan <- function(neighborhoods, min_pts) {
    core <- lengths(neighborhoods) >= min_pts
    labels <- rep(-2L, length(neighborhoods))
    queue <- integer(sum(lengths(neighborhoods)))
    cluster <- 0L
    for (point in seq_along(neighborhoods)) {
        if (labels[point] != -2L) next
        if (!core[point]) {
            labels[point] <- NOISE
            next
        }
        labels[point] <- cluster
        tail <- length(neighborhoods[[point]])
        queue[seq_len(tail)] <- neighborhoods[[point]]
        head <- 1L
        while (head <= tail) {
            other <- queue[head]
            head <- head + 1L
            if (labels[other] == NOISE) labels[other] <- cluster else if (labels[other] == -2L) {
                labels[other] <- cluster
                if (core[other]) {
                    neighbors <- neighborhoods[[other]]
                    queue[seq.int(tail + 1L, tail + length(neighbors))] <- neighbors
                    tail <- tail + length(neighbors)
                }
            }
        }
        cluster <- cluster + 1L
    }
    list(labels = labels, core = core)
}
