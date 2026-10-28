SAFETY_PROPERTIES <- c(
    "ELECTION_SAFETY",
    "LEADER_COMPLETENESS",
    "LOG_MATCHING",
    "STATE_MACHINE_SAFETY",
    "COMMITTED_KEPT"
)
new_checker <- function() {
  checker <- new.env(parent=emptyenv())
  checker$violations <- integer(5L)
  checker$leaders <- new.env(hash=TRUE,parent=emptyenv())
  checker$committed <- checker$applied <- list()
  checker$elected <- checker$log_checks <- checker$pair_checks <- checker$applies <- checker$truncations <- checker$removed <- 0L
  checker
}
check_leader <- function(checker,node) {
  checker$elected <- checker$elected+1L
  key <- as.character(node$term)
  recorded <- checker$leaders[[key]]
  if (is.null(recorded)) checker$leaders[[key]] <- node$number else if (recorded != node$number) checker$violations[1L] <- checker$violations[1L]+1L
  violation <- any(vapply(
      seq_along(checker$committed),
      function(i) i > last_index(node) || term_at(node,i) != checker$committed[[i]]$term,
      logical(1)
  ))
  if (violation) checker$violations[2L] <- checker$violations[2L]+1L
}
record_commit <- function(checker,index,term,time) {
  if (index > length(checker$committed)) checker$committed[[index]] <- list(term=term,time=time)
}
record_apply <- function(checker,index,entry,result) {
  checker$applies <- checker$applies+1L
  if (index > length(checker$applied)) checker$applied[[index]] <- list(
      entry=entry,
      result=result
  ) else if (!identical(
      checker$applied[[index]]$entry,
      entry
  )) checker$violations[4L] <- checker$violations[4L]+1L
}
check_truncate <- function(checker,first,entries) {
  checker$truncations <- checker$truncations+1L
  checker$removed <- checker$removed+length(entries)
  for (offset in seq_along(entries)) {
    index <- first+offset-1L
    if (index <= length(checker$committed) && checker$committed[[index]]$term == entries[[offset]]$term) checker$violations[5L] <- checker$violations[5L]+1L
  }
}
check_logs <- function(checker,nodes) {
  checker$log_checks <- checker$log_checks+1L
  for (a in seq_along(nodes)) if (a < length(nodes)) for (b in seq.int(a+1L,length(nodes))) {
    checker$pair_checks <- checker$pair_checks+1L
    first <- nodes[[a]]
    second <- nodes[[b]]
    limit <- min(last_index(first),last_index(second))
    greatest <- 0L
    for (i in rev(seq_len(limit))) if (term_at(first,i) == term_at(second,i)) {
      greatest <- i
      break
    }
    if (any(vapply(
        seq_len(greatest),
        function(i) !identical(first$log[[i]],second$log[[i]]),
        logical(1)
    ))) checker$violations[3L] <- checker$violations[3L]+1L
  }
}
checker_lines <- function(c,maximum_term) {
  details <- c(
      paste("terms",maximum_term,"leaders",length(ls(c$leaders,all.names=TRUE)),"elected",c$elected),
      paste("checks",c$elected,"committed",length(c$committed)),
      paste("checks",c$log_checks,"pairs",c$pair_checks),
      paste("applies",c$applies,"indices",length(c$applied)),
      paste("truncations",c$truncations,"removed",c$removed)
  )
  vapply(
      seq_len(5L),
      function(i) paste(
          SAFETY_PROPERTIES[i],
          if (c$violations[i] == 0L) "OK" else "FAIL",
          "violations",
          c$violations[i],
          details[i]
      ),
      character(1)
  )
}
