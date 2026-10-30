read_archive <- function(path) {
  lines <- read_lines(path)
  members <- list()
  index <- 1L
  while (index <= length(lines)) {
    header <- strsplit(lines[[index]], " ", fixed = TRUE)[[1L]]
    name <- paste0(basename(path), "(", header[[2L]], ")")
    parsed <- parse_object(lines, index + 1L, name)
    index <- parsed$index
    members[[length(members) + 1L]] <- new_record(object = parsed$object, exports = tail(header, -2L), loaded = FALSE)
  }
  members
}
scan_archive <- function(members, is_undefined, extract) {
  extracted <- 0L
  repeat {
    changed <- FALSE
    for (member in members) {
      if (member$loaded) next
      reason <- NULL
      for (name in member$exports) if (is_undefined(name)) {
        reason <- name
        break
      }
      if (is.null(reason)) next
      member$loaded <- TRUE
      extract(member$object, reason)
      extracted <- extracted + 1L
      changed <- TRUE
    }
    if (!changed) return(extracted)
  }
}
