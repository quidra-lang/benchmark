source("object_parser.R")
source("archive.R")
source("resolver.R")
source("layout.R")
source("relocator.R")
integer_text <- function(value) if (value == 0) "0" else sprintf("%.0f", value)
parse_hex <- function(text) {
  if (startsWith(text, "0x")) text <- substring(text, 3L)
  value <- 0
  for (character in utf8ToInt(text)) value <- value * 16 + if (character <= 57L) character - 48L else character - 87L
  value
}
hexadecimal <- function(value, digits = 8L) {
  alphabet <- strsplit("0123456789abcdef", "", fixed = TRUE)[[1L]]
  result <- character()
  repeat {
    result <- c(alphabet[[value %% 16 + 1L]], result)
    value <- value %/% 16
    if (value == 0) break
  }
  paste0(strrep("0", max(0L, digits - length(result))), paste(result, collapse = ""))
}
little_bytes <- function(value, width) vapply(seq_len(width) - 1L, function(index) as.integer((value %/% (256 ^ index)) %% 256), integer(1L))
new_script <- function(lines) {
  script <- new_record(entry = "", gc = FALSE, segments = list(), loads = list(), kept = character(),
                       sorted = character(), wrapped = character(), defines = list(), checksum = NULL, inputs = list())
  for (line in lines) {
    if (startsWith(line, "define ")) {
      at <- regexpr(" = ", line, fixed = TRUE)[[1L]]
      head <- substr(line, 1L, at - 1L)
      name <- strsplit(head, " ", fixed = TRUE)[[1L]][[2L]]
      script$defines[[length(script$defines) + 1L]] <- list(name = name, expression = substring(line, at + 3L))
      next
    }
    words <- strsplit(line, " ", fixed = TRUE)[[1L]]
    kind <- words[[1L]]
    if (kind == "entry") {
      script$entry <- words[[2L]]
    } else if (kind == "gc") {
      script$gc <- words[[2L]] == "on"
    } else if (kind == "segment") {
      script$segments[[length(script$segments) + 1L]] <- new_segment(words[[2L]], parse_hex(words[[3L]]), parse_hex(words[[4L]]), as.integer(parse_hex(words[[5L]])), tail(words, -5L))
    } else if (kind == "load") {
      script$loads[[length(script$loads) + 1L]] <- words[2L:3L]
    } else if (kind == "keep") {
      script$kept <- union(script$kept, words[[2L]])
    } else if (kind == "sort") {
      script$sorted <- union(script$sorted, words[[2L]])
    } else if (kind == "wrap") {
      script$wrapped <- union(script$wrapped, words[[2L]])
    } else if (kind == "checksum") {
      script$checksum <- words[2L:3L]
    } else {
      script$inputs[[length(script$inputs) + 1L]] <- list(kind = kind, names = tail(words, -1L))
    }
  }
  script$segment_names <- setNames(script$segments, vapply(script$segments, function(segment) segment$name, character(1L)))
  script$outputs <- do.call(c, lapply(script$segments, function(segment) segment$outputs))
  script$output_names <- setNames(script$outputs, vapply(script$outputs, function(output) output$name, character(1L)))
  script$script_names <- vapply(script$defines, function(define) define$name, character(1L))
  script
}
new_merged_strings <- function(sections) {
  merged <- new_record(kind = "merged", sections = sections, alignment = 1L, address = 0,
                       contents = integer(), strings = 0L, size = 0L, unique = 0L, saved = 0L)
  positions <- new.env(hash = TRUE, parent = emptyenv())
  original_size <- 0L
  for (section in sections) {
    section$merged <- merged
    original_size <- original_size + section$size
    start <- 1L
    while (start <= section$size) {
      ending <- start + which(section$contents[seq.int(start, section$size)] == 0L)[[1L]] - 1L
      bytes <- section$contents[seq.int(start, ending)]
      key <- paste(sprintf("%02x", bytes), collapse = "")
      if (!exists(key, positions, inherits = FALSE)) {
        assign(key, length(merged$contents), positions)
        merged$contents <- c(merged$contents, bytes)
      }
      section$merged_positions[[as.character(start - 1L)]] <- get(key, positions, inherits = FALSE)
      merged$strings <- merged$strings + 1L
      start <- ending + 1L
    }
  }
  merged$size <- length(merged$contents)
  merged$unique <- length(ls(positions, all.names = TRUE))
  merged$saved <- original_size - merged$size
  merged
}
new_veneer <- function(output, name) new_record(kind = "veneer", output = output, name = name, size = 8L, alignment = 4L, address = 0)
new_script_expression <- function(text, outputs, values) {
  tokens <- regmatches(text, gregexpr("0x[0-9a-f]+|[0-9]+|[A-Za-z_.][A-Za-z0-9_.]*|[(),+-]", text, perl = TRUE))[[1L]]
  new_record(tokens = tokens, index = 1L, outputs = outputs, values = values)
}
take_expression_token <- function(parser) {
  token <- parser$tokens[[parser$index]]
  parser$index <- parser$index + 1L
  token
}
script_expression <- function(parser) {
  value <- script_term(parser)
  while (parser$index <= length(parser$tokens) && parser$tokens[[parser$index]] %in% c("+", "-")) {
    operator <- take_expression_token(parser)
    right <- script_term(parser)
    value <- if (operator == "+") value + right else value - right
  }
  value
}
script_term <- function(parser) {
  token <- take_expression_token(parser)
  if (token == "(") {
    value <- script_expression(parser)
    take_expression_token(parser)
    return(value)
  }
  if (grepl("^[0-9]", token)) return(if (startsWith(token, "0x")) parse_hex(token) else as.numeric(token))
  if (parser$index > length(parser$tokens) || parser$tokens[[parser$index]] != "(") return(parser$values[[token]])
  take_expression_token(parser)
  if (token == "align") {
    value <- script_expression(parser)
    take_expression_token(parser)
    alignment <- script_expression(parser)
    take_expression_token(parser)
    return(align_address(value, alignment))
  }
  output <- parser$outputs[[take_expression_token(parser)]]
  take_expression_token(parser)
  switch(token, start = output$address, end = output$address + output$size,
         size = output$size, loadaddr = output$segment$paddr + output$address - output$segment$base)
}
new_linker <- function(script) {
  new_record(script = script, objects = list(), entries = list(), archives = list(), comdats = list(),
             comdat_order = character(), extractions = list(), orphans = list(), script_values = list(),
             veneers = list(), far_calls = integer(), applied = list(),
             relocation_counts = setNames(lapply(TYPES, function(type) c(ok = 0L, veneer = 0L, overflow = 0L, undefined = 0L)), TYPES))
}
symbol_defined <- function(linker, name) {
  name %in% linker$script$script_names || any(vapply(linker$entries[[name]], function(entry) entry$kind %in% c("defined", "common"), logical(1L)))
}
symbol_undefined <- function(linker, name) {
  if (symbol_defined(linker, name)) return(FALSE)
  name == linker$script$entry || any(vapply(linker$entries[[name]], function(entry) entry$kind == "undefined" && entry$binding == "global", logical(1L)))
}
load_object <- function(linker, object) {
  object$order <- length(linker$objects)
  for (group in object$comdats) {
    signature <- group$signature
    if (!is.null(linker$comdats[[signature]])) {
      linker$comdats[[signature]]$discarded <- c(linker$comdats[[signature]]$discarded, object$name)
      for (section in group$sections) section$discard_reason <- "comdat"
    } else {
      linker$comdats[[signature]] <- list(keeper = object$name, discarded = character())
      linker$comdat_order <- c(linker$comdat_order, signature)
    }
  }
  for (symbol in object$symbols) if (symbol$binding != "local" && symbol$kind == "defined" && identical(symbol$section$discard_reason, "comdat")) {
    symbol$kind <- "undefined"
    symbol$section <- NULL
  }
  for (symbol in object$symbols) if (symbol$kind == "undefined") {
    if (symbol$name %in% linker$script$wrapped) symbol$name <- paste0("__wrap_", symbol$name) else if (startsWith(symbol$name, "__real_") && substring(symbol$name, 8L) %in% linker$script$wrapped) symbol$name <- substring(symbol$name, 8L)
  }
  object$symbol_names <- setNames(object$symbols, vapply(object$symbols, function(symbol) symbol$name, character(1L)))
  for (symbol in object$symbols) if (symbol$binding != "local") {
    entries <- linker$entries[[symbol$name]]
    if (is.null(entries)) entries <- list()
    entries[[length(entries) + 1L]] <- symbol
    linker$entries[[symbol$name]] <- entries
  }
  linker$objects[[length(linker$objects) + 1L]] <- object
}
extract_member <- function(linker, object, reason) {
  references <- Filter(function(entry) entry$kind == "undefined" && entry$binding == "global", linker$entries[[reason]])
  referrer <- if (length(references)) references[[1L]]$owner$name else "*entry*"
  linker$extractions[[length(linker$extractions) + 1L]] <- list(name = object$name, referrer = referrer, reason = reason)
  load_object(linker, object)
}
scan_library <- function(linker, name) {
  if (is.null(linker$archives[[name]])) linker$archives[[name]] <- read_archive(file.path("input", name))
  scan_archive(linker$archives[[name]], function(symbol) symbol_undefined(linker, symbol), function(object, reason) extract_member(linker, object, reason))
}
load_inputs <- function(linker) {
  for (input in linker$script$inputs) {
    if (input$kind == "object") {
      load_object(linker, read_object(file.path("input", input$names[[1L]])))
    } else if (input$kind == "library") {
      scan_library(linker, input$names[[1L]])
    } else repeat {
      extracted <- 0L
      for (name in input$names) extracted <- extracted + scan_library(linker, name)
      if (!extracted) break
    }
  }
  linker$names <- resolve_names(linker$entries, linker$script$script_names)
  linker$commons <- Filter(function(resolution) resolution$kind == "common", linker$names)
}
assign_outputs <- function(linker) {
  linker$candidates <- list()
  for (object in linker$objects) for (section in object$sections) {
    if (identical(section$discard_reason, "comdat")) next
    section$output <- find_output(section$name, linker$script$outputs)
    if (is.null(section$output)) {
      section$discard_reason <- "orphan"
      count <- linker$orphans[[section$name]]
      linker$orphans[[section$name]] <- if (is.null(count)) 1L else count + 1L
    } else {
      section$output$sections[[length(section$output$sections) + 1L]] <- section
      linker$candidates[[length(linker$candidates) + 1L]] <- section
    }
  }
}
relocation_target <- function(linker, symbol) {
  if (symbol$binding == "local") return(symbol$section)
  resolution <- linker$names[[symbol$name]]
  if (resolution$kind %in% c("global", "weak")) return(resolution$definition$section)
  if (resolution$kind == "common") resolution else NULL
}
collect_garbage <- function(linker) {
  units <- c(linker$candidates, linker$commons)
  keys <- vapply(units, function(unit) unit$key, character(1L))
  if (!linker$script$gc) {
    for (unit in units) unit$live <- TRUE
  } else {
    pending <- Filter(function(section) section$output$name %in% linker$script$kept, linker$candidates)
    entry <- linker$names[[linker$script$entry]]
    if (!is.null(entry)) {
      if (entry$kind %in% c("global", "weak")) pending[[length(pending) + 1L]] <- entry$definition$section
      if (entry$kind == "common") pending[[length(pending) + 1L]] <- entry
    }
    while (length(pending)) {
      unit <- pending[[length(pending)]]
      pending <- head(pending, -1L)
      if (is.null(unit) || !unit$key %in% keys || unit$live) next
      unit$live <- TRUE
      if (unit$kind == "input") pending <- c(pending, lapply(unit$relocations, function(relocation) relocation_target(linker, relocation$symbol)))
    }
  }
  for (section in linker$candidates) if (!section$live) section$discard_reason <- "gc"
  for (object in linker$objects) {
    unresolved <- character()
    for (section in object$sections) if (section$live) for (relocation in section$relocations) {
      symbol <- relocation$symbol
      if (symbol$binding != "local" && linker$names[[symbol$name]]$kind == "undefined") unresolved <- union(unresolved, symbol$name)
    }
    for (name in unresolved) linker$names[[name]]$unresolved_referrers <- c(linker$names[[name]]$unresolved_referrers, object$name)
  }
}
build_components <- function(linker) {
  for (output in linker$script$outputs) {
    sections <- Filter(function(section) section$live, output$sections)
    if (output$name %in% linker$script$sorted) {
      priorities <- vapply(sections, function(section) if (section$name == output$name) 65536L else as.integer(substring(section$name, nchar(output$name) + 2L)), integer(1L))
      sections <- sections[order(priorities, seq_along(sections), method = "radix")]
    }
    strings <- Filter(function(section) section$string, sections)
    merged <- if (length(strings)) new_merged_strings(strings) else NULL
    components <- list()
    inserted <- FALSE
    for (section in sections) {
      if (section$string) {
        if (!inserted) {
          components[[length(components) + 1L]] <- merged
          inserted <- TRUE
        }
      } else {
        components[[length(components) + 1L]] <- section
      }
    }
    if (output$name == ".bss") {
      commons <- Filter(function(common) common$live, linker$commons)
      ordering <- order(-vapply(commons, function(common) common$alignment, integer(1L)), vapply(commons, function(common) common$name, character(1L)), method = "radix")
      components <- c(components, unname(commons[ordering]))
    }
    output$base_components <- components
  }
}
location_address <- function(section, offset) if (section$string) section$merged$address + section$merged_positions[[as.character(offset)]] else section$address + offset
definition_address <- function(resolution) location_address(resolution$definition$section, resolution$definition$offset)
find_far_calls <- function(linker) {
  calls <- list()
  for (section in linker$candidates) if (section$live) for (relocation in section$relocations) {
    symbol <- relocation$symbol
    if (relocation$type != "CALL24" || symbol$binding == "local") next
    resolution <- linker$names[[symbol$name]]
    if (!resolution$kind %in% c("global", "weak")) next
    value <- definition_address(resolution) + relocation$addend - section$address - relocation$offset
    if (value < -2 ^ 25 || value >= 2 ^ 25) calls[[length(calls) + 1L]] <- relocation
  }
  calls
}
veneer_key <- function(output, name) paste(output$name, name, sep = ":")
perform_layout <- function(linker) {
  build_components(linker)
  repeat {
    for (output in linker$script$outputs) {
      veneers <- Filter(function(veneer) identical(veneer$output, output), linker$veneers)
      ordering <- order(vapply(veneers, function(veneer) veneer$name, character(1L)), method = "radix")
      output$components <- c(output$base_components, unname(veneers[ordering]))
    }
    for (segment in linker$script$segments) assign_segment(segment)
    far_calls <- find_far_calls(linker)
    changed <- FALSE
    for (relocation in far_calls) {
      output <- relocation$section$output
      name <- relocation$symbol$name
      key <- veneer_key(output, name)
      if (is.null(linker$veneers[[key]])) {
        linker$veneers[[key]] <- new_veneer(output, name)
        changed <- TRUE
      }
    }
    if (!changed) {
      linker$far_calls <- vapply(far_calls, function(relocation) relocation$id, integer(1L))
      break
    }
  }
}
load_addresses <- function(linker) {
  storage <- setNames(lapply(linker$script$segments, function(segment) segment$base + segment$memsz), vapply(linker$script$segments, function(segment) segment$name, character(1L)))
  for (load in linker$script$loads) {
    segment <- linker$script$segment_names[[load[[1L]]]]
    destination <- load[[2L]]
    segment$paddr <- align_address(storage[[destination]], 4L)
    storage[[destination]] <- segment$paddr + segment$filesz
  }
  for (segment in linker$script$segments) segment$used <- storage[[segment$name]] - segment$base
}
evaluate_defines <- function(linker) {
  for (define in linker$script$defines) {
    parser <- new_script_expression(define$expression, linker$script$output_names, linker$script_values)
    linker$script_values[[define$name]] <- script_expression(parser)
  }
}
symbol_value <- function(linker, symbol) {
  if (symbol$binding == "local") return(location_address(symbol$section, symbol$offset))
  resolution <- linker$names[[symbol$name]]
  if (resolution$kind %in% c("global", "weak")) return(definition_address(resolution))
  if (resolution$kind == "common") return(resolution$address)
  if (resolution$kind == "script") return(linker$script_values[[resolution$name]])
  if (resolution$kind == "weakundef") 0 else NULL
}
entry_address <- function(linker) {
  entry <- linker$names[[linker$script$entry]]
  if (!is.null(entry)) {
    if (entry$kind %in% c("global", "weak")) return(definition_address(entry))
    if (entry$kind == "common") return(entry$address)
  }
  0
}
apply_relocations <- function(linker) {
  gp <- linker$script_values[["_gp"]]
  if (is.null(gp)) gp <- 0
  for (output in linker$script$outputs) for (section in output$components) {
    if (section$kind != "input") next
    for (index in seq_along(section$relocations)) {
      relocation <- section$relocations[[index]]
      relocation$place <- section$address + relocation$offset
      relocation$unpaired <- unpaired_hi16(section$relocations, index)
      relocation$symbol_value <- symbol_value(linker, relocation$symbol)
      if (is.null(relocation$symbol_value)) {
        relocation$status <- "undefined"
      } else {
        relocation$status <- "ok"
        if (relocation$id %in% linker$far_calls) {
          relocation$symbol_value <- linker$veneers[[veneer_key(output, relocation$symbol$name)]]$address
          relocation$status <- "veneer"
        }
        computed <- relocation_value(relocation$type, relocation$symbol_value, relocation$addend, relocation$place, gp)
        relocation$value <- computed$value
        relocation$field <- computed$field
        if (!computed$within_range) relocation$status <- "overflow"
        width <- WIDTHS[[relocation$type]]
        section$contents[seq.int(relocation$offset + 1L, relocation$offset + width)] <- little_bytes(computed$field, width)
      }
      linker$relocation_counts[[relocation$type]][[relocation$status]] <- linker$relocation_counts[[relocation$type]][[relocation$status]] + 1L
      linker$applied[[length(linker$applied) + 1L]] <- relocation
    }
  }
}
build_images <- function(linker) {
  for (segment in linker$script$segments) {
    segment$image <- rep(segment$fill, segment$filesz)
    for (output in segment$outputs) if (!output$nobits) for (component in output$components) {
      if (component$kind == "veneer") {
        destination <- definition_address(linker$names[[component$name]])
        contents <- c(4L, 240L, 31L, 229L, little_bytes(destination, 4L))
      } else {
        contents <- component$contents
      }
      start <- component$address - segment$base
      if (component$size) segment$image[seq.int(start + 1L, start + component$size)] <- contents
    }
  }
  if (!is.null(linker$script$checksum)) {
    segment <- linker$script$segment_names[[linker$script$checksum[[1L]]]]
    offset <- definition_address(linker$names[[linker$script$checksum[[2L]]]]) - segment$base
    segment$image[seq.int(offset + 1L, offset + 4L)] <- 0L
    total <- 0
    starts <- if (segment$filesz) seq.int(0L, segment$filesz - 1L, by = 4L) else integer()
    for (start in starts) for (index in seq.int(0L, min(3L, segment$filesz - start - 1L))) total <- total + segment$image[[start + index + 1L]] * 256 ^ index
    segment$image[seq.int(offset + 1L, offset + 4L)] <- little_bytes((-total) %% 2 ^ 32, 4L)
  }
}
symbol_rows <- function(linker) {
  rows <- list()
  for (name in names(linker$names)) {
    resolution <- linker$names[[name]]
    if (resolution$kind %in% c("global", "weak") && resolution$definition$section$live) {
      rows[[length(rows) + 1L]] <- list(address = definition_address(resolution), name = name, kind = resolution$kind, definer = resolution$definer)
    } else if (resolution$kind == "common" && resolution$live) {
      rows[[length(rows) + 1L]] <- list(address = resolution$address, name = name, kind = "common", definer = resolution$definer)
    } else if (resolution$kind == "script") {
      rows[[length(rows) + 1L]] <- list(address = linker$script_values[[name]], name = name, kind = "script", definer = "*script*")
    }
  }
  for (output in linker$script$outputs) for (component in output$components) if (component$kind == "veneer") rows[[length(rows) + 1L]] <- list(address = component$address, name = paste0("__veneer_", component$name), kind = "veneer", definer = "*linker*")
  ordering <- order(vapply(rows, function(row) row$address, numeric(1L)), vapply(rows, function(row) row$name, character(1L)), method = "radix")
  rows[ordering]
}
relocation_location <- function(relocation) paste0(relocation$section$owner$name, " ", relocation$section$name, "+", relocation$offset)
segment_heading <- function(segment) paste("segment", segment$name, "vaddr", hexadecimal(segment$base), "paddr", hexadecimal(segment$paddr), "filesz", integer_text(segment$filesz), "memsz", integer_text(segment$memsz))
diagnostics <- function(linker) {
  lines <- character()
  for (name in sort(names(linker$orphans), method = "radix")) lines <- c(lines, paste("warning: orphan section", name, "discarded from", linker$orphans[[name]], "object(s)"))
  for (name in names(linker$names)) {
    resolution <- linker$names[[name]]
    if (length(resolution$strong_definers) >= 2L) lines <- c(lines, paste0("error: multiple definition of ", name, ": ", paste(resolution$strong_definers, collapse = " ")))
    if (length(resolution$commons) && resolution$kind %in% c("global", "script")) lines <- c(lines, paste("warning: common symbol", name, "overridden by", resolution$definer))
    pairs <- unique(vapply(resolution$commons, function(entry) paste(integer_text(entry$size), entry$alignment, sep = ":"), character(1L)))
    if (resolution$kind == "common" && length(pairs) >= 2L) lines <- c(lines, paste("warning: common symbol", name, "merged to size", integer_text(resolution$size), "align", resolution$alignment))
  }
  entry <- linker$names[[linker$script$entry]]
  if (is.null(entry) || entry$kind %in% c("undefined", "weakundef")) lines <- c(lines, paste("error: entry symbol", linker$script$entry, "is undefined"))
  for (name in names(linker$names)) {
    resolution <- linker$names[[name]]
    if (resolution$kind == "undefined" && length(resolution$unresolved_referrers)) lines <- c(lines, paste("error: undefined symbol", name, "referenced by", paste(resolution$unresolved_referrers, collapse = " ")))
  }
  for (segment in linker$script$segments) if (segment$used > segment$length) lines <- c(lines, paste("error: segment", segment$name, "overflows its length by", integer_text(segment$used - segment$length), "bytes"))
  for (index in seq_along(linker$script$segments)) {
    first <- linker$script$segments[[index]]
    for (second in tail(linker$script$segments, -index)) if (first$memsz >= 1 && second$memsz >= 1 && first$base < second$base + second$memsz && second$base < first$base + first$memsz) lines <- c(lines, paste("error: segments", first$name, "and", second$name, "overlap"))
  }
  for (relocation in linker$applied) {
    location <- relocation_location(relocation)
    if (relocation$unpaired) lines <- c(lines, paste("error: unpaired HI16 at", location, "against", relocation$symbol$name))
    if (relocation$status == "overflow") lines <- c(lines, paste0("error: relocation overflow at ", location, ": ", relocation$type, " value ", integer_text(relocation$value), " against ", relocation$symbol$name))
  }
  errors <- sum(startsWith(lines, "error:"))
  warnings <- sum(startsWith(lines, "warning:"))
  c(lines, paste("errors", errors, "warnings", warnings))
}
image_dump <- function(linker) {
  lines <- paste("entry", hexadecimal(entry_address(linker)), linker$script$entry)
  for (segment in linker$script$segments) {
    lines <- c(lines, segment_heading(segment))
    if (segment$filesz) for (start in seq.int(0L, segment$filesz - 1L, by = 16L)) {
      chunk <- segment$image[seq.int(start + 1L, min(start + 16L, segment$filesz))]
      bytes <- paste(vapply(chunk, hexadecimal, character(1L), digits = 2L), collapse = " ")
      lines <- c(lines, paste(hexadecimal(segment$base + start), bytes))
    }
  }
  lines
}
hex_record <- function(type, address, data) {
  record <- c(length(data), address %/% 256, address %% 256, type, data)
  record <- c(record, (-sum(record)) %% 256)
  paste0(":", toupper(paste(vapply(record, hexadecimal, character(1L), digits = 2L), collapse = "")))
}
intel_hex <- function(linker) {
  lines <- character()
  upper <- 0
  segments <- linker$script$segments
  ordering <- order(vapply(segments, function(segment) segment$paddr, numeric(1L)), seq_along(segments), method = "radix")
  for (segment in segments[ordering]) {
    start <- 0L
    while (start < segment$filesz) {
      address <- segment$paddr + start
      count <- min(16L, segment$filesz - start, 65536 - address %% 65536)
      if (address %/% 65536 != upper) {
        upper <- address %/% 65536
        lines <- c(lines, hex_record(4L, 0L, c(upper %/% 256, upper %% 256)))
      }
      lines <- c(lines, hex_record(0L, address %% 65536, segment$image[seq.int(start + 1L, start + count)]))
      start <- start + count
    }
  }
  c(lines, hex_record(5L, 0L, rev(little_bytes(entry_address(linker), 4L))), hex_record(1L, 0L, integer()))
}
component_line <- function(component) {
  if (component$kind == "input") return(paste("input", hexadecimal(component$address), integer_text(component$size), component$alignment, component$owner$name, component$name))
  if (component$kind == "merged") return(paste("merged", hexadecimal(component$address), integer_text(component$size), "sections", length(component$sections), "strings", component$strings, "unique", component$unique, "saved", component$saved))
  if (component$kind == "common") return(paste("common", hexadecimal(component$address), integer_text(component$size), component$alignment, component$definer, component$name))
  paste("veneer", hexadecimal(component$address), "8", component$name)
}
link_map <- function(linker) {
  lines <- vapply(linker$extractions, function(record) paste("member", record$name, record$referrer, record$reason), character(1L))
  for (signature in linker$comdat_order) {
    group <- linker$comdats[[signature]]
    discarded <- if (length(group$discarded)) paste(group$discarded, collapse = ",") else "-"
    lines <- c(lines, paste("comdat", signature, group$keeper, discarded))
  }
  for (segment in linker$script$segments) {
    usage <- (100 * segment$used) %/% segment$length
    lines <- c(lines, paste(segment_heading(segment), "used", integer_text(segment$used), "length", integer_text(segment$length), paste0(integer_text(usage), "%")))
    for (output in segment$outputs) {
      lines <- c(lines, paste("section", output$name, hexadecimal(output$address), integer_text(output$size), output$alignment), vapply(output$components, component_line, character(1L)))
    }
  }
  for (object in linker$objects) for (section in object$sections) if (!is.null(section$discard_reason)) lines <- c(lines, paste("discard", object$name, section$name, integer_text(section$size), section$discard_reason))
  commons <- linker$commons
  ordering <- order(vapply(commons, function(common) common$name, character(1L)), method = "radix")
  for (common in commons[ordering]) if (!common$live) lines <- c(lines, paste("discard", common$definer, paste0("COMMON(", common$name, ")"), integer_text(common$size), "gc"))
  for (row in symbol_rows(linker)) lines <- c(lines, paste("symbol", hexadecimal(row$address), row$name, row$kind, row$definer))
  lines
}
cross_references <- function(linker) {
  lines <- character()
  for (name in names(linker$names)) {
    resolution <- linker$names[[name]]
    if (resolution$kind %in% c("global", "weak")) {
      status <- if (resolution$definition$section$live) "kept" else "discarded"
    } else if (resolution$kind == "common") {
      status <- if (resolution$live) "kept" else "discarded"
    } else {
      status <- if (resolution$kind == "script") "kept" else "-"
    }
    referrers <- if (length(resolution$referrers)) paste(resolution$referrers, collapse = ",") else "-"
    lines <- c(lines, paste(name, resolution$kind, status, resolution$definer, referrers))
  }
  lines
}
relocation_report <- function(linker) {
  lines <- character()
  for (relocation in linker$applied) {
    prefix <- paste(hexadecimal(relocation$place), relocation_location(relocation), relocation$type, relocation$symbol$name, integer_text(relocation$addend))
    values <- if (relocation$status == "undefined") "- - -" else paste(hexadecimal(relocation$symbol_value), integer_text(relocation$value), hexadecimal(relocation$field, 2L * WIDTHS[[relocation$type]]))
    lines <- c(lines, paste(prefix, values, relocation$status))
  }
  for (type in TYPES) {
    counts <- linker$relocation_counts[[type]]
    line <- paste("summary", type, "total", sum(counts))
    for (status in c("ok", "veneer", "overflow", "undefined")) line <- paste(line, status, counts[[status]])
    lines <- c(lines, line)
  }
  lines
}
main <- function() {
  linker <- new_linker(new_script(read_lines("input/link.txt")))
  load_inputs(linker)
  assign_outputs(linker)
  collect_garbage(linker)
  perform_layout(linker)
  load_addresses(linker)
  evaluate_defines(linker)
  apply_relocations(linker)
  build_images(linker)
  reports <- list("image.hex" = image_dump(linker), "flash.ihex" = intel_hex(linker),
                  "link.map" = link_map(linker), "xref.txt" = cross_references(linker),
                  "relocations.txt" = relocation_report(linker), "diagnostics.txt" = diagnostics(linker))
  dir.create("output", showWarnings = FALSE)
  for (name in names(reports)) {
    lines <- reports[[name]]
    connection <- file(file.path("output", name), open = "wb")
    if (length(lines)) writeChar(paste0(paste(lines, collapse = "\n"), "\n"), connection, eos = NULL, useBytes = TRUE)
    close(connection)
  }
}
main()
