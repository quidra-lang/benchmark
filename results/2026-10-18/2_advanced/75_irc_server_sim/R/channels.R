new_channel <- function(index,name,time) {
  channel <- new.env(parent=emptyenv())
  channel$index <- index
  channel$name <- name
  channel$created <- time
  channel$members <- channel$bans <- list()
  channel$topic <- channel$topic_setter <- channel$key <- ""
  channel$topic_time <- -1L
  channel$flags <- c("n","t")
  channel$limit <- channel$peak <- channel$messages <- 0L
  channel$active <- TRUE
  channel
}
channel_member <- function(channel,client) {
  for (member in channel$members) if (member$client == client$index) return(member)
  NULL
}
member_status <- function(member) if (member$operator) "@" else if (member$voice) "+" else ""
member_display <- function(member,clients) paste0(member_status(member),clients[[member$client]]$nickname)
channel_add <- function(channel,client,operator=FALSE) {
  member <- new.env(parent=emptyenv())
  member$client <- client$index
  member$operator <- operator
  member$voice <- FALSE
  channel$members[[length(channel$members)+1L]] <- member
  client$channels <- c(client$channels,channel$index)
  channel$peak <- max(channel$peak,length(channel$members))
  member
}
channel_remove <- function(channel,client) {
  channel$members <- Filter(function(m) m$client != client$index,channel$members)
  client$channels <- client$channels[client$channels != channel$index]
}
name_list <- function(channel,viewer,clients) {
  inside <- !is.null(channel_member(channel,viewer))
  visible <- Filter(function(m) inside || !clients[[m$client]]$invisible,channel$members)
  paste(vapply(visible,member_display,character(1),clients=clients),collapse=" ")
}
banned <- function(channel,client) any(vapply(
    channel$bans,
    function(b) mask_matches(b$mask,client_prefix(client)),
    logical(1)
))
can_speak <- function(channel,client) {
  member <- channel_member(channel,client)
  privileged <- !is.null(member) && (member$operator || member$voice)
  (!is.null(member) || !("n" %in% channel$flags)) && (!("m" %in% channel$flags) || privileged) && (privileged || !banned(
      channel,
      client
  ))
}
mode_display <- function(channel,include_key=TRUE) {
  mode <- "+"
  for (c in c("i","k","l","m","n","t")) {
    present <- if (c == "k") nzchar(channel$key) else if (c == "l") channel$limit > 0L else c %in% channel$flags
    if (present) mode <- paste0(mode,c)
  }
  if (include_key && nzchar(channel$key)) mode <- paste(mode,channel$key)
  if (channel$limit > 0L) mode <- paste(mode,channel$limit)
  mode
}
