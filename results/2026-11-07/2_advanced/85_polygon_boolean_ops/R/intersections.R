on_segment <- function(p,a,b) {
    cross(a,b,p) == 0 && p[[1]] >= qmin(a[[1]],b[[1]]) && p[[1]] <= qmax(a[[1]],b[[1]]) && p[[2]] >= qmin(a[[2]],b[[2]]) && p[[2]] <= qmax(
        a[[2]],
        b[[2]]
    )
}
segments_touch <- function(a,b,c,d) {
    proper <- cross(a,b,c)*cross(a,b,d) < 0 && cross(c,d,a)*cross(c,d,b) < 0
    proper || on_segment(c,a,b) || on_segment(d,a,b) || on_segment(a,c,d) || on_segment(b,c,d)
}
segments_overlap <- function(a,b,c,d) {
    if (cross(a,b,c) != 0 || cross(a,b,d) != 0) return(FALSE)
    axis <- if (a[[1]] != b[[1]]) 1L else 2L
    qmax(qmin(a[[axis]],b[[axis]]),qmin(c[[axis]],d[[axis]])) < qmin(
        qmax(a[[axis]],b[[axis]]),
        qmax(c[[axis]],d[[axis]])
    )
}
edge_crossing <- function(a,b,c,d) {
    rx <- b[[1]]-a[[1]]
    ry <- b[[2]]-a[[2]]
    sx <- d[[1]]-c[[1]]
    sy <- d[[2]]-c[[2]]
    den <- rx*sy-ry*sx
    if (den == 0) return(NULL)
    gx <- c[[1]]-a[[1]]
    gy <- c[[2]]-a[[2]]
    t <- (gx*sy-gy*sx)/den
    u <- (gx*ry-gy*rx)/den
    if (!(t > 0 && t < 1 && u > 0 && u < 1)) return(NULL)
    list(t=t,u=u,point=along(a,b,t))
}
clipping_point <- function(a,b,ca,cb) along(a,b,ca/(ca-cb))
