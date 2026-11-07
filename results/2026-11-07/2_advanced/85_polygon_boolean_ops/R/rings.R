ring_edges <- function(ring) lapply(seq_along(ring),function(i) list(ring[[i]],ring[[i %% length(ring)+1L]]))
inside_ring <- function(ring,p) {
    parity <- FALSE
    for (edge in ring_edges(ring)) {
        a <- edge[[1]]
        b <- edge[[2]]
        if ((a[[2]] > p[[2]]) != (b[[2]] > p[[2]])) {
            low <- if (a[[2]] < b[[2]]) a else b
            high <- if (a[[2]] < b[[2]]) b else a
            if (cross(low,high,p) > 0) parity <- !parity
        }
    }
    parity
}
interior <- function(rings,p) sum(vapply(rings,function(r) inside_ring(r,p),FALSE)) %% 2L == 1L
boundary <- function(ring,p) any(vapply(ring_edges(ring),function(e) on_segment(p,e[[1]],e[[2]]),FALSE))
rotate_ring <- function(ring) {
    lowest <- 1L
    for (i in seq_along(ring)) if (point_less(ring[[i]],ring[[lowest]])) lowest <- i
    c(ring[seq.int(lowest,length(ring))],if (lowest > 1L) ring[seq_len(lowest-1L)] else list())
}
counterclockwise <- function(ring) cross(ring[[length(ring)]],ring[[1]],ring[[2]]) > 0
reverse_ring <- function(ring) c(ring[1],rev(ring[-1]))
normalize_ring <- function(ring,outer) {
    result <- rotate_ring(ring)
    if (counterclockwise(result) == outer) result else reverse_ring(result)
}
sort_rings <- function(rings) {
    result <- list()
    for (ring in rings) {
        position <- 1L
        while (position <= length(result) && !point_less(
            ring[[1]],
            result[[position]][[1]]
        )) position <- position+1L
        result <- append(result,list(ring),after=position-1L)
    }
    result
}
assemble_rings <- function(rings) {
    rotated <- lapply(rings,rotate_ring)
    depths <- vapply(
        seq_along(rotated),
        function(i) sum(vapply(
            seq_along(rotated),
            function(j) j != i && inside_ring(rotated[[j]],rotated[[i]][[1]]),
            FALSE
        )),
        0
    )
    oriented <- lapply(
        seq_along(rotated),
        function(i) if (counterclockwise(rotated[[i]]) == (depths[i] %% 2L == 0L)) rotated[[i]] else reverse_ring(rotated[[i]])
    )
    outers <- which(depths %% 2L == 0L)
    ordered <- sort_rings(oriented[outers])
    result <- list()
    for (outer in ordered) {
        index <- which(vapply(oriented,function(r) point_equal(r[[1]],outer[[1]]),FALSE))[1]
        holes <- oriented[which(vapply(
            seq_along(oriented),
            function(j) depths[j] == depths[index]+1L && inside_ring(outer,oriented[[j]][[1]]),
            FALSE
        ))]
        result[[length(result)+1L]] <- c(list(outer),sort_rings(holes))
    }
    result
}
ring_area <- function(ring) {
    total <- 0
    for (edge in ring_edges(ring)) {
        a <- vapply(edge[[1]],coordinate_real,0)
        b <- vapply(edge[[2]],coordinate_real,0)
        total <- total+(a[1]*b[2]-b[1]*a[2])
    }
    total/2
}
ring_perimeter <- function(ring) {
    total <- 0
    for (edge in ring_edges(ring)) {
        a <- vapply(edge[[1]],coordinate_real,0)
        b <- vapply(edge[[2]],coordinate_real,0)
        dx <- b[1]-a[1]
        dy <- b[2]-a[2]
        total <- total+sqrt(dx*dx+dy*dy)
    }
    total
}
