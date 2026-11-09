graph_edges <- function(events,processes,packets,copies,messages) {
  outgoing <- replicate(length(events),integer(),simplify=FALSE)
  for (process in processes) if (length(process$events) > 1L) for (i in seq_len(length(process$events)-1L)) {
    index <- process$events[i]
    outgoing[[index]] <- c(outgoing[[index]],process$events[i+1L])
  }
  for (i in copies) {
    packet <- packets[[i]]
    if (packet$recv_event != 0L) {
      index <- messages[[packet$message]]$send_event
      outgoing[[index]] <- c(outgoing[[index]],packet$recv_event)
    }
  }
  outgoing
}
graph_path <- function(source,target,edges) {
  parent <- integer(length(edges))
  parent[source] <- -1L
  queue <- source
  head <- 1L
  while (head <= length(queue) && parent[target] == 0L) {
    current <- queue[head]
    head <- head+1L
    for (next_event in edges[[current]]) if (parent[next_event] == 0L) {
      parent[next_event] <- current
      queue <- c(queue,next_event)
    }
  }
  if (parent[target] == 0L) return(NULL)
  path <- integer()
  cursor <- target
  while (cursor != -1L) {
    path <- c(path,cursor)
    cursor <- parent[cursor]
  }
  rev(path)
}
concurrency_statistics <- function(events,n) {
  ordered <- concurrent <- same_lamport <- inversions <- 0L
  by_pair <- matrix(0L,n,n)
  if (length(events) > 1L) for (i in seq_len(length(events)-1L)) for (j in seq.int(i+1L,length(events))) {
    a <- events[[i]]
    b <- events[[j]]
    if (relation(a$vector,b$vector) == "||") {
      concurrent <- concurrent+1L
      same_lamport <- same_lamport+as.integer(a$lamport == b$lamport)
      if (a$process != b$process) {
        p <- min(a$process,b$process)
        q <- max(a$process,b$process)
        by_pair[p,q] <- by_pair[p,q]+1L
      }
    } else ordered <- ordered+1L
    if ((a$time-b$time)*(a$lamport-b$lamport) < 0L) inversions <- inversions+1L
  }
  list(
      pairs=length(events)*(length(events)-1L) %/% 2L,
      ordered=ordered,
      concurrent=concurrent,
      same_lamport=same_lamport,
      inversions=inversions,
      by_pair=by_pair
  )
}
races_and_violations <- function(processes,packets,messages,events) {
  races <- violations <- list()
  for (p in seq_along(processes)) {
    delivered <- processes[[p]]$delivered
    if (length(delivered) > 1L) for (j in seq_len(length(delivered)-1L)) {
      a <- delivered[j]
      b <- delivered[j+1L]
      if (relation(
          events[[messages[[packets[[a]]$message]]$send_event]]$vector,
          events[[messages[[packets[[b]]$message]]$send_event]]$vector
      ) == "||") races[[length(races)+1L]] <- list(process=p,a=a,b=b)
    }
    if (length(delivered) > 1L) for (i in seq_len(length(delivered)-1L)) for (j in seq.int(
        i+1L,
        length(delivered)
    )) {
      a <- delivered[i]
      b <- delivered[j]
      if (relation(
          events[[messages[[packets[[b]]$message]]$send_event]]$vector,
          events[[messages[[packets[[a]]$message]]$send_event]]$vector
      ) == "->") violations[[length(violations)+1L]] <- list(process=p,a=a,b=b)
    }
  }
  list(races=races,violations=violations)
}
consistent_cut <- function(cut,processes,events) all(vapply(
    seq_along(cut),
    function(p) cut[p] == 0L || less_equal(events[[processes[[p]]$events[cut[p]]]]$vector,cut),
    logical(1)
))
enumerate_cuts <- function(processes,events,time_limit,thresholds) {
  limits <- vapply(
      processes,
      function(process) sum(vapply(process$events,function(i) events[[i]]$time <= time_limit,logical(1))),
      integer(1)
  )
  strides <- rep(1L,length(limits))
  if (length(limits) > 1L) for (p in seq.int(2L,length(limits))) strides[p] <- strides[p-1L]*(limits[p-1L]+1L)
  product_size <- as.integer(prod(limits+1L))
  cuts <- lapply(seq_len(product_size)-1L,function(code) as.integer((code %/% strides) %% (limits+1L)))
  consistent <- rep(FALSE,product_size)
  transit <- integer(product_size)
  levels <- integer(sum(limits)+1L)
  initial <- sum(vapply(processes,function(process) process$initial,integer(1)))
  for (index in seq_along(cuts)) {
    cut <- cuts[[index]]
    if (!consistent_cut(cut,processes,events)) next
    consistent[index] <- TRUE
    levels[sum(cut)+1L] <- levels[sum(cut)+1L]+1L
    transit[index] <- initial-sum(vapply(
        seq_along(processes),
        function(p) balance_at_cut(processes[[p]],cut[p],events),
        integer(1)
    ))
  }
  predicates <- lapply(thresholds,function(threshold) {
    reached <- rep(FALSE,product_size)
    for (index in seq_along(cuts)) {
      cut <- cuts[[index]]
      if (!consistent[index] || transit[index] >= threshold) next
      if (index == 1L || any(vapply(
          seq_along(limits),
          function(p) cut[p] > 0L && reached[index-strides[p]],
          logical(1)
      ))) reached[index] <- TRUE
    }
    total <- sum(consistent & transit >= threshold)
    list(cuts=total,possibly=total > 0L,definitely=!tail(reached,1L))
  })
  list(limits=limits,product=product_size,consistent=sum(consistent),levels=levels,predicates=predicates)
}
