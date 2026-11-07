new_record <- function(...) list2env(list(...), parent = emptyenv())
belongs <- function(name, prefix) name == prefix || startsWith(name, paste0(prefix, "."))
is_nobits <- function(name) belongs(name, ".bss")
is_string_section <- function(name) belongs(name, ".rodata.str")
read_lines <- function(path) readLines(path, warn = FALSE)
LINK_IDS <- new.env(parent = emptyenv())
LINK_IDS$next_id <- 0L
next_link_id <- function() {
  LINK_IDS$next_id <- LINK_IDS$next_id + 1L
  LINK_IDS$next_id
}
new_section <- function(owner, name, alignment, size) {
  id <- next_link_id()
  new_record(kind = "input", owner = owner, name = name, alignment = alignment, size = size,
             contents = integer(), nobits = is_nobits(name), string = is_string_section(name),
             relocations = list(), discard_reason = NULL, output = NULL, live = FALSE,
             address = 0, merged = NULL, merged_positions = list(), key = paste0("s:", id))
}
new_symbol <- function(owner, name, binding, kind) {
  new_record(owner = owner, name = name, binding = binding, kind = kind, section = NULL,
             offset = 0L, size = 0, alignment = 1L)
}
new_relocation <- function(section, offset, type, symbol, addend) {
  new_record(section = section, offset = offset, type = type, symbol = symbol, addend = addend,
             id = next_link_id(), place = 0, unpaired = FALSE, symbol_value = NULL,
             value = NULL, field = NULL, status = "")
}
new_object <- function(name) new_record(name = name, order = -1L, sections = list(), section_names = list(),
                                       comdats = list(), symbols = list(), symbol_names = list())
parse_object <- function(lines, index, name) {
  object <- new_object(name)
  while (lines[[index]] != "end") {
    words <- strsplit(lines[[index]], " ", fixed = TRUE)[[1L]]
    index <- index + 1L
    if (words[[1L]] == "section") {
      section <- new_section(object, words[[2L]], as.integer(words[[3L]]), as.integer(words[[4L]]))
      object$sections[[length(object$sections) + 1L]] <- section
      object$section_names[[section$name]] <- section
      if (!section$nobits) while (length(section$contents) < section$size) {
        text <- strsplit(lines[[index]], " ", fixed = TRUE)[[1L]][[2L]]
        starts <- seq.int(1L, nchar(text), by = 2L)
        section$contents <- c(section$contents, strtoi(substring(text, starts, starts + 1L), base = 16L))
        index <- index + 1L
      }
    } else if (words[[1L]] == "comdat") {
      object$comdats[[length(object$comdats) + 1L]] <- list(signature = words[[2L]], sections = unname(object$section_names[tail(words, -2L)]))
    } else if (words[[1L]] == "symbol") {
      kind <- if (words[[4L]] == "undef") "undefined" else if (words[[4L]] == "common") "common" else "defined"
      symbol <- new_symbol(object, words[[2L]], words[[3L]], kind)
      if (kind == "common") {
        symbol$size <- as.numeric(words[[5L]])
        symbol$alignment <- as.integer(words[[6L]])
      } else if (kind == "defined") {
        symbol$section <- object$section_names[[words[[4L]]]]
        symbol$offset <- as.integer(words[[5L]])
      }
      object$symbols[[length(object$symbols) + 1L]] <- symbol
      object$symbol_names[[symbol$name]] <- symbol
    } else if (words[[1L]] == "reloc") {
      section <- object$section_names[[words[[2L]]]]
      symbol <- object$symbol_names[[words[[5L]]]]
      section$relocations[[length(section$relocations) + 1L]] <- new_relocation(section, as.integer(words[[3L]]), words[[4L]], symbol, as.numeric(words[[6L]]))
    }
  }
  list(object = object, index = index + 1L)
}
read_object <- function(path) parse_object(read_lines(path), 1L, basename(path))$object
