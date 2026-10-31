new_snapshot <- function(name,time,n) {
  result <- new.env(parent=emptyenv())
  result$name <- name
  result$start <- time
  result$complete <- 0L
  result$records <- vector("list",n)
  result$channel_states <- list()
  for (p in seq_len(n)) for (q in seq_len(n)) if (p != q) result$channel_states[[channel_key(
      p,
      q
  )]] <- integer()
  result$markers <- list()
  result$accepted <- character()
  result$ignored <- list()
  result
}
record_state <- function(snapshot,process,p,time,reason) {
  snapshot$records[[p]] <- list(
      time=time,
      reason=reason,
      balance=process$balance,
      lamport=process$lamport,
      vector=process$vector,
      pending=process$holdback
  )
}
accepted_marker <- function(snapshot,source,destination,time,n) {
  key <- channel_key(source,destination)
  snapshot$accepted <- union(snapshot$accepted,key)
  snapshot$markers[[key]]$accepted <- time
  if (length(snapshot$accepted) == n*(n-1L)) snapshot$complete <- time
}
snapshot_cut <- function(snapshot) vapply(
    seq_along(snapshot$records),
    function(p) snapshot$records[[p]]$vector[p],
    integer(1)
)
cut_details <- function(cut,processes,packets,copies,messages,events) {
  orphans <- transit <- integer()
  for (index in copies) {
    packet <- packets[[index]]
    sending <- events[[messages[[packet$message]]$send_event]]
    sent <- sending$local_number <= cut[packet$source]
    received <- packet$recv_event != 0L && events[[packet$recv_event]]$local_number <= cut[packet$destination]
    if (received && !sent) orphans <- c(orphans,index)
    if (sent && !received) transit <- c(transit,index)
  }
  balances <- sum(vapply(
      seq_along(processes),
      function(p) balance_at_cut(processes[[p]],cut[p],events),
      integer(1)
  ))
  money <- balances+sum(vapply(transit,function(i) messages[[packets[[i]]$message]]$amount,integer(1)))
  list(orphans=orphans,transit=transit,balances=balances,money=money,consistent=!length(orphans))
}
recorded_copies <- function(snapshot,channel_order) {
  entries <- unlist(
      lapply(channel_order,function(pair) snapshot$channel_states[[channel_key(pair[1L],pair[2L])]]),
      use.names=FALSE
  )
  pending <- unlist(lapply(snapshot$records,function(record) record$pending),use.names=FALSE)
  list(entries=as.integer(entries),pending=as.integer(pending))
}
transit_match <- function(entries,pending,transit) identical(sort(c(entries,pending)),sort(transit))
vector_consistent <- function(snapshot,cut) all(vapply(
    snapshot$records,
    function(record) less_equal(record$vector,cut),
    logical(1)
))
copy_label <- function(packet,messages,names) paste0(
    "m",
    messages[[packet$message]]$id,
    "->",
    names[packet$destination]
)
