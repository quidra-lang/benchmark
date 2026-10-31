parse_action <- function(words,names) {
  kind <- words[1L]
  if (kind %in% c("LOCAL","BROADCAST","SNAPSHOT")) return(list(
      kind=kind,
      text=words[2L],
      destination=0L,
      amount=0L
  ))
  destination <- if (words[2L] == "SENDER") 0L else match(words[2L],names)
  list(
      kind=kind,
      text=if (kind == "SEND") words[3L] else "transfer",
      destination=destination,
      amount=if (kind == "TRANSFER") as.integer(words[3L]) else 0L
  )
}
read_scripts <- function(names) {
  blocks <- list()
  current <- NULL
  for (line in readLines(file.path("input","programs.txt"))) {
    words <- strsplit(line," ",fixed=TRUE)[[1L]]
    if (words[1L] == "PROCESS") current <- list(
        balance=as.integer(words[4L]),
        at=list(),
        on=list()
    ) else if (words[1L] == "END") blocks[[length(blocks)+1L]] <- current else if (words[1L] == "AT") {
      periodic <- words[3L] == "EVERY"
      start <- if (periodic) 5L else 3L
      current$at[[length(current$at)+1L]] <- list(
          start=as.integer(words[2L]),
          period=if (periodic) as.integer(words[4L]) else 0L,
          action=parse_action(words[seq.int(start,length(words))],names)
      )
    } else current$on[[length(current$on)+1L]] <- list(
        tag=words[2L],
        action=parse_action(words[-c(1L,2L)],names)
    )
  }
  blocks
}
initialize_processes <- function(names,blocks) {
  n <- length(names)
  lapply(blocks,function(block) {
    process <- new.env(parent=emptyenv())
    process$initial <- process$balance <- process$min_balance <- block$balance
    process$lamport <- process$max_held <- process$incoming <- process$outgoing <- process$refused <- 0L
    process$vector <- process$broadcast <- integer(n)
    process$at <- block$at
    process$on <- block$on
    process$events <- process$holdback <- process$delivered <- integer()
    process$next_sequence <- rep(1L,n)
    process$reorder <- replicate(n,list(),simplify=FALSE)
    process$types <- setNames(integer(5L),c("LOCAL","NOFUNDS","SEND","BCAST","RECV"))
    process
  })
}
schedule_actions <- function(processes,limit,enqueue) {
  for (p in seq_along(processes)) for (entry in processes[[p]]$at) {
    if (entry$period == 0L) {
      if (entry$start <= limit) enqueue(entry$start,p,entry$action)
    } else if (entry$start <= limit) for (time in seq.int(
        entry$start,
        limit,
        by=entry$period
    )) enqueue(time,p,entry$action)
  }
}
reaction_actions <- function(process,tag) lapply(
    Filter(function(entry) entry$tag == tag,process$on),
    function(entry) entry$action
)
balance_at_cut <- function(
    process,
    count,
    events
) if (count == 0L) process$initial else events[[process$events[count]]]$balance
held_count <- function(process) sum(vapply(process$reorder,length,integer(1)))+length(process$holdback)
