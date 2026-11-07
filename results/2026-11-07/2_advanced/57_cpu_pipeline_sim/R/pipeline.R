CAUSES <- c("control","structural","load_use","raw")
STAGES <- c("IF","ID","EX","MEM","WB")
simulate <- function(instructions,sources,variant,mispredicted) {
  n <- length(instructions)
  timings <- matrix(0L,n,5L)
  records <- list()
  delays <- integer()
  for (i in seq_along(instructions)) {
    instruction <- instructions[[i]]
    execute <- if (instruction$kind == "MUL") variant$latency else 1L
    if (i == 1L) {
      fetch <- 1L
      decode <- 2L
      start <- 3L
    } else {
      previous <- timings[i-1L,]
      fetch <- if (mispredicted[i-1L]) previous[3L]+as.integer(!id_resolved(
          instructions[[i-1L]],
          variant
      )) else previous[2L]
      decode <- max(fetch+1L,previous[3L])
      ideal <- previous[3L]+1L
      load_ready <- raw_ready <- ideal
      load_producer <- raw_producer <- 0L
      for (source in sources[[i]]) {
        p <- source$producer
        if (p == 0L) next
        ready <- ready_cycle(instruction,instructions[[p]],timings[p,],variant)
        if (instructions[[p]]$kind == "LOAD") {
          if (ready > load_ready) {
            load_ready <- ready
            load_producer <- p
          }
        } else if (ready > raw_ready) {
          raw_ready <- ready
          raw_producer <- p
        }
      }
      bounds <- c(decode+1L,previous[4L],load_ready,raw_ready)
      producers <- c(0L,0L,load_producer,raw_producer)
      start <- ideal
      for (cause in seq_len(4L)) if (bounds[cause] > start) {
        records[[length(records)+1L]] <- list(
            cause=cause,
            cycles=bounds[cause]-start,
            responsible=if (cause <= 2L) i-1L else i,
            waiting=i,
            producer=producers[cause]
        )
        start <- bounds[cause]
      }
      delays <- c(delays,start-ideal)
    }
    timings[i,] <- c(fetch,decode,start,start+execute,start+execute+1L)
  }
  if (instructions[[n]]$kind == "MUL" && variant$latency >= 2L) records[[length(records)+1L]] <- list(
      cause=2L,
      cycles=variant$latency-1L,
      responsible=n,
      waiting=0L,
      producer=0L
  )
  list(timings=timings,records=records,delays=delays,cycles=timings[n,5L])
}
