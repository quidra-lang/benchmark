new_node <- function(p,side,crossing=0L) {
    node <- new.env(parent=emptyenv())
    node$point <- p
    node$side <- side
    node$crossing <- crossing
    node$next_id <- node$previous <- node$other <- 0L
    node$entering <- FALSE
    node
}
build_graph <- function(first,second) {
    sequences <- list(first,second)
    slots <- lapply(
        sequences,
        function(sequence) lapply(sequence,function(ring) rep(list(list()),length(ring)))
    )
    nodes <- list()
    crossing_count <- 0L
    for (ri in seq_along(first)) for (ei in seq_along(first[[ri]])) {
        e <- ring_edges(first[[ri]])[[ei]]
        for (rj in seq_along(second)) for (ej in seq_along(second[[rj]])) {
            f <- ring_edges(second[[rj]])[[ej]]
            found <- edge_crossing(e[[1]],e[[2]],f[[1]],f[[2]])
            if (is.null(found)) next
            crossing_count <- crossing_count+1L
            i <- length(nodes)+1L
            j <- i+1L
            nodes[[i]] <- new_node(found$point,1L,crossing_count)
            nodes[[j]] <- new_node(found$point,2L,crossing_count)
            nodes[[i]]$other <- j
            nodes[[j]]$other <- i
            entry <- slots[[1]][[ri]][[ei]]
            entry[[length(entry)+1L]] <- list(position=found$t,node=i)
            slots[[1]][[ri]][[ei]] <- entry
            entry <- slots[[2]][[rj]][[ej]]
            entry[[length(entry)+1L]] <- list(position=found$u,node=j)
            slots[[2]][[rj]][[ej]] <- entry
        }
    }
    ring_nodes <- list(list(),list())
    initial <- list(logical(),logical())
    for (side in 1:2) for (ri in seq_along(sequences[[side]])) {
        ring <- sequences[[side]][[ri]]
        listed <- integer()
        for (ei in seq_along(ring)) {
            id <- length(nodes)+1L
            nodes[[id]] <- new_node(ring[[ei]],side)
            listed <- c(listed,id)
            inserted <- slots[[side]][[ri]][[ei]]
            sorted <- list()
            for (entry in inserted) {
                position <- 1L
                while (position <= length(sorted) && sorted[[position]]$position < entry$position) position <- position+1L
                sorted <- append(sorted,list(entry),after=position-1L)
            }
            listed <- c(listed,vapply(sorted,function(s) s$node,0L))
        }
        state <- interior(sequences[[3L-side]],ring[[1]])
        initial[[side]] <- c(initial[[side]],state)
        for (i in seq_along(listed)) {
            node <- nodes[[listed[i]]]
            node$previous <- listed[(i-2L) %% length(listed)+1L]
            node$next_id <- listed[i %% length(listed)+1L]
            if (node$crossing != 0L) {
                node$entering <- !state
                state <- !state
            }
        }
        ring_nodes[[side]][[ri]] <- listed
    }
    listed <- unlist(ring_nodes[[1]],use.names=FALSE)
    crossings <- listed[vapply(listed,function(id) nodes[[id]]$crossing != 0L,FALSE)]
    list(
        sequences=sequences,
        nodes=nodes,
        ring_nodes=ring_nodes,
        initial=initial,
        crossings=crossings,
        n_a=sum(initial[[1]]),
        n_b=sum(initial[[2]])
    )
}
traverse_graph <- function(graph,invert_first,invert_second) {
    inverted <- c(invert_first,invert_second)
    visited <- integer()
    result <- list()
    for (start in graph$crossings) {
        start_crossing <- graph$nodes[[start]]$crossing
        if (start_crossing %in% visited) next
        points <- list()
        current <- start
        repeat {
            node <- graph$nodes[[current]]
            visited <- c(visited,node$crossing)
            points[[length(points)+1L]] <- node$point
            forward <- node$entering != inverted[node$side]
            stopped <- if (forward) node$next_id else node$previous
            while (graph$nodes[[stopped]]$crossing == 0L) {
                points[[length(points)+1L]] <- graph$nodes[[stopped]]$point
                stopped <- if (forward) graph$nodes[[stopped]]$next_id else graph$nodes[[stopped]]$previous
            }
            if (graph$nodes[[stopped]]$crossing == start_crossing) break
            current <- graph$nodes[[stopped]]$other
        }
        result[[length(result)+1L]] <- points
    }
    for (side in 1:2) for (i in seq_along(graph$sequences[[side]])) {
        if (any(vapply(
            graph$ring_nodes[[side]][[i]],
            function(id) graph$nodes[[id]]$crossing != 0L,
            FALSE
        ))) next
        if (graph$initial[[side]][i] != inverted[side]) result[[length(result)+1L]] <- graph$sequences[[side]][[i]]
    }
    result
}
