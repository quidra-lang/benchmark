breadth_first <- function(m, root) {
    parents <- rep(-1L, length(m$atoms))
    parents[root] <- 0L
    queue <- root
    head <- 1L
    while (head <= length(queue)) {
        a <- queue[head]
        head <- head+1L
        for (b in neighbor_numbers(m, a)) if (parents[b] == -1L) {
            parents[b] <- a
            queue <- c(queue, b)
        }
    }
    paths <- lapply(seq_along(m$atoms), function(a) {
        path <- integer()
        current <- a
        while (current != 0L) {
            path <- c(path, current)
            current <- parents[current]
        }
        path
    })
    list(parents=parents, paths=paths)
}
ring_bond_keys <- function(r) {
    vapply(seq_along(r), function(i) bond_key(r[(i-2L) %% length(r)+1L], r[i]), "")
}
sequence_less <- function(a, b) {
    for (i in seq_len(min(length(a), length(b)))) if (a[i] != b[i]) return(a[i] < b[i])
    length(a) < length(b)
}
ring_sequence <- function(sequence) {
    index <- which.min(sequence)
    forward <- c(sequence[seq.int(index, length(sequence))],
        if (index > 1L) sequence[seq_len(index-1L)] else integer())
    backward <- c(forward[1], rev(forward[-1]))
    if (sequence_less(forward, backward)) forward else backward
}
find_rings <- function(m) {
    candidates <- list()
    seen <- character()
    bonds <- ordered_bonds(m)
    keys <- vapply(bonds, function(b) bond_key(b$ends[1], b$ends[2]), "")
    indices <- setNames(seq_along(keys), keys)
    for (root in seq_along(m$atoms)) {
        bfs <- breadth_first(m, root)
        for (bond in bonds) {
            x <- bond$ends[1]
            y <- bond$ends[2]
            if (bfs$parents[x] == y || bfs$parents[y] == x) next
            if (!identical(sort(intersect(bfs$paths[[x]], bfs$paths[[y]])), root)) next
            sequence <- c(rev(bfs$paths[[x]]), head(bfs$paths[[y]], -1))
            edges <- sort(unname(indices[ring_bond_keys(sequence)]))
            key <- paste(edges, collapse=",")
            if (key %in% seen) next
            seen <- c(seen, key)
            candidates[[length(candidates)+1L]] <- list(sequence=sequence, edges=edges)
        }
    }
    candidates <- candidates[order(vapply(candidates, function(c) length(c$sequence), 0L), seq_along(candidates))]
    basis <- list()
    for (candidate in candidates) {
        reduced <- candidate$edges
        while (length(reduced)) {
            pivot <- as.character(max(reduced))
            if (is.null(basis[[pivot]])) {
                basis[[pivot]] <- reduced
                m$rings[[length(m$rings)+1L]] <- ring_sequence(candidate$sequence)
                break
            }
            reduced <- union(setdiff(reduced, basis[[pivot]]), setdiff(basis[[pivot]], reduced))
        }
    }
    keys <- vapply(m$rings, function(r) paste(sprintf("%03d", r), collapse=""), "")
    m$rings <- m$rings[order(lengths(m$rings), keys, method="radix")]
    for (ring in m$rings) {
        m$ring_atoms <- union(m$ring_atoms, ring)
        for (key in ring_bond_keys(ring)) m$bonds[[key]]$ring <- TRUE
    }
    invisible(NULL)
}
aromatic_systems <- function(m, needing) {
    remaining <- needing
    systems <- list()
    while (length(remaining)) {
        start <- min(remaining)
        remaining <- setdiff(remaining, start)
        queue <- start
        head <- 1L
        while (head <= length(queue)) {
            a <- queue[head]
            head <- head+1L
            for (b in neighbor_numbers(m, a)) if (b %in% remaining && get_bond(m, a, b)$kind == 4L) {
                remaining <- setdiff(remaining, b)
                queue <- c(queue, b)
            }
        }
        systems[[length(systems)+1L]] <- sort(queue)
    }
    systems
}
match_system <- function(m, system) {
    unpaired <- system
    pairs <- character()
    search <- function() {
        if (!length(unpaired)) return(TRUE)
        a <- min(unpaired)
        unpaired <<- setdiff(unpaired, a)
        for (b in neighbor_numbers(m, a)) {
            if (!b %in% unpaired || get_bond(m, a, b)$kind != 4L) next
            unpaired <<- setdiff(unpaired, b)
            pairs <<- c(pairs, bond_key(a, b))
            if (search()) return(TRUE)
            pairs <<- head(pairs, -1)
            unpaired <<- c(unpaired, b)
        }
        unpaired <<- c(unpaired, a)
        FALSE
    }
    if (search()) pairs else NULL
}
kekulize <- function(m, needing) {
    selected <- character()
    for (system in aromatic_systems(m, needing)) {
        pairs <- match_system(m, system)
        if (is.null(pairs)) analysis_error("kekulization failed", m$atoms[[min(system)]]$column)
        selected <- union(selected, pairs)
    }
    for (bond in ordered_bonds(m)) {
        bond$multiplicity <- if (bond$kind == 4L) {
            if (bond_key(bond$ends[1], bond$ends[2]) %in% selected) 2L else 1L
        } else bond$kind
    }
}
