for (name in c(
    "hexdump",
    "link_network",
    "transport",
    "dns_app",
    "flows"
)) source(paste0(name, ".R"))

FIELDS <- list(
    list("frame.number","integer"),
    list("frame.time","integer"),
    list("frame.len","integer"),
    list("frame.protocols","string"),
    list("frame.malformed","string"),
    list("frame.bad_checksum","presence"),
    list("eth.dst","mac"),
    list("eth.src","mac"),
    list("eth.type","hex4"),
    list("arp.opcode","integer"),
    list("arp.src.hw","mac"),
    list("arp.src.ip","ipv4"),
    list("arp.dst.hw","mac"),
    list("arp.dst.ip","ipv4"),
    list("ip.hdr_len","integer"),
    list("ip.tos","hex2"),
    list("ip.len","integer"),
    list("ip.id","hex4"),
    list("ip.flags.df","integer"),
    list("ip.flags.mf","integer"),
    list("ip.frag_offset","integer"),
    list("ip.ttl","integer"),
    list("ip.proto","integer"),
    list("ip.checksum","hex4"),
    list("ip.checksum.status","string"),
    list("ip.src","ipv4"),
    list("ip.dst","ipv4"),
    list("ip.fragment","presence"),
    list("icmp.type","integer"),
    list("icmp.code","integer"),
    list("icmp.checksum","hex4"),
    list("icmp.checksum.status","string"),
    list("icmp.id","integer"),
    list("icmp.seq","integer"),
    list("udp.srcport","integer"),
    list("udp.dstport","integer"),
    list("udp.length","integer"),
    list("udp.checksum","hex4"),
    list("udp.checksum.status","string"),
    list("tcp.srcport","integer"),
    list("tcp.dstport","integer"),
    list("tcp.stream","integer"),
    list("tcp.seq","integer"),
    list("tcp.seq_raw","integer"),
    list("tcp.ack","integer"),
    list("tcp.ack_raw","integer"),
    list("tcp.hdr_len","integer"),
    list("tcp.flags","hex2"),
    list("tcp.flags.fin","integer"),
    list("tcp.flags.syn","integer"),
    list("tcp.flags.rst","integer"),
    list("tcp.flags.psh","integer"),
    list("tcp.flags.ack","integer"),
    list("tcp.flags.urg","integer"),
    list("tcp.window","integer"),
    list("tcp.window.calc","integer"),
    list("tcp.checksum","hex4"),
    list("tcp.checksum.status","string"),
    list("tcp.urgent","integer"),
    list("tcp.option","string"),
    list("tcp.options.mss","integer"),
    list("tcp.options.wscale","integer"),
    list("tcp.options.malformed","presence"),
    list("tcp.len","integer"),
    list("tcp.analysis.retransmission","presence"),
    list("tcp.analysis.out_of_order","presence"),
    list("tcp.analysis.lost_segment","presence"),
    list("tcp.analysis.duplicate_ack","presence"),
    list("dns.id","hex4"),
    list("dns.flags","hex4"),
    list("dns.flags.response","integer"),
    list("dns.flags.opcode","integer"),
    list("dns.flags.rcode","integer"),
    list("dns.count.queries","integer"),
    list("dns.count.answers","integer"),
    list("dns.count.auth_rr","integer"),
    list("dns.count.add_rr","integer"),
    list("dns.qry.name","string"),
    list("dns.qry.type","integer"),
    list("dns.answer","string"),
    list("dns.authority","string"),
    list("dns.additional","string"),
    list("dns.a","ipv4"),
    list("data.len","integer")
)
ALIASES <- list(
    "eth.addr"=list("mac","eth.dst","eth.src"),
    "ip.addr"=list("ipv4","ip.src","ip.dst"),
    "udp.port"=list("integer","udp.srcport","udp.dstport"),
    "tcp.port"=list("integer","tcp.srcport","tcp.dstport")
)
PROTOCOL_FIELDS <- list("eth","arp","ip","icmp","udp","tcp","dns","data")
PROTOCOL_LABELS <- list("eth"="ETH","arp"="ARP","ip"="IPv4","icmp"="ICMP","udp"="UDP","tcp"="TCP","dns"="DNS")
CHECKSUM_LAYERS <- list(list("ip","IPv4"),list("icmp","ICMP"),list("udp","UDP"),list("tcp","TCP"))
FLAG_NAMES <- list("FIN","SYN","RST","PSH","ACK","URG","ECE","CWR")
MARK_LABELS <- list(
    "retransmission"="[TCP Retransmission] ",
    "out_of_order"="[TCP Out-Of-Order] ",
    "lost_segment"="[TCP Previous segment not captured] "
)
HIERARCHY <- list(
    list("eth",0),
    list("arp",2),
    list("ip",2),
    list("icmp",4),
    list("udp",4),
    list("dns",6),
    list("tcp",4)
)
CONVERSATION_HEADER <- "type,endpoint_a,endpoint_b,packets,bytes,packets_a_to_b,bytes_a_to_b,packets_b_to_a,bytes_b_to_a,start,duration"
ENDPOINT_HEADER <- "address,packets,bytes,tx_packets,tx_bytes,rx_packets,rx_bytes"
FIELD_TYPES <- setNames(vapply(FIELDS, `[[`, "", 2L), vapply(FIELDS, `[[`, "", 1L))

integer_text <- function(value) sprintf("%.0f", value)
seconds <- function(value) sprintf("%.0f.%06d", value %/% 1000000, as.integer(value %% 1000000))
optional <- function(value) if (is.null(value)) "-" else integer_text(value)
notation <- function(type, value) {
  if (type == "hex2") return(sprintf("0x%02x", as.integer(value)))
  if (type == "hex4") return(sprintf("0x%04x", as.integer(value)))
  if (type == "ipv4") return(ipv4_notation(value))
  if (type == "mac") return(mac_notation(value))
  if (type == "integer") integer_text(value) else value
}
shown <- function(packet, name) notation(FIELD_TYPES[[name]], packet_value(packet, name))
endpoint_text <- function(endpoint) {
  if (endpoint[[2L]] == -1) ipv4_notation(endpoint[[1L]]) else paste0(
      ipv4_notation(endpoint[[1L]]),
      ":",
      integer_text(endpoint[[2L]])
  )
}
field_type_of <- function(name) {
  if (name %in% names(FIELD_TYPES)) return(FIELD_TYPES[[name]])
  if (name %in% names(ALIASES)) return(ALIASES[[name]][[1L]])
  if (name %in% unlist(PROTOCOL_FIELDS)) "presence" else NULL
}
filter_field_values <- function(packet, name) {
  alias <- ALIASES[[name]]
  if (!is.null(alias)) c(
      field_values(packet, alias[[2L]]),
      field_values(packet, alias[[3L]])
  ) else field_values(packet, name)
}
dissect_layer <- function(packet, name, payload) {
  switch(name, eth = dissect_ethernet(payload), arp = dissect_arp(payload), ip = dissect_ipv4(payload),
         icmp = dissect_icmp(payload), udp = dissect_udp(
             payload,
             packet_value(packet, "ip.src"),
             packet_value(packet, "ip.dst")
         ),
         tcp = dissect_tcp(
             payload,
             packet_value(packet, "ip.src"),
             packet_value(packet, "ip.dst")
         ), dns = dissect_dns(payload))
}
dissect_layers <- function(packet) {
  name <- "eth"
  payload <- packet$data
  repeat {
    packet$layers <- c(packet$layers, name)
    layer <- tryCatch(dissect_layer(packet, name, payload), malformed = function(error) error)
    if (inherits(layer, "malformed")) return(conditionMessage(layer))
    packet$fields[names(layer$fields)] <- layer$fields
    if (is.null(layer$next_layer)) {
      packet$remaining <- layer$remaining
      return(NULL)
    }
    name <- layer$next_layer
    payload <- layer$payload
  }
}
dissect <- function(packet, base_time) {
  reason <- if (is.null(packet$error)) dissect_layers(packet) else packet$error
  if (is.null(reason) && length(packet$remaining)) {
    packet$layers <- c(packet$layers, "data")
    set_field(packet, "data.len", length(packet$remaining))
  }
  set_field(packet, "frame.number", packet$number)
  set_field(packet, "frame.time", packet$time - base_time)
  set_field(packet, "frame.len", packet$length)
  if (length(packet$layers)) set_field(packet, "frame.protocols", paste(packet$layers, collapse = ":"))
  if (!is.null(reason)) set_field(packet, "frame.malformed", reason)
  if (any(vapply(
      CHECKSUM_LAYERS,
      function(layer) identical(packet_value(packet, paste0(layer[[1L]], ".checksum.status")), "bad"),
      FALSE
  ))) {
    set_field(packet, "frame.bad_checksum", TRUE)
  }
}
addresses <- function(packet) {
  if (field_exists(packet, "ip.src")) return(c(shown(packet, "ip.src"), shown(packet, "ip.dst")))
  if (field_exists(packet, "eth.src")) return(c(shown(packet, "eth.src"), shown(packet, "eth.dst")))
  c("-", "-")
}
protocol_label <- function(packet) {
  layers <- packet$layers[packet$layers != "data"]
  if (length(layers)) PROTOCOL_LABELS[[tail(layers, 1L)]] else "DUMP"
}
option_summary <- function(options) {
  parts <- character()
  for (option in options) {
    words <- strsplit(option, " ", fixed = TRUE)[[1L]]
    if (words[[1L]] == "MSS") parts <- c(parts, paste0(" MSS=", words[[2L]]))
    if (words[[1L]] == "WS") parts <- c(parts, paste0(" WS=", integer_text(2 ^ as.integer(words[[2L]]))))
    if (words[[1L]] == "SACK_PERM") parts <- c(parts, " SACK_PERM")
    if (words[[1L]] == "TS") parts <- c(parts, paste0(" TSval=", words[[2L]], " TSecr=", words[[3L]]))
  }
  paste(parts, collapse = "")
}
tcp_info <- function(packet, duplicate_acks) {
  value <- function(name) packet_value(packet, name)
  prefix <- ""
  if (field_exists(packet, "tcp.analysis.duplicate_ack")) {
    pair <- duplicate_acks[[as.character(packet$number)]]
    prefix <- paste0("[TCP Dup ACK ", integer_text(pair[[1L]]), "#", integer_text(pair[[2L]]), "] ")
  } else {
    for (mark in MARKS[1L:3L]) {
      if (field_exists(packet, paste0("tcp.analysis.", mark))) {
        prefix <- MARK_LABELS[[mark]]
        break
      }
    }
  }
  flags <- value("tcp.flags")
  names <- unlist(FLAG_NAMES)[(flags %/% (2 ^ (0L:7L))) %% 2 == 1]
  flag_text <- if (length(names)) paste(names, collapse = ", ") else "<None>"
  text <- paste0(
      prefix,
      integer_text(value("tcp.srcport")),
      " -> ",
      integer_text(value("tcp.dstport")),
      " [",
      flag_text,
      "] Seq=",
      integer_text(value("tcp.seq"))
  )
  if (value("tcp.flags.ack") == 1) text <- paste0(text, " Ack=", integer_text(value("tcp.ack")))
  paste0(
      text,
      " Win=",
      integer_text(value("tcp.window.calc")),
      " Len=",
      integer_text(value("tcp.len")),
      option_summary(field_values(packet, "tcp.option"))
  )
}
dns_info <- function(packet) {
  value <- function(name) packet_value(packet, name)
  parts <- c(if (value("dns.flags.response") == 1) "Response" else "Query", shown(packet, "dns.id"))
  if (value("dns.flags.rcode") != 0) parts <- c(parts, rcode_name(value("dns.flags.rcode")))
  names <- field_values(packet, "dns.qry.name")
  types <- field_values(packet, "dns.qry.type")
  for (i in seq_along(names)) parts <- c(parts, type_name(types[[i]]), names[[i]])
  for (record in field_values(packet, "dns.answer")) {
    words <- strsplit(record, " ", fixed = TRUE)[[1L]]
    parts <- c(parts, words[[2L]], paste(words[seq.int(5L, length(words))], collapse = " "))
  }
  paste(parts, collapse = " ")
}
basic_info <- function(packet, protocol, duplicate_acks) {
  value <- function(name) packet_value(packet, name)
  if (field_exists(packet, "frame.malformed")) return(value("frame.malformed"))
  if (protocol == "ETH") return(paste("EtherType", shown(packet, "eth.type")))
  if (protocol == "ARP") {
    opcode <- value("arp.opcode")
    if (opcode == 1) return(paste0(
        "Who has ",
        shown(packet, "arp.dst.ip"),
        "? Tell ",
        shown(packet, "arp.src.ip")
    ))
    if (opcode == 2) return(paste(shown(packet, "arp.src.ip"), "is at", shown(packet, "arp.src.hw")))
    return(paste("Opcode", opcode))
  }
  if (protocol == "IPv4") {
    if (!field_exists(packet, "ip.fragment")) return(paste("Protocol", value("ip.proto")))
    return(paste0(
        "Fragment id=",
        shown(packet, "ip.id"),
        " off=",
        integer_text(value("ip.frag_offset")),
        if (value("ip.flags.mf") == 1) " MF" else ""
    ))
  }
  if (protocol == "ICMP") {
    type <- value("icmp.type")
    if (type %in% c(0, 8)) return(paste0(
        "Echo ",
        if (type == 8) "request" else "reply",
        " id=",
        integer_text(value("icmp.id")),
        " seq=",
        integer_text(value("icmp.seq"))
    ))
    return(paste("Type", type, "code", value("icmp.code")))
  }
  if (protocol == "UDP") return(paste0(
      integer_text(value("udp.srcport")),
      " -> ",
      integer_text(value("udp.dstport")),
      " Len=",
      integer_text(value("udp.length") - 8)
  ))
  if (protocol == "TCP") tcp_info(packet, duplicate_acks) else dns_info(packet)
}
summary_line <- function(packet, duplicate_acks) {
  endpoints <- addresses(packet)
  protocol <- protocol_label(packet)
  info <- basic_info(packet, protocol, duplicate_acks)
  if (field_exists(packet, "tcp.options.malformed")) info <- paste0(info, " [bad TCP options]")
  for (layer in CHECKSUM_LAYERS) {
    if (identical(
        packet_value(packet, paste0(layer[[1L]], ".checksum.status")),
        "bad"
    )) info <- paste0(info, " [bad ", layer[[2L]], " checksum]")
  }
  paste(
      integer_text(packet$number),
      seconds(packet_value(packet, "frame.time")),
      endpoints[[1L]],
      "->",
      endpoints[[2L]],
      protocol,
      integer_text(packet$length),
      info
  )
}
filter_error <- function(reason) {
  stop(structure(list(message = reason, call = NULL), class = c("filter_error", "error", "condition")))
}
tokenize <- function(expression) {
  tokens <- list()
  index <- 1L
  size <- nchar(expression, type = "bytes")
  word_character <- function(character) grepl("^[A-Za-z0-9._:]$", character)
  add <- function(kind, text, column) tokens[[length(tokens) + 1L]] <<- list(
      kind = kind,
      text = text,
      column = column
  )
  while (index <= size) {
    character <- substr(expression, index, index)
    pair <- substr(expression, index, index + 1L)
    if (character == " ") index <- index + 1L else if (pair %in% c("==", "!=", "<=", ">=", "&&", "||")) {
      add(pair, pair, index)
      index <- index + 2L
    } else if (character %in% c("(", ")", "!", "<", ">")) {
      add(character, character, index)
      index <- index + 1L
    } else if (character == '"') {
      after <- index + 1L
      while (after <= size && substr(expression, after, after) != '"') after <- after + 1L
      if (after > size) filter_error(paste("unterminated string at column", index))
      add("string", substr(expression, index, after), index)
      index <- after + 1L
    } else if (word_character(character)) {
      after <- index
      while (after <= size && word_character(substr(expression, after, after))) after <- after + 1L
      word <- substr(expression, index, after - 1L)
      kind <- switch(word, "and" = "&&", "or" = "||", "not" = "!", "word")
      add(kind, word, index)
      index <- after
    } else filter_error(paste0("invalid character '", character, "' at column ", index))
  }
  tokens
}
parse_filter_value <- function(type, token) {
  if (type == "string") return(if (token$kind == "string") substr(
      token$text,
      2L,
      nchar(token$text) - 1L
  ) else NULL)
  if (token$kind != "word") return(NULL)
  text <- token$text
  if (type %in% c("integer", "hex2", "hex4")) {
    if (grepl("^[0-9]{1,15}$", text)) return(as.numeric(text))
    if (grepl("^0x[0-9a-fA-F]{1,12}$", text)) {
      digits <- strsplit(substring(text, 3L), "", fixed = TRUE)[[1L]]
      value <- 0
      for (digit in digits) value <- value * 16 + strtoi(digit, base = 16L)
      return(value)
    }
    return(NULL)
  }
  parts <- strsplit(text, if (type == "ipv4") "." else ":", fixed = TRUE)[[1L]]
  if (endsWith(text, if (type == "ipv4") "." else ":")) parts <- c(parts, "")
  if (length(parts) != if (type == "ipv4") 4L else 6L) return(NULL)
  value <- 0
  for (part in parts) {
    if (type == "ipv4") {
      if (!grepl("^[0-9]{1,3}$", part)) return(NULL)
      octet <- as.integer(part)
      if (octet > 255L) return(NULL)
    } else {
      if (!grepl("^[0-9a-fA-F]{2}$", part)) return(NULL)
      octet <- strtoi(part, base = 16L)
    }
    value <- value * 256 + octet
  }
  value
}
unexpected <- function(token) filter_error(paste0("unexpected '", token$text, "' at column ", token$column))
parse_filter <- function(expression) {
  tokens <- tokenize(expression)
  position <- 1L
  next_kind <- function() if (position <= length(tokens)) tokens[[position]]$kind else ""
  take <- function() {
    if (position > length(tokens)) filter_error("unexpected end of filter")
    token <- tokens[[position]]
    position <<- position + 1L
    token
  }
  test <- function(name) {
    type <- field_type_of(name)
    if (is.null(type)) filter_error(paste("unknown field", name))
    if (!(next_kind() %in% c("==", "!=", "<", ">", "<=", ">="))) return(list(kind = "exists", field = name))
    operator <- take()$kind
    if (type == "presence" || (type == "string" && !(operator %in% c("==", "!=")))) filter_error(paste(
        "operator",
        operator,
        "not allowed for",
        name
    ))
    token <- take()
    if (!(token$kind %in% c("word", "string"))) unexpected(token)
    value <- parse_filter_value(type, token)
    if (is.null(value)) filter_error(paste("invalid value", token$text, "for", name))
    list(kind = "compare", field = name, operator = operator, value = value)
  }
  negation <- function() {
    if (next_kind() == "!") {
      take()
      return(list(kind = "not", left = negation()))
    }
    token <- take()
    if (token$kind == "(") {
      node <- expression_node()
      closing <- take()
      if (closing$kind != ")") unexpected(closing)
      return(node)
    }
    if (token$kind != "word") unexpected(token)
    test(token$text)
  }
  product <- function() {
    node <- negation()
    while (next_kind() == "&&") {
      take()
      node <- list(kind = "and", left = node, right = negation())
    }
    node
  }
  expression_node <- function() {
    node <- product()
    while (next_kind() == "||") {
      take()
      node <- list(kind = "or", left = node, right = product())
    }
    node
  }
  node <- expression_node()
  if (position <= length(tokens)) unexpected(tokens[[position]])
  node
}
compare_value <- function(left, operator, right) {
  switch(operator, "==" = left == right, "<" = left < right, ">" = left > right,
         "<=" = left <= right, ">=" = left >= right)
}
evaluate <- function(node, packet) {
  if (node$kind == "or") return(evaluate(node$left, packet) || evaluate(node$right, packet))
  if (node$kind == "and") return(evaluate(node$left, packet) && evaluate(node$right, packet))
  if (node$kind == "not") return(!evaluate(node$left, packet))
  if (node$kind == "exists") {
    if (node$field %in% unlist(PROTOCOL_FIELDS)) node$field %in% packet$layers else length(filter_field_values(
        packet,
        node$field
    )) > 0L
  } else {
    values <- filter_field_values(packet, node$field)
    if (!length(values)) return(FALSE)
    if (node$operator == "!=") all(vapply(values, function(value) value != node$value, FALSE)) else any(vapply(
        values,
        function(value) compare_value(value, node$operator, node$value),
        FALSE
    ))
  }
}
filter_block <- function(expression, packets, summaries) {
  lines <- c("", paste("filter", expression))
  tree <- tryCatch(parse_filter(expression), filter_error = function(error) error)
  if (inherits(tree, "filter_error")) return(c(lines, paste0("error: ", conditionMessage(tree))))
  matched <- which(vapply(packets, function(packet) evaluate(tree, packet), FALSE))
  c(lines, summaries[matched], paste("matched", length(matched), "of", length(packets)))
}
detail_lines <- function(packets, number) {
  if (number < 1 || number > length(packets)) return(paste("packet", integer_text(number), "not found"))
  packet <- packets[[number]]
  lines <- paste("packet", integer_text(number))
  for (layer in c("frame", packet$layers)) {
    lines <- c(lines, layer)
    for (field in FIELDS) {
      name <- field[[1L]]
      type <- field[[2L]]
      if (!startsWith(name, paste0(layer, "."))) next
      for (value in field_values(packet, name)) {
        lines <- c(
            lines,
            if (type == "presence") paste0("  ", name) else paste0("  ", name, " = ", notation(type, value))
        )
      }
    }
    if (layer == "data") lines <- c(lines, paste0("  ", hex_dump_lines(packet$remaining)))
  }
  lines
}
dns_transactions <- function(packets) {
  queries <- responses <- pending <- list()
  times <- numeric()
  for (packet in packets) {
    if (!field_exists(packet, "dns.id")) next
    if (packet_value(packet, "dns.flags.response") == 0) {
      queries[[length(queries) + 1L]] <- packet
      pending[[length(pending) + 1L]] <- packet
    } else {
      responses[[length(responses) + 1L]] <- packet
      for (index in seq_along(pending)) {
        query <- pending[[index]]
        pairs <- list(
            c("dns.id", "dns.id"),
            c("ip.src", "ip.dst"),
            c("udp.srcport", "udp.dstport"),
            c("ip.dst", "ip.src"),
            c("udp.dstport", "udp.srcport")
        )
        if (all(vapply(
            pairs,
            function(pair) packet_value(query, pair[[1L]]) == packet_value(packet, pair[[2L]]),
            FALSE
        ))) {
          times <- c(times, packet$time - query$time)
          pending <- pending[-index]
          break
        }
      }
    }
  }
  list(queries = queries, responses = responses, times = times, unanswered = length(pending))
}
protocol_stats_lines <- function(packets, transactions) {
  lines <- c(paste("packets", length(packets)), paste("bytes", sum(vapply(packets, function(packet) packet$length, 0))),
             paste("duration", seconds(tail(packets, 1L)[[1L]]$time - packets[[1L]]$time)), "hierarchy")
  for (entry in HIERARCHY) {
    name <- entry[[1L]]
    members <- Filter(function(packet) name %in% packet$layers, packets)
    total <- sum(vapply(members, function(packet) packet$length, 0))
    lines <- c(lines, paste0(strrep(" ", entry[[2L]]), name, " ", length(members), " ", integer_text(total)))
  }
  lines <- c(lines, "checksums")
  for (entry in CHECKSUM_LAYERS) {
    layer <- entry[[1L]]
    count_status <- function(status) sum(vapply(
        packets,
        function(packet) identical(packet_value(packet, paste0(layer, ".checksum.status")), status),
        FALSE
    ))
    text <- paste(layer, "good", count_status("good"), "bad", count_status("bad"))
    if (layer == "udp") text <- paste(text, "none", count_status("none"))
    lines <- c(lines, text)
  }
  lines <- c(
      lines,
      "malformed",
      paste("dump", sum(vapply(packets, function(packet) !is.null(packet$error), FALSE)))
  )
  for (name in unlist(PROTOCOL_FIELDS)[1L:7L]) {
    count <- sum(vapply(
        packets,
        function(packet) is.null(packet$error) && field_exists(
            packet,
            "frame.malformed"
        ) && tail(packet$layers, 1L) == name,
        FALSE
    ))
    lines <- c(lines, paste(name, count))
  }
  lines <- c(lines, "tcp analysis")
  for (mark in MARKS) lines <- c(
      lines,
      paste(
          mark,
          sum(vapply(packets, function(packet) field_exists(packet, paste0("tcp.analysis.", mark)), FALSE))
      )
  )
  lines <- c(lines, "dns", paste("queries", length(transactions$queries)), paste("responses", length(transactions$responses)),
             paste("transactions", length(transactions$times)), paste("unanswered", transactions$unanswered))
  times <- transactions$times
  lines <- c(
      lines,
      if (length(times)) paste(
          "response_time min",
          seconds(min(times)),
          "max",
          seconds(max(times))
      ) else "response_time -"
  )
  for (rcode in 0L:15L) {
    total <- sum(vapply(
        transactions$responses,
        function(packet) packet_value(packet, "dns.flags.rcode") == rcode,
        FALSE
    ))
    if (total) lines <- c(lines, paste("rcode", rcode_name(rcode), total))
  }
  lines <- c(lines, "names")
  counts <- integer()
  for (query in transactions$queries) {
    for (name in field_values(query, "dns.qry.name")) {
      if (!(name %in% names(counts))) counts[[name]] <- 0L
      counts[[name]] <- counts[[name]] + 1L
    }
  }
  if (length(counts)) {
    for (i in order(-counts, names(counts), method = "radix")) lines <- c(
        lines,
        paste(names(counts)[[i]], counts[[i]])
    )
  }
  lines
}
conversation_lines <- function(conversations, base_time) {
  lines <- CONVERSATION_HEADER
  for (flow in conversations) {
    row <- c(flow$kind, endpoint_text(flow$endpoint_a), endpoint_text(flow$endpoint_b),
             integer_text(c(
                 flow_packets(flow),
                 flow_bytes(flow),
                 flow$packets_a_to_b,
                 flow$bytes_a_to_b,
                 flow$packets_b_to_a,
                 flow$bytes_b_to_a
             )),
             seconds(flow$first_time - base_time), seconds(flow$last_time - flow$first_time))
    lines <- c(lines, paste(row, collapse = ","))
  }
  lines
}
endpoint_lines <- function(endpoints) {
  lines <- ENDPOINT_HEADER
  for (endpoint in endpoints) {
    row <- c(
        ipv4_notation(endpoint$address),
        integer_text(c(
            endpoint_packets(endpoint),
            endpoint_bytes(endpoint),
            endpoint$tx_packets,
            endpoint$tx_bytes,
            endpoint$rx_packets,
            endpoint$rx_bytes
        ))
    )
    lines <- c(lines, paste(row, collapse = ","))
  }
  lines
}
side_line <- function(side) {
  paste(
      side$name,
      "packets",
      side$packets,
      "payload",
      integer_text(side$payload),
      paste(paste(MARKS, side$marks[MARKS]), collapse = " ")
  )
}
stream_lines <- function(stream, packets) {
  client <- stream$client_side
  server <- stream$server_side
  rtt <- if (is.null(stream$syn) || is.null(stream$handshake_ack)) "-" else seconds(packets[[stream$handshake_ack]]$time - packets[[stream$syn]]$time)
  states <- vapply(stream$history, function(entry) paste(entry[[1L]], integer_text(entry[[2L]])), "")
  lines <- c(paste("stream", stream$number, endpoint_text(stream$client), "->", endpoint_text(stream$server)),
             paste(
                 "packets",
                 stream$packets,
                 "bytes",
                 integer_text(stream$bytes),
                 "start",
                 seconds(stream$start_time - packets[[1L]]$time),
                 "duration",
                 seconds(stream$end_time - stream$start_time)
             ),
             paste("states", paste(states, collapse = ", ")),
             paste(
                 "handshake syn",
                 optional(stream$syn),
                 "syn_ack",
                 optional(stream$syn_ack),
                 "ack",
                 optional(stream$handshake_ack),
                 "rtt",
                 rtt
             ),
             paste(
                 "options client mss",
                 optional(client$mss),
                 "wscale",
                 optional(client$wscale),
                 "server mss",
                 optional(server$mss),
                 "wscale",
                 optional(server$wscale)
             ),
             side_line(client), side_line(server))
  for (event in stream$events) lines <- c(
      lines,
      paste(
          "event",
          event[[1L]],
          event[[2L]],
          event[[3L]],
          "seq",
          integer_text(event[[4L]]),
          "len",
          integer_text(event[[5L]])
      )
  )
  lines
}
joined_blocks <- function(blocks) {
  lines <- character()
  for (index in seq_along(blocks)) {
    if (index > 1L) lines <- c(lines, "")
    lines <- c(lines, blocks[[index]])
  }
  lines
}
main <- function() {
  packets <- read_capture(file.path("input", "capture.txt"))
  filters <- character()
  detail_numbers <- numeric()
  for (line in readLines(file.path("input", "filters.txt"), warn = FALSE)) {
    if (startsWith(line, "FILTER ")) filters <- c(filters, substring(line, 8L))
    if (startsWith(line, "DETAIL ")) detail_numbers <- c(detail_numbers, as.numeric(substring(line, 8L)))
  }
  base_time <- packets[[1L]]$time
  for (packet in packets) dissect(packet, base_time)
  tracker <- new_tracker()
  for (packet in packets) if (field_exists(packet, "tcp.srcport")) track(tracker, packet)
  summaries <- vapply(packets, function(packet) summary_line(packet, tracker$duplicate_acks), "")
  summary <- summaries
  for (expression in filters) summary <- c(summary, filter_block(expression, packets, summaries))
  outputs <- list(
    "summary.txt" = summary,
    "details.txt" = joined_blocks(lapply(detail_numbers, function(number) detail_lines(packets, number))),
    "conversations.csv" = conversation_lines(build_conversations(packets), base_time),
    "endpoints.csv" = endpoint_lines(build_endpoints(packets)),
    "protocol_stats.txt" = protocol_stats_lines(packets, dns_transactions(packets)),
    "tcp_streams.txt" = joined_blocks(lapply(tracker$streams, function(stream) stream_lines(stream, packets)))
  )
  dir.create("output", showWarnings = FALSE)
  for (name in names(outputs)) writeLines(outputs[[name]], file.path("output", name), useBytes = TRUE)
}
main()
