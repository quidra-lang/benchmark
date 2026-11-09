DNS_TYPE_NAMES <- c(
    "1" = "A",
    "2" = "NS",
    "5" = "CNAME",
    "6" = "SOA",
    "12" = "PTR",
    "15" = "MX",
    "16" = "TXT",
    "28" = "AAAA"
)
RCODE_NAMES <- c("NoError", "FormErr", "ServFail", "NXDomain", "NotImp", "Refused")
type_name <- function(type) {
  name <- DNS_TYPE_NAMES[as.character(type)]
  if (is.na(name)) paste0("TYPE", type) else unname(name)
}
class_name <- function(class) if (class == 1) "IN" else paste0("CLASS", class)
rcode_name <- function(code) if (code < length(RCODE_NAMES)) RCODE_NAMES[[code + 1L]] else paste0(
    "RCODE",
    code
)
dns_chunk <- function(message, position, size) {
  if (position + size > length(message)) malformed("dns: truncated")
  byte_slice(message, position, size)
}
dns_byte <- function(message, position) dns_chunk(message, position, 1L)[[1L]]
dns_integer <- function(message, position, size) read_integer(dns_chunk(message, position, size), 0L, size)
dns_label <- function(label) {
  paste(vapply(label, function(byte) {
    if (byte >= 33L && byte <= 126L && !(byte %in% c(46L, 92L))) intToUtf8(byte) else sprintf("\\%03d", byte)
  }, ""), collapse = "")
}
dns_name <- function(message, position) {
  labels <- character()
  pointers <- 0L
  after <- NULL
  repeat {
    size <- dns_byte(message, position)
    if (size == 0L) {
      if (is.null(after)) after <- position + 1L
      break
    }
    if (size >= 192L) {
      low <- dns_byte(message, position + 1L)
      if (is.null(after)) after <- position + 2L
      pointers <- pointers + 1L
      if (pointers > 16L) malformed("dns: compression loop")
      target <- (size - 192L) * 256L + low
      if (target >= length(message)) malformed("dns: pointer out of range")
      position <- target
    } else if (size >= 64L) malformed("dns: bad label type") else {
      labels <- c(labels, dns_label(dns_chunk(message, position + 1L, size)))
      position <- position + size + 1L
    }
  }
  list(name = if (length(labels)) paste(labels, collapse = ".") else "<root>", after = after)
}
ipv6_notation <- function(address) {
  groups <- vapply(seq.int(0L, 14L, by = 2L), function(i) read_integer(address, i, 2L), 0)
  best_start <- 0L
  best_length <- 1L
  index <- 1L
  while (index <= length(groups)) {
    if (groups[[index]] != 0) {
      index <- index + 1L
      next
    }
    after <- index
    while (after <= length(groups) && groups[[after]] == 0) after <- after + 1L
    if (after - index > best_length) {
      best_start <- index
      best_length <- after - index
    }
    index <- after
  }
  texts <- sprintf("%x", as.integer(groups))
  if (!best_start) return(paste(texts, collapse = ":"))
  left <- if (best_start > 1L) texts[seq_len(best_start - 1L)] else character()
  after <- best_start + best_length
  right <- if (after <= length(groups)) texts[seq.int(after, length(groups))] else character()
  paste0(paste(left, collapse = ":"), "::", paste(right, collapse = ":"))
}
dns_rdata <- function(message, type, start, size) {
  if (type == 1) return(list(name = ipv4_notation(dns_integer(message, start, 4L)), after = start + 4L))
  if (type == 28) return(list(name = ipv6_notation(dns_chunk(message, start, 16L)), after = start + 16L))
  if (type %in% c(2, 5, 12)) return(dns_name(message, start))
  if (type == 15) {
    preference <- dns_integer(message, start, 2L)
    exchange <- dns_name(message, start + 2L)
    return(list(name = paste(preference, exchange$name), after = exchange$after))
  }
  if (type == 6) {
    primary <- dns_name(message, start)
    mailbox <- dns_name(message, primary$after)
    parts <- c(primary$name, mailbox$name)
    position <- mailbox$after
    for (i in seq_len(5L)) {
      parts <- c(parts, sprintf("%.0f", dns_integer(message, position, 4L)))
      position <- position + 4L
    }
    return(list(name = paste(parts, collapse = " "), after = position))
  }
  list(name = paste(size, "bytes"), after = start + size)
}
dns_record <- function(message, position, section, layer) {
  name <- dns_name(message, position)
  fixed <- dns_chunk(message, name$after, 10L)
  type <- read_integer(fixed, 0L, 2L)
  class <- read_integer(fixed, 2L, 2L)
  ttl <- read_integer(fixed, 4L, 4L)
  size <- read_integer(fixed, 8L, 2L)
  start <- name$after + 10L
  if (start + size > length(message)) malformed("dns: truncated")
  data <- dns_rdata(message, type, start, size)
  if (data$after != start + size) malformed("dns: bad rdata length")
  record <- paste(name$name, type_name(type), class_name(class), sprintf("%.0f", ttl), data$name)
  add_field(layer, section, record)
  if (section == "dns.answer" && type == 1) add_field(layer, "dns.a", read_integer(message, start, 4L))
  start + size
}
dissect_dns <- function(message) {
  header <- dns_chunk(message, 0L, 12L)
  flags <- read_integer(header, 2L, 2L)
  counts <- vapply(seq.int(4L, 10L, by = 2L), function(i) read_integer(header, i, 2L), 0)
  layer <- new_layer()
  set_field(layer, "dns.id", read_integer(header, 0L, 2L))
  set_field(layer, "dns.flags", flags)
  set_field(layer, "dns.flags.response", (flags %/% 32768) %% 2)
  set_field(layer, "dns.flags.opcode", (flags %/% 2048) %% 16)
  set_field(layer, "dns.flags.rcode", flags %% 16)
  names <- c("dns.count.queries", "dns.count.answers", "dns.count.auth_rr", "dns.count.add_rr")
  for (i in seq_along(names)) set_field(layer, names[[i]], counts[[i]])
  position <- 12L
  for (i in seq_len(counts[[1L]])) {
    name <- dns_name(message, position)
    tail <- dns_chunk(message, name$after, 4L)
    add_field(layer, "dns.qry.name", name$name)
    add_field(layer, "dns.qry.type", read_integer(tail, 0L, 2L))
    position <- name$after + 4L
  }
  sections <- c("dns.answer", "dns.authority", "dns.additional")
  for (i in seq_along(sections)) {
    for (j in seq_len(counts[[i + 1L]])) position <- dns_record(message, position, sections[[i]], layer)
  }
  layer
}
