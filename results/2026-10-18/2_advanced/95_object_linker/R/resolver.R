new_resolution <- function(name, entries, script = FALSE) {
  strong <- Filter(function(entry) entry$kind == "defined" && entry$binding == "global", entries)
  weak <- Filter(function(entry) entry$kind == "defined" && entry$binding == "weak", entries)
  commons <- Filter(function(entry) entry$kind == "common", entries)
  references <- Filter(function(entry) entry$kind == "undefined", entries)
  referrers <- unique(vapply(references, function(entry) entry$owner$name, character(1L)))
  strong_definers <- c(if (script) "*script*" else character(), vapply(strong, function(entry) entry$owner$name, character(1L)))
  definition <- NULL
  size <- 0
  alignment <- 1L
  if (script) {
    kind <- "script"
    definer <- "*script*"
  } else if (length(strong)) {
    kind <- "global"
    definition <- strong[[1L]]
    definer <- definition$owner$name
  } else if (length(commons)) {
    kind <- "common"
    size <- max(vapply(commons, function(entry) entry$size, numeric(1L)))
    alignment <- max(vapply(commons, function(entry) entry$alignment, integer(1L)))
    definer <- Filter(function(entry) entry$size == size, commons)[[1L]]$owner$name
  } else if (length(weak)) {
    kind <- "weak"
    definition <- weak[[1L]]
    definer <- definition$owner$name
  } else if (any(vapply(references, function(entry) entry$binding == "global", logical(1L)))) {
    kind <- "undefined"
    definer <- "-"
  } else {
    kind <- "weakundef"
    definer <- "-"
  }
  new_record(name = name, entries = entries, strong = strong, weak = weak, commons = commons,
             references = references, referrers = referrers, strong_definers = strong_definers,
             definition = definition, size = size, alignment = alignment, address = 0,
             live = FALSE, unresolved_referrers = character(), kind = kind, definer = definer,
             key = paste0("c:", name))
}
resolve_names <- function(entries, script_names) {
  names <- sort(union(names(entries), script_names), method = "radix")
  setNames(lapply(names, function(name) new_resolution(name, if (is.null(entries[[name]])) list() else entries[[name]], name %in% script_names)), names)
}
