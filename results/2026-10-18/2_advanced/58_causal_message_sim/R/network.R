minstd <- function(seed) {
  result <- new.env(parent=emptyenv())
  result$state <- as.numeric(seed)
  result$draws <- 0L
  result
}
draw <- function(generator) {
  generator$state <- (48271*generator$state) %% 2147483647
  generator$draws <- generator$draws+1L
  generator$state
}
channel_key <- function(source,destination) paste(source,destination,sep=",")
new_packet <- function(packet_type,message=0L,snapshot=0L) {
  result <- new.env(parent=emptyenv())
  result$packet_type <- packet_type
  result$message <- message
  result$snapshot <- snapshot
  result$source <- result$destination <- result$sequence <- result$dispatch_time <- result$arrival_time <- result$recv_event <- result$delivery_time <- 0L
  result$fifo_wait <- result$causal_wait <- FALSE
  result$missing <- integer()
  result
}
new_message <- function(id,kind,source,tag,amount,stamp) {
  result <- new.env(parent=emptyenv())
  result$id <- id
  result$kind <- kind
  result$source <- source
  result$tag <- tag
  result$amount <- amount
  result$stamp <- stamp
  result$copies <- integer()
  result$send_event <- result$send_time <- 0L
  result
}
read_topology <- function() {
  rows <- strsplit(readLines(file.path("input","topology.txt"))," ",fixed=TRUE)
  names <- rows[[1L]][-1L]
  channels <- list()
  for (words in rows[-1L]) {
    source <- match(words[2L],names)
    destination <- match(words[3L],names)
    channel <- new.env(parent=emptyenv())
    channel$source <- source
    channel$destination <- destination
    channel$kind <- words[4L]
    channel$minimum <- as.integer(words[5L])
    channel$maximum <- if (length(words) == 6L) as.integer(words[6L]) else channel$minimum
    for (key in c(
        "sequence",
        "last_arrival",
        "messages",
        "markers",
        "buffered",
        "max_delay",
        "entries"
    )) channel[[key]] <- 0L
    channel$previous_vector <- integer(length(names))
    channels[[channel_key(source,destination)]] <- channel
  }
  order <- list()
  for (source in seq_along(names)) for (destination in seq_along(names)) if (source != destination) order[[length(order)+1L]] <- c(
      source,
      destination
  )
  list(names=names,channels=channels,order=order)
}
copy_channels <- function(channels) lapply(channels,function(original) {
  channel <- new.env(parent=emptyenv())
  for (key in ls(original,all.names=TRUE)) channel[[key]] <- original[[key]]
  channel
})
dispatch <- function(channel,packet,time,generator,vector,enqueue) {
  channel$sequence <- channel$sequence+1L
  packet$sequence <- channel$sequence
  packet$source <- channel$source
  packet$destination <- channel$destination
  packet$dispatch_time <- time
  delay <- if (channel$minimum == channel$maximum) channel$minimum else as.integer(channel$minimum+draw(generator) %% (channel$maximum-channel$minimum+1L))
  arrival <- time+delay
  if (channel$kind == "FIFO") arrival <- max(arrival,channel$last_arrival)
  channel$last_arrival <- max(channel$last_arrival,arrival)
  packet$arrival_time <- arrival
  channel$max_delay <- max(channel$max_delay,arrival-time)
  if (packet$packet_type == "marker") channel$markers <- channel$markers+1L else {
    channel$messages <- channel$messages+1L
    channel$entries <- channel$entries+sum(channel$previous_vector != vector)
    channel$previous_vector <- vector
  }
  enqueue(arrival,channel$destination)
}
delay_notation <- function(channel) if (channel$minimum == channel$maximum) as.character(channel$minimum) else paste0(
    channel$minimum,
    "-",
    channel$maximum
)
