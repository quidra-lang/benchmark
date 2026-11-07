source("mime.R")
source("headers.R")
source("addresses.R")
source("dates.R")
source("threader.R")

checked_fields <- c("From", "To", "Cc", "Subject", "Date", "Message-ID", "In-Reply-To", "References",
                    "MIME-Version", "Content-Type", "Content-Transfer-Encoding", "Content-Disposition")
hidden_tags <- c("head", "style", "script")
paragraph_tags <- c("p", "div", "ul", "ol", "table", "tr", "blockquote", "h1", "h2", "h3", "h4", "h5", "h6")
character_references <- c(amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", nbsp = " ")

read_lines <- function(path) readLines(path, warn = FALSE)
find_after <- function(text, needle, start = 1L) {
  if (start > nchar(text)) return(-1L)
  position <- regexpr(needle, substring(text, start), fixed = TRUE)[1L]
  if (position < 0L) -1L else position + start - 1L
}
read_mailbox <- function(path) {
  messages <- list()
  lines <- read_lines(path)
  for (i in seq_along(lines)) {
    line <- lines[i]
    if (startsWith(line, "From ")) {
      messages[[length(messages) + 1L]] <- list()
      next
    }
    unquoted <- sub("^>+", "", line)
    if (unquoted != line && startsWith(unquoted, "From ")) line <- substring(line, 2L)
    if (length(messages) > 0L) {
      last <- length(messages)
      messages[[last]][[length(messages[[last]]) + 1L]] <- list(number = i, text = line)
    }
  }
  for (i in seq_along(messages)) {
    lines <- messages[[i]]
    if (length(lines) > 0L && lines[[length(lines)]]$text == "") messages[[i]] <- lines[-length(lines)]
  }
  messages
}
split_sections <- function(lines) {
  index <- which(vapply(lines, function(line) line$text == "", logical(1)))
  if (length(index) == 0L) return(list(header = lines, body = list()))
  first <- index[1L]
  list(header = if (first == 1L) list() else lines[seq_len(first - 1L)],
       body = if (first == length(lines)) list() else lines[seq.int(first + 1L, length(lines))])
}
is_message_id <- function(text) {
  if (nchar(text) < 3L || !startsWith(text, "<") || !endsWith(text, ">")) return(FALSE)
  inside <- substr(text, 2L, nchar(text) - 1L)
  letters <- chars(inside)
  if (sum(letters == "@") != 1L || startsWith(inside, "@") || endsWith(inside, "@")) return(FALSE)
  codes <- utf8ToInt(inside)
  all(codes >= 33L & codes <= 126L) && !any(letters %in% chars('<>()"\\'))
}
extract_ids <- function(value) {
  ids <- character()
  position <- 1L
  while (position <= nchar(value)) {
    start <- find_after(value, "<", position)
    if (start < 0L) break
    end <- find_after(value, ">", start + 1L)
    if (end < 0L) break
    id <- substr(value, start, end)
    if (is_message_id(id)) ids <- c(ids, id)
    position <- end + 1L
  }
  ids
}
date_notation <- function(date) if (is.null(date)) "invalid" else format_utc(date)
subject_notation <- function(subject) if (nzchar(subject)) subject else "(no subject)"
dash <- function(text) if (nzchar(text)) text else "-"
problem <- function(message, text) message$problems <- c(message$problems, text)

new_message <- function(number) {
  message <- new.env(parent = emptyenv())
  message$number <- number
  message$problems <- message$to <- message$cc <- message$references <- character()
  message$sender <- message$date <- message$body <- message$parent <- NULL
  message$subject <- message$base_subject <- message$id <- ""
  message$reply <- FALSE
  message$thread <- message$depth <- 0L
  message
}
read_recipients <- function(message, value, name) {
  if (is.null(value)) return(character())
  parsed <- parse_address_list(value)
  if (is.null(parsed)) {
    problem(message, paste("bad", name))
    return(character())
  }
  recipients <- character()
  for (address in parsed$addresses) {
    if (address$kind == "mailbox") {
      recipients <- c(recipients, address$address)
    } else {
      recipients <- c(recipients, vapply(address$mailboxes, function(mailbox) mailbox$address, character(1)))
    }
  }
  if (parsed$error) problem(message, paste("bad encoded word in", name))
  recipients
}
process_message <- function(message, lines, known_ids) {
  sections <- split_sections(lines)
  header <- parse_fields(sections$header)
  for (number in header$invalid) problem(message, paste("bad header line", number))
  for (name in checked_fields) if (header_count(header, name) > 1L) problem(message, paste("duplicate", name))
  value <- header_value(header, "From")
  if (is.null(value)) {
    problem(message, "missing From")
  } else {
    parsed <- parse_address_list(value)
    if (is.null(parsed) || length(parsed$addresses) != 1L || parsed$addresses[[1L]]$kind != "mailbox") {
      problem(message, "bad From")
    } else {
      message$sender <- parsed$addresses[[1L]]
      if (parsed$error) problem(message, "bad encoded word in From")
    }
  }
  message$to <- read_recipients(message, header_value(header, "To"), "To")
  message$cc <- read_recipients(message, header_value(header, "Cc"), "Cc")
  value <- header_value(header, "Subject")
  decoded <- decode_unstructured(if (is.null(value)) "" else value)
  message$subject <- decoded$text
  if (decoded$error) problem(message, "bad encoded word in Subject")
  base <- message$subject
  while (startsWith(ascii_lower(base), "re:")) {
    base <- sub("^ +", "", substring(base, 4L))
    message$reply <- TRUE
  }
  message$base_subject <- base
  value <- header_value(header, "Date")
  if (is.null(value)) {
    problem(message, "missing Date")
  } else {
    parsed <- parse_date(value)
    message$date <- parsed$date
    if (nzchar(parsed$error)) problem(message, parsed$error)
  }
  value <- header_value(header, "Message-ID")
  if (is.null(value)) {
    problem(message, "missing Message-ID")
  } else if (!is_message_id(value)) {
    problem(message, "bad Message-ID")
  } else if (exists(value, envir = known_ids, inherits = FALSE)) {
    problem(message, paste("Message-ID already used by message", get(value, envir = known_ids)))
  } else {
    message$id <- value
    assign(value, message$number, envir = known_ids)
  }
  value <- header_value(header, "References")
  message$references <- extract_ids(if (is.null(value)) "" else value)
  value <- header_value(header, "In-Reply-To")
  replies <- extract_ids(if (is.null(value)) "" else value)
  if (length(replies) > 0L && (length(message$references) == 0L || tail(message$references, 1L) != replies[1L])) {
    message$references <- c(message$references, replies[1L])
  }
  mime <- FALSE
  value <- header_value(header, "MIME-Version")
  if (!is.null(value)) {
    text <- remove_comments(value)
    mime <- !is.null(text) && gsub("[ \t]", "", text) == "1.0"
    if (!mime) problem(message, "bad MIME-Version")
  }
  message$body <- parse_entity(message, "1", header, sections$body, mime)
}

parse_entity <- function(message, number, header, lines, mime) {
  entity <- list(number = number, main_type = "text", subtype = "plain", parameters = list(),
                 disposition = NULL, filename = NULL, children = NULL, content = "")
  value <- header_value(header, "Content-Type")
  if (mime && !is.null(value)) {
    parsed <- parse_parameters(value, TRUE)
    if (is.null(parsed)) {
      problem(message, paste("bad Content-Type in part", number))
    } else {
      entity$main_type <- parsed$main_type
      entity$subtype <- parsed$subtype
      entity$parameters <- parsed$parameters
    }
  }
  value <- header_value(header, "Content-Disposition")
  if (mime && !is.null(value)) {
    parsed <- parse_parameters(value, FALSE)
    if (is.null(parsed)) {
      problem(message, paste("bad Content-Disposition in part", number))
    } else {
      entity$disposition <- parsed$main_type
      entity$filename <- parsed$parameters[["filename"]]
    }
  }
  if (is.null(entity$filename) || !nzchar(entity$filename)) entity$filename <- entity$parameters[["name"]]
  charset <- entity$parameters[["charset"]]
  if (entity$main_type == "text" && !is.null(charset) && ascii_lower(charset) != "us-ascii") {
    problem(message, paste0('unsupported charset "', ascii_lower(charset), '" in part ', number))
  }
  if (mime && entity$main_type == "multipart") {
    boundary <- entity$parameters[["boundary"]]
    if (!is.null(boundary) && nzchar(boundary)) return(split_multipart(message, entity, lines, boundary))
    problem(message, paste("missing boundary in part", number))
  }
  original <- paste(vapply(lines, function(line) line$text, character(1)), collapse = "\n")
  encoding <- "7bit"
  value <- header_value(header, "Content-Transfer-Encoding")
  if (mime && !is.null(value)) encoding <- ascii_lower(value)
  if (encoding == "base64") {
    content <- decode_base64_body(original)
    if (is.null(content)) {
      problem(message, paste("bad base64 in part", number))
      content <- ""
    }
  } else if (encoding == "quoted-printable") {
    decoded <- decode_quoted_printable(original)
    content <- decoded$text
    if (decoded$error) problem(message, paste("bad quoted-printable in part", number))
  } else {
    content <- original
    if (!(encoding %in% c("7bit", "8bit", "binary"))) {
      problem(message, paste0('unknown encoding "', encoding, '" in part ', number))
    }
  }
  entity$content <- content
  entity
}
split_multipart <- function(message, entity, lines, boundary) {
  parts <- list()
  closed <- FALSE
  for (line in lines) {
    text <- strip_trailing(line$text)
    if (text == paste0("--", boundary, "--")) {
      closed <- TRUE
      break
    }
    if (text == paste0("--", boundary)) {
      parts[[length(parts) + 1L]] <- list()
    } else if (length(parts) > 0L) {
      last <- length(parts)
      parts[[last]][[length(parts[[last]]) + 1L]] <- line
    }
  }
  if (length(parts) == 0L) {
    problem(message, paste("no parts in part", entity$number))
  } else if (!closed) problem(message, paste("unterminated multipart in part", entity$number))
  entity$children <- list()
  for (i in seq_along(parts)) {
    sections <- split_sections(parts[[i]])
    header <- parse_fields(sections$header)
    for (number in header$invalid) problem(message, paste("bad header line", number))
    entity$children[[i]] <- parse_entity(message, paste0(entity$number, ".", i), header, sections$body, TRUE)
  }
  entity
}
collect_text_parts <- function(entity, allow_html) {
  if (is.null(entity$children)) {
    if (identical(entity$disposition, "attachment") || entity$main_type != "text") return(list())
    if (entity$subtype == "plain" || entity$subtype == "html" && allow_html) return(list(entity))
    return(list())
  }
  if (entity$subtype == "alternative") {
    for (html in c(FALSE, TRUE)) for (child in entity$children) {
      parts <- collect_text_parts(child, html)
      if (length(parts) > 0L) return(parts)
    }
    return(list())
  }
  parts <- list()
  for (child in entity$children) parts <- c(parts, collect_text_parts(child, allow_html))
  parts
}

quote_prefix <- function(depth) if (depth > 0L) paste0(strrep(">", depth), " ") else ""
wrap <- function(text, prefix) {
  lines <- character()
  current <- ""
  for (word in split_words(text)) {
    if (nzchar(current) && nchar(current) + 1L + nchar(word) > 72L) {
      lines <- c(lines, paste0(prefix, current))
      current <- word
    } else if (nzchar(current)) {
      current <- paste(current, word)
    } else current <- word
  }
  c(lines, paste0(prefix, current))
}
flowed_lines <- function(content, delete_space) {
  if (!nzchar(content)) return(character())
  logical_lines <- list()
  for (line in split_lf(content)) {
    text <- sub("^>+", "", line)
    depth <- nchar(line) - nchar(text)
    if (startsWith(text, " ")) text <- substring(text, 2L)
    flowing <- endsWith(text, " ") && text != "-- "
    last <- length(logical_lines)
    if (last > 0L && logical_lines[[last]]$flowing && logical_lines[[last]]$depth == depth) {
      previous <- logical_lines[[last]]
      if (delete_space) previous$text <- substr(previous$text, 1L, nchar(previous$text) - 1L)
      previous$text <- paste0(previous$text, text)
      previous$flowing <- flowing
      logical_lines[[last]] <- previous
    } else logical_lines[[last + 1L]] <- list(depth = depth, text = text, flowing = flowing)
  }
  lines <- character()
  for (line in logical_lines) lines <- c(lines, wrap(line$text, quote_prefix(line$depth)))
  lines
}
tag_name <- function(text) ascii_lower(regmatches(text, regexpr("^[A-Za-z0-9]*", text)))
replace_references <- function(text) {
  output <- character()
  position <- 1L
  while (position <= nchar(text)) {
    replacement <- NULL
    end <- -1L
    if (substr(text, position, position) == "&") {
      end <- find_after(text, ";", position + 1L)
      if (end >= 0L) {
        name <- substr(text, position + 1L, end - 1L)
        value <- unname(character_references[name])
        if (!is.na(value)) replacement <- value
        if (is.null(replacement) && startsWith(name, "#") && has_digits(substring(name, 2L), 1:3)) {
          value <- as.integer(substring(name, 2L))
          if (value >= 32L && value <= 126L) replacement <- intToUtf8(value)
        }
      }
    }
    if (is.null(replacement)) {
      output <- c(output, substr(text, position, position))
      position <- position + 1L
    } else {
      output <- c(output, replacement)
      position <- end + 1L
    }
  }
  paste0(output, collapse = "")
}
html_lines <- function(content) {
  blocks <- list()
  depth <- 0L
  position <- 1L
  text <- ""
  hide <- NULL
  while (position <= nchar(content)) {
    char <- substr(content, position, position)
    close <- if (char == "<") find_after(content, ">", position + 1L) else -1L
    if (close < 0L) {
      if (is.null(hide)) text <- paste0(text, char)
      position <- position + 1L
      next
    }
    inside <- substr(content, position + 1L, close - 1L)
    position <- close + 1L
    end_tag <- startsWith(inside, "/")
    name <- tag_name(if (end_tag) substring(inside, 2L) else inside)
    if (!is.null(hide)) {
      if (end_tag && name == hide) hide <- NULL
    } else if (!end_tag && name %in% hidden_tags) {
      hide <- name
    } else if (name == "br" || name == "li" && !end_tag) {
      blocks[[length(blocks) + 1L]] <- list(depth = depth, text = text)
      text <- if (name == "li") "* " else ""
    } else if (name %in% paragraph_tags) {
      blocks <- c(blocks, list(list(depth = depth, text = text), list(depth = depth, text = "")))
      text <- ""
      if (name == "blockquote") depth <- if (end_tag) max(depth - 1L, 0L) else depth + 1L
    }
  }
  blocks[[length(blocks) + 1L]] <- list(depth = depth, text = text)
  lines <- character()
  for (block in blocks) {
    text <- collapse_whitespace(gsub("\n", " ", block$text, fixed = TRUE))
    text <- sub(" +$", "", sub("^ +", "", replace_references(text)))
    if (nzchar(text)) {
      lines <- c(lines, wrap(text, quote_prefix(block$depth)))
    } else if (length(lines) > 0L && nzchar(tail(lines, 1L))) lines <- c(lines, "")
  }
  while (length(lines) > 0L && !nzchar(tail(lines, 1L))) lines <- lines[-length(lines)]
  lines
}
display_lines <- function(entity) {
  if (entity$subtype == "html") return(list(format = "html", lines = html_lines(entity$content)))
  format <- entity$parameters[["format"]]
  if (!is.null(format) && ascii_lower(format) == "flowed") {
    delsp <- entity$parameters[["delsp"]]
    return(list(format = "flowed", lines = flowed_lines(entity$content, !is.null(delsp) && ascii_lower(delsp) == "yes")))
  }
  list(format = "plain", lines = if (nzchar(entity$content)) split_lf(entity$content) else character())
}

new_thread <- function(number, root) {
  entries <- list()
  messages <- list()
  walk <- function(container, prefix, stem, depth) {
    entries[[length(entries) + 1L]] <<- list(container = container, prefix = prefix, depth = depth)
    message <- container$message
    if (!is.null(message)) {
      messages[[length(messages) + 1L]] <<- message
      message$thread <- number
      message$depth <- depth
      message$parent <- if (is.null(container$parent)) NULL else container$parent$message
    }
    for (i in seq_along(container$children)) {
      if (i < length(container$children)) {
        walk(container$children[[i]], paste0(stem, "+- "), paste0(stem, "|  "), depth + 1L)
      } else walk(container$children[[i]], paste0(stem, "`- "), paste0(stem, "   "), depth + 1L)
    }
  }
  walk(root, "", "", 0L)
  list(number = number, root = root, entries = entries, messages = messages)
}
container_notation <- function(container) {
  message <- container$message
  if (!is.null(message)) {
    sender <- if (is.null(message$sender)) "-" else message$sender$address
    return(sprintf("[%d] %s %s %s", message$number, date_notation(message$date), sender, subject_notation(message$subject)))
  }
  if (!is.null(container$subject)) paste("[subject]", container$subject) else paste("[missing]", container$id)
}
thread_report <- function(thread) {
  depth <- max(vapply(thread$entries, function(entry) entry$depth, integer(1)))
  senders <- unique(vapply(Filter(function(message) !is.null(message$sender), thread$messages), function(message) message$sender$address, character(1)))
  dates <- unlist(lapply(thread$messages, function(message) message$date), use.names = FALSE)
  lines <- sprintf("thread %d messages %d depth %d senders %d", thread$number, length(thread$messages), depth, length(senders))
  lines <- c(lines, if (length(dates) > 0L) paste("span", format_utc(min(dates)), "..", format_utc(max(dates))) else "span -")
  subject <- if (is.null(thread$root$subject)) root_subject(thread$root) else thread$root$subject
  lines <- c(lines, paste("subject", subject_notation(subject)))
  for (entry in thread$entries) lines <- c(lines, paste0(entry$prefix, container_notation(entry$container)))
  lines
}
sender_notation <- function(sender) {
  if (is.null(sender)) return("-")
  if (nzchar(sender$name)) paste0(sender$name, " <", sender$address, ">") else sender$address
}
entity_lines <- function(entity) {
  line <- paste("part", entity$number, paste0(entity$main_type, "/", entity$subtype))
  if (!is.null(entity$children)) {
    lines <- line
    for (child in entity$children) lines <- c(lines, entity_lines(child))
    return(lines)
  }
  line <- paste(line, nchar(entity$content))
  if (!is.null(entity$disposition)) line <- paste(line, entity$disposition)
  if (!is.null(entity$filename) && nzchar(entity$filename)) line <- paste0(line, ' "', entity$filename, '"')
  line
}
message_report <- function(message) {
  parent <- if (is.null(message$parent)) "-" else as.character(message$parent$number)
  c(paste("message", message$number), paste("id", dash(message$id)), paste("date", date_notation(message$date)),
    paste("from", sender_notation(message$sender)), paste("to", dash(paste(message$to, collapse = ", "))),
    paste("cc", dash(paste(message$cc, collapse = ", "))), paste("subject", subject_notation(message$subject)),
    paste("refs", dash(paste(message$references, collapse = " "))),
    sprintf("thread %d depth %d parent %s", message$thread, message$depth, parent), entity_lines(message$body))
}
body_report <- function(request, by_id) {
  lines <- paste("request", request)
  if (!exists(request, envir = by_id, inherits = FALSE)) return(c(lines, "not found"))
  message <- get(request, envir = by_id)
  parts <- collect_text_parts(message$body, TRUE)
  lines <- c(lines, sprintf("message %d text parts %d", message$number, length(parts)))
  for (part in parts) {
    display <- display_lines(part)
    stripped <- strip_trailing(display$lines)
    quoted <- sum(startsWith(stripped, ">"))
    signatures <- which(stripped == "--")
    signature <- if (length(signatures) == 0L) 0L else length(stripped) - tail(signatures, 1L)
    lines <- c(lines, sprintf("part %s %s lines %d quoted %d signature %d", part$number, display$format,
                            length(stripped), quoted, signature))
    for (line in stripped) lines <- c(lines, if (nzchar(line)) paste("|", line) else "|")
  }
  lines
}
csv_field <- function(text) {
  if (grepl(",", text, fixed = TRUE) || grepl('"', text, fixed = TRUE)) paste0('"', gsub('"', '""', text, fixed = TRUE), '"') else text
}
senders_report <- function(messages) {
  stats <- new.env(hash = TRUE, parent = emptyenv())
  addresses <- character()
  for (message in messages) {
    if (is.null(message$sender)) next
    address <- message$sender$address
    if (!exists(address, envir = stats, inherits = FALSE)) {
      addresses <- c(addresses, address)
      assign(address, list(address = address, name = "", count = 0L, threads = integer(), first = NULL, last = NULL), envir = stats)
    }
    entry <- get(address, envir = stats)
    entry$count <- entry$count + 1L
    entry$threads <- union(entry$threads, message$thread)
    if (!is.null(message$date)) {
      if (is.null(entry$first) || message$date < entry$first) entry$first <- message$date
      if (is.null(entry$last) || message$date > entry$last) entry$last <- message$date
    }
    if (nzchar(message$sender$name)) entry$name <- message$sender$name
    assign(address, entry, envir = stats)
  }
  entries <- lapply(addresses, function(address) get(address, envir = stats))
  if (length(entries) > 0L) entries <- entries[order(-vapply(entries, function(entry) entry$count, integer(1)), addresses, method = "radix")]
  lines <- "address,name,messages,threads,first,last"
  for (entry in entries) {
    first <- if (is.null(entry$first)) "-" else format_utc(entry$first)
    last <- if (is.null(entry$last)) "-" else format_utc(entry$last)
    lines <- c(lines, sprintf("%s,%s,%d,%d,%s,%s", entry$address, csv_field(entry$name), entry$count, length(entry$threads), first, last))
  }
  lines
}
malformed_report <- function(messages) {
  counts <- vapply(messages, function(message) length(message$problems), integer(1))
  lines <- sprintf("messages %d malformed %d problems %d", length(messages), sum(counts > 0L), sum(counts))
  for (message in messages) for (text in message$problems) lines <- c(lines, sprintf("message %d: %s", message$number, text))
  lines
}
join_blocks <- function(blocks) {
  lines <- character()
  for (block in blocks) {
    if (length(lines) > 0L) lines <- c(lines, "")
    lines <- c(lines, block)
  }
  lines
}
write_output <- function(name, lines) writeLines(lines, file.path("output", name), useBytes = TRUE)

main <- function() {
  mailbox <- read_mailbox(file.path("input", "mailbox.mbox"))
  messages <- list()
  known_ids <- new.env(hash = TRUE, parent = emptyenv())
  for (i in seq_along(mailbox)) {
    message <- new_message(i)
    process_message(message, mailbox[[i]], known_ids)
    messages[[i]] <- message
  }
  roots <- build_threads(messages)
  threads <- lapply(seq_along(roots), function(i) new_thread(i, roots[[i]]))
  for (message in messages) {
    parent <- message$parent
    if (!is.null(parent) && !is.null(message$date) && !is.null(parent$date) && message$date < parent$date) {
      problem(message, paste("dated before parent message", parent$number))
    }
  }
  by_id <- new.env(hash = TRUE, parent = emptyenv())
  for (message in messages) if (nzchar(message$id)) assign(message$id, message, envir = by_id)
  requests <- read_lines(file.path("input", "requests.txt"))
  dir.create("output", showWarnings = FALSE)
  write_output("threads.txt", join_blocks(lapply(threads, thread_report)))
  write_output("messages.txt", join_blocks(lapply(messages, message_report)))
  write_output("bodies.txt", join_blocks(lapply(requests, function(request) body_report(request, by_id))))
  write_output("senders.csv", senders_report(messages))
  write_output("malformed.txt", malformed_report(messages))
}

main()
