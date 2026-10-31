read_settings <- function() {
  fields <- strsplit(readLines("input/cluster.txt",warn=FALSE)," ",fixed=TRUE)
  values <- setNames(
      lapply(fields,function(f) as.integer(f[-1L])),
      vapply(fields,function(f) f[1L],character(1))
  )
  list(
      nodes=values$NODES[1L],
      election_min=values$ELECTION[1L],
      election_max=values$ELECTION[2L],
      heartbeat=values$HEARTBEAT[1L],
      batch=values$BATCH[1L],
      quorum=values$QUORUM[1L],
      seed=values$SEED[1L],
      finish=values$END[1L],
      retry=values$RETRY[1L],
      attempts=values$ATTEMPTS[1L],
      sample=values$SAMPLE[1L]
  )
}
new_request <- function(number,time,destination,command) {
  request <- new.env(parent=emptyenv())
  request$number <- number
  request$time <- time
  request$initial_destination <- destination
  request$command <- command
  request$scheduled <- time
  request$destination <- destination
  request$attempts <- request$redirects <- request$accepted_index <- request$accepted_term <- request$latency <- 0L
  request$abandoned <- FALSE
  request$status <- ""
  request$result <- NULL
  request
}
read_script <- function() {
  controls <- requests <- list()
  for (line in readLines("input/script.txt",warn=FALSE)) {
    f <- strsplit(line," ",fixed=TRUE)[[1L]]
    time <- as.integer(f[1L])
    kind <- f[2L]
    if (kind == "REQUEST") {
      command <- list(kind=f[4L],key=f[5L])
      if (f[4L] %in% c("SET","ADD")) command$value <- as.integer(f[6L])
      requests[[length(requests)+1L]] <- new_request(length(requests)+1L,time,as.integer(f[3L]),command)
    } else {
      arguments <- if (kind == "PARTITION") lapply(
          strsplit(f[-c(1L,2L)],",",fixed=TRUE),
          as.integer
      ) else as.integer(f[-c(1L,2L)])
      controls[[length(controls)+1L]] <- list(time=time,kind=kind,arguments=arguments)
    }
  }
  list(controls=controls,requests=requests)
}
