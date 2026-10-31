VARIANTS <- c("ul", "ur", "dl", "dr")
segment_key <- function(a, b) paste(a, b, sep=",")
mark_conflicts <- function(orders, upper, node_count, position) {
    marked <- new.env(hash=TRUE, parent=emptyenv())
    for (layer in seq_len(length(orders)-1L)) {
        above <- orders[[layer]]
        below <- orders[[layer+1L]]
        first_bound <- 0L
        start <- 1L
        for (last in seq_along(below)) {
            v <- below[last]
            inner <- v > node_count && upper[[v]][1] > node_count
            if (!inner && last != length(below)) next
            last_bound <- if (inner) position[upper[[v]][1]] else length(above)-1L
            if (start <= last) for (w in below[seq.int(start, last)]) for (u in upper[[w]]) {
                if (position[u] < first_bound || position[u] > last_bound) marked[[segment_key(u, w)]] <- TRUE
            }
            start <- last+1L
            first_bound <- last_bound
        }
    }
    marked
}
alignment <- function(variant, orders, upper, lower, marked, vertex_count) {
    horizontal_left <- substr(variant, 2L, 2L) == "l"
    vertical_up <- substr(variant, 1L, 1L) == "u"
    scan <- lapply(orders, function(layer) if (horizontal_left) layer else rev(layer))
    rank <- positions(scan)
    root <- align <- seq_len(vertex_count)
    layers <- if (vertical_up) seq_along(orders) else rev(seq_along(orders))
    reference <- if (vertical_up) upper else lower
    for (layer in layers[-1]) {
        boundary <- -1L
        for (v in scan[[layer]]) {
            neighbors <- reference[[v]][order(rank[reference[[v]]])]
            if (!length(neighbors)) next
            middles <- c((length(neighbors)-1L) %/% 2L+1L, length(neighbors) %/% 2L+1L)
            for (middle in middles) {
                u <- neighbors[middle]
                key <- if (vertical_up) segment_key(u, v) else segment_key(v, u)
                if (align[v] == v && !exists(key, marked, inherits=FALSE) && boundary < rank[u]) {
                    align[u] <- v
                    root[v] <- root[u]
                    align[v] <- root[v]
                    boundary <- rank[u]
                }
            }
        }
    }
    list(root=root, scan=scan)
}
compact <- function(root, scan, variant, left, right, node_count, settings) {
    blocks <- sort(unique(root))
    outgoing <- incoming <- rep(list(integer()), length(root))
    horizontal_left <- substr(variant, 2L, 2L) == "l"
    for (layer in scan) for (i in seq_len(length(layer)-1L)) {
        first <- layer[i]
        second <- layer[i+1L]
        a <- if (horizontal_left) first else second
        b <- if (horizontal_left) second else first
        gap <- if (a <= node_count && b <= node_count) settings$node_sep else settings$dummy_sep
        distance <- right[a]+left[b]+1L+gap
        origin <- root[first]
        target <- root[second]
        key <- as.character(target)
        if (key %in% names(outgoing[[origin]])) distance <- max(distance, outgoing[[origin]][[key]])
        outgoing[[origin]][key] <- distance
        incoming[[target]][as.character(origin)] <- distance
    }
    pending <- lengths(incoming)
    ready <- blocks[pending[blocks] == 0L]
    ordered <- integer()
    y1 <- y2 <- integer(length(root))
    while (length(ready)) {
        block <- tail(ready, 1)
        ready <- head(ready, -1)
        ordered <- c(ordered, block)
        previous <- incoming[[block]]
        y1[block] <- max(c(0L, y1[as.integer(names(previous))]+previous))
        for (following in sort(as.integer(names(outgoing[[block]])))) {
            pending[following] <- pending[following]-1L
            if (pending[following] == 0L) ready <- c(ready, following)
        }
    }
    for (block in rev(ordered)) {
        coordinate <- y1[block]
        following <- outgoing[[block]]
        if (length(following)) coordinate <- max(coordinate, min(y2[as.integer(names(following))]-following))
        y2[block] <- coordinate
    }
    list(x=(if (horizontal_left) 1L else -1L)*y2[root], blocks=length(blocks))
}
assign_coordinates <- function(orders, upper, lower, widths, node_count, settings) {
    vertical <- settings$direction %in% c("TB", "BT")
    left <- if (vertical) (widths-1L) %/% 2L else integer(length(widths))
    right <- if (vertical) widths-1L-left else integer(length(widths))
    conflicts <- mark_conflicts(orders, upper, node_count, positions(orders))
    layouts <- blocks <- bounds <- spans <- list()
    for (variant in VARIANTS) {
        aligned <- alignment(variant, orders, upper, lower, conflicts, length(widths))
        result <- compact(aligned$root, aligned$scan, variant, left, right, node_count, settings)
        low <- min(result$x-left)
        high <- max(result$x+right)
        layouts[[variant]] <- result$x
        blocks[[variant]] <- result$blocks
        bounds[[variant]] <- c(low, high)
        spans[[variant]] <- high-low+1L
    }
    smallest <- VARIANTS[which.min(unlist(spans, use.names=FALSE))]
    aligned <- list()
    for (variant in VARIANTS) {
        side <- if (substr(variant, 2L, 2L) == "l") 1L else 2L
        shift <- bounds[[smallest]][side]-bounds[[variant]][side]
        aligned[[variant]] <- layouts[[variant]]+shift
    }
    x <- vapply(seq_along(widths), function(v) {
        values <- sort(vapply(aligned, function(layout) layout[v], 0L))
        (values[2]+values[3]) %/% 2L
    }, 0L)
    x <- unname(x-min(x-left))
    list(x=x, left=left, right=right, aligned=aligned, blocks=blocks, widths=spans,
        smallest=smallest, conflicts=conflicts)
}
