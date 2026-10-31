slab <- function(lo,hi,origin,direction) {
  near <- far <- NULL
  near_axis <- far_axis <- 0L
  for (axis in seq_len(3L)) {
    component <- direction[axis]
    if (component == 0) {
      if (origin[axis] < lo[axis] || origin[axis] > hi[axis]) return(NULL)
      next
    }
    a <- ((lo[axis]-origin[axis])*S) %/% component
    b <- ((hi[axis]-origin[axis])*S) %/% component
    entry <- min(a,b)
    exit <- max(a,b)
    if (is.null(near) || entry > near) {
      near <- entry
      near_axis <- axis
    }
    if (is.null(far) || exit < far) {
      far <- exit
      far_axis <- axis
    }
  }
  if (near > far) NULL else list(near=near,near_axis=near_axis,far=far,far_axis=far_axis)
}
candidate <- function(object,origin,direction,epsilon) {
  if (object$kind == "sphere") {
    oc <- sub(origin,object$center)
    b <- dot(oc,direction)
    tc <- (-b*S) %/% dot(direction,direction)
    h <- add(oc,sc(direction,tc))
    q <- object$radius^2 %/% S-dot(h,h)
    if (q < 0) return(NULL)
    width <- (integer_sqrt(q*S)*S) %/% vector_length(direction)
    t1 <- tc-width
    t2 <- tc+width
    distance <- if (t1 > epsilon) t1 else t2
    return(if (distance > epsilon) list(distance=distance,entering=FALSE,axis=0L) else NULL)
  }
  if (object$kind == "plane") {
    denominator <- dot(direction,object$normal)
    if (denominator == 0) return(NULL)
    distance <- (dot(sub(object$point,origin),object$normal)*S) %/% denominator
    return(if (distance > epsilon) list(distance=distance,entering=FALSE,axis=0L) else NULL)
  }
  interval <- slab(object$lo,object$hi,origin,direction)
  if (is.null(interval)) return(NULL)
  if (interval$near > epsilon) return(list(distance=interval$near,entering=TRUE,axis=interval$near_axis))
  if (interval$far > epsilon) return(list(distance=interval$far,entering=FALSE,axis=interval$far_axis))
  NULL
}
outward_normal <- function(object,point,direction,intersection) {
  if (object$kind == "sphere") return(norm(sub(point,object$center)))
  if (object$kind == "plane") return(object$normal)
  sign <- if (direction[intersection$axis] > 0) 1 else -1
  if (intersection$entering) sign <- -sign
  result <- numeric(3L)
  result[intersection$axis] <- sign*S
  result
}
object_bounds <- function(object,margin) {
  if (object$kind == "plane") return(NULL)
  if (object$kind == "sphere") {
    radius <- object$radius+margin
    return(list(lo=object$center-radius,hi=object$center+radius))
  }
  list(lo=object$lo-margin,hi=object$hi+margin)
}
