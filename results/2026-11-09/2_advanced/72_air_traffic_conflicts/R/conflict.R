loss_interval <- function(relative,velocity,t1,t2,dh,dv) {
  px <- relative[1L]
  py <- relative[2L]
  pz <- relative[3L]
  wx <- velocity[1L]
  wy <- velocity[2L]
  wz <- velocity[3L]
  qa <- wx*wx+wy*wy
  qb <- 2*(px*wx+py*wy)
  qc <- (px*px+py*py)-dh*dh
  lo <- as.numeric(t1)
  hi <- as.numeric(t2)
  if (qa < 1e-12) {
    if (qc >= 0) return(NULL)
  } else {
    discriminant <- qb*qb-4*qa*qc
    if (discriminant <= 0) return(NULL)
    root <- sqrt(discriminant)
    lo <- max(lo,t1+(-qb-root)/(2*qa))
    hi <- min(hi,t1+(-qb+root)/(2*qa))
  }
  if (wz == 0) {
    if (abs(pz) >= dv) return(NULL)
  } else {
    r1 <- (-dv-pz)/wz
    r2 <- (dv-pz)/wz
    lo <- max(lo,t1+min(r1,r2))
    hi <- min(hi,t1+max(r1,r2))
  }
  if (hi-lo <= 1e-6) return(NULL)
  tc <- if (qa >= 1e-12) t1+(-qb/(2*qa)) else as.numeric(t1)
  tc <- min(max(tc,lo),hi)
  tau <- tc-t1
  ex <- px+wx*tau
  ey <- py+wy*tau
  list(lo=lo,hi=hi,tc=tc,distance=sqrt(ex*ex+ey*ey),vertical=abs(pz+wz*tau))
}
pair_conflicts <- function(a,ta,b,tb,dh,dv) {
  pieces <- list()
  for (sa in ta$segments) for (sb in tb$segments) {
    t1 <- max(sa$ts,sb$ts)
    t2 <- min(sa$te,sb$te)
    if (t1 >= t2) next
    relative <- segment_position(sa,t1)-segment_position(sb,t1)
    velocity <- sa$velocity-sb$velocity
    interval <- loss_interval(relative,velocity,t1,t2,dh,dv)
    if (!is.null(interval)) pieces[[length(pieces)+1L]] <- c(interval,list(a_segment=sa,b_segment=sb))
  }
  pieces <- pieces[order(vapply(pieces,function(p) p$lo,numeric(1)))]
  conflicts <- list()
  for (piece in pieces) {
    n <- length(conflicts)
    if (!n || piece$lo-conflicts[[n]]$finish > 1e-6) conflicts[[n+1L]] <- list(
        pair=c(a,b),
        start=piece$lo,
        finish=piece$hi,
        pieces=list(piece),
        closest=piece
    ) else {
      conflicts[[n]]$pieces[[length(conflicts[[n]]$pieces)+1L]] <- piece
      conflicts[[n]]$finish <- piece$hi
      if (piece$distance < conflicts[[n]]$closest$distance-1e-9) conflicts[[n]]$closest <- piece
    }
  }
  conflicts
}
all_conflicts <- function(trajectories,dh,dv) {
  conflicts <- list()
  for (a in seq_along(trajectories)) if (a < length(trajectories)) for (b in seq.int(
      a+1L,
      length(trajectories)
  )) conflicts <- c(
      conflicts,
      pair_conflicts(a,trajectories[[a]],b,trajectories[[b]],dh,dv)
  )
  conflicts[order(
      vapply(conflicts,function(c) c$start,numeric(1)),
      vapply(conflicts,function(c) c$pair[1L],integer(1)),
      vapply(conflicts,function(c) c$pair[2L],integer(1))
  )]
}
