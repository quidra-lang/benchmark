q <- function(n, d=1) gmp::as.bigq(n, d)
point <- function(x, y) list(q(x),q(y))
along <- function(a,b,t) list(a[[1]]+t*(b[[1]]-a[[1]]), a[[2]]+t*(b[[2]]-a[[2]]))
cross <- function(o,a,b) (a[[1]]-o[[1]])*(b[[2]]-o[[2]])-(a[[2]]-o[[2]])*(b[[1]]-o[[1]])
point_equal <- function(a,b) isTRUE(a[[1]] == b[[1]]) && isTRUE(a[[2]] == b[[2]])
point_less <- function(a,b) if (a[[2]] == b[[2]]) a[[1]] < b[[1]] else a[[2]] < b[[2]]
sort_points <- function(points, less=point_less) {
    result <- list()
    for (p in points) {
        position <- 1L
        while (position <= length(result) && !less(p,result[[position]])) position <- position+1L
        result <- append(result,list(p),after=position-1L)
    }
    result
}
fraction_text <- function(value) sub("/1$", "", as.character(value))
point_text <- function(p) paste0("(",fraction_text(p[[1]]),",",fraction_text(p[[2]]),")")
segment_text <- function(a,b) paste0(point_text(a),"-",point_text(b))
coordinate_real <- function(value) as.numeric(value)

qmin <- function(a,b) if (a < b) a else b
qmax <- function(a,b) if (a > b) a else b
