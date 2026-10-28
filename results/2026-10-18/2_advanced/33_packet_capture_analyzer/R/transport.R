pseudo_header <- function(source, destination, protocol, size) {
  c(integer_bytes(source, 4L), integer_bytes(destination, 4L), 0L, protocol, integer_bytes(size, 2L))
}
dissect_icmp <- function(message) {
  if (length(message) < 8L) malformed("icmp: truncated")
  layer <- new_layer()
  type <- message[[1L]]
  set_field(layer, "icmp.type", type)
  set_field(layer, "icmp.code", message[[2L]])
  set_field(layer, "icmp.checksum", read_integer(message, 2L, 2L))
  set_field(layer, "icmp.checksum.status", checksum_status(message))
  if (type %in% c(0L, 8L)) {
    set_field(layer, "icmp.id", read_integer(message, 4L, 2L))
    set_field(layer, "icmp.seq", read_integer(message, 6L, 2L))
  }
  layer$remaining <- byte_slice(message, 8L, length(message) - 8L)
  layer
}
dissect_udp <- function(datagram, source, destination) {
  if (length(datagram) < 8L) malformed("udp: truncated")
  size <- read_integer(datagram, 4L, 2L)
  if (size < 8L || size > length(datagram)) malformed(paste("udp: bad length", size))
  source_port <- read_integer(datagram, 0L, 2L)
  destination_port <- read_integer(datagram, 2L, 2L)
  checksum <- read_integer(datagram, 6L, 2L)
  status <- if (checksum == 0) "none" else checksum_status(c(
      pseudo_header(source, destination, 17L, size),
      byte_slice(datagram, 0L, size)
  ))
  layer <- new_layer()
  values <- list("udp.srcport" = source_port, "udp.dstport" = destination_port,
                 "udp.length" = size, "udp.checksum" = checksum, "udp.checksum.status" = status)
  for (name in names(values)) set_field(layer, name, values[[name]])
  payload <- byte_slice(datagram, 8L, size - 8L)
  if (source_port == 53 || destination_port == 53) forward(
      layer,
      "dns",
      payload
  ) else layer$remaining <- payload
  layer
}
option_text <- function(kind, size, body, layer) {
  if (kind == 2L) {
    mss <- read_integer(body, 0L, 2L)
    set_field(layer, "tcp.options.mss", mss)
    return(paste("MSS", mss))
  }
  if (kind == 3L) {
    scale <- body[[1L]]
    set_field(layer, "tcp.options.wscale", scale)
    return(paste("WS", scale))
  }
  if (kind == 4L) return("SACK_PERM")
  if (kind == 5L) {
    blocks <- vapply(seq.int(0L, length(body) - 1L, by = 8L), function(i) {
      sprintf("%.0f-%.0f", read_integer(body, i, 4L), read_integer(body, i + 4L, 4L))
    }, "")
    return(paste(c("SACK", blocks), collapse = " "))
  }
  if (kind == 8L) return(sprintf("TS %.0f %.0f", read_integer(body, 0L, 4L), read_integer(body, 4L, 4L)))
  paste("kind", kind, "len", size)
}
parse_options <- function(options, layer) {
  lengths <- list("2" = 4L, "3" = 3L, "4" = 2L, "5" = c(10L, 18L, 26L, 34L), "8" = 10L)
  index <- 1L
  while (index <= length(options)) {
    kind <- options[[index]]
    if (kind == 0L) {
      add_field(layer, "tcp.option", "EOL")
      return(invisible(NULL))
    }
    if (kind == 1L) {
      add_field(layer, "tcp.option", "NOP")
      index <- index + 1L
      next
    }
    size <- if (index < length(options)) options[[index + 1L]] else 0L
    permitted <- lengths[[as.character(kind)]]
    if (size < 2L || index + size - 1L > length(options) || (!is.null(permitted) && !(size %in% permitted))) {
      set_field(layer, "tcp.options.malformed", TRUE)
      return(invisible(NULL))
    }
    body <- byte_slice(options, index + 1L, size - 2L)
    add_field(layer, "tcp.option", option_text(kind, size, body, layer))
    index <- index + size
  }
}
dissect_tcp <- function(segment, source, destination) {
  if (length(segment) < 20L) malformed("tcp: truncated header")
  header <- (segment[[13L]] %/% 16L) * 4L
  if (header < 20L) malformed(paste("tcp: bad header length", header))
  if (header > length(segment)) malformed("tcp: truncated header")
  flags <- segment[[14L]]
  layer <- new_layer()
  values <- list(
    "tcp.srcport" = read_integer(segment, 0L, 2L), "tcp.dstport" = read_integer(segment, 2L, 2L),
    "tcp.seq_raw" = read_integer(segment, 4L, 4L), "tcp.hdr_len" = header,
    "tcp.flags" = flags, "tcp.window" = read_integer(segment, 14L, 2L),
    "tcp.checksum" = read_integer(segment, 16L, 2L),
    "tcp.checksum.status" = checksum_status(c(
        pseudo_header(source, destination, 6L, length(segment)),
        segment
    )),
    "tcp.urgent" = read_integer(segment, 18L, 2L), "tcp.len" = length(segment) - header
  )
  for (name in names(values)) set_field(layer, name, values[[name]])
  flag_names <- c("fin", "syn", "rst", "psh", "ack", "urg")
  for (i in seq_along(flag_names)) set_field(
      layer,
      paste0("tcp.flags.", flag_names[[i]]),
      (flags %/% (2 ^ (i - 1L))) %% 2
  )
  if ((flags %/% 16L) %% 2L == 1L) set_field(layer, "tcp.ack_raw", read_integer(segment, 8L, 4L))
  parse_options(byte_slice(segment, 20L, header - 20L), layer)
  layer$remaining <- byte_slice(segment, header, length(segment) - header)
  layer
}
