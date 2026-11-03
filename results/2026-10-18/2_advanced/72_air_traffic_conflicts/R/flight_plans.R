load_all <- function() {
  types <- list()
  for (line in readLines("input/aircraft.txt",warn=FALSE)) {
    f <- strsplit(line," ",fixed=TRUE)[[1L]]
    types[[f[1L]]] <- list(climb=as.integer(f[2L]),descent=as.integer(f[3L]),minimum=as.integer(f[4L]))
  }
  sectors <- lapply(readLines("input/sectors.txt",warn=FALSE),function(line) {
    f <- strsplit(line," ",fixed=TRUE)[[1L]]
    v <- as.integer(f[-1L])
    list(name=f[1L],x1=v[1L],y1=v[2L],x2=v[3L],y2=v[4L],lower=v[5L],upper=v[6L],capacity=v[7L])
  })
  settings <- lapply(
      strsplit(readLines("input/params.txt",warn=FALSE)," ",fixed=TRUE),
      function(f) as.integer(f[-1L])
  )
  params <- list(
      dh=settings[[1L]][1L],
      dv=settings[[1L]][2L],
      lookahead=settings[[2L]][1L],
      max_delay=settings[[3L]][1L],
      level_min=settings[[4L]][1L],
      level_max=settings[[4L]][2L],
      sample_start=settings[[5L]][1L],
      sample_end=settings[[5L]][2L],
      radar=settings[[6L]],
      snapshots=settings[[7L]],
      leader=settings[[8L]][1L],
      alert=settings[[9L]][1L]
  )
  plans <- lapply(readLines("input/flights.csv",warn=FALSE)[-1L],function(line) {
    f <- strsplit(line,",",fixed=TRUE)[[1L]]
    waypoints <- lapply(strsplit(f[6L]," ",fixed=TRUE)[[1L]],function(text) {
      v <- as.integer(strsplit(text,":",fixed=TRUE)[[1L]])
      list(x=v[1L],y=v[2L],level=if (length(v) == 3L) v[3L] else NULL)
    })
    speed <- as.integer(f[5L])
    list(
        callsign=f[1L],
        type=f[2L],
        departure=as.integer(f[3L]),
        level=as.integer(f[4L]),
        speed_initial=speed,
        speed=speed,
        waypoints=waypoints,
        delay=0L,
        offset=0L,
        history=character()
    )
  })
  plans <- plans[order(vapply(plans,function(p) p$callsign,character(1)),method="radix")]
  list(plans=plans,types=types,sectors=sectors,params=params)
}
level_list <- function(p) c(
    p$level+p$offset,
    unlist(
        lapply(p$waypoints[-1L],function(w) if (is.null(w$level)) integer() else w$level+p$offset),
        use.names=FALSE
    )
)
