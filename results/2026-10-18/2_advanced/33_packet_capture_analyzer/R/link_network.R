malformed <- function(reason) {
  stop(structure(list(message = reason, call = NULL), class = c("malformed", "error", "condition")))
}
new_layer <- function() {
  new_object(fields = list(), next_layer = NULL, payload = integer(), remaining = integer())
}
byte_slice <- function(data, start, size) {
  if (size == 0) integer() else data[seq.int(start + 1L, start + size)]
}
read_integer <- function(data, position, count) {
  value <- 0
  for (byte in byte_slice(data, position, count)) value <- value * 256 + byte
  value
}
integer_bytes <- function(value, count) {
  as.integer(vapply(seq.int(count - 1L, 0L), function(power) (value %/% (256 ^ power)) %% 256, 0))
}
checksum_status <- function(data) {
  if (length(data) %% 2L) data <- c(data, 0L)
  total <- sum(data[seq.int(1L, length(data), by = 2L)] * 256 + data[seq.int(2L, length(data), by = 2L)])
  while (total > 65535) total <- (total %% 65536) + (total %/% 65536)
  if (total == 65535) "good" else "bad"
}
mac_notation <- function(value) paste(sprintf("%02x", integer_bytes(value, 6L)), collapse = ":")
ipv4_notation <- function(value) paste(integer_bytes(value, 4L), collapse = ".")
forward <- function(layer, name, payload) {
  layer$next_layer <- name
  layer$payload <- payload
}
dissect_ethernet <- function(frame) {
  if (length(frame) < 14L) malformed("eth: truncated")
  layer <- new_layer()
  type <- read_integer(frame, 12L, 2L)
  set_field(layer, "eth.dst", read_integer(frame, 0L, 6L))
  set_field(layer, "eth.src", read_integer(frame, 6L, 6L))
  set_field(layer, "eth.type", type)
  payload <- byte_slice(frame, 14L, length(frame) - 14L)
  if (type %in% c(2054, 2048)) {
    forward(layer, if (type == 2054) "arp" else "ip", payload)
  } else layer$remaining <- payload
  layer
}
dissect_arp <- function(message) {
  if (length(message) < 28L) malformed("arp: truncated")
  if (read_integer(message, 0L, 2L) != 1 || read_integer(
      message,
      2L,
      2L
  ) != 2048 || message[[5L]] != 6L || message[[6L]] != 4L) {
    malformed("arp: unsupported format")
  }
  layer <- new_layer()
  names <- c("arp.opcode", "arp.src.hw", "arp.src.ip", "arp.dst.hw", "arp.dst.ip")
  starts <- c(6L, 8L, 14L, 18L, 24L)
  sizes <- c(2L, 6L, 4L, 6L, 4L)
  for (i in seq_along(names)) set_field(layer, names[[i]], read_integer(message, starts[[i]], sizes[[i]]))
  layer
}
dissect_ipv4 <- function(datagram) {
  available <- length(datagram)
  if (available < 20L) malformed("ip: truncated header")
  version <- datagram[[1L]] %/% 16L
  if (version != 4L) malformed(paste("ip: bad version", version))
  header <- (datagram[[1L]] %% 16L) * 4L
  if (header < 20L) malformed(paste("ip: bad header length", header))
  if (available < header) malformed("ip: truncated header")
  total <- read_integer(datagram, 2L, 2L)
  if (total < header) malformed(paste("ip: bad total length", total))
  if (total > available) malformed(sprintf(
      "ip: truncated (total length %.0f, available %d)",
      total,
      available
  ))
  flags <- read_integer(datagram, 6L, 2L)
  more <- (flags %/% 8192) %% 2
  offset <- (flags %% 8192) * 8
  protocol <- datagram[[10L]]
  layer <- new_layer()
  values <- list(
    "ip.hdr_len" = header, "ip.tos" = datagram[[2L]], "ip.len" = total,
    "ip.id" = read_integer(datagram, 4L, 2L), "ip.flags.df" = (flags %/% 16384) %% 2,
    "ip.flags.mf" = more, "ip.frag_offset" = offset, "ip.ttl" = datagram[[9L]],
    "ip.proto" = protocol, "ip.checksum" = read_integer(datagram, 10L, 2L),
    "ip.checksum.status" = checksum_status(byte_slice(datagram, 0L, header)),
    "ip.src" = read_integer(datagram, 12L, 4L), "ip.dst" = read_integer(datagram, 16L, 4L)
  )
  for (name in names(values)) set_field(layer, name, values[[name]])
  payload <- byte_slice(datagram, header, total - header)
  if (more == 1 || offset != 0) {
    set_field(layer, "ip.fragment", TRUE)
    layer$remaining <- payload
  } else if (protocol %in% c(1L, 17L, 6L)) {
    next_layer <- if (protocol == 1L) "icmp" else if (protocol == 17L) "udp" else "tcp"
    forward(layer, next_layer, payload)
  } else layer$remaining <- payload
  layer
}
