SEQUENCE_MODULUS <- 4294967296
MARKS <- c("retransmission", "out_of_order", "lost_segment", "duplicate_ack")
new_side <- function(name) {
  new_object(name = name, isn = NULL, mss = NULL, wscale = NULL, base = NULL,
             expected = NULL, advanced_at = NULL, intervals = character(), previous_ack = NULL,
             packets = 0L, payload = 0, marks = setNames(integer(length(MARKS)), MARKS))
}
endpoint_key <- function(endpoint) paste(sprintf("%.0f", endpoint), collapse = ":")
endpoint_pair <- function(first, second) {
  precedes <- first[[1L]] < second[[1L]] || (first[[1L]] == second[[1L]] && first[[2L]] <= second[[2L]])
  if (precedes) paste(endpoint_key(first), endpoint_key(second), sep = "/") else paste(
      endpoint_key(second),
      endpoint_key(first),
      sep = "/"
  )
}
new_tracker <- function() new_object(
    streams = list(),
    latest = new.env(hash = TRUE, parent = emptyenv()),
    duplicate_acks = list()
)
make_segment <- function(packet) {
  value <- function(name) packet_value(packet, name)
  list(packet = packet, number = packet$number, time = packet$time,
       source = c(value("ip.src"), value("tcp.srcport")), destination = c(
           value("ip.dst"),
           value("tcp.dstport")
       ),
       seq = value("tcp.seq_raw"), ack = value("tcp.ack_raw"), fin = value("tcp.flags.fin"),
       syn = value("tcp.flags.syn"), rst = value("tcp.flags.rst"), has_ack = value("tcp.flags.ack"),
       window = value("tcp.window"), length = value("tcp.len"))
}
syn_only <- function(segment) segment$syn == 1 && segment$has_ack == 0
syn_ack <- function(segment) segment$syn == 1 && segment$has_ack == 1
change_state <- function(stream, state, number) {
  stream$state <- state
  stream$history[[length(stream$history) + 1L]] <- list(state, number)
}
record_syn <- function(stream, side, segment) {
  side$isn <- segment$seq
  side$mss <- packet_value(segment$packet, "tcp.options.mss")
  side$wscale <- packet_value(segment$packet, "tcp.options.wscale")
  if (side$name == "client") stream$syn <- segment$number else stream$syn_ack <- segment$number
}
open_stream <- function(tracker, segment) {
  if (syn_ack(segment)) {
    client <- segment$destination
    server <- segment$source
    state <- "SYN_RECEIVED"
  } else {
    client <- segment$source
    server <- segment$destination
    state <- if (syn_only(segment)) "SYN_SENT" else "ESTABLISHED"
  }
  stream <- new_object(number = length(tracker$streams), client = client, server = server, state = state,
                       history = list(list(
                           state,
                           segment$number
                       )), start_time = segment$time, end_time = segment$time,
                       packets = 0L, bytes = 0, syn = NULL, syn_ack = NULL, handshake_ack = NULL,
                       events = list(), closer = "", final_ack = NULL, client_side = new_side("client"), server_side = new_side("server"))
  if (syn_ack(segment)) record_syn(stream, stream$server_side, segment) else if (syn_only(segment)) record_syn(
      stream,
      stream$client_side,
      segment
  )
  tracker$streams[[length(tracker$streams) + 1L]] <- stream
  stream
}
sequence_mark <- function(side, start, size, time) {
  if (is.null(side$expected) || start == side$expected) return(NULL)
  if (start > side$expected) return("lost_segment")
  if (paste(start, size, sep = ":") %in% side$intervals) return("retransmission")
  if (time - side$advanced_at < 3000) "out_of_order" else "retransmission"
}
analyze_segment <- function(tracker, stream, side, segment, start) {
  size <- segment$length + segment$syn + segment$fin
  mark <- NULL
  if (size >= 1) {
    mark <- sequence_mark(side, start, size, segment$time)
    side$intervals <- union(side$intervals, paste(start, size, sep = ":"))
    if (is.null(side$expected) || start + size > side$expected) {
      side$expected <- start + size
      side$advanced_at <- segment$time
    }
  } else if (segment$has_ack == 1 && segment$rst == 0) {
    previous <- side$previous_ack
    if (!is.null(previous) && segment$ack == previous$ack && segment$window == previous$window) {
      mark <- "duplicate_ack"
      previous$count <- previous$count + 1L
      tracker$duplicate_acks[[as.character(segment$number)]] <- c(previous$number, previous$count)
    }
  }
  if (segment$has_ack == 1 && !identical(mark, "duplicate_ack")) {
    side$previous_ack <- new_object(
        ack = segment$ack,
        window = segment$window,
        number = segment$number,
        count = 0L
    )
  }
  if (!is.null(mark)) {
    set_field(segment$packet, paste0("tcp.analysis.", mark), TRUE)
    side$marks[[mark]] <- side$marks[[mark]] + 1L
    stream$events[[length(stream$events) + 1L]] <- list(segment$number, side$name, mark, start, size)
  }
}
transition <- function(stream, side, segment) {
  state <- stream$state
  number <- segment$number
  if (segment$rst == 1) {
    if (!(state %in% c("CLOSED", "RESET"))) change_state(stream, "RESET", number)
  } else if (state == "SYN_SENT" && syn_ack(segment) && side$name == "server" && segment$ack == (stream$client_side$isn + 1) %% SEQUENCE_MODULUS) {
    change_state(stream, "SYN_RECEIVED", number)
    record_syn(stream, stream$server_side, segment)
  } else if (state == "SYN_RECEIVED" && side$name == "client" && segment$has_ack == 1 && segment$syn == 0 && segment$ack == (stream$server_side$isn + 1) %% SEQUENCE_MODULUS) {
    change_state(stream, "ESTABLISHED", number)
    stream$handshake_ack <- number
  } else if (state == "ESTABLISHED" && segment$fin == 1) {
    change_state(stream, "FIN_WAIT", number)
    stream$closer <- side$name
  } else if (state == "FIN_WAIT" && segment$fin == 1 && side$name != stream$closer) {
    change_state(stream, "CLOSING", number)
    stream$final_ack <- (segment$seq + segment$length + 1) %% SEQUENCE_MODULUS
  } else if (state == "CLOSING" && side$name == stream$closer && segment$has_ack == 1 && segment$ack == stream$final_ack) {
    change_state(stream, "CLOSED", number)
  }
}
track <- function(tracker, packet) {
  segment <- make_segment(packet)
  key <- endpoint_pair(segment$source, segment$destination)
  stream <- if (exists(key, envir = tracker$latest, inherits = FALSE)) tracker$latest[[key]] else NULL
  if (is.null(stream) || (stream$state %in% c("CLOSED", "RESET") && syn_only(segment))) {
    stream <- open_stream(tracker, segment)
    tracker$latest[[key]] <- stream
  }
  set_field(packet, "tcp.stream", stream$number)
  if (identical(segment$source, stream$client)) {
    side <- stream$client_side
    other <- stream$server_side
  } else {
    side <- stream$server_side
    other <- stream$client_side
  }
  if (is.null(side$base)) side$base <- segment$seq
  if (segment$has_ack == 1 && is.null(other$base)) other$base <- segment$ack
  relative <- (segment$seq - side$base) %% SEQUENCE_MODULUS
  set_field(packet, "tcp.seq", relative)
  if (segment$has_ack == 1) set_field(packet, "tcp.ack", (segment$ack - other$base) %% SEQUENCE_MODULUS)
  analyze_segment(tracker, stream, side, segment, relative)
  scaled <- !is.null(stream$client_side$wscale) && !is.null(stream$server_side$wscale)
  window <- if (scaled && segment$syn == 0) segment$window * (2 ^ side$wscale) else segment$window
  set_field(packet, "tcp.window.calc", window)
  transition(stream, side, segment)
  side$packets <- side$packets + 1L
  side$payload <- side$payload + segment$length
  stream$packets <- stream$packets + 1L
  stream$bytes <- stream$bytes + packet$length
  stream$end_time <- segment$time
}
flow_packets <- function(flow) flow$packets_a_to_b + flow$packets_b_to_a
flow_bytes <- function(flow) flow$bytes_a_to_b + flow$bytes_b_to_a
conversation_views <- function(packet) {
  source <- packet_value(packet, "ip.src")
  destination <- packet_value(packet, "ip.dst")
  views <- list(list(
      kind = "ipv4",
      key = endpoint_pair(c(source, -1), c(destination, -1)),
      source = c(source, -1),
      destination = c(destination, -1)
  ))
  if (field_exists(packet, "tcp.stream")) {
    views[[length(views) + 1L]] <- list(kind = "tcp", key = as.character(packet_value(packet, "tcp.stream")),
                                      source = c(source, packet_value(packet, "tcp.srcport")), destination = c(
                                          destination,
                                          packet_value(packet, "tcp.dstport")
                                      ))
  }
  if (field_exists(packet, "udp.srcport")) {
    first <- c(source, packet_value(packet, "udp.srcport"))
    second <- c(destination, packet_value(packet, "udp.dstport"))
    views[[length(views) + 1L]] <- list(
        kind = "udp",
        key = endpoint_pair(first, second),
        source = first,
        destination = second
    )
  }
  views
}
build_conversations <- function(packets) {
  table <- new.env(hash = TRUE, parent = emptyenv())
  flows <- list()
  for (packet in packets) {
    if (!field_exists(packet, "ip.src")) next
    for (view in conversation_views(packet)) {
      key <- paste(view$kind, view$key, sep = "|")
      if (!exists(key, envir = table, inherits = FALSE)) {
        flow <- new_object(kind = view$kind, endpoint_a = view$source, endpoint_b = view$destination,
                           first_number = packet$number, first_time = packet$time, last_time = packet$time,
                           packets_a_to_b = 0L, bytes_a_to_b = 0, packets_b_to_a = 0L, bytes_b_to_a = 0)
        table[[key]] <- flow
        flows[[length(flows) + 1L]] <- flow
      }
      flow <- table[[key]]
      if (identical(view$source, flow$endpoint_a)) {
        flow$packets_a_to_b <- flow$packets_a_to_b + 1L
        flow$bytes_a_to_b <- flow$bytes_a_to_b + packet$length
      } else {
        flow$packets_b_to_a <- flow$packets_b_to_a + 1L
        flow$bytes_b_to_a <- flow$bytes_b_to_a + packet$length
      }
      flow$last_time <- packet$time
    }
  }
  if (!length(flows)) return(flows)
  positions <- order(-vapply(flows, flow_bytes, 0), -vapply(flows, flow_packets, 0L),
                     match(vapply(flows, function(flow) flow$kind, ""), c("ipv4", "tcp", "udp")),
                     vapply(flows, function(flow) flow$first_number, 0), method = "radix")
  flows[positions]
}
endpoint_packets <- function(endpoint) endpoint$tx_packets + endpoint$rx_packets
endpoint_bytes <- function(endpoint) endpoint$tx_bytes + endpoint$rx_bytes
build_endpoints <- function(packets) {
  table <- new.env(hash = TRUE, parent = emptyenv())
  for (packet in packets) {
    if (!field_exists(packet, "ip.src")) next
    source <- packet_value(packet, "ip.src")
    destination <- packet_value(packet, "ip.dst")
    for (address in c(source, destination)) {
      key <- sprintf("%.0f", address)
      if (!exists(key, envir = table, inherits = FALSE)) {
        table[[key]] <- new_object(
            address = address,
            tx_packets = 0L,
            tx_bytes = 0,
            rx_packets = 0L,
            rx_bytes = 0
        )
      }
    }
    sender <- table[[sprintf("%.0f", source)]]
    receiver <- table[[sprintf("%.0f", destination)]]
    sender$tx_packets <- sender$tx_packets + 1L
    sender$tx_bytes <- sender$tx_bytes + packet$length
    receiver$rx_packets <- receiver$rx_packets + 1L
    receiver$rx_bytes <- receiver$rx_bytes + packet$length
  }
  endpoints <- as.list(table, all.names = TRUE)
  if (!length(endpoints)) return(endpoints)
  endpoints[order(-vapply(endpoints, endpoint_bytes, 0), -vapply(endpoints, endpoint_packets, 0L),
                  vapply(endpoints, function(endpoint) endpoint$address, 0), method = "radix")]
}
