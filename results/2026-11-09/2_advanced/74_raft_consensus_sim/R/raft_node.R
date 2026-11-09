NODE_STATISTICS <- c(
    "elections",
    "leader_terms",
    "votes_granted",
    "leader_ticks",
    "ae_ok",
    "ae_fail",
    "appended",
    "truncated",
    "applies"
)
new_store <- function() new.env(hash=TRUE,parent=emptyenv())
new_node <- function(number) {
  node <- new.env(parent=emptyenv())
  node$number <- number
  node$term <- node$voted_for <- 0L
  node$log <- list()
  node$up <- TRUE
  node$stats <- setNames(integer(length(NODE_STATISTICS)),NODE_STATISTICS)
  reset_volatile(node)
  node
}
cancel_transfer <- function(node) {
  node$transfer_target <- 0L
  node$transfer_sent <- FALSE
  node$transfer_deadline <- -1L
}
reset_volatile <- function(node) {
  node$role <- "FOLLOWER"
  node$commit <- node$applied <- node$known_leader <- node$election_record <- 0L
  node$store <- new_store()
  node$votes <- node$next_index <- node$match_index <- node$heard <- integer()
  node$election_deadline <- node$heartbeat_deadline <- node$quorum_deadline <- -1L
  cancel_transfer(node)
}
crash_node <- function(node) {
  node$up <- FALSE
  reset_volatile(node)
}
last_index <- function(node) length(node$log)
last_term <- function(node) if (length(node$log)) tail(node$log,1L)[[1L]]$term else 0L
term_at <- function(node,index) if (index == 0L) 0L else node$log[[index]]$term
accepts_log <- function(
    node,
    index,
    term
) term > last_term(node) || (term == last_term(node) && index >= last_index(node))
new_entry <- function(term,command,request) list(term=term,command=command,request=request)
apply_command <- function(store,command) {
  operation <- command$kind
  if (operation == "NOOP") return(NULL)
  key <- command$key
  current <- store[[key]]
  if (operation == "SET") {
    store[[key]] <- command$value
    return("ok")
  }
  if (operation == "ADD") {
    store[[key]] <- (if (is.null(current)) 0L else current)+command$value
    return(store[[key]])
  }
  if (operation == "DEL") {
    if (!is.null(current)) {
      rm(list=key,envir=store)
      return("deleted")
    }
    return("missing")
  }
  if (is.null(current)) "missing" else current
}
