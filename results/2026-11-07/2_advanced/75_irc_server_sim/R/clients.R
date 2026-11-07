new_client <- function(index,identifier,hostname,time,capacity) {
  client <- new.env(parent=emptyenv())
  client$index <- index
  client$identifier <- identifier
  client$hostname <- hostname
  client$connection_time <- client$last_received <- time
  client$tokens <- capacity
  client$nickname <- client$username <- NULL
  client$realname <- client$away <- ""
  client$invisible <- client$registered <- FALSE
  client$registration_time <- client$last_speaking <- client$ping_sent <- client$refill_time <- -1L
  client$queue <- character()
  client$channels <- client$invites <- integer()
  client$received <- client$sent <- 0L
  client$active <- TRUE
  client
}
addressee <- function(client) if (is.null(client$nickname)) "*" else client$nickname
client_prefix <- function(client) paste0(client$nickname,"!",client$username,"@",client$hostname)
client_mode <- function(client) if (client$invisible) "+i" else "+"
use_token <- function(client,time,capacity,interval) {
  if (client$tokens == capacity) client$refill_time <- time+interval
  client$tokens <- client$tokens-1L
}
refill <- function(client,time,capacity,interval) {
  if (client$refill_time == time) {
    client$tokens <- client$tokens+1L
    client$refill_time <- if (client$tokens < capacity) time+interval else -1L
  }
}
