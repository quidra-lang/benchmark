named <- function(...) {
  items <- list(...)
  paste(paste0(names(items), "=", vapply(items, as.character, "")), collapse = " ")
}
number_list <- function(values) if (length(values)) paste(values, collapse = ",") else "-"
frequency <- function(values) {
  if (!length(values)) return("-")
  keys <- sort(unique(values))
  paste(vapply(keys, function(key) paste0(key, ":", sum(values == key)), ""), collapse = ",")
}
heading <- function(job) paste("JOB", job$number, job$text)
save_lines <- function(filename, lines) {
  dir.create("output", showWarnings = FALSE)
  writeLines(lines, file.path("output", filename), useBytes = TRUE)
}
save_paragraphs <- function(filename, paragraphs) {
  lines <- character()
  for (index in seq_along(paragraphs)) {
    if (index > 1L) lines <- c(lines, "")
    lines <- c(lines, paragraphs[[index]])
  }
  save_lines(filename, lines)
}
queens_board <- function(columns) paste0(
    strrep(".", columns - 1L),
    "Q",
    strrep(".", length(columns) - columns)
)
