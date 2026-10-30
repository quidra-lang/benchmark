graph_neighbors <- function(node_count, edges) {
    upper <- lower <- rep(list(integer()), node_count)
    for (edge in edges) {
        lower[[edge[1]]] <- c(lower[[edge[1]]], edge[2])
        upper[[edge[2]]] <- c(upper[[edge[2]]], edge[1])
    }
    list(upper=upper, lower=lower)
}
sequence_less <- function(a, b) {
    for (i in seq_len(min(length(a), length(b)))) if (a[i] != b[i]) return(a[i] < b[i])
    length(a) < length(b)
}
acyclic_order <- function(node_count, edges) {
    neighbors <- graph_neighbors(node_count, edges)
    remaining <- seq_len(node_count)
    head <- tail <- integer()
    while (length(remaining)) {
        indegree <- vapply(neighbors$upper, function(values) sum(values %in% remaining), 0L)
        outdegree <- vapply(neighbors$lower, function(values) sum(values %in% remaining), 0L)
        sinks <- remaining[outdegree[remaining] == 0L]
        sources <- remaining[indegree[remaining] == 0L]
        if (length(sinks)) {
            chosen <- min(sinks)
            tail <- c(chosen, tail)
        } else if (length(sources)) {
            chosen <- min(sources)
            head <- c(head, chosen)
        } else {
            chosen <- remaining[order(indegree[remaining]-outdegree[remaining], remaining)][1]
            head <- c(head, chosen)
        }
        remaining <- setdiff(remaining, chosen)
    }
    c(head, tail)
}
assign_heights <- function(node_count, edges, settings) {
    neighbors <- graph_neighbors(node_count, edges)
    upper <- neighbors$upper
    lower <- neighbors$lower
    heights <- rep(-1L, node_count)
    labels <- NULL
    if (settings$layering == "coffman") {
        labels <- integer(node_count)
        for (label in seq_len(node_count)) {
            candidates <- which(vapply(seq_len(node_count), function(v) labels[v] == 0L && all(labels[upper[[v]]] > 0L), FALSE))
            chosen <- candidates[1]
            best <- sort(labels[upper[[chosen]]], decreasing=TRUE)
            for (v in candidates[-1]) {
                key <- sort(labels[upper[[v]]], decreasing=TRUE)
                if (sequence_less(key, best)) {
                    chosen <- v
                    best <- key
                }
            }
            labels[chosen] <- label
        }
        current <- occupied <- 0L
        for (i in seq_len(node_count)) {
            candidates <- which(vapply(seq_len(node_count), function(v) heights[v] < 0L && all(heights[lower[[v]]] >= 0L), FALSE))
            chosen <- candidates[which.max(labels[candidates])]
            if (occupied == settings$width || any(heights[lower[[chosen]]] == current)) {
                current <- current+1L
                occupied <- 0L
            }
            heights[chosen] <- current
            occupied <- occupied+1L
        }
    } else {
        for (i in seq_len(node_count)) {
            chosen <- which(vapply(seq_len(node_count), function(v) heights[v] < 0L && all(heights[lower[[v]]] >= 0L), FALSE))[1]
            heights[chosen] <- max(c(0L, heights[lower[[chosen]]]+1L))
        }
    }
    dummies_before <- sum(vapply(edges, function(e) heights[e[1]]-heights[e[2]]-1L, 0L))
    records <- list()
    rounds <- 0L
    promote <- function(v) {
        difference <- 0L
        for (u in upper[[v]]) if (heights[u] == heights[v]+1L) difference <- difference+promote(u)
        heights[v] <<- heights[v]+1L
        difference+length(lower[[v]])-length(upper[[v]])
    }
    if (settings$promotion == "on") repeat {
        rounds <- rounds+1L
        accepted <- 0L
        for (v in seq_len(node_count)) {
            if (!length(upper[[v]])) next
            saved <- heights
            difference <- promote(v)
            if (difference < 0L) {
                accepted <- accepted+1L
                records[[length(records)+1L]] <- c(rounds, v, difference)
            } else heights <- saved
        }
        if (accepted == 0L) break
    }
    list(heights=heights, labels=labels, dummies_before=dummies_before, rounds=rounds, records=records)
}
