MESSAGE_TYPES <- c("RV","RVR","AE","AER","TN")
MESSAGE_FIELDS <- c("sent","delivered","inflight","partition","rule","loss","down")
MESSAGE_REASONS <- c("partition","rule","loss","down")
read_network <- function(n) {
  lines <- strsplit(readLines("input/network.txt",warn=FALSE)," ",fixed=TRUE)
  default <- as.integer(lines[[1L]][2L])
  network <- new.env(parent=emptyenv())
  network$links <- vector("list",n*n)
  network$n <- n
  for (a in seq_len(n)) for (b in seq_len(n)) if (a != b) {
    link <- new.env(parent=emptyenv())
    link$delay <- default
    link$loss <- link$passed <- 0L
    link$drops <- list()
    link$stats <- setNames(integer(length(MESSAGE_FIELDS)),MESSAGE_FIELDS)
    network$links[[(a-1L)*n+b]] <- link
  }
  for (f in lines[-1L]) for (a in seq_len(n)) for (b in seq_len(n)) {
    if (a == b || !(f[2L] == "*" || as.integer(f[2L]) == a) || !(f[3L] == "*" || as.integer(f[3L]) == b)) next
    link <- network$links[[(a-1L)*n+b]]
    if (f[1L] == "DELAY") link$delay <- as.integer(f[4L]) else if (f[1L] == "LOSS") link$loss <- as.integer(f[4L]) else link$drops[[length(link$drops)+1L]] <- list(
        kind=f[4L],
        start=as.integer(f[5L]),
        finish=as.integer(f[6L])
    )
  }
  network$groups <- integer(n)
  network$total <- setNames(integer(length(MESSAGE_FIELDS)),MESSAGE_FIELDS)
  network$by_type <- setNames(
      lapply(MESSAGE_TYPES,function(k) setNames(integer(length(MESSAGE_FIELDS)),MESSAGE_FIELDS)),
      MESSAGE_TYPES
  )
  network$queue <- list()
  network$serial <- 0L
  network
}
network_link <- function(network,a,b) network$links[[(a-1L)*network$n+b]]
network_count <- function(network,message,field,amount=1L) {
  network$total[field] <- network$total[field]+amount
  network$by_type[[message$kind]][field] <- network$by_type[[message$kind]][field]+amount
  link <- network_link(network,message$source,message$destination)
  link$stats[field] <- link$stats[field]+amount
}
separated <- function(network,a,b) network$groups[a] != network$groups[b]
event_less <- function(
    a,
    b
) a$arrival < b$arrival || (a$arrival == b$arrival && (a$source < b$source || (a$source == b$source && a$serial < b$serial)))
heap_push <- function(network,event) {
  i <- length(network$queue)+1L
  network$queue[[i]] <- event
  while (i > 1L) {
    p <- i %/% 2L
    if (!event_less(event,network$queue[[p]])) break
    network$queue[[i]] <- network$queue[[p]]
    i <- p
  }
  network$queue[[i]] <- event
}
heap_pop <- function(network) {
  first <- network$queue[[1L]]
  last <- tail(network$queue,1L)[[1L]]
  network$queue <- network$queue[-length(network$queue)]
  if (!length(network$queue)) return(first)
  i <- 1L
  n <- length(network$queue)
  while (2L*i <= n) {
    child <- 2L*i
    if (child < n && event_less(network$queue[[child+1L]],network$queue[[child]])) child <- child+1L
    if (!event_less(network$queue[[child]],last)) break
    network$queue[[i]] <- network$queue[[child]]
    i <- child
  }
  network$queue[[i]] <- last
  first
}
network_send <- function(network,time,source,destination,term,kind,data) {
  message <- list(kind=kind,source=source,destination=destination,term=term,data=data)
  network$serial <- network$serial+1L
  network_count(network,message,"sent")
  link <- network_link(network,source,destination)
  if (separated(network,source,destination)) {
    network_count(network,message,"partition")
    return(invisible(NULL))
  }
  blocked <- any(vapply(
      link$drops,
      function(d) d$kind %in% c(kind,"ALL") && d$start <= time && time <= d$finish,
      logical(1)
  ))
  if (blocked) {
    network_count(network,message,"rule")
    return(invisible(NULL))
  }
  link$passed <- link$passed+1L
  if (link$loss > 0L && link$passed %% link$loss == 0L) {
    network_count(network,message,"loss")
    return(invisible(NULL))
  }
  network_count(network,message,"inflight")
  heap_push(network,list(arrival=time+link$delay,source=source,serial=network$serial,message=message))
  invisible(NULL)
}
network_arrivals <- function(network,time) {
  messages <- list()
  while (length(network$queue) && network$queue[[1L]]$arrival == time) {
    message <- heap_pop(network)$message
    network_count(network,message,"inflight",-1L)
    messages[[length(messages)+1L]] <- message
  }
  messages
}
network_deliver <- function(network,message,up) {
  if (!up) {
    network_count(network,message,"down")
    return(FALSE)
  }
  if (separated(network,message$source,message$destination)) {
    network_count(network,message,"partition")
    return(FALSE)
  }
  network_count(network,message,"delivered")
  TRUE
}
