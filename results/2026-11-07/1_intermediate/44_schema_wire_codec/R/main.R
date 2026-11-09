wire_types <- c(uint32 = 0, uint64 = 0, sint32 = 0, sint64 = 0, bool = 0,
                fixed32 = 5, sfixed32 = 5, fixed64 = 1, string = 2, bytes = 2)
ranges <- list(uint32 = c(0, 4294967295), uint64 = c(0, 9007199254740991),
               sint32 = c(-2147483648, 2147483647),
               sint64 = c(-4503599627370496, 4503599627370495),
               fixed32 = c(0, 4294967295), sfixed32 = c(-2147483648, 2147483647),
               fixed64 = c(0, 9007199254740991))
wire_names <- c("0" = "varint", "1" = "i64", "2" = "len", "5" = "i32")
decimal <- function(x) sprintf("%.0f", if (x == 0) 0 else x)
fail <- function(reason) {
  stop(structure(list(message = reason, call = NULL),
                 class = c("command_error", "error", "condition")))
}
byte_error <- function(reason, offset) fail(paste(reason, "at byte", decimal(offset)))
column_error <- function(reason, column) fail(paste(reason, "at column", column))

number_fits <- function(text, low, high) {
  negative <- startsWith(text, "-")
  digits <- if (negative) substring(text, 2) else text
  digits <- sub("^0+", "", digits)
  if (digits == "") return(TRUE)
  limit <- if (negative) -low else high
  if (limit < 0) return(FALSE)
  bound <- decimal(limit)
  nchar(digits) < nchar(bound) ||
    (nchar(digits) == nchar(bound) && digits <= bound)
}
zigzag <- function(x) if (x >= 0) 2 * x else -2 * x - 1
unzigzag <- function(x) if (x %% 2 == 0) x / 2 else -(floor(x / 2) + 1)
varint_bytes <- function(x) {
  result <- integer()
  while (x >= 128) {
    result <- c(result, x %% 128 + 128)
    x <- floor(x / 128)
  }
  c(result, x)
}
little_bytes <- function(x, size) {
  result <- numeric(size)
  for (i in seq_len(size)) {
    result[i] <- x %% 256
    x <- floor(x / 256)
  }
  result
}
hex_digits <- function(data) paste(sprintf("%02x", as.integer(data)), collapse = "")
hex_text <- function(data) if (length(data)) hex_digits(data) else "-"
hex_bytes <- function(text) {
  if (!nchar(text)) return(integer())
  positions <- seq.int(1L, nchar(text), by = 2L)
  strtoi(substring(text, positions, positions + 1L), 16L)
}
parse_hex <- function(text) {
  if (text == "-") return(integer())
  if (!grepl("^([0-9a-f]{2})+$", text)) fail("invalid hex")
  hex_bytes(text)
}
quote_bytes <- function(data, json = FALSE) {
  parts <- vapply(data, function(b) {
    if (b == 34) return('\\"')
    if (b == 92) return("\\\\")
    if (b == 10) return("\\n")
    if (b == 9) return("\\t")
    if (b >= 32 && b <= 126) return(intToUtf8(b))
    paste0(if (json) "\\u00" else "\\x", sprintf("%02x", as.integer(b)))
  }, character(1))
  paste0('"', paste(parts, collapse = ""), '"')
}
base64_text <- function(data) {
  alphabet <- strsplit("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/", "")[[1]]
  result <- character()
  if (length(data)) for (i in seq.int(1L, length(data), by = 3L)) {
    size <- min(3L, length(data) - i + 1L)
    block <- c(data[seq.int(i, i + size - 1L)], rep(0, 3L - size))
    n <- block[1] * 65536 + block[2] * 256 + block[3]
    indices <- c(floor(n / 262144), floor(n / 4096) %% 64,
                 floor(n / 64) %% 64, n %% 64) + 1L
    chars <- alphabet[indices]
    if (size < 3L) chars[seq.int(size + 2L, 4L)] <- "="
    result <- c(result, chars)
  }
  paste(result, collapse = "")
}

input <- readLines(file("stdin"), warn = FALSE)
enums <- list()
messages <- list()
line_index <- 1L
repeat {
  words <- strsplit(input[line_index], " ", fixed = TRUE)[[1]]
  line_index <- line_index + 1L
  if (identical(words, c("END", "SCHEMA"))) break
  if (words[1] == "ENUM") {
    current <- words[2]
    enums[[current]] <- numeric()
  } else if (words[1] == "MESSAGE") {
    current <- words[2]
    messages[[current]] <- list(fields = list())
  } else if (words[1] == "VALUE") {
    enums[[current]][words[2]] <- as.numeric(words[3])
  } else if (words[1] == "FIELD") {
    options <- if (length(words) > 4L) words[-seq_len(4L)] else character()
    field <- list(number = as.numeric(words[2]), type = words[3], name = words[4],
                  required = "REQUIRED" %in% options, repeated = "REPEATED" %in% options,
                  packed = "PACKED" %in% options,
                  group = if ("ONEOF" %in% options) options[2] else "")
    messages[[current]]$fields[[field$name]] <- field
  }
}
for (type in names(messages)) {
  fields <- messages[[type]]$fields
  if (length(fields)) fields <- fields[order(vapply(fields, `[[`, numeric(1), "number"))]
  for (name in names(fields)) {
    f <- fields[[name]]
    if (f$type %in% names(wire_types)) {
      f$wire <- unname(wire_types[f$type])
      f$kind <- if (f$type %in% names(ranges)) "integer" else f$type
    } else {
      f$kind <- if (f$type %in% names(enums)) "enum" else "message"
      f$wire <- if (f$kind == "enum") 0 else 2
    }
    fields[[name]] <- f
  }
  messages[[type]]$fields <- fields
  messages[[type]]$by_number <- setNames(fields, vapply(fields, function(f) decimal(f$number), character(1)))
}
new_message <- function(type) list(type = type, values = list(), unknown = list())
has_field <- function(m, f) f$name %in% names(m$values)
items <- function(m, f) {
  if (!has_field(m, f)) return(list())
  if (f$repeated) m$values[[f$name]] else list(m$values[[f$name]])
}
set_items <- function(m, f, values) {
  if (length(values)) m$values[f$name] <- list(values) else m$values[[f$name]] <- NULL
  m
}
remove_group <- function(m, f) {
  if (nzchar(f$group)) for (other in messages[[m$type]]$fields) {
    if (other$group == f$group && other$name != f$name) m$values[[other$name]] <- NULL
  }
  m
}
apply_values <- function(m, f, values) {
  m <- remove_group(m, f)
  if (f$repeated) return(set_items(m, f, c(items(m, f), values)))
  value <- values[[1]]
  if (f$kind == "message" && has_field(m, f)) value <- merge_message(m$values[[f$name]], value)
  m$values[f$name] <- list(value)
  m
}
merge_message <- function(a, b) {
  for (f in messages[[b$type]]$fields) if (has_field(b, f)) a <- apply_values(a, f, items(b, f))
  a$unknown <- c(a$unknown, b$unknown)
  a
}
check_required <- function(m, prefix = "") {
  for (f in messages[[m$type]]$fields) {
    if (f$required && !has_field(m, f)) fail(paste0("missing required field ", prefix, f$name))
    if (f$kind == "message") {
      values <- items(m, f)
      for (i in seq_along(values)) {
        suffix <- if (f$repeated) paste0("[", i - 1L, "]") else ""
        check_required(values[[i]], paste0(prefix, f$name, suffix, "."))
      }
    }
  }
  invisible(NULL)
}
element_bytes <- function(f, value) {
  if (f$wire == 2) {
    payload <- if (f$kind == "message") encode_message(value) else value
    return(c(varint_bytes(length(payload)), payload))
  }
  if (f$wire == 5) return(little_bytes(if (value < 0) value + 4294967296 else value, 4L))
  if (f$wire == 1) return(little_bytes(value, 8L))
  if (f$kind == "bool") value <- as.numeric(value)
  if (f$type %in% c("sint32", "sint64")) value <- zigzag(value)
  varint_bytes(value)
}
field_records <- function(f, values) {
  if (f$packed) {
    payload <- unlist(lapply(values, function(v) element_bytes(f, v)), use.names = FALSE)
    return(c(varint_bytes(f$number * 8 + 2), varint_bytes(length(payload)), payload))
  }
  tag <- varint_bytes(f$number * 8 + f$wire)
  unlist(lapply(values, function(v) c(tag, element_bytes(f, v))), use.names = FALSE)
}
encode_message <- function(m) {
  result <- numeric()
  for (f in messages[[m$type]]$fields) if (has_field(m, f)) result <- c(result, field_records(f, items(m, f)))
  for (u in m$unknown) {
    value <- if (u$wire == 0) varint_bytes(u$raw) else if (u$wire == 2) c(varint_bytes(length(u$raw)), u$raw) else u$raw
    result <- c(result, varint_bytes(u$number * 8 + u$wire), value)
  }
  result
}
unknown_notation <- function(u) if (u$wire == 0) decimal(u$raw) else paste0("<", hex_digits(u$raw), ">")
value_notation <- function(f, value) {
  if (f$kind == "message") return(message_notation(value))
  if (f$kind == "enum") return(names(enums[[f$type]])[match(value, enums[[f$type]])])
  if (f$kind == "bool") return(if (value) "true" else "false")
  if (f$kind == "string") return(quote_bytes(value))
  if (f$kind == "bytes") return(paste0("<", hex_digits(value), ">"))
  decimal(value)
}
list_notation <- function(f, values) paste0("[", paste(vapply(values, function(v) value_notation(f, v), character(1)), collapse = ", "), "]")
message_notation <- function(m) {
  parts <- character()
  for (f in messages[[m$type]]$fields) if (has_field(m, f)) {
    value <- if (f$repeated) list_notation(f, items(m, f)) else value_notation(f, m$values[[f$name]])
    parts <- c(parts, paste0(f$name, ": ", value))
  }
  paste0("{", paste(parts, collapse = ", "), "}")
}
json_value <- function(f, value) {
  if (f$kind == "message") return(json_message(value))
  if (f$kind == "enum") return(paste0('"', value_notation(f, value), '"'))
  if (f$kind == "bool") return(if (value) "true" else "false")
  if (f$kind == "string") return(quote_bytes(value, TRUE))
  if (f$kind == "bytes") return(paste0('"', base64_text(value), '"'))
  if (f$type %in% c("uint64", "sint64", "fixed64")) return(paste0('"', decimal(value), '"'))
  decimal(value)
}
json_message <- function(m) {
  parts <- character()
  for (f in messages[[m$type]]$fields) if (has_field(m, f)) {
    key_parts <- strsplit(f$name, "_", fixed = TRUE)[[1]]
    key <- key_parts[1]
    if (length(key_parts) > 1L) for (p in key_parts[-1L]) key <- paste0(key, toupper(substr(p, 1L, 1L)), substring(p, 2L))
    values <- vapply(items(m, f), function(v) json_value(f, v), character(1))
    text <- if (f$repeated) paste0("[", paste(values, collapse = ","), "]") else values[1]
    parts <- c(parts, paste0('"', key, '":', text))
  }
  paste0("{", paste(parts, collapse = ","), "}")
}
text_contents <- function(m, depth) {
  indent <- strrep("  ", depth)
  result <- character()
  for (f in messages[[m$type]]$fields) for (value in items(m, f)) {
    if (f$kind == "message") result <- c(result, paste0(indent, f$name, " {"), text_contents(value, depth + 1L), paste0(indent, "}"))
    else result <- c(result, paste0(indent, f$name, ": ", value_notation(f, value)))
  }
  for (u in m$unknown) result <- c(result, paste0(indent, decimal(u$number), ": ", wire_names[decimal(u$wire)], " ", unknown_notation(u)))
  result
}
text_message <- function(m) c(paste0(m$type, " {"), text_contents(m, 1L), "}")

read_wire <- function(type, data, explaining = FALSE) {
  lines <- character()
  slice <- function(start, end) if (end > start) data[seq.int(start + 1L, end)] else integer()
  read_varint <- function(start, end) {
    value <- 0
    position <- start
    for (i in seq_len(8L)) {
      if (position >= end) byte_error("truncated varint", start)
      b <- data[position + 1L]
      position <- position + 1L
      if (i == 8L) {
        if (b >= 128) byte_error("varint too long", start)
        if (b >= 16) byte_error("varint too large", start)
      }
      value <- value + (b %% 128) * 128^(i - 1L)
      if (b < 128) return(list(value = value, position = position))
    }
  }
  read_fixed <- function(start, end, wire) {
    size <- if (wire == 1) 8L else 4L
    if (end - start < size) byte_error(paste("truncated", wire_names[decimal(wire)]), start)
    list(value = slice(start, start + size), position = start + size)
  }
  scalar <- function(f, raw, position) {
    if (f$kind == "string") {
      bad <- which(raw >= 128)
      if (length(bad)) byte_error("invalid string", position + bad[1] - 1L)
      return(raw)
    }
    if (f$kind == "bytes") return(raw)
    if (f$wire != 0) {
      if (f$wire == 1 && (raw[8] != 0 || raw[7] >= 32)) byte_error("value out of range", position)
      raw <- sum(raw * 256^(seq_along(raw) - 1L))
    }
    if (f$kind == "bool") {
      if (raw > 1) byte_error("value out of range", position)
      return(raw == 1)
    }
    if (f$kind == "enum") {
      if (!(raw %in% enums[[f$type]])) byte_error("unknown enum number", position)
      return(raw)
    }
    value <- raw
    if (f$type %in% c("sint32", "sint64")) value <- unzigzag(raw)
    if (f$type == "sfixed32" && value >= 2147483648) value <- value - 4294967296
    bounds <- ranges[[f$type]]
    if (value < bounds[1] || value > bounds[2]) byte_error("value out of range", position)
    value
  }
  read_message <- function(type, start, end, depth) {
    m <- new_message(type)
    position <- start
    while (position < end) {
      record_start <- position
      tag <- read_varint(position, end)
      position <- tag$position
      number <- floor(tag$value / 8)
      wire <- tag$value %% 8
      if (number == 0) byte_error("invalid field number", record_start)
      if (!(wire %in% c(0, 1, 2, 5))) byte_error("invalid wire type", record_start)
      f <- messages[[type]]$by_number[[decimal(number)]]
      packed <- !is.null(f) && f$repeated && f$wire != 2 && wire == 2
      if (!is.null(f) && wire != f$wire && !packed) byte_error("wire type mismatch", record_start)
      value_start <- position
      if (wire == 0) {
        read <- read_varint(position, end)
        raw <- read$value
        position <- read$position
      } else if (wire == 2) {
        length_start <- position
        read <- read_varint(position, end)
        value_start <- read$position
        if (read$value > end - value_start) byte_error("length past end", length_start)
        position <- value_start + read$value
        raw <- slice(value_start, position)
      } else {
        read <- read_fixed(position, end, wire)
        raw <- read$value
        position <- read$position
      }
      name <- if (is.null(f)) "?" else f$name
      header <- paste0(strrep("  ", depth), decimal(record_start), " ", decimal(number), " ", name, " ", wire_names[decimal(wire)])
      if (wire == 2) header <- paste(header, length(raw))
      if (is.null(f)) {
        u <- list(number = number, wire = wire, raw = raw)
        m$unknown <- c(m$unknown, list(u))
        if (explaining) lines <<- c(lines, paste(header, unknown_notation(u)))
      } else {
        if (f$kind == "message") {
          if (explaining) lines <<- c(lines, header)
          values <- list(read_message(f$type, value_start, position, depth + 1L))
        } else if (packed) {
          values <- list()
          p <- value_start
          while (p < position) {
            element_start <- p
            read <- if (f$wire == 0) read_varint(p, position) else read_fixed(p, position, f$wire)
            p <- read$position
            values <- c(values, list(scalar(f, read$value, element_start)))
          }
          if (explaining) {
            notations <- vapply(values, function(v) value_notation(f, v), character(1))
            lines <<- c(lines, paste(c(header, "packed", notations), collapse = " "))
          }
        } else {
          values <- list(scalar(f, raw, value_start))
          if (explaining) lines <<- c(lines, paste(header, value_notation(f, values[[1]])))
        }
        if (!explaining) m <- apply_values(m, f, values)
      }
    }
    m
  }
  m <- read_message(type, 0, length(data), 0L)
  if (explaining) return(if (length(lines)) lines else "(empty)")
  check_required(m)
  m
}

tokenize <- function(text) {
  chars <- strsplit(text, "", fixed = TRUE)[[1]]
  n <- length(chars)
  result <- list()
  p <- 1L
  add <- function(kind, column, text = "", value = NULL) {
    result[[length(result) + 1L]] <<- list(kind = kind, column = column, text = text, value = value)
  }
  while (p <= n) {
    ch <- chars[p]
    start <- p
    if (ch == " ") {
      p <- p + 1L
    } else if (ch %in% c("{", "}", "[", "]", ":", ",")) {
      add("symbol", p, ch)
      p <- p + 1L
    } else if (ch == '"') {
      p <- p + 1L
      bytes <- integer()
      while (p <= n && chars[p] != '"') {
        if (chars[p] != "\\") {
          bytes <- c(bytes, utf8ToInt(chars[p]))
          p <- p + 1L
        } else {
          if (p + 1L > n) column_error("syntax error", start)
          escape <- chars[p + 1L]
          escapes <- c('"' = 34L, "\\" = 92L, n = 10L, t = 9L)
          if (escape %in% names(escapes)) {
            bytes <- c(bytes, unname(escapes[escape]))
            p <- p + 2L
          } else if (escape == "x" && p + 3L <= n) {
            code <- paste(chars[seq.int(p + 2L, p + 3L)], collapse = "")
            if (!grepl("^[0-7][0-9a-f]$", code)) column_error("syntax error", start)
            bytes <- c(bytes, strtoi(code, 16L))
            p <- p + 4L
          } else column_error("syntax error", start)
        }
      }
      if (p > n) column_error("syntax error", start)
      add("string", start, value = bytes)
      p <- p + 1L
    } else if (ch == "<") {
      p <- p + 1L
      first <- p
      while (p <= n && chars[p] != ">") p <- p + 1L
      if (p > n) column_error("syntax error", start)
      code <- if (p > first) paste(chars[seq.int(first, p - 1L)], collapse = "") else ""
      if (!grepl("^([0-9a-f]{2})*$", code)) column_error("syntax error", start)
      add("bytes", start, value = hex_bytes(code))
      p <- p + 1L
    } else if (ch == "-" || grepl("^[0-9]$", ch)) {
      if (ch == "-") p <- p + 1L
      first <- p
      while (p <= n && grepl("^[0-9]$", chars[p])) p <- p + 1L
      if (p == first) column_error("syntax error", start)
      add("integer", start, paste(chars[seq.int(start, p - 1L)], collapse = ""))
    } else if (grepl("^[A-Za-z_]$", ch)) {
      p <- p + 1L
      while (p <= n && grepl("^[A-Za-z0-9_]$", chars[p])) p <- p + 1L
      add("name", start, paste(chars[seq.int(start, p - 1L)], collapse = ""))
    } else column_error("syntax error", p)
  }
  add("end", n + 1L)
  result
}
parse_literal <- function(text, type = NULL, field = NULL, whole = FALSE) {
  tokens <- tokenize(text)
  position <- 1L
  peek <- function() tokens[[position]]
  take <- function() {
    token <- peek()
    position <<- position + 1L
    token
  }
  at <- function(symbol) peek()$kind == "symbol" && peek()$text == symbol
  syntax <- function(reason = "syntax error") column_error(reason, peek()$column)
  expect <- function(symbol) {
    if (!at(symbol)) syntax()
    take()
  }
  shape <- function(token) {
    if (token$kind == "symbol") return(switch(token$text, "{" = "message", "[" = "list", ""))
    if (token$kind == "end") return("")
    if (token$kind == "name") return(if (token$text %in% c("true", "false")) "boolean" else "name")
    token$kind
  }
  element <- function(f) {
    token <- peek()
    token_shape <- shape(token)
    needed <- c(integer = "integer", bool = "boolean", enum = "name", string = "string", bytes = "bytes", message = "message")[[f$kind]]
    if (token_shape == "") syntax()
    if (token_shape != needed) syntax("type mismatch")
    if (token_shape == "message") return(message(f$type))
    take()
    if (token_shape == "integer") {
      bounds <- ranges[[f$type]]
      if (!number_fits(token$text, bounds[1], bounds[2])) column_error("out of range", token$column)
      return(as.numeric(token$text))
    }
    if (token_shape == "boolean") return(token$text == "true")
    if (token_shape == "name") {
      if (!(token$text %in% names(enums[[f$type]]))) column_error("unknown enum value", token$column)
      return(unname(enums[[f$type]][token$text]))
    }
    token$value
  }
  field_value <- function(f) {
    if (!f$repeated) return(element(f))
    token_shape <- shape(peek())
    if (token_shape == "") syntax()
    if (token_shape != "list") syntax("type mismatch")
    take()
    values <- list()
    if (!at("]")) {
      values <- list(element(f))
      while (at(",")) {
        take()
        values <- c(values, list(element(f)))
      }
    }
    expect("]")
    values
  }
  message <- function(type) {
    expect("{")
    m <- new_message(type)
    seen <- character()
    groups <- character()
    if (!at("}")) repeat {
      token <- peek()
      if (token$kind != "name") syntax()
      f <- messages[[type]]$fields[[token$text]]
      if (is.null(f)) syntax("unknown field")
      if (f$name %in% seen) syntax("duplicate field")
      if (nzchar(f$group) && f$group %in% groups) syntax("oneof conflict")
      take()
      seen <- c(seen, f$name)
      if (nzchar(f$group)) groups <- c(groups, f$group)
      expect(":")
      value <- field_value(f)
      if (f$repeated) m <- set_items(m, f, value) else m$values[f$name] <- list(value)
      if (!at(",")) break
      take()
    }
    closing <- expect("}")
    for (f in messages[[type]]$fields) if (f$required && !(f$name %in% seen)) column_error(paste("missing required field", f$name), closing$column)
    m
  }
  value <- if (!is.null(type)) message(type) else if (whole) field_value(field) else element(field)
  if (peek()$kind != "end") syntax()
  value
}

parse_path <- function(type, text) {
  if (!grepl("^[a-z][a-z0-9_]*(\\[[0-9]{1,6}\\])?(\\.[a-z][a-z0-9_]*(\\[[0-9]{1,6}\\])?)*$", text)) fail("invalid path")
  parts <- strsplit(text, ".", fixed = TRUE)[[1]]
  result <- list()
  for (i in seq_along(parts)) {
    name <- sub("\\[.*$", "", parts[i])
    index <- if (grepl("[", parts[i], fixed = TRUE)) as.numeric(sub("^.*\\[([0-9]+)\\]$", "\\1", parts[i])) else NULL
    f <- messages[[type]]$fields[[name]]
    if (is.null(f) || (!is.null(index) && !f$repeated)) fail("invalid path")
    result[[i]] <- list(field = f, index = index)
    if (i < length(parts)) {
      if (f$kind != "message" || (f$repeated && is.null(index))) fail("invalid path")
      type <- f$type
    }
  }
  result
}
whole_segment <- function(segment) segment$field$repeated && is.null(segment$index)
get_path <- function(m, path) {
  last <- path[[length(path)]]
  for (segment in head(path, -1L)) {
    values <- items(m, segment$field)
    index <- if (is.null(segment$index)) 1L else segment$index + 1L
    if (index > length(values)) return(if (whole_segment(last)) "[]" else "(none)")
    m <- values[[index]]
  }
  values <- items(m, last$field)
  if (whole_segment(last)) return(list_notation(last$field, values))
  index <- if (is.null(last$index)) 1L else last$index + 1L
  if (index > length(values)) "(none)" else value_notation(last$field, values[[index]])
}
change_path <- function(m, path, value = NULL, clear = FALSE, level = 1L) {
  segment <- path[[level]]
  f <- segment$field
  values <- items(m, f)
  index <- if (is.null(segment$index)) 1L else segment$index + 1L
  if (level == length(path)) {
    if (clear) {
      if (is.null(segment$index)) m$values[[f$name]] <- NULL
      else if (index <= length(values)) m <- set_items(m, f, values[-index])
    } else if (whole_segment(segment)) m <- set_items(m, f, value)
    else if (f$repeated) {
      if (index > length(values)) fail("index out of range")
      values[index] <- list(value)
      m <- set_items(m, f, values)
    } else {
      m <- remove_group(m, f)
      m$values[f$name] <- list(value)
    }
    return(m)
  }
  if (index > length(values)) {
    if (clear) return(m)
    if (f$repeated) fail("index out of range")
    m <- remove_group(m, f)
    values <- list(new_message(f$type))
  }
  child <- change_path(values[[index]], path, value, clear, level + 1L)
  if (f$repeated) {
    values[index] <- list(child)
    m <- set_items(m, f, values)
  } else m$values[f$name] <- list(child)
  m
}
compare_messages <- function(a, b, prefix = "") {
  result <- character()
  for (f in messages[[a$type]]$fields) {
    left <- items(a, f)
    right <- items(b, f)
    for (i in seq_len(max(length(left), length(right)))) {
      path <- paste0(prefix, f$name, if (f$repeated) paste0("[", i - 1L, "]") else "")
      both <- i <= length(left) && i <= length(right)
      if (both && f$kind == "message") result <- c(result, compare_messages(left[[i]], right[[i]], paste0(path, ".")))
      else if (!both || !isTRUE(all.equal(left[[i]], right[[i]], tolerance = 0, check.attributes = FALSE))) {
        old <- if (i <= length(left)) value_notation(f, left[[i]]) else "(none)"
        new <- if (i <= length(right)) value_notation(f, right[[i]]) else "(none)"
        result <- c(result, paste0(path, ": ", old, " -> ", new))
      }
    }
  }
  result
}
schema_fields <- function(type, chain, depth) {
  result <- character()
  for (f in messages[[type]]$fields) {
    kind <- if (f$required) "required " else if (f$packed) "repeated packed " else if (f$repeated) "repeated " else if (nzchar(f$group)) paste0("oneof ", f$group, " ") else ""
    line <- paste0(strrep("  ", depth), decimal(f$number), " ", f$name, ": ", kind, f$type)
    if (f$kind == "enum") {
      values <- sort(enums[[f$type]])
      line <- paste0(line, " (", paste(paste0(names(values), "=", vapply(values, decimal, character(1))), collapse = ", "), ")")
    }
    recursive <- f$kind == "message" && f$type %in% chain
    result <- c(result, paste0(line, if (recursive) " (recursive)" else ""))
    if (f$kind == "message" && !recursive) result <- c(result, schema_fields(f$type, c(chain, f$type), depth + 1L))
  }
  result
}
word_counts <- c(VARINT = 2L, ZIGZAG = 2L, SCHEMA = 2L, ENCODE = 3L, SIZE = 3L,
                 DECODE = 3L, LITERAL = 3L, JSON = 3L, CANON = 3L, EXPLAIN = 3L,
                 GET = 4L, PATCH = 5L, CLEAR = 4L, MERGE = 4L, DIFF = 4L)
text_after <- function(line, separator) {
  p <- gregexpr(" ", line, fixed = TRUE)[[1]][separator]
  substring(line, p + 1L)
}
execute <- function(line) {
  words <- strsplit(line, " ", fixed = TRUE)[[1]]
  command <- words[1]
  if (!(command %in% names(word_counts))) fail("unknown command")
  expected <- word_counts[[command]]
  variable <- command %in% c("ENCODE", "SIZE", "PATCH")
  if (length(words) < expected || (!variable && length(words) != expected)) fail("wrong number of arguments")
  if (command %in% c("VARINT", "ZIGZAG")) {
    bounds <- if (command == "VARINT") ranges$uint64 else ranges$sint64
    if (!grepl("^-?[0-9]{1,18}$", words[2]) || !number_fits(words[2], bounds[1], bounds[2])) fail("invalid number")
    value <- as.numeric(words[2])
    if (command == "VARINT") return(hex_text(varint_bytes(value)))
    value <- zigzag(value)
    return(paste(decimal(value), hex_text(varint_bytes(value))))
  }
  type <- words[2]
  if (!(type %in% names(messages))) fail("unknown message type")
  data <- list()
  if (!(command %in% c("SCHEMA", "ENCODE", "SIZE"))) {
    data <- list(parse_hex(words[3]))
    if (command %in% c("MERGE", "DIFF")) data[[2]] <- parse_hex(words[4])
  }
  if (command %in% c("GET", "PATCH", "CLEAR")) path <- parse_path(type, words[4])
  if (command == "SCHEMA") return(c(type, schema_fields(type, type, 1L)))
  if (command %in% c("ENCODE", "SIZE")) {
    m <- parse_literal(text_after(line, 2L), type = type)
    encoded <- encode_message(m)
    if (command == "ENCODE") return(hex_text(encoded))
    parts <- as.character(length(encoded))
    for (f in messages[[type]]$fields) if (has_field(m, f)) parts <- c(parts, paste0(f$name, "=", length(field_records(f, items(m, f)))))
    return(paste(parts, collapse = " "))
  }
  if (command == "EXPLAIN") return(read_wire(type, data[[1]], TRUE))
  if (command == "MERGE") return(text_message(read_wire(type, c(data[[1]], data[[2]]))))
  if (command == "DIFF") {
    a <- tryCatch(read_wire(type, data[[1]]), command_error = function(e) fail(paste(e$message, "in first")))
    b <- tryCatch(read_wire(type, data[[2]]), command_error = function(e) fail(paste(e$message, "in second")))
    differences <- compare_messages(a, b)
    return(if (length(differences)) differences else "SAME")
  }
  m <- read_wire(type, data[[1]])
  if (command == "DECODE") return(text_message(m))
  if (command == "LITERAL") return(message_notation(m))
  if (command == "JSON") return(json_message(m))
  if (command == "CANON") return(hex_text(encode_message(m)))
  if (command == "GET") return(get_path(m, path))
  if (command == "PATCH") {
    last <- path[[length(path)]]
    value <- parse_literal(text_after(line, 4L), field = last$field, whole = whole_segment(last))
    m <- change_path(m, path, value)
  } else if (command == "CLEAR") m <- change_path(m, path, clear = TRUE)
  check_required(m)
  hex_text(encode_message(m))
}
count <- as.integer(input[line_index])
output <- character()
for (i in seq_len(count)) {
  line <- input[line_index + i]
  result <- tryCatch(execute(line), command_error = function(e) paste("ERROR", e$message))
  output <- c(output, result)
}
writeLines(output)
