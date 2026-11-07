make_segment <- function(leg,phase,ts,te,start,velocity,finish,number) list(
    leg=leg,
    phase=phase,
    ts=ts,
    te=te,
    start=start,
    velocity=velocity,
    finish=finish,
    number=number
)
build_trajectory <- function(plan,types) {
  current <- as.numeric(plan$departure+plan$delay)
  level <- plan$level+plan$offset
  segments <- list()
  times <- list(c(current,level))
  route_length <- 0
  aircraft <- types[[plan$type]]
  for (leg in seq_len(length(plan$waypoints)-1L)) {
    first <- plan$waypoints[[leg]]
    last <- plan$waypoints[[leg+1L]]
    dx <- last$x-first$x
    dy <- last$y-first$y
    distance <- sqrt(dx*dx+dy*dy)/10
    duration <- distance*3600/plan$speed
    vx <- (dx/10)/duration
    vy <- (dy/10)/duration
    route_length <- route_length+distance
    target <- if (is.null(last$level)) level else last$level+plan$offset
    x <- first$x/10
    y <- first$y/10
    finish <- c(last$x/10,last$y/10,target*100)
    if (target == level) {
      segments[[length(segments)+1L]] <- make_segment(
          leg,
          "LVL",
          current,
          current+duration,
          c(x,y,level*100),
          c(vx,vy,0),
          finish,
          length(segments)+1L
      )
    } else {
      climbing <- target > level
      rate <- if (climbing) aircraft$climb else aircraft$descent
      vz <- if (climbing) rate/60 else -(rate/60)
      change_time <- abs(target-level)*6000/rate
      changed <- c(x+vx*change_time,y+vy*change_time,target*100)
      segments[[length(segments)+1L]] <- make_segment(
          leg,
          if (climbing) "CLB" else "DES",
          current,
          current+change_time,
          c(x,y,level*100),
          c(vx,vy,vz),
          changed,
          length(segments)+1L
      )
      segments[[length(segments)+1L]] <- make_segment(
          leg,
          "LVL",
          current+change_time,
          current+duration,
          changed,
          c(vx,vy,0),
          finish,
          length(segments)+1L
      )
    }
    current <- current+duration
    level <- target
    times[[length(times)+1L]] <- c(current,level)
  }
  list(segments=segments,arrival=current,length=route_length,waypoint_times=times)
}
segment_position <- function(segment,time) segment$start+segment$velocity*(time-segment$ts)
active_segment <- function(trajectory,time) {
  segments <- trajectory$segments
  if (!(segments[[1L]]$ts <= time && time < tail(segments,1L)[[1L]]$te)) return(NULL)
  for (segment in segments) if (segment$ts <= time && time < segment$te) return(segment)
  NULL
}
current_position <- function(trajectory,time) {
  segment <- active_segment(trajectory,time)
  if (is.null(segment)) NULL else list(point=segment_position(segment,time),segment=segment)
}
