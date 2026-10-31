junction_record <- function(node, offset, tokens) {
  phases <- lapply(tokens, function(token) {
    fields <- strsplit(token, ":", fixed = TRUE)[[1L]]
    list(duration = as.numeric(fields[1L]), token = fields[2L], greens = if (fields[2L] == "-") character() else strsplit(fields[2L], ",", fixed = TRUE)[[1L]])
  })
  list2env(list(node = node, offset = offset, phases = phases, cycle = sum(vapply(phases, function(phase) phase$duration, numeric(1L))), incoming = list()), parent = emptyenv())
}
is_green <- function(segment, step) {
  junction <- segment$junction
  if (!length(junction$phases)) return(TRUE)
  offset <- integer_mod(step - 1L + junction$offset, junction$cycle)
  for (phase in junction$phases) {
    if (offset < phase$duration) return(segment$id %in% phase$greens)
    offset <- offset - phase$duration
  }
}
plan_lines <- function(junction) {
  if (!length(junction$phases)) return(paste("JUNCTION", junction$node, "unsignalized"))
  lines <- line_text("JUNCTION", junction$node, "signal cycle", junction$cycle, "offset", junction$offset)
  first <- 0
  for (index in seq_along(junction$phases)) {
    phase <- junction$phases[[index]]
    last <- first + phase$duration - 1L
    lines <- c(lines, line_text("  PHASE", index, paste0(integer_text(first), "-", integer_text(last)), phase$token))
    first <- last + 1L
  }
  lines
}
